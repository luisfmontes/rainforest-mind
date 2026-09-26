#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash) — nega, dentro de subagente, `find` que parte da raiz do disco.
 * Protege contra: subagente que termina e fica "travado" na lista porque deixou
 *   um `find /` rodando em segundo plano (o harness empurra para lá o que passa
 *   de 2 min, e varrer o disco inteiro no Windows não termina em tempo útil)
 * Não protege contra: bateria longa (resolvida pelo `timeout` explícito do perfil
 *   de trabalho, D4), busca longa em pasta grande que não é a raiz, janela principal
 *
 * Design: docs/rainforest/design/2026-09-25-busca-na-raiz.md (D1–D3). Medido nas
 * duas contas em 14 dias: 34 de 113 revisores com comando em segundo plano; os
 * `find /` prenderam por horas — inclusive com `-maxdepth 6` e `-maxdepth 2`, por
 * isso a profundidade não é saída.
 *
 * Só subagente (D2): `agent_id` só aparece no payload quando a chamada sai de
 * dentro de um (mesma fronteira da folha na portaria). Presença da chave, não
 * truthiness. Toggle `busca-na-raiz` (D3).
 *
 * Payload ilegível, vazio ou de outra ferramenta: sai 0, como os gates irmãos.
 */

const fs = require("node:fs");
const path = require("node:path");

// Raiz de disco como ponto de partida: `/`, `/c`, `/c/`, `C:`, `C:/`, `C:\`,
// `C:\\` (qualquer letra), com ou sem aspas.
const RAIZ_DE_DISCO = /^(\/|\/[a-zA-Z]\/?|[a-zA-Z]:[\\/]*)$/;

function tirarAspas(t) {
  return t.replace(/^(['"])(.*)\1$/, "$2");
}

/** Corpo de heredoc é texto, não comando: `cat <<'EOF'` com `find /` dentro
 * (um relato deste mesmo incidente) não pode ser barrado. Tira as linhas entre
 * `<<[-]DELIM` e a linha que é só `DELIM`. */
function semCorpoDeHeredoc(comando) {
  const linhas = comando.split("\n");
  const saida = [];
  let fim = null;
  for (const linha of linhas) {
    if (fim !== null) {
      if (linha.trim() === fim) fim = null;
      continue;
    }
    saida.push(linha);
    const m = linha.match(/<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/);
    if (m) fim = m[2];
  }
  return saida.join("\n");
}

// Palavras que vêm antes do comando de verdade sem mudar qual ele é: as
// palavras-chave do bash (`if find / ...; then`, `! find /`, `{ find /; }`) e
// os comandos que só envolvem outro (`time`, `nice -n 10`, `env VAR=x`,
// `timeout 300`, `xargs -0`). Terceira revisão: sem isto, qualquer uma delas
// antes do `find` fazia o segmento inteiro passar sem ser lido.
const PALAVRAS_CHAVE = new Set(["if", "then", "elif", "else", "while", "until", "do", "!", "{"]);
const ENVOLTORIOS = new Set(["sudo", "command", "exec", "nice", "env", "nohup", "xargs", "stdbuf", "timeout", "time"]);

function pularPrefixos(tokens, i) {
  while (i < tokens.length) {
    const t = tokens[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) || PALAVRAS_CHAVE.has(t)) { i++; continue; }
    if (ENVOLTORIOS.has(t)) {
      i++;
      // opções do envoltório e seus valores (`-n 10`, `-s KILL`, `-0`),
      // atribuições do `env` e a duração do `timeout` (`300`, `10s`, `1m`)
      while (i < tokens.length && (/^-/.test(tokens[i]) || /^\d+(\.\d+)?[smhd]?$/.test(tokens[i]) ||
        /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i]) || (/^-[ns]$/.test(tokens[i - 1]) && !/^-/.test(tokens[i])))) i++;
      continue;
    }
    break;
  }
  return i;
}

