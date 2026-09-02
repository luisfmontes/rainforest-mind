#!/usr/bin/env node
"use strict";
/* Bateria do núcleo da Tarefa 3 do fluxo 9 (portaria).
 *
 * Testa decisões 1–7 de D3: manifesto ausente/inválido, agente não declarado,
 * estágio fora da lista, ausência de estágio ativo, normalização de prefixo,
 * e aprovação com gravação de log.
 *
 * Chama o hook como PROCESSO REAL via spawnSync, assere sobre exit code,
 * stderr e conteúdo de arquivo. Sandbox com git init + estado.
 *
 * Exit 0 = tudo passou; exit 1+ = alguma falha.
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

function rodaHook(raiz, stdin) {
  return spawnSync(process.execPath, [HOOK], {
    input: stdin,
    env: { ...process.env, CLAUDE_PROJECT_DIR: raiz },
    encoding: "utf8",
  });
}

function caixa() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-nucleo-"));
}

function criarEstadoAtivo(raiz, branchBase, estagio) {
  // Cria docs/rainforest/estado/<data>-<branchBase>.json com estágio aberto
  // O resolver() casa branch 'fluxo/teste' com arquivo cujo slug pós-data seja 'teste'
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  // Mapa de status fechado por estágio (copiado de estagio-ativo.cjs)
  const FECHADO = { design: "aprovado", plano: "ok" };

  const estado = {
    slug: `2026-09-01-${branchBase}`,
  };

  // Cria toda a cascata de estágios, fechando os que vêm antes do desejado
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (e === estagio) {
      // Estágio ativo = pendente
      estado[e] = { status: "pendente" };
    } else if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
      // Estágio antes do desejado = fechado
      estado[e] = { status: FECHADO[e] || "ok" };
    } else {
      // Estágio depois do desejado = pendente
      estado[e] = { status: "pendente" };
    }
  }

  const estadoPath = path.join(dirEstado, `2026-09-01-${branchBase}.json`);
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + "\n", "utf8");
}

function criarManifesto(raiz, manifesto) {
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  const path_ = path.join(dir, "agentes.json");
  fs.writeFileSync(path_, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
}

function iniciarGit(raiz, branch) {
  // Inicializa git com pelo menos um commit para que HEAD exista
  spawnSync("git", ["init"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-m", "initial"], { cwd: raiz });
  spawnSync("git", ["checkout", "-b", branch], { cwd: raiz });
}

// Envolver agentes em schema D2 (versao + agentes)
function manifestoD2(agentes) {
  return {
    versao: 1,
    agentes: agentes,
  };
}

// == 1. Agente não declarado → exit 2, nome no stderr ==
console.log("== 1. agente nao declarado ==");
{
  const raiz = caixa();

  // Setup: inicializa git e cria estado
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Manifesto sem o agente 'executar'
  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  const payload = {
    session_id: "teste-1",
    tool_input: { subagent_type: "executar" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita o agente", r.stderr.includes("executar"), `stderr: ${r.stderr}`);
  caso(
    "stderr menciona manifesto",
    r.stderr.includes("manifesto"),
    `stderr: ${r.stderr}`
  );

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. Agente declarado, estágio errado → exit 2, estágios no stderr ==
console.log("== 2. agente declarado, estagio errado ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "executar"); // Stage ativo = executar

  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar", "verificar"], escreve: false }, // Só revisar/verificar permitido
  }));

  const payload = {
    session_id: "teste-2",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita estágio atual", r.stderr.includes("executar"), `stderr: ${r.stderr}`);
  caso("stderr cita estágios permitidos", r.stderr.includes("revisar"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 3. Agente declarado, estágio certo → exit 0 + log ==
console.log("== 3. agente declarado, estagio certo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  const sessaoId = "teste-3-sessao-xyz";
  const payload = {
    session_id: sessaoId,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0", r.status === 0, `exit=${r.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  const logExists = fs.existsSync(logPath);
  caso("despachos.jsonl existe", logExists);

  if (logExists) {
    const linhas = fs
      .readFileSync(logPath, "utf8")
      .trim()
      .split("\n");

    const ultima = linhas[linhas.length - 1];
    let entrada = null;
    try {
      entrada = JSON.parse(ultima);
    } catch {}

    caso("linha é JSON válido", entrada !== null, ultima);
    if (entrada) {
      caso("decisao = 'allow'", entrada.decisao === "allow", entrada.decisao);
      caso("agente = 'revisor'", entrada.agente === "revisor", entrada.agente);
      caso("estagio = 'revisar'", entrada.estagio === "revisar", entrada.estagio);
      caso("sessao correto", entrada.sessao === sessaoId, entrada.sessao);
      caso("ts em ISO-8601", /^\d{4}-\d{2}-\d{2}T/.test(entrada.ts), entrada.ts);
      caso("sem motivo em 'allow'", !entrada.motivo);
    }
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 4. Manifesto ausente → exit 2 (fail-closed) ==
console.log("== 4. manifesto ausente ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Não cria manifesto

  const payload = {
    session_id: "teste-4",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr não vazio", r.stderr.length > 0, `"${r.stderr}"`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 5. Manifesto JSON inválido → exit 2 (fail-closed) ==
console.log("== 5. manifesto JSON invalido ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{isso nao e json", "utf8");

  const payload = {
    session_id: "teste-5",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr não vazio", r.stderr.length > 0, `"${r.stderr}"`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 6. Normalização de prefixo rainforest-mind: ==
console.log("== 6. normalizacao de prefixo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  const payload = {
    session_id: "teste-6",
    tool_input: { subagent_type: "rainforest-mind:revisor" }, // Com prefixo
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 (prefixo foi removido)", r.status === 0, `exit=${r.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  if (fs.existsSync(logPath)) {
    const linha = fs.readFileSync(logPath, "utf8").trim();
    let entrada = null;
    try {
      entrada = JSON.parse(linha);
    } catch {}
    caso("agente no log é 'revisor' (sem prefixo)", entrada && entrada.agente === "revisor", entrada && entrada.agente);
  } else {
    caso("agente no log é 'revisor' (sem prefixo)", false, "log não criado");
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 7. Sem estágio ativo → exit 2 ==
console.log("== 7. sem estagio ativo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/outro"); // Branch = fluxo/outro
  criarEstadoAtivo(raiz, "teste", "revisar"); // Estado para fluxo-teste (não casa)

  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  const payload = {
    session_id: "teste-7",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr contém 'estágio ativo'", r.stderr.includes("estágio ativo"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 8. Log append-only (não reescreve) ==
console.log("== 8. log append-only ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  const payload = {
    session_id: "teste-8",
    tool_input: { subagent_type: "revisor" },
  };

  // Primeira execução
  rodaHook(raiz, JSON.stringify(payload));

  // Segunda execução
  const r2 = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 na segunda execução", r2.status === 0, `exit=${r2.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  if (fs.existsSync(logPath)) {
    const linhas = fs
      .readFileSync(logPath, "utf8")
      .trim()
      .split("\n")
      .filter(l => l.trim());

    caso("log tem duas linhas", linhas.length === 2, `tem ${linhas.length}`);

    let ambas = true;
    for (const linha of linhas) {
      try {
        JSON.parse(linha);
      } catch {
        ambas = false;
        break;
      }
    }
    caso("ambas as linhas são JSON válidas", ambas);
  } else {
    caso("log tem duas linhas", false, "log não criado");
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 9. Manifesto sem versao → exit 2 ==
console.log("== 9. manifesto sem versao ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Manifesto sem versao
  criarManifesto(raiz, {
    agentes: {
      revisor: { estagios: ["revisar"], escreve: false },
    },
  });

  const payload = {
    session_id: "teste-9",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona versao", r.stderr.includes("versao"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 10. Manifesto com versao desconhecida (99) → exit 2 ==
console.log("== 10. manifesto com versao desconhecida ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Manifesto com versao 99
  criarManifesto(raiz, {
    versao: 99,
    agentes: {
      revisor: { estagios: ["revisar"], escreve: false },
    },
  });

  const payload = {
    session_id: "teste-10",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona versao 99", r.stderr.includes("99"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 11. raiz vem do payload.cwd, não do process.cwd() ==
console.log("== 11. raiz vem do payload.cwd (CRÍTICO 1) ==");
{
  // Cria dois sandboxes:
  //   A: com manifesto e estágio que aprovam
  //   B: outro repo git, sem manifesto
  const raizA = caixa();
  const raizB = caixa();

  iniciarGit(raizA, "fluxo/teste");
  criarEstadoAtivo(raizA, "teste", "revisar");
  criarManifesto(raizA, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  iniciarGit(raizB, "outro");

  const payload = {
    session_id: "teste-11",
    tool_input: { subagent_type: "revisor" },
    cwd: raizA, // A é no payload
  };

  // Roda o hook com:
  //   - process.cwd() em B (seria negado se processo.cwd() fosse usado)
  //   - CLAUDE_PROJECT_DIR apontando para B (seria negado se env fosse usado)
  //   - payload.cwd apontando para A (aprovado, prova que payload vence)
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    cwd: raizB, // Simula que o processo atual está em outro lugar
    env: { ...process.env, CLAUDE_PROJECT_DIR: raizB },
    encoding: "utf8",
  });

  caso("exit 0 (payload.cwd venceu)", r.status === 0, `exit=${r.status}`);

  const logPathA = path.join(raizA, ".rainforest", "portaria", "despachos.jsonl");
  caso("log gravado em A (payload.cwd)", fs.existsSync(logPathA));

  const logPathB = path.join(raizB, ".rainforest", "portaria", "despachos.jsonl");
  caso("log NÃO gravado em B", !fs.existsSync(logPathB));

  fs.rmSync(raizA, { recursive: true, force: true });
  fs.rmSync(raizB, { recursive: true, force: true });
}

// == 12. normalização de raiz para subdiretório ==
console.log("== 12. normalização de raiz para subdiretório ==");
{
  const raizA = caixa();

  iniciarGit(raizA, "fluxo/teste");
  criarEstadoAtivo(raizA, "teste", "revisar");
  criarManifesto(raizA, manifestoD2({
    revisor: { estagios: ["revisar"], escreve: false },
  }));

  // Cria um subdiretório
  const subdir = path.join(raizA, "hooks");
  fs.mkdirSync(subdir, { recursive: true });

  const payload = {
    session_id: "teste-12",
    tool_input: { subagent_type: "revisor" },
    cwd: subdir, // Payload aponta para subdiretório, não raiz
  };

  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    env: { ...process.env, CLAUDE_PROJECT_DIR: "" }, // Sem env
    encoding: "utf8",
  });

  caso("exit 0 (mesmo com payload.cwd em subdir)", r.status === 0, `exit=${r.status}`);

  const logPath = path.join(raizA, ".rainforest", "portaria", "despachos.jsonl");
  caso("log gravado na raiz (normalizado)", fs.existsSync(logPath));

  fs.rmSync(raizA, { recursive: true, force: true });
}

/* == 13. allow que NAO pode conferir `escreve: false` sai marcado no log ==
 *
 * Critico 2 da rodada 4 da revisao. Quando o arquivo do agente nao existe, a
 * checagem de escrita e pulada (e tem de ser: em repositorio de CONSUMIDOR do
 * plugin nao ha `agents/` local) — mas o allow saia byte a byte igual ao de um
 * agente conferido, e o log, que e evidencia de primeira classe (D4), afirmava
 * mais do que sabia. Este caso exige que as duas linhas sejam DISTINGUIVEIS.
 */
