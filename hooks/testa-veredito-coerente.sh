#!/bin/bash
# Bateria da coerência veredito x achados (D3 e D8 do lote 2,
# docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-2.md; tarefa 1 do plano
# docs/rainforest/planos/2026-10-24-apoio-ao-dev-lote-2.md).
#
# Cobre hooks/veredito-revisor.cjs (SubagentStop) e scripts/critica-do-revisor.cjs
# com payload realista: agent_type rainforest-mind:revisor, Slug: no primeiro
# prompt do transcrito, ultima linha do relato = VEREDITO. Molde:
# hooks/testa-veredito-revisor.sh (sandbox, HOME falso, repositorio de fixture,
# transcrito na pasta real de sessao, payload por node -e).
#
# Caminho NATIVO via cygpath -m (mesma armadilha de testa-veredito-revisor.sh).
set -u
SRC_POSIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cygpath -m "$SRC_POSIX" 2>/dev/null || printf '%s' "$SRC_POSIX")"
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

ok=0; falhou=0

# Repositorio git real: toplevel(payload.cwd) precisa funcionar de verdade.
R="$RAIZ/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
mkdir -p "$R/docs/rainforest/estado"
echo base > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base

SLUG="revisor-fixture-caixa"
SLUG_JSON="$R/docs/rainforest/estado/$SLUG.json"

reset_estado() {
  node -e '
const fs = require("fs");
const path = require("path");
const [p, slug] = process.argv.slice(1);
fs.mkdirSync(path.dirname(p), {recursive: true});
fs.writeFileSync(p, JSON.stringify({
  slug, titulo: "fixture da bateria de coerencia do veredito", criado_em: "2026-10-24",
  arqueologia: { status: "dispensada" },
  design: { status: "aprovado", em: "2026-10-24" },
  plano: { status: "ok", em: "2026-10-24" },
  executar: { status: "ok", em: "2026-10-24" },
  revisar: { status: "pendente", vereditos: [] },
  verificar: { status: "pendente" },
  fechar: { status: "pendente" },
}, null, 2) + "\n");
' "$SLUG_JSON" "$SLUG"
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
' "$SLUG_JSON" "$1"
}

# Transcrito de sessao real com o TEXTO EXATO do relato (mesmo formato de
# testa-veredito-revisor.sh, transcrito_com_texto): D12 reextrai a ultima
# linha do arquivo, entao o texto do transcrito tem de bater com o payload.
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

# Payload de SubagentStop com os campos do payload real (mesmo molde de
# testa-veredito-revisor.sh). extra(JSON) sobrescreve: agent_transcript_path,
# stop_hook_active.
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

# Roda o hook real: SAIDA (stdout) e GOT (exit).
disparar() { # payload_json
  SAIDA="$(printf '%s' "$1" | RFM_ESTADO_ROOT="$R" node "$HOOK" 2>/dev/null)"; GOT=$?
}

# Roda critica-do-revisor.cjs sobre um transcrito: CRIT_OUT, CRIT_EXIT.
critica_com() { # texto, id
  local t root="$RAIZ_POSIX/crit-$2"
  t="$(transcrito_com_texto "$1" "$2")"
  mkdir -p "$root/docs/rainforest/estado"
  printf '{"revisar":{"vereditos":[{"agente":"revisor","agente_id":"%s","veredito":"reprovado","em":"2026-10-24","transcrito":"%s"}]}}\n' "$2" "$t" > "$root/docs/rainforest/estado/$SLUG.json"
  CRIT_OUT="$(RFM_ESTADO_ROOT="$(cygpath -m "$root" 2>/dev/null || printf '%s' "$root")" node "$CRITICA" --slug "$SLUG" 2>/dev/null)"; CRIT_EXIT=$?
}

registra() { # $1 = caso, $2 = 0 se passou
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok    $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (exit=$GOT)"
    echo "    saida: $SAIDA"
  fi
}

