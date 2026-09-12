#!/bin/bash
# Bateria do gate-verificador-staged.cjs
# rainforest-gate: dados-de-exemplo
#
# Uso: bash hooks/testa-gate-verificador-staged.sh
# Saída: exit 0 se todos os casos passaram; exit 1 se algum falhou.
# Imprime placar: ok: N   falhou: M
#
# Casos:
#  (a) config com "verificador-staged" que reprova com SEGREDO staged → exit 2
#  (b) mesmo arquivo com SEGREDO só no working tree (não staged) → exit 0
#  (c) sem config, scripts/check-personal-data.py presente (dublê) → verificador foi chamado
#  (d) sem verificador nenhum → exit 0
#  (e) command = `git status` (não git commit) → exit 0 sem rodar verificador
#  (f) payload com agent_id → stderr SEM .rainforest-gate-off
#  (g) RAINFOREST_GATE_OFF=1 → exit 0 mesmo com SEGREDO

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-verificador-staged.cjs"
SANDBOXES_POSIX="$(mktemp -d)"
SANDBOXES="$(cygpath -m "$SANDBOXES_POSIX" 2>/dev/null || printf '%s' "$SANDBOXES_POSIX")"
trap 'rm -rf "$SANDBOXES_POSIX"' EXIT
echo "[testa-gate-verificador-staged] caixa de areia: $SANDBOXES"

ok=0; falhou=0

gate() { # nome, cwd, command, esperado_exit, json_extra
  local nome="$1" cwd="$2" command="$3" esp="$4" json_extra="${5:-}"
  local saida; saida=$(printf '%s' "$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}%s}' "$cwd" "$command" "$json_extra")" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -5; fi
}

esc() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1" | sed 's|\\|/|g'; }

echo "== Caso (a): config com verificador que reprova SEGREDO staged =="
CASE_A_POSIX="$SANDBOXES_POSIX/case-a"
CASE_A="$(cygpath -m "$CASE_A_POSIX" 2>/dev/null || printf '%s' "$CASE_A_POSIX")"
mkdir -p "$CASE_A_POSIX"
mkdir -p "$CASE_A_POSIX/.rainforest"
mkdir -p "$CASE_A_POSIX/scripts"
git init -q "$CASE_A_POSIX"
git -C "$CASE_A_POSIX" config user.email test@test
git -C "$CASE_A_POSIX" config user.name test
git -C "$CASE_A_POSIX" config core.autocrlf false
echo "base" > "$CASE_A_POSIX/arquivo.txt"
git -C "$CASE_A_POSIX" add arquivo.txt
git -C "$CASE_A_POSIX" commit -qm "base"
cat > "$CASE_A_POSIX/.rainforest/config.json" <<'EOF'
{"verificador-staged": "bash scripts/verifica.sh"}
EOF
# Script verificador que reprova se algum argumento contém SEGREDO
cat > "$CASE_A_POSIX/scripts/verifica.sh" << 'EOF'
#!/bin/bash
for arquivo in "$@"; do
  if grep -q "SEGREDO" "$arquivo" 2>/dev/null; then
    echo "encontrado: SEGREDO no arquivo"
    exit 1
  fi
done
exit 0
EOF
chmod +x "$CASE_A_POSIX/scripts/verifica.sh"
# Stage arquivo com SEGREDO
echo "contato: SEGREDO" > "$CASE_A_POSIX/arquivo.txt"
git -C "$CASE_A_POSIX" add arquivo.txt
gate "case-a: SEGREDO staged" "$CASE_A" "git commit -m x" 2

echo
echo "== Caso (b): SEGREDO no working tree mas não staged =="
CASE_B_POSIX="$SANDBOXES_POSIX/case-b"
CASE_B="$(cygpath -m "$CASE_B_POSIX" 2>/dev/null || printf '%s' "$CASE_B_POSIX")"
mkdir -p "$CASE_B_POSIX"
mkdir -p "$CASE_B_POSIX/.rainforest"
mkdir -p "$CASE_B_POSIX/scripts"
git init -q "$CASE_B_POSIX"
git -C "$CASE_B_POSIX" config user.email test@test
git -C "$CASE_B_POSIX" config user.name test
git -C "$CASE_B_POSIX" config core.autocrlf false
echo "base" > "$CASE_B_POSIX/arquivo.txt"
git -C "$CASE_B_POSIX" add arquivo.txt
git -C "$CASE_B_POSIX" commit -qm "base"
cat > "$CASE_B_POSIX/.rainforest/config.json" <<'EOF'
{"verificador-staged": "bash scripts/verifica.sh"}
EOF
cat > "$CASE_B_POSIX/scripts/verifica.sh" << 'EOF'
#!/bin/bash
for arquivo in "$@"; do
  if grep -q "SEGREDO" "$arquivo" 2>/dev/null; then
    exit 1
  fi
done
exit 0
EOF
chmod +x "$CASE_B_POSIX/scripts/verifica.sh"
# SEGREDO APENAS no working tree, não staged
printf 'contato: clean' > "$CASE_B_POSIX/arquivo.txt"
git -C "$CASE_B_POSIX" add arquivo.txt
# Agora muda o arquivo no disco (não staged)
printf 'contato: SEGREDO' > "$CASE_B_POSIX/arquivo.txt"
gate "case-b: SEGREDO não staged" "$CASE_B" "git commit -m x" 0

echo
echo "== Caso (c): scripts/check-personal-data.py presente (dublê) =="
CASE_C_POSIX="$SANDBOXES_POSIX/case-c"
CASE_C="$(cygpath -m "$CASE_C_POSIX" 2>/dev/null || printf '%s' "$CASE_C_POSIX")"
mkdir -p "$CASE_C_POSIX"
git init -q "$CASE_C_POSIX"
git -C "$CASE_C_POSIX" config user.email test@test
git -C "$CASE_C_POSIX" config user.name test
git -C "$CASE_C_POSIX" config core.autocrlf false
echo "base" > "$CASE_C_POSIX/arquivo.txt"
git -C "$CASE_C_POSIX" add arquivo.txt
git -C "$CASE_C_POSIX" commit -qm "base"
# Dublê que grava os argumentos num arquivo
mkdir -p "$CASE_C_POSIX/scripts"
cat > "$CASE_C_POSIX/scripts/check-personal-data.py" << 'EOF'
#!/usr/bin/env python3
import sys
import os
try:
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "duble-chamado.txt"), "w") as f:
        for arg in sys.argv[1:]:
            f.write(arg + "\n")
