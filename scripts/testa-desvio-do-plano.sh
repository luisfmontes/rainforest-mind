#!/bin/bash
# @categoria: bateria
# Bateria do scripts/desvio-do-plano.cjs (arquivo escrito x `arquivos:` do plano do fluxo).
#
# EXECUTA o script real contra um repo temporario com `git init` + `git worktree add`, o plano
# real 2026-10-03-mod-faixa-foco.md (via `git show`) e um estado em `executar`.
# Nunca le o ~/.rainforest vivo: HOME, USERPROFILE e RFM_ROOT apontam para caixas.
#
# Casos: dentro, fora, isento, fora-da-raiz, sem-fluxo, sem-plano, caminho absoluto Windows
# (barras invertidas, drive em caixa diferente), worktree agent-*, exit 2 sem argumento.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC/scripts/desvio-do-plano.cjs"
SLUG=2026-10-03-mod-faixa-foco
PLANO_REL="docs/rainforest/planos/$SLUG.md"

SANDBOXES=()
novo_sandbox() {
  local d; d=$(mktemp -d)
  if command -v cygpath >/dev/null 2>&1; then d=$(cygpath -m "$d"); fi
  SANDBOXES+=("$d"); echo "$d"
}
limpar() { local d; for d in "${SANDBOXES[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap limpar EXIT

OK=0; FALHA=0
passa() { OK=$((OK + 1)); echo "ok   $1"; }
falha() { FALHA=$((FALHA + 1)); echo "FALHA $1"; [ -n "${2:-}" ] && echo "     $2"; }

CAIXA_HOME=$(novo_sandbox)
RAIZ_VAZIA=$(novo_sandbox)

# rodar <cwd> <arquivo>: stdout em $SAIDA, exit em $CODIGO
rodar() {
  SAIDA=$(env -u CLAUDE_PROJECT_DIR HOME="$CAIXA_HOME" USERPROFILE="$CAIXA_HOME" RFM_ROOT="$RAIZ_VAZIA" \
    node "$SCRIPT" --cwd "$1" --arquivo "$2" 2>"$CAIXA_HOME/stderr.txt")
  CODIGO=$?
}
# veredito <nome> <esperado> [rel esperado]
veredito() {
  local nome="$1" esp="$2" rel="${3:--}"
  if [ "$CODIGO" -ne 0 ]; then falha "$nome" "exit=$CODIGO stderr=$(cat "$CAIXA_HOME/stderr.txt")"; return; fi
  if printf '%s' "$SAIDA" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const ok = d.veredito === '$esp' && ('$rel' === '-' || d.rel === '$rel');
    if (!ok) { console.error(JSON.stringify(d)); process.exit(1); }
  " 2>"$CAIXA_HOME/asserta.txt"; then passa "$nome"; else falha "$nome" "$(cat "$CAIXA_HOME/asserta.txt")"; fi
}
estado() { mkdir -p "$1/docs/rainforest/estado"; printf '%s' "$3" > "$1/docs/rainforest/estado/$2.json"; }

REPO=$(novo_sandbox)
WT="$REPO-wt"; SANDBOXES+=("$WT")
AGENTE="$REPO/.claude/worktrees/agent-abc123"
SEMPLANO="$REPO-sp"; SANDBOXES+=("$SEMPLANO")
SEMARQ="$REPO-sa"; SANDBOXES+=("$SEMARQ")
git init -q "$REPO" >/dev/null 2>&1
cd "$REPO" || exit 1
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
git worktree add -q -b ramo "$WT" >/dev/null 2>&1
git worktree add -q -b ramo-agente "$AGENTE" >/dev/null 2>&1
git worktree add -q -b ramo-sp "$SEMPLANO" >/dev/null 2>&1
git worktree add -q -b ramo-sa "$SEMARQ" >/dev/null 2>&1
cd "$SRC" || exit 1
[ -d "$WT" ] && [ -d "$AGENTE" ] && [ -d "$SEMPLANO" ] || { echo "FALHA montagem do worktree temporario"; exit 1; }

# Plano real, via git show (nao leitura do disco do checkout).
mkdir -p "$WT/docs/rainforest/planos"
git show "HEAD:$PLANO_REL" > "$WT/$PLANO_REL"
[ -s "$WT/$PLANO_REL" ] || { echo "FALHA git show do plano real vazio"; exit 1; }
estado "$WT" "$SLUG" "{\"slug\":\"$SLUG\",\"titulo\":\"Faixa\",\"criado_em\":\"2026-10-03\",\"design\":{\"status\":\"aprovado\"},\"plano\":{\"status\":\"ok\"}}"
mkdir -p "$WT/hooks"

rodar "$WT" "$WT/hooks/faixa-puro.mjs";               veredito "arquivo declarado no plano e dentro" dentro "hooks/faixa-puro.mjs"
rodar "$WT" "$WT/README.md";                          veredito "README declarado e dentro" dentro "README.md"
rodar "$WT" "$WT/scripts/estado.cjs";                 veredito "arquivo fora dos arquivos do plano e acusado" fora "scripts/estado.cjs"
rodar "$WT" "$WT/tsconfig.json";                      veredito "tsconfig fora do plano e acusado" fora "tsconfig.json"
rodar "$WT" "$WT/docs/rainforest/design/$SLUG.md";    veredito "design do proprio slug e isento" isento
rodar "$WT" "$WT/$PLANO_REL";                         veredito "plano do proprio slug e isento" isento
rodar "$WT" "$CAIXA_HOME/qualquer.txt";               veredito "arquivo em TEMP e fora-da-raiz" fora-da-raiz
rodar "$WT/hooks" "faixa-puro.mjs";                   veredito "cwd em subpasta, caminho relativo ao cwd" dentro "hooks/faixa-puro.mjs"

# Caminho absoluto de Windows: barras invertidas e drive em caixa diferente.
if command -v cygpath >/dev/null 2>&1; then
  WINPATH=$(cygpath -w "$WT/hooks/faixa-puro.mjs")
  rodar "$WT" "$WINPATH";                             veredito "absoluto Windows com barras invertidas" dentro "hooks/faixa-puro.mjs"
  PRIMEIRA=${WINPATH:0:1}
  MAIUSC=$(echo "$PRIMEIRA" | tr a-z A-Z)
  if [ "$PRIMEIRA" = "$MAIUSC" ]; then TROCADA=$(echo "$PRIMEIRA" | tr A-Z a-z); else TROCADA=$MAIUSC; fi
  rodar "$WT" "$TROCADA${WINPATH:1}";                 veredito "drive em caixa diferente" dentro "hooks/faixa-puro.mjs"
else
  rodar "$WT" "$WT/hooks/faixa-puro.mjs";             veredito "absoluto Windows com barras invertidas (so Windows: absoluto comum)" dentro "hooks/faixa-puro.mjs"
  rodar "$WT" "$WT/hooks/faixa-puro.mjs";             veredito "drive em caixa diferente (so Windows: absoluto comum)" dentro "hooks/faixa-puro.mjs"
fi

# Worktree agent-*: relativiza contra a raiz do agente, nao contra a do repo principal.
rodar "$WT" "$AGENTE/hooks/faixa-puro.mjs";           veredito "arquivo em worktree agent-* relativiza contra a raiz dele" dentro "hooks/faixa-puro.mjs"
rodar "$WT" "$AGENTE/scripts/estado.cjs";             veredito "arquivo fora do plano em worktree agent-*" fora "scripts/estado.cjs"

# sem-fluxo: o principal e o agente nao tem fluxo registrado como worktree deles.
rodar "$REPO" "$REPO/hooks/faixa-puro.mjs";           veredito "diretorio sem fluxo em curso e sem-fluxo" sem-fluxo
rodar "$AGENTE" "$AGENTE/hooks/faixa-puro.mjs";       veredito "worktree agent-* sem fluxo proprio e sem-fluxo" sem-fluxo
NAOREPO=$(novo_sandbox)
rodar "$NAOREPO" "$NAOREPO/x.txt";                    veredito "diretorio que nao e repo e sem-fluxo" sem-fluxo

# fluxo concluido nao conta como em curso.
estado "$WT" concluido '{"slug":"concluido","criado_em":"2026-10-01","design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":{"status":"ok"},"verificar":{"status":"ok"},"fechar":{"status":"ok"}}'
rodar "$WT" "$WT/hooks/faixa-puro.mjs";               veredito "fluxo concluido nao atrapalha o em curso" dentro

# sem-plano: fluxo em curso sem arquivo de plano.
estado "$SEMPLANO" sem-plano-x '{"slug":"sem-plano-x","criado_em":"2026-10-04","design":{"status":"aprovado"}}'
rodar "$SEMPLANO" "$SEMPLANO/hooks/faixa-puro.mjs";   veredito "fluxo sem arquivo de plano e sem-plano" sem-plano

# sem-arquivos: plano existente sem nenhum `arquivos:` nao acusa nada.
estado "$SEMARQ" sem-arq-x '{"slug":"sem-arq-x","criado_em":"2026-10-04","design":{"status":"aprovado"}}'
mkdir -p "$SEMARQ/docs/rainforest/planos"
printf '### 1. Tarefa [tipo: implementar]\n\narquivos: nenhum\n' > "$SEMARQ/docs/rainforest/planos/sem-arq-x.md"
rodar "$SEMARQ" "$SEMARQ/hooks/qualquer.mjs";         veredito "plano sem arquivos: e sem-arquivos, nao fora" sem-arquivos

# Sem argumento: exit 2.
env HOME="$CAIXA_HOME" USERPROFILE="$CAIXA_HOME" RFM_ROOT="$RAIZ_VAZIA" node "$SCRIPT" --cwd "$WT" >/dev/null 2>&1
[ $? -eq 2 ] && passa "sem --arquivo sai 2" || falha "sem --arquivo sai 2"
env HOME="$CAIXA_HOME" USERPROFILE="$CAIXA_HOME" RFM_ROOT="$RAIZ_VAZIA" node "$SCRIPT" --arquivo x >/dev/null 2>&1
[ $? -eq 2 ] && passa "sem --cwd sai 2" || falha "sem --cwd sai 2"

echo "ok: $OK   falhou: $FALHA   skipped: 0"
[ "$FALHA" -eq 0 ]
