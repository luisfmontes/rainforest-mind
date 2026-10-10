// Compactacao automatica (opcoes `compactarSozinho` e `compactarEm`): quando o contexto sobe
// ao limiar, compacta a conversa uma vez por subida. Com subagente em andamento so avisa, e
// compacta no primeiro measure depois que ele termina. A decisao e pura e mora em
// ./compactar-puro.mjs; aqui so se liga o evento. O engine so aceita `$` passado a funcao
// declarada no topo deste arquivo; aos `.mjs` vao so valores.
// O mecanismo e adaptado do mod do wildz-data, de Rafael Lopes, com autorizacao dele (2026-10-09).
// Falha aberta: o hook devolve SEMPRE `next(e)`, e qualquer erro daqui so deixa de compactar.
import { atom, read } from 'claude-code'
import type { Register } from 'claude-code'
import type { RainforestMindPainelStats } from '../types'
import { LIMIAR_PADRAO, decidir, textoAviso } from './compactar-puro.mjs'

// As estatisticas do painel sao do hooks/mod.tsx (mesmo ref): aqui so se le. O criterio de
// "subagente em andamento" e o da barra e vem de la.
const painelStats = atom({ plugin: 'rainforest-mind', key: 'painelStats' } as const, null as RainforestMindPainelStats | null)

type Painel = {
  agenteRodando: (stats: RainforestMindPainelStats | null, agora: number) => boolean
}

// Estado entre measures. Zerado quando o modulo recarrega, como o estado do mod.
let armado = true
let avisado = false
let adiadoAvisado = false

export const register = (on: Parameters<Register>[0], options: Parameters<Register>[1], painel: Painel): void => {
  on('session.measure', async ($, e, next) => {
    try {
      if (options.compactarSozinho === false) return next(e)
      if (!e.changed.includes('context')) return next(e)
      const percent = e.context.percent
      const limiar = Number(options.compactarEm) || LIMIAR_PADRAO
      const aviso = (texto: string) => void Promise.resolve($.ui.toast(texto)).catch(() => {})
      const agenteRodando = painel.agenteRodando(await read($, painelStats), await $.clock.now())
      const d = decidir({ percent, limiar, armado, agenteRodando, ligado: true, avisado }) as {
        acao: 'nada' | 'compactar' | 'avisar'
        armado: boolean
        avisado: boolean
      }
      armado = d.armado
      avisado = d.avisado
      if (typeof percent === 'number' && percent < limiar) adiadoAvisado = false
      if (d.acao === 'avisar') aviso(textoAviso(percent, true))
      if (d.acao === 'compactar') {
        // Sem await: a compactacao e demorada e o proprio engine mede o contexto dentro dela.
        $.session
          .compact()
          .then(r => {
            if (r.skip) aviso('compactação ignorada')
            else aviso(textoAviso(percent, false))
          })
          .catch(() => {
            // Rejeita enquanto um turno roda: rearma para o proximo measure e avisa uma vez.
            armado = true
            if (!adiadoAvisado) aviso('compactação adiada (turno em curso)')
            adiadoAvisado = true
          })
      }
    } catch {
      // a compactacao automatica nunca atrapalha a medicao
    }
    return next(e)
  })
}
