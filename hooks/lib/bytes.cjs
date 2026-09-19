'use strict';

/**
 * bytes.cjs — corte de texto por BYTES, sem partir caractere multibyte no meio.
 *
 * Extraído de memoria-sessao.cjs e contexto-sessao.cjs (Issue #259): as duas
 * libs definiam `cortarBytes` com o corpo byte a byte idêntico — a mesma
 * busca binária sobre `Buffer.byteLength` —, e o comentário de uma delas
 * afirmava "reusa a lógica" da outra sem reusar nada. Esta lib é a peça
 * própria da qual as duas passam a importar, para não criar dependência
 * lateral entre duas libs hoje independentes.
 */

/**
 * Corta `texto` no maior prefixo cujo tamanho em UTF-8 cabe em `max` bytes,
 * sem cortar um caractere multibyte pela metade — busca binária sobre
 * `Buffer.byteLength`.
 *
 * @param {string} texto
 * @param {number} max teto em BYTES
 * @returns {string}
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

module.exports = { cortarBytes };
