#!/usr/bin/env node
'use strict';
/**
 * Bateria de `memoria.cjs buscar --projeto` aceitando curto, slug ou caminho (#435, D3/D6/D9).
 * Uso: node scripts/testa-buscar-projeto.cjs
 *
 * A caixa é uma pasta temporária (fs.mkdtempSync) passada por RFM_ROOT explícito ao processo
 * filho; nunca toca ~/.rainforest. Nenhum caso lê o texto do fonte: tudo se confere pelo
 * exit e pela saída do processo real.
 */
const assert = require('assert');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const MEMORIA = path.join(__dirname, 'memoria.cjs');
const { abrirBanco, criarSchema } = require(MEMORIA);

const T = '2026-10-08T10:00:00';
const base = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-buscar-projeto-'));
const raiz = path.join(base, 'caixa');
fs.mkdirSync(raiz);

const c = abrirBanco(path.join(raiz, 'rainforest.db'));
criarSchema(c);
const ins = c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
const SEMENTES = [
  ['C--Projetos-alfa', 'banana alfa um', 'o:1'],
  ['C--Projetos-alfa', 'banana alfa dois', 'o:2'],
  ['C--Projetos-alfa', 'banana alfa tres', 'o:3'],
  ['C--Projetos-beta', 'banana beta um', 'o:4'],
  ['omega', 'banana omega um', 'o:5'],
  ['proj-subst', 'banana antiga um', 'o:6'],
  ['C--A-comum', 'banana a um', 'o:7'],
  ['C--B-comum', 'banana b um', 'o:8'],
];
for (const [p, t, o] of SEMENTES) ins.run(p, t, T, o);
c.close();

function buscar(args) {
  const r = cp.spawnSync(process.execPath, [MEMORIA, 'buscar', ...args], {
    env: { ...process.env, RFM_ROOT: raiz },
    encoding: 'utf8',
  });
  return { exit: r.status, out: r.stdout, err: r.stderr };
}
const conteudos = (args) => JSON.parse(buscar(args).out).map(o => o.conteudo).sort();
const ALFA = ['banana alfa dois', 'banana alfa tres', 'banana alfa um'];

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok    ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}: ${String(e.message).split('\n')[0]}`);
  }
}

try {
  for (const valor of ['alfa', 'C--Projetos-alfa', 'C--projetos-ALFA', 'C:/Projetos/alfa', 'C:\\Projetos\\alfa']) {
    caso(`--projeto ${valor} devolve as 3 observações do alfa (sem texto)`, () => {
      assert.deepStrictEqual(conteudos(['--projeto', valor, '--json']), ALFA);
    });
  }
  caso('--projeto alfa com --texto devolve as 3 do alfa', () => {
    assert.deepStrictEqual(conteudos(['--projeto', 'alfa', '--texto', 'banana', '--json']), ALFA);
  });
  caso('órfão omega casa por igualdade', () => {
    assert.deepStrictEqual(conteudos(['--projeto', 'omega', '--json']), ['banana omega um']);
  });
  caso('nome de bateria antiga proj-subst casa por igualdade', () => {
    assert.deepStrictEqual(conteudos(['--projeto', 'proj-subst', '--json']), ['banana antiga um']);
  });
  caso('curto ambiguo sai com exit 2 listando os candidatos', () => {
    for (const extra of [[], ['--texto', 'banana']]) {
      const r = buscar(['--projeto', 'comum', ...extra, '--json']);
      assert.strictEqual(r.exit, 2, `exit ${r.exit}`);
      assert.ok(r.err.includes('comum'), 'valor digitado ausente');
      assert.ok(r.err.includes('ambíguo'), 'motivo ausente');
      assert.ok(r.err.includes('C--A-comum') && r.err.includes('C--B-comum'), 'candidatos ausentes');
      assert.ok(/nome completo ou o caminho/.test(r.err), 'instrução ausente');
      assert.strictEqual(r.out, '', 'stdout deveria estar vazio');
    }
  });
  caso('desconhecido sai com exit 2 listando os projetos conhecidos', () => {
    for (const extra of [[], ['--texto', 'banana']]) {
      const r = buscar(['--projeto', 'desconhecido', ...extra, '--json']);
      assert.strictEqual(r.exit, 2, `exit ${r.exit}`);
      assert.ok(r.err.includes('desconhecido'), 'valor digitado ausente');
      assert.ok(r.err.includes('não encontrado'), 'motivo ausente');
      for (const p of ['C--Projetos-alfa', 'C--Projetos-beta', 'omega', 'C--A-comum', 'C--B-comum']) {
        assert.ok(r.err.split('\n').some(l => l.trim() === p), `candidato ${p} ausente`);
      }
      assert.ok(/nome completo ou o caminho/.test(r.err), 'instrução ausente');
    }
  });
  caso('caminho que não casa nenhum projeto sai com exit 2', () => {
    assert.strictEqual(buscar(['--projeto', 'C:/Projetos/zeta', '--json']).exit, 2);
  });
  caso('sem --projeto devolve todos como antes', () => {
    const r = buscar(['--json', '--limite', '50']);
    assert.strictEqual(r.exit, 0);
    assert.strictEqual(JSON.parse(r.out).length, SEMENTES.length);
  });
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
