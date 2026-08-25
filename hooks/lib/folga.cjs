// Avaliador de folga contra um teto de orçamento.
//
// Estratégia: a folga é a diferença entre o teto e o valor medido. Quando a folga
// cai abaixo de uma banda (limiar), o estado muda de 'ok' para 'aviso'. Quando fica
// negativa, vira 'estouro'. A banda é configurável (padrão 5% do teto).
//
// A mensagem de aviso/estouro enunciava o trade-off — nomeando números e listando
// de onde o byte pode sair (alternativas). Nunca prescreve o conserto: quem bate
// no teto pode querer adicionar regra, e aí o byte sai do FOCO ou do agregado,
// não do núcleo.

const fs = require('fs');
const path = require('path');

// Mensagem de estado 'ok': vazia.
function mensagemOk() {
  return '';
}

// Mensagem de estado 'aviso' ou 'estouro'.
function mensagemAlerta(estado, teto, folga, limiar, nome, alternativas) {
  const prefixo = estado === 'estouro'
    ? `Estouro de ${nome}: `
    : `Aviso de folga em ${nome}: `;

  // Para estouro: mostra valor, teto e excesso explícitos (e.g., "14462 B > 14000 B (+462 B)")
  // Para aviso: mostra folga restante e limiar (e.g., "11 de 5600 bytes (limiar: 280 B)")
  let numerosMsg;
  if (estado === 'estouro') {
    const valor = teto - folga; // folga é negativo, então valor = teto + Math.abs(folga)
    const excesso = Math.abs(folga);
    numerosMsg = `${valor} B > ${teto} B (+${excesso} B)`;
  } else {
    numerosMsg = `${folga} de ${teto} bytes (limiar: ${limiar} B).`;
  }

  let msg = prefixo + numerosMsg;

  if (alternativas && alternativas.length > 0) {
    msg += ` O byte pode sair de: ${alternativas.join(', ')}.`;
  }

  return msg;
}

function avaliarFolga(valor, teto, opcoes = {}) {
  const banda = opcoes.banda !== undefined ? opcoes.banda : 0.05;
  const nome = opcoes.nome || 'teto';
  const alternativas = opcoes.alternativas || [];

  const limiar = Math.round(teto * banda);
  const folga = teto - valor;

  let estado;
  if (folga < 0) {
    estado = 'estouro';
  } else if (folga < limiar) {
    estado = 'aviso';
  } else {
    estado = 'ok';
  }

  const pct = ((folga / teto) * 100).toFixed(2);
  const mensagem = estado === 'ok'
    ? mensagemOk()
    : mensagemAlerta(estado, teto, folga, limiar, nome, alternativas);

  return {
    estado,
    folga,
    limiar,
    pct,
    mensagem,
  };
}

module.exports = {
  avaliarFolga,
};
