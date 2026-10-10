// Prova de engine da compactacao automatica do mod: `claude plugin test <raiz>`.
// O engine carrega hooks/mod.tsx de verdade; por baixo dos plugins respondem `session.compact`
// (conta as compactacoes, ou recusa como o engine faz com um turno em curso), `ui.toast`
// (guarda os avisos), `agent.spawn` (o subagente da barra), `process.run`, o relogio simulado
// e o resto da sessao. O `session.measure` e levantado pelo teste com o formato do tipo
// `SessionMeasureInput`. A logica de decisao tem bateria propria em Node
// (hooks/testa-mod-compactar.cjs); aqui se prova a FIACAO: o evento certo, o limiar, o
// subagente da barra, a opcao desligada e o rearme quando o engine recusa.
import { test, expect, mock } from 'claude-code/testing'

const USAGE_REAL = { input_tokens: 2, cache_creation_input_tokens: 45815, cache_read_input_tokens: 30782, output_tokens: 273, model: 'claude-opus-5-5' }

const saida = (stdout: string, exitCode = 0) => ({
  value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'recusado', isStdoutTruncated: false, isStderrTruncated: false },
})

type Surface = 'terminal' | 'desktop'
type Modo = 'ok' | 'rejeita'

async function montar($: any, on: any, surface: Surface) {
  mock.clock(on, { now: 1760000000000 })
  const s = {
    compacts: 0,
    modo: 'ok' as Modo,
    toasts: [] as string[],
  }
  on('process.run', async (_$: any, e: any) => {
    // O localizador (where.exe) acha o node fora de qualquer repositorio; os scripts dao vazio.
    if (/[\\/]where\.exe$/i.test(String(e.argv[0]))) return saida('C:\\Program Files\\nodejs\\node.exe\r\n')
    return saida('{"fluxos":[]}')
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.id', async () => ({ value: 'sessao-atual' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', async () => ({ sessionId: 'sessao-atual' }) as never)
  on('command.register', async () => ({ value: { command: 'painel' } }) as never)
  on('session.usage', async () => ({ value: { startedAt: 0, context: { tokens: 1, window: 200000, percent: 1 }, rateLimits: [] } }) as never)
  on('turn.complete', async () => ({ text: '' }))
  on('agent.spawn', async () => ({ model: 'haiku', agentId: 'ag-1' }) as never)
  on('ui.toast', async (_$: any, e: any) => {
    s.toasts.push(String(e.text))
    return { value: undefined } as never
  })
  // Fundo da cadeia: o engine ecoa o que mudou.
  on('session.measure', async (_$: any, e: any) => ({ changed: e.changed }) as never)
  on('session.compact', async () => {
    s.compacts += 1
    if (s.modo === 'rejeita') throw new Error('um turno esta em curso')
    return { messages: [{ role: 'user', text: 'resumo', toolUses: [] }], tokensBefore: 150000, tokensAfter: 20000 } as never
  })
  const medir = async (percent: number, changed: string[] = ['context']) => {
    await $.session.measure({ context: { window: 200000, percent }, rateLimits: [], changed } as never)
    // A compactacao e a ultima coisa que o hook faz, sem await: deixa a promessa assentar.
    for (let i = 0; i < 5; i++) await Promise.resolve()
  }
  let n = 0
  const terminar = (extra: Record<string, unknown> = {}) =>
    $.turn.complete({ answer: 'feito', durationMs: 1, isAborted: false, turnId: `t${++n}`, reason: 'answer', ...extra } as never)
  const comecar = () => $.session.start({ cwd: '/projeto', surface, isInteractive: true })
  const caso = async (nome: string, fn: () => Promise<void>) => {
    try {
      await fn()
    } catch (err) {
      throw new Error(`[${surface}] ${nome}: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  return { s, medir, terminar, comecar, caso }
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`compacta uma vez por subida (${surface})`, async ($, on) => {
    const { s, medir, comecar, caso } = await montar($, on, surface)
    await comecar()
    await caso('30 -> 61 -> 61: uma compactacao so', async () => {
      await medir(30)
      expect(s.compacts).toBe(0)
      await medir(61)
      expect(s.compacts).toBe(1)
      await medir(61)
      expect(s.compacts).toBe(1)
      expect(s.toasts).toEqual(['compactado em 61%'])
    })
    await caso('so o contexto conta: measure sem `context` em changed nao compacta', async () => {
      await medir(20)
      await medir(70, ['cost'])
      expect(s.compacts).toBe(1)
    })
    await caso('desce abaixo do limiar e sobe de novo: segunda compactacao', async () => {
      await medir(65)
      expect(s.compacts).toBe(2)
    })
  })

  test(`agente rodando: avisa e nao compacta (${surface})`, async ($, on) => {
    const { s, medir, terminar, comecar, caso } = await montar($, on, surface)
    await comecar()
    await medir(30)
    await caso('com subagente em andamento a 61%: um toast, nenhuma compactacao', async () => {
      await $.agent.spawn({ prompt: 'p', description: 'revisar o diff', subagentType: 'general-purpose', tool_use_id: 'u1' } as never)
      await medir(61)
      expect(s.compacts).toBe(0)
      expect(s.toasts).toEqual(['contexto em 61%: agente rodando, compacto quando ele voltar (ou faça a passagem)'])
      await medir(62)
      expect(s.compacts).toBe(0)
      expect(s.toasts.length).toBe(1)
    })
    await caso('o subagente termina: o proximo measure compacta', async () => {
      await terminar({ agentId: 'ag-1', usage: { ...USAGE_REAL, model: 'haiku' } })
      await medir(63)
      expect(s.compacts).toBe(1)
    })
  })

  test(`desligado nunca compacta (${surface})`, { options: { compactarSozinho: false } }, async ($, on) => {
    const { s, medir, comecar } = await montar($, on, surface)
    await comecar()
    await medir(30)
    await medir(61)
    await medir(95)
    expect(s.compacts).toBe(0)
    expect(s.toasts).toEqual([])
  })

  test(`limiar da opcao compactarEm (${surface})`, { options: { compactarEm: 80 } }, async ($, on) => {
    const { s, medir, comecar } = await montar($, on, surface)
    await comecar()
    await medir(30)
    await medir(79)
    expect(s.compacts).toBe(0)
    await medir(80)
    expect(s.compacts).toBe(1)
  })

  test(`compactacao rejeitada rearma (${surface})`, async ($, on) => {
    const { s, medir, comecar, caso } = await montar($, on, surface)
    await comecar()
    await medir(30)
    await caso('o engine recusa (turno em curso): tenta, avisa uma vez e fica armado', async () => {
      s.modo = 'rejeita'
      await medir(61)
      expect(s.compacts).toBe(1)
      expect(s.toasts).toEqual(['compactação adiada (turno em curso)'])
      await medir(62)
      expect(s.compacts).toBe(2)
      expect(s.toasts).toEqual(['compactação adiada (turno em curso)'])
    })
    await caso('o turno acaba: o measure seguinte compacta', async () => {
      s.modo = 'ok'
      await medir(63)
      expect(s.compacts).toBe(3)
      expect(s.toasts[s.toasts.length - 1]).toBe('compactado em 63%')
    })
  })
}
