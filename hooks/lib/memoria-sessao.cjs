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
  /**
   * Teto da LEGENDA VISÍVEL de memória (o `systemMessage`), em BYTES.
   *
   * Canal separado do `additionalContext` — o harness conta os dois em métricas
   * distintas —, então este teto não disputa bytes com as 14 observações
   * injetadas. É pequeno porque a legenda responde UMA pergunta ("onde eu tinha
   * parado?"), não substitui o corpus.
   */
  LEGENDA_MAX_BYTES: 420,
  /** Quantas marcas a legenda mostra. O resto continua no `additionalContext`. */
  LEGENDA_MARCAS: 2,
  /**
   * Teto de UMA linha da legenda, em CARACTERES — não em bytes.
   *
   * A unidade importa, e ela estava errada até 2026-08-25: o teto era de 150 BYTES,
   * mas quem corta a linha é o TERMINAL, que conta caractere. Com acento e emoji,
   * 150 bytes viraram 143 caracteres, e o harness ainda prefixa
   * `SessionStart:startup says: ` (27 caracteres) na primeira linha do bloco — 170
   * de largura, cortados com `…` no meio da frase. Medido em captura de tela dele.
   *
   * É a mesma família do `AVANCOS_MAX_BYTES` de `contexto-sessao.cjs`: parâmetro cuja
   * unidade não é a unidade do problema continua parecendo certo enquanto mente.
   *
   * 90 é dimensionado para o pior caso — primeira linha, com prefixo, em terminal de
   * 120 colunas. E é disciplina, não só limite: legenda que não cabe num olhar para
   * de ser lida.
   */
  LEGENDA_LINHA_MAX_CHARS: 90,
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
 * Corta em CARACTERES (code points), acrescentando `…` quando cortou.
 *
 * `Array.from` e não `slice`: emoji fora do plano básico ocupa dois code units, e
 * `slice` por índice de string parte o par substituto no meio — o terminal desenha o
 * losango de caractere inválido. O teto conta o `…` dentro do limite, para que o
 * resultado nunca passe do que foi pedido.
 *
 * @param {string} texto
 * @param {number} maxChars teto em caracteres, incluindo a reticência
 * @returns {string}
 */
