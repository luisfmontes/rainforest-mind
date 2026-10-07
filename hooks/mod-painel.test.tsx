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
const FIXTURE_DADOS = {"fluxos":[{"slug":"2026-10-07-painel-pane","titulo":"Pane do painel","etapa":"executar","tarefas_ok":1,"tarefas":3,"em_voo":["agente-a"],"criado_em":"2026-10-07","worktree":"C:/tmp/painel-repo-0l2wTg"}]}
const FIXTURE_SESSOES = {"ociosidade_min":45,"janelas":[{"cwd":"/projetos/painel","desde":0},{"cwd":"/projetos/loja-api","desde":0}]}
const FIXTURE_JORNADA = {"escopo":"s.jsonl","mensagens":13,"efetiva_min":552,"bruto_min":552,"primeiro":"2026-10-03T11:18:00-03:00","ultimo":"2026-10-03T20:30:00-03:00","corte_min":55,"descartadas":[]}

// Saidas REAIS de `node scripts/desvio-do-plano.cjs --cwd <worktree> --arquivo <abs>` sobre repo
// temporario montado como em scripts/testa-desvio-do-plano.sh (git init + git worktree add, plano
// real 2026-10-03-mod-faixa-foco.md via `git show`, estado em executar); SEMFLUXO e o mesmo
// script num repo sem estado nenhum.
const DESVIO_DENTRO = '{"veredito":"dentro","rel":"hooks/faixa-puro.mjs","slug":"2026-10-03-mod-faixa-foco"}'
const DESVIO_FORA = '{"veredito":"fora","rel":"scripts/estado.cjs","slug":"2026-10-03-mod-faixa-foco"}'
const DESVIO_SEM_FLUXO = '{"veredito":"sem-fluxo","rel":null,"slug":null}'

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
        { name: 'Ferramentas sob demanda', tokens: 4200, color: 'e', isDeferred: true, kind: 'deferred' },
        { name: 'Reserva de compactação', tokens: 33000, color: 'f', isDeferred: false, kind: 'buffer' },
        { name: 'Livre', tokens: 200000 - tokens - 33000, color: 'd', isDeferred: false, kind: 'free' },
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

// Texto real de docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md:111.
const ADIAMENTO_REAL = '9. **Fluxo 4 (território)** fica para depois do núcleo estável —'

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

