#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash) — nega, dentro de subagente, todo comando `gh` que
 * ESCREVE no GitHub: no comando direto, atrás de um wrapper que repassa
 * (`stdbuf`, `env`, `timeout`, ...), dentro de um wrapper de string
 * (`bash -c`, `eval`, `Invoke-Expression`, `pwsh -Command`, `cmd /c`) ou no
 * corpo de um heredoc citado como texto.
 *
 * Protege contra: subagente rodando `gh issue close`, `gh pr merge`, `gh
 * release create`, `gh api -X POST`, etc. — direto ou escondido atrás de um
 * wrapper. Duas vezes (2026-09-13, `zerar-issues-3`; 2026-09-28,
 * `zerar-issues-10`) um revisor rodou `gh issue close 12` real com a
 * proibição só em prosa no briefing; a regra em prosa não segura.
 *
 * Não protege (ainda) contra: escrita escondida dentro de um SCRIPT que o
 * subagente manda executar (`bash script.sh` com `gh issue close` no corpo
 * do arquivo) — é a tarefa 2 do plano (D4/D5), ponto de extensão marcado
 * abaixo em `arquivoDeScriptExecutado`/`TODO_TAREFA_2`. Escrita por outro
 * meio que não `gh` (`curl` na API do GitHub, `git push`) está fora de
 * escopo (design, seção "Fora de escopo").
 *
 * Design: docs/rainforest/design/gate-subagente-sem-gh.md (D1-D6).
 * Só subagente (D1): `agent_id` só aparece no payload quando a chamada sai de
 * dentro de um. Presença da chave, não truthiness — mesma regra de
 * `gate-bateria-sem-timeout.cjs`. Toggle `subagente-sem-gh` (D1), padrão
 * ligado, mesma forma de `bateria-sem-timeout`.
 *
 * Payload ilegível, vazio ou de outra ferramenta: sai 0, como os gates irmãos.
 */

const path = require("node:path");
const {
  tokensComAspas, posicaoDeComando, textoAPartir,
  WRAPPERS_QUE_REPASSAM, WRAPPERS_DE_COMANDO, desempacotarWrapperDeString,
  OPERADORES_DE_DOIS, colapsaContinuacaoDeLinhaNoTopo, semContrabarra,
} = require("./lib/tokens-comando.cjs");
const { corpoDeHeredoc, linhaDoHeredocTemInterpretador, fimDaLinhaLogica } = require("./lib/heredoc.cjs");

/**
 * D2 — tabela de VERBOS DE ESCRITA por família de subcomando `gh`. A linha
 * de `issue` é citada ao pé da letra pela mutação (catraca do plano): mudar
 * este Set é o comportamento que a bateria tem que sentir.
 */
const VERBOS_ESCRITA = {
  issue: new Set(["close", "comment", "edit", "create", "reopen", "delete", "transfer", "pin", "unpin", "lock", "unlock"]),
  pr: new Set(["create", "edit", "merge", "close", "comment", "reopen", "review", "ready"]),
  release: new Set(["create", "edit", "delete", "upload"]),
  repo: new Set(["create", "edit", "delete", "rename", "archive"]),
  label: new Set(["create", "edit", "delete", "set"]),
  secret: new Set(["create", "edit", "delete", "set"]),
  variable: new Set(["create", "edit", "delete", "set"]),
  workflow: new Set(["run", "enable", "disable"]),
  run: new Set(["rerun", "cancel", "delete"]),
};

// Todos os pares [família, verbo] da tabela acima, como sequência de DOIS
// tokens — usados pela rede de segurança W2 (wrapper desconhecido) e pela
// varredura de texto de heredoc, que procuram a sequência literal em vez de
// consultar a tabela por família (ali o primeiro token já é sabidamente `gh`;
// aqui não se sabe qual comando o cerca, então casa-se o par direto).
const PADROES_DE_ESCRITA = [];
for (const [familia, verbos] of Object.entries(VERBOS_ESCRITA)) {
  for (const verbo of verbos) PADROES_DE_ESCRITA.push([familia, verbo]);
}

// Flags de `gh api` que consomem o próximo token como VALOR do método HTTP.
const FLAGS_METODO = new Set(["-x", "--method"]);
// Flags de `gh api` que indicam corpo/campo — sem `-X`/`--method` explícito
// (ou explícito e diferente de GET), o `gh api` faz POST por padrão.
const FLAGS_CAMPO = new Set(["-f", "-F", "--field", "--raw-field", "--input"]);

