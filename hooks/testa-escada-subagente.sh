#!/bin/bash
# Bateria do hook/escada-subagente.cjs — injeção de escada YAGNI em SubagentStart.
#
# O que esta bateria precisa provar, nesta ordem de importância:
#   1. que o hook roda e emite JSON válido com a estrutura SubagentStart;
#   2. que o additionalContext contém todos os 7 degraus da escada;
#   3. que a escada é extraída de modo-dev/SKILL.md, não duplicada no .cjs;
#   4. que o JSON é necessário — texto cru no stdout seria descartado;
#   5. degradação graciosa: arquivo ausente não trava o hook.
#
# A última seção é MUTAÇÃO: remove a estrutura JSON e exige que a bateria falhe.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/escada-subagente.cjs"
SKILL="$SRC/skills/modo-dev/SKILL.md"

# Raiz temporária para testes de extração (com arquivo modificado)
RAIZ_TESTE_POSIX="$(mktemp -d)"
RAIZ_TESTE="$(cygpath -m "$RAIZ_TESTE_POSIX" 2>/dev/null || printf '%s' "$RAIZ_TESTE_POSIX")"
trap 'rm -rf "$RAIZ_TESTE_POSIX"' EXIT
echo "(caixa de areia: $RAIZ_TESTE)"

ok=0; falhou=0

checa() { # nome, modo(tem|nao_tem), padrao, saida
  local nome="$1" modo="$2" pad="$3" saida="$4"
  if echo "$saida" | grep -qF "$pad"; then achou=1; else achou=0; fi
  local esperado=1; [ "$modo" = "nao_tem" ] && esperado=0
  if [ "$achou" = "$esperado" ]; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome (modo=$modo, padrao='$pad')"
    echo "$saida" | sed 's/^/         /' | head -5
  fi
}

esperado_exit() { # nome, esperado_exit, comando...
  local nome="$1" esp="$2"; shift 2
  local saida g
  saida=$("$@" 2>&1)
  g=$?
  if [ "$g" = "$esp" ]; then
    ok=$((ok+1)); echo "  ok    $nome (exit $g)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $g"
    echo "$saida" | sed 's/^/         /' | head -5
  fi
  echo "$saida"
}

echo
echo "== 1. o hook roda e emite JSON válido =="
SAIDA=$(node "$HOOK" 2>&1)
SAIDA_EXIT=$?
if [ "$SAIDA_EXIT" = "0" ]; then
  ok=$((ok+1)); echo "  ok    hook roda com exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA hook saiu com exit $SAIDA_EXIT"
fi

# JSON.parse deve rodar sem erro
if echo "$SAIDA" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    JSON parseia corretamente"
else
  falhou=$((falhou+1)); echo "  FALHA JSON não parseia"
  echo "$SAIDA" | sed 's/^/         /' | head -3
fi

echo
echo "== 2. hookSpecificOutput contém a estrutura correta =="
checa "tem hookSpecificOutput" tem "hookSpecificOutput" "$SAIDA"
checa "hookEventName é SubagentStart" tem '"hookEventName":"SubagentStart"' "$SAIDA"
checa "tem additionalContext" tem "additionalContext" "$SAIDA"

