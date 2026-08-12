#!/bin/bash
# Bateria do conferir-entrega.py. Monta um repo git de verdade com worktree de
# verdade e ENCENA cada uma das seis falhas dos dois relatorios, exigindo que
# cada uma reprove. Uso: bash scripts/testa-conferir-entrega.sh
#
# Por que encenar em vez de simular saida: o script existe justamente porque
# relato nao e evidencia. Testa-lo com git falso repetiria o erro que ele
# conserta (regra 12).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$SRC/scripts/conferir-entrega.py"
RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | tail -12
  fi
}
contem() { # nome, texto, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -qi -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}

# ---------------------------------------------------------------- cenario
novo_repo() { # $1 = nome
  local R="$RAIZ/$1"
  git init -q "$R"
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  echo v1 > "$R/a.txt"; git -C "$R" add .; git -C "$R" commit -qm base
  echo v1 > "$R/rastreado.txt"; git -C "$R" add .; git -C "$R" commit -qm segundo
  echo "$R"
}

R=$(novo_repo principal)
BASE=$(git -C "$R" rev-parse HEAD)
HEAD_ANTES=$BASE
WT="$RAIZ/wt-bom"
git -C "$R" worktree add -q -b trabalho "$WT" >/dev/null 2>&1
echo novo > "$WT/feito.txt"; git -C "$WT" add .; git -C "$WT" commit -qm "entrega"

echo "== entrega correta =="
esperado "worktree real, base certa, tudo limpo -> aprovado" 0 \
  python "$CONF" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"

echo
echo "== as seis falhas dos relatorios =="

# 1 — trabalhou no diretorio principal em vez do worktree
esperado "agente no repo principal (nao e worktree linkado)" 1 \
  python "$CONF" --worktree "$R" --base "$BASE" --head-antes "$HEAD_ANTES"
contem "  ... e diz que faltou 'worktrees' no git-dir" "worktrees" \
  python "$CONF" --worktree "$R" --base "$BASE"

# 2 — commit sobre base errada
OUTRA=$(git -C "$R" rev-parse HEAD~1)
WT2="$RAIZ/wt-base-errada"
git -C "$R" worktree add -q -b desviada "$WT2" "$OUTRA" >/dev/null 2>&1
echo x > "$WT2/x.txt"; git -C "$WT2" add .; git -C "$WT2" commit -qm "sobre base velha"
esperado "commit fora da historia da base do briefing" 1 \
  python "$CONF" --worktree "$WT2" --base "$BASE"
contem "  ... e recusa a auto-absolvicao" "conclusao da janela principal" \
  python "$CONF" --worktree "$WT2" --base "$BASE"

# 3 — sujeira nao commitada
echo sujo > "$WT/solto.txt"
esperado "entrega com arquivo nao commitado" 1 python "$CONF" --worktree "$WT" --base "$BASE"
esperado "  ... dispensavel por --permite-sujeira" 0 \
  python "$CONF" --worktree "$WT" --base "$BASE" --permite-sujeira
rm "$WT/solto.txt"

# 4 — arquivo rastreado apagado (N3)
rm "$WT/rastreado.txt"
esperado "arquivo rastreado apagado como dano colateral" 1 python "$CONF" --worktree "$WT" --base "$BASE"
contem "  ... nomeando a falha N3" "N3" python "$CONF" --worktree "$WT" --base "$BASE"
git -C "$WT" checkout -q -- rastreado.txt

# 5 — mexeu no diretorio principal (N1)
echo intruso > "$R/intruso.txt"
esperado "alteracao no diretorio principal do usuario" 1 \
  python "$CONF" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
rm "$R/intruso.txt"

# 6 — HEAD do principal movido (N1, o stash/pop)
git -C "$R" checkout -q HEAD~1
esperado "HEAD do repo principal movido durante a tarefa" 1 \
  python "$CONF" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
git -C "$R" checkout -q "$HEAD_ANTES"

echo
echo "== bordas =="
esperado "worktree inexistente -> exit 2, nao 0" 2 \
  python "$CONF" --worktree "$RAIZ/nao-existe" --base "$BASE"
esperado "sem --base ainda roda, com aviso" 0 \
  python "$CONF" --worktree "$WT" --head-antes "$HEAD_ANTES"
contem "  ... e o aviso diz que o briefing devia ter fixado a base" "briefing devia ter fixado" \
  python "$CONF" --worktree "$WT" --head-antes "$HEAD_ANTES"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
