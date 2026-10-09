// Painel de PR do mod (/pr): acompanha um PR do `gh pr create` ao merge, mostra o estado num
// pane proprio e, nas viradas que pedem acao, grava uma nota na conversa e acorda a sessao.
// A logica pura (resumo, eventos, virada, nota, quem pode acordar) mora em ./pr-puro.mjs; aqui
// so se liga os eventos. O engine so aceita `$` passado a funcao declarada no topo deste
// arquivo (as de baixo); aos `.mjs` vao so valores.
// Toda leitura do mundo falha aberta: o hook de `tool.call` devolve SEMPRE o resultado de
// `next(e)` como veio, e o pane diz o que faltou em vez de quebrar.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import type {
  RainforestMindPrAcompanhado,
  RainforestMindPrEvento,
  RainforestMindPrOrigem,
  RainforestMindPrPendente,
  RainforestMindPrResumo,
} from '../types'
import { POLL_MS, QUIETO_MS, deveAcordar, eventos, nota, resumir, virada } from './pr-puro.mjs'

const PANE = 'rainforest-mind-pr'
const AJUDA = 'Uso: /pr [numero | url | fechar]'
const MAX_EVENTOS = 100

const prAcompanhado = atom({ plugin: 'rainforest-mind', key: 'prAcompanhado' } as const, null as RainforestMindPrAcompanhado | null)
const prResumo = atom({ plugin: 'rainforest-mind', key: 'prResumo' } as const, null as RainforestMindPrResumo | null)
const prEventos = atom({ plugin: 'rainforest-mind', key: 'prEventos' } as const, [] as RainforestMindPrEvento[])
const prErro = atom({ plugin: 'rainforest-mind', key: 'prErro' } as const, '')
const prPendente = atom({ plugin: 'rainforest-mind', key: 'prPendente' } as const, null as RainforestMindPrPendente | null)

const CAMPOS = 'number,title,url,state,isDraft,headRefOid,headRefName,baseRefName,author,updatedAt,mergeable,mergeStateStatus,reviewDecision,latestReviews,statusCheckRollup,comments'
const QUERY_THREADS = 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){totalCount nodes{isResolved}}}}}'

const GH_PR = /\bgh(\.exe)?\s+pr\s+(create|merge|checks|ready|view)\b/
const GH_PR_CREATE = /\bgh(\.exe)?\s+pr\s+create\b/
const PR_URL = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+$/
const PR_URL_G = /https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+/
const PR_PARTES = /^https:\/\/github\.com\/([\w.-]+)\/([\w.-]+)\/pull\/(\d+)$/

// Timer do polling e travas contra consulta e despertar em paralelo: nao sao dado de sessao.
let timer: { cancel: () => void } | null = null
let consultando = false
let acordando = false

const dois = (n: number): string => String(n).padStart(2, '0')
const hhmm = (ms: number): string => {
  const d = new Date(ms)
  return Number.isNaN(d.getTime()) ? '' : `${dois(d.getHours())}:${dois(d.getMinutes())}`
}

const corDoIcone = (icone: string): string | undefined => (icone === '✓' ? 'green' : icone === '×' ? 'red' : icone === '◐' ? 'yellow' : undefined)
const corDosChecks = (c: string): string | undefined => (c.startsWith('checks ok') ? 'green' : c.includes('falharam') ? 'red' : c.includes('rodando') ? 'yellow' : undefined)

function parar(): void {
  if (timer !== null) {
    try {
      timer.cancel()
    } catch {
      // timer ja encerrado
    }
    timer = null
  }
}

// Acorda a sessao uma vez por virada: so PR da sessao (D6), so depois da quietude (D7). A
// pendencia sai do estado antes do envio, entao a mesma virada nunca acorda duas vezes.
async function acordarSePreciso($: EngineInterface): Promise<void> {
  if (acordando) return
  acordando = true
  try {
    const pendente = await read($, prPendente)
    const ac = await read($, prAcompanhado)
    if (pendente === null || ac === null) return
    const agoraMs = await $.clock.now()
    const pr = {
      deveAcordar: deveAcordar({
        origem: ac.origem,
        branch: ac.branch,
        virada: pendente.virada,
        ultimaMudancaMs: pendente.ultimaMudancaMs,
        agoraMs,
      }),
    }
    if (pr.deveAcordar) await update($, prPendente, () => null)
    if (pr.deveAcordar) await $.prompt.submit({ text: pendente.nota })
  } catch {
    // acordar e conveniencia: a nota ja esta na conversa
  } finally {
    acordando = false
  }
}

async function gh($: EngineInterface, argv: string[]) {
  let cwd: string | undefined
  try {
    cwd = await $.session.cwd()
  } catch {
    cwd = undefined
  }
  return $.process.run(['gh', ...argv], { cwd, timeoutMs: 30_000 })
}

