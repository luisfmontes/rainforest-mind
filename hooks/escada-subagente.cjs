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
const { extrairEscada, extrairCarveOuts, filtrarEscadaPorNivel } = require('./lib/escada.cjs');

function readSafe(p) {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return '';
  }
}

/**
 * Lê o nível de intensidade de config.json.
 * Best-effort: arquivo ausente, inválido ou chave ausente → retorna 'padrão'.
 */
function lerNivelIntensidade() {
  const raizDados = process.env.RFM_ESTADO_ROOT || process.env.RFM_ROOT;
  if (!raizDados) {
    return 'padrão'; // sem dados configurados, usa padrão
  }

  const configPath = path.join(raizDados, 'config.json');
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const nivel = cfg['escada-intensidade'];
    // Best-effort: valor inválido cai para padrão
    if (typeof nivel === 'string' && ['enxuto', 'padrão', 'completo'].includes(nivel)) {
      return nivel;
    }
    return 'padrão';
  } catch {
    return 'padrão'; // arquivo ausente ou inválido
  }
}

// Hook roda no contexto do plugin; caminhos relativos precisam de CLAUDE_PLUGIN_ROOT
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');
const SKILL_PATH = path.join(PLUGIN_ROOT, 'skills', 'modo-dev', 'SKILL.md');

const skillText = readSafe(SKILL_PATH);
const escada = extrairEscada(skillText);
const carveOuts = extrairCarveOuts(skillText);
const nivel = lerNivelIntensidade();

// Filtrar pela intensidade selecionada
const additionalContext = filtrarEscadaPorNivel(escada, carveOuts, nivel);

// Best-effort: se não conseguir extrair, emite JSON sem additionalContext
// e o modelo prossegue sem injeção (degradação graciosa).
const saida = {
  hookSpecificOutput: {
    hookEventName: 'SubagentStart',
    additionalContext: additionalContext || '(escada YAGNI não foi carregada)',
  },
};

console.log(JSON.stringify(saida));
process.exit(0);
