#!/bin/bash
# Bateria do hooks/veredito-revisor.cjs (SubagentStop) — grava o veredito de
# uma linha do revisor em docs/rainforest/estado/<slug>.json (D1/D3/D5,
# docs/rainforest/planos/2026-09-23-contrato-de-veredito.md, tarefas 8 e 9).
#
# Molde: hooks/testa-escada-subagente.sh (sandbox temporario, placar, trap de
# limpeza) + hooks/testa-gate-agente-em-voo.sh (repositorio git de fixture,
# RFM_ESTADO_ROOT, payload construido por node -e para evitar aspas quebradas).
#
# Caminho NATIVO via cygpath -m, nao o /tmp/... do Git Bash: o hook grava o
# valor de agent_transcript_path DIRETO do JSON do stdin (nunca passa por argv,
# entao a conversao automatica de caminho do MSYS nao ajuda) — um caminho
# posix "/c/..." dentro do JSON vira "\c\..." relativo ao drive corrente do
# Node no Windows e o fs.readFileSync falha em silencio, fazendo a bateria
# passar verde testando um "arquivo ausente" que na verdade e caminho errado.
# Mesma armadilha documentada em testa-gate-agente-em-voo.sh.
set -u
SRC_POSIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cygpath -m "$SRC_POSIX" 2>/dev/null || printf '%s' "$SRC_POSIX")"
HOOK="$SRC/hooks/veredito-revisor.cjs"
ESTADO="$SRC/scripts/estado.cjs"
HOOKS_JSON="$SRC/hooks/hooks.json"
# D12 — Tarefa 16: `estado.cjs veredito` agora exige `--transcrito <caminho>`
# dentro de uma pasta `subagents` (o hook passa o mesmo caminho que ja
# resolvia para achar o Slug). Os fixtures moraram soltos ate a tarefa 16;
# agora ficam em subagents/, e ganharam duas variantes cujo ULTIMO texto do
# assistente bate com o vocabulario ('-ok'/'-reprovado') — o arquivo antigo
# (sem sufixo) continua fora do vocabulario ('Lendo o diff.'), de proposito,
# para o caso 5 (veredito 'invalido').
FIX="$SRC/hooks/fixtures/veredito-revisor/subagents"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# D14 — Tarefa 18: `estado.cjs veredito` (chamado pelo hook) agora tambem
# exige que --transcrito more na pasta REAL de sessao
# (<CLAUDE_CONFIG_DIR>/projects/<p>/<s>/subagents/agent-<id>.jsonl, com o
# '.meta.json' irmao de agentType revisor) — nao basta confirmar Slug e
# veredito no conteudo (D12). HOME/USERPROFILE apontam pro sandbox, nunca o
# home de verdade do usuario; no Windows so' USERPROFILE conta (Node nem le
# HOME nativo la), em POSIX e' o contrario — exporta os dois.
HOME_SBOX_POSIX="$RAIZ_POSIX/home"
mkdir -p "$HOME_SBOX_POSIX"
HOME_SBOX="$(cygpath -m "$HOME_SBOX_POSIX" 2>/dev/null || printf '%s' "$HOME_SBOX_POSIX")"
export HOME="$HOME_SBOX"
export USERPROFILE="$HOME_SBOX"
# A config dir em uso decide qual arvore vale (emenda da 3a revisao): fixa no
# sandbox — herdar a da sessao apontaria para o ~/.claude* de verdade, e em CI
# (sem a variavel) cairia em ~/.claude, que os fixtures nao usam.
export CLAUDE_CONFIG_DIR="$HOME_SBOX/.claude-personal"

ok=0; falhou=0

# Copia o CONTEUDO de um fixture existente (nome livre, ex.
# transcript-slug-string-ok.jsonl) para o caminho real de sessao que D14
# exige, renomeado para `agent-<agente_id>.jsonl`, com o '.meta.json' de
# agentType revisor ao lado. Devolve o caminho NOVO, em formato nativo
# (mesma razao do comentario do topo do arquivo sobre cygpath -m).
real_transcrito() { # fixture_src, agente_id, sessao(opcional, default sess-caixa)
  local src="$1" id="$2" sess="${3:-sess-caixa}"
  local dir="$HOME_SBOX_POSIX/.claude-personal/projects/p/$sess/subagents"
  mkdir -p "$dir"
  cp "$src" "$dir/agent-$id.jsonl"
  printf '{"agentType":"rainforest-mind:revisor"}' > "$dir/agent-$id.meta.json"
  cygpath -m "$dir/agent-$id.jsonl" 2>/dev/null || printf '%s' "$dir/agent-$id.jsonl"
}

