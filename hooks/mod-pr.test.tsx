// Prova de engine do painel de PR (/pr) e do /plugins-em-dia: `claude plugin test <raiz>`.
// O engine carrega hooks/mod.tsx de verdade; por baixo dos plugins respondem `process.run`
// (a saida de `gh`, escolhida pelo argv), `tool.call`, `ui.open`, `prompt.submit` e o relogio
// simulado de `mock.clock` (so anda quando o teste manda). A logica pura tem bateria propria
// em Node (hooks/testa-mod-pr.cjs e hooks/testa-mod-plugins-em-dia.cjs); aqui se prova a
// FIACAO: que o gatilho abre o pane, que a nota entra na conversa, que so PR da sessao acorda
// e uma vez so, que o polling para no merge e que o comando observado volta como veio.
// Os dados nao sao inventados: PR_455 e a saida REAL de `gh pr view 455 --repo
// luisfmontes/rainforest-mind --json ...` (retirados author.id/name e detailsUrl, como em
// testa-mod-pr.cjs) e THREADS_455 a de `gh api graphql` com reviewThreads do mesmo PR; as
// variantes mudam so o campo citado.
import { test, expect, mock } from 'claude-code/testing'

const URL_PR = 'https://github.com/luisfmontes/rainforest-mind/pull/455'

const PR_455 = {
  number: 455,
  title: 'Gate: & "$pasta\\script.ps1" analisado pelo nome literal (1.53.2)',
  url: URL_PR,
  state: 'MERGED',
  isDraft: false,
  headRefOid: 'a954e193059d3f392aab8afc1d9de4748b5a2c41',
  headRefName: 'fluxo/gate-call-operator-variavel',
  baseRefName: 'main',
  author: { login: 'luisfmontes' },
  updatedAt: '2026-10-09T17:11:48Z',
  mergeable: 'UNKNOWN',
  mergeStateStatus: 'UNKNOWN',
  reviewDecision: '',
  latestReviews: [] as unknown[],
  statusCheckRollup: [
    { __typename: 'CheckRun', completedAt: '2026-10-09T17:08:20Z', conclusion: 'SUCCESS', name: 'baterias (node 24, shard 1/2)', startedAt: '2026-10-09T16:50:45Z', status: 'COMPLETED', workflowName: 'baterias' },
    { __typename: 'CheckRun', completedAt: '2026-10-09T17:10:05Z', conclusion: 'SUCCESS', name: 'baterias (node 24, shard 2/2)', startedAt: '2026-10-09T16:50:44Z', status: 'COMPLETED', workflowName: 'baterias' },
  ] as Record<string, unknown>[],
  comments: [] as unknown[],
}
const THREADS_455 = '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]}}}}}'

// (a) o PR com a CI ainda rodando; (b) a mesma CI terminada, mergeavel; (c) conflito; (d) merge feito.
const EM_CURSO = { ...PR_455, state: 'OPEN', statusCheckRollup: PR_455.statusCheckRollup.map(c => ({ ...c, status: 'IN_PROGRESS', conclusion: '' })) }
const VERDE = { ...EM_CURSO, statusCheckRollup: EM_CURSO.statusCheckRollup.map(c => ({ ...c, status: 'COMPLETED', conclusion: 'SUCCESS' })), mergeStateStatus: 'CLEAN', mergeable: 'MERGEABLE' }
const CONFLITO = { ...VERDE, mergeStateStatus: 'DIRTY', mergeable: 'CONFLICTING' }
const MERGEADO = { ...VERDE, state: 'MERGED' }

const MIN = 60000
const INICIO = 1760000000000

const PANE_PROPS = {
  title: 'PR',
  isFocused: false,
  bodyColumns: 100,
  placement: 'inline' as const,
  scroll: { offset: 0, bodyRows: 40 },
  view: {},
}

