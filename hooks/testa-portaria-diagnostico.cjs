#!/usr/bin/env node
"use strict";
/* Bateria de diagnóstico da Tarefa 3 do fluxo 9 (portaria).
 *
 * Testa as mensagens de negação enriquecidas com diagnóstico:
 * (a) a negação cita a raiz lida
 * (b) cita a branch atual
 * (c) com outro worktree do mesmo repo em fluxo aberto, cita slug e estágio dele
 * (d) sem outro worktree em fluxo aberto, não inventa nenhum
 * (f) a negação por agente não declarado diz QUAL manifesto foi lido
 *
 * A negação que carrega o diagnóstico mudou em 2026-09-14 (D5). Até então era
 * "manifesto ausente": todo caso montava um sandbox SEM manifesto e o hook
 * negava. Com o padrão embarcado (D2), repo sem manifesto próprio virou o caso
 * NORMAL — a pergunta "por que a portaria não enxerga meu setup" passou a cair
 * em **sem estágio ativo**, que é onde o bloco de diagnóstico mora agora (mesma
 * `raiz lida`, mesma `branch`, mesmos outros worktrees). O caso (f) é novo e
 * cobre a metade da pergunta que não existia antes: com dois manifestos
 * possíveis, "não consta" sem dizer onde se leu manda conferir o arquivo errado.
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

// `RFM_ROOT` desde 2026-09-14 (D6): o log resolve pela raiz de DADOS, que sem
// isolamento é a pasta pessoal do usuário. Esta bateria não olha o log — mas
// sem isto ela escrevia nele.
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

// `realpathSync.native` de propósito: no runner do CI o `os.tmpdir()` do
// Windows vem em forma curta 8.3 (o nome de usuário aparece truncado com `~1`),
// e a portaria imprime o caminho que o Node RESOLVE, por extenso — sem
// normalizar aqui, o `stderr.includes(raiz)` falhava só no CI (verde na máquina
// do dono, vermelho lá, 2026-09-04). Só o `.native` expande nome 8.3; o
// `realpathSync` puro devolve `C:\PROGRA~1` intacto (medido em 2026-09-04).
function caixa() {
  return fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "portaria-diag-")));
}

// A portaria imprime o caminho com barra normal; o `caixa()` devolve com
// contrabarra. Comparar as duas formas sem normalizar falhava no CI mesmo com
// o caminho já expandido (segundo run vermelho de 2026-09-04). Caixa alta/baixa
// também: NTFS não distingue, e o runner já devolveu as duas formas para a
// mesma pasta.
function mesmoCaminho(texto, caminho) {
  const norm = (s) => s.replace(/\\/g, "/").toLowerCase();
  return norm(texto).includes(norm(caminho));
}

function criarEstadoAtivo(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = {
    slug: `2026-09-01-${branchBase}`,
  };

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
  const path_ = path.join(dir, "agentes.json");
  fs.writeFileSync(path_, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
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

function manifestoD2(agentes) {
  return {
    versao: 1,
    agentes: agentes,
  };
}

// == (a) A negação cita a raiz lida ==
console.log("== (a) negação cita raiz lida ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  // Sem estado de fluxo: é a negação por "sem estágio ativo" que carrega o
  // diagnóstico. (Antes da D5 o gatilho era a falta de manifesto, que hoje é o
  // caso normal — ver o cabeçalho.)

  const payload = {
    session_id: "diag-a",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita raiz lida", mesmoCaminho(r.stderr, raiz), `stderr: ${r.stderr}`);
  caso("stderr inclui 'raiz lida:'", r.stderr.includes("raiz lida:"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (b) Negação cita a branch atual ==
console.log("== (b) negação cita branch atual ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/memoria");
  // Sem estado de fluxo — ver (a).

  const payload = {
    session_id: "diag-b",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita branch fluxo/memoria", r.stderr.includes("fluxo/memoria"), `stderr: ${r.stderr}`);
  caso("stderr inclui 'branch:'", r.stderr.includes("branch:"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (c) Com outro worktree em fluxo aberto, cita slug e estágio ==
console.log("== (c) outro worktree em fluxo aberto é mencionado ==");
{
  const raizPrincipal = caixa();
  const raizWorktree = caixa();

  // Setup: dois repositórios separados simulando dois worktrees
  // Vamos usar um truque: criar os dois em um mesmo repo

  // Cria um repo principal
  iniciarGit(raizPrincipal, "main");

  // Cria um "worktree" (na verdade um segundo repo, mas conseguimos o efeito)
  // Para simular melhor, vamos aproveitar que git worktree list funciona em um repo
  // Cria um worktree real
  const dirWorktrees = path.join(raizPrincipal, ".git", "worktrees");
  fs.mkdirSync(dirWorktrees, { recursive: true });

  // Na verdade, vamos fazer mais simples: colocamos ambos em um mesmo repo com git worktree add
  spawnSync("git", ["worktree", "add", raizWorktree, "-b", "fluxo/outro"], { cwd: raizPrincipal });

  // Cria estado no worktree
  criarEstadoAtivo(raizWorktree, "outro", "plano");

  // O principal NÃO tem estado de fluxo: é ele quem nega, por "sem estágio
  // ativo". O worktree tem, e é ele que a mensagem deve citar.

  const payload = {
    session_id: "diag-c",
    cwd: raizPrincipal,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raizPrincipal, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona fluxo aberto", r.stderr.includes("fluxo aberto"), `stderr: ${r.stderr}`);
  caso("stderr cita 'slug'", r.stderr.includes("slug"), `stderr: ${r.stderr}`);
  // O outro worktree foi criado com estágio "plano" aberto — a mensagem tem
  // de citar esse estágio real (lido do lado do outro worktree), nunca "?"
  // (que seria o efeito do bug: ler o estado do worktree atual, onde o
  // arquivo daquele slug não existe).
  caso("stderr cita 'estágio: plano' (estágio real do outro worktree)", r.stderr.includes("estágio: plano"), `stderr: ${r.stderr}`);
  caso("stderr não cita 'estágio: ?' (não devolve '?' para o outro worktree)", !r.stderr.includes("estágio: ?"), `stderr: ${r.stderr}`);

  // Limpeza
  try {
    spawnSync("git", ["worktree", "remove", raizWorktree], { cwd: raizPrincipal });
  } catch {}
  fs.rmSync(raizPrincipal, { recursive: true, force: true });
  if (fs.existsSync(raizWorktree)) {
    fs.rmSync(raizWorktree, { recursive: true, force: true });
  }
}

// == (d) Sem outro worktree em fluxo aberto, não menciona slug ==
console.log("== (d) sem fluxo aberto, nao menciona slug ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/isolado");
  // Sem estado de fluxo e sem nenhum outro worktree

  const payload = {
    session_id: "diag-d",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  // A palavra "slug" não deve aparecer quando não há outros worktrees
  const temSlugAcidentralmente = r.stderr.includes("slug") && r.stderr.includes("outros worktrees");
  caso("stderr não menciona 'slug' (sem outros worktrees)", !temSlugAcidentralmente, `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (e) Dois worktrees com mesmo estado aberto — deduplica ==
console.log("== (e) dois worktrees com mesmo estado aberto — deduplica ==");
{
  const raizPrincipal = caixa();
  const raizWorktree1 = caixa();
  const raizWorktree2 = caixa();

  // Cria um repo principal
  iniciarGit(raizPrincipal, "main");

  // Cria dois worktrees reais com a mesma branch (simulando fluxo aberto)
  spawnSync("git", ["worktree", "add", raizWorktree1, "-b", "fluxo/deduplica"], { cwd: raizPrincipal });
  spawnSync("git", ["worktree", "add", raizWorktree2, "-b", "fluxo/deduplica-2"], { cwd: raizPrincipal });

  // Cria o MESMO estado aberto em ambos os worktrees
  criarEstadoAtivo(raizWorktree1, "mesmo-slug", "executar");
  criarEstadoAtivo(raizWorktree2, "mesmo-slug", "executar");

  // O principal NÃO tem estado de fluxo: é ele quem nega, por "sem estágio ativo".

  const payload = {
    session_id: "diag-e",
    cwd: raizPrincipal,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raizPrincipal, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);

  // Conta quantas vezes "2026-09-01-mesmo-slug" com "estágio: executar" aparece
  // dentro do bloco "outros worktrees em fluxo aberto"
  const match = r.stderr.match(/slug: 2026-09-01-mesmo-slug, estágio: executar/g);
  const ocorrencias = match ? match.length : 0;
  caso("ocorrência de (slug, estágio) é exatamente 1", ocorrencias === 1, `encontradas ${ocorrencias} ocorrências: ${r.stderr}`);

  // Limpeza
  try {
    spawnSync("git", ["worktree", "remove", raizWorktree1], { cwd: raizPrincipal });
    spawnSync("git", ["worktree", "remove", raizWorktree2], { cwd: raizPrincipal });
  } catch {}
  fs.rmSync(raizPrincipal, { recursive: true, force: true });
  [raizWorktree1, raizWorktree2].forEach(p => {
    if (fs.existsSync(p)) {
      fs.rmSync(p, { recursive: true, force: true });
    }
  });
}

// == (f) Negação por agente não declarado diz QUAL manifesto foi lido ==
//
// Com dois manifestos possíveis (o do repo e o padrão embarcado), "não consta
// no manifesto" sozinho manda o usuário abrir o arquivo errado. As duas metades
// têm de aparecer: o caminho lido, e de qual dos dois níveis ele veio.
console.log("== (f) negação por agente não declarado diz qual manifesto foi lido ==");
{
  // -- (f1) quem decide é o padrão embarcado (repo sem manifesto próprio) --
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/diagf");
  criarEstadoAtivo(raiz, "diagf", "revisar");

  const r = rodaHook(raiz, JSON.stringify({
    session_id: "diag-f1",
    tool_input: { subagent_type: "agente-inexistente-em-qualquer-manifesto" },
  }));

  caso("exit 2", r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("stderr inclui 'manifesto lido:'", r.stderr.includes("manifesto lido:"), `stderr: ${r.stderr}`);
  caso("stderr cita o agentes.padrao.json do plugin",
    r.stderr.includes("agentes.padrao.json"), `stderr: ${r.stderr}`);
  caso("stderr diz que a origem é o padrão embarcado",
    r.stderr.includes("padrão embarcado do plugin"), `stderr: ${r.stderr}`);
  caso("e ensina como substituir só neste repositório",
    r.stderr.includes("SUBSTITUI o padrão"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });

  // -- (f2) quem decide é o manifesto do repo --
  const raiz2 = caixa();
  iniciarGit(raiz2, "fluxo/diagf2");
  criarEstadoAtivo(raiz2, "diagf2", "revisar");
  criarManifesto(raiz2, manifestoD2({ executor: { estagios: ["executar"], escreve: true } }));

  const r2 = rodaHook(raiz2, JSON.stringify({
    session_id: "diag-f2",
    tool_input: { subagent_type: "revisor" },
  }));

  caso("exit 2 (o revisor está no padrão, mas o repo substituiu)",
    r2.status === 2, `exit=${r2.status} stderr=${r2.stderr}`);
  caso("stderr cita o manifesto DO REPO",
    mesmoCaminho(r2.stderr, path.join(raiz2, ".rainforest", "agentes.json")), `stderr: ${r2.stderr}`);
  caso("stderr diz que a origem é o manifesto do repositório",
    r2.stderr.includes("manifesto deste repositório"), `stderr: ${r2.stderr}`);
  caso("e NÃO cita o padrão embarcado (não foi ele que decidiu)",
    !r2.stderr.includes("agentes.padrao.json"), `stderr: ${r2.stderr}`);

  fs.rmSync(raiz2, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