# Gera um transcrito de sessao real (mesmo formato de real_transcrito) com o
# TEXTO EXATO do assistente passado — para casos 12/13, onde `estado.cjs
# veredito` (D12, transcritoConfirmaVeredito) reextrai a ultima linha DIRETO
# do arquivo, independente do que o payload de SubagentStop carrega em
# last_assistant_message. Os dois precisam bater, senao `estado.cjs` recusa
# a gravacao (RECUSADO: ... nao confirma). Usar um fixture estatico (como
# real_transcrito faz) so funciona quando o texto do fixture, apos a mesma
# extracao, cai no mesmo veredito do payload — o que nao vale para o caso 13
# (texto depois do veredito, dentro do negrito).
transcrito_com_texto() { # texto_assistente, agente_id, sessao(opcional)
  local texto="$1" id="$2" sess="${3:-sess-caixa}"
  local dir="$HOME_SBOX_POSIX/.claude-personal/projects/p/$sess/subagents"
  mkdir -p "$dir"
  node -e '
const fs = require("fs");
const [dir, id, texto] = process.argv.slice(1);
const linha1 = JSON.stringify({type:"user", isSidechain:true, message:{role:"user", content:"Slug: revisor-fixture-caixa\nRevise o diff da tarefa de teste. Responda com a ultima linha exatamente VEREDITO: ok ou VEREDITO: reprovado."}});
const linha2 = JSON.stringify({type:"assistant", isSidechain:true, message:{role:"assistant", content:[{type:"text", text: texto}]}});
fs.writeFileSync(dir + "/agent-" + id + ".jsonl", linha1 + "\n" + linha2 + "\n");
fs.writeFileSync(dir + "/agent-" + id + ".meta.json", JSON.stringify({agentType:"rainforest-mind:revisor"}));
' "$dir" "$id" "$texto"
  cygpath -m "$dir/agent-$id.jsonl" 2>/dev/null || printf '%s' "$dir/agent-$id.jsonl"
}

# ---------------------------------------------------------------- a fixture
# Repositorio git real: toplevel(payload.cwd) em veredito-revisor.cjs precisa
# de um `git rev-parse --show-toplevel` que funcione de verdade — sem isso o
# hook sai 0 por "repoRoot nao resolvido" e nenhum caso testaria a gravacao.
R="$RAIZ/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
mkdir -p "$R/docs/rainforest/estado"
echo base > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base

SLUG="revisor-fixture-caixa"
SLUG_JSON="$R/docs/rainforest/estado/$SLUG.json"

# Escreve (ou reescreve) o estado do slug com a janela de vereditos vazia —
# chamado antes de cada caso que precisa de uma janela limpa.
reset_estado() {
  node -e '
const fs = require("fs");
const [p, slug] = process.argv.slice(1);
fs.writeFileSync(p, JSON.stringify({
  slug, titulo: "fixture da bateria de contrato de veredito", criado_em: "2026-09-23",
  arqueologia: { status: "dispensada" },
  design: { status: "aprovado", em: "2026-09-23" },
  plano: { status: "ok", em: "2026-09-23" },
  executar: { status: "ok", em: "2026-09-23" },
  revisar: { status: "pendente", vereditos: [] },
  verificar: { status: "pendente" },
  fechar: { status: "pendente" },
}, null, 2) + "\n");
' "$SLUG_JSON" "$SLUG"
}
reset_estado

# Le a janela de vereditos do slug direto do arquivo (nunca via `estado.cjs
# ler`: esse subcomando avisa em stdout sobre carimbos divergentes do ledger
# e poluiria a comparacao — o arquivo em disco e a fonte real).
vereditos() {
  node -e '
const fs = require("fs");
const e = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write(JSON.stringify((e.revisar && e.revisar.vereditos) || []));
' "$SLUG_JSON" 2>/dev/null || echo '[]'
}

sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Payload de SubagentStop montado por node -e, com os campos do payload real
# capturado (session_id, transcript_path, cwd, prompt_id, permission_mode,
# agent_id, agent_type, effort, hook_event_name, stop_hook_active,
# last_assistant_message, background_tasks, session_crons) + extra(JSON) para
# sobrescrever/adicionar campos (agent_transcript_path, session_id p/
# fallback). Nunca por printf com aspas aninhadas — isso ja produziu JSON
# invalido neste repo (comentario de testa-gate-agente-em-voo.sh).
pay() { # cwd, agent_type, agent_id, last_assistant_message, extra_json(opcional)
  node -e '
const [cwd, agentType, agentId, lastMsg, extra] = process.argv.slice(1);
const base = {
  session_id: "sess-caixa",
  transcript_path: cwd + "/transcripts/main.jsonl",
  cwd,
  prompt_id: "prompt-1",
  permission_mode: "default",
  agent_id: agentId,
  agent_type: agentType,
  effort: "medium",
  hook_event_name: "SubagentStop",
  stop_hook_active: false,
  last_assistant_message: lastMsg,
  background_tasks: [],
  session_crons: [],
};
const merged = Object.assign(base, extra ? JSON.parse(extra) : {});
process.stdout.write(JSON.stringify(merged));
' "$1" "$2" "$3" "$4" "${5:-}"
}

rodar_hook() { # payload_json -> roda o hook real, devolve exit code em $?
  printf '%s' "$1" | RFM_ESTADO_ROOT="$R" node "$HOOK" >/dev/null 2>&1
}

VEREDITO_OK="Diff revisado, sem pendencia.
VEREDITO: ok"

