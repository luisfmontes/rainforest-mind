#!/usr/bin/env node
/**
 * Resolução do diretório corrente efetivo em comandos shell com `cd` e `git -C`.
 *
 * Extraído de `hooks/gate-worktree.cjs:alvosBash()` e generalizado para servir
 * a múltiplas decisões (D1, D8 do design de 2026-09-03).
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// `cd X` isolado num segmento do encadeamento.
const CD = /^\s*cd\s+(?:--\s+)?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))\s*$/;
// Diretorio que o proprio git recebe, e que vence o cwd do shell.
const GIT_DIR_EXPLICITO = /\bgit\b[^\n;&|]*?(?:-C|--work-tree(?:=|\s+))\s*(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))/;
// Separadores de comando.
const SEPARADORES = /&&|\|\||;|\n|\|/;
// `pushd X`: muda o cwd corrente igual `cd X`, mas empilha o cwd de antes
// para o `popd` desfazer (H2, rodada 5 do lote 3).
const PUSHD = /^\s*pushd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))\s*$/;
// `popd`: volta ao cwd de antes do ultimo `pushd`. Aceita o `-n` ("nao
// re-imprime a pilha"), que nao muda o alvo.
const POPD = /^\s*popd(?:\s+-n)?\s*$/;
// `env -C <dir> <cmd...>` / `env --chdir=<dir> <cmd...>` (GNU coreutils):
// muda o cwd SO do comando que ele lanca — nunca do shell, entao nao
// persiste para os segmentos seguintes. Pula `NOME=valor` antes do `-C`,
// que e a forma comum (`env FOO=1 -C /dir cmd`).
const ENV_C = /^\s*env\s+(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S*)\s+)*(?:-C\s+|--chdir=)(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))/;

/**
 * Quebra a linha de comando em segmentos respeitando aspas.
 *
 * Similares a `tokensComAspas`, mas opera sobre separadores de comando
 * (`;`, `&&`, `||`, `|`) em vez de espaçamento de tokens.
 * Aspas simples e duplas protegem separadores do inside.
 */
function segmentosComAspas(cmd) {
  const segmentos = [];
  let atual = "", aspa = null;

  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];

    if (aspa) {
      // Dentro de aspas: só sair da aspa ou adicionar caractere
      if (c === aspa) {
        aspa = null;
      }
      atual += c;
    } else if (c === '"' || c === "'") {
      // Entrar em aspa
      aspa = c;
      atual += c;
    } else if (i + 1 < cmd.length && (
      (c === '&' && cmd[i + 1] === '&') ||
      (c === '|' && cmd[i + 1] === '|') ||
      c === ';' ||
      c === '|' ||
      c === '\n'
    )) {
      // Separador encontrado fora de aspas
      if (atual.trim()) {
        segmentos.push(atual);
      }
      // Pula o separador (um ou dois caracteres)
      if (c === '&' && cmd[i + 1] === '&') i++;
      else if (c === '|' && cmd[i + 1] === '|') i++;
      atual = "";
    } else {
      atual += c;
    }
  }

  if (atual.trim()) {
    segmentos.push(atual);
  }

  return segmentos;
}

/**
 * O segmento tem subshell ou grupo `(...)`/`{...}`?
 *
 * `(cd /principal && codex exec --yolo)` de dentro do worktree: o split por
 * `&&` quebra em `(cd /principal ` e ` codex exec --yolo)` — nenhum dos dois
 * comeca com `cd` puro, entao o `CD` regex nunca casa e o `cd` do subshell
 * passa batido, sem marcar incerto. O `cd` de dentro de `(...)` NAO PERSISTE
 * para fora dele quando o shell roda de verdade — mas dentro do subshell ele
 * vale para os comandos ali, que e exatamente o perigo. Sem tentar "resolver"
 * o subshell (isso exigiria parsear a arvore inteira), a unica leitura segura
 * e marcar o resultado INCERTO.
 *
 * Duas condicoes, cada uma suficiente:
 *   - o segmento COMECA com `(` ou `{` (abre subshell ou grupo);
 *   - o segmento contem `(` ou `)` fora de aspas que nao seja abertura `$(`
 *     de substituicao de comando (essa ja cai no `/[$\`]/` de cima).
 */
