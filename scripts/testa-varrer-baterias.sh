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

# Criar 15 baterias verdes em scripts/ (o piso de la)
for i in $(seq 1 15); do
  cat > "$sandbox_a/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_a/scripts/testa-verde-$i.sh"
done

# Piso proprio de hooks/: a caixa de areia precisa das duas metades.
for i in $(seq 1 5); do
  cat > "$sandbox_a/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_a/hooks/testa-hook-verde-$i.sh"
done

cd "$sandbox_a"
saida=$(bash "$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 0 ]; then
  echo "  FAIL (a): exit code $exitcode em vez de 0"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "== 20 baterias =="; then
  if echo "$saida" | grep -q "as 20 baterias passaram"; then
    echo "  PASS (a)"
  else
    echo "  FAIL (a): placar final nao menciona 'as 15 baterias passaram'"
    echo "$saida"
    exit 1
  fi
else
  echo "  FAIL (a): contador de baterias nao menciona 20"
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

# Piso proprio de hooks/: a caixa de areia precisa das duas metades.
for i in $(seq 1 5); do
  cat > "$sandbox_b/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_b/hooks/testa-hook-verde-$i.sh"
done

cd "$sandbox_b"
saida=$(bash "$VARRER" 2>&1)
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

# Piso proprio de hooks/: a caixa de areia precisa das duas metades.
for i in $(seq 1 5); do
  cat > "$sandbox_c/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_c/hooks/testa-hook-verde-$i.sh"
done

cd "$sandbox_c"
saida=$(bash "$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 1 ]; then
  echo "  FAIL (c): exit code $exitcode em vez de 1"
  echo "$saida"
  exit 1
fi
if echo "$saida" | grep -q "FALHA achei 0 baterias em scripts/"; then
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

# Preencher com mais baterias verdes para atingir o piso de scripts/
for i in $(seq 1 13); do
  cat > "$sandbox_f/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_f/scripts/testa-verde-$i.sh"
done

# Piso proprio de hooks/: a caixa de areia precisa das duas metades.
for i in $(seq 1 5); do
  cat > "$sandbox_f/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_f/hooks/testa-hook-verde-$i.sh"
done

cd "$sandbox_f"
saida=$(bash "$VARRER" 2>&1)
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

# Testes (g) a (l): o que a revisao do zerar-issues-4 mediu em 2026-09-15 e a
# primeira versao deste script nao segurava.

# (g) Piso POR PASTA. Na arvore real sao 89 baterias em scripts/ e 27 em
# hooks/: com piso unico de 15, scripts/ sozinho ja satisfazia, e se o glob de
# hooks/ quebrasse os 27 gates saiam da varredura com o placar dizendo verde.
echo "=== Teste (g): hooks/ vazio com scripts/ cheio (piso por pasta) ==="
sandbox_g=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_g"
mkdir -p "$sandbox_g/scripts" "$sandbox_g/hooks"
for i in $(seq 1 20); do
  cat > "$sandbox_g/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_g/scripts/testa-verde-$i.sh"
done
cd "$sandbox_g"
saida=$(bash "$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && echo "$saida" | grep -q "FALHA achei 0 baterias em hooks/"; then
  echo "  PASS (g)"
else
  echo "  FAIL (g): exit=$exitcode; saida: $saida"
  exit 1
fi

# (h) `--so` nao e um jeito de rodar script arbitrario com a cara da varredura.
echo "=== Teste (h): --so com script que nao e bateria ==="
sandbox_h=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_h"
cat > "$sandbox_h/qualquer-coisa.sh" << 'EOF'
#!/bin/bash
echo "RODEI ARBITRARIO"
exit 0
EOF
chmod +x "$sandbox_h/qualquer-coisa.sh"
saida=$(bash "$VARRER" --so "$sandbox_h/qualquer-coisa.sh" 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && ! echo "$saida" | grep -q "RODEI ARBITRARIO"; then
  echo "  PASS (h)"
else
  echo "  FAIL (h): exit=$exitcode; saida: $saida"
  exit 1
fi

# (i) `for f in $baterias` sem aspas fazia globbing: `--so "<pasta>/*.sh"`
# rodava VARIAS e o placar dizia "bateria passou", no singular.
echo "=== Teste (i): --so com glob nao expande ==="
sandbox_i=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_i"
for n in a b; do
  cat > "$sandbox_i/testa-$n.sh" << EOF
#!/bin/bash
echo "RODEI $n"
exit 0
EOF
  chmod +x "$sandbox_i/testa-$n.sh"
done
saida=$(bash "$VARRER" --so "$sandbox_i/testa-*.sh" 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && ! echo "$saida" | grep -q "RODEI a"; then
  echo "  PASS (i)"
else
  echo "  FAIL (i): exit=$exitcode; saida: $saida"
  exit 1
fi

# (j) e (k): errar a invocacao nao pode cair calado no modo completo. Da raiz
# do repositorio isso sao 116 baterias no lugar de uma mensagem de uso.
echo "=== Teste (j): --so sem valor ==="
saida=$(bash "$VARRER" --so 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && echo "$saida" | grep -q "exige exatamente um caminho"; then
  echo "  PASS (j)"
else
  echo "  FAIL (j): exit=$exitcode; saida: $saida"
  exit 1
fi

echo "=== Teste (k): flag desconhecida ==="
saida=$(bash "$VARRER" --sso x 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && echo "$saida" | grep -q "opcao desconhecida"; then
  echo "  PASS (k)"
else
  echo "  FAIL (k): exit=$exitcode; saida: $saida"
  exit 1
fi

# (l) `vermelhas` tambem precisava virar array: era string, e `for f in
# $vermelhas` partia no espaco. Caminho de caixa de areia com espaco e o caso.
echo "=== Teste (l): caminho com espaco chega inteiro na lista de vermelhas ==="
sandbox_l="$(mktemp -d)/com espaco"
mkdir -p "$sandbox_l"
SANDBOXES="$SANDBOXES $sandbox_l"
cat > "$sandbox_l/testa-vermelha.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$sandbox_l/testa-vermelha.sh"
saida=$(bash "$VARRER" --so "$sandbox_l/testa-vermelha.sh" 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && echo "$saida" | grep -qF "  - $sandbox_l/testa-vermelha.sh"; then
  echo "  PASS (l)"
else
  echo "  FAIL (l): exit=$exitcode; saida: $saida"
  exit 1
fi

echo ""
echo "======= TODOS OS TESTES PASSARAM ======="
exit 0