# Extrai o additionalContext para testes seguintes
CONTEXTO=$(echo "$SAIDA" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

echo
echo "== 3. additionalContext contém todos os 7 degraus =="
checa "tem Degrau 1" tem "Degrau 1" "$CONTEXTO"
checa "tem Degrau 2" tem "Degrau 2" "$CONTEXTO"
checa "tem Degrau 3" tem "Degrau 3" "$CONTEXTO"
checa "tem Degrau 4" tem "Degrau 4" "$CONTEXTO"
checa "tem Degrau 5" tem "Degrau 5" "$CONTEXTO"
checa "tem Degrau 6" tem "Degrau 6" "$CONTEXTO"
checa "tem Degrau 7" tem "Degrau 7" "$CONTEXTO"
checa "tem YAGNI" tem "YAGNI" "$CONTEXTO"
checa "tem Cabe em uma linha" tem "Cabe em uma linha" "$CONTEXTO"
checa "tem Ponto de variação" tem "Ponto de variação" "$CONTEXTO"

echo
echo "== 4. escada é extraída, não duplicada (mutação de conteúdo) =="
# Cria uma cópia temporária de modo-dev/SKILL.md com escada modificada
mkdir -p "$RAIZ_TESTE_POSIX/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/skills/modo-dev/SKILL.md"
# Altera a escada na cópia
sed -i 's/Degrau 1\./DEGRAU_MUTANTE_1./g' "$RAIZ_TESTE_POSIX/skills/modo-dev/SKILL.md"
# Roda o hook apontando para a cópia (simulando outro repo)
# Nota: o hook lê de CLAUDE_PLUGIN_ROOT, então precisamos simular alterando o caminho
# Vamos copiá-lo para a raiz de teste e rodá-lo de lá
cp "$HOOK" "$RAIZ_TESTE_POSIX/escada-subagente.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/escada.cjs"
# Modifica o require no hook temporário
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|" "$RAIZ_TESTE_POSIX/escada-subagente.cjs"

# Simula um PLUGIN_ROOT apontando para a raiz de teste
SAIDA_MUT=$(CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX" node "$RAIZ_TESTE_POSIX/escada-subagente.cjs" 2>&1)
CONTEXTO_MUT=$(echo "$SAIDA_MUT" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

checa "versão original tem Degrau 1" tem "Degrau 1" "$CONTEXTO"
checa "versão mutante tem DEGRAU_MUTANTE_1" tem "DEGRAU_MUTANTE_1" "$CONTEXTO_MUT"
checa "versão mutante não tem Degrau 1 normal" nao_tem "Degrau 1\\." "$CONTEXTO_MUT"

echo
echo "== 5. hooks.json tem SubagentStart registrado =="
HOOKS_JSON="$SRC/hooks/hooks.json"
if cat "$HOOKS_JSON" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    hooks.json é JSON válido"
else
  falhou=$((falhou+1)); echo "  FALHA hooks.json não parseia como JSON"
fi
HOOKS_CONTENT="$(cat "$HOOKS_JSON")"
checa "hooks.json tem SubagentStart" tem '"SubagentStart"' "$HOOKS_CONTENT"
checa "SubagentStart aponta para escada-subagente.cjs" tem "escada-subagente.cjs" "$HOOKS_CONTENT"

echo
echo "== 6. mutação: remover JSON e comprovar que falha =="
# Copia o hook original
cp "$HOOK" "$RAIZ_TESTE_POSIX/escada-subagente-mut.cjs"
# Remove a estrutura JSON (substitui console.log JSON por console.log texto)
sed -i 's|console.log(JSON.stringify(saida));|console.log(escada);|' "$RAIZ_TESTE_POSIX/escada-subagente-mut.cjs"

# Quando o JSON é removido, a saída deve ser um texto plano (não JSON)
SAIDA_TEXT=$(node "$RAIZ_TESTE_POSIX/escada-subagente-mut.cjs" 2>&1)
# Tenta parsear como JSON — deve falhar
if echo "$SAIDA_TEXT" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA mutação: stdout cru ainda parseia como JSON (mutação não aplicou)"
else
  ok=$((ok+1)); echo "  ok    mutação expôs que o JSON é necessário (texto cru não parseia)"
fi

echo
echo "== 7. carve-outs e proteções estão injetadas =="
checa "tem 'Onde a escada não desce'" tem "Onde a escada não desce" "$CONTEXTO"
checa "tem 'fronteira de confiança'" tem "fronteira de confiança" "$CONTEXTO"
checa "tem 'perda de dados'" tem "perda de dados" "$CONTEXTO"
checa "tem 'segurança'" tem "segurança" "$CONTEXTO"
checa "tem 'o que o usuário pediu explicitamente'" tem "o que o usuário pediu explicitamente" "$CONTEXTO"
checa "tem 'Bug = causa raiz, não sintoma'" tem "Bug = causa raiz, não sintoma" "$CONTEXTO"

echo
echo "== 8. degraus estão na ordem correta =="
# Degrau 2 deve aparecer antes de Degrau 3
idx_d2=$(echo "$CONTEXTO" | grep -o -b "Degrau 2\\." | head -1 | cut -d: -f1)
idx_d3=$(echo "$CONTEXTO" | grep -o -b "Degrau 3\\." | head -1 | cut -d: -f1)
if [ -n "$idx_d2" ] && [ -n "$idx_d3" ] && [ "$idx_d2" -lt "$idx_d3" ]; then
  ok=$((ok+1)); echo "  ok    Degrau 2 vem antes de Degrau 3"
else
  falhou=$((falhou+1)); echo "  FALHA Degrau 2 não vem antes de Degrau 3"
fi

# Degrau 2 (já existe neste codebase) deve vir antes de Degrau 5 (cabe em uma linha)
idx_d2_atual=$(echo "$CONTEXTO" | grep -o -b "Já existe neste codebase" | head -1 | cut -d: -f1)
idx_d5_atual=$(echo "$CONTEXTO" | grep -o -b "Cabe em uma linha" | head -1 | cut -d: -f1)
if [ -n "$idx_d2_atual" ] && [ -n "$idx_d5_atual" ] && [ "$idx_d2_atual" -lt "$idx_d5_atual" ]; then
  ok=$((ok+1)); echo "  ok    'Já existe neste codebase' vem antes de 'Cabe em uma linha'"
else
  falhou=$((falhou+1)); echo "  FALHA 'Já existe neste codebase' não vem antes de 'Cabe em uma linha'"
fi

# Degrau 3 (stdlib) deve vir antes de Degrau 4 (dependência)
idx_stdlib=$(echo "$CONTEXTO" | grep -o -b "Stdlib resolve" | head -1 | cut -d: -f1)
idx_dep=$(echo "$CONTEXTO" | grep -o -b "Dependência já instalada" | head -1 | cut -d: -f1)
if [ -n "$idx_stdlib" ] && [ -n "$idx_dep" ] && [ "$idx_stdlib" -lt "$idx_dep" ]; then
  ok=$((ok+1)); echo "  ok    'Stdlib resolve' vem antes de 'Dependência já instalada'"
else
  falhou=$((falhou+1)); echo "  FALHA 'Stdlib resolve' não vem antes de 'Dependência já instalada'"
fi

# Degrau 4 (dependência) deve vir antes de Degrau 5 (cabe em uma linha)
idx_dep_d4=$(echo "$CONTEXTO" | grep -o -b "Dependência já instalada" | head -1 | cut -d: -f1)
idx_cabe=$(echo "$CONTEXTO" | grep -o -b "Cabe em uma linha" | head -1 | cut -d: -f1)
if [ -n "$idx_dep_d4" ] && [ -n "$idx_cabe" ] && [ "$idx_dep_d4" -lt "$idx_cabe" ]; then
  ok=$((ok+1)); echo "  ok    'Dependência já instalada' vem antes de 'Cabe em uma linha'"
else
  falhou=$((falhou+1)); echo "  FALHA 'Dependência já instalada' não vem antes de 'Cabe em uma linha'"
fi

echo
echo "== 9. formatação do degrau 5 (cabe em uma linha) está correta =="
checa "tem formato correto 'pulei: [X], entra quando [Y]'" tem "pulei: [X], entra quando [Y]" "$CONTEXTO"

echo
echo "== 10. degradação graciosa: arquivo SKILL.md ausente =="
# Cria hook que aponta para raiz sem SKILL.md
mkdir -p "$RAIZ_TESTE_POSIX/skills-vazia"
cp "$HOOK" "$RAIZ_TESTE_POSIX/escada-gracioso.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|" "$RAIZ_TESTE_POSIX/escada-gracioso.cjs"
# Sem SKILL.md no path, a extração retorna vazio, mas o hook ainda emite JSON válido
SAIDA_VAZIO=$(CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/skills-vazia" node "$RAIZ_TESTE_POSIX/escada-gracioso.cjs" 2>&1)
if echo "$SAIDA_VAZIO" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    hook emite JSON mesmo sem SKILL.md (degradação graciosa)"
else
  falhou=$((falhou+1)); echo "  FALHA hook falhou quando SKILL.md ausente"
fi

# Verifica que há um additionalContext (mesmo que vazio ou fallback)
checa "sem arquivo, tem additionalContext fallback" tem "additionalContext" "$SAIDA_VAZIO"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
