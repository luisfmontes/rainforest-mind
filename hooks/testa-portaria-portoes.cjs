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
 * P2 — agente não declarado recebe allow com `declarado: false` no log.
 * P3 — manifesto JSON inválido recebe deny com motivo citando JSON inválido.
 * P4 — agente declarado + estágio certo recebe allow, e despachos.jsonl
 *      ganha exatamente uma linha com os campos obrigatórios. Prova adicional
 *      exigida pelo design: append-only comprovado por BYTE COUNT MONOTÔNICO
 *      entre duas execuções consecutivas, com a 1ª linha idêntica byte a byte
 *      depois da 2ª gravação — contagem de linhas sozinha não pega um rewrite
 *      que por acaso produza o mesmo número de linhas.
 * P5 — mudança em tempo de execução: agente que era DECLARADO vira NÃO-DECLARADO
 *      quando o manifesto muda, passa com `declarado: false` na 2ª execução.
 *      Prova que o log captura mudanças e que não há cache entre execuções.
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

// `RFM_ROOT` desde 2026-09-14 (D6): o log resolve pela raiz de DADOS, e sem
// isolamento a raiz de dados é a pasta pessoal do usuário. Apontar para
// `<raiz>/.rainforest` deixa cada caso na sua própria caixa (todo `caixa()` é um
// mkdtemp novo) e mantém o P4 lendo o mesmo caminho de sempre — o portão P4 é
// sobre o CONTEÚDO da linha e o append-only, não sobre onde o arquivo mora.
// Quem prova o destino do log é `testa-portaria-log-fora-do-repo.cjs`.
function rodaHook(raiz, stdin) {
  return spawnSync(process.execPath, [HOOK], {
    input: stdin,
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: raiz,
      RFM_ROOT: path.join(raiz, ".rainforest"),
    },
    encoding: "utf8",
  });
}

function rodaLint(manifestoPath, agentesDir) {
  return spawnSync(process.execPath, [HOOK, "--lint", "--manifesto", manifestoPath, "--agentes-dir", agentesDir], {
    encoding: "utf8",
  });
}

// `realpathSync.native` pelo mesmo motivo de `testa-portaria-diagnostico.cjs`
// (comentário de 2026-09-04): a CI roda em Windows e o `os.tmpdir()` do runner
// vem em forma curta 8.3 (`RUNNER~1`), enquanto a portaria imprime o caminho
// que o Node RESOLVE, por extenso. O P5 confere que o stderr cita o manifesto
// DO REPO comparando com este caminho — sem expandir o 8.3 ele acusava caminho
// errado onde a portaria tinha lido o certo: verde aqui, vermelho só lá
// (2026-09-14). Só o `.native` expande nome curto.
function caixa(prefixo) {
  return fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), `portaria-portoes-${prefixo}-`)));
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

