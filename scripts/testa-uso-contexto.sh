#!/bin/bash
# Bateria do aviso de contexto alto (design 2026-11-09-aviso-contexto-alto).
# Uso: bash scripts/testa-uso-contexto.sh
#
# Tudo roda o `estado.cjs exigir` real numa caixa, com transcript no formato que
# o Claude Code grava. Nenhum caso afirma sobre o texto do fonte.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAIZ_TMP=$(mktemp -d)
trap 'rm -rf "$RAIZ_TMP" 2>/dev/null || true' EXIT
SBP="$RAIZ_TMP/caixa"
mkdir -p "$SBP/scripts/lib" "$SBP/hooks/lib" "$SBP/.rainforest" "$RAIZ_TMP/t"
cp "$SRC/scripts/estado.cjs" "$SRC/scripts/conferir-fluxo.cjs" "$SRC/scripts/conferir-mutacao.cjs" "$SBP/scripts/"
cp "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$SRC/scripts/lib/uso-contexto.cjs" "$SBP/scripts/lib/"
for lib in raiz config trava-jsonl pastas-docs resolver-executavel caminho-real contar-ocorrencias caminho-leve slug-branch; do
  cp "$SRC/hooks/lib/$lib.cjs" "$SBP/hooks/lib/"
done
# A caixa vira raiz de dados: sem marcador, resolverRaiz cairia no repo de verdade.
touch "$SBP/FOCO.md"
cd "$SBP" || exit 1
HOME_CAIXA="$SBP/home"
CFG="$HOME_CAIXA/.claude"
TRANSCRITOS="$CFG/projects/C--algum-projeto"
mkdir -p "$TRANSCRITOS"
export HOME="$HOME_CAIXA" USERPROFILE="$HOME_CAIXA" CLAUDE_CONFIG_DIR="$CFG" RFM_ESTADO_ROOT="$SBP"
unset CLAUDE_PROJECT_DIR

T="$RAIZ_TMP/t"
ok=0; falhou=0
passa() { ok=$((ok+1)); echo "  ok   $1"; }
falha() { falhou=$((falhou+1)); echo "  FALHA $1"; [ -z "${2:-}" ] || echo "$2" | sed 's/^/         /'; }

# Mensagem no formato real; quase tudo em cache_read, como numa sessão de verdade.
msg() {
  printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":%d,"output_tokens":9}}}\n' "$(( $1 - 3 ))"
}
# Resposta que consultou o advisor, no formato real: o topo soma as duas chamadas
# `message` (cache_read e cache_creation em dobro), e cada iteração traz a sua.
# msg_advisor <primeira> <ultima>: tokens de prompt de cada iteração `message`.
msg_advisor() {
  printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":4,"cache_creation_input_tokens":4,"cache_read_input_tokens":%d,"output_tokens":9,"iterations":[{"input_tokens":2,"cache_creation_input_tokens":2,"cache_read_input_tokens":%d,"output_tokens":5,"type":"message"},{"input_tokens":114616,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":6908,"type":"advisor_message","model":"claude-fable-5-1"},{"input_tokens":2,"cache_creation_input_tokens":2,"cache_read_input_tokens":%d,"output_tokens":4,"type":"message"}]}}}\n' \
    "$(( $1 + $2 - 8 ))" "$(( $1 - 4 ))" "$(( $2 - 4 ))"
}
usuario() { printf '{"type":"user","message":{"role":"user","content":"oi"}}\n'; }

# rodar <id> [estagio]: roda o exigir e guarda stdout, stderr e exit.
rodar() {
  CLAUDE_CODE_SESSION_ID="$1" node scripts/estado.cjs exigir --slug caixa --estagio "${2:-limpar}" > "$T/out" 2> "$T/err"
  RC=$?
}
sem_aviso() { # nome
  if [ "$RC" = 0 ] && ! grep -q "contexto em" "$T/err" && [ ! -s "$T/err" ]; then passa "$1"
  else falha "$1" "exit=$RC stderr=$(cat "$T/err")"; fi
}
com_aviso() { # nome, trecho
  if [ "$RC" = 0 ] && grep -qF "$2" "$T/err"; then passa "$1"
  else falha "$1" "exit=$RC stderr=$(cat "$T/err")"; fi
}
cfg() { printf '%s\n' "$1" > "$SBP/.rainforest/config.json"; }
sem_cfg() { rm -f "$SBP/.rainforest/config.json"; }