const PANE_PROPS = {
  title: 'Esta sessão',
  isFocused: false,
  bodyColumns: 80,
  placement: 'inline' as const,
  scroll: { offset: 0, bodyRows: 40 },
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
    modoOpen: 'ok' as 'ok' | 'recusa',
    opens: [] as unknown[],
    usageCalls: 0,
    dados: [] as { argv: readonly string[]; cwd: unknown }[],
    runs: 0,
    passos: 0,
    // Desvio do plano: cada execucao do script, o modo da resposta e o atraso (ms do relogio simulado).
    desvios: [] as { argv: readonly string[]; cwd: unknown; env: unknown; timeoutMs: unknown }[],
    modoDesvio: 'plano' as 'plano' | 'sem-fluxo' | 'exit1' | 'json-ruim' | 'rejeita',
    atrasoDesvio: 0,
    toasts: [] as string[],
    logs: [] as string[],
    submits: 0,
    // Deixado para depois: as chamadas do segundo modelo, o modo e o texto da resposta dele, o
    // atraso (ms do relogio simulado) e os rascunhos que o botao "Faz agora" preencheu.
    modelos: [] as { model: unknown; prompt: unknown; maxTokens: unknown; timeoutMs: unknown }[],
    modoModelo: 'ok' as 'ok' | 'sem-resposta',
    textoModelo: 'NENHUM',
    atrasoModelo: 0,
    fills: [] as { text: unknown; mode: unknown }[],
  }
  on('process.run', async (_$: any, e: any) => {
    s.runs += 1
    const alvo = String(e.argv[1] ?? '')
    if (alvo.endsWith('desvio-do-plano.cjs')) {
      s.desvios.push({ argv: [...e.argv], cwd: e.init?.cwd, env: e.init?.env, timeoutMs: e.init?.timeoutMs })
      if (s.atrasoDesvio > 0) await relogio.sleep(s.atrasoDesvio)
      if (s.modoDesvio === 'rejeita') return ({ deny: 'recusado pelo sec-default' }) as never
      if (s.modoDesvio === 'exit1') return saida('', 1)
      if (s.modoDesvio === 'json-ruim') return saida('isto nao e json {')
      if (s.modoDesvio === 'sem-fluxo') return saida(DESVIO_SEM_FLUXO)
      return saida(String(e.argv[e.argv.indexOf('--arquivo') + 1]).endsWith('faixa-puro.mjs') ? DESVIO_DENTRO : DESVIO_FORA)
    }
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
  on('ui.open', async (_$: any, e: any) => {
    s.opens.push(e)
    return { value: { isPlaced: s.modoOpen === 'ok' } } as never
  })
  on('turn.complete', async () => ({ text: '' }))
  on('prompt.submit', async (_$: any, e: any) => {
    s.submits += 1
    return e as never
  })
  on('model.complete', async (_$: any, e: any) => {
    s.modelos.push({ model: e.model, prompt: e.prompt, maxTokens: e.maxTokens, timeoutMs: e.timeoutMs })
    if (s.atrasoModelo > 0) await relogio.sleep(s.atrasoModelo)
    const usage = { input_tokens: 1, output_tokens: 1 }
    if (s.modoModelo === 'sem-resposta') return { value: { isAnswered: false, reason: 'empty-reply', usage } } as never
    return { value: { isAnswered: true, text: s.textoModelo, usage } } as never
  })
  on('prompt.fill', async (_$: any, e: any) => {
    s.fills.push({ text: e.text, mode: e.mode })
    return { isFilled: true } as never
  })
  on('ui.toast', async (_$: any, e: any) => {
    s.toasts.push(String(e.text))
    return { value: undefined } as never
  })
  on('ui.log', async (_$: any, e: any) => {
    s.logs.push(String(e.text))
    return { value: undefined } as never
  })
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
  // O pane do /painel monta no lugar da barra (cada teste usa um ou outro).
  const abrirPane = async (props: Record<string, unknown> = {}) => {
    ui = await $.ui.mount({ plugin: 'rainforest-mind', surface, component: 'Pane', requestId: 'painel', props: { ...PANE_PROPS, ...props } })
    return ui
  }
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
  return { relogio, s, get ui() { return ui }, abrir, abrirPane, textos, juntos, quieta, comecar, terminar, passo, painel, caso }
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
      expect(r.text).toContain('checar ligar|desligar')
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

  test(`painel (${surface}): pane com fluxos, contexto por fatia, cache, subagentes, custo e subagente em tela`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { relogio, s, textos, juntos, comecar, terminar, passo, painel, caso } = m
    const soma = (t: string[]) => t.filter(x => /^[█▒░]+$/.test(x)).reduce((n, x) => n + x.length, 0)

    await caso(`pane (${surface}): /painel sem argumento abre o pane, mede o contexto e devolve o texto`, async () => {
      await comecar()
      await relogio.advance(2000)
      await passo()
      await terminar(ANSWER, { usage: USAGE_REAL })
      const antes = s.usageCalls
      const r = await painel('')
      expect(r.text).toBe('Painel aberto.')
      expect(s.opens).toEqual([{ id: 'painel', title: 'Esta sessão' }])
      expect(s.usageCalls).toBe(antes + 1)
      await m.abrirPane()
    })

    await caso(`pane (${surface}): Fluxos em curso traz o slug sem data, a etapa, 1/3 e 1 em voo`, async () => {
      const t = await textos()
      expect(t).toContain(' Fluxos em curso ')
      expect(t).toContain('painel-pane')
      expect(t).not.toContain('2026-10-07-painel-pane')
      expect(t).toContain('executar · 1/3 · 1 em voo')
    })

    await caso(`pane (${surface}): a barra de contexto soma exatamente a largura interna`, async () => {
      expect(soma(await textos())).toBe(76) // bodyColumns 80 - 4
      await m.ui.redraw({ ...PANE_PROPS, bodyColumns: 50 })
      expect(soma(await textos())).toBe(46)
      await m.ui.redraw({ ...PANE_PROPS, bodyColumns: 10 })
      expect(soma(await textos())).toBe(16) // o piso do interior
      await m.ui.redraw(PANE_PROPS)
    })

    await caso(`pane (${surface}): Onde foi o contexto traz nome, compacto e % de cada fatia e as ferramentas sob demanda`, async () => {
      const t = await textos()
      expect(t).toContain(' Onde foi o contexto ')
      expect(t).toContain('Usado')
      expect(t).toContain('38% de 200.0K')
      expect(t).toContain('■ Mensagens')
      expect(t).toContain('38.3K  19%')
      expect(t).toContain('■ Ferramentas')
      expect(t).toContain('23.0K  11%')
      expect(t).toContain('■ Sistema')
      expect(t).toContain('15.3K   8%')
      expect(t).toContain('▒ Reserva de compactação')
      expect(t).toContain('░ Livre')
      expect(t).toContain('+ 4.2K em ferramentas sob demanda')
      expect(t).not.toContain('Medição indisponível')
    })

    await caso(`pane (${surface}): Cache de prompt mostra quente, o custo quente e frio e a estimativa de 1h`, async () => {
      const t = await textos()
      expect(t).toContain(' Cache de prompt ')
      expect(t).toContain('quente, faltam 60:00')
      expect(t).toContain('$0.02')
      expect(t).toContain('$0.61')
      expect(t).toContain('Estimativa: reenvio da conversa a preço de lista, cache de 1h')
      await painel('cache 5m')
      const c = await textos()
      expect(c).toContain('Estimativa: reenvio da conversa a preço de lista, cache de 5m')
      expect(c).toContain('$0.38') // 76599 tokens a US$ 4/M, escrita a 1,25x
      await relogio.advance(6 * MIN)
      const frio = await textos()
      expect(frio).toContain('frio')
      expect(frio).not.toContain('quente, faltam 0:00')
      await painel('cache 1h')
    })

    await caso(`pane (${surface}): Subagentes lista o agente com tipo, modelo e ferramentas`, async () => {
      expect(await textos()).toContain('Nenhum iniciado ainda')
      await $.agent.spawn({ prompt: 'p', description: 'revisar o diff', subagentType: 'general-purpose', tool_use_id: 'u1' } as never)
      await $.tool.call({ tool: 'Bash', command: 'ls', agentId: 'ag-1' } as never)
      const t = await textos()
      expect(t).toContain(' Subagentes ')
      expect(t.some(x => x.includes('● revisar o diff'))).toBe(true)
      expect(t.some(x => x.includes('trabalhando · general-purpose · haiku · 1 ferramentas'))).toBe(true)
      await terminar('feito', { agentId: 'ag-1', usage: { ...USAGE_REAL, model: 'haiku' } })
      expect((await textos()).some(x => x.includes('✓ revisar o diff'))).toBe(true)
    })

    await caso(`pane (${surface}): Custo e tokens traz custo, lidos, % servida do cache, escritos e turnos`, async () => {
      const t = await textos()
      expect(t).toContain(' Custo e tokens ')
      expect(t).toContain('Custo da sessão')
      expect(t).toContain('$0.42')
      expect(t).toContain('153.2K') // 76599 do turno e 76599 do subagente
      expect(t).toContain('40%') // 30782 de 76599 lidos do cache, nos dois turnos
      expect(t).toContain('546') // 273 + 273 tokens escritos
      expect(t).toContain('Turnos')
      expect(t).toContain('1')
    })

    await caso(`pane (${surface}): com view.agentId o pane e o do subagente e diz que contexto e cache sao da principal`, async () => {
      await m.ui.redraw({ ...PANE_PROPS, view: { agentId: 'ag-1' } })
      const t = await juntos()
      expect(t).toContain('Subagente em tela')
      expect(t).toContain('revisar o diff')
      expect(t).toContain('Todos os subagentes')
      expect(t).toContain('Contexto e cache são da sessão principal')
      expect(t).not.toContain('Onde foi o contexto')
      expect(t).not.toContain('Cache de prompt')
      await m.ui.redraw({ ...PANE_PROPS, view: { agentId: 'ag-novo' } })
      expect(await juntos()).toContain('Sem atividade vista ainda')
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): mapa da sessao, desvio do plano e um toast por arquivo`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { relogio, s, textos, juntos, comecar, caso } = m
    const vermelhos = async () => (await m.ui.findAll({ type: 'Text' })).filter((x: any) => x.props.color === '#ff4d4d').map((x: any) => x.text as string)
    let ran: any

    await caso(`mapa (${surface}): escritas, leitura, Bash, MCP, skill e subagente`, async () => {
      await comecar()
      await m.abrirPane()
      const antes = s.submits
      ran = await $.tool.call({ tool: 'Write', file_path: '/projeto/hooks/faixa-puro.mjs', content: 'x' } as never)
      await $.tool.call({ tool: 'Edit', file_path: '/projeto/scripts/estado.cjs', old_string: 'a', new_string: 'b' } as never)
      await $.tool.call({ tool: 'Edit', file_path: '/projeto/scripts/estado.cjs', old_string: 'b', new_string: 'c' } as never)
      await $.tool.call({ tool: 'Read', file_path: '/projeto/hooks/mod.tsx' } as never)
      await $.tool.call({ tool: 'Bash', command: 'echo oi > bash-escreveu.txt' } as never)
      await $.tool.call({ tool: 'mcp__claude_ai_Claude_Docs__guide', items: [] } as never)
      await $.tool.call({ tool: 'Skill', skill: 'plano' } as never)
      await $.agent.spawn({ prompt: 'p', description: 'revisar o diff', subagentType: 'general-purpose', tool_use_id: 'u1' } as never)
      await relogio.settle()
      expect(ran.result).toBe('ok')
      expect(ran.context).toBeUndefined()
      expect(s.submits).toBe(antes) // o desvio nunca vira prompt nem contexto
      const t = await textos()
      expect(t).toContain(' Mapa da sessão ')
      expect(t).toContain('✓ hooks/faixa-puro.mjs')
      expect(t.filter(x => x === '✗ scripts/estado.cjs')).toHaveLength(1)
      expect(t).toContain('  plano')
      expect(t).toContain('  claude_ai_Claude_Docs')
      expect(t).toContain('  revisar o diff')
      expect(t.some(x => x.includes('mod.tsx'))).toBe(false) // Read nao entra
      expect(t.some(x => x.includes('bash-escreveu') || x.includes('echo oi'))).toBe(false) // Bash nao entra
      expect(t.some(x => x.startsWith('Escrita feita por Bash não é detectada'))).toBe(true)
    })

    await caso(`mapa (${surface}): o que esta fora do plano fica vermelho e so ele`, async () => {
      const v = await vermelhos()
      expect(v).toContain('✗ scripts/estado.cjs')
      expect(v).toContain('  fora dos arquivos do plano')
      expect(v.some(x => x.includes('faixa-puro'))).toBe(false)
    })

    await caso(`mapa (${surface}): um toast por arquivo, nao por escrita`, async () => {
      expect(s.toasts).toEqual(['Fora dos arquivos do plano: scripts/estado.cjs'])
      expect(s.desvios).toHaveLength(3) // so escrita dispara o script: 3 escritas, nenhuma leitura nem Bash
    })

    await caso(`mapa (${surface}): o script roda com o argv, o cwd e o env do contrato`, async () => {
      const d = s.desvios[0]
      expect(d.argv.slice(0, 1)).toEqual(['node'])
      expect(String(d.argv[1]).endsWith('/scripts/desvio-do-plano.cjs')).toBe(true)
      expect(d.argv.slice(2)).toEqual(['--cwd', '/projeto', '--arquivo', '/projeto/hooks/faixa-puro.mjs'])
      expect(d.env).toEqual({ CLAUDE_PROJECT_DIR: '/projeto' })
      expect(d.timeoutMs).toBe(5000)
      expect(String(d.cwd)).toBe(String(d.argv[1]).replace(/\/scripts\/desvio-do-plano\.cjs$/, ''))
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): desvio em segundo plano, fora de fluxo e falha aberta do script`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { relogio, s, textos, comecar, caso } = m
    const escrever = (arquivo: string) => $.tool.call({ tool: 'Write', file_path: arquivo, content: 'x' } as never) as Promise<any>

    await caso(`mapa (${surface}): o resultado do tool.call chega antes do script`, async () => {
      await comecar()
      await m.abrirPane()
      s.atrasoDesvio = 3000
      const ran = await escrever('/projeto/scripts/estado.cjs')
      expect(ran.result).toBe('ok')
      await relogio.settle()
      expect(s.desvios).toHaveLength(1) // o script ja saiu...
      expect(s.toasts).toEqual([]) // ...mas ainda nao respondeu
      expect((await textos()).some(x => x.includes('estado.cjs'))).toBe(false)
      await relogio.advance(3000)
      expect(s.toasts).toEqual(['Fora dos arquivos do plano: scripts/estado.cjs'])
      expect(await textos()).toContain('✗ scripts/estado.cjs')
      s.atrasoDesvio = 0
    })

    await caso(`mapa (${surface}): fora de fluxo o mapa lista sem vermelho e sem toast`, async () => {
      s.modoDesvio = 'sem-fluxo'
      await escrever('/projeto/lista-sem-fluxo.txt')
      await relogio.settle()
      expect(s.toasts).toHaveLength(1) // so o da escrita anterior
      const t = await textos()
      expect(t).toContain('✓ /projeto/lista-sem-fluxo.txt')
      expect((await m.ui.findAll({ type: 'Text' })).filter((x: any) => x.props.color === '#ff4d4d' && x.text.includes('lista-sem-fluxo'))).toHaveLength(0)
    })

    await caso(`mapa (${surface}): exit 1, JSON invalido e process.run rejeitado nao acusam nem quebram`, async () => {
      const toasts = s.toasts.length
      for (const [modo, arquivo] of [['exit1', '/projeto/a-exit1.txt'], ['json-ruim', '/projeto/b-json.txt'], ['rejeita', '/projeto/c-rejeita.txt']] as const) {
        s.modoDesvio = modo
        const ran = await escrever(arquivo)
        expect(ran.result).toBe('ok')
        await relogio.settle()
        expect(await textos()).toContain(`✓ ${arquivo}`)
      }
      expect(s.toasts).toHaveLength(toasts)
      expect(s.logs.some(l => l.startsWith('painel: desvio: '))).toBe(true)
    })

    await caso(`mapa (${surface}): escrita que falhou nao dispara o script nem entra no mapa`, async () => {
      const antes = s.desvios.length
      const ran = await $.tool.call({ tool: 'Write', file_path: '/projeto/falhou.txt', command: 'comando-que-falha' } as never) as any
      expect(ran.isError).toBe(true)
      await relogio.settle()
      expect(await textos()).not.toContain('✓ /projeto/falhou.txt')
      expect(s.desvios).toHaveLength(antes)
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): pane com ui.open recusado, session.usage rejeitado e subcomando desconhecido`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { s, textos, comecar, painel, caso } = m

    await caso(`pane (${surface}): ui.open recusado ainda devolve o texto do comando`, async () => {
      await comecar()
      s.modoOpen = 'recusa'
      const r = await painel('')
      expect(r.text).toContain('Painel indisponível aqui')
      expect(r.text).toContain('Contexto 38%')
      expect(r.text).toContain('custo $0.42')
      s.modoOpen = 'ok'
    })

    await caso(`pane (${surface}): session.usage rejeitado ainda devolve o texto e o pane diz Medição indisponível`, async () => {
      s.modoUsage = 'falha'
      const r = await painel('')
      expect(r.text).toBe('Painel aberto.')
      await m.abrirPane()
      const t = await textos()
      expect(t).toContain('Medição indisponível')
      expect(t).toContain(' Fluxos em curso ')
      expect(t).toContain(' Cache de prompt ')
      expect(t).toContain(' Custo e tokens ')
      expect(t.some(x => /^[█▒░]+$/.test(x))).toBe(false)
    })

    await caso(`pane (${surface}): /painel xyz devolve a lista de subcomandos`, async () => {
      const r = await painel('xyz')
      for (const sub of ['esconder', 'mostrar', 'cache 5m|1h', 'checar ligar|desligar']) expect(r.text).toContain(sub)
      expect(s.opens.length).toBe(2) // so os dois /painel sem argumento abriram o pane
    })

    await m.ui.unmount()
  })

  test(`painel (${surface}): deixado para depois, varredura, marcadores e checker do segundo modelo`, async ($, on) => {
    const m = await montar($, on, surface, em(20, 40), false)
    const { relogio, s, textos, juntos, comecar, terminar, painel, caso } = m
    const pedir = (texto: string, origem: Record<string, unknown> | undefined = { kind: 'composer' }) =>
      $.prompt.submit({ text: texto, ...(origem === undefined ? {} : { origin: origem }) } as never)
    const ferramentas = async (...chamadas: Record<string, unknown>[]) => {
      for (const c of chamadas) await $.tool.call(c as never)
      await relogio.settle()
    }
    const bash = { tool: 'Bash', command: 'ls' }
    const falha = { tool: 'Bash', command: 'comando-que-falha' }
    const edit = { tool: 'Edit', file_path: '/projeto/hooks/faixa-puro.mjs', old_string: 'a', new_string: 'b' }
    const itens = async () => (await textos()).filter(t => /^D\d+ · /.test(t))

    await caso(`varredura (${surface}): a frase real vira 1 item Claude disse e Faz agora so preenche o prompt`, async () => {
      await comecar()
      await m.abrirPane()
      const submits = s.submits
      await pedir('me diga o status do fluxo 4')
      await terminar(ADIAMENTO_REAL)
      expect(await itens()).toEqual(['D1 · Claude disse'])
      const t = await textos()
      expect(t).toContain('Fluxo 4 (território) fica para depois do núcleo estável —')
      expect(s.toasts.filter(x => x.startsWith('Deixado para depois: Fluxo 4'))).toHaveLength(1)
      await m.ui.press({ key: 'faz-1' })
      expect(s.fills).toHaveLength(1)
      expect(s.fills[0].mode).toBe('append')
      expect(String(s.fills[0].text)).toContain('Fluxo 4 (território) fica para depois do núcleo estável')
      expect(String(s.fills[0].text)).toContain('Faca agora')
      expect(s.submits).toBe(submits + 1) // so o prompt.submit do pedido: o botao nunca envia
      expect(await itens()).toEqual([])
    })

    await caso(`checker (${surface}): so com 5 ou mais ferramentas`, async () => {
      expect(s.modelos).toHaveLength(0) // o turno anterior teve 0 ferramentas
      await pedir('rode a bateria e corrija')
      await ferramentas(bash, bash, falha, edit)
      await terminar('Tudo certo, terminei.')
      expect(s.modelos).toHaveLength(0)
      await pedir('rode a bateria e corrija o que falhar')
      await ferramentas(bash, bash, falha, edit, edit)
      s.textoModelo = 'Rodar a bateria da tarefa 2'
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(s.modelos).toHaveLength(1)
      const c = s.modelos[0]
      const prompt = String(c.prompt)
      expect(c.model).toBe('haiku')
      expect(c.maxTokens).toBe(300)
      expect(c.timeoutMs).toBe(30000)
      expect(prompt).toContain('rode a bateria e corrija o que falhar')
      expect(prompt).toContain('Tudo certo, terminei.')
      expect(prompt).toContain('Bash x3 (1 erro), Edit x2')
    })

    await caso(`checker (${surface}): a resposta vira item segundo modelo e toast`, async () => {
      expect(await itens()).toEqual(['D2 · segundo modelo'])
      expect(await textos()).toContain('Rodar a bateria da tarefa 2')
      expect(s.toasts).toContain('Deixado para depois: Rodar a bateria da tarefa 2')
    })

    await caso(`checker (${surface}): NENHUM nao gera nada e a lista do turno foi zerada`, async () => {
      const toasts = s.toasts.length
      s.textoModelo = 'NENHUM'
      await pedir('faça de novo')
      await ferramentas(bash, bash, bash, bash, bash)
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(s.modelos).toHaveLength(2)
      expect(String(s.modelos[1].prompt)).toContain('Bash x5')
      expect(String(s.modelos[1].prompt)).not.toContain('Edit')
      expect(await itens()).toEqual(['D2 · segundo modelo'])
      expect(s.toasts).toHaveLength(toasts)
    })

    await caso(`checker (${surface}): /painel checar desligar impede a chamada e ligar a restaura`, async () => {
      expect((await painel('checar desligar')).text).toContain('desligada')
      expect(await juntos()).toContain('Checagem do segundo modelo: desligada')
      await pedir('mais uma')
      await ferramentas(bash, bash, bash, bash, bash)
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(s.modelos).toHaveLength(2)
      expect((await painel('checar ligar')).text).toContain('ligada')
      await pedir('mais uma')
      await ferramentas(bash, bash, bash, bash, bash)
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(s.modelos).toHaveLength(3)
    })

    await caso(`checker (${surface}): isAnswered falso nao gera item nem toast e grava painel: checker no debug`, async () => {
      s.modoModelo = 'sem-resposta'
      const toasts = s.toasts.length
      await pedir('outra')
      await ferramentas(bash, bash, bash, bash, bash)
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(s.modelos).toHaveLength(4)
      expect(s.logs.some(l => l.startsWith('painel: checker: '))).toBe(true)
      expect(await itens()).toEqual(['D2 · segundo modelo'])
      expect(s.toasts).toHaveLength(toasts)
      s.modoModelo = 'ok'
    })

    await caso(`checker (${surface}): checando aparece enquanto o modelo pensa e some depois`, async () => {
      s.atrasoModelo = 5000
      s.textoModelo = 'Conferir a tarefa 3'
      await pedir('devagar')
      await ferramentas(bash, bash, bash, bash, bash)
      await terminar('Tudo certo, terminei.')
      await relogio.settle()
      expect(await textos()).toContain('Checando com o segundo modelo…')
      await relogio.advance(5000)
      expect(await textos()).not.toContain('Checando com o segundo modelo…')
      expect(await itens()).toEqual(['D2 · segundo modelo', 'D3 · segundo modelo'])
      s.atrasoModelo = 0
    })

    await caso(`marcador (${surface}): TODO com dois pontos em arquivo escrito vira item em arquivo e TODO heredoc nao`, async () => {
      await ferramentas({ tool: 'Write', file_path: '/projeto/hooks/faixa-puro.mjs', content: 'x\n// TODO: tratar timeout\ny' })
      expect(await itens()).toEqual(['D2 · segundo modelo', 'D3 · segundo modelo', 'D4 · em arquivo'])
      expect(await textos()).toContain('Escreveu "// TODO: tratar timeout" em faixa-puro.mjs')
      await ferramentas({ tool: 'Write', file_path: '/projeto/hooks/faixa-puro.mjs', content: 'corpo de TODO heredoc' })
      expect(await itens()).toHaveLength(3)
    })

    await caso(`subagente (${surface}): o turno do subagente nao dispara varredura nem checker`, async () => {
      const chamadas = s.modelos.length
      const itensAntes = (await itens()).length
      await ferramentas(...[1, 2, 3, 4, 5, 6].map(() => ({ tool: 'Bash', command: 'ls', agentId: 'ag-1' })))
      await terminar(ADIAMENTO_REAL, { agentId: 'ag-1', usage: { ...USAGE_REAL, model: 'haiku' } })
      await relogio.settle()
      expect(s.modelos).toHaveLength(chamadas)
      expect(await itens()).toHaveLength(itensAntes)
    })

    await caso(`barra (${surface}): Deixado N conta os itens abertos`, async () => {
      await m.ui.unmount()
      await m.abrir()
      expect(await juntos()).toContain('Deixado 3')
      await m.abrirPane()
      await m.ui.press({ key: 'deixado-limpar' })
      expect(await itens()).toEqual([])
      await m.ui.unmount()
      await m.abrir()
      expect(await juntos()).not.toContain('Deixado')
    })

    await m.ui.unmount()
  })
}