console.log("== 13. allow sem poder conferir escreve:false sai marcado ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");
  criarManifesto(raiz, manifestoD2({
    semarquivo: { estagios: ["revisar"], escreve: false },
    comarquivo: { estagios: ["revisar"], escreve: false },
  }));
  // So `comarquivo` tem arquivo, e ele e read-only de verdade.
  const dirAgentes = path.join(raiz, "agents");
  fs.mkdirSync(dirAgentes, { recursive: true });
  fs.writeFileSync(path.join(dirAgentes, "comarquivo.md"), "---\nname: comarquivo\ntools: Read, Grep\n---\nc\n", "utf8");

  const r1 = rodaHook(raiz, JSON.stringify({ session_id: "t13", tool_input: { subagent_type: "semarquivo" } }));
  const r2 = rodaHook(raiz, JSON.stringify({ session_id: "t13", tool_input: { subagent_type: "comarquivo" } }));
  caso("os dois aprovam (pular a checagem nao vira deny)", r1.status === 0 && r2.status === 0,
    `semarquivo=${r1.status} comarquivo=${r2.status}`);

  const linhas = fs.readFileSync(path.join(raiz, ".rainforest", "portaria", "despachos.jsonl"), "utf8")
    .split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const semArq = linhas.find((l) => l.agente === "semarquivo");
  const comArq = linhas.find((l) => l.agente === "comarquivo");

  caso("o allow NAO conferido traz escreve_conferido:false",
    semArq && semArq.escreve_conferido === false, JSON.stringify(semArq));
  caso("o allow conferido NAO traz o campo",
    comArq && comArq.escreve_conferido === undefined, JSON.stringify(comArq));
  caso("as duas linhas sao distinguiveis",
    JSON.stringify(semArq && semArq.escreve_conferido) !== JSON.stringify(comArq && comArq.escreve_conferido));

  fs.rmSync(raiz, { recursive: true, force: true });
}

