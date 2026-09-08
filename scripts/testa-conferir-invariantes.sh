#!/usr/bin/env bash
# testa-conferir-invariantes.sh — bateria para validar conferir-invariantes.cjs
#
# Checa:
# 1. O script passa com o repositório íntegro
# 2. O script falha quando uma frase é movida para depois de <!-- detalhe -->

set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

marca() {
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"
  fi
}

echo "== invariantes nao foram perdidas na extracao ===="
echo

# Caso 1: O repositório íntegro passa
node scripts/conferir-invariantes.cjs > /tmp/invariantes-check.log 2>&1
REPO_INTEGRO=$?
marca "repositorio integro passa no conferir" $REPO_INTEGRO

# Casos vermelhos — mutações numa CÓPIA, nunca no repo
CAIXA="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}"' EXIT

cp scripts/conferir-invariantes.cjs "$CAIXA/"
cp skills/rainforest-mind/invariantes.json "$CAIXA/"
cp skills/rainforest-mind/SKILL.md "$CAIXA/SKILL.md"
cp -r hooks "$CAIXA/"

# (1) MUTAÇÃO: mover a frase "3.000+ tokens" para DEPOIS de <!-- detalhe --> no SKILL.md
# Encontra a regra 10, remove "3.000+ tokens" dela, colocando a frase após a marca detalhe
(cd "$CAIXA" && node -e "
const fs=require('fs');
const arquivo='SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar a regra 10 e sua marca detalhe
const regex = /(\*\*10\. [^\n]+\n(?:[^\n]+\n)*?)(\<!-- detalhe -->)/;
const match = antes.match(regex);

if (!match) {
  console.error('Nao achei regra 10 ou marca detalhe');
  process.exit(3);
}

// Remover a frase do núcleo
let regra10 = match[1];
if (!regra10.includes('3.000+ tokens')) {
  console.error('Nao achei a frase 3.000+ tokens na regra 10');
  process.exit(3);
}

const regra10SemFrase = regra10.replace('3.000+ tokens', '3.000[removido]');
const detalhe = match[2];
const depois = antes.replace(match[0], regra10SemFrase + detalhe + '\n(3.000+ tokens agora só em detalhe)');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO1=$?

if [ "$MUTACAO1" -eq 0 ]; then
  # Agora executar o conferir na cópia com a mutação
  (cd "$CAIXA" && node conferir-invariantes.cjs > /tmp/mutacao1.log 2>&1)
  VERMELHO1=$?
  if [ "$VERMELHO1" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase movida para apos detalhe derruba conferir (exit $VERMELHO1)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a primeira mutacao"
fi

# (2) MUTAÇÃO: remover a frase "exit ≠ 0 nunca é sucesso" de regra 12
cp -r skills/rainforest-mind/references "$CAIXA/referencias"
(cd "$CAIXA" && node -e "
const fs=require('fs');
const arquivo='SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar e remover a frase
if (!antes.includes('exit ≠ 0 nunca é sucesso')) {
  console.error('Nao achei a frase exit ≠ 0 nunca é sucesso');
  process.exit(3);
}

const depois = antes.replace('exit ≠ 0 nunca é sucesso', 'exit diferente de zero[REMOVIDO]');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO2=$?

if [ "$MUTACAO2" -eq 0 ]; then
  (cd "$CAIXA" && node conferir-invariantes.cjs > /tmp/mutacao2.log 2>&1)
  VERMELHO2=$?
  if [ "$VERMELHO2" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase removida derruba conferir (exit $VERMELHO2)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a segunda mutacao"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