const saida = (stdout: string, exitCode = 0) => ({
  value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'recusado', isStdoutTruncated: false, isStderrTruncated: false },
})

type Surface = 'terminal' | 'desktop'

// Monta o mundo por baixo do mod. `pr` e o que `gh pr view` devolve agora; `retomada` e o
// que `gh pr view --json state,url,headRefName` devolve na abertura (null = exit 1, sem PR).
async function montar($: any, on: any, surface: Surface, inicial: Record<string, unknown> = EM_CURSO) {
  const relogio = mock.clock(on, { now: INICIO })
  mock.store(on)
  const sessao = mock.session(on)
  const s = {
    pr: inicial as Record<string, unknown>,
    ghSai1: false,
    retomada: null as null | { state: string; url: string; headRefName: string },
    gh: [] as string[][],
    opens: [] as { id: unknown }[],
    closes: 0,
    notifies: [] as string[],
    submits: [] as string[],
    toasts: [] as string[],
    cmdTool: 'ok' as string,
    toolFalha: false,
  }
  on('process.run', async (_$: any, e: any) => {
    if (e.argv[0] === 'gh') {
      s.gh.push([...e.argv])
      if (e.argv[1] === 'api') return saida(THREADS_455)
      if (e.argv.includes('state,url,headRefName')) return s.retomada === null ? saida('', 1) : saida(JSON.stringify(s.retomada))
      return s.ghSai1 ? saida('', 1) : saida(JSON.stringify(s.pr))
    }
    return saida('', 1)
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.id', async () => ({ value: 'sessao-atual' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', async () => ({ sessionId: 'sessao-atual' }) as never)
  on('command.register', async (_$: any, e: any) => ({ value: { command: e.name } }) as never)
  on('ui.open', async (_$: any, e: any) => {
    s.opens.push({ id: e.id })
    return { value: { isPlaced: true } } as never
  })
  on('ui.close', async () => {
    s.closes += 1
    return { value: undefined } as never
  })
  on('ui.notify', async (_$: any, e: any) => {
    s.notifies.push(String(e.text))
    return { value: undefined } as never
  })
  on('ui.toast', async (_$: any, e: any) => {
    s.toasts.push(String(e.text))
    return { value: undefined } as never
  })
  on('prompt.submit', async (_$: any, e: any) => {
    s.submits.push(String(e.text))
    return e as never
  })
  on('tool.call', async () => ({ result: s.cmdTool, isError: s.toolFalha }) as never)
  on('turn.complete', async () => ({ text: '' }))
  // Fundo da cadeia do desenho: o que o engine desenharia quando o mod cede.
  on('ui.render', async (t$: any, e: any) => {
    const { Box } = t$.ui.resolve(e)
    return <Box />
  })

  const abrirPane = async () => $.ui.mount({ plugin: 'rainforest-mind', surface, component: 'Pane', requestId: 'rainforest-mind-pr', props: PANE_PROPS })
  const textos = async (ui: any) => (await ui.findAll({ type: 'Text' })).map((t: any) => t.text as string)
  const comecar = () => $.session.start({ cwd: '/projeto', surface, isInteractive: true })
  const bash = (command: string) => $.tool.call({ tool: 'Bash', command } as never)
  const ghDeView = () => s.gh.filter(a => a[1] === 'pr' && !a.includes('state,url,headRefName')).length
  const caso = async (nome: string, fn: () => Promise<void>) => {
    try {
      await fn()
    } catch (err) {
      throw new Error(`[${surface}] ${nome}: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  return { relogio, s, sessao, abrirPane, textos, comecar, bash, ghDeView, caso }
}

const NOTA_VERDE = 'PR #455: checks ok e mergeável (mergeStateStatus CLEAN). Mande mergear: gh pr merge 455 --squash --delete-branch'

for (const surface of ['terminal', 'desktop'] as const) {
  test(`gh pr create observado abre o pane e marca origem sessao (${surface})`, async ($, on) => {
    const m = await montar($, on, surface)
    const { s, relogio, bash, abrirPane, textos, caso, sessao } = m
    await m.comecar()
    await relogio.settle()

    await caso('gh pr create abre o pane com o PR da URL que saiu na saida', async () => {
      s.cmdTool = `${URL_PR}\n`
      await bash('gh pr create --title t --body b')
      await relogio.settle()
      expect(s.opens.map(o => o.id)).toEqual(['rainforest-mind-pr'])
      const visao = s.gh.find(a => a[1] === 'pr' && !a.includes('state,url,headRefName'))!
      expect(visao[3]).toBe(URL_PR)
      const t = (await textos(await abrirPane())).join('\n')
      expect(t).toContain('#455')
      expect(t).toContain('fluxo/gate-call-operator-variavel → main · @luisfmontes')
      expect(t).toContain('checks: 2 rodando de 2')
      expect(t).toContain('threads 0/0')
      expect(t).toContain('a954e19')
      expect(t).toContain('acompanhando a partir de a954e19')
    })

    await caso('origem sessao: a CI terminar acorda a sessao depois da quietude', async () => {
      s.pr = VERDE
      await relogio.advance(MIN)
      expect(s.submits).toEqual([])
      await relogio.advance(3 * MIN)
      expect(s.submits).toEqual([NOTA_VERDE])
      const linhas = sessao.appended().map(r => JSON.stringify(r.message))
      expect(linhas.filter(l => l.includes(NOTA_VERDE)).length).toBe(1)
    })
  })

  test(`gh pr view 455 observado tambem abre o pane (${surface})`, async ($, on) => {
    const m = await montar($, on, surface)
    const { s, relogio, bash, caso } = m
    await caso('abre pela URL que esta no comando', async () => {
      s.cmdTool = 'ok'
      await bash(`gh pr view ${URL_PR}`)
      await relogio.settle()
      expect(s.opens.map(o => o.id)).toEqual(['rainforest-mind-pr'])
    })
    await caso('comando sem URL de PR nao abre nada', async () => {
      await bash('gh pr view 456')
      await relogio.settle()
      expect(s.opens.length).toBe(1)
    })
  })

  test(`comando que falha nao abre o pane e o resultado volta identico (${surface})`, async ($, on) => {
    const m = await montar($, on, surface)
    const { s, relogio, bash, caso } = m
    await caso('gh pr create que falhou nao abre', async () => {
      s.cmdTool = 'erro de rede'
      s.toolFalha = true
      const ran = await bash(`gh pr create && echo ${URL_PR}`)
      await relogio.settle()
      expect(s.opens.length).toBe(0)
      expect(s.gh.length).toBe(0)
      expect((ran as any).isError).toBe(true)
    })
    await caso('com o gh saindo 1 o tool.call volta igual ao de um comando que o mod nao observa', async () => {
      s.toolFalha = false
      s.cmdTool = `${URL_PR}\n`
      s.ghSai1 = true
      const observado = await bash('gh pr create --fill')
      await relogio.settle()
      const comum = await bash('git status')
      expect(JSON.stringify(observado)).toBe(JSON.stringify(comum))
      expect(s.gh.length).toBeGreaterThan(0)
    })
  })

  test(`PR acompanhado por /pr nao acorda a sessao (${surface})`, async ($, on) => {
    const m = await montar($, on, surface)
    const { s, relogio, sessao, caso } = m
    await caso('/pr 455 abre o pane', async () => {
      const r = await $.command.run({ command: 'pr', args: '455' } as never)
      await relogio.settle()
      expect(s.opens.map(o => o.id)).toEqual(['rainforest-mind-pr'])
      expect(String((r as any).text)).toContain('Acompanhando #455')
    })
    await caso('a virada grava a nota na conversa e avisa, mas nao acorda ninguem', async () => {
      s.pr = VERDE
      await relogio.advance(MIN)
      const linhas = sessao.appended().map(r => JSON.stringify(r.message))
      expect(linhas.filter(l => l.includes(NOTA_VERDE)).length).toBe(1)
      expect(s.notifies.length).toBe(1)
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual([])
    })
  })

  test(`PR da sessao acorda uma vez so e o conflito traz ao usuario (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, VERDE)
    const { s, relogio, bash, caso } = m
    await caso('abre com a CI ja verde: sem virada, nada acorda', async () => {
      s.cmdTool = `${URL_PR}\n`
      await bash('gh pr create --fill')
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual([])
    })
    await caso('conflito: uma nota que manda resumir sem alterar, enviada uma vez', async () => {
      s.pr = CONFLITO
      await relogio.advance(MIN)
      expect(s.submits).toEqual([])
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual(['PR #455: conflito com a base. Resuma e traga ao usuário, sem alterar nada.'])
    })
  })

  test(`merged para o polling: nenhum gh depois (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, VERDE)
    const { s, relogio, bash, abrirPane, textos, ghDeView, caso } = m
    await caso('acompanha e sente o merge no poll seguinte', async () => {
      s.cmdTool = `${URL_PR}\n`
      await bash('gh pr create --fill')
      await relogio.settle()
      s.pr = MERGEADO
      await relogio.advance(MIN)
      const t = (await textos(await abrirPane())).join('\n')
      expect(t).toContain('merged')
      expect(t).toContain('open → merged')
    })
    await caso('depois do merge nenhuma consulta nova', async () => {
      const antes = s.gh.length
      expect(ghDeView()).toBeGreaterThan(0)
      await relogio.advance(20 * MIN)
      expect(s.gh.length).toBe(antes)
    })
  })

  test(`retomada: PR aberto de branch fluxo/ na abertura acorda (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, VERDE)
    const { s, relogio, comecar, caso } = m
    await caso('abertura numa branch com PR OPEN acompanha pela URL', async () => {
      s.retomada = { state: 'OPEN', url: URL_PR, headRefName: 'fluxo/gate-call-operator-variavel' }
      s.pr = EM_CURSO
      await comecar()
      await relogio.settle()
      expect(s.opens.map(o => o.id)).toEqual(['rainforest-mind-pr'])
    })
    await caso('branch fluxo/: a CI terminar acorda', async () => {
      s.pr = VERDE
      await relogio.advance(MIN)
      await relogio.advance(4 * MIN)
      expect(s.submits).toEqual([NOTA_VERDE])
    })
  })

  test(`retomada em branch comum so mostra (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, EM_CURSO)
    const { s, relogio, comecar, caso } = m
    await caso('abertura em branch comum acompanha mas a CI terminar nao acorda', async () => {
      s.retomada = { state: 'OPEN', url: URL_PR, headRefName: 'feature/qualquer' }
      await comecar()
      await relogio.settle()
      expect(s.opens.length).toBe(1)
      s.pr = VERDE
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual([])
    })
  })

  test(`sem PR na abertura nao ha gh depois dela (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, EM_CURSO)
    const { s, relogio, comecar, caso } = m
    await caso('sem PR na branch: so a checagem de abertura roda gh', async () => {
      s.retomada = null
      await comecar()
      await relogio.settle()
      await relogio.advance(10 * MIN)
      expect(s.gh.length).toBe(1)
      expect(s.opens.length).toBe(0)
    })
  })
}

