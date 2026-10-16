#!/bin/bash
# Bateria do subcomando `pendencia` do scripts/estado.cjs (#470, tarefa 1 do plano
# docs/rainforest/planos/2026-10-15-deixado-vira-pendencia.md).
# Uso: bash scripts/testa-estado-pendencia.sh
#
# Cada grupo roda numa caixa nova (mktemp -d, fora do worktree), com a copia real de
# estado.cjs e um fluxo de verdade montado pelos proprios subcomandos (iniciar, marcar,
# exigir, destinar). Os casos conferem o JSON gravado em docs/rainforest/estado/ e o exit,
# nunca o texto do fonte. Recusa conferida pelo exit e pelo arquivo intacto (cksum).
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler). Exit 1 se falhar algum.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT

ok=0; falhou=0
SLUG=2026-10-15-pendencia-teste
E=""; ARQ=""

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

# J <expressao>: le o JSON da entrada padrao e imprime a expressao sobre `j`.
J() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=(new Function("j","return "+process.argv[1]))(j);console.log(typeof v==="string"?v:JSON.stringify(v===undefined?null:v));' "$1"
}
# LER <expressao>: a expressao sobre o arquivo de estado do slug da caixa.
LER() { J "$1" < "$ARQ"; }

# Caixa nova: pasta de dados do fluxo, copia real do estado.cjs, design e plano validos.
caixa_nova() {
  local CX; CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  local W; W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
  export HOME="$CX/casa" USERPROFILE="$CX/casa" CLAUDE_CONFIG_DIR="$CX/casa/.claude-personal"
  mkdir -p "$HOME" "$CX/scripts/lib" "$CX/hooks/lib" "$CX/docs/rainforest/design" \
    "$CX/docs/rainforest/planos" "$CX/docs/rainforest/varredura" "$CX/docs/rainforest/estado"
  cp "$SRC/scripts/estado.cjs" "$CX/scripts/"
  cp "$SRC/scripts/lib/camadas.cjs" "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$CX/scripts/lib/"
  local lib
  for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve teto-despachos; do
    cp "$SRC/hooks/lib/$lib.cjs" "$CX/hooks/lib/"
  done
  touch "$CX/FOCO.md"
  export RFM_ESTADO_ROOT="$W"
  cd "$CX" || exit 1
  E="node scripts/estado.cjs"
  ARQ="$CX/docs/rainforest/estado/$SLUG.json"
  echo "$SLUG" > "$CX/docs/rainforest/varredura/$SLUG.txt"
  cat > "$CX/docs/rainforest/design/$SLUG.md" << EOF
# Design

## Objetivo
Teste

## Decisões fechadas
- **D1 — teste**

## Avaliado e descartado
n/a

## Fora de escopo
n/a

## Em aberto
n/a

## Varredura
docs/rainforest/varredura/$SLUG.txt
EOF
  cat > "$CX/docs/rainforest/planos/$SLUG.md" << 'EOF'
# Plano de Teste

## Tarefas

### 1. Tarefa um
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste

### 2. Tarefa dois
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste

### 3. Tarefa tres
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste

### 4. Tarefa quatro
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste

### 5. Tarefa cinco
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste

### 6. Tarefa seis
atende: D1
mutacao:
  arquivo: scripts/estado.cjs
  de: n/a
  para: n/a
  motivo: teste
EOF
}

# Fluxo com design e plano fechados e executar parcial (5 de 6 tarefas).
fluxo_ate_executar_parcial() {
  $E iniciar --slug "$SLUG" >/dev/null
  $E marcar --slug "$SLUG" --estagio design --status aprovado --json "{\"arquivo\":\"docs/rainforest/design/$SLUG.md\"}" >/dev/null
  $E marcar --slug "$SLUG" --estagio plano --status ok --json "{\"arquivo\":\"docs/rainforest/planos/$SLUG.md\"}" >/dev/null
  $E exigir --slug "$SLUG" --estagio executar >/dev/null
  $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"tarefas_ok":5,"tarefas":6}' >/dev/null
}

