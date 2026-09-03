#!/bin/bash
# Bateria para scripts/fechar-issue.cjs com trava: verifica que gh é do sandbox

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar repositório git na caixa de areia (para validação de caminho)
(cd "$SBP" && git init . >/dev/null 2>&1 && git config user.email "t@t" && git config user.name "Test")

# Criar stub em batch
mkdir -p "$SBP/bin"
cat > "$SBP/bin/gh.cmd" <<'STUB'
@node "%~dp0gh-stub.js" %*
STUB
# Stub em Node, nao em batch: o batch com `enabledelayedexpansion` escrevia o log
# num arquivo chamado literalmente `!GH_LOG!` quando rodava sob a suite inteira
# (expansao atrasada nao valia), e a bateria ficava vermelha so em paralelo.
cat > "$SBP/bin/gh-stub.js" <<'STUB'
const fs = require("fs");
const args = process.argv.slice(2);
const log = process.env.GH_LOG;
const EOL = require("os").EOL;
if (log) {
  fs.appendFileSync(log, "CHAMADA: gh " + args.join(" ") + EOL);
  const i = args.indexOf("--body-file");
  if (i >= 0 && args[i + 1]) {
    fs.appendFileSync(log, "CORPO:" + EOL + fs.readFileSync(args[i + 1], "utf8") + EOL + "---" + EOL);
  }
}
if (args[0] === "issue" && args[1] === "comment" && process.env.GH_COMMENT_FAIL) process.exit(1);
if (args[0] === "issue" && args[1] === "view" && args[3] === "--json" && args[4] === "body") {
  const com = process.env.GH_CORPO_COM_CRITERIO === "1";
  const body = com
    ? "Como reproduzir: passo1 passo2 ## Criterio de pronto (falsificavel) comando esperado"
    : "Como reproduzir: passo1 passo2";
  process.stdout.write(JSON.stringify({ body }) + EOL);
  process.exit(0);
}
process.exit(0);
STUB

# TRAVA: verificar que gh resolvido é do sandbox, não do sistema
echo "== TRAVA: verificar que gh é do sandbox =="
(
  export PATH="$SBP/bin:$PATH"
  node "$SRC/scripts/fechar-issue.cjs" --verificar-gh "$SBP/bin"
) >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "  ok   gh é do sandbox"
else
  echo "  FALHA gh NÃO é do sandbox ou não encontrado"
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi

# Caso (a): corpo COM a seção → comenta e fecha
echo
echo "== (a) corpo COM critério de pronto → comenta e fecha =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-a"
  export GH_CORPO_COM_CRITERIO=1
  node "$SRC/scripts/fechar-issue.cjs" 999901 --comando "git log -1" --saida "commit abc123"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_A="$(cat "$SBP/log-a" 2>/dev/null || echo '')"
[ -n "$LOG_A" ] && {
  echo "$LOG_A" | grep -q "issue view" && test_ok "issue view chamado" || test_fail "issue view"
  echo "$LOG_A" | grep -q "issue comment" && test_ok "issue comment chamado" || test_fail "issue comment"
  echo "$LOG_A" | grep -q "issue close" && test_ok "issue close chamado" || test_fail "issue close"
  echo "$LOG_A" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
  echo "$LOG_A" | grep -q "git log -1" && test_ok "comando" || test_fail "comando"
  echo "$LOG_A" | grep -q "commit abc123" && test_ok "saída" || test_fail "saída"
} || {
  test_fail "log vazio"
  test_fail "issue view"
  test_fail "issue comment"
  test_fail "issue close"
  test_fail "marcador"
  test_fail "comando"
  test_fail "saída"
}

# Caso (b): corpo SEM a seção → exit 2, sem comentário
echo
echo "== (b) corpo SEM critério de pronto → exit 2, sem comentar nem fechar =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-b"
  unset GH_CORPO_COM_CRITERIO
  node "$SRC/scripts/fechar-issue.cjs" 999902 --comando "echo teste" --saida "ok" 2>&1
) >/dev/null
[ $? -eq 2 ] && test_ok "exit 2" || test_fail "exit code"
LOG_B="$(cat "$SBP/log-b" 2>/dev/null || echo '')"
[ -n "$LOG_B" ] && {
  echo "$LOG_B" | grep -q "issue view" && test_ok "issue view chamado" || test_fail "issue view"
  echo "$LOG_B" | grep -q "issue comment" && test_fail "issue comment foi chamado!" || test_ok "issue comment ausente"
  echo "$LOG_B" | grep -q "issue close" && test_fail "issue close foi chamado!" || test_ok "issue close ausente"
} || {
  test_fail "log vazio"
}

# Caso (c): verificar que commands/issue.md tem a seção no template
echo
echo "== (c) commands/issue.md contém a seção no template =="
grep -nF "## Critério de pronto (falsificável)" "$SRC/commands/issue.md" >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "seção no template" || test_fail "seção não encontrada"

# Caso (d): Ordem: issue comment antes de issue close
echo
echo "== (d) gh issue comment com sucesso → gh issue close é chamado (ORDEM verificada) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-d"
  export GH_CORPO_COM_CRITERIO=1
  node "$SRC/scripts/fechar-issue.cjs" 999903 --comando "git log -1" --saida "commit abc123"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_D="$(cat "$SBP/log-d" 2>/dev/null || echo '')"
