#!/usr/bin/env node
/**
 * Conferir esteira — validação de fechamento entre design, plano e código.
 *
 * Por que existe: a esteira não tem checagem de fechamento entre artefatos
 * vizinhos. Decisão do design pode não virar tarefa, opção refutada não tem
 * onde morar, e código sem tarefa correspondente atravessa o revisar como se
 * fosse estilo. As três costuras fecham aqui com checagem que trava, não com
 * instrução que pede.
 *
 * Desenho: D1 (esta é a trava — não prosa), D2 (identificador D<n>), D3
 * (opção em "Avaliado e descartado"), D4 (creep reprova), D6 (arquivo → glob),
 * D7 (script único com subcomandos).
 *
 * Uso:
 *   node scripts/conferir-esteira.cjs design --slug <s>
 *   node scripts/conferir-esteira.cjs cobertura --slug <s>
 *   node scripts/conferir-esteira.cjs creep --slug <s> --base <ref> --head <ref>
 *
 * Exit: 0 passou, 2 recusa deliberada, 1 erro de uso.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// A raiz é a do PROJETO em que se trabalha, mesma cadeia do estado.cjs
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

// ================================================================ Utilitários

function arg(nome, obrigatorio = true) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) {
    if (obrigatorio) {
      console.error(`erro: falta --${nome}`);
      process.exit(1);
    }
    return null;
  }
  return process.argv[i + 1];
}

function lerMarkdown(arquivo) {
  if (!fs.existsSync(arquivo)) {
    return null;
  }
  return fs.readFileSync(arquivo, 'utf8');
}

// ================================================================ design

/**
 * Valida a estrutura do design document.
 * Exige seções: Objetivo, Decisões fechadas, Avaliado e descartado, Fora de escopo, Em aberto.
 * Decisões são linhas `- **D<n> — <texto>**` com n sequencial, sem buraco, sem repetido.
 */
function cmdDesign() {
  const slug = arg('slug');
  const arquivo = path.join(RAIZ, 'docs', 'rainforest', 'design', `${slug}.md`);

  const conteudo = lerMarkdown(arquivo);
  if (!conteudo) {
    console.error(`RECUSADO: arquivo não existe: ${arquivo}`);
    process.exit(2);
  }

  // Verifica seções obrigatórias (como linhas exatas, não como substring)
  const secoes_obrigatorias = [
    '## Objetivo',
    '## Decisões fechadas',
    '## Avaliado e descartado',
    '## Fora de escopo',
    '## Em aberto',
  ];

  const linhas_conteudo = conteudo.split('\n');
  const secoes_encontradas = new Set(linhas_conteudo);

  for (const secao of secoes_obrigatorias) {
    if (!secoes_encontradas.has(secao)) {
      console.error(`RECUSADO: seção obrigatória ausente: ${secao}`);
      process.exit(2);
    }
  }

  // Extrai decisões de "Decisões fechadas"
  // Padrão: - **D<n> — <texto>** (travessão U+2014)
  const linhas = conteudo.split('\n');
  let em_decisoes = false;
  const decisoes = [];
  const decisoes_vistas = new Set();

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];

    // Marca inicio de "Decisões fechadas"
    if (linha === '## Decisões fechadas') {
      em_decisoes = true;
      continue;
    }

    // Marca fim de "Decisões fechadas" (outra seção começa)
    if (linha.startsWith('## ') && em_decisoes) {
      em_decisoes = false;
      continue;
    }

    // Se estamos em "Decisões fechadas", procura padrão D<n>
    if (em_decisoes && linha.startsWith('- **D')) {
      // Padrão: - **D<n> — <texto>**
      const match = linha.match(/^- \*\*D(\d+) — /);
      if (match) {
        const n = parseInt(match[1], 10);
        decisoes.push(n);
        decisoes_vistas.add(n);
      }
    }
  }

  // Valida seqüência: deve começar em 1, sem buraco, sem repetido
  if (decisoes.length === 0) {
    console.error('RECUSADO: nenhuma decisão encontrada no formato D<n>');
    process.exit(2);
  }

  // Ordena para checar
  const ordenadas = [...new Set(decisoes)].sort((a, b) => a - b);

  // Verifica se começa em 1
  if (ordenadas[0] !== 1) {
    console.error(`RECUSADO: decisões devem começar em D1, encontrado D${ordenadas[0]}`);
    process.exit(2);
  }

  // Verifica seqüência sem buraco
  for (let i = 0; i < ordenadas.length; i++) {
    if (ordenadas[i] !== i + 1) {
      console.error(`RECUSADO: buraco na seqüência de decisões: esperado D${i + 1}, pulou para D${ordenadas[i]}`);
      process.exit(2);
    }
  }

  // Verifica se há repetido
  if (decisoes.length !== ordenadas.length) {
    const duplicados = decisoes.filter((v, i) => decisoes.indexOf(v) !== i);
    console.error(`RECUSADO: decisão(ões) repetida(s): D${[...new Set(duplicados)].join(', D')}`);
    process.exit(2);
  }

  console.log(`ok: ${decisoes.length} decisão(ões) válida(s)`);
}