node scripts/estado.cjs iniciar --slug caixa --titulo "caixa" > /dev/null 2>&1 || { echo "FALHA iniciar"; exit 1; }

echo "== medida (D1, D2) =="
{ usuario; msg 200000; usuario; msg 320000; } > "$TRANSCRITOS/alto.jsonl"
env -u CLAUDE_CODE_SESSION_ID node scripts/estado.cjs exigir --slug caixa --estagio limpar > "$T/out-base" 2> "$T/err-base"
rodar alto
com_aviso "uso acima do limiar avisa com tokens, limiar e estagio" "aviso: contexto em 320 mil tokens (limiar 310 mil). Siga com 'limpar' normalmente: o autocompact compacta a sessão sozinho quando precisar, e o estado do fluxo está gravado e sobrevive à compactação. Não pare o fluxo, não peça /compact ao usuário nem proponha sessão nova por causa deste aviso."
if cmp -s "$T/out" "$T/out-base"; then passa "stdout igual ao de sessao sem transcript"; else falha "stdout igual ao de sessao sem transcript" "$(cat "$T/out")"; fi

{ msg 320000; msg 309999; } > "$TRANSCRITOS/abaixo.jsonl"
rodar abaixo; sem_aviso "abaixo do limiar nao avisa, e vale a ultima mensagem"
msg 310000 > "$TRANSCRITOS/exato.jsonl"
rodar exato; com_aviso "exatamente no limiar avisa" "contexto em 310 mil"
{ msg 440000; usuario; msg 40000; } > "$TRANSCRITOS/compactou.jsonl"
rodar compactou; sem_aviso "depois de compactar o aviso some"

# Advisor: o topo diria 620 mil; a última iteração `message` diz 320 mil.
msg_advisor 300000 320000 > "$TRANSCRITOS/advisor.jsonl"
rodar advisor; com_aviso "com advisor vale a ultima iteracao message, nao a soma do topo" "contexto em 320 mil tokens"
# Topo acima do limiar (300 + 200 = 500 mil), a última iteração abaixo dele.
msg_advisor 300000 200000 > "$TRANSCRITOS/advisor-baixo.jsonl"
rodar advisor-baixo; sem_aviso "com advisor a soma do topo nao dispara sozinha"
# Iteração de outro tipo no fim da lista não é o contexto da janela.
printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":114618,"cache_creation_input_tokens":2,"cache_read_input_tokens":319996,"output_tokens":9,"iterations":[{"input_tokens":2,"cache_creation_input_tokens":2,"cache_read_input_tokens":319996,"output_tokens":5,"type":"message"},{"input_tokens":114616,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":6908,"type":"advisor_message"}]}}}\n' > "$TRANSCRITOS/advisor-no-fim.jsonl"
rodar advisor-no-fim; com_aviso "iteracao advisor_message no fim da lista e ignorada" "contexto em 320 mil tokens"