/**
 * `gh api ...` escreve? D2: `-X`/`--method` diferente de `GET`, OU
 * `-f`/`-F`/`--field`/`--raw-field`/`--input` sem `-X GET` explícito.
 * `argsApi` são os tokens (strings cruas) depois de `api`.
 */
function apiEhEscrita(argsApi) {
  let metodo = null;
  let temCampo = false;
  for (let i = 0; i < argsApi.length; i += 1) {
    const tok = semContrabarra(argsApi[i]);
    const igual = tok.indexOf("=");
    const chave = (igual === -1 ? tok : tok.slice(0, igual)).toLowerCase();
    // `-XPOST` colado (integração, 2026-09-28): saía 0.
    if (igual === -1 && /^-X./.test(tok)) {
      metodo = tok.slice(2).toUpperCase();
      continue;
    }
    if (FLAGS_METODO.has(chave)) {
      const valor = igual !== -1 ? tok.slice(igual + 1) : argsApi[i + 1];
      metodo = String(valor || "").toUpperCase();
      if (igual === -1) i += 1;
      continue;
    }
    if (FLAGS_CAMPO.has(chave)) {
      temCampo = true;
      continue;
    }
  }
  if (metodo !== null) return metodo !== "GET";
  return temCampo;
}

/**
 * `subcomandos` são os tokens (strings cruas, `.v` de `tokensComAspas`) que
 * vêm depois de `gh`. Devolve `true` se a invocação ESCREVE no GitHub (D2).
 */
// Integração (2026-09-28): flag global antes da família ou entre família e
// verbo escondia a escrita — `gh -R o/r issue close 12` e `gh issue -R o/r
// close 12` saíam 0 (o cobra aceita a flag em qualquer ponto). Família e verbo
// passam a ser os dois primeiros POSICIONAIS; `-R`/`--repo` consomem o valor.
const FLAGS_GH_COM_VALOR = new Set(["-r", "--repo", "--hostname"]);

function comandoGhEhEscrita(subcomandos) {
  const posicionais = [];
  for (let i = 0; i < subcomandos.length && posicionais.length < 2; i += 1) {
    const tok = semContrabarra(subcomandos[i]);
    if (tok.startsWith("-")) {
      if (!tok.includes("=") && FLAGS_GH_COM_VALOR.has(tok.toLowerCase())) i += 1;
      continue;
    }
    posicionais.push({ v: tok.toLowerCase(), i });
  }
  if (posicionais.length === 0) return false;
  const familia = posicionais[0].v;
  if (familia === "api") return apiEhEscrita(subcomandos.slice(posicionais[0].i + 1));
  const verbos = VERBOS_ESCRITA[familia];
  if (!verbos) return false;
  if (posicionais.length < 2) return false;
  return verbos.has(posicionais[1].v);
}

/**
 * Índice da primeira ocorrência de `padrao` (par [família, verbo]) como
 * sub-sequência CONTÍGUA (case-insensitive, sem contrabarra) em `tokens`, ou
 * -1. Usada pela rede de segurança W2 e pela varredura de heredoc — as duas
 * situações em que não se sabe de antemão que o primeiro token é `gh`.
 */
function indiceSequenciaGh(tokens, padrao) {
  for (let i = 0; i + 1 < tokens.length; i += 1) {
    if (semContrabarra(tokens[i]).toLowerCase() !== "gh") continue;
    const familia = semContrabarra(tokens[i + 1]).toLowerCase();
    if (familia !== padrao[0]) continue;
    if (familia === "api") return i; // api decidido à parte, por flags
    if (i + 2 >= tokens.length) continue;
    const verbo = semContrabarra(tokens[i + 2]).toLowerCase();
    if (verbo === padrao[1]) return i;
  }
  return -1;
}

function bateriaLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("subagente-sem-gh", { projeto });
}

// TEXTOS_DE_HEREDOC: corpos de heredoc tratados como DADO nesta invocação —
// o texto ainda é varrido pelos padrões diretos (D3), como
// `gate-fechar-issue.cjs` já faz para `gh issue close`/`gh pr merge`.
let TEXTOS_DE_HEREDOC = [];

