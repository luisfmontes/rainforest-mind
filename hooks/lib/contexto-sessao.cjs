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
  /**
   * Teto do bloco "Avanços", em BYTES.
   *
   * Era contagem (`AVANCOS_RESIDENTES: 3`), calibrada em 2026-08-09 com entradas
   * de ~110 tokens. Em 2026-08-10 as entradas passaram a ter ~1,5 KB cada — o dia
   * rendeu e o registro acompanhou — e as mesmas 3 entradas viraram 2.271 B, mais
   * que o bloco de foco inteiro. Contagem não é teto quando o tamanho do item
   * varia 10x, e o pior é que nada avisa: a unidade do parâmetro (entradas) não é
   * a unidade do problema (bytes), então o número continua parecendo certo.
   */
  AVANCOS_MAX_BYTES: 900,
  /** Marcos AINDA DE PÉ que ficam residentes. Cumprido não entra em nenhum caso. */
  MARCOS_RESIDENTES: 2,
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
   * Teto do bloco de sessões paralelas, em BYTES. É o único bloco do payload que
   * cresce com o USO da máquina e não com o texto que alguém escreveu: em
   * 2026-08-10 o `sessoes.json` tinha 21 janelas vivas em 7 pastas, 1.373 B de
   * linhas — quase o dobro do piso do foco — e foi o que estourou o orçamento.
   * O corte precede a dedução por pasta, então este teto só morde numa máquina
   * com muitas pastas distintas abertas ao mesmo tempo.
   */
  SESSOES_MAX_BYTES: 300,
  /**
   * Quantas pastas o radar LISTA por nome. O resto vira contagem.
   *
   * A regra 17 pergunta duas coisas — "tem sessão paralela?" e "a janela do foco
   * esfriou?" — e as duas se respondem com as pastas mais RECENTES. Listar as oito
   * não responde melhor: em 2026-08-11 o bloco chegou a 691 B com 11 janelas e
   * empurrou os Marcos para fora da injeção; a entrega de sexta parou de chegar na
   * abertura por causa de `repo-de-trabalho` aparecendo três vezes.
   *
   * Contagem no lugar do nome mantém o sinal ("há trabalho paralelo") e devolve o
   * espaço ao foco, que é o que o Luís precisa ler.
   */
  SESSOES_PASTAS_LISTADAS: 3,
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
 * Mantém residentes os avanços mais recentes que cabem num teto de BYTES, e troca o
 * resto por um ponteiro explícito. Nada se perde: o arquivo continua inteiro em disco.
 *
 * Motivo (medido em 2026-08-09): "Avanços" era 42% do FOCO.md, append-only e sem
 * teto. Num projeto de 3 meses ultrapassaria o bloco de regras inteiro. É o mesmo
 * movimento do filtro de citação, agora no FOCO.
 *
 * O teto era em ENTRADAS até 2026-08-10, e a diferença não é cosmética: entrada de
 * avanço não tem tamanho fixo. Três entradas de ~110 tokens custavam ~350 B; três
 * entradas de um dia produtivo custaram 2.271 B, e o parâmetro continuou dizendo
 * "3" o tempo todo. Teto na unidade errada não avisa quando para de valer.
 */
function resumirAvancos(focoText, maxBytes = TETOS.AVANCOS_MAX_BYTES) {
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
  if (Buffer.byteLength(corpo, 'utf8') <= maxBytes) return foco;

  // Do mais recente para o mais antigo, enquanto couber. Pelo menos uma entrada
  // fica sempre: "Avanços:" com ponteiro e nada embaixo esconde a data que a
  // regra 3 usa para ver foco parado, e o iparAvancoRecente depende dela.
  const mantidas = [];
  let usado = 0;
  for (const entrada of [...entradas].reverse()) {
    const custo = Buffer.byteLength(entrada, 'utf8') + 1;
    if (mantidas.length && usado + custo > maxBytes) break;
    mantidas.unshift(entrada);
    usado += custo;
  }

  const ocultas = entradas.length - mantidas.length;
  if (!ocultas) return foco;
  const ponteiro = `- (${ocultas} ${ocultas === 1 ? 'entrada anterior' : 'entradas anteriores'} ` +
    `${ocultas === 1 ? 'foi omitida' : 'foram omitidas'} desta injeção para conter o custo por sessão. ` +
    'Elas continuam no FOCO.md — **leia o arquivo antes de afirmar o que já foi decidido ou feito neste foco**.)';

  return foco.slice(0, corpoInicio) + '\n' + [ponteiro, ...mantidas].join('\n') + cauda;
}

