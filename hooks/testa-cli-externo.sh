#!/bin/bash
# Bateria para cli-externo.cjs — validação de valores seguros para shell
# Uso: bash hooks/testa-cli-externo.sh

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "(testes de valorSeguroParaShell)"
echo ""

cd "$SRC"

node << 'NODEOF'
const { valorSeguroParaShell } = require('./hooks/lib/cli-externo.cjs');

const testes_aceitos = [
  { desc: 'letras simples', val: 'abc' },
  { desc: 'dígitos', val: '123' },
  { desc: 'caminho com espaço', val: '/tmp/dir com espaco/arquivo.txt' },
  { desc: 'caminho Windows', val: 'C:/tmp/arquivo.txt' },
  { desc: 'caracteres permitidos', val: 'abc-def_ghi~jkl.mno:pqr' },
  { desc: 'vírgula', val: 'abc,def' },
  { desc: 'barra', val: 'abc/def' },
  { desc: 'barra invertida', val: 'abc\\def' },
];

const testes_recusados = [
  { desc: 'aspas duplas', val: 'x"y' },
  { desc: 'apóstrofo', val: "x'y" },
  { desc: 'backtick', val: 'x`y' },
  { desc: 'cifrão', val: 'x$y' },
  { desc: 'ampersand', val: 'x&y' },
  { desc: 'pipe', val: 'x|y' },
  { desc: 'ponto-e-vírgula', val: 'x;y' },
  { desc: 'menor que', val: 'x<y' },
  { desc: 'maior que', val: 'x>y' },
  { desc: 'circunflexo', val: 'x^y' },
  { desc: 'percentual', val: 'x%y' },
  { desc: 'exclamação', val: 'x!y' },
  { desc: 'parêntese esquerdo', val: 'x(y' },
  { desc: 'parêntese direito', val: 'x)y' },
  { desc: 'vazio', val: '' },
  { desc: 'quebra de linha', val: 'x\ny' },
  { desc: 'null', val: null },
  { desc: 'undefined', val: undefined },
  { desc: 'número', val: 123 },
  { desc: 'array', val: [] },
  { desc: 'objeto', val: {} },
];

let ok = 0, falhas = 0;

console.log('-- Valores aceitos --');
for (const t of testes_aceitos) {
  const r = valorSeguroParaShell(t.val);
  if (r === true) {
    console.log(`  ok   ${t.desc}`);
    ok++;
  } else {
    console.log(`  FALHA ${t.desc}: esperava aceito, obteve ${r}`);
    falhas++;
  }
}

console.log('');
console.log('-- Valores recusados --');
for (const t of testes_recusados) {
  const r = valorSeguroParaShell(t.val);
  if (r === false) {
    console.log(`  ok   ${t.desc} recusado`);
    ok++;
  } else {
    console.log(`  FALHA ${t.desc}: esperava recusado, obteve ${r}`);
    falhas++;
  }
}

console.log('');
console.log(`resultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas > 0 ? 1 : 0);
NODEOF
exit $?
