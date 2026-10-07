'use strict';
// Onde moram mapa, design e plano num repo. Em repo de cliente que já usa
// `docs/legado/` (arqueologia) e `docs/plans/` (design/plano), o rainforest segue
// a pasta existente em vez de criar `docs/rainforest/{mapas,design,planos}`
// paralelos. Estado de máquina (estado, portoes, reguas, varredura, projeto)
// NÃO passa por aqui: fica sempre em `docs/rainforest/`.
const fs = require('fs');
const path = require('path');
const { resolverConfig } = require('./config.cjs');

const TIPOS = ['mapas', 'design', 'planos'];

function existe(raiz, rel) {
  try {
    return fs.existsSync(path.join(raiz, rel));
  } catch {
    return false;
  }
}

function temDocsPlans(raiz) {
  try {
    return fs.readdirSync(path.join(raiz, 'docs', 'plans'))
      .some((f) => f.endsWith('-design.md') || f.endsWith('.gates.json'));
  } catch {
    return false;
  }
}

// Pasta RELATIVA à raiz, com '/'.
function pastaDe(tipo, { raiz, config } = {}) {
  if (!TIPOS.includes(tipo)) throw new Error(`tipo inválido: ${tipo}`);
  raiz = raiz || process.env.RFM_ESTADO_ROOT || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const cfg = config || resolverConfig({ projeto: raiz });
  const pastas = cfg && cfg.valores && cfg.valores.pastas;
  if (pastas && typeof pastas[tipo] === 'string' && pastas[tipo]) {
    return pastas[tipo].replace(/\\/g, '/').replace(/\/+$/, '');
  }
  if (tipo === 'mapas' && existe(raiz, 'docs/legado/COBERTURA.md')) return 'docs/legado';
  if ((tipo === 'design' || tipo === 'planos') && temDocsPlans(raiz)) return 'docs/plans';
  return `docs/rainforest/${tipo}`;
}

// Caminho RELATIVO do doc. Mapas não leva slug: devolve a pasta.
function caminhoDoc(tipo, slug, { raiz, config } = {}) {
  const pasta = pastaDe(tipo, { raiz, config });
  if (tipo === 'mapas') return pasta;
  if (pasta === `docs/rainforest/${tipo}`) return `${pasta}/${slug}.md`;
  return `${pasta}/${slug}${tipo === 'design' ? '-design' : '-plano'}.md`;
}

module.exports = { pastaDe, caminhoDoc };
