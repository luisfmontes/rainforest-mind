#!/bin/bash
# Bateria do status `flaky` do `executar` no scripts/estado.cjs (Tarefa 3 do
# plano flaky-teto, D6): o flake terminal fecha o `executar` com um status
# proprio, que NAO consome TETO_TENTATIVAS e so sai com o `liberar`.
# Uso: bash scripts/testa-estado-flaky-status.sh
#
# O que precisa provar:
#   1. com o terminal gravado, `marcar executar ok` recusa (exit 2) citando `flaky`,
#      e o mesmo `ok` sem terminal ainda fecha (controle);
#   2. `marcar executar flaky` fecha sem consumir tentativa e preserva `flakes`;
#   3. de `flaky` so se sai com `liberar`, e o `liberar` vale uma rodada;
#   4. `flaky` so existe para o `executar` e so fecha com o terminal gravado.
# Nenhum caso afirma sobre o texto do fonte: tudo roda o estado.cjs real numa caixa.
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
# campo do estado como JSON compacto: campo <slug> <expressao sobre e>
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json","utf8"));const v=(new Function("e","return "+process.argv[2]))(e);console.log(JSON.stringify(v===undefined?null:v));' "$1" "$2"
}

EVID='{"comando":"bash x.sh","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso"}]}'
FLAKE='[{"tarefa":2,"gate":"bash x.sh","voltas":[0,1]}]'
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
}
# fluxo em volta 1 com o flake da tarefa 2 gravado so na volta 0
chegar_na_volta_1() { abrir "$1"; $E registrar-flake --slug "$1" --tarefa 2 --gate "bash x.sh" >/dev/null; virar_volta "$1"; }

echo
echo "== 1. ok recusa com o terminal gravado; sem terminal ainda fecha =="
chegar_na_volta_1 s0
$E exigir --slug s0 --estagio executar >/dev/null 2>&1
saida=$($E registrar-flake --slug s0 --tarefa 3 --gate "bash outro.sh" 2>&1)
nao_contem "controle: flake so da volta 1 nao e terminal" "FLAKY TERMINAL" "$saida"
esperado "controle: marcar executar ok sem terminal fecha" 0 $E marcar --slug s0 --estagio executar --status ok --json "$EVID"

chegar_na_volta_1 s1
saida=$($E registrar-flake --slug s1 --tarefa 2 --gate "bash x.sh" 2>&1)
contem "terminal gravado na volta 1" "FLAKY TERMINAL" "$saida"
$E exigir --slug s1 --estagio executar >/dev/null 2>&1
saida=$($E marcar --slug s1 --estagio executar --status ok --json "$EVID" 2>&1); cod=$?
igual "marcar executar ok com terminal sai 2" "2" "$cod"
contem "a recusa cita flaky" "flaky" "$saida"
igual "o ok recusado nao gravou" '"parcial"' "$(campo s1 'e.executar.status')"

echo
echo "== 2. flaky nao consome tentativas =="
igual "verificar.tentativas antes" "1" "$(campo s1 'e.verificar.tentativas')"
esperado "marcar executar flaky sai 0" 0 $E marcar --slug s1 --estagio executar --status flaky
igual "executar.status e flaky" '"flaky"' "$(campo s1 'e.executar.status')"
igual "flaky nao grava executar.tentativas" "null" "$(campo s1 'e.executar.tentativas')"
igual "verificar.tentativas segue 1" "1" "$(campo s1 'e.verificar.tentativas')"
igual "executar.flakes preservado" "$FLAKE" "$(campo s1 'e.executar.flakes')"

echo
echo "== 3. de flaky so se sai com liberar =="
saida=$($E exigir --slug s1 --estagio executar 2>&1); cod=$?
igual "exigir executar em flaky sai 2" "2" "$cod"
contem "aponta o liberar" "liberar --slug s1 --estagio executar" "$saida"
esperado "marcar executar parcial em flaky sai 2" 2 $E marcar --slug s1 --estagio executar --status parcial
esperado "marcar executar ok em flaky sai 2" 2 $E marcar --slug s1 --estagio executar --status ok --json "$EVID"
igual "proximo imprime executar" "executar" "$($E proximo --slug s1 2>/dev/null | tail -1)"
esperado "exigir revisar em flaky sai 2" 2 $E exigir --slug s1 --estagio revisar
esperado "liberar executar sai 0" 0 $E liberar --slug s1 --estagio executar
esperado "depois do liberar, exigir executar sai 0" 0 $E exigir --slug s1 --estagio executar
esperado "depois do liberar, marcar executar parcial sai 0" 0 $E marcar --slug s1 --estagio executar --status parcial

echo
echo "== 4. o liberar vale uma rodada =="
saida=$($E registrar-flake --slug s1 --tarefa 2 --gate "bash x.sh" 2>&1)
contem "repetir o flake na volta 1 volta a dar FLAKY TERMINAL" "FLAKY TERMINAL" "$saida"
igual "o terminal apaga executar.liberado_em" "null" "$(campo s1 'e.executar.liberado_em')"
esperado "marcar executar ok sai 2 de novo" 2 $E marcar --slug s1 --estagio executar --status ok --json "$EVID"
esperado "marcar executar flaky fecha de novo" 0 $E marcar --slug s1 --estagio executar --status flaky

echo
echo "== 5. flaky so no executar, e so com o terminal =="
for est in revisar verificar fechar; do
  esperado "marcar $est flaky sai 1 (status invalido)" 1 $E marcar --slug s1 --estagio "$est" --status flaky
done
saida=$($E marcar --slug s1 --estagio executar --status xyz 2>&1)
contem "a mensagem de status invalido do executar lista flaky" "flaky" "$saida"
nao_contem "a do revisar nao lista flaky" "flaky" "$($E marcar --slug s1 --estagio revisar --status xyz 2>&1)"
abrir s3
esperado "flaky sem flake nenhum sai 2" 2 $E marcar --slug s3 --estagio executar --status flaky
chegar_na_volta_1 s4
$E registrar-flake --slug s4 --tarefa 2 --gate "bash y.sh" >/dev/null
esperado "flakes de gates diferentes em voltas seguidas: flaky sai 2" 2 $E marcar --slug s4 --estagio executar --status flaky
igual "o flaky recusado nao gravou" '"parcial"' "$(campo s4 'e.executar.status')"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = 0 ]
