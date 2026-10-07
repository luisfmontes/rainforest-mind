#!/bin/bash
# Bateria do scripts/faixa-dados.cjs (dados do painel do mod: fluxos em curso).
#
# EXECUTA o script real contra um repo temporario com `git init` + `git worktree add`.
# Nunca le o ~/.rainforest vivo: HOME e USERPROFILE apontam para uma caixa e RFM_ROOT
# para outra, entao a cadeia de resolverRaiz so ve o que a bateria montou.
#
# Casos:
#   1. copia velha no principal x copia avancada no worktree: vale a avancada
#   2. "fluxo completo nao entra na lista"
#   3. estado ilegivel ignorado, com aviso no stderr e exit 0
#   4. o foco saiu do JSON: nem sem FOCO.md nem com ele a chave `foco` existe (D2)
#   5. diretorio que nao e repo cai para [cwd]
#   6. ordem: criado_em desc, depois slug desc
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC/scripts/faixa-dados.cjs"

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

# rodar <cwd> [RFM_ROOT]: stdout em $SAIDA, stderr em $ERRO, exit em $CODIGO
rodar() {
  local cwd="$1" rfm="${2:-$RAIZ_VAZIA}"
  SAIDA=$(env -u CLAUDE_PROJECT_DIR HOME="$CAIXA_HOME" USERPROFILE="$CAIXA_HOME" RFM_ROOT="$rfm" \
    node "$SCRIPT" --cwd "$cwd" 2>"$CAIXA_HOME/stderr.txt")
  CODIGO=$?
  ERRO=$(cat "$CAIXA_HOME/stderr.txt")
}

# checa <nome> <expressao js sobre d>: verdadeira = passa
checa() {
  local nome="$1" expr="$2"
  if [ "$CODIGO" -ne 0 ]; then falha "$nome" "exit=$CODIGO stderr=$ERRO"; return; fi
  if printf '%s' "$SAIDA" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    if (!($expr)) { console.error(JSON.stringify(d)); process.exit(1); }
  " 2>"$CAIXA_HOME/asserta.txt"; then passa "$nome"; else falha "$nome" "$(cat "$CAIXA_HOME/asserta.txt")"; fi
}

estado() { # estado <dir> <slug> <json>
  mkdir -p "$1/docs/rainforest/estado"
  printf '%s' "$3" > "$1/docs/rainforest/estado/$2.json"
}

REPO=$(novo_sandbox)
WT="$REPO-wt"; SANDBOXES+=("$WT")
git init -q "$REPO" >/dev/null 2>&1
( cd "$REPO" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1 \
  && git worktree add -q -b ramo "$WT" >/dev/null 2>&1 )
[ -d "$WT" ] || { echo "FALHA montagem do worktree temporario"; exit 1; }

# Caso 1: velha no principal (so design: etapa plano), avancada no worktree (executar).
estado "$REPO" fluxo-x '{"slug":"fluxo-x","titulo":"Fluxo X","criado_em":"2026-10-01","design":{"status":"aprovado"}}'
estado "$WT" fluxo-x '{"slug":"fluxo-x","titulo":"Fluxo X","criado_em":"2026-10-01","design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"parcial","tarefas_ok":2,"tarefas":5,"em_voo":[{"agente":"agente-a"},{"nome":"sem-agente"},null]}}'
# Caso 2: completo no principal.
estado "$REPO" fluxo-pronto '{"slug":"fluxo-pronto","criado_em":"2026-10-02","design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":{"status":"ok"},"verificar":{"status":"ok"},"fechar":{"status":"ok"}}'
# Caso 3: ilegivel.
printf '{ isto nao e json' > "$REPO/docs/rainforest/estado/quebrado.json"
# Caso 6: outro fluxo mais novo.
estado "$REPO" fluxo-novo '{"slug":"fluxo-novo","titulo":"Novo","criado_em":"2026-10-03","design":{"status":"pendente"}}'

rodar "$REPO"
checa "copia avancada no worktree vence a velha do principal" \
  "d.fluxos.filter(f => f.slug === 'fluxo-x').length === 1 && d.fluxos.find(f => f.slug === 'fluxo-x').etapa === 'executar' && d.fluxos.find(f => f.slug === 'fluxo-x').worktree.replace(/\\\\/g,'/').endsWith('-wt')"
checa "progresso e em_voo do bloco da etapa ativa (sem entrada sem agente)" \
  "(() => { const f = d.fluxos.find(f => f.slug === 'fluxo-x'); return f.tarefas_ok === 2 && f.tarefas === 5 && JSON.stringify(f.em_voo) === '[\"agente-a\"]'; })()"
