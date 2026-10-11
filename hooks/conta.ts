// Aviso da troca de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 8; design D6): a cada
// 60 s roda `scripts/conta.cjs eventos --desde <ultima>` e mostra um aviso por evento novo.
// A logica pura (frases, filtro por tempo) mora em ./conta-puro.mjs; aqui so se liga os eventos.
// O engine so aceita `$` passado a funcao declarada no topo deste arquivo (as de baixo); aos
// `.mjs` vao so valores. Toda leitura do mundo falha aberta: sem node ou sem dados, nada aparece.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { frase, novos } from './conta-puro.mjs'
import { escolherExecutavel, localizadores } from './pr-puro.mjs'

const INTERVALO_MS = 60_000
const nodeCaminho = atom({ plugin: 'rainforest-mind', key: 'contaNode' } as const, '')

// Timestamp (ms) do ultimo aviso dado: so o que chegou depois dele aparece. Estado de modulo
// como o timer do pr.tsx: nao e dado de sessao.
let ultima = 0
let rodando = false

// SystemRoot do ambiente; sem ele (ou se a leitura falhar) o localizador cai em C:\Windows.
async function raizDoWindows($: EngineInterface): Promise<string | undefined> {
  try {
    return await $.env.get('SystemRoot')
  } catch {
    return undefined
  }
}

async function cwdDaSessao($: EngineInterface): Promise<string> {
  try {
    return (await $.session.cwd()) ?? ''
  } catch {
    return ''
  }
}

// Caminho absoluto do node, achado UMA vez e fora do repositorio da sessao (o Windows procura o
// executavel primeiro na pasta atual). O localizador roda na pasta do plugin, nunca no repo.
async function caminhoDoNode($: EngineInterface): Promise<string | null> {
  const guardado = await read($, nodeCaminho)
  if (guardado !== '') return guardado
  const cwd = await cwdDaSessao($)
  for (const argv of localizadores('node', await raizDoWindows($)) as string[][]) {
    try {
      const r = await $.process.run(argv, { cwd: $.plugin.root, timeoutMs: 10_000 })
      if (r.exitCode !== 0) continue
      const achado = escolherExecutavel(r.stdout, cwd) as string | null
      if (achado !== null) {
        await update($, nodeCaminho, () => achado)
        return achado
      }
    } catch {
      // este localizador nao existe nesta maquina; o outro tenta
    }
  }
  return null
}

async function rodada($: EngineInterface): Promise<void> {
  if (rodando) return
  rodando = true
  try {
    const node = await caminhoDoNode($)
    if (node === null) return
    const r = await $.process.run([node, `${$.plugin.root}/scripts/conta.cjs`, 'eventos', '--desde', String(ultima)], { cwd: $.plugin.root, timeoutMs: 30_000 })
    if (r.exitCode !== 0) return
    for (const ev of novos(String(r.stdout).split('\n'), ultima) as { em: number }[]) {
      const texto = frase(ev) as string
      if (texto !== '') void Promise.resolve($.ui.notify(texto, { title: 'Conta' })).catch(() => {})
      ultima = Math.max(ultima, ev.em)
    }
  } catch {
    // falha silenciosa: a proxima rodada tenta de novo
  } finally {
    rodando = false
  }
}

export const register: Register = on => {
  on('session.start', { isInteractive: true }, async ($, e, next) => {
    try {
      // So aparece o que chegar depois de abrir a sessao: o historico nao vira enxurrada de avisos.
      ultima = await $.clock.now()
      $.clock.every(INTERVALO_MS, () => void rodada($))
    } catch {
      // sem relogio nao ha como separar o que e novo: o aviso fica quieto nesta sessao
    }
    return next(e)
  })
}