JSON_OK='{"comando":"tp","saida":"tp-out","tarefas_ok":6,"tarefas":6,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"},{"tarefa":2,"resultado":"n/a","motivo":"teste"},{"tarefa":3,"resultado":"n/a","motivo":"teste"},{"tarefa":4,"resultado":"n/a","motivo":"teste"},{"tarefa":5,"resultado":"n/a","motivo":"teste"},{"tarefa":6,"resultado":"n/a","motivo":"teste"}]}'
RESTO_EXECUTAR='(({pendentes,...r})=>JSON.stringify(r))(j.executar)'

# ---------------------------------------------------------------- grupo A: executar parcial
caixa_nova
fluxo_ate_executar_parcial
RESTO_ANTES="$(LER "$RESTO_EXECUTAR")"

# (a) pendencia no estagio aberto: texto entra, status e demais campos ficam
esperado "(a) pendencia sai 0" 0 $E pendencia --slug "$SLUG" --texto "rodar a bateria X"
igual "(a) pendentes ganha o texto" '["rodar a bateria X"]' "$(LER 'JSON.stringify(j.executar.pendentes)')"
igual "(a) status segue parcial" "parcial" "$(LER 'j.executar.status')"
igual "(a) demais campos do executar iguais" "$RESTO_ANTES" "$(LER "$RESTO_EXECUTAR")"

# (b) repetir o mesmo texto nao duplica
esperado "texto repetido nao duplica: sai 0" 0 $E pendencia --slug "$SLUG" --texto "rodar a bateria X"
igual "texto repetido nao duplica: lista continua com um item" "1" "$(LER 'j.executar.pendentes.length')"


# (c) texto vazio ou ausente sai 1 e nao grava nada
antes_cksum="$(cksum < "$ARQ")"
esperado "(c) texto vazio sai 1" 1 $E pendencia --slug "$SLUG" --texto ""
esperado "(c) sem --texto sai 1" 1 $E pendencia --slug "$SLUG"
igual "(c) arquivo de estado intacto" "$antes_cksum" "$(cksum < "$ARQ")"

# (d) o ok do executar recusa pela pendencia; destino por pendencia libera so ela
esperado "(d) segunda pendencia sai 0" 0 $E pendencia --slug "$SLUG" --texto "outra"
saida_d="$($E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK" 2>&1)"; got_d=$?
igual "(d) ok recusado por pendencia sem destino (exit 2)" "2" "$got_d"
igual "(d) recusa cita a primeira pendencia" "1" "$(printf '%s\n' "$saida_d" | grep -c 'rodar a bateria X')"
igual "(d) recusa cita a segunda pendencia" "1" "$(printf '%s\n' "$saida_d" | grep -c 'outra')"
esperado "(d) destinar so a primeira sai 0" 0 $E destinar --slug "$SLUG" --estagio executar \
  --json '{"destinos":[{"pendente":"rodar a bateria X","destino":"descartada","motivo":"coberta pela bateria de estado"}]}'
saida_d2="$($E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK" 2>&1)"; got_d2=$?
igual "(d) com a segunda ainda sem destino, continua recusando (exit 2)" "2" "$got_d2"
igual "(d) recusa agora so cita a segunda" "0" "$(printf '%s\n' "$saida_d2" | grep -c 'rodar a bateria X')"
esperado "(d) destinar a segunda sai 0" 0 $E destinar --slug "$SLUG" --estagio executar \
  --json '{"destinos":[{"pendente":"outra","destino":"descartada","motivo":"nao se aplica"}]}'
esperado "(d) com as duas destinadas, o ok fecha (exit 0)" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK"
igual "(d) status do executar virou ok" "ok" "$(LER 'j.executar.status')"

