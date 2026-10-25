#!/bin/bash
# Bateria do D7 (lote 6): a consolidação da memória não pula pedaço calada.
# Uso: bash scripts/testa-memoria-consolidar-pulo.sh
#
# O que esta bateria prova:
#   1. pedaço em que o LLM devolve null é CONTADO: a passada de manutenção
#      grava `consolidar: fim (N pedaço(s) pulado(s))` e termina em
#      `manutencao: completa com falhas`;
#   2. com o LLM ok, a passada termina em `manutencao: completa` e o consolidar
#      grava `consolidar: fim` sem contagem;
#   3. sem grupo elegível, o consolidar ainda fecha limpo (devolve contagem zero);
#   4. a CLI direta `consolidar` imprime o total pulado;
#   5. 30 observações de 2.000 caracteres chegam ao LLM com no máximo 16.000
#      caracteres e gravam um resumo; o banco não muda, só o texto enviado.
#
# Toda caixa é um subdiretório de UMA sandbox `mktemp -d`, removida no EXIT.
# O RFM_ROOT de cada chamada aponta para essa caixa — nunca para a raiz real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
MEMORIA="node --no-warnings $SRC/scripts/memoria.cjs"

ok=0
falhou=0

afirma() {
  # afirma <nome> <condição: 0 = passou>
  if [ "$2" = 0 ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"
  fi
}

# semear <caixa> <quantas> <tamanho> <sessao> — observações de 31 dias atrás
semear() {
  RFM_ROOT="$1" $MEMORIA iniciar > /dev/null 2>&1
  RFM_ROOT="$1" SEMEAR_N="$2" SEMEAR_TAM="$3" SEMEAR_SESSAO="$4" SRC_MEM="$SRC/scripts/memoria.cjs" node --no-warnings -e "
const { abrirBanco } = require(process.env.SRC_MEM);
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const antiga = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
const n = Number(process.env.SEMEAR_N);
const tam = Number(process.env.SEMEAR_TAM);
for (let i = 0; i < n; i++) {
  const base = 'Observacao ' + i + ' ';
  const conteudo = base + 'x'.repeat(Math.max(0, tam - base.length));
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-pulo', conteudo, antiga, 'sessao:' + process.env.SEMEAR_SESSAO + ':offset:' + i);
}
db.close();
" > /dev/null 2>&1
}

# contar <caixa> <consulta> — roda uma consulta escalar no banco da caixa
contar() {
  RFM_ROOT="$1" SQL="$2" SRC_MEM="$SRC/scripts/memoria.cjs" node --no-warnings -e "
const { abrirBanco } = require(process.env.SRC_MEM);
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
process.stdout.write(String(db.prepare(process.env.SQL).get().c));
db.close();
" 2>/dev/null
}

# Dublê de LLM: falha com TESTADOR_LLM_FALHAR=1; senão devolve resumo fixo.
# Se DUBLE_REGISTRO estiver setado, anota o tamanho do texto de cada pedaço
# de consolidação (o texto começa com "1. ", a numeração do pedaço).
DUBLE="$BASE/dubleLLM.cjs"
cat > "$DUBLE" <<'EOF'
const fs = require('fs');
async function chamarLLM(texto) {
  if (process.env.DUBLE_REGISTRO && /^1\. /.test(texto)) {
    fs.appendFileSync(process.env.DUBLE_REGISTRO, texto.length + '\n');
  }
  if (process.env.TESTADOR_LLM_FALHAR === '1') return null;
  return 'Síntese do grupo: tópicos consolidados';
}
module.exports = { chamarLLM };
EOF

echo "== consolidação do D7: pedaço pulado não passa calado =="

# --- 1. LLM que falha deixa a manutenção completa com falhas
CAIXA_A="$BASE/caixa-a"; mkdir -p "$CAIXA_A"
semear "$CAIXA_A" 3 100 "sessao-pulo-a"
RFM_ROOT="$CAIXA_A" TESTADOR_CHAMAR_LLM="$DUBLE" TESTADOR_LLM_FALHAR=1 $MEMORIA manutencao > /dev/null 2>&1
LOG_A="$CAIXA_A/manutencao.log"
ULTIMA_A="$(tail -n 1 "$LOG_A" 2>/dev/null | sed 's/^[^ ]* //')"
echo "  comando: RFM_ROOT=<caixa> TESTADOR_LLM_FALHAR=1 node scripts/memoria.cjs manutencao; última linha: $ULTIMA_A"
grep "consolidar: fim" "$LOG_A" 2>/dev/null | sed 's/^/  log: /'
PULADO_A="$(grep -c 'consolidar: fim (1 pedaço(s) pulado(s))' "$LOG_A" 2>/dev/null)"
afirma "LLM que falha deixa a manutenção completa com falhas" $([ "$ULTIMA_A" = "manutencao: completa com falhas" ] && [ "$PULADO_A" = 1 ] && echo 0 || echo 1)

# --- 2. LLM ok: passada completa, consolidar sem contagem
CAIXA_B="$BASE/caixa-b"; mkdir -p "$CAIXA_B"
semear "$CAIXA_B" 3 100 "sessao-pulo-b"
RFM_ROOT="$CAIXA_B" TESTADOR_CHAMAR_LLM="$DUBLE" $MEMORIA manutencao > /dev/null 2>&1
LOG_B="$CAIXA_B/manutencao.log"
ULTIMA_B="$(tail -n 1 "$LOG_B" 2>/dev/null | sed 's/^[^ ]* //')"
SEM_PULO_B="$(grep -c 'consolidar: fim$' "$LOG_B" 2>/dev/null)"
RESUMOS_B="$(contar "$CAIXA_B" 'SELECT COUNT(*) c FROM resumos')"
echo "  comando: RFM_ROOT=<caixa> node scripts/memoria.cjs manutencao; última linha: $ULTIMA_B; resumos: $RESUMOS_B"
afirma "LLM ok deixa a manutenção completa e o consolidar sem pulado" $([ "$ULTIMA_B" = "manutencao: completa" ] && [ "$SEM_PULO_B" = 1 ] && [ "$RESUMOS_B" = 1 ] && echo 0 || echo 1)

# --- 3. sem grupo elegível: consolidar fecha limpo (contagem zero)
CAIXA_C="$BASE/caixa-c"; mkdir -p "$CAIXA_C"
RFM_ROOT="$CAIXA_C" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_C" TESTADOR_CHAMAR_LLM="$DUBLE" $MEMORIA manutencao > /dev/null 2>&1
LOG_C="$CAIXA_C/manutencao.log"
ULTIMA_C="$(tail -n 1 "$LOG_C" 2>/dev/null | sed 's/^[^ ]* //')"
FIM_C="$(grep -c 'consolidar: fim$' "$LOG_C" 2>/dev/null)"
FALHA_C="$(grep -c 'consolidar: falhou' "$LOG_C" 2>/dev/null)"
echo "  comando: RFM_ROOT=<caixa vazia> node scripts/memoria.cjs manutencao; última linha: $ULTIMA_C"
afirma "sem grupo elegível o consolidar fecha limpo" $([ "$ULTIMA_C" = "manutencao: completa" ] && [ "$FIM_C" = 1 ] && [ "$FALHA_C" = 0 ] && echo 0 || echo 1)

# --- 4. CLI direta imprime o total pulado
CAIXA_E="$BASE/caixa-e"; mkdir -p "$CAIXA_E"
semear "$CAIXA_E" 2 100 "sessao-pulo-e"
SAIDA_E="$(RFM_ROOT="$CAIXA_E" TESTADOR_CHAMAR_LLM="$DUBLE" TESTADOR_LLM_FALHAR=1 $MEMORIA consolidar 2>&1)"
echo "  comando: RFM_ROOT=<caixa> TESTADOR_LLM_FALHAR=1 node scripts/memoria.cjs consolidar; saída: $(echo "$SAIDA_E" | tail -n 1)"
afirma "a CLI consolidar direta imprime o total pulado" $(echo "$SAIDA_E" | grep -q 'pedaço(s) pulado(s) (LLM falhou): 1' && echo 0 || echo 1)

# --- 5. pedaço de 30 observações de 2.000 caracteres: texto ≤ 16.000 e resumo gravado
CAIXA_D="$BASE/caixa-d"; mkdir -p "$CAIXA_D"
semear "$CAIXA_D" 30 2000 "sessao-pulo-d"
REGISTRO_D="$CAIXA_D/tamanhos.txt"
RFM_ROOT="$CAIXA_D" DUBLE_REGISTRO="$REGISTRO_D" TESTADOR_CHAMAR_LLM="$DUBLE" $MEMORIA consolidar > /dev/null 2>&1
TAMANHOS_D="$(cat "$REGISTRO_D" 2>/dev/null | tr '\n' ' ')"
MAIOR_D="$(sort -n "$REGISTRO_D" 2>/dev/null | tail -n 1)"
RESUMOS_D="$(contar "$CAIXA_D" 'SELECT COUNT(*) c FROM resumos')"
CONSOLIDADAS_D="$(contar "$CAIXA_D" 'SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL')"
echo "  comando: RFM_ROOT=<caixa> node scripts/memoria.cjs consolidar; texto(s) ao LLM: $TAMANHOS_D; resumos: $RESUMOS_D; consolidadas: $CONSOLIDADAS_D"
afirma "30 observações de 2.000 caracteres chegam ao LLM com até 16.000 e gravam resumo" $([ -n "$MAIOR_D" ] && [ "$MAIOR_D" -le 16000 ] && [ "$RESUMOS_D" = 1 ] && [ "$CONSOLIDADAS_D" = 30 ] && echo 0 || echo 1)

# --- 6. observar.cjs: o ok da linha final conta só as fatias tratadas quando o
# orçamento de tempo corta o resto (TESTADOR_ORCAMENTO_MS=1 força o corte).
CAIXA_F="$BASE/caixa-f"; mkdir -p "$CAIXA_F"
RFM_ROOT="$CAIXA_F" $MEMORIA iniciar > /dev/null 2>&1
# O Node cria o transcrito e a marca a partir de RFM_ROOT (o mesmo caminho que
# o memoria.cjs e o observar.cjs resolvem); mexer em disco pelo bash com o
# caminho do mktemp não bate com o caminho que o Node resolve no Windows.
RFM_ROOT="$CAIXA_F" SRC_MEM="$SRC/scripts/memoria.cjs" node --no-warnings -e "
const fs = require('fs');
const path = require('path');
const { abrirBanco } = require(process.env.SRC_MEM);
const dir = path.join(process.env.RFM_ROOT, 'projects', 'proj-obs');
fs.mkdirSync(dir, { recursive: true });
const transcrito = path.join(dir, 'sessao.jsonl');
const linhas = [];
for (let i = 0; i < 16; i++) {
  linhas.push(JSON.stringify({ type: 'user', message: { role: 'user', content: ('Pergunta ' + i + ' ').padEnd(3000, 'y') }, timestamp: '2026-10-01T10:00:00Z', sessionId: 'sessao', version: '2.1.0', cwd: 'test' }));
}
fs.writeFileSync(transcrito, linhas.join('\n') + '\n');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)')
  .run('proj-obs', 'sessao', transcrito, 0, new Date().toISOString());
