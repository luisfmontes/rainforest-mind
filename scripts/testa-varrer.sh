#!/bin/bash
# Bateria do varrer.cjs — coleta estruturada de issues, PRs, branches e commits.
#
# Monta um repositório descartável com issue, PR, branch e commit citando um termo,
# um ideias.jsonl de sandbox com uma ideia secreta, e um dublê de gh que devolve
# Issues/PRs diferentes para --state all vs --state open.
#
# Uso: bash scripts/testa-varrer.sh

set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/varrer.cjs"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/           /' | tail -12
  fi
}

contem() { # nome, arquivo_ou_saida, texto
  local nome="$1" alvo="$2" txt="$3"
  if grep -q -F "$txt" "$alvo" 2>/dev/null; then ok=$((ok+1)); echo "  ok    $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"
  fi
}

nao_contem() { # nome, arquivo_ou_saida, texto
  local nome="$1" alvo="$2" txt="$3"
  if ! grep -q -F "$txt" "$alvo" 2>/dev/null; then ok=$((ok+1)); echo "  ok    $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: encontrei '$txt' quando nao deveria"
  fi
}

# ================================================================ Montar sandbox

# Criar ideias.jsonl no sandbox com uma ideia secreta
RAINFOREST="$SANDBOX/.rainforest"
mkdir -p "$RAINFOREST"
cat > "$RAINFOREST/ideias.jsonl" <<'EOF'
{"id":"x-travas","titulo":"Ideia sobre travas","descricao":"SEGREDO-NAO-PODE-SAIR","contexto":"teste","projeto":"test","gancho":"verificar","status":"plantada"}
EOF

# Criar dublê de gh que simula resposta real
GH_MOCK="$SANDBOX/gh-mock.cjs"
cat > "$GH_MOCK" <<'EOF'
#!/usr/bin/env node
const args = process.argv.slice(2);
const stateIdx = args.indexOf('--state');
const state = stateIdx >= 0 ? args[stateIdx + 1] : '';

if (args[0] === 'issue') {
  if (state === 'all') {
    console.log(JSON.stringify([
      {number: 253, title: 'Travas do semear #253', state: 'CLOSED'}
    ]));
  } else {
    console.log('[]');
  }
} else if (args[0] === 'pr') {
  if (state === 'all') {
    console.log(JSON.stringify([
      {number: 99, title: 'PR sobre travas #99', state: 'MERGED'}
    ]));
  } else {
    console.log('[]');
  }
}
EOF
chmod +x "$GH_MOCK"

# ================================================================ Testes

echo "== Issue FECHADA e PR merged com --state all =="
RFM_ESTADO_ROOT="$RAINFOREST" RFM_VARRER_GH="$GH_MOCK" \
  bash -c "node '$SCRIPT' --slug teste travas >/dev/null 2>&1"
TXT="$RAINFOREST/docs/rainforest/varredura/teste.txt"
esperado "Issue FECHADA com o termo aparece na varredura (o caso #253)" 0 \
  test -f "$TXT"
contem "Issue #253 aparece no .txt" "$TXT" "Travas do semear #253"
contem "PR #99 aparece no .txt" "$TXT" "PR sobre travas #99"

echo
echo "== Ideia gravada sem descricao =="
contem "Ideia sai so com id e titulo (descricao secreta ausente do .txt)" "$TXT" '"id":"x-travas"'
nao_contem "Descricao secreta nao sai" "$TXT" "SEGREDO-NAO-PODE-SAIR"

echo
echo "== gh ausente e nenhum arquivo gravado =="
esperado "gh ausente: exit 69 e nenhum arquivo gravado" 69 \
  bash -c "RFM_ESTADO_ROOT='$RAINFOREST' RFM_VARRER_GH='$SANDBOX/nao-existe.cjs' node '$SCRIPT' --slug teste2 travas >/dev/null 2>&1"
test ! -f "$RAINFOREST/docs/rainforest/varredura/teste2.txt" && ok=$((ok+1)) && echo "  ok    nenhum arquivo gravado em exit 69" || { falhou=$((falhou+1)); echo "  FALHA nenhum arquivo gravado em exit 69"; }

echo
echo "== Comandos executados aparecem no .txt =="
contem "O .txt cita cada comando executado" "$TXT" "gh issue list --state all --search"
contem "Comando gh pr aparece" "$TXT" "gh pr list --state all --search"

echo
echo "== Validacoes de argumento =="
esperado "sem termo: exit 2" 2 \
  bash -c "RFM_ESTADO_ROOT='$RAINFOREST' node '$SCRIPT' --slug teste"
esperado "sem --slug: exit 2" 2 \
  bash -c "RFM_ESTADO_ROOT='$RAINFOREST' node '$SCRIPT' travas"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
