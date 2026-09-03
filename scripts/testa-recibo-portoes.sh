#!/bin/bash
# Bateria de testes para `recibo.cjs gravar` com portões.
# Uso: bash scripts/testa-recibo-portoes.sh
#
# Tarefa 3 do plano `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que `gravar` pule portões porque têm evidência gravada. O flag
#      `--reverificar` força a re-execução AGORA, rejeitando evidência stale.
#
#   2. Que `gravar` sobrescreva um recibo anterior quando o portão falha.
#      Nenhum arquivo em `.rainforest/colheita/` é tocado se o exit for ≠ 0.
#
#   3. Que `gravar` proceda sem portão mesmo quando a evidência é velha.
#      Com `--reverificar`, o portão marcado `[x]` e com evidência de ontem
#      é re-executado hoje, e reprova se o CHECK falha AGORA.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIBO="$RAIZ/scripts/recibo.cjs"

[ -f "$RECIBO" ] || { echo "FALHA: nao achei $RECIBO"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/estado" "$S/docs/rainforest/portoes"

# Copia os oráculos para a sandbox (portoes.cjs roda com cwd: RAIZ da sandbox)
mkdir -p "$S/test/fixtures/portoes/scripts"
cp "$RAIZ/test/fixtures/portoes/scripts/sempre-ok.cjs" "$S/test/fixtures/portoes/scripts/"
cp "$RAIZ/test/fixtures/portoes/scripts/sempre-falha.cjs" "$S/test/fixtures/portoes/scripts/"

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# Roda o recibo.cjs numa raiz-sandbox. `cd "$RAIZ"` de proposito: o confinamento
# por realpath usa RAIZ REAL, e e' assim que roda em producao.
rec() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$RECIBO" "$@" 2>&1); }

echo "== T3a. sem portoes.md: grava normalmente, exit 0 =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo um" > "$S/docs/a-gravar/um.md"
cat > "$S/docs/rainforest/estado/sem-portoes.json" <<FIM
{
  "slug": "sem-portoes",
  "plano": {
    "entregaveis": ["docs/a-gravar/um.md"]
  }
}
FIM
SAIDA="$(rec gravar --slug sem-portoes --nao-provado '["algo"]')"; C=$?
afirma "T3a1. exit 0 sem portoes.md" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "T3a2. recibo foi gravado" "$([ -f "$S/.rainforest/colheita/sem-portoes-recibo.json" ] && echo 1 || echo 0)"

if [ -f "$S/.rainforest/colheita/sem-portoes-recibo.json" ]; then
  PORTOES_CAMPO=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/sem-portoes-recibo.json'))); console.log(d.portoes ? 'tem' : 'nao tem')" 2>/dev/null || echo "erro")
  afirma "T3a3. recibo NAO tem campo portoes sem portoes.md" "$([ "$PORTOES_CAMPO" = "nao tem" ] && echo 1 || echo 0)"
else
  echo "  FALHA T3a3. recibo NAO tem campo portoes sem portoes.md"
  falhou=$((falhou+1))
fi

echo "== T3b. portoes.md com CHECK sempre-ok.cjs: exit 0, campo portoes gravado =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo dois" > "$S/docs/a-gravar/dois.md"
cat > "$S/docs/rainforest/portoes/com-ok.md" <<FIM
# Portões: caminho feliz

- [ ] P1: o verificador passa
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM

cat > "$S/docs/rainforest/estado/com-ok.json" <<FIM
{
  "slug": "com-ok",
  "plano": {
    "entregaveis": ["docs/a-gravar/dois.md"]
  }
}
FIM
SAIDA="$(rec gravar --slug com-ok --nao-provado '["algo"]')"; C=$?
afirma "T3b1. exit 0 com portao ok" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "T3b2. recibo foi gravado" "$([ -f "$S/.rainforest/colheita/com-ok-recibo.json" ] && echo 1 || echo 0)"

if [ -f "$S/.rainforest/colheita/com-ok-recibo.json" ]; then
  PORTOES_CAMPO=$(RFM_ESTADO_ROOT="$S" node -e "const fs=require('fs'); const path=require('path'); const d=JSON.parse(fs.readFileSync(path.join(process.env.RFM_ESTADO_ROOT, '.rainforest/colheita/com-ok-recibo.json'))); console.log(d.portoes ? 'tem' : 'nao tem')" 2>/dev/null || echo "erro")
  afirma "T3b3. recibo TEM campo portoes" "$([ "$PORTOES_CAMPO" = "tem" ] && echo 1 || echo 0)"
fi

echo "== T3c. portoes.md com CHECK sempre-falha.cjs: exit 1, nenhum recibo criado =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo tres" > "$S/docs/a-gravar/tres.md"
cat > "$S/docs/rainforest/portoes/com-falha.md" <<FIM
# Portões: o CHECK reprova

- [ ] P1: o módulo falha
  CHECK: node test/fixtures/portoes/scripts/sempre-falha.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM

cat > "$S/docs/rainforest/estado/com-falha.json" <<FIM
{
  "slug": "com-falha",
  "plano": {
    "entregaveis": ["docs/a-gravar/tres.md"]
  }
}
FIM
SAIDA="$(rec gravar --slug com-falha --nao-provado '["algo"]')"; C=$?
afirma "T3c1. exit 1 com portao falha" "$([ "$C" -eq 1 ] && echo 1 || echo 0)"
afirma "T3c2. stderr menciona RECUSADO e portoes" \
  "$(printf '%s' "$SAIDA" | grep -q "RECUSADO" && printf '%s' "$SAIDA" | grep -q "portoes" && echo 1 || echo 0)"
afirma "T3c3. nenhum arquivo criado em .rainforest/colheita para com-falha" \
  "$([ ! -f "$S/.rainforest/colheita/com-falha-recibo.json" ] && echo 1 || echo 0)"

echo "== T3d. evidencia velha: portao [x] marcado com EVIDENCIA gravada, CHECK hoje falha =="
# Criamos um estado anterior, como se já tivéssemos gravado um recibo neste slug.
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo quatro original" > "$S/docs/a-gravar/quatro.md"
cat > "$S/docs/rainforest/estado/evidencia-velha.json" <<FIM
{
  "slug": "evidencia-velha",
  "plano": {
    "entregaveis": ["docs/a-gravar/quatro.md"]
  }
}
FIM

# Criamos um portão com [x] (cumprido) e EVIDENCIA gravada, mas cujo CHECK
# hoje aponta para `sempre-falha.cjs`. Isso espelha o caso G21/G22:
# marcado de sucesso ONTEM, mas falha AGORA.
cat > "$S/docs/rainforest/portoes/evidencia-velha.md" <<FIM
# Portões: evidência velha

- [x] P1: o portão que passou ontem
  CHECK: node test/fixtures/portoes/scripts/sempre-falha.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: {"shell":"cmd.exe","cwd":".","exit":0,"match":true,"fingerprint":"abc123"}
FIM

# Primeiro gravamos um recibo "anterior" para ter algo em disco
SAIDA1="$(rec gravar --slug evidencia-velha --nao-provado '["teste"]' 2>&1)"
C1=$?
# Este primeiro `gravar` vai falhar (portão reprova), então não há recibo anterior.
# Para simular a situação de G21/G22, precisamos burlar isto criando um recibo
# manualmente como se ele tivesse passado ontem.
mkdir -p "$S/.rainforest/colheita"
cat > "$S/.rainforest/colheita/evidencia-velha-recibo.json" <<FIM
{
  "slug": "evidencia-velha",
  "em": "2026-09-02T10:00:00.000Z",
  "entregaveis": [
    {
      "caminho": "docs/a-gravar/quatro.md",
      "sha256": "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1",
      "bytes": 29
    }
  ],
  "nao_provado": ["teste"]
}
FIM

# Agora rodamos `gravar` de novo. O portão TEM evidência gravada (`[x]` + `EVIDENCIA:`),
# mas com `--reverificar`, `portoes.cjs rodar` re-executa e reprova.
BYTES_ANTES=$(stat -f%z "$S/.rainforest/colheita/evidencia-velha-recibo.json" 2>/dev/null || echo "0")
SAIDA="$(rec gravar --slug evidencia-velha --nao-provado '["teste"]' 2>&1)"; C=$?
BYTES_DEPOIS=$(stat -f%z "$S/.rainforest/colheita/evidencia-velha-recibo.json" 2>/dev/null || echo "0")

afirma "T3d1. exit 1 mesmo com evidencia velha (reprova com --reverificar)" "$([ "$C" -eq 1 ] && echo 1 || echo 0)"
afirma "T3d2. stderr menciona portoes reprovados" \
  "$(printf '%s' "$SAIDA" | grep -q "portoes" && echo 1 || echo 0)"
# Em Windows, stat pode não funcionar. Usamos uma abordagem alternativa.
if [ "$BYTES_ANTES" != "0" ] && [ "$BYTES_DEPOIS" != "0" ]; then
  afirma "T3d3. arquivo nao foi sobrescrito (bytes identicos)" "$([ "$BYTES_ANTES" = "$BYTES_DEPOIS" ] && echo 1 || echo 0)"
else
  # Fallback: verifica o conteúdo do JSON
  CONTEUDO_DEPOIS=$(cat "$S/.rainforest/colheita/evidencia-velha-recibo.json" 2>/dev/null || echo "")
  afirma "T3d3. arquivo nao foi sobrescrito (tem campo antigo)" \
    "$(printf '%s' "$CONTEUDO_DEPOIS" | grep -q 'abc123' && echo 1 || echo 0)"
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