// ================================================================ cobertura

/**
 * Valida cobertura entre design e plano.
 * Decisão sem tarefa → recusa.
 * Tarefa com atende: vazio/ausente → recusa.
 * Tarefa citando D<n> inexistente → recusa.
 */
function cmdCobertura() {
  const slug = arg('slug');

  // Lê design
  const arquivo_design = path.join(RAIZ, 'docs', 'rainforest', 'design', `${slug}.md`);
  const conteudo_design = lerMarkdown(arquivo_design);
  if (!conteudo_design) {
    console.error(`RECUSADO: design não existe: ${arquivo_design}`);
    process.exit(2);
  }

  // Lê plano
  const arquivo_plano = path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  const conteudo_plano = lerMarkdown(arquivo_plano);
  if (!conteudo_plano) {
    console.error(`RECUSADO: plano não existe: ${arquivo_plano}`);
    process.exit(2);
  }

  // Extrai decisões do design
  const decisoes_design = extrairDecisoes(conteudo_design);

  // Extrai tarefas e seus atende do plano
  const tarefas = extrairTarefas(conteudo_plano);

  // Extrai D<n> mencionados em tarefas
  const decisoes_citadas = new Set();
  const erros = [];

  for (const tarefa of tarefas) {
    const { numero, nome, atende } = tarefa;

    // Verifica se atende está vazio/ausente
    if (!atende || atende.trim() === '') {
      erros.push(`tarefa ${numero}. ${nome} tem atende: vazio`);
      continue;
    }

    // Extrai D<n> de atende (format: "D1, D2, D3")
    const matches = atende.match(/D(\d+)/g);
    if (matches) {
      for (const match of matches) {
        const d = parseInt(match.substring(1), 10);
        decisoes_citadas.add(d);

        // Verifica se D existe
        if (!decisoes_design.has(d)) {
          erros.push(`tarefa ${numero}. ${nome} cita D${d} que não existe no design`);
        }
      }
    }
  }

  // Verifica decisões sem tarefa (D que nenhuma tarefa atende)
  for (const d of decisoes_design) {
    if (!decisoes_citadas.has(d)) {
      erros.push(`decisão D${d} não tem tarefa correspondente no plano`);
    }
  }

  if (erros.length > 0) {
    console.error('RECUSADO:');
    for (const erro of erros) {
      console.error(`  ${erro}`);
    }
    process.exit(2);
  }

  console.log(`ok: cobertura válida — ${decisoes_design.size} decisão(ões), ${tarefas.length} tarefa(s)`);
}