/**
 * Separa um comando em segmentos, respeitando aspas simples/duplas — mesma
 * segmentação de `gate-fechar-issue.cjs` (`segmentosParaGate`), incluindo o
 * tratamento de heredoc/here-string como TEXTO quando o receptor não é
 * interpretador. Ver o docblock de lá para o porquê de cada ramo; mantida
 * aqui como cópia (não extraída para a lib comum) porque `arquivos:` da
 * tarefa 1 não inclui mover esta função — `gate-bateria-sem-timeout.cjs` já
 * segue o mesmo precedente de manter a própria segmentação.
 */
function segmentosParaGate(cmd) {
  cmd = colapsaContinuacaoDeLinhaNoTopo(cmd);
  const segmentos = [];
  let atual = "";
  let aspa = null;

  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];

    if (aspa) {
      if (aspa === '"' && c === "$" && cmd[i + 1] === "(") {
        let profundidade = 1;
        let j = i + 2;
        let interno = "";
        while (j < cmd.length && profundidade > 0) {
          if (cmd[j] === "(") profundidade += 1;
          else if (cmd[j] === ")") {
            profundidade -= 1;
            if (profundidade === 0) break;
          }
          interno += cmd[j];
          j += 1;
        }
        if (interno.trim()) segmentos.push(interno);
      }
      if (c === aspa) aspa = null;
      atual += c;
      continue;
    }
    if (c === '"' || c === "'") {
      aspa = c;
      atual += c;
      continue;
    }
    if (c === "&" && cmd[i + 1] === "&") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      i++;
      continue;
    }
    if (c === "|" && cmd[i + 1] === "|") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      i++;
      continue;
    }
    if (OPERADORES_DE_DOIS.has(cmd[i] + (cmd[i + 1] || ""))) {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      i++;
      continue;
    }
    if (c === ";" || c === "|" || c === "\n" || c === "(" || c === ")" || c === "{" || c === "}") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }
    if (
      c === "&" &&
      cmd[i + 1] !== "&" &&
      cmd[i + 1] !== ">" &&
      cmd[i - 1] !== ">" &&
      cmd[i - 1] !== "<" &&
      cmd[i - 1] !== "|" &&
      atual.trim() !== ""
    ) {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }
    if (c === "<" && cmd[i + 1] === "<" && cmd[i + 2] === "<") {
      let k = i + 3;
      while (k < cmd.length && (cmd[k] === ' ' || cmd[k] === '\t')) k++;
      let conteudo = '';
      if (cmd[k] === "'" || cmd[k] === '"') {
        const aspaHs = cmd[k];
        k++;
        while (k < cmd.length && cmd[k] !== aspaHs) { conteudo += cmd[k]; k++; }
        if (k < cmd.length) k++;
      } else {
        while (k < cmd.length && !/[\s;&|]/.test(cmd[k])) {
          if (cmd[k] === '\\' && k + 1 < cmd.length) { conteudo += cmd[k + 1]; k += 2; continue; }
          conteudo += cmd[k]; k++;
        }
      }
      if (linhaDoHeredocTemInterpretador(cmd, i)) {
        for (const sub of segmentosParaGate(conteudo)) {
          if (sub.trim()) segmentos.push(sub);
        }
      } else {
        TEXTOS_DE_HEREDOC.push(conteudo);
      }
      atual += cmd.slice(i, k);
      i = k - 1;
      continue;
    }
    if (c === "<" && cmd[i + 1] === "<") {
      const heredoc = corpoDeHeredoc(cmd, i);
      if (heredoc !== null) {
        atual += cmd.slice(i, i + 2);
        let j = i + 2;
        if (cmd[j] === '-') j++;
        while (j < cmd.length && (cmd[j] === ' ' || cmd[j] === '\t')) j++;
        if (cmd[j] === '"' || cmd[j] === "'") {
          const tipoAspa = cmd[j];
          j++;
          while (j < cmd.length && cmd[j] !== tipoAspa) j++;
          if (j < cmd.length && cmd[j] === tipoAspa) j++;
        } else {
          while (j < cmd.length && cmd[j] !== ' ' && cmd[j] !== '\t' && cmd[j] !== '\n' && cmd[j] !== ';' && cmd[j] !== '&' && cmd[j] !== '|' && cmd[j] !== ')' && cmd[j] !== '<' && cmd[j] !== '>') {
            j++;
          }
        }
        atual += cmd.slice(i + 2, j);

        if (linhaDoHeredocTemInterpretador(cmd, i)) {
          for (const sub of segmentosParaGate(heredoc.corpo)) {
            if (sub.trim()) segmentos.push(sub);
          }
        } else {
          TEXTOS_DE_HEREDOC.push(heredoc.corpo);
        }

        const inicioCorpo = fimDaLinhaLogica(cmd, i);
        if (inicioCorpo !== -1 && inicioCorpo < heredoc.fim) {
          const fechado = inicioCorpo + 1 + heredoc.corpo.length < heredoc.fim;
          const depois = fechado ? cmd.slice(heredoc.fim - 1) : '';
          cmd = cmd.slice(0, inicioCorpo) + depois;
        }
        i = j - 1;
        continue;
      }
    }
    atual += c;
  }

  if (atual.trim()) segmentos.push(atual);
  return segmentos;
}

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