async function lerThreads($: EngineInterface, url: string): Promise<{ totalCount: number; nodes: { isResolved: boolean }[] } | null> {
  const m = PR_PARTES.exec(url)
  if (m === null) return null
  try {
    const r = await gh($, ['api', 'graphql', '-F', `owner=${m[1]}`, '-F', `name=${m[2]}`, '-F', `number=${m[3]}`, '-f', `query=${QUERY_THREADS}`])
    if (r.exitCode !== 0) return null
    const t = JSON.parse(r.stdout)?.data?.repository?.pullRequest?.reviewThreads
    return t && Array.isArray(t.nodes) ? t : null
  } catch {
    return null
  }
}

async function consultar($: EngineInterface): Promise<void> {
  if (consultando) return
  consultando = true
  try {
    const ac = await read($, prAcompanhado)
    if (ac === null) return
    let pr: Record<string, unknown>
    try {
      const r = await gh($, ['pr', 'view', ...(ac.alvo ? [ac.alvo] : []), '--json', CAMPOS])
      if (r.exitCode !== 0) {
        const motivo = String(r.stderr).includes('no pull requests found')
          ? 'Nenhum PR para a branch atual.'
          : `gh saiu ${r.exitCode}: ${String(r.stderr).trim().split('\n')[0]}`
        await update($, prErro, () => motivo)
        return
      }
      pr = JSON.parse(r.stdout)
    } catch (err) {
      await update($, prErro, () => `gh nao rodou: ${String(err).slice(0, 120)}`)
      return
    }
    await update($, prErro, () => '')

    const agora = await $.clock.now()
    const threads = await lerThreads($, String(pr.url ?? ''))
    const novo: RainforestMindPrResumo = { ...resumir(pr, threads), atualizadoEm: hhmm(Date.parse(String(pr.updatedAt ?? ''))) }
    const velho = await read($, prResumo)
    const evs = eventos(velho, novo, agora) as { icone: string; texto: string }[]
    const hora = hhmm(agora)
    await update($, prResumo, () => novo)
    // O alvo vira a URL: dali em diante a consulta nao depende da branch nem do cwd.
    if (ac.alvo !== novo.url) await update($, prAcompanhado, a => (a === null ? a : { ...a, alvo: novo.url }))
    if (evs.length > 0) {
      await update($, prEventos, l => [...l, ...evs.map(ev => ({ hora, icone: ev.icone, texto: ev.texto }))].slice(-MAX_EVENTOS))
      // Qualquer mudanca recomeca a contagem de quietude de uma virada que ainda espera.
      await update($, prPendente, p => (p === null ? p : { ...p, ultimaMudancaMs: agora }))
    }

    const v = virada(velho, novo) as string | null
    if (v !== null) {
      const texto = nota(v, novo) as string
      await update($, prPendente, () => ({ virada: v, nota: texto, ultimaMudancaMs: agora }))
      try {
        await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: texto }] } })
      } catch {
        // sem a nota na conversa o pane e o aviso seguem
      }
      void Promise.resolve($.ui.notify(`#${novo.numero}: ${v}`, { title: 'PR' })).catch(() => {})
      // A checagem de quietude: o poll tambem olha, mas o PR pode ter parado de mudar.
      void $.clock.after(QUIETO_MS, () => void acordarSePreciso($))
    }

    if (novo.estado === 'MERGED' || novo.estado === 'CLOSED') {
      parar()
      return
    }
    await acordarSePreciso($)
  } finally {
    consultando = false
  }
}

// Passa a acompanhar `alvo` ('' = PR da branch atual, numero ou URL) e abre o pane.
async function seguir($: EngineInterface, alvo: string, origem: RainforestMindPrOrigem, branch: string): Promise<boolean> {
  const ac = await read($, prAcompanhado)
  if (ac === null || ac.alvo !== alvo) {
    await update($, prAcompanhado, () => ({ alvo, origem, branch }))
    await update($, prResumo, () => null)
    await update($, prEventos, () => [])
    await update($, prErro, () => '')
    await update($, prPendente, () => null)
  }
  await consultar($)
  // Terminou (merge ou fechamento) na primeira leitura: nao ha o que pesquisar depois.
  const r = await read($, prResumo)
  parar()
  if (r === null || (r.estado !== 'MERGED' && r.estado !== 'CLOSED')) {
    timer = $.clock.every(POLL_MS, () => void consultar($))
  }
  const aberto = await $.ui.open({ id: PANE, title: 'PR' })
  return aberto.isPlaced === true
}

