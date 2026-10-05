// Prova de engine do relogio do mod (jornada e janela parada): `claude plugin test <raiz>`.
// O engine carrega hooks/mod.tsx de verdade; por baixo dos plugins respondem `process.run`
// (a saida dos dois scripts, escolhida pelo argv), `session.cwd`, `session.id` e o relogio
// simulado de `mock.clock` (so anda quando o teste manda).
// Um `test` por surface para a sequencia longa (cada caso herda o estado do anterior: a
// ordem e parte do contrato) e um `test` por surface para cada caso que precisa de estado
// novo (falha, nao interativo, session.end, leitura lenta, limiares, largura).
// Os dados nao sao inventados: FIXTURE_SESSOES e FIXTURE_JORNADA sao a saida REAL de
// `scripts/relogio-sessoes.cjs` e de `scripts/jornada.cjs --json` (hooks/testa-mod-relogio.cjs
// confere que as chaves seguem as dos scripts); so os valores que cada caso varia mudam
// (os `desde` em ms foram zerados na copia: o valor de cada caso vem de sessoesJson).
import { test, expect, mock } from 'claude-code/testing'
import { largura } from './faixa-puro.mjs'

const FIXTURE_SESSOES = {"ociosidade_min":45,"janelas":[{"cwd":"/projetos/painel","desde":0},{"cwd":"/projetos/loja-api","desde":0}]}
const FIXTURE_JORNADA = {"escopo":"s.jsonl","mensagens":13,"efetiva_min":552,"bruto_min":552,"primeiro":"2026-10-03T11:18:00-03:00","ultimo":"2026-10-03T20:30:00-03:00","corte_min":55,"descartadas":[]}

const DADOS_FAIXA = { foco: '🚀 Lancar faixa', fluxos: [{ slug: '2026-10-03-faixa-teste', etapa: 'executar', tarefas_ok: 1, tarefas: 3, em_voo: ['agente-a'] }] }
const VAZIO = { foco: null, fluxos: [] }

const ANSWER = `> ❓ **Q1 — Onde o token vive**: sessão no servidor ou JWT no cliente?
> ➡️ **Recomendo:** sessão no servidor.
>
> ❓ **Q2 — Expiração**: 15 min com refresh, ou 8h fixas?
> ➡️ **Recomendo:** 8h fixas.
`

const MIN = 60000
const em = (h: number, m: number, dia = 3) => new Date(2026, 9, dia, h, m).getTime()

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 20 },
  view: {},
}

const saida = (stdout: string, exitCode = 0) => ({
  value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'recusado', isStdoutTruncated: false, isStderrTruncated: false },
})

const jornadaJson = (efetiva_min: number, ultimo_ms: number) => ({
  ...FIXTURE_JORNADA,
  efetiva_min,
  bruto_min: efetiva_min,
  ultimo: new Date(ultimo_ms).toISOString(),
})
const sessoesJson = (ociosidade_min: number, janelas: { cwd: string; desde: number }[]) => ({ ...FIXTURE_SESSOES, ociosidade_min, janelas })

type Modo = 'ok' | 'exit1' | 'exit2' | 'lixo' | 'lenta'
type Surface = 'terminal' | 'desktop'

