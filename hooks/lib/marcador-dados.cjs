// Marcador que dispensa a conferência de dados sensíveis num conteúdo.
// Só conta nas 5 primeiras linhas do CONTEÚDO analisado — nunca em qualquer
// ponto do arquivo (Issue #293: credencial nova escapava com o marcador
// enterrado longe do topo, e o gate de publicação a deixava passar).
//
// A frase completa do marcador mora só no regex abaixo, fora deste
// comentário, para o próprio arquivo não se autoisentar quando um gate lê
// este arquivo do disco.
const RE_MARCADOR = /rainforest-gate:\s*dados-de-exemplo/i;

function temMarcadorNoConteudo(conteudo) {
  if (typeof conteudo !== "string") return false;
  const primeirasLinhas = conteudo.split('\n').slice(0, 5).join('\n');
  return RE_MARCADOR.test(primeirasLinhas);
}

module.exports = { temMarcadorNoConteudo };
