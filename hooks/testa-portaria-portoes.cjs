#!/usr/bin/env node
"use strict";
/* Bateria dos PORTÕES do fluxo 9 (portaria) — Tarefa 6.
 *
 * Não repete a cobertura exaustiva de testa-portaria-nucleo.cjs / -lint.cjs /
 * -captura.cjs / -gitignore.cjs. Esta bateria é o critério de "pronto" do
 * design inteiro: cinco portões, cada um com sandbox próprio, chamando
 * hooks/portaria.cjs como PROCESSO REAL via spawnSync. Tudo offline.
 *
 * P1 — `--lint` sai 0 num repo com manifesto de exemplo.
 * P2 — agente não declarado recebe deny com motivo não vazio.
 * P3 — agente declarado em estágio errado recebe deny citando o estágio
 *      atual e os permitidos.
 * P4 — agente declarado + estágio certo recebe allow, e despachos.jsonl
 *      ganha exatamente uma linha com os campos obrigatórios. Prova adicional
 *      exigida pelo design: append-only comprovado por BYTE COUNT MONOTÔNICO
 *      entre duas execuções consecutivas, com a 1ª linha idêntica byte a byte
 *      depois da 2ª gravação — contagem de linhas sozinha não pega um rewrite
 *      que por acaso produza o mesmo número de linhas.
 * P5 — fail-closed em TEMPO DE EXECUÇÃO: o MESMO sandbox que aprovou o
 *      despacho (P4) passa a negá-lo depois que .rainforest/agentes.json é
 *      removido. Sandbox que nunca aprovou nada não prova fail-closed —
 *      prova só que sandbox vazio nega.
 *
 * Cada portão imprime seu rótulo ESPERA quando fecha (`P1 lint:ok`, ...).
 * Exit 0 só se os cinco fecharem; exit ≠ 0 na primeira falha, com o que
 * esperava e o que veio.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const FIXTURES = path.join(__dirname, "..", "test", "fixtures", "portaria");

function falhar(portao, esperado, veio) {
  console.error(`FALHA ${portao}`);
  console.error(`  esperava: ${esperado}`);
  console.error(`  veio:     ${veio}`);
  process.exit(1);
}

function fechar(portao, rotulo) {
  console.log(`${portao} ${rotulo}`);
}

function rodaHook(raiz, stdin) {
  return spawnSync(process.execPath, [HOOK], {
    input: stdin,
    env: { ...process.env, CLAUDE_PROJECT_DIR: raiz },
    encoding: "utf8",
  });
}

function rodaLint(manifestoPath, agentesDir) {
  return spawnSync(process.execPath, [HOOK, "--lint", "--manifesto", manifestoPath, "--agentes-dir", agentesDir], {
    encoding: "utf8",
  });
}

function caixa(prefixo) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `portaria-portoes-${prefixo}-`));
}

function iniciarGit(raiz, branch) {
  spawnSync("git", ["init"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-m", "initial"], { cwd: raiz });
  spawnSync("git", ["checkout", "-b", branch], { cwd: raiz });
}

// Cria docs/rainforest/estado/<data>-<branchBase>.json com o `estagio` pedido
// aberto (pendente) e tudo antes dele fechado — mesmo padrão usado em
// testa-portaria-nucleo.cjs e testa-portaria-captura.cjs, para o resolver de
// estagio-ativo.cjs achar exatamente um candidato.
function criarEstadoAtivo(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = { slug: `2026-09-01-${branchBase}` };
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
      estado[e] = { status: FECHADO[e] || "ok" };
    } else {
      estado[e] = { status: "pendente" };
    }
  }

  const estadoPath = path.join(dirEstado, `2026-09-01-${branchBase}.json`);
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + "\n", "utf8");
}

function criarManifesto(raiz, manifesto) {
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  const manifestoPath = path.join(dir, "agentes.json");
  fs.writeFileSync(manifestoPath, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
  return manifestoPath;
}

function logPath(raiz) {
  return path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
}

// ============================================================ P1 — lint:ok
{
  const raiz = caixa("p1");
  const agentesDir = path.join(raiz, "agentes");
  fs.mkdirSync(agentesDir, { recursive: true });
  fs.writeFileSync(
    path.join(agentesDir, "leitor.md"),
    "---\nname: Leitor\ntools: Read, Grep, Glob\n---\n\nAgente de leitura para teste do portao P1.\n",
    "utf8"
  );
  const manifestoPath = path.join(raiz, "agentes.json");
  fs.writeFileSync(
    manifestoPath,
    JSON.stringify({ versao: 1, agentes: { leitor: { estagios: ["executar", "revisar"], escreve: false } } }, null, 2) + "\n",
    "utf8"
  );

  const r = rodaLint(manifestoPath, agentesDir);
  if (r.status !== 0) {
    falhar("P1", "exit 0", `exit=${r.status} stdout=${JSON.stringify(r.stdout)} stderr=${JSON.stringify(r.stderr)}`);
  }
  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P1", "lint:ok");
}

// ================================================ P2 — deny:nao-declarado
{
  const raiz = caixa("p2");
  iniciarGit(raiz, "fluxo/p2-nao-declarado");
  criarEstadoAtivo(raiz, "p2-nao-declarado", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: { leitor: { estagios: ["revisar"], escreve: false } },
  });

  const payload = { session_id: "p2-sessao", tool_input: { subagent_type: "fantasma" } };
  const r = rodaHook(raiz, JSON.stringify(payload));

  if (r.status !== 2) {
    falhar("P2", "exit 2 (deny)", `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  }
  const motivo = (r.stderr || "").trim();
  if (!motivo) {
    falhar("P2", "motivo não vazio no stderr", "stderr veio vazio");
  }
  if (!motivo.includes("fantasma") || !motivo.toLowerCase().includes("manifesto")) {
    falhar("P2", "motivo citando o agente e o manifesto", motivo);
  }
  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P2", "deny:nao-declarado");
}

// ====================================================== P3 — deny:estagio
{
  const raiz = caixa("p3");
  iniciarGit(raiz, "fluxo/p3-estagio-errado");
  // Estágio ATIVO é "revisar", mas o agente só está autorizado em "executar".
  criarEstadoAtivo(raiz, "p3-estagio-errado", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: { revisor: { estagios: ["executar"], escreve: false } },
  });

  const payload = { session_id: "p3-sessao", tool_input: { subagent_type: "revisor" } };
  const r = rodaHook(raiz, JSON.stringify(payload));

  if (r.status !== 2) {
    falhar("P3", "exit 2 (deny)", `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  }
  const motivo = (r.stderr || "").trim();
  if (!motivo.includes("revisar")) {
    falhar("P3", "motivo citando o estágio ATIVO ('revisar')", motivo);
  }
  if (!motivo.includes("executar")) {
    falhar("P3", "motivo citando os estágios PERMITIDOS ('executar')", motivo);
  }
  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P3", "deny:estagio");
}

// ======================================================== P4 — allow:logado
{
  const raiz = caixa("p4");
  iniciarGit(raiz, "fluxo/p4-allow-logado");
  criarEstadoAtivo(raiz, "p4-allow-logado", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: { revisor: { estagios: ["revisar"], escreve: false } },
  });

  const payload = { session_id: "p4-sessao", tool_input: { subagent_type: "revisor" } };
  const log = logPath(raiz);

  // --- 1ª execução ---
  const r1 = rodaHook(raiz, JSON.stringify(payload));
  if (r1.status !== 0) {
    falhar("P4", "exit 0 (allow) na 1ª execução", `exit=${r1.status} stderr=${JSON.stringify(r1.stderr)}`);
  }
  if (!fs.existsSync(log)) {
    falhar("P4", "despachos.jsonl existe após a 1ª execução", "arquivo não existe");
  }

  const buf1 = fs.readFileSync(log); // Buffer — comparação byte a byte, não string
  const texto1 = buf1.toString("utf8");
  const linhas1 = texto1.split("\n").filter(Boolean);
  if (linhas1.length !== 1) {
    falhar("P4", "exatamente 1 linha após a 1ª execução", `${linhas1.length} linha(s): ${JSON.stringify(texto1)}`);
  }
  let entrada1;
  try {
    entrada1 = JSON.parse(linhas1[0]);
  } catch (e) {
    falhar("P4", "linha 1 é JSON válido", `${e.message} — linha: ${linhas1[0]}`);
  }
  const camposObrigatorios = ["ts", "agente", "estagio", "decisao", "sessao"];
  for (const campo of camposObrigatorios) {
    if (!(campo in entrada1)) {
      falhar("P4", `campo '${campo}' presente na linha logada`, JSON.stringify(entrada1));
    }
  }
  if (entrada1.decisao !== "allow") {
    falhar("P4", "decisao = 'allow' na 1ª execução", entrada1.decisao);
  }

  const size1 = fs.statSync(log).size;
  if (size1 !== buf1.length) {
    falhar("P4", "statSync.size bate com o tamanho do buffer lido", `stat=${size1} buffer=${buf1.length}`);
  }

  // --- 2ª execução, mesmo sandbox, sem tocar no arquivo entre as duas ---
  const r2 = rodaHook(raiz, JSON.stringify(payload));
  if (r2.status !== 0) {
    falhar("P4", "exit 0 (allow) na 2ª execução", `exit=${r2.status} stderr=${JSON.stringify(r2.stderr)}`);
  }

  const buf2 = fs.readFileSync(log);
  const texto2 = buf2.toString("utf8");
  const linhas2 = texto2.split("\n").filter(Boolean);
  if (linhas2.length !== 2) {
    falhar("P4", "exatamente 2 linhas após a 2ª execução (append-only)", `${linhas2.length} linha(s): ${JSON.stringify(texto2)}`);
  }
  for (let i = 0; i < linhas2.length; i++) {
    try {
      JSON.parse(linhas2[i]);
    } catch (e) {
      falhar("P4", `linha ${i + 1} (pós-2ª execução) é JSON válido`, `${e.message} — linha: ${linhas2[i]}`);
    }
  }

  const size2 = fs.statSync(log).size;
  // Byte count monotônico: nunca pode DECRESCER entre as duas medições.
  if (size2 < size1) {
    falhar("P4", `tamanho do arquivo não decresce (size1=${size1})`, `size2=${size2} (decresceu)`);
  }
  // A prova forte: a 1ª linha continua BYTE A BYTE idêntica — um rewrite
  // (fs.writeFileSync sobrescrevendo com só a linha nova) mudaria o prefixo
  // mesmo que, por coincidência, o número de linhas desse errado por outro
  // motivo. Comparação feita sobre o Buffer bruto, não sobre string decodada.
  const prefixo2 = buf2.subarray(0, buf1.length);
  if (!prefixo2.equals(buf1)) {
    falhar(
      "P4",
      "prefixo do arquivo pós-2ª execução é byte a byte igual ao conteúdo inteiro pós-1ª execução",
      `prefixo pós-2ª (${prefixo2.length} bytes) difere do conteúdo pós-1ª (${buf1.length} bytes) — não foi um append`
    );
  }

  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P4", "allow:logado");
}

// =================================================== P5 — deny:fail-closed
{
  const raiz = caixa("p5");
  iniciarGit(raiz, "fluxo/p5-fail-closed");
  criarEstadoAtivo(raiz, "p5-fail-closed", "revisar");
  const manifestoPath = criarManifesto(raiz, {
    versao: 1,
    agentes: { revisor: { estagios: ["revisar"], escreve: false } },
  });

  const payload = { session_id: "p5-sessao", tool_input: { subagent_type: "revisor" } };

  // --- confirma que o MESMO sandbox aprova antes de remover o manifesto ---
  const r1 = rodaHook(raiz, JSON.stringify(payload));
  if (r1.status !== 0) {
    falhar("P5", "exit 0 (allow) ANTES de remover o manifesto — pré-condição do fail-closed", `exit=${r1.status} stderr=${JSON.stringify(r1.stderr)}`);
  }

  // --- remove o manifesto em tempo de execução, mesmo sandbox, mesmo payload ---
  fs.rmSync(manifestoPath, { force: true });
  if (fs.existsSync(manifestoPath)) {
    falhar("P5", "manifesto removido do disco", "arquivo ainda existe após rmSync");
  }

  const r2 = rodaHook(raiz, JSON.stringify(payload));
  if (r2.status !== 2) {
    falhar("P5", "exit 2 (deny) DEPOIS de remover o manifesto", `exit=${r2.status} stderr=${JSON.stringify(r2.stderr)}`);
  }
  const motivo = (r2.stderr || "").trim();
  if (!motivo) {
    falhar("P5", "motivo não vazio no stderr da negação pós-remoção", "stderr veio vazio");
  }

  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P5", "deny:fail-closed");
}

console.log("P1..P5: OK");
process.exit(0);