// ================================== P2 — allow:nao-declarado + marcas-de-registro
{
  const raiz = caixa("p2");
  iniciarGit(raiz, "fluxo/p2-nao-declarado");
  criarEstadoAtivo(raiz, "p2-nao-declarado", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: { leitor: { estagios: ["revisar"], escreve: false } },
  });

  // Agente não declarado agora PASSA e ganha marca no log
  const payload = { session_id: "p2-sessao", tool_input: { subagent_type: "fantasma" } };
  const r = rodaHook(raiz, JSON.stringify(payload));

  if (r.status !== 0) {
    falhar("P2", "exit 0 (allow)", `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  }

  // Confira a linha do log
  const log = logPath(raiz);
  if (!fs.existsSync(log)) {
    falhar("P2", "despachos.jsonl existe após allow de não-declarado", "arquivo não existe");
  }
  const texto = fs.readFileSync(log, "utf8").trim();
  const linhas = texto.split("\n").filter(Boolean);
  if (linhas.length !== 1) {
    falhar("P2", "exatamente 1 linha no log", `${linhas.length} linha(s)`);
  }
  let entrada;
  try {
    entrada = JSON.parse(linhas[0]);
  } catch (e) {
    falhar("P2", "linha é JSON válido", e.message);
  }
  if (entrada.decisao !== "allow") {
    falhar("P2", "decisao = 'allow'", entrada.decisao);
  }
  if (entrada.declarado !== false) {
    falhar("P2", "declarado = false no log", JSON.stringify(entrada.declarado));
  }

  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P2", "allow:nao-declarado");
}

// ================================ P3 — deny:manifesto-invalido
{
  const raiz = caixa("p3");
  iniciarGit(raiz, "fluxo/p3-manifesto-invalido");
  criarEstadoAtivo(raiz, "p3-manifesto-invalido", "revisar");

  // Cria manifesto JSON inválido (este continua negando)
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{isso nao e json", "utf8");

  const payload = { session_id: "p3-sessao", tool_input: { subagent_type: "revisor" } };
  const r = rodaHook(raiz, JSON.stringify(payload));

  if (r.status !== 2) {
    falhar("P3", "exit 2 (deny manifesto inválido)", `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  }
  const motivo = (r.stderr || "").trim();
  if (!motivo || !motivo.toLowerCase().includes("json")) {
    falhar("P3", "motivo citando JSON inválido", motivo);
  }
  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P3", "deny:manifesto-invalido");
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

// ============================ P5 — allow:nao-declarado-por-mudanca
{
  const raiz = caixa("p5");
  iniciarGit(raiz, "fluxo/p5-nao-declarado-por-mudanca");
  criarEstadoAtivo(raiz, "p5-nao-declarado-por-mudanca", "revisar");
  const manifestoPath = criarManifesto(raiz, {
    versao: 1,
    agentes: { revisor: { estagios: ["revisar"], escreve: false } },
  });

  const payload = { session_id: "p5-sessao", tool_input: { subagent_type: "revisor" } };

  // --- confirma que o MESMO sandbox aprova antes de remover do manifesto ---
  const r1 = rodaHook(raiz, JSON.stringify(payload));
  if (r1.status !== 0) {
    falhar("P5", "exit 0 (allow) ANTES de remover do manifesto — pré-condição", `exit=${r1.status} stderr=${JSON.stringify(r1.stderr)}`);
  }
  const log1 = logPath(raiz);
  const linhas1 = fs.readFileSync(log1, "utf8").trim().split("\n").filter(Boolean);
  let entrada1 = JSON.parse(linhas1[0]);
  if (entrada1.declarado !== false && entrada1.declarado !== undefined) {
    // Primeira execução com agente DECLARADO não deve ter o campo
    if (entrada1.declarado === false) {
      falhar("P5", "primeira execução tem agente DECLARADO (sem marca 'declarado: false')", JSON.stringify(entrada1));
    }
  }

  // --- muda o manifesto em tempo de execução, mesmo sandbox, mesmo payload ---
  // Agora o revisor não está mais no manifesto do repo, então vira não-declarado
  // e passa com `declarado: false`
  criarManifesto(raiz, {
    versao: 1,
    agentes: { executor: { estagios: ["executar"], escreve: false } },
  });

  const r2 = rodaHook(raiz, JSON.stringify(payload));
  if (r2.status !== 0) {
    falhar("P5", "exit 0 (allow) DEPOIS de tirar do manifesto do repo", `exit=${r2.status} stderr=${JSON.stringify(r2.stderr)}`);
  }

  // Segunda execução deve ter marcado como não-declarado
  const linhas2 = fs.readFileSync(log1, "utf8").trim().split("\n").filter(Boolean);
  if (linhas2.length !== 2) {
    falhar("P5", "log append-only: 2 linhas após 2ª execução", `${linhas2.length} linha(s)`);
  }
  let entrada2 = JSON.parse(linhas2[1]);
  if (entrada2.decisao !== "allow") {
    falhar("P5", "2ª execução decisao = 'allow'", entrada2.decisao);
  }
  if (entrada2.declarado !== false) {
    falhar("P5", "2ª execução tem declarado = false (agente saiu do manifesto)", JSON.stringify(entrada2.declarado));
  }

  fs.rmSync(raiz, { recursive: true, force: true });
  fechar("P5", "allow:nao-declarado-por-mudanca");
}

/* ============================================== P6 — registro:alcance
 *
 * Achado ao exercitar a mutação da tarefa 3, em 2026-09-14: trocar o matcher de
 * `Task|Agent` por `Bash` no `hooks/hooks.json` deixava esta suíte inteira
 * **verde**. Todas as baterias invocam `portaria.cjs` como processo, direto —
 * nenhuma perguntava se o harness chegaria a invocá-lo. A decisão que a portaria
 * toma estava coberta em 307 casos; o fato de ela ser *chamada* não estava
 * coberto em nenhum, e é ele que faz a regra 10 valer em toda sessão (D1).
 *
 * Gate desarmado passa em todo teste que só mede o gate.
 */
{
  const hooksJson = path.join(__dirname, "hooks.json");
  if (!fs.existsSync(hooksJson)) {
    falhar("P6", `hooks/hooks.json existe (${hooksJson})`, "arquivo não encontrado");
  }

  let cfg;
  try {
    cfg = JSON.parse(fs.readFileSync(hooksJson, "utf8"));
  } catch (e) {
    falhar("P6", "hooks/hooks.json é JSON válido", e.message);
  }

  const pre = (cfg.hooks && cfg.hooks.PreToolUse) || [];
  if (!Array.isArray(pre) || pre.length === 0) {
    falhar("P6", "hooks.json tem grupos em PreToolUse", JSON.stringify(cfg.hooks || {}).slice(0, 200));
  }

  const grupo = pre.find((g) =>
    Array.isArray(g.hooks) && g.hooks.some((h) => String(h.command || "").includes("portaria.cjs"))
  );
  if (!grupo) {
    falhar("P6", "algum grupo de PreToolUse invoca portaria.cjs",
      pre.map((g) => g.matcher).join(" | ") || "(nenhum)");
  }

  // O matcher tem de casar os DOIS nomes pelos quais o harness despacha
  // subagente. Casar só um deixa metade dos despachos passar sem portão — e
  // passa despercebido, porque a decisão continua correta para a outra metade.
  let re;
  try {
    re = new RegExp(`^(?:${grupo.matcher})$`);
  } catch (e) {
    falhar("P6", `matcher '${grupo.matcher}' é regex válida`, e.message);
  }
  for (const tool of ["Task", "Agent"]) {
    if (!re.test(tool)) {
      falhar("P6", `matcher '${grupo.matcher}' casa a tool '${tool}'`, "não casa");
    }
  }
  // E NÃO casa o que não é despacho: matcher largo demais faria a portaria
  // decidir sobre Bash, Read e Write, negando trabalho que ela não governa.
  for (const tool of ["Bash", "Read", "Write"]) {
    if (re.test(tool)) {
      falhar("P6", `matcher '${grupo.matcher}' NÃO casa '${tool}'`, "casou — matcher largo demais");
    }
  }

  // O comando aponta para o plugin, não para o projeto aberto: é a diferença
  // entre valer em toda sessão e valer só onde o arquivo existir.
  const cmd = grupo.hooks.find((h) => String(h.command || "").includes("portaria.cjs")).command;
  if (!cmd.includes("CLAUDE_PLUGIN_ROOT")) {
    falhar("P6", "o comando resolve pelo CLAUDE_PLUGIN_ROOT (vale em qualquer projeto)", cmd);
  }
  if (cmd.includes("CLAUDE_PROJECT_DIR")) {
    falhar("P6", "o comando NÃO aponta para o projeto aberto", cmd);
  }

  // E a portaria decide UMA vez: um segundo registro no settings.json deste repo
  // duplicaria cada linha da trilha de auditoria e daria duas chances de divergir.
  const settings = path.join(__dirname, "..", ".claude", "settings.json");
  if (fs.existsSync(settings) && fs.readFileSync(settings, "utf8").includes("portaria")) {
    falhar("P6", ".claude/settings.json não registra a portaria de novo", "registro duplicado");
  }

  fechar("P6", "registro:alcance");
}

console.log("P1..P6: OK");
process.exit(0);
