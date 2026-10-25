#!/bin/bash
# Bateria do acoplamento por require entre tarefas da mesma camada (D6, 2026-10-24):
# `acoplamentos` e `alvosDeRequire` em `scripts/lib/camadas.cjs`, o aviso que a
# `cobertura` imprime no stderr e a chave `acoplamentos` do JSON da `camadas`.
# Uso: bash scripts/testa-camadas-acoplamento.sh
#
# Fixture: cada caso monta um repo-caixa dentro de UM mktemp -d (fora do worktree),
# com plano e design minimos e os arquivos .cjs, e roda a cobertura de verdade.
# Aviso não recusa: todo caso segue com exit 0. Os casos negativos provam que o
# aviso some quando não há require de arquivo da outra tarefa, não só que aparece
# quando há.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$RAIZ/scripts/conferir-fluxo.cjs"
[ -f "$CHECADOR" ] || { echo "FALHA: nao achei $CHECADOR"; exit 1; }

ok=0; falhou=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"; ERR="$TMP/err"
n=0

# Caso novo: pastas a/ e a/sub/ e design com D1. CX é o caminho POSIX; W, o do Windows (o node lê W).
novo_caso() {
  n=$((n+1))
  CX="$TMP/c$n"
  mkdir -p "$CX/docs/rainforest/planos" "$CX/docs/rainforest/design" "$CX/a/sub"
  printf '# Design s\n\n## Decisões fechadas\n- **D1 — Teste.** — porquê: x.\n' > "$CX/docs/rainforest/design/s.md"
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
}

# `arq <relativo> <conteudo>`: grava um arquivo do caso.
arq() { mkdir -p "$(dirname "$CX/$1")"; printf '%s\n' "$2" > "$CX/$1"; }

# `bloco <numero> <arquivo> <depende de>`: uma tarefa do plano, no formato real.
bloco() {
  printf '### %s. Tarefa %s [tipo: implementar]\natende: D1\narquivos: `%s`\ndepende de: %s\nparalela: nao\nmutacao: n/a\nmotivo: teste de forma\n\n' "$1" "$1" "$2" "$3"
}

# `prepara <arquivo-tarefa-1> <arquivo-tarefa-2> <depende de tarefa 2>`: caso novo com o plano de duas tarefas.
prepara() {
  novo_caso
  { printf '# Plano s\n\n## Tarefas\n\n'; bloco 1 "$1" nenhuma; bloco 2 "$2" "$3"; } > "$CX/docs/rainforest/planos/s.md"
}

cobertura() { RFM_ESTADO_ROOT="$W" node "$CHECADOR" cobertura --slug s --plano "$W/docs/rainforest/planos/s.md" --design "$W/docs/rainforest/design/s.md"; }
camadas() { RFM_ESTADO_ROOT="$W" node "$CHECADOR" camadas --slug s --plano "$W/docs/rainforest/planos/s.md"; }

# `esperar <rotulo> <exit> <regex-stdout|-> <regex-stderr|-> <cmd...>`
esperar() {
  local rotulo="$1" esperado="$2" rout="$3" rerr="$4"; shift 4
  "$@" >"$OUT" 2>"$ERR"; local got=$?
  local motivo=""
  [ "$got" -eq "$esperado" ] || motivo="exit $got (esperado $esperado)"
  if [ "$rout" != "-" ] && ! grep -qE -- "$rout" "$OUT"; then motivo="$motivo; stdout nao casa /$rout/"; fi
  if [ "$rerr" != "-" ] && ! grep -qE -- "$rerr" "$ERR"; then motivo="$motivo; stderr nao casa /$rerr/"; fi
  if [ -z "$motivo" ]; then
    ok=$((ok+1))
  else
    falhou=$((falhou+1))
    echo "  FALHA $rotulo:$motivo"
    echo "  stdout: $(head -c 400 "$OUT")"
    echo "  stderr: $(head -c 400 "$ERR")"
  fi
}

# `silencio <rotulo> <cmd...>`: a cobertura valida (exit 0 e o `ok:`), e nenhum aviso de require no stderr.
silencio() {
  local rotulo="$1"; shift
  "$@" >"$OUT" 2>"$ERR"; local got=$?
  if [ "$got" -eq 0 ] && grep -q 'ok: cobertura' "$OUT" && ! grep -q 'faz require' "$ERR"; then
    ok=$((ok+1))
  else
    falhou=$((falhou+1))
    echo "  FALHA $rotulo: exit $got; stdout: $(head -c 400 "$OUT"); stderr: $(head -c 400 "$ERR")"
  fi
}

echo "== aviso: as formas que contam"

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "const x = require('./x');"
esperar "require('./x') entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/y.cjs\) faz require de a/x.cjs, da tarefa 1, na mesma camada 1' cobertura

prepara a/x.cjs a/sub/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/sub/y.cjs "const x = require('../x.cjs');"
esperar "require('../x.cjs') entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/sub/y.cjs\) faz require de a/x.cjs, da tarefa 1' cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "import y from './x';"
esperar "import y from './x' entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/y.cjs\) faz require de a/x.cjs' cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "const m = import('./x');"
esperar "import('./x') entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/y.cjs\) faz require de a/x.cjs' cobertura

prepara a/lib/x.cjs a/y.cjs nenhuma
arq a/lib/x.cjs 'module.exports = 1;'
arq a/y.cjs "const x = require(path.join(__dirname, 'lib', 'x.cjs'));"
esperar "require(path.join(__dirname, 'lib', 'x.cjs')) entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/y.cjs\) faz require de a/lib/x.cjs, da tarefa 1' cobertura

prepara a/x.cjs a/sub/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/sub/y.cjs "const x = require(path.join(__dirname, '..', 'x.cjs'));"
esperar "require(path.join(__dirname, '..', 'x.cjs')) entre tarefas da mesma camada avisa" 0 - 'aviso: tarefa 2 \(a/sub/y.cjs\) faz require de a/x.cjs' cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs "const y = require('./y');"
arq a/y.cjs "const x = require('./x');"
esperar "A requer B e B requer A: avisa o sentido de B para A" 0 - 'aviso: tarefa 2 \(a/y.cjs\) faz require de a/x.cjs' cobertura
esperar "A requer B e B requer A: avisa o sentido de A para B" 0 - 'aviso: tarefa 1 \(a/x.cjs\) faz require de a/y.cjs' cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "const x = require('./x');"
esperar "camadas inclui acoplamentos no JSON" 0 '"acoplamentos":\[\{"camada":1,"a":1,"b":2,"arquivo":"a/y.cjs","alvo":"a/x.cjs"\}\]' - camadas

echo "== sem aviso: o que não é require entre tarefas da mesma camada"

prepara a/x.cjs a/y.cjs 1
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "const x = require('./x');"
silencio "tarefas em camadas diferentes não avisam" cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/x.cjs 'module.exports = 1;'
arq a/y.cjs "const caminho = './x'; const x = require(caminho);"
silencio "require de variável não avisa" cobertura

prepara a/fs.cjs a/y.cjs nenhuma
arq a/fs.cjs 'module.exports = 1;'
arq a/y.cjs "const fs = require('fs');"
silencio "módulo de pacote não avisa, mesmo com arquivo de mesmo nome na outra tarefa" cobertura

prepara a/x.cjs a/y.cjs nenhuma
arq a/y.cjs "const x = require('./x');"
silencio "arquivo declarado que não existe fica fora" cobertura

echo "-----------------------------------------"
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
