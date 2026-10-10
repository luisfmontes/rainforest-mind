#!/usr/bin/env node
'use strict';
/* Bateria da Issue #450: o comando de regenerar que o `conferir-ponte` imprime tem
 * de rodar colado SEM EDICAO no repositorio-alvo, onde `scripts/ponte.cjs` nao existe.
 *
 * Cenario da issue, num `git init` temporario fora do plugin: gera a ponte do Codex,
 * edita uma linha do bloco gerado, roda o `conferir-ponte` (exit 2), extrai o comando
 * impresso, roda-o com cwd no alvo e confere de novo (exit 0). Vale para as tres
 * mensagens com comando de regenerar que dao para montar: editado a mao, SKILL.md que
 * andou (hash velho) e glossario que surgiu.
 *
 * O comando impresso e quebrado em argumentos respeitando aspas e rodado sem shell; o
 * primeiro argumento (`node`) vira `process.execPath`.
 * Placar: `N ok, M falha(s)`; exit 1 se alguma falhar.
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PONTE = path.join(__dirname, 'ponte.cjs');
const CONFERIR = path.join(__dirname, 'conferir-ponte.cjs');
const TIMEOUT_MS = 60000;
let ok = 0;
let falhas = 0;

function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`ok  ${nome}`); }
  else { falhas++; console.log(`FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 800)}` : ''}`); }
}

function rodar(args, cwd) {
  return spawnSync(process.execPath, args, { cwd, encoding: 'utf8', timeout: TIMEOUT_MS });
}

function caixa(nome, pai = os.tmpdir()) {
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(pai, `ponte-colado-${nome}-`)));
  spawnSync('git', ['init', '-q'], { cwd: dir, timeout: TIMEOUT_MS });
  const g = rodar([PONTE, '--alvo', dir, '--agente', 'codex', '--aplicar'], dir);
  if (g.status !== 0) throw new Error(`ponte.cjs falhou: ${g.stderr}`);
  return dir;
}

// Linha impressa `node "<...>/ponte.cjs" --alvo ... --aplicar` -> argumentos sem shell.
function comandoImpresso(saida) {
  const linha = saida.split('\n').map((l) => l.trim()).find((l) => /^node .*ponte\.cjs.* --aplicar$/.test(l));
  if (!linha) return null;
  const args = [...linha.matchAll(/'([^']*)'|(\S+)/g)].map((m) => (m[1] !== undefined ? m[1] : m[2]));
  return args[0] === 'node' ? args.slice(1) : null;
}

function cenario(nome, estragar) {
  const dir = caixa(nome);
  try {
    const agents = path.join(dir, 'AGENTS.md');
    estragar(dir, agents);
    const antes = rodar([CONFERIR, 'AGENTS.md'], dir);
    caso(`${nome}: conferir-ponte acusa (exit 2)`, antes.status === 2, `exit=${antes.status} ${antes.stdout}${antes.stderr}`);
    const args = comandoImpresso(antes.stdout || '');
    caso(`${nome}: imprime um comando node ... ponte.cjs ... --aplicar`, args !== null, antes.stdout);
    if (!args) return;
    caso(`${nome}: o ponte.cjs do comando e caminho absoluto que existe`,
      path.isAbsolute(args[0]) && fs.existsSync(args[0]), args[0]);
    const regen = rodar(args, dir);
    caso(`${nome}: o comando colado sem edicao no alvo sai 0`, regen.status === 0, `exit=${regen.status} ${regen.stderr}`);
    const depois = rodar([CONFERIR, 'AGENTS.md'], dir);
    caso(`${nome}: conferir-ponte seguinte sai 0`, depois.status === 0, `exit=${depois.status} ${depois.stdout}${depois.stderr}`);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

cenario('editado-a-mao', (dir, agents) => {
  const linhas = fs.readFileSync(agents, 'utf8').split('\n');
  const i = linhas.findIndex((l, n) => n > 2 && l.trim() !== '' && !l.startsWith('<!--'));
  linhas[i] = `${linhas[i]} (editado a mao)`;
  fs.writeFileSync(agents, linhas.join('\n'));
});

// SKILL.md que andou: hash do marcador velho E conteudo diferente (so o hash diferente,
// com o conteudo igual, o conferir-ponte aceita).
cenario('hash-velho', (dir, agents) => {
  const t = fs.readFileSync(agents, 'utf8').replace(/hash:[0-9a-f]+/, 'hash:0000000000000000');
  fs.writeFileSync(agents, t.replace('# rainforest-mind — ponte para o Codex', '# rainforest-mind — ponte antiga'));
});

cenario('glossario-surgiu', (dir) => {
  fs.writeFileSync(path.join(dir, 'GLOSSARIO.md'), '# Glossario\n');
});

// Revisao de seguranca do #450: diretorio com `$(...)` no nome. O comando impresso, colado
// no bash, nao pode executar o trecho: aspas simples sao literais.
{
  const pai = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'ponte-colado-pai-')));
  const isca = path.join(pai, 'PWNED');
  const estranho = path.join(pai, 'x$(touch PWNED)');
  fs.mkdirSync(estranho);
  try {
    const dir = caixa('injecao', estranho);
    fs.writeFileSync(path.join(dir, 'GLOSSARIO.md'), '# Glossario\n');
    const antes = rodar([CONFERIR, 'AGENTS.md'], dir);
    const linha = (antes.stdout || '').split('\n').map((l) => l.trim()).find((l) => /^node .*ponte\.cjs.* --aplicar$/.test(l));
    caso('injecao: imprime o comando com aspas simples, sem aspas duplas', !!linha && !linha.includes('"'), antes.stdout);
    if (linha) {
      const nodeBarras = process.execPath.split(path.sep).join('/');
      const r = spawnSync('bash', ['-c', linha.replace(/^node /, `'${nodeBarras}' `)], { cwd: pai, encoding: 'utf8', timeout: TIMEOUT_MS });
      caso('injecao: colado no bash, o $(...) do nome nao roda', !fs.existsSync(isca), `isca criada; exit=${r.status} ${r.stderr}`);
      caso('injecao: colado no bash, o comando sai 0', r.status === 0, `exit=${r.status} ${r.stderr}`);
    }
  } finally {
    fs.rmSync(pai, { recursive: true, force: true });
  }
}

console.log(`\n${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
