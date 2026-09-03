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
 * Resolve o diretório efetivo onde um comando roda, seguindo `cd` e `git -C`.
 *
 * A traversia percorre o comando mantendo o diretório corrente, sem escolher
 * um único alvo: isso permitiria `cd /worktree && git -C /repo-principal commit`
 * passar batido. `cd` que não resolve (variável, subshell, `cd -`) marca a
 * decisão como INCERTA, e conservadorismo somaria o cwd inicial.
 *
 * @param {string} comando - Linha de comando shell, potencialmente com `;`, `&&`, etc.
 * @param {string} cwdInicial - Diretório inicial (antes do comando rodar).
 * @returns {{cwd: string, incerto: boolean}} O diretório efetivo e se há incerteza.
 */
function resolverCwdEfetivo(comando, cwdInicial) {
  const segmentos = segmentosComAspas(comando);
  let atual = cwdInicial;
  let incerto = false;

  for (const seg of segmentos) {
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
        incerto = true;
        continue;
      }
      atual = path.resolve(atual, destino);
      continue;
    }

    // `git -C <dir>` — o argumento de `-C` vence o cwd do shell
    // Usa o ÚLTIMO se houver múltiplos
    if (seg.includes("git")) {
      const p = extrairUltimoDirGit(seg);
      if (p) {
        // `-C` com variável: não dá para resolver — fica INCERTO.
        if (/[$`]/.test(p)) {
          incerto = true;
          continue;
        }
        // O caminho de `-C` é o cwd efetivo deste segmento
        atual = path.resolve(atual, p);
        continue;
      }
    }
  }

  return { cwd: atual, incerto };
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
  toplevelConfinado,
  segmentosComAspas,
  extrairUltimoDirGit,
  CD,
  GIT_DIR_EXPLICITO,
  SEPARADORES,
};
