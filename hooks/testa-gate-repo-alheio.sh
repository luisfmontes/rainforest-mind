#!/bin/bash
# Bateria do gate-repo-alheio.cjs. Monta dois repos git de verdade e
# alimenta o hook com payloads reais de PreToolUse, conferindo o exit code.
# Uso: bash hooks/testa-gate-repo-alheio.sh
#
# O que esta bateria precisa provar, nesta ordem:
#   1. que BARRA escrita em repo alheio (exit 2);
#   2. que NAO barra escrita no MESMO repo, em caminho fora de git, nem
#      worktree linkado do mesmo repo — falso positivo aqui atrapalha o
#      usuario em todos os repos, entao os casos que devem PASSAR sao a maioria.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-repo-alheio.cjs"
# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o gate libera — a bateria passaria verde
# testando nada. Custou uma rodada inteira em 2026-08-09.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Issue #160: a bateria lia a config REAL de quem a roda — quem desligou um gate
# no escopo usuario pelo `/setup` via a suite vermelha sem pista da causa. A raiz
# de dados passa a ser uma pasta descartavel, como faz o `testa-orcamento.sh`
# (Issue #81). Caso que precisa de outra raiz sobrescreve por chamada.
export RFM_ROOT="$RAIZ/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -6; fi
}

# Repo da sessao
R1="$RAIZ/sessao"; git init -q "$R1"; git -C "$R1" config user.email t@t; git -C "$R1" config user.name t
git -C "$R1" config commit.gpgsign false
echo v1 > "$R1/a.txt"; git -C "$R1" add .; git -C "$R1" commit -qm base

# Worktree do MESMO repo
WT1="$RAIZ/wt-sessao"; git -C "$R1" worktree add -q -b trabalho "$WT1" >/dev/null 2>&1

# Outro repo git (alheio)
R2="$RAIZ/outro"; git init -q "$R2"; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
git -C "$R2" config commit.gpgsign false
echo v1 > "$R2/b.txt"; git -C "$R2" add .; git -C "$R2" commit -qm base

# Caminho fora de repo git
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"

# Submodulo de verdade dentro do repo da sessao. Para o git e repositorio
# DIFERENTE (git-dir em R1/.git/modules/sub), e foi por isso que a primeira
# versao da trava barrava escrita legitima ali. Achado pelo revisar em
# 2026-08-26 — nem o design nem o plano tinham considerado submodulo.
git -c protocol.file.allow=always -C "$R1" submodule add -q "$R2" sub >/dev/null 2>&1
TEM_SUB=0; [ -d "$R1/sub" ] && TEM_SUB=1

# Repo aninhado SEM relacao de submodulo: `git init` na mao dentro do
# checkout da sessao. Mesmo ponto de codigo, e passa pela mesma razao —
# esta DENTRO da arvore desta sessao, entao nao e trabalho alheio.
ANIN="$R1/aninhado"; git init -q "$ANIN"; git -C "$ANIN" config user.email t@t
git -C "$ANIN" config user.name t; git -C "$ANIN" config commit.gpgsign false

esc() { printf '%s' "$1" | sed 's|\\|/|g'; }

# payload de SUBAGENTE que escreve em alvo especifico
j() { # tool, file_path, cwd
  printf '{"agent_id":"ag-1","agent_type":"executor","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
    "$(esc "$3")" "$1" "$(esc "$2")"
}

# payload de JANELA PRINCIPAL (SEM agent_id) — e' o caso do incidente de
# 2026-08-23: a sessao cujo cwd era C:/Projetos/whatsapp-mcp foi consertar o
# rainforest-mind dali mesmo. Nao ha subagente nenhum nessa historia, e um
# gate que so olha subagente nao teria visto o defeito que existe para pegar.
p() { # tool, file_path, cwd
  printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
    "$(esc "$3")" "$1" "$(esc "$2")"
}

echo "== deve BARRAR (exit 2) — escrita em repo alheio =="
gate "subagente escreve em outro repo (Write)"       2 "$(j Write "$R2/novo.txt" "$R1")"
gate "subagente escreve em outro repo (Edit)"        2 "$(j Edit "$R2/b.txt" "$R1")"
gate "escrita em subdir do outro repo"               2 "$(j Write "$R2/dir/arquivo.txt" "$R1")"
gate "JANELA PRINCIPAL escreve em outro repo (incidente)" 2 "$(p Write "$R2/novo.txt" "$R1")"
gate "JANELA PRINCIPAL edita em outro repo"            2 "$(p Edit "$R2/b.txt" "$R1")"

