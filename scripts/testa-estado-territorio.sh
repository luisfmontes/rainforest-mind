#!/bin/bash
# Bateria do rastro do territorio no scripts/estado.cjs (D9 do mapa de estagios).
# Uso: bash scripts/testa-estado-territorio.sh
#
# Monta uma caixa de areia como a testa-estado.sh (copia dos scripts para mktemp),
# com territorio.cjs ao lado e um CLAUDE_CONFIG_DIR/HOME temporarios cujo
# installed_plugins.json aponta para o territorio sintetico (inventado; extensao .abc).
# Zero casos pulados.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$SRC/test/fixtures/territorio"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

total=0
vermelhas=""
caso() { # nome, 0=ok
  total=$((total + 1))
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FALHA $1"; vermelhas="$vermelhas\"$1\","; fi
}

nativo() { local p="$1"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -m "$1")"; printf '%s' "$p"; }

# HOME e config de teste: nunca o do usuario.
HOME_T="$TMP/home"; mkdir -p "$HOME_T"
PLUG="$TMP/plugin"; cp -r "$FIX/sintetico" "$PLUG"
CFG="$HOME_T/.claude-personal"; mkdir -p "$CFG/plugins"
printf '{"version":2,"plugins":{"sintetico@teste":[{"scope":"user","installPath":"%s"}]}}' "$(nativo "$PLUG")" > "$CFG/plugins/installed_plugins.json"
export HOME="$HOME_T" USERPROFILE="$HOME_T" CLAUDE_CONFIG_DIR="$CFG"
unset RFM_ESTADO_ROOT CLAUDE_PROJECT_DIR

monta_caixa() { # dir, com_territorio_cjs(1|0), com_abc(1|0)
  local d="$1"
  mkdir -p "$d/scripts/lib" "$d/hooks/lib"
  cp "$SRC/scripts/estado.cjs" "$SRC/scripts/conferir-fluxo.cjs" "$SRC/scripts/conferir-mutacao.cjs" "$d/scripts/"
  [ "$2" = 1 ] && cp "$SRC/scripts/territorio.cjs" "$d/scripts/"
  cp "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$d/scripts/lib/"
  cp "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/trava-jsonl.cjs" "$d/hooks/lib/"
  touch "$d/FOCO.md"
  [ "$3" = 1 ] && cp "$FIX/repo-abc/x.abc" "$d/x.abc"
  return 0
}

M() { node scripts/estado.cjs marcar --slug "$@"; } # M <slug> --estagio ...

# Fluxo ate o estagio anterior ao verificar, com a evidencia de territorio que o mapa pede.
# Roda dentro da caixa corrente. $1 = slug. Silencioso.
ate_executar_fechado() {
  local s="$1"
  node scripts/estado.cjs iniciar --slug "$s" >/dev/null
  M "$s" --estagio design --status aprovado --json '{"territorio":{"mcp":[{"tool":"mcp__srv__dicionario"}]}}' >/dev/null 2>&1
  M "$s" --estagio plano --status ok >/dev/null 2>&1
  node scripts/estado.cjs exigir --slug "$s" --estagio executar >/dev/null 2>&1
  M "$s" --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-1"}],"territorio":{"agentes":[{"tipo":"sintetico:executor"}]}}' >/dev/null 2>&1
}
ate_revisar_fechado() {
  ate_executar_fechado "$1"
  M "$1" --estagio revisar --status ok >/dev/null 2>&1
}

SB="$TMP/caixa"; monta_caixa "$SB" 1 1
cd "$SB" || exit 1