// Monta o mundo por baixo do mod e a tela montada; devolve o que os casos usam.
async function montar($: any, on: any, surface: Surface, inicio: number, dadosFaixa: unknown = VAZIO) {
  const relogio = mock.clock(on, { now: inicio })
  const s = {
    jornada: jornadaJson(552, inicio - 10 * MIN) as unknown,
    sessoes: sessoesJson(45, []) as unknown,
    modoJ: 'ok' as Modo,
    modoS: 'ok' as Modo,
    runsJ: 0,
    runsS: 0,
    voo: 0,
    maxVoo: 0,
    argvS: [] as string[][],
    faixa: dadosFaixa,
    ctx: [] as string[],
  }
  const resposta = (modo: Modo, corpo: unknown) => {
    if (modo === 'exit1') return saida('', 1)
    if (modo === 'exit2') return saida(JSON.stringify({ escopo: 'tudo', mensagens: 0, erro: 'sem mensagem humana no dia' }), 2)
    if (modo === 'lixo') return saida('isto nao e json')
    return saida(JSON.stringify(corpo))
  }
  on('process.run', async (_$: any, e: any) => {
    const alvo = String(e.argv[1] ?? '')
    if (alvo.endsWith('relogio-sessoes.cjs')) {
      s.runsS += 1
      s.argvS.push([...e.argv])
      return resposta(s.modoS, s.sessoes)
    }
    if (alvo.endsWith('jornada.cjs')) {
      s.runsJ += 1
      s.voo += 1
      s.maxVoo = Math.max(s.maxVoo, s.voo)
      try {
        if (s.modoJ === 'lenta') await relogio.sleep(400000)
        return resposta(s.modoJ === 'lenta' ? 'ok' : s.modoJ, s.jornada)
      } finally {
        s.voo -= 1
      }
    }
    return saida(JSON.stringify(s.faixa))
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.id', async () => ({ value: 'sessao-atual' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', async () => ({ sessionId: 'sessao-atual' }) as never)
  on('turn.complete', async () => ({ text: '' }))
  // Fundo da cadeia: guarda o `context` que chegou ate aqui (o que o modelo leria).
  on('prompt.submit', async (_$: any, e: any) => {
    s.ctx = [...(e.context ?? [])]
    return e as never
  })
  on('ui.render', async (t$: any, e: any) => {
    const { Box } = t$.ui.resolve(e)
    return <Box />
  })

  const ui = await $.ui.mount({ plugin: 'rainforest-mind', surface, component: 'AbovePrompt', props: PROPS })
  const todos = async () => (await ui.findAll({ type: 'Text' })).map((t: any) => t.text as string)
  const textos = async () => {
    const t = await todos()
    // Caso 14: o texto do relogio nunca traz o aviso da regra 8 nem a palavra agua.
    for (const linha of t) {
      expect(linha).not.toContain('ponto de parada')
      expect(linha).not.toContain('água')
    }
    return t
  }
  const juntos = async () => (await textos()).join('\n')
  const botao = () => ui.find({ type: 'Button', key: 'esconder' })
  const quieta = async () => {
    expect(await textos()).toEqual([])
    expect(await botao()).toBeUndefined()
  }
  const comecar = (interativo = true) => $.session.start({ cwd: '/projeto', surface, isInteractive: interativo })
  const terminarSessao = () => $.session.end({ reason: 'other' } as never)
  let n = 0
  const terminar = (answer: string) =>
    $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: `t${++n}`, reason: 'answer' } as never)
  const caso = async (nome: string, fn: () => Promise<void>) => {
    try {
      await fn()
    } catch (err) {
      throw new Error(`[${surface}] ${nome}: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  // Envia um prompt e devolve o `context` que chegou ao fundo.
  const enviar = async (prompt: string, origin?: { kind: string }) => {
    s.ctx = []
    await $.prompt.submit((origin === undefined ? { text: prompt } : { text: prompt, origin }) as never)
    return s.ctx
  }
  return { relogio, s, ui, textos, juntos, botao, quieta, comecar, terminarSessao, terminar, caso, enviar }
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`relogio (${surface}): linha, minutos, esconder, nota e virada do dia`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, juntos, quieta, botao, comecar, terminarSessao, caso, enviar } = m

    await caso('1 quieta antes de qualquer tick', async () => {
      await quieta()
      await comecar()
      await quieta()
      expect(s.runsS + s.runsJ).toBe(0)
    })

    await caso('2 jornada acende depois de session.start + advance(2000), com 552 min e mensagem as 20h30', async () => {
      s.jornada = jornadaJson(552, em(20, 30))
      await relogio.advance(2000)
      const t = await juntos()
      expect(t).toContain('jornada 9h12')
      expect(t).toContain('20h40')
      expect(t).not.toContain('parada')
      expect(await botao()).toBeDefined()
    })

    await caso('11 o argv da leitura de janelas leva --sessao com o id de $.session.id()', async () => {
      expect(s.runsS).toBeGreaterThan(0)
      const argv = s.argvS[0]
      expect(argv[argv.indexOf('--sessao') + 1]).toBe('sessao-atual')
      expect(argv[argv.indexOf('--cwd') + 1]).toBe('/projeto')
    })

    await caso('6 esconder deixa quieta', async () => {
      await ui.press({ key: 'esconder' })
      await quieta()
    })

    await caso('7 loop_wakeup, system e sdk nao gastam a nota', async () => {
      for (const kind of ['loop_wakeup', 'schedule_wakeup', 'system', 'sdk', 'task-notification', 'bridge']) {
        expect(await enviar('tick', { kind })).toEqual([])
      }
    })

    await caso('7 o primeiro prompt do usuario do dia leva a nota, mesmo com a faixa escondida', async () => {
      const c = (await enviar('oi', { kind: 'composer' })).join('\n')
      expect(c).toContain('regra 8')
      expect(c).toContain('9h12')
      expect(c).toContain('20h40')
    })

    await caso('a nota chega uma vez so: o segundo prompt do dia vai sem ela', async () => {
      expect(await enviar('de novo', { kind: 'composer' })).toEqual([])
      expect(await enviar('sem origin')).toEqual([])
    })

    await caso('3 janela parada ha 32 min traz a faixa de volta, com a pasta', async () => {
      s.sessoes = sessoesJson(30, [{ cwd: '/projetos/loja-api', desde: em(20, 41) - 32 * MIN }])
      await relogio.advance(58000) // 20h41:00: o tick de 60 s le as janelas
      const t = await juntos()
      expect(t).toContain('loja-api parada há 32 min')
      expect(t).toContain('jornada 9h12')
      expect(t).not.toContain('(+')
    })

    await caso('4 advance(60000) muda 32 min para 33 min e a assinatura nao muda (esconder segue valendo)', async () => {
      await relogio.advance(60000)
      expect(await juntos()).toContain('loja-api parada há 33 min')
      await ui.press({ key: 'esconder' })
      await quieta()
      await relogio.advance(60000) // 34 min: so os minutos mudaram
      await quieta()
    })

    await caso('3 duas janelas acima do limite: a mais antiga nomeada e (+1), e isso traz de volta', async () => {
      s.sessoes = sessoesJson(30, [
        { cwd: '/projetos/loja-api', desde: em(20, 41) - 32 * MIN },
        { cwd: '/projetos/painel', desde: em(20, 40) - 100 * MIN },
      ])
      await relogio.advance(60000)
      const t = await juntos()
      expect(t).toContain('painel parada há')
      expect(t).toContain('(+1)')
    })

    await caso('6 esconder segue valendo com advance(300000) e a mesma jornada', async () => {
      await ui.press({ key: 'esconder' })
      await quieta()
      await relogio.advance(300000)
      await quieta()
    })

    await caso('6 outra janela virando a mais parada traz de volta', async () => {
      s.sessoes = sessoesJson(30, [
        { cwd: '/projetos/loja-api', desde: em(20, 41) - 32 * MIN },
        { cwd: '/projetos/api-x', desde: em(20, 40) - 200 * MIN },
      ])
      await relogio.advance(60000)
      expect(await juntos()).toContain('api-x parada há')
    })

    await caso('6 so a jornada, escondida, e a virada do dia traz a jornada de volta', async () => {
      s.sessoes = sessoesJson(30, [])
      await relogio.advance(60000)
      const t = await juntos()
      expect(t).toContain('jornada 9h12')
      expect(t).not.toContain('parada')
      await ui.press({ key: 'esconder' })
      await quieta()
      await relogio.advance(300000)
      await quieta()
      // dia seguinte, 20h40: a sessao reabre (sem 1.440 ticks no meio)
      await terminarSessao()
      await relogio.set(em(20, 40, 4))
      s.jornada = jornadaJson(552, em(20, 35, 4))
      await comecar()
      await relogio.advance(2000)
      expect(await juntos()).toContain('jornada 9h12')
    })

    await caso('7 o dia seguinte entrega outra nota, e so uma', async () => {
      const c = (await enviar('bom dia', { kind: 'composer' })).join('\n')
      expect(c).toContain('regra 8')
      expect(c).toContain('9h12')
      expect(await enviar('outra', { kind: 'composer' })).toEqual([])
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): limiares, 8h59 as 14h e 8h00 as 20h com mensagem ha 31 min`, async ($, on) => {
    const m = await montar($, on, surface, em(14, 0))
    const { relogio, s, ui, quieta, comecar, terminarSessao, caso } = m

    await caso('5 8h59 as 14h deixa quieta', async () => {
      s.jornada = jornadaJson(539, em(13, 55))
      await comecar()
      await relogio.advance(2000)
      expect(s.runsJ).toBe(1)
      await quieta()
    })

    await caso('5 8h00 as 20h com mensagem ha 31 min deixa quieta', async () => {
      await terminarSessao()
      await relogio.set(em(20, 0))
      s.jornada = jornadaJson(480, em(20, 0) - 31 * MIN)
      await comecar()
      await relogio.advance(2000)
      expect(s.runsJ).toBe(2)
      await quieta()
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): falha de leitura apaga so a linha, sem excecao`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, textos, juntos, quieta, comecar, caso } = m

    await caso('8 dados bons acendem as duas partes', async () => {
      s.jornada = jornadaJson(552, em(20, 30))
      s.sessoes = sessoesJson(30, [{ cwd: '/projetos/loja-api', desde: em(20, 40) - 32 * MIN }])
      await comecar()
      await relogio.advance(2000)
      const t = await juntos()
      expect(t).toContain('jornada 9h12')
      expect(t).toContain('loja-api parada')
    })

    await caso('8 process.run exit 1 na jornada apaga so a jornada', async () => {
      s.modoJ = 'exit1'
      await relogio.advance(300000)
      const t = await juntos()
      expect(t).not.toContain('jornada')
      expect(t).toContain('loja-api parada')
    })

    await caso('8 jornada.cjs exit 2 (sem mensagem no dia) tambem, sem excecao', async () => {
      s.modoJ = 'exit2'
      await relogio.advance(300000)
      const t = await juntos()
      expect(t).not.toContain('jornada')
      expect(t).toContain('loja-api parada')
    })

    await caso('8 saida que nao e JSON apaga a leitura de janelas', async () => {
      s.modoS = 'lixo'
      await relogio.advance(60000)
      await quieta()
    })

    await caso('8 a leitura volta quando o script volta', async () => {
      s.modoS = 'ok'
      s.modoJ = 'ok'
      await relogio.advance(300000)
      expect((await textos()).length).toBeGreaterThan(0)
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): session.start nao interativo nao arma o relogio`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, quieta, comecar, caso } = m

    await caso('9 isInteractive false nao dispara nenhum process.run do relogio', async () => {
      s.jornada = jornadaJson(552, em(20, 30))
      await comecar(false)
      await relogio.advance(600000)
      expect(s.runsS).toBe(0)
      expect(s.runsJ).toBe(0)
      await quieta()
    })

    await caso('9b session.start nao interativo depois do interativo nao cancela o relogio', async () => {
      await comecar(true)
      await relogio.advance(2000)
      await comecar(false)
      const antes = s.runsS
      await relogio.advance(60000)
      expect(s.runsS).toBeGreaterThan(antes)
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): session.end cancela os timers`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, terminarSessao, caso } = m

    await caso('10 depois de session.end o advance nao chama process.run', async () => {
      await comecar()
      await relogio.advance(2000)
      expect(s.runsS).toBeGreaterThan(0)
      expect(s.runsJ).toBeGreaterThan(0)
      await terminarSessao()
      const antes = { s: s.runsS, j: s.runsJ }
      await relogio.advance(600000)
      expect(s.runsS).toBe(antes.s)
      expect(s.runsJ).toBe(antes.j)
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): leitura lenta de jornada nao e reentrada`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, caso } = m

    await caso('12 um tick de 5 min no meio da leitura lenta nao empilha outra', async () => {
      s.modoJ = 'lenta'
      await comecar()
      await relogio.advance(2000) // a primeira leitura comeca e dorme 400 s
      expect(s.runsJ).toBe(1)
      await relogio.advance(300000) // o tick de 5 min cai com ela em voo
      expect(s.runsJ).toBe(1)
      expect(s.maxVoo).toBe(1)
      await relogio.advance(100000) // a primeira termina (402 s)
      await relogio.advance(200000) // o tick de 600 s le de novo
      expect(s.runsJ).toBe(2)
      expect(s.maxVoo).toBe(1)
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): largura e linhas (Q e relogio sobram quando falta espaco)`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), DADOS_FAIXA)
    const { relogio, s, ui, textos, juntos, comecar, terminar, caso } = m

    await caso('13 com bodyColumns 30 cada Text cabe em 30 celulas', async () => {
      s.jornada = jornadaJson(552, em(20, 30))
      s.sessoes = sessoesJson(30, [{ cwd: '/projetos/loja-api-com-nome-bem-comprido', desde: em(20, 40) - 32 * MIN }])
      await comecar()
      await terminar(ANSWER)
      await relogio.advance(2000)
      expect(await juntos()).toContain('jornada 9h12')
      await ui.redraw({ ...PROPS, bodyColumns: 30 })
      const t = await textos()
      expect(t.length).toBeGreaterThan(0)
      for (const linha of t) expect(largura(linha)).toBeLessThanOrEqual(30)
      await ui.redraw(PROPS)
    })

    await caso('13 com maxRows 3 sobram Q e relogio (foco e fluxo cedem)', async () => {
      await ui.redraw({ ...PROPS, maxRows: 3 })
      const t = await textos()
      expect(t.length).toBe(2)
      expect(t.some(linha => linha.includes('Q1 Onde o token vive'))).toBe(true)
      expect(t.some(linha => linha.includes('jornada 9h12'))).toBe(true)
      expect(t.some(linha => linha.includes('Lancar faixa'))).toBe(false)
      expect(t.some(linha => linha.includes('fluxo faixa-teste'))).toBe(false)
      await ui.redraw(PROPS)
    })

    await ui.unmount()
  })
}