const MSG_JANELA_PRINCIPAL =
  "Escrita no GitHub (fechar/comentar Issue, abrir/mergear/fechar PR, criar release, " +
  "rodar workflow, etc.) é da janela principal, não de subagente.\n";

const MSG_MEDIR =
  "Para medir este gate sem executar `gh` de verdade, alimente-o com o payload JSON " +
  "no stdin do hook:\n" +
  "  echo '{\"tool_name\":\"Bash\",\"agent_id\":\"a1\",\"tool_input\":{\"command\":\"...\"}}' " +
  "| node hooks/gate-subagente-sem-gh.cjs\n";

function bloqueiaEscrita(comandoVisto) {
  bloqueia(
    `BLOQUEADO pelo gate de subagente sem GitHub do rainforest-mind.\n\n` +
    `Comando visto: \`${comandoVisto.trim()}\`\n\n` +
    MSG_JANELA_PRINCIPAL + "\n" + MSG_MEDIR
  );
}

function bloqueiaIlegivel(comandoVisto) {
  bloqueia(
    `BLOQUEADO pelo gate de subagente sem GitHub do rainforest-mind.\n\n` +
    `Comando visto: \`${comandoVisto.trim()}\`\n\n` +
    `Razão: comando encapsulado (eval/bash -c/sh -c/pwsh -Command/cmd /c) contém ` +
    `variável ou substituição de comando; não consigo ler o que roda dentro com ` +
    `segurança (ilegível), e pode ser um \`gh\` de escrita escondido.\n\n` +
    MSG_JANELA_PRINCIPAL + "\n" + MSG_MEDIR
  );
}

/**
 * `exe` (já normalizado) é um prefixo que sabemos que só repassa o comando
 * adiante, ou um wrapper que sabemos desempacotar? Mesma função de
 * `gate-fechar-issue.cjs` — um wrapper RECONHECIDO já foi resolvido por
 * `posicaoDeComando`/`desempacotarWrapperDeString`; se o mecanismo específico
 * dele falhar (ou for mutado), a bateria tem que sentir, não ser socorrida
 * por esta rede de segurança genérica.
 */
function ehPrefixoOuWrapperConhecido(exe) {
  return (
    exe === "gh" ||
    exe === "eval" ||
    exe === "invoke-expression" ||
    exe === "iex" ||
    exe === "pwsh" ||
    exe === "powershell" ||
    exe === "cmd" ||
    WRAPPERS_QUE_REPASSAM.has(exe) ||
    !!WRAPPERS_DE_COMANDO[exe]
  );
}

