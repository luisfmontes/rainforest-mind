#!/usr/bin/env node
"use strict";
/* Portaria — NÚCLEO DE DECISÃO (Tarefas 2 e 3 do fluxo 9, D1–D7).
 *
 * Registrado como PreToolUse em `.claude/settings.json` com matcher de
 * despacho de subagente. Aqui é implementada a decisão fail-closed sobre
 * admissão de subagente via `.rainforest/agentes.json` (manifesto) + estágio
 * ativo (sem exceder estagios permitidos + escreve).
 *
 * Exit 0: aprovado, linha de log anexada.
 * Exit 2: negado, motivo no stderr (fail-closed — sempre com motivo não-vazio).
 *
 * Modo captura (D7) mantido: primeira amostra em `.rainforest/portaria/amostra.json`.
 */

const fs = require("fs");
const path = require("path");

function raizDoProjeto() {
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

function negar(motivo) {
  if (motivo) {
    process.stderr.write(motivo);
    if (!motivo.endsWith('\n')) process.stderr.write('\n');
  }
  process.exit(2);
}

function normalizarNomeAgente(nome) {
  if (!nome || typeof nome !== "string") return null;
  // Remove prefixo tipo 'rainforest-mind:' se existir
  if (nome.includes(":")) {
    return nome.split(":").pop();
  }
  return nome;
}

function obterDefinicaoAgente(raiz, nomeAgente, agentesDir) {
  // Se agentesDir for passado, usa-o diretamente
  if (agentesDir) {
    const caminho = path.join(agentesDir, `${nomeAgente}.md`);
    if (fs.existsSync(caminho)) {
      try {
        return fs.readFileSync(caminho, "utf8");
      } catch {
        return null;
      }
    }
    return null;
  }

  // Caso padrão: tenta `.claude/agents/<nome>.md` primeiro, depois `agents/<nome>.md`
  const caminhos = [
    path.join(raiz, ".claude", "agents", `${nomeAgente}.md`),
    path.join(raiz, "agents", `${nomeAgente}.md`),
  ];

  for (const caminho of caminhos) {
    if (fs.existsSync(caminho)) {
      try {
        return fs.readFileSync(caminho, "utf8");
      } catch {
        // Arquivo ilegível — passa para o próximo
      }
    }
  }

  return null; // Arquivo não encontrado
}

function gravarAmostra(raiz, payload) {
  // Captura primeira amostra apenas (D7)
  const dir = path.join(raiz, ".rainforest", "portaria");
  const amostraPath = path.join(dir, "amostra.json");

  if (!fs.existsSync(amostraPath)) {
    try {
      fs.mkdirSync(dir, { recursive: true });
      const tmp = amostraPath + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(payload, null, 2) + "\n", "utf8");
      fs.renameSync(tmp, amostraPath);
    } catch {
      // Falha de gravacao nao pode travar a sessao do usuario.
    }
  }
}

function gravarDespacho(raiz, decisao, agente, estagio, sessao, motivo) {
  // Append-only log de despachos (D4)
  const dir = path.join(raiz, ".rainforest", "portaria");
  const logPath = path.join(dir, "despachos.jsonl");

  try {
    fs.mkdirSync(dir, { recursive: true });

    const entrada = {
      ts: new Date().toISOString(),
      agente,
      estagio,
      decisao,
      sessao,
    };

    if (motivo) {
      entrada.motivo = motivo;
    }

    const linha = JSON.stringify(entrada) + "\n";
    fs.appendFileSync(logPath, linha, "utf8");
  } catch {
    // Falha de gravacao nao pode travar a sessao do usuario.
  }
}