function contemSubshellOuGrupo(seg) {
  if (/^\s*[({]/.test(seg)) return true;
  let aspa = null;
  for (let i = 0; i < seg.length; i += 1) {
    const c = seg[i];
    if (aspa) {
      if (c === aspa) aspa = null;
      continue;
    }
    if (c === '"' || c === "'") { aspa = c; continue; }
    if (c === "(" && seg[i - 1] !== "$") return true;
    if (c === ")") return true;
  }
  return false;
}

/**
 * Extrai o ÚLTIMO diretório de `-C` num segmento de git.
 *
 * Se múltiplos `-C` aparecem, git usa o último. Exemplo:
 * `git -C /a -C /b commit` → usa `/b`.
 */
function extrairUltimoDirGit(seg) {
  // Encontra todas as ocorrências de -C ou --work-tree
  const regex = /(?:-C|--work-tree(?:=|\s+))\s*(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))/g;
  let ultima = null;
  let match;

  while ((match = regex.exec(seg)) !== null) {
    ultima = match[1] || match[2] || match[3];
  }

  return ultima;
}

/**
 * Reconhece `cd`, `pushd`, `popd` e `env -C`/`--chdir=` num ÚNICO segmento, e
 * aplica o efeito ao `estado` da travessia (mutado in-place).
 *
 * ÚNICO lugar que sabe reconhecer estes quatro movedores de diretório —
 * nasceu da emenda do auditor à rodada 5 (lote 3, 2026-09-03): `alvosBash` e
 * `alvosBashEscrita`, em `gate-worktree.cjs`, só reconheciam `cd` (via
 * `seg.match(CD)` cru) e `git -C`, então `pushd <principal> && git commit`
 * e `env -C <principal> git commit` — o A2 do auditor aplicado ao caminho
 * mais crítico (commit/checkout/reset/merge no principal) — passavam com
 * exit 0. `cwdPorSegmento` já reconhecia os quatro só para o ramo de CLI do
 * `gate-worktree.cjs` e para `gate-staging-total.cjs`; agora os TRÊS
 * consumidores chamam este helper, em vez de cada um ter sua própria lista
 * (parcial) de movedores.
 *
 * `soMovedor: true` (cd/pushd/popd) — a regex é ANCORADA de ponta a ponta:
 * o segmento INTEIRO é o comando de mudança de diretório, nunca há outro
 * comando colado no mesmo segmento. Quem chama pode pular a checagem de
 * comando/verbo neste segmento e ir para o próximo.
 *
 * `soMovedor: false` para `env -C` (e para um segmento comum): `env -C X` é
 * um PREFIXO — o comando de verdade (git, CLI) vem depois, no MESMO
 * segmento (`env -C /principal git commit -m x`), e o cwd devolvido aqui
 * (o alvo do `-C`) é só para ESTE comando — não persiste em `estado.atual`
 * para os segmentos seguintes.
 *
 * @param {string} seg
 * @param {{atual: string, incerto: boolean, pilhaPushd: string[]}} estado
 * @returns {{cwd: string, incerto: boolean, soMovedor: boolean}}
 */
function resolverMovedor(seg, estado) {
  // Subshell/grupo: o `cd` de dentro dele nao persiste pra fora, mas vale
  // para os comandos dentro — a unica leitura segura e marcar INCERTO,
  // sem tentar decidir o resto deste segmento por ele.
  if (contemSubshellOuGrupo(seg)) estado.incerto = true;

  // `pushd X` — muda o cwd corrente igual `cd X`, guardando o de antes.
  const pd = seg.match(PUSHD);
  if (pd) {
    const destino = pd[1] || pd[2] || pd[3];
    estado.pilhaPushd.push(estado.atual);
    if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") {
      estado.incerto = true;
    } else {
      estado.atual = path.resolve(estado.atual, destino);
    }
    return { cwd: estado.atual, incerto: estado.incerto, soMovedor: true };
  }

  // `popd` — volta ao cwd de antes do ultimo `pushd`. Pilha vazia (nenhum
  // `pushd` visto NESTA linha) significa que o destino de verdade depende
  // de um estado de shell que este parser nao enxerga — INCERTO, nunca
  // "supõe que nada mudou".
  if (POPD.test(seg)) {
    if (estado.pilhaPushd.length) {
      estado.atual = estado.pilhaPushd.pop();
    } else {
      estado.incerto = true;
    }
    return { cwd: estado.atual, incerto: estado.incerto, soMovedor: true };
  }

  // `cd` isolado num segmento
  const cd = seg.match(CD);
  if (cd) {
    const destino = cd[1] || cd[2] || cd[3];
    // `cd -`, `cd ~`, `$VAR`, `$(...)`: não dá para resolver aqui sem executar.
    //
    // O `~` só é expansão de home no COMEÇO (`~`, `~/x`, `~fulano/x`). Até
    // 2026-08-17 este teste era /[$`~]/, que casava com o til em QUALQUER
    // posição — caminho do Windows tem til no meio (formato 8.3). O efeito
    // era o pior possível para um gate: `cd <worktree> && git commit` num
    // caminho 8.3 virava INCERTO, o conservadorismo somava o cwd principal
    // aos alvos, e o gate BARRAVA um commit perfeitamente legítimo dentro
    // do worktree. Achado pelo CI (Issue #16): a bateria ficou vermelha lá
    // e verde aqui. `$` e crase continuam valendo em qualquer posição —
    // são expansão mesmo.
    if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") {
      estado.incerto = true;
      return { cwd: estado.atual, incerto: estado.incerto, soMovedor: true };
    }
    estado.atual = path.resolve(estado.atual, destino);
    return { cwd: estado.atual, incerto: estado.incerto, soMovedor: true };
  }

  // `env -C <dir> <cmd>` — muda o cwd SO deste comando, nunca do shell:
  // nao mexe em `estado.atual`, que continua valendo para os segmentos
  // seguintes. NAO e `soMovedor`: o resto do segmento (o comando de
  // verdade) ainda precisa ser avaliado por quem chamou.
  const envC = seg.match(ENV_C);
  if (envC) {
    const destino = envC[1] || envC[2] || envC[3];
    if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") {
      return { cwd: estado.atual, incerto: true, soMovedor: false };
    }
    return { cwd: path.resolve(estado.atual, destino), incerto: estado.incerto, soMovedor: false };
  }

  return { cwd: estado.atual, incerto: estado.incerto, soMovedor: false };
}

