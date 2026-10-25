#!/bin/bash
# Bateria do conferir-prova.cjs: prova que sai ≠ 0 sem executar caso nenhum é recusada
# Uso: bash scripts/testa-conferir-prova-sem-caso.sh

set -u
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFERIR="$SCRIPTDIR/conferir-prova.cjs"

ok=0; falhou=0

# Sandboxes e limpeza
SANDBOXES=()
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

# Repo descartável, com as baterias de prova commitadas (a prova roda num
# worktree criado a partir do HEAD, então o arquivo precisa estar no commit)
R=$(mktemp -d)
SANDBOXES+=("$R")
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false)
mkdir -p "$R/scripts" "$R/docs/rainforest/planos"

printf '%s\n' 'echo "ok: 0   falhou: 0"' 'exit 1' > "$R/scripts/vermelho-sem-caso.sh"
printf '%s\n' 'echo "ok: 3   falhou: 1"' 'exit 1' > "$R/scripts/vermelho-com-casos.sh"
printf '%s\n' 'echo "0 ok, 0 falhou"' 'exit 1' > "$R/scripts/vermelho-formato-dois.sh"
printf '%s\n' 'echo "quebrou antes de qualquer placar"' 'exit 1' > "$R/scripts/vermelho-sem-placar.sh"
printf '%s\n' 'echo "== resultado: 0 ok, 0 falha(s) =="' 'exit 1' > "$R/scripts/vermelho-resultado-falha-s.sh"
printf '%s\n' 'echo "ok: 0   falha(s): 0"' 'exit 1' > "$R/scripts/vermelho-ok-falha-s-zero.sh"
printf '%s\n' 'echo "== resultado: 3 ok, 1 falha(s) =="' 'exit 1' > "$R/scripts/vermelho-resultado-com-casos.sh"

(cd "$R" && git add -A && git commit -qm "baterias de prova")

W="$(cygpath -m "$R" 2>/dev/null || printf '%s' "$R")"
P="$R/docs/rainforest/planos/t.md"

echo "(caixa de areia: $W)"
echo

# Um caso = um plano com uma tarefa implementar cuja prova é $4.
# Confere exit esperado e, quando $3 não é "-", que a saída case com a regex.
caso() {
  local nome="$1" esp="$2" rx="$3" prova="$4"
  printf '# Plano sem caso\n\n## Tarefas\n\n### 1. Caso [tipo: implementar]\natende: D1\narquivos: scripts/x.cjs\nprova: `%s`\npronto quando: ok\n' "$prova" > "$P"
  local saida got
  saida=$(RFM_ESTADO_ROOT="$W" node "$CONFERIR" plano --slug t --plano "$P" 2>&1); got=$?
  if [ "$got" = "$esp" ] && { [ "$rx" = "-" ] || printf '%s' "$saida" | grep -qF -- "$rx"; }; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    printf '%s\n' "$saida" | sed 's/^/         /' | tail -4
  fi
}

echo "== 1. Placar com zero casos (ok: 0 falhou: 0) =="
caso "prova que sai 1 com placar ok: 0 falhou: 0 é recusada" 2 \
  "a prova não executou caso nenhum na base" \
  "bash scripts/vermelho-sem-caso.sh"
caso "placar em forma '0 ok, 0 falhou' também é recusado" 2 \
  "a prova não executou caso nenhum na base" \
  "bash scripts/vermelho-formato-dois.sh"
caso "'== resultado: 0 ok, 0 falha(s) ==' com exit 1 é recusada" 2 \
  "a prova não executou caso nenhum na base" \
  "bash scripts/vermelho-resultado-falha-s.sh"
caso "'ok: 0   falha(s): 0' com exit 1 é recusada" 2 \
  "a prova não executou caso nenhum na base" \
  "bash scripts/vermelho-ok-falha-s-zero.sh"

echo
echo "== 2. Placar com casos executados e falha =="
caso "prova que sai 1 com ok: 3 falhou: 1 é aceita" 0 "-" \
  "bash scripts/vermelho-com-casos.sh"
caso "'== resultado: 3 ok, 1 falha(s) ==' com exit 1 é aceita" 0 "-" \
  "bash scripts/vermelho-resultado-com-casos.sh"

echo
echo "== 3. Saída sem placar reconhecível =="
caso "prova que sai 1 sem placar reconhecível é aceita (como hoje)" 0 "-" \
  "bash scripts/vermelho-sem-placar.sh"

echo
echo "== 4. Arquivo ausente na base (126/127 na forma simples) =="
caso "bash <arquivo ausente na base> continua aceita" 0 "-" \
  "bash scripts/nao-existe-ainda.sh"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
