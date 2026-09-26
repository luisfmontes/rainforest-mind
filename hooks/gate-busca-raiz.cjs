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
    let i = 0;
    while (i < tokens.length) {
      const t = tokens[i];
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) || t === "sudo" || t === "command" || t === "exec") { i++; continue; }
      if (t === "timeout") { i += 2; continue; }
      break;
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