function main() {
  const raiz = raizDoProjeto();

  // Ler payload do stdin
  let bruto = "";
  try {
    bruto = fs.readFileSync(0, "utf8");
  } catch {
    negar("Não foi possível ler o payload do stdin");
  }

  if (!bruto.trim()) {
    negar("Payload vazio");
  }

  let payload;
  try {
    payload = JSON.parse(bruto);
  } catch {
    negar("Payload JSON inválido");
  }

  // Grava amostra (primeira captura vence)
  gravarAmostra(raiz, payload);

  // Extrai nome do agente (com normalização)
  const nomeAgenteBruto = payload.tool_input && payload.tool_input.subagent_type;
  if (!nomeAgenteBruto) {
    negar("Campo tool_input.subagent_type ausente no payload");
  }

  const nomeAgente = normalizarNomeAgente(nomeAgenteBruto);
  if (!nomeAgente) {
    negar("Nome do agente inválido");
  }

  const sessao = payload.session_id || "desconhecida";

  // Carrega manifesto (D3 passo 2: ausente ou inválido → nega)
  const manifestoPath = path.join(raiz, ".rainforest", "agentes.json");
  let manifesto;

  if (!fs.existsSync(manifestoPath)) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto ausente");
    negar(`Manifesto não encontrado em ${manifestoPath}`);
  }

  try {
    const brutoManifesto = fs.readFileSync(manifestoPath, "utf8");
    manifesto = JSON.parse(brutoManifesto);
  } catch {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto JSON inválido");
    negar("Manifesto JSON inválido");
  }

  // D3 passo 2b: validar versao e agentes (schema D2)
  if (manifesto.versao === undefined || manifesto.versao === null) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto sem versao");
    negar("Manifesto sem versao");
  }

  if (manifesto.versao !== 1) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, `manifesto com versao desconhecida: ${manifesto.versao}`);
    negar(`Manifesto com versao desconhecida: ${manifesto.versao}`);
  }

  if (typeof manifesto.agentes !== "object" || manifesto.agentes === null || Array.isArray(manifesto.agentes)) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto.agentes invalido");
    negar("Manifesto.agentes inválido");
  }

  // D3 passo 3: agente não declarado → nega
  if (!manifesto.agentes[nomeAgente]) {
    const motivo = `agente '${nomeAgente}' não consta no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);
    negar(motivo);
  }

  const agentConfig = manifesto.agentes[nomeAgente];

  // D3 passo 4: sem estágio ativo → nega
  const estReader = require("./lib/estagio-ativo.cjs");
  const estResult = estReader.resolver({ cwd: raiz });

  if (!estResult) {
    const motivo = "sem estágio ativo — abra um fluxo";
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);
    negar(motivo);
  }

  const { estagio: estagioAtivo } = estResult;

  // D3 passo 5: estágio fora da lista permitida → nega
  if (!agentConfig.estagios || !Array.isArray(agentConfig.estagios)) {
    const motivo = `Configuração inválida do agente '${nomeAgente}' no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
    negar(motivo);
  }

  if (!agentConfig.estagios.includes(estagioAtivo)) {
    const permitidos = agentConfig.estagios.join(", ");
    const motivo = `estágio '${estagioAtivo}' não permitido para '${nomeAgente}' (permitidos: ${permitidos})`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
    negar(motivo);
  }

  // D3 passo 6: escreve: false com tools fora de allowlist → nega
  if (agentConfig.escreve === false) {
    const def = obterDefinicaoAgente(raiz, nomeAgente);

    if (def) {
      // Parse frontmatter para extrair tools (se declaradas)
      const fmMatch = def.match(/^---\n([\s\S]*?)\n---/);
      if (fmMatch) {
        const frontmatter = fmMatch[1];
        const toolsMatch = frontmatter.match(/^tools:\s*(.+)$/m);

        if (toolsMatch) {
          const toolsStr = toolsMatch[1];
          const allowlist = ["Read", "Grep", "Glob"];

          // Parse lista de tools (pode ser simples ou complexa)
          const tools = toolsStr.split(",").map(t => t.trim());

          for (const tool of tools) {
            if (!allowlist.includes(tool)) {
              const motivo = `agente '${nomeAgente}' com escreve:false declara tool fora da allowlist: ${tool}`;
              gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
              negar(motivo);
            }
          }
        }
      }
    }
    // Se arquivo não encontrado, não falha — pula a checagem (D3 passo 6)
  }

  // Passou tudo → aprova (D3 passo 7)
  gravarDespacho(raiz, "allow", nomeAgente, estagioAtivo, sessao);
  process.exit(0);
}

