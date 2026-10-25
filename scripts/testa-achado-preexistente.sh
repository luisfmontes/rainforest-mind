#!/bin/bash
# Bateria do achado preexistente (lote 6, D3 e D9 de
# docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md; tarefa 1 do plano
# docs/rainforest/planos/2026-10-24-apoio-ao-dev-lote-6.md).
#
# Cobre a marca [preexistente] na lib hooks/lib/achados-revisor.cjs, no hook
# hooks/veredito-revisor.cjs (SubagentStop), em scripts/critica-do-revisor.cjs
# (redespacho e --comparacao). O repositório é real: a base vai para origin/main
# (remoto bare na caixa) e a branch altera só a linha 3 de a.cjs. Tudo numa caixa
# mktemp -d FORA do worktree. Molde: hooks/testa-veredito-coerente.sh.
set -u

SRC_POSIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cygpath -m "$SRC_POSIX" 2>/dev/null || printf '%s' "$SRC_POSIX")"
LIB="$SRC/hooks/lib/achados-revisor.cjs"
HOOK="$SRC/hooks/veredito-revisor.cjs"
CRITICA="$SRC/scripts/critica-do-revisor.cjs"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

HOME_SBOX_POSIX="$RAIZ_POSIX/home"
mkdir -p "$HOME_SBOX_POSIX"
HOME_SBOX="$(cygpath -m "$HOME_SBOX_POSIX" 2>/dev/null || printf '%s' "$HOME_SBOX_POSIX")"
export HOME="$HOME_SBOX"
export USERPROFILE="$HOME_SBOX"
export CLAUDE_CONFIG_DIR="$HOME_SBOX/.claude-personal"
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@teste
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@teste

ok=0; falhou=0
SLUG="revisor-fixture-caixa"

# ---------------------------------------------------------------- a fixture
# Remoto bare (origin/main) + repo com a base em main e a branch que muda a linha 3.
REMOTO_POSIX="$RAIZ_POSIX/remoto.git"
REMOTO="$RAIZ/remoto.git"
R_POSIX="$RAIZ_POSIX/repo"
R="$RAIZ/repo"
git init -q --bare "$REMOTO_POSIX"
git init -q -b main "$R_POSIX"
git -C "$R_POSIX" config commit.gpgsign false
printf 'l1\nl2\nl3\nl4\nl5\n' > "$R_POSIX/a.cjs"
# Caminho com espaço e acento, como os dos repositórios Protheus: o git põe
# tabulação no fim do cabeçalho +++ e o caminho não cabe em [\w./-].
PE_DIR="Ponto de Entrada/69 - Gestão"
mkdir -p "$R_POSIX/$PE_DIR"
printf 'p1\np2\np3\n' > "$R_POSIX/$PE_DIR/x y.prw"
git -C "$R_POSIX" add -A
git -C "$R_POSIX" commit -qm base
git -C "$R_POSIX" remote add origin "$REMOTO"
git -C "$R_POSIX" push -q origin main
git -C "$R_POSIX" fetch -q origin
printf 'l1\nl2\nNOVA\nl4\nl5\n' > "$R_POSIX/a.cjs"
printf 'p1\nP2 NOVA\np3\n' > "$R_POSIX/$PE_DIR/x y.prw"
git -C "$R_POSIX" commit -qam "altera a linha 3 de a.cjs e a 2 do prw"

# Repo sem remoto: não há origin/main, então a marca não é conferível.
R2_POSIX="$RAIZ_POSIX/sem-remoto"
R2="$RAIZ/sem-remoto"
git init -q -b main "$R2_POSIX"
printf 'l1\nl2\nl3\nl4\nl5\n' > "$R2_POSIX/a.cjs"
git -C "$R2_POSIX" add a.cjs
git -C "$R2_POSIX" commit -qm base

mkdir -p "$R_POSIX/docs/rainforest/estado" "$R2_POSIX/docs/rainforest/estado"

