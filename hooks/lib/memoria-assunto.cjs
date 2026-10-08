'use strict';
/**
 * Memória por assunto (design 2026-10-08, D3/D4/D6): dado o texto de um pedido,
 * acha no FTS as memórias de QUALQUER projeto que tratam do mesmo assunto e
 * monta o bloco injetável. Sem I/O além da conexão recebida; nunca lança.
 */
const path = require('path');
const { filtroVivas } = require(path.join(__dirname, '..', '..', 'scripts', 'memoria.cjs'));
const { formatarObservacao } = require('./memoria-sessao.cjs');

// bm25 do FTS5 é negativo (mais negativo = mais relevante). Entra a candidata
// com bm25 <= LIMIAR_BM25. Calibrado em docs/rainforest/referencia/2026-10-08-limiar-memoria-assunto.md.
const LIMIAR_BM25 = -16;
const TETO_BYTES = 1500;
const CABECALHO = '## Memória do assunto';
const LIMITE_TERMOS = 30;
const LIMITE_SQL = 50;

// Query OR dos LIMITE_TERMOS termos MAIS RAROS do texto: menor document frequency > 0 em
// observacoes_fts (termo com df 0 nao casa nada e nao entra). Briefing longo nao dilui a
// consulta com palavras comuns. Desempate estavel (ordem de aparicao). Lanca se o FTS faltar.
function construirQueryAssunto(conexao, texto) {
  const brutos = String(texto || '').match(/[\p{L}\p{N}]+/gu) || [];
  const unicos = Array.from(new Set(brutos.map((t) => t.toLowerCase())));
  if (unicos.length === 0) return null;
  const contar = conexao.prepare('SELECT count(*) AS n FROM observacoes_fts WHERE observacoes_fts MATCH ?');
  const comDf = [];
  unicos.forEach((t, i) => {
    const n = Number(contar.get('"' + t.replace(/"/g, '""') + '"').n);
    if (n > 0) comDf.push({ t, n, i });
  });
  if (comDf.length === 0) return null;
  comDf.sort((a, b) => (a.n - b.n) || (a.i - b.i));
  return comDf.slice(0, LIMITE_TERMOS).map((x) => '"' + x.t.replace(/"/g, '""') + '"').join(' OR ');
}

function buscarPorAssunto(conexao, texto, { projetoAtual, jaServidos = new Set(), max = 3, limiar = LIMIAR_BM25 } = {}) {
  try {
    const query = construirQueryAssunto(conexao, texto);
    if (!query) return [];
    const linhas = conexao
      .prepare(
        `SELECT o.id, o.projeto, o.conteudo, o.criada_em, bm25(observacoes_fts) AS bm25
         FROM observacoes_fts JOIN observacoes o ON o.id = observacoes_fts.rowid
         WHERE observacoes_fts MATCH ? AND o.consolidada_em IS NULL ${filtroVivas('o.')}
         ORDER BY bm25(observacoes_fts) LIMIT ${LIMITE_SQL}`
      )
      .all(query)
      .filter((l) => l.bm25 <= limiar);
    const candidatas = linhas.filter((l) => !jaServidos.has(l.id));
    candidatas.sort((a, b) =>
      (a.bm25 - b.bm25) ||
      ((b.projeto === projetoAtual) - (a.projeto === projetoAtual)) ||
      (a.id - b.id));
    return candidatas.slice(0, max).map((l) => ({
      id: l.id, projeto: l.projeto, conteudo: l.conteudo, criada_em: l.criada_em, bm25: l.bm25,
    }));
  } catch (e) {
    return [];
  }
}

function montarBlocoAssunto(linhas) {
  if (!Array.isArray(linhas) || linhas.length === 0) return '';
  let bloco = CABECALHO;
  let algumaLinha = false;
  for (const l of linhas) {
    const proxima = bloco + '\n' + formatarObservacao(l, null, 300);
    if (Buffer.byteLength(proxima, 'utf8') > TETO_BYTES) break;
    bloco = proxima;
    algumaLinha = true;
  }
  return algumaLinha ? bloco : '';
}

module.exports = { LIMIAR_BM25, construirQueryAssunto, buscarPorAssunto, montarBlocoAssunto };