except:
    print("(pulado: sem python)")
sys.exit(0)
EOF
chmod +x "$CASE_C_POSIX/scripts/check-personal-data.py"
# Stage um arquivo
echo "contato: info" > "$CASE_C_POSIX/arquivo.txt"
git -C "$CASE_C_POSIX" add arquivo.txt
rm -f "$CASE_C_POSIX/scripts/duble-chamado.txt"
gate "case-c: check-personal-data.py chamado" "$CASE_C" "git commit -m x" 0
# Verifica se o dublê foi chamado
if [ -f "$CASE_C_POSIX/scripts/duble-chamado.txt" ] && grep -q "arquivo.txt" "$CASE_C_POSIX/scripts/duble-chamado.txt"; then
  echo "  ok   case-c: dublê foi chamado com caminhos"
  ok=$((ok+1))
else
  echo "  FALHA case-c: dublê não foi chamado ou não recebeu caminhos"
  falhou=$((falhou+1))
fi

echo
echo "== Caso (d): sem verificador nenhum =="
CASE_D_POSIX="$SANDBOXES_POSIX/case-d"
CASE_D="$(cygpath -m "$CASE_D_POSIX" 2>/dev/null || printf '%s' "$CASE_D_POSIX")"
mkdir -p "$CASE_D_POSIX"
git init -q "$CASE_D_POSIX"
git -C "$CASE_D_POSIX" config user.email test@test
git -C "$CASE_D_POSIX" config user.name test
git -C "$CASE_D_POSIX" config core.autocrlf false
echo "base" > "$CASE_D_POSIX/arquivo.txt"
git -C "$CASE_D_POSIX" add arquivo.txt
git -C "$CASE_D_POSIX" commit -qm "base"
# Sem verificador de nenhum tipo
echo "qualquer coisa" > "$CASE_D_POSIX/arquivo.txt"
git -C "$CASE_D_POSIX" add arquivo.txt
gate "case-d: sem verificador" "$CASE_D" "git commit -m x" 0