# Estado completo (fluxo com design, plano e executar fechados) no repo R.
reset_estado() {
  printf '%s\n' '{"slug":"revisor-fixture-caixa","titulo":"fixture do achado preexistente","criado_em":"2026-10-24","arqueologia":{"status":"dispensada"},"design":{"status":"aprovado","em":"2026-10-24"},"plano":{"status":"ok","em":"2026-10-24"},"executar":{"status":"ok","em":"2026-10-24"},"revisar":{"status":"pendente","vereditos":[]},"verificar":{"status":"pendente"},"fechar":{"status":"pendente"}}' > "$R_POSIX/docs/rainforest/estado/$SLUG.json"
}

# Janela de revisar com o bloco que o teste escolhe (JSON já montado).
estado_com() { # <json do bloco revisar>
  printf '{"design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":%s}\n' "$1" > "$R_POSIX/docs/rainforest/estado/$SLUG.json"
}

# Veredito gravado para um agente_id ("-" se nada foi gravado para ele).
veredito_de() { # agente_id
  node -e '
const fs = require("fs");
try {
  const e = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const v = ((e.revisar && e.revisar.vereditos) || []).filter((x) => x.agente_id === process.argv[2]);
  process.stdout.write(v.length ? v[v.length - 1].veredito : "-");
} catch {
  process.stdout.write("-");
}
' "$R_POSIX/docs/rainforest/estado/$SLUG.json" "$1"
}