/* == 14. `escreve` tem de ser booleano — crítico da rodada 5 ==
 *
 * `escreve === false` é igualdade estrita, e até aqui QUALQUER outro valor caía
 * fora do `if`: a checagem de escrita desligava inteira e o allow saía SEM a
 * marca `escreve_conferido`, byte a byte igual ao de um agente conferido.
 * Reabria o "allow que mentia" da rodada 4 por outra porta — e sem nem a marca,
 * que era o que tornava aquela porta auditável. Os agentes destes casos
 * declaram `tools: Write, Edit, Bash`, ou seja, seriam negados na hora se o
 * `escreve` fosse o booleano de verdade.
 */
console.log("== 14. escreve nao-booleano nega, em vez de desligar a checagem ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");
  criarManifesto(raiz, manifestoD2({
    strfalse: { estagios: ["revisar"], escreve: "false" },
    semescreve: { estagios: ["revisar"] },
    escrevetrue: { estagios: ["revisar"], escreve: true },
    boolfalse: { estagios: ["revisar"], escreve: false },
  }));
  const dirAgentes = path.join(raiz, "agents");
  fs.mkdirSync(dirAgentes, { recursive: true });
  for (const n of ["strfalse", "semescreve", "escrevetrue"]) {
    fs.writeFileSync(path.join(dirAgentes, `${n}.md`), `---\nname: ${n}\ntools: Write, Edit, Bash\n---\nc\n`, "utf8");
  }
  fs.writeFileSync(path.join(dirAgentes, "boolfalse.md"), "---\nname: boolfalse\ntools: Read, Grep\n---\nc\n", "utf8");

  const r1 = rodaHook(raiz, JSON.stringify({ session_id: "t14", tool_input: { subagent_type: "strfalse" } }));
  caso("escreve:'false' (string) nega", r1.status === 2, `exit=${r1.status} stderr=${r1.stderr}`);
  caso("e o motivo diz que nao e booleano", r1.stderr.includes("nao-booleano"), r1.stderr);

  const r2 = rodaHook(raiz, JSON.stringify({ session_id: "t14", tool_input: { subagent_type: "semescreve" } }));
  caso("escreve ausente nega", r2.status === 2, `exit=${r2.status} stderr=${r2.stderr}`);

  // `escreve: true` e valido desde 2026-09-02, mas SEM `isolation` no despacho
  // continua negando — o caso 17 cobre a trava inteira. O que este caso guarda
  // e que o booleano `true` nao cai mais no ramo do "nao-booleano".
  const r3 = rodaHook(raiz, JSON.stringify({ session_id: "t14", tool_input: { subagent_type: "escrevetrue" } }));
  caso("escreve:true sem isolation nega", r3.status === 2, `exit=${r3.status} stderr=${r3.stderr}`);
  caso("e nega por ISOLAMENTO, nao por 'nao-booleano'",
    r3.stderr.includes("isolation") && !r3.stderr.includes("nao-booleano"), r3.stderr);

  // O booleano de verdade continua funcionando — o conserto nao virou deny-por-tudo.
  const r4 = rodaHook(raiz, JSON.stringify({ session_id: "t14", tool_input: { subagent_type: "boolfalse" } }));
  caso("escreve:false booleano com tools read-only aprova", r4.status === 0, `exit=${r4.status} stderr=${r4.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

/* == 15. falha interna NEGA (exit 2), não crasha (exit 1) ==
 *
 * Crítico da rodada 6. Exit 2 num `PreToolUse` barra; exit 1 é erro
 * NÃO-BLOQUEANTE e o despacho passa. Uma exceção não tratada produz exit 1 —
 * então crashar não é fail-closed, é fail-OPEN, e sem sequer uma linha no log.
 *
 * O teste monta uma cópia da árvore do hook e QUEBRA a dependência interna
 * (`scripts/estado.cjs` fora do lugar), que é o modo de falha real: arquivo
 * ausente, erro de sintaxe introduzido em edição futura, I/O. Nada do repositório
 * é tocado — a cópia mora em pasta temporária.
 */
console.log("== 15. falha interna nega (exit 2) em vez de crashar (exit 1) ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");
  criarManifesto(raiz, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));

  // Cópia da árvore do plugin, para quebrar sem tocar no repositório.
  const arvore = fs.mkdtempSync(path.join(os.tmpdir(), "portaria-quebrada-"));
  fs.mkdirSync(path.join(arvore, "hooks", "lib"), { recursive: true });
  fs.mkdirSync(path.join(arvore, "scripts"), { recursive: true });
  const daqui = (rel) => path.join(__dirname, "..", rel);
  fs.copyFileSync(daqui("hooks/portaria.cjs"), path.join(arvore, "hooks", "portaria.cjs"));
  fs.copyFileSync(daqui("hooks/lib/estagio-ativo.cjs"), path.join(arvore, "hooks", "lib", "estagio-ativo.cjs"));
  fs.copyFileSync(daqui("scripts/estado.cjs"), path.join(arvore, "scripts", "estado.cjs"));

  const hookCopia = path.join(arvore, "hooks", "portaria.cjs");
  const payload = JSON.stringify({ session_id: "t15", cwd: raiz, tool_input: { subagent_type: "revisor" } });
  const roda = () => spawnSync(process.execPath, [hookCopia], { input: payload, encoding: "utf8" });

  // Controle: a cópia intacta decide normalmente.
  const inteiro = roda();
  caso("copia intacta decide (exit 0 ou 2, nunca 1)", inteiro.status === 0 || inteiro.status === 2,
    `exit=${inteiro.status} stderr=${inteiro.stderr}`);

  // Agora quebra a dependência interna.
  fs.rmSync(path.join(arvore, "scripts", "estado.cjs"));
  const quebrado = roda();
  caso("com a dependencia quebrada, exit 2 (nega) e nao 1 (passaria)",
    quebrado.status === 2, `exit=${quebrado.status} stderr=${quebrado.stderr}`);
  caso("e o stderr diz que negou por falha interna",
    /falha interna/i.test(quebrado.stderr || ""), quebrado.stderr);

  fs.rmSync(arvore, { recursive: true, force: true });
  fs.rmSync(raiz, { recursive: true, force: true });
}

/* == 16. nenhum `require` de arquivo do PROJETO no topo do módulo ==
 *
 * Apontado pela auditoria externa (codex-cli, 2026-09-01). A rede que transforma
 * exceção em `exit 2` envolve a chamada de `main()`. `require` de módulo do
 * projeto executado no TOPO do arquivo roda ANTES dessa rede — se ele lançar, o
 * processo morre com exit 1, e exit 1 num `PreToolUse` deixa o despacho passar.
 * Ou seja, mover um `require` para o topo, mesmo de boa fé, reabre exatamente o
 * crítico da rodada 6, e nenhum outro teste veria.
 *
 * Hoje os dois `require` de projeto estão dentro de `main()` e de
 * `executarLint()`, portanto cobertos. Esta asserção é a trava que mantém assim
 * — é sobre a FORMA do arquivo, não sobre comportamento, e é de propósito: o
 * comportamento que ela protege só se manifesta num modo de falha raro.
 *
 * Builtins do Node (`fs`, `path`, `child_process`) podem ficar no topo: eles não
 * lançam por causa do estado do projeto.
 */
console.log("== 16. sem require de projeto no topo do modulo (rede so cobre main) ==");
{
  const fonte = fs.readFileSync(path.join(__dirname, "portaria.cjs"), "utf8");
  const linhas = fonte.split("\n");
  const BUILTINS = new Set(["fs", "path", "child_process", "os", "util", "crypto"]);
  const forasDaRede = [];
  let profundidade = 0;

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];
    const m = linha.match(/require\(\s*["']([^"']+)["']\s*\)/);
    // Profundidade de chave ANTES desta linha: 0 = topo do módulo.
    if (m && profundidade === 0) {
      const alvo = m[1];
      if (!BUILTINS.has(alvo)) forasDaRede.push(`${i + 1}: ${linha.trim()}`);
    }
    // Conta chaves ignorando as que estão dentro de string ou comentário de linha.
    const semComentario = linha.replace(/\/\/.*$/, "").replace(/(["'`]).*?\1/g, "");
    for (const ch of semComentario) {
      if (ch === "{") profundidade++;
      else if (ch === "}") profundidade--;
    }
  }

  caso("nenhum require de projeto fora de funcao",
    forasDaRede.length === 0,
    `escapariam da rede: ${forasDaRede.join(" | ")}`);
}

