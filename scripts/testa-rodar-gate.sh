#!/bin/bash
# Bateria de scripts/rodar-gate.cjs (Tarefa 6 do plano flaky-teto, D4 e D8).
# Uso: bash scripts/testa-rodar-gate.sh
#
# A bateria de caixa tem exit VARIAVEL por chamada: um arquivo-contador e uma
# sequencia de exits, um por chamada (a forma real da bateria instavel).
#
# O que precisa provar:
#   1. verde de primeira nao repete; vermelho repete UMA vez, nunca duas;
#   2. verde so na nova tentativa sai 0 e imprime FLAKE; vermelho nas duas sai 2;
#   3. estouro de tempo, uso errado e comando inexistente nunca repetem;
#   4. --slug/--tarefa gravam o flake (e o terminal), sem mudar o exit.
# Nenhum caso afirma sobre o texto do fonte.
#
# Placar no formato `ok: N   falhou: M`.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
novo_sandbox() { local d; d=$(mktemp -d); SANDBOXES+=("$d"); printf -v "$1" '%s' "$d"; }
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT
novo_sandbox SBP0; SBP="$SBP0/caixa"
novo_sandbox CNTDIR

mkdir -p "$SBP/scripts/lib" "$SBP/hooks/lib"
cp "$SRC/scripts/estado.cjs" "$SBP/scripts/"
cp "$SRC/scripts/conferir-fluxo.cjs" "$SBP/scripts/"
cp "$SRC/scripts/conferir-mutacao.cjs" "$SBP/scripts/"
cp "$SRC/scripts/rodar-gate.cjs" "$SBP/scripts/"
cp "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SBP/scripts/lib/"
cp "$SRC/scripts/lib/extrair-veredito.cjs" "$SBP/scripts/lib/"
for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve; do
  cp "$SRC/hooks/lib/$lib.cjs" "$SBP/hooks/lib/"
done
# A caixa vira raiz de dados: sem marcador, resolverRaiz cairia no repo de verdade.
touch "$SBP/FOCO.md"

# SEQ = "1 0": 1a chamada exit 1, 2a exit 0. Alem da sequencia repete o ultimo.
# `s` = dorme 5 s (para o teste de estouro de tempo).
cat > "$SBP/bat.sh" <<'FIM'
n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$CNT"
arr=($SEQ); i=$((n-1)); [ "$i" -ge "${#arr[@]}" ] && i=$((${#arr[@]}-1))
v="${arr[$i]}"
if [ "$v" = "s" ]; then sleep 5; exit 0; fi
if [ "$v" = "0" ]; then echo "ok: 5   falhou: 0"; else echo "ok: 4   falhou: 1"; fi
exit "$v"
FIM

cd "$SBP" || exit 1
HOME_SBOX="$SBP/home"
mkdir -p "$HOME_SBOX"
export HOME="$HOME_SBOX" USERPROFILE="$HOME_SBOX" CLAUDE_CONFIG_DIR="$HOME_SBOX/.claude-personal"
export RFM_ESTADO_ROOT="$SBP"
export CNT="$CNTDIR/contador"
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
OUT=""; ERR=""; RC=0

# roda o gate com a sequencia SEQ; zera o contador antes. Guarda RC, OUT, ERR.
gate() { # SEQ, demais flags...
  export SEQ="$1"; shift
  rm -f "$CNT"
  OUT=$(node scripts/rodar-gate.cjs --comando 'bash bat.sh' --raiz "$SBP" "$@" 2>"$SBP0/err.txt")
  RC=$?
  ERR=$(cat "$SBP0/err.txt")
}
contador() { cat "$CNT" 2>/dev/null || echo 0; }

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
contem() { # nome, trecho, texto
  case "$3" in
    *"$2"*) ok=$((ok+1)); echo "  ok   $1" ;;
    *) falhou=$((falhou+1)); echo "  FALHA $1: nao achei '$2' em: $3" ;;
  esac
}
nao_contem() { # nome, trecho, texto
  case "$3" in
    *"$2"*) falhou=$((falhou+1)); echo "  FALHA $1: achei '$2' em: $3" ;;
    *) ok=$((ok+1)); echo "  ok   $1" ;;
  esac
}
confere() { # nome, exit, contador
  igual "$1: exit" "$2" "$RC"
  igual "$1: contador" "$3" "$(contador)"
}

echo
echo "== 1. verde de primeira nao repete =="
gate "0"
confere "sequencia 0" 0 1
nao_contem "sequencia 0 nao imprime FLAKE" "FLAKE" "$OUT"