[ -n "$LOG_D" ] && {
  # Verificar ordem: comment deve vir antes de close
  COMMENT_LINE=$(echo "$LOG_D" | grep -n "issue comment" | cut -d: -f1 | head -1)
  CLOSE_LINE=$(echo "$LOG_D" | grep -n "issue close" | cut -d: -f1 | head -1)
  if [ -n "$COMMENT_LINE" ] && [ -n "$CLOSE_LINE" ] && [ "$COMMENT_LINE" -lt "$CLOSE_LINE" ]; then
    test_ok "order: comment antes de close"
  else
    test_fail "order: comment antes de close"
  fi
  echo "$LOG_D" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
} || {
  test_fail "log vazio"
}

# Caso (e): comment falha, exit != 0
echo
echo "== (e) gh issue comment falha → gh issue close NUNCA é chamado =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-e"
  export GH_COMMENT_FAIL=1
  export GH_CORPO_COM_CRITERIO=1
  node "$SRC/scripts/fechar-issue.cjs" 999904 --comando "echo teste" --saida "ok"
) >/dev/null 2>&1
[ $? -ne 0 ] && test_ok "exit != 0" || test_fail "exit code"
LOG_E="$(cat "$SBP/log-e" 2>/dev/null || echo '')"
[ -n "$LOG_E" ] && {
  echo "$LOG_E" | grep -q "issue comment" && test_ok "issue comment chamado" || test_fail "issue comment"
  echo "$LOG_E" | grep -q "issue close" && test_fail "issue close exists" || test_ok "issue close ausente"
} || {
  test_fail "log vazio"
  test_fail "issue comment"
}

# Caso (f): --saida-arquivo lé arquivo
echo
echo "== (f) --saida-arquivo lê arquivo e coloca no comentário =="
echo "resultado: sucesso" > "$SBP/arquivo.txt"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-f"
  export GH_CORPO_COM_CRITERIO=1
  cd "$SBP"  # Estar no repositório para que git rev-parse funcione
  node "$SRC/scripts/fechar-issue.cjs" 999905 --comando "bash teste.sh" --saida-arquivo "$SBP/arquivo.txt"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_F="$(cat "$SBP/log-f" 2>/dev/null || echo '')"
[ -n "$LOG_F" ] && {
  echo "$LOG_F" | grep -q "resultado: sucesso" && test_ok "arquivo lido" || test_fail "arquivo lido"
  echo "$LOG_F" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
  echo "$LOG_F" | grep -q "bash teste.sh" && test_ok "comando" || test_fail "comando"
} || {
  test_fail "log vazio"
  test_fail "arquivo lido"
  test_fail "marcador"
  test_fail "comando"
}

# Caso (g): --saida com caminho existente trata como texto
echo
echo "== (g) --saida '.env' trata como texto literal, NÃO lê arquivo =="
echo "SECRET_KEY=segredo" > "$SBP/.env"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-g"
  export GH_CORPO_COM_CRITERIO=1
  cd "$SBP"
  node "$SRC/scripts/fechar-issue.cjs" 999906 --comando "test" --saida ".env"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_G="$(cat "$SBP/log-g" 2>/dev/null || echo '')"
[ -n "$LOG_G" ] && {
  echo "$LOG_G" | grep -q "SECRET_KEY" && test_fail "arquivo FOI lido!" || test_ok "arquivo NÃO lido"
  echo "$LOG_G" | grep -q "\.env" && test_ok ".env literal" || test_fail ".env literal"
} || {
  test_fail "log vazio"
  test_ok "arquivo NÃO lido"
  test_fail ".env literal"
}

# Caso (h): --saida-arquivo FORA do repositório (criando subrepo) → exit 2, SEM chamar gh
echo
echo "== (h) --saida-arquivo fora do repositório → exit 2, sem chamar gh =="
mkdir -p "$SBP/subrepo"
(cd "$SBP/subrepo" && git init . >/dev/null 2>&1 && git config user.email "t@t" && git config user.name "Test")
FORA_DO_REPO="$SBP/fora-do-repo.txt"
echo "dados secretos" > "$FORA_DO_REPO"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-h"
  export GH_CORPO_COM_CRITERIO=1
  cd "$SBP/subrepo"  # subrepo é git init'ado, mas $FORA_DO_REPO está fora
  node "$SRC/scripts/fechar-issue.cjs" 999907 --comando "test" --saida-arquivo "$FORA_DO_REPO" 2>&1
) >/dev/null
[ $? -eq 2 ] && test_ok "exit 2" || test_fail "exit code"
LOG_H="$(cat "$SBP/log-h" 2>/dev/null || echo '')"
[ -n "$LOG_H" ] && {
  echo "$LOG_H" | grep -q "issue view\|issue comment\|issue close" && test_fail "gh foi chamado!" || test_ok "gh não foi chamado"
} || {
  test_ok "gh não foi chamado (log vazio)"
}

# Caso (i): --saida-arquivo DENTRO do repositório → segue como hoje (exit 0)
echo
echo "== (i) --saida-arquivo dentro do repositório → exit 0 como antes =="
DENTRO_DO_REPO="$SBP/resultado.txt"
echo "resultado esperado" > "$DENTRO_DO_REPO"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-i"
  export GH_CORPO_COM_CRITERIO=1
  cd "$SBP"  # Já está no git repo que criamos no início
  node "$SRC/scripts/fechar-issue.cjs" 999908 --comando "test" --saida-arquivo "$DENTRO_DO_REPO"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_I="$(cat "$SBP/log-i" 2>/dev/null || echo '')"
[ -n "$LOG_I" ] && {
  echo "$LOG_I" | grep -q "resultado esperado" && test_ok "arquivo lido" || test_fail "arquivo não lido"
  echo "$LOG_I" | grep -q "issue comment" && test_ok "issue comment chamado" || test_fail "issue comment não chamado"
} || {
  test_fail "log vazio"
}

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
