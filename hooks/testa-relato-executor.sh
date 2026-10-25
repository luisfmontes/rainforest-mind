#!/bin/bash
# Bateria do hooks/relato-executor.cjs (SubagentStop) — o relato do executor de
# fluxo tem fim declarado: a última linha é `ENTREGA: completa` ou
# `ENTREGA: parcial` (D4 do lote 6,
# docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md).
#
# Caixa de areia: um único mktemp -d com trap EXIT. RFM_ROOT aponta para uma raiz
# de dados vazia, então o config REAL de quem roda a bateria nunca é lido. O
# config de projeto vem de um repositório git descartável dentro da caixa.
#
# Payloads e transcritos são montados por node (nunca printf — #403), com o texto
# por variável de ambiente, para que aspas e quebras de linha cheguem inteiras.
# Caminhos vão nativos (cygpath -m): o hook lê agent_transcript_path direto do
# JSON, sem passar pela conversão do MSYS.
set -u
SRC_POSIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cygpath -m "$SRC_POSIX" 2>/dev/null || printf '%s' "$SRC_POSIX")"
HOOK="$SRC/hooks/relato-executor.cjs"

SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
echo "(caixa de areia: $SB)"

# Raiz de dados vazia: sem config do usuário, o padrão (tudo ligado) vale.
RFM_ROOT_PADRAO="$SB/dados"; mkdir -p "$SBP/dados"

# Config do usuário desligando o contrato (raiz de dados própria).
mkdir -p "$SBP/dados-off"
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'contrato-relato-executor': false}))" "$SBP/dados-off/config.json"

# Repositório git descartável com o config de projeto desligando o contrato.
mkdir -p "$SBP/repo" "$SBP/repo-off/.rainforest" "$SBP/semgit"
(cd "$SBP/repo" && git init -q)
(cd "$SBP/repo-off" && git init -q)
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'contrato-relato-executor': false}))" "$SBP/repo-off/.rainforest/config.json"
REPO="$SB/repo"
REPO_OFF="$SB/repo-off"
SEM_GIT="$SB/semgit"

# Montador de fixtures: um único script, copiado para a caixa.
MK="$SBP/mk.cjs"
cat > "$MK" <<'EOF'
// Monta um transcrito .jsonl ("jsonl") ou um payload de SubagentStop ("payload").
// O texto chega por variável de ambiente, nunca pelo shell.
const fs = require('fs');
const [saida, modo] = process.argv.slice(2);
const e = process.env;
if (modo === 'jsonl') {
  const linhas = [{ type: 'user', message: { role: 'user', content: e.T_PROMPT } }];
  if (e.T_ULTIMA) {
    linhas.push({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: e.T_ULTIMA }] } });
  }
  fs.writeFileSync(saida, linhas.map((l) => JSON.stringify(l)).join('\n') + '\n');
} else if (modo === 'payload') {
  const p = {
    hook_event_name: 'SubagentStop',
    agent_type: e.P_AGENTE,
    agent_id: 'a1b2c3',
    session_id: 'sessao1',
    cwd: e.P_CWD,
    agent_transcript_path: e.P_TRANSCRITO,
    stop_hook_active: e.P_STOP === 'sim',
  };
  if (e.P_MSG !== undefined) p.last_assistant_message = e.P_MSG;
  fs.writeFileSync(saida, e.P_RAW !== undefined ? e.P_RAW : JSON.stringify(p));
}
EOF

PROMPT_FLUXO=$'Runtime: claude\nSlug: 2026-10-24-apoio-ao-dev-lote-6\n\nTarefa: exemplo de briefing de fluxo.'
PROMPT_AVULSO=$'Tarefa avulsa, sem linha de slug.'

ok=0; falhou=0; N=0
mkdir -p "$SBP/t"

# Roda o hook com o payload $1 e a raiz de dados $2. Guarda SAIDA e GOT.
rodar() {
  SAIDA="$(RFM_ROOT="$2" node "$HOOK" < "$1" 2>"$SBP/err.txt")"; GOT=$?
}

# Verdadeiro se a saída é um bloqueio com o motivo do relato.
bloqueou() {
  [ "$GOT" = 0 ] && printf '%s' "$SAIDA" | node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); process.exit(o.decision === "block" && /ENTREGA/.test(o.reason) ? 0 : 1)' 2>/dev/null
}

# Verdadeiro se o hook saiu 0 sem imprimir nada.
silencio() {
  [ "$GOT" = 0 ] && [ -z "$SAIDA" ]
}

registra() { # $1 nome, $2 0 = passou
  if [ "$2" = 0 ]; then
    ok=$((ok+1)); echo "  ok    $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (exit=$GOT, saida=$SAIDA, err=$(cat "$SBP/err.txt"))"
  fi
}

