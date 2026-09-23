#!/bin/bash
# Bateria de scripts/lib/utilidade.cjs — sinal de utilidade da memória.
# Design: docs/rainforest/design/2026-09-23-memoria-sinal-de-utilidade.md
# Plano:  docs/rainforest/planos/2026-09-23-memoria-sinal-de-utilidade.md
# Uso: bash scripts/testa-utilidade.sh
#
# O que esta bateria prova, nesta ordem:
#   1. Extrator (Tarefa 1): contra um TRANSCRITO REAL desta máquina, `utilidade
#      --extrair` devolve o mesmo número de servidas que uma contagem
#      independente (outra leitura do arquivo, sem chamar o módulo sob
#      teste); e a prosa do assistente que ecoa a injeção nunca entra no texto.
#   2. Pontuação (Tarefa 2): contra uma CÓPIA do rainforest.db real + o mesmo
#      transcrito real, `pontuarSessao` grava as servidas e o contrafactual,
#      idempotente, sem coluna de texto de sessão em `uso_memoria`; e um termo
#      comum ao corpus (frequência de documento alta) não pontua sozinho.
#   3. Manutenção (Tarefa 3): `manutencao` pontua as sessões pendentes da
#      `marca_dagua`, e transcrito apagado não derruba reconciliar/consolidar.
#   4. Relatório (Tarefa 4): a régua D9 liga com 1/3, não liga com 1/4, e lista
#      as não-servidas que motivaram a decisão só quando há perda.
#
# Hermética por padrão (mktemp -d + RFM_ROOT) — SALVO as seções 1a e 2a, que
# leem CÓPIAS do transcrito real e do rainforest.db real desta máquina (nunca
# escrevem neles) porque o próprio "pronto quando" do plano exige medir
# contra dado real, não sintético. Se a máquina não tiver banco/transcrito
# reais, a bateria REPORTA a ausência e conta como falha — não finge sucesso.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Forma Windows do caminho — heredocs abaixo viram arquivos .cjs que o NODE
# resolve via require(); require() não passa pela tradução de argv do MSYS
# (essa tradução só se aplica a argumentos passados na hora do spawn, nunca a
# um caminho gravado DENTRO do conteúdo de um arquivo). Um require('$SRC/...')
# com o `$SRC` em forma POSIX (`/c/Projetos/...`) falha com MODULE_NOT_FOUND —
# medido nesta bateria antes deste comentário existir.
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

MEMORIA="node $SRC/scripts/memoria.cjs"
ok=0; falhou=0

echo "== Tarefa 1: extrator do transcrito (servidas/texto) =="

# --- 1a. transcrito real desta máquina ---
TRANSCRITO_REAL=""
for f in $(ls -t "$HOME/.claude-personal/projects/C--Projetos-rainforest-mind/"*.jsonl 2>/dev/null); do
  if grep -q "corpus residentes" "$f" 2>/dev/null; then
    TRANSCRITO_REAL="$f"
    break
  fi
done

if [ -z "$TRANSCRITO_REAL" ]; then
  falhou=$((falhou+1))
  echo "  FALHA nao achei transcrito real com 'corpus residentes' em ~/.claude-personal/projects/C--Projetos-rainforest-mind/"
else
  CAIXA1="$(novo_sandbox)"
  cp "$TRANSCRITO_REAL" "$CAIXA1/transcrito.jsonl"

  SAIDA_EXTRAIR=$($MEMORIA utilidade --extrair "$CAIXA1/transcrito.jsonl" 2>&1)
  echo "  comando: node scripts/memoria.cjs utilidade --extrair <transcrito real copiado>"
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

  if [ "$N_EXTRAIDO" = "$CONTAGEM_INDEPENDENTE" ] && [ "$N_EXTRAIDO" != "ERRO" ]; then
    ok=$((ok+1)); echo "  ok   servidas do transcrito real = $N_EXTRAIDO (contagem independente = $CONTAGEM_INDEPENDENTE)"
  else
    falhou=$((falhou+1)); echo "  FALHA servidas do transcrito real = $N_EXTRAIDO, contagem independente = $CONTAGEM_INDEPENDENTE"
  fi