function extrairDecisoes(conteudo) {
  const decisoes = new Set();
  const linhas = conteudo.split('\n');
  let em_decisoes = false;

  for (const linha of linhas) {
    if (linha === '## Decisões fechadas') {
      em_decisoes = true;
      continue;
    }
    if (linha.startsWith('## ') && em_decisoes) {
      em_decisoes = false;
      continue;
    }
    if (em_decisoes && linha.startsWith('- **D')) {
      const match = linha.match(/^- \*\*D(\d+) — /);
      if (match) {
        decisoes.add(parseInt(match[1], 10));
      }
    }
  }

  return decisoes;
}

function extrairTarefas(conteudo) {
  const tarefas = [];
  const linhas = conteudo.split('\n');

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];

    // Tarefa começa com ### <n>. <nome>
    const match = linha.match(/^### (\d+)\. (.+?)(?:\s+\[tipo:|$)/);
    if (match) {
      const numero = parseInt(match[1], 10);
      const nome = match[2].trim();

      // Procura campo atende: nas próximas linhas
      let atende = '';
      for (let j = i + 1; j < linhas.length; j++) {
        const proxima = linhas[j];

        // Para quando chegar na próxima tarefa ou seção
        if (proxima.startsWith('###') || proxima.startsWith('##')) {
          break;
        }

        // Procura "atende: ..."
        if (proxima.startsWith('atende:')) {
          atende = proxima.substring('atende:'.length).trim();
          break;
        }
      }

      tarefas.push({ numero, nome, atende });
    }
  }

  return tarefas;
}

// ================================================================ creep

/**
 * Detecta arquivos no diff que não casam com glob de tarefa nenhuma.
 * Globs: *, **, ?
 * Isenção: docs/rainforest/design/**, docs/rainforest/planos/**, docs/rainforest/estado/**
 */
function cmdCreep() {
  const slug = arg('slug');
  const base = arg('base');
  const head = arg('head');

  // Lê plano
  const arquivo_plano = path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  const conteudo_plano = lerMarkdown(arquivo_plano);
  if (!conteudo_plano) {
    console.error(`RECUSADO: plano não existe: ${arquivo_plano}`);
    process.exit(2);
  }

  // Extrai globs de todas as tarefas
  const tarefas = extrairTarefas(conteudo_plano);
  const globs = [];
  for (const tarefa of tarefas) {
    const gs = extrairArquivos(conteudo_plano, tarefa.numero);
    globs.push(...gs);
  }

  // Isentos: os artefatos que a PRÓPRIA esteira escreve para ESTE trabalho.
  // Eles nunca aparecem no `arquivos:` de tarefa nenhuma — quem os escreve é o
  // brainstorm, o plano e o `estado.cjs` —, então sem isenção a checagem acusaria
  // o próprio rastro dela e nunca passaria.
  //
  // **Escopado por slug de propósito.** A primeira versão isentava
  // `docs/rainforest/design/**` inteiro, e com isso um diff que também tocasse o
  // design de OUTRA feature passava despercebido — creep de verdade, escondido
  // dentro da pasta isenta. É a mesma forma do glob largo que a decisão D6 proíbe
  // numa tarefa, só que embutida no checador, onde nenhum `revisar` a veria.
  // Achado 4 da revisão de 2026-08-13.
  const globs_isentos = [
    `docs/rainforest/design/${slug}.md`,
    `docs/rainforest/planos/${slug}.md`,
    `docs/rainforest/estado/${slug}.json`,
  ];

  // Pega diff
  let diff_arquivos = [];
  try {
    const cmd = `git diff --name-only ${base}...${head}`;
    const output = execSync(cmd, { cwd: RAIZ, encoding: 'utf8' });
    diff_arquivos = output.trim().split('\n').filter(f => f.length > 0);
  } catch (err) {
    console.error(`erro ao rodar git diff: ${err.message}`);
    process.exit(1);
  }

  // Normaliza \ para / (Windows)
  diff_arquivos = diff_arquivos.map(f => f.replace(/\\/g, '/'));

  // Verifica cada arquivo do diff
  const creep = [];
  for (const arquivo of diff_arquivos) {
    // Verifica se está nos globs isentos
    let isento = false;
    for (const g of globs_isentos) {
      if (globMatches(arquivo, g)) {
        isento = true;
        break;
      }
    }
    if (isento) continue;

    // Verifica se casa com algum glob de tarefa
    let casou = false;
    for (const g of globs) {
      if (globMatches(arquivo, g)) {
        casou = true;
        break;
      }
    }

    if (!casou) {
      creep.push(arquivo);
    }
  }

  if (creep.length > 0) {
    console.error('RECUSADO: arquivo(s) no diff sem tarefa correspondente:');
    for (const arq of creep) {
      console.error(`  ${arq}`);
    }
    console.error('Emendar o plano: adicione uma tarefa com campos arquivos: que cubra este(s) arquivo(s)');
    process.exit(2);
  }

  console.log(`ok: sem creep — ${diff_arquivos.length} arquivo(s) coberto(s)`);
}

