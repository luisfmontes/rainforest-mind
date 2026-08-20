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
 * Extrai título e subtítulo de uma observação (conteúdo estruturado em markdown).
 * Observações têm estrutura: ## Título\n\nSubtítulo\n\n### Seções...
 *
 * @param {string} conteudo conteúdo da observação
 * @returns {object} {titulo, subtitulo}
 */
function extrairTituloESubtitulo(conteudo) {
  if (!conteudo) return { titulo: '', subtitulo: '' };

  const linhas = conteudo.split('\n').map(l => l.trim()).filter(Boolean);

  // Primeira linha não vazia é o título (remove ## se existir)
  let titulo = linhas[0] || '';
  titulo = titulo.replace(/^#+\s*/, '').trim();

  // Próxima linha não vazia que não seja cabeçalho (###, ##, etc) é o subtítulo
  let subtitulo = '';
  for (let i = 1; i < linhas.length; i++) {
    if (!linhas[i].match(/^#+\s/)) {
      subtitulo = linhas[i];
      break;
    }
  }

  return { titulo, subtitulo };
}

/**
 * Formata uma observação como linha curta com título e subtítulo.
 * Formato: [data (projeto)] título — subtítulo
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

  // Extrai título e subtítulo do conteúdo
  const { titulo, subtitulo } = extrairTituloESubtitulo(conteudo);

  // Formata como: [data (projeto)] título — subtítulo
  let linha = `[${data}${proj}]`;
  if (titulo) linha += ` ${titulo}`;
  if (subtitulo) linha += ` — ${subtitulo}`;

  return linha.trim();
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

  // Formata cada observação como linha curta (título + subtítulo).
  const linhas = observacoes.map(formatarObservacao).filter(Boolean);
  const corpo = linhas.join('\n');

  // Ponteiro para busca sob demanda (D11 — reduz observações residentes mas mantém acesso ao corpus).
  const ponteiro = '\n\n(Para buscar no corpus completo: `node scripts/memoria.cjs buscar --texto <termo> --limite 5`)';

  const texto = cabecalho + corpo + ponteiro;

  // Teto em bytes com corte ANUNCIADO.
  return limitarBytes(texto, TETOS.MEMORIA_MAX_BYTES, 'Memória');
}

module.exports = {
  TETOS,
  montarMemoria,
  formatarObservacao,
  extrairTituloESubtitulo,
  limitarBytes,
  cortarBytes,
};
