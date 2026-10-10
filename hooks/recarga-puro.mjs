// Marcador de recarga: como a janela que atualizou o plugin avisa as outras para rodar
// /reload-plugins. Enxerto de `plugin/scripts/reload_marker.mjs` do wildz-data, de Rafael
// Lopes (autorizacao dele, 2026-10-09), reduzido ao marcador compartilhado: aqui a
// atualizacao roda dentro do mod (hooks/plugins-em-dia.ts), e a janela que atualizou ja
// recarrega ou avisa a si mesma. ES module sem Node: caminhos juntados a mao.
//
// Conteudo: { "v": 1, "at": <ms> }. Quem le age uma vez por `at`, so se ele for mais novo
// que o carregamento do proprio modulo (o /reload-plugins recarrega o modulo e o
// "carregado em" passa do marcador).

const PASTA_DE_DADOS = 'rainforest-mind-rainforest-mind';

/** <CLAUDE_CONFIG_DIR ou HOME/.claude>/plugins/data/rainforest-mind-rainforest-mind/recarga-pedida.json */
export function caminhoMarcador({ CLAUDE_CONFIG_DIR, HOME } = {}) {
  const config = CLAUDE_CONFIG_DIR || `${HOME}/.claude`;
  return `${config}/plugins/data/${PASTA_DE_DADOS}/recarga-pedida.json`;
}

/** O texto do marcador de uma atualizacao. */
export function textoMarcador(at) {
  return JSON.stringify({ v: 1, at });
}

/** `{ at }`, ou null para texto ausente, quebrado ou de outro formato. */
export function lerMarcador(texto) {
  if (typeof texto !== 'string') return null;
  let m;
  try {
    m = JSON.parse(texto);
  } catch {
    return null;
  }
  if (m === null || typeof m !== 'object' || m.v !== 1) return null;
  if (typeof m.at !== 'number' || !Number.isFinite(m.at)) return null;
  return { at: m.at };
}

/**
 * O `at` pelo qual esta janela deve recarregar, ou null: so marcador mais novo que o
 * carregamento deste modulo e que o ultimo ja tratado.
 */
export function deveRecarregar({ marcador, carregadoEm, tratadoEm }) {
  const m = lerMarcador(marcador);
  if (m === null || !(m.at > carregadoEm)) return null;
  if (typeof tratadoEm === 'number' && m.at <= tratadoEm) return null;
  return m.at;
}
