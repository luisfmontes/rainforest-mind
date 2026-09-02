#!/usr/bin/env node
"use strict";
/* Bateria da Tarefa 4 do fluxo 9 (D4) — o log de despacho fica FORA do git, e
 * o manifesto e a amostra ficam DENTRO.
 *
 * Por que uma bateria para uma linha de `.gitignore`: as tres decisoes moram no
 * mesmo diretorio `.rainforest/portaria/`, e a forma mais natural de escrever a
 * regra — `.rainforest/` ou `.rainforest/portaria/` — leva junto o manifesto
 * (D2) e a amostra (D7), que TEM de ser versionados. Um `.gitignore` largo
 * demais nao quebra nada nesta maquina: quebra no clone da proxima pessoa, que
 * recebe o hook sem o manifesto que ele exige e ve a portaria negar tudo com
 * "manifesto ausente". A assercao negativa (`agentes.json` NAO pode estar
 * ignorado) e o ponto desta bateria, nao a positiva.
 *
 * O caso do log usa uma linha REAL, gravada por uma decisao real do
 * `portaria.cjs` — nao um `touch`. Arquivo criado por outro caminho provaria a
 * regra do `.gitignore`, nao que o caminho que o hook escreve e o mesmo que a
 * regra cobre. O arquivo e removido no fim se este teste o criou.
 */

const { execFileSync, spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const RAIZ = path.resolve(__dirname, "..");
const HOOK = path.join(__dirname, "portaria.cjs");
const REL_LOG = ".rainforest/portaria/despachos.jsonl";
const LOG = path.join(RAIZ, ".rainforest", "portaria", "despachos.jsonl");

let ok = 0;
let falhou = 0;

function checa(rotulo, condicao, detalhe) {
  if (condicao) {
    ok++;
    console.log(`  ok   ${rotulo}`);
  } else {
    falhou++;
    console.log(`  FALHA ${rotulo}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

/* `git check-ignore -q <caminho>`: exit 0 = ignorado, 1 = nao ignorado.
 *
 * `--no-index` NAO e detalhe: sem ele, este teste inteiro mentia. O git ignora
 * o `.gitignore` para caminho que JA ESTA NO INDICE — arquivo rastreado sempre
 * responde "nao ignorado", diga o `.gitignore` o que disser. Os quatro caminhos
 * da checagem 2 estao commitados, entao a checagem passava sozinha: trocar a
 * regra por `.rainforest/portaria/` — a "regra larga demais" que o cabecalho
 * deste arquivo diz temer — deixava a bateria 9 ok / 0 falha, e a mutacao pelo
 * `conferir-mutacao.cjs` saia 2 (VERDE com o comportamento invertido).
 * Achado na rodada 4 da revisao, reproduzido com `git check-ignore -v` nos dois
 * modos. Com `--no-index`, a resposta e a da REGRA, que e o que este teste
 * afirma medir.
 */
function ignorado(rel) {
  const r = spawnSync("git", ["check-ignore", "-q", "--no-index", "--", rel], { cwd: RAIZ });
  return r.status === 0;
}

console.log("== 1. o log de despacho fica FORA do git ==");
checa(
  `${REL_LOG} e ignorado`,
  ignorado(REL_LOG),
  "sem isto, todo despacho suja o `git status` e o log entra em PR"
);

console.log("");
console.log("== 2. manifesto e amostra ficam DENTRO do git (D2, D7) ==");
for (const rel of [
  ".rainforest/agentes.json",
  ".rainforest/portaria/amostra.json",
  ".rainforest/portaria/amostra-com-isolation.json",
  ".rainforest/portaria/LEIA-ME.md",
]) {
  checa(
    `${rel} NAO e ignorado`,
    !ignorado(rel),
    "regra larga demais no .gitignore levou junto documentacao versionada"
  );
}

console.log("");
console.log("== 3. linha REAL gravada pelo hook nao aparece no git status ==");

const existiaAntes = fs.existsSync(LOG);
const tamanhoAntes = existiaAntes ? fs.statSync(LOG).size : 0;

// Um despacho que o hook NEGA basta: `gravarDespacho` roda nos dois caminhos, e
// negar nao depende de manifesto nem de estagio ativo existirem nesta arvore.
const payload = JSON.stringify({
  session_id: "sessao-do-teste-gitignore",
  hook_event_name: "PreToolUse",
  tool_name: "Agent",
  tool_input: { subagent_type: "agente-que-nao-existe-no-manifesto" },
});

const r = spawnSync(process.execPath, [HOOK], {
  input: payload,
  cwd: RAIZ,
  env: { ...process.env, CLAUDE_PROJECT_DIR: RAIZ },
  encoding: "utf8",
});

checa(
  "o hook decidiu (exit 0 ou 2, nunca crash)",
  r.status === 0 || r.status === 2,
  `veio exit=${r.status}, stderr=${(r.stderr || "").trim().slice(0, 200)}`
);
checa(
  `${REL_LOG} existe depois do despacho`,
  fs.existsSync(LOG),
  "o hook nao gravou onde o .gitignore cobre — regra e escrita divergiram"
);
checa(
  "o log CRESCEU (append, nao truncate)",
  fs.existsSync(LOG) && fs.statSync(LOG).size > tamanhoAntes,
  `antes ${tamanhoAntes} B, depois ${fs.existsSync(LOG) ? fs.statSync(LOG).size : "(ausente)"} B`
);

const porcelain = execFileSync("git", ["status", "--short"], {
  cwd: RAIZ,
  encoding: "utf8",
});
checa(
  "git status --short NAO lista o log",
  !porcelain.includes("despachos.jsonl"),
  `git status trouxe:\n${porcelain}`
);

// Limpeza: so remove o que este teste criou.
if (!existiaAntes && fs.existsSync(LOG)) fs.unlinkSync(LOG);

console.log("");
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou === 0 ? 0 : 1);