db.close();
" > /dev/null 2>&1
RFM_ROOT="$CAIXA_F" TESTADOR_CHAMAR_LLM="$SRC/scripts/dubliador-llm-ok.cjs" TESTADOR_ORCAMENTO_MS=1 \
  node --no-warnings "$SRC/scripts/observar.cjs" --sessao sessao --projeto proj-obs > "$CAIXA_F/saida.txt" 2>/dev/null
SAIDA_F="$(cat "$CAIXA_F/saida.txt")"
PROCESSADAS_F="$(grep -c '^processando fatia' "$CAIXA_F/saida.txt")"
OK_F="$(echo "$SAIDA_F" | sed -n 's/^ok: observacao gravada em \([0-9]*\) fatias\{0,1\} para sessao.*$/\1/p')"
TOTAL_F="$(echo "$SAIDA_F" | sed -n 's/^orcamento de [0-9]*ms atingido apos [0-9]* fatia(s) de \([0-9]*\);.*$/\1/p')"
echo "  comando: RFM_ROOT=<caixa> TESTADOR_ORCAMENTO_MS=1 node scripts/observar.cjs --sessao sessao --projeto proj-obs; processadas: $PROCESSADAS_F; linha ok: $OK_F de $TOTAL_F"
afirma "observar: o ok conta só as fatias tratadas quando o orçamento corta" $([ -n "$OK_F" ] && [ -n "$TOTAL_F" ] && [ "$OK_F" = "$PROCESSADAS_F" ] && [ "$OK_F" -lt "$TOTAL_F" ] && echo 0 || echo 1)

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