/* == 17. `escreve: true`: a trava e isolation + ausencia de name ==
 *
 * Ate 2026-09-02 este ramo era um deny duro, e o custo apareceu longe daqui:
 * com os quatro agentes escritores fora do manifesto, NENHUM agente cobria o
 * estagio `executar`, e a regra 10 ficou desligada sem que nada dissesse isso.
 * Duas sessoes distintas bateram na parede antes de alguem somar as pontas.
 *
 * As duas condicoes nao sao invencao da portaria: sao as regras 11 (worktree
 * sempre) e 10 (agente que edita nunca e nomeado) escritas em codigo. E o que
 * a portaria confere e o PEDIDO, nao o worktree em disco — ela roda ANTES do
 * despacho, quando o worktree ainda nao existe. Conferir o worktree real na
 * volta e da integracao (scripts/conferir-entrega.cjs), e continua sendo.
 */
console.log("== 17. escreve:true exige isolation worktree e recusa name ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "executar");
  criarManifesto(raiz, manifestoD2({
    escritor: { estagios: ["executar"], escreve: true },
  }));
  const dirAgentes = path.join(raiz, "agents");
  fs.mkdirSync(dirAgentes, { recursive: true });
  fs.writeFileSync(path.join(dirAgentes, "escritor.md"),
    "---\nname: escritor\ntools: Write, Edit, Bash\n---\nc\n", "utf8");

  const despacha = (entrada) => rodaHook(raiz, JSON.stringify({
    session_id: "t17",
    tool_input: { subagent_type: "escritor", ...entrada },
  }));

  const semIso = despacha({});
  caso("sem isolation nega", semIso.status === 2, `exit=${semIso.status} stderr=${semIso.stderr}`);
  caso("e o motivo nomeia isolation", semIso.stderr.includes('isolation: "worktree"'), semIso.stderr);

  const isoErrado = despacha({ isolation: "remote" });
  caso("isolation diferente de worktree nega", isoErrado.status === 2,
    `exit=${isoErrado.status} stderr=${isoErrado.stderr}`);

  const comNome = despacha({ isolation: "worktree", name: "sonda-um" });
  caso("worktree MAS nomeado nega", comNome.status === 2,
    `exit=${comNome.status} stderr=${comNome.stderr}`);
  caso("e o motivo nomeia o name recebido", comNome.stderr.includes("sonda-um"), comNome.stderr);

  const nomeVazio = despacha({ isolation: "worktree", name: "   " });
  caso("name so com espaco nao conta como nome", nomeVazio.status === 0,
    `exit=${nomeVazio.status} stderr=${nomeVazio.stderr}`);

  const bom = despacha({ isolation: "worktree" });
  caso("worktree e sem nome APROVA", bom.status === 0, `exit=${bom.status} stderr=${bom.stderr}`);

  // O log tem de dizer SOB QUE isolamento a escrita foi admitida: allow de
  // agente que escreve sem esse campo nao responde a pergunta pela qual o log
  // e evidencia de primeira classe.
  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  const linhas = fs.readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  const ultima = linhas[linhas.length - 1];
  caso("a ultima linha e o allow", ultima.decisao === "allow", JSON.stringify(ultima));
  caso("e registra isolation: worktree", ultima.isolation === "worktree", JSON.stringify(ultima));
  caso("e NAO traz escreve_conferido (allow conferido)",
    ultima.escreve_conferido === undefined, JSON.stringify(ultima));
  caso("as tres negacoes ficaram no log",
    linhas.filter((l) => l.decisao === "deny").length === 3,
    JSON.stringify(linhas.map((l) => l.decisao)));

  // A ORDEM das decisoes nao mudou: estagio fora da lista nega ANTES de chegar
  // na checagem de escrita, mesmo com o despacho perfeito.
  const raiz2 = caixa();
  iniciarGit(raiz2, "fluxo/teste");
  criarEstadoAtivo(raiz2, "teste", "revisar");
  criarManifesto(raiz2, manifestoD2({ escritor: { estagios: ["executar"], escreve: true } }));
  const foraDoEstagio = rodaHook(raiz2, JSON.stringify({
    session_id: "t17b",
    tool_input: { subagent_type: "escritor", isolation: "worktree" },
  }));
  caso("estagio fora da lista nega mesmo com worktree", foraDoEstagio.status === 2,
    `exit=${foraDoEstagio.status} stderr=${foraDoEstagio.stderr}`);
  caso("e nega pelo ESTAGIO, nao pelo isolamento",
    foraDoEstagio.stderr.includes("permitido"), foraDoEstagio.stderr);

  fs.rmSync(raiz, { recursive: true, force: true });
  fs.rmSync(raiz2, { recursive: true, force: true });
}

