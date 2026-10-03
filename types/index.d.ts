// Contrato de estado do mod (`$.state`, plugin `rainforest-mind`). O engine confere cada
// chave que o modulo nomeia contra este arquivo. Forma dos dados: scripts/faixa-dados.cjs.
export type RainforestMindFaixaFluxo = {
  slug: string
  titulo?: string
  etapa: string
  tarefas_ok: number | null
  tarefas: number | null
  em_voo: string[]
  criado_em?: string
  worktree?: string
}

export type RainforestMindFaixaDados = {
  foco: string | null
  fluxos: RainforestMindFaixaFluxo[]
}

export type RainforestMindFaixaQ = { n: number; titulo: string }

declare module 'claude-code' {
  interface PluginState {
    'rainforest-mind': {
      faixaDados: RainforestMindFaixaDados | null
      faixaQ: RainforestMindFaixaQ[]
      faixaOculta: string | null
    }
  }
}