echo
echo "== 2. vermelho na primeira rodada repete uma vez =="
gate "1 0"
confere "sequencia 1 0 passa na nova tentativa" 0 2
contem "sequencia 1 0 imprime FLAKE: passou so na nova tentativa" "FLAKE: passou so na nova tentativa" "$OUT"

gate "1 1 0"
confere "sequencia 1 1 e vermelha, e nunca ha terceira rodada" 2 2
contem "stderr traz o exit da 1a rodada" "1a rodada saiu 1" "$ERR"
contem "stderr traz o exit da nova tentativa" "nova tentativa saiu 1" "$ERR"
nao_contem "vermelho nas duas nao e flake" "FLAKE" "$OUT"

gate "3 5"
confere "exits diferentes nas duas rodadas" 2 2
contem "stderr traz os dois exits" "1a rodada saiu 3 e a nova tentativa saiu 5" "$ERR"

echo
echo "== 3. o que nunca repete =="
gate "s" --timeout 300
confere "estouro de tempo sai 1 sem repetir" 1 1

export SEQ="0"; rm -f "$CNT"
OUT=$(node scripts/rodar-gate.cjs --comando 'comando-que-nao-existe-gate-xyz' --raiz "$SBP" 2>"$SBP0/err.txt"); RC=$?
igual "comando inexistente sai 69" 69 "$RC"

export SEQ="0"; rm -f "$CNT"
OUT=$(node scripts/rodar-gate.cjs --raiz "$SBP" 2>"$SBP0/err.txt"); RC=$?
igual "sem --comando sai 1" 1 "$RC"

gate "0" --slug so-slug
confere "--slug sem --tarefa sai 1 e nao roda" 1 0
gate "0" --tarefa 2
confere "--tarefa sem --slug sai 1 e nao roda" 1 0

echo
echo "== 4. --slug e --tarefa gravam o flake; o terminal e repassado =="
E="node scripts/estado.cjs"
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json","utf8"));const v=(new Function("e","return "+process.argv[2]))(e);console.log(JSON.stringify(v===undefined?null:v));' "$1" "$2"
}
EVID='{"comando":"bash x.sh","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso"}]}'
S=2026-01-01-gate
$E iniciar --slug $S >/dev/null
$E marcar --slug $S --estagio design --status aprovado >/dev/null
$E marcar --slug $S --estagio plano --status ok >/dev/null
$E exigir --slug $S --estagio executar >/dev/null

gate "1 0"
igual "sem --slug o estado nao e tocado" "null" "$(campo $S e.executar.flakes)"

gate "1 0" --slug $S --tarefa 2
confere "com --slug, sequencia 1 0 segue saindo 0" 0 2
igual "grava o flake da tarefa 2" '[{"tarefa":2,"gate":"criterio: bash bat.sh","voltas":[0]}]' "$(campo $S e.executar.flakes)"
contem "o stdout repassa o que o registrar-flake imprimiu" "flake registrado: tarefa 2, volta 0" "$OUT"
nao_contem "flake de uma volta so nao e terminal" "FLAKY TERMINAL" "$OUT"

gate "1 1" --slug $S --tarefa 2
confere "vermelho nas duas segue saindo 2" 2 2
igual "vermelho de verdade nao grava flake" '[0]' "$(campo $S 'e.executar.flakes[0].voltas')"

# fecha a volta: executar ok, revisar ok, verificar reprovado (reabre o executar)
$E marcar --slug $S --estagio executar --status ok --json "$EVID" >/dev/null 2>&1
$E marcar --slug $S --estagio revisar --status ok >/dev/null 2>&1
$E exigir --slug $S --estagio verificar >/dev/null 2>&1
$E marcar --slug $S --estagio verificar --status reprovado >/dev/null 2>&1

gate "1 0" --slug $S --tarefa 2
confere "na volta seguinte, sequencia 1 0 segue saindo 0" 0 2
igual "voltas viram [0,1]" '[{"tarefa":2,"gate":"criterio: bash bat.sh","voltas":[0,1]}]' "$(campo $S e.executar.flakes)"
contem "o stdout repassa FLAKY TERMINAL" "FLAKY TERMINAL" "$OUT"
$E marcar --slug $S --estagio executar --status ok --json "$EVID" >/dev/null 2>&1
igual "marcar executar ok passa a sair 2" "2" "$?"

gate "1 0" --slug 2026-01-01-nao-existe --tarefa 2
confere "slug inexistente mantem o exit" 0 2
contem "slug inexistente avisa no stderr" "aviso: nao consegui registrar o flake" "$ERR"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ]
