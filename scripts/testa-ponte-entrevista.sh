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
cp "$SRC/scripts/ponte.cjs" "$PLUG/scripts/"
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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
