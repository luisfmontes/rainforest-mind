#!/bin/bash
# Bateria do `liberar-teto` do scripts/estado.cjs (Tarefa 4 do plano flaky-teto,
# D13): +10 despachos para o fluxo, com o motivo por escrito. O subcomando so
# registra a liberacao em `teto_despachos.liberacoes[]`; quem soma o +10 e o hook.
# Uso: bash scripts/testa-estado-teto.sh
#
# O que precisa provar:
#   1. a primeira liberacao grava {motivo, em} e nao mexe em mais nada;
#   2. a segunda ACUMULA, na ordem (nao substitui a primeira);
#   3. motivo vazio ou so de espacos recusa (exit 2) sem tocar o arquivo;
#   4. entrada invalida (sem --motivo, slug inexistente, flag de estagio) sai 1;
#   5. o `liberar` de sempre segue como era.
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
# campo do estado como JSON compacto: campo <slug> <expressao sobre e>
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json","utf8"));const v=(new Function("e","return "+process.argv[2]))(e);console.log(JSON.stringify(v===undefined?null:v));' "$1" "$2"
}
# o estado sem o bloco teto_despachos, para provar que "todo o resto fica igual"
sem_teto() { campo "$1" '(()=>{const c={...e};delete c.teto_despachos;return c})()'; }
# o arquivo inteiro, byte a byte (hash)
hash_arq() { node -e 'console.log(require("crypto").createHash("sha256").update(require("fs").readFileSync("docs/rainforest/estado/"+process.argv[1]+".json")).digest("hex"))' "$1"; }
HOJE=$(node -e 'const d=new Date(),p=n=>String(n).padStart(2,"0");console.log(d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()))')

echo
echo "== 1. a primeira liberacao =="
$E iniciar --slug s1 >/dev/null
RESTO0=$(sem_teto s1)
igual "antes, o estado nao tem teto_despachos" "null" "$(campo s1 'e.teto_despachos')"
esperado "liberar-teto sai 0" 0 $E liberar-teto --slug s1 --motivo "Luis: fluxo grande, segue"
igual "uma liberacao com motivo e data" "[{\"motivo\":\"Luis: fluxo grande, segue\",\"em\":\"$HOJE\"}]" "$(campo s1 'e.teto_despachos.liberacoes')"
igual "todo o resto do JSON fica igual" "$RESTO0" "$(sem_teto s1)"

echo
echo "== 2. segunda liberacao acumula =="
RESTO1=$(sem_teto s1)
esperado "segunda liberar-teto sai 0" 0 $E liberar-teto --slug s1 --motivo "Luis: mais um tanto"
igual "dois itens, na ordem" "[{\"motivo\":\"Luis: fluxo grande, segue\",\"em\":\"$HOJE\"},{\"motivo\":\"Luis: mais um tanto\",\"em\":\"$HOJE\"}]" "$(campo s1 'e.teto_despachos.liberacoes')"
igual "o resto continua igual" "$RESTO1" "$(sem_teto s1)"
esperado "terceira liberar-teto sai 0" 0 $E liberar-teto --slug s1 --motivo "terceira"
igual "tres itens" "3" "$(campo s1 'e.teto_despachos.liberacoes.length')"
igual "o primeiro continua o primeiro" '"Luis: fluxo grande, segue"' "$(campo s1 'e.teto_despachos.liberacoes[0].motivo')"

echo
echo "== 3. motivo vazio recusa e nao toca o arquivo =="
ANTES=$(hash_arq s1)
esperado "motivo vazio sai 2" 2 $E liberar-teto --slug s1 --motivo ""
igual "arquivo igual byte a byte apos motivo vazio" "$ANTES" "$(hash_arq s1)"
esperado "motivo de espacos sai 2" 2 $E liberar-teto --slug s1 --motivo "   "
igual "arquivo igual byte a byte apos motivo de espacos" "$ANTES" "$(hash_arq s1)"

echo
echo "== 4. entrada invalida sai 1 =="
esperado "sem --motivo sai 1" 1 $E liberar-teto --slug s1
igual "arquivo igual apos a falta de --motivo" "$ANTES" "$(hash_arq s1)"
esperado "slug inexistente sai 1" 1 $E liberar-teto --slug nao-existe --motivo "x"
esperado "--estagio executar sai 1 (o teto nao e estagio)" 1 $E liberar-teto --slug s1 --estagio executar --motivo "x"
igual "arquivo igual apos a flag desconhecida" "$ANTES" "$(hash_arq s1)"

echo
echo "== 5. o liberar de sempre segue como era =="
$E iniciar --slug s2 >/dev/null
esperado "liberar revisar sem --rodada-extra continua saindo 2" 2 $E liberar --slug s2 --estagio revisar
esperado "liberar executar continua saindo 0" 0 $E liberar --slug s2 --estagio executar
igual "liberar executar grava liberado_em" "\"$HOJE\"" "$(campo s2 'e.executar.liberado_em')"
esperado "liberar-teto convive com o liberado_em" 0 $E liberar-teto --slug s2 --motivo "depois do liberar"
igual "o liberado_em do executar segue la" "\"$HOJE\"" "$(campo s2 'e.executar.liberado_em')"
igual "a liberacao do teto entrou" "1" "$(campo s2 'e.teto_despachos.liberacoes.length')"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = 0 ]
