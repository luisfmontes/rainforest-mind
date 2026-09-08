#!/usr/bin/env node
/**
 * conferir-invariantes.cjs — valida que frases críticas não foram perdidas na extração.
 *
 * O SKILL.md é cortado na marca `<!-- detalhe -->` antes de injetar. Se uma frase
 * crítica estiver depois dessa marca, ela é perdida em silêncio. Este script checa:
 *
 * Para cada invariante:
 *   1. A frase existe no SKILL.md (núcleo antes do corte)? → emSkill
 *   2. A frase existe no núcleo extraído (o que será injetado)? → emNucleo
 *
 * Se a frase estiver em SKILL.md mas não no núcleo extraído, foi perdida.
 */

const fs = require('fs');
const path = require('path');

const INVARIANTES_PATH = path.join(__dirname, '../skills/rainforest-mind/invariantes.json');
const SKILL_PATH = path.join(__dirname, '../skills/rainforest-mind/SKILL.md');
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

// Carregar invariantes
let invariantes;
try {
  const content = fs.readFileSync(INVARIANTES_PATH, 'utf-8');
  invariantes = JSON.parse(content);
} catch (e) {
  console.error(`Erro ao carregar invariantes.json: ${e.message}`);
  process.exit(1);
}

// Ler o SKILL.md
let skillContent;
try {
  skillContent = fs.readFileSync(SKILL_PATH, 'utf-8');
} catch (e) {
  console.error(`Erro ao ler SKILL.md: ${e.message}`);
  process.exit(1);
}

// Aplicar o parser real para extrair o núcleo injetado
const regrasTexto = filtrarRegras(skillContent);
const nucleoContent = extrairNucleo(regrasTexto);

let totalInvariantes = 0;
let falhas = 0;

// Checar cada invariante
for (const inv of invariantes) {
  const { regra, frase, onde, descricao } = inv;
  totalInvariantes++;

  // Checagem 1: a frase está no núcleo do SKILL.md (antes do corte)?
  const emSkill = regrasTexto.includes(frase);

  // Checagem 2: a frase está no núcleo extraído (o que será injetado)?
  const emNucleo = nucleoContent.includes(frase);

  // Validar congruência baseada em 'onde'

  // Se deve estar em skill, checar se está
  if (onde.includes('skill') && !emSkill) {
    console.error(`FALHA invariante regra-${regra}: frase não encontrada no SKILL.md`);
    console.error(`  frase: "${frase}"`);
    console.error(`  descricao: ${descricao}`);
    falhas++;
  }

  // Se deve estar no núcleo injetado, checar se está
  // Se estiver em SKILL mas não em NUCLEO, foi perdida na extração
  if (onde.includes('nucleo')) {
    if (emSkill && !emNucleo) {
      // Frase está no arquivo original mas não no núcleo extraído
      // Significa que foi movida para depois da marca <!-- detalhe -->
      console.error(`FALHA invariante regra-${regra}: frase existe em SKILL.md mas não chega ao núcleo extraído`);
      console.error(`  frase: "${frase}"`);
      console.error(`  descricao: ${descricao}`);
      falhas++;
    } else if (!emSkill && !emNucleo) {
      // Frase não está em nenhum lugar — erro de configuração
      console.error(`FALHA invariante regra-${regra}: frase não encontrada nem em SKILL.md nem em núcleo extraído`);
      console.error(`  frase: "${frase}"`);
      falhas++;
    }
  }
}

if (falhas === 0) {
  console.log(`ok: conferidas ${totalInvariantes} invariantes`);
  process.exit(0);
} else {
  console.error(`FALHA: ${falhas} invariante(s) falharam`);
  process.exit(1);
}
