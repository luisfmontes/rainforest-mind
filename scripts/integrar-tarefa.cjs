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
 *   2. git apply --index do diff base..HEAD do agente (todos os commits dele, de uma vez;
 *      o apply é atômico: se não encaixa, nada entra no índice nem no disco);
 *   3. conferir-fluxo mutacoes --tarefa N (a bateria precisa ficar vermelha);
 *   4. git commit com o trailer `Rainforest-Tarefa: <slug>#<N>`;
 *   5. estado marcar executar parcial, com integradas e em_voo sem a tarefa N;
 *   6. remoção do worktree do agente e da branch dele.
 *
 * RECUSA. Um passo que reprova desfaz o que trouxe (passos 2 e 3) e não commita. Nenhum
 * commit sai de uma entrega que o conferir-entrega recusou, nem de uma cuja mutação
 * sobreviveu. Índice já com stage no worktree do fluxo é recusado antes do passo 2, para
 * que o commit leve só o que veio do agente.
 *
 * RETOMADA. Se a branch do fluxo já tem, depois da --base, um commit com o trailer da tarefa
 * (o marcar falhou numa chamada anterior), os passos 1 a 4 são pulados e o script segue do 5.
 * Com o worktree do agente presente, a entrega dele tem de já estar no HEAD (apply --check
 * -R); se não estiver, recusa no passo `retomada`. Sem o worktree, retoma do mesmo jeito.
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
 *   0   aceito (commit feito e estado marcado; se o worktree do agente não saiu, o JSON
 *       traz "worktree_removido":false e o stderr diz por quê)
 *   2   recusado no passo indicado; o stderr traz o passo e a saída dele
 *   69  nao-verificavel: falta ambiente (worktree sumiu fora da retomada, não é repositório
 *       git, ou o marcar falhou depois do commit; rodar de novo retoma do marcar)
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

// Desfaz o que o apply trouxe: arquivo novo sai do índice e do disco, junto com as pastas que
// ficarem vazias; arquivo modificado ou apagado volta ao HEAD, índice e árvore.
function desfazer(trazidos, topo) {
  for (const t of trazidos) {
    if (t.status === 'A') {
      git(['rm', '-q', '--cached', '-f', '--', t.arquivo], topo);
      fs.rmSync(path.join(topo, t.arquivo), { force: true });
      for (let dir = path.dirname(path.join(topo, t.arquivo)); path.relative(topo, dir) && !path.relative(topo, dir).startsWith('..'); dir = path.dirname(dir)) {
        try { fs.rmdirSync(dir); } catch { break; }
      }
    } else {
      git(['restore', '--source=HEAD', '--staged', '--worktree', '--', t.arquivo], topo);
    }
  }
}

