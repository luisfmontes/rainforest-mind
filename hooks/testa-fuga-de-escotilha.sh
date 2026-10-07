#!/bin/bash
# Bateria de fuga de escotilha — verifica que os seis gates nomeiam
# saídas de emergência APENAS para a janela principal, nunca para subagente.
# rainforest-gate: dados-de-exemplo
#
# Para cada gate, cria um cenário que dispara a recusa (exit 2) com agent_id,
# e afirma que o stderr não contém .rainforest-gate-off nem RAINFOREST_GATE_OFF.
#
# Uso: bash hooks/testa-fuga-de-escotilha.sh
# Saída: exit 0 se todos os 6 gates passaram; exit 1 se algum falhou.
# Imprime placar: ok: N   falhou: M

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "[testa-fuga-de-escotilha] caixa de areia: $RAIZ"

ok=0; falhou=0

testa_gate() { # nome_gate, payload_json, esperado_strings_proibidas
  local nome_gate="$1" payload="$2"
  local gate_script="$SRC/hooks/$nome_gate.cjs"

  if [ ! -f "$gate_script" ]; then
    echo "  ✗ $nome_gate: arquivo não encontrado ($gate_script)"
    falhou=$((falhou+1))
    return 1
  fi

  local msg; msg=$(printf '%s' "$payload" | node "$gate_script" 2>&1); local rc=$?

  # Gate deve recusar com exit 2
  if [ "$rc" != 2 ]; then
    echo "  ✗ $nome_gate: esperava exit 2, veio $rc"
    echo "$msg" | sed 's/^/    /'
    falhou=$((falhou+1))
    return 1
  fi

  # Mensagem não pode conter .rainforest-gate-off ou RAINFOREST_GATE_OFF
  if printf '%s' "$msg" | grep -q "\.rainforest-gate-off\|RAINFOREST_GATE_OFF"; then
    echo "  ✗ $nome_gate: stderr contém saídas de emergência (que não deveria)"
    printf '%s' "$msg" | grep "rainforest-gate-off\|RAINFOREST_GATE_OFF" | sed 's/^/    /'
    falhou=$((falhou+1))
    return 1
  fi

  echo "  ✓ $nome_gate: recusou sem nomear saídas"
  ok=$((ok+1))
  return 0
}

echo "== Preparação: repos git de teste =="

# Repo principal (para gate-worktree e gate-publicacao)
PRINCIPAL="$RAIZ/principal"
git init -q "$PRINCIPAL"
git -C "$PRINCIPAL" config user.email test@test
git -C "$PRINCIPAL" config user.name test
git -C "$PRINCIPAL" config commit.gpgsign false
echo "base" > "$PRINCIPAL/arquivo.txt"
git -C "$PRINCIPAL" add arquivo.txt
git -C "$PRINCIPAL" commit -qm "base commit"

# Worktree isolado (para gate-worktree)
WORKTREE="$PRINCIPAL/.claude/worktrees/test-wt"
git -C "$PRINCIPAL" worktree add -q "$WORKTREE" -b test-branch

# Repo alheio (para gate-repo-alheio)
ALHEIO="$RAIZ/alheio"
git init -q "$ALHEIO"
git -C "$ALHEIO" config user.email test@test
git -C "$ALHEIO" config user.name test
git -C "$ALHEIO" config commit.gpgsign false
echo "outro repo" > "$ALHEIO/outro.txt"
git -C "$ALHEIO" add outro.txt
git -C "$ALHEIO" commit -qm "base"

echo

echo "== Testando os 6 gates com agent_id =="

# Helper: escape caminho para Windows/POSIX

# GATE 1: gate-worktree
# Subagente tenta Write fora do worktree isolado → recusado
echo "1. gate-worktree:"
PAYLOAD=$(node -e 'const [p,w]=process.argv.slice(1);const fp=p+"/outside.txt";console.log(JSON.stringify({cwd:w,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:"test"},agent_id:"agent-1",agent_type:"executor"}))' "$PRINCIPAL" "$WORKTREE")
testa_gate "gate-worktree" "$PAYLOAD"

# GATE 2: gate-staging-total
# Subagente tenta `git add -A` em repo com múltiplas sessões → recusado
# Para simular múltiplas sessões, precisamos criar o sessoes.json
echo "2. gate-staging-total:"
SESSOES_JSON="$PRINCIPAL/.rainforest/sessions.json"
mkdir -p "$(dirname "$SESSOES_JSON")"
node -e 'const fs=require("fs");const [p,j]=process.argv.slice(1);const sess={session1:{session_id:"sess1",parada:false,ultimo_ts:Date.now()-10000,cwd:p}};fs.writeFileSync(j,JSON.stringify(sess))' "$PRINCIPAL" "$SESSOES_JSON" 2>/dev/null || true
PAYLOAD=$(node -e 'const p=process.argv[1];console.log(JSON.stringify({cwd:p,session_id:"sess-diferente",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git add -A"},agent_id:"agent-2",agent_type:"executor"}))' "$PRINCIPAL")
testa_gate "gate-staging-total" "$PAYLOAD"

# GATE 3: gate-repo-alheio
# Subagente tenta Write em outro repositório → recusado
echo "3. gate-repo-alheio:"
# cwd do subagente é no PRINCIPAL, mas tenta escrever no ALHEIO
PAYLOAD=$(node -e 'const [a,p]=process.argv.slice(1);const fp=a+"/novo.txt";console.log(JSON.stringify({cwd:p,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:"dados"},agent_id:"agent-3",agent_type:"executor"}))' "$ALHEIO" "$PRINCIPAL")
testa_gate "gate-repo-alheio" "$PAYLOAD"

