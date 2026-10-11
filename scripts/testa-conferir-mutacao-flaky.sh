#!/bin/bash
# Bateria da nova tentativa e da confirmacao do vermelho em scripts/conferir-mutacao.cjs
# (Tarefa 5 do plano flaky-teto, D4, D7 e D8).
# Uso: bash scripts/testa-conferir-mutacao-flaky.sh
#
# A bateria de caixa tem exit VARIAVEL por chamada: um arquivo-contador (FORA da
# copia que a catraca faz da raiz, senao cada rodada recomecaria do zero) e uma
# sequencia de exits, um por chamada. E a forma real da bateria instavel.
#
# O que precisa provar:
#   1. baseline e pos-mutacao decidem so depois da nova tentativa, e o contador
#      conta as rodadas EXATAS (1 0 / 1 1 -> 4; 1 1 -> 2; ...);
#   2. 0 so sai com vermelho nas DUAS rodadas pos-mutacao; sequencia mista sai 2
#      e imprime FLAKE;
#   3. exits 1, 3, 5, 6 e 69 nunca repetem;
#   4. --slug/--tarefa gravam o flake no estado; falhar ao gravar so avisa.
# Nenhum caso afirma sobre o texto do fonte; o "de:" da mutacao so e lido pela catraca.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

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
cp "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SBP/scripts/lib/"
cp "$SRC/scripts/lib/extrair-veredito.cjs" "$SBP/scripts/lib/"
for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve; do
  cp "$SRC/hooks/lib/$lib.cjs" "$SBP/hooks/lib/"
done
# A caixa vira raiz de dados: sem marcador, resolverRaiz cairia no repo de verdade.
touch "$SBP/FOCO.md"

# Fonte a mutar (uma ocorrencia do trecho) e outra com duas ocorrencias.
printf 'const alvo = 1;\n' > "$SBP/fonte.cjs"
printf 'const alvo = 1;\nconst alvo = 2;\n' > "$SBP/dupla.cjs"

