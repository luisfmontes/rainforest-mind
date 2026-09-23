#!/bin/bash
# Bateria de scripts/lib/utilidade.cjs — sinal de utilidade da memória.
# Design: docs/rainforest/design/2026-09-23-memoria-sinal-de-utilidade.md
# Plano:  docs/rainforest/planos/2026-09-23-memoria-sinal-de-utilidade.md
# Uso: bash scripts/testa-utilidade.sh
#
# O que esta bateria prova, nesta ordem:
#   1. Extrator (Tarefa 1): contra o transcrito sintético versionado, `utilidade
#      --extrair` devolve o mesmo número de servidas que uma contagem
#      independente (outra leitura do arquivo, sem chamar o módulo sob
#      teste); e a prosa do assistente que ecoa a injeção nunca entra no texto.
#   2. Pontuação (Tarefa 2): contra um banco sintético (montado a partir de
#      `scripts/esquema-memoria.sql`) + o mesmo transcrito sintético,
#      `pontuarSessao` grava as servidas e o contrafactual, idempotente, sem
#      coluna de texto de sessão em `uso_memoria`; e um termo comum ao corpus
#      (frequência de documento alta) não pontua sozinho.
#   3. Manutenção (Tarefa 3): `manutencao` pontua as sessões pendentes da
#      `marca_dagua`, e transcrito apagado não derruba reconciliar/consolidar.
#   4. Relatório (Tarefa 4): a régua D9 liga com 1/3, não liga com 1/4, e lista
#      as não-servidas que motivaram a decisão só quando há perda.
#   6-11. Emendas: reconciliação que substitui uma servida ainda casa por id;
#      teto por passada e log de servidas sem id; denominador da régua só
#      conta sessão com servida; servida sem id nunca "vaza" para o
#      contrafactual (checada com cwd real subindo até o `.git` do próprio
#      repositório, e com rótulo forçado); sessão que falha é marcada sem
#      travar a fila; banco ocupado adia a sessão em vez de marcá-la.
#
# HERMÉTICA de propósito (Tarefa 13, Emenda 4 — CI do PR #326 vermelha: o
# runner do GitHub não tem banco nem transcrito reais desta máquina, e
# `.github/workflows/baterias.yml` proíbe plantar dado sintético fora da
# bateria). Toda seção usa:
#   - o banco: montado do zero em cada caixa (`mktemp -d`) a partir de
#     `scripts/esquema-memoria.sql` (via `criarSchema`, nunca DDL duplicado
#     aqui), populado com o corpus sintético de
#     `scripts/fixtures/utilidade/gerar-banco.cjs --popular`;
#   - o transcrito: o fixture versionado
#     `scripts/fixtures/utilidade/transcrito-sessao.jsonl`, no formato real do
#     harness (attachment de SessionStart, prompt de usuário, tool_use,
#     tool_result, prosa do assistente), conteúdo inteiramente sintético.
# `gerar-banco.cjs` é a ÚNICA fonte das observações: o fixture .jsonl foi
# gerado a partir dele (`node scripts/fixtures/utilidade/gerar-banco.cjs
# --emitir-transcrito scripts/fixtures/utilidade/transcrito-sessao.jsonl`) —
# se o corpus mudar, regenere o fixture com o mesmo comando antes de commitar.
# A única seção que NÃO usa esse fixture é a primeira metade da Tarefa 9: ela
# testa a subida real até um `.git` de verdade, e usa o próprio checkout deste
# repositório como cwd — nunca um dado externo à máquina que roda a bateria.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Forma Windows do caminho — heredocs abaixo viram arquivos .cjs que o NODE
# resolve via require(); require() não passa pela tradução de argv do MSYS
# (essa tradução só se aplica a argumentos passados na hora do spawn, nunca a
# um caminho gravado DENTRO do conteúdo de um arquivo). Um require('$SRC/...')
# com o `$SRC` em forma POSIX (`/c/Projetos/...`) falha com MODULE_NOT_FOUND —
# medido nesta bateria antes deste comentário existir.
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

FIXTURE="$SRC/scripts/fixtures/utilidade/transcrito-sessao.jsonl"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

MEMORIA="node $SRC/scripts/memoria.cjs"
ok=0; falhou=0

if [ ! -f "$FIXTURE" ]; then
  echo "FALHA fixture ausente: $FIXTURE"
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi

# Dublê de chamada de LLM — reconciliar/consolidar (chamados por `manutencao`
# antes do passo de utilidade) nunca podem spawnar o `claude` real numa
# bateria. Usado por toda seção que roda `manutencao`.
duble_llm() {
  local dir
  dir="$(novo_sandbox)"
  cat > "$dir/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return '{"acao":"store","alvo_id":null}';
}
module.exports = { chamarLLM };
EOF
  echo "$dir"
}

# Monta uma caixa hermética completa: banco (schema + corpus sintético de
# gerar-banco.cjs) e uma cópia do transcrito fixture. Define CAIXA_PREP e
# CAIXA_PREP_WIN (convenção "variável global" — o mesmo estilo que o resto
# desta bateria já usa para CAIXA1, CAIXA2, ...).
preparar_caixa_utilidade() {
  local caixa caixa_win
  caixa="$(novo_sandbox)"
  caixa_win="$(cygpath -m "$caixa" 2>/dev/null || printf '%s' "$caixa")"
  RFM_ROOT="$caixa" $MEMORIA iniciar > /dev/null 2>&1
  RFM_ROOT="$caixa" node --no-warnings "$SRC/scripts/fixtures/utilidade/gerar-banco.cjs" --popular > /dev/null
  cp "$FIXTURE" "$caixa/transcrito.jsonl"
  CAIXA_PREP="$caixa"
  CAIXA_PREP_WIN="$caixa_win"
}

echo "== Tarefa 1: extrator do transcrito (servidas/texto) =="

# --- 1a. fixture versionado: contagem de servidas bate com contagem independente ---
CAIXA1="$(novo_sandbox)"
cp "$FIXTURE" "$CAIXA1/transcrito.jsonl"

SAIDA_EXTRAIR=$($MEMORIA utilidade --extrair "$CAIXA1/transcrito.jsonl" 2>&1)
echo "  comando: node scripts/memoria.cjs utilidade --extrair <fixture versionado>"
echo "  saida: $SAIDA_EXTRAIR"

cat > "$CAIXA1/contagem-independente.cjs" <<'EOF'
// Contagem INDEPENDENTE das servidas — releitura do arquivo sem chamar
// scripts/lib/utilidade.cjs, para provar que o extrator não está apenas
// concordando consigo mesmo.
const fs = require('fs');
const caminho = process.argv[2];
const linhas = fs.readFileSync(caminho, 'utf8').split('\n');
let total = 0;
for (const l of linhas) {
  if (!l.trim()) continue;
  let o;
  try { o = JSON.parse(l); } catch (e) { continue; }
  if (o.type !== 'attachment' || !o.attachment || o.attachment.hookEvent !== 'SessionStart') continue;
  let parsed;
  try { parsed = JSON.parse(o.attachment.stdout); } catch (e) { continue; }
  const ctx = parsed && parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext;
  if (!ctx) continue;
  const inicio = ctx.indexOf('## Memória (corpus residentes)');
  if (inicio === -1) continue;
  const fimIdx = ctx.indexOf('mais:', inicio);
  const fim = fimIdx === -1 ? ctx.length : fimIdx;
  const bloco = ctx.slice(inicio, fim);
  total += bloco.split('\n').map(x => x.trim()).filter(x => x.startsWith('[')).length;
}
process.stdout.write(String(total));
EOF
CONTAGEM_INDEPENDENTE=$(node --no-warnings "$CAIXA1/contagem-independente.cjs" "$CAIXA1/transcrito.jsonl")
N_EXTRAIDO=$(printf '%s' "$SAIDA_EXTRAIR" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{process.stdout.write(String(JSON.parse(s).servidas))}catch(e){process.stdout.write('ERRO')}})")