function extrairArquivos(conteudo_plano, numero_tarefa) {
  const linhas = conteudo_plano.split('\n');
  let em_tarefa = false;
  const globs = [];

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];

    // Identifica a tarefa pelo número
    if (linha.match(new RegExp(`^### ${numero_tarefa}\\.`))) {
      em_tarefa = true;
      continue;
    }

    // Para quando chegar em outra tarefa ou seção
    if (em_tarefa && (linha.startsWith('###') || linha.startsWith('##'))) {
      break;
    }

    // Procura "arquivos: ..."
    if (em_tarefa && linha.startsWith('arquivos:')) {
      // Formato: arquivos: `<glob>`, `<glob>`
      // ou: arquivos: `<glob>`
      const match = linha.match(/arquivos:\s*(.+)/);
      if (match) {
        const items = match[1];
        // Extrai globs entre backticks
        const matches = items.match(/`([^`]+)`/g);
        if (matches) {
          for (const m of matches) {
            globs.push(m.replace(/`/g, ''));
          }
        }
      }
    }
  }

  return globs;
}

/**
 * Glob simples: *, **, ?
 * * não cruza /
 * ** cruza /
 * ? é qualquer caractere (não /)
 */
function globMatches(arquivo, glob) {
  // Simples: se não tem *, **, ou ?, é match literal
  if (!glob.includes('*') && !glob.includes('?')) {
    return arquivo === glob;
  }

  // Converte glob para regex
  let pattern = glob
    .replace(/\./g, '\\.')
    .replace(/\//g, '/');

  // ** em qualquer lugar cruza /
  pattern = pattern.replace(/\*\*/g, '<<<DOUBLESTAR>>>');
  // * em qualquer lugar não cruza /
  pattern = pattern.replace(/\*/g, '[^/]*');
  // ? é qualquer caractere (não /)
  pattern = pattern.replace(/\?/g, '[^/]');
  // Restaura **
  pattern = pattern.replace(/<<<DOUBLESTAR>>>/g, '.*');

  // Âncora: se não começar com *, é desde o início
  if (!glob.startsWith('*')) {
    pattern = '^' + pattern;
  }
  // Se não terminar com *, é até o final
  if (!glob.endsWith('*')) {
    pattern = pattern + '$';
  }

  const regex = new RegExp(pattern);
  return regex.test(arquivo);
}

// ================================================================ main

function main() {
  const cmd = process.argv[2];

  if (cmd === 'design') {
    return cmdDesign();
  }

  if (cmd === 'cobertura') {
    return cmdCobertura();
  }

  if (cmd === 'creep') {
    return cmdCreep();
  }

  console.error('uso: design | cobertura | creep');
  process.exit(1);
}

if (require.main === module) main();
module.exports = { globMatches };
