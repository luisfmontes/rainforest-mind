#!/bin/bash
# Bateria que prova a decisao D3: quando o hook estoura timeout,
# EXIT_n = 124 e ERR_n contem a mensagem "timeout: hook nao respondeu em <N> ms".
#
# O exportador de hooks de sessao precisa distinguir timeout de falha.
# Timeout em spawnSync vira status === null; a bateria monta um hooks.json
# sintetico com dois hooks: um que dorme 3s com timeout 1s, outro que imprime.
#
# Uso: bash scripts/testa-exporta-hooks-sessao-start.sh
# Saida: placar com "ok" e "FALHA"; exit 0 se todos ok, exit 1 se alguma falha.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

ok=0; falhou=0

# Caixa de areia com trap para cleanup
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

DADOS_POSIX="$(novo_sandbox)"
DADOS="$(cygpath -m "$DADOS_POSIX" 2>/dev/null || printf '%s' "$DADOS_POSIX")"

checa() { # nome, condicao(0=ok)
  local nome="$1" cond="$2"
  if [ "$cond" = "0" ]; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome"
  fi
}

# Monta hooks.json sintetico com os casos de teste
cat > "$DADOS_POSIX/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node -e \"setTimeout(()=>{},3000)\"",
            "timeout": 1
          },
          {
            "type": "command",
            "command": "node -e \"console.log('oi')\"",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "node -e \"process.exit(3)\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF

if [ ! -f "$DADOS_POSIX/hooks.json" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui criar o hooks.json sintetico"
  exit 1
else
  ok=$((ok+1)); echo "  ok    setup: hooks.json sintetico criado"
fi

echo
echo "1. HOOK COM TIMEOUT (3s dormindo, timeout 1s) → EXIT_1=124, ERR_1 com timeout"

eval "$(RFM_HOOKS_JSON="$DADOS_POSIX/hooks.json" RFM_ROOT="$DADOS" node "$SRC_WIN/scripts/exporta-hooks-sessao-start.cjs" "$DADOS" 2>&1)"

# Checar EXIT_1 = 124
[ "${EXIT_1:-}" = "124" ]
checa "EXIT_1 = 124 (timeout)" "$?"

# Checar ERR_1 contém "timeout"
echo "${ERR_1:-}" | grep -qF "timeout"
checa "ERR_1 contem 'timeout'" "$?"

# Checar ERR_1 contém "1000 ms"
echo "${ERR_1:-}" | grep -qF "1000 ms"
checa "ERR_1 contem '1000 ms'" "$?"

echo
echo "2. HOOK COM SUCESSO → EXIT_2=0, OUT_2 com 'oi'"

[ "${EXIT_2:-}" = "0" ]
checa "EXIT_2 = 0 (sucesso)" "$?"

echo "${OUT_2:-}" | grep -qF "oi"
checa "OUT_2 contem 'oi'" "$?"

echo
echo "3. HOOK COM FALHA PROPOSITAL (exit 3) → EXIT_3=3 (nao 124)"

[ "${EXIT_3:-}" = "3" ]
checa "EXIT_3 = 3 (falha, nao timeout)" "$?"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