fi

# --- 1b. fixture da mutação: prosa do assistente que ecoa a injecao nao entra no texto ---
CAIXA2="$(novo_sandbox)"
cat > "$CAIXA2/fixture-prosa.cjs" <<'EOF'
// Fixture da Tarefa 1 (mutacao): transcrito sintético com um attachment de
// SessionStart (2 servidas), um prompt do usuário, uma prosa do assistente
// (deve ficar de FORA do texto) e um tool_use (deve ENTRAR no texto).
const fs = require('fs');
const destino = process.argv[2];

const additionalContext = [
  '## Memória (corpus residentes)',
  '[2026-01-01 (proj)] titulo um — sub um',
  '[2026-01-02 (proj)] titulo dois — sub dois',
  '',
  'mais: node scripts/memoria.cjs buscar --texto "<termo>"',
].join('\n');

const linhas = [];
linhas.push(JSON.stringify({
  type: 'attachment',
  cwd: 'C:\\Projetos\\fixture-proj',
  attachment: {
    hookEvent: 'SessionStart',
    stdout: JSON.stringify({ hookSpecificOutput: { additionalContext } }),
  },
}));
linhas.push(JSON.stringify({
  type: 'user',
  cwd: 'C:\\Projetos\\fixture-proj',
  message: { role: 'user', content: 'prompt do usuario com o termo MARCADORPROMPTUNICO' },
}));
linhas.push(JSON.stringify({
  type: 'assistant',
  cwd: 'C:\\Projetos\\fixture-proj',
  message: {
    role: 'assistant',
    content: [{ type: 'text', text: 'prosa do assistente com o termo MARCADORPROSAUNICO que ecoa a injecao' }],
  },
}));
linhas.push(JSON.stringify({
  type: 'assistant',
  cwd: 'C:\\Projetos\\fixture-proj',
  message: {
    role: 'assistant',
    content: [{ type: 'tool_use', id: 't1', name: 'Bash', input: { command: 'echo MARCADORFERRAMENTAUNICO' } }],
  },
}));
linhas.push(JSON.stringify({
  type: 'user',
  cwd: 'C:\\Projetos\\fixture-proj',
  message: {
    role: 'user',
    content: [{ type: 'tool_result', tool_use_id: 't1', content: 'MARCADORRESULTADOUNICO' }],
  },
}));

fs.writeFileSync(destino, linhas.join('\n') + '\n');
EOF
node --no-warnings "$CAIXA2/fixture-prosa.cjs" "$CAIXA2/transcrito.jsonl"