if [ "$N_EXTRAIDO" = "$CONTAGEM_INDEPENDENTE" ] && [ "$N_EXTRAIDO" != "ERRO" ] && [ "$N_EXTRAIDO" != "0" ]; then
  ok=$((ok+1)); echo "  ok   servidas do transcrito real = $N_EXTRAIDO (contagem independente = $CONTAGEM_INDEPENDENTE)"
else
  falhou=$((falhou+1)); echo "  FALHA servidas do transcrito real = $N_EXTRAIDO, contagem independente = $CONTAGEM_INDEPENDENTE"
fi

# --- 1b. mesma fixture: prosa do assistente que ecoa a injecao nao entra no texto ---
cat > "$CAIXA1/checar-fixture.cjs" <<EOF
const { extrairSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const r = extrairSessao(process.argv[2]);
const temPrompt = r.texto.includes('MARCADORPROMPTUNICO');
const temFerramenta = r.texto.includes('MARCADORFERRAMENTAUNICO');
const temProsa = r.texto.includes('MARCADORPROSAUNICO');
const temResultado = r.texto.includes('MARCADORRESULTADOUNICO');
process.stdout.write(JSON.stringify({ servidas: r.servidas.length, temPrompt, temFerramenta, temProsa, temResultado }));
EOF
RESULTADO_FIXTURE=$(node --no-warnings "$CAIXA1/checar-fixture.cjs" "$CAIXA1/transcrito.jsonl")
echo "  comando: node -e \"extrairSessao(<fixture versionado>)\" (secao \"prosa do assistente que ecoa a injecao nao entra no texto\")"
echo "  saida: $RESULTADO_FIXTURE"
if echo "$RESULTADO_FIXTURE" | grep -q '"servidas":5' \
  && echo "$RESULTADO_FIXTURE" | grep -q '"temPrompt":true' \
  && echo "$RESULTADO_FIXTURE" | grep -q '"temFerramenta":true' \
  && echo "$RESULTADO_FIXTURE" | grep -q '"temProsa":false' \
  && echo "$RESULTADO_FIXTURE" | grep -q '"temResultado":false'; then
  ok=$((ok+1)); echo "  ok   prosa do assistente que ecoa a injecao nao entra no texto (prompt e tool_use entram, prosa e tool_result nao)"
else
  falhou=$((falhou+1)); echo "  FALHA fixture da prosa do assistente: $RESULTADO_FIXTURE"
fi

echo
echo "== Tarefa 2: pontuacao (nota crua, contrafactual, idempotencia) =="

# --- 2a/2b. banco sintetico (esquema-memoria.sql + corpus de gerar-banco.cjs) + fixture ---
preparar_caixa_utilidade
CAIXA3="$CAIXA_PREP"
CAIXA3_WIN="$CAIXA_PREP_WIN"

cat > "$CAIXA3/pontuar-real.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const caminhoTranscrito = process.argv[3];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);

const r1 = pontuarSessao(conexao, 'sessao-bateria-utilidade', caminhoTranscrito);
const servidasRow = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND servida = 1").get('sessao-bateria-utilidade');
const contraRow = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND servida = 0").get('sessao-bateria-utilidade');
const foraDeFaixaRow = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND (nota IS NULL OR nota < 0 OR nota > 1)").get('sessao-bateria-utilidade');

// segunda rodada — idempotencia
pontuarSessao(conexao, 'sessao-bateria-utilidade', caminhoTranscrito);
const servidasRow2 = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND servida = 1").get('sessao-bateria-utilidade');
const contraRow2 = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND servida = 0").get('sessao-bateria-utilidade');

const colunas = conexao.prepare("PRAGMA table_info(uso_memoria)").all().map(c => c.name).sort();

conexao.close();
process.stdout.write(JSON.stringify({
  servidasComId: r1.servidasComId,
  servidasEsperadasEmUso: servidasRow.c,
  contrafactualEmUso: contraRow.c,
  foraDeFaixa: foraDeFaixaRow.c,
  idempotenteServida: servidasRow.c === servidasRow2.c,
  idempotenteContra: contraRow.c === contraRow2.c,
  colunas,
}));
EOF
RESULTADO_PONTUACAO=$(node --no-warnings "$CAIXA3/pontuar-real.cjs" "$CAIXA3_WIN" "$CAIXA3_WIN/transcrito.jsonl" 2>&1)
echo "  comando: RFM_ROOT=<caixa sintetica> node -e \"pontuarSessao(conexao, sessao, <fixture versionado>)\""
echo "  saida: $RESULTADO_PONTUACAO"

S_SERVIDAS=$(printf '%s' "$RESULTADO_PONTUACAO" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasEsperadasEmUso))}catch(e){process.stdout.write('ERRO')}})")
C_CONTRA=$(printf '%s' "$RESULTADO_PONTUACAO" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.contrafactualEmUso))}catch(e){process.stdout.write('ERRO')}})")

if echo "$RESULTADO_PONTUACAO" | grep -q '"foraDeFaixa":0' \
  && echo "$RESULTADO_PONTUACAO" | grep -q '"idempotenteServida":true' \
  && echo "$RESULTADO_PONTUACAO" | grep -q '"idempotenteContra":true' \
  && [ "$S_SERVIDAS" != "ERRO" ] && [ "$S_SERVIDAS" != "0" ] && [ "$C_CONTRA" != "ERRO" ] && [ "$C_CONTRA" != "0" ]; then
  ok=$((ok+1)); echo "  ok   pontuacao real: $S_SERVIDAS servidas + $C_CONTRA contrafactual, idempotente"
else
  falhou=$((falhou+1)); echo "  FALHA pontuacao real nao bateu: $RESULTADO_PONTUACAO"
fi

if echo "$RESULTADO_PONTUACAO" | grep -q '"colunas":\["nota","origem","pontuada_em","ref_id","servida","sessao"\]'; then
  ok=$((ok+1)); echo "  ok   nenhuma coluna de texto em uso_memoria"
else
  falhou=$((falhou+1)); echo "  FALHA colunas de uso_memoria fora do esperado (D10): $RESULTADO_PONTUACAO"
fi

# --- 2c. fixture da mutacao: termo comum a todo o corpus nao pontua (ja hermetica) ---
CAIXA4="$(novo_sandbox)"
CAIXA4_WIN="$(cygpath -m "$CAIXA4" 2>/dev/null || printf '%s' "$CAIXA4")"
RFM_ROOT="$CAIXA4" $MEMORIA iniciar > /dev/null 2>&1

cat > "$CAIXA4/fixture-nota.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { calcularNota, LIMIAR_DF } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();