// Registro REAL de plugins instalados (forma da versao 2): ids nome@marketplace, lista de
// instalacoes com scope e version; so o installPath ficou neutro.
const registro = (versao: string) =>
  JSON.stringify({
    version: 2,
    plugins: {
      'rainforest-mind@rainforest-mind': [
        { scope: 'user', installPath: `<home>/plugins/cache/rainforest-mind/rainforest-mind/${versao}`, version: versao, installedAt: '2026-08-08T15:56:01.994Z', lastUpdated: '2026-10-09T13:47:15.749Z' },
      ],
    },
  })

async function montarPlugins($: any, on: any) {
  const relogio = mock.clock(on, { now: INICIO })
  mock.store(on)
  mock.env(on, { CLAUDE_CONFIG_DIR: 'C:/ContaTeste' })
  const s = { versao: '1.53.2', lidos: [] as string[], cli: [] as string[][], reloads: 0, toasts: [] as string[] }
  on('fs.read', async (_$: any, e: any) => {
    s.lidos.push(String(e.path))
    return { value: registro(s.versao) } as never
  })
  on('process.run', async (_$: any, e: any) => {
    // O painel de PR tambem roda `gh` na abertura (sem PR aqui): so o `claude` entra na conta.
    if (e.argv[0] !== 'cmd') return saida('', 1)
    s.cli.push([...e.argv])
    if (e.argv[0] === 'cmd' && e.argv.includes('update') && e.argv.includes('rainforest-mind@rainforest-mind')) s.versao = '1.54.0'
    return saida('ok')
  })
  on('command.run', { command: 'reload-plugins' }, async () => {
    s.reloads += 1
    return { text: '' }
  })
  on('ui.toast', async (_$: any, e: any) => {
    s.toasts.push(String(e.text))
    return { value: undefined } as never
  })
  on('command.register', async (_$: any, e: any) => ({ value: { command: e.name } }) as never)
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  return { relogio, s }
}