cat > "$CAIXA2/checar-fixture.cjs" <<EOF
const { extrairSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');
const r = extrairSessao(process.argv[2]);
const temPrompt = r.texto.includes('MARCADORPROMPTUNICO');
const temFerramenta = r.texto.includes('MARCADORFERRAMENTAUNICO');
const temProsa = r.texto.includes('MARCADORPROSAUNICO');
const temResultado = r.texto.includes('MARCADORRESULTADOUNICO');
process.stdout.write(JSON.stringify({ servidas: r.servidas.length, temPrompt, temFerramenta, temProsa, temResultado }));
EOF
RESULTADO_FIXTURE=$(node --no-warnings "$CAIXA2/checar-fixture.cjs" "$CAIXA2/transcrito.jsonl")
echo "  comando: node -e \"extrairSessao(<fixture>)\" (secao \"prosa do assistente que ecoa a injecao nao entra no texto\")"
echo "  saida: $RESULTADO_FIXTURE"
if echo "$RESULTADO_FIXTURE" | grep -q '"servidas":2' \
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

# --- 2a/2b. banco real (copia) + transcrito real ---
if [ -z "$TRANSCRITO_REAL" ]; then
  falhou=$((falhou+1)); echo "  FALHA sem transcrito real, pulando 2a/2b"
elif [ ! -f "$HOME/.rainforest/rainforest.db" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei $HOME/.rainforest/rainforest.db (banco real) para copiar"
else
  CAIXA3="$(novo_sandbox)"
  cp "$HOME/.rainforest/rainforest.db" "$CAIXA3/rainforest.db"
  cp "$TRANSCRITO_REAL" "$CAIXA3/transcrito.jsonl"
  CAIXA3_WIN="$(cygpath -m "$CAIXA3" 2>/dev/null || printf '%s' "$CAIXA3")"

  cat > "$CAIXA3/pontuar-real.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const caminhoTranscrito = process.argv[3];
const { abrirBanco, criarSchema, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
criarSchema(conexao);

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
  echo "  comando: RFM_ROOT=<copia> node -e \"pontuarSessao(conexao, sessao, <transcrito real copiado>)\""
  echo "  saida: $RESULTADO_PONTUACAO"

  S_SERVIDAS=$(printf '%s' "$RESULTADO_PONTUACAO" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.servidasEsperadasEmUso))}catch(e){process.stdout.write('ERRO')}})")
  C_CONTRA=$(printf '%s' "$RESULTADO_PONTUACAO" | node --no-warnings -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{const o=JSON.parse(s);process.stdout.write(String(o.contrafactualEmUso))}catch(e){process.stdout.write('ERRO')}})")

  if echo "$RESULTADO_PONTUACAO" | grep -q '"foraDeFaixa":0' \
    && echo "$RESULTADO_PONTUACAO" | grep -q '"idempotenteServida":true' \
    && echo "$RESULTADO_PONTUACAO" | grep -q '"idempotenteContra":true' \
    && [ "$S_SERVIDAS" != "ERRO" ] && [ "$C_CONTRA" != "ERRO" ]; then
    ok=$((ok+1)); echo "  ok   pontuacao real: $S_SERVIDAS servidas + $C_CONTRA contrafactual, idempotente"
  else
    falhou=$((falhou+1)); echo "  FALHA pontuacao real nao bateu: $RESULTADO_PONTUACAO"
  fi

  if echo "$RESULTADO_PONTUACAO" | grep -q '"colunas":\["nota","origem","pontuada_em","ref_id","servida","sessao"\]'; then
    ok=$((ok+1)); echo "  ok   nenhuma coluna de texto em uso_memoria"
  else
    falhou=$((falhou+1)); echo "  FALHA colunas de uso_memoria fora do esperado (D10): $RESULTADO_PONTUACAO"
  fi
fi

# --- 2c. fixture da mutacao: termo comum a todo o corpus nao pontua ---
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

if [ -z "$TRANSCRITO_REAL" ] || [ ! -f "$HOME/.rainforest/rainforest.db" ]; then
  falhou=$((falhou+1)); echo "  FALHA sem transcrito/banco real, pulando Tarefa 3"
else
  # Dublê de LLM: reconciliar/consolidar (chamados por `manutencao` ANTES do
  # passo de utilidade) nunca devem spawnar o `claude` real nesta bateria —
  # o banco copiado é o real, com centenas de observações pendentes.
  DUBLE_LLM_DIR="$(novo_sandbox)"
  cat > "$DUBLE_LLM_DIR/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return '{"acao":"store","alvo_id":null}';
}
module.exports = { chamarLLM };
EOF

  CAIXA5="$(novo_sandbox)"
  CAIXA5_WIN="$(cygpath -m "$CAIXA5" 2>/dev/null || printf '%s' "$CAIXA5")"
  cp "$HOME/.rainforest/rainforest.db" "$CAIXA5/rainforest.db"
  cp "$TRANSCRITO_REAL" "$CAIXA5/transcrito-a.jsonl"
  cp "$TRANSCRITO_REAL" "$CAIXA5/transcrito-b.jsonl"

  cat > "$CAIXA5/marcar.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, criarSchema, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