function executarLint(manifestoPath, agentesDir) {
  let estadoModule;
  try {
    estadoModule = require("../scripts/estado.cjs");
  } catch (err) {
    console.error(`erro: não consegui carregar estado.cjs: ${err.message}`);
    process.exit(1);
  }

  const { PRE_REQUISITOS } = estadoModule;
  const estadioValidos = new Set(
    Object.keys(PRE_REQUISITOS).filter(e => e !== "limpar")
  );

  let erros = 0;
  let avisos = 0;

  // Carregar e validar manifesto
  let manifesto;
  if (!fs.existsSync(manifestoPath)) {
    console.error(`erro: manifesto não encontrado em ${manifestoPath}`);
    erros++;
  } else {
    try {
      const conteudo = fs.readFileSync(manifestoPath, "utf8");
      manifesto = JSON.parse(conteudo);

      // Checagem 5: validar schema D2
      if (manifesto.versao === undefined || manifesto.versao === null) {
        console.error("erro: manifesto sem versao");
        erros++;
      } else if (manifesto.versao !== 1) {
        console.error(`erro: manifesto com versao desconhecida: ${manifesto.versao}`);
        erros++;
      } else if (typeof manifesto.agentes !== "object" || manifesto.agentes === null || Array.isArray(manifesto.agentes)) {
        console.error("erro: manifesto.agentes invalido");
        erros++;
      }
    } catch (err) {
      console.error("erro: manifesto JSON inválido");
      erros++;
      manifesto = null;
    }
  }

  if (!manifesto) {
    if (erros > 0) {
      process.exit(1);
    }
    return;
  }

  const agentes = manifesto.agentes || {};
  const nomesDeclArados = Object.keys(agentes);

  // Listar arquivos em agentes-dir
  let agentesEmDisco = [];
  if (fs.existsSync(agentesDir)) {
    agentesEmDisco = fs
      .readdirSync(agentesDir)
      .filter(f => f.endsWith(".md"))
      .map(f => f.replace(/\.md$/, ""));
  }

  const agentesEmDiscoSet = new Set(agentesEmDisco);

  // Checagem 1: agente no manifesto sem arquivo correspondente
  for (const nome of nomesDeclArados) {
    if (!agentesEmDiscoSet.has(nome)) {
      console.error(`erro: agente '${nome}' declarado no manifesto mas sem arquivo em ${agentesDir}/${nome}.md`);
      erros++;
    }

    // Checagem 4: estágios desconhecidos
    const config = agentes[nome];
    if (config && Array.isArray(config.estagios)) {
      for (const est of config.estagios) {
        if (!estadioValidos.has(est)) {
          console.error(`erro: agente '${nome}' declara estágio desconhecido: '${est}'`);
          erros++;
        }
      }
    }

    // Checagem 3: escreve: false mas tool de escrita no frontmatter
    if (config && config.escreve === false) {
      const def = obterDefinicaoAgente(process.env.CLAUDE_PROJECT_DIR || process.cwd(), nome, agentesDir);
      if (def) {
        const fmMatch = def.match(/^---\n([\s\S]*?)\n---/);
        if (fmMatch) {
          const frontmatter = fmMatch[1];
          const toolsMatch = frontmatter.match(/^tools:\s*(.+)$/m);
          if (toolsMatch) {
            const toolsStr = toolsMatch[1];
            const allowlist = ["Read", "Grep", "Glob"];
            const tools = toolsStr.split(",").map(t => t.trim());
            for (const tool of tools) {
              if (!allowlist.includes(tool)) {
                console.error(`erro: agente '${nome}' com escreve:false declara tool fora da allowlist: ${tool}`);
                erros++;
              }
            }
          }
        }
      }
    }
  }

  // Checagem 2: arquivo em agentes-dir sem entrada no manifesto (órfão)
  for (const nome of agentesEmDisco) {
    if (!nomesDeclArados.includes(nome)) {
      console.warn(`aviso: agente '${nome}' em ${agentesDir} mas não declarado no manifesto (órfão)`);
      avisos++;
    }
  }

  if (erros > 0) {
    process.exit(1);
  }
  // Avisos não mudam exit code
}

if (require.main === module) {
  if (process.argv[2] === "--lint") {
    let manifestoPath = ".rainforest/agentes.json";
    let agentesDir = "agents";

    for (let i = 3; i < process.argv.length; i++) {
      if (process.argv[i] === "--manifesto" && i + 1 < process.argv.length) {
        manifestoPath = process.argv[i + 1];
        i++;
      } else if (process.argv[i] === "--agentes-dir" && i + 1 < process.argv.length) {
        agentesDir = process.argv[i + 1];
        i++;
      }
    }

    const raiz = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    // Se o caminho for absoluto, usa como está; se for relativo, usa raiz
    const manifestoCompleto = path.isAbsolute(manifestoPath) ? manifestoPath : path.join(raiz, manifestoPath);
    const agentesCompleto = path.isAbsolute(agentesDir) ? agentesDir : path.join(raiz, agentesDir);
    executarLint(manifestoCompleto, agentesCompleto);
  } else {
    main();
  }
}