// Termo comum: aparece em mais observacoes que LIMIAR_DF (df alto, NAO raro).
// Termo raro: aparece so na observacao sondada (df=1, raro).
for (let i = 0; i < LIMIAR_DF + 2; i++) {
  conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-nota', 'texto com termocomumnestecorpus numero ' + i, agora, 'fixture-comum-' + i);
}
conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
  .run('proj-nota', 'termocomumnestecorpus termoraroexclusivo', agora, 'fixture-sondada');

// Texto da sessao tem o termo RARO, mas NAO tem o termo COMUM.
const textoSessao = 'a sessao usou termoraroexclusivo em algum momento';

const conteudoSondada = 'termocomumnestecorpus termoraroexclusivo';
const nota = calcularNota(conexao, conteudoSondada, textoSessao);
conexao.close();
process.stdout.write(String(nota));
EOF
NOTA_FIXTURE=$(node --no-warnings "$CAIXA4/fixture-nota.cjs" "$CAIXA4_WIN")
echo "  comando: node -e \"calcularNota(conexao, <sondada>, <texto>)\" (secao \"termo comum a todo o corpus nao pontua\")"
echo "  saida: nota=$NOTA_FIXTURE"
if [ "$NOTA_FIXTURE" = "1" ]; then
  ok=$((ok+1)); echo "  ok   termo comum a todo o corpus nao pontua (nota=$NOTA_FIXTURE, só o termo raro contou)"
else
  falhou=$((falhou+1)); echo "  FALHA termo comum a todo o corpus nao pontua: esperava nota=1, veio $NOTA_FIXTURE"
fi

echo
echo "== Tarefa 3: pontuacao dentro da manutencao, sessoes pendentes =="

DUBLE_LLM_DIR_T3="$(duble_llm)"

preparar_caixa_utilidade
CAIXA5="$CAIXA_PREP"
CAIXA5_WIN="$CAIXA_PREP_WIN"

cat > "$CAIXA5/marcar.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { resolverCaminhos, abrirBanco } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-manutencao-a', process.argv[3], 100, 100, agora);
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-manutencao-b', process.argv[3], 100, 100, agora);
conexao.close();
EOF
node --no-warnings "$CAIXA5/marcar.cjs" "$CAIXA5_WIN" "$CAIXA5_WIN/transcrito.jsonl"

RFM_ROOT="$CAIXA5" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T3/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
got_manutencao=$?
LOG_MANUTENCAO="$CAIXA5/manutencao.log"
echo "  comando: RFM_ROOT=<caixa sintetica com 2 marcas pendentes> node scripts/memoria.cjs manutencao"
echo "  saida (log): $(cat "$LOG_MANUTENCAO" 2>/dev/null | tr '\n' ' | ')"

cat > "$CAIXA5/conferir-sessoes.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBancoSomenteLeitura, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBancoSomenteLeitura(caminhoDb);
const linhas = conexao.prepare('SELECT sessao FROM uso_memoria_sessoes WHERE sessao IN (?, ?)').all('sessao-manutencao-a', 'sessao-manutencao-b');
conexao.close();
process.stdout.write(String(linhas.length));
EOF
N_MARCADAS=$(node --no-warnings "$CAIXA5/conferir-sessoes.cjs" "$CAIXA5_WIN")

if [ "$got_manutencao" = "0" ] && [ "$N_MARCADAS" = "2" ] && grep -q "utilidade: 2 sessao(oes) pontuada(s)" "$LOG_MANUTENCAO"; then
  ok=$((ok+1)); echo "  ok   manutencao pontua as sessoes pendentes da marca_dagua (2 em uso_memoria_sessoes, log 'utilidade: 2 sessao(oes) pontuada(s)')"
else
  falhou=$((falhou+1)); echo "  FALHA manutencao nao pontuou as 2 pendentes: exit=$got_manutencao marcadas=$N_MARCADAS"
  echo "         log: $(cat "$LOG_MANUTENCAO" 2>/dev/null)"
fi

# --- transcrito apagado nao derruba reconciliar/consolidar ---
DUBLE_LLM_DIR_T3B="$(duble_llm)"

preparar_caixa_utilidade
CAIXA6="$CAIXA_PREP"
CAIXA6_WIN="$CAIXA_PREP_WIN"
mv "$CAIXA6/transcrito.jsonl" "$CAIXA6/transcrito-existe.jsonl"
# transcrito-sumiu.jsonl e apontado na marca_dagua mas NUNCA criado.

cat > "$CAIXA6/marcar2.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-existe', process.argv[3], 100, 100, agora);
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-sumiu', process.argv[4], 100, 100, agora);
conexao.close();
EOF
node --no-warnings "$CAIXA6/marcar2.cjs" "$CAIXA6_WIN" "$CAIXA6_WIN/transcrito-existe.jsonl" "$CAIXA6_WIN/transcrito-sumiu.jsonl"

RFM_ROOT="$CAIXA6" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T3B/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
got_manutencao2=$?
LOG_MANUTENCAO2="$CAIXA6/manutencao.log"

if [ "$got_manutencao2" = "0" ] \
  && grep -q "reconciliar: fim" "$LOG_MANUTENCAO2" \
  && grep -q "consolidar: fim" "$LOG_MANUTENCAO2"; then
  ok=$((ok+1)); echo "  ok   transcrito apagado nao derruba a manutencao (exit 0, reconciliar/consolidar seguem registrados)"
else
  falhou=$((falhou+1)); echo "  FALHA transcrito apagado derrubou a manutencao: exit=$got_manutencao2"
  echo "         log: $(cat "$LOG_MANUTENCAO2" 2>/dev/null)"
fi

echo
echo "== Tarefa 4: relatorio com a regua D9 =="

# --- 4a. LIGA com 1 de 3 (ja hermetica: banco proprio, sem depender do fixture) ---
CAIXA7="$(novo_sandbox)"
CAIXA7_WIN="$(cygpath -m "$CAIXA7" 2>/dev/null || printf '%s' "$CAIXA7")"
RFM_ROOT="$CAIXA7" $MEMORIA iniciar > /dev/null 2>&1

cat > "$CAIXA7/popular-1de3.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();

// 3 observacoes so para idadeEmDias() ter de onde ler criada_em.
for (let i = 1; i <= 3; i++) {
  conexao.prepare('INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?, ?)')
    .run(i, 'proj-regua', 'obs ' + i, agora, 'regua-' + i);
}

function sessao(id, servidaNota, naoServidaNota) {
  conexao.prepare('INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)').run(id, agora);
  conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
    .run('observacao', 1, id, 1, servidaNota, agora);
  if (naoServidaNota !== null) {
    conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
      .run('observacao', 2, id, 0, naoServidaNota, agora);
  }
}

// sessao-1: nao-servida (0.9) pontua ACIMA da melhor servida (0.3) -> perda.
sessao('sessao-1', 0.3, 0.9);
// sessao-2 e sessao-3: sem perda (nao-servida abaixo ou ausente).
sessao('sessao-2', 0.8, 0.2);
sessao('sessao-3', 0.5, null);

conexao.close();
EOF
node --no-warnings "$CAIXA7/popular-1de3.cjs" "$CAIXA7_WIN"