function normalizarExecutavel(nome) {
  let sem_aspas = nome.replace(/^["']|["']$/g, "");
  sem_aspas = path.basename(sem_aspas);
  sem_aspas = sem_aspas.replace(/\.(exe|cmd|bat)$/i, "");
  return sem_aspas.toLowerCase();
}

/**
 * Ponto de extensão da tarefa 2 (D4/D5, ainda não implementada): quando um
 * segmento executa um ARQUIVO (`bash|sh|source|. <arq>`, caminho direto
 * `./x.sh`, `node|python <arq>`), a tarefa 2 lê esse arquivo e nega se
 * alguma linha não comentada casar com o padrão de escrita de D2 — com
 * isenção para bateria `testa-*` rastreada (D5). Deliberadamente vazio nesta
 * tarefa: `segmento` e `cwd` chegam prontos para quem implementar a tarefa 2
 * não precisar redesenhar a chamada.
 */
// eslint-disable-next-line no-unused-vars
function arquivoDeScriptExecutado(segmento, cwd) {
  return null; // TODO (tarefa 2): ler o arquivo e devolver achado de escrita, ou null.
}

/**
 * Aplica as checagens D2/D3 a UM segmento (já separado por `;`, `&&`, `||`,
 * `|`, `(`, `)`, `{`, `}` via `segmentosParaGate`).
 */
function processarSegmento(segmento) {
  const toks = tokensComAspas(segmento);
  if (toks.length === 0) return;

  const pos = posicaoDeComando(toks);
  if (pos !== null && normalizarExecutavel(toks[pos].v) === "gh") {
    const subcomandos = toks.slice(pos + 1).map((t) => t.v);
    if (comandoGhEhEscrita(subcomandos)) {
      bloqueiaEscrita(segmento);
    }
    return;
  }

  const { interno, ilegivel } = pos === null
    ? { interno: null, ilegivel: false }
    : desempacotarWrapperDeString(textoAPartir(toks, pos));
  if (ilegivel) {
    bloqueiaIlegivel(segmento);
  }
  if (interno !== null) {
    for (const sub of segmentosParaGate(interno)) {
      processarSegmento(sub);
    }
    return;
  }

  // W2: rede de segurança para wrapper DESCONHECIDO — procura a sequência
  // `gh <família> <verbo>` em qualquer posição do segmento, fora de
  // comentário shell (`#` não citado). Mesma postura de `gate-fechar-issue.cjs`.
  const idxComentario = toks.findIndex((t) => !t.q && t.v.startsWith("#"));
  const toksSemComentario = idxComentario === -1 ? toks : toks.slice(0, idxComentario);
  const valores = toksSemComentario.map((t) => t.v);
  const primeiro = valores.length ? normalizarExecutavel(valores[0]) : null;
  if (primeiro !== null && !ehPrefixoOuWrapperConhecido(primeiro)) {
    for (const padrao of PADROES_DE_ESCRITA) {
      const idx = indiceSequenciaGh(valores, padrao);
      if (idx === -1) continue;
      if (padrao[0] === "api") {
        // `api` decidido por flags — recolhe o resto do segmento a partir
        // dali e aplica a mesma checagem de `comandoGhEhEscrita`.
        if (comandoGhEhEscrita(valores.slice(idx + 1))) bloqueiaEscrita(segmento);
      } else {
        bloqueiaEscrita(segmento);
      }
      return;
    }
  }
}

/**
 * Varre o TEXTO dos corpos de heredoc tratados como dado (D3) — mesma busca
 * de sequência da rede W2, linha a linha, sem desempacotar wrapper. Só
 * `gh <família> <verbo>` literal no corpo dispara o bloqueio.
 */
function verificarTextosDeHeredoc() {
  for (const corpo of TEXTOS_DE_HEREDOC) {
    for (const linha of corpo.split('\n')) {
      if (!linha.trim()) continue;
      let toks;
      try { toks = tokensComAspas(linha); } catch { toks = linha.split(/\s+/).filter(Boolean).map((v) => ({ v, q: false })); }
      const idxComentario = toks.findIndex((t) => !t.q && t.v.startsWith("#"));
      const valores = (idxComentario === -1 ? toks : toks.slice(0, idxComentario)).map((t) => t.v);
      for (const padrao of PADROES_DE_ESCRITA) {
        const idx = indiceSequenciaGh(valores, padrao);
        if (idx === -1) continue;
        if (padrao[0] === "api") {
          if (comandoGhEhEscrita(valores.slice(idx + 1))) { bloqueiaEscrita(linha); }
        } else {
          bloqueiaEscrita(linha);
        }
        break;
      }
    }
  }
}

function main() {
  let ev;
  try {
    const bruto = require("node:fs").readFileSync(0, "utf8");
    if (!bruto.trim()) process.exit(0);
    ev = JSON.parse(bruto);
  } catch {
    process.exit(0);
  }
  if (!ev || ev.tool_name !== "Bash") process.exit(0);
  if (!Object.prototype.hasOwnProperty.call(ev, "agent_id")) process.exit(0);

  const projeto = ev.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!bateriaLigada(path.resolve(projeto))) process.exit(0);

  const comando = ev.tool_input && ev.tool_input.command;
  if (typeof comando !== "string" || !comando) process.exit(0);

  TEXTOS_DE_HEREDOC = [];
  for (const segmento of segmentosParaGate(comando)) {
    processarSegmento(segmento);
  }
  verificarTextosDeHeredoc();

  process.exit(0);
}

if (require.main === module) main();

module.exports = { comandoGhEhEscrita, apiEhEscrita, VERBOS_ESCRITA };
