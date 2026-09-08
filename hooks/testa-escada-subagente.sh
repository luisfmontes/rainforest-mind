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
echo "== 11. dial de intensidade: nível enxuto =="
# Cria uma pasta de testes com config.json especificando nível enxuto
mkdir -p "$RAIZ_TESTE_POSIX/estado-enxuto/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/estado-enxuto/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/estado-enxuto/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/estado-enxuto/escada.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_TESTE_POSIX/estado-enxuto/raiz.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|g; s|require('./lib/raiz.cjs')|require('./raiz.cjs')|g" "$RAIZ_TESTE_POSIX/estado-enxuto/escada-hook.cjs"

# Escreve config.json com nível enxuto
echo '{"escada-intensidade":"enxuto"}' > "$RAIZ_TESTE_POSIX/estado-enxuto/config.json"
# Cria FOCO.md para que raiz.cjs reconheça como raiz válida
touch "$RAIZ_TESTE_POSIX/estado-enxuto/FOCO.md"

SAIDA_ENXUTO=$(RFM_ESTADO_ROOT="$RAIZ_TESTE_POSIX/estado-enxuto" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/estado-enxuto" node "$RAIZ_TESTE_POSIX/estado-enxuto/escada-hook.cjs" 2>&1)
CONTEXTO_ENXUTO=$(echo "$SAIDA_ENXUTO" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

# Nível enxuto deve ter degraus comprimidos + carve-outs
checa "nivel enxuto: tem 'Onde a escada nao desce'" tem "Onde a escada não desce" "$CONTEXTO_ENXUTO"
checa "nivel enxuto: tem carve-out de segurança" tem "segurança" "$CONTEXTO_ENXUTO"
checa "nivel enxuto: tem Degrau 1 (comprimido)" tem "Degrau 1" "$CONTEXTO_ENXUTO"
checa "nivel enxuto: tem Degrau 7 (comprimido)" tem "Degrau 7" "$CONTEXTO_ENXUTO"

# Medir tamanho do nível enxuto
TAMANHO_ENXUTO=${#CONTEXTO_ENXUTO}

echo
echo "== 12. dial de intensidade: nível padrão =="
mkdir -p "$RAIZ_TESTE_POSIX/estado-padrao/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/estado-padrao/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/estado-padrao/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/estado-padrao/escada.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_TESTE_POSIX/estado-padrao/raiz.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|g; s|require('./lib/raiz.cjs')|require('./raiz.cjs')|g" "$RAIZ_TESTE_POSIX/estado-padrao/escada-hook.cjs"

echo '{"escada-intensidade":"padrão"}' > "$RAIZ_TESTE_POSIX/estado-padrao/config.json"
touch "$RAIZ_TESTE_POSIX/estado-padrao/FOCO.md"

SAIDA_PADRAO=$(RFM_ESTADO_ROOT="$RAIZ_TESTE_POSIX/estado-padrao" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/estado-padrao" node "$RAIZ_TESTE_POSIX/estado-padrao/escada-hook.cjs" 2>&1)
CONTEXTO_PADRAO=$(echo "$SAIDA_PADRAO" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

checa "nivel padrao: tem todos os 7 degraus" tem "Degrau 7" "$CONTEXTO_PADRAO"
checa "nivel padrao: tem carve-outs" tem "Onde a escada não desce" "$CONTEXTO_PADRAO"

TAMANHO_PADRAO=${#CONTEXTO_PADRAO}

echo
echo "== 13. dial de intensidade: nível completo (deve retornar padrão) =="
mkdir -p "$RAIZ_TESTE_POSIX/estado-completo/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/estado-completo/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/estado-completo/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/estado-completo/escada.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_TESTE_POSIX/estado-completo/raiz.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|g; s|require('./lib/raiz.cjs')|require('./raiz.cjs')|g" "$RAIZ_TESTE_POSIX/estado-completo/escada-hook.cjs"

echo '{"escada-intensidade":"completo"}' > "$RAIZ_TESTE_POSIX/estado-completo/config.json"
touch "$RAIZ_TESTE_POSIX/estado-completo/FOCO.md"

SAIDA_COMPLETO=$(RFM_ESTADO_ROOT="$RAIZ_TESTE_POSIX/estado-completo" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/estado-completo" node "$RAIZ_TESTE_POSIX/estado-completo/escada-hook.cjs" 2>&1)
CONTEXTO_COMPLETO=$(echo "$SAIDA_COMPLETO" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

# 'completo' não é suportado; deve cair para padrão (fallback)
checa "nivel completo: não suportado, usa padrão (tem todos 7 degraus)" tem "Degrau 7" "$CONTEXTO_COMPLETO"
checa "nivel completo: não suportado, usa padrão (tem carve-outs)" tem "Onde a escada não desce" "$CONTEXTO_COMPLETO"

TAMANHO_COMPLETO=${#CONTEXTO_COMPLETO}

echo
echo "== 14. dial de intensidade: comparação de tamanhos =="
if [ "$TAMANHO_ENXUTO" -lt "$TAMANHO_PADRAO" ]; then
  ok=$((ok+1)); echo "  ok    enxuto ($TAMANHO_ENXUTO bytes) é menor que padrão ($TAMANHO_PADRAO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA enxuto não é menor que padrão (enxuto=$TAMANHO_ENXUTO, padrão=$TAMANHO_PADRAO)"
fi

if [ "$TAMANHO_PADRAO" -eq "$TAMANHO_COMPLETO" ]; then
  ok=$((ok+1)); echo "  ok    padrão e completo têm o mesmo tamanho (versão atual: $TAMANHO_PADRAO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA padrão ($TAMANHO_PADRAO) diferente de completo ($TAMANHO_COMPLETO)"
fi

echo
echo "== 15. dial de intensidade: nível inválido cai no padrão =="
mkdir -p "$RAIZ_TESTE_POSIX/estado-invalido/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/estado-invalido/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/estado-invalido/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/estado-invalido/escada.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|" "$RAIZ_TESTE_POSIX/estado-invalido/escada-hook.cjs"

echo '{"escada-intensidade":"valor-invalido"}' > "$RAIZ_TESTE_POSIX/estado-invalido/config.json"

SAIDA_INVALIDO=$(RFM_ESTADO_ROOT="$RAIZ_TESTE_POSIX/estado-invalido" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/estado-invalido" node "$RAIZ_TESTE_POSIX/estado-invalido/escada-hook.cjs" 2>&1)
if echo "$SAIDA_INVALIDO" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    nível inválido emite JSON válido (fallback para padrão)"
else
  falhou=$((falhou+1)); echo "  FALHA nível inválido resultou em JSON inválido"
fi

CONTEXTO_INVALIDO=$(echo "$SAIDA_INVALIDO" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)
checa "nível inválido: tem Degrau 7 (padrão)" tem "Degrau 7" "$CONTEXTO_INVALIDO"

echo
echo "== 16. dial de intensidade: config.json ausente usa padrão =="
mkdir -p "$RAIZ_TESTE_POSIX/estado-sem-config/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/estado-sem-config/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/estado-sem-config/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/estado-sem-config/escada.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|" "$RAIZ_TESTE_POSIX/estado-sem-config/escada-hook.cjs"

# Não cria config.json, testa degradação graciosa

SAIDA_SEM_CONFIG=$(RFM_ESTADO_ROOT="$RAIZ_TESTE_POSIX/estado-sem-config" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/estado-sem-config" node "$RAIZ_TESTE_POSIX/estado-sem-config/escada-hook.cjs" 2>&1)
if echo "$SAIDA_SEM_CONFIG" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    sem config.json, emite JSON válido (fallback para padrão)"
else
  falhou=$((falhou+1)); echo "  FALHA sem config.json resultou em JSON inválido"
fi

CONTEXTO_SEM_CONFIG=$(echo "$SAIDA_SEM_CONFIG" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)
checa "sem config: tem Degrau 7 (padrão)" tem "Degrau 7" "$CONTEXTO_SEM_CONFIG"

echo
echo "== 17. dial de intensidade: resolução de raiz via raiz.cjs (sem RFM_ESTADO_ROOT) =="
# Este é o caso crítico: valida que raiz.cjs é chamado e funciona quando
# RFM_ESTADO_ROOT não está definido. Verifica o caminho de resolução que ef8af15 fixou.
mkdir -p "$RAIZ_TESTE_POSIX/projeto-com-foco/.rainforest"
mkdir -p "$RAIZ_TESTE_POSIX/projeto-com-foco/skills/modo-dev"
cp "$SKILL" "$RAIZ_TESTE_POSIX/projeto-com-foco/skills/modo-dev/SKILL.md"
cp "$HOOK" "$RAIZ_TESTE_POSIX/projeto-com-foco/escada-hook.cjs"
cp "$SRC/hooks/lib/escada.cjs" "$RAIZ_TESTE_POSIX/projeto-com-foco/escada.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_TESTE_POSIX/projeto-com-foco/raiz.cjs"
sed -i "s|require('./lib/escada.cjs')|require('./escada.cjs')|g; s|require('./lib/raiz.cjs')|require('./raiz.cjs')|g" "$RAIZ_TESTE_POSIX/projeto-com-foco/escada-hook.cjs"

# Escreve config.json em nível 2 (projeto/.rainforest)
echo '{"escada-intensidade":"enxuto"}' > "$RAIZ_TESTE_POSIX/projeto-com-foco/.rainforest/config.json"
# Marca como raiz válida (marcador de nível 2 em raiz.cjs)
touch "$RAIZ_TESTE_POSIX/projeto-com-foco/.rainforest/FOCO.md"

# Executa sem RFM_ESTADO_ROOT nem RFM_ROOT
# env -u remove as variáveis; CLAUDE_PROJECT_DIR aponta para o projeto
SAIDA_RAIZ=$(env -u RFM_ESTADO_ROOT -u RFM_ROOT CLAUDE_PROJECT_DIR="$RAIZ_TESTE_POSIX/projeto-com-foco" CLAUDE_PLUGIN_ROOT="$RAIZ_TESTE_POSIX/projeto-com-foco" node "$RAIZ_TESTE_POSIX/projeto-com-foco/escada-hook.cjs" 2>&1)
CONTEXTO_RAIZ=$(echo "$SAIDA_RAIZ" | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(data.hookSpecificOutput?.additionalContext || '');
" 2>&1)

# Verifica que a resolução funcionou (tem os degraus comprimidos)
checa "via raiz.cjs: tem Degrau 1" tem "Degrau 1" "$CONTEXTO_RAIZ"
checa "via raiz.cjs: tem Degrau 7" tem "Degrau 7" "$CONTEXTO_RAIZ"
checa "via raiz.cjs: tem carve-outs" tem "Onde a escada não desce" "$CONTEXTO_RAIZ"

TAMANHO_RAIZ=${#CONTEXTO_RAIZ}

# Compara com padrão: enxuto resolvido via raiz.cjs deve ser menor que padrão
if [ "$TAMANHO_RAIZ" -lt "$TAMANHO_PADRAO" ]; then
  ok=$((ok+1)); echo "  ok    enxuto via raiz.cjs ($TAMANHO_RAIZ bytes) é menor que padrão ($TAMANHO_PADRAO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA enxuto via raiz.cjs não é menor que padrão (via raiz=$TAMANHO_RAIZ, padrão=$TAMANHO_PADRAO)"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