// Commit da branch do fluxo, feito DEPOIS da base do briefing, que já carrega o trailer
// desta tarefa, ou null. Só depois da base: um redespacho da mesma tarefa no laço nasce do
// HEAD novo, e o commit da integração anterior fica antes da base dele.
function commitDaTarefa(slug, numero, base, topo) {
  const log = saidaGit(['log', '--format=%H %(trailers:key=Rainforest-Tarefa,valueonly,separator=%x2C)', `${base}..HEAD`], topo);
  if (!log) return null;
  for (const linha of log.split(/\r?\n/)) {
    const [hash, valores = ''] = linha.split(' ');
    if (valores.split(',').map((v) => v.trim()).includes(`${slug}#${numero}`)) return hash;
  }
  return null;
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

  // Retomada vem antes da checagem do worktree: depois de um 69 no marcar, o worktree do
  // agente pode já ter sido removido à mão.
  let agenteHead = null;
  let hash = commitDaTarefa(slug, numero, base, topo);
  if (hash) {
    // O trailer sozinho não prova que ESTE trabalho do agente entrou (base velha, fluxo
    // rebaseado). Com o worktree presente, o diff do agente tem de já estar no HEAD; se não
    // estiver, recusa e o worktree fica, porque o passo 6 o apagaria com a correção dentro.
    if (fs.existsSync(worktree)) {
      const head = saidaGit(['rev-parse', 'HEAD'], worktree);
      const d = head && git(['diff', '--binary', '--no-renames', base, head], topo);
      if (!d || d.status !== 0) {
        return recusar('retomada', { stderr: `não consegui ler o diff ${base}..${head} do agente\n` });
      }
      if (d.stdout.trim()) {
        const dir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'integrar-'));
        const remendo = path.join(dir, 'entrega.patch');
        fs.writeFileSync(remendo, d.stdout);
        const contido = git(['apply', '--check', '-R', '--cached', remendo], topo);
        fs.rmSync(dir, { recursive: true, force: true });
        if (contido.status !== 0) {
          return recusar('retomada', { stderr: `o commit ${hash} tem o trailer da tarefa ${numero}, mas a entrega do agente não está no HEAD; confira a --base\n` });
        }
      }
    }
    console.error(`retomada: a branch já tem o commit ${hash} da tarefa ${numero}; seguindo do marcar`);
  } else {
    if (!fs.existsSync(worktree)) ambiente(`worktree do agente não existe: ${worktree}`);
    agenteHead = saidaGit(['rev-parse', 'HEAD'], worktree);
    if (agenteHead === null) ambiente(`${worktree} não é worktree git`);
    hash = integrarCommit();
  }

  function integrarCommit() {
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

  // O commit tem de levar só o que veio do agente: índice com stage prévio é recusado.
  const indice = git(['diff', '--cached', '--quiet'], topo);
  if (indice.status !== 0) {
    return recusar('indice-sujo', { stderr: `o índice do worktree do fluxo já tem stage; o commit levaria junto:\n${saidaGit(['diff', '--cached', '--name-status'], topo)}\n` });
  }
  if (git(['merge-base', '--is-ancestor', base, agenteHead], topo).status !== 0) {
    return recusar('base', { stderr: `a base ${base} não é ancestral do HEAD do agente ${agenteHead}\n` });
  }

  // 2. Traz TODOS os commits do agente (base..HEAD) para o índice e o disco, sem commitar.
  // O apply é atômico: se algum trecho não encaixa, nada é escrito.
  const diff = git(['diff', '--binary', '--no-renames', base, agenteHead], topo);
  if (diff.status !== 0) return recusar('diff', diff);
  const remendo = path.join(fs.mkdtempSync(path.join(require('os').tmpdir(), 'integrar-')), 'entrega.patch');
  fs.writeFileSync(remendo, diff.stdout);
  const ap = git(['apply', '--index', '--binary', remendo], topo);
  fs.rmSync(path.dirname(remendo), { recursive: true, force: true });
  if (ap.status !== 0) return recusar('apply', ap);
  // -z: caminho com acento ou espaço vem cru, sem as aspas e os escapes octais do git.
  const campos = (git(['diff', '--cached', '--no-renames', '--name-status', '-z'], topo).stdout || '').split('\0');
  const trazidos = [];
  for (let i = 0; i + 1 < campos.length; i += 2) {
    if (campos[i]) trazidos.push({ status: campos[i], arquivo: campos[i + 1] });
  }

  // 3. Mutação: a bateria da tarefa tem de ficar vermelha com o trecho invertido.
  const mut = rodar('conferir-fluxo.cjs', [
    'mutacoes', '--slug', slug, '--tarefa', tarefaArg,
    '--raiz-codigo', topo, '--plano', plano,
  ]);
  if (mut.status !== 0) return recusar('mutacao', mut, trazidos);

  // 4. Commit com o trailer da tarefa.
  const corpo = `Integra a tarefa ${numero} do fluxo ${slug}, trazida do worktree do agente.\n\n`
    +'A entrega passou pelo conferir-entrega (escopo: arquivos: da tarefa) e pela mutação '
    + `da tarefa ${numero}: a bateria ficou vermelha com o trecho invertido.`;
  const commit = git(['commit', '-m', titulo, '-m', corpo, '--trailer', `Rainforest-Tarefa: ${slug}#${numero}`], topo);
  if (commit.status !== 0) return recusar('commit', commit, trazidos);
  return saidaGit(['rev-parse', 'HEAD'], topo);
  }

  // 5. Marca a tarefa como integrada e tira ela do em_voo.
  const restantes = emVooDoEstado(slug).filter((a) => Number.parseInt(String(a && a.tarefa), 10) !== numero);
  const json = JSON.stringify({ integradas: [numero], em_voo: restantes });
  const marc = rodar('estado.cjs', ['marcar', '--slug', slug, '--estagio', 'executar', '--status', 'parcial', '--json', json]);
  if (marc.status !== 0) {
    process.stderr.write(marc.stderr);
    ambiente(`commit ${hash} feito, mas o marcar falhou; a tarefa ${numero} ficou sem marca`);
  }

  // 6. Remove o worktree do agente e a branch dele. A tarefa já está integrada: falha aqui
  // é aviso, não parada.
  if (!fs.existsSync(worktree)) {
    // Sem o worktree não há como saber o nome da branch do agente: fica para remoção por nome.
    console.error(`aviso: o worktree ${worktree} já não existia; se a branch do agente sobrou, apague-a por nome`);
    console.log(JSON.stringify({ tarefa: numero, resultado: 'aceito', passo: 'integrada', commit: hash, worktree_removido: true }));
    process.exit(0);
  }
  const branchAgente = saidaGit(['rev-parse', '--abbrev-ref', 'HEAD'], worktree);
  const branchFluxo = saidaGit(['rev-parse', '--abbrev-ref', 'HEAD'], topo);
  const rem = git(['worktree', 'remove', '--force', worktree], topo);
  const removido = rem.status === 0;
  if (!removido) {
    process.stderr.write(rem.stderr);
    console.error(`aviso: tarefa ${numero} integrada, mas o worktree ${worktree} não saiu; remova por caminho`);
  } else if (branchAgente && branchAgente !== 'HEAD' && branchAgente !== branchFluxo && branchAgente !== 'main') {
    git(['branch', '-D', branchAgente], topo);
  }
  console.log(JSON.stringify({ tarefa: numero, resultado: 'aceito', passo: 'integrada', commit: hash, worktree_removido: removido }));
  process.exit(0);
}

if (require.main === module) main();