/* == 18. negacao anterior ao passo 4 registra o estagio REAL ==
 *
 * O log e evidencia de primeira classe (D4), e ate 2026-09-02 toda negacao
 * anterior a resolucao do estagio gravava `estagio: "?"`. Medido no dia do
 * conserto: cinco negacoes de `executor`, em duas sessoes distintas, todas com
 * `?` — nenhuma respondia "em qual estagio", que e um terco da pergunta que
 * o log existe para responder.
 *
 * A ORDEM das decisoes continua a mesma: agente ausente do manifesto nega
 * antes de tudo. O que mudou e so o que se grava.
 */
console.log("== 18. deny por agente ausente registra o estagio ativo, nao '?' ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "executar");
  criarManifesto(raiz, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));

  const r = rodaHook(raiz, JSON.stringify({
    session_id: "t18",
    tool_input: { subagent_type: "naodeclarado" },
  }));
  caso("agente ausente do manifesto continua negando", r.status === 2,
    `exit=${r.status} stderr=${r.stderr}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  const linha = JSON.parse(fs.readFileSync(logPath, "utf8").trim().split("\n").pop());
  caso("e a linha grava o estagio ativo", linha.estagio === "executar", JSON.stringify(linha));
  caso("e o motivo continua sendo o do manifesto",
    (linha.motivo || "").includes("manifesto"), JSON.stringify(linha));

  // Sem fluxo aberto nenhum, '?' volta a ser a verdade — e nao uma lacuna.
  const raiz2 = caixa();
  iniciarGit(raiz2, "fluxo/teste");
  criarManifesto(raiz2, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));
  const r2 = rodaHook(raiz2, JSON.stringify({
    session_id: "t18b",
    tool_input: { subagent_type: "naodeclarado" },
  }));
  caso("sem fluxo aberto tambem nega", r2.status === 2, `exit=${r2.status}`);
  const linha2 = JSON.parse(fs.readFileSync(
    path.join(raiz2, ".rainforest", "portaria", "despachos.jsonl"), "utf8").trim().split("\n").pop());
  caso("e o estagio volta a ser '?' (nao ha estagio)", linha2.estagio === "?", JSON.stringify(linha2));

  fs.rmSync(raiz, { recursive: true, force: true });
  fs.rmSync(raiz2, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
