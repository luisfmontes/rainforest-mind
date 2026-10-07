// Prova de engine da barra de sessao acima do prompt e do /painel: `claude plugin test <raiz>`.
// O engine carrega hooks/mod.tsx de verdade e monta `AbovePrompt` em cada surface; por baixo
// dos plugins respondem `process.run` (a saida dos scripts, escolhida pelo argv),
// `session.usage`, `session.cwd`, `session.id`, o fundo de cada evento chamado e o relogio
// simulado de `mock.clock` (so anda quando o teste manda).
// Um `test` por surface para a sequencia longa (`$.state` dura a sessao de teste inteira, entao
// cada caso herda o estado do anterior: a ordem e parte do contrato) e um por surface para o que
// precisa de estado novo (falha aberta, largura, nao interativo).
// Os dados nao sao inventados: FIXTURE_DADOS e a saida REAL de `scripts/faixa-dados.cjs` sobre
// um repo temporario e FIXTURE_JORNADA/FIXTURE_SESSOES as de `scripts/jornada.cjs --json` e
// `scripts/relogio-sessoes.cjs` (hooks/testa-mod-painel.cjs confere que as chaves da
// FIXTURE_DADOS seguem as do script); USAGE_REAL e o `usage` do 1o turno de um transcript real
// desta maquina (claude-opus-5-5, 2 + 45815 + 30782 = 76599 tokens de contexto, cache de 1 h).
// INFERIDO ate a medicao em REPL real (tarefa 11): a forma do `session.usage` (SESSION_USAGE,
// vinda dos tipos `SessionUsage` e `ContextBreakdownDetail`) e os rotulos das fatias.
import { test, expect, mock } from 'claude-code/testing'
import { largura } from './faixa-puro.mjs'

// Saida real do script; so o campo `worktree` (caminho da caixa temporaria) foi trocado por um
// caminho neutro.
const FIXTURE_DADOS = {"fluxos":[{"slug":"2026-10-03-faixa-teste","titulo":"Faixa de teste","etapa":"executar","tarefas_ok":1,"tarefas":3,"em_voo":["agente-a"],"criado_em":"2026-10-03","worktree":"C:/tmp/faixa-repo-OdhnjD"}]}
const FIXTURE_SESSOES = {"ociosidade_min":45,"janelas":[{"cwd":"/projetos/painel","desde":0},{"cwd":"/projetos/loja-api","desde":0}]}
const FIXTURE_JORNADA = {"escopo":"s.jsonl","mensagens":13,"efetiva_min":552,"bruto_min":552,"primeiro":"2026-10-03T11:18:00-03:00","ultimo":"2026-10-03T20:30:00-03:00","corte_min":55,"descartadas":[]}

const USAGE_REAL = { input_tokens: 2, cache_creation_input_tokens: 45815, cache_read_input_tokens: 30782, output_tokens: 273, model: 'claude-opus-5-5' }

const SESSION_USAGE = (percent: number, tokens: number, usd: number) => ({
  startedAt: 0,
  context: {
    tokens,
    window: 200000,
    percent,
    breakdown: {
      percentage: percent,
      totalTokens: tokens,
      maxTokens: 200000,
      rawMaxTokens: 200000,
      categories: [
        { name: 'Mensagens', tokens: Math.round(tokens / 2), color: 'a', isDeferred: false, kind: 'used' },
        { name: 'Ferramentas', tokens: Math.round(tokens * 0.3), color: 'b', isDeferred: false, kind: 'used' },
        { name: 'Sistema', tokens: Math.round(tokens * 0.2), color: 'c', isDeferred: false, kind: 'used' },
        { name: 'Livre', tokens: 200000 - tokens, color: 'd', isDeferred: false, kind: 'free' },
      ],
    },
  },
  rateLimits: [],
  cost: { usd },
})

// Texto real do exemplo de Q1 e Q2 do README.md: a barra nao tem mais linha de Q (D2).
const ANSWER = `Você pede uma feature. Em vez de sair codificando, vem uma rodada numerada,
cada pergunta **já com a resposta recomendada**:

> ❓ **Q1 — Onde o token vive**: sessão no servidor ou JWT no cliente?
> ➡️ **Recomendo:** sessão no servidor — você já tem Redis.
`

