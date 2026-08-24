#!/usr/bin/env node
/**
 * Extrai elaborações de regras do SKILL.md para arquivos individuais
 * Preserva toda a estrutura: ## As regras fica, ## Comando /foco fica
 */

const fs = require('fs');
const path = require('path');

const SKILL_PATH = path.join(__dirname, '../skills/rainforest-mind/SKILL.md');
const REFERENCES_DIR = path.join(__dirname, '../skills/rainforest-mind/references');

// Criar diretório references
if (!fs.existsSync(REFERENCES_DIR)) {
  fs.mkdirSync(REFERENCES_DIR, { recursive: true });
}

// Ler o arquivo
const content = fs.readFileSync(SKILL_PATH, 'utf-8');

// Encontrar a posição de cada regra e suas elaborações
const rulePositions = [];
const ruleRegex = /\*\*(\d+)\.\s([^\n]*)/g;
let match;

while ((match = ruleRegex.exec(content)) !== null) {
  const ruleNum = parseInt(match[1], 10);
  const ruleTitle = match[2].trim();
  const ruleStart = match.index;

  // Encontrar o <!-- detalhe --> após esta regra
  const detalheStart = content.indexOf('<!-- detalhe -->', ruleStart);

  if (detalheStart === -1 && ruleNum !== 4) {
    console.log(`  Regra ${ruleNum}: sem <!-- detalhe -->`);
    continue;
  }

  let elaboracaoStart = detalheStart !== -1 ? detalheStart + '<!-- detalhe -->'.length : -1;
  let elaboracaoEnd = -1;

  if (elaboracaoStart !== -1) {
    // Encontrar a próxima regra
    const nextRuleMatch = /\n\*\*\d+\./g.exec(content.substring(elaboracaoStart));
    if (nextRuleMatch) {
      elaboracaoEnd = elaboracaoStart + nextRuleMatch.index;
    } else {
      // Se não há próxima regra, procurar ## Comando /foco
      const focolIdx = content.indexOf('\n## Comando /foco', elaboracaoStart);
      elaboracaoEnd = focolIdx !== -1 ? focolIdx : content.length;
    }
  }

  rulePositions.push({
    num: ruleNum,
    title: ruleTitle,
    ruleStart,
    detalheStart,
    elaboracaoStart,
    elaboracaoEnd
  });
}

console.log(`Encontradas ${rulePositions.length} regras`);

// Processar cada regra
const replacements = [];

for (const rule of rulePositions) {
  const ruleNumPadded = String(rule.num).padStart(2, '0');

  if (rule.num === 4) {
    // Regra 4: auto-suficiente
    const fileContent = `# Regra 4\n\nEsta regra é auto-suficiente e não possui elaboração adicional.\n`;
    const filePath = path.join(REFERENCES_DIR, `regra-${ruleNumPadded}.md`);
    fs.writeFileSync(filePath, fileContent, 'utf-8');
    console.log(`  Regra 4: ${fileContent.length} bytes (auto-suficiente)`);
  } else if (rule.elaboracaoStart !== -1 && rule.elaboracaoEnd !== -1) {
    // Outras regras
    let elaboracao = content.substring(rule.elaboracaoStart, rule.elaboracaoEnd);

    // Remover a primeira quebra de linha após <!-- detalhe -->
    if (elaboracao.startsWith('\n')) {
      elaboracao = elaboracao.substring(1);
    } else if (elaboracao.startsWith('\r\n')) {
      elaboracao = elaboracao.substring(2);
    }

    // Remover espaços em branco finais, mas manter 1 quebra de linha no fim
    elaboracao = elaboracao.trimRight();

    const fileContent = `# Regra ${rule.num} — ${rule.title}\n\n${elaboracao}\n`;
    const filePath = path.join(REFERENCES_DIR, `regra-${ruleNumPadded}.md`);
    fs.writeFileSync(filePath, fileContent, 'utf-8');
    console.log(`  Regra ${rule.num}: ${fileContent.length} bytes`);

    // Preparar substituição
    const oldText = content.substring(rule.detalheStart, rule.elaboracaoEnd);
    const newText = `<!-- detalhe -->\nElaboração: references/regra-${ruleNumPadded}.md\n`;

    replacements.push({ old: oldText, new: newText });
  }
}

// Aplicar substituições
let newContent = content;
for (const repl of replacements) {
  newContent = newContent.replace(repl.old, repl.new);
}

// Escrever
fs.writeFileSync(SKILL_PATH, newContent, 'utf-8');

console.log('\nSKILL.md atualizado com ponteiros.');
