#!/usr/bin/env node
// @categoria: sensor
/**
 * conferir-invariantes.cjs — valida que frases críticas não foram perdidas na extração.
 *
 * Procura todos os `skills/<nome>/invariantes.json` e valida frases de cada skill
 * contra seu correspondente `skills/<nome>/SKILL.md`.
 *
 * Formato de invariante:
 *   - `frase`: string a validar (obrigatório)
 *   - `tipo`: "deve" (padrão) ou "nao_deve" (obrigatório)
 *   - `onde`: ["skill", "nucleo", "referencia"] — opcional
 *     - Ausente: testa presença no corpo do SKILL.md
 *     - Presente: testa presença conforme configurado (skill, referencia, nucleo)
 *   - `regra`, `descricao`: metadados
 *
 * Regra do `tipo: "nao_deve"`:
 * - Frase proibida só vale se for vocabulário que o texto correto nunca usa
 * - Exemplo: `--confirmo` é proibido no `fechar` e obrigatório no `limpar`, então
 *   um `nao_deve: --confirmo` dispararia no texto certo — proibido
 * - `CONFIRMO fechar issue` é seguro: não existe em nenhuma skill correta
 */

const fs = require('fs');
const path = require('path');

const SKILLS_DIR = path.join(__dirname, '../skills');
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

// Descobrir todas as skills com invariantes.json
let skillsComInvariantes = [];
try {
  const entries = fs.readdirSync(SKILLS_DIR);
  for (const entry of entries) {
    const skillDir = path.join(SKILLS_DIR, entry);
    const stats = fs.statSync(skillDir);
    if (stats.isDirectory()) {
      const invariantesPath = path.join(skillDir, 'invariantes.json');
      if (fs.existsSync(invariantesPath)) {
        skillsComInvariantes.push(entry);
      }
    }
  }
  skillsComInvariantes.sort();
} catch (e) {
  console.error(`Erro ao descobrir skills: ${e.message}`);
  process.exit(1);
}

// Zero arquivos encontrados é erro
if (skillsComInvariantes.length === 0) {
  console.error('Erro: nenhum arquivo skills/*/invariantes.json encontrado');
  process.exit(1);
}

let totalInvariantes = 0;
let falhas = 0;

// Processar cada skill com invariantes
for (const nomeSkill of skillsComInvariantes) {
  const skillDir = path.join(SKILLS_DIR, nomeSkill);
  const invariantesPath = path.join(skillDir, 'invariantes.json');
  const skillMdPath = path.join(skillDir, 'SKILL.md');
  const referencesDir = path.join(skillDir, 'references');

  // Carregar invariantes
  let invariantes;
  try {
    const content = fs.readFileSync(invariantesPath, 'utf-8');
    invariantes = JSON.parse(content);
  } catch (e) {
    console.error(`Erro ao carregar [${nomeSkill}] invariantes.json: ${e.message}`);
    process.exit(1);
  }

  // Ler o SKILL.md
  let skillContent;
  try {
    skillContent = fs.readFileSync(skillMdPath, 'utf-8');
  } catch (e) {
    console.error(`Erro ao ler [${nomeSkill}] SKILL.md: ${e.message}`);
    process.exit(1);
  }

  // Cache de referencias lidas para esta skill
  const referenciaCache = {};

  function lerReferencia(regra) {
    if (referenciaCache[regra] !== undefined) {
      return referenciaCache[regra];
    }

    const caminhoReferencia = path.join(referencesDir, `regra-${regra}.md`);
    try {
      if (fs.existsSync(caminhoReferencia)) {
        referenciaCache[regra] = fs.readFileSync(caminhoReferencia, 'utf-8');
        return referenciaCache[regra];
      }
    } catch (e) {
      // arquivo não existe ou não conseguiu ler
    }
    referenciaCache[regra] = null;
    return null;
  }

  // Aplicar o parser real para extrair o núcleo injetado apenas se necessário
  let regrasTexto, nucleoContent;
  const temOnde = invariantes.some(inv => inv.onde !== undefined);
  if (temOnde) {
    regrasTexto = filtrarRegras(skillContent);
    nucleoContent = extrairNucleo(regrasTexto);
  }

  // Checar cada invariante
  for (const inv of invariantes) {
    const { regra, frase, onde = undefined, descricao, tipo = 'deve' } = inv;
    totalInvariantes++;

    // Validar tipo conhecido
    if (tipo !== 'deve' && tipo !== 'nao_deve') {
      console.error(`Erro: tipo desconhecido "${tipo}" na invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}`);
      process.exit(1);
    }

    // Determinação do "corpo" a testar conforme o tipo e onde
    const corpo = skillContent;

    // Checagem de tipo nao_deve
    const proibidaPresente = tipo === 'nao_deve' && corpo.includes(inv.frase);
    if (proibidaPresente) {
      console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase proibida encontrada no corpo`);
      console.error(`  frase: "${frase}"`);
      console.error(`  descricao: ${descricao}`);
      falhas++;
      continue;
    }

    // Se for deve, executar checagens normais
    if (tipo === 'deve') {
      // Se onde não foi especificado, apenas testa presença no corpo
      if (onde === undefined) {
        if (!corpo.includes(frase)) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada no SKILL.md`);
          console.error(`  frase: "${frase}"`);
          console.error(`  descricao: ${descricao}`);
          falhas++;
        } else {
          // Checar ocorrência única
          const n = corpo.split(frase).length - 1;
          if (n >= 2) {
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase aparece ${n} vezes (deve aparecer exatamente 1)`);
            console.error(`  frase: "${frase}"`);
            falhas++;
          }
        }
      } else {
        // onde foi especificado — executar checagens conforme a semântica original

        // Checagem 1: a frase está no núcleo do SKILL.md (antes do corte)?
        const emSkill = regrasTexto.includes(frase);

        // Checagem 2: a frase está na referência (references/regra-<n>.md)?
        let emReferencia = false;
        if (onde.includes('referencia')) {
          const conteudoReferencia = lerReferencia(regra);
          emReferencia = conteudoReferencia !== null && conteudoReferencia.includes(frase);
        }

        // Checagem 3: a frase está no núcleo extraído (o que será injetado)?
        const emNucleo = nucleoContent.includes(frase);

        // Validar congruência baseada em 'onde'

        // Se deve estar em skill, checar se está
        if (onde.includes('skill') && !emSkill) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada no SKILL.md`);
          console.error(`  frase: "${frase}"`);
          console.error(`  descricao: ${descricao}`);
          falhas++;
        }

        // Se deve estar em referencia, checar se está
        if (onde.includes('referencia') && !emReferencia) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada na references/regra-${regra}.md`);
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
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase existe em SKILL.md mas não chega ao núcleo extraído`);
            console.error(`  frase: "${frase}"`);
            console.error(`  descricao: ${descricao}`);
            falhas++;
          } else if (!emSkill && !emNucleo) {
            // Frase não está em nenhum lugar — erro de configuração
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada nem em SKILL.md nem em núcleo extraído`);
            console.error(`  frase: "${frase}"`);
            falhas++;
          }
        }

        // Checar ocorrência única
        const n = corpo.split(frase).length - 1;
        if (n >= 2) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase aparece ${n} vezes (deve aparecer exatamente 1)`);
          console.error(`  frase: "${frase}"`);
          falhas++;
        }
      }
    }
  }
}

if (falhas === 0) {
  console.log(`ok: conferidas ${totalInvariantes} invariantes`);
  process.exit(0);
} else {
  console.error(`FALHA: ${falhas} invariante(s) falharam`);
  process.exit(2);
}