export const register: Register = on => {
  on('session.start', { cwd: /.*/ }, async ($, e, next) => {
    try {
      await $.command.register({
        name: 'pr',
        description: 'Painel do PR: checks, reviews e merge (sem argumento = PR da branch atual)',
        argumentHint: '[numero | url | fechar]',
      })
    } catch {
      // sem comando, o gatilho automatico segue
    }
    if (!e.isInteractive) return next(e)
    // Sessao que abre numa branch com PR aberto ja acompanha (retomada de fluxo). Nao bloqueia
    // a abertura; sem PR ou sem gh, nada acontece.
    void (async () => {
      const r = await $.process.run(['gh', 'pr', 'view', '--json', 'state,url,headRefName'], { cwd: e.cwd, timeoutMs: 20_000 })
      if (r.exitCode !== 0) return
      const pr = JSON.parse(r.stdout) as { state: string; url: string; headRefName: string }
      if (pr.state === 'OPEN' && (await read($, prAcompanhado)) === null) await seguir($, pr.url, 'retomada', pr.headRefName)
    })().catch(() => {})
    return next(e)
  })

  on('command.run', { command: 'pr' }, async ($, e) => {
    const arg = `${e.args ?? ''}`.trim()
    if (arg === 'fechar') {
      parar()
      await update($, prAcompanhado, () => null)
      await update($, prPendente, () => null)
      try {
        await $.ui.close({ id: PANE })
      } catch {
        // pane ja fechado
      }
      return { text: 'Painel do PR fechado.' }
    }
    if (arg !== '' && !/^\d+$/.test(arg) && !PR_URL.test(arg)) return { text: AJUDA }
    let colocado = false
    try {
      // Sem argumento e com PR ja acompanhado: reabre o pane sem trocar a origem.
      const atual = arg === '' ? await read($, prAcompanhado) : null
      colocado = await seguir($, atual === null ? arg : atual.alvo, atual === null ? 'manual' : atual.origem, atual === null ? '' : atual.branch)
    } catch {
      // o texto abaixo diz o que faltou
    }
    const r = await read($, prResumo)
    const onde = r ? `#${r.numero} ${r.titulo}` : (await read($, prErro)) || 'nenhum PR'
    return { text: colocado ? `Acompanhando ${onde}.` : `Acompanhando ${onde} (alargue o terminal para ver o painel).` }
  }).catch(() => ({ text: 'Painel do PR indisponível agora.' }))

  // Automatico: todo `gh pr create|merge|checks|ready|view` que a sessao rodar passa a ser
  // acompanhado, pela URL que saiu no comando ou na saida. Nunca atrapalha o comando: o
  // resultado de `next(e)` volta como veio, e se este hook lancar o `.catch` repassa.
  for (const tool of ['Bash', 'PowerShell'] as const) {
    on('tool.call', { tool }, async ($, e, next) => {
      const ran = await next(e)
      try {
        const cmd = String((e as { command?: unknown }).command ?? '')
        if (!GH_PR.test(cmd) || ran.deny !== undefined || ran.isError) return ran
        const url = (cmd + ' ' + JSON.stringify(ran.result ?? '')).match(PR_URL_G)?.[0]
        if (url !== undefined) {
          const ac = await read($, prAcompanhado)
          if (ac === null || ac.alvo !== url) void seguir($, url, GH_PR_CREATE.test(cmd) ? 'sessao' : 'manual', '').catch(() => {})
        }
      } catch {
        // observar nunca muda o comando
      }
      return ran
    }).catch(($, e, next) => next(e))
  }

  // O pane: titulo, branch -> base, estado, checks, merge, threads, head e a linha do tempo.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    try {
      const { Box, Text } = $.ui.resolve(e)
      const r = await read($, prResumo)
      const lista = await read($, prEventos)
      const msg = await read($, prErro)
      const sala = Math.max(3, (e.props.scroll?.bodyRows ?? 24) - 8)
      if (r === null) return <Text dimColor>{msg || 'Consultando o PR...'}</Text>
      return (
        <Box flexDirection="column">
          <Text bold>{`#${r.numero} ${r.titulo}`}</Text>
          <Text dimColor>{`${r.branch} → ${r.base} · @${r.autor}`}</Text>
          <Text color={corDosChecks(r.checks)}>{`${r.estado.toLowerCase()} · ${r.checks} · ${r.motivo} · threads ${r.threadsAbertas}/${r.threadsTotal}`}</Text>
          <Text dimColor>{`${r.head} · atualizado ${r.atualizadoEm}`}</Text>
          {msg ? <Text color="red">{msg}</Text> : null}
          <Text> </Text>
          {[...lista]
            .slice(-sala)
            .reverse()
            .map((ev, i) => (
              <Text key={`ev-${i}`} color={corDoIcone(ev.icone)}>{`${ev.hora} ${ev.icone} ${ev.texto}`}</Text>
            ))}
        </Box>
      )
    } catch {
      return next(e)
    }
  })
}
