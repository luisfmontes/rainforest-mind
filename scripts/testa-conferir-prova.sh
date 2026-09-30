#!/bin/bash
# Bateria do conferir-prova.cjs
# Uso: bash scripts/testa-conferir-prova.sh

set -u
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFERIR="$SCRIPTDIR/conferir-prova.cjs"
RAIZ="$(cd "$SCRIPTDIR/.." && pwd)"
FLUXO="$RAIZ/docs/rainforest/planos/2026-09-30-semear-travas.md"

ok=0; falhou=0

# Sandboxes e limpeza
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

# Helpers
exige() {  # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    printf '%s\n' "$saida" | sed 's/^/         /' | tail -5
  fi
}

exige_msg() {  # nome, regex, comando...
  local nome="$1" regex="$2"; shift 2
  if "$@" 2>&1 | grep -qi -- "$regex"; then ok=$((ok+1)); echo "  ok    $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei /$regex/ na saida"; fi
}

# Cria um repo descartável com um plano de teste
novo_repo() {
  local tmpdir; tmpdir=$(mktemp -d)
  SANDBOXES+=("$tmpdir")

  git init -q "$tmpdir"
  git -C "$tmpdir" config user.email t@t
  git -C "$tmpdir" config user.name t
  git -C "$tmpdir" config commit.gpgsign false

  # Cria estrutura de plano
  mkdir -p "$tmpdir/docs/rainforest/planos"

  echo "$tmpdir"
}

# Cria um plano-fixture com as tarefas
criar_plano() {
  local repo="$1"
  local plano="$repo/docs/rainforest/planos/t.md"

  cat > "$plano" <<'EOF'
# Plano de teste

## Tarefas

### 1. Tarefa que testa prova verde [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova: `exit 0`
pronto quando: ok

### 2. Tarefa que testa prova vermelha [tipo: implementar]
atende: D2
arquivos: scripts/y.cjs
prova: `exit 1`
pronto quando: ok

### 3. Tipo docs sem prova [tipo: docs]
atende: D3
arquivos: docs/z.md
pronto quando: ok

### 4. Implementar sem prova [tipo: implementar]
atende: D4
arquivos: scripts/z.cjs
pronto quando: ok

### 5. Prova-na-base com motivo [tipo: implementar]
atende: D5
arquivos: scripts/m.cjs
prova-na-base: verde — fixture de bateria
pronto quando: ok

### 6. Prova-na-base sem motivo [tipo: implementar]
atende: D6
arquivos: scripts/n.cjs
prova-na-base:
pronto quando: ok

### 7. Comando inexistente [tipo: implementar]
atende: D7
arquivos: scripts/o.cjs
prova: `comando_inexistente_xyz 2>&1`
pronto quando: ok

### 8. Prova malformada [tipo: implementar]
atende: D8
arquivos: scripts/p.cjs
prova: exit 1
pronto quando: ok
EOF

  # Cria commit inicial
  git -C "$repo" add .
  git -C "$repo" commit -qm "plano de teste"
}

echo "== Criando repo de teste =="
R=$(novo_repo)
criar_plano "$R"
W="$(cygpath -m "$R" 2>/dev/null || printf '%s' "$R")"
P="$R/docs/rainforest/planos/t.md"

echo "(caixa de areia: $W)"
echo

# Teste 1: prova que sai 0 (recusa) e prova que sai 1 (aceita)
echo "== 1. Provas que saem 0 (recusa) e 1 (aceita) =="
# Testa exit 2 E mensagem contendo "tarefa 1"
OUTPUT=$(RFM_ESTADO_ROOT="$W" node "$CONFERIR" plano --slug t --plano "$P" 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] && printf '%s' "$OUTPUT" | grep -q 'tarefa 1'; then
  ok=$((ok+1)); echo "  ok    prova que sai 0 na base: exit 2 nomeando a tarefa"
else
  falhou=$((falhou+1)); echo "  FALHA prova que sai 0 na base: exit 2 nomeando a tarefa (got exit $EXIT)"
fi

# Cria um novo plano só com a tarefa que sai 1
cat > "$P" <<'EOF'
# Plano de teste 2
### 1. Tarefa vermelha [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova: `exit 1`
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 2"

exige "prova que sai 1 na base: aceita, exit 0" 0 \
  bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'"

# Teste 2: tipo docs sem prova (isento) e implementar sem prova (recusa)
echo
echo "== 2. Tipo docs sem prova e implementar sem prova =="

cat > "$P" <<'EOF'
# Plano de teste 3
### 1. Docs [tipo: docs]
atende: D1
arquivos: docs/x.md
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 3"

exige "tipo docs sem prova: isento" 0 \
  bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'"

cat > "$P" <<'EOF'
# Plano de teste 4
### 1. Impl [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 4"

exige "implementar sem prova nem prova-na-base: exit 2" 2 \
  bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'"

# Teste 3: prova-na-base com motivo (aceita) e sem motivo (recusa)
echo
echo "== 3. Prova-na-base com motivo e sem motivo =="

cat > "$P" <<'EOF'
# Plano de teste 5
### 1. Com motivo [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova-na-base: verde — fixture de bateria
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 5"

exige "prova-na-base com motivo: aceita sem executar (sentinela ausente)" 0 \
  bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'"

