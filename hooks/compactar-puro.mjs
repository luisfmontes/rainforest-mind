// Logica pura da compactacao automatica do mod. Sem Node e sem relogio: quem chama
// passa o estado e recebe o novo estado de volta.
// O mecanismo e adaptado do mod do wildz-data, de Rafael Lopes, com autorizacao dele (2026-10-09).

export const LIMIAR_PADRAO = 60;

// Decide a acao de um tick. `armado` e `avisado` sao o estado entre chamadas.
// acao: 'nada' | 'compactar' | 'avisar'
export function decidir({ percent, limiar, armado, agenteRodando, ligado, avisado }) {
  if (!ligado) return { acao: 'nada', armado, avisado };
  if (typeof percent !== 'number' || Number.isNaN(percent)) return { acao: 'nada', armado, avisado };
  if (percent < limiar) return { acao: 'nada', armado: true, avisado: false };
  if (!armado) return { acao: 'nada', armado, avisado };
  if (agenteRodando) {
    if (!avisado) return { acao: 'avisar', armado: true, avisado: true };
    return { acao: 'nada', armado: true, avisado: true };
  }
  return { acao: 'compactar', armado: false, avisado };
}

export function textoAviso(percent, agenteRodando) {
  const n = Math.round(percent);
  return agenteRodando
    ? `contexto em ${n}%: agente rodando, compacto quando ele voltar (ou faça a passagem)`
    : `compactado em ${n}%`;
}
