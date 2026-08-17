'use strict';

/**
 * memoria-sessao.cjs — motor puro do SessionStart de memória (memoria-session-start.cjs).
 *
 * É PURO de propósito: entra JSON de observações, sai TEXTO. Não lê arquivo,
 * não abre banco, não abre socket. Quem faz I/O é o adaptador (memoria-session-start.cjs).
 * A divisão é a mesma do contexto-sessao.cjs de propósito — sem ela, testar
 * a injeção exige subir uma sessão de verdade.
 *
 * ORÇAMENTO: o bloco de memória é item separado (D10) com teto próprio em bytes,
 * independente do teto de 8.000 B do hook de foco. A disputa por bytes já deixou
 * regras fora da injeção antes; este item de contexto novo não deve repetir isso.
 *
 * Teto: dimensionado em bytes, com corte ANUNCIADO. Banco ausente/vazio/corrompido
 * entrega bloco vazio, exit 0 — nunca erro.
 */

/** Tetos do bloco de memória, em BYTES. */
const TETOS = {
  /** Teto do bloco inteiro de memória. */
  MEMORIA_MAX_BYTES: 3000,
};

/**
 * Corta texto em BYTES sem partir caractere multibyte no meio.
 * Reusa a mesma lógica de contexto-sessao.cjs por confiabilidade.
 */
function cortarBytes(texto, max) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= max) return s;
  let baixo = 0;
  let alto = s.length;
  while (baixo < alto) {
    const meio = Math.ceil((baixo + alto) / 2);
    if (Buffer.byteLength(s.slice(0, meio), 'utf8') <= max) baixo = meio;
    else alto = meio - 1;
  }
  return s.slice(0, baixo);
}

/**
 * Teto duro em BYTES, com aviso explícito de corte que cabe dentro do teto.
 * Reusa a lógica de contexto-sessao.cjs por confiabilidade.
 */
function limitarBytes(texto, maxBytes, nomeDoBloco) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= maxBytes) return s;
  const aviso = `\n\n[${nomeDoBloco} truncado no teto de ${maxBytes} bytes — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
  const espaco = Math.max(0, maxBytes - Buffer.byteLength(aviso, 'utf8'));
  return cortarBytes(s, espaco).trimEnd() + aviso;
}

/**
 * Formata uma observação como linha de texto.
 *
 * @param {object} obs observação do banco
 * @returns {string} linha formatada
 */
function formatarObservacao(obs) {
  if (!obs) return '';
  const { conteudo, projeto, criada_em } = obs;
  // criada_em é timestamp ISO; tira a hora para economizar bytes.
  const data = (criada_em || '').split('T')[0] || '';
  const proj = projeto ? ` (${projeto})` : '';
  return `- [${data}${proj}] ${conteudo || ''}`.trim();
}

/**
 * Monta o bloco de memória para injeção.
 *
 * @param {object} o
 * @param {array} [o.observacoes] array de observações do banco
 * @returns {string} bloco montado, dentro do teto de bytes
 */
function montarMemoria(o) {
  const observacoes = Array.isArray(o?.observacoes) ? o.observacoes : [];

  // Se vazio, devolve bloco vazio (não injetar item de contexto desnecessário).
  if (!observacoes.length) {
    return '';
  }

  // Cabeçalho do bloco.
  const cabecalho = '## Memória (corpus residentes)\n';

  // Formata cada observação como linha.
  const linhas = observacoes.map(formatarObservacao).filter(Boolean);
  const corpo = linhas.join('\n');

  const rodape = '\n\n(Estas são as observações mais recentes do corpus. Use `Skill(rainforest-mind)` para buscar mais.)';

  const texto = cabecalho + corpo + rodape;

  // Teto em bytes com corte ANUNCIADO.
  return limitarBytes(texto, TETOS.MEMORIA_MAX_BYTES, 'Memória');
}

module.exports = {
  TETOS,
  montarMemoria,
  formatarObservacao,
  limitarBytes,
  cortarBytes,
};