echo
echo "== Caso (e): git status (não git commit) =="
CASE_E_POSIX="$SANDBOXES_POSIX/case-e"
CASE_E="$(cygpath -m "$CASE_E_POSIX" 2>/dev/null || printf '%s' "$CASE_E_POSIX")"
mkdir -p "$CASE_E_POSIX"
mkdir -p "$CASE_E_POSIX/.rainforest"
mkdir -p "$CASE_E_POSIX/scripts"
git init -q "$CASE_E_POSIX"
git -C "$CASE_E_POSIX" config user.email test@test
git -C "$CASE_E_POSIX" config user.name test
git -C "$CASE_E_POSIX" config core.autocrlf false
echo "base" > "$CASE_E_POSIX/arquivo.txt"
git -C "$CASE_E_POSIX" add arquivo.txt
git -C "$CASE_E_POSIX" commit -qm "base"
cat > "$CASE_E_POSIX/.rainforest/config.json" <<'EOF'
{"verificador-staged": "bash scripts/verifica.sh"}
EOF
cat > "$CASE_E_POSIX/scripts/verifica.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$CASE_E_POSIX/scripts/verifica.sh"
echo "qualquer coisa" > "$CASE_E_POSIX/arquivo.txt"
git -C "$CASE_E_POSIX" add arquivo.txt
# Comando NÃO é git commit
gate "case-e: git status (não git commit)" "$CASE_E" "git status" 0

echo
echo "== Caso (f): agent_id no payload =="
CASE_F_POSIX="$SANDBOXES_POSIX/case-f"
CASE_F="$(cygpath -m "$CASE_F_POSIX" 2>/dev/null || printf '%s' "$CASE_F_POSIX")"
mkdir -p "$CASE_F_POSIX"
git init -q "$CASE_F_POSIX"
git -C "$CASE_F_POSIX" config user.email test@test
git -C "$CASE_F_POSIX" config user.name test
git -C "$CASE_F_POSIX" config core.autocrlf false
echo "base" > "$CASE_F_POSIX/arquivo.txt"
git -C "$CASE_F_POSIX" add arquivo.txt
git -C "$CASE_F_POSIX" commit -qm "base"
mkdir -p "$CASE_F_POSIX/.rainforest"
mkdir -p "$CASE_F_POSIX/scripts"
cat > "$CASE_F_POSIX/.rainforest/config.json" <<'EOF'
{"verificador-staged": "bash scripts/verifica.sh"}
EOF
cat > "$CASE_F_POSIX/scripts/verifica.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$CASE_F_POSIX/scripts/verifica.sh"
echo "qualquer coisa" > "$CASE_F_POSIX/arquivo.txt"
git -C "$CASE_F_POSIX" add arquivo.txt
# Payload COM agent_id
msg=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"agent_id":"agent-1","agent_type":"executor"}' "$CASE_F" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ] && ! printf '%s' "$msg" | grep -q "\.rainforest-gate-off\|RAINFOREST_GATE_OFF"; then
  echo "  ok   case-f: agent_id não nomeia escotilhas"
  ok=$((ok+1))
else
  echo "  FALHA case-f: agent_id não funcionou ou contém escotilhas"
  printf '%s' "$msg" | sed 's/^/         /' | head -5
  falhou=$((falhou+1))
fi

echo
echo "== Caso (g): RAINFOREST_GATE_OFF=1 =="
CASE_G_POSIX="$SANDBOXES_POSIX/case-g"
CASE_G="$(cygpath -m "$CASE_G_POSIX" 2>/dev/null || printf '%s' "$CASE_G_POSIX")"
mkdir -p "$CASE_G_POSIX"
git init -q "$CASE_G_POSIX"
git -C "$CASE_G_POSIX" config user.email test@test
git -C "$CASE_G_POSIX" config user.name test
git -C "$CASE_G_POSIX" config core.autocrlf false
echo "base" > "$CASE_G_POSIX/arquivo.txt"
git -C "$CASE_G_POSIX" add arquivo.txt
git -C "$CASE_G_POSIX" commit -qm "base"
mkdir -p "$CASE_G_POSIX/.rainforest"
mkdir -p "$CASE_G_POSIX/scripts"
cat > "$CASE_G_POSIX/.rainforest/config.json" <<'EOF'
{"verificador-staged": "bash scripts/verifica.sh"}
EOF
cat > "$CASE_G_POSIX/scripts/verifica.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$CASE_G_POSIX/scripts/verifica.sh"
echo "contato: SEGREDO" > "$CASE_G_POSIX/arquivo.txt"
git -C "$CASE_G_POSIX" add arquivo.txt
# Com RAINFOREST_GATE_OFF=1
msg=$(printf '%s' "$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' "$CASE_G")" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  echo "  ok   case-g: RAINFOREST_GATE_OFF=1 derrota tudo"
  ok=$((ok+1))
else
  echo "  FALHA case-g: RAINFOREST_GATE_OFF=1 não funcionou (exit $rc)"
  falhou=$((falhou+1))
fi

echo
echo "== Resultado: $ok ok   $falhou falha(s) =="
[ "$falhou" = 0 ]
