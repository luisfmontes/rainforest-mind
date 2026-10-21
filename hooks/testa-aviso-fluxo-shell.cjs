#!/usr/bin/env node
'use strict';
/* Bateria do aviso de código escrito pelo shell sem fluxo (Issue #564, D3 e D4 do design
 * docs/rainforest/design/2026-10-21-portaria-aviso-bash.md).
 *
 * Cada caso escreve no repositório de verdade (redirecionamento, edição de arquivo
 * rastreado) e roda o `aviso-fluxo-shell.cjs` como PROCESSO REAL, com o payload que o
 * harness manda no PostToolUse de Bash. Isolamento (regra 15): repositório git num
 * mkdtemp, `RFM_ROOT` e o diretório temporário do hook (onde ele guarda o conjunto)
 * dentro do sandbox, apagados ao fim.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const HOOK = path.join(__dirname, 'aviso-fluxo-shell.cjs');
const ESTADO = path.join(__dirname, '..', 'scripts', 'estado.cjs');
const TIMEOUT_MS = 60000;

let ok = 0;
let falhou = 0;
function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`  ok    ${nome}`); } else {
    falhou++; console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 600)}` : ''}`);
  }
}

function git(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', timeout: TIMEOUT_MS });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} falhou: ${r.stderr}`);
  return r.stdout;
}

const sandboxes = [];
// Repositório com `main`, um .sh rastreado e (com trilho) docs/rainforest/estado/.
function novoRepo({ trilho = true, branch = 'fluxo/teste' } = {}) {
  const sbx = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'aviso-shell-')));
  sandboxes.push(sbx);
  const repo = path.join(sbx, 'repo');
  const tmp = path.join(sbx, 'tmp');
  fs.mkdirSync(repo);
  fs.mkdirSync(tmp);
  git(repo, ['init', '-q']);
  git(repo, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  git(repo, ['config', 'user.email', 't@t']);
  git(repo, ['config', 'user.name', 'Test']);
  fs.writeFileSync(path.join(repo, 'a.sh'), 'echo a\n');
  git(repo, ['add', '.']);
  git(repo, ['commit', '-q', '-m', 'init']);
  if (branch !== 'main') git(repo, ['checkout', '-q', '-b', branch]);
  if (trilho) fs.mkdirSync(path.join(repo, 'docs', 'rainforest', 'estado'), { recursive: true });
  return { sbx, repo, tmp, dados: path.join(sbx, 'dados') };
}

function ambiente(r) {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: r.repo, RFM_ROOT: r.dados, TMP: r.tmp, TEMP: r.tmp, TMPDIR: r.tmp };
  delete env.RAINFOREST_GATE_OFF;
  delete env.RFM_ESTADO_ROOT;
  return env;
}

function rodar(r, extra = {}) {
  const payload = {
    session_id: 'sessao-shell', cwd: r.repo, hook_event_name: 'PostToolUse', tool_name: 'Bash',
    tool_input: { command: 'python patch.py' }, tool_response: { stdout: '', stderr: '' }, ...extra,
  };
  return spawnSync(process.execPath, [HOOK], { input: JSON.stringify(payload), encoding: 'utf8', env: ambiente(r), timeout: TIMEOUT_MS });
}

function estado(r, args) {
  return spawnSync(process.execPath, [ESTADO, ...args], { cwd: r.repo, encoding: 'utf8', env: { ...ambiente(r), RFM_ESTADO_ROOT: r.repo }, timeout: TIMEOUT_MS });
}

console.log('== A. rainforest sem fluxo aberto, branch de trabalho ==');
{
  const r = novoRepo();
  const limpo = rodar(r);
  caso('A1 arvore limpa: exit 0', limpo.status === 0, `exit=${limpo.status} stderr=${limpo.stderr}`);

  fs.writeFileSync(path.join(r.repo, 'x.py'), 'print(1)\n'); // o que `echo ... > x.py` deixa
  const novo = rodar(r);
  caso('A2 arquivo de codigo novo pelo shell: exit 2', novo.status === 2, `exit=${novo.status} stderr=${novo.stderr}`);
  caso('A2 o aviso nomeia o arquivo', /x\.py/.test(novo.stderr || ''), novo.stderr);
  caso('A2 o aviso diz que o comando ja rodou', /o comando já rodou e nada foi desfeito/.test(novo.stderr || ''), novo.stderr);
  caso('A2 o aviso traz a saida do leve com comando colavel', /estado\.cjs' leve --motivo/.test(novo.stderr || ''), novo.stderr);
  caso('A2 o aviso traz a saida de abrir o fluxo', /brainstorm/.test(novo.stderr || ''), novo.stderr);

  const repetido = rodar(r);
  caso('A3 segunda chamada sem mudanca nova: exit 0', repetido.status === 0, `exit=${repetido.status} stderr=${repetido.stderr}`);

  fs.writeFileSync(path.join(r.repo, 'a.sh'), 'echo b\n'); // o que `sed -i` deixa num rastreado
  const rastreado = rodar(r);
  caso('A4 arquivo rastreado editado pelo shell: exit 2', rastreado.status === 2, `exit=${rastreado.status} stderr=${rastreado.stderr}`);
  caso('A4 o aviso nomeia so o caminho novo (a.sh, nao x.py)',
    /a\.sh/.test(rastreado.stderr || '') && !/x\.py/.test(rastreado.stderr || ''), rastreado.stderr);

  fs.mkdirSync(path.join(r.repo, 'docs', 'ferramenta'), { recursive: true });
  fs.writeFileSync(path.join(r.repo, 'docs', 'ferramenta', 'z.js'), '1\n');
  const docs = rodar(r);
  caso('A5 codigo sob docs/: exit 0', docs.status === 0, `exit=${docs.status} stderr=${docs.stderr}`);

  fs.writeFileSync(path.join(r.repo, 'notas.txt'), 'x\n');
  const texto = rodar(r);
  caso('A6 extensao que nao e de codigo: exit 0', texto.status === 0, `exit=${texto.status} stderr=${texto.stderr}`);

  fs.writeFileSync(path.join(r.repo, 'y.ps1'), 'Write-Host 1\n');
  const sub = rodar(r, { agent_id: 'agente-1', agent_type: 'executor' });
  caso('A7 subagente: exit 0', sub.status === 0, `exit=${sub.status} stderr=${sub.stderr}`);
  const ps = rodar(r, { tool_name: 'PowerShell', tool_input: { command: 'Set-Content y.ps1 1' } });
  caso('A8 o mesmo caminho na sessao principal, pelo PowerShell: exit 2',
    ps.status === 2 && /y\.ps1/.test(ps.stderr || ''), `exit=${ps.status} stderr=${ps.stderr}`);

  const outra = rodar(r, { session_id: 'outra-sessao' });
  caso('A9 outra sessao sem conjunto guardado: o codigo ja sujo avisa uma vez',
    outra.status === 2 && /x\.py/.test(outra.stderr || ''), `exit=${outra.status} stderr=${outra.stderr}`);
}

console.log('== B. o que silencia ==');
{
  const r = novoRepo();
  fs.mkdirSync(path.join(r.repo, '.rainforest'));
  fs.writeFileSync(path.join(r.repo, '.rainforest', 'config.json'), JSON.stringify({ 'aviso-fluxo': false }));
  fs.writeFileSync(path.join(r.repo, 'x.py'), '1\n');
  const desligado = rodar(r);
  caso('B1 chave aviso-fluxo desligada: exit 0', desligado.status === 0, `exit=${desligado.status} stderr=${desligado.stderr}`);
}
{
  const r = novoRepo();
  const leve = estado(r, ['leve', '--motivo', 'hotfix de teste', '--repo', r.repo]);
  caso('B2 estado.cjs leve grava o caminho leve', leve.status === 0, `exit=${leve.status} ${leve.stdout} ${leve.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'x.py'), '1\n');
  const comLeve = rodar(r);
  caso('B2 branch com leve: exit 0', comLeve.status === 0, `exit=${comLeve.status} stderr=${comLeve.stderr}`);
}
{
  const r = novoRepo();
  // O sandbox e um checkout principal na branch de trabalho: a chave e o que o `iniciar` aceita ali.
  fs.mkdirSync(path.join(r.repo, '.rainforest'));
  fs.writeFileSync(path.join(r.repo, '.rainforest', 'config.json'), JSON.stringify({ 'principal-livre': true }));
  const ini = estado(r, ['iniciar', '--slug', '2026-10-21-teste', '--titulo', 'teste']);
  caso('B3 estado.cjs iniciar abre o fluxo da branch', ini.status === 0, `exit=${ini.status} ${ini.stdout} ${ini.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'x.py'), '1\n');
  const aberto = rodar(r);
  caso('B3 fluxo aberto na branch: exit 0', aberto.status === 0, `exit=${aberto.status} stderr=${aberto.stderr}`);
}
{
  const r = novoRepo({ trilho: false });
  fs.writeFileSync(path.join(r.repo, 'x.py'), '1\n');
  const semTrilho = rodar(r);
  caso('B4 repositorio sem trilho de fluxo: exit 0', semTrilho.status === 0, `exit=${semTrilho.status} stderr=${semTrilho.stderr}`);
}
{
  const r = novoRepo();
  const fora = rodar(r, { cwd: r.sbx });
  caso('B5 cwd fora de repo git: exit 0', fora.status === 0, `exit=${fora.status} stderr=${fora.stderr}`);
}

console.log('== D. codigo criado e commitado na mesma chamada ==');
{
  const r = novoRepo();
  const base = rodar(r);
  caso('D0 foto inicial com a arvore limpa: exit 0', base.status === 0, `exit=${base.status} stderr=${base.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'novo.py'), 'print(2)\n'); // `echo ... > novo.py && git commit`
  git(r.repo, ['add', 'novo.py']);
  git(r.repo, ['commit', '-q', '-m', 'novo']);
  const comitado = rodar(r);
  caso('D1 arquivo criado e commitado pelo shell, arvore limpa: exit 2',
    comitado.status === 2 && /novo\.py/.test(comitado.stderr || ''), `exit=${comitado.status} stderr=${comitado.stderr}`);
  const repetido = rodar(r);
  caso('D2 chamada seguinte sem commit novo: exit 0', repetido.status === 0, `exit=${repetido.status} stderr=${repetido.stderr}`);

  // O que chega por pull e trabalho alheio, mesmo com data de commit recente: o reflog o
  // registra como `pull`, nao como `commit`.
  const colega = path.join(r.sbx, 'colega');
  git(r.sbx, ['clone', '-q', '-b', 'fluxo/teste', r.repo, colega]);
  git(colega, ['config', 'user.email', 'c@c']);
  git(colega, ['config', 'user.name', 'Colega']);
  fs.writeFileSync(path.join(colega, 'colega.py'), 'print(3)\n');
  git(colega, ['add', 'colega.py']);
  git(colega, ['commit', '-q', '-m', 'colega']);
  git(r.repo, ['pull', '-q', '--ff-only', colega, 'fluxo/teste']);
  const puxado = rodar(r);
  caso('D3 commit recente de outro clone trazido por git pull: exit 0',
    puxado.status === 0, `exit=${puxado.status} stderr=${puxado.stderr}`);

  fs.mkdirSync(path.join(r.repo, 'docs', 'x'), { recursive: true });
  fs.writeFileSync(path.join(r.repo, 'docs', 'x', 'y.js'), '1\n');
  fs.writeFileSync(path.join(r.repo, 'leia.txt'), '1\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'doc']);
  const doc = rodar(r);
  caso('D4 commit so com docs/ e texto: exit 0', doc.status === 0, `exit=${doc.status} stderr=${doc.stderr}`);

  // Pasta com acento, como as dos repositorios Protheus: o git cita o nome se nao for lido com -z.
  fs.mkdirSync(path.join(r.repo, 'Gestão'));
  fs.writeFileSync(path.join(r.repo, 'Gestão', 'Contrato.prw'), 'User Function X()\nReturn\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'acento']);
  const acento = rodar(r);
  caso('D5 codigo em pasta com acento criado e commitado na mesma chamada: exit 2',
    acento.status === 2 && /Gestão\/Contrato\.prw/.test(acento.stderr || ''), `exit=${acento.status} stderr=${acento.stderr}`);
}
{
  const r = novoRepo();
  rodar(r);
  fs.writeFileSync(path.join(r.repo, 'z.py'), 'print(1)\n');
  const sujo = rodar(r);
  caso('D6 z.py novo e sujo avisa: exit 2', sujo.status === 2 && /z\.py/.test(sujo.stderr || ''), `exit=${sujo.status} stderr=${sujo.stderr}`);
  git(r.repo, ['add', 'z.py']);
  git(r.repo, ['commit', '-q', '-m', 'z']);
  const comitado = rodar(r);
  caso('D6 o mesmo z.py commitado depois nao reavisa: exit 0', comitado.status === 0, `exit=${comitado.status} stderr=${comitado.stderr}`);
  git(r.repo, ['commit', '-q', '--amend', '-m', 'z2']);
  const emendado = rodar(r);
  caso('D6 commit --amend do mesmo z.py nao reavisa: exit 0', emendado.status === 0, `exit=${emendado.status} stderr=${emendado.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'z.py'), 'print(2)\n');
  git(r.repo, ['commit', '-q', '-am', 'z de novo']);
  const deNovo = rodar(r);
  caso('D7 z.py ja visto, mexido e commitado na mesma chamada, nao reavisa: exit 0',
    deNovo.status === 0, `exit=${deNovo.status} stderr=${deNovo.stderr}`);
}

console.log('== E. trabalho alheio e commit de antes da sessao ==');
{
  // Merge com conflito: o arquivo que chega da outra branch fica staged ate o commit.
  const r = novoRepo();
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 0\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'base']);
  git(r.repo, ['checkout', '-q', '-b', 'al']);
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 2\n');
  fs.writeFileSync(path.join(r.repo, 'alheio.py'), 'print(9)\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'al']);
  git(r.repo, ['checkout', '-q', 'fluxo/teste']);
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 1\n');
  git(r.repo, ['commit', '-q', '-am', 'meu']);
  rodar(r);
  spawnSync('git', ['merge', '-q', 'al'], { cwd: r.repo, encoding: 'utf8' }); // conflito em conf.py
  const conflito = rodar(r);
  caso('E1 merge em conflito: o arquivo alheio staged nao avisa (exit 0)',
    conflito.status === 0, `exit=${conflito.status} stderr=${conflito.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 3\n');
  git(r.repo, ['add', 'conf.py']);
  git(r.repo, ['commit', '-q', '--no-edit']);
  const resolvido = rodar(r);
  caso('E2 commit que resolve o merge nao avisa o alheio depois (exit 0)',
    resolvido.status === 0, `exit=${resolvido.status} stderr=${resolvido.stderr}`);
}
{
  // Commit de antes da sessao emendado so na mensagem: nenhum codigo novo.
  const r = novoRepo();
  fs.writeFileSync(path.join(r.repo, 'anterior.py'), 'print(1)\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'anterior']);
  rodar(r);
  git(r.repo, ['commit', '-q', '--amend', '-m', 'mensagem corrigida']);
  const soMensagem = rodar(r);
  caso('E3 --amend so da mensagem de commit anterior a sessao: exit 0',
    soMensagem.status === 0, `exit=${soMensagem.status} stderr=${soMensagem.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'emenda.py'), 'print(2)\n');
  git(r.repo, ['add', 'emenda.py']);
  git(r.repo, ['commit', '-q', '--amend', '--no-edit']);
  const comCodigo = rodar(r);
  caso('E4 --amend que acrescenta codigo avisa so o acrescentado',
    comCodigo.status === 2 && /emenda\.py/.test(comCodigo.stderr || '') && !/anterior\.py/.test(comCodigo.stderr || ''),
    `exit=${comCodigo.status} stderr=${comCodigo.stderr}`);
}

console.log('== F. rearranjo de commits de antes da sessao e rebase ==');
{
  // Squash por reset --soft: o codigo ja existia na foto, nada novo.
  const r = novoRepo();
  for (const n of ['p1', 'p2']) {
    fs.writeFileSync(path.join(r.repo, `${n}.py`), `print("${n}")\n`);
    git(r.repo, ['add', '.']);
    git(r.repo, ['commit', '-q', '-m', n]);
  }
  rodar(r);
  git(r.repo, ['reset', '-q', '--soft', 'HEAD~2']);
  git(r.repo, ['commit', '-q', '-m', 'squash']);
  const squash = rodar(r);
  caso('F1 reset --soft HEAD~2 e commit de codigo de antes da sessao: exit 0',
    squash.status === 0, `exit=${squash.status} stderr=${squash.stderr}`);
}
{
  // Rebase em conflito: os commits reaplicados ficam staged com o HEAD destacado.
  const r = novoRepo();
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 0\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'base']);
  git(r.repo, ['branch', 'outra']);
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 1\n');
  fs.writeFileSync(path.join(r.repo, 'pre.py'), 'print(1)\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'meu']);
  git(r.repo, ['checkout', '-q', 'outra']);
  fs.writeFileSync(path.join(r.repo, 'conf.py'), 'a = 2\n');
  git(r.repo, ['commit', '-q', '-am', 'deles']);
  git(r.repo, ['checkout', '-q', 'fluxo/teste']);
  rodar(r);
  const reb = spawnSync('git', ['rebase', 'outra'], { cwd: r.repo, encoding: 'utf8' });
  caso('F2 preparo: o rebase parou em conflito', reb.status !== 0, `exit=${reb.status} ${reb.stdout} ${reb.stderr}`);
  const conflito = rodar(r);
  caso('F2 rebase em conflito: o codigo de antes da sessao staged nao avisa (exit 0)',
    conflito.status === 0, `exit=${conflito.status} stderr=${conflito.stderr}`);
  spawnSync('git', ['rebase', '--abort'], { cwd: r.repo, encoding: 'utf8' });
}
{
  // merge --squash de branch alheia deixa o codigo dela staged, sem MERGE_HEAD.
  const r = novoRepo();
  git(r.repo, ['checkout', '-q', '-b', 'al']);
  fs.writeFileSync(path.join(r.repo, 'colega.py'), 'print(5)\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'colega']);
  git(r.repo, ['checkout', '-q', 'fluxo/teste']);
  rodar(r);
  git(r.repo, ['merge', '-q', '--squash', 'al']);
  const squashMerge = rodar(r);
  caso('F3 merge --squash de branch alheia: exit 0', squashMerge.status === 0, `exit=${squashMerge.status} stderr=${squashMerge.stderr}`);
}
{
  // Remocao de arquivo rastreado avisa como codigo mexido.
  const r = novoRepo();
  rodar(r);
  fs.rmSync(path.join(r.repo, 'a.sh'));
  const rm = rodar(r);
  caso('F4 rm de arquivo de codigo rastreado avisa: exit 2 nomeando a.sh',
    rm.status === 2 && /a\.sh/.test(rm.stderr || ''), `exit=${rm.status} stderr=${rm.stderr}`);
  caso('F4 o aviso diz "código novo ou mexido"', /há código novo ou mexido/.test(rm.stderr || ''), rm.stderr);
}

{
  // `git reset HEAD~1` (mixed) desfaz um commit de antes da sessao: o arquivo volta como nao
  // rastreado, com o mesmo conteudo que tinha no HEAD da foto.
  const r = novoRepo();
  fs.writeFileSync(path.join(r.repo, 'p1.py'), 'print("p1")\n');
  git(r.repo, ['add', '.']);
  git(r.repo, ['commit', '-q', '-m', 'p1']);
  rodar(r);
  git(r.repo, ['reset', '-q', 'HEAD~1']);
  const desfeito = rodar(r);
  caso('F5 git reset HEAD~1 de commit de antes da sessao: exit 0', desfeito.status === 0, `exit=${desfeito.status} stderr=${desfeito.stderr}`);
  fs.writeFileSync(path.join(r.repo, 'p1.py'), 'print("p1 mexido")\n');
  const mexido = rodar(r);
  caso('F5 o mesmo p1.py ja visto e mexido depois nao reavisa (limite aceito): exit 0',
    mexido.status === 0, `exit=${mexido.status} stderr=${mexido.stderr}`);
}

console.log('== G. foto adulterada ==');
{
  // A foto mora no diretorio temporario: um HEAD que nao e hash nao pode virar opcao do git.
  const r = novoRepo();
  rodar(r);
  const top = path.resolve(git(r.repo, ['rev-parse', '--show-toplevel']).trim());
  const chave = require('crypto').createHash('sha1').update(`sessao-shell\n${top.toLowerCase()}`).digest('hex').slice(0, 16);
  const foto = path.join(r.tmp, 'rainforest-aviso-shell', `${chave}.json`);
  caso('G0 a foto da sessao existe onde o hook a grava', fs.existsSync(foto), foto);
  const alvo = path.join(r.sbx, 'injetado.txt');
  fs.writeFileSync(foto, JSON.stringify({ caminhos: [], head: `--output=${alvo}`, ts: Math.floor(Date.now() / 1000) }));
  fs.writeFileSync(path.join(r.repo, 'g.py'), '1\n');
  const adulterada = rodar(r);
  caso('G1 HEAD da foto que nao e hash: a opcao injetada nao age', !fs.existsSync(alvo), `existe=${fs.existsSync(alvo)}`);
  caso('G1 e o codigo novo segue avisando', adulterada.status === 2 && /g\.py/.test(adulterada.stderr || ''), `exit=${adulterada.status} stderr=${adulterada.stderr}`);
}

console.log('== C. branch padrao ==');
{
  const r = novoRepo({ branch: 'main' });
  fs.writeFileSync(path.join(r.repo, 'x.py'), '1\n');
  const padrao = rodar(r);
  caso('C1 codigo novo na main sem fluxo: exit 2', padrao.status === 2, `exit=${padrao.status} stderr=${padrao.stderr}`);
  caso('C1 na branch padrao o aviso manda para o worktree, sem oferecer o leve',
    /git worktree add/.test(padrao.stderr || '') && !/leve --motivo/.test(padrao.stderr || ''), padrao.stderr);
}

for (const s of sandboxes) fs.rmSync(s, { recursive: true, force: true });
console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou === 0 ? 0 : 1);