{ msg 320000; printf '{"type":"assistant","message":{"usage":{"input_tok'; } > "$TRANSCRITOS/truncado.jsonl"
rodar truncado; com_aviso "linha final truncada vale a anterior" "contexto em 320 mil"
{ msg 320000; printf '{"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n'; } > "$TRANSCRITOS/sintetico.jsonl"
rodar sintetico; com_aviso "mensagem sintetica zerada vale a anterior" "contexto em 320 mil"
{ msg 320000; printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":5,"cache_read_input_tokens":10}}}\n'; } > "$TRANSCRITOS/lateral.jsonl"
rodar lateral; com_aviso "mensagem de subagente no fim vale a anterior" "contexto em 320 mil"
{ node -e 'process.stdout.write("x".repeat(1200000)+"\n")'; msg 320000; } > "$TRANSCRITOS/grande.jsonl"
rodar grande; com_aviso "transcript maior que a cauda" "contexto em 320 mil"
# Só a cauda de 1 MB é lida: a mensagem alta antes de 1,2 MB de outra coisa não conta.
{ msg 440000; node -e 'process.stdout.write("x".repeat(1200000)+"\n")'; } > "$TRANSCRITOS/fora-da-cauda.jsonl"
rodar fora-da-cauda; sem_aviso "mensagem antes da cauda de 1 MB nao conta"
# Em 60 transcripts reais, o último assistant útil ficou até 211 KB antes do fim.
{ msg 320000; node -e 'process.stdout.write("x".repeat(200000)+"\n")'; } > "$TRANSCRITOS/dentro-da-cauda.jsonl"
rodar dentro-da-cauda; com_aviso "mensagem 200 KB antes do fim ainda esta na cauda" "contexto em 320 mil"

echo "== sem medida (D2, D5) =="
env -u CLAUDE_CODE_SESSION_ID node scripts/estado.cjs exigir --slug caixa --estagio limpar > "$T/out" 2> "$T/err"; RC=$?
sem_aviso "sessao sem a variavel fica calada"
rodar nao-existe; sem_aviso "sessao sem transcript fica calada"
msg 900000 > "$CFG/fora.jsonl"
rodar "../../fora"; sem_aviso "id com ../ nao vira caminho"
rm -f "$CFG/fora.jsonl"
printf 'lixo\n{nem json\n' > "$TRANSCRITOS/lixo.jsonl"
rodar lixo; sem_aviso "transcript ilegivel fica calado"
CLAUDE_CONFIG_DIR="$RAIZ_TMP/sem-pasta" CLAUDE_CODE_SESSION_ID=alto node scripts/estado.cjs exigir --slug caixa --estagio limpar > "$T/out" 2> "$T/err"; RC=$?
sem_aviso "config dir sem projects fica calado"
env -u CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID=alto node scripts/estado.cjs exigir --slug caixa --estagio limpar > "$T/out" 2> "$T/err"; RC=$?
com_aviso "sem CLAUDE_CONFIG_DIR acha o transcript em ~/.claude" "contexto em 320 mil"

echo "== limiar (D3) =="
msg 120000 > "$TRANSCRITOS/medio.jsonl"
rodar medio; sem_aviso "padrao 310 mil nao avisa em 120 mil"
cfg '{"contexto-alto-tokens":100000}'
rodar medio; com_aviso "limiar do projeto vale no exigir" "contexto em 120 mil tokens (limiar 100 mil)"
msg 900000 > "$TRANSCRITOS/muito.jsonl"
cfg '{"contexto-alto-tokens":0}'
rodar muito; sem_aviso "zero desliga mesmo em 900 mil"
for invalido in '"muito"' '-5' '1.5'; do
  cfg "{\"contexto-alto-tokens\":$invalido}"
  rodar alto; com_aviso "valor invalido $invalido cai no padrao" "limiar 310 mil"
done
sem_cfg

echo "== exigir (D4, D5) =="
rodar alto verificar
if [ "$RC" = 2 ] && grep -qF "Siga com 'verificar'" "$T/err" && grep -q "RECUSADO\|pre-requisito\|pré-requisito\|recus" "$T/err"; then passa "exigir recusado segue saindo 2 e avisa"
else falha "exigir recusado segue saindo 2 e avisa" "exit=$RC stderr=$(cat "$T/err")"; fi
mv scripts/lib/uso-contexto.cjs "$T/guardada.cjs"
rodar alto; sem_aviso "sem a lib o exigir sai 0 sem aviso e sem erro"
mv "$T/guardada.cjs" scripts/lib/uso-contexto.cjs

echo "ok: $ok   falhou: $falhou"
[ "$falhou" = 0 ]
