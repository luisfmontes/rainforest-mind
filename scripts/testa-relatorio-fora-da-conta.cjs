#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria do relatorio sem o que nao foi medido (D3 de
 * docs/rainforest/design/2026-10-09-assunto-regua.md; tarefa 7 do plano
 * docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * A servida de nota nula (toda a memoria estava no pedido) nao entra nem no numerador nem no
 * denominador da regua D7 e do relatorio por canal; o relatorio diz quantas ficaram de fora.
 * O inicio da janela da regua continua contando a servida nula (o canal estava vivo desde
 * aquela sessao).
 *
 * A caixa nasce do `criarSchema` real, em pasta temporaria, povoada como em `bancoRegua` de
 * scripts/testa-utilidade-canais.sh (mesmo dia 2026-10-09, `pontuada_em` crescente, a primeira
 * servida no canal pedido). O relatorio sai pelo comando real
 * `RFM_ROOT=<caixa> node scripts/memoria.cjs utilidade --relatorio`. Nunca toca ~/.rainforest.
 * Nenhum caso le o texto do fonte.
 *
 * Uso: node scripts/testa-relatorio-fora-da-conta.cjs
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const { criarSchema } = require(path.join(SRC, 'scripts', 'memoria.cjs'));

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHA  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const CAIXA = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-relatorio-fora-')));

// servidas: lista de [canal, nota]; nota null = nao medida
function bancoCom(nome, sessoes) {
  const dir = path.join(CAIXA, nome);
  fs.mkdirSync(dir, { recursive: true });
  const b = new DatabaseSync(path.join(dir, 'rainforest.db'));
  criarSchema(b);
  const iU = b.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal) VALUES (?,?,?,?,?,?,?)');
  const iS = b.prepare('INSERT INTO uso_memoria_sessoes (sessao, pontuada_em, buscas_principal, buscas_subagente, subagentes) VALUES (?,?,?,?,?)');
  sessoes.forEach(([nomeSessao, servidas], i) => {
    const t = '2026-10-09T00:00:' + String(i).padStart(2, '0') + '.000Z';
    servidas.forEach(([canal, nota], j) => iU.run('observacao', j + 1, nomeSessao, 1, nota, t, canal));
    iS.run(nomeSessao, t, 0, 0, 0);
  });
  b.close();
  return dir;
}
function relatorioCli(dir) {
  return execFileSync(process.execPath, ['--no-warnings', path.join(SRC, 'scripts', 'memoria.cjs'), 'utilidade', '--relatorio'], {
    env: Object.assign({}, process.env, { RFM_ROOT: dir }),
    cwd: dir,
    encoding: 'utf8',
  });
}
function selecionar(dir, sql) {
  const b = new DatabaseSync(path.join(dir, 'rainforest.db'));
  try {
    return b.prepare(sql).get();
  } finally {
    b.close();
  }
}
const linhasDe = (txt) => txt.trimEnd().split('\n');

// 10 sessoes: s0..s2 medidas 0,8 (pedido, abertura, subagente); s3..s5 medidas 0,1 nos mesmos canais;
// s6 e s7 so com uma servida nula no pedido; s8 com nula no subagente e medida 0,8 na abertura;
// s9 com nula no pedido e medida 0,1 na abertura.
const COMPLETA = [
  ['s0', [['pedido', 0.8]]],
  ['s1', [['abertura', 0.8]]],
  ['s2', [['subagente', 0.8]]],
  ['s3', [['pedido', 0.1]]],
  ['s4', [['abertura', 0.1]]],
  ['s5', [['subagente', 0.1]]],
  ['s6', [['pedido', null]]],
  ['s7', [['pedido', null]]],
  ['s8', [['subagente', null], ['abertura', 0.8]]],
  ['s9', [['pedido', null], ['abertura', 0.1]]],
];

caso('sessao so com servida nula sai do denominador e a linha fora da conta diz quantas', () => {
  const dir = bancoCom('completa', COMPLETA);
  const txt = relatorioCli(dir);
  console.log(linhasDe(txt).map((l) => '  | ' + l).join('\n'));
  const linhas = linhasDe(txt);
  const tem = (l) => assert.ok(linhas.includes(l), 'falta a linha: ' + l + '\n' + txt);
  tem('sessões pontuadas: 10');
  tem('2 sessão(ões) sem servida fora da conta');
  tem('servidas fora da conta (toda a memória estava no pedido): 4 em 4 sessão(ões)');
  tem('canal pedido: sessões com servida útil 1 de 2 (50%)');
  tem('canal abertura: sessões com servida útil 2 de 4 (50%)');
  tem('canal subagente: sessões com servida útil 1 de 2 (50%)');
  assert.ok(linhas.some((l) => l.startsWith('sessões com servida útil em qualquer canal: 4 de 8 (50%)')), txt);
  assert.ok(linhas.some((l) => l.startsWith('janela da régua D7: 8 sessão(ões) com servida desde 2026-10-09T')), txt);
});

caso('o numero da linha fora da conta e o do SELECT direto na caixa', () => {
  const dir = path.join(CAIXA, 'completa');
  const r = selecionar(dir, 'SELECT count(*) n, count(DISTINCT sessao) s FROM uso_memoria WHERE servida = 1 AND nota IS NULL');
  const linhas = linhasDe(relatorioCli(dir));
  assert.ok(
    linhas.includes(`servidas fora da conta (toda a memória estava no pedido): ${r.n} em ${r.s} sessão(ões)`),
    'linha diverge do SELECT: ' + r.n + ' em ' + r.s
  );
  assert.strictEqual(Number(r.n), 4);
});

caso('sem nenhuma servida nula a linha fora da conta nao aparece', () => {
  const dir = bancoCom('sem-nulas', COMPLETA.filter(([, s]) => s.every(([, nota]) => nota !== null)));
  const txt = relatorioCli(dir);
  assert.ok(!txt.includes('servidas fora da conta'), txt);
  assert.ok(txt.includes('sessões pontuadas: 6'), txt);
});

caso('o inicio da janela da regua continua contando a servida nula', () => {
  // n0: nula no pedido (o canal ja estava vivo); a1: medida na abertura; p1: medida no pedido.
  const dir = bancoCom('janela-nula', [
    ['n0', [['pedido', null]]],
    ['a1', [['abertura', 0.8]]],
    ['p1', [['pedido', 0.8]]],
  ]);
  const linhas = linhasDe(relatorioCli(dir));
  assert.ok(linhas.some((l) => l.startsWith('janela da régua D7: 2 sessão(ões) com servida desde 2026-10-09T00:00:00.000Z')), linhas.join('\n'));
});

try {
  fs.rmSync(CAIXA, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