# 1
ate_revisar_fechado a1
out=$(M a1 --estagio verificar --status ok --json '{"comando":"bash test.sh","saida":"3 casos"}' 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'lint'
caso "verificar sem evidencia do comando obrigatorio recusa com exit 2" $?

# 2
ate_revisar_fechado a2
out=$(M a2 --estagio verificar --status ok --json '{"comando":"bash test.sh","saida":"3 casos","territorio":{"comandos":[{"id":"lint","comando":"true x.abc","saida":"limpo","exit":0}]}}' 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'verificar: ok'
caso "verificar com evidencia do comando obrigatorio passa" $?

# 3
grave=$(node scripts/estado.cjs ler --slug a2 2>&1 | node -e '
let t="";process.stdin.on("data",d=>t+=d).on("end",()=>{
const e=JSON.parse(t);const c=e.verificar&&e.verificar.territorio&&e.verificar.territorio.comandos;
process.stdout.write(c&&c[0]&&c[0].id==="lint"?"gravado":"ausente");});')
[ "$grave" = "gravado" ]
caso "campo territorio fica gravado no estado" $?

# 4
ate_executar_fechado a4
out2=$(M a4 --estagio revisar --status ok 2>&1); rc2=$?
[ $rc2 = 0 ] && echo "$out2" | grep -q 'aviso: item opcional do territorio sem evidencia: sintetico:revisor' && echo "$out2" | grep -qx 'revisar: ok'
caso "opcional sem evidencia so avisa e sai 0" $?

# 5: mesmo marcar em repo sem territorio, com e sem territorio.cjs ao lado
SA="$TMP/sem-a"; monta_caixa "$SA" 1 0
SBX="$TMP/sem-b"; monta_caixa "$SBX" 0 0
fluxo_sem() { # imprime stdout+exit de cada marcar
  local s=z
  node scripts/estado.cjs iniciar --slug $s >/dev/null
  M $s --estagio design --status aprovado; echo "rc=$?"
  M $s --estagio plano --status ok; echo "rc=$?"
  node scripts/estado.cjs exigir --slug $s --estagio executar >/dev/null 2>&1
  M $s --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-1"}]}'; echo "rc=$?"
  M $s --estagio revisar --status ok; echo "rc=$?"
  M $s --estagio verificar --status ok --json '{"comando":"bash test.sh","saida":"3 casos"}'; echo "rc=$?"
}
sa=$(cd "$SA" && fluxo_sem 2>/dev/null)
sb=$(cd "$SBX" && fluxo_sem 2>/dev/null)
[ -n "$sa" ] && [ "$sa" = "$sb" ] && echo "$sa" | grep -qx 'verificar: ok'
caso "repo sem territorio: marcar identico ao de antes" $?
cd "$SB" || exit 1

# 6
HV="$TMP/home-vazio"; mkdir -p "$HV"
js=$(HOME="$HV" USERPROFILE="$HV" node "$SRC/scripts/territorio.cjs" estagio verificar --json --raiz "$FIX/repo-abc" 2>&1); rc=$?
ok6=$(node -e '
const j=JSON.parse(process.argv[1]);
const l=j.itens.find(i=>i.classe==="comando"&&i.id==="lint");
process.stdout.write(j.territorio==="sintetico"&&l&&l.obrigatorio===true&&!process.argv[1].includes("{lint}")?"s":"n");
' "$js" 2>&1)
[ $rc = 0 ] && [ "$ok6" = "s" ]
caso "territorio.cjs --json lista itens sem resolver variavel" $?

# 7: plugin invalido (versao_contrato 1) que nao casa com o repo nao recusa o marcar
PZ="$TMP/plugin-zz"; mkdir -p "$PZ"
printf '{"versao_contrato":1,"nome":"zz","deteccao":{"extensoes":[".zzz"],"arquivos":[]}}' > "$PZ/territorio.json"
CFGZ="$HOME_T/.claude-zz"; mkdir -p "$CFGZ/plugins"
printf '{"version":2,"plugins":{"zz@teste":[{"scope":"user","installPath":"%s"}],"sintetico@teste":[{"scope":"user","installPath":"%s"}]}}' "$(nativo "$PZ")" "$(nativo "$PLUG")" > "$CFGZ/plugins/installed_plugins.json"
SZ="$TMP/sem-z"; monta_caixa "$SZ" 1 0
sz=$(cd "$SZ" && CLAUDE_CONFIG_DIR="$CFGZ" fluxo_sem 2>/dev/null)
[ -n "$sz" ] && [ "$sz" = "$sa" ] && echo "$sz" | grep -qx 'verificar: ok'
caso "plugin invalido que nao casa nao recusa o marcar" $?

echo "total=$total vermelhas:[${vermelhas%,}]"
[ -z "$vermelhas" ]
