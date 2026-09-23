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
#
# Hermética por padrão (mktemp -d + RFM_ROOT) — SALVO a seção 1a, que lê uma
# CÓPIA do transcrito real desta máquina (nunca escreve nele) porque o próprio
# "pronto quando" do plano exige medir contra dado real, não sintético. Se a
# máquina não tiver transcrito real com o bloco de memória, a bateria REPORTA
# a ausência e conta como falha — não finge sucesso.

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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
