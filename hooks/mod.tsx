// Entrada do mod: a abertura (register.ts, sem mudanca) mais a faixa acima do prompt
// (foco, fluxos em curso e Q abertas). A logica pura mora em ./faixa-puro.mjs; aqui so se
// liga os eventos. O engine recusa `$` passado como argumento a qualquer funcao do arquivo
// (closure inclusive), entao `buscar` recebe so `{ rodar, cwd, raiz }`, montado no ponto de
// chamada de cada hook.
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'
import type {
  RainforestMindFaixaDados,
  RainforestMindFaixaQ,
  RainforestMindRelogioJornada,
  RainforestMindRelogioSessoes,
} from '../types'
import { register as abertura } from './register.ts'
import { MAX_LINHAS, assinatura, escondida, extrairQs, montarLinhas } from './faixa-puro.mjs'
import { assinaturaRelogio, avaliarRelogio, linhaRelogio, notaJornada } from './relogio-puro.mjs'

const faixaDados = atom({ plugin: 'rainforest-mind', key: 'faixaDados' } as const, null as RainforestMindFaixaDados | null)
const faixaQ = atom({ plugin: 'rainforest-mind', key: 'faixaQ' } as const, [] as RainforestMindFaixaQ[])
const faixaOculta = atom({ plugin: 'rainforest-mind', key: 'faixaOculta' } as const, null as string | null)
const relogioJornada = atom({ plugin: 'rainforest-mind', key: 'relogioJornada' } as const, null as RainforestMindRelogioJornada | null)
const relogioSessoes = atom({ plugin: 'rainforest-mind', key: 'relogioSessoes' } as const, null as RainforestMindRelogioSessoes | null)
const relogioNotaPendente = atom({ plugin: 'rainforest-mind', key: 'relogioNotaPendente' } as const, null as string | null)
const relogioNotaEntregue = atom({ plugin: 'rainforest-mind', key: 'relogioNotaEntregue' } as const, null as string | null)

type Io = {
  rodar: (argv: string[], init: { env: Record<string, string>; timeoutMs: number }) => Promise<{ exitCode: number; stdout: string }>
  cwd: () => Promise<string>
  raiz: string
}

// Falha aberta: exit != 0, JSON invalido, timeout ou excecao devolvem null (apaga so os dados).
async function buscar(io: Io): Promise<RainforestMindFaixaDados | null> {
  try {
    const cwd = await io.cwd()
    const r = await io.rodar(
      ['node', `${io.raiz}/scripts/faixa-dados.cjs`, '--cwd', cwd],
      { env: { CLAUDE_PROJECT_DIR: cwd }, timeoutMs: 5000 },
    )
    return r.exitCode === 0 ? JSON.parse(r.stdout) : null
  } catch {
    return null
  }
}

type IoRodar = { rodar: Io['rodar'] }

// Falha aberta: exit != 0 (jornada.cjs exit 2 = sem linha), JSON invalido, timeout ou excecao
// devolvem null (apaga so a leitura).
async function rodarJson(io: IoRodar, argv: string[], timeoutMs: number, env: Record<string, string>): Promise<unknown> {
  try {
    const r = await io.rodar(argv, { env, timeoutMs })
    return r.exitCode === 0 ? JSON.parse(r.stdout) : null
  } catch {
    return null
  }
}

function jornadaDe(bruto: any): RainforestMindRelogioJornada | null {
  const ultimo_ms = bruto ? Date.parse(bruto.ultimo) : NaN
  if (!bruto || typeof bruto.efetiva_min !== 'number' || !Number.isFinite(ultimo_ms)) return null
  return { efetiva_min: bruto.efetiva_min, ultimo_ms }
}

function sessoesDe(bruto: any): RainforestMindRelogioSessoes | null {
  if (!bruto || typeof bruto.ociosidade_min !== 'number' || !Array.isArray(bruto.janelas)) return null
  return { ociosidade_min: bruto.ociosidade_min, janelas: bruto.janelas }
}

