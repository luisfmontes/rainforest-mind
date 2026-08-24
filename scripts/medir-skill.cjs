#!/usr/bin/env node
/**
 * Mede o tamanho do núcleo injetado do skill rainforest-mind
 * Formato: nucleo=<bytes> regras=<n> references=<n> setas-duplas=<n> skill-bytes=<n> maior-reference=<arquivo>:<bytes>
 */

const fs = require('fs');
const path = require('path');

const SKILL_PATH = path.join(__dirname, '../skills/rainforest-mind/SKILL.md');
const REFERENCES_DIR = path.join(__dirname, '../skills/rainforest-mind/references');

// Ler o SKILL.md
const skillContent = fs.readFileSync(SKILL_PATH, 'utf-8');

// Extrair o núcleo (tudo até a seção ## Comando /foco)
const focolMarkIdx = skillContent.indexOf('## Comando /foco');
const nucleoContent = focolMarkIdx !== -1 ?
  skillContent.substring(0, focolMarkIdx) :
  skillContent;

const nucleoBytes = Buffer.byteLength(nucleoContent, 'utf-8');

// Contar regras (**<n>. no início de linha)
// O núcleo contém os headers das 17 regras
const rulesMatch = nucleoContent.match(/^\*\*\d+\.\s/gm);
const rulesCount = rulesMatch ? rulesMatch.length : 0;

// Contar referências
let referencesCount = 0;
const references = [];
if (fs.existsSync(REFERENCES_DIR)) {
  const files = fs.readdirSync(REFERENCES_DIR);
  for (const file of files) {
    if (file.endsWith('.md')) {
      referencesCount++;
      const filePath = path.join(REFERENCES_DIR, file);
      const size = fs.statSync(filePath).size;
      references.push({ file, size });
    }
  }
}

// Contar setas duplas (↳ ↳)
const doubleArrowsMatch = nucleoContent.match(/↳\s↳/g);
const doubleArrowsCount = doubleArrowsMatch ? doubleArrowsMatch.length : 0;

// Tamanho total do SKILL.md
const skillBytes = Buffer.byteLength(skillContent, 'utf-8');

// Encontrar o maior reference
let maiorReference = '';
let maiorTamanho = 0;
for (const ref of references) {
  if (ref.size > maiorTamanho) {
    maiorTamanho = ref.size;
    maiorReference = ref.file;
  }
}

const output = `nucleo=${nucleoBytes} regras=${rulesCount} references=${referencesCount} setas-duplas=${doubleArrowsCount} skill-bytes=${skillBytes} maior-reference=${maiorReference}:${maiorTamanho}`;
console.log(output);