SAIDA_1DE3=$(RFM_ROOT="$CAIXA7" $MEMORIA utilidade --relatorio 2>&1)
echo "  comando: RFM_ROOT=<caixa 1 de 3> node scripts/memoria.cjs utilidade --relatorio"
echo "  saida:"
echo "$SAIDA_1DE3" | sed 's/^/    /'
if echo "$SAIDA_1DE3" | grep -q "régua D9: LIGA o ranking (1 de 3 sessões)"; then
  ok=$((ok+1)); echo "  ok   regua D9 liga com 1 de 3 sessoes com perda"
else
  falhou=$((falhou+1)); echo "  FALHA regua D9 nao ligou com 1 de 3: $SAIDA_1DE3"
fi
if echo "$SAIDA_1DE3" | grep -q "não-servidas que a recência perdeu:"; then
  ok=$((ok+1)); echo "  ok   lista de nao-servidas presente quando ha perda"
else
  falhou=$((falhou+1)); echo "  FALHA lista de nao-servidas ausente com 1 sessao com perda"
fi

# --- 4b. NAO liga com 1 de 4 (mesma caixa, 1 sessao a mais sem perda) ---
cat > "$CAIXA7/popular-mais1.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();
conexao.prepare('INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)').run('sessao-4', agora);
conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
  .run('observacao', 1, 'sessao-4', 1, 0.9, agora);
conexao.close();
EOF
node --no-warnings "$CAIXA7/popular-mais1.cjs" "$CAIXA7_WIN"

SAIDA_1DE4=$(RFM_ROOT="$CAIXA7" $MEMORIA utilidade --relatorio 2>&1)
echo "  comando: RFM_ROOT=<caixa 1 de 4> node scripts/memoria.cjs utilidade --relatorio"
echo "  saida:"
echo "$SAIDA_1DE4" | sed 's/^/    /'
if echo "$SAIDA_1DE4" | grep -q "régua D9: NÃO liga — recência basta (1 de 4 sessões)"; then
  ok=$((ok+1)); echo "  ok   regua D9 nao liga com 1 de 4 sessoes com perda"
else
  falhou=$((falhou+1)); echo "  FALHA regua D9 deveria nao ligar com 1 de 4: $SAIDA_1DE4"
fi

# --- 4c. lista some quando nao ha perda nenhuma ---
CAIXA8="$(novo_sandbox)"
CAIXA8_WIN="$(cygpath -m "$CAIXA8" 2>/dev/null || printf '%s' "$CAIXA8")"
RFM_ROOT="$CAIXA8" $MEMORIA iniciar > /dev/null 2>&1
cat > "$CAIXA8/popular-sem-perda.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();
conexao.prepare('INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)').run('sessao-sem-perda', agora);
conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
  .run('observacao', 1, 'sessao-sem-perda', 1, 0.9, agora);
conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
  .run('observacao', 2, 'sessao-sem-perda', 0, 0.1, agora);
conexao.close();
EOF
node --no-warnings "$CAIXA8/popular-sem-perda.cjs" "$CAIXA8_WIN"

SAIDA_SEM_PERDA=$(RFM_ROOT="$CAIXA8" $MEMORIA utilidade --relatorio 2>&1)
echo "  comando: RFM_ROOT=<caixa sem perda> node scripts/memoria.cjs utilidade --relatorio"
echo "  saida:"
echo "$SAIDA_SEM_PERDA" | sed 's/^/    /'
if echo "$SAIDA_SEM_PERDA" | grep -q "não-servidas que a recência perdeu:"; then
  falhou=$((falhou+1)); echo "  FALHA lista de nao-servidas apareceu sem perda nenhuma"
else
  ok=$((ok+1)); echo "  ok   lista de nao-servidas some quando nao ha perda"
fi

echo
echo "== Tarefa 6: servida substituida pela reconciliacao ainda casa com o id =="

preparar_caixa_utilidade
CAIXA9="$CAIXA_PREP"
CAIXA9_WIN="$CAIXA_PREP_WIN"

cat > "$CAIXA9/fixture-substituida.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const caminhoTranscrito = process.argv[3];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);

// Passada 1: sem nenhuma marca — descobre um id de observacao servida (o
// unico jeito de achar um alvo de verdade eh pontuar contra o fixture).
const r1 = pontuarSessao(conexao, 'sessao-substituida-sem-marca', caminhoTranscrito);
const alvo = conexao.prepare(
  "SELECT ref_id FROM uso_memoria WHERE sessao = ? AND servida = 1 AND origem = 'observacao' LIMIT 1"
).get('sessao-substituida-sem-marca');

if (!alvo) {
  process.stdout.write(JSON.stringify({ erro: 'nenhuma observacao servida encontrada no fixture (nao da para testar a Tarefa 6)' }));
} else {
  // Marca a observacao servida como substituida pela reconciliacao (D3) —
  // a reconciliacao roda ANTES da pontuacao na mesma passada.
  conexao.prepare('UPDATE observacoes SET substituida_por = ? WHERE id = ?').run(999999, alvo.ref_id);

  // Passada 2: MESMO transcrito, sessao DIFERENTE (para nao reaproveitar a
  // linha ja gravada pela passada 1 via INSERT OR REPLACE).
  const r2 = pontuarSessao(conexao, 'sessao-substituida-com-marca', caminhoTranscrito);
  const aindaServida = conexao.prepare(
    "SELECT servida FROM uso_memoria WHERE sessao = ? AND origem = 'observacao' AND ref_id = ?"
  ).get('sessao-substituida-com-marca', alvo.ref_id);

  conexao.close();
  process.stdout.write(JSON.stringify({
    alvoRefId: alvo.ref_id,
    aindaServida: aindaServida ? aindaServida.servida : null,
    servidasSemIdSemMarca: r1.servidasSemId,
    servidasSemIdComMarca: r2.servidasSemId,
  }));
}
EOF
RESULTADO_SUBSTITUIDA=$(node --no-warnings "$CAIXA9/fixture-substituida.cjs" "$CAIXA9_WIN" "$CAIXA9_WIN/transcrito.jsonl" 2>&1)
echo "  comando: RFM_ROOT=<caixa sintetica> node -e \"pontuarSessao(...)\" apos UPDATE observacoes SET substituida_por (secao \"servida substituida pela reconciliacao ainda casa com o id\")"
echo "  saida: $RESULTADO_SUBSTITUIDA"

if echo "$RESULTADO_SUBSTITUIDA" | grep -q '"aindaServida":1' \
  && echo "$RESULTADO_SUBSTITUIDA" | node --no-warnings -e "
    let s='';process.stdin.on('data',d=>s+=d);
    process.stdin.on('end',()=>{
      try {
        const o = JSON.parse(s);
        process.exit(o.servidasSemIdSemMarca === o.servidasSemIdComMarca ? 0 : 1);
      } catch (e) { process.exit(1); }
    });
  "; then
  ok=$((ok+1)); echo "  ok   servida substituida pela reconciliacao ainda casa com o id"
else
  falhou=$((falhou+1)); echo "  FALHA servida substituida pela reconciliacao nao casou com o id: $RESULTADO_SUBSTITUIDA"
fi

echo
echo "== Tarefa 7: teto por passada e servidas_sem_id no log =="

DUBLE_LLM_DIR_T7="$(duble_llm)"

TETO_PONTUAR_VAL=$(node --no-warnings -e "process.stdout.write(String(require('$SRC_WIN/scripts/lib/utilidade.cjs').TETO_PONTUAR))")

