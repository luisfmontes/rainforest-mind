#!/bin/bash
# Bateria do lib/config.cjs e do scripts/setup.cjs — o que esta ligado, e onde.
#
# O que esta bateria precisa provar, nesta ordem de importancia:
#   1. que o toggle DESLIGA DE VERDADE o gate. Toggle que nada le e promessa sem
#      mecanismo — e o defeito que este repo passou o dia 11/08 inteiro catando;
#   2. que a precedencia e a prometida: emergencia > projeto > usuario > padrao.
#      Precedencia errada e pior que ausente: o usuario desliga num lugar e continua
#      barrado, sem saber por que;
#   3. que config ilegivel deixa a trava LIGADA. Falhar para o lado de desligar
#      apaga a protecao em silencio, que e a familia de defeito da injecao muda;
#   4. que o setup nao sobrescreve dado que ja existe.
#
# A ultima secao e MUTACAO: inverte o lado seguro do `ligado()` e exige que o
# item 3 pare de pegar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SB)"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }
esperado() { local nome="$1" esp="$2"; shift 2; local s; s=$("$@" 2>&1); local g=$?
  if [ "$g" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $g)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $g"; echo "$s" | sed 's/^/         /'; fi; }

# Projeto git de mentira, so para o gate ter onde morder.
mkdir -p "$SBP/proj"
( cd "$SBP/proj" && git init -q )
PROJ="$SB/proj"
PAYLOAD="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add -A\"},\"cwd\":\"$PROJ\"}"
gate() { echo "$PAYLOAD" | node "$SRC/hooks/gate-staging-total.cjs" >/dev/null 2>&1; }

echo
echo "== 1. o toggle DESLIGA o gate de verdade =="
esperado "sem config, o gate barra"                 2 gate
mkdir -p "$SBP/proj/.rainforest"
echo '{"gate-staging": false}' > "$SBP/proj/.rainforest/config.json"
esperado "desligado no projeto, o gate passa"       0 gate
echo '{"gate-staging": true}' > "$SBP/proj/.rainforest/config.json"
esperado "religado no projeto, o gate volta a barrar" 2 gate

echo
echo "== 2. precedencia: emergencia > projeto > usuario > padrao =="
cfg() { # config_projeto_json, config_usuario_json, [env_extra]
  mkdir -p "$SBP/lar/.rainforest" "$SBP/proj/.rainforest"
  printf '%s' "$1" > "$SBP/proj/.rainforest/config.json"
  printf '%s' "$2" > "$SBP/lar/.rainforest/config.json"
  RFM_ROOT="$SB/lar/.rainforest" node -e "
    const { resolverConfig } = require('$SRC_WIN/hooks/lib/config.cjs');
    const r = resolverConfig({ projeto: '$PROJ' });
    process.stdout.write(r.valores['gate-staging'] + ' ' + r.origem['gate-staging']);
  " 2>&1
}
igual "projeto vence usuario"        "false projeto" "$(cfg '{"gate-staging":false}' '{"gate-staging":true}')"
igual "usuario vale sem projeto"     "false usuario" "$(cfg '{}' '{"gate-staging":false}')"
igual "sem nenhum, cai no padrao"    "true padrao"   "$(cfg '{}' '{}')"
EMERG="$(RAINFOREST_GATE_OFF=1 RFM_ROOT="$SB/lar/.rainforest" node -e "
  const { resolverConfig } = require('$SRC_WIN/hooks/lib/config.cjs');
  const r = resolverConfig({ projeto: '$PROJ' });
  process.stdout.write(r.valores['gate-staging'] + ' ' + r.origem['gate-staging']);
" 2>&1)"
igual "emergencia vence ate o projeto ligado" "false RAINFOREST_GATE_OFF" "$EMERG"
# O fluxo nao e gate: a saida de emergencia dos gates nao pode desliga-la junto.
FLUXO="$(RAINFOREST_GATE_OFF=1 node -e "
  const { resolverConfig } = require('$SRC_WIN/hooks/lib/config.cjs');
  process.stdout.write(String(resolverConfig({ projeto: '$PROJ' }).valores.fluxo));
" 2>&1)"
igual "emergencia NAO desliga o fluxo" "true" "$FLUXO"

echo
echo "== 3. config ilegivel deixa a trava LIGADA =="
printf '{nao e json' > "$SBP/proj/.rainforest/config.json"
esperado "json quebrado no projeto: o gate segue barrando" 2 gate
igual "ligado() devolve true com json quebrado" "true" "$(node -e "
  process.stdout.write(String(require('$SRC_WIN/hooks/lib/config.cjs').ligado('gate-staging', { projeto: '$PROJ' })));
" 2>&1)"
rm -f "$SBP/proj/.rainforest/config.json"

echo
echo "== 4. o setup nao sobrescreve o que ja existe =="
LAR="$SBP/novo-lar"
mkdir -p "$LAR"
( cd "$SBP" && HOME="$LAR" USERPROFILE="$(cygpath -m "$LAR" 2>/dev/null || printf '%s' "$LAR")" \
  env -u RFM_ROOT node "$SRC/scripts/setup.cjs" --criar >/dev/null 2>&1 )
igual "criou o FOCO.md"     "sim" "$([ -f "$LAR/.rainforest/FOCO.md" ] && echo sim || echo nao)"
igual "criou o ideias.jsonl" "sim" "$([ -f "$LAR/.rainforest/ideias.jsonl" ] && echo sim || echo nao)"
echo '{"id":"nao-me-apague"}' > "$LAR/.rainforest/ideias.jsonl"
echo "FOCO DO USUARIO" > "$LAR/.rainforest/FOCO.md"
( cd "$SBP" && HOME="$LAR" USERPROFILE="$(cygpath -m "$LAR" 2>/dev/null || printf '%s' "$LAR")" \
  env -u RFM_ROOT node "$SRC/scripts/setup.cjs" --criar >/dev/null 2>&1 )
igual "rodar de novo preserva as ideias" "nao-me-apague" "$(node -e "
  process.stdout.write(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8').trim()).id)
" "$LAR/.rainforest/ideias.jsonl" 2>&1)"
igual "rodar de novo preserva o foco"    "FOCO DO USUARIO" "$(head -1 "$LAR/.rainforest/FOCO.md")"

echo
echo "== 5. MUTACAO — quem segura a trava com config quebrada e o PADRAO =="
# A primeira versao deste bloco mutava o `catch` do `ligado()` e nao teve efeito:
# com JSON quebrado o resolverConfig NAO lanca — o `lerJson` engole o erro, a
# chave fica ausente e cai no padrao. Ou seja, o lado seguro nao mora no catch,
# mora no `padrao: true` da tabela CHAVES. Mutacao que erra o alvo passa verde
# sem provar nada, e foi o que aconteceu ate esta linha ser reescrita.
cp "$SRC/hooks/lib/config.cjs" "$SBP/config-mutante.cjs"
node - "$SBP/config-mutante.cjs" <<'JS'
const fs = require("fs");
const alvo = process.argv[2];
const antes = fs.readFileSync(alvo, "utf8");
const de = "  'gate-staging': {\n    padrao: true,";
if (!antes.includes(de)) throw new Error("ancora do padrao de gate-staging sumiu");
fs.writeFileSync(alvo, antes.replace(de, "  'gate-staging': {\n    padrao: false,"), "utf8");
JS
printf '{nao e json' > "$SBP/proj/.rainforest/config.json"
MUT="$(node -e "
  process.stdout.write(String(require('$SB/config-mutante.cjs').ligado('gate-staging', { projeto: '$PROJ' })));
" 2>&1)"
if [ "$MUT" = "false" ]; then
  ok=$((ok+1)); echo "  ok   com o padrao invertido, config quebrada DESLIGA a trava (o padrao e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e o padrao que segura (veio '$MUT')"
fi
rm -f "$SBP/proj/.rainforest/config.json"

echo
echo "== 6. P1 — a escotilha nao e revelada a quem esta sendo bloqueado =="
# Relatorio 2026-08-11-escotilha-do-gate-usada-para-contornar: um implementador
# bloqueado leu o nome do arquivo de escape NA PROPRIA mensagem de bloqueio,
# criou `.rainforest-gate-off` na raiz do checkout principal do usuario e seguiu
# trabalhando. Reportou DONE. A escotilha e da JANELA PRINCIPAL; a mensagem era
# lida pelo subagente. E em 2026-08-11 o /setup acrescentou uma TERCEIRA rota, a
# mais amigavel de todas — por isso a mensagem ao subagente nao nomeia nenhuma.
msg() { echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add -A\"},\"cwd\":\"$PROJ\"$1}" \
  | node "$SRC/hooks/gate-staging-total.cjs" 2>&1; }
# Sem barra invertida aqui: o `echo` da funcao ja escapa as aspas dele. Com ela o
# JSON saia invalido, o gate saia 0 sem mensagem, e as tres checagens de "NAO ve"
# passavam num texto VAZIO — falso-positivo que so apareceu porque as de "ve"
# falharam ao lado.
SUB="$(msg ',"agent_id":"a1"')"
PRI="$(msg '')"
temf()     { if echo "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_temf() { if echo "$2" | grep -qF "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }

nao_temf "subagente NAO ve o arquivo de escape"    "$SUB" ".rainforest-gate-off"
nao_temf "subagente NAO ve a variavel de ambiente" "$SUB" "RAINFOREST_GATE_OFF"
nao_temf "subagente NAO ve o comando do setup"     "$SUB" "setup.cjs --desligar"
temf     "subagente e mandado PARAR e reportar"    "$SUB" "PARE e reporte"
temf     "e proibido de criar o contorno sozinho"  "$SUB" "a decisao nao e sua"
# A janela principal continua sabendo como seguir: tirar a saida dela transformaria
# uma escolha legitima em beco sem saida.
temf     "janela principal ve as tres saidas"      "$PRI" "tres saidas"
temf     "janela principal ve a preferida"         "$PRI" "setup.cjs --desligar"

echo
echo "== 7. as chaves ponte-*: quais agentes recebem as regras =="
# Elas entraram porque "quais agentes eu uso nesta maquina" e configuracao, e
# configuracao mora no /setup. Padrao FALSO nos tres: gerar arquivo em repositorio
# de terceiro nunca e padrao.
for chave in ponte-claude ponte-codex ponte-gemini; do
  if node -e "
const {CHAVES}=require('$SRC_WIN/hooks/lib/config.cjs');
const d=CHAVES['$chave'];
if (!d) { console.error('chave ausente'); process.exit(1); }
if (d.padrao !== false) { console.error('padrao nao e falso: '+d.padrao); process.exit(1); }
" 2>/dev/null; then ok=$((ok+1)); echo "  ok   $chave existe e nasce DESLIGADA"
  else falhou=$((falhou+1)); echo "  FALHA $chave ausente ou ligada por padrao"; fi
done

echo
echo "== 8. o nome antigo continua sendo LIDO (esteira -> fluxo) =="
# Renomear chave de config e mudanca silenciosa por natureza: o config do usuario
# em disco continua dizendo `"esteira": false`, o codigo passa a perguntar por
# `fluxo`, ninguem casa, e o padrao `true` RELIGA o que ele tinha desligado. Quem
# desligou descobre pelo comportamento. Por isso o alias, e por isso esta secao.
flx() { # config_projeto_json, config_usuario_json
  mkdir -p "$SBP/lar/.rainforest" "$SBP/proj/.rainforest"
  printf '%s' "$1" > "$SBP/proj/.rainforest/config.json"
  printf '%s' "$2" > "$SBP/lar/.rainforest/config.json"
  RFM_ROOT="$SB/lar/.rainforest" node -e "
    const { resolverConfig } = require('$SRC_WIN/hooks/lib/config.cjs');
    const r = resolverConfig({ projeto: '$PROJ' });
    process.stdout.write(r.valores.fluxo + ' ' + r.origem.fluxo);
  " 2>&1
}
igual "so o nome antigo: o valor dele vale"   "false usuario (esteira)" "$(flx '{}' '{"esteira":false}')"
igual "so o nome antigo, no projeto"          "false projeto (esteira)" "$(flx '{"esteira":false}' '{}')"
igual "nome novo vence o antigo no MESMO arquivo" "true usuario" "$(flx '{}' '{"fluxo":true,"esteira":false}')"
igual "nome novo no projeto vence antigo do usuario" "true projeto" "$(flx '{"fluxo":true}' '{"esteira":false}')"
igual "nenhum dos dois: padrao"               "true padrao"  "$(flx '{}' '{}')"

# MUTACAO — tirar o alias tem de fazer o primeiro caso RELIGAR sozinho. Sem isto,
# a secao inteira passaria verde num codigo que nunca leu o nome antigo.
cp "$SRC/hooks/lib/config.cjs" "$SBP/config-sem-alias.cjs"
node - "$SBP/config-sem-alias.cjs" <<'JS'
const fs = require("fs");
const alvo = process.argv[2];
const antes = fs.readFileSync(alvo, "utf8");
const de = "  fluxo: ['esteira'],";
if (!antes.includes(de)) throw new Error("ancora do alias sumiu");
fs.writeFileSync(alvo, antes.replace(de, ""), "utf8");
JS
mkdir -p "$SBP/lar/.rainforest" "$SBP/proj/.rainforest"
printf '{}' > "$SBP/proj/.rainforest/config.json"
printf '{"esteira":false}' > "$SBP/lar/.rainforest/config.json"
SEM="$(RFM_ROOT="$SB/lar/.rainforest" node -e "
  const { resolverConfig } = require('$SB/config-sem-alias.cjs');
  process.stdout.write(String(resolverConfig({ projeto: '$PROJ' }).valores.fluxo));
" 2>&1)"
if [ "$SEM" = "true" ]; then
  ok=$((ok+1)); echo "  ok   sem o alias, quem tinha 'esteira:false' seria RELIGADO (o alias e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e o alias que segura (veio '$SEM')"
fi
rm -f "$SBP/proj/.rainforest/config.json" "$SBP/lar/.rainforest/config.json"

echo
echo "== hooks.json: o hook de ferramentas so dispara em Bash =="
# O bloco PreToolUse dos gates NAO tem matcher, e dispara em toda chamada de
# ferramenta — sao 3 processos do SO por tool call. O hook de ferramentas serve
# so ao `Bash` (D9 da #76), entao entra em bloco proprio com matcher: sem isso
# ele encareceria TODO tool call para servir um caso so.
#
# Caminho por argv, nunca interpolado no fonte do node: caminho do Windows tem
# `\` e `:` e vira sintaxe quebrada dentro de string de script.
hjson() { node -e "$1" "$SRC/hooks/hooks.json" 2>&1; }

MATCHER="$(hjson '
  const h = require(process.argv[1]).hooks;
  const blocos = (h.PreToolUse || []).filter(b => b.hooks.some(x => x.command.includes("ferramentas-consulta.cjs")));
  process.stdout.write(blocos.length === 1 ? String(blocos[0].matcher) : "blocos:" + blocos.length);
')"
if [ "$MATCHER" = "Bash" ]; then
  ok=$((ok+1)); echo "  ok   ferramentas-consulta esta em bloco proprio com matcher Bash"
else
  falhou=$((falhou+1)); echo "  FALHA matcher do ferramentas-consulta veio '$MATCHER', esperava 'Bash'"
fi

OUTROS="$(hjson '
  const h = require(process.argv[1]).hooks;
  const semMatcher = (h.PreToolUse || []).filter(b => b.matcher === undefined);
  process.stdout.write(String(semMatcher.reduce((n,b) => n + b.hooks.length, 0)));
')"
if [ "$OUTROS" = "4" ]; then
  ok=$((ok+1)); echo "  ok   os quatro gates sem matcher seguem intactos"
else
  falhou=$((falhou+1)); echo "  FALHA gates sem matcher: $OUTROS, esperava 4"
fi

# `PostToolUse` e PROIBIDO neste repo: 15.331 eventos em oito dias, um processo
# do SO cada (design de 2026-08-17, D12). A #76 quase reintroduziu o evento.
POST="$(hjson 'process.stdout.write(String("PostToolUse" in require(process.argv[1]).hooks));')"
if [ "$POST" = "false" ]; then
  ok=$((ok+1)); echo "  ok   PostToolUse continua fora do hooks.json"
else
  falhou=$((falhou+1)); echo "  FALHA PostToolUse no hooks.json (veio '$POST')"
fi

echo
echo "== 9. PODA — escrita de metricas, nasce ligada =="
poda() { # config_projeto_json, config_usuario_json
  mkdir -p "$SBP/lar/.rainforest" "$SBP/proj/.rainforest"
  printf '%s' "$1" > "$SBP/proj/.rainforest/config.json"
  printf '%s' "$2" > "$SBP/lar/.rainforest/config.json"
  RFM_ROOT="$SB/lar/.rainforest" node -e "
    const { resolverConfig } = require('$SRC_WIN/hooks/lib/config.cjs');
    const r = resolverConfig({ projeto: '$PROJ' });
    process.stdout.write(r.valores.poda + ' ' + r.origem.poda);
  " 2>&1
}
igual "sem config, poda e true (padrao)"              "true padrao"   "$(poda '{}' '{}')"
igual "projeto sobrescreve para false"                "false projeto" "$(poda '{"poda":false}' '{}')"
igual "usuario vale sem projeto"                      "true usuario"  "$(poda '{}' '{"poda":true}')"
igual "projeto vence usuario"                         "false projeto" "$(poda '{"poda":false}' '{"poda":true}')"
rm -f "$SBP/proj/.rainforest/config.json" "$SBP/lar/.rainforest/config.json"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
