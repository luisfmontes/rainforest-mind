export const meta = {
  name: 'divergir-frames',
  description:
    'Seis frames isolados em paralelo, um por lente ortogonal, mais um crítico que nasce zerado — abre o espaço de decisão antes de convergir, sem decidir por conta própria',
  whenToUse:
    'Invocado pela skill `divergir` quando o espaço de decisão é largo e a primeira ideia já está ancorando a conversa. Requer args: o enunciado do problema em texto, como string crua ou {enunciado: "..."}. Devolve shortlist, escolha não-óbvia, se ela bate com a primeira ideia da rodada, a refutação do caminho sedutor-mas-quebrado, e as ideias cruas de cada frame — quem monta a decisão numerada para o usuário é a sessão que chamou, nunca o grafo.',
  phases: [
    { title: 'Divergir', detail: 'seis frames isolados em paralelo, mesmo enunciado, contexto zero entre si' },
    { title: 'Focar', detail: 'um crítico que nasce zerado agrupa, corta e refuta, sem saber de que frame veio cada ideia' },
  ],
}

// `args` pode chegar como o objeto já interpretado, como uma string JSON
// bruta, ou como o enunciado em texto puro (nem sempre JSON válido) —
// normaliza os três casos, seguindo o padrão do exemplo oficial
// (code-modernization/portfolio-assess.js): tenta JSON.parse; se falhar,
// o valor original (texto puro) segue adiante como está.
let ARGS = args
if (typeof ARGS === 'string') {
  try {
    ARGS = JSON.parse(ARGS)
  } catch (e) {
    // não era JSON — o próprio texto é o enunciado, mantém como string
  }
}
const enunciado = typeof ARGS === 'string' ? ARGS : ARGS && typeof ARGS.enunciado === 'string' ? ARGS.enunciado : null
if (!enunciado || !enunciado.trim()) {
  throw new Error(
    'divergir-frames workflow requires args: o enunciado do problema em texto — string crua ou {enunciado: "..."}',
  )
}

// Seis frames fixos (D2 do design) — ortogonais, cada um com justificativa
// própria na SKILL.md. A pergunta de cada um é copiada literalmente da
// tabela de lá.
const FRAMES = [
  {
    nome: 'restricao-dura',
    pergunta:
      'e se o recurso mais caro (tempo, memória, atenção do usuário, dinheiro, tokens) fosse 10x menor?',
  },
  {
    nome: 'inversao',
    pergunta:
      'e se a responsabilidade morasse do outro lado da fronteira — no chamador, no dado, no usuário, no sistema operacional?',
  },
  {
    nome: 'incentivo',
    pergunta:
      'quem ganha e quem perde com cada caminho, e que comportamento o desenho premia sem querer?',
  },
  {
    nome: 'ja-existe',
    pergunta:
      'que peça pronta (deste repo, do host, do SO, do protocolo) resolve isso sem código novo? "Não construa" é resposta legítima',
  },
  {
    nome: 'modo-de-falha',
    pergunta:
      'comece pelo desastre e volte: que desenho torna aquele desastre impossível em vez de improvável?',
  },
  {
    nome: 'premissa',
    pergunta: 'o problema como foi enunciado está certo? Ataque o pedido, não a solução',
  },
]

// Bloco comum, byte-a-byte idêntico nos seis prompts — só a pergunta do
// frame, anexada depois deste bloco, muda entre eles. É o que garante que
// o isolamento (regra da skill: "os seis recebem exatamente o mesmo
// enunciado") não dependa de eu lembrar de repetir o texto igual seis
// vezes: é o mesmo texto, montado uma vez só.
const INSTRUCOES_COMUNS = `Você é um dos seis frames isolados da skill \`divergir\`. Você não vê os outros cinco frames, e nenhum deles vê você — cada um pensa sozinho, sem se ancorar na resposta de nenhum outro. Não mencione nem presuma a existência de outros frames na sua resposta.

Enunciado do problema:
${enunciado}

Sua tarefa: gerar ideias distintas para este problema, olhando estritamente pela lente da pergunta abaixo — não pela lente genérica de "melhores práticas" e não pelas outras cinco lentes que você não conhece. Devolva no mínimo DUAS ideias, cada uma com o porquê ela resolve o problema sob esta lente. Frame que devolve uma ideia só opinou, não divergiu.

Não decida entre as ideias, não as compare com nenhuma outra lente e não escreva código — isso é trabalho de uma fase posterior, que você não integra.`

const promptDoFrame = frame => `${INSTRUCOES_COMUNS}

Sua pergunta: ${frame.pergunta}`

const IDEIAS_SCHEMA = {
  type: 'object',
  required: ['ideias'],
  properties: {
    ideias: {
      type: 'array',
      minItems: 2,
      items: {
        type: 'object',
        required: ['ideia', 'porque'],
        properties: {
          ideia: { type: 'string', description: 'A ideia, em uma ou duas frases' },
          porque: { type: 'string', description: 'Por que ela resolve o problema sob esta lente' },
        },
      },
    },
  },
}

log(`Divergindo em 6 frames isolados sobre: ${enunciado.slice(0, 160)}${enunciado.length > 160 ? '…' : ''}`)

const resultadosFrames = await parallel(
  FRAMES.map(frame => () =>
    agent(promptDoFrame(frame), {
      agentType: 'rainforest-mind:planejador',
      label: `frame:${frame.nome}`,
      phase: 'Divergir',
      schema: IDEIAS_SCHEMA,
    }).then(r => (r && Array.isArray(r.ideias) ? { frame: frame.nome, ideias: r.ideias } : null)),
  ),
)