# caso <nome> <agente> <prompt> <ultima do transcrito> <msg do payload|-> <stop sim|nao> <bloqueia|silencio> [raiz de dados] [cwd]
caso() {
  local nome="$1" agente="$2" prompt="$3" ultima="$4" msg="$5" stop="$6" esperado="$7"
  local raiz="${8:-$RFM_ROOT_PADRAO}" cwd="${9:-$REPO}"
  N=$((N+1))
  local tp="$SBP/t/$N.jsonl" tn="$SB/t/$N.jsonl" pay="$SBP/t/$N.payload.json"
  mkdir -p "$SBP/t"
  T_PROMPT="$prompt" T_ULTIMA="$ultima" node "$MK" "$tp" jsonl
  if [ "$msg" = "-" ]; then
    P_AGENTE="$agente" P_CWD="$cwd" P_TRANSCRITO="$tn" P_STOP="$stop" node "$MK" "$pay" payload
  else
    P_MSG="$msg" P_AGENTE="$agente" P_CWD="$cwd" P_TRANSCRITO="$tn" P_STOP="$stop" node "$MK" "$pay" payload
  fi
  rodar "$pay" "$raiz"
  local r=1
  if [ "$esperado" = bloqueia ]; then bloqueou && r=0; else silencio && r=0; fi
  registra "$nome" "$r"
}

caso "executor em fluxo sem a linha ENTREGA devolve a vez" \
  executor "$PROMPT_FLUXO" "Relato sem fim. Arquivo alterado: a.cjs." "Relato sem fim. Arquivo alterado: a.cjs." nao bloqueia

caso "rainforest-mind:executor em fluxo sem a linha ENTREGA devolve a vez" \
  rainforest-mind:executor "$PROMPT_FLUXO" "Relato sem fim." "Relato sem fim." nao bloqueia

caso "ENTREGA: completa como última linha deixa passar" \
  executor "$PROMPT_FLUXO" "Feito.
ENTREGA: completa" "Feito.
ENTREGA: completa" nao silencio

caso "**ENTREGA: parcial** em negrito deixa passar" \
  executor "$PROMPT_FLUXO" "Parcial, um item NÃO FEITO.
**ENTREGA: parcial**" "Parcial, um item NÃO FEITO.
**ENTREGA: parcial**" nao silencio

caso "ENTREGA em caixa alta conta (a leitura põe em minúsculas)" \
  executor "$PROMPT_FLUXO" "Feito.
ENTREGA: COMPLETA" "Feito.
ENTREGA: COMPLETA" nao silencio

caso "ENTREGA no meio com texto depois não conta: devolve a vez" \
  executor "$PROMPT_FLUXO" "ENTREGA: completa
Depois do fim ainda escrevi isto." "ENTREGA: completa
Depois do fim ainda escrevi isto." nao bloqueia

caso "segunda parada sem a linha deixa passar (não bloqueia duas vezes)" \
  executor "$PROMPT_FLUXO" "Relato sem fim." "Relato sem fim." sim silencio

caso "sem Slug: no briefing, executor fora de fluxo não é tocado" \
  executor "$PROMPT_AVULSO" "Relato sem fim." "Relato sem fim." nao silencio

caso "agente revisor com Slug e sem ENTREGA não é tocado" \
  revisor "$PROMPT_FLUXO" "Achados. VEREDITO: ok" "Achados. VEREDITO: ok" nao silencio

caso "sem a linha no payload, a última mensagem do transcrito tem ENTREGA: deixa passar" \
  executor "$PROMPT_FLUXO" "Feito.
ENTREGA: completa" "-" nao silencio

caso "sem a linha no payload nem no transcrito devolve a vez" \
  executor "$PROMPT_FLUXO" "" "-" nao bloqueia

caso "config contrato-relato-executor desligado na raiz de dados deixa passar" \
  executor "$PROMPT_FLUXO" "Relato sem fim." "Relato sem fim." nao silencio "$SB/dados-off"

caso "config de projeto desligado (.rainforest/config.json) deixa passar" \
  executor "$PROMPT_FLUXO" "Relato sem fim." "Relato sem fim." nao silencio "$SB/dados" "$REPO_OFF"

caso "cwd fora de repositório git sai 0 sem bloquear" \
  executor "$PROMPT_FLUXO" "Relato sem fim." "Relato sem fim." nao silencio "$SB/dados" "$SEM_GIT"

# Payload ilegível: o hook sai 0 sem imprimir nada.
N=$((N+1)); PAY_RUIM="$SBP/t/$N.payload.json"
P_RAW='{"agent_type": "executor", ' node "$MK" "$PAY_RUIM" payload
rodar "$PAY_RUIM" "$RFM_ROOT_PADRAO"
if silencio; then registra "payload ilegível sai 0 sem nada" 0; else registra "payload ilegível sai 0 sem nada" 1; fi

echo
echo "-----------------------------------------"
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
