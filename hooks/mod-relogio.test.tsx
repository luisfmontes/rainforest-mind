// Prova de engine do relogio do mod (jornada e janela parada), agora uma figura da barra:
// `claude plugin test <raiz>`. "Quieta" quer dizer sem o ⏰ na barra; "escondida" e a barra
// inteira calada por `/painel esconder` (D9: so volta com `/painel mostrar`).
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

const DADOS_FAIXA = { fluxos: [{ slug: '2026-10-03-faixa-teste', etapa: 'executar', tarefas_ok: 1, tarefas: 3, em_voo: ['agente-a'] }] }
const VAZIO = { fluxos: [] }

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
  // A conferencia de recarga do plugins-em-dia (timer de 5 s) desligada pelo kill switch dela: o
  // relogio simulado comprime horas, e cada disparo de timer custa ~50 ms no harness (este teste
  // nao e sobre recarga; a prova dela e hooks/mod-recarga.test.tsx).
  mock.env(on, { RAINFOREST_RECARGA: 'off' })
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
    cwdS: [] as unknown[],
    cwdJ: [] as unknown[],
    faixa: dadosFaixa,
    ctx: [] as string[],
    sessaoId: 'sessao-atual',
    // #480: localizadores do node rodados, e o modo em que nenhum acha.
    loc: 0,
    semNode: false,
  }
  const resposta = (modo: Modo, corpo: unknown) => {
    if (modo === 'exit1') return saida('', 1)
    if (modo === 'exit2') return saida(JSON.stringify({ escopo: 'tudo', mensagens: 0, erro: 'sem mensagem humana no dia' }), 2)
    if (modo === 'lixo') return saida('isto nao e json')
    return saida(JSON.stringify(corpo))
  }
  on('process.run', async (_$: any, e: any) => {
    // O localizador (where.exe, ou which fora do Windows) acha o node fora de qualquer
    // repositorio; nao e um dos scripts. Com semNode nenhum dos dois acha.
    if (/[\\/]where\.exe$/i.test(String(e.argv[0])) || e.argv[0] === '/usr/bin/which') {
      s.loc += 1
      return s.semNode ? saida('', 1) : saida('C:\\Program Files\\nodejs\\node.exe\r\n')
    }
    const alvo = String(e.argv[1] ?? '')
    if (alvo.endsWith('relogio-sessoes.cjs')) {
      s.runsS += 1
      s.argvS.push([...e.argv])
      s.cwdS.push(e.init?.cwd)
      return resposta(s.modoS, s.sessoes)
    }
    if (alvo.endsWith('jornada.cjs')) {
      s.runsJ += 1
      s.voo += 1
      s.cwdJ.push(e.init?.cwd)
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
  on('session.id', async () => ({ value: s.sessaoId }))
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
  // A barra segue desenhada, sem o relogio.
  const quieta = async () => {
    expect(await juntos()).not.toContain('⏰')
    expect(await ui.find({ type: 'Button' })).toBeUndefined()
  }
  // A barra inteira calada (`/painel esconder`).
  const escondida = async () => {
    expect(await textos()).toEqual([])
  }
  const painel = (args: string) => $.command.run({ command: 'painel', args } as never)
  const comecar = (interativo = true) => $.session.start({ cwd: '/projeto', surface, isInteractive: interativo })
  const terminarSessao = () => $.session.end({ reason: 'other', sessionId: 'sessao-atual' } as never)
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
  return { relogio, s, ui, textos, juntos, quieta, escondida, painel, comecar, terminarSessao, terminar, caso, enviar }
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`relogio (${surface}): linha, minutos, esconder, nota e virada do dia`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, juntos, quieta, escondida, painel, comecar, terminarSessao, caso, enviar } = m

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
      expect(await ui.find({ type: 'Button' })).toBeUndefined()
    })

    await caso('11 o argv da leitura de janelas leva --sessao com o id de $.session.id()', async () => {
      expect(s.runsS).toBeGreaterThan(0)
      const argv = s.argvS[0]
      expect(argv[argv.indexOf('--sessao') + 1]).toBe('sessao-atual')
      expect(argv[argv.indexOf('--cwd') + 1]).toBe('/projeto')
    })

    await caso('6 /painel esconder deixa a barra escondida', async () => {
      await painel('esconder')
      await escondida()
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

    await caso('3 janela parada ha 32 min aparece na barra (apos /painel mostrar), com a pasta', async () => {
      await painel('mostrar')
      s.sessoes = sessoesJson(30, [{ cwd: '/projetos/loja-api', desde: em(20, 41) - 32 * MIN }])
      await relogio.advance(58000) // 20h41:00: o tick de 60 s le as janelas
      const t = await juntos()
      expect(t).toContain('loja-api parada há 32 min')
      expect(t).toContain('jornada 9h12')
      expect(t).not.toContain('(+')
    })

    await caso('4 advance(60000) muda 32 min para 33 min e esconder nao volta com os minutos', async () => {
      await relogio.advance(60000)
      expect(await juntos()).toContain('loja-api parada há 33 min')
      await painel('esconder')
      await escondida()
      await relogio.advance(60000) // 34 min: so os minutos mudaram
      await escondida()
    })

    await caso('3 duas janelas acima do limite: a mais antiga nomeada e (+1)', async () => {
      await painel('mostrar')
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
      await painel('esconder')
      await escondida()
      await relogio.advance(300000)
      await escondida()
    })

    await caso('6 outra janela virando a mais parada aparece depois de /painel mostrar', async () => {
      await painel('mostrar')
      s.sessoes = sessoesJson(30, [
        { cwd: '/projetos/loja-api', desde: em(20, 41) - 32 * MIN },
        { cwd: '/projetos/api-x', desde: em(20, 40) - 200 * MIN },
      ])
      await relogio.advance(60000)
      expect(await juntos()).toContain('api-x parada há')
    })

    await caso('6 so a jornada, escondida, e a virada do dia com /painel mostrar acende a jornada', async () => {
      s.sessoes = sessoesJson(30, [])
      await relogio.advance(60000)
      const t = await juntos()
      expect(t).toContain('jornada 9h12')
      expect(t).not.toContain('parada')
      await painel('esconder')
      await escondida()
      await relogio.advance(300000)
      await escondida()
      // dia seguinte, 20h40: a sessao reabre (sem 1.440 ticks no meio)
      await terminarSessao()
      await relogio.set(em(20, 40, 4))
      s.jornada = jornadaJson(552, em(20, 35, 4))
      await comecar()
      await painel('mostrar')
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
      expect(await juntos()).toContain('⏰')
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): o process.run do relogio roda com cwd na raiz do plugin`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, caso } = m

    await caso('12 relogio-sessoes e jornada rodam com cwd na raiz do plugin, nao na pasta da sessao', async () => {
      await comecar()
      await relogio.advance(2000)
      expect(s.cwdS.length).toBeGreaterThan(0)
      expect(s.cwdJ.length).toBeGreaterThan(0)
      // argv[1] = <raiz>/scripts/<script>.cjs: a raiz sai dele, sem supor o valor de $.plugin.root.
      const raiz = s.argvS[0][1].replace(/[\\/]scripts[\\/]relogio-sessoes\.cjs$/, '')
      expect(raiz).not.toBe(s.argvS[0][1])
      expect(raiz).not.toBe('/projeto')
      for (const c of [...s.cwdS, ...s.cwdJ]) expect(c).toBe(raiz)
      // a pasta da sessao segue indo por --cwd
      expect(s.argvS[0][s.argvS[0].indexOf('--cwd') + 1]).toBe('/projeto')
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): localizador do node que falhou nao roda de novo no prazo`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, caso } = m

    await caso('16 sem node: uma busca, nenhuma outra em 5 min, e de novo depois do prazo', async () => {
      s.semNode = true
      await comecar()
      await relogio.advance(2000)
      const primeira = s.loc
      expect(primeira).toBeGreaterThan(0)
      // sem node, os scripts do relogio nao rodam (falha aberta)
      expect(s.runsS + s.runsJ).toBe(0)
      await relogio.advance(4 * MIN)
      expect(s.loc).toBe(primeira)
      await relogio.advance(2 * MIN)
      expect(s.loc).toBeGreaterThan(primeira)
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

  test(`relogio (${surface}): session.end de outra sessao nao cancela os timers`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, caso } = m

    await caso('D2 session.end com outro sessionId deixa o relogio armado', async () => {
      await comecar()
      await relogio.advance(2000)
      await $.session.end({ reason: 'other', sessionId: 'outra-sessao' } as never)
      const antes = s.runsS
      await relogio.advance(60000)
      expect(s.runsS).toBeGreaterThan(antes)
    })

    await ui.unmount()
  })

  test(`relogio (${surface}): clear mantem o relogio e troca o --sessao`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, comecar, caso } = m

    await caso('D3 /clear mantem os timers e passa a ler com o id novo', async () => {
      await comecar()
      await relogio.advance(2000)
      s.sessaoId = 'sessao-nova'
      await $.session.end({ reason: 'clear', sessionId: 'sessao-atual' } as never)
      const antes = s.runsS
      await relogio.advance(60000)
      expect(s.runsS).toBeGreaterThan(antes)
      const argv = s.argvS[s.argvS.length - 1]
      expect(argv[argv.indexOf('--sessao') + 1]).toBe('sessao-nova')
    })

    await caso('D3 o session.end da sessao nova cancela os timers', async () => {
      await $.session.end({ reason: 'other', sessionId: 'sessao-nova' } as never)
      const antes = { s: s.runsS, j: s.runsJ }
      await relogio.advance(120000)
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

  test(`relogio (${surface}): largura (o relogio cabe em cada Text e e o ultimo a cair)`, async ($, on) => {
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

    await caso('13 com 40 colunas e so a jornada, o relogio fica depois do estado e as outras figuras cedem', async () => {
      s.sessoes = sessoesJson(30, [])
      await relogio.advance(60000) // o tick de 60 s le as janelas: nenhuma parada
      await ui.redraw({ ...PROPS, bodyColumns: 40 })
      const t = await textos()
      expect(t.length).toBe(2)
      expect(t[0]).toBe('○ pronto')
      expect(t[1]).toContain('jornada 9h12')
      expect(t.some(linha => linha.includes('foco') || linha.includes('fluxo') || linha.includes('Q1'))).toBe(false)
      for (const linha of t) expect(largura(linha)).toBeLessThanOrEqual(40)
      await ui.redraw(PROPS)
    })

    await ui.unmount()
  })
}