criarSchema(conexao);
const agora = new Date().toISOString();
// Limpa a marca_dagua HERDADA do banco real copiado — sem isto,
// pontuarSessoesPendentes tentaria processar dezenas de sessoes reais, e a
// contagem "2 pontuadas" deste teste nao bateria.
conexao.exec('DELETE FROM marca_dagua');
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-manutencao-a', process.argv[3], 100, 100, agora);
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-manutencao-b', process.argv[4], 100, 100, agora);
conexao.close();
EOF
  node --no-warnings "$CAIXA5/marcar.cjs" "$CAIXA5_WIN" "$CAIXA5_WIN/transcrito-a.jsonl" "$CAIXA5_WIN/transcrito-b.jsonl"

  RFM_ROOT="$CAIXA5" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
  got_manutencao=$?
  LOG_MANUTENCAO="$CAIXA5/manutencao.log"
  echo "  comando: RFM_ROOT=<copia com 2 marcas pendentes> node scripts/memoria.cjs manutencao"
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
  CAIXA6="$(novo_sandbox)"
  CAIXA6_WIN="$(cygpath -m "$CAIXA6" 2>/dev/null || printf '%s' "$CAIXA6")"
  cp "$HOME/.rainforest/rainforest.db" "$CAIXA6/rainforest.db"
  cp "$TRANSCRITO_REAL" "$CAIXA6/transcrito-existe.jsonl"
  # transcrito-sumiu.jsonl e apontado na marca_dagua mas NUNCA criado.

  cat > "$CAIXA6/marcar2.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const { abrirBanco, criarSchema, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
criarSchema(conexao);
const agora = new Date().toISOString();
conexao.exec('DELETE FROM marca_dagua');
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-existe', process.argv[3], 100, 100, agora);
conexao.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-manutencao', 'sessao-sumiu', process.argv[4], 100, 100, agora);
conexao.close();
EOF
  node --no-warnings "$CAIXA6/marcar2.cjs" "$CAIXA6_WIN" "$CAIXA6_WIN/transcrito-existe.jsonl" "$CAIXA6_WIN/transcrito-sumiu.jsonl"

  RFM_ROOT="$CAIXA6" TESTADOR_CHAMAR_LLM="$DUBLE_LLM_DIR/dubleLLM.cjs" $MEMORIA manutencao > /dev/null 2>&1
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
fi

echo
echo "== Tarefa 4: relatorio com a regua D9 =="

# --- 4a. LIGA com 1 de 3 ---
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

if [ -z "$TRANSCRITO_REAL" ] || [ ! -f "$HOME/.rainforest/rainforest.db" ]; then
  falhou=$((falhou+1)); echo "  FALHA sem transcrito/banco real, pulando Tarefa 6"
else
  CAIXA9="$(novo_sandbox)"
  CAIXA9_WIN="$(cygpath -m "$CAIXA9" 2>/dev/null || printf '%s' "$CAIXA9")"
  cp "$HOME/.rainforest/rainforest.db" "$CAIXA9/rainforest.db"
  cp "$TRANSCRITO_REAL" "$CAIXA9/transcrito.jsonl"

  cat > "$CAIXA9/fixture-substituida.cjs" <<EOF
process.env.RFM_ROOT = process.argv[2];
const caminhoTranscrito = process.argv[3];
const { abrirBanco, criarSchema, resolverCaminhos } = require('$SRC_WIN/scripts/memoria.cjs');
const { pontuarSessao } = require('$SRC_WIN/scripts/lib/utilidade.cjs');

const { caminhoDb } = resolverCaminhos();
const conexao = abrirBanco(caminhoDb);
criarSchema(conexao);

// Passada 1: sem nenhuma marca — descobre um id de observacao servida (o
// unico jeito de achar um alvo de verdade eh pontuar contra o transcrito real).
const r1 = pontuarSessao(conexao, 'sessao-substituida-sem-marca', caminhoTranscrito);
const alvo = conexao.prepare(
  "SELECT ref_id FROM uso_memoria WHERE sessao = ? AND servida = 1 AND origem = 'observacao' LIMIT 1"
).get('sessao-substituida-sem-marca');

if (!alvo) {
  process.stdout.write(JSON.stringify({ erro: 'nenhuma observacao servida encontrada no transcrito real (nao da para testar a Tarefa 6)' }));
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
  echo "  comando: RFM_ROOT=<copia> node -e \"pontuarSessao(...)\" apos UPDATE observacoes SET substituida_por (secao \"servida substituida pela reconciliacao ainda casa com o id\")"
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
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
