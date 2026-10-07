// A barra de sessao e o pane /painel daqui sao adaptados do terminal-desk 0.2.1 (licenca
// MIT, titular ClariSortAi); texto da licenca e origem em NOTICE, na raiz do plugin.
// Entrada do mod: a abertura (register.ts, sem mudanca) mais a barra de sessao acima do
// prompt (estado, tokens, custo, contexto, cache, subagentes, erros e o relogio) e o
// comando /painel. A logica pura mora em ./painel-puro.mjs e ./relogio-puro.mjs; aqui so se
// liga os eventos. O engine recusa `$` passado como argumento a qualquer funcao do arquivo,
// entao `buscar` e `medir` recebem so valores e lambdas montadas no ponto de chamada de
// cada hook. Toda leitura do mundo tem falha aberta: so a peca afetada some.
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'
import type {
  RainforestMindFaixaDados,
  RainforestMindPainelAgente,
  RainforestMindPainelDeixado,
  RainforestMindPainelDeixadoOrigem,
  RainforestMindPainelFatia,
  RainforestMindPainelMapa,
  RainforestMindPainelStats,
  RainforestMindRelogioJornada,
  RainforestMindRelogioSessoes,
} from '../types'
import { register as abertura } from './register.ts'
import { CHECAR_MIN_FERRAMENTAS, deferimentos, lerResolvidosChecker, lerRespostaChecker, marcadoresEmArquivo, montarPromptChecker, perguntaDecisao, rascunhoFazAgora } from './deixado-puro.mjs'
import { largura, cortar, semControle } from './faixa-puro.mjs'
import { ESCRITORAS, escritaDe, mapaVazio, registrar } from './mapa-puro.mjs'
import { cacheDe, compacto, dinheiro, fatias, figurasDaBarra, restante, ritmoPorMinuto, rotuloSubagente } from './painel-puro.mjs'
import { avaliarRelogio, linhaRelogio, notaJornada } from './relogio-puro.mjs'

type Fatia = RainforestMindPainelFatia

const MIN = 60_000
const HORA = 60 * MIN
const MAX_AGENTES = 12

const VAZIO: RainforestMindPainelStats = {
  turnos: 0,
  ferramentas: 0,
  falhas: 0,
  tokensNovos: 0,
  tokensCacheLido: 0,
  tokensCacheEscrito: 0,
  tokensSaida: 0,
  custoUsd: null,
  ctxPct: null,
  ctxTokens: null,
  ctxJanela: null,
  fatias: [],
  carimbos: [],
  agentes: [],
  ultimaRequisicaoMs: 0,
  modelo: null,
  ttlMs: HORA,
  medirDeNovo: false,
}

const faixaDados = atom({ plugin: 'rainforest-mind', key: 'faixaDados' } as const, null as RainforestMindFaixaDados | null)
const painelStats = atom({ plugin: 'rainforest-mind', key: 'painelStats' } as const, VAZIO)
const painelOculto = atom({ plugin: 'rainforest-mind', key: 'painelOculto' } as const, false)
const painelMapa = atom({ plugin: 'rainforest-mind', key: 'painelMapa' } as const, mapaVazio() as RainforestMindPainelMapa)
const relogioJornada = atom({ plugin: 'rainforest-mind', key: 'relogioJornada' } as const, null as RainforestMindRelogioJornada | null)
const relogioSessoes = atom({ plugin: 'rainforest-mind', key: 'relogioSessoes' } as const, null as RainforestMindRelogioSessoes | null)
const relogioNotaPendente = atom({ plugin: 'rainforest-mind', key: 'relogioNotaPendente' } as const, null as string | null)
const relogioNotaEntregue = atom({ plugin: 'rainforest-mind', key: 'relogioNotaEntregue' } as const, null as string | null)

// `PARADO` = nenhum checker em voo. O literal que desce o aviso mora so no `finally` da checagem,
// a linha unica que a prova de mutacao troca.
const PARADO = false
const DEIXADO_VAZIO: RainforestMindPainelDeixado = { itens: [], proximo: 1, checando: PARADO, checar: true, pedido: '', ferramentas: [] }
const painelDeixado = atom({ plugin: 'rainforest-mind', key: 'painelDeixado' } as const, DEIXADO_VAZIO)

const deixadoInteiro = (d: RainforestMindPainelDeixado | null | undefined): RainforestMindPainelDeixado => ({ ...DEIXADO_VAZIO, ...(d ?? {}) })

const inteiro = (s: RainforestMindPainelStats | null | undefined): RainforestMindPainelStats => ({ ...VAZIO, ...(s ?? {}) })

type Io = {
  rodar: (argv: string[], init: { cwd: string; env: Record<string, string>; timeoutMs: number }) => Promise<{ exitCode: number; stdout: string }>
  cwd: () => Promise<string>
  raiz: string
}

// Falha aberta: exit != 0, JSON invalido, timeout ou excecao devolvem null (apaga so os dados).
async function buscar(io: Io): Promise<RainforestMindFaixaDados | null> {
  try {
    const cwd = await io.cwd()
    const r = await io.rodar(
      ['node', `${io.raiz}/scripts/faixa-dados.cjs`, '--cwd', cwd],
      { cwd: io.raiz, env: { CLAUDE_PROJECT_DIR: cwd }, timeoutMs: 5000 },
    )
    return r.exitCode === 0 ? JSON.parse(r.stdout) : null
  } catch {
    return null
  }
}

type IoRodar = { rodar: Io['rodar']; raiz: string }

type IoAnotar = {
  gravar: (f: (d: RainforestMindPainelDeixado) => RainforestMindPainelDeixado) => Promise<unknown>
  avisar: (texto: string) => void
}

// Itens novos do "deixado para depois": o mesmo texto nao entra duas vezes, guarda os 40 mais
// recentes e avisa com um toast so quando entrou algo. Recebe so valores e lambdas (o engine
// recusa `$` como argumento).
async function anotar(io: IoAnotar, achados: string[], origem: RainforestMindPainelDeixadoOrigem): Promise<void> {
  if (achados.length === 0) return
  let novos: string[] = []
  await io.gravar(raw => {
    const d = deixadoInteiro(raw)
    novos = [...new Set(achados)].filter(texto => !d.itens.some(i => i.texto === texto))
    if (novos.length === 0) return d
    return {
      ...d,
      proximo: d.proximo + novos.length,
      itens: [...d.itens, ...novos.map((texto, i) => ({ id: d.proximo + i, texto, origem, estado: 'aberto' as const }))].slice(-40),
    }
  })
  if (novos.length > 0) io.avisar(`Deixado para depois: ${(novos[0] ?? '').slice(0, 80)}`)
}

// Falha aberta: exit != 0 (jornada.cjs exit 2 = sem linha), JSON invalido, timeout ou excecao
// devolvem null (apaga so a leitura).
async function rodarJson(io: IoRodar, argv: string[], timeoutMs: number, env: Record<string, string>): Promise<unknown> {
  try {
    const r = await io.rodar(argv, { cwd: io.raiz, env, timeoutMs })
    return r.exitCode === 0 ? JSON.parse(r.stdout) : null
  } catch {
    return null
  }
}

function jornadaDe(bruto: any): RainforestMindRelogioJornada | null {
  const ultimo_ms = bruto ? Date.parse(bruto.ultimo) : NaN
  if (!bruto || typeof bruto.efetiva_min !== 'number' || !Number.isFinite(ultimo_ms)) return null
  return { efetiva_min: bruto.efetiva_min, ultimo_ms }
}

