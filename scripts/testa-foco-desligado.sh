#!/bin/bash
# Bateria do aviso do /foco com a chave `foco` desligada (2.0.0, D8 do design
# 2026-10-25-versao-2-0-0).
#
# Desde a 2.0.0 o foco nasce desligado: o /foco grava o FOCO.md como sempre, mas o
# foco so entra na abertura com `foco: true`. O /foco roda `foco.cjs aviso` depois de
# gravar, e e esse verbo que diz ao usuario como ligar. Sem o aviso, quem declara um
# foco acredita que o radar passou a valer, e ele nao passou.
#
# Tudo roda numa caixa `mktemp -d` com RFM_ROOT e cwd num projeto falso: nenhum caso
# le ou escreve o config real do usuario.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3', veio '$2')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

mkdir -p "$SBP/dados" "$SBP/proj"
printf '# Foco\n\n## Ativo\n\n**Foco de caixa** — declarado 2026-10-25.\n' > "$SBP/dados/FOCO.md"

# Devolve a saida do verbo e, na ultima linha, o exit.
aviso() { (cd "$SBP/proj" && env -u CLAUDE_PROJECT_DIR RFM_ROOT="$SBP/dados" node "$SRC/scripts/foco.cjs" aviso 2>&1; echo "exit=$?"); }

echo "== 1. declarar com a chave desligada avisa que o foco só entra na abertura com foco: true =="
rm -f "$SBP/dados/config.json"
S="$(aviso)"
tem     "sem config.json: o aviso sai" "$S" "só entra na abertura com foco: true"
tem     "o aviso diz como ligar" "$S" "setup.cjs --ligar foco"
tem     "sai 0" "$S" "exit=0"

printf '{"foco": false}' > "$SBP/dados/config.json"
S="$(aviso)"
tem     "foco: false: o aviso sai" "$S" "só entra na abertura com foco: true"

printf '{quebrado' > "$SBP/dados/config.json"
S="$(aviso)"
tem     "config ilegivel conta como desligado: o aviso sai" "$S" "só entra na abertura com foco: true"
tem     "config ilegivel nao derruba o verbo" "$S" "exit=0"

echo
echo "== 2. com foco: true, nada a avisar =="
printf '{"foco": true}' > "$SBP/dados/config.json"
S="$(aviso)"
nao_tem "foco: true: sem aviso" "$S" "só entra na abertura"
igual   "a unica linha e o exit" "$S" "exit=0"

# O projeto vem do CLAUDE_PROJECT_DIR antes do cwd, como no setup e na abertura
# (achado 5 da revisao): shell em outra pasta, projeto com foco ligado, sem aviso.
rm -f "$SBP/dados/config.json"
mkdir -p "$SBP/proj/.rainforest" "$SBP/outra"
printf '{"foco": true}' > "$SBP/proj/.rainforest/config.json"
S="$( (cd "$SBP/outra" && CLAUDE_PROJECT_DIR="$SBP/proj" RFM_ROOT="$SBP/dados" node "$SRC/scripts/foco.cjs" aviso 2>&1; echo "exit=$?") )"
nao_tem "foco ligado no CLAUDE_PROJECT_DIR, cwd em outra pasta: sem aviso" "$S" "só entra na abertura"
rm -f "$SBP/proj/.rainforest/config.json"

echo
echo "== 3. o /foco chama o verbo depois de gravar =="
tem     "commands/foco.md cita foco.cjs aviso" "$(cat "$SRC/commands/foco.md")" 'scripts/foco.cjs" aviso'

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