/**
 * Resolve o diretório efetivo onde CADA SEGMENTO do comando roda, seguindo
 * `cd`, `pushd`/`popd`, `env -C` (via `resolverMovedor`) e `git -C`.
 *
 * Nasceu do H1 (rodada 5, lote 3, 2026-09-03): `resolverCwdEfetivo` só
 * devolvia o cwd FINAL da linha inteira, e quem decidia por ele julgava a
 * operação pelo cwd de onde a linha TERMINA, não de onde ela RODOU —
 * `codex exec --yolo && cd <worktree>` rodado no repo principal tem o
 * `codex` rodando no principal, mas o cwd final (depois do `cd`) é o
 * worktree, e o gate liberava lendo o lugar errado. Mesmo defeito em
 * `git add -A && cd <worktree>` no `gate-staging-total.cjs`.
 *
 * H2 (mesma rodada): `pushd <dir>` move como `cd <dir>` (e empilha o cwd de
 * antes para o `popd` desfazer); `popd` sem `pushd` correspondente nesta
 * mesma linha não dá pra resolver — INCERTO; `env -C <dir> <cmd>` muda o cwd
 * só DAQUELE comando, sem persistir para os segmentos seguintes. Nenhum dos
 * três era modelado: ficavam com `incerto=false` e o cwd inicial, liberando
 * o comando de verdade.
 *
 * A traversia percorre o comando mantendo o diretório corrente, sem escolher
 * um único alvo: isso permitiria `cd /worktree && git -C /repo-principal commit`
 * passar batido. `cd` que não resolve (variável, subshell, `cd -`) marca a
 * decisão como INCERTA, e conservadorismo somaria o cwd inicial.
 *
 * Aud3 (lacuna, baixa, rodada 5): flags de diretório da PRÓPRIA CLI alvo
 * (`codex --cwd X`, `gemini -C X`, `algumacli --directory X`) não são
 * modeladas — cada CLI tem sua própria sintaxe, e não há lista fechada de
 * flags de diretório por CLI. Registrado aqui, não coberto.
 *
 * @param {string} comando - Linha de comando shell, potencialmente com `;`, `&&`, etc.
 * @param {string} cwdInicial - Diretório inicial (antes do comando rodar).
 * @returns {Array<{seg: string, cwd: string, incerto: boolean}>} Um item por
 *   segmento, na ordem em que aparecem no comando.
 */