# A bateria de exit variavel. SEQ = "1 0" quer dizer: 1a chamada exit 1, 2a exit 0.
# Chamada alem da sequencia repete o ultimo valor. `c` = colapso (exit 1, placar 0/0).
# Placar impresso no formato da catraca: falha tem falhou 1, verde tem falhou 0.
cat > "$SBP/bat.sh" <<'FIM'
n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$CNT"
arr=($SEQ); i=$((n-1)); [ "$i" -ge "${#arr[@]}" ] && i=$((${#arr[@]}-1))
v="${arr[$i]}"
if [ "$v" = "c" ]; then echo "ok: 0   falhou: 0"; exit 1; fi
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
DE='alvo = 1'; PARA='alvo = 0'

# roda a catraca com a sequencia SEQ; zera o contador antes. Guarda RC, OUT, ERR.
catraca() { # SEQ, arquivo, demais flags...
  export SEQ="$1"; local arq="$2"; shift 2
  echo 0 > "$CNT"; rm -f "$CNT"
  OUT=$(node scripts/conferir-mutacao.cjs --raiz "$SBP" --arquivo "$arq" --de "$DE" --para "$PARA" \
        --bateria 'bash bat.sh' "$@" 2>"$SBP0/err.txt")
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
# exit esperado + contador esperado da ultima execucao de `catraca`
confere() { # nome, exit, contador
  igual "$1: exit" "$2" "$RC"
  igual "$1: contador" "$3" "$(contador)"
}

echo
echo "== 1. baseline: so o vermelho numerico ganha nova tentativa =="
catraca "1 0 1 1" fonte.cjs
confere "baseline 1 0, pos 1 1 aprova" 0 4
contem "baseline 1 0 imprime FLAKE: baseline" "FLAKE: baseline" "$OUT"
nao_contem "baseline 1 0 e pos vermelha nao imprime FLAKE: pos-mutacao" "FLAKE: pos-mutacao" "$OUT"

catraca "1 1" fonte.cjs
confere "baseline 1 1 recusa" 4 2
contem "baseline 1 1 diz NAO-VERDE" "baseline NAO-VERDE" "$ERR"

echo
echo "== 2. pos-mutacao verde: nova tentativa, e sai 2 em qualquer resultado =="
catraca "0 0 0" fonte.cjs
confere "pos 0 0 recusa" 2 3
nao_contem "pos 0 0 nao e flake" "FLAKE" "$OUT"

catraca "0 0 1" fonte.cjs
confere "pos 0 1 recusa (verde e depois vermelho)" 2 3
contem "pos 0 1 imprime FLAKE: pos-mutacao" "FLAKE: pos-mutacao" "$OUT"

echo
echo "== 3. pos-mutacao vermelha: so aprova confirmada =="
catraca "0 1 1" fonte.cjs
confere "pos 1 1 aprova" 0 3
nao_contem "pos 1 1 nao e flake" "FLAKE" "$OUT"

catraca "0 1 0" fonte.cjs
confere "vermelho e depois verde nao confirma" 2 3
contem "vermelho e depois verde imprime FLAKE: pos-mutacao" "FLAKE: pos-mutacao" "$OUT"
contem "vermelho e depois verde diz que nao se repetiu" "não se repetiu" "$ERR"

echo
echo "== 4. o que nunca repete (1, 3, 5, 6, 69) =="
DE='nao existe no fonte' catraca "0 1 1" fonte.cjs
confere "--de que nao casa sai 3" 3 1

DE='const alvo' PARA='const outro' catraca "0 1 1" dupla.cjs
confere "--de que casa duas vezes sai 4" 4 1

catraca "0 c" fonte.cjs
confere "bateria que colapsa sai 6 sem terceira rodada" 6 2

# a confirmacao do vermelho passa pela mesma checagem de colapso da primeira rodada
catraca "0 1 c" fonte.cjs
confere "confirmacao que colapsa sai 6, nao 0" 6 3
contem "confirmacao que colapsa recusa com a mensagem de colapso" "a bateria colapsou" "$ERR"

# comando inexistente: o shell resolve e devolve 127 -> 69 (ambiente), sem nova tentativa
export SEQ="0"; rm -f "$CNT"
OUT=$(node scripts/conferir-mutacao.cjs --raiz "$SBP" --arquivo fonte.cjs --de 'alvo = 1' --para 'alvo = 0' \
      --bateria 'comando-que-nao-existe-flaky-xyz' 2>"$SBP0/err.txt"); RC=$?
igual "comando de bateria inexistente sai 69" 69 "$RC"

catraca "0 1 1" fonte.cjs --slug so-slug
igual "--slug sem --tarefa sai 1" 1 "$RC"
igual "--slug sem --tarefa nao roda bateria" 0 "$(contador)"
catraca "0 1 1" fonte.cjs --tarefa 3
igual "--tarefa sem --slug sai 1" 1 "$RC"
igual "--tarefa sem --slug nao roda bateria" 0 "$(contador)"

echo
echo "== 5. --slug e --tarefa gravam o flake; falha de gravacao so avisa =="
E="node scripts/estado.cjs"
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json","utf8"));const v=(new Function("e","return "+process.argv[2]))(e);console.log(JSON.stringify(v===undefined?null:v));' "$1" "$2"
}
$E iniciar --slug 2026-01-01-caixa >/dev/null
$E marcar --slug 2026-01-01-caixa --estagio design --status aprovado >/dev/null
$E marcar --slug 2026-01-01-caixa --estagio plano --status ok >/dev/null
$E exigir --slug 2026-01-01-caixa --estagio executar >/dev/null

catraca "0 0 1" fonte.cjs
igual "sem --slug o estado nao e tocado" "null" "$(campo 2026-01-01-caixa e.executar.flakes)"

catraca "0 0 1" fonte.cjs --slug 2026-01-01-caixa --tarefa 3
confere "com --slug, pos 0 1 segue saindo 2" 2 3
igual "pos 0 1 grava o flake da tarefa 3" '[{"tarefa":3,"gate":"catraca: bash bat.sh","voltas":[0]}]' "$(campo 2026-01-01-caixa e.executar.flakes)"
contem "o stdout repassa o que o registrar-flake imprimiu" "flake registrado: tarefa 3, volta 0" "$OUT"

catraca "1 0 1 1" fonte.cjs --slug 2026-01-01-caixa --tarefa 4
confere "com --slug, baseline 1 0 e pos 1 1 segue saindo 0" 0 4
igual "baseline flake grava a tarefa 4" '[3,4]' "$(campo 2026-01-01-caixa 'e.executar.flakes.map(f=>f.tarefa)')"

catraca "0 0 1" fonte.cjs --slug 2026-01-01-nao-existe --tarefa 3
confere "slug inexistente mantem o exit" 2 3
contem "slug inexistente avisa no stderr" "aviso: nao consegui registrar o flake" "$ERR"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ]
