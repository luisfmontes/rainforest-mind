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
// Onde o localizador (where.exe) acha o gh e o CLI do Claude, fora de qualquer repositorio.
const GH_EXE = 'C:\\Program Files\\GitHub CLI\\gh.exe'
const CLAUDE_CMD = 'C:\\Users\\teste\\AppData\\Roaming\\npm\\claude.cmd'

const PR_455 = {
  number: 455,
  title: 'Gate: & "$pasta\\script.ps1" analisado pelo nome literal (1.53.2)',
  url: URL_PR,
  state: 'MERGED',
  isDraft: false,
  headRefOid: 'a954e193059d3f392aab8afc1d9de4748b5a2c41',
  headRefName: 'fluxo/gate-call-operator-variavel',
  baseRefName: 'main',
  isCrossRepository: false,
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
    eu: 'luisfmontes',
    localizador: `${GH_EXE}\r\n`,
    rodou: [] as string[],
    ghEnv: [] as any[],
    toolFalha: false,
  }
  on('process.run', async (_$: any, e: any) => {
    s.rodou.push(String(e.argv[0]))
    // O localizador: where.exe acha o que s.localizador diz; o `which` nao existe aqui (exit 1).
    if (/[\\/]system32[\\/]where\.exe$/i.test(String(e.argv[0]))) return saida(s.localizador)
    if (e.argv[0] === GH_EXE) {
      s.gh.push([...e.argv])
      s.ghEnv.push(e.init?.env ?? null)
      if (e.argv[1] === 'api' && e.argv[2] === 'user') return saida(`${s.eu}\n`)
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

const NOTA_ALHEIA = 'PR #455 (acompanhado, não é desta sessão): checks ok e mergeável. Só informe o usuário; não aja sobre ele.'
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
      expect(linhas.filter(l => l.includes(NOTA_ALHEIA)).length).toBe(1)
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

  test(`PR de fork aberto pela sessao nao acorda (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, { ...EM_CURSO, isCrossRepository: true })
    const { s, relogio, sessao, bash, caso } = m
    await caso('gh pr create observado: o pane abre, mas o PR de fork rebaixa a origem', async () => {
      s.cmdTool = `${URL_PR}\n`
      await bash('gh pr create --fill')
      await relogio.settle()
      expect(s.opens.map(o => o.id)).toEqual(['rainforest-mind-pr'])
    })
    await caso('a CI terminar grava a nota na conversa, mas nao acorda ninguem', async () => {
      s.pr = { ...VERDE, isCrossRepository: true }
      await relogio.advance(MIN)
      const linhas = sessao.appended().map(r => JSON.stringify(r.message))
      expect(linhas.filter(l => l.includes(NOTA_ALHEIA)).length).toBe(1)
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual([])
    })
  })

  test(`PR de outro autor aberto pela sessao nao acorda (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, EM_CURSO)
    const { s, relogio, bash, caso } = m
    await caso('o gh logado e outra conta: a URL na saida nao basta', async () => {
      s.eu = 'outra-conta'
      s.cmdTool = `${URL_PR}\n`
      await bash('gh pr create --fill')
      await relogio.settle()
      s.pr = VERDE
      await relogio.advance(10 * MIN)
      expect(s.submits).toEqual([])
    })
  })

  test(`gh no repositorio da sessao nao e executado (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, EM_CURSO)
    const { s, relogio, comecar, caso } = m
    await caso('o localizador so acha gh dentro do cwd: nenhum process.run com esse caminho', async () => {
      s.localizador = '/projeto/gh.exe\r\n/projeto/sub/gh.cmd\r\n'
      s.retomada = { state: 'OPEN', url: URL_PR, headRefName: 'fluxo/gate-call-operator-variavel' }
      await comecar()
      const r = await $.command.run({ command: 'pr', args: '455' } as never)
      await relogio.advance(10 * MIN)
      expect(s.rodou.filter(a => a.startsWith('/projeto'))).toEqual([])
      expect(s.gh.length).toBe(0)
      expect(String((r as any).text)).toContain('gh nao encontrado fora do repositorio')
    })
  })

  // Auditoria de 2026-10-09: chamado pelo nome, o localizador e procurado primeiro na pasta
  // atual; e o gh, que roda na pasta do repositorio, nao pode herdar um core.fsmonitor plantado.
  test(`todo processo vai por caminho absoluto e o gh com fsmonitor desligado (${surface})`, async ($, on) => {
    const m = await montar($, on, surface, EM_CURSO)
    const { s, relogio, comecar, caso } = m
    await caso('/pr 455 e uma rodada de consulta', async () => {
      await comecar()
      await $.command.run({ command: 'pr', args: '455' } as never)
      await relogio.advance(2 * MIN)
      expect(s.rodou.length).toBeGreaterThan(0)
      // `node` pelo nome vem do /painel (hooks/mod.tsx), anterior a este mod: Issue propria.
      expect(s.rodou.filter(a => a !== 'node' && !/^([A-Za-z]:[\\/]|\/)/.test(a))).toEqual([])
      expect(s.ghEnv.length).toBeGreaterThan(0)
      expect(s.ghEnv.filter(env => !(env && env.GIT_CONFIG_KEY_0 === 'core.fsmonitor' && env.GIT_CONFIG_VALUE_0 === 'false'))).toEqual([])
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
      // Outro plugin instalado no escopo user, fora da lista padrao: so a opcao `plugins` o traz.
      'plugin-x@mkt-x': [{ scope: 'user', installPath: '<home>/plugins/cache/mkt-x/plugin-x/2.0.0', version: '2.0.0', installedAt: '2026-08-08T15:56:01.994Z', lastUpdated: '2026-10-09T13:47:15.749Z' }],
    },
  })

async function montarPlugins($: any, on: any) {
  const relogio = mock.clock(on, { now: INICIO })
  mock.store(on)
  mock.env(on, { CLAUDE_CONFIG_DIR: 'C:/ContaTeste' })
  const s = { versao: '1.53.2', lidos: [] as string[], cli: [] as string[][], reloads: 0, toasts: [] as string[], localizador: `${CLAUDE_CMD}\r\n` }
  on('fs.read', async (_$: any, e: any) => {
    s.lidos.push(String(e.path))
    return { value: registro(s.versao) } as never
  })
  on('process.run', async (_$: any, e: any) => {
    // O localizador responde so pelo CLI do Claude; o gh do painel de PR nao existe aqui (exit 1).
    if (/[\\/]system32[\\/]where\.exe$/i.test(String(e.argv[0]))) return e.argv.includes('claude.cmd') ? saida(s.localizador) : saida('', 1)
    // O cmd vai por caminho absoluto (%SystemRoot%\System32\cmd.exe), nunca pelo nome.
    if (!/[\\/]system32[\\/]cmd\.exe$/i.test(String(e.argv[0]))) return saida('', 1)
    s.cli.push(['cmd', ...e.argv.slice(1)])
    if (e.argv.includes('update') && e.argv.includes('rainforest-mind@rainforest-mind')) s.versao = '1.54.0'
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
  expect(s.cli[0]).toEqual(['cmd', '/d', '/c', CLAUDE_CMD, 'plugin', 'marketplace', 'update', 'rainforest-mind'])
  expect(s.cli[1]).toEqual(['cmd', '/d', '/c', CLAUDE_CMD, 'plugin', 'update', 'rainforest-mind@rainforest-mind', '--scope', 'user'])
  expect(s.reloads).toBe(0)
  expect(s.toasts.some(t => t.includes('/reload-plugins'))).toBe(true)
})

test('plugins-em-dia: claude no repositorio da sessao nao e executado', async ($, on) => {
  const { s } = await montarPlugins($, on)
  s.localizador = '/projeto/claude.cmd\r\n'
  const r = await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  expect(String((r as any).text)).toContain('claude nao encontrado fora do repositorio')
  expect(s.cli.length).toBe(0)
  expect(s.toasts.some(t => t.includes('claude nao encontrado'))).toBe(true)
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

test('plugins-em-dia: a opcao plugins chega ao mod e troca a lista', { options: { plugins: ['plugin-x@mkt-x'] } }, async ($, on) => {
  const { s } = await montarPlugins($, on)
  const r = await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  // so o plugin da opcao entra: o rainforest-mind esta instalado mas nao esta na lista
  expect(s.cli.map(a => a.slice(4).join(' '))).toEqual(['plugin marketplace update mkt-x', 'plugin update plugin-x@mkt-x --scope user'])
  expect(String((r as any).text)).toContain('tudo em dia (plugin-x 2.0.0)')
})
