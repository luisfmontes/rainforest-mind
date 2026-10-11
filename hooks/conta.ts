// Aviso da troca de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 8; design D6): a cada
// 60 s roda `scripts/conta.cjs eventos --desde <ultima>` e mostra um aviso por evento novo.
// A logica pura (frases, filtro por tempo, localizador do node) mora em ./conta-puro.mjs; aqui so
// se liga os eventos. O engine so aceita `$` passado a funcao declarada no topo deste arquivo (as
// de baixo); aos `.mjs` vao so valores. Toda leitura do mundo falha aberta: sem node ou sem dados,
// nada aparece.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { acharNode, frase, novos } from './conta-puro.mjs'

const INTERVALO_MS = 60_000
// Mesmas chaves do relogio (mod.tsx): o node achado, e a falha que espera o prazo, valem para os dois.
const nodeCaminho = atom({ plugin: 'rainforest-mind', key: 'nodeCaminho' } as const, '')
const nodeFalhouEm = atom({ plugin: 'rainforest-mind', key: 'nodeFalhouEm' } as const, 0)

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

// Caminho absoluto do node: a regra (achar uma vez, nao procurar de novo 5 min depois de falhar)
// e a mesma do relogio, em acharNode de ./conta-puro.mjs.
async function caminhoDoNode($: EngineInterface): Promise<string | null> {
  return acharNode({
    guardado: await read($, nodeCaminho),
    falhouEm: await read($, nodeFalhouEm),
    agora: await $.clock.now(),
    lerCwd: async () => {
      try {
        return (await $.session.cwd()) ?? ''
      } catch {
        return ''
      }
    },
    lerRaiz: () => raizDoWindows($),
    rodar: argv => $.process.run(argv, { cwd: $.plugin.root, timeoutMs: 10_000 }),
    gravarCaminho: achado => update($, nodeCaminho, () => achado),
    gravarFalha: agora => update($, nodeFalhouEm, () => agora),
  }) as Promise<string | null>
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
  // Timer do aviso e id da sessao que o armou: so o session.end dela cancela o timer (como o
  // relogio do mod.tsx; uma sessao nao interativa que compartilha a instancia nao mexe nele).
  let timer: { cancel: () => void } | null = null
  let armadoPor: string | null = null
  const cancelar = () => {
    armadoPor = null
    if (timer !== null) {
      try {
        timer.cancel()
      } catch {
        // timer ja encerrado
      }
      timer = null
    }
  }

  on('session.start', { isInteractive: true }, async ($, e, next) => {
    cancelar()
    try {
      // So aparece o que chegar depois de abrir a sessao: o historico nao vira enxurrada de avisos.
      ultima = await $.clock.now()
      armadoPor = await $.session.id()
      timer = $.clock.every(INTERVALO_MS, () => {
        void (async () => {
          // Depois de /clear o processo segue com outro id: le-o de novo no proximo tick.
          if (armadoPor === null) {
            try {
              armadoPor = await $.session.id()
            } catch {
              // sem id, o fim desta sessao nao cancela o aviso (falha aberta)
            }
          }
          await rodada($)
        })()
      })
    } catch {
      // sem relogio nao ha como separar o que e novo: o aviso fica quieto nesta sessao
    }
    return next(e)
  })

  // O matcher (qualquer motivo) evita colidir com o session.end sem matcher da abertura.
  on('session.end', { reason: /.*/ }, async (_$, e, next) => {
    if (armadoPor !== null && e.sessionId === armadoPor) {
      // /clear nao tem session.start depois: o aviso segue e o id novo e lido no proximo tick.
      if (e.reason === 'clear') armadoPor = null
      else cancelar()
    }
    return next(e)
  })
}