# GATE 4: gate-publicacao-destino
# Subagente tenta Write com dados sensíveis → recusado
echo "4. gate-publicacao-destino:"
# Gera JID em runtime (concatenação) para não deixar literal no arquivo
JID="5500"
JID="${JID}900000001@s.whatsapp.net"
PAYLOAD=$(node -e 'const [p,j]=process.argv.slice(1);const fp=p+"/test.txt";console.log(JSON.stringify({cwd:p,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:"contato: "+j},agent_id:"agent-4",agent_type:"executor"}))' "$PRINCIPAL" "$JID")
testa_gate "gate-publicacao-destino" "$PAYLOAD"

# GATE 5: gate-verificador-staged
# Subagente tenta git commit com SEGREDO staged → recusado
echo "5. gate-verificador-staged:"
STAGED_REPO="$RAIZ/staged-test"
mkdir -p "$STAGED_REPO"
mkdir -p "$STAGED_REPO/.rainforest"
mkdir -p "$STAGED_REPO/scripts"
git init -q "$STAGED_REPO"
git -C "$STAGED_REPO" config user.email test@test
git -C "$STAGED_REPO" config user.name test
git -C "$STAGED_REPO" config core.autocrlf false
echo "base" > "$STAGED_REPO/arquivo.txt"
git -C "$STAGED_REPO" add arquivo.txt
git -C "$STAGED_REPO" commit -qm "base"
cat > "$STAGED_REPO/.rainforest/config.json" <<'EOFCFG'
{"verificador-staged": "bash scripts/verifica.sh"}
EOFCFG
cat > "$STAGED_REPO/scripts/verifica.sh" << 'EOFSCRIPT'
#!/bin/bash
for arquivo in "$@"; do
  if grep -q "SEGREDO" "$arquivo" 2>/dev/null; then
    exit 1
  fi
done
exit 0
EOFSCRIPT
chmod +x "$STAGED_REPO/scripts/verifica.sh"
# Stage arquivo com SEGREDO
echo "contato: SEGREDO" > "$STAGED_REPO/arquivo.txt"
git -C "$STAGED_REPO" add arquivo.txt
PAYLOAD=$(node -e 'const s=process.argv[1];console.log(JSON.stringify({cwd:s,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit -m test"},agent_id:"agent-5",agent_type:"executor"}))' "$STAGED_REPO")
testa_gate "gate-verificador-staged" "$PAYLOAD"

# GATE 6: gate-git-verificacao (D10, #417)
# Subagente tenta `git commit --no-verify` → recusado, sem a secao de saidas
echo "6. gate-git-verificacao: subagente nao ve RAINFOREST_GATE_OFF"
PAYLOAD=$(node -e 'const p=process.argv[1];console.log(JSON.stringify({cwd:p,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit --no-verify -m x"},agent_id:"agent-6",agent_type:"executor"}))' "$PRINCIPAL")
testa_gate "gate-git-verificacao" "$PAYLOAD"

# Contraprova: a janela principal (sem agent_id) CONTINUA vendo a variavel
MSG6=$(node -e 'const p=process.argv[1];console.log(JSON.stringify({cwd:p,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit --no-verify -m x"}}))' "$PRINCIPAL" | node "$SRC/hooks/gate-git-verificacao.cjs" 2>&1)
if printf '%s' "$MSG6" | grep -q "RAINFOREST_GATE_OFF"; then
  echo "  ✓ gate-git-verificacao: a janela principal ainda ve RAINFOREST_GATE_OFF"; ok=$((ok+1))
else
  echo "  ✗ gate-git-verificacao: a janela principal deixou de ver a saida"; falhou=$((falhou+1))
fi

echo
echo "== Casos com aspas duplas para validar JSON.stringify ==="

# GATE 1: gate-worktree com aspas no file_path
echo "1. gate-worktree com aspas:"
PAYLOAD=$(node -e 'const [p,w]=process.argv.slice(1);const fp=p+"/\"outside\".txt";console.log(JSON.stringify({cwd:w,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:"test"},agent_id:"agent-1q",agent_type:"executor"}))' "$PRINCIPAL" "$WORKTREE")
testa_gate "gate-worktree" "$PAYLOAD"

# GATE 2: gate-repo-alheio com aspas no file_path
echo "2. gate-repo-alheio com aspas:"
PAYLOAD=$(node -e 'const [a,p]=process.argv.slice(1);const fp=a+"/\"novo\".txt";console.log(JSON.stringify({cwd:p,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:"dados"},agent_id:"agent-3q",agent_type:"executor"}))' "$ALHEIO" "$PRINCIPAL")
testa_gate "gate-repo-alheio" "$PAYLOAD"

# GATE 3: gate-verificador-staged com aspas no command
echo "3. gate-verificador-staged com aspas:"
PAYLOAD=$(node -e 'const s=process.argv[1];console.log(JSON.stringify({cwd:s,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit -m \"test message\""},agent_id:"agent-5q",agent_type:"executor"}))' "$STAGED_REPO")
testa_gate "gate-verificador-staged" "$PAYLOAD"

echo
echo "== Resultado: $ok ok   $falhou falha(s) =="
[ "$falhou" = 0 ]