preparar_caixa_utilidade
CAIXA10="$CAIXA_PREP"
CAIXA10_WIN="$CAIXA_PREP_WIN"

cat > "$CAIXA10/marcar-teto.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { TETO_PONTUAR } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const total = TETO_PONTUAR + 2;
const insert = conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)');
for (let i = 0; i < total; i++) {
  // processada_em CRESCENTE — a sessao i eh mais antiga quanto menor i, e
  // pontuarSessoesPendentes ordena por processada_em ASC (as mais antigas
  // primeiro entram no lote do teto). Todas as sessoes reusam o MESMO
  // arquivo de transcrito (variacao real seria so custo, o teto so olha
  // quantas sessoes existem, nao o conteudo de cada uma).
  const processadaEm = new Date(Date.now() - (total - i) * 1000).toISOString();
  insert.run('proj-teto', 'sessao-teto-' + String(i).padStart(3, '0'), process.argv[3], 100, 100, processadaEm);
}
conexao.close();
process.stdout.write(String(total));
EOF
TOTAL_MARCADAS=$(node --no-warnings "$CAIXA10/marcar-teto.cjs" "$CAIXA10_WIN" "$CAIXA10_WIN/transcrito.jsonl")

cat > "$CAIXA10/contar-pontuadas.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBancoSomenteLeitura, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBancoSomenteLeitura(caminhoDb);
const row = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria_sessoes WHERE sessao LIKE 'sessao-teto-%'").get();
conexao.close();
process.stdout.write(String(row.c));
EOF

# --- passada 1: deve pontuar exatamente TETO_PONTUAR, deixar 2 pendentes ---
RFM_ROOT="$CAIXA10" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T7/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
got_manutencao_teto1=$?
LOG_TETO="$CAIXA10/manutencao.log"
LINHA_UTILIDADE_T7=$(grep "^.*utilidade: [0-9]" "$LOG_TETO" | tail -1)
echo "  comando: RFM_ROOT=<caixa sintetica com $TOTAL_MARCADAS marcas pendentes (TETO_PONTUAR+2)> node scripts/memoria.cjs manutencao"
echo "  saida (linha utilidade do manutencao.log): $LINHA_UTILIDADE_T7"

N_PONTUADAS_PASSADA1=$(node --no-warnings "$CAIXA10/contar-pontuadas.cjs" "$CAIXA10_WIN")

# --- passada 2: deve completar as 2 restantes ---
RFM_ROOT="$CAIXA10" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T7/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
N_PONTUADAS_PASSADA2=$(node --no-warnings "$CAIXA10/contar-pontuadas.cjs" "$CAIXA10_WIN")

if [ "$got_manutencao_teto1" = "0" ] \
  && [ "$N_PONTUADAS_PASSADA1" = "$TETO_PONTUAR_VAL" ] \
  && echo "$LINHA_UTILIDADE_T7" | grep -q "2 pendente(s) para a proxima" \
  && [ "$N_PONTUADAS_PASSADA2" = "$TOTAL_MARCADAS" ]; then
  ok=$((ok+1)); echo "  ok   passada respeita TETO_PONTUAR e deixa o resto pendente"
else
  falhou=$((falhou+1)); echo "  FALHA passada nao respeitou TETO_PONTUAR: passada1=$N_PONTUADAS_PASSADA1 (esperado $TETO_PONTUAR_VAL), passada2=$N_PONTUADAS_PASSADA2 (esperado $TOTAL_MARCADAS), linha: $LINHA_UTILIDADE_T7"
fi

if echo "$LINHA_UTILIDADE_T7" | grep -Eq "[0-9]+ servida\(s\) sem id"; then
  ok=$((ok+1)); echo "  ok   manutencao.log registra servidas sem id"
else
  falhou=$((falhou+1)); echo "  FALHA manutencao.log nao registrou servidas sem id: $LINHA_UTILIDADE_T7"
fi

echo
echo "== Tarefa 8: denominador da regua so conta sessao com servida =="

CAIXA11="$(novo_sandbox)"
CAIXA11_WIN="$(cygpath -m "$CAIXA11" 2>/dev/null || printf '%s' "$CAIXA11")"
RFM_ROOT="$CAIXA11" $MEMORIA iniciar > /dev/null 2>&1

cat > "$CAIXA11/popular-sem-servida.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();

for (let i = 1; i <= 3; i++) {
  conexao.prepare('INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?, ?)')
    .run(i, 'proj-regua8', 'obs ' + i, agora, 'regua8-' + i);
}

function sessaoComServida(id, servidaNota, naoServidaNota) {
  conexao.prepare('INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)').run(id, agora);
  conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
    .run('observacao', 1, id, 1, servidaNota, agora);
  if (naoServidaNota !== null) {
    conexao.prepare('INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?,?,?,?,?,?)')
      .run('observacao', 2, id, 0, naoServidaNota, agora);
  }
}

function sessaoSemServida(id) {
  // marcada pela manutencao (ex.: transcrito ausente) — entra em
  // uso_memoria_sessoes mas NUNCA tem linha servida=1 em uso_memoria.
  conexao.prepare('INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)').run(id, agora);
}

// 3 sessoes com servida, 1 com perda (mesmo formato da Tarefa 4).
sessaoComServida('sessao8-1', 0.3, 0.9);
sessaoComServida('sessao8-2', 0.8, 0.2);
sessaoComServida('sessao8-3', 0.5, null);

// 3 sessoes marcadas sem transcrito/sem servida — nao podem entrar no denominador.
sessaoSemServida('sessao8-sem-a');
sessaoSemServida('sessao8-sem-b');
sessaoSemServida('sessao8-sem-c');

conexao.close();
EOF
node --no-warnings "$CAIXA11/popular-sem-servida.cjs" "$CAIXA11_WIN"

SAIDA_TAREFA8=$(RFM_ROOT="$CAIXA11" $MEMORIA utilidade --relatorio 2>&1)
echo "  comando: RFM_ROOT=<caixa 3 com servida + 3 sem servida> node scripts/memoria.cjs utilidade --relatorio"
echo "  saida:"
echo "$SAIDA_TAREFA8" | sed 's/^/    /'

if echo "$SAIDA_TAREFA8" | grep -q "régua D9: LIGA o ranking (1 de 3 sessões)" \
  && echo "$SAIDA_TAREFA8" | grep -q "3 sessão(ões) sem servida fora da conta"; then
  ok=$((ok+1)); echo "  ok   sessao sem servida nao entra no denominador da regua"
else
  falhou=$((falhou+1)); echo "  FALHA sessao sem servida entrou no denominador ou linha 'fora da conta' ausente: $SAIDA_TAREFA8"
fi

echo
echo "== Tarefa 9: servida sem id nunca vira nao-servida no contrafactual =="

# --- 9a. cwd em subpasta casa as mesmas servidas — usa o proprio checkout
# deste repositorio como cwd (tem .git de verdade), NUNCA o fixture (que usa
# cwd sintetico de proposito, ver comentario de gerar-banco.cjs) — e a UNICA
# forma de provar que lerProjetoDoTranscrito sobe ate um .git de verdade sem
# depender de onde o repositorio esta checked out. ---
CAIXA12="$(novo_sandbox)"
CAIXA12_WIN="$(cygpath -m "$CAIXA12" 2>/dev/null || printf '%s' "$CAIXA12")"
RFM_ROOT="$CAIXA12" $MEMORIA iniciar > /dev/null 2>&1

