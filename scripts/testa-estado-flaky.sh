#!/bin/bash
# Bateria do subcomando `registrar-flake` do scripts/estado.cjs (Tarefa 1 do
# plano flaky-teto, D4 e D6): grava o flake no estado do fluxo e acha o terminal.
# Uso: bash scripts/testa-estado-flaky.sh
#
# O que precisa provar:
#   1. que o flake fica gravado (`executar.flakes`) e que repetir na mesma volta nao duplica;
#   2. que so e TERMINAL o (tarefa + gate) gravado na volta atual E na anterior,
#      e que a volta so cresce (nenhum `ok` a apaga);
#   3. que entrada invalida sai 1 sem gravar, e que 6 chamadas juntas nao se atropelam.
# O "de:" da mutacao desta tarefa so e lido pela catraca; nenhum caso aqui afirma
# sobre o texto do fonte, tudo roda o estado.cjs real numa caixa.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
novo_sandbox() { local d; d=$(mktemp -d); SANDBOXES+=("$d"); printf -v "$1" '%s' "$d"; }
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT
novo_sandbox SBP0; SBP="$SBP0/caixa"

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
cd "$SBP" || exit 1
HOME_SBOX="$SBP/home"
mkdir -p "$HOME_SBOX"
export HOME="$HOME_SBOX" USERPROFILE="$HOME_SBOX" CLAUDE_CONFIG_DIR="$HOME_SBOX/.claude-personal"
export RFM_ESTADO_ROOT="$SBP"
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
E="node scripts/estado.cjs"

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
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
# campo do estado como JSON compacto: campo <slug> <expressao sobre e.executar>
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json","utf8"));const v=(new Function("e","return "+process.argv[2]))(e);console.log(JSON.stringify(v===undefined?null:v));' "$1" "$2"
}

EVID='{"comando":"bash x.sh","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso"}]}'
# abre um fluxo com executar armado
abrir() {
  $E iniciar --slug "$1" >/dev/null
  $E marcar --slug "$1" --estagio design --status aprovado >/dev/null
  $E marcar --slug "$1" --estagio plano --status ok >/dev/null
  $E exigir --slug "$1" --estagio executar >/dev/null
}
# fecha a volta: executar ok, revisar ok, verificar reprovado (reabre o executar, volta +1)
virar_volta() {
  $E exigir --slug "$1" --estagio executar >/dev/null 2>&1
  $E marcar --slug "$1" --estagio executar --status ok --json "$EVID" >/dev/null 2>&1
  $E marcar --slug "$1" --estagio revisar --status ok >/dev/null 2>&1
  $E exigir --slug "$1" --estagio verificar >/dev/null 2>&1
  $E marcar --slug "$1" --estagio verificar --status reprovado >/dev/null 2>&1
  $E liberar --slug "$1" --estagio verificar >/dev/null 2>&1
}

echo
echo "== 1. grava o flake e nao duplica =="
abrir f1
saida=$($E registrar-flake --slug f1 --tarefa 2 --gate "bash x.sh" 2>&1); cod=$?
igual "registrar-flake sai 0" "0" "$cod"
contem "imprime a linha de registro" "flake registrado: tarefa 2, volta 0" "$saida"
igual "executar.flakes gravado" '[{"tarefa":2,"gate":"bash x.sh","voltas":[0]}]' "$(campo f1 'e.executar.flakes')"
saida=$($E registrar-flake --slug f1 --tarefa 2 --gate "bash x.sh" 2>&1)
igual "repetir na mesma volta nao duplica" '[{"tarefa":2,"gate":"bash x.sh","voltas":[0]}]' "$(campo f1 'e.executar.flakes')"
echo
echo "== 2. flake de uma volta so nao e terminal =="
nao_contem "flake de uma volta so nao e terminal" "FLAKY TERMINAL" "$saida"
esperado "marcar executar ok com flake de uma volta so ainda fecha" 0 $E marcar --slug f1 --estagio executar --status ok --json "$EVID"
igual "o ok nao apaga as flakes" '[{"tarefa":2,"gate":"bash x.sh","voltas":[0]}]' "$(campo f1 'e.executar.flakes')"