# Transcrito de sessão com o texto do relato: o hook e a crítica leem a última
# mensagem e o Slug: da primeira (mesmo formato de testa-veredito-coerente.sh).
transcrito_com_texto() { # texto, agente_id
  local texto="$1" id="$2" sess="sess-caixa"
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

# Payload de SubagentStop (molde de testa-veredito-coerente.sh). cwd = repo R.
pay() { # cwd, agent_type, agent_id, last_assistant_message, extra_json
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
process.stdout.write(JSON.stringify(Object.assign(base, extra ? JSON.parse(extra) : {})));
' "$1" "$2" "$3" "$4" "${5:-}"
}

# Roda o hook real: SAIDA (stdout), GOT (exit) e ERR_HOOK (stderr).
disparar() { # payload_json
  SAIDA="$(printf '%s' "$1" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>"$RAIZ_POSIX/err-hook")"; GOT=$?
  ERR_HOOK="$(cat "$RAIZ_POSIX/err-hook")"
}

# Roda critica-do-revisor.cjs sobre o repo R (ou o de RAIZ_ALVO): CRIT_OUT, CRIT_ERR, CRIT_EXIT.
critica_com() { # texto, agente_id
  local t
  t="$(transcrito_com_texto "$1" "$2")"
  estado_com "{\"status\":\"reprovado\",\"vereditos\":[{\"agente\":\"revisor\",\"agente_id\":\"$2\",\"veredito\":\"reprovado\",\"em\":\"2026-10-24\",\"transcrito\":\"$t\"}]}"
  CRIT_OUT="$(RFM_ESTADO_ROOT="$R" node "$CRITICA" --slug "$SLUG" 2>"$RAIZ_POSIX/err-crit")"; CRIT_EXIT=$?
  CRIT_ERR="$(cat "$RAIZ_POSIX/err-crit")"
}

# tem <texto> <trecho>: o trecho (literal) aparece no texto?
tem() { printf '%s' "$1" | grep -qF -- "$2"; }

registra() { # $1 = caso, $2 = 0 se passou
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok    $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (hook exit=$GOT, critica exit=${CRIT_EXIT:-?})"
    echo "    saida do hook: $SAIDA"
    echo "    stderr do hook: $ERR_HOOK"
    echo "    saida da critica: $CRIT_OUT"
    echo "    stderr da critica: $CRIT_ERR"
  fi
}

# ---------------------------------------------------------------- relatos
TXT_H1='**[alta]** [preexistente] a.cjs:5 — defeito antigo, linha que a entrega não tocou
VEREDITO: ok'
TXT_H2='**[alta]** [preexistente] a.cjs:3 — defeito criado pela própria entrega
VEREDITO: ok'
TXT_H3='**[media]** [preexistente] a.cjs:5 — defeito antigo
VEREDITO: reprovado'
TXT_H4='**[media]** b.cjs:1 — defeito novo
**[alta]** [preexistente] a.cjs:5 — defeito antigo
VEREDITO: reprovado'
TXT_C1='**[alta]** [preexistente] a.cjs:5 — defeito antigo
**[media]** b.cjs:1 — defeito novo
VEREDITO: reprovado'
TXT_C2='**[alta]** [preexistente] a.cjs:3 — defeito criado pela própria entrega
VEREDITO: reprovado'
TXT_C3='**[alta]** [preexistente] a.cjs:5 — defeito antigo
VEREDITO: reprovado'

echo "== achado preexistente: marca na lib, no hook e na crítica (D3/D9 do lote 6) =="

# ---------------------------------------------------------------- (L) lib, sem git
echo "-- (L) lib achados-revisor: a marca não bloqueia, e reprovado só com preexistente é incoerente --"
RES_LIB="$(node -e '
const { contarAchados, incoerencia } = require(process.argv[1]);
const r = {
  L1: incoerencia("ok", contarAchados("**[alta]** [preexistente] a.cjs:3 — x\nVEREDITO: ok")) === null,
  L2: (() => { const a = contarAchados("[preexistente] [media] b.cjs:1 — y"); return a.media === 0 && a.total === 0 && a.preexistente === 1; })(),
  L3: /reprovado sem achado marcado/.test(incoerencia("reprovado", contarAchados("[alta] [preexistente] a.cjs:3 — x")) || ""),
  L4: /ok com achado/.test(incoerencia("ok", contarAchados("**[alta]** a.cjs:3 — x")) || ""),
};
process.stdout.write(JSON.stringify(r));
' "$LIB" 2>&1)"
GOT=0; SAIDA=""; ERR_HOOK=""; CRIT_EXIT=""; CRIT_OUT=""; CRIT_ERR=""
r=1; if [ "$RES_LIB" = '{"L1":true,"L2":true,"L3":true,"L4":true}' ]; then r=0; fi
registra "(L1) ok com [alta] [preexistente] é coerente; (L2) ordem livre, não conta; (L3) reprovado só preexistente é incoerente; (L4) [alta] sem marca segue incoerente (obtido: $RES_LIB)" $r

# ---------------------------------------------------------------- (H) hook
echo "-- (H) hook SubagentStop: a marca aceita por padrão e recusada quando o diff toca a linha --"

reset_estado
T=$(transcrito_com_texto "$TXT_H1" H1)
disparar "$(pay "$R" "rainforest-mind:revisor" "H1" "$TXT_H1" '{"agent_transcript_path":"'"$T"'"}')"
r=1
if [ "$GOT" -eq 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de H1)" = "ok" ]; then r=0; fi
registra "(H1) ok com [alta] [preexistente] a.cjs:5 (linha fora do diff) grava ok sem bloquear" $r

reset_estado
T=$(transcrito_com_texto "$TXT_H2" H2)
disparar "$(pay "$R" "rainforest-mind:revisor" "H2" "$TXT_H2" '{"agent_transcript_path":"'"$T"'"}')"
r=1
if [ "$GOT" -eq 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' \
  && tem "$ERR_HOOK" 'marca [preexistente] recusada: a.cjs:3 está no diff' && [ "$(veredito_de H2)" = "-" ]; then r=0; fi
registra "(H2) ok com [alta] [preexistente] a.cjs:3 (linha que o diff trocou) devolve a vez e não grava" $r

reset_estado
T=$(transcrito_com_texto "$TXT_H3" H3)
disparar "$(pay "$R" "rainforest-mind:revisor" "H3" "$TXT_H3" '{"agent_transcript_path":"'"$T"'"}')"
r=1
if [ "$GOT" -eq 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && tem "$SAIDA" 'reprovado sem achado marcado'; then r=0; fi
registra "(H3) reprovado só com [media] [preexistente] a.cjs:5 devolve a vez: regra reprovado sem achado marcado" $r

reset_estado
T=$(transcrito_com_texto "$TXT_H4" H4)
disparar "$(pay "$R" "rainforest-mind:revisor" "H4" "$TXT_H4" '{"agent_transcript_path":"'"$T"'"}')"
r=1
if [ "$GOT" -eq 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de H4)" = "reprovado" ]; then r=0; fi
registra "(H4) reprovado com [media] normal e um [alta] [preexistente] fora do diff grava reprovado" $r

# Segunda parada do H2: o hook não bloqueia de novo e grava invalido. O estado.cjs
# confirma o invalido no transcrito, e tem de aplicar a mesma recusa pelo diff.
reset_estado
T=$(transcrito_com_texto "$TXT_H2" H5)
disparar "$(pay "$R" "rainforest-mind:revisor" "H5" "$TXT_H2" '{"agent_transcript_path":"'"$T"'","stop_hook_active":true}')"
r=1
if [ "$GOT" -eq 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de H5)" = "invalido" ]; then r=0; fi
registra "(H5) segunda parada do ok com [alta] [preexistente] a.cjs:3 grava invalido (obtido: $(veredito_de H5))" $r

# Revisor com cwd fora do repo do estado (worktree de agente): o hook confere no
# cwd dele (aqui, sem base: a marca vale e reprovado fica sem achado -> invalido),
# e o estado.cjs tem de conferir no MESMO cwd, não na raiz do estado (onde a.cjs:3
# está no diff e a recusa tornaria o relato coerente, sem gravar nada).
TXT_H6='**[media]** [preexistente] a.cjs:3 — defeito antigo
VEREDITO: reprovado'
reset_estado
cp "$R_POSIX/docs/rainforest/estado/$SLUG.json" "$R2_POSIX/docs/rainforest/estado/$SLUG.json"
T=$(transcrito_com_texto "$TXT_H6" H6)
disparar "$(pay "$R2" "rainforest-mind:revisor" "H6" "$TXT_H6" '{"agent_transcript_path":"'"$T"'","stop_hook_active":true}')"
r=1
if [ "$GOT" -eq 0 ] && [ "$(veredito_de H6)" = "invalido" ]; then r=0; fi
registra "(H6) cwd do revisor sem base e estado em repo com diff: a segunda parada grava invalido (obtido: $(veredito_de H6))" $r

# ---------------------------------------------------------------- (P) caminho com espaço e acento; sem citação
echo "-- (P) a citação se acha pelo caminho do diff, com espaço e acento; sem citação, a marca é recusada --"
RES_P="$(node -e '
const { preexistentesNoDiff } = require(process.argv[1]);
const cwd = process.argv[2];
const m = (t) => (preexistentesNoDiff(t, cwd) || ["sem base"]).map((x) => x.motivo).join("|");
process.stdout.write(JSON.stringify({
  P1: m("**[alta]** [preexistente] Ponto de Entrada\\69 - Gestão\\x y.prw:2 — linha que o diff trocou"),
  P2: m("**[alta]** [preexistente] `Ponto de Entrada/69 - Gestão/x y.prw:3` — linha antiga"),
  P3: m("**[alta]** [preexistente] a funcao X quebra o contrato"),
  P4: m("**[alta]** [preexistente] xa.cjs:3 — outro arquivo, que só termina em a.cjs"),
}));
' "$LIB" "$R" 2>&1)"
GOT=0; SAIDA=""; ERR_HOOK=""; CRIT_EXIT=""; CRIT_OUT=""; CRIT_ERR=""
r=1; if [ "$RES_P" = '{"P1":"Ponto de Entrada/69 - Gestão/x y.prw:2 está no diff","P2":"","P3":"sem arquivo:linha para conferir","P4":""}' ]; then r=0; fi
registra "(P1) prw com espaço e acento na linha do diff é recusado; (P2) a linha antiga dele passa; (P3) sem arquivo:linha é recusado; (P4) xa.cjs:3 não é a.cjs:3 (obtido: $RES_P)" $r

# ---------------------------------------------------------------- (C) crítica
echo "-- (C) critica-do-revisor: a marca aceita sai do redespacho; a recusada fica sem a marca --"

critica_com "$TXT_C1" C1
r=1
if [ "$CRIT_EXIT" -eq 0 ] && tem "$CRIT_OUT" 'b.cjs:1 — defeito novo' && ! tem "$CRIT_OUT" 'a.cjs:5' \
  && tem "$CRIT_ERR" '## Preexistentes (não são da entrega — Issue, não correção)' && tem "$CRIT_ERR" 'a.cjs:5 — defeito antigo'; then r=0; fi
registra "(C1) preexistente aceito sai do redespacho e vai à seção Preexistentes; o novo fica" $r

critica_com "$TXT_C2" C2
r=1
if [ "$CRIT_EXIT" -eq 0 ] && tem "$CRIT_OUT" 'a.cjs:3 — defeito criado pela própria entrega' && ! tem "$CRIT_OUT" '[preexistente]' \
  && tem "$CRIT_ERR" 'marca [preexistente] recusada: a.cjs:3 está no diff'; then r=0; fi
registra "(C2) marca recusada pelo diff: a linha fica na crítica sem a marca, e o stderr diz recusada" $r

critica_com "$TXT_C3" C3
r=1
if [ "$CRIT_EXIT" -eq 4 ] && tem "$CRIT_ERR" 'reprovado sem achado marcado'; then r=0; fi
registra "(C3) reprovado só com preexistente aceito sai 4, como reprovado sem achado" $r

# Sem base: repo sem origin/main. A marca vale como escrita e o stderr diz não conferida.
t2="$(transcrito_com_texto "$TXT_C1" C4)"
printf '{"revisar":{"status":"reprovado","vereditos":[{"agente":"revisor","agente_id":"C4","veredito":"reprovado","em":"2026-10-24","transcrito":"%s"}]}}\n' "$t2" > "$R2_POSIX/docs/rainforest/estado/$SLUG.json"
CRIT_OUT="$(RFM_ESTADO_ROOT="$R2" node "$CRITICA" --slug "$SLUG" 2>"$RAIZ_POSIX/err-crit")"; CRIT_EXIT=$?
CRIT_ERR="$(cat "$RAIZ_POSIX/err-crit")"
r=1
if [ "$CRIT_EXIT" -eq 0 ] && tem "$CRIT_ERR" 'marca [preexistente] não conferida: sem base' && tem "$CRIT_ERR" 'a.cjs:5 — defeito antigo'; then r=0; fi
registra "(C4) sem base conferível: stderr diz não conferida e a marca vale como escrita" $r

# --comparacao: só o bloco; sai 0 também com veredito ok na janela atual.
ta="$(transcrito_com_texto "$TXT_C1" ANT5)"
tb="$(transcrito_com_texto 'VEREDITO: ok' ATU5)"
estado_com "{\"status\":\"ok\",\"voltas\":[{\"volta\":1,\"vereditos\":[{\"agente\":\"revisor\",\"agente_id\":\"ANT5\",\"veredito\":\"reprovado\",\"em\":\"2026-10-24\",\"transcrito\":\"$ta\"}]}],\"vereditos\":[{\"agente\":\"revisor\",\"agente_id\":\"ATU5\",\"veredito\":\"ok\",\"em\":\"2026-10-24\",\"transcrito\":\"$tb\"}]}"
CRIT_OUT="$(RFM_ESTADO_ROOT="$R" node "$CRITICA" --slug "$SLUG" --comparacao 2>"$RAIZ_POSIX/err-crit")"; CRIT_EXIT=$?
CRIT_ERR="$(cat "$RAIZ_POSIX/err-crit")"
r=1
if [ "$CRIT_EXIT" -eq 0 ] && tem "$CRIT_OUT" '## Comparação com a volta anterior' && tem "$CRIT_OUT" '- [alta] a.cjs — sumiu — confirmar se foi corrigido' \
  && ! tem "$CRIT_OUT" 'defeito novo'; then r=0; fi
registra "(C5) --comparacao com veredito ok: sai 0, só o bloco, e o que sumiu aparece" $r

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
