#!/usr/bin/env bash
# O bloco de perfil de trabalho vive em OITO lugares: a fonte
# (`referencias/perfil-de-trabalho.md`) e os sete `agents/*.md`. Esta bateria
# existe para que eles nao divirjam em silencio.
#
# E o mesmo desenho do `testa-versao.sh`, pela mesma razao registrada la: em
# 2026-08-14 a versao do plugin estava em dois lugares, divergiu por uma entrega
# inteira, e cinco revisoes independentes passaram por cima sem ver. Numero (ou
# texto) que precisa existir em varios lugares tem UMA fonte, e os demais se
# conferem contra ela.
#
# Nao testa um script — testa um invariante do repositorio.
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

echo "== o bloco de perfil esta igual nos sete agentes =="
echo

node scripts/perfil.cjs --conferir > /tmp/perfil-conferir.log 2>&1
marca "conferir devolve exit 0 com tudo sincronizado" $?

# Falsificacao. Duas mutacoes numa COPIA, nunca no repo — bateria que edita o
# proprio fonte deixa o repositorio sujo se morrer no meio, e esta roda no CI.
#
# ATENCAO ao `cd` antes do `node -e`: caminho POSIX embutido em `node -e` NAO
# passa pela conversao do MSYS (ela vale para argumento e variavel de ambiente,
# nao para o texto do script). A primeira versao desta bateria escreveu em
# `C:\tmp\...`, que nao existe, a mutacao nunca aconteceu, e os dois casos
# "passaram" por vacuidade — exatamente o defeito que eles existem para pegar.
CAIXA="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}"' EXIT
cp -r referencias "$CAIXA/referencias"
cp -r agents "$CAIXA/agents"
cp -r scripts "$CAIXA/scripts"

# (1) Alteracao DENTRO do bloco — o modo de falha que importa: alguem edita o
# agente a mao e a fonte fica para tras.
(cd "$CAIXA" && node -e "
const fs=require('fs');
const p='agents/executor.md';
const antes=fs.readFileSync(p,'utf8');
const depois=antes.replace('Config mudada não conta','Config mudada CONTA');
if (antes === depois) { console.error('MUTACAO NAO APLICADA'); process.exit(3); }
fs.writeFileSync(p,depois);
")
APLICOU=$?
if [ "$APLICOU" -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA a mutacao nem foi aplicada — a prova abaixo nao valeria nada"
else
  (cd "$CAIXA" && node scripts/perfil.cjs --conferir > /dev/null 2>&1)
  DENTRO=$?
  if [ "$DENTRO" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: alteracao DENTRO do bloco derruba o conferir (exit $DENTRO)"
  else
    falhou=$((falhou+1)); echo "  FALHA alteracao dentro do bloco passou — a comparacao nao e do bloco inteiro"
  fi
fi

# (2) Bloco removido inteiro — agente que perdeu o bloco tem que reprovar, senao
# um agente sem padrao de evidencia passaria despercebido.
cp -r agents "$CAIXA/agents"  2>/dev/null
rm -rf "$CAIXA/agents"; cp -r agents "$CAIXA/agents"
(cd "$CAIXA" && node -e "
const fs=require('fs');
const p='agents/tester.md';
const antes=fs.readFileSync(p,'utf8');
const i=antes.indexOf('<!-- perfil-de-trabalho:inicio -->');
if (i === -1) { console.error('SEM BLOCO PARA REMOVER'); process.exit(3); }
fs.writeFileSync(p, antes.slice(0, i));
")
REMOVEU=$?
if [ "$REMOVEU" -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui remover o bloco para a prova"
else
  (cd "$CAIXA" && node scripts/perfil.cjs --conferir > /dev/null 2>&1)
  SEM=$?
  if [ "$SEM" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: agente sem o bloco derruba o conferir (exit $SEM)"
  else
    falhou=$((falhou+1)); echo "  FALHA agente sem bloco passou no conferir"
  fi
fi

# Os sete agentes existem mesmo (se alguem renomear a pasta, o conferir passaria
# com zero arquivos e ninguem notaria).
QUANTOS=$(ls agents/*.md 2>/dev/null | wc -l)
if [ "$QUANTOS" -ge 7 ]; then
  ok=$((ok+1)); echo "  ok   ha $QUANTOS agentes conferidos (esperado >= 7)"
else
  falhou=$((falhou+1)); echo "  FALHA so $QUANTOS agente(s) encontrado(s), esperado >= 7"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
