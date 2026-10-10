#!/usr/bin/env node
'use strict';
/* Bateria da Issue #475: a suspeita de corte de shell do `conferir-mutacao` e por tempo, e
 * tempo sob carga mente. `mediuEFalhou` diz quando a saida pos-mutacao prova que a bateria
 * chegou a medir e falhar, e ai nao ha corte. Casos com entrada fixa, sem cronometro.
 *
 * O ultimo caso roda a catraca de verdade numa caixa: uma bateria `node --test` cujo
 * baseline dorme 4 s (acima do piso) e cuja mutacao falha na hora (abaixo de 10%). Antes
 * do conserto saia exit 5 (corte); agora sai 0 (vermelha legitima).
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { mediuEFalhou } = require('./conferir-mutacao.cjs');

let ok = 0;
let falhas = 0;
function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`ok  ${nome}`); }
  else { falhas++; console.log(`FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 600)}` : ''}`); }
}

caso('resumo do node --test com falha (ℹ fail 1) e medida', mediuEFalhou('ℹ tests 1\nℹ pass 0\nℹ fail 1\n') === true);
caso('resumo TAP com falha (# fail 2) e medida', mediuEFalhou('# tests 3\n# pass 1\n# fail 2\n') === true);
caso('placar "ok: 3   falhou: 1" e medida', mediuEFalhou('ok: 3   falhou: 1') === true);
caso('placar "3 ok, 2 falhou" e medida', mediuEFalhou('3 ok, 2 falhou') === true);
caso('node --test com fail 0 nao e prova de falha', mediuEFalhou('ℹ pass 1\nℹ fail 0\n') === false);
caso('placar sem falha nao e prova', mediuEFalhou('ok: 3   falhou: 0') === false);
caso('erro de shell sem placar nao e prova (continua suspeita)', mediuEFalhou('bash: x: unbound variable\n') === false);
caso('saida vazia nao e prova', mediuEFalhou('') === false);
caso('"fail" no meio de uma frase nao e resumo', mediuEFalhou('a funcao fail 3 vezes') === false);

// Ponta a ponta: a catraca real numa caixa.
{
  const cx = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'mutacao-mediu-')));
  try {
    fs.mkdirSync(path.join(cx, 'src'));
    fs.mkdirSync(path.join(cx, 'test'));
    fs.writeFileSync(path.join(cx, 'src', 'x.js'), 'function ok(x) {\n  if (x === 1) return true;\n  return false;\n}\nmodule.exports = { ok };\n');
    fs.writeFileSync(path.join(cx, 'test', 'x.test.js'),
      "const test = require('node:test');\nconst assert = require('node:assert');\nconst { ok } = require('../src/x.js');\n" +
      "test('ok(1)', () => {\n  if (ok(1)) { const fim = Date.now() + 4000; while (Date.now() < fim) {} }\n  assert.strictEqual(ok(1), true);\n});\n");
    const r = spawnSync(process.execPath, [path.join(__dirname, 'conferir-mutacao.cjs'),
      '--arquivo', 'src/x.js', '--de', 'if (x === 1) return true;', '--para', 'if (x === 1) return false;',
      '--bateria', 'node --test test/x.test.js', '--raiz', cx], { cwd: cx, encoding: 'utf8', timeout: 120000 });
    caso('ponta a ponta: mutacao rapida que falhou medindo sai 0, nao 5 (corte)', r.status === 0,
      `exit=${r.status}\n${r.stdout}\n${r.stderr}`);
  } finally {
    fs.rmSync(cx, { recursive: true, force: true });
  }
}

console.log(`\n${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
