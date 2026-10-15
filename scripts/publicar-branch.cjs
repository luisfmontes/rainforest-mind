#!/usr/bin/env node
/**
 * Publicação conferida do `fechar`. Design
 * docs/rainforest/design/2026-10-13-fechar-push-merge.md, D1 a D6.
 *
 * Por que existe: o passo 5 do `fechar` publicava em prosa, e a sessão declarava
 * "pushado" e "mergeado" pelo texto do CLI. Este script faz as conferências que
 * a prosa pulava: conflito com a base antes do push (merge-tree, fail-closed),
 * HEAD igual ao @{u} depois do push, reaproveitamento de PR aberto e, onde a chave
 * `fechar-mergear` autoriza, espera do CI e confirmação do merge pelo `state` do
 * PR, nunca pela linha de sucesso do `gh`. Nunca roda `gh pr create` nem
 * `gh pr merge` por dentro: isso escaparia do gate-fechar-issue.
 *
 * Uso:
 *   node scripts/publicar-branch.cjs publicar [--base <ref>]
 *   node scripts/publicar-branch.cjs esperar-ci --pr <n>
 *   node scripts/publicar-branch.cjs confirmar-merge --pr <n>
 *
 * Saídas:
 *   0   ok
 *   1   uso (subcomando desconhecido, flag desconhecida, --pr não inteiro positivo)
 *   3   conflito com a base (publicar): nada foi empurrado, arquivos listados
 *   4   push divergiu (recusado, ou HEAD != @{u} depois do push)
 *   5   CI não verde (esperar-ci)
 *   6   merge não confirmado: state fechado sem merge, ou prazo esgotado (confirmar-merge)
 *   7   CI verde mas `fechar-mergear` desligada: merge não autorizado (esperar-ci)
 *   69  ambiente: git/gh ausente ou sem auth, falha de rede, remoto não GitHub onde
 *       o subcomando precisa dele, ou saída inesperada do gh
 *
 * `RFM_MERGE_PRAZO_S` (padrão 60) limita a espera do state em confirmar-merge.
 */
'use strict';

const { spawnSync } = require('child_process');
const { caminhoExecutavel, executar } = require('../hooks/lib/resolver-executavel.cjs');
const { resolverConfig } = require('../hooks/lib/config.cjs');

const USO = 'uso: node scripts/publicar-branch.cjs publicar [--base <ref>] | esperar-ci --pr <n> | confirmar-merge --pr <n>';
const SUBCOMANDOS = { publicar: ['--base'], 'esperar-ci': ['--pr'], 'confirmar-merge': ['--pr'] };

function git(args) {
  return spawnSync(caminhoExecutavel('git'), args, { encoding: 'utf8', windowsHide: true });
}

function erro(msg, detalhe) {
  process.stderr.write(`${msg}\n`);
  if (detalhe && detalhe.trim()) process.stderr.write(`${detalhe.trim()}\n`);
}

function lerArgs(argv) {
  const [sub, ...resto] = argv;
  if (!Object.prototype.hasOwnProperty.call(SUBCOMANDOS, sub)) return null;
  const permitidas = SUBCOMANDOS[sub];
  const o = {};
  for (let i = 0; i < resto.length; i++) {
    const flag = resto[i];
    const valor = resto[i + 1];
    if (!permitidas.includes(flag) || valor === undefined || valor.startsWith('-')) return null;
    o[flag.slice(2)] = valor;
    i++;
  }
  if (o.pr !== undefined && !/^[1-9]\d*$/.test(o.pr)) return null;
  if (sub !== 'publicar' && o.pr === undefined) return null;
  return { sub, o };
}

function toplevel() {
  const r = git(['rev-parse', '--show-toplevel']);
  return r.status === 0 ? r.stdout.trim() : null;
}

// Lê a URL CRUA do remote, sem expandir insteadOf. `git remote get-url` expande
// insteadOf, e nesta bateria o remoto GitHub é reescrito para um bare local: a
// checagem de "é GitHub?" tem de ver a URL que o repositório declara.
function urlOrigem() {
  const r = git(['config', '--get', 'remote.origin.url']);
  return r.status === 0 ? r.stdout.trim() : null;
}

