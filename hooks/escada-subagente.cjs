#!/usr/bin/env node
/**
 * Hook de SubagentStart: injeta a escada YAGNI em todos os subagentes.
 *
 * SubagentStart é parent-thread only (como SessionStart), mas exige JSON
 * com estrutura específica — texto cru no stdout é descartado em silêncio.
 * Veja: ponytail-runtime.js (dietrichgebert/ponytail) e o comentário longo
 * em hooks/foco-session-start.cjs sobre a diferença entre exit 0 (injeção
 * silenciada) e JSON entregue (injeção feita).
 *
 * Best-effort: falha de leitura, JSON inválido, arquivo ausente → o hook
 * sai 0 e injeta o que conseguir. Um hook de SubagentStart que estoura
 * trava spawn de subagente.
 */

const fs = require('fs');
const path = require('path');
const { extrairEscada } = require('./lib/escada.cjs');

function readSafe(p) {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return '';
  }
}

// Hook roda no contexto do plugin; caminhos relativos precisam de CLAUDE_PLUGIN_ROOT
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');
const SKILL_PATH = path.join(PLUGIN_ROOT, 'skills', 'modo-dev', 'SKILL.md');

const skillText = readSafe(SKILL_PATH);
const escada = extrairEscada(skillText);

// Best-effort: se não conseguir extrair, emite JSON sem additionalContext
// e o modelo prossegue sem injeção (degradação graciosa).
const saida = {
  hookSpecificOutput: {
    hookEventName: 'SubagentStart',
    additionalContext: escada || '(escada YAGNI não foi carregada)',
  },
};

console.log(JSON.stringify(saida));
process.exit(0);