cat > "$P" <<'EOF'
# Plano de teste 6
### 1. Sem motivo [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova-na-base:
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 6"

exige "prova-na-base sem motivo: exit 2" 2 \
  bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'"

# Teste 4: comando inexistente (exit 127)
echo
echo "== 4. Comando inexistente =="

cat > "$P" <<'EOF'
# Plano de teste 7
### 1. Inexistente [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova: `comando_xyz_nao_existe_mesmo`
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 7"

OUTPUT=$(RFM_ESTADO_ROOT="$W" node "$CONFERIR" plano --slug t --plano "$P" 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] && printf '%s' "$OUTPUT" | grep -qi 'a prova n.*o executa'; then
  ok=$((ok+1)); echo "  ok    comando inexistente (127): exit 2, a prova nao executa"
else
  falhou=$((falhou+1)); echo "  FALHA comando inexistente (127): exit 2, a prova nao executa (got exit $EXIT)"
fi

# Teste 5: timeout e worktree list
echo
echo "== 5. Timeout e limpeza de worktree =="

WL_ANTES=$(git -C "$R" worktree list | wc -l)

cat > "$P" <<'EOF'
# Plano de teste 8
### 1. Timeout [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova: `sleep 5`
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 8"

exige "timeout: exit 69 e git worktree list igual ao de antes" 69 \
  bash -c "RFM_PROVA_TIMEOUT_MS=500 RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P' 2>&1"

WL_DEPOIS=$(git -C "$R" worktree list | wc -l)
if [ "$WL_ANTES" = "$WL_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    git worktree list limpo após timeout"
else
  falhou=$((falhou+1)); echo "  FALHA git worktree list não limpo: $WL_ANTES -> $WL_DEPOIS"
fi

# Teste 5b: prova que grava arquivo não deixa rastro
echo
echo "== 5b. Prova que grava arquivo não deixa rastro =="

cat > "$P" <<'EOF'
# Plano de teste 9
### 1. Grava [tipo: implementar]
atende: D1
arquivos: scripts/x.cjs
prova: `touch /tmp/sentinela-teste-$$ && exit 1`
pronto quando: ok
EOF
git -C "$R" add . && git -C "$R" commit -qm "plano 9"

ANTES=$(git -C "$R" status --porcelain | wc -l)
bash -c "RFM_ESTADO_ROOT='$W' node '$CONFERIR' plano --slug t --plano '$P'" >/dev/null 2>&1
DEPOIS=$(git -C "$R" status --porcelain | wc -l)

if [ "$ANTES" = "$DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    prova que grava arquivo nao deixa rastro no repo (status limpo)"
else
  falhou=$((falhou+1)); echo "  FALHA status do repo mudou: $ANTES -> $DEPOIS"
fi

# Teste 6: bash scripts/testa-conferir-fluxo.sh segue verde
echo
echo "== 6. Bateria testa-conferir-fluxo.sh continua verde =="

bash "$RAIZ/scripts/testa-conferir-fluxo.sh" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    testa-conferir-fluxo.sh termina 0"
else
  falhou=$((falhou+1)); echo "  FALHA testa-conferir-fluxo.sh falhou"
fi

# Teste 7: estado.cjs marcar com prova verde/vermelha
echo
echo "== 7. estado.cjs marcar com prova verde/vermelha =="

S=$(novo_sandbox)
git init -q "$S"
git -C "$S" config user.email t@t; git -C "$S" config user.name t
git -C "$S" config commit.gpgsign false
mkdir -p "$S/docs/rainforest/design" "$S/docs/rainforest/planos"

# Design minimal
cat > "$S/docs/rainforest/design/t.md" <<'DESIGN'
# Design

## Fora de escopo

## Avaliado e descartado

## Decisões fechadas

- **D1** — porque: test

DESIGN

# Plano com prova verde
cat > "$S/docs/rainforest/planos/t-verde.md" <<'PLANO'
# Plano

Design: docs/rainforest/design/t.md

## Tarefas

### 1. Tarefa [tipo: implementar]
atende: D1
arquivos: x
prova: `exit 0`
mutacao:
  arquivo: x
  de: a
  para: b
  bateria: `bash test.sh`
  fixture: test
pronto quando: ok
PLANO

git -C "$S" add -A; git -C "$S" commit -q -m init

E() { RFM_ESTADO_ROOT="$S" node "$RAIZ/scripts/estado.cjs" "$@"; }

E iniciar --slug t >/dev/null 2>&1
E marcar --slug t --estagio design --status aprovado >/dev/null 2>&1

exige "marcar plano ok com prova verde na base: exit 2 pelo estado.cjs" 2 \
  E marcar --slug t --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/t-verde.md","tarefas":1}'

# Plano com prova vermelha
cp "$S/docs/rainforest/planos/t-verde.md" "$S/docs/rainforest/planos/t-vermelho.md"
sed -i 's/exit 0/exit 1/' "$S/docs/rainforest/planos/t-vermelho.md"
git -C "$S" add -A; git -C "$S" commit -q -m "prova vermelha"
E iniciar --slug t2 >/dev/null 2>&1
E marcar --slug t2 --estagio design --status aprovado >/dev/null 2>&1

exige "marcar plano ok com prova vermelha na base: exit 0" 0 \
  E marcar --slug t2 --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/t-vermelho.md","tarefas":1}'

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
