// Caminho do transcrito de um subagente, a partir do payload do `SubagentStop`.
//
// Por que existe: `hooks/veredito-revisor.cjs` (revisor) e `hooks/relato-executor.cjs`
// (executor de fluxo) leem o mesmo transcrito do mesmo evento. Ter a resolução do
// caminho em dois lugares é a segunda cópia que diverge calada — por isso mora aqui.

const path = require('path');

/**
 * Caminho do transcrito do SUBAGENTE. `agent_transcript_path` quando o
 * payload trouxer; senão o fallback que bateu byte a byte na captura da
 * task 1: `<dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl`.
 */
function caminhoTranscritoSubagente(payload) {
  if (typeof payload.agent_transcript_path === 'string' && payload.agent_transcript_path) {
    return payload.agent_transcript_path;
  }
  if (
    typeof payload.transcript_path === 'string' && payload.transcript_path
    && typeof payload.session_id === 'string' && payload.session_id
    && typeof payload.agent_id === 'string' && payload.agent_id
  ) {
    return path.join(
      path.dirname(payload.transcript_path),
      payload.session_id,
      'subagents',
      `agent-${payload.agent_id}.jsonl`,
    );
  }
  return null;
}

module.exports = { caminhoTranscritoSubagente };