function cwdPorSegmento(comando, cwdInicial) {
  const segmentos = segmentosComAspas(comando);
  const estado = { atual: cwdInicial, incerto: false, pilhaPushd: [] };
  const resultado = [];

  for (const seg of segmentos) {
    const mov = resolverMovedor(seg, estado);
    if (mov.soMovedor) {
      resultado.push({ seg, cwd: mov.cwd, incerto: mov.incerto });
      continue;
    }

    // `git -C <dir>` — o argumento de `-C` vence o cwd do shell (o de `env -C`
    // incluso, se houver: `mov.cwd` já é o alvo do `env -C` deste segmento).
    // Usa o ÚLTIMO se houver múltiplos.
    if (seg.includes("git")) {
      const p = extrairUltimoDirGit(seg);
      if (p) {
        // `-C` com variável: não dá para resolver — fica INCERTO.
        if (/[$`]/.test(p)) {
          estado.incerto = true;
        } else {
          // O caminho de `-C` é o cwd efetivo deste segmento
          estado.atual = path.resolve(mov.cwd, p);
        }
        resultado.push({ seg, cwd: estado.atual, incerto: estado.incerto });
        continue;
      }
    }

    resultado.push({ seg, cwd: mov.cwd, incerto: mov.incerto });
  }

  return resultado;
}

/**
 * Wrapper de compatibilidade com o formato anterior: só o cwd e a incerteza
 * do ÚLTIMO segmento da linha. Consumidor que precisa do cwd de um segmento
 * ESPECÍFICO (onde a operação de verdade aparece, não onde a linha termina)
 * usa `cwdPorSegmento` direto — foi exatamente essa troca que resolveu o H1.
 *
 * @param {string} comando - Linha de comando shell, potencialmente com `;`, `&&`, etc.
 * @param {string} cwdInicial - Diretório inicial (antes do comando rodar).
 * @returns {{cwd: string, incerto: boolean}} O diretório efetivo e se há incerteza.
 */
function resolverCwdEfetivo(comando, cwdInicial) {
  const porSegmento = cwdPorSegmento(comando, cwdInicial);
  if (!porSegmento.length) return { cwd: cwdInicial, incerto: false };
  const ultimo = porSegmento[porSegmento.length - 1];
  return { cwd: ultimo.cwd, incerto: ultimo.incerto };
}

/**
 * Conferência de confinamento: o toplevel lido DE DENTRO de `dir` bate com `dir`?
 *
 * `git -C <dir-sem-.git> status --porcelain` responde pelo pai com exit 0,
 * mascarando a falta de `.git` próprio. Decisão D4 (design 2026-09-03):
 * qualquer `git -C <dir>` é conferido, rodando `git rev-parse --show-toplevel`
 * DE DENTRO de `<dir>` (nunca `git -C` de fora), e comparando por `realpath` se
 * o toplevel devolvido é o próprio `dir`.
 *
 * @param {string} dir - Diretório a conferir.
 * @returns {{ok: boolean, toplevel: string|null}} Se confinado e o toplevel lido.
 */
function toplevelConfinado(dir) {
  try {
    const toplevelRaw = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd: dir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();

    if (!toplevelRaw) return { ok: false, toplevel: null };

    // Comparação por `realpath` (native), nunca `path.resolve` + `startsWith`
    const dirReal = fs.realpathSync.native(dir);
    const toplevelReal = fs.realpathSync.native(toplevelRaw);

    return {
      ok: dirReal === toplevelReal,
      toplevel: toplevelRaw,
    };
  } catch {
    return { ok: false, toplevel: null };
  }
}

// Exports também as constantes para que alvosBash e alvosBashEscrita as importem,
// evitando duplicação de regex.
module.exports = {
  resolverCwdEfetivo,
  cwdPorSegmento,
  resolverMovedor,
  toplevelConfinado,
  segmentosComAspas,
  extrairUltimoDirGit,
  contemSubshellOuGrupo,
  CD,
  PUSHD,
  POPD,
  ENV_C,
  GIT_DIR_EXPLICITO,
  SEPARADORES,
};
