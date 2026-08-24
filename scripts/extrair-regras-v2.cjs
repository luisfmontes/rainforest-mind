#!/usr/bin/env node
/**
 * Extrai elaborações de regras do SKILL.md e cria arquivos individuais
 * Preserva bytes exatamente como estão
 */

const fs = require('fs');
const path = require('path');

const SKILL_PATH = path.join(__dirname, '../skills/rainforest-mind/SKILL.md');
const REFERENCES_DIR = path.join(__dirname, '../skills/rainforest-mind/references');

// Garantir que o diretório references existe
if (!fs.existsSync(REFERENCES_DIR)) {
  fs.mkdirSync(REFERENCES_DIR, { recursive: true });
}

const content = fs.readFileSync(SKILL_PATH, 'utf-8');

// Encontrar todas as regras e seus posicionamentos
const rules = [];
const rulePattern = /^\*\*(\d+)\.\s/gm;
let match;

while ((match = rulePattern.exec(content)) !== null) {
  const ruleNum = parseInt(match[1], 10);
  const startPos = match.index;

  // Encontrar a próxima regra ou seção
  let endPos = content.length;
  const nextRuleMatch = rulePattern.exec(content);
  if (nextRuleMatch) {
    endPos = nextRuleMatch.index;
    // Retroceder para achar a próxima regra
    rulePattern.lastIndex = match.index + 1;
  }

  rules.push({
    num: ruleNum,
    startPos,
    content: content.substring(startPos, endPos)
  });
}

// Reparar o lastIndex para buscar de novo
rulePattern.lastIndex = 0;
while ((match = rulePattern.exec(content)) !== null) {
  const ruleNum = parseInt(match[1], 10);
  const startPos = match.index;

  // Encontrar a próxima regra ou fim da seção de regras
  let endPos = content.length;

  // Procurar a próxima regra depois desta
  const rest = content.substring(startPos + 20); // Skip ahead
  const nextMatch = /^\*\*\d+\./m.exec(rest);
  if (nextMatch) {
    endPos = startPos + 20 + nextMatch.index;
  }

  // Atualizar a regra correspondente
  for (let rule of rules) {
    if (rule.startPos === startPos) {
      rule.endPos = endPos;
      rule.content = content.substring(startPos, endPos);
      break;
    }
  }
}

console.log(`Encontradas ${rules.length} regras`);

// Processar cada regra
let modifiedContent = content;
const offsets = [];

for (const rule of rules) {
  const ruleContent = rule.content;
  const detalheIdx = ruleContent.indexOf('<!-- detalhe -->');

  let elaboracao = '';
  let nucleoEndIdx = ruleContent.length;

  if (detalheIdx !== -1) {
    nucleoEndIdx = detalheIdx + '<!-- detalhe -->'.length;

    // Extrair tudo depois de <!-- detalhe --> até a próxima regra ou fim
    let afterDetalhe = ruleContent.substring(nucleoEndIdx);

    // Se termina com quebra de linha após <!-- detalhe -->, remover
    if (afterDetalhe.startsWith('\n')) {
      afterDetalhe = afterDetalhe.substring(1);
    }

    // Se termina com quebra(s) de linha antes da próxima regra, manter tudo
    elaboracao = afterDetalhe.trimRight();
  }

  const ruleNumPadded = String(rule.num).padStart(2, '0');

  if (elaboracao.length > 0 || rule.num === 4) {
    // Extrair título da regra
    const titleMatch = ruleContent.match(/^\*\*\d+\.\s(.*?)(?:\*\*|$)/m);
    const titleText = titleMatch ? titleMatch[1] : '';

    // Criar o arquivo
    const ruleFilePath = path.join(REFERENCES_DIR, `regra-${ruleNumPadded}.md`);

    let fileContent = '';
    if (rule.num === 4) {
      // Regra 4 é auto-suficiente
      fileContent = `# Regra ${rule.num}\n\nEsta regra é auto-suficiente e não possui elaboração adicional.\n`;
    } else {
      // Outras regras
      fileContent = `# Regra ${rule.num} — ${titleText.trim()}\n\n${elaboracao}\n`;
    }

    fs.writeFileSync(ruleFilePath, fileContent, 'utf-8');
    console.log(`  Regra ${rule.num}: ${fileContent.length} bytes`);

    // Substituir no conteúdo
    const newRuleContent = ruleContent.substring(0, nucleoEndIdx) +
                           `\nElaboração: references/regra-${ruleNumPadded}.md\n`;

    modifiedContent = modifiedContent.replace(
      ruleContent,
      newRuleContent
    );
  }
}

// Escrever o novo SKILL.md
fs.writeFileSync(SKILL_PATH, modifiedContent, 'utf-8');

console.log('\nArquivos criados!');