// Linha e assinatura do relogio para o desenho; qualquer falha apaga so o relogio.
function relogioDe(jornada: RainforestMindRelogioJornada | null, sessoes: RainforestMindRelogioSessoes | null, agora: number) {
  try {
    const r = avaliarRelogio({ jornada, sessoes, agora })
    return { linha: linhaRelogio(r) as string | null, sig: assinaturaRelogio(r) as string }
  } catch {
    return { linha: null as string | null, sig: '' }
  }
}

export const register: Register = (on, options) => {
  abertura(on, options)

  // Timers do relogio: ficam no escopo do register para o session.end e o proximo
  // session.start cancelarem os da sessao anterior.
  let timers: { cancel: () => void }[] = []
  // Id da sessao que armou os timers: so o session.end dela cancela o relogio.
  let armadoPor: string | null = null
  const cancelarRelogio = () => {
    armadoPor = null
    const velhos = timers
    timers = []
    for (const t of velhos) {
      try {
        t.cancel()
      } catch {
        // timer ja encerrado
      }
    }
  }

  on('session.start', async ($, e, next) => {
    try {
      const dados = await buscar({
        rodar: (argv, init) => $.process.run(argv, init),
        cwd: () => $.session.cwd(),
        raiz: $.plugin.root,
      })
      await update($, faixaDados, () => dados)
    } catch {
      // a faixa nunca quebra a abertura da sessao
    }
    // claude -p, SDK e subagente nao desenham a faixa: sem timer, e sem cancelar o relogio da
    // sessao interativa que compartilha esta instancia do mod.
    if (!e.isInteractive) return next(e)
    cancelarRelogio()
    try {
      const id = await $.session.id()
      armadoPor = id
      const cwd = await $.session.cwd()
      const raiz = $.plugin.root
      const io = { rodar: (argv: string[], init: { env: Record<string, string>; timeoutMs: number }) => $.process.run(argv, init) }
      let sessoesEmCurso = false
      let jornadaEmCurso = false

      // Arma a nota do dia quando a jornada acende e o dia ainda nao foi entregue.
      const reavaliar = async () => {
        try {
          const agora = await $.clock.now()
          const rel = avaliarRelogio({ jornada: await read($, relogioJornada), sessoes: await read($, relogioSessoes), agora })
          if (rel.jornada) {
            const dia = rel.jornada.dia
            const entregue = await read($, relogioNotaEntregue)
            const pendente = await read($, relogioNotaPendente)
            if (entregue !== dia && pendente !== dia) await update($, relogioNotaPendente, () => dia)
          }
        } catch {
          // o relogio nunca quebra nada
        }
        try {
          $.ui.invalidate('ui.render')
        } catch {
          // sem tela, sem redesenho
        }
      }

      const lerSessoes = async () => {
        if (sessoesEmCurso) return
        sessoesEmCurso = true
        try {
          const bruto = await rodarJson(io, ['node', `${raiz}/scripts/relogio-sessoes.cjs`, '--cwd', cwd, '--sessao', id], 5000, { CLAUDE_PROJECT_DIR: cwd })
          const dados = sessoesDe(bruto)
          await update($, relogioSessoes, () => dados)
          await reavaliar()
        } catch {
          // falha apaga so a linha do relogio
        } finally {
          sessoesEmCurso = false
        }
      }

      const lerJornada = async () => {
        if (jornadaEmCurso) return
        jornadaEmCurso = true
        try {
          const bruto = await rodarJson(io, ['node', `${raiz}/scripts/jornada.cjs`, '--json'], 60000, {})
          const dados = jornadaDe(bruto)
          await update($, relogioJornada, () => dados)
          await reavaliar()
        } catch {
          // falha apaga so a linha do relogio
        } finally {
          jornadaEmCurso = false
        }
      }

      timers.push($.clock.after(1000, lerSessoes))
      timers.push($.clock.after(2000, lerJornada))
      timers.push($.clock.every(60000, lerSessoes))
      timers.push($.clock.every(300000, lerJornada))
    } catch {
      // o relogio nunca quebra a abertura da sessao
    }
    return next(e)
  })

  // O matcher (qualquer motivo) evita colidir com o session.end sem matcher da abertura.
  on('session.end', { reason: /.*/ }, async (_$, e, next) => {
    if (armadoPor !== null && e.sessionId === armadoPor) {
      cancelarRelogio()
    }
    return next(e)
  })

  // Mensagem do usuario responde as Q do turno anterior: a linha sai na hora, e o
  // `turn.complete` seguinte traz de volta as que continuarem abertas. O evento e o
  // `prompt.submit` porque o gancho classico de envio (UserPromptSubmit) nao roda, em mod, no composer do REPL.
  on('prompt.submit', async ($, e, next) => {
    try {
      await update($, faixaQ, () => [])
    } catch {
      // a faixa nunca quebra o envio
    }
    // Nota da regra 8: uma vez por dia, so em prompt digitado no composer (nao em loop/schedule/system).
    // Vai em `context`: o modelo le, o usuario nao ve, e o texto do prompt segue intacto.
    let nota: string | null = null
    try {
      if (e.origin === undefined || e.origin.kind === 'composer') {
        const pendente = await read($, relogioNotaPendente)
        if (pendente) {
          const agora = await $.clock.now()
          const rel = avaliarRelogio({ jornada: await read($, relogioJornada), sessoes: await read($, relogioSessoes), agora })
          const dia = rel.jornada ? rel.jornada.dia : null
          const texto = notaJornada(rel) as string | null
          if (dia && texto && pendente === dia) {
            await update($, relogioNotaEntregue, () => dia)
            await update($, relogioNotaPendente, () => null)
            nota = texto
          }
        }
      }
    } catch {
      // a nota nunca quebra o envio
    }
    if (nota === null) return next(e)
    return next({ ...e, context: [...(e.context ?? []), nota] })
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    try {
      if (e.reason === 'answer') {
        const qs = extrairQs(e.answer ?? '')
        await update($, faixaQ, () => qs)
      }
      const dados = await buscar({
        rodar: (argv, init) => $.process.run(argv, init),
        cwd: () => $.session.cwd(),
        raiz: $.plugin.root,
      })
      await update($, faixaDados, () => dados)
    } catch {
      // a faixa nunca quebra o turno
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    try {
      if (e.props.hasSurvey) return next(e)
      const dados = await read($, faixaDados)
      const qs = await read($, faixaQ)
      const oculto = await read($, faixaOculta)
      let rel: { linha: string | null; sig: string } = { linha: null, sig: '' }
      try {
        rel = relogioDe(await read($, relogioJornada), await read($, relogioSessoes), await $.clock.now())
      } catch {
        // sem relogio, a faixa segue
      }
      const linhas = montarLinhas(dados, qs, e.props.bodyColumns, Math.min(MAX_LINHAS, e.props.maxRows - 1), rel.linha)
      if (linhas.length === 0 || escondida(oculto, assinatura(dados, qs, rel.sig))) return next(e)
      const { Box, Button, Text } = $.ui.resolve(e)
      return (
        <Box flexDirection="column">
          {linhas.map((linha: string, i: number) => (
            <Text key={`l${i}`} wrap="truncate-end">{linha}</Text>
          ))}
          <Button
            key="esconder"
            label="esconder"
            onPress={async () => {
              try {
                const d = await read($, faixaDados)
                const q = await read($, faixaQ)
                let sig = ''
                try {
                  sig = relogioDe(await read($, relogioJornada), await read($, relogioSessoes), await $.clock.now()).sig
                } catch {
                  // sem relogio na assinatura
                }
                await update($, faixaOculta, () => assinatura(d, q, sig))
                const dados = await buscar({
                  rodar: (argv, init) => $.process.run(argv, init),
                  cwd: () => $.session.cwd(),
                  raiz: $.plugin.root,
                })
                await update($, faixaDados, () => dados)
              } catch {
                // botao sem rejeicao solta
              }
            }}
          />
        </Box>
      )
    } catch {
      return next(e)
    }
  })
}