checa "fluxo completo nao entra na lista" "!d.fluxos.some(f => f.slug === 'fluxo-pronto')"
checa "estado ilegivel ignorado, os outros seguem" "d.fluxos.length === 2"
if printf '%s' "$ERRO" | grep -q "quebrado.json"; then passa "estado ilegivel avisa no stderr"; else falha "estado ilegivel avisa no stderr" "stderr=$ERRO"; fi
checa "ordem criado_em desc" "d.fluxos.map(f => f.slug).join(',') === 'fluxo-novo,fluxo-x'"
checa "sem FOCO.md, a saida so tem a chave fluxos" "JSON.stringify(Object.keys(d)) === '[\"fluxos\"]'"

# Empate de criado_em: slug desc.
estado "$REPO" aaa-empate '{"slug":"aaa-empate","criado_em":"2026-10-03","design":{"status":"pendente"}}'
rodar "$REPO"
checa "empate de criado_em ordena por slug desc" "d.fluxos.map(f => f.slug).join(',') === 'fluxo-novo,aaa-empate,fluxo-x'"
rm -f "$REPO/docs/rainforest/estado/aaa-empate.json"

# Caso 4: com FOCO.md ativo ao lado, a saida continua sem foco.
RAIZ_FOCO=$(novo_sandbox)
printf '# Foco\n\n## Ativo\n\n**Faixa de teste**\nresto\n\n## Concluido\n' > "$RAIZ_FOCO/FOCO.md"
rodar "$REPO" "$RAIZ_FOCO"
checa "com FOCO.md ativo, a chave foco nao existe" "!('foco' in d) && JSON.stringify(Object.keys(d)) === '[\"fluxos\"]'"

# Caso 5: diretorio que nao e repo cai para [cwd].
NAOREPO=$(novo_sandbox)
estado "$NAOREPO" so-aqui '{"slug":"so-aqui","criado_em":"2026-09-30","design":{"status":"pendente"}}'
rodar "$NAOREPO"
checa "diretorio que nao e repo cai para [cwd]" \
  "d.fluxos.length === 1 && d.fluxos[0].slug === 'so-aqui' && d.fluxos[0].etapa === 'design' && d.fluxos[0].worktree.replace(/\\\\/g,'/') === '$NAOREPO'"

# Caso 7: worktree de subagente (.claude/worktrees/agent-*) com copia do despacho mais
# avancada (fluxo reaberto no real) nao vence a copia do worktree real.
AG="$REPO/.claude/worktrees/agent-velho"
( cd "$REPO" && git worktree add -q --detach "$AG" >/dev/null 2>&1 )
[ -d "$AG" ] || { echo "FALHA montagem do worktree de agente"; exit 1; }
estado "$AG" fluxo-x '{"slug":"fluxo-x","criado_em":"2026-10-01","design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":{"status":"ok"}}'
rodar "$REPO"
checa "worktree de agente nao vence a copia real mesmo mais avancado" \
  "(() => { const f = d.fluxos.find(f => f.slug === 'fluxo-x'); return f.etapa === 'executar' && f.worktree.replace(/\\\\/g,'/').endsWith('-wt'); })()"
estado "$AG" so-no-agente '{"slug":"so-no-agente","criado_em":"2026-09-01","design":{"status":"pendente"}}'
rodar "$REPO"
checa "copia so no worktree de agente ainda aparece" "d.fluxos.some(f => f.slug === 'so-no-agente')"
( cd "$REPO" && git worktree remove --force "$AG" >/dev/null 2>&1 )

# Somente leitura: nada novo apareceu no repo temporario alem do que a bateria escreveu.
ANTES=$(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | md5sum)
rodar "$REPO"
DEPOIS=$(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | md5sum)
if [ "$ANTES" = "$DEPOIS" ]; then passa "somente leitura: nenhum arquivo novo"; else falha "somente leitura: nenhum arquivo novo"; fi

# require mudo: o modulo exporta lerFluxos e worktrees e nao imprime nada.
MUDO=$(node -e "const d=require(process.argv[1]);console.log(typeof d.lerFluxos,typeof d.worktrees)" "$SCRIPT" 2>&1)
if [ "$MUDO" = "function function" ]; then passa "require mudo: exporta lerFluxos e worktrees sem imprimir"; else falha "require mudo" "saida: $MUDO"; fi

echo "$OK ok, $FALHA falha(s), 0 skipped"
[ "$FALHA" -eq 0 ]
