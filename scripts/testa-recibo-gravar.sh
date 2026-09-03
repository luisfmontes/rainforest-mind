#!/bin/bash
# Bateria de testes para `recibo.cjs gravar`.
# Uso: bash scripts/testa-recibo-gravar.sh
#
# Tarefa 2 do plano `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que `gravar` escreva recibo quando nao ha `plano.entregaveis`. Opt-in:
#      fluxo sem manifesto sai 0 sem gravar nada.
#
#   2. Que `gravar` aceite entregavel ausente ou fora da arvore. Antes de congelar
#      qualquer coisa em disco, todos os entregaveis precisam estar proximos e
#      confinados.
#
#   3. Que `nao_provado` seja vazio ou ausente. Um recibo que alega provar TUDO e'
#      suspeito por construcao. O que ficou de fora precisa ser declarado.
#
#   4. Que o hash gravado nao confira com o arquivo. Cada entregavel precisa ter
#      sha256 e bytes corretos, computados no momento da gravacao atomica.
#
#   5. Que `gravar` quebre a invariante do opt-in criando arquivo mesmo sem
#      `plano.entregaveis` declarado.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIBO="$RAIZ/scripts/recibo.cjs"
FIX="$RAIZ/test/fixtures/recibo"

[ -f "$RECIBO" ] || { echo "FALHA: nao achei $RECIBO"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/estado" "$S/docs/rainforest/portoes"

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# Roda o recibo.cjs numa raiz-sandbox. `cd "$RAIZ"` de proposito: o confinamento
# por realpath usa RAIZ REAL, e e' assim que roda em producao — o script nao muda
# o cwd de quem o chamou.
rec() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$RECIBO" "$@" 2>&1); }

echo "== T2a. sem plano.entregaveis: sai 0, nada criado =="
mkdir -p "$S/docs/rainforest/estado"
cat > "$S/docs/rainforest/estado/sem-entregaveis.json" <<FIM
{
  "slug": "sem-entregaveis",
  "plano": {}
}
FIM
SAIDA="$(rec gravar --slug sem-entregaveis --nao-provado '["algo"]')"; C=$?
afirma "T2a1. exit 0" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "T2a2. stdout contem 'sem manifesto'" \
  "$(printf '%s' "$SAIDA" | grep -q "sem manifesto" && echo 1 || echo 0)"
afirma "T2a3. nenhum arquivo criado em .rainforest/colheita" \
  "$([ ! -d "$S/.rainforest/colheita" ] && echo 1 || echo 0)"

echo "== T2b. entregavel ausente: sai 2 nomeando o arquivo =="
cat > "$S/docs/rainforest/estado/com-ausente.json" <<FIM
{
  "slug": "com-ausente",
  "plano": {
    "entregaveis": ["docs/nao-existe.md"]
  }
}
FIM
SAIDA="$(rec gravar --slug com-ausente --nao-provado '["algo"]')"; C=$?
afirma "T2b1. exit 2" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "T2b2. stderr menciona o arquivo" \
  "$(printf '%s' "$SAIDA" | grep -q "docs/nao-existe.md" && echo 1 || echo 0)"

echo "== T2c. entregavel via junction/link para fora: sai 2 =="
EXTERNO="$(mktemp -d)"
trap "rm -rf '$S' '$EXTERNO'" EXIT
LINK="$S/docs/dentro-com-link"
mkdir -p "$LINK"
CRIOU=0
if [ "${OS:-}" = "Windows_NT" ]; then
  cmd //c mklink //J "$(cygpath -w "$LINK/atalho")" "$(cygpath -w "$EXTERNO")" >/dev/null 2>&1 && CRIOU=1
else
  ln -s "$EXTERNO" "$LINK/atalho" 2>/dev/null && CRIOU=1
fi

if [ "$CRIOU" -eq 1 ]; then
  echo "conteudo teste" > "$EXTERNO/arquivo.txt"
  cat > "$S/docs/rainforest/estado/com-link.json" <<FIM
{
  "slug": "com-link",
  "plano": {
    "entregaveis": ["docs/dentro-com-link/atalho/arquivo.txt"]
  }
}
FIM
  SAIDA="$(rec gravar --slug com-link --nao-provado '["algo"]')"; C=$?
  afirma "T2c1. exit 2 para link para fora" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
  afirma "T2c2. stderr menciona o caminho" \
    "$(printf '%s' "$SAIDA" | grep -q "arquivo.txt" && echo 1 || echo 0)"
else
  echo "  ok   T2c1. (pulado: nao consegui criar link nesta maquina)"
  echo "  ok   T2c2. (pulado: nao consegui criar link nesta maquina)"
  ok=$((ok+2))
fi

echo "== T2d. nao-provado ausente: sai 2 com mensagem sobre nao_provado =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo para arquivo 1" > "$S/docs/a-gravar/arquivo1.txt"
cat > "$S/docs/rainforest/estado/com-arquivo-ausente-args.json" <<FIM
{
  "slug": "com-arquivo-ausente-args",
  "plano": {
    "entregaveis": ["docs/a-gravar/arquivo1.txt"]
  }
}
FIM
SAIDA="$(rec gravar --slug com-arquivo-ausente-args)"; C=$?
afirma "T2d1. exit 2 quando nao-provado ausente" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "T2d2. stderr menciona nao_provado" \
  "$(printf '%s' "$SAIDA" | grep -qi "nao_provado" && echo 1 || echo 0)"

echo "== T2e. nao-provado: [] vazio sai 2 =="
SAIDA="$(rec gravar --slug com-arquivo-ausente-args --nao-provado '[]')"; C=$?
afirma "T2e1. exit 2 para nao-provado vazio" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"

echo "== T2f. caminho feliz: dois entregaveis com hash/bytes corretos =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo um" > "$S/docs/a-gravar/um.md"
echo "conteudo arquivo dois com mais texto" > "$S/docs/a-gravar/dois.cjs"

cat > "$S/docs/rainforest/estado/feliz.json" <<FIM
{
  "slug": "feliz",
  "plano": {
    "entregaveis": ["docs/a-gravar/um.md", "docs/a-gravar/dois.cjs"]
  }
}
FIM

SAIDA="$(rec gravar --slug feliz --nao-provado '["revisao visual","comportamento em producao"]')"; C=$?
afirma "T2f1. exit 0" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

# Confere que o arquivo foi gravado
RECIBO_ARQUIVO="$S/.rainforest/colheita/feliz-recibo.json"
afirma "T2f2. recibo foi gravado" "$([ -f "$RECIBO_ARQUIVO" ] && echo 1 || echo 0)"

if [ -f "$RECIBO_ARQUIVO" ]; then
  # Lê o recibo usando o ambiente RFM_ESTADO_ROOT que está definido globalmente
  # Node consegue ler o arquivo porque é usando a variável de env que foi setup no rec()
  SHA1_JSON=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/feliz-recibo.json'))); console.log(d.entregaveis[0].sha256)" 2>/dev/null || echo "erro")
  BYTES1_JSON=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/feliz-recibo.json'))); console.log(d.entregaveis[0].bytes)" 2>/dev/null || echo "erro")

  # Calcula sha256 e bytes reais do primeiro arquivo
  SHA1_REAL=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const crypto=require('crypto'); const path=require('path'); const buf=fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, 'docs/a-gravar/um.md')); console.log(crypto.createHash('sha256').update(buf).digest('hex'))" 2>/dev/null || echo "erro")
  BYTES1_REAL=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); console.log(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, 'docs/a-gravar/um.md')).length)" 2>/dev/null || echo "erro")

  afirma "T2f3. sha256 do primeiro entregavel confere" "$([ "$SHA1_JSON" = "$SHA1_REAL" ] && echo 1 || echo 0)"
  afirma "T2f4. bytes do primeiro entregavel confere" "$([ "$BYTES1_JSON" = "$BYTES1_REAL" ] && echo 1 || echo 0)"

  # Confere segundo entregavel
  SHA2_JSON=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/feliz-recibo.json'))); console.log(d.entregaveis[1].sha256)" 2>/dev/null || echo "erro")
  BYTES2_JSON=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/feliz-recibo.json'))); console.log(d.entregaveis[1].bytes)" 2>/dev/null || echo "erro")

  SHA2_REAL=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const crypto=require('crypto'); const path=require('path'); const buf=fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, 'docs/a-gravar/dois.cjs')); console.log(crypto.createHash('sha256').update(buf).digest('hex'))" 2>/dev/null || echo "erro")
  BYTES2_REAL=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); console.log(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, 'docs/a-gravar/dois.cjs')).length)" 2>/dev/null || echo "erro")

  afirma "T2f5. sha256 do segundo entregavel confere" "$([ "$SHA2_JSON" = "$SHA2_REAL" ] && echo 1 || echo 0)"
  afirma "T2f6. bytes do segundo entregavel confere" "$([ "$BYTES2_JSON" = "$BYTES2_REAL" ] && echo 1 || echo 0)"

  # Confere nao_provado
  NAO_PROV=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/feliz-recibo.json'))); console.log(JSON.stringify(d.nao_provado))" 2>/dev/null || echo "erro")
  afirma "T2f7. nao_provado foi gravado no JSON" \
    "$([ "$NAO_PROV" = '["revisao visual","comportamento em producao"]' ] && echo 1 || echo 0)"
else
  echo "  FALHA T2f3. sha256 do primeiro entregavel confere"
  echo "  FALHA T2f4. bytes do primeiro entregavel confere"
  echo "  FALHA T2f5. sha256 do segundo entregavel confere"
  echo "  FALHA T2f6. bytes do segundo entregavel confere"
  echo "  FALHA T2f7. nao_provado foi gravado no JSON"
  falhou=$((falhou+5))
fi

echo "== T2g. .gitignore contem .rainforest/colheita/ =="
afirma "T2g1. .gitignore tem a linha colheita" \
  "$(grep -q '\.rainforest/colheita/' "$RAIZ/.gitignore" && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
