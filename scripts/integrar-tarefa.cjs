#!/usr/bin/env node
// @categoria: sensor
'use strict';
/**
 * Integra UMA tarefa de um fluxo num comando só (D7 do design 2026-10-13-executar-autonomo).
 *
 * POR QUE EXISTE. No `executar-dag-painel`, a integração era montada à mão pela sessão:
 * regex sem escape, mensagem barrada pelo gate, mutação morta no teto. Aqui a sequência
 * inteira mora num script, na ordem fixa abaixo, e o script responde aceito ou recusado.
 *
 * ORDEM FIXA. Cada passo só roda se o anterior passou:
 *   1. conferir-entrega, com o `arquivos:` da tarefa como escopo;
 *   2. git cherry-pick --no-commit do HEAD do worktree do agente;
 *   3. conferir-fluxo mutacoes --tarefa N (a bateria precisa ficar vermelha);
 *   4. git commit com o trailer `Rainforest-Tarefa: <slug>#<N>`;
 *   5. estado marcar executar parcial, com integradas e em_voo sem a tarefa N;
 *   6. remoção do worktree do agente e da branch dele.
 *
 * RECUSA. Um passo que reprova desfaz o que trouxe (passos 2 e 3) e não commita. Nenhum
 * commit sai de uma entrega que o conferir-entrega recusou, nem de uma cuja mutação
 * sobreviveu.
 *
 * Uso:
 *   node scripts/integrar-tarefa.cjs --slug <s> --tarefa <N> --worktree <dir> --base <h> \
 *        --head-antes <h0> --sujo-antes <arq> --titulo "<t>" [--repo-principal <dir>]
 *
 * --repo-principal é o checkout de onde saíram --head-antes e --sujo-antes. Sem a flag,
 * vale o checkout principal do repositório (o pai do git-common-dir), nunca o worktree do
 * fluxo: arquivo sujo no worktree do fluxo não é sujeira do principal.
 *
 * Exit:
 *   0   aceito (commit feito, estado marcado, worktree do agente removido)
 *   2   recusado no passo indicado; o stderr traz o passo e a saída dele
 *   69  nao-verificavel: falta ambiente (worktree sumiu, não é repositório git, ou o
 *       marcar falhou depois do commit)
 *   1   erro de uso
 *
 * Saída: uma linha JSON em stdout, {"tarefa":N,"resultado":"aceito|recusado","passo":"...","commit":"<hash>|null"}.
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const { caminhoDoc } = require(path.join(__dirname, '..', 'hooks', 'lib', 'pastas-docs.cjs'));
const { extrairTarefas, lerMarkdown } = require(path.join(__dirname, 'conferir-fluxo.cjs'));

const CWD = process.cwd();
const GIT = caminhoExecutavel('git');
const NODE = process.execPath;

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) {
    console.error(`erro: falta --${nome}`);
    process.exit(1);
  }
  return process.argv[i + 1];
}

function git(args, cwd = CWD) {
  return spawnSync(GIT, args, { cwd, encoding: 'utf8', stdio: 'pipe' });
}

function saidaGit(args, cwd = CWD) {
  const r = git(args, cwd);
  return r.status === 0 ? r.stdout.trim() : null;
}

function rodar(script, args) {
  return spawnSync(NODE, [path.join(__dirname, script), ...args], { cwd: CWD, encoding: 'utf8', stdio: 'pipe' });
}

function ambiente(motivo) {
  console.error(`nao-verificavel: ${motivo}`);
  process.exit(69);
}

// Desfaz o que o cherry-pick trouxe: arquivo novo sai do índice e do disco; arquivo
// modificado ou apagado volta ao HEAD, índice e árvore.
function desfazer(trazidos, topo) {
  for (const t of trazidos) {
    if (t.status === 'A') {
      git(['rm', '-q', '--cached', '-f', '--', t.arquivo], topo);
      fs.rmSync(path.join(topo, t.arquivo), { force: true });
    } else {
      git(['restore', '--source=HEAD', '--staged', '--worktree', '--', t.arquivo], topo);
    }
  }
}

// Lê o estado pelo mesmo caminho que o estado.cjs usa (RFM_ESTADO_ROOT, depois CLAUDE_PROJECT_DIR).
function emVooDoEstado(slug) {
  const raiz = process.env.RFM_ESTADO_ROOT || process.env.CLAUDE_PROJECT_DIR || CWD;
  const arq = path.join(raiz, 'docs', 'rainforest', 'estado', `${slug}.json`);
  if (!fs.existsSync(arq)) return [];
  const estado = JSON.parse(fs.readFileSync(arq, 'utf8'));
  return Array.isArray(estado.executar && estado.executar.em_voo) ? estado.executar.em_voo : [];
}

function main() {
  const slug = arg('slug');
  const tarefaArg = arg('tarefa');
  const worktree = arg('worktree');
  const base = arg('base');
  const headAntes = arg('head-antes');
  const sujoAntes = arg('sujo-antes');
  const titulo = arg('titulo');
  const iRp = process.argv.indexOf('--repo-principal');
  const repoPrincipalArg = iRp !== -1 && iRp + 1 < process.argv.length ? process.argv[iRp + 1] : null;

  if (!/^[1-9][0-9]*$/.test(tarefaArg)) {
    console.error('erro: --tarefa precisa ser inteiro positivo');
    process.exit(1);
  }
  const numero = Number(tarefaArg);

  const topo = saidaGit(['rev-parse', '--show-toplevel']);
  if (topo === null) ambiente(`${CWD} não é repositório git`);
  if (!fs.existsSync(worktree)) ambiente(`worktree do agente não existe: ${worktree}`);
  const agenteHead = saidaGit(['rev-parse', 'HEAD'], worktree);
  if (agenteHead === null) ambiente(`${worktree} não é worktree git`);
  const comum = saidaGit(['rev-parse', '--path-format=absolute', '--git-common-dir'], topo);
  if (comum === null) ambiente('não consegui achar o checkout principal (git-common-dir)');
  const repoPrincipal = repoPrincipalArg || path.dirname(comum);

  const recusar = (passo, res, trazidos = null) => {
    if (trazidos) desfazer(trazidos, topo);
    console.error(`RECUSADO: ${passo}`);
    if (res && res.stdout) process.stderr.write(res.stdout);
    if (res && res.stderr) process.stderr.write(res.stderr);
    console.log(JSON.stringify({ tarefa: numero, resultado: 'recusado', passo, commit: null }));
    process.exit(2);
  };

  const plano = path.join(topo, caminhoDoc('planos', slug, { raiz: topo }));
  const conteudo = lerMarkdown(plano);
  if (!conteudo) return recusar('plano', { stderr: `plano não existe: ${plano}\n` });
  const tarefa = extrairTarefas(conteudo).find((t) => t.numero === numero);
  if (!tarefa) return recusar('tarefa', { stderr: `o plano não tem a tarefa ${numero}\n` });
  if (!tarefa.arquivos || tarefa.arquivos.length === 0) {
    return recusar('escopo', { stderr: `tarefa ${numero} sem arquivos: declarados\n` });
  }

  // 1. conferir-entrega, com o arquivos: da tarefa como escopo.
  const escopo = tarefa.arquivos.flatMap((a) => ['--escopo', a]);
  const entrega = spawnSync(NODE, [
    path.join(__dirname, 'conferir-entrega.cjs'),
    '--worktree', worktree,
    '--base', base,
    '--repo-principal', repoPrincipal,
    '--head-antes', headAntes,
    '--sujo-antes', sujoAntes,
    ...escopo,
  ], { cwd: topo, encoding: 'utf8', stdio: 'pipe' });
  if (entrega.status === 69) {
    process.stderr.write(entrega.stderr);
    process.exit(69);
  }
  if (entrega.status !== 0) return recusar('conferir-entrega', entrega);

  // 2. Traz o commit do agente para o índice, sem commitar.
  const cp = git(['cherry-pick', '--no-commit', agenteHead], topo);
  if (cp.status !== 0) {
    git(['cherry-pick', '--abort'], topo);
    return recusar('cherry-pick', cp);
  }
  const trazidos = saidaGit(['diff', '--cached', '--no-renames', '--name-status'], topo)
    .split('\n').filter(Boolean).map((linha) => {
      const [status, arquivo] = linha.split('\t');
      return { status, arquivo };
    });

  // 3. Mutação: a bateria da tarefa tem de ficar vermelha com o trecho invertido.
  const mut = rodar('conferir-fluxo.cjs', [
    'mutacoes', '--slug', slug, '--tarefa', tarefaArg,
    '--raiz-codigo', topo, '--plano', plano,
  ]);
  if (mut.status !== 0) return recusar('mutacao', mut, trazidos);

  // 4. Commit com o trailer da tarefa.
  const corpo = `Integra a tarefa ${numero} do fluxo ${slug}, trazida do worktree do agente.\n\n`
    + 'A entrega passou pelo conferir-entrega (escopo: arquivos: da tarefa) e pela mutação '
    + `da tarefa ${numero}: a bateria ficou vermelha com o trecho invertido.`;
  const commit = git(['commit', '-m', titulo, '-m', corpo, '--trailer', `Rainforest-Tarefa: ${slug}#${numero}`], topo);
  if (commit.status !== 0) return recusar('commit', commit, trazidos);
  const hash = saidaGit(['rev-parse', 'HEAD'], topo);

  // 5. Marca a tarefa como integrada e tira ela do em_voo.
  const restantes = emVooDoEstado(slug).filter((a) => Number.parseInt(String(a && a.tarefa), 10) !== numero);
  const json = JSON.stringify({ integradas: [numero], em_voo: restantes });
  const marc = rodar('estado.cjs', ['marcar', '--slug', slug, '--estagio', 'executar', '--status', 'parcial', '--json', json]);
  if (marc.status !== 0) {
    process.stderr.write(marc.stderr);
    ambiente(`commit ${hash} feito, mas o marcar falhou; a tarefa ${numero} ficou sem marca`);
  }

  // 6. Remove o worktree do agente e a branch dele.
  const branchAgente = saidaGit(['rev-parse', '--abbrev-ref', 'HEAD'], worktree);
  const branchFluxo = saidaGit(['rev-parse', '--abbrev-ref', 'HEAD'], topo);
  console.log(JSON.stringify({ tarefa: numero, resultado: 'aceito', passo: 'integrada', commit: hash }));
  const rem = git(['worktree', 'remove', '--force', worktree], topo);
  if (rem.status !== 0) {
    process.stderr.write(rem.stderr);
    ambiente(`tarefa ${numero} integrada, mas o worktree ${worktree} não saiu`);
  }
  if (branchAgente && branchAgente !== 'HEAD' && branchAgente !== branchFluxo && branchAgente !== 'main') {
    git(['branch', '-D', branchAgente], topo);
  }
  process.exit(0);
}

if (require.main === module) main();
