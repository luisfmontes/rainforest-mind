'use strict';
/**
 * contexto-sessao.cjs — motor puro do SessionStart (foco-session-start.cjs).
 *
 * É PURO de propósito: entra TEXTO, sai TEXTO. Não lê arquivo, não escreve na tela,
 * não abre socket. Quem faz I/O é o adaptador (foco-session-start.cjs). A divisão é
 * a mesma do sonar-engine.cjs de um plugin interno de cliente, e existe pelo mesmo motivo: sem
 * ela, testar a injeção exige subir uma sessão de verdade — e o que não se testa
 * barato não se testa.
 *
 * Origem (2026-08-09): diff contra o session-context-lib.cjs de um plugin interno de cliente,
 * ancestral deste hook. Três coisas vieram de lá — teto mecânico de tamanho,
 * degradação barulhenta e a própria separação motor/adaptador.
 */

/** Tetos. Mexer aqui muda o custo de TODA sessão — o número é a política. */
const TETOS = {
  /** Entradas datadas de "Avanços" que ficam residentes na injeção. */
  AVANCOS_RESIDENTES: 3,
  /** Teto duro do bloco de foco depois do resumo. */
  FOCO_MAX_CHARS: 4500,
  /**
   * Piso do bloco de regras. Abaixo disto considera-se que NÃO carregou.
   * Não é `if (!regras)`: SKILL.md truncado ou heading renomeado produzem
   * bloco curto e não-vazio, e essa falha é tão grave quanto o vazio.
   */
  REGRAS_MIN_CHARS: 500,
};

/**
 * Incidente citado em blockquote sai da injeção e continua no arquivo, ao lado da
 * regra que ele fundamenta. Narrativa (o que aconteceu, quando, quem corrigiu) vai
 * pro blockquote; instrução nunca — se a frase diz o que fazer, ela fica residente.
 */
const CITACAO = /^>.*(?:\r?\n|$)/gm;

/** Início de uma entrada datada de "Avanços": `- 2026-08-09: ...` */
const ENTRADA_DATADA = /\n(?=- \d{4}-\d{2}-\d{2})/;

/** Extrai o bloco de regras do SKILL.md e remove as citações. */
function filtrarRegras(skillText) {
  const bruto = (String(skillText || '').split('## As regras')[1] || '').split('## Comando')[0] || '';
  return bruto.replace(CITACAO, '').replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * Bloco de regras com degradação BARULHENTA.
 *
 * O hook antigo imprimia o cabeçalho seguido de nada quando o SKILL.md não era
 * legível: a sessão subia sem regra nenhuma e ninguém ficava sabendo. O próprio
 * texto injetado dizia "silêncio faz o Luís acreditar que a regra rodou" — e o
 * hook cometia exatamente essa falha. Reproduzido em 2026-08-09 rodando o hook
 * com RFM_ROOT numa pasta vazia.
 */
function blocoRegras(regras, caminhoSkill) {
  const texto = String(regras || '').trim();
  if (texto.length >= TETOS.REGRAS_MIN_CHARS) return texto;

  const diagnostico = texto.length === 0
    ? 'o arquivo não foi lido, ou não tem a seção `## As regras`'
    : `só ${texto.length} caracteres foram extraídos (piso: ${TETOS.REGRAS_MIN_CHARS}) — arquivo truncado ou heading renomeado`;

  return [
    '⚠️ **FALHA AO CARREGAR AS REGRAS — esta sessão está SEM o rainforest-mind.**',
    '',
    `Origem esperada: \`${caminhoSkill}\``,
    `Diagnóstico: ${diagnostico}.`,
    '',
    'Nenhuma regra numerada está valendo nesta sessão: nem responder tudo na ordem,',
    'nem o radar de escopo, nem os guarda-corpos de agente e de jornada.',
    '',
    '**Diga isto ao Luís na primeira resposta do turno, antes de qualquer trabalho.**',
    'Não trabalhe como se as regras estivessem ativas — elas não estão.',
  ].join('\n');
}

/**
 * Mantém residentes as N entradas mais recentes de "Avanços" e troca o resto por um
 * ponteiro explícito. Nada se perde: o arquivo continua inteiro em disco.
 *
 * Motivo (medido em 2026-08-09): "Avanços" era 42% do FOCO.md, ~110 tokens por
 * entrada, append-only e sem teto. Num projeto de 3 meses ultrapassaria o bloco de
 * regras inteiro. É o mesmo movimento do filtro de citação, agora no FOCO.
 */
function resumirAvancos(focoText, maxEntradas = TETOS.AVANCOS_RESIDENTES) {
  const foco = String(focoText || '');
  const marcador = '\nAvanços:';
  const inicio = foco.indexOf(marcador);
  if (inicio === -1) return foco;

  const corpoInicio = inicio + marcador.length;
  const resto = foco.slice(corpoInicio);
  const fim = resto.search(/\n## /);
  const corpo = fim === -1 ? resto : resto.slice(0, fim);
  const cauda = fim === -1 ? '' : resto.slice(fim);

  const entradas = corpo.split(ENTRADA_DATADA).map((e) => e.trim()).filter(Boolean);
  if (entradas.length <= maxEntradas) return foco;

  const ocultas = entradas.length - maxEntradas;
  const mantidas = entradas.slice(-maxEntradas);
  const ponteiro = `- (${ocultas} ${ocultas === 1 ? 'entrada anterior' : 'entradas anteriores'} ` +
    `${ocultas === 1 ? 'foi omitida' : 'foram omitidas'} desta injeção para conter o custo por sessão. ` +
    'Elas continuam no FOCO.md — **leia o arquivo antes de afirmar o que já foi decidido ou feito neste foco**.)';

  return foco.slice(0, corpoInicio) + '\n' + [ponteiro, ...mantidas].join('\n') + cauda;
}

/** Teto duro, com aviso explícito de que houve corte. Nunca corta em silêncio. */
function limitar(texto, max, nomeDoBloco) {
  const s = String(texto || '');
  if (s.length <= max) return s;
  return s.slice(0, max).trimEnd() +
    `\n\n[${nomeDoBloco} truncado no teto de ${max} caracteres — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
}

/**
 * Monta o additionalContext. Recebe texto já lido pelo adaptador.
 *
 * @param {object} o
 * @param {string} o.skillText      conteúdo do SKILL.md
 * @param {string} o.focoText       conteúdo do FOCO.md
 * @param {string} [o.caminhoSkill] caminho do SKILL.md, citado no diagnóstico de falha
 * @param {string} [o.root]         raiz dos arquivos de apoio
 * @param {string} [o.sessoes]      bloco do radar multi-janela
 * @param {string} [o.revisao]      aviso de revisão vencida
 * @param {string} [o.dependencias] bloco de dependências de ambiente
 */
function montarContexto(o) {
  const regras = blocoRegras(filtrarRegras(o.skillText), o.caminhoSkill || '(caminho não informado)');
  const focoResumido = resumirAvancos(o.focoText);
  const foco = focoResumido.trim()
    ? limitar(focoResumido.trim(), TETOS.FOCO_MAX_CHARS, 'Foco')
    : '(nenhum foco declarado — sugira /foco <texto> se o Luís disser no que precisa entregar)';

  return `RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do Luís (perfil 2e).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
${foco}
${o.sessoes || ''}${o.revisao || ''}${o.dependencias || ''}

Arquivos de apoio: ${o.root || ''}\\FOCO.md e ${o.root || ''}\\ideias.jsonl (uma ideia por linha)`;
}

module.exports = { TETOS, filtrarRegras, blocoRegras, resumirAvancos, limitar, montarContexto };
