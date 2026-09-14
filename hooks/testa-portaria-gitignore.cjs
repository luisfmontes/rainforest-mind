#!/usr/bin/env node
"use strict";
/* Bateria da Tarefa 4 do fluxo 9 (D4) — o log de despacho fica FORA do git, e
 * o manifesto e a amostra ficam DENTRO.
 *
 * Por que uma bateria para uma linha de `.gitignore`: as tres decisoes moram no
 * mesmo diretorio `.rainforest/portaria/`, e a forma mais natural de escrever a
 * regra — `.rainforest/` ou `.rainforest/portaria/` — leva junto o manifesto
 * padrao (D2) e a amostra (D7), que TEM de ser versionados. Um `.gitignore`
 * largo demais nao quebra nada nesta maquina: quebra no clone da proxima
 * pessoa, que recebe o plugin SEM o padrao embarcado que ele exige e ve a
 * portaria morrer com "instalacao incompleta" em toda sessao, em todo repo. A
 * assercao negativa (`agentes.padrao.json` NAO pode estar ignorado) e o ponto
 * desta bateria, nao a positiva — e ela ficou mais cara de errar depois da D1,
 * porque o alcance deixou de ser este repositorio.
 *
 * MUDOU EM 2026-09-14 (D6). O log de despacho parou de ser escrito dentro do
 * repositorio: ele resolve pela raiz de DADOS (`hooks/lib/raiz.cjs`). A
 * checagem 3 afirmava "o hook gravou no caminho que o .gitignore cobre" e
 * gravava de fato — hoje ela afirma o contrario, e pelo motivo certo: o log NAO
 * aparece no `git status` porque **nao e escrito aqui**, nao porque esta
 * ignorado. As duas razoes dao o mesmo `git status` limpo e sao verificaveis
 * separadamente, entao a checagem mede as duas: a linha existe (na raiz de
 * dados) E o repositorio nao ganhou o arquivo.
 *
 * A linha do `.gitignore` continua onde esta, e a checagem 1 com ela: ela cobre
 * o clone de quem atualiza o plugin com um log antigo no disco, e o repositorio
 * que **optar** por ter `.rainforest/` proprio com marcador — caso em que a D6
 * manda o log ficar local de propria vontade.
 *
 * O caso do log usa uma linha REAL, gravada por uma decisao real do
 * `portaria.cjs` — nao um `touch`. Arquivo criado por outro caminho provaria a
 * regra do `.gitignore`, nao o que o hook faz.
 */

const { execFileSync, spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
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
  ".rainforest/agentes.padrao.json",
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
console.log("== 3. o log de uma decisao REAL nao entra neste repositorio ==");

const existiaAntes = fs.existsSync(LOG);
const tamanhoAntes = existiaAntes ? fs.statSync(LOG).size : 0;

// Um despacho que o hook NEGA basta: `gravarDespacho` roda nos dois caminhos, e
// negar nao depende de estagio ativo existir nesta arvore.
const payload = JSON.stringify({
  session_id: "sessao-do-teste-gitignore",
  hook_event_name: "PreToolUse",
  tool_name: "Agent",
  tool_input: { subagent_type: "agente-que-nao-existe-no-manifesto" },
});

// Raiz de dados em caixa de areia. Sem isso a linha ia para a pasta pessoal do
// usuario de verdade (medido em 2026-09-14: esta bateria, junto com as outras,
// deixou 53 linhas de teste em `<home>/.rainforest/portaria/`). `RFM_ROOT` e o
// nivel 1 de `resolverRaiz`.
const dados = fs.mkdtempSync(path.join(os.tmpdir(), "portaria-gitignore-dados-"));
const logNaCaixa = path.join(dados, "portaria", "despachos.jsonl");

const r = spawnSync(process.execPath, [HOOK], {
  input: payload,
  cwd: RAIZ,
  env: { ...process.env, CLAUDE_PROJECT_DIR: RAIZ, RFM_ROOT: dados },
  encoding: "utf8",
});

checa(
  "o hook decidiu (exit 0 ou 2, nunca crash)",
  r.status === 0 || r.status === 2,
  `veio exit=${r.status}, stderr=${(r.stderr || "").trim().slice(0, 200)}`
);

// A linha EXISTE — sem esta checagem, as duas de baixo passariam tambem se o
// hook simplesmente tivesse parado de logar.
checa(
  "a linha foi gravada na raiz de dados",
  fs.existsSync(logNaCaixa),
  `esperava ${logNaCaixa}`
);
checa(
  "e a linha carrega o caminho deste repo no campo `repo`",
  fs.existsSync(logNaCaixa) &&
    (() => {
      const l = JSON.parse(fs.readFileSync(logNaCaixa, "utf8").trim().split("\n").pop());
      return String(l.repo).replace(/\\/g, "/").toLowerCase()
        === RAIZ.replace(/\\/g, "/").toLowerCase();
    })(),
  fs.existsSync(logNaCaixa) ? fs.readFileSync(logNaCaixa, "utf8").trim().split("\n").pop() : ""
);

// E o repositorio nao ganhou nada. Este e o fato que mudou: antes da D6 o
// arquivo nascia aqui e era o `.gitignore` que o escondia.
checa(
  `${REL_LOG} NAO foi criado pelo despacho`,
  !fs.existsSync(LOG) || fs.statSync(LOG).size === tamanhoAntes,
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

fs.rmSync(dados, { recursive: true, force: true });
// Limpeza: so remove o que este teste criou.
if (!existiaAntes && fs.existsSync(LOG)) fs.unlinkSync(LOG);

console.log("");
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou === 0 ? 0 : 1);
