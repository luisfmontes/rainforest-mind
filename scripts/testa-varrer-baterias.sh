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

# Piso minimo de scripts/.cjs (1)
cat > "$sandbox_a/scripts/testa-cjs-verde-1.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
chmod +x "$sandbox_a/scripts/testa-cjs-verde-1.cjs"

# Piso proprio de hooks/.sh (5)
for i in $(seq 1 5); do
  cat > "$sandbox_a/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_a/hooks/testa-hook-verde-$i.sh"
done

# Piso minimo de hooks/.cjs (10)
for i in $(seq 1 10); do
  cat > "$sandbox_a/hooks/testa-hook-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
  chmod +x "$sandbox_a/hooks/testa-hook-cjs-verde-$i.cjs"
done

cd "$sandbox_a"
saida=$(bash "$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -ne 0 ]; then
  echo "  FAIL (a): exit code $exitcode em vez de 0"
  echo "$saida"
  exit 1
fi
total_expected=31  # 15 + 1 + 5 + 10
if echo "$saida" | grep -q "== $total_expected baterias =="; then
  if echo "$saida" | grep -q "as $total_expected baterias passaram"; then
    echo "  PASS (a)"
  else
    echo "  FAIL (a): placar final nao menciona 'as $total_expected baterias passaram'"
    echo "$saida"
    exit 1
  fi
else
  echo "  FAIL (a): contador de baterias nao menciona $total_expected"
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

# Piso minimo de scripts/.cjs (1)
cat > "$sandbox_b/scripts/testa-cjs-verde-1.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
chmod +x "$sandbox_b/scripts/testa-cjs-verde-1.cjs"

# Piso proprio de hooks/.sh (5)
for i in $(seq 1 5); do
  cat > "$sandbox_b/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_b/hooks/testa-hook-verde-$i.sh"
done

# Piso minimo de hooks/.cjs (10)
for i in $(seq 1 10); do
  cat > "$sandbox_b/hooks/testa-hook-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
  chmod +x "$sandbox_b/hooks/testa-hook-cjs-verde-$i.cjs"
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

# Piso proprio de hooks/.sh
for i in $(seq 1 5); do
  cat > "$sandbox_c/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_c/hooks/testa-hook-verde-$i.sh"
done

# Piso minimo de hooks/.cjs (10)
for i in $(seq 1 10); do
  cat > "$sandbox_c/hooks/testa-hook-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
  chmod +x "$sandbox_c/hooks/testa-hook-cjs-verde-$i.cjs"
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

# Piso minimo de scripts/.cjs (1)
cat > "$sandbox_f/scripts/testa-cjs-verde-1.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
chmod +x "$sandbox_f/scripts/testa-cjs-verde-1.cjs"

# Piso proprio de hooks/.sh (5)
for i in $(seq 1 5); do
  cat > "$sandbox_f/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_f/hooks/testa-hook-verde-$i.sh"
done

# Piso minimo de hooks/.cjs (10)
for i in $(seq 1 10); do
  cat > "$sandbox_f/hooks/testa-hook-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
  chmod +x "$sandbox_f/hooks/testa-hook-cjs-verde-$i.cjs"
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
cat > "$sandbox_g/scripts/testa-cjs-verde-1.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
chmod +x "$sandbox_g/scripts/testa-cjs-verde-1.cjs"
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

# (#335) Bateria .cjs quebrada deixa o placar vermelho. A mutacao tira a linha
# `de_hooks_cjs=(hooks/testa-*.cjs)`, entao as .cjs nunca sao descobertas e o
# varredor para achei <0 em hooks/*.cjs. Medindo de verdade: montamos uma caixa
# com .cjs quebradas, o varredor tem que descobri-las e marcar vermelhas.
echo "=== Teste (m): (#335) bateria .cjs quebrada deixa o placar vermelho ==="
sandbox_m=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_m"
mkdir -p "$sandbox_m/scripts" "$sandbox_m/hooks"

# Criar 15 baterias verdes em scripts/ (o piso de la)
for i in $(seq 1 15); do
  cat > "$sandbox_m/scripts/testa-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_m/scripts/testa-verde-$i.sh"
done

# Piso proprio de hooks/.sh
for i in $(seq 1 5); do
  cat > "$sandbox_m/hooks/testa-hook-verde-$i.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$sandbox_m/hooks/testa-hook-verde-$i.sh"
done

# Piso minimo de scripts/.cjs (1) e hooks/.cjs (10)
for i in $(seq 1 1); do
  cat > "$sandbox_m/scripts/testa-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
  chmod +x "$sandbox_m/scripts/testa-cjs-verde-$i.cjs"
done

for i in $(seq 1 10); do
  if [ $i -eq 5 ]; then
    # Uma quebrada
    cat > "$sandbox_m/hooks/testa-cjs-vermelha-5.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(1);
EOF
    chmod +x "$sandbox_m/hooks/testa-cjs-vermelha-5.cjs"
  else
    cat > "$sandbox_m/hooks/testa-cjs-verde-$i.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(0);
EOF
    chmod +x "$sandbox_m/hooks/testa-cjs-verde-$i.cjs"
  fi
done

cd "$sandbox_m"
saida=$(bash "$VARRER" 2>&1)
exitcode=$?
if [ $exitcode -eq 1 ] && echo "$saida" | grep -q "testa-cjs-vermelha-5.cjs"; then
  echo "  PASS (m)"
else
  echo "  FAIL (m): exit=$exitcode (esperava 1); saida: $saida"
  exit 1
fi

echo "=== Teste (n): (#335, #341) nenhuma testa-*.sh executa outra bateria (a arvore real e uma caixa de areia) ==="
# O varredor roda toda testa-*.sh e testa-*.cjs direto; uma bateria .sh que
# tambem execute outra faz a mesma bateria rodar duas vezes, e a falha dela
# aparece em dobro, uma vez com o nome da bateria errada. Tres escaparam:
# scripts/testa-cli-externo.sh (nome literal; achado da revisao),
# hooks/testa-portaria.sh (glob `hooks/testa-portaria-*.cjs` + `node "$f"`;
# achado no verificar) e hooks/testa-gate-publicacao-destino.sh (rodava
# testa-gate-staging-total.sh e testa-conferir-publicacao.sh; #341).
# Este arquivo fica de fora porque monta fixtures nas caixas de areia.
#
# cascas_em: qualquer mencao nao comentada a uma testa-*.cjs, glob inclusive.
cascas_em() {
  (cd "$1" && grep -nE '^[^#]*testa-[A-Za-z0-9_*-]+\.cjs' scripts/testa-*.sh hooks/testa-*.sh 2>/dev/null | grep -v '^scripts/testa-varrer-baterias\.sh:')
}
# execucoes_sh_em: testa-*.sh EXECUTANDO outra testa-*.sh -- bash/sh/source/./
# exec, ou o caminho direto pelo shebang (`./hooks/testa-x.sh`), em posicao
# de comando (inicio da linha, depois de ; & | ( ou de if/then/do/..., com
# atribuicoes NOME=valor na frente). Mencao que nao e execucao nao conta:
# caminho como argumento (alvo de Edit num payload) ou texto de echo. A
# bateria que reexecuta a si mesma (o caso K de testa-saude.sh roda uma copia
# da propria bateria) nao e dobro de outra.
execucoes_sh_em() {
  (cd "$1" && grep -nE '(^|[;&|(]|(^|[[:space:]])(if|then|do|else|elif|while|until|!))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]$"'"'"'(]*[[:space:]]+)*((bash|sh|source|\.|exec)[[:space:]]+[^|;&]*|"?[^[:space:]|;&"]*/)testa-[A-Za-z0-9_.-]+\.sh' scripts/testa-*.sh hooks/testa-*.sh 2>/dev/null \
    | grep -v '^scripts/testa-varrer-baterias\.sh:' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | awk -F: '{ n = split($1, p, "/"); resto = substr($0, length($1) + length($2) + 3); if (index(resto, p[n]) == 0) print }')
}
# Contraprova: as checagens tem de achar, numa caixa de areia, a casca .cjs
# por glob e a .sh que executa outra .sh -- e nao achar mencao que nao executa.
sandbox_n=$(mktemp -d)
SANDBOXES="$SANDBOXES $sandbox_n"
mkdir -p "$sandbox_n/scripts" "$sandbox_n/hooks"
printf '#!/bin/bash\nfor f in hooks/testa-p-*.cjs; do node "$f"; done\n' > "$sandbox_n/hooks/testa-p.sh"
if [ -z "$(cascas_em "$sandbox_n")" ]; then
  echo "  FAIL (n): a checagem nao achou a casca por glob da caixa de areia"
  exit 1
fi
cat > "$sandbox_n/hooks/testa-a.sh" <<'EOF'
#!/bin/bash
if bash "$SRC/hooks/testa-b.sh" > /dev/null; then echo ok; fi
EOF
if ! execucoes_sh_em "$sandbox_n" | grep -q '^hooks/testa-a\.sh:'; then
  echo "  FAIL (n): a checagem nao achou a .sh que executa outra .sh na caixa de areia"
  exit 1
fi
cat > "$sandbox_n/scripts/testa-d.sh" <<'EOF'
#!/bin/bash
./hooks/testa-b.sh
EOF
if ! execucoes_sh_em "$sandbox_n" | grep -q '^scripts/testa-d\.sh:'; then
  echo "  FAIL (n): a checagem nao achou a execucao direta ./hooks/testa-b.sh na caixa de areia"
  exit 1
fi
cat > "$sandbox_n/hooks/testa-c.sh" <<'EOF'
#!/bin/bash
echo "== bash hooks/testa-b.sh =="
gate x 0 "$(pay Edit "$SRC/scripts/testa-b.sh" y)"
( cd "$C" && X=1 bash "$C/hooks/testa-c.sh" )
EOF
if execucoes_sh_em "$sandbox_n" | grep -q '^hooks/testa-c\.sh:'; then
  echo "  FAIL (n): a checagem pegou mencao que nao e execucao (echo, argumento, a propria bateria):"
  execucoes_sh_em "$sandbox_n" | grep '^hooks/testa-c\.sh:' | sed 's/^/    /'
  exit 1
fi
RAIZ_REAL="$(cd "$SCRIPT_DIR/.." && pwd)"
cascas=$(cascas_em "$RAIZ_REAL")
if [ -n "$cascas" ]; then
  echo "  FAIL (n): casca .sh executa bateria .cjs (rodaria em dobro):"
  printf '%s\n' "$cascas" | sed 's/^/    /'
  exit 1
fi
execucoes=$(execucoes_sh_em "$RAIZ_REAL")
if [ -n "$execucoes" ]; then
  echo "  FAIL (n): bateria .sh executa outra bateria .sh (rodaria em dobro):"
  printf '%s\n' "$execucoes" | sed 's/^/    /'
  exit 1
fi
echo "  PASS (n)"

echo ""
echo "======= TODOS OS TESTES PASSARAM ======="
exit 0