const MIN = 60000
const em = (h: number, m: number, dia = 3) => new Date(2026, 9, dia, h, m).getTime()

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 200,
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

type Surface = 'terminal' | 'desktop'

// Monta o mundo por baixo do mod e a tela montada; devolve o que os casos usam.
// `comUi: false` deixa a tela por montar (`abrir()`): um avanco longo do relogio redesenharia a
// barra a cada segundo, e sem tela montada o teste fica rapido.
async function montar($: any, on: any, surface: Surface, inicio: number, comUi = true) {
  const relogio = mock.clock(on, { now: inicio })
  const s = {
    jornada: jornadaJson(552, inicio - 10 * MIN) as unknown,
    sessoes: { ...FIXTURE_SESSOES, janelas: [] } as unknown,
    modoJornada: 'ok' as 'ok' | 'falha',
    modoDados: 'ok' as 'ok' | 'falha',
    usage: SESSION_USAGE(38, 76599, 0.42) as unknown,
    modoUsage: 'ok' as 'ok' | 'falha',
    usageCalls: 0,
    dados: [] as { argv: readonly string[]; cwd: unknown }[],
    runs: 0,
    passos: 0,
  }
  on('process.run', async (_$: any, e: any) => {
    s.runs += 1
    const alvo = String(e.argv[1] ?? '')
    if (alvo.endsWith('relogio-sessoes.cjs')) return saida(JSON.stringify(s.sessoes))
    if (alvo.endsWith('jornada.cjs')) return s.modoJornada === 'falha' ? saida('', 1) : saida(JSON.stringify(s.jornada))
    s.dados.push({ argv: [...e.argv], cwd: e.init?.cwd })
    return s.modoDados === 'falha' ? saida('', 1) : saida(JSON.stringify(FIXTURE_DADOS))
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.id', async () => ({ value: 'sessao-atual' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', async () => ({ sessionId: 'sessao-atual' }) as never)
  on('command.register', async () => ({ value: { command: 'painel' } }) as never)
  on('session.usage', async () => {
    s.usageCalls += 1
    return s.modoUsage === 'falha' ? ({ deny: 'recusado pelo sec-default' } as never) : ({ value: s.usage } as never)
  })
  on('turn.complete', async () => ({ text: '' }))
  on('prompt.submit', async (_$: any, e: any) => e as never)
  on('tool.call', async (_$: any, e: any) => ({ result: 'ok', isError: e.command === 'comando-que-falha' }) as never)
  on('agent.spawn', async () => ({ model: 'haiku', agentId: 'ag-1' }) as never)
  on('turn.step', async function* (_$: any, e: any) {
    s.passos += 1
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [] }
  } as never)
  on('session.compact', async () => ({ messages: [{ role: 'user', text: 'resumo', toolUses: [] }], tokensBefore: 150000, tokensAfter: 20000 }) as never)
  // Fundo da cadeia: o que o engine desenharia quando o mod cede (aqui, uma caixa vazia).
  on('ui.render', async (t$: any, e: any) => {
    const { Box } = t$.ui.resolve(e)
    return <Box />
  })

  let ui: any = null
  const abrir = async () => {
    ui = await $.ui.mount({ plugin: 'rainforest-mind', surface, component: 'AbovePrompt', props: PROPS })
    return ui
  }
  if (comUi) await abrir()
  const textos = async () => (await ui.findAll({ type: 'Text' })).map((t: any) => t.text as string)
  const juntos = async () => (await textos()).join('\n')
  const quieta = async () => {
    expect(await textos()).toEqual([])
    expect(await ui.find({ type: 'Button' })).toBeUndefined()
  }
  const comecar = (interativo = true) => $.session.start({ cwd: '/projeto', surface, isInteractive: interativo })
  let n = 0
  const terminar = (answer: string, extra: Record<string, unknown> = {}) =>
    $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: `t${++n}`, reason: 'answer', ...extra } as never)
  const passo = async (extra: Record<string, unknown> = {}) => {
    const fluxo = $.turn.step({ turnId: `t${n + 1}`, index: 0, model: 'claude-opus-5-5', messageCount: 1, ...extra } as never)
    for await (const _pedaco of fluxo) void _pedaco
  }
  const painel = (args: string) => $.command.run({ command: 'painel', args } as never)
  const caso = async (nome: string, fn: () => Promise<void>) => {
    try {
      await fn()
    } catch (err) {
      throw new Error(`[${surface}] ${nome}: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  return { relogio, s, get ui() { return ui }, abrir, textos, juntos, quieta, comecar, terminar, passo, painel, caso }
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`painel (${surface}): barra, usage real, cache, subagente, esconder, compact e relogio`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, ui, textos, juntos, quieta, comecar, terminar, passo, painel, caso } = m

    await caso(`barra (${surface}): desenha antes de qualquer evento, sem foco, fluxo, Q nem botao`, async () => {
      const t = await juntos()
      expect(t).toContain('○ pronto')
      expect(t).toContain('Tokens 0')
      expect(t).toContain('Custo --')
      expect(t).not.toContain('foco')
      expect(t).not.toContain('fluxo')
      expect(await ui.find({ type: 'Button' })).toBeUndefined()
    })

    await caso(`barra (${surface}): o process.run dos dados roda com cwd na raiz do plugin e a sessao vai por --cwd`, async () => {
      await comecar()
      const dados = s.dados.filter(c => String(c.argv[1]).endsWith('faixa-dados.cjs'))
      expect(dados.length).toBeGreaterThan(0)
      for (const c of dados) {
        const raiz = String(c.argv[1]).replace(/[\\/]scripts[\\/]faixa-dados\.cjs$/, '')
        expect(raiz).not.toBe(String(c.argv[1]))
        expect(c.cwd).toBe(raiz)
        expect(c.argv[c.argv.indexOf('--cwd') + 1]).toBe('/projeto')
      }
    })

    await caso(`barra (${surface}): o relogio aparece como figura, a ultima da barra`, async () => {
      await relogio.advance(2000)
      const t = await textos()
      expect(t[t.length - 1]).toBe('⏰ jornada 9h12 · 20h40')
    })

    await caso(`barra (${surface}): trabalhando com isWorking e pronto sem ele`, async () => {
      await ui.redraw({ ...PROPS, isWorking: true })
      expect(await juntos()).toContain('● trabalhando')
      await ui.redraw(PROPS)
      expect(await juntos()).toContain('○ pronto')
    })

    await caso(`barra (${surface}): o usage real do turno vira Tokens 76.9K, Custo $0.42, 38% e o cache quente`, async () => {
      await passo()
      await terminar(ANSWER, { usage: USAGE_REAL })
      const t = await juntos()
      expect(t).toContain('Tokens 76.9K')
      expect(t).toContain('Custo $0.42')
      expect(t).toContain('38%')
      expect(t).toContain('Turnos 1')
      expect(t).toContain('Cache ● quente 60:00')
      expect(s.usageCalls).toBe(1)
    })

    await caso(`barra (${surface}): a mesma Q numa resposta nao acende foco, fluxo nem linha de Q`, async () => {
      const t = await juntos()
      expect(t).not.toContain('Q1')
      expect(t).not.toContain('Onde o token vive')
      expect(t).not.toContain('foco')
      expect(t).not.toContain('fluxo')
      expect(await ui.find({ type: 'Button' })).toBeUndefined()
    })

    await caso(`barra (${surface}): Erros 1 depois de um tool.call com isError, e Ferram./min conta a chamada`, async () => {
      expect(await juntos()).toContain('Erros 0')
      await $.tool.call({ tool: 'Bash', command: 'comando-que-falha' } as never)
      const t = await juntos()
      expect(t).toContain('Erros 1')
      expect(t).toContain('Ferram./min 1')
    })

    await caso(`barra (${surface}): Subagentes 1 depois do agent.spawn e 0 depois do turn.complete do agentId`, async () => {
      expect(await juntos()).toContain('Subagentes 0')
      await $.agent.spawn({ prompt: 'p', description: 'revisar o diff', subagentType: 'general-purpose', tool_use_id: 'u1' } as never)
      expect(await juntos()).toContain('Subagentes 1')
      await terminar('feito', { agentId: 'ag-1', usage: { ...USAGE_REAL, model: 'haiku' } })
      const t = await juntos()
      expect(t).toContain('Subagentes 0')
      expect(t).toContain('Turnos 1') // turno de subagente nao conta como turno da sessao
    })

    await caso(`barra (${surface}): com view.agentId a barra e a do subagente e o contexto e o da sessao principal`, async () => {
      await ui.redraw({ ...PROPS, view: { agentId: 'ag-1' } })
      const t = await juntos()
      expect(t).toContain('Subagente')
      expect(t).toContain('revisar o diff')
      expect(t).toContain('Status pronto')
      expect(t).toContain('Tokens 76.9K')
      expect(t).toContain('Sessão principal: contexto 38%')
      expect(t).not.toContain('Cache')
      await ui.redraw({ ...PROPS, view: { agentId: 'ag-desconhecido' } })
      expect(await juntos()).toContain('Sem atividade vista ainda')
      await ui.redraw(PROPS)
    })

    await caso(`barra (${surface}): hasSurvey cede a vaga com next(e)`, async () => {
      await ui.redraw({ ...PROPS, hasSurvey: true })
      await quieta()
      await ui.redraw(PROPS)
      expect(await juntos()).toContain('Tokens 153.7K') // o turno do subagente soma no total da sessao
    })

    await caso(`barra (${surface}): esconder e mostrar`, async () => {
      const r = await painel('esconder')
      expect(r.text).toContain('escondida')
      await quieta()
      // a barra muda a cada segundo e continua escondida (D9: nada de esconder por assinatura)
      await relogio.advance(5000)
      await ui.redraw(PROPS)
      await quieta()
      await terminar('de novo', { usage: USAGE_REAL })
      await quieta()
      const v = await painel('mostrar')
      expect(v.text).toContain('volta')
      expect(await juntos()).toContain('Tokens')
    })

    await caso(`barra (${surface}): subcomando desconhecido responde com a lista`, async () => {
      const r = await painel('xyz')
      expect(r.text).toContain('esconder')
      expect(r.text).toContain('mostrar')
      expect(r.text).toContain('cache 5m|1h')
    })

    await ui.unmount()
  })

  test(`painel (${surface}): cache de 10 min depois, /painel cache 5m e session.compact`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { relogio, s, juntos, comecar, terminar, passo, painel, caso } = m

    await caso(`barra (${surface}): 10 minutos depois o cache mostra quente 50:00 com reenvio $0.02 e $0.61 se esfriar`, async () => {
      await comecar()
      await relogio.advance(2000)
      await passo()
      await terminar(ANSWER, { usage: USAGE_REAL })
      await relogio.advance(10 * MIN) // sem tela montada: nada redesenha a cada segundo
      await m.abrir()
      const t = await juntos()
      expect(t).toContain('quente 50:00')
      expect(t).toContain('$0.02')
      expect(t).toContain('($0.61 se esfriar)')
    })

    await caso(`barra (${surface}): /painel cache 5m muda o TTL e a estimativa de reenvio (escrita a 1,25x)`, async () => {
      // 10 min e 7 s depois do 1o passo: com TTL de 5 min o cache ja esfriou
      const r = await painel('cache 5m')
      expect(r.text).toContain('5m')
      const frio = await juntos()
      expect(frio).toContain('Cache ○ frio')
      expect(frio).toContain('reenvio $0.38') // 76599 tokens * US$ 4/M * 1,25
      await passo()
      const t = await juntos()
      expect(t).toContain('quente 5:00')
      expect(t).toContain('($0.38 se esfriar)')
      await painel('cache 1h')
      expect(await juntos()).toContain('($0.61 se esfriar)')
    })

    await caso(`barra (${surface}): session.compact mostra o contexto novo na hora e pede medicao nova`, async () => {
      const antes = s.usageCalls
      await $.session.compact({ trigger: 'manual', messages: [{ role: 'user', text: 'oi', toolUses: [] }] } as never)
      const t = await juntos()
      expect(t).toContain('10%') // 20000 de 200000, a contagem da propria compactacao
      expect(t).not.toContain('38%')
      expect(s.usageCalls).toBe(antes) // ainda nao mediu: so pediu
      s.usage = SESSION_USAGE(12, 24000, 0.45)
      await relogio.advance(1000) // o tique refaz a medicao pendente
      expect(s.usageCalls).toBe(antes + 1)
      const d = await juntos()
      expect(d).toContain('12%')
      expect(d).toContain('Custo $0.45')
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): largura, o relogio e o ultimo a cair com 40 colunas`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, ui, textos, comecar, terminar, caso } = m

    await caso(`barra (${surface}): com 40 colunas cada Text cabe e o ⏰ e o ultimo a cair`, async () => {
      await comecar()
      await relogio.advance(2000)
      await terminar(ANSWER, { usage: USAGE_REAL })
      await ui.redraw({ ...PROPS, bodyColumns: 40 })
      const t = await textos()
      expect(t.length).toBeGreaterThan(0)
      for (const linha of t) expect(largura(linha)).toBeLessThanOrEqual(40)
      expect(t[0]).toBe('○ pronto')
      expect(t[t.length - 1]).toBe('⏰ jornada 9h12 · 20h40')
      expect(t.length).toBeLessThan(10) // a 40 colunas algo tinha de cair
      expect(t.some(linha => linha.startsWith('Cache'))).toBe(false)
    })

    await caso(`barra (${surface}): com 200 colunas todas as figuras cabem`, async () => {
      await ui.redraw(PROPS)
      const t = await textos()
      expect(t.some(linha => linha.startsWith('Contexto 0'))).toBe(true)
      expect(t.some(linha => linha.startsWith('Erros'))).toBe(true)
      expect(t[t.length - 1]).toBe('⏰ jornada 9h12 · 20h40')
    })

    await ui.unmount()
  })

  test(`painel (${surface}): falha aberta, cada leitura que falha apaga so a sua figura`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, juntos, comecar, terminar, caso } = m

    await caso(`falha aberta (${surface}): dados bons acendem contexto, custo e relogio`, async () => {
      await comecar()
      await relogio.advance(2000)
      await terminar(ANSWER, { usage: USAGE_REAL })
      const t = await juntos()
      expect(t).toContain('Contexto 0')
      expect(t).toContain('Custo $0.42')
      expect(t).toContain('⏰ jornada 9h12')
    })

    await caso(`falha aberta (${surface}): session.usage recusado apaga o Contexto e deixa o resto`, async () => {
      s.modoUsage = 'falha'
      await terminar('outro', { usage: USAGE_REAL })
      const t = await juntos()
      expect(t).not.toContain('Contexto 0')
      expect(t).not.toContain('38%')
      expect(t).toContain('Tokens')
      expect(t).toContain('Turnos 2')
      expect(t).toContain('⏰ jornada 9h12')
      s.modoUsage = 'ok'
    })

    await caso(`falha aberta (${surface}): process.run da jornada com exit 1 apaga so o relogio`, async () => {
      s.modoJornada = 'falha'
      await m.ui.unmount() // 5 min com o cache quente redesenhariam a barra a cada segundo
      await relogio.advance(5 * MIN)
      await m.abrir()
      const t = await juntos()
      expect(t).not.toContain('⏰')
      expect(t).toContain('Tokens')
      expect(t).toContain('Turnos 2')
    })

    await caso(`falha aberta (${surface}): process.run dos dados com exit 1 nao toca a barra`, async () => {
      s.modoDados = 'falha'
      const antes = await juntos()
      await terminar('de novo', { usage: USAGE_REAL })
      const t = await juntos()
      expect(t).toContain('Turnos 3')
      expect(antes).toContain('Tokens')
      expect(t).toContain('Tokens')
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): nao interativo nao arma o tique nem o relogio`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40))
    const { relogio, s, comecar, ui, caso } = m

    await caso(`barra (${surface}): isInteractive false nao dispara process.run do relogio nem mede por tique`, async () => {
      await comecar(false)
      const antes = s.runs
      await relogio.advance(10 * MIN)
      expect(s.runs).toBe(antes)
      expect(s.usageCalls).toBe(0)
    })

    await ui.unmount()
  })
}