test('plugins-em-dia: sobe a versao, devolve o texto e, sem recarregarSozinho, so avisa', async ($, on) => {
  const { s } = await montarPlugins($, on)
  const r = await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  expect(String((r as any).text)).toContain('rainforest-mind 1.53.2 -> 1.54.0')
  // o engine normaliza o separador do caminho que o mod montou com barras
  expect(s.lidos[0].replace(/\\/g, '/')).toBe('C:/ContaTeste/plugins/installed_plugins.json')
  // marketplace antes de plugin, com o shim .cmd do npm do Windows
  expect(s.cli[0]).toEqual(['cmd', '/d', '/c', 'claude', 'plugin', 'marketplace', 'update', 'rainforest-mind'])
  expect(s.cli[1]).toEqual(['cmd', '/d', '/c', 'claude', 'plugin', 'update', 'rainforest-mind@rainforest-mind', '--scope', 'user'])
  expect(s.reloads).toBe(0)
  expect(s.toasts.some(t => t.includes('/reload-plugins'))).toBe(true)
})

test('plugins-em-dia: com recarregarSozinho recarrega pelo comando do engine', { options: { recarregarSozinho: true } }, async ($, on) => {
  const { s, relogio } = await montarPlugins($, on)
  const r = await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  expect(String((r as any).text)).toContain('atualizados: rainforest-mind 1.53.2 -> 1.54.0; recarregando em 1 s')
  // o recarregamento sai de um evento posterior ao comando, nunca de dentro dele
  expect(s.reloads).toBe(0)
  await relogio.advance(1000)
  expect(s.reloads).toBe(1)
  expect(s.toasts.some(t => t.includes('atualizados e recarregados'))).toBe(true)
})

test('plugins-em-dia: a abertura roda sozinha, a trava de 30 min segura a segunda e o comando passa por cima', async ($, on) => {
  const { s, relogio } = await montarPlugins($, on)
  await $.session.start({ cwd: '/projeto', surface: 'terminal', isInteractive: true })
  await relogio.settle()
  expect(s.versao).toBe('1.54.0')
  const rodou = s.cli.length
  expect(rodou).toBe(2)
  await relogio.advance(10 * MIN)
  expect(s.cli.length).toBe(rodou)
  const r = await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  expect(String((r as any).text)).toContain('tudo em dia (rainforest-mind 1.54.0)')
  expect(s.cli.length).toBe(rodou * 2)
})
