#!/bin/bash
# Bateria do scripts/territorio.cjs — descoberta do territorio e bloco do estagio.
# Uso: bash scripts/testa-territorio.sh
#
# Monta um CLAUDE_CONFIG_DIR temporario cujo installed_plugins.json aponta para uma
# copia do territorio sintetico (inventado; extensao .abc). Zero casos pulados.
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

monta_config() { # dir-config dir-plugin
  mkdir -p "$1/plugins"
  # No Git Bash o caminho de mktemp e estilo MSYS; o node (e o JSON) precisam do nativo.
  local p="$2"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -m "$2")"
  printf '{"version":2,"plugins":{"sintetico@teste":[{"scope":"user","installPath":"%s"}]}}' "$p" > "$1/plugins/installed_plugins.json"
}

PLUG="$TMP/plugin"; cp -r "$FIX/sintetico" "$PLUG"
CFG="$TMP/cfg"; monta_config "$CFG" "$PLUG"
T() { CLAUDE_CONFIG_DIR="$CFG" node "$SRC/scripts/territorio.cjs" "$@"; }

out=$(T estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'modo: soma' && echo "$out" | grep -qx 'agente: sintetico:revisor obrigatorio=false mcp=orquestrador'
caso "estagio revisar em repo-abc mostra modo soma e o agente" $?

out=$(T estagio revisar --raiz "$FIX/repo-vazio" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "sem territorio" ]
caso "repo-vazio imprime sem territorio e sai 0" $?

R3="$TMP/repo-apontado"; mkdir -p "$R3/.rainforest"; echo "x" > "$R3/LEIAME.txt"; echo "sintetico" > "$R3/.rainforest/territorio"
out=$(T estagio revisar --raiz "$R3" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'territorio: sintetico'
caso "apontamento do repo vence a deteccao" $?

R4="$TMP/repo-inexistente"; mkdir -p "$R4/.rainforest"; echo "fantasma" > "$R4/.rainforest/territorio"
out=$(T estagio revisar --raiz "$R4" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'fantasma'
caso "apontamento para nome inexistente sai 2 nomeando" $?

PLUG5="$TMP/plugin5"; cp -r "$FIX/sintetico" "$PLUG5"
sed -i 's/"versao_contrato": 0/"versao_contrato": 1/' "$PLUG5/territorio.json"
CFG5="$TMP/cfg5"; monta_config "$CFG5" "$PLUG5"
out=$(CLAUDE_CONFIG_DIR="$CFG5" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'sintetico'
caso "versao_contrato diferente de 0 sai 2" $?

out=$(T estagio brainstorm --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'mcp: mcp__srv__consulta quem=orquestrador obrigatorio=false'
caso "mcp sem campo quem sai como quem=orquestrador" $?

# --- variaveis (D6/D7): HOME/USERPROFILE temporario, config local em .rainforest/territorios
H1="$TMP/home1"; mkdir -p "$H1/.rainforest/territorios"
echo '{"lint":"/bin/true"}' > "$H1/.rainforest/territorios/sintetico.json"
H2="$TMP/home2"; mkdir -p "$H2"
TH() { local h="$1"; shift; command -v cygpath >/dev/null 2>&1 && h="$(cygpath -m "$h")"; HOME="$h" USERPROFILE="$h" CLAUDE_CONFIG_DIR="$CFG" node "$SRC/scripts/territorio.cjs" "$@"; }

out=$(TH "$H1" estagio verificar --raiz "$FIX/repo-abc" --arquivo x.abc 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'comando: lint /bin/true x.abc obrigatorio=true'
caso "variavel resolvida pelo config local" $?

out=$(TH "$H2" estagio verificar --raiz "$FIX/repo-abc" --arquivo x.abc 2>&1); rc=$?
[ $rc = 3 ] && echo "$out" | grep -q 'lint' && echo "$out" | grep -q 'sintetico.json'
caso "variavel sem valor no config local sai 3 nomeando a variavel" $?

# --- itens indisponiveis (D5): manifesto alterado numa copia, plugin "ausente" nao instalado
PLUG6="$TMP/plugin6"; cp -r "$FIX/sintetico" "$PLUG6"
sed -i 's/sintetico:revisor/ausente:revisor/' "$PLUG6/territorio.json"
CFG6="$TMP/cfg6"; monta_config "$CFG6" "$PLUG6"
out=$(CLAUDE_CONFIG_DIR="$CFG6" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'aviso: agente ausente:revisor indisponivel, papel padrao do rainforest' && ! echo "$out" | grep -q '^agente:'
caso "agente opcional de plugin ausente vira aviso e sai 0" $?

PLUG7="$TMP/plugin7"; cp -r "$FIX/sintetico" "$PLUG7"
sed -i 's/sintetico:revisor/outro:revisor/' "$PLUG7/territorio.json"
CFG7="$TMP/cfg7"; mkdir -p "$CFG7/plugins"
P7="$PLUG7"; command -v cygpath >/dev/null 2>&1 && P7="$(cygpath -m "$PLUG7")"
printf '{"version":2,"plugins":{"sintetico@teste":[{"scope":"user","installPath":"%s"}],"outro@teste":[{"scope":"user","installPath":"%s/nada"}]}}' "$P7" "$P7" > "$CFG7/plugins/installed_plugins.json"
# controle: outro instalado e habilitado -> a linha do agente sai normal
c7=$(CLAUDE_CONFIG_DIR="$CFG7" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1)
echo '{"enabledPlugins":{"outro@teste":false}}' > "$CFG7/settings.json"
out=$(CLAUDE_CONFIG_DIR="$CFG7" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
# territorio desabilitado: a descoberta o ignora
echo '{"enabledPlugins":{"sintetico@teste":false}}' > "$CFG7/settings.json"
outd=$(CLAUDE_CONFIG_DIR="$CFG7" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1)
echo "$c7" | grep -qx 'agente: outro:revisor obrigatorio=false mcp=orquestrador' && [ $rc = 0 ] && echo "$out" | grep -qx 'aviso: agente outro:revisor indisponivel, papel padrao do rainforest' && [ "$outd" = "sem territorio" ]
caso "plugin desabilitado em settings.json conta como ausente" $?

PLUG9="$TMP/plugin9"; cp -r "$FIX/sintetico" "$PLUG9"
sed -i 's/sintetico:executor/ausente:executor/' "$PLUG9/territorio.json"
CFG9="$TMP/cfg9"; monta_config "$CFG9" "$PLUG9"
out=$(CLAUDE_CONFIG_DIR="$CFG9" node "$SRC/scripts/territorio.cjs" estagio executar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'ausente:executor'
caso "agente obrigatorio de plugin ausente sai 2" $?

# --- plugin invalido so conta quando casa com o repositorio (A1)
# monta_dois: sintetico valido + zz (versao_contrato 1, deteccao .zzz); $1 = dir-config
PLUGZ="$TMP/pluginz"; mkdir -p "$PLUGZ"
printf '{"versao_contrato":1,"nome":"zz","deteccao":{"extensoes":[".zzz"],"arquivos":[]}}' > "$PLUGZ/territorio.json"
monta_dois() { # dir-config plugin-invalido
  mkdir -p "$1/plugins"
  local a="$PLUG" b="$2"
  command -v cygpath >/dev/null 2>&1 && { a="$(cygpath -m "$PLUG")"; b="$(cygpath -m "$2")"; }
  printf '{"version":2,"plugins":{"zz@teste":[{"scope":"user","installPath":"%s"}],"sintetico@teste":[{"scope":"user","installPath":"%s"}]}}' "$b" "$a" > "$1/plugins/installed_plugins.json"
}
CFGZ="$TMP/cfgz"; monta_dois "$CFGZ" "$PLUGZ"
TZ_() { CLAUDE_CONFIG_DIR="$CFGZ" node "$SRC/scripts/territorio.cjs" "$@"; }

so=$(TZ_ estagio revisar --raiz "$FIX/repo-vazio" 2>/dev/null); rc=$?
se=$(TZ_ estagio revisar --raiz "$FIX/repo-vazio" 2>&1 >/dev/null)
soj=$(TZ_ estagio revisar --raiz "$FIX/repo-vazio" --json 2>/dev/null); rcj=$?
sej=$(TZ_ estagio revisar --raiz "$FIX/repo-vazio" --json 2>&1 >/dev/null)
[ $rc = 0 ] && [ "$so" = "sem territorio" ] && echo "$se" | grep -q 'aviso: plugin zz ignorado' \
  && [ $rcj = 0 ] && [ "$soj" = '{"territorio":null,"itens":[]}' ] && echo "$sej" | grep -q 'aviso: plugin zz ignorado'
caso "plugin com versao_contrato 1 que nao casa nao bloqueia" $?

RZ="$TMP/repo-zzz"; mkdir -p "$RZ"; echo x > "$RZ/a.zzz"
out=$(TZ_ estagio revisar --raiz "$RZ" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'zz' && echo "$out" | grep -q 'versao_contrato 1'
caso "plugin com versao_contrato 1 que casa sai 2" $?

PLUGN="$TMP/pluginn"; mkdir -p "$PLUGN"; printf 'null' > "$PLUGN/territorio.json"
CFGN="$TMP/cfgn"; monta_dois "$CFGN" "$PLUGN"
out=$(CLAUDE_CONFIG_DIR="$CFGN" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-vazio" 2>&1); rc=$?
[ $rc = 0 ] && ! echo "$out" | grep -qE 'TypeError|^\s+at ' && echo "$out" | grep -qx 'sem territorio'
caso "territorio.json null nao derruba" $?

PLUGS="$TMP/plugins"; cp -r "$FIX/sintetico" "$PLUGS"
sed -i 's/sintetico:conhecimento/ausente:conhecimento/' "$PLUGS/territorio.json"
CFGS="$TMP/cfgs"; monta_config "$CFGS" "$PLUGS"
out=$(CLAUDE_CONFIG_DIR="$CFGS" node "$SRC/scripts/territorio.cjs" estagio brainstorm --raiz "$FIX/repo-abc" 2>&1); rc=$?
out6=$(CLAUDE_CONFIG_DIR="$CFG6" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1)
[ $rc = 0 ] && echo "$out" | grep -qx 'aviso: skill ausente:conhecimento indisponivel, papel padrao do rainforest' && echo "$out6" | grep -qx 'aviso: agente ausente:revisor indisponivel, papel padrao do rainforest'
caso "aviso de indisponivel nomeia o tipo" $?

H3="$TMP/home3"; mkdir -p "$H3/.rainforest/territorios"
echo '{"lint":"  "}' > "$H3/.rainforest/territorios/sintetico.json"
out=$(TH "$H3" estagio verificar --raiz "$FIX/repo-abc" --arquivo x.abc 2>&1); rc=$?
echo '{"lint":""}' > "$H3/.rainforest/territorios/sintetico.json"
out2=$(TH "$H3" estagio verificar --raiz "$FIX/repo-abc" --arquivo x.abc 2>&1); rc2=$?
[ $rc = 3 ] && [ $rc2 = 3 ] && echo "$out" | grep -q 'lint' && echo "$out2" | grep -q 'lint'
caso "variavel com valor vazio sai 3" $?

# --- forma errada do manifesto (versao_contrato 0 mas campos invalidos): nunca stack trace
PLUGF="$TMP/pluginf"; mkdir -p "$PLUGF"
printf '{"versao_contrato":0,"nome":"ff","deteccao":{"extensoes":[".fff"],"arquivos":[]},"estagios":{"revisar":{"agentes":"x"}}}' > "$PLUGF/territorio.json"
CFGF="$TMP/cfgf"; monta_dois "$CFGF" "$PLUGF"
RF="$TMP/repo-fff"; mkdir -p "$RF"; echo x > "$RF/a.fff"
out=$(CLAUDE_CONFIG_DIR="$CFGF" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$RF" 2>&1); rc=$?
[ $rc = 2 ] && ! echo "$out" | grep -qE 'TypeError|^\s+at ' && echo "$out" | grep -q 'agentes'
caso "manifesto com agentes nao-array que casa sai 2 sem stack trace" $?

so=$(CLAUDE_CONFIG_DIR="$CFGF" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-vazio" 2>/dev/null); rc=$?
se=$(CLAUDE_CONFIG_DIR="$CFGF" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-vazio" 2>&1 >/dev/null)
[ $rc = 0 ] && [ "$so" = "sem territorio" ] && echo "$se" | grep -q 'aviso: plugin zz ignorado' && echo "$se" | grep -q 'agentes' && ! echo "$se" | grep -qE 'TypeError|^\s+at '
caso "manifesto com forma errada que nao casa so avisa" $?

echo "total=$total vermelhas:[${vermelhas%,}]"
[ -z "$vermelhas" ]