function exigirGithub() {
  const url = urlOrigem();
  if (url === null) {
    erro('sem remoto origin: este subcomando precisa de um remoto GitHub');
    return 69;
  }
  if (!/github\.com/.test(url)) {
    erro(`remoto não é GitHub (${url}): este subcomando precisa de gh`);
    return 69;
  }
  return 0;
}

function basePadrao() {
  const r = git(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']);
  const nome = r.status === 0 ? r.stdout.trim() : '';
  return nome.startsWith('origin/') ? nome.slice('origin/'.length) : 'main';
}

function publicar(argBase) {
  const br = git(['symbolic-ref', '--short', 'HEAD']);
  if (br.status !== 0) {
    erro('HEAD destacado: não há branch para publicar', br.stderr);
    return 69;
  }
  const nome = br.stdout.trim();
  const base = argBase || basePadrao();

  const f = git(['fetch', 'origin', base]);
  if (f.status !== 0) {
    erro(`git fetch origin ${base} falhou: nada foi empurrado`, f.stderr);
    return 69;
  }

  // Fail-closed: só "sem conflito" com exit 0. Exit 1 é conflito; qualquer outro
  // exit é falha do comando, e falha do comando não vira "passou".
  const mt = git(['merge-tree', '--write-tree', '--name-only', 'HEAD', `origin/${base}`]);
  if (mt.status === 1) {
    // Exit 1 também sai de ref que não existe ("not something we can merge"):
    // conflito de verdade imprime o OID da árvore na 1ª linha e ao menos um arquivo.
    const linhas = mt.stdout.split(/\r?\n/);
    const arquivos = [];
    for (const linha of linhas.slice(1)) {
      if (linha.trim() === '') break;
      arquivos.push(linha);
    }
    if (!/^[0-9a-f]{40,64}$/.test((linhas[0] || '').trim()) || arquivos.length === 0) {
      erro(`git merge-tree saiu 1 sem árvore de conflito (origin/${base} não resolve?): nada foi empurrado`, mt.stderr);
      return 69;
    }
    process.stdout.write(`CONFLITO com origin/${base}: a branch ${nome} NAO foi empurrada.\n`);
    for (const a of arquivos) process.stdout.write(`conflito em: ${a}\n`);
    process.stdout.write('Resolva (merge ou rebase de origin/' + base + ') e rode publicar de novo.\n');
    return 3;
  }
  if (mt.status !== 0) {
    erro(`git merge-tree falhou (base origin/${base}): nada foi empurrado`, mt.stderr);
    return 69;
  }

  const p = git(['push', '-u', 'origin', nome]);
  if (p.status !== 0) {
    erro(`push de ${nome} recusado`, p.stderr);
    return 4;
  }

  const h = git(['rev-parse', 'HEAD']);
  const u = git(['rev-parse', '@{u}']);
  if (h.status !== 0 || u.status !== 0 || h.stdout.trim() !== u.stdout.trim()) {
    erro(`HEAD != @{u} depois do push de ${nome}`, `${h.stdout}${u.stdout}${h.stderr}${u.stderr}`);
    return 4;
  }
  process.stdout.write(`publicado: ${nome} em ${h.stdout.trim()}\n`);

  const url = urlOrigem() || '';
  if (!/github\.com/.test(url)) {
    process.stdout.write('PR aberto: n/a (remoto não é GitHub)\n');
    return 0;
  }

  const pr = executar('gh', ['pr', 'list', '--head', nome, '--state', 'open', '--json', 'number', '--jq', '.[0].number']);
  if (pr.status !== 0) {
    erro('gh pr list falhou (gh ausente ou sem auth?): o push já foi feito, o PR não foi conferido', pr.stderr);
    return 69;
  }
  const valor = (pr.stdout || '').trim();
  if (valor === '' || valor === 'null') {
    process.stdout.write('PR aberto: nenhum\n');
    return 0;
  }
  if (/^[1-9]\d*$/.test(valor)) {
    process.stdout.write(`PR aberto: ${valor}\n`);
    return 0;
  }
  erro(`saída inesperada de gh pr list: ${JSON.stringify(valor)}`);
  return 69;
}

// Lê a chave com `resolverConfig().valores`, NÃO com `ligado()`: `ligado()` devolve
// true em erro, e aqui o lado seguro é o merge NÃO autorizado. Erro = false.
function mergeAutorizado() {
  try {
    return resolverConfig({ projeto: toplevel() || undefined }).valores['fechar-mergear'] === true;
  } catch {
    return false;
  }
}

function esperarCi(pr) {
  const sem = exigirGithub();
  if (sem !== 0) return sem;

  const auth = executar('gh', ['auth', 'status']);
  if (auth.status !== 0) {
    erro('gh ausente ou sem auth: não dá para acompanhar o CI', auth.stderr);
    return 69;
  }

  const checks = executar('gh', ['pr', 'checks', String(pr), '--watch', '--interval', '20'], { stdio: 'inherit' });
  if (checks.status !== 0) {
    erro(`CI não verde no PR ${pr} (gh pr checks saiu ${checks.status}; "no checks reported" conta como não verde)`);
    return 5;
  }

  // O exit 0 do `gh pr checks` não prova verde: o gh 2.96 sai 0 com um check
  // CANCELLED (bucket `cancel`, impresso como `fail`), e um shard que estourou o
  // timeout-minutes virou "CI verde: merge autorizado" no PR #537. Só `pass` e
  // `skipping` contam; qualquer outro bucket, ou leitura que falha, não é verde.
  const lidos = executar('gh', ['pr', 'checks', String(pr), '--json', 'name,bucket']);
  let naoVerdes;
  try {
    const lista = JSON.parse(lidos.stdout);
    if (!Array.isArray(lista) || lista.length === 0) throw new Error('lista vazia');
    naoVerdes = lista.filter((c) => c.bucket !== 'pass' && c.bucket !== 'skipping');
  } catch {
    erro(`CI não verde no PR ${pr}: não deu para ler os checks em JSON`, lidos.stderr);
    return 5;
  }
  if (naoVerdes.length) {
    erro(`CI não verde no PR ${pr}: ${naoVerdes.map((c) => `${c.name} (${c.bucket})`).join(', ')}`);
    return 5;
  }

  if (!mergeAutorizado()) {
    process.stdout.write('CI verde: merge não autorizado (fechar-mergear desligada) — pare no PR aberto\n');
    return 7;
  }
  process.stdout.write(`CI verde: merge autorizado — rode gh pr merge ${pr} --squash\n`);
  return 0;
}

function esperar(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function confirmarMerge(pr) {
  const sem = exigirGithub();
  if (sem !== 0) return sem;

  const prazoEnv = Number(process.env.RFM_MERGE_PRAZO_S);
  const prazoS = prazoEnv > 0 ? prazoEnv : 60;
  const fim = Date.now() + prazoS * 1000;
  let ultimo = null;

  for (;;) {
    const v = executar('gh', ['pr', 'view', pr, '--json', 'state']);
    if (v.status !== 0) {
      erro(`gh pr view ${pr} falhou`, v.stderr);
      return 69;
    }
    let estado;
    try {
      estado = JSON.parse(v.stdout).state;
    } catch {
      erro(`saída ilegível de gh pr view: ${JSON.stringify(v.stdout)}`);
      return 69;
    }
    ultimo = estado;
    if (estado === 'MERGED') {
      process.stdout.write(`merge confirmado: PR ${pr} MERGED\n`);
      return 0;
    }
    if (estado === 'CLOSED') {
      process.stdout.write(`PR ${pr} fechado sem merge\n`);
      return 6;
    }
    const resta = fim - Date.now();
    if (resta <= 0) {
      process.stdout.write(`state do PR ${pr} não virou MERGED em ${prazoS} s (último: ${ultimo})\n`);
      return 6;
    }
    esperar(Math.min(5000, resta));
  }
}

function main(argv) {
  const lido = lerArgs(argv);
  if (!lido) {
    process.stderr.write(`${USO}\n`);
    return 1;
  }
  if (toplevel() === null) {
    erro('não é repositório git');
    return 69;
  }
  if (lido.sub === 'publicar') return publicar(lido.o.base);
  if (lido.sub === 'esperar-ci') return esperarCi(lido.o.pr);
  return confirmarMerge(lido.o.pr);
}

process.exitCode = main(process.argv.slice(2));
