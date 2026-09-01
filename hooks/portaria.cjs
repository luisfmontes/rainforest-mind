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

function obterDefinicaoAgente(raiz, nomeAgente) {
  // Tenta `.claude/agents/<nome>.md` primeiro, depois `agents/<nome>.md`
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

  // D3 passo 3: agente não declarado → nega
  if (!manifesto[nomeAgente]) {
    const motivo = `agente '${nomeAgente}' não consta no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);
    negar(motivo);
  }

  const agentConfig = manifesto[nomeAgente];

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

main();