const framesComResposta = resultadosFrames.filter(Boolean)
const framesFalhos = FRAMES.filter(f => !framesComResposta.some(r => r.frame === f.nome))
if (framesFalhos.length) {
  log(`Frame(s) sem resposta (agente pulou ou falhou): ${framesFalhos.map(f => f.nome).join(', ')} — a rodada segue só com os que responderam`)
}
if (framesComResposta.length === 0) {
  throw new Error('divergir-frames: nenhum dos seis frames respondeu — sem ideias não há o que levar ao crítico')
}

// Ideias cruas, com origem — vão no retorno final para quem chamou (ex.:
// gravação da rodada), mas NUNCA no prompt do crítico nesta forma.
const ideiasCruas = framesComResposta.flatMap(r => r.ideias.map(i => ({ frame: r.frame, ideia: i.ideia, porque: i.porque })))

// A primeira ideia da rodada, na ordem determinística de FRAMES (antes de
// qualquer embaralhamento) — é a referência de ancoragem que o crítico
// precisa para responder "bate_com_a_primeira_ideia", sem que isso revele
// de que frame ela veio.
const primeiraIdeiaDaRodada = ideiasCruas[0]

// Embaralhamento determinístico por intercalação de índice entre frames —
// nunca por sorteio (a função de número aleatório do runtime lança exceção
// aqui, e mesmo se não lançasse, a skill não pede aleatoriedade, pede que a
// ordem de chegada não reflita a ordem de geração). O campo de origem
// (`frame`) é descartado aqui: o crítico recebe só {ideia, porque}.
const listasPorFrame = framesComResposta.map(r => r.ideias)
const maiorLista = listasPorFrame.reduce((max, l) => Math.max(max, l.length), 0)
const ideiasEmbaralhadas = []
for (let i = 0; i < maiorLista; i++) {
  for (const lista of listasPorFrame) {
    if (lista[i]) ideiasEmbaralhadas.push({ ideia: lista[i].ideia, porque: lista[i].porque })
  }
}

const listaNumerada = ideiasEmbaralhadas.map((it, idx) => `${idx + 1}. ${it.ideia} — ${it.porque}`).join('\n')

const CRITICO_SCHEMA = {
  type: 'object',
  required: ['shortlist', 'escolha_nao_obvia', 'bate_com_a_primeira_ideia', 'refutacao'],
  properties: {
    shortlist: {
      type: 'array',
      items: {
        type: 'object',
        required: ['ideia', 'criterio_de_corte'],
        properties: {
          ideia: { type: 'string', description: 'Ideias que são a mesma coisa com nome diferente já colapsadas numa só' },
          criterio_de_corte: { type: 'string', description: 'Por que esta sobreviveu ao corte' },
        },
      },
    },
    escolha_nao_obvia: {
      type: 'string',
      description: 'O caminho que sobreviveu e que ninguém teria proposto de primeira, com o porquê',
    },
    bate_com_a_primeira_ideia: {
      type: 'boolean',
      description: 'Verdadeiro se a escolha não-óbvia é a mesma ideia apontada como "primeira ideia desta rodada" no prompt',
    },
    refutacao: {
      type: 'string',
      description:
        'Refutação do caminho sedutor-mas-quebrado: texto livre com cenário concreto de falha (entrada, estado, sequência) — "eu faria diferente" não conta como refutação',
    },
  },
}

const promptCritico = `Você é o crítico da skill \`divergir\`, e nasce zerado: não gerou nenhuma das ideias abaixo, não integrou nenhum dos seis frames que as produziram, e não sabe de que frame veio cada uma — a origem foi removida de propósito, e a ordem abaixo foi embaralhada para não vazar a ordem de geração.

Enunciado do problema:
${enunciado}

Ideias produzidas por seis frames isolados, sem indicação de origem, em ordem embaralhada:
${listaNumerada}

Para referência (sem revelar de que frame veio): a primeira ideia produzida nesta rodada, antes do embaralhamento, foi "${primeiraIdeiaDaRodada.ideia}".

Sua tarefa:
1. Agrupamento — colapse em uma só entrada da shortlist as ideias que são a mesma coisa com nome diferente.
2. Shortlist com o critério explícito de corte para cada entrada que sobreviver.
3. A escolha não-óbvia — dentre a shortlist, o caminho que sobreviveu e que ninguém teria proposto de primeira, com o porquê.
4. Diga em bate_com_a_primeira_ideia se a sua escolha não-óbvia é a mesma ideia apontada acima como "primeira ideia produzida nesta rodada". Se for, isso é o resultado mais valioso da rodada — a ancoragem não custou nada desta vez — e não um problema a esconder.
5. Refutação do sedutor-mas-quebrado — a ideia (dentre todas as listadas, não só a shortlist) que soa ótima e falha na primeira semana, com cenário concreto de falha: entrada, estado, sequência. "Eu faria diferente" não refuta nada.

Você não decide pelo usuário e não escreve código — isso não é seu trabalho.`

const critico = await agent(promptCritico, {
  agentType: 'rainforest-mind:revisor',
  label: 'critico',
  phase: 'Focar',
  schema: CRITICO_SCHEMA,
})

if (!critico) {
  throw new Error('divergir-frames: o crítico não respondeu — sem ele não há shortlist, escolha não-óbvia nem refutação para devolver')
}

// Retorno: as quatro chaves do crítico mais as ideias cruas (com origem),
// para quem chamou decidir e, se quiser, gravar a rodada. O grafo não
// decide e não grava (D7/D9 do design) — isso é da sessão que invocou.
return {
  shortlist: critico.shortlist,
  escolha_nao_obvia: critico.escolha_nao_obvia,
  bate_com_a_primeira_ideia: critico.bate_com_a_primeira_ideia,
  refutacao: critico.refutacao,
  ideias: ideiasCruas,
}
