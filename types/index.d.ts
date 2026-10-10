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

// Mapa da sessao (D13): o que foi escrito (por Edit, Write ou NotebookEdit), que skill rodou, que
// servico MCP respondeu e que subagente entrou. `desvio` = fora dos `arquivos:` do plano do fluxo.
export type RainforestMindPainelMapa = {
  arquivos: { caminho: string; desvio: boolean }[]
  skills: string[]
  servicos: string[]
  subagentes: string[]
}

// "Deixado para depois" (D7): itens (aberto, enviado pelo Faz agora ou resolvido pelo
// checker), se o checker esta rodando e ligado, o ultimo pedido
// da pessoa (ate 4000 caracteres) e as ferramentas do turno da sessao principal (nome e falha).
export type RainforestMindPainelDeixadoOrigem = 'Claude disse' | 'em arquivo' | 'segundo modelo'

export type RainforestMindPainelDeixado = {
  itens: { id: number; texto: string; origem: RainforestMindPainelDeixadoOrigem; estado: 'aberto' | 'enviado' | 'resolvido' }[]
  proximo: number
  checando: boolean
  checar: boolean
  pedido: string
  ferramentas: { tool: string; deny: boolean; isError: boolean }[]
}

// Painel de PR (/pr): o que se acompanha, a ultima leitura resumida (forma de `resumir` em
// hooks/pr-puro.mjs mais a hora da ultima atualizacao no GitHub), a linha do tempo e a virada
// que espera a quietude de 3 min para acordar a sessao. `origem` decide quem pode acordar (D6).
export type RainforestMindPrOrigem = 'sessao' | 'manual' | 'retomada'

export type RainforestMindPrAcompanhado = { alvo: string; origem: RainforestMindPrOrigem; branch: string }

export type RainforestMindPrResumo = {
  numero: number
  titulo: string
  url: string
  estado: string
  branch: string
  base: string
  autor: string
  head: string
  checks: string
  mergavel: boolean
  motivo: string
  review: string
  threadsAbertas: number
  threadsTotal: number
  comentarios: number
  atualizadoEm: string
}

export type RainforestMindPrEvento = { hora: string; icone: string; texto: string }

export type RainforestMindPrPendente = { virada: string; nota: string; ultimaMudancaMs: number }

// Caminhos absolutos de `gh` (fora do repositorio da sessao) e o login de quem esta logado nele,
// resolvidos uma vez por sessao. Vazio = ainda nao resolvido.
export type RainforestMindPrFerramentas = { gh: string; eu: string }

declare module 'claude-code' {
  interface PluginState {
    'rainforest-mind': {
      faixaDados: RainforestMindFaixaDados | null
      painelStats: RainforestMindPainelStats
      painelOculto: boolean
      painelMapa: RainforestMindPainelMapa
      painelDeixado: RainforestMindPainelDeixado
      relogioJornada: RainforestMindRelogioJornada | null
      relogioSessoes: RainforestMindRelogioSessoes | null
      relogioNotaPendente: string | null
      relogioNotaEntregue: string | null
      prAcompanhado: RainforestMindPrAcompanhado | null
      prResumo: RainforestMindPrResumo | null
      prEventos: RainforestMindPrEvento[]
      prErro: string
      prPendente: RainforestMindPrPendente | null
      prFerramentas: RainforestMindPrFerramentas
      pluginsEmDiaClaude: string
      nodeCaminho: string
    }
  }
}