# Relatos realistas: achados numerados, ultima linha = VEREDITO.
TXT_ALTA='Achados:
1. [alta] O teste de borda quebra o CI em a.txt:1, o cenario e lista vazia.
2. [baixa] A mensagem de erro omite o caminho do arquivo.
VEREDITO: ok'
TXT_REPROVADO_NU='Falta ajuste no diff, o teste de borda nao cobre lista vazia.
VEREDITO: reprovado'

echo "== coerencia do veredito com os achados (D3) =="

echo "-- ok com [alta] --"
reset_estado
T=$(transcrito_com_texto "$TXT_ALTA" C1)
disparar "$(pay "$R" "rainforest-mind:revisor" "C1" "$TXT_ALTA" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' \
  && printf '%s' "$SAIDA" | grep -qF 'ok com achado [alta]' && printf '%s' "$SAIDA" | grep -qF 'alta 1' \
  && [ "$(veredito_de C1)" = "-" ]; then r=0; else r=1; fi
registra "VEREDITO: ok com achado [alta] devolve a vez na primeira parada (reason cita a regra e a contagem, nada gravado)" $r

reset_estado
TB=$(transcrito_com_texto "$TXT_ALTA" C1B)
disparar "$(pay "$R" "rainforest-mind:revisor" "C1B" "$TXT_ALTA" '{"agent_transcript_path":"'"$TB"'","stop_hook_active":true}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de C1B)" = "invalido" ]; then r=0; else r=1; fi
registra "ok com achado [alta], segunda parada: grava invalido e nao bloqueia (stop_hook_active)" $r

echo "-- reprovado sem achado marcado --"
reset_estado
T=$(transcrito_com_texto "$TXT_REPROVADO_NU" C2)
disparar "$(pay "$R" "rainforest-mind:revisor" "C2" "$TXT_REPROVADO_NU" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' \
  && printf '%s' "$SAIDA" | grep -qF 'reprovado sem achado marcado' && [ "$(veredito_de C2)" = "-" ]; then r=0; else r=1; fi
registra "VEREDITO: reprovado sem achado marcado devolve a vez na primeira parada" $r

reset_estado
TB=$(transcrito_com_texto "$TXT_REPROVADO_NU" C2B)
disparar "$(pay "$R" "rainforest-mind:revisor" "C2B" "$TXT_REPROVADO_NU" '{"agent_transcript_path":"'"$TB"'","stop_hook_active":true}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de C2B)" = "invalido" ]; then r=0; else r=1; fi
registra "reprovado sem achado marcado, segunda parada: grava invalido e nao bloqueia" $r

echo "-- severidade que nao bloqueia --"
TXT_OK_MEDIA='Achados:
1. [media] Mensagem de erro sem o caminho do arquivo.
VEREDITO: ok'
reset_estado
T=$(transcrito_com_texto "$TXT_OK_MEDIA" M1)
disparar "$(pay "$R" "rainforest-mind:revisor" "M1" "$TXT_OK_MEDIA" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de M1)" = "ok" ]; then r=0; else r=1; fi
registra "ok so com [media] grava ok sem bloquear" $r

TXT_OK_BAIXA='Achados:
- [baixa] Nome de variavel pouco claro em a.txt:2.
VEREDITO: ok'
reset_estado
T=$(transcrito_com_texto "$TXT_OK_BAIXA" B1)
disparar "$(pay "$R" "rainforest-mind:revisor" "B1" "$TXT_OK_BAIXA" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de B1)" = "ok" ]; then r=0; else r=1; fi
registra "ok so com [baixa] grava ok sem bloquear" $r

TXT_REPROVADO_BAIXA='**[baixa]** Falta um teste de borda.
VEREDITO: reprovado'
reset_estado
T=$(transcrito_com_texto "$TXT_REPROVADO_BAIXA" B2)
disparar "$(pay "$R" "rainforest-mind:revisor" "B2" "$TXT_REPROVADO_BAIXA" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de B2)" = "reprovado" ]; then r=0; else r=1; fi
registra "reprovado com um [baixa] grava reprovado sem bloquear" $r