/**
 * Mantém residentes só os marcos que ainda estão de pé, e os PRÓXIMOS.
 *
 * Marco cumprido já cumpriu sua função: a regra 3 mede contra prazo **vencido ou a
 * ≤2 dias**, e nenhum marco com ✅ pode disparar isso. Injetar os cinco custava 641 B
 * — mais que a sobra inteira do bloco de foco — e o efeito medido em 2026-08-10 era
 * o pior possível: o bloco não cabia, saía inteiro, e a sessão subia sem prazo
 * nenhum. Dois marcos de pé custam ~260 B e respondem a pergunta que a regra faz.
 *
 * O cabeçalho do bloco fica sempre: é ele que diz que a data é a REUNIÃO e que a
 * entrega vence antes. Marco sem essa regra de leitura vira prazo errado por 1 dia.
 */
function resumirMarcos(secao, mantidos = TETOS.MARCOS_RESIDENTES) {
  const texto = String(secao);
  const inicio = texto.search(/^Marcos/m);
  if (inicio === -1) return texto;

  const resto = texto.slice(inicio);
  const fimRelativo = resto.search(/\n\n/);
  const bloco = fimRelativo === -1 ? resto : resto.slice(0, fimRelativo);
  const cauda = fimRelativo === -1 ? '' : resto.slice(fimRelativo);

  const partes = bloco.split(/\n(?=- )/);
  const cabecalho = partes.shift();
  const cumpridos = partes.filter((m) => m.includes('✅'));
  const dePe = partes.filter((m) => !m.includes('✅'));
  if (!cumpridos.length && dePe.length <= mantidos) return texto;

  const residentes = dePe.slice(0, mantidos);
  const adiante = dePe.length - residentes.length;
  const nota = [];
  if (adiante) nota.push(`${adiante} marco${adiante > 1 ? 's' : ''} adiante`);
  if (cumpridos.length) nota.push(`${cumpridos.length} já cumprido${cumpridos.length > 1 ? 's' : ''}`);
  const ponteiro = nota.length ? `\n- (${nota.join(' e ')} — estão no FOCO.md.)` : '';

  return texto.slice(0, inicio) + [cabecalho, ...residentes].join('\n') + ponteiro + cauda;
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
  // Sem exigir o `:` colado na data: a entrada real escreve "- 2026-08-10 (tarde):"
  // e a versão anterior do padrão simplesmente não a via — some a linha inteira, e
  // com ela a checagem de foco parado da regra 3.
  const datas = (String(secao).match(/(?:^|\n)- (\d{4}-\d{2}-\d{2})/g) || [])
    .map((s) => s.trim().slice(2, 12))
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
      mantidas.push(iparAvancoRecente(resumirMarcos(parte.trim())));
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

/**
 * Ordem de prioridade dos blocos do foco. O primeiro padrão que casa manda.
 *
 * Existe porque o corte do foco era por POSIÇÃO: o bloco recebia a sobra do
 * orçamento e era truncado de cima para baixo. Medido em 2026-08-10, isso parava
 * no meio do "Critério de pronto" — ou seja, **os marcos e prazos não chegavam a
 * sessão nenhuma**, que é exatamente contra o que a regra 3 mede. Cortar por
 * importância entrega prazo e marcos dentro dos mesmos bytes.
 *
 * Parágrafo que não casa com padrão nenhum cai no fim da fila de propósito: é o
 * lugar da prosa explicativa do arquivo, que documenta o formato do FOCO.md e não
 * diz nada sobre o que o Luís está entregando.
 */
const PRIORIDADE_FOCO = [
  { rank: 0, teste: (b) => /^#{1,2} /.test(b) || /^Último avanço datado:/.test(b) },
  { rank: 1, teste: (b) => /^\*\*/.test(b) },
  // Lista solta abaixo de um cabeçalho residente: sai junto com ele ou não sai.
  // Cabeçalho sem o conteúdo dele ("## Compromissos com prazo" e nada embaixo) lê
  // como "não há compromisso", que é afirmação — e pode ser falsa.
  // MARCOS TEM RANK PRÓPRIO, acima de qualquer outra lista. Prazo é o que mais
  // dói perder, e até 2026-08-11 ele empatava em rank 2 com toda lista solta: o
  // preenchimento é guloso, levou o `- (nenhum além do foco ativo)` de 30 B e
  // deixou os Marcos — com a entrega de sexta — fora da injeção. Empate resolvido
  // por ordem no arquivo não é prioridade, é acaso.
  { rank: 2, teste: (b) => /^Marcos/.test(b) },
  { rank: 3, teste: (b) => /^- /.test(b) },
  { rank: 4, teste: (b) => /^Avanços:/.test(b) || /^\(Seções do FOCO\.md omitidas/.test(b) },
];

/**
 * Nome curto do bloco, para o ponteiro de omissão. Curto de propósito: o ponteiro
 * disputa bytes com o conteúdo que ele está anunciando, e um ponteiro gordo tira
 * do foco justamente o espaço que faria o bloco caber.
 */
function nomeDoBloco(bloco) {
  const primeira = bloco.split('\n')[0].replace(/[*#`]/g, '').split(/[—(:]/)[0].trim();
  return primeira.length > 24 ? `${primeira.slice(0, 24)}…` : primeira;
}

/**
 * Encaixa o foco no teto tirando os blocos MENOS importantes primeiro, e nomeando
 * o que saiu. A ordem original é preservada na saída — prioridade decide quem
 * fica, não onde fica.
 *
 * Só cai no truncamento linear quando nem o bloco de maior prioridade cabe: aí o
 * problema é de orçamento, não de escolha, e o aviso de corte do `limitarBytes` é
 * a informação certa.
 */
function priorizarFoco(focoResumido, teto) {
  const texto = String(focoResumido || '').trim();
  if (!texto || Buffer.byteLength(texto, 'utf8') <= teto) return texto;

  const blocos = texto.split(/\n{2,}/).map((b, ordem) => {
    const t = b.trim();
    const regra = PRIORIDADE_FOCO.find((p) => p.teste(t));
    return { texto: t, ordem, rank: regra ? regra.rank : 9 };
  });

  const fila = [...blocos].sort((a, b) => a.rank - b.rank || a.ordem - b.ordem);
  const mantidos = [];
  const fora = [];
  let usado = 0;
  // Reserva para o ponteiro de omissão: ele PRECISA caber, senão o corte vira
  // silencioso — a falha que este arquivo inteiro existe para não cometer.
  const reserva = 120;
  for (const bloco of fila) {
    const custo = Buffer.byteLength(bloco.texto, 'utf8') + 2;
    if (usado + custo <= teto - reserva) {
      mantidos.push(bloco);
      usado += custo;
    } else {
      fora.push(bloco);
    }
  }

  if (!mantidos.length) return limitarBytes(texto, teto, 'Foco');

  // A reserva é estimativa: o ponteiro só tem tamanho depois de saber QUEM saiu, e
  // quem sai depende do espaço. Em vez de adivinhar, monta o texto final e devolve
  // blocos até caber de verdade — a versão que confiava na estimativa passou 25 B
  // do teto e fez a trava de orçamento cortar o próprio ponteiro.
  const montar = () => {
    const corpo = [...mantidos].sort((a, b) => a.ordem - b.ordem).map((b) => b.texto).join('\n\n');
    if (!fora.length) return corpo;
    const nomes = fora.map((b) => nomeDoBloco(b.texto)).filter(Boolean);
    const mostrados = nomes.slice(0, 3).join('; ') + (nomes.length > 3 ? `; +${nomes.length - 3}` : '');
    return `${corpo}\n\n(Fora desta injeção por espaço: ${mostrados}. ` +
      '**Leia o FOCO.md** antes de afirmar prazo, marco ou avanço.)';
  };

  let saida = montar();
  while (Buffer.byteLength(saida, 'utf8') > teto && mantidos.length > 1) {
    // Devolve sempre o de MENOR prioridade entre os mantidos.
    mantidos.sort((a, b) => a.rank - b.rank || a.ordem - b.ordem);
    fora.push(mantidos.pop());
    saida = montar();
  }
  return Buffer.byteLength(saida, 'utf8') > teto ? limitarBytes(saida, teto, 'Foco') : saida;
}

/**
 * Descarta do estado as sessões cujo processo morreu, e devolve só as vivas.
 *
 * O `sessoes.json` não tinha noção de sessão ENCERRADA: guardava `cwd`,
 * `prompt_ts` e `stop_ts`, e fechar a janela não gerava evento nenhum. A última
 * linha de uma sessão morta ficava idêntica à de uma sessão viva e ociosa. Medido
 * em 2026-08-10: 3 `claude.exe` rodando de verdade contra 18 entradas contadas
 * como vivas na injeção — 15 fantasmas, e foi o que estourou o orçamento.
 *
 * O `SessionEnd` cobre o encerramento limpo; esta varredura cobre o resto (janela
 * fechada no X, crash, reboot), onde evento nenhum chega. Entrada sem `pid` é de
 * antes desta mudança e sobrevive pela idade — ela some sozinha em 24h.
 *
 * @param {object} state          conteúdo do sessoes.json
 * @param {number} agora          timestamp de referência
 * @param {number} janelaMs       idade máxima para a entrada contar
 * @param {(pid:number)=>boolean} vivo  predicado de vida (injetável no teste)
 */
/**
 * Sessão de SUBAGENTE, não janela do Luís.
 *
 * Subagente despachado com `isolation: "worktree"` abre sessão própria, com cwd
 * dentro de `.claude/worktrees/`. Ela entrava no radar como se fosse mais uma
 * janela paralela dele — e a regra 17 mede o paralelismo DELE, não o meu rastro.
 *
 * Dois danos, os dois medidos em 2026-08-11: o radar mentia sobre quantas
 * frentes ele tinha abertas, e o bloco de sessões disputa orçamento com o foco —
 * naquele dia a injeção chegou a 7992 B de 8000, com o radar em 676 B, e o prazo
 * mais próximo já tinha caído fora da injeção uma vez. Quanto mais eu despacho,
 * menos foco chegava.
 */
function ehWorktreeDeAgente(cwd) {
  if (!cwd) return false;
  return /[\\/]\.claude[\\/]worktrees([\\/]|$)/.test(cwd);
}

function sessoesVivas(state, agora, janelaMs, vivo) {
  const estaVivo = typeof vivo === 'function' ? vivo : processoVivo;
  return Object.entries(state || {})
    .filter(([, s]) => s && agora - Math.max(s.prompt_ts || 0, s.stop_ts || 0) < janelaMs)
    .filter(([, s]) => !s.pid || estaVivo(s.pid))
    .filter(([, s]) => !ehWorktreeDeAgente(s.cwd));
}

/** Existência de processo por PID. O sinal 0 não mata nada — só pergunta. */
function processoVivo(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // EPERM = existe e é de outro usuário. Só ESRCH prova que morreu.
    return e && e.code === 'EPERM';
  }
}

/**
 * Reduz o radar multi-janela a UMA linha por pasta, e cabe num teto.
 *
 * A regra 17 pergunta duas coisas por PASTA — "tem sessão paralela aqui?" e "a
 * janela do foco esfriou?" —, e as duas se respondem com a janela mais recente
 * daquela pasta. Nove linhas da mesma pasta em ordem qualquer não respondem
 * melhor: custam 9x e ainda enterram as outras pastas no fim do bloco, que é
 * exatamente onde o corte do orçamento cai.
 *
 * Foi este bloco que estourou a injeção de 2026-08-10 (8.306 B para um teto de
 * 8.000): 21 janelas vivas, 7 pastas. Ele é o único pedaço do payload que cresce
 * com quantas janelas o Luís abriu no dia — os outros crescem com texto escrito,
 * que alguém revisa; este ninguém revisa.
 *
 * @param {Array<{cwd?: string, trabalhando?: boolean, minutos?: number}>} entradas
 * @param {string} ociosidade minutos de ociosidade máxima do foco ativo
 */
function resumirSessoes(entradas, ociosidade, teto = TETOS.SESSOES_MAX_BYTES) {
  const lista = Array.isArray(entradas) ? entradas.filter(Boolean) : [];
  if (!lista.length) return '';

  const porPasta = new Map();
  for (const e of lista) {
    const pasta = e.cwd || '(pasta desconhecida)';
    const min = Number.isFinite(e.minutos) ? e.minutos : Infinity;
    const atual = porPasta.get(pasta);
    // Mais recente = menos minutos desde o último evento.
    if (!atual || min < atual.minutos) porPasta.set(pasta, { pasta, minutos: min, trabalhando: !!e.trabalhando, janelas: (atual ? atual.janelas : 0) + 1 });
    else porPasta.set(pasta, { ...atual, janelas: atual.janelas + 1 });
  }

  const linhas = [...porPasta.values()]
    .sort((a, b) => a.minutos - b.minutos)
    .map((p) => {
      const estado = p.trabalhando
        ? `Claude trabalhando (turno em curso há ${p.minutos} min)`
        : `esperando o Luís há ${p.minutos} min`;
      const extras = p.janelas > 1 ? ` [${p.janelas} janelas nesta pasta; estado da mais recente]` : '';
      return `- ${p.pasta} — ${estado}${extras}`;
    });

  // Corte em DOIS passos, e o primeiro é por quantidade, não por bytes.
  //
  // Só o teto de bytes deixava o bloco crescer até 691 B com 11 janelas — e o que
  // ele empurrava para fora era o foco, com os Marcos e o prazo mais próximo
  // dentro. Listar pasta fria não responde nenhuma das duas perguntas da regra 17
  // e custa exatamente o espaço de que o foco precisa.
  const listadas = linhas.slice(0, TETOS.SESSOES_PASTAS_LISTADAS);
  // Reserva para o ponteiro de omissão, quando ele for existir. Sem ela o teto
  // mente: as linhas cabiam em 300 B, o ponteiro entrava DEPOIS e o bloco saía
  // com 351. Parâmetro que não governa o número que ele nomeia é a mesma família
  // do teto em entradas que virou 2.271 B — o problema não é o valor, é a conta.
  const reserva = linhas.length > listadas.length ? 80 : 0;
  const cabidas = [];
  let usado = 0;
  for (const linha of listadas) {
    const custo = Buffer.byteLength(linha, 'utf8') + 1;
    if (usado + custo > teto - reserva) break;
    cabidas.push(linha);
    usado += custo;
  }
  // Pasta omitida em silêncio vira "não havia sessão lá", que é afirmação errada.
  // O que sai vira NÚMERO — o sinal "há trabalho paralelo" sobrevive ao corte.
  const fora = linhas.length - cabidas.length;
  if (fora) {
    const janelasFora = [...porPasta.values()]
      .sort((a, b) => a.minutos - b.minutos)
      .slice(cabidas.length)
      .reduce((n, p) => n + p.janelas, 0);
    cabidas.push(`- (+${janelasFora} janela(s) em ${fora} outra(s) pasta(s) — nomes no \`sessoes.json\`.)`);
  }

  return `\n## Outras sessões recentes (radar multi-janela, regra 17)\n${cabidas.join('\n')}\n` +
    `Ociosidade máxima deste foco: ${ociosidade} min.\n`;
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
    'O texto abaixo foi cortado no FIM por este hook para caber na entrega do',
    'harness. O corte come de trás para frente: primeiro as dependências de',
    'ambiente e o radar de janelas, depois o foco, e só num estouro grande as',
    'últimas regras. **Nada do que foi cortado está valendo nesta sessão** — trate',
    'como bloqueio de ambiente (regra 14), diga isto ao Luís em uma linha, carregue',
    '`Skill(rainforest-mind)` antes de aplicar regra e leia o FOCO.md antes de medir',
    'escopo. Conserto: encurtar os núcleos no SKILL.md, apertar os tetos do rodapé',
    '(`SESSOES_MAX_BYTES`) ou revisar o orçamento aqui.',
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

  // A separação é do rodapé, não dos blocos que ele recebe: quando não havia
  // sessão paralela, o `## Dependências` colava na última linha do foco e virava
  // continuação do texto dele. Normalizar aqui vale para qualquer combinação de
  // blocos presentes ou ausentes.
  const rodape = '\n\n' + [o.sessoes, o.revisao, o.dependencias]
    .filter(Boolean)
    .map((bloco) => String(bloco).replace(/^\n+/, '').trimEnd())
    .concat(`Arquivos de apoio: ${o.root || ''}\\FOCO.md e ${o.root || ''}\\ideias.jsonl (uma ideia por linha)`)
    .join('\n\n');

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
    // Por prioridade, não por posição: cortar de cima para baixo deixava marcos e
    // prazos de fora de toda sessão enquanto a prosa do topo sobrevivia inteira.
    foco = priorizarFoco(focoResumido, tetoFoco);
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
  priorizarFoco,
  sessoesVivas,
  ehWorktreeDeAgente,
  processoVivo,
  resumirSessoes,
  travarOrcamento,
  montarContexto,
};