function cortarCaracteres(texto, maxChars) {
  const s = String(texto || '');
  const chars = Array.from(s);
  if (chars.length <= maxChars) return s;
  return chars.slice(0, Math.max(0, maxChars - 1)).join('').trimEnd() + '…';
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
 * @param {object} [apelidos] mapa chave-do-banco -> nome curto para exibição
 * @returns {string} linha formatada
 */
function formatarObservacao(obs, apelidos) {
  if (!obs) return '';
  const { conteudo, projeto, criada_em } = obs;
  // criada_em é timestamp ISO; tira a hora para economizar bytes.
  const data = (criada_em || '').split('T')[0] || '';
  // O rótulo exibe o apelido curto quando há um. A chave que o banco guarda é a
  // pasta do harness (`C--Projetos-rainforest-mind`), ~12 bytes a mais por linha
  // que o nome curto — e o bloco tem teto duro. Medido em 2026-08-22: a chave
  // longa derrubou a injeção de 15 observações para 12.
  const nome = (apelidos && apelidos[projeto]) || projeto;
  const proj = nome ? ` (${nome})` : '';

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
 * @param {object} [o.apelidos] mapa chave-do-banco -> nome curto para exibição
 * @returns {string} bloco montado, dentro do teto de bytes
 */
function montarMemoria(o) {
  const observacoes = Array.isArray(o?.observacoes) ? o.observacoes : [];
  const apelidos = (o && typeof o.apelidos === 'object' && o.apelidos) || null;

  // Se vazio, devolve bloco vazio (não injetar item de contexto desnecessário).
  if (!observacoes.length) {
    return '';
  }

  // Cabeçalho do bloco.
  const cabecalho = '## Memória (corpus residentes)\n';

  // Formata cada observação como linha curta (título + subtítulo).
  const linhas = observacoes.map((obs) => formatarObservacao(obs, apelidos)).filter(Boolean);
  const corpo = linhas.join('\n');

  // Ponteiro para busca sob demanda (D11 — reduz observações residentes mas mantém acesso ao corpus).
  const ponteiro = '\n\n(Para buscar no corpus completo: `node scripts/memoria.cjs buscar --texto <termo> --limite 5`)';

  const texto = cabecalho + corpo + ponteiro;

  // Teto em bytes com corte ANUNCIADO.
  return limitarBytes(texto, TETOS.MEMORIA_MAX_BYTES, 'Memória');
}

/**
 * Monta a LEGENDA VISÍVEL da memória — o texto do `systemMessage`, que é o que o
 * usuario VÊ na abertura. O `montarMemoria` acima continua sendo o que o MODELO
 * recebe; são dois canais e dois públicos.
 *
 * Por que existe (2026-08-25): o corpus era injetado em silêncio no
 * `additionalContext`. O modelo abria a sessão sabendo onde tinha parado, e o
 * usuario abria a sessão olhando para uma tela vazia. Quem precisa lembrar do
 * fio da meada é ele.
 *
 * @param {object} o
 * @param {array} [o.observacoes] observações do banco, mais recentes primeiro
 * @param {object} [o.apelidos] mapa chave-do-banco -> nome curto
 * @param {number} [o.quantas] quantas marcas mostrar (default: TETOS.LEGENDA_MARCAS)
 * @param {number} [o.teto] teto em bytes (default: TETOS.LEGENDA_MAX_BYTES)
 * @returns {string} legenda, ou '' quando não há marca nenhuma
 */
function montarLegendaMemoria(o) {
  const observacoes = Array.isArray(o?.observacoes) ? o.observacoes.filter(Boolean) : [];
  if (!observacoes.length) return '';
  const apelidos = (o && typeof o.apelidos === 'object' && o.apelidos) || null;
  const quantas = Number.isFinite(o?.quantas) ? o.quantas : TETOS.LEGENDA_MARCAS;
  const teto = Number.isFinite(o?.teto) ? o.teto : TETOS.LEGENDA_MAX_BYTES;

  const linhas = observacoes.slice(0, Math.max(0, quantas)).map((obs) => {
    // Data curta: quem lê na abertura quer "quando", não o ano — e o ano custa
    // 5 dos 150 bytes da linha.
    const iso = String(obs.criada_em || '').split('T')[0];
    const partes = iso.split('-');
    const data = partes.length === 3 ? `${partes[2]}/${partes[1]}` : iso;
    const nome = (apelidos && apelidos[obs.projeto]) || obs.projeto || '';
    const { titulo, subtitulo } = extrairTituloESubtitulo(obs.conteudo);
    // Título vazio acontece (observação só com corpo): o subtítulo assume, em vez
    // de sair uma linha com data e nada.
    const texto = titulo || subtitulo || '(sem título)';
    const linha = `🧠 ${data}${nome ? ` ${nome}` : ''} — ${texto}`;
    // Corte MUDO aqui, ao contrário do teto do bloco: a linha já é um resumo de
    // resumo, e um aviso de truncamento por linha custaria mais que o texto.
    //
    // Por CARACTERE, e com `Array.from` em vez de `slice`: emoji fora do plano básico
    // ocupa dois code units em JS, e cortar por índice de string parte o par
    // substituto no meio — o terminal desenha o losango de caractere inválido, que é
    // pior que a linha longa que se queria evitar.
    return cortarCaracteres(linha, TETOS.LEGENDA_LINHA_MAX_CHARS);
  }).filter(Boolean);

  if (!linhas.length) return '';
  return limitarBytes(linhas.join('\n'), teto, 'Legenda da memória');
}

module.exports = {
  TETOS,
  montarMemoria,
  montarLegendaMemoria,
  formatarObservacao,
  extrairTituloESubtitulo,
  limitarBytes,
  cortarBytes,
  cortarCaracteres,
};
