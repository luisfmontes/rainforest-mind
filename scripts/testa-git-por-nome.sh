#!/bin/bash
# Bateria de detecção de chamadas ao git/gh por nome em vez de pelo caminho absoluto.
# Varre hooks/ e scripts/ procurando por spawn/spawnSync/execFile/execFileSync/exec/execSync
# que usam strings 'git', 'gh' ou iniciadas por 'git ', 'gh ' como primeiro argumento,
# e também padrões como || "git" ou || 'gh'.
# @categoria: bateria

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

ok=0
falhou=0

# Detecta spawn/exec com 'git'/'gh' como primeiro argumento
detectar_git_gh_por_nome() {
  local arquivo="$1" crase=$'\x60'
  # Detecta: spawn/exec*('git'/'gh', ...) ou exec/execSync('git '...) ou || "git"/"gh"
  grep -nE "(spawn|spawnSync|execFile|execFileSync)\s*\(\s*(['\"])(git|gh)\2(\s|['\"]|,)|(exec|execSync)\s*\(\s*['\"\`](git|gh)\s|\|\|\s*['\"]+(git|gh)['\"]+" "$arquivo" || true
}

echo "== Detecção de chamadas a git/gh por nome (caminhoExecutavel obrigatório) =="
echo

# =========== Caso 1: helper caminhoExecutavel com PATH real ===========
echo "1. helper caminhoExecutavel com PATH real"
echo

cat > /tmp/tg1.cjs << 'EOFN1'
const path = require('path');
const fs = require('fs');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));
const caminho = caminhoExecutavel('git');
console.log('caminho:', caminho);
console.log('absoluto:', path.isAbsolute(caminho));
console.log('existe:', fs.existsSync(caminho));
EOFN1

resultado=$(node /tmp/tg1.cjs "$SRC" 2>&1)

if echo "$resultado" | grep -q "absoluto: true" && echo "$resultado" | grep -q "existe: true"; then
  ok=$((ok+1))
  echo "  ok   caminhoExecutavel('git') é absoluto e existe"
else
  falhou=$((falhou+1))
  echo "  FALHA caminhoExecutavel('git') não devolveu caminho válido"
fi

echo

# =========== Caso 2: PATH com . na frente não resolve pela pasta atual ===========
echo "2. PATH com . na frente não resolve pela pasta atual"
echo

SBP="$(novo_sandbox)"
cp /c/Windows/System32/whoami.exe "$SBP/git.exe"

cat > /tmp/tg2a.cjs << 'EOFN2a'
const path = require('path');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));
const realDir = path.dirname(caminhoExecutavel('git'));
console.log(realDir);
EOFN2a

REAL_GIT_DIR=$(node /tmp/tg2a.cjs "$SRC" 2>&1)

cat > /tmp/tg2b.cjs << 'EOFN2b'
const path = require('path');
const src = process.argv[2];
const realDir = process.argv[3];
const { resolverExecutavel, caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));

const env = {};
Object.keys(process.env).forEach(k => {
  if (k.toUpperCase() !== 'PATH') env[k] = process.env[k];
});
env.PATH = '.' + path.delimiter + realDir;

const r1 = resolverExecutavel('git', env);
const r2 = caminhoExecutavel('git', env);
const falso = path.join(process.cwd(), 'git.exe').toLowerCase();
const r1_abs = r1 ? path.resolve(r1).toLowerCase() : '';
const r2_abs = r2 ? path.resolve(r2).toLowerCase() : '';

console.log('r1_nao_eh_falso:', r1_abs !== falso);
console.log('r2_nao_eh_falso:', r2_abs !== falso);
EOFN2b

resultado=$(cd "$SBP" && node /tmp/tg2b.cjs "$SRC" "$REAL_GIT_DIR" 2>&1)

if echo "$resultado" | grep -q "r1_nao_eh_falso: true" && echo "$resultado" | grep -q "r2_nao_eh_falso: true"; then
  ok=$((ok+1))
  echo "  ok   PATH com . na frente não resolve pelo falso"
else
  falhou=$((falhou+1))
  echo "  FALHA PATH com . resolveu para o falso ou ocorreu erro"
fi

echo

# =========== Caso 3: .cmd antes de .exe ===========
echo "3. .cmd antes de .exe"
echo

SBP3="$(novo_sandbox)"
DIRCMD="$SBP3/dir-cmd"
DIREXE="$SBP3/dir-exe"
mkdir -p "$DIRCMD" "$DIREXE"

echo '@echo off' > "$DIRCMD/x.cmd"
cp /c/Windows/System32/whoami.exe "$DIREXE/x.exe"

cat > /tmp/tg3.cjs << 'EOFN3'
const path = require('path');
const src = process.argv[2];
const dirCmd = process.argv[3];
const dirExe = process.argv[4];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));

const env = {};
Object.keys(process.env).forEach(k => {
  if (k.toUpperCase() !== 'PATH') env[k] = process.env[k];
});
env.PATH = dirCmd + path.delimiter + dirExe;

const r = caminhoExecutavel('x', env);
const esperado = path.join(dirExe, 'x.exe').toLowerCase();
const resultado = path.resolve(r).toLowerCase();

console.log('match:', resultado === esperado);
EOFN3

