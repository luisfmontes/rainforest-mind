#!/usr/bin/env node
"use strict";
/* Bateria do destino do log de despacho (D6 e D8 de 2026-09-13).
 *
 * Ate 2026-09-13 `gravarDespacho` escrevia em
 * `<projeto>/.rainforest/portaria/despachos.jsonl`. Aqui isso esta no
 * `.gitignore`; num repositorio de cliente, nao — e a partir do momento em que
 * a portaria passou a rodar em TODA sessao (D1), cada despacho criaria pasta
 * nao rastreada no `git status` de outra pessoa. A regra 15 diz que ninguem
 * altera o ambiente do usuario; sujar repo alheio e a versao pequena disso.
 *
 * O log passa a resolver por `hooks/lib/raiz.cjs` — o mesmo mecanismo que ja
 * decide onde moram FOCO e ideias — e cada linha carrega o campo `repo`, porque
 * uma trilha que atravessa repositorios precisa dizer de qual ela fala.
 *
 * A DIVERGENCIA DECLARADA, e por que ela nao e escape: um repositorio que tenha
 * o proprio `.rainforest/` com marcador (`FOCO.md` ou `ideias.jsonl`) mantem o
 * log la. Esse repo **optou** por ter dados proprios do rainforest, e o log
 * acompanha a raiz que governa. O caso 2 mede exatamente isso.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
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
    console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 500)}` : ""}`);
  }
}

/* `dados === null` deixa `RFM_ROOT` DE FORA de proposito.
 *
 * `RFM_ROOT` e o nivel 1 de `resolverRaiz` e vence o `.rainforest` do projeto —
 * com ele setado, a divergencia da D6 (repo que optou mantem o log local) nao
 * teria como aparecer, e o caso 2 mediria a precedencia do proprio teste. Omitir
 * so e seguro porque aquele caso cria `.rainforest/FOCO.md` no repo: o nivel 2
 * responde ANTES do nivel 3, entao a pasta pessoal do usuario nunca e alcancada.
 */
function despachar(repo, dados, agente) {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: repo, RFM_TEST: "1" };
  if (dados === null) delete env.RFM_ROOT;
  else env.RFM_ROOT = dados;

  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({
      session_id: "log-fora-do-repo",
      cwd: repo,
      tool_name: "Task",
      tool_input: { subagent_type: agente, prompt: "prova" },
    }),
    encoding: "utf8",
    env,
  });
}

function linhas(p) {
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "portaria-log-"));

// == 1. Repo sem `.rainforest` proprio: o log vai para a raiz de dados ==
console.log("== 1. repo sem .rainforest -> log na raiz de dados, e nada no repo ==");
const repo1 = path.join(caixa, "repo-limpo");
const dados1 = path.join(caixa, "dados");
fs.mkdirSync(repo1, { recursive: true });
fs.mkdirSync(dados1, { recursive: true });

despachar(repo1, dados1, "revisor");

const logDados = path.join(dados1, "portaria", "despachos.jsonl");
caso("o log existe na raiz de dados", fs.existsSync(logDados), logDados);
caso("e o repo NAO ganhou pasta .rainforest",
  !fs.existsSync(path.join(repo1, ".rainforest")),
  fs.existsSync(path.join(repo1, ".rainforest"))
    ? fs.readdirSync(path.join(repo1, ".rainforest")).join(",")
    : "");

const ls1 = linhas(logDados);
caso("gravou ao menos uma linha", ls1.length >= 1, `linhas=${ls1.length}`);
caso("a linha tem o campo `repo` com o caminho do repo",
  ls1.length >= 1 && ls1[ls1.length - 1].repo === repo1,
  ls1.length >= 1 ? JSON.stringify(ls1[ls1.length - 1]) : "");

// == 2. Repo que OPTOU por raiz propria mantem o log local (divergencia da D6) ==
console.log("== 2. repo com .rainforest/FOCO.md proprio -> log fica local ==");
const repo2 = path.join(caixa, "repo-com-raiz");
fs.mkdirSync(path.join(repo2, ".rainforest"), { recursive: true });
fs.writeFileSync(path.join(repo2, ".rainforest", "FOCO.md"), "# Foco\n", "utf8");

const antes = linhas(logDados).length;
despachar(repo2, null, "revisor");

const logLocal = path.join(repo2, ".rainforest", "portaria", "despachos.jsonl");
caso("o log local do repo que optou existe", fs.existsSync(logLocal), logLocal);
caso("e a raiz de dados NAO recebeu linha nova",
  linhas(logDados).length === antes,
  `antes=${antes} depois=${linhas(logDados).length}`);

// == 3. Falha de gravacao se anuncia, mas nao vira negacao (D8) ==
//
// `gravarDespacho` engolia erro de escrita num `catch` vazio. Enquanto o log era
// um arquivo ignorado do proprio repo, uma linha perdida era uma linha perdida;
// depois da D6 ele e a unica trilha que atravessa repositorios, e perder linha
// em silencio e pior que nao ter trilha — porque parece ter. A escrita continua
// NAO-fatal (log ilegivel nao pode barrar trabalho), mas deixa de ser calada.
// Desde 2026-09-15 a decisao deixa de ser negada por falta de log: o log e
// trilha, nao portao. A falha ainda aparece no stderr (para auditoria), mas
// a decisao passa a ser 'allow' — agora a trilha pode ter buraco, mas o trabalho
// nao e barrado.
console.log("== 3. falha de gravacao aparece no stderr, mas deixa de negar ==");
const repo3 = path.join(caixa, "repo-sem-log");
fs.mkdirSync(repo3, { recursive: true });
// Aponta a raiz de dados para um ARQUIVO: `mkdir` dentro dele e impossivel.
const dadosArquivo = path.join(caixa, "isto-e-um-arquivo");
fs.writeFileSync(dadosArquivo, "nao sou pasta\n", "utf8");

const r3 = despachar(repo3, dadosArquivo, "revisor");
caso("o stderr diz que a linha NAO foi gravada",
  /linha do log NAO foi gravada/i.test(r3.stderr || ""), r3.stderr);
caso("mas a decisao continua saindo 0 (log e trilha, nao portao)",
  r3.status === 0, `exit=${r3.status}`);

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
try { fs.rmSync(caixa, { recursive: true, force: true }); } catch {}
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
