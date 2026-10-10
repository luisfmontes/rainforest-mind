'use strict';
// Comando impresso para o usuario (ou o agente) colar no shell. Issue #474.
//
// Caminho vai entre aspas SIMPLES: dentro de aspas duplas o bash expande `$(...)` e crase,
// e uma pasta com esse nome executaria codigo ao ser colada. Aspas simples sao literais no
// bash e no PowerShell. Caminho com aspa simples ou caractere de controle nao tem forma
// segura nos dois shells: `seguro` diz nao, e quem monta a mensagem troca o comando por
// uma instrucao sem comando para colar.
//
// O mesmo conserto do `comandoRegerar` de scripts/conferir-ponte.cjs (#450).

function barras(caminho) {
  return String(caminho).split('\\').join('/');
}

function seguro(...partes) {
  return partes.every((p) => !/['\x00-\x1f\x7f]/.test(String(p)));
}

function aspas(texto) {
  return `'${texto}'`;
}

module.exports = { barras, seguro, aspas };
