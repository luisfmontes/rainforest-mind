#!/bin/bash
# Bateria do scripts/release-da-versao.cjs — publica a release da versão do manifesto.
# Uso: bash scripts/testa-release-da-versao.sh
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR: a release de uma versão nova não sair, ou
# sair duas vezes, ou sair com as notas de outra versão. O `gh` é um stub que
# registra cada chamada; a bateria nunca chama o gh real. Antes dos casos, o gate
# prova que o PATH com o stub acha o stub e que o PATH sem ele não acha gh.
# Design docs/rainforest/design/2026-10-30-release-automatica.md, D5.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/release-da-versao.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
afirma() { # nome, status (0 = passou)
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1"; fi
}

S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
BIN="$S/bin"; REPO="$S/repo"; DADOS_PLUGIN="$REPO/.claude-plugin"
SAIDA="$S/saida.txt"; ERRO="$S/erro.txt"
LOG="$S/log.txt"; NOTAS="$S/notas-stub.txt"
mkdir -p "$BIN" "$DADOS_PLUGIN"
BIN_W="$(cygpath -m "$BIN" 2>/dev/null || printf '%s' "$BIN")"
RAIZ_W="$(cygpath -m "$RAIZ" 2>/dev/null || printf '%s' "$RAIZ")"
LOG_W="$(cygpath -m "$LOG" 2>/dev/null || printf '%s' "$LOG")"
NOTAS_W="$(cygpath -m "$NOTAS" 2>/dev/null || printf '%s' "$NOTAS")"

# ----------------------------------------------------- stub de gh (caminho POSIX)
# `gh` (shell) para `command -v gh`; `gh.cmd` + `gh-stub.js` para o resolver do
# repo, que no Windows só acha .cmd/.exe. Mesmo padrao de scripts/testa-publicar-branch.sh.
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
exec node "$(dirname "$0")/gh-stub.js" "$@"
STUB
chmod +x "$BIN/gh"
cat > "$BIN/gh.cmd" <<'STUB'
@node "%~dp0gh-stub.js" %*
STUB
cat > "$BIN/gh-stub.js" <<'STUB'
const fs = require('fs');
const args = process.argv.slice(2);
if (process.env.STUB_LOG) fs.appendFileSync(process.env.STUB_LOG, 'gh ' + args.join(' ') + '\n');
if (args[0] === 'release' && args[1] === 'view') {
  process.exit(Number(process.env.STUB_VIEW_EXIT || 1));
}
if (args[0] === 'release' && args[1] === 'create') {
  const i = args.indexOf('--notes-file');
  if (i >= 0 && process.env.STUB_NOTAS) {
    fs.copyFileSync(args[i + 1], process.env.STUB_NOTAS);
  }
  process.exit(0);
}
process.exit(0);
STUB

# ----------------------------------------------------------- ambiente de execução
NODE_DIR="$(dirname "$(command -v node)")"
GIT_DIR="$(dirname "$(command -v git)")"
PATH_COM_STUB="$BIN:$PATH"
PATH_SEM_GH="$NODE_DIR:$GIT_DIR"

# ------------------------------------------------------------------ gate
G1="$(PATH="$PATH_COM_STUB" node -e "console.log(require('$RAIZ_W/hooks/lib/resolver-executavel.cjs').resolverExecutavel('gh'))" 2>/dev/null | tr -d '\r' | tr '\\' '/')"
case "$G1" in "$BIN_W"/*) g1=0 ;; *) g1=1 ;; esac
afirma "g1: com o stub no PATH, resolverExecutavel('gh') acha o stub ($G1)" $g1
if [ "$g1" -ne 0 ]; then
  echo
  echo "-----------------------------------------"
  echo "ok: $ok   falhou: $falhou"
  echo "gate g1 falhou: os casos nao rodaram, para nao chamar o gh real"
  exit 1
fi

G2="$(PATH="$PATH_SEM_GH" node -e "console.log(require('$RAIZ_W/hooks/lib/resolver-executavel.cjs').resolverExecutavel('gh'))" 2>/dev/null | tr -d '\r')"
[ "$G2" = "null" ] && g2=0 || g2=1
afirma "g2: sem o stub no PATH, resolverExecutavel('gh') devolve null ($G2)" $g2

# ------------------------------------------------------------ o fixture
changelog_completo() {
  printf '# Notas\n\n## 9.8.7 — 2026-01-02\n- nota da nove-oito-sete\n\n## 9.8.6 — 2026-01-01\n- nota da nove-oito-seis\n' > "$REPO/CHANGELOG.md"
}
printf '{"version": "9.8.7"}\n' > "$DADOS_PLUGIN/plugin.json"
changelog_completo

# Roda o script no repo falso. STDOUT vai para $SAIDA, STDERR para $ERRO.
roda() {
  (PATH="$PATH_COM_STUB" node "$SCRIPT" --sha abc123 --raiz "$REPO") > "$SAIDA" 2> "$ERRO"
  CODIGO=$?
}
zera() { rm -f "$LOG" "$NOTAS"; }
tem_create() { [ -f "$LOG" ] && grep -q 'release create' "$LOG"; }

# ----------------------------------------------------------------- os casos
echo
zera
export STUB_LOG="$LOG_W" STUB_NOTAS="$NOTAS_W"
STUB_VIEW_EXIT=1 roda
afirma "(a) release inexistente: exit 0" $CODIGO
grep -q 'release create v9.8.7' "$LOG" 2>/dev/null; afirma "(a) create com a tag v9.8.7" $?
grep -q -- '--target abc123' "$LOG" 2>/dev/null; afirma "(a) create com --target abc123" $?
grep -q 'rainforest-mind 9.8.7' "$LOG" 2>/dev/null; afirma "(a) create com titulo 'rainforest-mind 9.8.7'" $?
grep -q 'nota da nove-oito-sete' "$NOTAS" 2>/dev/null; afirma "(a) notas contem a secao 9.8.7" $?
cp -f "$NOTAS" "$S/notas-a.txt" 2>/dev/null

zera
STUB_VIEW_EXIT=0 roda
afirma "(b) release existente: exit 0" $CODIGO
if tem_create; then s=1; else s=0; fi
afirma "(b) release existente: nenhum release create" $s
grep -q 'já existe' "$SAIDA"; afirma "(b) release existente: mensagem 'ja existe'" $?

zera
printf '# Notas\n\n## 9.8.6 — 2026-01-01\n- nota da nove-oito-seis\n' > "$REPO/CHANGELOG.md"
STUB_VIEW_EXIT=1 roda
changelog_completo
afirma "(c) secao ausente: exit 1" $([ "$CODIGO" -eq 1 ] && echo 0 || echo 1)
if tem_create; then s=1; else s=0; fi
afirma "(c) secao ausente: nenhum release create" $s
grep -q 'CHANGELOG sem a seção 9.8.7' "$ERRO"; afirma "(c) secao ausente: stderr diz 'CHANGELOG sem a seção 9.8.7'" $?

# (d) usa as notas do caso (a), capturadas acima.
if [ -f "$S/notas-a.txt" ] && ! grep -q 'nove-oito-seis' "$S/notas-a.txt" && ! grep -q '^## ' "$S/notas-a.txt"; then s=0; else s=1; fi
afirma "(d) notas param antes da secao seguinte (sem nove-oito-seis, sem '## ')" $s

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