cat > "$CAIXA12/fixture-t9-git.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const fs = require('fs');
const SRC_WIN_ARG = process.argv[3];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { lerProjetoDoTranscrito, pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const { formatarObservacao } = require('$SRC_WIN/hooks/lib/memoria-sessao.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);

// Descobre harnessKey/curto para a raiz do repo usando a MESMA funcao sob
// teste, aplicada a um transcrito minimo cujo unico papel e carregar o cwd.
const tmpCwdOnly = process.argv[4];
fs.writeFileSync(tmpCwdOnly, JSON.stringify({ cwd: SRC_WIN_ARG }) + '\n');
const { harnessKey, curto } = lerProjetoDoTranscrito(tmpCwdOnly);

const criadaEm = '2026-01-09T00:00:00.000Z';
const conteudo = 'titulo t9 dinamico\nsubtitulo t9 dinamico termoclimbt9unico';
conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run(harnessKey, conteudo, criadaEm, 'fx-t9-dinamica');

const apelidos = harnessKey && curto && harnessKey !== curto ? { [harnessKey]: curto } : null;
const linhaServida = formatarObservacao({ conteudo, projeto: harnessKey, criada_em: criadaEm }, apelidos);

const additionalContext = [
  '## Memória (corpus residentes)',
  linhaServida,
  '',
  'mais: node scripts/memoria.cjs buscar --texto "<termo>"',
].join('\n');

function transcrito(cwd) {
  return [
    JSON.stringify({ cwd, type: 'attachment', attachment: { hookEvent: 'SessionStart', stdout: JSON.stringify({ hookSpecificOutput: { additionalContext } }) } }),
    JSON.stringify({ cwd, type: 'user', message: { role: 'user', content: 'termoclimbt9unico' } }),
  ].join('\n') + '\n';
}

const caminhoRaiz = process.argv[5];
const caminhoSubpasta = process.argv[6];
fs.writeFileSync(caminhoRaiz, transcrito(SRC_WIN_ARG));
fs.writeFileSync(caminhoSubpasta, transcrito(SRC_WIN_ARG + '/scripts'));

const r1 = pontuarSessao(conexao, 'sessao-t9-raiz', caminhoRaiz);
const idsRaiz = conexao.prepare("SELECT ref_id FROM uso_memoria WHERE sessao = 'sessao-t9-raiz' AND servida = 1 AND origem = 'observacao' ORDER BY ref_id").all().map((r) => r.ref_id);
const r2 = pontuarSessao(conexao, 'sessao-t9-subpasta', caminhoSubpasta);
const idsSubpasta = conexao.prepare("SELECT ref_id FROM uso_memoria WHERE sessao = 'sessao-t9-subpasta' AND servida = 1 AND origem = 'observacao' ORDER BY ref_id").all().map((r) => r.ref_id);

conexao.close();
process.stdout.write(JSON.stringify({
  servidasComIdRaiz: r1.servidasComId,
  servidasComIdSubpasta: r2.servidasComId,
  idsIguais: JSON.stringify(idsRaiz) === JSON.stringify(idsSubpasta) && idsRaiz.length > 0,
}));
EOF
RESULTADO_T9_GIT=$(node --no-warnings "$CAIXA12/fixture-t9-git.cjs" "$CAIXA12_WIN" "$SRC_WIN" "$CAIXA12_WIN/cwd-only.jsonl" "$CAIXA12_WIN/raiz.jsonl" "$CAIXA12_WIN/subpasta.jsonl" 2>&1)
echo "  comando: node -e \"pontuarSessao com cwd = raiz deste checkout e cwd = <raiz>/scripts (subida real ate o .git)\" (secao \"cwd em subpasta casa as mesmas servidas\")"
echo "  saida: $RESULTADO_T9_GIT"

if echo "$RESULTADO_T9_GIT" | grep -q '"idsIguais":true' \
  && echo "$RESULTADO_T9_GIT" | grep -q '"servidasComIdRaiz":1' \
  && echo "$RESULTADO_T9_GIT" | grep -q '"servidasComIdSubpasta":1'; then
  ok=$((ok+1)); echo "  ok   cwd em subpasta casa as mesmas servidas"
else
  falhou=$((falhou+1)); echo "  FALHA cwd em subpasta nao casou as mesmas servidas: $RESULTADO_T9_GIT"
fi

# --- 9b. servida sem id nao reaparece como nao-servida — rotulo de projeto
# forcado (bogus), usando o fixture versionado com o cwd trocado. ---
preparar_caixa_utilidade
CAIXA13="$CAIXA_PREP"
CAIXA13_WIN="$CAIXA_PREP_WIN"

cat > "$CAIXA13/preparar-bogus.cjs" <<EOF
const fs = require('fs');
const { CWD_FIXTURE_BOGUS } = require('$SRC_WIN/scripts/fixtures/utilidade/gerar-banco.cjs');
const linhas = fs.readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean);
const out = linhas.map((l) => { const o = JSON.parse(l); o.cwd = CWD_FIXTURE_BOGUS; return JSON.stringify(o); });
fs.writeFileSync(process.argv[3], out.join('\n') + '\n');
EOF
node --no-warnings "$CAIXA13/preparar-bogus.cjs" "$CAIXA13_WIN/transcrito.jsonl" "$CAIXA13_WIN/transcrito-bogus.jsonl"

cat > "$CAIXA13/fixture-t9.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const caminhoOriginal = process.argv[3];
const caminhoBogus = process.argv[4];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);

// 1) cwd original (do fixture) — baseline: todas as 5 servidas casam por id.
const r1 = pontuarSessao(conexao, 'sessao-t9-original', caminhoOriginal);
const idsOriginal = conexao.prepare(
  "SELECT ref_id FROM uso_memoria WHERE sessao = 'sessao-t9-original' AND servida = 1 AND origem = 'observacao' ORDER BY ref_id"
).all().map((r) => r.ref_id);