# ---------------------------------------------------------------- grupo E: fluxo completo
caixa_nova
$E iniciar --slug "$SLUG" >/dev/null
node -e '
const fs = require("fs");
const p = process.argv[1];
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.design = { status: "aprovado" };
j.plano = { status: "ok" };
for (const e of ["executar", "revisar", "verificar", "fechar"]) j[e] = { status: "ok" };
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
' "$ARQ"
igual "(e) fluxo fechado: proximo diz completo" "completo" "$($E proximo --slug "$SLUG")"
antes_cksum="$(cksum < "$ARQ")"
esperado "(e) pendencia num fluxo completo sai 2" 2 $E pendencia --slug "$SLUG" --texto "algo"
igual "(e) fluxo completo: arquivo intacto" "$antes_cksum" "$(cksum < "$ARQ")"

# ---------------------------------------------------------------- grupo F: design recem-aberto
caixa_nova
$E iniciar --slug "$SLUG" >/dev/null
igual "(f) antes: proximo e design" "design" "$($E proximo --slug "$SLUG")"
esperado "(f) pendencia sai 0 com o fluxo recem-aberto" 0 $E pendencia --slug "$SLUG" --texto "decidir o nome do campo"
igual "(f) pendencia entra no bloco design" '["decidir o nome do campo"]' "$(LER 'JSON.stringify(j.design.pendentes)')"
igual "(f) status do design segue pendente" "pendente" "$(LER 'j.design.status')"
igual "(f) proximo segue design" "design" "$($E proximo --slug "$SLUG")"
esperado "(f) exigir design segue passando" 0 $E exigir --slug "$SLUG" --estagio design
esperado "(f) exigir plano segue recusando (design aberto)" 2 $E exigir --slug "$SLUG" --estagio plano
esperado "(f) aprovar design recusa pela pendencia sem destino" 2 \
  $E marcar --slug "$SLUG" --estagio design --status aprovado --json "{\"arquivo\":\"docs/rainforest/design/$SLUG.md\"}"
esperado "(f) destinar a pendencia do design sai 0" 0 $E destinar --slug "$SLUG" --estagio design \
  --json '{"destinos":[{"pendente":"decidir o nome do campo","destino":"descartada","motivo":"nome decidido no plano"}]}'
esperado "(f) aprovar design passa depois do destino" 0 \
  $E marcar --slug "$SLUG" --estagio design --status aprovado --json "{\"arquivo\":\"docs/rainforest/design/$SLUG.md\"}"
igual "(f) proximo avanca para plano" "plano" "$($E proximo --slug "$SLUG")"

# ---------------------------------------------------------------- grupo G: bloco ausente
caixa_nova
$E iniciar --slug "$SLUG" >/dev/null
node -e '
const fs = require("fs");
const p = process.argv[1];
const j = JSON.parse(fs.readFileSync(p, "utf8"));
delete j.design;
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
' "$ARQ"
esperado "(g) pendencia com bloco ausente sai 0" 0 $E pendencia --slug "$SLUG" --texto "texto sem bloco"
igual "(g) bloco nasce so com pendentes" '["pendentes"]' "$(LER 'JSON.stringify(Object.keys(j.design))')"
igual "(g) proximo segue design (sem status fechado)" "design" "$($E proximo --slug "$SLUG")"
esperado "(g) exigir plano segue recusando" 2 $E exigir --slug "$SLUG" --estagio plano

# ---------------------------------------------------------------- grupo H: texto que comeca com --
caixa_nova
fluxo_ate_executar_parcial
esperado "(h) texto que comeca com -- sai 0" 0 $E pendencia --slug "$SLUG" --texto "-- TODO: indexar"
igual "(h) o texto com -- entra como esta" '["-- TODO: indexar"]' "$(LER 'JSON.stringify(j.executar.pendentes)')"
esperado "(h) flag desconhecida de verdade segue recusada" 1 $E pendencia --slug "$SLUG" --texto "x" --inventada "y"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