TXT_REPROVADO_ACENTO='1. [média] Falta o teste de borda.
VEREDITO: reprovado'
reset_estado
T=$(transcrito_com_texto "$TXT_REPROVADO_ACENTO" AC1)
disparar "$(pay "$R" "rainforest-mind:revisor" "AC1" "$TXT_REPROVADO_ACENTO" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de AC1)" = "reprovado" ]; then r=0; else r=1; fi
registra "[média] com acento conta como achado: reprovado so com [média] grava reprovado" $r

echo "-- o que nao conta como achado --"
TXT_CITA_ALTA='Diff conferido, sem pendencia. Cito o marcador [alta] so como exemplo, no meio da frase.
VEREDITO: ok'
reset_estado
T=$(transcrito_com_texto "$TXT_CITA_ALTA" CI1)
disparar "$(pay "$R" "rainforest-mind:revisor" "CI1" "$TXT_CITA_ALTA" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de CI1)" = "ok" ]; then r=0; else r=1; fi
registra "[alta] citado no meio da frase nao conta: ok grava ok" $r

TXT_DESIGN_ANTES='Achados:
1. [design] [alta] O plano contesta a D3, e o revisor nao aceita o formato.
VEREDITO: ok'
reset_estado
T=$(transcrito_com_texto "$TXT_DESIGN_ANTES" DA1)
disparar "$(pay "$R" "rainforest-mind:revisor" "DA1" "$TXT_DESIGN_ANTES" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && printf '%s' "$SAIDA" | grep -qF 'ok com achado [alta]'; then r=0; else r=1; fi
registra "[design] antes da severidade: [alta] depois dele ainda conta, ok devolve a vez" $r

TXT_SO_DESIGN='1. [design] O plano contesta a D3, e o formato nao cabe no caso.
VEREDITO: reprovado'
reset_estado
T=$(transcrito_com_texto "$TXT_SO_DESIGN" SD1)
disparar "$(pay "$R" "rainforest-mind:revisor" "SD1" "$TXT_SO_DESIGN" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de SD1)" = "reprovado" ]; then r=0; else r=1; fi
registra "reprovado cujo unico item e [design] (sem severidade) conta no total: grava reprovado sem bloquear" $r

echo "-- estado.cjs recusa invalido que a mensagem nao justifica --"
ESTADO="$SRC/scripts/estado.cjs"
TXT_NEG='Diff conferido, sem pendencia.
VEREDITO: ok'
reset_estado
TN=$(transcrito_com_texto "$TXT_NEG" NEG1)
SAIDA=$(RFM_ESTADO_ROOT="$R" node "$ESTADO" veredito --slug "$SLUG" --estagio revisar --veredito invalido --agente rainforest-mind:revisor --agente-id NEG1 --transcrito "$TN" 2>&1); GOT=$?
if [ "$GOT" -eq 2 ] && [ "$(veredito_de NEG1)" = "-" ]; then r=0; else r=1; fi
registra "estado.cjs recusa --veredito invalido com transcrito VEREDITO: ok sem [alta] (exit 2, nada gravado)" $r

echo "-- critica-do-revisor.cjs com a mesma regra --"
critica_com "$TXT_REPROVADO_NU" CR1
if [ "$CRIT_EXIT" -eq 4 ] && [ -z "$CRIT_OUT" ]; then r=0; else r=1; fi
registra "critica-do-revisor sai 4 para reprovado sem achado marcado (exit=$CRIT_EXIT)" $r

critica_com 'Achados:
1. [media] Falta o teste de borda.
VEREDITO: reprovado' CR2
if [ "$CRIT_EXIT" -eq 0 ] && printf '%s' "$CRIT_OUT" | grep -qF '[media] Falta'; then r=0; else r=1; fi
registra "critica-do-revisor sai 0 para reprovado com um [media] (exit=$CRIT_EXIT)" $r

