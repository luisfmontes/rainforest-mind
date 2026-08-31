#!/bin/bash
# Bateria do scripts/ponte.cjs --entrevistar --varredura
# Uso: bash scripts/testa-ponte-entrevista.sh
#
# Casos de teste para varredura pura de repositório:
# (a) detecta stack Node por package.json real, com scripts.test e scripts.build
# (b) layout lista os dirs de 1º nível sem .git/node_modules
# (c) nada escrito no alvo (projeto.md inexistente depois)
# (d) alvo sem package.json → JSON com stack desconhecida, exit 0 (não explode)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Copia do PLUGIN, para a ponte poder resolver o próprio caminho por __dirname
PLUG="$CAIXA/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/hooks/lib" "$PLUG/skills/rainforest-mind"
cp "$SRC/scripts/ponte.cjs" "$SRC/scripts/conferir-ponte.cjs" "$PLUG/scripts/"
cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/projetos.cjs" "$SRC/hooks/lib/ponte-corpo.cjs" "$PLUG/hooks/lib/"
cp "$SRC/scripts/setup.cjs" "$PLUG/scripts/"
cp "$SRC/skills/rainforest-mind/SKILL.md" "$PLUG/skills/rainforest-mind/"
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
PONTE="node $PLUG/scripts/ponte.cjs"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
prova() { # nome, comando de teste (bash -c)
  local nome="$1"; shift
  if bash -c "$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== (a) detecta stack Node por package.json real, com scripts.test e scripts.build =="
REPO_A="$CAIXA/repo-a"
mkdir -p "$REPO_A/.github/workflows"
cat > "$REPO_A/package.json" <<'EOF'
{
  "name": "teste-a",
  "scripts": {
    "test": "node --test",
    "build": "node build.js"
  }
}
EOF
cat > "$REPO_A/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
REPO_A_WIN="$(cygpath -m "$REPO_A" 2>/dev/null || printf '%s' "$REPO_A")"
esperado "varredura roda" 0 $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... nomeia node" '"stack": "node"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista scripts.test literal" '"comando": "node --test"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista scripts.build literal" '"comando": "node build.js"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista workflows" '"ci"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"

echo
echo "== (b) layout lista os dirs de 1º nível sem .git/node_modules/docs =="
REPO_B="$CAIXA/repo-b"
mkdir -p "$REPO_B/.git" "$REPO_B/node_modules" "$REPO_B/src" "$REPO_B/build"
# Sem package.json neste caso
REPO_B_WIN="$(cygpath -m "$REPO_B" 2>/dev/null || printf '%s' "$REPO_B")"
contem "  ... lista src" '"src"' $PONTE --entrevistar --varredura --alvo "$REPO_B_WIN"
contem "  ... lista build" '"build"' $PONTE --entrevistar --varredura --alvo "$REPO_B_WIN"
prova "  ... nao lista .git" "! ($PONTE --entrevistar --varredura --alvo '$REPO_B_WIN' 2>&1 | grep -q '\".git\"')"
prova "  ... nao lista node_modules" "! ($PONTE --entrevistar --varredura --alvo '$REPO_B_WIN' 2>&1 | grep -q 'node_modules')"
prova "  ... nao lista docs (reservado)" "! ($PONTE --entrevistar --varredura --alvo '$REPO_B_WIN' 2>&1 | grep -q '\"docs\"')"

echo
echo "== (c) nada escrito no alvo (projeto.md inexistente depois) =="
REPO_C="$CAIXA/repo-c"
mkdir -p "$REPO_C"
cat > "$REPO_C/package.json" <<'EOF'
{
  "name": "teste-c",
  "scripts": {
    "test": "echo test"
  }
}
EOF
REPO_C_WIN="$(cygpath -m "$REPO_C" 2>/dev/null || printf '%s' "$REPO_C")"
esperado "varredura nao escreve" 0 $PONTE --entrevistar --varredura --alvo "$REPO_C_WIN"
prova "  ... projeto.md nao existe" "[ ! -e '$REPO_C/docs/rainforest/projeto.md' ]"

echo
echo "== (d) alvo sem package.json → stack desconhecida, exit 0 =="
REPO_D="$CAIXA/repo-d"
mkdir -p "$REPO_D"
esperado "varredura com stack vazia" 0 $PONTE --entrevistar --varredura --alvo "$(cygpath -m "$REPO_D" 2>/dev/null || printf '%s' "$REPO_D")"
contem "  ... stack e desconhecida" '"stack": "desconhecida"' $PONTE --entrevistar --varredura --alvo "$(cygpath -m "$REPO_D" 2>/dev/null || printf '%s' "$REPO_D")"

echo
echo "== (e) grava projeto.md atomicamente, e nao pela metade =="
REPO_E="$CAIXA/repo-e"
mkdir -p "$REPO_E/.github/workflows"
cat > "$REPO_E/package.json" <<'EOF'
{
  "name": "teste-e",
  "scripts": {
    "test": "npm test",
    "build": "npm run build"
  }
}
EOF
cat > "$REPO_E/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
mkdir -p "$REPO_E/src" "$REPO_E/docs"

# Cria fixture de respostas
RESPOSTAS_E="$CAIXA/respostas-e.json"
cat > "$RESPOSTAS_E" <<'EOF'
{
  "pronto": "Todos os testes passam e o build nao falha",
  "nao_toca": "Dependencias externas, credenciais",
  "convencao": "Comentarios em português, nomenclatura camelCase",
  "revisao": "Pelo menos uma aprovacao antes de merge"
}
EOF

REPO_E_WIN="$(cygpath -m "$REPO_E" 2>/dev/null || printf '%s' "$REPO_E")"
RESPOSTAS_E_WIN="$(cygpath -m "$RESPOSTAS_E" 2>/dev/null || printf '%s' "$RESPOSTAS_E")"

esperado "grava com --aplicar" 0 $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_E_WIN" --alvo "$REPO_E_WIN" --aplicar
prova "  ... projeto.md existe" "[ -f '$REPO_E/docs/rainforest/projeto.md' ]"
contem "  ... contem pronto literal" "Todos os testes passam" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_E_WIN" --alvo "$REPO_E_WIN"
contem "  ... contem nao_toca literal" "Dependencias externas" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_E_WIN" --alvo "$REPO_E_WIN"
contem "  ... contem convencao literal" "Comentarios em português" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_E_WIN" --alvo "$REPO_E_WIN"
contem "  ... contem revisao literal" "Pelo menos uma aprovacao" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_E_WIN" --alvo "$REPO_E_WIN"
contem "  ... contem stack" '"stack": "node"' $PONTE --entrevistar --varredura --alvo "$REPO_E_WIN"
contem "  ... contem layout" "src" cat "$REPO_E/docs/rainforest/projeto.md"

echo
echo "== (f) sem --aplicar, nada criado e markdown sai no stdout =="
REPO_F="$CAIXA/repo-f"
mkdir -p "$REPO_F"
cat > "$REPO_F/package.json" <<'EOF'
{
  "name": "teste-f",
  "scripts": {
    "test": "jest"
  }
}
EOF

RESPOSTAS_F="$CAIXA/respostas-f.json"
cat > "$RESPOSTAS_F" <<'EOF'
{
  "pronto": "Pronto quando tudo",
  "nao_toca": "Nao toque",
  "convencao": "Convencoes",
  "revisao": "Revisao"
}
EOF

REPO_F_WIN="$(cygpath -m "$REPO_F" 2>/dev/null || printf '%s' "$REPO_F")"
RESPOSTAS_F_WIN="$(cygpath -m "$RESPOSTAS_F" 2>/dev/null || printf '%s' "$RESPOSTAS_F")"

contem "  ... markdown no stdout" "Pronto quando tudo" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_F_WIN" --alvo "$REPO_F_WIN"
prova "  ... projeto.md nao criado" "[ ! -e '$REPO_F/docs/rainforest/projeto.md' ]"

echo
echo "== (g) rodar duas vezes com --aplicar nao duplica conteudo =="
REPO_G="$CAIXA/repo-g"
mkdir -p "$REPO_G"
cat > "$REPO_G/package.json" <<'EOF'
{
  "name": "teste-g"
}
EOF

RESPOSTAS_G="$CAIXA/respostas-g.json"
cat > "$RESPOSTAS_G" <<'EOF'
{
  "pronto": "Pronto",
  "nao_toca": "Nao toca",
  "convencao": "Convencao",
  "revisao": "Revisao"
}
EOF

REPO_G_WIN="$(cygpath -m "$REPO_G" 2>/dev/null || printf '%s' "$REPO_G")"
RESPOSTAS_G_WIN="$(cygpath -m "$RESPOSTAS_G" 2>/dev/null || printf '%s' "$RESPOSTAS_G")"

$PONTE --entrevistar --gravar --respostas "$RESPOSTAS_G_WIN" --alvo "$REPO_G_WIN" --aplicar >/dev/null 2>&1
tamanho1=$(stat -f%z "$REPO_G/docs/rainforest/projeto.md" 2>/dev/null || wc -c < "$REPO_G/docs/rainforest/projeto.md")
$PONTE --entrevistar --gravar --respostas "$RESPOSTAS_G_WIN" --alvo "$REPO_G_WIN" --aplicar >/dev/null 2>&1
tamanho2=$(stat -f%z "$REPO_G/docs/rainforest/projeto.md" 2>/dev/null || wc -c < "$REPO_G/docs/rainforest/projeto.md")
if [ "$tamanho1" = "$tamanho2" ]; then ok=$((ok+1)); echo "  ok   arquivo substituido, tamanho constante"
else falhou=$((falhou+1)); echo "  FALHA tamanho mudou: $tamanho1 -> $tamanho2"; fi

echo
echo "== (h) --respostas com JSON invalido → erro claro, exit ≠ 0, nada gravado =="
REPO_H="$CAIXA/repo-h"
mkdir -p "$REPO_H"
cat > "$REPO_H/package.json" <<'EOF'
{
  "name": "teste-h"
}
EOF

RESPOSTAS_H_INVALID="$CAIXA/respostas-h-invalid.json"
echo '{nao e json valido}' > "$RESPOSTAS_H_INVALID"

REPO_H_WIN="$(cygpath -m "$REPO_H" 2>/dev/null || printf '%s' "$REPO_H")"
RESPOSTAS_H_WIN="$(cygpath -m "$RESPOSTAS_H_INVALID" 2>/dev/null || printf '%s' "$RESPOSTAS_H_INVALID")"

esperado "rejeita JSON invalido" 1 $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_H_WIN" --alvo "$REPO_H_WIN" --aplicar
prova "  ... projeto.md nao criado" "[ ! -e '$REPO_H/docs/rainforest/projeto.md' ]"

echo
echo "== (i) bloco de projeto aparece quando ha projeto.md no alvo, e some quando nao ha =="
REPO_I="$CAIXA/repo-i"
mkdir -p "$REPO_I/.github/workflows"
cat > "$REPO_I/package.json" <<'EOF'
{
  "name": "teste-i",
  "scripts": {
    "test": "npm test"
  }
}
EOF
cat > "$REPO_I/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
mkdir -p "$REPO_I/src"

# Cria projeto.md no alvo com marcadores de projeto
mkdir -p "$REPO_I/docs/rainforest"
cat > "$REPO_I/docs/rainforest/projeto.md" <<'EOF'
<!-- rainforest-mind:projeto:inicio -->
# Bloco do projeto

## Fatos da varredura

### Stack
node

### Comandos de teste/build
- **test**: `npm test`

### Layout (diretórios de 1º nível)
- src

## Respostas da entrevista

### O que é "pronto" aqui
Todos os testes passam

### O que não se toca
Dependências

### Convenção não escrita
Português

### Política de revisão
Uma aprovação
<!-- rainforest-mind:projeto:fim -->
EOF

REPO_I_WIN="$(cygpath -m "$REPO_I" 2>/dev/null || printf '%s' "$REPO_I")"

# Com projeto.md: dois pares de marcadores devem aparecer
esperado "gera com projeto.md" 0 $PONTE --alvo "$REPO_I_WIN" --agente codex --aplicar
contem "  ... tem bloco de projeto" "rainforest-mind:projeto:inicio" cat "$REPO_I/AGENTS.md"
contem "  ... contém conteúdo do projeto" "Todos os testes passam" cat "$REPO_I/AGENTS.md"
prova "  ... tem exatamente um marcador de início" "[ \$(grep -c 'rainforest-mind:projeto:inicio' '$REPO_I/AGENTS.md') -eq 1 ]"

# Apaga projeto.md e regenera: o bloco deve sumir
rm "$REPO_I/docs/rainforest/projeto.md"
esperado "regenera sem projeto.md" 0 $PONTE --alvo "$REPO_I_WIN" --agente codex --aplicar
prova "  ... bloco de projeto sumiu" "! grep -q 'rainforest-mind:projeto' '$REPO_I/AGENTS.md'"

# Cria novamente e regenera 2x: não deve duplicar
cat > "$REPO_I/docs/rainforest/projeto.md" <<'EOF'
<!-- rainforest-mind:projeto:inicio -->
# Bloco do projeto

## Fatos da varredura

### Stack
node

## Respostas da entrevista

### O que é "pronto" aqui
Pronto
<!-- rainforest-mind:projeto:fim -->
EOF

$PONTE --alvo "$REPO_I_WIN" --agente codex --aplicar >/dev/null 2>&1
contar1=$(grep -c 'rainforest-mind:projeto:inicio' "$REPO_I/AGENTS.md" 2>/dev/null || echo 0)
$PONTE --alvo "$REPO_I_WIN" --agente codex --aplicar >/dev/null 2>&1
contar2=$(grep -c 'rainforest-mind:projeto:inicio' "$REPO_I/AGENTS.md" 2>/dev/null || echo 0)
if [ "$contar1" = 1 ] && [ "$contar2" = 1 ]; then ok=$((ok+1)); echo "  ok   regeneracao não duplica marcador"
else falhou=$((falhou+1)); echo "  FALHA regeneracao duplicou: $contar1 -> $contar2"; fi

# Verifica byte-identidade entre os agentes (bloco de projeto)
$PONTE --alvo "$REPO_I_WIN" --agente claude --aplicar >/dev/null 2>&1
$PONTE --alvo "$REPO_I_WIN" --agente codex --aplicar >/dev/null 2>&1
$PONTE --alvo "$REPO_I_WIN" --agente gemini --aplicar >/dev/null 2>&1
# Extrai o bloco de projeto de cada arquivo
BLOCO_CLAUDE=$(sed -n '/<!-- rainforest-mind:projeto:inicio -->/,/<!-- rainforest-mind:projeto:fim -->/p' "$REPO_I/CLAUDE.md")
BLOCO_CODEX=$(sed -n '/<!-- rainforest-mind:projeto:inicio -->/,/<!-- rainforest-mind:projeto:fim -->/p' "$REPO_I/AGENTS.md")
BLOCO_GEMINI=$(sed -n '/<!-- rainforest-mind:projeto:inicio -->/,/<!-- rainforest-mind:projeto:fim -->/p' "$REPO_I/GEMINI.md")
if [ "$BLOCO_CLAUDE" = "$BLOCO_CODEX" ] && [ "$BLOCO_CODEX" = "$BLOCO_GEMINI" ]; then ok=$((ok+1)); echo "  ok   bloco de projeto byte-identico entre agentes"
else falhou=$((falhou+1)); echo "  FALHA bloco de projeto diverge entre agentes"; fi

echo
echo "== (j) bloco de projeto editado a mao e detectado, sem confundir com o bloco de regras =="
REPO_J="$CAIXA/repo-j"
mkdir -p "$REPO_J/.github/workflows"
cat > "$REPO_J/package.json" <<'EOF'
{
  "name": "teste-j",
  "scripts": {
    "test": "npm test"
  }
}
EOF
cat > "$REPO_J/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
mkdir -p "$REPO_J/docs/rainforest"

# Cria projeto.md com conteúdo inicial
cat > "$REPO_J/docs/rainforest/projeto.md" <<'EOF'
<!-- rainforest-mind:projeto:inicio -->
# Bloco do projeto

## Fatos da varredura

### Stack
node

## Respostas da entrevista

### O que é "pronto" aqui
Testes passam
<!-- rainforest-mind:projeto:fim -->
EOF

REPO_J_WIN="$(cygpath -m "$REPO_J" 2>/dev/null || printf '%s' "$REPO_J")"

# Gera AGENTS.md com o bloco de projeto
$PONTE --alvo "$REPO_J_WIN" --agente codex --aplicar >/dev/null 2>&1

# Referência ao conferir-ponte.cjs já copiado no cabeçalho
CONFERIR_PONTE="$PLUG/scripts/conferir-ponte.cjs"
SKILL_PONTE="$PLUG/skills/rainforest-mind/SKILL.md"

# Edita manualmente uma linha DENTRO do bloco de projeto no arquivo gerado
sed -i 's/Testes passam/Editado manualmente/' "$REPO_J/AGENTS.md"

# Confere — deve acusar RECUSADO citando a linha divergente
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" 2>&1 | grep -q "Bloco de projeto foi editado à mão"; then
  ok=$((ok+1)); echo "  ok   detecta edicao no bloco de projeto"
else
  falhou=$((falhou+1)); echo "  FALHA detecta edicao no bloco de projeto: nao achei 'Bloco de projeto foi editado à mão'"
fi

# Verifica que ainda reconhece RECUSADO (exit 2)
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" >/dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA exit 2 para edicao no projeto: esperava exit 2, veio 0"
else
  exitcode=$?
  if [ "$exitcode" = 2 ]; then
    ok=$((ok+1)); echo "  ok   exit 2 para edicao no projeto"
  else
    falhou=$((falhou+1)); echo "  FALHA exit 2 para edicao no projeto: esperava exit 2, veio $exitcode"
  fi
fi

# Regenera projeto.md com conteúdo diferente, sem regerar AGENTS.md
cat > "$REPO_J/docs/rainforest/projeto.md" <<'EOF'
<!-- rainforest-mind:projeto:inicio -->
# Bloco do projeto

## Fatos da varredura

### Stack
node

## Respostas da entrevista

### O que é "pronto" aqui
Testes passam e build OK
<!-- rainforest-mind:projeto:fim -->
EOF

# Confere — deve acusar "ficou para trás" no bloco de projeto
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" 2>&1 | grep -q "ficou para trás"; then
  ok=$((ok+1)); echo "  ok   detecta ficou-para-tras no projeto"
else
  falhou=$((falhou+1)); echo "  FALHA detecta ficou-para-tras no projeto: nao achei 'ficou para trás'"
fi

# Regenera AGENTS.md com o novo projeto.md
$PONTE --alvo "$REPO_J_WIN" --agente codex --aplicar >/dev/null 2>&1

# Confere — deve sair CONFERIDO
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" 2>&1 | grep -q "CONFERIDO"; then
  ok=$((ok+1)); echo "  ok   volta a conferido depois de regerar"
else
  falhou=$((falhou+1)); echo "  FALHA volta a conferido depois de regerar: nao achei 'CONFERIDO'"
fi

# Verifica exit 0
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" >/dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   exit 0 para conferido"
else
  exitcode=$?
  falhou=$((falhou+1)); echo "  FALHA exit 0 para conferido: esperava exit 0, veio $exitcode"
fi

# Remove projeto.md e regenera — deve sair CONFERIDO mesmo sem bloco de projeto
rm "$REPO_J/docs/rainforest/projeto.md"
$PONTE --alvo "$REPO_J_WIN" --agente codex --aplicar >/dev/null 2>&1
if node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_J/AGENTS.md" >/dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   conferido mesmo sem projeto.md"
else
  exitcode=$?
  falhou=$((falhou+1)); echo "  FALHA conferido mesmo sem projeto.md: esperava exit 0, veio $exitcode"
fi

echo
echo "== (l) INVARIANTE E2: resposta com marcador nao trunca o bloco =="
REPO_L="$CAIXA/repo-l"
mkdir -p "$REPO_L"
cat > "$REPO_L/package.json" <<'EOF'
{
  "name": "teste-l",
  "scripts": {
    "test": "npm test"
  }
}
EOF

# Cria respostas com uma adversarial que contem o marcador de fim
RESPOSTAS_L="$CAIXA/respostas-l-adversarial.json"
cat > "$RESPOSTAS_L" <<'EOF'
{
  "pronto": "Testes passam e build nao falha",
  "nao_toca": "<!-- rainforest-mind:projeto:fim --> -- nao mexa aqui",
  "convencao": "Português, camelCase",
  "revisao": "Uma aprovação"
}
EOF

REPO_L_WIN="$(cygpath -m "$REPO_L" 2>/dev/null || printf '%s' "$REPO_L")"
RESPOSTAS_L_WIN="$(cygpath -m "$RESPOSTAS_L" 2>/dev/null || printf '%s' "$RESPOSTAS_L")"

# Gera projeto.md com resposta adversarial
esperado "gera com resposta adversarial" 0 $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_L_WIN" --alvo "$REPO_L_WIN" --aplicar
prova "  ... projeto.md existe" "[ -f '$REPO_L/docs/rainforest/projeto.md' ]"
# Verifica que as 4 respostas estao presentes (sentinelas)
contem "  ... resposta 'pronto' presente" "Testes passam e build" cat "$REPO_L/docs/rainforest/projeto.md"
contem "  ... resposta 'nao_toca' presente (sanitizada)" "nao mexa aqui" cat "$REPO_L/docs/rainforest/projeto.md"
contem "  ... resposta 'convencao' presente" "Português" cat "$REPO_L/docs/rainforest/projeto.md"
contem "  ... resposta 'revisao' presente" "Uma aprovação" cat "$REPO_L/docs/rainforest/projeto.md"
# Gera bloco de ponte com o projeto.md
esperado "gera ponte com projeto.md adversarial" 0 $PONTE --alvo "$REPO_L_WIN" --agente claude --aplicar
# Verifica que o bloco de projeto aparece e nao foi truncado
contem "  ... bloco de projeto presente no CLAUDE.md" "rainforest-mind:projeto:inicio" cat "$REPO_L/CLAUDE.md"
contem "  ... resposta 'nao_toca' também presente no CLAUDE.md" "nao mexa aqui" cat "$REPO_L/CLAUDE.md"
# Confere — deve voltar exit 0
esperado "conferir-ponte valida o CLAUDE.md com projeto adversarial" 0 node "$CONFERIR_PONTE" --skill "$SKILL_PONTE" "$REPO_L/CLAUDE.md"

echo
echo "== (m) TAREFA 15: resposta que nao e string e recusada com erro =="
REPO_M="$CAIXA/repo-m"
mkdir -p "$REPO_M"
cat > "$REPO_M/package.json" <<'EOF'
{
  "name": "teste-m"
}
EOF

# Cria respostas com uma que não é string (array)
RESPOSTAS_M="$CAIXA/respostas-m-array.json"
cat > "$RESPOSTAS_M" <<'EOF'
{
  "pronto": "Testes passam",
  "nao_toca": ["<!-- rainforest-mind:projeto:fim -->"],
  "convencao": "Português",
  "revisao": "Uma aprovação"
}
EOF

REPO_M_WIN="$(cygpath -m "$REPO_M" 2>/dev/null || printf '%s' "$REPO_M")"
RESPOSTAS_M_WIN="$(cygpath -m "$RESPOSTAS_M" 2>/dev/null || printf '%s' "$RESPOSTAS_M")"

esperado "rejeita resposta array" 1 $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_M_WIN" --alvo "$REPO_M_WIN" --aplicar
contem "  ... erro menciona validacao de tipo" "deve ser string" $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_M_WIN" --alvo "$REPO_M_WIN" --aplicar
prova "  ... projeto.md nao criado" "[ ! -e '$REPO_M/docs/rainforest/projeto.md' ]"

echo
echo "== (n) TAREFA 16: conferir com caminho relativo devolve mesmo veredito do absoluto =="
REPO_N="$CAIXA/repo-n"
mkdir -p "$REPO_N"
cat > "$REPO_N/package.json" <<'EOF'
{
  "name": "teste-n",
  "scripts": {
    "test": "npm test"
  }
}
EOF
mkdir -p "$REPO_N/.github/workflows"
cat > "$REPO_N/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF

# Cria respostas simples
RESPOSTAS_N="$CAIXA/respostas-n.json"
cat > "$RESPOSTAS_N" <<'EOF'
{
  "pronto": "Testes passam",
  "nao_toca": "Dependências",
  "convencao": "Português",
  "revisao": "Uma aprovação"
}
EOF

REPO_N_WIN="$(cygpath -m "$REPO_N" 2>/dev/null || printf '%s' "$REPO_N")"
RESPOSTAS_N_WIN="$(cygpath -m "$RESPOSTAS_N" 2>/dev/null || printf '%s' "$RESPOSTAS_N")"

# Gera projeto.md
esperado "gera projeto.md" 0 $PONTE --entrevistar --gravar --respostas "$RESPOSTAS_N_WIN" --alvo "$REPO_N_WIN" --aplicar
# Gera ponte (sem entrevista, pois projeto.md já existe)
esperado "gera ponte CLAUDE.md" 0 $PONTE --alvo "$REPO_N_WIN" --agente claude --aplicar

# Confere com caminho absoluto
ABS_CLAUDE="$REPO_N/CLAUDE.md"
esperado "conferir com caminho absoluto" 0 node "$PLUG/scripts/conferir-ponte.cjs" "$ABS_CLAUDE"

# Confere com caminho relativo (cd para o diretório alvo e confere relativo)
# Ao fazer cd e depois usar caminho relativo, o diretório alvo resolve corretamente
prova "  ... caminho relativo devolve CONFERIDO" "cd '$REPO_N' && node $PLUG/scripts/conferir-ponte.cjs CLAUDE.md"

echo
echo "== (k) executa cada linha do bloco de exemplos de skills/ponte/SKILL.md =="
REPO_K="$CAIXA/repo-k"
mkdir -p "$REPO_K/.github/workflows"
cat > "$REPO_K/package.json" <<'EOF'
{
  "name": "teste-k",
  "scripts": {
    "test": "npm test"
  }
}
EOF
cat > "$REPO_K/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
mkdir -p "$REPO_K/src"

REPO_K_WIN="$(cygpath -m "$REPO_K" 2>/dev/null || printf '%s' "$REPO_K")"

# Extrai o bloco shell-node-ponte-exemplos do SKILL.md
SKILL_PONTE_FULL="$SRC/skills/ponte/SKILL.md"
BLOCOS=$(sed -n '/```shell-node-ponte-exemplos/,/```/p' "$SKILL_PONTE_FULL" | sed '1d;$d' | grep -v '^#' | grep -v '^$')

# Cria arquivo JSON de respostas
RESPOSTAS_K="$CAIXA/respostas-k.json"
cat > "$RESPOSTAS_K" <<'EOF'
{
  "pronto": "Testes passam",
  "nao_toca": "Dependências",
  "convencao": "Português",
  "revisao": "Uma aprovação"
}
EOF
RESPOSTAS_K_WIN="$(cygpath -m "$RESPOSTAS_K" 2>/dev/null || printf '%s' "$RESPOSTAS_K")"

# Substitui placeholders e executa cada linha
while IFS= read -r linha; do
  # Ignora linhas vazias e comentários
  [[ -z "$linha" || "$linha" =~ ^# ]] && continue

  # Substitui placeholders
  cmd=$(echo "$linha" | sed "s|/tmp/repo-exemplo|$REPO_K_WIN|g" | sed "s|/tmp/respostas.json|$RESPOSTAS_K_WIN|g")

  if bash -c "$cmd" >/dev/null 2>&1; then
    ok=$((ok+1)); echo "  ok   $cmd"
  else
    falhou=$((falhou+1)); echo "  FALHA $cmd"; fi
done <<< "$BLOCOS"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
