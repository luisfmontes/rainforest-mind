#!/usr/bin/env node
// SessionStart hook: injeta as regras rainforest-mind + foco declarado em toda sessão.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

function readSafe(p) {
  try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; }
}

const foco = readSafe(path.join(ROOT, 'FOCO.md'));
const skill = readSafe(path.join(ROOT, 'skills', 'rainforest-mind', 'SKILL.md'));

// Aviso de revisão bimestral a partir da linha "Última revisão: YYYY-MM-DD"
let revisao = '';
const m = skill.match(/Última revisão:\s*(\d{4}-\d{2}-\d{2})/);
if (m) {
  const dias = Math.floor((Date.now() - new Date(m[1]).getTime()) / 86400000);
  if (dias > 60) {
    revisao = `\n⚠ A skill rainforest-mind não é revisada há ${dias} dias (limite: 60). Avise o Luís que está na hora de revisá-la.`;
  }
}

const regras = skill.split('## As regras')[1]?.split('## Comando')[0]?.trim() || '';

console.log(`RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do Luís (perfil 2e).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
${foco || '(nenhum foco declarado — sugira /foco <texto> se o Luís disser no que precisa entregar)'}
${revisao}
Arquivos de apoio: ${ROOT}\\FOCO.md e ${ROOT}\\IDEIAS.md`);