resultado=$(node /tmp/tg3.cjs "$SRC" "$DIRCMD" "$DIREXE" 2>&1)

if echo "$resultado" | grep -q "match: true"; then
  ok=$((ok+1))
  echo "  ok   caminhoExecutavel devolveu .exe"
else
  falhou=$((falhou+1))
  echo "  FALHA .exe não foi preferido"
fi

echo

# =========== Caso 4: ausente dá ENOENT com caminho absoluto ===========
echo "4. ausente dá ENOENT com caminho absoluto"
echo

cat > /tmp/tg4.cjs << 'EOFN4'
const { spawnSync } = require('child_process');
const path = require('path');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));

const caminho = caminhoExecutavel('nao-existe-xyz-123456');
const result = spawnSync(caminho, [], { encoding: 'utf-8' });

console.log('codigo_erro:', result.error && result.error.code);
console.log('absoluto:', path.isAbsolute(caminho));
EOFN4

resultado=$(node /tmp/tg4.cjs "$SRC" 2>&1)

if echo "$resultado" | grep -q "codigo_erro: ENOENT" && echo "$resultado" | grep -q "absoluto: true"; then
  ok=$((ok+1))
  echo "  ok   ENOENT com caminho absoluto"
else
  falhou=$((falhou+1))
  echo "  FALHA Não foi ENOENT ou caminho não era absoluto"
fi

echo

# =========== Caso 5: varredura de git/gh por nome no repositório ===========
echo "5. varredura de git/gh por nome em hooks/ e scripts/"
echo

encontrou_algum=0

find "$SRC/hooks" "$SRC/scripts" -type f \( -name '*.cjs' -o -name '*.mjs' -o -name '*.js' -o -name '*.tsx' \) -print0 | while IFS= read -r -d '' arquivo; do
  basename_arquivo=$(basename "$arquivo")
  if [[ "$basename_arquivo" == testa-* ]] || [[ "$basename_arquivo" == *.test.* ]]; then
    continue
  fi

  if [[ "$arquivo" == *"hooks/lib/resolver-executavel.cjs" ]]; then
    continue
  fi

  resultado=$(detectar_git_gh_por_nome "$arquivo" | grep -vE '^[0-9]+:[[:space:]]*(//|\*)') || true

  if [ -n "$resultado" ]; then
    encontrou_algum=1
    while IFS= read -r linha; do
      if [ -n "$linha" ]; then
        num_linha="$(echo "$linha" | cut -d: -f1)"
        trecho="$(echo "$linha" | cut -d: -f2-)"
        arquivo_rel="${arquivo#$SRC/}"
        echo "  $arquivo_rel:$num_linha:$trecho"
      fi
    done <<< "$resultado"
  fi
done

if [ "$encontrou_algum" -eq 0 ]; then
  ok=$((ok+1))
  echo "  ok   nenhum git/gh por nome fora de bateria"
else
  echo "  NOTA varredura encontrou ocorrências (esperado das tarefas 2-6)"
fi

echo

# =========== Caso 6: detector acende com três formas ===========
echo "6. detector acende com três formas de git/gh por nome"
echo

SBP6="$(novo_sandbox)"
arquivo_teste="$SBP6/teste-git-por-nome.cjs"

cat > "$arquivo_teste" <<'EOF'
const { spawn } = require('child_process');
spawn('git', ['status']);
execSync('git log');
|| "gh"
// spawnSync("git")
EOF

resultado_teste="$(detectar_git_gh_por_nome "$arquivo_teste")" || true
resultado_teste_sem_coment=$(echo "$resultado_teste" | grep -vE '^[0-9]+:[[:space:]]*(//|\*)' | grep -v '^$') || true
n_linhas=$(echo "$resultado_teste_sem_coment" | wc -l | tr -d ' ')

if [ "$n_linhas" = "3" ]; then
  ok=$((ok+1))
  echo "  ok   detector identificou 3 formas"
else
  falhou=$((falhou+1))
  echo "  FALHA esperava 3, encontrou $n_linhas"
fi

echo

# =========== Caso 7: entrada real ===========
echo "7. entrada real: conferir-versao com git falso"
echo

SBP7="$(novo_sandbox)"
cp /c/Windows/System32/whoami.exe "$SBP7/git.exe"

prova=$(cd "$SBP7" && env -u NoDefaultCurrentDirectoryInExePath node -e "
const { spawnSync } = require('child_process');
const result = spawnSync('git', [], { encoding: 'utf-8' });
const saida = (result.stdout + result.stderr).replace(/\r/g, '');
console.log(saida);
" 2>&1)

if echo "$prova" | grep -qE '\\'; then
  echo "  7(i) ok   falso ao alcance"
else
  echo "  7(i) FALHA fixture"
  falhou=$((falhou+1))
fi

teste_conf=$(cd "$SBP7" && env -u NoDefaultCurrentDirectoryInExePath node "$SRC/scripts/conferir-versao.cjs" 2>&1) || true
teste_conf=$(echo "$teste_conf" | tr -d '\r')

if ! echo "$teste_conf" | grep -qE '\\'; then
  ok=$((ok+1))
  echo "  7(ii) ok  conferir-versao seguro"
else
  echo "  7(ii) FALHA conferir-versao rodou o falso"
  falhou=$((falhou+1))
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