/** Pontos de partida de cada `find` do comando. Divide em segmentos por
 * `;`, `&&`, `||`, `|`, `&`, quebra de linha e abertura de substituição ou
 * subshell (`$(`, crase, `(`), e só olha o segmento cujo comando (depois de
 * `sudo`/`timeout N`/atribuições `VAR=x`) é `find` — `grep "find /"` e
 * `echo find /` não contam. */
function partidasDeFind(comando) {
  const partidas = [];
  // Todo `(` sem barra antes abre segmento: subshell colado (`true;(find /)`),
  // `$(`, `<(`/`>(` de substituição de processo. Só `\(` — a expressão do
  // próprio find — fica de fora. Tratar posição por posição deixou brecha duas
  // vezes na revisão; a classe inteira fecha aqui.
  const separado = semCorpoDeHeredoc(comando)
    .replace(/`/g, "\n")
    .replace(/(^|[^\\])\(/g, "$1\n");
  for (const segmento of separado.split(/&&|\|\||;|\||&|\n/)) {
    const tokens = segmento.trim().match(/"[^"]*"|'[^']*'|\S+/g) || [];
    let i = pularPrefixos(tokens, 0);
    // `bash -c "..."`, `sh -c '...'` e `eval "..."`: o texto de dentro é
    // comando, e passa pelo mesmo parser.
    if (/^(ba|z)?sh$/.test(tokens[i] || "")) {
      const c = tokens.indexOf("-c", i);
      if (c !== -1 && tokens[c + 1]) partidas.push(...partidasDeFind(tirarAspas(tokens[c + 1])));
      continue;
    }
    if (tokens[i] === "eval") {
      partidas.push(...partidasDeFind(tokens.slice(i + 1).map(tirarAspas).join(" ")));
      continue;
    }
    if (tokens[i] !== "find" && !/[\\/]find(\.exe)?$/.test(tokens[i] || "")) continue;
    i++;
    // opções de symlink/otimização antes dos caminhos
    while (i < tokens.length && /^-(H|L|P|O\d*|D)$/.test(tokens[i])) i++;
    while (i < tokens.length && !/^[-(!]/.test(tokens[i])) {
      partidas.push(tirarAspas(tokens[i]));
      i++;
    }
  }
  return partidas;
}

function buscaNaRaizLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("busca-na-raiz", { projeto });
}

function main() {
  let payload;
  try {
    const bruto = fs.readFileSync(0, "utf8");
    if (!bruto.trim()) process.exit(0);
    payload = JSON.parse(bruto);
  } catch {
    process.exit(0);
  }
  if (!payload || payload.tool_name !== "Bash") process.exit(0);
  if (!Object.prototype.hasOwnProperty.call(payload, "agent_id")) process.exit(0);

  const comando = payload.tool_input && payload.tool_input.command;
  if (typeof comando !== "string") process.exit(0);

  const raiz = partidasDeFind(comando).find((p) => RAIZ_DE_DISCO.test(p));
  if (raiz === undefined) process.exit(0);

  // Mesma ordem da portaria (`raizDoProjeto`) e dos gates irmãos: o cwd do
  // EVENTO primeiro. Subagente em worktree traz ali o worktree, enquanto
  // CLAUDE_PROJECT_DIR aponta o checkout principal — a config que vale é a
  // de onde o agente trabalha (achado da revisão de 2026-09-25).
  const projeto = payload.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!buscaNaRaizLigada(path.resolve(projeto))) process.exit(0);

  process.stderr.write(
    `BLOQUEADO: \`find ${raiz}\` varre o disco inteiro — passa dos 2 min, vai para segundo plano ` +
    `e deixa este agente preso na lista depois de terminar (com ou sem -maxdepth). ` +
    `Procure no caminho conhecido: o repositório (\`git rev-parse --show-toplevel\`), a pasta de dados ` +
    `do rainforest (~/.rainforest), a config da integração (ex.: ~/.whatsapp-mcp/) ou o caminho que o briefing deu. ` +
    `Se o caminho não é conhecido, diga isso no relato em vez de varrer. ` +
    `Para desligar neste projeto: "busca-na-raiz": false em .rainforest/config.json.\n`
  );
  process.exit(2);
}

main();
