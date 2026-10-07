// Contrato de estado do mod (`$.state`, plugin `rainforest-mind`). O engine confere cada
// chave que o modulo nomeia contra este arquivo. Forma dos dados: scripts/faixa-dados.cjs
// (faixaDados) e hooks/mod.tsx (painelStats).
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
  fluxos: RainforestMindFaixaFluxo[]
}

export type RainforestMindRelogioJornada = { efetiva_min: number; ultimo_ms: number }

export type RainforestMindRelogioSessoes = {
  ociosidade_min: number
  janelas: { cwd: string; desde: number }[]
}

// Uma fatia do contexto, como o `session.usage` a devolve (so as categorias `used`).
export type RainforestMindPainelFatia = { nome: string; tokens: number; tipo: string }

// Um subagente visto pelo mod. `fimEm` nulo = ainda em andamento (ou sem fim visto).
export type RainforestMindPainelAgente = {
  id: string
  rotulo: string
  tipo: string
  modelo: string | null
  iniciadoEm: number
  fimEm: number | null
  vistoEm: number
  criadoAqui: boolean
  ferramentas: number
  tokensLidos: number
  tokensSaida: number
  falhou: boolean
}

// Contadores da sessao que a barra e o pane leem. Tempos em ms de `$.clock.now()`.
export type RainforestMindPainelStats = {
  turnos: number
  ferramentas: number
  falhas: number
  tokensNovos: number
  tokensCacheLido: number
  tokensCacheEscrito: number
  tokensSaida: number
  custoUsd: number | null
  ctxPct: number | null
  ctxTokens: number | null
  ctxJanela: number | null
  fatias: RainforestMindPainelFatia[]
  carimbos: number[]
  agentes: RainforestMindPainelAgente[]
  ultimaRequisicaoMs: number
  modelo: string | null
  ttlMs: number
  medirDeNovo: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'rainforest-mind': {
      faixaDados: RainforestMindFaixaDados | null
      painelStats: RainforestMindPainelStats
      painelOculto: boolean
      relogioJornada: RainforestMindRelogioJornada | null
      relogioSessoes: RainforestMindRelogioSessoes | null
      relogioNotaPendente: string | null
      relogioNotaEntregue: string | null
    }
  }
}
