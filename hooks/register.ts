// Canario temporario do fluxo 2026-10-02-mod-regras-inteiras (sera substituido na tarefa 6).
// Inerte sem a variavel RFM_CANARIO_MOD: mede ate onde um mod de plugin do marketplace
// consegue empurrar texto para o system prompt, e se o mod chega a carregar.
import type { Register } from 'claude-code'

const MARCAS: ReadonlyArray<readonly [number, string]> = [
  [1024, 'RF-TETO-CANARIO-1024'],
  [3072, 'RF-TETO-CANARIO-3072'],
  [16384, 'RF-TETO-CANARIO-16384'],
  [32000, 'RF-TETO-CANARIO-32000'],
  [40000, 'RF-TETO-CANARIO-40000'],
  [48000, 'RF-TETO-CANARIO-48000'],
]
const TOTAL = 49500
const ENCHIMENTO = 'Enchimento neutro de medicao, sem significado nem instrucao.\n'

function corpo(): string {
  let out = ''
  for (const [pos, marca] of MARCAS) {
    while (out.length < pos) out += ENCHIMENTO
    out += marca + '\n'
  }
  while (out.length < TOTAL) out += ENCHIMENTO
  return out
}

export const register: Register = on => {
  on('prompt.compose', async ($, e, next) => {
    const ativo = await $.env.get('RFM_CANARIO_MOD')
    if (!ativo) return next(e)
    const r = await next(e)
    const diag =
      `RF-TETO-TRAITS-${e.traits.join('+')}\n` +
      `RF-TETO-TOOLS-${e.tools.length}\n` +
      `RF-TETO-IDS-${r.sections.map(s => s.id).join('+')}\n`
    return {
      sections: [
        ...r.sections,
        { id: 'rainforest-mind:canario', text: corpo() + diag, scope: 'session' as const },
      ],
    }
  })
}