echo
echo "== deve PASSAR (exit 0) — repo da sessao, fora de git, worktree do mesmo repo =="
gate "escreve no repo da sessao (Write)"             0 "$(j Write "$R1/novo.txt" "$R1")"
gate "edita no repo da sessao (Edit)"                0 "$(j Edit "$R1/a.txt" "$R1")"
gate "escreve em subdir do repo da sessao"           0 "$(j Write "$R1/dir/arquivo.txt" "$R1")"
gate "escreve fora de repo git"                      0 "$(j Write "$FORA/nota.txt" "$R1")"
gate "escreve em worktree linkado do MESMO repo"     0 "$(j Write "$WT1/novo.txt" "$R1")"
gate "edita em worktree linkado do MESMO repo"       0 "$(j Edit "$WT1/a.txt" "$R1")"
gate "JANELA PRINCIPAL escreve no repo da sessao"   0 "$(p Write "$R1/novo.txt" "$R1")"
gate "JANELA PRINCIPAL escreve fora de repo git"    0 "$(p Write "$FORA/nota.txt" "$R1")"
gate "JANELA PRINCIPAL em worktree do MESMO repo"   0 "$(p Write "$WT1/novo.txt" "$R1")"
gate "escreve em repo ANINHADO dentro da sessao"   0 "$(j Write "$ANIN/x.txt" "$R1")"
gate "JANELA PRINCIPAL em repo aninhado"           0 "$(p Write "$ANIN/x.txt" "$R1")"
if [ "$TEM_SUB" = 1 ]; then
  gate "escreve dentro de SUBMODULO do repo da sessao" 0 "$(j Write "$R1/sub/x.txt" "$R1")"
  gate "JANELA PRINCIPAL dentro de submodulo"          0 "$(p Write "$R1/sub/b.txt" "$R1")"
else
  echo "  (pulado: git submodule add nao funcionou nesta maquina — 2 casos NAO rodaram)"
fi

# `file_path` RELATIVO, com o processo do hook rodando FORA de git: o alvo
# tem que ser resolvido contra o cwd do EVENTO, nao contra o do processo.
# Resolvendo contra o do processo, o gate cai em "fora de git" e libera pelo
# motivo errado, sem nunca avaliar o caminho. Achado pelo revisar.
# O processo roda em $FORA/fundo, DUAS pastas fundo, de proposito: em $FORA o
# relativo "../outro" resolveria por acidente contra $RAIZ/outro, que e o R2 —
# e a mutacao do conserto passaria verde. Foi o que aconteceu na primeira
# tentativa deste caso. Aqui "../outro" nao existe, e so o cwd do EVENTO resolve.
mkdir -p "$FORA/fundo"
saida=$(cd "$FORA/fundo" && printf '%s' "$(j Write "../outro/b.txt" "$R1")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   relativo resolve contra o cwd do EVENTO, e barra (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA relativo nao foi avaliado: esperava 2, veio $rc"; fi
saida=$(cd "$FORA/fundo" && printf '%s' "$(j Write "a.txt" "$R1")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   relativo no proprio repo da sessao passa (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA relativo no proprio repo barrou: esperava 0, veio $rc"; fi

echo
echo "== tool_name que nao e escrita passa =="
gate "Bash (Read) no outro repo"                     0 \
  "$(printf '{"agent_id":"ag-1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"cat %s"}}' "$(esc "$R1")" "$(esc "$R2/b.txt")")"

echo
echo "== saidas de emergencia =="
saida=$(printf '%s' "$(j Write "$R2/novo.txt" "$R1")" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF nao liberou (exit $rc)"; fi

touch "$R2/.rainforest-gate-off"
gate ".rainforest-gate-off na raiz do outro repo libera" 0 "$(j Write "$R2/novo.txt" "$R1")"
rm "$R2/.rainforest-gate-off"
gate "  ... e volta a barrar quando o arquivo sai"      2 "$(j Write "$R2/novo.txt" "$R1")"

echo
echo "== casos-limite =="
gate "payload vazio nunca trava"                     0 "{}"
gate "payload ilegivel nunca trava"                  0 "isto nao e json"
gate "janela principal sem cwd nunca trava"           0 \
  "$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$(esc "$R2/novo.txt")")"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
