#!/usr/bin/env node
"use strict";
/* Bateria do corpus de comandos legítimos (tarefa 13 do fluxo 2026-09-30-semear-travas).
 *
 * Para cada um dos dez gates (gate-worktree, gate-staging-total, gate-verificador-staged,
 * gate-mensagem-commit, gate-fechar-issue, gate-git-verificacao, gate-publicacao-destino,
 * gate-busca-raiz, gate-bateria-sem-timeout, gate-subagente-sem-gh), para cada comando
 * de `hooks/fixtures/corpus-comandos/legitimos.jsonl`, roda o gate como processo real
 * com o payload no stdin em dois contextos (principal e subagente).
 *
 * Exit 2 fora de `esperados.json` é FALHA (bloqueio não registrado).
 * Entrada de `esperados.json` que não barra mais é FALHA (achado apodrece).
 *
 * Com RFM_CORPUS_LOCAL, roda corpus adicional e lista cada bloqueio como achado.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const RAIZ_FIXTURES = path.join(__dirname, "fixtures", "corpus-comandos");
const PAYLOAD_BASE_PATH = path.join(__dirname, "fixtures", "busca-raiz", "payload-bash-subagente.json");
const GATES = [
  "gate-worktree",
  "gate-staging-total",
  "gate-verificador-staged",
  "gate-mensagem-commit",
  "gate-fechar-issue",
  "gate-git-verificacao",
  "gate-publicacao-destino",
  "gate-busca-raiz",
  "gate-bateria-sem-timeout",
  "gate-subagente-sem-gh",
];

const MAPA_CONFIG = {
  "gate-worktree": "gate-worktree",
  "gate-staging-total": "gate-staging",
  "gate-verificador-staged": "gate-verificador-staged",
  "gate-mensagem-commit": null, // sem config
  "gate-fechar-issue": "gate-fechar-issue",
  "gate-git-verificacao": "gate-git-verificacao",
  "gate-publicacao-destino": "gate-publicacao",
  "gate-busca-raiz": "busca-na-raiz",
  "gate-bateria-sem-timeout": "bateria-sem-timeout",
  "gate-subagente-sem-gh": "subagente-sem-gh",
};

let ok = 0;
let falhou = 0;
let bloqueios_encontrados = [];

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 400)}` : ""}`);
  }
}

function achado(id, gate, contexto, motivo) {
  bloqueios_encontrados.push({ id, gate, contexto, motivo, issue: null });
}

// Preparar sandbox
const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "corpus-"));
let wt; // Será preenchido após criar o worktree
process.on("exit", () => {
  try {
    fs.rmSync(caixa, { recursive: true, force: true });
  } catch {}
});

// Inicializar git no sandbox
const sandbox = path.join(caixa, "repo");
fs.mkdirSync(sandbox, { recursive: true });
const config = path.join(sandbox, ".rainforest");
fs.mkdirSync(config, { recursive: true });

try {
  const { spawnSync: spawn } = require("child_process");
  spawn("git", ["init"], { cwd: sandbox, encoding: "utf8" });
  spawn("git", ["config", "user.name", "Teste"], { cwd: sandbox, encoding: "utf8" });
  spawn("git", ["config", "user.email", "teste@local"], { cwd: sandbox, encoding: "utf8" });
  // Commit inicial
  fs.writeFileSync(path.join(sandbox, "file.txt"), "x");
  spawn("git", ["add", "file.txt"], { cwd: sandbox, encoding: "utf8" });
  spawn("git", ["commit", "-m", "init"], { cwd: sandbox, encoding: "utf8" });
  // Criar worktree linkado para contexto subagente
  wt = path.join(caixa, "worktree");
  const r = spawn("git", ["worktree", "add", "--detach", wt], { cwd: sandbox, encoding: "utf8" });
  if (r.status !== 0) {
    console.error("Erro ao criar worktree:", r.stderr);
    process.exit(1);
  }
} catch (e) {
  console.error("Erro ao preparar sandbox:", e.message);
  process.exit(1);
}

// Carregar payload base
const PAYLOAD_BASE = (() => {
  try {
    return JSON.parse(fs.readFileSync(PAYLOAD_BASE_PATH, "utf8"));
  } catch (e) {
    console.error("Erro ao carregar payload base:", e.message);
    process.exit(1);
  }
})();

// Carregar comandos
const COMANDOS = (() => {
  try {
    const linhas = fs.readFileSync(path.join(RAIZ_FIXTURES, "legitimos.jsonl"), "utf8").split("\n").filter(Boolean);
    return linhas.map(l => JSON.parse(l));
  } catch (e) {
    console.error("Erro ao carregar comandos:", e.message);
    process.exit(1);
  }
})();

// Carregar esperados
const ESPERADOS = (() => {
  try {
    return JSON.parse(fs.readFileSync(path.join(RAIZ_FIXTURES, "esperados.json"), "utf8"));
  } catch (e) {
    console.error("Erro ao carregar esperados:", e.message);
    process.exit(1);
  }
})();

// Função para rodar gate com payload customizado
function rodarPayload(gatePath, payload, config_obj) {
  const cwd_efetivo = payload.cwd;

  // Escrever config se necessário
  if (config_obj) {
    fs.writeFileSync(path.join(config, "config.json"), JSON.stringify(config_obj));
  } else {
    try {
      fs.unlinkSync(path.join(config, "config.json"));
    } catch {}
  }

  const r = spawnSync(process.execPath, [gatePath], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: cwd_efetivo,
      RFM_ROOT: path.join(caixa, "dados"),
    },
  });

  return {
    status: r.status,
    stdout: r.stdout || "",
    stderr: r.stderr || "",
  };
}

// Função para rodar gate (wrapper que prepara payload padrão)
function rodarGate(gatePath, comando, contexto, config_obj) {
  const payload = JSON.parse(JSON.stringify(PAYLOAD_BASE));
  payload.tool_input.command = comando;
  const cwd_efetivo = contexto === "subagente" ? wt : sandbox;
  payload.cwd = cwd_efetivo;
  if (contexto === "principal") {
    delete payload.agent_id;
    delete payload.agent_type;
  }
  // contexto === "subagente" mantém agent_id e agent_type

  return rodarPayload(gatePath, payload, config_obj);
}

// Rodapé de tempo
const inicio = Date.now();

// Contar verificações esperadas
let verificacoes_esperadas = 0;
for (const esperado of ESPERADOS) {
  if (GATES.includes(esperado.gate)) {
    verificacoes_esperadas++;
  }
}

console.log("== corpus-comandos ==");

// Funções de teste para controle positivo de cada gate
function testeGateWorktree() {
  // Subagente escrevendo no checkout principal (não worktree)
  const payload = JSON.parse(JSON.stringify(PAYLOAD_BASE));
  payload.cwd = sandbox; // cwd = checkout principal (não worktree)
  payload.tool_name = "Write";
  payload.tool_input = { file_path: path.join(sandbox, "test-file.txt"), content: "test" };
  // agent_id já está no PAYLOAD_BASE para subagente
  const r = rodarPayload(path.join(__dirname, "gate-worktree.cjs"), payload);
  return r.status === 2 ? true : `exit ${r.status}, esperado 2`;
}

function testeGateMensagemCommit() {
  // Commit com assunto > 72 colunas
  const assunto_longo = "x".repeat(80); // Maior que 72 colunas
  const cmd = `git commit -m "${assunto_longo}"`;
  const r = rodarGate(path.join(__dirname, "gate-mensagem-commit.cjs"), cmd, "principal");
  return r.status === 2 ? true : `exit ${r.status}, esperado 2`;
}

function testeGateVerificadorStaged() {
  // Arquivo staged com dados sensíveis que o conferir-publicacao rejeita
  try {
    // Copiar conferir-publicacao.cjs para a sandbox
    const conferirSource = path.join(path.dirname(__dirname), "scripts", "conferir-publicacao.cjs");
    const scriptsDir = path.join(sandbox, "scripts");
    fs.mkdirSync(scriptsDir, { recursive: true });
    fs.copyFileSync(conferirSource, path.join(scriptsDir, "conferir-publicacao.cjs"));
    // git pelo caminho (Issue #392): sem o resolvedor ao lado, o require quebra e o
    // gate recusaria por MODULE_NOT_FOUND, nao pelo telefone.
    fs.mkdirSync(path.join(sandbox, "hooks", "lib"), { recursive: true });
    fs.copyFileSync(path.join(path.dirname(__dirname), "hooks", "lib", "resolver-executavel.cjs"), path.join(sandbox, "hooks", "lib", "resolver-executavel.cjs"));

    // Escrever arquivo com dado sensível (telefone)
    const telefone = "+55" + "119" + "12345" + "678";
    const conteudo_sensivel = `Contato do cliente: ${telefone}\nNão publicar!`;
    fs.writeFileSync(path.join(sandbox, "file.txt"), conteudo_sensivel, "utf8");

    // Stage o arquivo
    spawnSync("git", ["add", "file.txt"], { cwd: sandbox, encoding: "utf8" });

    // Rodar gate
    const payload = JSON.parse(JSON.stringify(PAYLOAD_BASE));
    payload.cwd = sandbox;
    payload.tool_name = "Bash";
    payload.tool_input = { command: "git commit -m test" };
    delete payload.agent_id; // contexto principal
    delete payload.agent_type;

    const r = rodarPayload(path.join(__dirname, "gate-verificador-staged.cjs"), payload);

    // Limpar
    try {
      spawnSync("git", ["reset", "-q"], { cwd: sandbox });
      fs.unlinkSync(path.join(sandbox, "file.txt"));
    } catch {}

    return r.status === 2 ? true : `exit ${r.status}, esperado 2`;
  } catch (e) {
    return `erro: ${e.message}`;
  }
}

function testeGatePublicacaoDestino() {
  // Escrita com dados sensíveis (telefone)
  try {
    const payload = JSON.parse(JSON.stringify(PAYLOAD_BASE));
    payload.cwd = sandbox;
    payload.tool_name = "Write";
    // Montar telefone em tempo de execução para não bloquear a bateria em si
    const telefone = "+55" + "119" + "12345" + "678";
    payload.tool_input = {
      file_path: path.join(sandbox, "dados.txt"),
      content: `Contato: ${telefone}`
    };
    delete payload.agent_id;
    delete payload.agent_type;

    const r = rodarPayload(path.join(__dirname, "gate-publicacao-destino.cjs"), payload);
    return r.status === 2 ? true : `exit ${r.status}, esperado 2`;
  } catch (e) {
    return `erro: ${e.message}`;
  }
}

function testeGateBateriaSemTimeout() {
  // Bateria sem timeout em subagente
  const payload = JSON.parse(JSON.stringify(PAYLOAD_BASE));
  payload.cwd = wt; // worktree para subagente
  payload.tool_name = "Bash";
  payload.tool_input = { command: "bash scripts/testa-cli-externo.cjs" };
  delete payload.tool_input.timeout; // Remover timeout
  // agent_id mantido para subagente

  const r = rodarPayload(path.join(__dirname, "gate-bateria-sem-timeout.cjs"), payload);
  return r.status === 2 ? true : `exit ${r.status}, esperado 2`;
}

// Rodar replay de cada gate
for (const gateName of GATES) {
  const gatePath = path.join(__dirname, `${gateName}.cjs`);
  if (!fs.existsSync(gatePath)) {
    console.log(`  FALHA ${gateName}: arquivo não encontrado`);
    falhou++;
    continue;
  }

  let bloqueios_gate = 0;
  let fora_esperados = 0;
  let erros_gate = 0;
  const chaves_bloqueadas = new Set();

  for (const cmd of COMANDOS) {
    for (const contexto of ["principal", "subagente"]) {
      const r = rodarGate(gatePath, cmd.comando, contexto);

      // Verificar exit code inválido
      if (r.status !== 0 && r.status !== 2 && r.status !== null) {
        erros_gate++;
        const primeira_linha_stderr = (r.stderr || "").split("\n")[0];
        console.log(`    ERRO ${gateName} ${cmd.id} (${contexto}): exit ${r.status} — ${primeira_linha_stderr.slice(0, 100)}`);
      }

      const chave = `${cmd.id}|${gateName}|${contexto}`;
      const bloqueado = r.status === 2;
      const registrado = ESPERADOS.some(
        e => e.id === cmd.id && e.gate === gateName && e.contexto === contexto
      );

      if (bloqueado) {
        bloqueios_gate++;
        chaves_bloqueadas.add(chave);
        if (!registrado) {
          fora_esperados++;
          // Registrar achado
          const primeira_linha_stderr = (r.stderr || "").split("\n")[0];
          achado(cmd.id, gateName, contexto, primeira_linha_stderr);
        }
      }
    }
  }

  // Controle positivo: testar comando que DEVE ser bloqueado
  let resultado_controle = null;
  let mensagem_controle = "";

  switch (gateName) {
    case "gate-git-verificacao": {
      const r_principal = rodarGate(gatePath, "git commit --no-verify", "principal");
      const r_subagente = rodarGate(gatePath, "git commit --no-verify", "subagente");
      resultado_controle = r_principal.status === 2 || r_subagente.status === 2;
      break;
    }
    case "gate-staging-total": {
      const r_principal = rodarGate(gatePath, "git add -A", "principal");
      const r_subagente = rodarGate(gatePath, "git add -A", "subagente");
      resultado_controle = r_principal.status === 2 || r_subagente.status === 2;
      break;
    }
    case "gate-fechar-issue": {
      const r_principal = rodarGate(gatePath, "gh issue close 1", "principal");
      const r_subagente = rodarGate(gatePath, "gh issue close 1", "subagente");
      resultado_controle = r_principal.status === 2 || r_subagente.status === 2;
      break;
    }
    case "gate-busca-raiz": {
      const r = rodarGate(gatePath, "find / -name x", "subagente");
      resultado_controle = r.status === 2;
      break;
    }
    case "gate-subagente-sem-gh": {
      const r = rodarGate(gatePath, "gh issue close 1", "subagente");
      resultado_controle = r.status === 2;
      break;
    }
    case "gate-worktree": {
      const testResult = testeGateWorktree();
      resultado_controle = testResult === true;
      if (testResult !== true) mensagem_controle = testResult;
      break;
    }
    case "gate-mensagem-commit": {
      const testResult = testeGateMensagemCommit();
      resultado_controle = testResult === true;
      if (testResult !== true) mensagem_controle = testResult;
      break;
    }
    case "gate-verificador-staged": {
      const testResult = testeGateVerificadorStaged();
      resultado_controle = testResult === true;
      if (testResult !== true) mensagem_controle = testResult;
      break;
    }
    case "gate-publicacao-destino": {
      const testResult = testeGatePublicacaoDestino();
      resultado_controle = testResult === true;
      if (testResult !== true) mensagem_controle = testResult;
      break;
    }
    case "gate-bateria-sem-timeout": {
      const testResult = testeGateBateriaSemTimeout();
      resultado_controle = testResult === true;
      if (testResult !== true) mensagem_controle = testResult;
      break;
    }
  }

  if (resultado_controle !== null) {
    caso(`${gateName}: controle positivo barrado (exit 2)`, resultado_controle, mensagem_controle);
  }

  const msg = `${gateName}: ${COMANDOS.length} comando(s) x 2 contexto(s), ${fora_esperados} bloqueio(s) fora de esperados`;
  caso(msg, fora_esperados === 0 && erros_gate === 0, fora_esperados > 0 ? `fora: ${fora_esperados}` : erros_gate > 0 ? `erros: ${erros_gate}` : "");
}

// Verificar se esperados estão apodrencidos
let apodrecidos = 0;
for (const esperado of ESPERADOS) {
  const cmd = COMANDOS.find(c => c.id === esperado.id);
  if (!cmd) continue; // comando não encontrado, pular
  const r = rodarGate(path.join(__dirname, `${esperado.gate}.cjs`), cmd.comando, esperado.contexto);
  if (r.status !== 2) {
    apodrecidos++;
  }
}

// Caso especial: c-ancora-add não deve ser barrado
let cmd_ancora = COMANDOS.find(c => c.id === "c-ancora-add");
if (cmd_ancora) {
  const r_principal = rodarGate(path.join(__dirname, "gate-staging-total.cjs"), cmd_ancora.comando, "principal");
  const r_subagente = rodarGate(path.join(__dirname, "gate-staging-total.cjs"), cmd_ancora.comando, "subagente");
  caso(
    "c-ancora-add nao e barrado por gate-staging-total em nenhum contexto",
    r_principal.status !== 2 && r_subagente.status !== 2,
    `principal: ${r_principal.status}, subagente: ${r_subagente.status}`
  );
} else {
  console.log("  FALHA c-ancora-add não encontrado no corpus");
  falhou++;
}

// Varredor de segredo
const r_varredura = spawnSync(process.execPath, ["scripts/conferir-publicacao.cjs", path.join(RAIZ_FIXTURES, "legitimos.jsonl")], {
  encoding: "utf8",
  cwd: path.dirname(__dirname),
});
caso("fixture passa no varredor de segredo (conferir-publicacao exit 0)", r_varredura.status === 0, `exit ${r_varredura.status}`);

// Verificar apodrecimento de esperados
caso("esperados.json sem entrada apodrecida", apodrecidos === 0, `${apodrecidos} apodrecido(s)`);

// Função para processar corpus local
function processarCorpusLocal(arquivo_path) {
  const achados_locais = [];
  try {
    const local_cmds = fs.readFileSync(arquivo_path, "utf8").split("\n").filter(Boolean).map(l => JSON.parse(l));
    console.log(`  ok   RFM_CORPUS_LOCAL com ${local_cmds.length} comando(s):`);
    for (const cmd of local_cmds) {
      for (const gate of GATES) {
        for (const contexto of ["principal", "subagente"]) {
          const r = rodarGate(path.join(__dirname, `${gate}.cjs`), cmd.comando, contexto);
          if (r.status === 2) {
            const novo_achado = { id: cmd.id, gate: gate, contexto: contexto, motivo: r.stderr.split("\n")[0], issue: null };
            achados_locais.push(novo_achado);
            console.log(`    bloqueio: ${cmd.id} por ${gate} (${contexto})`);
          }
        }
      }
    }
  } catch (e) {
    console.log(`  FALHA RFM_CORPUS_LOCAL: ${e.message}`);
    falhou++;
  }
  return achados_locais;
}

// RFM_CORPUS_LOCAL
if (process.env.RFM_CORPUS_LOCAL) {
  processarCorpusLocal(process.env.RFM_CORPUS_LOCAL);
}

// Critério (4): RFM_CORPUS_LOCAL com git add -A lista o bloqueio como achado
{
  const temp_corpus_path = path.join(caixa, "temp-corpus.jsonl");
  fs.writeFileSync(temp_corpus_path, JSON.stringify({ id: "c-test-add-a", comando: "git add -A" }) + "\n");
  fs.writeFileSync(temp_corpus_path, JSON.stringify({ id: "c-test-status", comando: "git status" }) + "\n", { flag: "a" });
  fs.writeFileSync(temp_corpus_path, JSON.stringify({ id: "c-test-commit", comando: "git commit -m test" }) + "\n", { flag: "a" });

  const achados_criterion_4 = processarCorpusLocal(temp_corpus_path);
  const bloqueio_add_a = achados_criterion_4.find(a => a.id === "c-test-add-a" && a.gate === "gate-staging-total");
  caso(
    "RFM_CORPUS_LOCAL com git add -A lista o bloqueio como achado",
    bloqueio_add_a !== undefined,
    bloqueio_add_a ? "" : "bloqueio de git add -A não encontrado"
  );
}

const tempo_ms = Date.now() - inicio;
const tempo_s = (tempo_ms / 1000).toFixed(1);

console.log(`tempo: ${tempo_s} s`);
console.log(`ok: ${ok}   falhou: ${falhou}`);

process.exit(falhou > 0 ? 1 : 0);
