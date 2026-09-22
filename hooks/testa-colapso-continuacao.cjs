#!/usr/bin/env node
// @categoria: bateria
//
// Bateria de UNIDADE do colapso de continuacao de linha
// (`colapsaContinuacaoDeLinha`, hooks/lib/tokens-comando.cjs).
//
// POR QUE EXISTE, com data. A revisao 4 do fluxo zerar-issues-8 (2026-09-22)
// mediu os casos novos da bateria do gate contra a versao ANTERIOR do codigo e
// achou que dois deles — contrabarra unica e CRLF — davam exit 2 nas duas, ou
// seja, nao discriminavam nada: outra camada do gate (a busca por substring
// "gh issue close") ja barrava aqueles comandos com a funcao certa OU quebrada.
// Regressao isolada no colapso passaria pela bateria do gate sem acender.
//
// Aqui o veredito e a STRING que a funcao devolve, nao o exit code do gate.
// O oraculo de cada caso e o bash de verdade: a coluna `bash` de cada linha
// abaixo foi medida alimentando o bash por STDIN (`bash -x` com o comando no
// input) — passar o comando por argv no Windows corrompe a contagem de
// contrabarras, armadilha que a propria revisao 4 documentou.

const { colapsaContinuacaoDeLinha } = require("./lib/tokens-comando.cjs");

const B = String.fromCharCode(92); // contrabarra, montada assim de proposito
const LF = "\n";
const CR = "\r";

const casos = [
  // [nome, entrada, saida esperada]
  ["1 contrabarra + LF: continua a linha", `echo hi ${B}${LF}gh issue close 12`, "echo hi gh issue close 12"],
  ["2 contrabarras + LF: a quebra SEPARA comandos", `echo hi ${B}${B}${LF}gh issue close 12`, `echo hi ${B}${B}${LF}gh issue close 12`],
  ["3 contrabarras + LF: a impar continua a linha", `echo hi ${B}${B}${B}${LF}gh`, `echo hi ${B}${B}gh`],
  ["4 contrabarras + LF: a quebra SEPARA", `echo hi ${B}${B}${B}${B}${LF}gh`, `echo hi ${B}${B}${B}${B}${LF}gh`],
  ["CRLF tambem e continuacao", `echo hi ${B}${CR}${LF}gh issue close 12`, "echo hi gh issue close 12"],
  ["dentro de aspas simples nao colapsa", `echo 'a${B}${LF}b'`, `echo 'a${B}${LF}b'`],
  ["dentro de aspas duplas colapsa", `echo "a${B}${LF}b"`, `echo "a${B}${LF}b"`.replace(`${B}${LF}`, "")],
  ["apostrofo solto em aspas duplas nao protege a quebra", `--body "it's closes ${B}${LF}#42, don't"`, `--body "it's closes #42, don't"`],
  ["aspa dupla escapada nao fecha a aspa", `echo "a${B}"b ${B}${LF}c"`, `echo "a${B}"b c"`],
  ["contrabarra solta no fim absoluto: o bash descarta", `echo hi${B}`, "echo hi"],
  ["2 contrabarras no fim absoluto ficam", `echo hi${B}${B}`, `echo hi${B}${B}`],
  ["quebra sem contrabarra fica", `gh issue${LF}close 12`, `gh issue${LF}close 12`],
  ["string vazia", "", ""],
  ["so quebras", `${LF}${LF}`, `${LF}${LF}`],
  ["CR sozinho nao e continuacao", `echo hi ${B}${CR}gh`, `echo hi ${B}${CR}gh`],
  ["aspas simples dentro de duplas", `echo "a'b ${B}${LF}c"`, `echo "a'b c"`],
  ["aspas duplas dentro de simples", `echo 'a"b ${B}${LF}c'`, `echo 'a"b ${B}${LF}c'`],
  // Medido no bash (comando pelo stdin): a saida e `cant'stop \<LF>here`, com a
  // contrabarra e a quebra LITERAIS — depois do `\'` a aspa seguinte ABRE aspas
  // simples de novo, e ali dentro nada colapsa. Nao colapsar e o certo.
  ["idioma fecha-escapa-reabre nao colapsa", `echo 'cant'${B}''stop ${B}${LF}here'`, `echo 'cant'${B}''stop ${B}${LF}here'`],
  ["caminho Windows nao vira continuacao", `grep x C:${B}Users${B}Luis${B}nota.txt`, `grep x C:${B}Users${B}Luis${B}nota.txt`],
];

function visivel(s) {
  return JSON.stringify(s);
}

let ok = 0;
let falhou = 0;
for (const [nome, entrada, esperado] of casos) {
  const veio = colapsaContinuacaoDeLinha(entrada);
  if (veio === esperado) {
    ok += 1;
    console.log(`  ok   ${nome}`);
  } else {
    falhou += 1;
    console.log(`  FALHA ${nome}`);
    console.log(`        entrada : ${visivel(entrada)}`);
    console.log(`        esperado: ${visivel(esperado)}`);
    console.log(`        veio    : ${visivel(veio)}`);
  }
}

console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou === 0 ? 0 : 1);
