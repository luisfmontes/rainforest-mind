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
 *
 * ORÇAMENTO DE ENTREGA (2026-08-10) — por que este arquivo tem um teto em bytes:
 * o harness limita o que ENTREGA ao modelo por hook. Passando do limite, ele grava
 * o stdout num arquivo, injeta um preview de ~2 KB e **sai com exit 0**, o que é
 * indistinguível de sucesso. Este hook emitia 32 KB e foi cortado a ~2,2 KB em
 * **50 de 50 sessões** desde o primeiro registro: as regras 4 a 17 nunca chegaram
 * a sessão nenhuma — inclusive a 14, que é a regra que mandaria anunciar isto.
 *
 * Medido nos transcripts (`python scripts/medir-injecao.py --entrega`):
 *   - 9.766 B de `additionalContext` entregues inteiros, zero truncados;
 *   - este hook era o ÚNICO emitindo texto cru; todos os outros emitem JSON e
 *     nenhum deles foi truncado.
 * Daí as duas metades do conserto: o adaptador emite JSON (`additionalContext`),
 * e o texto cabe num orçamento com folga sob o maior passe observado.
 */

/** Tetos. Mexer aqui muda o custo de TODA sessão — o número é a política. */
const TETOS = {
  /** Entradas datadas de "Avanços" que ficam residentes na injeção. */
  AVANCOS_RESIDENTES: 3,
  /**
   * Teto do payload inteiro, em BYTES. 8.000 contra 9.766 B observados passando
   * inteiros — ~18% de folga. O limite exato do harness não é documentado; este
   * número é dimensionado para não depender de descobri-lo.
   */
  ORCAMENTO_BYTES: 8000,
  /**
   * Teto e piso do bloco de foco, em BYTES — a mesma unidade do orçamento.
   * Misturar as duas unidades é erro silencioso aqui: em português acentuado
   * 1 char ≈ 1,08 byte, então um teto em chars deixa o payload passar do teto
   * em bytes e a trava dispara sem ninguém entender por quê.
   */
  FOCO_MAX_BYTES: 2600,
  FOCO_MIN_BYTES: 700,
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

/** Início de uma regra numerada: `**7. Tom sênior.** ...` */
const INICIO_REGRA = /\n(?=\*\*\d+\.)/;

/** Linha que separa o núcleo da regra da sua elaboração. */
const MARCA_DETALHE = /^<!--\s*detalhe\s*-->[ \t]*$/m;

/** Seções do FOCO.md que ficam residentes. O resto vira ponteiro. */
const SECOES_RESIDENTES = ['Ativo', 'Compromissos com prazo'];

/** Extrai o bloco de regras do SKILL.md e remove as citações. */
function filtrarRegras(skillText) {
  const bruto = (String(skillText || '').split('## As regras')[1] || '').split('## Comando')[0] || '';
  return bruto.replace(CITACAO, '').replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * Reduz cada regra ao seu NÚCLEO — o texto antes da linha `<!-- detalhe -->`.
 *
 * A elaboração continua no SKILL.md e se carrega sob demanda com `Skill`. A regra
 * cujo detalhe foi deixado de fora ganha `↳` no fim, e o cabeçalho da injeção diz
 * o que a marca significa: sem isso, uma regra pela metade **parece completa**, que
 * é pior que ausente — foi exatamente o que aconteceu com a regra 3 durante 50
 * sessões, cortada no meio da frase por um corte que ninguém anunciava.
 *
 * Regra sem a marca é injetada inteira (é curta o bastante para caber). Isso mantém
 * o arquivo válido enquanto regras novas ainda não foram divididas.
 */
function extrairNucleo(regrasTexto) {
  return String(regrasTexto || '')
    .split(INICIO_REGRA)
    .map((bloco) => {
      const corte = bloco.search(MARCA_DETALHE);
      if (corte === -1) return bloco.trim();
      const nucleo = bloco.slice(0, corte).trim();
      return nucleo ? `${nucleo} ↳` : '';
    })
    .filter(Boolean)
    .join('\n\n');
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

/**
 * Iça a data do avanço mais recente para logo abaixo do cabeçalho da seção.
 *
 * O bloco de foco recebe a sobra do orçamento e é cortado pelo FIM quando não cabe
 * — e os "Avanços" moram no fim da seção Ativo, então eram a primeira coisa a
 * sumir. A data do último avanço não é decoração: a regra 3 avisa quando o foco
 * ativo está há 7+ dias sem avanço, e sem a data essa checagem não tem como rodar.
 * Uma linha no topo custa ~35 B e sobrevive a qualquer corte que preserve o
 * cabeçalho; o histórico completo continua no arquivo.
 */
function iparAvancoRecente(secao) {
  const datas = (String(secao).match(/- (\d{4}-\d{2}-\d{2}):/g) || [])
    .map((s) => s.slice(2, 12))
    .sort();
  if (!datas.length) return secao;
  const cabecalho = secao.match(/^## .+$/m);
  if (!cabecalho) return secao;
  const corte = secao.indexOf(cabecalho[0]) + cabecalho[0].length;
  return `${secao.slice(0, corte)}\nÚltimo avanço datado: ${datas[datas.length - 1]}.${secao.slice(corte)}`;
}

/**
 * Mantém residentes só as seções do FOCO.md contra as quais a regra 3 mede, e
 * nomeia as que ficaram de fora.
 *
 * O critério sai da própria regra 3: o desvio se mede **só contra o foco ativo**, e
 * as frentes e concluídos existem para a troca ser barata, não para disparar aviso.
 * Injetá-los custava o orçamento de toda sessão para responder uma pergunta que
 * ninguém faz na abertura. O ponteiro nomeia o que saiu — omissão anunciada é
 * recuperável, omissão silenciosa vira afirmação errada sobre o que já foi decidido.
 */
function resumirFoco(focoText) {
  const texto = resumirAvancos(String(focoText || '')).trim();
  if (!texto) return '';

  const partes = texto.split(/\n(?=## )/);
  const mantidas = [];
  const omitidas = [];
  for (const parte of partes) {
    const cabecalho = parte.match(/^## (.+)$/m);
    if (!cabecalho || SECOES_RESIDENTES.includes(cabecalho[1].trim())) {
      mantidas.push(iparAvancoRecente(parte.trim()));
    } else {
      omitidas.push(cabecalho[1].trim());
    }
  }
  if (omitidas.length) {
    mantidas.push(`(Seções do FOCO.md omitidas desta injeção: ${omitidas.join(', ')}. ` +
      'Elas continuam no arquivo — **leia o FOCO.md antes de afirmar o que está fora de escopo, ' +
      'em que frente algo mora, ou o que já foi concluído**.)');
  }
  return mantidas.filter(Boolean).join('\n\n');
}

/** Teto duro, com aviso explícito de que houve corte. Nunca corta em silêncio. */
function limitar(texto, max, nomeDoBloco) {
  const s = String(texto || '');
  if (s.length <= max) return s;
  return s.slice(0, max).trimEnd() +
    `\n\n[${nomeDoBloco} truncado no teto de ${max} caracteres — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
}

/** Teto duro em BYTES, com aviso de corte que já cabe dentro do teto. */
function limitarBytes(texto, maxBytes, nomeDoBloco) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= maxBytes) return s;
  const aviso = `\n\n[${nomeDoBloco} truncado no teto de ${maxBytes} bytes — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
  const espaco = Math.max(0, maxBytes - Buffer.byteLength(aviso, 'utf8'));
  return cortarBytes(s, espaco).trimEnd() + aviso;
}

/** Corta em `max` BYTES sem partir um caractere multibyte no meio. */
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
 * Trava de orçamento: falha RUIDOSA quando o payload passa do teto.
 *
 * O aviso vai no TOPO, e a posição é o ponto todo. O corte do harness leva os
 * **primeiros** ~2 KB e descarta o resto — então rodapé não sobrevive a ele, e uma
 * salvaguarda escrita no fim do payload seria mais uma regra que nunca chega. Como
 * o corte próprio já traz o texto para dentro do orçamento, o aviso chega inteiro.
 *
 * Isto é o que faltava em 2026-08-10: o hook escrevia 32 KB, saía com exit 0, e
 * nada em lugar nenhum dizia que 93% do texto não tinha chegado.
 */
function travarOrcamento(payload, orcamento = TETOS.ORCAMENTO_BYTES) {
  const bytes = Buffer.byteLength(payload, 'utf8');
  if (bytes <= orcamento) return payload;

  const aviso = [
    `⚠️ **INJEÇÃO ACIMA DO ORÇAMENTO: ${bytes} B para um teto de ${orcamento} B.**`,
    '',
    'O texto abaixo foi cortado por este hook para caber na entrega do harness —',
    'parte das regras não está aqui. Regra ausente **não está valendo** nesta',
    'sessão: trate como regra bloqueada pelo ambiente (regra 14), diga isto ao Luís',
    'em uma linha, e carregue `Skill(rainforest-mind)` antes de aplicar qualquer',
    'regra. Conserto: reduzir os núcleos no SKILL.md ou revisar o teto aqui.',
    '',
    '---',
    '',
  ].join('\n');

  return aviso + cortarBytes(payload, Math.max(0, orcamento - Buffer.byteLength(aviso, 'utf8')));
}

/**
 * Monta o additionalContext. Recebe texto já lido pelo adaptador.
 *
 * A ordem de alocação importa: as regras têm custo fixo (são o contrato), e o foco
 * recebe **a sobra** do orçamento. O inverso — foco fixo, regras na sobra — é como
 * se chegou nas 50 sessões em que nenhuma regra passou da terceira.
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
  const regras = blocoRegras(extrairNucleo(filtrarRegras(o.skillText)), o.caminhoSkill || '(caminho não informado)');
  const caminho = o.caminhoSkill || `${o.root || ''}\\skills\\rainforest-mind\\SKILL.md`;

  // O imóvel mais caro do payload é o começo: é o único pedaço que sobrevive a um
  // corte. Ele carrega a CONVOCAÇÃO, não a identidade — "quem eu sou" não faz nada
  // acontecer; "carregue a skill antes de aplicar a regra marcada" faz.
  const cabecalho = `RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do Luís (perfil 2e).

**Isto é o NÚCLEO das regras, não o texto completo.** Regra marcada com ↳ tem
elaboração que não está aqui — critérios finos, comandos exatos, incidentes.
**Antes de aplicar uma regra marcada, carregue \`Skill(rainforest-mind)\`**
(${caminho}).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
`;

  const rodape = `${o.sessoes || ''}${o.revisao || ''}${o.dependencias || ''}

Arquivos de apoio: ${o.root || ''}\\FOCO.md e ${o.root || ''}\\ideias.jsonl (uma ideia por linha)`;

  const fixo = Buffer.byteLength(cabecalho + rodape, 'utf8');
  const sobra = TETOS.ORCAMENTO_BYTES - fixo;
  const tetoFoco = Math.min(TETOS.FOCO_MAX_BYTES, Math.max(0, sobra));

  const focoResumido = resumirFoco(o.focoText).trim();
  let foco;
  if (!focoResumido) {
    foco = '(nenhum foco declarado — sugira /foco <texto> se o Luís disser no que precisa entregar)';
  } else if (tetoFoco < TETOS.FOCO_MIN_BYTES) {
    // Abaixo do piso, um excerto é pior que um ponteiro: sobrariam o título e o
    // cabeçalho, e o critério de pronto — que é contra o que a regra 3 mede —
    // ficaria de fora, com o bloco parecendo completo. O piso não vira alocação
    // forçada (isso estouraria o orçamento e faria a trava acusar as regras por um
    // defeito que é do foco); vira aviso.
    foco = `⚠️ O foco não coube nesta injeção (${tetoFoco} B livres, piso ${TETOS.FOCO_MIN_BYTES} B).\n` +
      '**Leia o FOCO.md antes de medir desvio de escopo ou afirmar o que está em andamento** (regra 3).';
  } else {
    foco = limitarBytes(focoResumido, tetoFoco, 'Foco');
  }

  return travarOrcamento(cabecalho + foco + rodape);
}

module.exports = {
  TETOS,
  filtrarRegras,
  extrairNucleo,
  blocoRegras,
  resumirAvancos,
  resumirFoco,
  limitar,
  limitarBytes,
  cortarBytes,
  travarOrcamento,
  montarContexto,
};
