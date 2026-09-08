#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Permite override por RFM_ROOT para testes
const ROOT = process.env.RFM_ROOT || path.resolve(__dirname, '..');

// Encontra todos os arquivos, pulando .git, node_modules, .claude/worktrees
function* findFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (['.git', 'node_modules', '.claude'].includes(entry.name)) continue;

    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      // Pula .claude/worktrees mesmo se não estiver no root
      if (entry.name === 'worktrees' && path.dirname(fullPath).endsWith('.claude')) continue;
      yield* findFiles(fullPath);
    } else {
      yield fullPath;
    }
  }
}

// Processa um arquivo e extrai os marcadores
function extractAtalhos(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    const matches = [];

    lines.forEach((line, idx) => {
      // Regex que aceita tanto 'atalho:' quanto 'ponytail:'
      const match = line.match(/(?:\/\/|#)\s*(?:atalho|ponytail):\s*(.+?)(?:\.\s*volta quando:\s*(.+))?$/i);
      if (match) {
        const lineNum = idx + 1;
        const teto = match[1].trim();
        const volta = match[2] ? match[2].trim() : null;
        matches.push({ lineNum, teto, volta });
      }
    });

    return matches;
  } catch (err) {
    return [];
  }
}

// Coleta todos os marcadores
const atalhos = [];
for (const file of findFiles(ROOT)) {
  const matches = extractAtalhos(file);
  for (const m of matches) {
    const relPath = path.relative(ROOT, file);
    atalhos.push({
      file: relPath,
      line: m.lineNum,
      teto: m.teto,
      volta: m.volta,
    });
  }
}

// Ordena por arquivo e linha
atalhos.sort((a, b) => {
  if (a.file !== b.file) return a.file.localeCompare(b.file);
  return a.line - b.line;
});

// Emite as linhas
let semGatilho = 0;
for (const a of atalhos) {
  const voltaQuando = a.volta ? a.volta : 'sem-gatilho';
  if (!a.volta) semGatilho++;

  console.log(`${a.file}:${a.line}, ${a.teto}. teto: ${a.teto}. volta quando: ${voltaQuando}.`);
}

// Fecha com contagem
const total = atalhos.length;
if (total === 0) {
  console.log('Nenhum atalho registrado. Ledger limpo.');
} else {
  console.log(`${total} marcadores, ${semGatilho} sem gatilho.`);
}

process.exit(0);