critica_com "$TXT_SO_DESIGN" CR3
if [ "$CRIT_EXIT" -eq 3 ] && printf '%s' "$CRIT_OUT" | grep -qF '[design] O plano'; then r=0; else r=1; fi
registra "critica-do-revisor sai 3 para reprovado cujo unico item e [design] (exit=$CRIT_EXIT)" $r

echo "-- etiquetas em negrito separado (achado do revisor, lote 2 volta 2) --"
TXT_NEG_SEP='Achados:
1. **[design]** **[alta]** O plano contesta a D3, e o revisor nao aceita o formato.
VEREDITO: ok'
reset_estado
T=$(transcrito_com_texto "$TXT_NEG_SEP" NS1)
disparar "$(pay "$R" "rainforest-mind:revisor" "NS1" "$TXT_NEG_SEP" '{"agent_transcript_path":"'"$T"'"}')"
if [ "$GOT" = 0 ] && printf '%s' "$SAIDA" | grep -qF '"decision":"block"' \
  && printf '%s' "$SAIDA" | grep -qF 'alta 1' && printf '%s' "$SAIDA" | grep -qF 'design 1'; then r=0; else r=1; fi
registra "**[design]** **[alta]** em negrito separado conta alta 1 e design 1: ok devolve a vez na primeira parada" $r

CONT="$(node -e '
const { contarAchados } = require(process.argv[1]);
const casos = ["1. **[design]** **[alta]** t", "1. **[alta]** **[design]** t", "**[alta] [design]** t", "[alta] **[design]** t"];
const ok = casos.every((c) => { const a = contarAchados(c); return a.alta === 1 && a.design === 1 && a.total === 1; });
process.stdout.write(ok ? "ok" : JSON.stringify(casos.map((c) => contarAchados(c))));
' "$SRC/hooks/lib/achados-revisor.cjs" 2>&1)"
SAIDA="$CONT"; GOT=0
if [ "$CONT" = "ok" ]; then r=0; else r=1; fi
registra "contarAchados: [alta] e [design] em qualquer ordem e com negrito separado contam alta 1, design 1, total 1" $r

TXT_ALTA_DESIGN_NEG='Achados:
1. **[alta]** **[design]** O plano contesta a D3, e o formato nao cabe no caso.
VEREDITO: reprovado'
critica_com "$TXT_ALTA_DESIGN_NEG" CR4
if [ "$CRIT_EXIT" -eq 3 ] && printf '%s' "$CRIT_OUT" | grep -qF 'O plano contesta a D3'; then r=0; else r=1; fi
registra "critica-do-revisor sai 3 para reprovado com 1. **[alta]** **[design]** (exit=$CRIT_EXIT)" $r

echo "-- segunda parada com resposta curta (achado 1, lote 2 volta 2) --"
TXT_CURTO='Corrigido, o veredito e reprovado.
VEREDITO: reprovado'
reset_estado
T=$(transcrito_com_texto "$TXT_ALTA" CUR1)
disparar "$(pay "$R" "rainforest-mind:revisor" "CUR1" "$TXT_ALTA" '{"agent_transcript_path":"'"$T"'"}')"
PRIMEIRA_SAIDA="$SAIDA"; PRIMEIRA_GOT=$GOT
T=$(transcrito_com_texto "$TXT_CURTO" CUR1)
disparar "$(pay "$R" "rainforest-mind:revisor" "CUR1" "$TXT_CURTO" '{"agent_transcript_path":"'"$T"'","stop_hook_active":true}')"
if [ "$PRIMEIRA_GOT" = 0 ] && printf '%s' "$PRIMEIRA_SAIDA" | grep -qF 'RELATO COMPLETO' \
  && [ "$GOT" = 0 ] && ! printf '%s' "$SAIDA" | grep -qF '"decision":"block"' && [ "$(veredito_de CUR1)" = "invalido" ]; then r=0; else r=1; fi
registra "resposta curta sem achado na segunda parada grava invalido; o motivo da primeira parada pede o RELATO COMPLETO" $r

echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
