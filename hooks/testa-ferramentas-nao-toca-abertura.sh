#!/usr/bin/env bash
# Catraca da D1 da #76: o catalogo de ferramentas NAO entra na abertura.
#
# Por que existe, com numero: `ORCAMENTO_BYTES` e 8.000 B e a saida do
# `foco-session-start.cjs` ja estava em 8.085 B ANTES deste trabalho comecar.
# Nao havia "O(1) pequeno" a acrescentar — todo byte novo na abertura sai de um
# bloco de regra. Por isso a D1 decidiu leitura sob demanda, e nada na abertura.
#
# O que esta catraca NAO faz, e a razao importa: ela nao compara a saida contra
# um teto absoluto. A primeira versao do criterio fazia isso, e a medicao a
# derrubou no mesmo dia — a saida foi para 8.430 B sem que uma linha deste
# trabalho tocasse o gerador da abertura. O payload varia com o FOCO.md, com o
# corpus de memoria e com o bloco multi-janela, ou seja, com DADO DO USUARIO.
# Teto absoluto ficaria vermelho por motivo alheio e mediria a coisa errada;
# veredito certo pelo motivo errado e pior que veredito errado, porque ninguem
# volta a olhar.
#
# O que ela afere e o que a D1 promete: contribuicao ZERO deste trabalho.
#
# Cobre tambem a D4 — a checagem da bridge do WhatsApp continua onde estava,
# vinda do `foco-session-start.cjs`, e NAO foi absorvida por este mecanismo.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok=0; falhou=0

# O bloco "Dependencias de ambiente (regra 14)" so e emitido quando ha algo
# checado — e a checagem da bridge so roda com WHATSAPP_API_BASE_URL declarada.
# Ate 2026-09-02 a bateria herdava o ambiente de quem a roda: verde na maquina
# do dono (variavel no ambiente), vermelha no runner (Issues #153 e #163). A
# bateria passa a DECLARAR a dependencia, apontando para uma porta que recusa na
# hora: o que se afirma e que o bloco existe e vem do foco-session-start.cjs,
# nao que a bridge esta de pe. A raiz de dados e descartavel (Issue #160).
DADOS="$(mktemp -d)"; trap 'rm -rf "$DADOS"' EXIT
SAIDA="$(RFM_ROOT="$DADOS" WHATSAPP_API_BASE_URL="http://127.0.0.1:1/api" node "$SRC/hooks/foco-session-start.cjs" 2>/dev/null)"

echo "== D1: nada deste trabalho entrou na abertura =="

# A palavra "ferramenta" aparece legitimamente no texto da regra 15 ("ferramenta
# ausente para e reporta"). O que nao pode aparecer e o MECANISMO: o arquivo do
# ledger, o hook, ou o comando da porta unica.
VAZOU=""
for termo in "ferramentas.jsonl" "ferramentas-consulta" "ferramentas.cjs" "catalogo de ferramentas"; do
  printf '%s' "$SAIDA" | grep -qi -- "$termo" && VAZOU="$VAZOU $termo"
done
if [ -z "$VAZOU" ]; then
  ok=$((ok+1)); echo "  ok   nada de ferramentas entrou na abertura"
else
  falhou=$((falhou+1)); echo "  FALHA a abertura menciona:$VAZOU"
fi

QTD="$(node -e '
  const h = require(process.argv[1]).hooks;
  process.stdout.write(String((h.SessionStart || []).reduce((n,b) => n + b.hooks.length, 0)));
' "$SRC/hooks/hooks.json" 2>&1)"
if [ "$QTD" = "4" ]; then
  ok=$((ok+1)); echo "  ok   SessionStart continua com 4 hooks"
else
  falhou=$((falhou+1)); echo "  FALHA SessionStart tem $QTD hooks, esperava 4"
fi

echo
echo "== D4: a checagem da bridge continua separada, e viva =="

if printf '%s' "$SAIDA" | grep -q "Dependências de ambiente (regra 14)"; then
  ok=$((ok+1)); echo "  ok   o bloco de dependencias de ambiente continua na abertura"
else
  falhou=$((falhou+1)); echo "  FALHA sumiu o bloco 'Dependências de ambiente (regra 14)'"
fi

# A origem importa: se alguem mover a checagem para o mecanismo novo, este caso
# acusa. A D4 e uma divida declarada, nao um acidente a ser "consertado" em
# silencio por quem passar por aqui.
if grep -q "Dependências de ambiente (regra 14)" "$SRC/hooks/foco-session-start.cjs"; then
  ok=$((ok+1)); echo "  ok   o bloco continua vindo do foco-session-start.cjs"
else
  falhou=$((falhou+1)); echo "  FALHA a checagem saiu do foco-session-start.cjs"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