function sessoesDe(bruto: any): RainforestMindRelogioSessoes | null {
  if (!bruto || typeof bruto.ociosidade_min !== 'number' || !Array.isArray(bruto.janelas)) return null
  return { ociosidade_min: bruto.ociosidade_min, janelas: bruto.janelas }
}

// Linha do relogio para a barra; qualquer falha apaga so o relogio.
function linhaDoRelogio(jornada: RainforestMindRelogioJornada | null, sessoes: RainforestMindRelogioSessoes | null, agora: number): string | null {
  try {
    return linhaRelogio(avaliarRelogio({ jornada, sessoes, agora })) as string | null
  } catch {
    return null
  }
}

type IoMedir = {
  usage: () => Promise<any>
  gravar: (f: (s: RainforestMindPainelStats) => RainforestMindPainelStats) => Promise<unknown>
  log: (texto: string) => void
}

// Contexto e custo pela estimativa local (`breakdown: 'summary'`; `full` chama a API de
// contagem a cada turno). Falha aberta: o contexto some da barra, o resto fica.
async function medir(io: IoMedir): Promise<void> {
  let uso: any
  try {
    uso = await io.usage()
  } catch (err) {
    try {
      io.log(`painel: contexto: ${String(err)}`)
    } catch {
      // sem log, sem problema
    }
    try {
      await io.gravar(raw => ({ ...inteiro(raw), ctxPct: null, ctxTokens: null, ctxJanela: null, fatias: [], medirDeNovo: false }))
    } catch {
      // a medicao nunca quebra nada
    }
    return
  }
  try {
    const contexto = uso?.context ?? {}
    const detalhe = contexto.breakdown
    const fatias = (Array.isArray(detalhe?.categories) ? detalhe.categories : [])
      .filter((c: any) => c && typeof c.tokens === 'number' && c.tokens > 0)
      .map((c: any) => ({ nome: String(c.name), tokens: c.tokens as number, tipo: String(c.kind) }))
    const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
    await io.gravar(raw => {
      const s = inteiro(raw)
      return {
        ...s,
        custoUsd: num(uso?.cost?.usd) ?? s.custoUsd,
        ctxPct: num(detalhe?.percentage) ?? num(contexto.percent),
        ctxTokens: num(contexto.tokens) ?? num(detalhe?.totalTokens),
        ctxJanela: num(detalhe?.rawMaxTokens) ?? num(contexto.window),
        fatias,
        medirDeNovo: false,
      }
    })
  } catch {
    // a medicao nunca quebra nada
  }
}

// Subagentes: a linha de um agente nunca visto comeca em branco; acima do teto saem os
// mais antigos ja encerrados (um em andamento nunca sai).
function comAgente(agentes: RainforestMindPainelAgente[], id: string, at: number, mudar: (a: RainforestMindPainelAgente) => RainforestMindPainelAgente): RainforestMindPainelAgente[] {
  const conhecido: RainforestMindPainelAgente = agentes.find(a => a.id === id) ?? {
    id,
    rotulo: `agente ${id.slice(0, 6)}`,
    tipo: 'subagente',
    modelo: null,
    iniciadoEm: at,
    fimEm: null,
    vistoEm: at,
    criadoAqui: false,
    ferramentas: 0,
    tokensLidos: 0,
    tokensSaida: 0,
    falhou: false,
  }
  const linhas = [...agentes.filter(a => a.id !== id), { ...mudar(conhecido), vistoEm: at }]
  const sobra = linhas.filter(a => a.fimEm !== null).slice(0, Math.max(0, linhas.length - MAX_AGENTES))
  return linhas.filter(a => !sobra.includes(a))
}

// Um agente que ninguem viu comecar nesta carga do mod pode nunca avisar que acabou: o
// silencio de 2 min o encerra.
const emAndamento = (a: RainforestMindPainelAgente, agora: number): boolean =>
  a.fimEm === null && (a.criadoAqui || agora - a.vistoEm < 2 * MIN)

const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000))
  return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0')
}

const COR = { ambar: '#ffb000', verde: '#00d67a', vermelho: '#ff4d4d', ciano: '#4dd2ff', cinza: '#808080' }
const CORES_FATIA = ['#4dd2ff', '#00d67a', '#ffb000', '#c792ea', '#ff7eb6', '#7aa2f7', '#e0af68']
const PANE = 'painel'
const FATIAS_NA_LEGENDA = 7
const AGENTES_NO_PANE = 6

// O slug do fluxo comeca pela data de criacao; no pane so o nome conta.
const slugSemData = (slug: string): string => slug.replace(/^\d{4}-\d{2}-\d{2}-/, '')

const AJUDA = 'Subcomandos: esconder, mostrar, cache 5m|1h, checar ligar|desligar, limpar, erros [horas]. Sem argumento abre o painel.'
// Ate tantas escritas esperam a vez do script do desvio; as demais entram no mapa sem veredito.
const FILA_DESVIO_MAX = 50