echo
echo "== 3. duas voltas seguidas: terminal =="
$E marcar --slug f1 --estagio revisar --status ok >/dev/null 2>&1
$E exigir --slug f1 --estagio verificar >/dev/null 2>&1
$E marcar --slug f1 --estagio verificar --status reprovado >/dev/null 2>&1
igual "verificar reprovado soma 1 em executar.reaberturas" "1" "$(campo f1 'e.executar.reaberturas')"
saida=$($E registrar-flake --slug f1 --tarefa 2 --gate "bash x.sh" 2>&1); cod=$?
igual "registrar na volta 1 sai 0" "0" "$cod"
contem "imprime a volta 1" "flake registrado: tarefa 2, volta 1" "$saida"
igual "voltas viram [0,1]" '[{"tarefa":2,"gate":"bash x.sh","voltas":[0,1]}]' "$(campo f1 'e.executar.flakes')"
contem "linha FLAKY TERMINAL" "FLAKY TERMINAL" "$saida"
contem "nomeia a tarefa" "tarefa 2" "$saida"
contem "nomeia o gate" "bash x.sh" "$saida"
contem "nomeia o comando de fechamento" "marcar --slug f1 --estagio executar --status flaky" "$saida"

echo
echo "== 4. o que NAO e terminal =="
abrir f2
$E registrar-flake --slug f2 --tarefa 2 --gate "bash x.sh" >/dev/null
virar_volta f2
saida=$($E registrar-flake --slug f2 --tarefa 2 --gate "bash y.sh" 2>&1)
nao_contem "gate diferente na volta 1 nao e terminal" "FLAKY TERMINAL" "$saida"
saida=$($E registrar-flake --slug f2 --tarefa 3 --gate "bash x.sh" 2>&1)
nao_contem "tarefa diferente na volta 1 nao e terminal" "FLAKY TERMINAL" "$saida"
igual "tres entradas distintas gravadas" "3" "$(campo f2 'e.executar.flakes.length')"

abrir f3
$E registrar-flake --slug f3 --tarefa 2 --gate "bash x.sh" >/dev/null
virar_volta f3
virar_volta f3
igual "volta 2 alcancada" "2" "$(campo f3 'e.executar.reaberturas')"
saida=$($E registrar-flake --slug f3 --tarefa 2 --gate "bash x.sh" 2>&1)
contem "volta 2 registrada" "volta 2" "$saida"
nao_contem "voltas 0 e 2 nao sao terminal" "FLAKY TERMINAL" "$saida"

abrir f4
$E registrar-flake --slug f4 --tarefa 2 --gate "bash x.sh" >/dev/null
virar_volta f4
virar_volta f4
virar_volta f4
igual "volta 3 alcancada com ok de revisar e de executar no meio" "3" "$(campo f4 'e.executar.reaberturas')"
saida=$($E registrar-flake --slug f4 --tarefa 2 --gate "bash x.sh" 2>&1)
contem "volta 3 registrada" "volta 3" "$saida"
nao_contem "voltas 0 e 3 nao sao terminal (a volta so cresce)" "FLAKY TERMINAL" "$saida"
igual "voltas 0 e 3 gravadas" '[0,3]' "$(campo f4 'e.executar.flakes[0].voltas')"

echo
echo "== 5. entrada invalida sai 1 =="
abrir f5
esperado "sem --gate" 1 $E registrar-flake --slug f5 --tarefa 2
esperado "sem --tarefa" 1 $E registrar-flake --slug f5 --gate "bash x.sh"
for t in abc 0 -1 1.5; do
  esperado "--tarefa $t" 1 $E registrar-flake --slug f5 --tarefa "$t" --gate "bash x.sh"
done
esperado "slug inexistente" 1 $E registrar-flake --slug nao-existe --tarefa 2 --gate "bash x.sh"
esperado "flag desconhecida" 1 $E registrar-flake --slug f5 --tarefa 2 --gate "bash x.sh" --coisa 1
igual "entrada invalida nao gravou nada" "null" "$(campo f5 'e.executar.flakes')"

echo
echo "== 6. seis chamadas juntas =="
abrir f6
for t in 1 2 3 4 5 6; do
  $E registrar-flake --slug f6 --tarefa "$t" --gate "bash x.sh" >/dev/null 2>&1 &
done
wait
igual "6 entradas gravadas" "6" "$(campo f6 'e.executar.flakes.length')"
igual "tarefas 1 a 6, sem perda" "[1,2,3,4,5,6]" "$(campo f6 'e.executar.flakes.map((f)=>f.tarefa).sort()')"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = 0 ]
