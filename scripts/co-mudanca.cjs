#!/usr/bin/env node
"use strict";
/**
 * co-mudanca.cjs — arquivos que mudam junto com o alvo, pelo histórico do git.
 *
 * Uso (na raiz do repo):
 *   node scripts/co-mudanca.cjs <arquivo> [--meses 6] [--min 3]
 *
 * Lê `git log --name-only` dos últimos N meses, ignora commit com mais de 20
 * arquivos (refatoração ampla não é acoplamento) e lista os outros arquivos que
 * mudaram junto com o alvo pelo menos --min vezes, com score
 * juntos / mudancas_do_alvo >= 0.3, do maior para o menor.
 *
 * Exit: 0 lista ou histórico insuficiente; 1 fora de repo git ou git falhou;
 * 2 uso errado.
 */

const { execFileSync } = require('child_process');
const { caminhoExecutavel } = require(require('path').join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const MAX_ARQUIVOS_COMMIT = 20;
const SCORE_MINIMO = 0.3;

function uso(msg) {
  process.stderr.write(`${msg}\nUso: node scripts/co-mudanca.cjs <arquivo> [--meses 6] [--min 3]\n`);
  process.exit(2);
}

function lerArgs(argv) {
  const opts = { meses: 6, min: 3, alvo: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--meses' || a === '--min') {
      const v = argv[++i];
      if (!/^\d+$/.test(v || '') || Number(v) < 1) uso(`valor inválido para ${a}: ${v}`);
      opts[a === '--meses' ? 'meses' : 'min'] = Number(v);
    } else if (a.startsWith('--')) {
      uso(`opção desconhecida: ${a}`);
    } else if (opts.alvo === null) {
      opts.alvo = a;
    } else {
      uso(`argumento sobrando: ${a}`);
    }
  }
  if (!opts.alvo) uso('falta o <arquivo>');
  return opts;
}

// Devolve um array de commits; cada commit é a lista de arquivos que ele tocou.
function lerCommits(meses) {
  let saida;
  try {
    saida = execFileSync(
      caminhoExecutavel('git'),
      ['-c', 'core.quotePath=false', 'log', `--since=${meses} months ago`, '--name-only', '--format=%x00%H', '--no-merges'],
      { cwd: process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 512 * 1024 * 1024 }
    );
  } catch (e) {
    const motivo = String(e.stderr || e.message || 'git falhou').trim().split('\n')[0];
    process.stderr.write(`co-mudanca: ${motivo}\n`);
    process.exit(1);
  }
  // Cada bloco começa com o NUL do formato; a primeira linha do bloco é o hash.
  return saida.split('\0').slice(1).map((bloco) =>
    bloco.split('\n').filter((l) => l.length > 0).slice(1)
  );
}

function main() {
  const opts = lerArgs(process.argv.slice(2));
  const alvo = opts.alvo.replace(/\\/g, '/');
  const commits = lerCommits(opts.meses);

  let mudancas = 0;
  const juntos = new Map();
  for (const arquivos of commits) {
    if (arquivos.length > MAX_ARQUIVOS_COMMIT) continue;
    if (!arquivos.includes(alvo)) continue;
    mudancas++;
    for (const outro of new Set(arquivos)) {
      if (outro === alvo) continue;
      juntos.set(outro, (juntos.get(outro) || 0) + 1);
    }
  }

  if (mudancas < opts.min) {
    process.stdout.write(
      `histórico insuficiente: ${alvo} mudou ${mudancas} vez(es) em ${opts.meses} meses (mínimo ${opts.min})\n`
    );
    process.exit(0);
  }

  const linhas = [...juntos.entries()]
    .map(([arquivo, n]) => ({ arquivo, n, score: n / mudancas }))
    .filter((x) => x.n >= opts.min && x.score >= SCORE_MINIMO)
    .sort((a, b) => b.score - a.score || a.arquivo.localeCompare(b.arquivo));

  for (const x of linhas) {
    process.stdout.write(`${x.arquivo}  ${x.n}/${mudancas}  ${x.score.toFixed(2)}\n`);
  }
  process.exit(0);
}

main();