// 2) rotulo de projeto bogus (sem .git ancestral) — acharAlvo so acha por id
// a servida gravada com o rotulo curto direto ('outro-proj'), que nenhum
// apelido traduz; as demais (gravadas com o harnessKey do projeto proprio)
// ficam "servida sem id". A defesa por conteudo (semPrefixo) tem que impedir
// que as 4 originais reapareçam como servida=0 (contrafactual) sob o rotulo
// bogus.
const r3 = pontuarSessao(conexao, 'sessao-t9-bogus', caminhoBogus);
const idsOriginalSql = idsOriginal.length ? idsOriginal.join(',') : '-1';
const vazamento = conexao.prepare(
  \`SELECT COUNT(*) c FROM uso_memoria WHERE sessao = ? AND servida = 0 AND origem = 'observacao' AND ref_id IN (\${idsOriginalSql})\`
).get('sessao-t9-bogus').c;

conexao.close();
process.stdout.write(JSON.stringify({
  servidasComIdOriginal: r1.servidasComId,
  servidasComIdBogus: r3.servidasComId,
  servidasSemIdBogus: r3.servidasSemId,
  vazamento,
}));
EOF
RESULTADO_T9=$(node --no-warnings "$CAIXA13/fixture-t9.cjs" "$CAIXA13_WIN" "$CAIXA13_WIN/transcrito.jsonl" "$CAIXA13_WIN/transcrito-bogus.jsonl" 2>&1)
echo "  comando: RFM_ROOT=<caixa sintetica> node -e \"pontuarSessao com cwd original e rotulo bogus\" (secao \"servida sem id nao reaparece como nao-servida\")"
echo "  saida: $RESULTADO_T9"

SERVIDAS_COM_ID_ORIGINAL_T9=$(printf '%s' "$RESULTADO_T9" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasComIdOriginal))}catch(e){process.stdout.write('ERRO')}})")
SERVIDAS_COM_ID_BOGUS_T9=$(printf '%s' "$RESULTADO_T9" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasComIdBogus))}catch(e){process.stdout.write('ERRO')}})")
SERVIDAS_SEM_ID_BOGUS_T9=$(printf '%s' "$RESULTADO_T9" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasSemIdBogus))}catch(e){process.stdout.write('ERRO')}})")

# Defesa sintética e determinística, independente do fixture: colisão
# FORÇADA (mesmo id, mesmo conteúdo, termo raro escolhido a dedo) chamando
# `buscarContrafactual` DIRETO — o chamador real dentro de `pontuarSessao`
# (mesma assinatura, mesmos 4 argumentos), só que com `jaServidos` vazio para
# simular exatamente o caso "servida sem id": a defesa por `textosServidos` é
# a ÚNICA coisa que pode barrar o vazamento.
CAIXA13B="$(novo_sandbox)"
CAIXA13B_WIN="$(cygpath -m "$CAIXA13B" 2>/dev/null || printf '%s' "$CAIXA13B")"
RFM_ROOT="$CAIXA13B" $MEMORIA iniciar > /dev/null 2>&1

cat > "$CAIXA13B/fixture-t9-sintetico.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { buscarContrafactual } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const { formatarObservacao } = require('$SRC_WIN/hooks/lib/memoria-sessao.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const agora = new Date().toISOString();

conexao.prepare('INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?, ?)')
  .run(777, 'proj-t9', 'titulo termoexclusivot9 — subtitulo com termoexclusivot9 no conteudo', agora, 'fixture-t9-contra');

const row = conexao.prepare('SELECT id, conteudo, projeto, criada_em FROM observacoes WHERE id = 777').get();
// MESMA formatação que buscarContrafactual aplica ao candidato internamente
// — semPrefixo é só o regex do prefixo de data/projeto, sem depender de
// nenhuma função interna do módulo sob teste.
const linha = formatarObservacao(row, null);
const semPrefixoLocal = linha.replace(/^\[[^\]]*\]\s*/, '');
const textosServidos = new Set([semPrefixoLocal]);

// jaServidos VAZIO — simula "servida sem id": nada exclui o candidato 777
// por id, só a defesa por conteúdo pode barrá-lo.
const texto = 'a sessao usou termoexclusivot9 em algum lugar do texto';
const resultado = buscarContrafactual(conexao, texto, new Set(), textosServidos);

conexao.close();
process.stdout.write(JSON.stringify({ apareceu: resultado.some((r) => r.id === 777) }));
EOF
RESULTADO_T9_SINTETICO=$(node --no-warnings "$CAIXA13B/fixture-t9-sintetico.cjs" "$CAIXA13B_WIN" 2>&1)
echo "  comando: node -e \"buscarContrafactual(conexao, texto, new Set(), textosServidos)\" com jaServidos vazio (secao \"servida sem id nao reaparece como nao-servida\")"
echo "  saida: $RESULTADO_T9_SINTETICO"

if [ "$SERVIDAS_COM_ID_BOGUS_T9" != "ERRO" ] && [ "$SERVIDAS_COM_ID_ORIGINAL_T9" != "ERRO" ] \
  && [ "$SERVIDAS_COM_ID_BOGUS_T9" -lt "$SERVIDAS_COM_ID_ORIGINAL_T9" ] \
  && echo "$RESULTADO_T9" | grep -q '"vazamento":0' \
  && [ "$SERVIDAS_SEM_ID_BOGUS_T9" != "0" ] && [ "$SERVIDAS_SEM_ID_BOGUS_T9" != "ERRO" ] \
  && echo "$RESULTADO_T9_SINTETICO" | grep -q '"apareceu":false'; then
  ok=$((ok+1)); echo "  ok   servida sem id nao reaparece como nao-servida"
else
  falhou=$((falhou+1)); echo "  FALHA servida sem id reapareceu como nao-servida: real=$RESULTADO_T9 sintetico=$RESULTADO_T9_SINTETICO"
fi

echo
echo "== Tarefa 10: sessao que falha e marcada e a fila anda =="

DUBLE_LLM_DIR_T10="$(duble_llm)"

TETO_PONTUAR_VAL_T10=$(node --no-warnings -e "process.stdout.write(String(require('$SRC_WIN/scripts/lib/utilidade.cjs').TETO_PONTUAR))")

preparar_caixa_utilidade
CAIXA14="$CAIXA_PREP"
CAIXA14_WIN="$CAIXA_PREP_WIN"
mv "$CAIXA14/transcrito.jsonl" "$CAIXA14/transcrito-valido.jsonl"
# Transcrito quebrado: um DIRETORIO no lugar do arquivo. fs.existsSync()
# (que pontuarSessoesPendentes usa para decidir "tem transcrito") enxerga
# um diretorio como existente; fs.readFileSync() dentro de extrairSessao
# entao lanca EISDIR — throw real e reproduzivel. JSON truncado dentro de
# uma linha (o exemplo do plano) NAO lanca: a Tarefa 1 ja blinda esse caso
# com try/catch por linha (linha corrompida vira "sem servida", nao throw).
mkdir -p "$CAIXA14/transcrito-quebrado.jsonl"

cat > "$CAIXA14/marcar-t10.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { TETO_PONTUAR } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
const insert = conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)');
const agora = Date.now();
// TETO_PONTUAR sessoes QUEBRADAS, as mais antigas — entram inteiras no lote.
for (let i = 0; i < TETO_PONTUAR; i++) {
  const processadaEm = new Date(agora - (TETO_PONTUAR + 2 - i) * 1000).toISOString();
  insert.run('proj-t10', 'sessao-t10-quebrada-' + String(i).padStart(3, '0'), process.argv[3], 100, 100, processadaEm);
}
// 2 sessoes VALIDAS, mais novas — ficam pendentes para a passada seguinte.
insert.run('proj-t10', 'sessao-t10-valida-a', process.argv[4], 100, 100, new Date(agora - 2000).toISOString());
insert.run('proj-t10', 'sessao-t10-valida-b', process.argv[4], 100, 100, new Date(agora - 1000).toISOString());
conexao.close();
EOF
node --no-warnings "$CAIXA14/marcar-t10.cjs" "$CAIXA14_WIN" "$CAIXA14_WIN/transcrito-quebrado.jsonl" "$CAIXA14_WIN/transcrito-valido.jsonl"

cat > "$CAIXA14/conferir-t10.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBancoSomenteLeitura, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBancoSomenteLeitura(caminhoDb);
const quebradas = conexao.prepare("SELECT COUNT(*) c FROM uso_memoria_sessoes WHERE sessao LIKE 'sessao-t10-quebrada-%'").get().c;
const validas = conexao.prepare("SELECT sessao FROM uso_memoria_sessoes WHERE sessao IN ('sessao-t10-valida-a','sessao-t10-valida-b')").all().length;
conexao.close();
process.stdout.write(JSON.stringify({ quebradas, validas }));
EOF

# --- passada 1: as TETO_PONTUAR quebradas falham e sao marcadas; as 2 validas ficam pendentes ---
RFM_ROOT="$CAIXA14" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T10/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
got_manutencao_t10_1=$?
LOG_T10="$CAIXA14/manutencao.log"
LINHA_UTILIDADE_T10_1=$(grep "^.*utilidade: [0-9]" "$LOG_T10" | tail -1)
echo "  comando: RFM_ROOT=<caixa sintetica com $TETO_PONTUAR_VAL_T10 sessoes quebradas (diretorio no lugar do transcrito) + 2 validas> node scripts/memoria.cjs manutencao"
echo "  saida (linha utilidade do manutencao.log, 1a passada): $LINHA_UTILIDADE_T10_1"

CONFERE_PASSADA1_T10=$(node --no-warnings "$CAIXA14/conferir-t10.cjs" "$CAIXA14_WIN")
echo "  saida (uso_memoria_sessoes apos 1a passada): $CONFERE_PASSADA1_T10"

# --- passada 2: fila anda — as 2 validas sao pontuadas agora ---
RFM_ROOT="$CAIXA14" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR_T10/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
got_manutencao_t10_2=$?
CONFERE_PASSADA2_T10=$(node --no-warnings "$CAIXA14/conferir-t10.cjs" "$CAIXA14_WIN")
echo "  saida (uso_memoria_sessoes apos 2a passada): $CONFERE_PASSADA2_T10"

if [ "$got_manutencao_t10_1" = "0" ] && [ "$got_manutencao_t10_2" = "0" ] \
  && echo "$LINHA_UTILIDADE_T10_1" | grep -q "${TETO_PONTUAR_VAL_T10} falharam" \
  && echo "$LINHA_UTILIDADE_T10_1" | grep -q "utilidade: 0 sessao(oes) pontuada(s)" \
  && echo "$CONFERE_PASSADA1_T10" | grep -q "\"quebradas\":${TETO_PONTUAR_VAL_T10}" \
  && echo "$CONFERE_PASSADA1_T10" | grep -q '"validas":0' \
  && echo "$CONFERE_PASSADA2_T10" | grep -q '"validas":2'; then
  ok=$((ok+1)); echo "  ok   sessao que falha e marcada e a fila anda"
else
  falhou=$((falhou+1)); echo "  FALHA sessao que falha nao foi marcada ou a fila nao andou: passada1=$CONFERE_PASSADA1_T10 linha1=$LINHA_UTILIDADE_T10_1 passada2=$CONFERE_PASSADA2_T10"
fi

echo
echo "== Tarefa 11: banco ocupado adia a sessao sem marcar nem gravar parcial =="

preparar_caixa_utilidade
CAIXA15="$CAIXA_PREP"
CAIXA15_WIN="$CAIXA_PREP_WIN"

# Uma sessao pendente na marca_dagua apontando para o transcrito fixture.
# Uma SEGUNDA conexao DatabaseSync no MESMO arquivo segura BEGIN IMMEDIATE
# (o lock de escrita) antes da conexao principal tentar pontuar — e' o
# mesmo mecanismo que uma escrita concorrente de outra sessao (ex.:
# memoria-marca.cjs no Stop/SessionEnd de outra janela) produziria. Tudo
# num processo so, para poder segurar a trava, chamar
# pontuarSessoesPendentes, conferir o estado, soltar a trava (ROLLBACK) e
# chamar de novo, sem reabrir processo entre os passos.
cat > "$CAIXA15/fixture-t11.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessoesPendentes } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const { DatabaseSync } = require('node:sqlite');

const caminhoTranscrito = process.argv[3];
const { caminhoDb } = resolverCaminhos();

const setup = abrirBanco(caminhoDb);
setup.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-t11', 'sessao-t11-ocupado', caminhoTranscrito, 100, 100, new Date().toISOString());
setup.close();

// Segunda conexao: segura o lock de escrita ANTES da principal tentar pontuar.
const locker = new DatabaseSync(caminhoDb);
locker.exec('PRAGMA journal_mode = WAL;');
locker.exec('BEGIN IMMEDIATE');

const principal = abrirBanco(caminhoDb);
const resultado1 = pontuarSessoesPendentes(principal);
const emSessoesTabela1 = principal.prepare("SELECT COUNT(*) c FROM uso_memoria_sessoes WHERE sessao = 'sessao-t11-ocupado'").get().c;
const linhasUsoMemoria1 = principal.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = 'sessao-t11-ocupado'").get().c;
principal.close();

// Solta a trava: a sessao volta a ficar pontuavel na proxima chamada.
locker.exec('ROLLBACK');
locker.close();

const principal2 = abrirBanco(caminhoDb);
const resultado2 = pontuarSessoesPendentes(principal2);
const emSessoesTabela2 = principal2.prepare("SELECT COUNT(*) c FROM uso_memoria_sessoes WHERE sessao = 'sessao-t11-ocupado'").get().c;
const servidasLinhas2 = principal2.prepare("SELECT COUNT(*) c FROM uso_memoria WHERE sessao = 'sessao-t11-ocupado' AND servida = 1").get().c;
principal2.close();

process.stdout.write(JSON.stringify({
  adiadas1: resultado1.adiadas,
  falharam1: resultado1.falharam,
  pontuadas1: resultado1.pontuadas,
  emSessoesTabela1,
  linhasUsoMemoria1,
  pontuadas2: resultado2.pontuadas,
  emSessoesTabela2,
  servidasLinhas2,
}));
EOF
RESULTADO_T11=$(node --no-warnings "$CAIXA15/fixture-t11.cjs" "$CAIXA15_WIN" "$CAIXA15_WIN/transcrito.jsonl" 2>&1)
echo "  comando: RFM_ROOT=<caixa sintetica> node -e \"segunda conexao com BEGIN IMMEDIATE ativo + pontuarSessoesPendentes(conexaoPrincipal)\" (secao \"banco ocupado adia a sessao sem marcar nem gravar parcial\")"
echo "  saida: $RESULTADO_T11"

SERVIDAS_LINHAS2_T11=$(printf '%s' "$RESULTADO_T11" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasLinhas2))}catch(e){process.stdout.write('ERRO')}})")

if echo "$RESULTADO_T11" | grep -q '"adiadas1":1' \
  && echo "$RESULTADO_T11" | grep -q '"falharam1":0' \
  && echo "$RESULTADO_T11" | grep -q '"pontuadas1":0' \
  && echo "$RESULTADO_T11" | grep -q '"emSessoesTabela1":0' \
  && echo "$RESULTADO_T11" | grep -q '"linhasUsoMemoria1":0' \
  && echo "$RESULTADO_T11" | grep -q '"pontuadas2":1' \
  && echo "$RESULTADO_T11" | grep -q '"emSessoesTabela2":1' \
  && [ "$SERVIDAS_LINHAS2_T11" != "0" ] && [ "$SERVIDAS_LINHAS2_T11" != "ERRO" ]; then
  ok=$((ok+1)); echo "  ok   banco ocupado adia a sessao sem marcar nem gravar parcial"
else
  falhou=$((falhou+1)); echo "  FALHA banco ocupado nao adiou corretamente: $RESULTADO_T11"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
