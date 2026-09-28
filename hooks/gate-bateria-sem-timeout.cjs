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
const { colapsaContinuacaoDeLinha, tokensComAspas, posicaoDeComando, textoAPartir, desempacotarWrapperDeString, pularFlagsDoWrapper } = require("./lib/tokens-comando.cjs");

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

/**
 * Segmenta comando respeitando aspas e tratando crase/$(...)
 * como separadores FORA de aspas simples e também DENTRO de
 * aspas duplas (onde o bash expande). Usa pilha para `$(`/crase.
 *
 * Separadores: ; && || | & \n ( ) { } ` $(
 */
function segmentosComAspasESubcomandos(cmd) {
  const segmentos = [];
  let atual = "";
  let estado = "fora"; // "fora" | "simples" | "duplas"
  const pilha = []; // [{tipo: "crase|paren", estadoAntes}, ...]

  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];
    const prox = i + 1 < cmd.length ? cmd[i + 1] : null;

    if (estado === "simples") {
      // Dentro de aspas simples: só sair com ' ou adicionar
      if (c === "'") {
        estado = "fora";
      }
      atual += c;
      continue;
    }

    if (c === "'") {
      // Abrir aspas simples
      estado = "simples";
      atual += c;
      continue;
    }

    if (c === '"') {
      // Alternar aspas duplas
      estado = estado === "duplas" ? "fora" : "duplas";
      atual += c;
      continue;
    }

    if (c === "\\") {
      // Escape: emite \ + próximo
      atual += c;
      if (prox !== null) {
        atual += prox;
        i += 1;
      }
      continue;
    }

    if (estado === "duplas") {
      // Dentro de aspas duplas: só `"`, `\`, e potencialmente crase/$(
      if (c === "`") {
        // Crase dentro de aspas duplas: abre subcomando
        if (atual.trim()) segmentos.push(atual);
        pilha.push({ tipo: "crase", estado: "duplas" });
        estado = "fora";
        atual = "";
        continue;
      }

      if (c === "$" && prox === "(") {
        // $( dentro de aspas duplas: abre subcomando
        if (atual.trim()) segmentos.push(atual);
        pilha.push({ tipo: "paren", estado: "duplas" });
        estado = "fora";
        atual = "";
        i += 1; // pula o (
        continue;
      }

      // Tudo mais dentro de aspas duplas é texto
      atual += c;
      continue;
    }

    // Fora de aspas (estado === "fora")
    if (c === "`") {
      // Crase fora de aspas
      if (pilha.length > 0 && pilha[pilha.length - 1].tipo === "crase") {
        // Fechar crase
        pilha.pop();
        const prev = pilha.length > 0 ? pilha[pilha.length - 1] : null;
        estado = prev ? prev.estado : "fora";
      } else {
        // Abrir crase
        if (atual.trim()) segmentos.push(atual);
        pilha.push({ tipo: "crase", estado: "fora" });
        atual = "";
      }
      continue;
    }

    if (c === "$" && prox === "(") {
      // $( fora de aspas
      if (pilha.length > 0 && pilha[pilha.length - 1].tipo === "paren") {
        // Não fecha aqui, só incrementa nesting — mas não vamos tratar nesting,
        // a régua do bash é abrir fechadas, recursão não existe no gate.
        // Simplificado: só primeira abertura é segmento.
        atual += c;
        i += 1;
        atual += cmd[i];
      } else {
        // Abrir $(
        if (atual.trim()) segmentos.push(atual);
        pilha.push({ tipo: "paren", estado: "fora" });
        atual = "";
        i += 1; // pula o (
      }
      continue;
    }

    if (c === ")") {
      // Fechar paren se topo da pilha for paren
      if (pilha.length > 0 && pilha[pilha.length - 1].tipo === "paren") {
        pilha.pop();
        const prev = pilha.length > 0 ? pilha[pilha.length - 1] : null;
        estado = prev ? prev.estado : "fora";
        // ) é separador, salva segmento
        if (atual.trim()) segmentos.push(atual);
        atual = "";
        continue;
      }
      // ) não fecha nada: separador fora de aspas
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }

    // Fora de aspas: verificar separadores de comando
    if ((c === "&" && prox === "&") || (c === "|" && prox === "|")) {
      // && ou ||
      if (atual.trim()) segmentos.push(atual);
      i += 1; // pula o segundo caractere
      atual = "";
      continue;
    }

    if (c === ";" || c === "|" || c === "&" || c === "\n" || c === "{" || c === "(" || c === ")") {
      // Separador simples
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }

    // Caractere normal
    atual += c;
  }

  if (atual.trim()) segmentos.push(atual);
  return segmentos;
}

function bateriaLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("bateria-sem-timeout", { projeto });
}

/**
 * Reconhece se um segmento contém uma bateria sem timeout apropriado.
 * Retorna { ehBateria, nomeScript: nome ou null, ehVarredor, args: [] }
 *
 * Usa `tokensComAspas` e `posicaoDeComando` para pular wrappers e flags corretamente,
 * incluindo flags que consomem valor (nice -n, timeout -k, env -i, etc).
 * Também desempacota wrappers de string (bash -c, eval, etc).
 */
function analisaSegmento(segmento) {
  const toks = tokensComAspas(segmento.trim());
  if (!toks.length) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };

  // Acha posição de comando, pulando wrappers e flags com valores conhecidos
  const posCmd = posicaoDeComando(toks);
  if (posCmd === null) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };

  const cmd = toks[posCmd];
  let nomeScript = null;
  let scriptIndex = posCmd;

  // Tenta desempacotador de string (bash -c "...", eval, etc)
  const wrapper = desempacotarWrapperDeString(textoAPartir(toks, posCmd));
  if (wrapper.interno && !wrapper.ilegivel) {
    // String desempacotada e legível: analisa recursivamente
    const subAnalise = analisaSegmento(wrapper.interno);
    if (subAnalise.ehBateria) return subAnalise;
    // Senão, continua com o resto
  }

  // `stdbuf` só ajusta o buffer e repassa o comando, como `nice` (revisão 3):
  // pula as flags dele (`-oL`, `-i 0`, `--output=L`) e analisa o que sobra.
  if (cmd.v === "stdbuf") {
    const i = pularFlagsDoWrapper(toks, posCmd + 1, "stdbuf");
    return i < toks.length ? analisaSegmento(textoAPartir(toks, i)) : { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };
  }

  // Se é interpretador (bash, sh, node, etc), o script é o próximo token não-flag
  if (/^(ba|z)?sh$|^node$/.test(cmd.v)) {
    scriptIndex = posCmd + 1;
    // Pula flags do interpretador. Checagem de sintaxe (`bash -n`, `node --check`)
    // volta na hora e não é execução (revisão 3): não conta como bateria.
    while (scriptIndex < toks.length && toks[scriptIndex].v.startsWith("-")) {
      const flag = toks[scriptIndex].v;
      const soSintaxe = cmd.v === "node" ? (flag === "--check" || flag === "-c") : /^-[a-z]*n[a-z]*$/.test(flag);
      if (soSintaxe) return { ehBateria: false, nomeScript: null, ehVarredor: false, args: [] };
      scriptIndex++;
    }
    if (scriptIndex < toks.length) {
      nomeScript = toks[scriptIndex].v;
    }
  } else if (/[\\/]/.test(cmd.v)) {
    // Comando direto que contém / ou \ (caminho, com ou sem ./)
    nomeScript = cmd.v;
  } else {
    // Não é interpretador nem contém separador de caminho
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
    for (let j = scriptIndex + 1; j < toks.length; j++) {
      args.push(toks[j].v);
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
  for (let j = scriptIndex + 1; j < toks.length; j++) {
    args.push(toks[j].v);
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

  // Divide em segmentos respeitando aspas e crases/$(...)
  const segmentos = segmentosComAspasESubcomandos(cmdLimpo);

  // Coleta análises de todos os segmentos
  const analises = [];
  for (const segmento of segmentos) {
    const analise = analisaSegmento(segmento);
    if (analise.ehBateria) {
      analises.push(analise);
    }
  }

  // Duas decisões independentes por análise
  const temTimeout = typeof entrada.timeout === "number" && entrada.timeout > 120000;

  for (const analise of analises) {
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

    if (!temTimeout) {
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