echo
echo "== 1. agent_type certo grava =="
reset_estado
T1=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" AAA)
P=$(pay "$R" "rainforest-mind:revisor" "AAA" "$VEREDITO_OK" '{"agent_transcript_path":"'"$T1"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"ok"' && printf '%s' "$V" | grep -q '"agente_id":"AAA"' && printf '%s' "$V" | grep -q '"agente":"rainforest-mind:revisor"'; then
  ok=$((ok+1)); echo "  ok    agent_type rainforest-mind:revisor grava veredito ok (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA agent_type certo nao gravou como esperado (exit $GOT): $V"
fi

echo
echo "== 2. agent_type que nao e revisor e ignorado =="
# Fixture do transcrito TEM Slug valido e o veredito e vocabulario-valido — se
# o filtro de agent_type sumir (mutacao da tarefa 8), o hook gravaria mesmo
# assim, e esta secao pegaria isso. O transcrito mora na arvore real (com
# .meta.json de revisor): senao a checagem de D14 no estado.cjs recusaria
# sozinha e o mutante sobreviveria — foi o que a catraca do verificar achou.
reset_estado
P=$(pay "$R" "outro-agente" "BBB" "$VEREDITO_OK" '{"agent_transcript_path":"'"$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" BBB)"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && [ "$V" = "[]" ]; then
  ok=$((ok+1)); echo "  ok    agent_type 'outro-agente' nao grava, mesmo com Slug e veredito validos (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA agent_type errado gravou (nao deveria): $V"
fi

echo
echo "== 3. sem Slug: nao grava (sha256 igual) =="
reset_estado
ANTES=$(sha "$SLUG_JSON")
P=$(pay "$R" "rainforest-mind:revisor" "CCC" "$VEREDITO_OK" '{"agent_transcript_path":"'"$FIX"'/transcript-sem-slug.jsonl"}')
rodar_hook "$P"; GOT=$?
DEPOIS=$(sha "$SLUG_JSON")
if [ "$GOT" = 0 ] && [ "$ANTES" = "$DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    briefing sem 'Slug:' nao toca o arquivo de estado (sha256 igual, exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA sem Slug: o arquivo mudou (antes=$ANTES depois=$DEPOIS, exit $GOT)"
fi

echo
echo "== 4. slug inexistente nao grava e sai 0 =="
rm -f "$SLUG_JSON"
P=$(pay "$R" "rainforest-mind:revisor" "DDD" "$VEREDITO_OK" '{"agent_transcript_path":"'"$FIX"'/transcript-slug-string.jsonl"}')
rodar_hook "$P"; GOT=$?
if [ "$GOT" = 0 ] && [ ! -f "$SLUG_JSON" ]; then
  ok=$((ok+1)); echo "  ok    slug sem estado em disco: hook sai 0 e nao cria o arquivo"
else
  falhou=$((falhou+1)); echo "  FALHA slug inexistente: exit=$GOT, arquivo criado=$([ -f "$SLUG_JSON" ] && echo sim || echo nao)"
fi
reset_estado

echo
echo "== 5. veredito fora do vocabulario grava invalido =="
# Tarefa 3 (D1/D3): desde que a 1a parada com veredito invalido passou a
# bloquear (casos 14-19), este caso precisa simular a 2a parada
# (stop_hook_active:true) para continuar testando o que sempre testou: a
# extracao fora do vocabulario -> grava 'invalido'.
reset_estado
T5=$(real_transcrito "$FIX/transcript-slug-string.jsonl" EEE)
P=$(pay "$R" "rainforest-mind:revisor" "EEE" "Ficou bom, acho que sim." '{"agent_transcript_path":"'"$T5"'","stop_hook_active":true}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"invalido"'; then
  ok=$((ok+1)); echo "  ok    ultima linha fora do vocabulario grava veredito 'invalido'"
else
  falhou=$((falhou+1)); echo "  FALHA veredito fora do vocabulario nao gravou 'invalido': $V"
fi

echo
echo "== 6. dois hooks concorrentes preservam as duas entradas =="
reset_estado
T6A=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" CONC-1)
T6B=$(real_transcrito "$FIX/transcript-slug-string-reprovado.jsonl" CONC-2)
P1=$(pay "$R" "rainforest-mind:revisor" "CONC-1" "Parece certo.
VEREDITO: ok" '{"agent_transcript_path":"'"$T6A"'"}')
P2=$(pay "$R" "rainforest-mind:revisor" "CONC-2" "Falta ajuste.
VEREDITO: reprovado" '{"agent_transcript_path":"'"$T6B"'"}')
( printf '%s' "$P1" | RFM_ESTADO_ROOT="$R" node "$HOOK" >/dev/null 2>&1 ) &
PID1=$!
( printf '%s' "$P2" | RFM_ESTADO_ROOT="$R" node "$HOOK" >/dev/null 2>&1 ) &
PID2=$!
wait "$PID1"; wait "$PID2"
V=$(vereditos)
N=$(printf '%s' "$V" | node -e 'const v=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(v.length));' 2>/dev/null)
if [ "$N" = "2" ] && printf '%s' "$V" | grep -q '"agente_id":"CONC-1"' && printf '%s' "$V" | grep -q '"agente_id":"CONC-2"'; then
  ok=$((ok+1)); echo "  ok    dois hooks concorrentes (agent_id distintos) preservam as duas entradas"
else
  falhou=$((falhou+1)); echo "  FALHA concorrencia: esperava 2 entradas distintas, veio: $V"
fi

echo
echo "== 7. fallback sem agent_transcript_path =="
# Sem agent_transcript_path no payload: o hook calcula
# <dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl —
# D14 exige que esse caminho tambem caia na arvore real de sessao, entao
# `transcript_path` do payload e' sobrescrito pra apontar pro HOME sandbox
# (dirname dele vira a pasta que o fallback usa como base).
reset_estado
FB_DIR="$HOME_SBOX_POSIX/.claude-personal/projects/p/sess-fallback/subagents"
mkdir -p "$FB_DIR"
cp "$FIX/transcript-slug-string-ok.jsonl" "$FB_DIR/agent-FB1.jsonl"
printf '{"agentType":"rainforest-mind:revisor"}' > "$FB_DIR/agent-FB1.meta.json"
FB_TRANSCRIPT_PATH="$(cygpath -m "$HOME_SBOX_POSIX/.claude-personal/projects/p/session.jsonl" 2>/dev/null || printf '%s' "$HOME_SBOX_POSIX/.claude-personal/projects/p/session.jsonl")"
P=$(pay "$R" "rainforest-mind:revisor" "FB1" "$VEREDITO_OK" '{"session_id":"sess-fallback","transcript_path":"'"$FB_TRANSCRIPT_PATH"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"agente_id":"FB1"' && printf '%s' "$V" | grep -q '"veredito":"ok"'; then
  ok=$((ok+1)); echo "  ok    sem agent_transcript_path, o fallback via transcript_path+session_id+agent_id grava"
else
  falhou=$((falhou+1)); echo "  FALHA fallback sem agent_transcript_path nao gravou: $V"
fi

echo
echo "== 8. content como array =="
reset_estado
T8=$(real_transcrito "$FIX/transcript-slug-array.jsonl" ARR1)
P=$(pay "$R" "rainforest-mind:revisor" "ARR1" "$VEREDITO_OK" '{"agent_transcript_path":"'"$T8"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"agente_id":"ARR1"' && printf '%s' "$V" | grep -q '"veredito":"ok"'; then
  ok=$((ok+1)); echo "  ok    content do transcrito como array de blocos tambem extrai o Slug"
else
  falhou=$((falhou+1)); echo "  FALHA content como array nao gravou: $V"
fi

echo
echo "== 9. toggle desligado nao grava =="
reset_estado
mkdir -p "$R/.rainforest"
printf '{"contrato-veredito": false}' > "$R/.rainforest/config.json"
T9=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" TOG1)
P=$(pay "$R" "rainforest-mind:revisor" "TOG1" "$VEREDITO_OK" '{"agent_transcript_path":"'"$T9"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && [ "$V" = "[]" ]; then
  ok=$((ok+1)); echo "  ok    contrato-veredito desligado no projeto: hook sai 0 e nao grava"
else
  falhou=$((falhou+1)); echo "  FALHA toggle desligado gravou mesmo assim: $V"
fi
# Religa e confirma que o MESMO payload volta a gravar — prova que foi o
# toggle (e nao outra coisa) que impediu a gravacao acima.
printf '{"contrato-veredito": true}' > "$R/.rainforest/config.json"
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"agente_id":"TOG1"'; then
  ok=$((ok+1)); echo "  ok    religando o toggle, o mesmo payload volta a gravar"
else
  falhou=$((falhou+1)); echo "  FALHA religando o toggle, o payload nao gravou: $V"
fi
rm -rf "$R/.rainforest"

echo
echo "== 10. hooks.json aponta para o hook certo =="
if node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$HOOKS_JSON" >/dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok    hooks.json e JSON valido"
else
  falhou=$((falhou+1)); echo "  FALHA hooks.json nao parseia como JSON"
fi

CMD=$(node -e '
const h = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const grupos = (h.hooks && h.hooks.SubagentStop) || [];
let cmd = null;
for (const g of grupos) {
  for (const hk of (g.hooks || [])) {
    if (typeof hk.command === "string" && hk.command.includes("veredito-revisor.cjs")) cmd = hk.command;
  }
}
process.stdout.write(cmd || "");
' "$HOOKS_JSON")

if [ -n "$CMD" ]; then
  ok=$((ok+1)); echo "  ok    hooks.json registra SubagentStop apontando para veredito-revisor.cjs ($CMD)"
else
  falhou=$((falhou+1)); echo "  FALHA hooks.json nao tem SubagentStop com veredito-revisor.cjs"
fi

# Resolve ${CLAUDE_PLUGIN_ROOT} para a raiz do repo e roda o comando EXATO
# encontrado (nao um caminho hardcoded pela bateria) — se a tarefa 9 apontar
# para um arquivo que nao existe, esta secao pega o MODULE_NOT_FOUND.
reset_estado
THJ=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" HOOKSJSON1)
P=$(pay "$R" "rainforest-mind:revisor" "HOOKSJSON1" "$VEREDITO_OK" '{"agent_transcript_path":"'"$THJ"'"}')
SAIDA_CMD=$(printf '%s' "$P" | CLAUDE_PLUGIN_ROOT="$SRC" RFM_ESTADO_ROOT="$R" bash -c "$CMD" 2>&1)
GOT_CMD=$?
V=$(vereditos)
if [ "$GOT_CMD" = 0 ] && ! printf '%s' "$SAIDA_CMD" | grep -qi "cannot find module\|MODULE_NOT_FOUND\|ENOENT"; then
  ok=$((ok+1)); echo "  ok    o comando exato de hooks.json roda sem ENOENT/MODULE_NOT_FOUND (exit $GOT_CMD)"
else
  falhou=$((falhou+1)); echo "  FALHA comando de hooks.json falhou (exit $GOT_CMD): $SAIDA_CMD"
fi
if printf '%s' "$V" | grep -q '"agente_id":"HOOKSJSON1"'; then
  ok=$((ok+1)); echo "  ok    o comando exato de hooks.json de fato grava o veredito"
else
  falhou=$((falhou+1)); echo "  FALHA o comando de hooks.json nao gravou: $V"
fi

echo
echo "== 11. degradacao: payload ilegivel e cwd fora de git =="
# Adversarial: nenhum dos dois esta no minimo pedido pela tarefa 12, mas sao
# os dois primeiros `process.exit(0)` do hook (linhas 94-95 e 119-121) — se
# alguem "simplificar" o try/catch do JSON.parse ou o toplevel(), e aqui que
# quebra primeiro.
reset_estado
SAIDA_LIXO=$(printf 'isto nao e json' | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>&1); GOT_LIXO=$?
if [ "$GOT_LIXO" = 0 ]; then
  ok=$((ok+1)); echo "  ok    payload ilegivel (nao-JSON) no stdin nao derruba o hook (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA payload ilegivel derrubou o hook (exit $GOT_LIXO): $SAIDA_LIXO"
fi

FORA_GIT="$RAIZ/fora-de-git"; mkdir -p "$FORA_GIT"
P=$(pay "$FORA_GIT" "rainforest-mind:revisor" "FORAGIT1" "$VEREDITO_OK" '{"agent_transcript_path":"'"$FIX"'/transcript-slug-string.jsonl"}')
printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" >/dev/null 2>&1; GOT_FORA=$?
V=$(vereditos)
if [ "$GOT_FORA" = 0 ] && [ "$V" = "[]" ]; then
  ok=$((ok+1)); echo "  ok    cwd fora de repositorio git: toplevel() falha e o hook nao grava"
else
  falhou=$((falhou+1)); echo "  FALHA cwd fora de git: exit=$GOT_FORA, vereditos=$V"
fi

echo
echo "== 12. veredito em negrito na ultima linha grava ok =="
# D2/D4 (docs/rainforest/design/2026-09-25-veredito-fora-da-linha.md): a
# extracao aceita marcacao (*, _ ou crase) SO nas pontas da ultima linha.
# Cobre as tres formas vistas em revisao real (negrito, sublinhado, crase)
# mais o caso reprovado em negrito.
MD_BOLD_OK='Diff revisado, sem pendencia.
**VEREDITO: ok**'
MD_UNDER_OK='Diff revisado, sem pendencia.
__VEREDITO: ok__'
MD_CRASE_OK='Diff revisado, sem pendencia.
`VEREDITO: ok`'
MD_BOLD_REPROVADO='Falta ajuste no contrato.
**VEREDITO: reprovado**'

reset_estado
TMD1=$(transcrito_com_texto "$MD_BOLD_OK" MD1)
P=$(pay "$R" "rainforest-mind:revisor" "MD1" "$MD_BOLD_OK" '{"agent_transcript_path":"'"$TMD1"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"ok"' && printf '%s' "$V" | grep -q '"agente_id":"MD1"'; then
  ok=$((ok+1)); echo "  ok    **VEREDITO: ok** (negrito) grava veredito ok"
else
  falhou=$((falhou+1)); echo "  FALHA **VEREDITO: ok** (negrito) nao gravou ok: $V"
fi

reset_estado
TMD2=$(transcrito_com_texto "$MD_UNDER_OK" MD2)
P=$(pay "$R" "rainforest-mind:revisor" "MD2" "$MD_UNDER_OK" '{"agent_transcript_path":"'"$TMD2"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"ok"' && printf '%s' "$V" | grep -q '"agente_id":"MD2"'; then
  ok=$((ok+1)); echo "  ok    __VEREDITO: ok__ (sublinhado) grava veredito ok"
else
  falhou=$((falhou+1)); echo "  FALHA __VEREDITO: ok__ (sublinhado) nao gravou ok: $V"
fi

reset_estado
TMD3=$(transcrito_com_texto "$MD_CRASE_OK" MD3)
P=$(pay "$R" "rainforest-mind:revisor" "MD3" "$MD_CRASE_OK" '{"agent_transcript_path":"'"$TMD3"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"ok"' && printf '%s' "$V" | grep -q '"agente_id":"MD3"'; then
  ok=$((ok+1)); echo "  ok    \`VEREDITO: ok\` (crase) grava veredito ok"
else
  falhou=$((falhou+1)); echo "  FALHA \`VEREDITO: ok\` (crase) nao gravou ok: $V"
fi

reset_estado
TMD4=$(transcrito_com_texto "$MD_BOLD_REPROVADO" MD4)
P=$(pay "$R" "rainforest-mind:revisor" "MD4" "$MD_BOLD_REPROVADO" '{"agent_transcript_path":"'"$TMD4"'"}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"reprovado"' && printf '%s' "$V" | grep -q '"agente_id":"MD4"'; then
  ok=$((ok+1)); echo "  ok    **VEREDITO: reprovado** (negrito) grava veredito reprovado"
else
  falhou=$((falhou+1)); echo "  FALHA **VEREDITO: reprovado** (negrito) nao gravou reprovado: $V"
fi

echo
echo "== 13. negrito com texto depois do veredito nao grava =="
# D2: a marcacao so tolera as PONTAS da linha. Texto depois do veredito
# dentro do negrito ("**VEREDITO: reprovado — 4 bloqueantes**") continua
# fora do vocabulario fechado -> invalido, nunca reprovado.
MD_BOLD_TEXTO_DEPOIS='Faltam bloqueantes.
**VEREDITO: reprovado — 4 bloqueantes**'
# Tarefa 3 (D1/D3): mesmo motivo do caso 5 — simula a 2a parada para
# continuar testando a extracao (fora do vocabulario -> invalido), nao o
# bloqueio da 1a parada (ja coberto pelos casos 14-19).
reset_estado
TMD5=$(transcrito_com_texto "$MD_BOLD_TEXTO_DEPOIS" MD5)
P=$(pay "$R" "rainforest-mind:revisor" "MD5" "$MD_BOLD_TEXTO_DEPOIS" '{"agent_transcript_path":"'"$TMD5"'","stop_hook_active":true}')
rodar_hook "$P"; GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && printf '%s' "$V" | grep -q '"veredito":"invalido"' && printf '%s' "$V" | grep -q '"agente_id":"MD5"'; then
  ok=$((ok+1)); echo "  ok    **VEREDITO: reprovado — 4 bloqueantes** (texto depois do veredito) grava invalido, nao reprovado"
else
  falhou=$((falhou+1)); echo "  FALHA negrito com texto depois do veredito nao gravou invalido: $V"
fi

# Texto cuja ultima linha nao e veredito valido (formato visto na revisao de
# 2026-09-24 e citado no briefing da tarefa 3) — usado nos casos 14-19 abaixo,
# todos sobre o bloqueio da primeira parada (D1/D3/D5).
TEXTO_INVALIDO='Analisei o diff da tarefa.
Premissas aceitas sem conferir: caminho do fixture nao testado ao vivo.'

# Confirma que a saida e um JSON {decision:"block", reason: "..."} cujo
# reason cita as duas formas exatas do vocabulario — nunca so grep na
# palavra "block", que passaria com um JSON truncado ou com outro campo.
decisao_bloqueio_valida() { # saida_stdout
  printf '%s' "$1" | node -e '
let d = "";
process.stdin.on("data", c => d += c);
process.stdin.on("end", () => {
  try {
    const o = JSON.parse(d);
    if (o.decision === "block" && typeof o.reason === "string" && o.reason.includes("VEREDITO: ok") && o.reason.includes("VEREDITO: reprovado")) {
      process.stdout.write("valido");
    }
  } catch {}
});
'
}

echo
echo "== 14. primeira parada sem veredito valido bloqueia com o motivo e nao grava =="
reset_estado
T14=$(transcrito_com_texto "$TEXTO_INVALIDO" BLK1)
P=$(pay "$R" "rainforest-mind:revisor" "BLK1" "$TEXTO_INVALIDO" '{"agent_transcript_path":"'"$T14"'"}')
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
V=$(vereditos)
DEC=$(decisao_bloqueio_valida "$SAIDA")
if [ "$GOT" = 0 ] && [ "$DEC" = "valido" ] && [ "$V" = "[]" ]; then
  ok=$((ok+1)); echo "  ok    primeira parada com ultima linha fora do vocabulario bloqueia com {decision:block,reason:...VEREDITO: ok/reprovado...} e nao grava (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA primeira parada nao bloqueou como esperado (exit $GOT, decisao=$DEC): saida=$SAIDA vereditos=$V"
fi

echo
echo "== 15. segunda parada sem veredito valido grava invalido e nao bloqueia =="
# Base: a fixture REAL hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json
# (task 1), trocando so agent_type/cwd/agent_transcript_path/last_assistant_message
# para o cenario do teste — mantem stop_hook_active:true e as demais chaves.
FIXTURE_2P="$SRC/hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json"
reset_estado
T15=$(transcrito_com_texto "$TEXTO_INVALIDO" adc320ec84df66697)
P=$(node -e '
const fs = require("fs");
const [fixturePath, cwd, agentType, agentTranscriptPath, lastMsg] = process.argv.slice(1);
const base = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
base.cwd = cwd;
base.agent_type = agentType;
base.agent_transcript_path = agentTranscriptPath;
base.last_assistant_message = lastMsg;
process.stdout.write(JSON.stringify(base));
' "$FIXTURE_2P" "$R" "rainforest-mind:revisor" "$T15" "$TEXTO_INVALIDO")
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && [ -z "$SAIDA" ] && printf '%s' "$V" | grep -q '"veredito":"invalido"' && printf '%s' "$V" | grep -q '"agente_id":"adc320ec84df66697"'; then
  ok=$((ok+1)); echo "  ok    segunda parada (stop_hook_active:true) com veredito invalido grava e nao bloqueia (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA segunda parada nao gravou/bloqueou como esperado (exit $GOT): saida=$SAIDA vereditos=$V"
fi

echo
echo "== 16. veredito valido nao bloqueia =="
reset_estado
T16=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" VLD1)
P=$(pay "$R" "rainforest-mind:revisor" "VLD1" "$VEREDITO_OK" '{"agent_transcript_path":"'"$T16"'"}')
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
V=$(vereditos)
if [ "$GOT" = 0 ] && [ -z "$SAIDA" ] && printf '%s' "$V" | grep -q '"veredito":"ok"'; then
  ok=$((ok+1)); echo "  ok    veredito valido (VEREDITO: ok) nao bloqueia e grava normalmente (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA veredito valido bloqueou ou nao gravou (exit $GOT): saida=$SAIDA vereditos=$V"
fi

echo
echo "== 17. sem Slug nao bloqueia =="
reset_estado
P=$(pay "$R" "rainforest-mind:revisor" "NOSLUG1" "$TEXTO_INVALIDO" '{"agent_transcript_path":"'"$FIX"'/transcript-sem-slug.jsonl"}')
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
if [ "$GOT" = 0 ] && [ -z "$SAIDA" ]; then
  ok=$((ok+1)); echo "  ok    briefing sem 'Slug:' nao bloqueia, mesmo com ultima linha invalida (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA sem Slug bloqueou (nao deveria, exit $GOT): saida=$SAIDA"
fi

echo
echo "== 18. agente que nao e revisor nao bloqueia =="
reset_estado
P=$(pay "$R" "outro-agente" "NREV1" "$TEXTO_INVALIDO" '{"agent_transcript_path":"'"$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" NREV1)"'"}')
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
if [ "$GOT" = 0 ] && [ -z "$SAIDA" ]; then
  ok=$((ok+1)); echo "  ok    agent_type 'outro-agente' nao bloqueia, mesmo com ultima linha invalida (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA agente que nao e revisor bloqueou (nao deveria, exit $GOT): saida=$SAIDA"
fi

echo
echo "== 19. contrato-veredito desligado nao bloqueia =="
reset_estado
mkdir -p "$R/.rainforest"
printf '{"contrato-veredito": false}' > "$R/.rainforest/config.json"
T19=$(real_transcrito "$FIX/transcript-slug-string-ok.jsonl" TOGB1)
P=$(pay "$R" "rainforest-mind:revisor" "TOGB1" "$TEXTO_INVALIDO" '{"agent_transcript_path":"'"$T19"'"}')
SAIDA=$(printf '%s' "$P" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null); GOT=$?
if [ "$GOT" = 0 ] && [ -z "$SAIDA" ]; then
  ok=$((ok+1)); echo "  ok    contrato-veredito desligado nao bloqueia, mesmo com ultima linha invalida (exit $GOT)"
else
  falhou=$((falhou+1)); echo "  FALHA toggle desligado bloqueou (nao deveria, exit $GOT): saida=$SAIDA"
fi
rm -rf "$R/.rainforest"

echo
echo "-----------------------------------------"
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
