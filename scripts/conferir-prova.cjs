#!/usr/bin/env node
// @categoria: sensor
/**
 * conferir-prova — a `prova:` executa na base e tem de falhar
 *
 * Uso:
 *   node scripts/conferir-prova.cjs plano --slug <s> [--plano <arquivo>]
 *
 * Exit: 0 todas as provas OK, 2 recusa deliberada, 1 erro de uso, 69 nao-verificavel
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const { caminhoDoc } = require(path.join(__dirname, '..', 'hooks', 'lib', 'pastas-docs.cjs'));
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const SCRIPT_DIR = path.dirname(__filename);
const { extrairTarefas, lerMarkdown } = require(path.join(SCRIPT_DIR, 'conferir-fluxo.cjs'));

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

// ================================================================ Limpeza de worktree

let worktreeAtual = null;

function criaWorktree(repo) {
  try {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-prova-'));
    const r = spawnSync(caminhoExecutavel('git'), ['worktree', 'add', '--detach', tmp, 'HEAD'], {
      cwd: repo,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (r.error || r.status !== 0) {
      return null;
    }
    worktreeAtual = { path: tmp, repo };
    return tmp;
  } catch {
    return null;
  }
}

function removeWorktree() {
  if (!worktreeAtual) return;
  const { path: tmpPath, repo } = worktreeAtual;
  try {
    spawnSync(caminhoExecutavel('git'), ['worktree', 'remove', '--force', tmpPath], {
      cwd: repo,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    spawnSync(caminhoExecutavel('git'), ['worktree', 'prune'], {
      cwd: repo,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    // ignore
  }
  try {
    if (fs.existsSync(tmpPath)) {
      fs.rmSync(tmpPath, { recursive: true, force: true });
    }
  } catch {
    // ignore
  }
  worktreeAtual = null;
}

function limpeza() {
  removeWorktree();
}

process.on('exit', limpeza);
process.on('SIGINT', () => { limpeza(); process.exit(130); });
process.on('SIGTERM', () => { limpeza(); process.exit(143); });

// ================================================================ Comando plano

function cmdPlano() {
  const slug = arg('slug');
  const arquivo = arg('plano', false) || path.join(RAIZ, caminhoDoc('planos', slug, { raiz: RAIZ }));

  const conteudo = lerMarkdown(arquivo);
  if (!conteudo) {
    console.error(`RECUSADO: plano não existe: ${arquivo}`);
    process.exit(2);
  }

  const tarefas = extrairTarefas(conteudo);
  const recusas = [];
  let provasExecutadas = 0;

  for (const tarefa of tarefas) {
    const { numero, nome, tipo, prova, provaMalformada, provaNaBase } = tarefa;

    // Tipos isentos: docs, pesquisar, pesquisa, configurar
    if (['docs', 'pesquisar', 'pesquisa', 'configurar'].includes(tipo)) {
      continue;
    }

    // prova malformada: recusa
    if (provaMalformada) {
      recusas.push(`tarefa ${numero}. ${nome} tem \`prova:\` malformada`);
      continue;
    }

    // Sem prova nem prova-na-base: recusa
    if (!prova && !provaNaBase) {
      recusas.push(`tarefa ${numero}. ${nome} sem \`prova:\` nem \`prova-na-base:\``);
      continue;
    }

    // Ambos prova e prova-na-base: recusa (incompatível)
    if (prova && provaNaBase !== null) {
      recusas.push(`tarefa ${numero}. ${nome} tem \`prova:\` e \`prova-na-base:\` simultaneamente`);
      continue;
    }

    // prova-na-base sem motivo: recusa
    if (provaNaBase !== null && provaNaBase.trim() === '') {
      recusas.push(`tarefa ${numero}. ${nome} tem \`prova-na-base:\` sem motivo`);
      continue;
    }

    // Se tem prova-na-base, validar forma: deve ser "verde — <motivo>"
    if (provaNaBase !== null && provaNaBase.trim() !== '') {
      const match = provaNaBase.match(/^verde\s+—\s+(.+)$/);
      if (!match || !match[1].trim()) {
        recusas.push(`tarefa ${numero}. ${nome} tem \`prova-na-base:\` fora da forma \`verde — <motivo>\``);
        continue;
      }
      // Prova-na-base válida: imprimir motivo ao stdout
      console.log(`tarefa ${numero}: prova-na-base verde — ${match[1]}`);
      continue;
    }

    // Executa a prova (se chegou aqui, tem `prova`)
    const wt = criaWorktree(RAIZ);
    if (!wt) {
      // Não conseguiu criar worktree: 69 (nao-verificavel)
      console.error('nao-verificavel: não conseguiu criar worktree');
      process.exit(69);
    }

    const timeout = parseInt(process.env.RFM_PROVA_TIMEOUT_MS || '120000', 10);
    // Preparar env: remover variáveis que apontam para o repo/estado reais
    const env = { ...process.env };
    delete env.RFM_ESTADO_ROOT;
    delete env.CLAUDE_PROJECT_DIR;
    delete env.RFM_ROOT;
    const resultado = spawnSync('bash', ['-c', prova], {
      cwd: wt,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout,
      env,
    });

    // 126/127 so e "o arquivo nasce na tarefa" na forma simples
    // `bash|sh|node|python <arquivo>`, sem operador de shell, e com o arquivo
    // de fato ausente na base. Olhar so o primeiro token aceitava
    // `bash -c 'comando-inexistente'` e `bash x.sh || comando-inexistente`.
    const formaSimples = /^(bash|sh|node|python|python3)\s+("[^"]+"|'[^']+'|[^\s;&|<>()`$]+)$/.exec(prova.trim());
    const arquivoNasceNaTarefa = !!formaSimples &&
      !fs.existsSync(path.join(wt, formaSimples[2].replace(/^["']|["']$/g, '')));

    removeWorktree();

    // Analisar resultado
    if (resultado.error) {
      // ENOENT ou ETIMEDOUT
      if (resultado.error.code === 'ETIMEDOUT') {
        console.error('nao-verificavel: timeout na execução da prova');
        process.exit(69);
      } else {
        console.error('nao-verificavel: erro ao executar prova');
        process.exit(69);
      }
    }

    if (resultado.signal) {
      console.error('nao-verificavel: prova interrompida por sinal');
      process.exit(69);
    }

    // Exit 0: recusa (a prova já passa na base)
    if (resultado.status === 0) {
      recusas.push(`tarefa ${numero}. ${nome} tem prova que sai 0 na base`);
      continue;
    }

    // Exit 126 ou 127: comando que nao executa (recusa), salvo a forma simples
    // cujo arquivo a propria tarefa cria (arquivoNasceNaTarefa, acima).
    if (resultado.status === 126 || resultado.status === 127) {
      if (!arquivoNasceNaTarefa) {
        recusas.push(`tarefa ${numero}. ${nome} a prova não executa (exit ${resultado.status}) — se ela roda um arquivo que a tarefa cria, use a forma simples: bash <arquivo>`);
        continue;
      }
      provasExecutadas++;
      continue;
    }

    // Qualquer outro exit ≠ 0: aceita
    provasExecutadas++;
  }

  if (recusas.length > 0) {
    console.error('RECUSADO:');
    for (const recusa of recusas) {
      console.error(`  ${recusa}`);
    }
    process.exit(2);
  }

  // Se não executou nenhuma prova (todas isentas ou com prova-na-base), tudo bem
  if (provasExecutadas > 0) {
    console.log(`ok: ${provasExecutadas} prova(s) executada(s), todas falhando na base`);
  } else {
    console.log('ok: nenhuma prova para executar');
  }
}

// ================================================================ Main

function main() {
  const subcmd = process.argv[2];
  if (subcmd === 'plano') {
    cmdPlano();
  } else {
    console.error('uso: plano --slug <s> [--plano <arquivo>]');
    process.exit(1);
  }
}

if (require.main === module) main();
module.exports = { cmdPlano };
