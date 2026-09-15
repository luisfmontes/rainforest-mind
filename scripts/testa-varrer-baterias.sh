#!/bin/bash
# Teste do script varrer-baterias.sh
# Monta um sandbox com baterias sinteticas e valida todos os caminhos.

set -u

SANDBOXES=""
trap 'for d in $SANDBOXES; do rm -rf "$d"; done' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARRER="$SCRIPT_DIR/varrer-baterias.sh"

# Teste (a): baterias sintéticas todas verdes → exit 0 e o placar cita o total
echo "=== Teste (a): todas verdes com piso ==="
sandbox_a=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_a"
mkdir -p "$sandbox_a/scripts" "$sandbox_a/hooks"

# Criar exatamente 15 baterias verdes (o piso)
for i in $(seq 1 15); do
  cat > "$sandbox_a/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_a/scripts/testa-verde-$i.sh"
done

cd "$sandbox_a"
saida=$("$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 0 ]; then
  echo "  FAIL (a): exit code $exitcode em vez de 0"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "== 15 baterias =="; then
  if echo "$saida" | grep -q "as 15 baterias passaram"; then
    echo "  PASS (a)"
  else
    echo "  FAIL (a): placar final nao menciona 'as 15 baterias passaram'"
    echo "$saida"
    exit 1
  fi
else
  echo "  FAIL (a): contador de baterias nao menciona 15"
  echo "$saida"
  exit 1
fi

# Teste (b): uma vermelha entre elas → exit 1 e o nome dela aparece na lista de vermelhas
echo "=== Teste (b): uma vermelha entre verdes ==="
sandbox_b=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_b"
mkdir -p "$sandbox_b/scripts" "$sandbox_b/hooks"

# Criar 15 baterias verdes
for i in $(seq 1 15); do
  cat > "$sandbox_b/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_b/scripts/testa-verde-$i.sh"
done

# Criar uma bateria vermelha
cat > "$sandbox_b/scripts/testa-vermelha.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$sandbox_b/scripts/testa-vermelha.sh"

cd "$sandbox_b"
saida=$("$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 1 ]; then
  echo "  FAIL (b): exit code $exitcode em vez de 1"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "testa-vermelha.sh"; then
  echo "  PASS (b)"
else
  echo "  FAIL (b): testa-vermelha.sh nao aparece na saida"
  echo "$saida"
  exit 1
fi

# Teste (c): glob que não casa com ninguém → exit 1 citando a guarda de piso, não exit 0
echo "=== Teste (c): glob vazio (piso nao atingido) ==="
sandbox_c=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_c"
# Cria estrutura mas nenhuma bateria, entao o glob nao acha nada
mkdir -p "$sandbox_c/scripts" "$sandbox_c/hooks"

cd "$sandbox_c"
saida=$("$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 1 ]; then
  echo "  FAIL (c): exit code $exitcode em vez de 1"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "FALHA achei"; then
  echo "  PASS (c)"
else
  echo "  FAIL (c): guarda de piso nao foi acionada"
  echo "$saida"
  exit 1
fi

# Teste (d): --so <uma bateria verde> → exit 0, sem a guarda de piso
echo "=== Teste (d): --so com bateria verde ==="
sandbox_d=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_d"
cat > "$sandbox_d/testa-verde-1.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$sandbox_d/testa-verde-1.sh"

saida=$(bash "$VARRER" --so "$sandbox_d/testa-verde-1.sh" 2>&1)
exitcode=$?
if [ $exitcode -ne 0 ]; then
  echo "  FAIL (d): exit code $exitcode em vez de 0"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "FALHA achei"; then
  echo "  FAIL (d): guarda de piso foi acionada quando nao deveria"
  echo "$saida"
  exit 1
fi
echo "  PASS (d)"

# Teste (e): --so <uma vermelha> → exit 1
echo "=== Teste (e): --so com bateria vermelha ==="
sandbox_e=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_e"
cat > "$sandbox_e/testa-vermelha.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$sandbox_e/testa-vermelha.sh"

saida=$(bash "$VARRER" --so "$sandbox_e/testa-vermelha.sh" 2>&1)
exitcode=$?
if [ $exitcode -ne 1 ]; then
  echo "  FAIL (e): exit code $exitcode em vez de 1"
  echo "$saida"
  exit 1
fi
echo "  PASS (e)"

# Teste (f): com duas baterias que imprimem saídas diferentes, as duas saídas aparecem no log
echo "=== Teste (f): preservacao de saida por bateria ==="
sandbox_f=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_f"
mkdir -p "$sandbox_f/scripts" "$sandbox_f/hooks"

# Criar duas baterias com saidas diferentes
cat > "$sandbox_f/scripts/testa-saida1.sh" << 'EOF'
#!/bin/bash
echo "saida PRIMEIRA bateria"
exit 0
EOF
chmod +x "$sandbox_f/scripts/testa-saida1.sh"

cat > "$sandbox_f/scripts/testa-saida2.sh" << 'EOF'
#!/bin/bash
echo "saida SEGUNDA bateria diferente"
exit 0
EOF
chmod +x "$sandbox_f/scripts/testa-saida2.sh"

# Preencher com mais baterias verdes para atingir o piso de 15
for i in $(seq 1 13); do
  cat > "$sandbox_f/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_f/scripts/testa-verde-$i.sh"
done

cd "$sandbox_f"
saida=$("$VARRER" 2>&1)
if echo "$saida" | grep -q "saida PRIMEIRA bateria"; then
  if echo "$saida" | grep -q "saida SEGUNDA bateria diferente"; then
    echo "  PASS (f)"
  else
    echo "  FAIL (f): saida da segunda bateria nao aparece"
    echo "$saida"
    exit 1
  fi
else
  echo "  FAIL (f): saida da primeira bateria nao aparece"
  echo "$saida"
  exit 1
fi

echo ""
echo "======= TODOS OS TESTES PASSARAM ======="
exit 0
