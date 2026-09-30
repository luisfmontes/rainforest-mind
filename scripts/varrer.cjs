#!/usr/bin/env node
"use strict";
/**
 * Varrer.cjs — coleta o que o repositório já sabia em varredura estruturada.
 *
 * Uso:
 *   node scripts/varrer.cjs --slug <s> <termo>...
 *
 * Grava: docs/rainforest/varredura/<slug>.txt com a data, termos, cada comando
 * e sua saída, em ordem: Issues, PRs, branches remotas, commits, ideias.
 *
 * Exit: 0 sucesso, 2 uso (sem --slug, sem termo), 69 nao-verificavel (gh ausente,
 * sem autenticação, ambiente inacessível). Nenhum arquivo é gravado em 69.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Resolver a raiz: mesma cadeia de conferir-fluxo.cjs
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

// Estado padrão para os dois comandos gh
const ESTADO_TODOS = "all";

// Utilitários

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) return null;
  return process.argv[i + 1];
}

function naoVerificavel(msg) {
  console.error(`nao-verificavel: ${msg}`);
  process.exit(69);
}

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  process.exit(2);
}

// Processar argumentos
const slug = arg('slug');
if (!slug) {
  erroUso('falta --slug <s>');
}

const termos = process.argv.slice(process.argv.indexOf('--slug') + 2);
if (termos.length === 0 || termos.some(t => t.startsWith('-'))) {
  erroUso('falta termo (um ou mais)');
}

// Coletar dados de todas as fontes
const saidas = [];

// Helper para rodar comando com gh
function spawnarGh(args) {
  const gh = process.env.RFM_VARRER_GH || 'gh';
  const ehNode = /\.(c|m)?js$/i.test(gh);

  const cmd = ehNode ? process.execPath : gh;
  const cmdArgs = ehNode ? [gh, ...args] : args;

  const r = spawnSync(cmd, cmdArgs, {
    encoding: 'utf8',
    cwd: RAIZ,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (r.error && r.error.code === 'ENOENT') {
    naoVerificavel(`gh não encontrado`);
  }

  return r;
}

// 1. Issues abertas e fechadas
for (const termo of termos) {
  const r = spawnarGh([
    'issue', 'list',
    '--state', ESTADO_TODOS,
    '--search', termo,
    '--json', 'number,title,state'
  ]);

  if (r.status !== 0) {
    naoVerificavel(`gh issue falhou com exit ${r.status}`);
  }

  saidas.push({
    comando: `gh issue list --state ${ESTADO_TODOS} --search "${termo}" --json number,title,state`,
    saida: r.stdout
  });
}

// 2. PRs em todos os estados
for (const termo of termos) {
  const r = spawnarGh([
    'pr', 'list',
    '--state', ESTADO_TODOS,
    '--search', termo,
    '--json', 'number,title,state'
  ]);

  if (r.status !== 0) {
    naoVerificavel(`gh pr falhou com exit ${r.status}`);
  }

  saidas.push({
    comando: `gh pr list --state ${ESTADO_TODOS} --search "${termo}" --json number,title,state`,
    saida: r.stdout
  });
}

// 3. Branches remotas
for (const termo of termos) {
  const r = spawnSync('git', ['ls-remote', '--heads', 'origin'], {
    encoding: 'utf8',
    cwd: RAIZ,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (r.error && r.error.code === 'ENOENT') {
    naoVerificavel('git não encontrado');
  }

  if (r.status === 0) {
    // Filtrar pelo termo
    const linhas = r.stdout
      .split('\n')
      .filter(l => l.includes(termo))
      .join('\n');
    if (linhas.trim()) {
      saidas.push({
        comando: `git ls-remote --heads origin`,
        saida: linhas
      });
    }
  }
}

// 4. git log com grep
for (const termo of termos) {
  const r = spawnSync('git', ['log', '--all', `--grep=${termo}`, '--oneline'], {
    encoding: 'utf8',
    cwd: RAIZ,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (r.error && r.error.code === 'ENOENT') {
    naoVerificavel('git não encontrado');
  }

  if (r.status === 0) {
    const linhas = r.stdout.trim();
    if (linhas) {
      saidas.push({
        comando: `git log --all --grep="${termo}" --oneline`,
        saida: linhas
      });
    }
  }
}

// 5. ideias.jsonl (só id e titulo, filtrado por termo)
const caminhoIdeias = path.join(RAIZ, 'ideias.jsonl');
if (fs.existsSync(caminhoIdeias)) {
  try {
    const conteudo = fs.readFileSync(caminhoIdeias, 'utf8');
    const ideias = conteudo
      .split('\n')
      .filter(l => l.trim())
      .map(l => {
        try {
          return JSON.parse(l);
        } catch {
          return null;
        }
      })
      .filter(o => o !== null && (
        (o.id && termos.some(t => o.id.includes(t))) ||
        (o.titulo && termos.some(t => o.titulo.includes(t)))
      ))
      .map(o => ({ id: o.id, titulo: o.titulo }));

    if (ideias.length > 0) {
      saidas.push({
        comando: `cat ${caminhoIdeias}`,
        saida: ideias.map(o => JSON.stringify(o)).join('\n') + '\n'
      });
    }
  } catch (e) {
    // Silencioso se falhar na leitura de ideias
  }
}

// Montar o conteúdo do arquivo de varredura
const agora = new Date().toISOString().split('T')[0];
let conteudo = `Data: ${agora}\n`;
conteudo += `Termos: ${termos.join(', ')}\n`;
conteudo += '\n';

for (const { comando, saida } of saidas) {
  conteudo += `$ ${comando}\n`;
  conteudo += saida || '(vazio)\n';
  conteudo += '\n';
}

// Gravar o arquivo
const dirVarredura = path.join(RAIZ, 'docs', 'rainforest', 'varredura');
try {
  fs.mkdirSync(dirVarredura, { recursive: true });
  const caminhoSaida = path.join(dirVarredura, `${slug}.txt`);
  fs.writeFileSync(caminhoSaida, conteudo, 'utf8');
  process.exit(0);
} catch (e) {
  naoVerificavel(`Não foi possível gravar ${dirVarredura}/${slug}.txt: ${e.message}`);
}