export const register: Register = (on, options) => {
  abertura(on, options)

  // Desvio do plano: no maximo um spawn do script por vez. Escritas que chegam durante ele
  // esperam em `filaDesvio`; `desvioPendente` (na fila ou rodando) e `desvioConsultado` (ja
  // tem veredito) garantem que cada caminho roda uma vez so. Zerados a cada sessao.
  const filaDesvio: { escrita: string; rodar: () => Promise<boolean> }[] = []
  const desvioPendente = new Set<string>()
  const desvioConsultado = new Set<string>()
  let desvioRodando = false
  const drenarDesvios = async (): Promise<void> => {
    if (desvioRodando) return
    desvioRodando = true
    try {
      for (let item = filaDesvio.shift(); item !== undefined; item = filaDesvio.shift()) {
        try {
          if (await item.rodar()) desvioConsultado.add(item.escrita)
        } catch {
          // o desvio nunca quebra a ferramenta
        }
        desvioPendente.delete(item.escrita)
      }
    } finally {
      desvioRodando = false
    }
  }

  // Timers do relogio e do tique da barra: ficam no escopo do register para o session.end e
  // o proximo session.start cancelarem os da sessao anterior.
  let timers: { cancel: () => void }[] = []
  // Id da sessao que armou os timers: so o session.end dela cancela o relogio.
  let armadoPor: string | null = null
  // O tique da barra (1 s) so existe depois de alguma atividade (ferramenta, passo, subagente,
  // turno) ou de um compact que pediu medicao nova, e se desarma quando nada mais conta: parado,
  // nao ha timer nenhum.
  let ativo = false
  let medirPendente = false
  let tiqueTimer: { cancel: () => void } | null = null
  let armarTique: (() => void) | null = null
  const acordar = () => {
    ativo = true
    try {
      if (armarTique !== null) armarTique()
    } catch {
      // sem tique, a barra so se redesenha quando o estado muda
    }
  }
  const cancelarRelogio = () => {
    armadoPor = null
    armarTique = null
    if (tiqueTimer !== null) {
      try {
        tiqueTimer.cancel()
      } catch {
        // timer ja encerrado
      }
      tiqueTimer = null
    }
    ativo = false
    const velhos = timers
    timers = []
    for (const t of velhos) {
      try {
        t.cancel()
      } catch {
        // timer ja encerrado
      }
    }
  }

  on('session.start', async ($, e, next) => {
    desvioConsultado.clear()
    try {
      await $.command.register({
        name: 'painel',
        description: 'Painel da sessao: /painel abre o pane; esconder, mostrar, cache 5m|1h',
      })
    } catch {
      // sem comando, a barra segue
    }
    // claude -p, SDK e subagente nao desenham a barra: sem timer, sem ler os fluxos do painel,
    // e sem cancelar o relogio da sessao interativa que compartilha esta instancia do mod.
    if (!e.isInteractive) return next(e)
    try {
      const dados = await buscar({
        rodar: (argv, init) => $.process.run(argv, init),
        cwd: () => $.session.cwd(),
        raiz: $.plugin.root,
      })
      await update($, faixaDados, () => dados)
    } catch {
      // a barra nunca quebra a abertura da sessao
    }
    cancelarRelogio()
    try {
      const id = await $.session.id()
      armadoPor = id
      const cwd = await $.session.cwd()
      const raiz = $.plugin.root
      const io = { rodar: (argv: string[], init: { cwd: string; env: Record<string, string>; timeoutMs: number }) => $.process.run(argv, init), raiz }
      let sessoesEmCurso = false
      let jornadaEmCurso = false

      // Arma a nota do dia quando a jornada acende e o dia ainda nao foi entregue.
      const reavaliar = async () => {
        try {
          const agora = await $.clock.now()
          const rel = avaliarRelogio({ jornada: await read($, relogioJornada), sessoes: await read($, relogioSessoes), agora })
          if (rel.jornada) {
            const dia = rel.jornada.dia
            const entregue = await read($, relogioNotaEntregue)
            const pendente = await read($, relogioNotaPendente)
            if (entregue !== dia && pendente !== dia) await update($, relogioNotaPendente, () => dia)
          }
        } catch {
          // o relogio nunca quebra nada
        }
        try {
          $.ui.invalidate('ui.render')
        } catch {
          // sem tela, sem redesenho
        }
      }

      const lerSessoes = async () => {
        if (sessoesEmCurso) return
        sessoesEmCurso = true
        try {
          // Depois de /clear o processo segue com outro id: le-o de novo uma vez.
          if (armadoPor === null) armadoPor = await $.session.id()
          const bruto = await rodarJson(io, ['node', `${raiz}/scripts/relogio-sessoes.cjs`, '--cwd', cwd, '--sessao', armadoPor], 5000, { CLAUDE_PROJECT_DIR: cwd })
          const dados = sessoesDe(bruto)
          await update($, relogioSessoes, () => dados)
          await reavaliar()
        } catch {
          // falha apaga so a figura do relogio
        } finally {
          sessoesEmCurso = false
        }
      }

      const lerJornada = async () => {
        if (jornadaEmCurso) return
        jornadaEmCurso = true
        try {
          const bruto = await rodarJson(io, ['node', `${raiz}/scripts/jornada.cjs`, '--json'], 60000, {})
          const dados = jornadaDe(bruto)
          await update($, relogioJornada, () => dados)
          await reavaliar()
        } catch {
          // falha apaga so a figura do relogio
        } finally {
          jornadaEmCurso = false
        }
      }

      // A contagem do cache e o ritmo andam sozinhos: o tique redesenha a barra a cada segundo
      // enquanto algo conta (cache quente, ferramenta no ultimo minuto, subagente) e refaz a
      // medicao que um compact deixou pendente. Nunca roda processo.
      const tique = async () => {
        if (!ativo && !medirPendente) return
        try {
          if (medirPendente) {
            medirPendente = false
            await medir({
              usage: () => $.session.usage({ breakdown: 'summary' }),
              gravar: f => update($, painelStats, f),
              log: m => $.ui.log(m, { to: 'debug' }),
            })
          }
          const s = inteiro(await read($, painelStats))
          const agora = await $.clock.now()
          const contando =
            ritmoPorMinuto(s.carimbos, agora) > 0 ||
            s.agentes.some(a => emAndamento(a, agora)) ||
            cacheDe({ modelo: s.modelo, ctxTokens: s.ctxTokens, ultimaRequisicaoMs: s.ultimaRequisicaoMs, agora, ttlMs: s.ttlMs }).quente
          if (contando) $.ui.invalidate('ui.render')
          else {
            ativo = false
            if (tiqueTimer !== null) tiqueTimer.cancel()
            tiqueTimer = null
          }
        } catch {
          // o tique nunca quebra nada
        }
      }

      timers.push($.clock.after(1000, lerSessoes))
      timers.push($.clock.after(2000, lerJornada))
      timers.push($.clock.every(60000, lerSessoes))
      timers.push($.clock.every(300000, lerJornada))
      armarTique = () => {
        if (tiqueTimer === null) tiqueTimer = $.clock.every(1000, tique)
      }
    } catch {
      // o relogio nunca quebra a abertura da sessao
    }
    return next(e)
  })

  // O matcher (qualquer motivo) evita colidir com o session.end sem matcher da abertura.
  on('session.end', { reason: /.*/ }, async (_$, e, next) => {
    if (armadoPor !== null && e.sessionId === armadoPor) {
      // /clear nao tem session.start depois: o relogio segue e o id novo e lido no proximo tick.
      if (e.reason === 'clear') armadoPor = null
      else cancelarRelogio()
    }
    return next(e)
  })

  on('command.run', { command: 'painel' }, async ($, e) => {
    const palavra = `${e.args ?? ''}`.trim().toLowerCase()
    if (palavra === 'esconder' || palavra === 'mostrar') {
      await update($, painelOculto, () => palavra === 'esconder')
      return { text: palavra === 'esconder' ? 'Barra escondida.' : 'Barra de volta.' }
    }
    if (palavra === 'cache 5m' || palavra === 'cache 1h') {
      await update($, painelStats, s => ({ ...inteiro(s), ttlMs: palavra === 'cache 5m' ? 5 * MIN : HORA }))
      return { text: `Vida do cache em ${palavra.slice(6)}.` }
    }
    if (palavra === 'checar ligar' || palavra === 'checar desligar') {
      await update($, painelDeixado, d => ({ ...deixadoInteiro(d), checar: palavra === 'checar ligar' }))
      return { text: palavra === 'checar ligar' ? 'Checagem do segundo modelo ligada.' : 'Checagem do segundo modelo desligada.' }
    }
    if (palavra === 'erros' || /^erros \d+$/.test(palavra)) {
      const horas = palavra === 'erros' ? '24' : palavra.slice(6)
      try {
        const cwd = await $.session.cwd()
        const r = await $.process.run(['node', `${$.plugin.root}/scripts/erros.cjs`, 'listar', '--horas', horas], {
          cwd: $.plugin.root,
          env: { CLAUDE_PROJECT_DIR: cwd },
          timeoutMs: 10000,
        })
        return { text: r.exitCode === 0 ? r.stdout.trimEnd() : `Log de erros indisponível (exit ${r.exitCode}).` }
      } catch {
        return { text: 'Log de erros indisponível.' }
      }
    }
    if (palavra === 'limpar') {
      await update($, painelDeixado, d => ({ ...deixadoInteiro(d), itens: [] }))
      return { text: 'Deixado para depois zerado.' }
    }
    if (palavra !== '') return { text: AJUDA }
    // Sem argumento: abre o pane, mede o contexto e atualiza os fluxos. Cada peca que falha
    // some sozinha; o comando sempre devolve o texto.
    let aberto = false
    try {
      aberto = (await $.ui.open({ id: PANE, title: 'Esta sessão' })).isPlaced === true
    } catch {
      // sem pane, o texto do comando basta
    }
    try {
      await medir({
        usage: () => $.session.usage({ breakdown: 'summary' }),
        gravar: f => update($, painelStats, f),
        log: m => $.ui.log(m, { to: 'debug' }),
      })
      const dados = await buscar({
        rodar: (argv, init) => $.process.run(argv, init),
        cwd: () => $.session.cwd(),
        raiz: $.plugin.root,
      })
      await update($, faixaDados, () => dados)
    } catch {
      // a medicao nunca quebra o comando
    }
    if (aberto) return { text: 'Painel aberto.' }
    const s = inteiro(await read($, painelStats))
    return { text: `Painel indisponível aqui. Contexto ${s.ctxPct === null ? '--' : Math.round(s.ctxPct) + '%'}, custo ${dinheiro(s.custoUsd)}.` }
  })

  on('agent.spawn', async ($, e, next) => {
    const criado = await next(e)
    acordar()
    try {
      if (criado.agentId !== undefined) {
        const id = criado.agentId
        const at = await $.clock.now()
        await update($, painelStats, raw => {
          const s = inteiro(raw)
          return {
            ...s,
            agentes: comAgente(s.agentes, id, at, a => ({
              ...a,
              rotulo: rotuloSubagente(e.description, 40),
              tipo: String(e.subagentType),
              modelo: criado.model,
              criadoAqui: true,
              fimEm: null,
            })),
          }
        })
      }
    } catch {
      // o contador nunca quebra o spawn
    }
    try {
      await update($, painelMapa, raw => registrar(raw, { agente: true, description: e.description }).mapa as RainforestMindPainelMapa)
    } catch {
      // o mapa nunca quebra o spawn
    }
    return criado
  })

  // Nota da regra 8: uma vez por dia, so em prompt digitado no composer (nao em loop/schedule/system).
  // Vai em `context`: o modelo le, o usuario nao ve, e o texto do prompt segue intacto. O evento e
  // o `prompt.submit` porque o gancho classico de envio (UserPromptSubmit) nao roda, em mod, no
  // composer do REPL.
  on('prompt.submit', async ($, e, next) => {
    // O pedido da pessoa fica guardado para o checker do fim do turno (so o que ela mesma mandou).
    try {
      const tipo: string | undefined = e.origin?.kind
      if (tipo === undefined || tipo === 'composer' || tipo === 'bridge' || tipo === 'sdk') {
        const pedido = String(e.text ?? '').slice(0, 4000)
        await update($, painelDeixado, d => ({ ...deixadoInteiro(d), pedido }))
      }
    } catch {
      // o pedido guardado nunca quebra o envio
    }
    let nota: string | null = null
    try {
      if (e.origin === undefined || e.origin.kind === 'composer') {
        const pendente = await read($, relogioNotaPendente)
        if (pendente) {
          const agora = await $.clock.now()
          const rel = avaliarRelogio({ jornada: await read($, relogioJornada), sessoes: await read($, relogioSessoes), agora })
          const dia = rel.jornada ? rel.jornada.dia : null
          const texto = notaJornada(rel) as string | null
          if (dia && texto && pendente === dia) {
            await update($, relogioNotaEntregue, () => dia)
            await update($, relogioNotaPendente, () => null)
            nota = texto
          }
        }
      }
    } catch {
      // a nota nunca quebra o envio
    }
    if (nota === null) return next(e)
    return next({ ...e, context: [...(e.context ?? []), nota] })
  })

  // Cada requisicao do laco. A vida do cache corre do comeco da ultima requisicao do laco
  // principal; uma requisicao de subagente quer dizer que ele esta trabalhando.
  on('turn.step', async function* ($, e, next) {
    acordar()
    try {
      const at = await $.clock.now()
      const agentId = e.agentId
      await update($, painelStats, raw => {
        const s = inteiro(raw)
        return agentId === undefined
          ? { ...s, ultimaRequisicaoMs: at }
          : { ...s, agentes: comAgente(s.agentes, agentId, at, a => ({ ...a, fimEm: null })) }
      })
    } catch {
      // o contador nunca quebra o passo
    }
    return yield* next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    acordar()
    try {
      const at = await $.clock.now()
      const agentId = e.agentId
      const falhou = ran.deny !== undefined || ran.isError === true
      await update($, painelStats, raw => {
        const s = inteiro(raw)
        return {
          ...s,
          ferramentas: s.ferramentas + 1,
          falhas: s.falhas + (falhou ? 1 : 0),
          carimbos: [...s.carimbos, at].filter(t => at - t <= MIN),
          agentes: agentId === undefined ? s.agentes : comAgente(s.agentes, agentId, at, a => ({ ...a, fimEm: null, ferramentas: a.ferramentas + 1 })),
        }
      })
    } catch {
      // o contador nunca quebra a ferramenta
    }
    // Cada falha vira uma linha em <raiz>/erros.jsonl na hora (scripts/erros.cjs), para triar
    // depois com /painel erros. Na hora e nao no SessionEnd: janela fechada no X nao dispara
    // SessionEnd. So roda em falha (custa um node, ~100 ms) e nunca quebra a ferramenta. O corte
    // fino e o mascaramento de segredo sao do script: cortar aqui deixaria meio token sem mascara.
    if (ran.deny !== undefined || ran.isError === true) {
      const entrada = e as unknown as Record<string, unknown>
      const comando = entrada.command ?? entrada.file_path ?? entrada.notebook_path ?? entrada.pattern ?? entrada.url ?? entrada.description ?? ''
      try {
        const cwd = await $.session.cwd()
        const falha = {
          sessao: await $.session.id(),
          cwd,
          ferramenta: String(e.tool),
          tipo: ran.deny !== undefined ? 'bloqueio' : 'erro',
          comando: semControle(String(comando)).slice(0, 4000),
          mensagem: semControle(String(ran.deny ?? ran.text ?? '')).slice(0, 4000),
        }
        await $.process.run(['node', `${$.plugin.root}/scripts/erros.cjs`, 'gravar'], {
          cwd: $.plugin.root,
          env: { CLAUDE_PROJECT_DIR: cwd },
          stdin: JSON.stringify(falha),
          timeoutMs: 5000,
        })
      } catch {
        // o log de erros nunca quebra a ferramenta
      }
    }
    try {
      const falhou = ran.deny !== undefined || ran.isError === true
      if (e.agentId === undefined) {
        await update($, painelDeixado, d => {
          const x = deixadoInteiro(d)
          return { ...x, ferramentas: [...x.ferramentas, { tool: String(e.tool), deny: ran.deny !== undefined, isError: ran.isError === true }] }
        })
      }
      if (!falhou && ESCRITORAS.has(String(e.tool))) {
        const entrada = e as unknown as Record<string, unknown>
        const escrito = String(entrada.new_string ?? entrada.content ?? entrada.new_source ?? '')
        const linha = (marcadoresEmArquivo(escrito) as string[])[0]
        if (linha !== undefined) {
          // O nome do arquivo e a linha vem do modelo: nenhum controle chega ao Text nem ao toast.
          const arquivo = semControle(String(entrada.file_path ?? entrada.notebook_path ?? 'arquivo')).split(/[\\/]/).pop() ?? 'arquivo'
          await anotar(
            { gravar: f => update($, painelDeixado, f), avisar: t => $.ui.toast(t) },
            [`Escreveu "${semControle(linha).slice(0, 90)}" em ${arquivo}`],
            'em arquivo',
          )
        }
      }
    } catch {
      // o deixado nunca quebra a ferramenta
    }
    try {
      if (ran.deny === undefined && ran.isError !== true) {
        const escrita = escritaDe(e) as string | null
        if (escrita === null) {
          await update($, painelMapa, raw => registrar(raw, e).mapa as RainforestMindPainelMapa)
        } else {
          // Escrita: o script do desvio roda em segundo plano (3 a 5 s medidos) e o resultado
          // da ferramenta nao espera por ele. Um spawn por vez: as escritas que chegam durante
          // ele esperam na fila, e cada caminho roda uma vez so (veredito ou espera ja valem
          // por ele). O arquivo entra no mapa quando a resposta chega, para o `novo` do desvio
          // valer uma vez por arquivo (D15). Nada daqui vai ao modelo.
          if (desvioConsultado.has(escrita) || desvioPendente.has(escrita)) {
            // ja tem veredito, ou ja espera a vez
          } else if (filaDesvio.length >= FILA_DESVIO_MAX) {
            await update($, painelMapa, raw => registrar(raw, e).mapa as RainforestMindPainelMapa)
          } else {
            const raiz = $.plugin.root
            const log = (err: unknown) => {
              try {
                $.ui.log(`painel: desvio: ${String(err)}`, { to: 'debug' })
              } catch {
                // sem log, sem problema
              }
            }
            // Devolve true quando o script respondeu um veredito; falha aberta, nunca lanca.
            const rodar = async (): Promise<boolean> => {
              let desvio: { veredito?: string; rel?: string | null } | null = null
              try {
                const cwd = await $.session.cwd()
                const r = await $.process.run(
                  ['node', `${raiz}/scripts/desvio-do-plano.cjs`, '--cwd', cwd, '--arquivo', escrita],
                  // Roda em segundo plano depois da escrita: sob carga passa de 5 s, e o teto folga.
                  { cwd: raiz, env: { CLAUDE_PROJECT_DIR: cwd }, timeoutMs: 10000 },
                )
                const lido = r.exitCode === 0 ? JSON.parse(r.stdout) : null
                desvio = lido !== null && typeof lido === 'object' && typeof lido.veredito === 'string' ? lido : null
              } catch (err) {
                log(err)
              }
              try {
                const caminho: string = typeof desvio?.rel === 'string' && desvio.rel !== '' ? desvio.rel : escrita
                const escreveu = { tool: e.tool, file_path: caminho, notebook_path: caminho }
                let avisar = false
                await update($, painelMapa, raw => {
                  if (desvio === null) return registrar(raw, escreveu).mapa as RainforestMindPainelMapa
                  const marcado = registrar(raw, { desvio: true, caminho })
                  if (desvio.veredito === 'fora' && marcado.novo) {
                    avisar = true
                  }
                  return (desvio.veredito === 'fora' ? marcado.mapa : registrar(raw, escreveu).mapa) as RainforestMindPainelMapa
                })
                if (avisar) $.ui.toast(`Fora dos arquivos do plano: ${caminho}`)
              } catch (err) {
                log(err)
              }
              return desvio !== null
            }
            desvioPendente.add(escrita)
            filaDesvio.push({ escrita, rodar })
            void drenarDesvios()
          }
        }
      }
    } catch {
      // o mapa nunca quebra a ferramenta
    }
    return ran
  })

  on('turn.complete', async ($, e, next) => {
    const agentId = e.agentId
    acordar()
    const log = (m: string) => {
      try {
        $.ui.log(m, { to: 'debug' })
      } catch {
        // sem log, sem problema
      }
    }
    // As ferramentas e o pedido do turno saem do estado e a lista zera ANTES de qualquer outra
    // espera: o turno seguinte ja pode estar chamando ferramentas enquanto este fecha as medidas.
    const turno: { d: RainforestMindPainelDeixado | null } = { d: null }
    if (agentId === undefined) {
      try {
        await update($, painelDeixado, x => {
          const d = deixadoInteiro(x)
          turno.d = d
          return { ...d, ferramentas: [] }
        })
      } catch {
        // o deixado nunca quebra o turno
      }
    }
    try {
      const at = await $.clock.now()
      const saida = e.usage?.output_tokens ?? 0
      // `input_tokens` e so a parte sem cache; um prompt em cache reporta quase tudo nos dois
      // campos de cache.
      const novos = e.usage?.input_tokens ?? 0
      const lidos = e.usage?.cache_read_input_tokens ?? 0
      const escritos = e.usage?.cache_creation_input_tokens ?? 0
      await update($, painelStats, raw => {
        const s = inteiro(raw)
        return {
          ...s,
          // So onde nenhuma requisicao do laco principal foi vista comecar.
          ultimaRequisicaoMs: agentId === undefined && s.ultimaRequisicaoMs === 0 ? at : s.ultimaRequisicaoMs,
          modelo: agentId === undefined ? (e.usage?.model ?? s.modelo) : s.modelo,
          turnos: s.turnos + (agentId === undefined ? 1 : 0),
          tokensNovos: s.tokensNovos + novos,
          tokensCacheLido: s.tokensCacheLido + lidos,
          tokensCacheEscrito: s.tokensCacheEscrito + escritos,
          tokensSaida: s.tokensSaida + saida,
          agentes: agentId === undefined
            ? s.agentes
            : comAgente(s.agentes, agentId, at, a => ({
                ...a,
                fimEm: at,
                modelo: e.usage?.model ?? a.modelo,
                tokensLidos: a.tokensLidos + novos + lidos + escritos,
                tokensSaida: a.tokensSaida + saida,
                falhou: e.reason === 'error' || e.reason === 'aborted',
              })),
        }
      })
      if (agentId === undefined) {
        // Sem await: medir (session.usage) e buscar (scripts) levam segundos e o turno nao
        // espera por eles. Falha aberta: cada um apaga so a propria leitura.
        medir({
          usage: () => $.session.usage({ breakdown: 'summary' }),
          gravar: f => update($, painelStats, f),
          log: m => $.ui.log(m, { to: 'debug' }),
        }).catch((err: unknown) => log(`painel: medir: ${String(err)}`))
        buscar({
          rodar: (argv, init) => $.process.run(argv, init),
          cwd: () => $.session.cwd(),
          raiz: $.plugin.root,
        })
          .then(dados => update($, faixaDados, () => dados))
          .catch((err: unknown) => log(`painel: buscar: ${String(err)}`))
      }
    } catch {
      // a barra nunca quebra o turno
    }
    if (agentId === undefined) {
      try {
        const d = turno.d
        if (d !== null && e.reason === 'answer') {
          const relato = String(e.answer ?? '')
          const io = { gravar: (f: (x: RainforestMindPainelDeixado) => RainforestMindPainelDeixado) => update($, painelDeixado, f), avisar: (t: string) => $.ui.toast(t) }
          await anotar(io, deferimentos(relato) as string[], 'Claude disse')
          const ligado = d.checar
          const ferramentas = d.ferramentas
          const pedido = d.pedido
          // Duas metades: achar pendencia nova pede turno de 5+ ferramentas e relato sem decisao
          // `Q<n>` para a pessoa (a Q espera a palavra dela); fechar item resolvido roda em todo
          // turno com item aberto, porque a fala da pessoa no pedido tambem e evidencia.
          const abertos = d.itens.filter(i => i.estado === 'aberto').map(i => ({ id: i.id, texto: i.texto }))
          const acharNovos = ferramentas.length >= CHECAR_MIN_FERRAMENTAS && !perguntaDecisao(relato)
          const deveChecar = ligado && pedido !== '' && (acharNovos || abertos.length > 0);
          if (deveChecar) {
            // Sem await: o turno acaba agora e o achado chega quando chegar.
            await update($, painelDeixado, x => ({ ...deixadoInteiro(x), checando: true }))
            const checagem = async () => {
              try {
                const r = await $.model.complete({
                  model: 'haiku',
                  prompt: montarPromptChecker({ pedido, relato, ferramentas, abertos }),
                  maxTokens: 300,
                  timeoutMs: 30000,
                })
                if (!r.isAnswered) {
                  log(`painel: checker: o modelo nao respondeu (${r.reason})`)
                  return
                }
                // So `aberto -> resolvido`, dentro do update: o estado pode ter mudado enquanto o
                // modelo pensava (Faz agora, limpar).
                const resolvidos = new Set(lerResolvidosChecker(r.text, abertos.map(i => i.id)) as number[])
                if (resolvidos.size > 0) {
                  await update($, painelDeixado, x => {
                    const y = deixadoInteiro(x)
                    return { ...y, itens: y.itens.map(i => (i.estado === 'aberto' && resolvidos.has(i.id) ? { ...i, estado: 'resolvido' as const } : i)) }
                  })
                }
                if (acharNovos) await anotar(io, lerRespostaChecker(r.text) as string[], 'segundo modelo')
              } finally {
                try {
                  await update($, painelDeixado, (d) => ({ ...d, checando: false }));
                } catch {
                  // sem estado, o aviso de checando some quando o pane redesenhar
                }
              }
            }
            checagem().catch((err: unknown) => log(`painel: checker: ${String(err)}`))
          }
        }
      } catch {
        // o deixado nunca quebra o turno
      }
    }
    return next(e)
  })

  // A conversa compactada e outra janela: mostra a contagem da propria compactacao na hora e
  // pede medicao nova (o engine troca a conversa depois que este hook volta, entao uma leitura
  // agora ainda seria a velha).
  // O matcher casa qualquer gatilho: register.ts ja tem um session.compact sem matcher.
  on('session.compact', { trigger: /.*/ }, async ($, e, next) => {
    const feito = await next(e)
    try {
      if (e.agentId !== undefined || e.trigger === 'precompute' || feito.messages === undefined) return feito
      const depois = feito.tokensAfter
      medirPendente = true
      acordar()
      await update($, painelStats, raw => {
        const s = inteiro(raw)
        const medida = depois !== undefined && s.ctxJanela !== null && s.ctxJanela > 0
        return {
          ...s,
          medirDeNovo: true,
          ctxTokens: depois ?? s.ctxTokens,
          ctxPct: medida ? (depois / (s.ctxJanela ?? 1)) * 100 : s.ctxPct,
          fatias: medida ? [] : s.fatias,
        }
      })
    } catch {
      // o contador nunca quebra a compactacao
    }
    return feito
  })

  // O pane do /painel: fluxos em curso, onde foi o contexto, cache, subagentes e custo. Toda
  // leitura que falta vira uma frase no proprio painel; excecao devolve next(e).
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    try {
      const { Box, Text, Button } = $.ui.resolve(e)
      const s = inteiro(await read($, painelStats))
      const dados = await read($, faixaDados)
      const deixado = deixadoInteiro(await read($, painelDeixado))
      const agora = await $.clock.now()
      const interior = Math.max(16, e.props.bodyColumns - 4)
      const visto = e.props.view?.agentId
      const corte = (texto: string, margem: number): string => rotuloSubagente(texto, Math.max(8, interior - margem))

      const linha = (chave: string, rotulo: string, valor: string, cor: string) => (
        <Box key={chave} flexDirection="row" justifyContent="space-between">
          <Text color={COR.ambar} dimColor>{rotulo}</Text>
          <Text color={cor} bold>{valor}</Text>
        </Box>
      )
      const painel = (chave: string, cor: string, titulo: string, filhos: unknown) => (
        <Box key={chave} flexDirection="column" borderStyle="single" borderColor={cor} paddingX={1}>
          <Text backgroundColor={cor} color="#000000" bold>{` ${titulo} `}</Text>
          {filhos}
        </Box>
      )
      const linhasAgentes = (limite: number) =>
        [...s.agentes]
          .sort((a, b) => b.iniciadoEm - a.iniciadoEm)
          .slice(0, limite)
          .map(a => {
            const roda = emAndamento(a, agora)
            const cor = roda ? COR.verde : a.falhou ? COR.vermelho : COR.ciano
            const seta = a.id === visto ? '▶ ' : ''
            return (
              <Box key={`ag-${a.id}`} flexDirection="column">
                <Box flexDirection="row" justifyContent="space-between">
                  <Text color={cor} bold>{corte(`${seta}${roda ? '●' : a.falhou ? '✗' : '✓'} ${a.rotulo}`, 7)}</Text>
                  <Text color={cor}>{mmss((roda ? agora : (a.fimEm ?? a.vistoEm)) - a.iniciadoEm)}</Text>
                </Box>
                <Text dimColor>{corte(`  ${roda ? 'trabalhando' : a.falhou ? 'parou' : 'pronto'} · ${a.tipo} · ${a.modelo ?? 'modelo desconhecido'} · ${a.ferramentas} ferramentas`, 0)}</Text>
              </Box>
            )
          })

      // O transcript de um subagente esta em tela: o pane e dele, e contexto e cache sao da principal.
      if (visto !== undefined) {
        const a = s.agentes.find(x => x.id === visto)
        const roda = a !== undefined && emAndamento(a, agora)
        const cor = a === undefined ? COR.ambar : roda ? COR.verde : a.falhou ? COR.vermelho : COR.ciano
        return (
          <Box flexDirection="column">
            {painel('p-agente', COR.ciano, 'Subagente em tela', [
              <Text key="nome" color={cor} bold>{corte(a?.rotulo ?? `agente ${visto.slice(0, 6)}`, 0)}</Text>,
              a === undefined ? <Text key="sem" dimColor>Sem atividade vista ainda</Text> : null,
              a !== undefined ? linha('status', 'Status', roda ? 'trabalhando' : a.falhou ? 'parou' : 'pronto', cor) : null,
              a !== undefined ? linha('tempo', 'Tempo', mmss((roda ? agora : (a.fimEm ?? a.vistoEm)) - a.iniciadoEm), cor) : null,
              a !== undefined ? linha('tipo', 'Tipo', a.tipo, COR.ciano) : null,
              a !== undefined ? linha('modelo', 'Modelo', a.modelo ?? 'desconhecido', COR.ciano) : null,
              a !== undefined ? linha('ferr', 'Ferramentas', `${a.ferramentas}`, COR.ciano) : null,
              a !== undefined ? linha('lidos', 'Tokens lidos', compacto(a.tokensLidos), COR.ciano) : null,
              a !== undefined ? linha('escritos', 'Tokens escritos', compacto(a.tokensSaida), COR.verde) : null,
              <Text key="nota" dimColor>Os tokens sobem cada vez que ele termina uma rodada</Text>,
            ])}
            {painel('p-agentes', COR.ambar, 'Todos os subagentes', linhasAgentes(AGENTES_NO_PANE))}
            <Text dimColor>Contexto e cache são da sessão principal. Volte a ela para vê-los.</Text>
          </Box>
        )
      }

      // Fluxos em curso (D4): o que esta aberto neste repositorio, lido de faixa-dados.cjs.
      const fluxos = dados?.fluxos ?? []
      // Leitura que falhou (exit, timeout, JSON) nao se mostra como "nenhum": vazio nao e ok.
      const painelFluxos = painel('p-fluxos', COR.ciano, 'Fluxos em curso', dados === null
        ? <Text color={COR.ambar}>Leitura dos fluxos indisponível agora; tenta de novo no fim do próximo turno</Text>
        : fluxos.length === 0
        ? <Text dimColor>Nenhum fluxo em curso</Text>
        : fluxos.map(f => {
            const partes = [f.etapa]
            if (f.tarefas !== null && f.tarefas_ok !== null) partes.push(`${f.tarefas_ok}/${f.tarefas}`)
            if (f.em_voo.length > 0) partes.push(`${f.em_voo.length} em voo`)
            const direita = rotuloSubagente(partes.join(' · '), Math.max(24, Math.floor(interior / 2)))
            return (
              <Box key={`fl-${f.slug}`} flexDirection="row" justifyContent="space-between">
                <Text color={COR.ciano} bold>{rotuloSubagente(slugSemData(f.slug), Math.max(8, interior - largura(direita) - 2))}</Text>
                <Text>{direita}</Text>
              </Box>
            )
          }))

      // Onde foi o contexto: maiores primeiro, depois o livre e a reserva; as ferramentas
      // carregadas sob demanda ficam fora da janela e so sao listadas.
      const ocupadas = s.fatias.filter(f => f.tipo === 'used').sort((a, b) => b.tokens - a.tokens)
      const sobras = s.fatias.filter(f => f.tipo === 'free' || f.tipo === 'buffer')
      const sobDemanda = s.fatias.filter(f => f.tipo === 'deferred').reduce((soma, f) => soma + f.tokens, 0)
      const desenhadas = [...ocupadas, ...sobras]
      const celulas = fatias(desenhadas, interior);
      const janela = desenhadas.reduce((soma, f) => soma + f.tokens, 0)
      const tinta = (f: Fatia): string => (f.tipo === 'used' ? (CORES_FATIA[ocupadas.indexOf(f) % CORES_FATIA.length] ?? COR.ciano) : COR.cinza)
      const celula = (f: Fatia): string => (f.tipo === 'used' ? '█' : f.tipo === 'buffer' ? '▒' : '░')
      const restoUsado = ocupadas.slice(FATIAS_NA_LEGENDA).reduce((soma, f) => soma + f.tokens, 0)
      const legenda = [...ocupadas.slice(0, FATIAS_NA_LEGENDA), ...sobras]
      const corCtx = (s.ctxPct ?? 0) > 80 ? COR.vermelho : COR.verde
      const painelContexto = painel('p-contexto', COR.ambar, 'Onde foi o contexto', [
        linha('usado', 'Usado', s.ctxPct === null ? '--' : `${Math.round(s.ctxPct)}% de ${compacto(s.ctxJanela ?? 0)}`, corCtx),
        desenhadas.length === 0 ? <Text key="indisp" color={COR.ambar}>Medição indisponível</Text> : null,
        desenhadas.length > 0 ? (
          <Box key="barra" flexDirection="row">
            {desenhadas.map((f, i) => ((celulas[i] ?? 0) > 0 ? <Text key={`c-${i}`} color={ocupadas.indexOf(f) >= FATIAS_NA_LEGENDA ? COR.cinza : tinta(f)}>{celula(f).repeat(celulas[i] ?? 0)}</Text> : null))}
          </Box>
        ) : null,
        ...legenda.map((f, i) => (
          <Box key={`lg-${i}`} flexDirection="row" justifyContent="space-between">
            <Text color={tinta(f)}>{`${celula(f) === '█' ? '■' : celula(f)} ${rotuloSubagente(f.nome, Math.max(8, interior - 14))}`}</Text>
            <Text color={tinta(f)} bold>{`${compacto(f.tokens)} ${`${Math.round((f.tokens / Math.max(1, janela)) * 100)}%`.padStart(4)}`}</Text>
          </Box>
        )),
        restoUsado > 0 ? <Text key="resto" dimColor>{`■ ${ocupadas.length - FATIAS_NA_LEGENDA} itens menores, ${compacto(restoUsado)}`}</Text> : null,
        sobDemanda > 0 ? <Text key="demanda" dimColor>{`+ ${compacto(sobDemanda)} em ferramentas sob demanda`}</Text> : null,
      ])

      // Cache de prompt: quente enquanto a ultima requisicao ainda cabe na vida do cache.
      const cache = cacheDe({ modelo: s.modelo, ctxTokens: s.ctxTokens, ultimaRequisicaoMs: s.ultimaRequisicaoMs, agora, ttlMs: s.ttlMs })
      const painelCache = painel('p-cache', COR.ambar, 'Cache de prompt', [
        s.ultimaRequisicaoMs === 0 ? <Text key="sem" dimColor>Medido depois do próximo turno</Text> : null,
        s.ultimaRequisicaoMs !== 0 ? linha('agora', 'Agora', cache.quente ? `quente, faltam ${restante(cache.restanteMs)}` : 'frio', cache.quente ? COR.vermelho : COR.ciano) : null,
        s.ultimaRequisicaoMs !== 0 ? linha('quente', 'Próxima mensagem com o cache quente', dinheiro(cache.custoQuente), COR.verde) : null,
        s.ultimaRequisicaoMs !== 0 ? linha('frio', 'Próxima mensagem com o cache frio', dinheiro(cache.custoFrio), cache.quente ? COR.ambar : COR.vermelho) : null,
        <Text key="nota" dimColor>{`Estimativa: reenvio da conversa a preço de lista, cache de ${s.ttlMs > 5 * MIN ? '1h' : '5m'}`}</Text>,
      ])

      // Mapa da sessao (D13): so o que foi escrito por Edit, Write e NotebookEdit, skills, servicos
      // MCP e subagentes. Ler e Bash nao entram; fora de fluxo nada fica vermelho.
      const mapa = { ...mapaVazio(), ...(await read($, painelMapa)) } as RainforestMindPainelMapa
      const fim = (texto: string, max: number): string => (largura(texto) > max ? `…${texto.slice(-(Math.max(4, max) - 1))}` : texto)
      const secao = (chave: string, titulo: string, itens: unknown[], vazio: string) => [
        <Text key={`mt-${chave}`} color={COR.ambar} dimColor>{titulo}</Text>,
        ...(itens.length === 0 ? [<Text key={`mv-${chave}`} dimColor>{`  ${vazio}`}</Text>] : itens),
      ]
      const painelMapa_ = painel('p-mapa', COR.ciano, 'Mapa da sessão', [
        ...secao('arq', 'Arquivos escritos', mapa.arquivos.map((a, i) => (
          <Box key={`ma-${i}`} flexDirection="column">
            <Text color={a.desvio ? COR.vermelho : COR.verde} bold={a.desvio}>{fim(`${a.desvio ? '✗' : '✓'} ${a.caminho}`, interior - 2)}</Text>
            {a.desvio ? <Text color={COR.vermelho}>{'  fora dos arquivos do plano'}</Text> : null}
          </Box>
        )), 'nenhum'),
        ...secao('sk', 'Skills', mapa.skills.map((x, i) => <Text key={`ms-${i}`} color={COR.ciano}>{fim(`  ${x}`, interior)}</Text>), 'nenhuma'),
        ...secao('sv', 'Serviços MCP', mapa.servicos.map((x, i) => <Text key={`mc-${i}`} color={COR.ciano}>{fim(`  ${x}`, interior)}</Text>), 'nenhum'),
        ...secao('sa', 'Subagentes chamados', mapa.subagentes.map((x, i) => <Text key={`mg-${i}`} color={COR.ciano}>{fim(`  ${x}`, interior)}</Text>), 'nenhum'),
        <Text key="mnota" dimColor>Escrita feita por Bash não é detectada; só Edit, Write e NotebookEdit entram aqui.</Text>,
      ])

      // Deixado para depois (D7): o que Claude adiou, escreveu como pendencia ou o segundo modelo
      // achou faltando. "Faz agora" so preenche o prompt; quem envia e a pessoa.
      const abertos = deixado.itens.filter(i => i.estado === 'aberto')
      const fazAgora = async (id: number, texto: string): Promise<void> => {
        try {
          const preenchido = await $.prompt.fill({ text: rascunhoFazAgora(texto) as string, mode: 'append' })
          // Prompt que recusou o texto deixa o item aberto: nada chegou a pessoa.
          if (!preenchido?.isFilled) return
          await update($, painelDeixado, d => ({ ...deixadoInteiro(d), itens: deixadoInteiro(d).itens.map(i => (i.id === id ? { ...i, estado: 'enviado' as const } : i)) }))
        } catch (err) {
          try {
            $.ui.log(`painel: deixado: ${String(err)}`, { to: 'debug' })
          } catch {
            // sem log, sem problema
          }
        }
      }
      const limpar = async (): Promise<void> => {
        try {
          await update($, painelDeixado, d => ({ ...deixadoInteiro(d), itens: [] }))
        } catch {
          // limpar nunca quebra o pane
        }
      }
      const painelDeixadoTela = painel('p-deixado', COR.vermelho, 'Deixado para depois', [
        deixado.checando ? <Text key="checando" color={COR.ambar}>Checando com o segundo modelo…</Text> : null,
        abertos.length === 0 && !deixado.checando ? <Text key="nada" dimColor>Nada marcado. O trabalho que Claude deixar para depois aparece aqui.</Text> : null,
        ...abertos.map((item, i) => (
          <Box key={`dx-${item.id}`} flexDirection="column" marginTop={i === 0 ? 0 : 1}>
            <Text color={COR.vermelho} bold>{`D${item.id} · ${item.origem}`}</Text>
            <Text wrap="wrap">{item.texto}</Text>
            <Button key={`faz-${item.id}`} label="Faz agora (só preenche o prompt)" onPress={() => fazAgora(item.id, item.texto)} />
          </Box>
        )),
        abertos.length > 0 ? <Button key="deixado-limpar" label="Limpar tudo" onPress={limpar} /> : null,
        <Text key="dnota" dimColor>{`Checagem do segundo modelo: ${deixado.checar ? 'ligada' : 'desligada'} (/painel checar ligar|desligar)`}</Text>,
      ])

      const lidos = s.tokensNovos + s.tokensCacheLido + s.tokensCacheEscrito
      const doCache = lidos === 0 ? 0 : Math.round((s.tokensCacheLido / lidos) * 100)
      return (
        <Box flexDirection="column">
          {painelFluxos}
          {painelDeixadoTela}
          {painelMapa_}
          {painelContexto}
          {painelCache}
          {painel('p-agentes', COR.ambar, 'Subagentes', s.agentes.length === 0 ? <Text dimColor>Nenhum iniciado ainda</Text> : linhasAgentes(AGENTES_NO_PANE))}
          {painel('p-custo', COR.ambar, 'Custo e tokens', [
            linha('custo', 'Custo da sessão', dinheiro(s.custoUsd), COR.ambar),
            linha('lidos', 'Tokens lidos', compacto(lidos), COR.ciano),
            linha('servido', '  servidos do cache', `${doCache}%`, COR.ciano),
            linha('escritos', 'Tokens escritos', compacto(s.tokensSaida), COR.verde),
            linha('turnos', 'Turnos', `${s.turnos}`, COR.ciano),
            <Text key="nota" dimColor>Tokens e turnos contam desde que o mod carregou</Text>,
          ])}
        </Box>
      )
    } catch {
      return next(e)
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    try {
      if (e.props.hasSurvey || (await read($, painelOculto))) return next(e)
      const { Box, Text } = $.ui.resolve(e)
      const s = inteiro(await read($, painelStats))
      const agora = await $.clock.now()
      const cols = e.props.bodyColumns
      const visto = e.props.view?.agentId

      // O transcript de um subagente esta em tela: a barra e dele, e o contexto e o da sessao principal.
      if (visto !== undefined) {
        const a = s.agentes.find(x => x.id === visto)
        const roda = a !== undefined && emAndamento(a, agora)
        const cor = a === undefined ? COR.ambar : roda ? COR.verde : a.falhou ? COR.vermelho : COR.ciano
        const partes: { texto: string; cor: string }[] = [
          { texto: ' Subagente ', cor: COR.ciano },
          { texto: rotuloSubagente(a?.rotulo ?? `agente ${visto.slice(0, 6)}`, 24), cor },
        ]
        if (a === undefined) {
          partes.push({ texto: 'Sem atividade vista ainda', cor: COR.ambar })
        } else {
          partes.push(
            { texto: 'Status ' + (roda ? 'trabalhando' : a.falhou ? 'parou' : 'pronto'), cor },
            { texto: 'Tempo ' + mmss((roda ? agora : (a.fimEm ?? a.vistoEm)) - a.iniciadoEm), cor },
            { texto: 'Ferram. ' + a.ferramentas, cor },
            { texto: 'Tokens ' + compacto(a.tokensLidos + a.tokensSaida), cor },
            { texto: 'Modelo ' + rotuloSubagente(a.modelo ?? 'desconhecido', 24), cor },
          )
        }
        partes.push({ texto: 'Sessão principal: contexto ' + (s.ctxPct === null ? '--' : Math.round(s.ctxPct) + '%'), cor: COR.ambar })
        const ficam: { texto: string; cor: string }[] = []
        let usado = 0
        for (const p of partes) {
          const custo = largura(p.texto) + (ficam.length > 0 ? 2 : 0)
          if (ficam.length > 0 && usado + custo > cols) break
          ficam.push(ficam.length === 0 ? { ...p, texto: cortar(p.texto, cols) } : p)
          usado += custo
        }
        return (
          <Box flexDirection="row" height={1} overflow="hidden">
            {ficam.map((p, i) => (
              <Box key={`a${i}`} marginLeft={i === 0 ? 0 : 2}>
                <Text color={p.cor} wrap="truncate-end">{p.texto}</Text>
              </Box>
            ))}
          </Box>
        )
      }

      let relogio: string | null = null
      try {
        relogio = linhaDoRelogio(await read($, relogioJornada), await read($, relogioSessoes), agora)
      } catch {
        // sem relogio, a barra segue
      }
      const figuras = figurasDaBarra(
        {
          trabalhando: e.props.isWorking,
          tokens: s.tokensNovos + s.tokensCacheLido + s.tokensCacheEscrito + s.tokensSaida,
          custoUsd: s.custoUsd,
          ctxPct: s.ctxPct ?? undefined,
          ctxTokens: s.ctxTokens ?? undefined,
          modelo: s.modelo,
          ttlMs: s.ttlMs,
          ultimaRequisicaoMs: s.ultimaRequisicaoMs,
          agora,
          carimbos: s.carimbos,
          subagentes: s.agentes.filter(a => emAndamento(a, agora)).length,
          turnos: s.turnos,
          erros: s.falhas,
          deixado: deixadoInteiro(await read($, painelDeixado)).itens.filter(i => i.estado === 'aberto').length,
        },
        relogio,
        cols,
      ) as { id: string; texto: string; largura: number }[]
      if (figuras.length === 0) return next(e)
      const corDe = (id: string): string | undefined =>
        id === 'estado' ? (e.props.isWorking ? COR.verde : COR.ambar) : id === 'erros' ? (s.falhas > 0 ? COR.vermelho : COR.verde) : id === 'relogio' ? COR.ambar : undefined
      return (
        <Box flexDirection="row" height={1} overflow="hidden">
          {figuras.map((f, i) => (
            <Box key={f.id} marginLeft={i === 0 ? 0 : 2}>
              <Text color={corDe(f.id)} wrap="truncate-end">{f.texto}</Text>
            </Box>
          ))}
        </Box>
      )
    } catch {
      return next(e)
    }
  })
}
