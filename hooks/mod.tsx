// Entrada do mod: a abertura (register.ts, sem mudanca) mais a faixa acima do prompt
// (foco, fluxos em curso e Q abertas). A logica pura mora em ./faixa-puro.mjs; aqui so se
// liga os eventos. O engine recusa `$` passado como argumento a qualquer funcao do arquivo
// (closure inclusive), entao `buscar` recebe so `{ rodar, cwd, raiz }`, montado no ponto de
// chamada de cada hook.
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'
import type { RainforestMindFaixaDados, RainforestMindFaixaQ } from '../types'
import { register as abertura } from './register.ts'
import { MAX_LINHAS, assinatura, escondida, extrairQs, montarLinhas } from './faixa-puro.mjs'

const faixaDados = atom({ plugin: 'rainforest-mind', key: 'faixaDados' } as const, null as RainforestMindFaixaDados | null)
const faixaQ = atom({ plugin: 'rainforest-mind', key: 'faixaQ' } as const, [] as RainforestMindFaixaQ[])
const faixaOculta = atom({ plugin: 'rainforest-mind', key: 'faixaOculta' } as const, null as string | null)

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

export const register: Register = (on, options) => {
  abertura(on, options)

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
    return next(e)
  })

  // Mensagem do usuario responde as Q do turno anterior: a linha sai na hora, e o
  // `turn.complete` seguinte traz de volta as que continuarem abertas.
  on('classic.UserPromptSubmit', async ($, e, next) => {
    try {
      await update($, faixaQ, () => [])
    } catch {
      // a faixa nunca quebra o envio
    }
    return next(e)
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
      const linhas = montarLinhas(dados, qs, e.props.bodyColumns, Math.min(MAX_LINHAS, e.props.maxRows - 1))
      if (linhas.length === 0 || escondida(oculto, assinatura(dados, qs))) return next(e)
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
                await update($, faixaOculta, () => assinatura(d, q))
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
