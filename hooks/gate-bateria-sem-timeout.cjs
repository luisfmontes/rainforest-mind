#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash) — nega, dentro de subagente, bateria sem `timeout` > 120000ms
 * ou `varrer-baterias.sh` sem `--so <bateria>`.
 *
 * Protege contra: subagente que empurra bateria longa para segundo plano,
 *   deixando o agente preso na lista até ela terminar (design de 2026-09-27,
 *   medido em 10 de 14 subagentes na sessão fafafc3e). Baterias (`testa-*.sh`,
 *   `testa-*.cjs`, `varrer-baterias.sh`, `conferir-mutacao.cjs`,
 *   `conferir-fluxo.cjs mutacoes`) rodadas sem `timeout` na chamada do Bash
 *   passam do teto de 2 min e são empurradas para segundo plano pelo harness.
 *   Com `timeout: 600000` (10 min), o Bash aguarda em primeiro plano.
 *
 * Não protege contra: leitura de bateria (`cat`, `grep`, `sed -n`, `head`),
 *   bateria chamada por variável ou dentro de heredoc, comando longo que não
 *   é bateria (resolvida pelo `timeout` explícito do perfil, fora de escopo)
 *
 * Design: docs/rainforest/design/agente-sem-background.md (D1–D3).
 * Só subagente (D3): `agent_id` só aparece no payload quando a chamada sai de
 * dentro de um. Presença da chave, não truthiness. Toggle `bateria-sem-timeout` (D3).
 *
 * Payload ilegível, vazio ou de outra ferramenta: sai 0, como os gates irmãos.
 */

const fs = require("node:fs");
const path = require("node:path");
const { colapsaContinuacaoDeLinha } = require("./lib/tokens-comando.cjs");

// Corpo de heredoc é texto, não comando
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

function bateriaLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("bateria-sem-timeout", { projeto });
}

/**
 * Reconhece se um segmento contém uma bateria sem timeout apropriado.
 * Retorna { ehBateria, nomeScript: nome ou null, ehVarredor, args: [] }
 */
