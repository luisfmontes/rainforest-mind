#!/usr/bin/env node
/**
 * Mede o tamanho do núcleo injetado do skill rainforest-mind
 * Formato: nucleo=<bytes> regras=<n> references=<n> setas-duplas=<n> skill-bytes=<n> maior-reference=<arquivo>:<bytes>
 *
 * Usa o parser real de contexto-sessao.cjs para extrair o núcleo — a mesma função
 * que o hook usa para injetar.
 */

const fs = require('fs');
const path = require('path');

const SKILL_PATH = path.join(__dirname, '../skills/rainforest-mind/SKILL.md');
const REFERENCES_DIR = path.join(__dirname, '../skills/rainforest-mind/references');
const CONTEXTO_LIB = path.join(__dirname, '../hooks/lib/contexto-sessao.cjs');

// Importar as funções do motor real
let filtrarRegras, extrairNucleo;
try {
  const lib = require(CONTEXTO_LIB);
  filtrarRegras = lib.filtrarRegras;
  extrairNucleo = lib.extrairNucleo;
} catch (e) {
  console.error(`Erro ao carregar contexto-sessao.cjs: ${e.message}`);
  process.exit(1);
}

// Ler o SKILL.md
const skillContent = fs.readFileSync(SKILL_PATH, 'utf-8');

// Aplicar o parser real
const regrasTexto = filtrarRegras(skillContent);
const nucleoContent = extrairNucleo(regrasTexto);
const nucleoBytes = Buffer.byteLength(nucleoContent, 'utf-8');

// Contar regras (**<n>. no início de linha) — fazer no núcleo processado
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

// Contar setas duplas (↳ ↳) no núcleo
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

// Flag --conferir-description: valida que o numero de tokens no description bate com a realidade
const args = process.argv.slice(2);
if (args.includes('--conferir-description')) {
  const BYTES_PER_TOKEN = 3.480; // taxa do repositorio: 58.540 B = 16.8k tokens

  // Extrair o numero de tokens citado no description
  // Formato esperado: "~2,7k tokens" ou "~16,8k tokens"
  const descriptionMatch = skillContent.match(/description:\s*(.+?)(?:\n|$)/);
  if (!descriptionMatch) {
    console.error('Erro: nao achei o description no frontmatter');
    process.exit(1);
  }

  const description = descriptionMatch[1];
  const citedMatch = description.match(/~([\d,]+)k\s+tokens/);
  if (!citedMatch) {
    console.error('Erro: nao achei o custo em tokens no description (formato esperado: ~X,Xk tokens)');
    process.exit(1);
  }

  const citedTokensStr = citedMatch[1].replace(',', '.');
  const citedTokens = parseFloat(citedTokensStr) * 1000;
  const actualTokens = skillBytes / BYTES_PER_TOKEN;
  const percentDiff = Math.abs(citedTokens - actualTokens) / actualTokens * 100;

  if (percentDiff < 10) {
    console.log('ok');
    process.exit(0);
  } else {
    console.log(`divergencia: ${citedTokensStr}k tokens citados, ${(actualTokens/1000).toFixed(1)}k tokens reais (${percentDiff.toFixed(1)}% de diferenca)`);
    process.exit(1);
  }
}
