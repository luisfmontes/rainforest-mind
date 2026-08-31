#!/bin/bash
# Bateria de `hooks/lib/poda-estagio.cjs` — resolve estágio ativo por branch git
#
# O que esta bateria precisa provar:
#   1. com um trabalho aberto cuja slug bate com a branch git, devolve {slug, estagio};
#   2. com dois trabalhos, um batendo e outro não, devolve o certo;
#   3. sem nenhum trabalho aberto, sem repo git, ou com branch não batendo, devolve null;
#   4. mutação: sem a checagem de branch, pega sempre o primeiro (aqui falha a mutação).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SB)"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }

# --- Fixture 1: um trabalho aberto cujo slug bate com a branch ---
echo
echo "== 1. um trabalho aberto com slug batendo a branch =="
mkdir -p "$SBP/proj/docs/rainforest/estado"
( cd "$SBP/proj" && git init -q && touch .gitkeep && git add .gitkeep && git commit -q -m init )
( cd "$SBP/proj" && git checkout -q -b "memory-e-dados-do-rainforest" 2>/dev/null || true )

# Cria um arquivo de estado com slug que bate a branch (sem a data)
cat > "$SBP/proj/docs/rainforest/estado/2026-08-17-memory-e-dados-do-rainforest.json" <<'EOF'
{
  "slug": "2026-08-17-memory-e-dados-do-rainforest",
  "titulo": "Test work",
  "criado_em": "2026-08-17",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

RESULT="$(cd "$SBP/proj" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
ESPERADO='{"slug":"2026-08-17-memory-e-dados-do-rainforest","estagio":"plano"}'
igual "retorna {slug, estagio} do trabalho certo" "$ESPERADO" "$RESULT"

# --- Fixture 2: dois trabalhos, um batendo e outro não ---
echo
echo "== 2. dois trabalhos abertos, um batendo a branch =="
cat > "$SBP/proj/docs/rainforest/estado/2026-08-15-outro-trabalho.json" <<'EOF'
{
  "slug": "2026-08-15-outro-trabalho",
  "titulo": "Other work",
  "criado_em": "2026-08-15",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

RESULT2="$(cd "$SBP/proj" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
igual "retorna o trabalho que bate, ignorando o outro" "$ESPERADO" "$RESULT2"

# --- Fixture 3: sem trabalhos abertos ---
echo
echo "== 3. sem trabalhos abertos devolve null =="
rm -f "$SBP/proj/docs/rainforest/estado/"*.json
RESULT3="$(cd "$SBP/proj" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
igual "sem trabalhos abertos" "null" "$RESULT3"

# --- Fixture 4: trabalho completo (nenhum estágio pendente) ---
echo
echo "== 4. trabalho completo (sem pendentes) devolve null =="
cat > "$SBP/proj/docs/rainforest/estado/2026-08-17-memory-e-dados-do-rainforest.json" <<'EOF'
{
  "slug": "2026-08-17-memory-e-dados-do-rainforest",
  "titulo": "Completed work",
  "criado_em": "2026-08-17",
  "design": {"status": "ok"},
  "plano": {"status": "ok"},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"},
  "fechar": {"status": "ok"}
}
EOF

RESULT4="$(cd "$SBP/proj" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
igual "trabalho sem pendentes" "null" "$RESULT4"

# --- Fixture 5: branch não bate nenhum slug ---
echo
echo "== 5. branch não bate nenhum slug devolve null =="
( cd "$SBP/proj" && git checkout -q -b "outra-branch" 2>/dev/null || true )
cat > "$SBP/proj/docs/rainforest/estado/2026-08-17-memory-e-dados-do-rainforest.json" <<'EOF'
{
  "slug": "2026-08-17-memory-e-dados-do-rainforest",
  "titulo": "Test work",
  "criado_em": "2026-08-17",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

RESULT5="$(cd "$SBP/proj" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
igual "branch sem match" "null" "$RESULT5"

# --- Fixture 6: sem repo git ---
echo
echo "== 6. sem repo git devolve null =="
mkdir -p "$SBP/nao-git/docs/rainforest/estado"
cat > "$SBP/nao-git/docs/rainforest/estado/2026-08-17-memory-e-dados-do-rainforest.json" <<'EOF'
{
  "slug": "2026-08-17-memory-e-dados-do-rainforest",
  "titulo": "Test work",
  "criado_em": "2026-08-17",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

RESULT6="$(cd "$SBP/nao-git" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"
igual "sem repo git" "null" "$RESULT6"

# --- CLI direto ---
echo
echo "== 7. CLI direto funciona =="
( cd "$SBP/proj" && git checkout -q "memory-e-dados-do-rainforest" 2>/dev/null || true )
cat > "$SBP/proj/docs/rainforest/estado/2026-08-17-memory-e-dados-do-rainforest.json" <<'EOF'
{
  "slug": "2026-08-17-memory-e-dados-do-rainforest",
  "titulo": "Test work",
  "criado_em": "2026-08-17",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

CLI_RESULT="$(cd "$SBP/proj" && node "$SRC/hooks/lib/poda-estagio.cjs")"
igual "CLI direto devolve JSON" "$ESPERADO" "$CLI_RESULT"

# --- MUTAÇÃO ---
echo
echo "== 8. MUTAÇÃO — sem checagem de branch, pega o primeiro =="
# Cria repo nova para mutação, com trabalhos nomeados para ordem previsível
mkdir -p "$SBP/mut/docs/rainforest/estado"
( cd "$SBP/mut" && git init -q && touch .gitkeep && git add .gitkeep && git commit -q -m init )
# Coloca em branch que nao bate nenhum trabalho
( cd "$SBP/mut" && git checkout -q -b "branch-sem-match" 2>/dev/null || true )

# Cria dois trabalhos:  aquele que NÃO bate ANTES do que bate (nomes alfabéticos garantem ordem)
cat > "$SBP/mut/docs/rainforest/estado/0001-nao-bate.json" <<'EOF'
{
  "slug": "2026-08-10-nao-bate",
  "titulo": "This one does NOT match branch",
  "criado_em": "2026-08-10",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

cat > "$SBP/mut/docs/rainforest/estado/0002-sim-bate.json" <<'EOF'
{
  "slug": "2026-08-17-branch-sem-match",
  "titulo": "This one DOES match branch",
  "criado_em": "2026-08-17",
  "arqueologia": {"status": "dispensada"},
  "design": {"status": "ok"},
  "plano": {"status": "pendente"},
  "executar": {"status": "pendente"},
  "revisar": {"status": "pendente"},
  "verificar": {"status": "pendente"},
  "fechar": {"status": "pendente"}
}
EOF

# Sem mutação, deve pegar o segundo (que bate)
NORMAL_RESULT="$(cd "$SBP/mut" && node -e "
  const {estagioAtivo} = require('$SRC_WIN/hooks/lib/poda-estagio.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"

# Copia e muta o arquivo
cp "$SRC/hooks/lib/poda-estagio.cjs" "$SBP/poda-estagio-mutante.cjs"
node - "$SBP/poda-estagio-mutante.cjs" <<'JS'
const fs = require("fs");
const alvo = process.argv[2];
const antes = fs.readFileSync(alvo, "utf8");
// Muta: retorna sempre o primeiro trabalho, ignorando branch
const de = "  // Exatamente um match → retorna o estágio ativo\n  if (matches.length === 1) {\n    const estagio = proximoEstagio(matches[0].estado);\n    return estagio\n      ? {\n          slug: matches[0].slug,\n          estagio,\n        }\n      : null;\n  }\n\n  // Zero ou ambíguo → não adivinha\n  return null;";
if (!antes.includes(de)) throw new Error("ancora nao encontrada");
const depois = antes.replace(de, "  // MUTACAO: sempre pega o primeiro, sem checar branch\n  if (abertos.length >= 1) {\n    const estagio = proximoEstagio(abertos[0].estado);\n    return estagio\n      ? {\n          slug: abertos[0].slug,\n          estagio,\n        }\n      : null;\n  }\n  return null;");
if (depois === antes) throw new Error("mutacao nao foi aplicada");
fs.writeFileSync(alvo, depois, "utf8");
JS

MUT_RESULT="$(cd "$SBP/mut" && node -e "
  const {estagioAtivo} = require('$SB/poda-estagio-mutante.cjs');
  const r = estagioAtivo({cwd: process.cwd()});
  process.stdout.write(r ? JSON.stringify(r) : 'null');
")"

# Com a mutação, deve pegar o PRIMEIRO (0001-nao-bate), não o segundo que realmente bate
MUT_ESPERADO='{"slug":"2026-08-10-nao-bate","estagio":"plano"}'
NORMAL_ESPERADO='{"slug":"2026-08-17-branch-sem-match","estagio":"plano"}'

if [ "$NORMAL_RESULT" = "$NORMAL_ESPERADO" ] && [ "$MUT_RESULT" = "$MUT_ESPERADO" ]; then
  ok=$((ok+1)); echo "  ok   mutacao prova a checagem de branch (sem ela pega o primeiro)"
else
  falhou=$((falhou+1)); echo "  FALHA normal foi '$NORMAL_RESULT' (esperava '$NORMAL_ESPERADO'), mutante foi '$MUT_RESULT' (esperava '$MUT_ESPERADO')"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
