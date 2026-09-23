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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
