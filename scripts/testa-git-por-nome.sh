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

# Pasta temporaria propria: nada de nome fixo em /tmp (duas rodadas simultaneas se atropelariam).
TMPB="$(novo_sandbox)"

# Detector em Node: qualquer chamada com 'git'/'gh' literal no primeiro argumento (spawnSync,
# rodar, ...), chamada quebrada em duas linhas, execSync de string, || 'gh', e subprocess com
# ["git", ...] em .py. Comentario nao conta. A versao por grep de linha deixava passar o
# rodar('git', ...) do saude.cjs e o spawnSync(\n "git" do ideias.cjs (revisao, rodada 1).
cat > "$TMPB/detector.cjs" <<'EOFDET'
// Detector de git/gh chamado pelo nome. Uso: node detector.cjs <arquivo>
// Imprime "linha:trecho" por ocorrencia. Linha que termina em "(" junta com a
// seguinte (chamada quebrada em duas linhas). Comentario nao conta.
const fs = require("fs");
const arquivo = process.argv[2];
const py = /\.py$/.test(arquivo);
const linhas = fs.readFileSync(arquivo, "utf8").split(/\r?\n/);
const comentario = py ? /^\s*#/ : /^\s*(\/\/|\*|\/\*)/;
const SEGUROS = new Set(["executar", "caminhoExecutavel", "resolverExecutavel", "require"]);
const NOME = "(git|gh)";
const Q = "['\"`]";
const padroes = py
  ? [new RegExp("\\[\\s*['\"]" + NOME + "['\"]\\s*,")]
  : [
      // qualquer chamada com o nome literal no primeiro argumento: spawnSync('git', ...), rodar('git', ...)
      new RegExp("([A-Za-z_$][\\w$]*)\\s*\\(\\s*" + Q + NOME + Q + "\\s*,"),
      // comando inteiro numa string: execSync('git status'), exec(`gh pr ...`)
      new RegExp("\\b(exec|execSync)\\s*\\(\\s*" + Q + NOME + "\\s"),
      // nome como padrao de variavel: x || 'gh'
      new RegExp("\\|\\|\\s*['\"]" + NOME + "['\"]"),
    ];
for (let i = 0; i < linhas.length; i++) {
  if (comentario.test(linhas[i])) continue;
  let texto = linhas[i];
  if (/\(\s*$/.test(texto) && i + 1 < linhas.length) texto += " " + linhas[i + 1].trim();
  for (const p of padroes) {
    const m = texto.match(p);
    if (!m) continue;
    if (!py && p === padroes[0] && SEGUROS.has(m[1])) continue;
    console.log(`${i + 1}:${linhas[i].trim()}`);
    break;
  }
}
EOFDET
detectar_git_gh_por_nome() { node "$TMPB/detector.cjs" "$1"; }

echo "== Detecção de chamadas a git/gh por nome (caminhoExecutavel obrigatório) =="
echo

# =========== Caso 1: helper caminhoExecutavel com PATH real ===========
echo "1. helper caminhoExecutavel com PATH real"
echo

cat > $TMPB/tg1.cjs << 'EOFN1'
const path = require('path');
const fs = require('fs');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));
const caminho = caminhoExecutavel('git');
console.log('caminho:', caminho);
console.log('absoluto:', path.isAbsolute(caminho));
console.log('existe:', fs.existsSync(caminho));
EOFN1

resultado=$(node $TMPB/tg1.cjs "$SRC" 2>&1)

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

cat > $TMPB/tg2a.cjs << 'EOFN2a'
const path = require('path');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));
const realDir = path.dirname(caminhoExecutavel('git'));
console.log(realDir);
EOFN2a

REAL_GIT_DIR=$(node $TMPB/tg2a.cjs "$SRC" 2>&1)

cat > $TMPB/tg2b.cjs << 'EOFN2b'
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

resultado=$(cd "$SBP" && node $TMPB/tg2b.cjs "$SRC" "$REAL_GIT_DIR" 2>&1)

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

cat > $TMPB/tg3.cjs << 'EOFN3'
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

resultado=$(node $TMPB/tg3.cjs "$SRC" "$DIRCMD" "$DIREXE" 2>&1)

if echo "$resultado" | grep -q "match: true"; then
  ok=$((ok+1))
  echo "  ok   caminhoExecutavel devolveu .exe"
else
  falhou=$((falhou+1))
  echo "  FALHA .exe não foi preferido"
fi

echo

echo
echo "3b. entrada do PATH entre aspas e diretorio com o nome do executavel"
echo
SB3B="$(novo_sandbox)"
mkdir -p "$SB3B/git.exe"
cat > "$TMPB/tg3b.cjs" << 'EOFN3B'
const path = require('path');
const { spawnSync } = require('child_process');
const [src, dirFalso] = process.argv.slice(2);
const r = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));
const real = r.caminhoExecutavel('git');
const dirReal = path.dirname(real);
const Q = String.fromCharCode(34);
// (a) entrada entre aspas: o libuv acha, o resolvedor tem de achar o mesmo
const envA = { PATH: Q + dirReal + Q };
const libuv = spawnSync('git', ['--version'], { env: { ...envA, SystemRoot: process.env.SystemRoot }, encoding: 'utf8' });
const a = r.caminhoExecutavel('git', envA);
console.log('aspas-libuv:', libuv.status === 0);
console.log('aspas-resolvedor:', a === real);
// (b) pasta chamada git.exe antes do git real: nao e executavel, segue o PATH
const envB = { PATH: dirFalso + ';' + dirReal };
console.log('diretorio:', r.caminhoExecutavel('git', envB) === real && r.resolverExecutavel('git', envB) !== path.join(dirFalso, 'git.exe'));
EOFN3B
resultado=$(node "$TMPB/tg3b.cjs" "$SRC" "$SB3B" 2>&1)
if echo "$resultado" | grep -q 'aspas-libuv: true' && echo "$resultado" | grep -q 'aspas-resolvedor: true' && echo "$resultado" | grep -q 'diretorio: true'; then
  ok=$((ok+1)); echo "  ok   entrada entre aspas resolve como no libuv; pasta git.exe e pulada"
