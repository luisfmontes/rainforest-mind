#!/usr/bin/env node
"use strict";
/* Bateria da catraca da Tarefa 2 do fluxo 9 (portaria, modo captura + nucleo).
 *
 * Testava: idempotencia da gravacao (D7 — primeira captura vence).
 * Agora testa TAMBÉM a captura dentro do nucleo de decisao (Tarefa 3).
 * Ajustada (Tarefa 3 justificativa): o hook transformou de "captura-only" para
 * "nucleo de decisao + captura mantida". Testes 1-2 agora configuram manifesto+estagio
 * para que a hook possa tomar decisao (success path). Testes 3-4 verificam que
 * payloads invalidos nao capturam e agora exitem 2 (fail-closed), nao 0.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha (com contagem no fim).
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

// `hook` opcional: os casos 1 e 2 rodam o ESPELHO do plugin, não o hook desta
// árvore (ver `espelharPlugin`). `RFM_ROOT` desde 2026-09-14 (D6): sem ele o log
// de despacho ia para a pasta pessoal do usuário.
function rodaHook(raiz, stdin, hook) {
  return spawnSync(process.execPath, [hook || HOOK], {
    input: stdin,
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: raiz,
      RFM_ROOT: path.join(raiz, ".rainforest"),
    },
    encoding: "utf8",
  });
}

function caixa() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-captura-"));
}

/* Copia o plugin para dentro do sandbox e devolve o caminho do hook copiado.
 *
 * Desde 2026-09-14 a amostra só é gravada quando o projeto aberto É o próprio
 * plugin — `path.resolve(__dirname, "..") === path.resolve(raiz)`. Num sandbox
 * comum essa igualdade nunca vale, e os casos 1 e 2 passaram a medir o novo
 * portão em vez da idempotência que eles existem para medir. Espelhando o
 * plugin, o sandbox *é* o plugin, e a pergunta volta a ser "a segunda execução
 * sobrescreve?".
 *
 * Mesma forma que `scripts/testa-memoria-somente-leitura.sh` já usa.
 */
function espelharPlugin(destino) {
  fs.cpSync(__dirname, path.join(destino, "hooks"), { recursive: true });
  // `hooks/lib/estagio-ativo.cjs` requer `../../scripts/estado.cjs`: sem o
  // `scripts/` no espelho o hook nega por "falha interna (main)" e o caso
  // mediria o require quebrado, não a captura.
  fs.cpSync(path.join(__dirname, "..", "scripts"), path.join(destino, "scripts"), { recursive: true });
  fs.mkdirSync(path.join(destino, ".rainforest"), { recursive: true });
  fs.copyFileSync(
    path.join(__dirname, "..", ".rainforest", "agentes.padrao.json"),
    path.join(destino, ".rainforest", "agentes.padrao.json")
  );
  return path.join(destino, "hooks", "portaria.cjs");
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

function criarEstado(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = { slug: `2026-09-01-${branchBase}` };
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (e === estagio) {
      estado[e] = { status: "pendente" };
    } else if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
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
}

// == 1. primeira execucao grava a amostra ==
console.log("== 1. primeira execucao grava a amostra ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      leitor: { estagios: ["revisar"], escreve: false },
    },
  });

  const hook = espelharPlugin(raiz);
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, JSON.stringify({ session_id: "s1", tool_input: { subagent_type: "leitor" } }), hook);
  caso("exit 0", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("amostra.json existe", fs.existsSync(amostra));
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra e JSON valido com session_id da 1a execucao",
    lido && lido.session_id === "s1", lido && lido.session_id ? `session_id=${lido.session_id}` : "ilegivel");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. segunda execucao NAO sobrescreve (primeira captura vence, D7) ==
console.log("== 2. segunda execucao NAO sobrescreve ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      leitor: { estagios: ["revisar"], escreve: false },
    },
  });

  const hook = espelharPlugin(raiz);
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  rodaHook(raiz, JSON.stringify({ session_id: "s1", tool_input: { subagent_type: "leitor" } }), hook);
  const r2 = rodaHook(raiz, JSON.stringify({ session_id: "s2", tool_input: { subagent_type: "leitor" } }), hook);
  caso("exit 0 na segunda execucao", r2.status === 0, `exit=${r2.status} stderr=${r2.stderr}`);
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra continua com session_id da PRIMEIRA execucao (s1)",
    lido && lido.session_id === "s1",
    lido && lido.session_id ? `veio ${lido.session_id}` : "amostra ilegivel");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 3. stdin vazio nao vira amostra (agora exit 0: libera) ==
console.log("== 3. stdin vazio nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "");
  caso("exit 0 (libera)", r.status === 0, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 4. payload ilegivel nao vira amostra (agora exit 0: libera) ==
console.log("== 4. payload ilegivel nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "{isso nao e json");
  caso("exit 0 (libera)", r.status === 0, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 5. subagent_type ausente continua negando (fail-closed) ==
console.log("== 5. subagent_type ausente continua negando ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      leitor: { estagios: ["revisar"], escreve: false },
    },
  });

  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  // Payload válido JSON mas SEM tool_input.subagent_type
  const r = rodaHook(raiz, JSON.stringify({ session_id: "s1", tool_input: {} }));
  caso("exit 2 (fail-closed)", r.status === 2, `exit=${r.status}`);
  caso("erro no stderr", r.stderr && r.stderr.includes("subagent_type"), `stderr: "${r.stderr}"`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

/* == 6. Repo que NÃO é o plugin não ganha amostra ==
 *
 * O inverso dos casos 1 e 2, e a mudança de 2026-09-14 propriamente dita. Sem
 * este caso, espelhar o plugin nos dois primeiros teria só devolvido o verde
 * antigo: a amostra voltaria a ser provada onde sempre foi, e o comportamento
 * novo — não sujar repositório alheio — não seria medido em lugar nenhum.
 *
 * Despacho idêntico ao do caso 1, com a única diferença que importa: o projeto
 * aberto é um repo comum.
 */
console.log("== 6. repo que NAO e o plugin nao ganha amostra ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: { leitor: { estagios: ["revisar"], escreve: false } },
  });

  const r = rodaHook(raiz, JSON.stringify({ session_id: "s6", tool_input: { subagent_type: "leitor" } }));
  caso("exit 0 (o despacho e admitido, como no caso 1)", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("amostra.json NAO existe",
    !fs.existsSync(path.join(raiz, ".rainforest", "portaria", "amostra.json")));

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