function analisaSegmento(segmento) {
  const tokens = segmento.trim().match(/"[^"]*"|'[^']*'|\S+/g) || [];
  if (!tokens.length) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };

  // Pula atribuições (VAR=x) e palavras-chave
  let i = 0;
  const palavrasChave = new Set(["if", "then", "elif", "else", "while", "until", "do", "!", "{"]);
  const wrappers = new Set(["sudo", "command", "exec", "nice", "env", "nohup", "xargs", "stdbuf", "timeout", "time"]);

  while (i < tokens.length) {
    const tok = tokens[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tok)) { i++; continue; }
    if (palavrasChave.has(tok)) { i++; continue; }
    if (wrappers.has(tok)) {
      // Pula o wrapper e qualquer flag. Para simplificar, pulamos só o próprio token
      // e tentamos o próximo. Timeout com valor é só pulado um (a duração fica para depois)
      i++;
      if (tok === "timeout" && i < tokens.length && /^\d+/.test(tokens[i])) i++;
      continue;
    }
    break;
  }

  if (i >= tokens.length) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };

  // Token na posição i é o comando (ou interpretador)
  const cmd = tokens[i];
  let nomeScript = null;
  let scriptIndex = i;

  // Se é interpretador (bash, sh, node, etc), o script é o próximo token não-flag
  if (/^(ba|z)?sh$|^node$/.test(cmd)) {
    i++;
    // Pula flags do interpretador
    while (i < tokens.length && tokens[i].startsWith("-")) i++;
    if (i < tokens.length) {
      nomeScript = tokens[i].replace(/^["']|["']$/g, "");
      scriptIndex = i;
    }
  } else if (/[\\/]/.test(cmd)) {
    // Comando direto que contém / ou \ (caminho, com ou sem ./)
    nomeScript = cmd.replace(/^["']|["']$/g, "");
  } else {
    // Não é interpretador nem contém separador de caminho — pode ser nome de bateria direto
    // (como um comando no PATH), mas aqui não conta como bateria
    return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };
  }

  if (!nomeScript) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };

  // Extrai basename
  const basename = nomeScript.split(/[\\/]/).pop();

  // Conta como bateria: testa-*.sh, testa-*.cjs, varrer-baterias.sh, conferir-mutacao.cjs
  const ehBateriaSimplesmente = /^(testa-.*\.(sh|cjs)|varrer-baterias\.sh|conferir-mutacao\.cjs)$/.test(basename);
  if (!ehBateriaSimplesmente && basename !== "conferir-fluxo.cjs") {
    return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };
  }

  // Se é conferir-fluxo.cjs, só conta como bateria se primeiro arg é "mutacoes"
  if (basename === "conferir-fluxo.cjs") {
    const args = [];
    for (let j = scriptIndex + 1; j < tokens.length; j++) {
      args.push(tokens[j].replace(/^["']|["']$/g, ""));
    }
    // Só conta se "mutacoes" é o primeiro arg
    if (args.length === 0 || args[0] !== "mutacoes") {
      return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };
    }
    const ehVarredor = false;
    return { ehBateria: true, nomeScript: basename, ehVarredor, args };
  }

  // Se é varrer-baterias.sh, marca como varredor
  const ehVarredor = basename === "varrer-baterias.sh";

  // Coleta args (tokens depois do script)
  const args = [];
  for (let j = scriptIndex + 1; j < tokens.length; j++) {
    args.push(tokens[j].replace(/^["']|["']$/g, ""));
  }

  return { ehBateria: true, nomeScript: basename, ehVarredor, args };
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

  const entrada = payload.tool_input;
  const comando = entrada && entrada.command;
  if (typeof comando !== "string") process.exit(0);

  // Projeto do evento, mesmo que worktree em isolamento
  const projeto = payload.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!bateriaLigada(path.resolve(projeto))) process.exit(0);

  // Remove heredoc do comando (corpo é texto, não código), após colapsar continuação de linha
  const cmdLimpo = semCorpoDeHeredoc(colapsaContinuacaoDeLinha(comando));

  // Divide em segmentos por separadores de comando
  const separado = cmdLimpo
    .replace(/`/g, "\n")
    .replace(/(^|[^\\])\(/g, "$1\n")
    .replace(/(^|[^\\])\)/g, "$1\n");

  // Analisa cada segmento
  for (const segmento of separado.split(/&&|\|\||;|\||&|\n/)) {
    const analise = analisaSegmento(segmento);
    if (!analise.ehBateria) continue;

    // Duas decisões independentes
    const temTimeout = typeof entrada.timeout === "number" && entrada.timeout > 120000;
    const varreduraCompleta = analise.ehVarredor && !analise.args.includes("--so");

    if (varreduraCompleta) {
      // D2: varredura completa negada mesmo com timeout
      process.stderr.write(
        `BLOQUEADO: \`${analise.nomeScript}\` sem \`--so <bateria>\` é varredura completa (~29 min) ` +
        `— passa do teto de 10 min do Bash e não termina em primeiro plano. ` +
        `Use \`--so <bateria>\` ou rode a bateria direto. Varredura completa roda na integração (quem faz merge). ` +
        `Para desligar neste projeto: "bateria-sem-timeout": false em .rainforest/config.json.\n`
      );
      process.exit(2);
    }

    if (analise.ehBateria && !temTimeout) {
      // D1: bateria sem timeout apropriado
      process.stderr.write(
        `BLOQUEADO: \`${analise.nomeScript}\` rodada sem \`timeout: 600000\` na chamada do Bash ` +
        `— passa de 2 min, é empurrada para segundo plano e deixa este agente preso na lista. ` +
        `Adicione \`timeout: 600000\` à chamada da ferramenta Bash (10 min). ` +
        `Para desligar neste projeto: "bateria-sem-timeout": false em .rainforest/config.json.\n`
      );
      process.exit(2);
    }
  }

  process.exit(0);
}

main();