else
  falhou=$((falhou+1)); echo "  FALHA aspas/diretorio: $resultado"
fi

# =========== Caso 4: ausente dá ENOENT com caminho absoluto ===========
echo "4. ausente dá ENOENT com caminho absoluto"
echo

cat > $TMPB/tg4.cjs << 'EOFN4'
const { spawnSync } = require('child_process');
const path = require('path');
const src = process.argv[2];
const { caminhoExecutavel } = require(path.join(src, 'hooks', 'lib', 'resolver-executavel.cjs'));

const caminho = caminhoExecutavel('nao-existe-xyz-123456');
const result = spawnSync(caminho, [], { encoding: 'utf-8' });

console.log('codigo_erro:', result.error && result.error.code);
console.log('absoluto:', path.isAbsolute(caminho));
EOFN4

resultado=$(node $TMPB/tg4.cjs "$SRC" 2>&1)

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

# Sem pipe: o while num pipe roda em subshell e encontrou_algum se perderia.
while IFS= read -r -d '' arquivo; do
  basename_arquivo=$(basename "$arquivo")
  if [[ "$basename_arquivo" == testa-* ]] || [[ "$basename_arquivo" == *.test.* ]]; then
    continue
  fi

  if [[ "$arquivo" == *"hooks/lib/resolver-executavel.cjs" ]]; then
    continue
  fi

  resultado=$(detectar_git_gh_por_nome "$arquivo") || true

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
done < <(find "$SRC/hooks" "$SRC/scripts" -type f \( -name '*.cjs' -o -name '*.mjs' -o -name '*.js' -o -name '*.tsx' -o -name '*.py' \) ! -name 'test_*' -print0)

if [ "$encontrou_algum" -eq 0 ]; then
  ok=$((ok+1))
  echo "  ok   nenhum git/gh por nome fora de bateria"
else
  falhou=$((falhou+1))
  echo "  FALHA git/gh chamado por nome nas linhas acima"
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
const gh = process.env.X || "gh";
rodar('git', ['rev-parse', 'HEAD'], { cwd });
r = spawnSync(
  "git",
  ['log']);
// spawnSync("git", ['x'])
executar('gh', ['pr', 'list']);
spawnSync(caminhoExecutavel('git'), ['status']);
EOF
arquivo_py="$SBP6/teste_git.py"
cat > "$arquivo_py" <<'EOF'
import subprocess
subprocess.run(["git", "status"])
# subprocess.run(["git", "x"])
subprocess.run([_caminho_git(), "status"])
EOF
n_js=$(detectar_git_gh_por_nome "$arquivo_teste" | grep -c .)
n_py=$(detectar_git_gh_por_nome "$arquivo_py" | grep -c .)
if [ "$n_js" = "5" ] && [ "$n_py" = "1" ]; then
  ok=$((ok+1))
  echo "  ok   detector acende em 5 formas JS (literal, execSync, || gh, wrapper, duas linhas) e 1 Python; comentario e caminho resolvido nao acendem"
else
  falhou=$((falhou+1))
  echo "  FALHA esperava 5 JS e 1 Python, encontrou $n_js e $n_py"
  detectar_git_gh_por_nome "$arquivo_teste"; detectar_git_gh_por_nome "$arquivo_py"
fi

echo

# =========== Caso 7: entrada real ===========
echo "7. entrada real: conferir-versao com git falso"
echo

SBP7="$(novo_sandbox)"
# git.exe falso = copia do node.exe: `git rev-parse ...` roda o arquivo rev-parse
# desta pasta, que grava a marca FALSO_RODOU. Marca no disco = o falso rodou.
cp "$(node -p process.execPath)" "$SBP7/git.exe"
echo 'require("fs").writeFileSync(require("path").join(__dirname, "FALSO_RODOU"), "")' > "$SBP7/rev-parse"

(cd "$SBP7" && env -u NoDefaultCurrentDirectoryInExePath node -e 'require("child_process").spawnSync("git", ["rev-parse", "--show-toplevel"])') >/dev/null 2>&1
if [ -f "$SBP7/FALSO_RODOU" ]; then
  ok=$((ok+1)); echo "  7(i) ok   spawnSync('git') por nome roda o falso da pasta atual (fixture alcanca)"
else
  falhou=$((falhou+1)); echo "  7(i) FALHA fixture nao alcanca o falso: a medicao abaixo nao provaria nada"
fi
rm -f "$SBP7/FALSO_RODOU"

(cd "$SBP7" && env -u NoDefaultCurrentDirectoryInExePath node "$SRC/scripts/conferir-versao.cjs") >/dev/null 2>&1
if [ ! -f "$SBP7/FALSO_RODOU" ]; then
  ok=$((ok+1)); echo "  7(ii) ok  conferir-versao com git.exe falso na pasta atual nao o roda"
else
  falhou=$((falhou+1)); echo "  7(ii) FALHA conferir-versao rodou o git.exe da pasta atual"
fi
echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
