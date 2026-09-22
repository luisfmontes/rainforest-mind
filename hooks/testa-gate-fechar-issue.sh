#!/bin/bash
# Bateria para hooks/gate-fechar-issue.cjs com trava

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Forma Windows de $SRC, para `require()` do Node quando o cwd do processo
# node não é $SRC (rodada 19, lote 3: casos (bz5)/(bz6) rodam com `cd "$SBP"`).
SRC_WIN="$(cygpath -m "$SRC")"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
# Converter para forma Windows para payloads (cwd em Windows)
SBP_WIN="$(cygpath -m "$SBP")"
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar stub compatível com Windows
mkdir -p "$SBP/bin"

# Criar versão em Node.js como executável (sem extensão, para bash)
cat > "$SBP/bin/gh" <<'STUB'
#!/usr/bin/env node
if (process.argv[2] === 'issue' && process.argv[3] === 'view') {
  if (process.env.GH_COM_MARCADOR === '1') {
    console.log(JSON.stringify({comments:[{body:'<!-- rainforest-evidencia --> Marcador presente'}]}));
  } else {
    console.log(JSON.stringify({comments:[{body:'Sem marcador aqui'}]}));
  }
  process.exit(0);
}
process.exit(0);
STUB
chmod +x "$SBP/bin/gh"

# Criar versão .cmd para Windows (fallback) — é esta que o resolvedor
# (ordem de extensões .cmd/.bat/.exe/'') de fato escolhe nesta caixa.
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
if "%1"=="issue" if "%2"=="view" (
  if "%GH_COM_MARCADOR%"=="1" (
    echo {"comments":[{"body":"<!-- rainforest-evidencia --> Marcador presente"}]}
  ) else (
    echo {"comments":[{"body":"Sem marcador aqui"}]}
  )
  exit /b 0
)
if "%1"=="pr" if "%2"=="view" (
  if "%GH_PR_VIEW_FAIL%"=="1" (
    exit /b 1
  )
  node -e "console.log(JSON.stringify({body: process.env.GH_PR_VIEW_BODY || ''}))"
  exit /b 0
)
exit /b 0
STUB

# Também criar versão shell para bash, caso resolvedor procure sem extensão
cat > "$SBP/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  if [ "$GH_COM_MARCADOR" = "1" ]; then
    echo '{"comments":[{"body":"<!-- rainforest-evidencia --> Marcador presente"}]}'
  else
    echo '{"comments":[{"body":"Sem marcador aqui"}]}'
  fi
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  if [ "$GH_PR_VIEW_FAIL" = "1" ]; then
    exit 1
  fi
  node -e "console.log(JSON.stringify({body: process.env.GH_PR_VIEW_BODY || ''}))"
  exit 0
fi
exit 0
STUB
chmod +x "$SBP/bin/gh"

# TRAVA: verificar que gh é do sandbox usando resolverExecutavel
echo "== TRAVA: verificar que gh é do sandbox =="
if ! (
  export PATH="$SBP/bin:$PATH"
  # Converter SRC para caminho absoluto real (remove /c/ etc)
  SRC_ABS="$(cd "$SRC" && pwd)"
  RESOLVED="$(node -e "const { resolverExecutavel } = require('./hooks/lib/resolver-executavel.cjs'); const exe = resolverExecutavel('gh'); console.log(exe || 'NOT_FOUND');" 2>&1)"
  if [[ "$RESOLVED" == *"bin"*"gh"* ]]; then
    echo "  ok   gh resolvido para sandbox"
  else
    echo "  FALHA gh não resolvido para sandbox (veio: $RESOLVED)"
    exit 1
  fi
); then
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi

# Caso (a): `gh issue close 12` → exit 2, stderr aponta scripts/fechar-issue.cjs
echo
echo "== (a) gh issue close <n> direto → exit 2, stderr aponta script =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-a"
EXIT_A=$?
[ $EXIT_A -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_A)"
ERR_A="$(cat "$SBP/err-a")"
echo "$ERR_A" | grep -q "scripts/fechar-issue.cjs" && test_ok "stderr aponta script" || test_fail "stderr não aponta script"

# Caso (b): `gh pr create --body "closes #12"` sem marcador → exit 2
echo
echo "== (b) gh pr create com closes #12 SEM marcador → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-b"
EXIT_B=$?
[ $EXIT_B -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_B)"

# Caso (c): `gh pr create --body "closes #12"` COM marcador → exit 0
echo
echo "== (c) gh pr create com closes #12 COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-c"
EXIT_C=$?
[ $EXIT_C -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_C)"

# Caso (d): `gh pr create --body-file arquivo` lendo closes #12
echo
echo "== (d) gh pr create --body-file com closes #12 → mesma checagem =="
echo "closes #99" > "$SBP/corpo.txt"
SBP_WIN_CORPO="$(cygpath -m "$SBP/corpo.txt")"
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body-file '"$SBP_WIN_CORPO"'"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-d"
EXIT_D=$?
[ $EXIT_D -eq 2 ] && test_ok "exit 2 sem marcador" || test_fail "exit code sem marcador (foi $EXIT_D)"

# Caso (d2): Mesmo arquivo, COM marcador
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body-file '"$SBP_WIN_CORPO"'"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-d2"
EXIT_D2=$?
[ $EXIT_D2 -eq 0 ] && test_ok "exit 0 com marcador" || test_fail "exit code com marcador (foi $EXIT_D2)"

# Caso (e): RAINFOREST_GATE_OFF=1 → libera tudo
echo
echo "== (e) RAINFOREST_GATE_OFF=1 libera gh issue close =="
(
  export PATH="$SBP/bin:$PATH"
  export RAINFOREST_GATE_OFF=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh issue close 999"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-e"
EXIT_E=$?
[ $EXIT_E -eq 0 ] && test_ok "exit 0 (emergência ativa)" || test_fail "exit code (foi $EXIT_E)"

# Caso (f): .rainforest-gate-off na raiz → libera tudo
echo
echo "== (f) .rainforest-gate-off libera gh pr merge =="
mkdir -p "$SBP/repo"
cd "$SBP/repo"
git init . >/dev/null 2>&1
touch "$SBP/repo/.rainforest-gate-off"
SBP_WIN_REPO="$(cygpath -m "$SBP/repo")"
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN_REPO"'","tool_name":"Bash","tool_input":{"command":"gh pr merge --body \"closes #888\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-f"
EXIT_F=$?
[ $EXIT_F -eq 0 ] && test_ok "exit 0 (arquivo de emergência)" || test_fail "exit code (foi $EXIT_F)"

# Caso (g): `gh.exe issue close 999921` → exit 2 (exe com extensão)
echo
echo "== (g) gh.exe issue close 999921 → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh.exe issue close 999921"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-g"
EXIT_G=$?
[ $EXIT_G -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_G)"

# Caso (h): `"gh" issue close 999921` → exit 2 (com aspas)
echo
echo "== (h) \"gh\" issue close 999921 → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"\"gh\" issue close 999921"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-h"
EXIT_H=$?
[ $EXIT_H -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_H)"

# Caso (i): `gh pr create --body "$(printf 'closes #999922')"` → exit 2 (corpo com $())
echo
echo "== (i) gh pr create --body \"\\$(printf ...)\" → exit 2 (corpo ilegível) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"\\$(printf '\''closes #999922'\'')\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-i"
EXIT_I=$?
[ $EXIT_I -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_I)"
ERR_I="$(cat "$SBP/err-i")"
echo "$ERR_I" | grep -q "substituição de comando" && test_ok "mensagem de corpo ilegível" || test_fail "mensagem incorreta"

# Caso (j): `C:\qualquer\gh.exe pr merge --body "closes #999923"` SEM marcador → exit 2
# (D15, 15ª revisão: o `--body` do merge NÃO é mais a fonte — o gate lê a
# descrição real via `gh pr view --json body`, aqui simulada por GH_PR_VIEW_BODY;
# o `--body` deste comando vira só a mensagem do merge commit, e é ignorado.)
echo
echo "== (j) C:\\qualquer\\gh.exe pr merge com closes (sem marcador) → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="closes #999923"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"C:\\\\qualquer\\\\gh.exe pr merge --body \"closes #999923\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-j"
EXIT_J=$?
[ $EXIT_J -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_J)"

# Caso (k): `cd /tmp && gh issue close 12` → exit 2 (evasão por segmento cd)
echo
echo "== (k) cd /tmp && gh issue close 12 → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"cd /tmp && gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-k"
EXIT_K=$?
[ $EXIT_K -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_K)"

# Caso (l): `true && gh issue close 12` → exit 2
echo
echo "== (l) true && gh issue close 12 → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"true && gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-l"
EXIT_L=$?
[ $EXIT_L -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_L)"

# Caso (m): `echo oi; gh issue close 12` → exit 2
echo
echo "== (m) echo oi; gh issue close 12 → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"echo oi; gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-m"
EXIT_M=$?
[ $EXIT_M -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_M)"

# Caso (n): `bash -c "gh issue close 12"` → exit 2 (recursiona na string interna)
echo
echo "== (n) bash -c \"gh issue close 12\" → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-n"
EXIT_N=$?
[ $EXIT_N -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_N)"
ERR_N="$(cat "$SBP/err-n")"
echo "$ERR_N" | grep -q "scripts/fechar-issue.cjs" && test_ok "stderr aponta script" || test_fail "stderr não aponta script"

# Caso (o): `true && gh pr create --body "closes #999"` SEM marcador → exit 2
echo
echo "== (o) true && gh pr create --body \"closes #999\" sem marcador → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"true && gh pr create --body \"closes #999\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-o"
EXIT_O=$?
[ $EXIT_O -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_O)"

# Caso (p): `bash -c "$CMD"` → exit 2 (string interna ilegível: variável)
echo
echo "== (p) bash -c \"\$CMD\" → exit 2 (ilegível) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -c \"$CMD\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-p"
EXIT_P=$?
[ $EXIT_P -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_P)"
ERR_P="$(cat "$SBP/err-p")"
echo "$ERR_P" | grep -q "ilegível" && test_ok "mensagem de encapsulamento ilegível" || test_fail "mensagem incorreta"

# Caso (q): `echo "gh issue close 12"` → exit 0 (texto citado em posição de argumento)
echo
echo "== (q) echo \"gh issue close 12\" → exit 0 (não é comando) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"echo \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-q"
EXIT_Q=$?
[ $EXIT_Q -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_Q)"

# Caso (r): `echo x; gh issue view 12` → exit 0 (view é leitura, nunca barrada)
echo
echo "== (r) echo x; gh issue view 12 → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"echo x; gh issue view 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-r"
EXIT_R=$?
[ $EXIT_R -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_R)"

# Caso (s): `true && gh pr create --body "...MARCADOR... closes #7"` COM marcador → exit 0
echo
echo "== (s) true && gh pr create --body com closes #7 COM marcador → exit 0 (caminho feliz encadeado) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"true && gh pr create --body \"resumo da entrega, closes #7\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-s"
EXIT_S=$?
[ $EXIT_S -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_S)"

# Caso (t): `(gh issue close 12)` → exit 2 (grupo/subshell vira segmento)
echo
echo "== (t) (gh issue close 12) → exit 2 (grupo) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"(gh issue close 12)"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-t"
EXIT_T=$?
[ $EXIT_T -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_T)"

# Caso (u): `x=$(gh issue close 12)` → exit 2 (substituição de comando vira segmento)
echo
echo "== (u) x=\$(gh issue close 12) → exit 2 (substituição) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"x=$(gh issue close 12)"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-u"
EXIT_U=$?
[ $EXIT_U -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_U)"

# Caso (v): `{ gh issue close 12; }` → exit 2 (grupo com chaves vira segmento)
echo
echo "== (v) { gh issue close 12; } → exit 2 (grupo com chaves) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"{ gh issue close 12; }"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-v"
EXIT_V=$?
[ $EXIT_V -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_V)"

# Caso (w): `env gh issue close 12` → exit 2 (prefixo que repassa o comando)
echo
echo "== (w) env gh issue close 12 → exit 2 (prefixo env) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"env gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-w"
EXIT_W=$?
[ $EXIT_W -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_W)"

# Caso (x): `command gh issue close 12` → exit 2 (prefixo command)
echo
echo "== (x) command gh issue close 12 → exit 2 (prefixo command) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"command gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-x"
EXIT_X=$?
[ $EXIT_X -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_X)"

# Caso (y): `eval "gh issue close 12"` → exit 2 (recursiona no conteúdo do eval)
echo
echo "== (y) eval \"gh issue close 12\" → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"eval \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-y"
EXIT_Y=$?
[ $EXIT_Y -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_Y)"
ERR_Y="$(cat "$SBP/err-y")"
echo "$ERR_Y" | grep -q "scripts/fechar-issue.cjs" && test_ok "stderr aponta script" || test_fail "stderr não aponta script"

# Caso (z): `nohup gh issue close 12` → exit 2 (prefixo nohup)
echo
echo "== (z) nohup gh issue close 12 → exit 2 (prefixo nohup) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"nohup gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-z"
EXIT_Z=$?
[ $EXIT_Z -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_Z)"

# Caso (aa): `timeout 5 gh issue close 12` → exit 2 (prefixo timeout + duração)
echo
echo "== (aa) timeout 5 gh issue close 12 → exit 2 (prefixo timeout) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout 5 gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-aa"
EXIT_AA=$?
[ $EXIT_AA -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AA)"

# Caso (ab): `xargs gh issue close 12` → exit 2 (prefixo xargs)
echo
echo "== (ab) xargs gh issue close 12 → exit 2 (prefixo xargs) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"xargs gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ab"
EXIT_AB=$?
[ $EXIT_AB -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AB)"

# Caso (ac): `pwsh -c "gh issue close 12"` → exit 2 (flag -Command abreviada)
echo
echo "== (ac) pwsh -c \"gh issue close 12\" → exit 2 (flag abreviada) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"pwsh -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ac"
EXIT_AC=$?
[ $EXIT_AC -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AC)"
ERR_AC="$(cat "$SBP/err-ac")"
echo "$ERR_AC" | grep -q "scripts/fechar-issue.cjs" && test_ok "stderr aponta script" || test_fail "stderr não aponta script"

# Caso (ad): `powershell -EncodedCommand <base64>` → exit 2 (ilegível, base64)
echo
echo "== (ad) powershell -EncodedCommand <base64> → exit 2 (ilegível) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"powershell -EncodedCommand Z2ggaXNzdWUgY2xvc2UgMTI="}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ad"
EXIT_AD=$?
[ $EXIT_AD -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AD)"
ERR_AD="$(cat "$SBP/err-ad")"
echo "$ERR_AD" | grep -q "ilegível" && test_ok "mensagem de -EncodedCommand ilegível" || test_fail "mensagem incorreta"

# Caso (ae): `X=1 gh pr create --body "... closes #7"` COM marcador → exit 0
# (prefixo de atribuição não muda o caminho feliz)
echo
echo "== (ae) X=1 gh pr create --body com closes #7 COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"X=1 gh pr create --body \"resumo da entrega, closes #7\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ae"
EXIT_AE=$?
[ $EXIT_AE -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AE)"

# Caso (af): `git commit -m "(gh issue close 12)"` → exit 0 (citado, é texto)
echo
echo "== (af) git commit -m \"(gh issue close 12)\" → exit 0 (citado) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"git commit -m \"(gh issue close 12)\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-af"
EXIT_AF=$?
[ $EXIT_AF -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AF)"

# K1 do auditor (rodada 6, lote 3, 2026-09-03): '&' simples nao separava
# segmento em `segmentosParaGate`. `pularPrefixos` parava no `&` (nao e
# atribuicao, nem exe conhecido), e como `tokens[0]` (`sudo`/`true`) ERA um
# prefixo conhecido, a rede de seguranca de "wrapper desconhecido"
# (`ehPrefixoOuWrapperConhecido`) tambem pulava o segmento inteiro — o
# `gh issue close`/`gh pr merge` direto escapava sem checagem nenhuma.
# Caso (ag): `sudo & gh issue close 42` → exit 2
echo
echo "== (ag) sudo & gh issue close 42 → exit 2 (K1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"sudo & gh issue close 42"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ag"
EXIT_AG=$?
[ $EXIT_AG -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AG)"

# Caso (ah): `true & gh pr merge 7 --body "closes #7"` SEM marcador → exit 2
# (D15, 15ª revisão: descrição real via GH_PR_VIEW_BODY, não o --body do merge.)
echo
echo "== (ah) true & gh pr merge 7 com closes #7 sem marcador → exit 2 (K1) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="closes #7"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"true & gh pr merge 7 --body \"closes #7\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ah"
EXIT_AH=$?
[ $EXIT_AH -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AH)"

# Caso (ai): `gh issue view 12 2>&1` → exit 0 (leitura; 2>&1 nao e separador)
echo
echo "== (ai) gh issue view 12 2>&1 → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh issue view 12 2>&1"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ai"
EXIT_AI=$?
[ $EXIT_AI -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AI)"

# Caso (aj): `gh pr create --body "...closes #7" 2>&1` COM marcador → exit 0
echo
echo "== (aj) gh pr create com closes #7 COM marcador 2>&1 → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"resumo da entrega, closes #7\" 2>&1"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-aj"
EXIT_AJ=$?
[ $EXIT_AJ -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AJ)"

# M2 (auditor, 5a revisao, 2026-09-03): o GitHub tambem fecha Issue quando o
# corpo cita a URL COMPLETA, nao so `#N` — `extrairIssuesCitadas` so casava
# `#N` ate aqui.
# Caso (ak): `gh pr create --body "Closes https://github.com/org/repo/issues/42"`
# sem marcador → exit 2 citando #42
echo
echo "== (ak) gh pr create com Closes <URL completa da Issue 42> SEM marcador → exit 2 citando #42 (M2) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Closes https://github.com/org/repo/issues/42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ak"
EXIT_AK=$?
[ $EXIT_AK -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AK)"
ERR_AK="$(cat "$SBP/err-ak")"
echo "$ERR_AK" | grep -q "#42" && test_ok "stderr cita #42" || test_fail "stderr não cita #42"

# Caso (al): `gh pr create --body "Fixed <URL completa da Issue 42>"` COM marcador → exit 0
echo
echo "== (al) gh pr create com Fixed <URL completa da Issue 42> COM marcador → exit 0 (M2) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Fixed https://github.com/org/repo/issues/42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-al"
EXIT_AL=$?
[ $EXIT_AL -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AL)"

# Caso (am): `gh pr create --body "veja <URL da Issue 42>"` (sem palavra-chave) → exit 0
echo
echo "== (am) gh pr create com URL da Issue 42 SEM palavra-chave de fechamento → exit 0 (M2) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"veja https://github.com/org/repo/issues/42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-am"
EXIT_AM=$?
[ $EXIT_AM -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AM)"

# P1 (rodada 8, lote 3, 2026-09-04): `env -u` parava a busca na PROPRIA
# flag (so `-C`/`--chdir` eram conhecidas) — `gh issue close` direto atras
# dela escapava. P2: este gate agora usa a MESMA tabela de tokens-comando.cjs
# dos outros dois gates, entao o conserto vale aqui tambem.
# Caso (an): `env -u FOO gh issue close 12` → exit 2
echo
echo "== (an) env -u FOO gh issue close 12 → exit 2 (P1/P2) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"env -u FOO gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-an"
EXIT_AN=$?
[ $EXIT_AN -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AN)"

# P3 (rodada 8, lote 3, 2026-09-04): o regex antigo, `/--body\s+["']([^"']+)["']/i`,
# parava no PRIMEIRO apostrofo — `--body "don't forget: closes #42"` capturava
# so `don`, o `closes #42` sumia, e o gate liberava. Apostrofo em prosa e
# rotina, nao ataque — o caso mais grave dos cinco achados.
# Caso (ao): `gh pr create --body "don't forget: closes #42"` SEM marcador → exit 2 citando #42
echo
echo "== (ao) gh pr create --body com apostrofo (don't) e closes #42 SEM marcador → exit 2 citando #42 (P3) =="
COMANDO_AO=$'gh pr create --body "don\'t forget: closes #42"'
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$COMANDO_AO")
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ao"
EXIT_AO=$?
[ $EXIT_AO -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AO)"
ERR_AO="$(cat "$SBP/err-ao")"
echo "$ERR_AO" | grep -q "#42" && test_ok "stderr cita #42" || test_fail "stderr não cita #42"

# Caso (ap): `gh pr create --body "it's done, closes #7"` COM marcador (stub
# devolvendo comentário marcado) → exit 0 — o mesmo apostrofo, caminho feliz.
echo
echo "== (ap) gh pr create --body com apostrofo (it's) e closes #7 COM marcador → exit 0 (P3) =="
COMANDO_AP=$'gh pr create --body "it\'s done, closes #7"'
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$COMANDO_AP")
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ap"
EXIT_AP=$?
[ $EXIT_AP -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AP)"

# Caso (aq): `gh pr create --body='closes #42'` (forma com `=`) SEM marcador → exit 2
echo
echo "== (aq) gh pr create --body='closes #42' SEM marcador → exit 2 (P3) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body='"'"'closes #42'"'"'"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-aq"
EXIT_AQ=$?
[ $EXIT_AQ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AQ)"

# P4 (rodada 8, lote 3, 2026-09-04): `$(...)` DENTRO de aspas DUPLAS e
# executado pelo bash mesmo citado — `segmentosParaGate` nao descia nele, e
# `echo "$(gh issue close 42)"` escapava por inteiro. Aspas SIMPLES nao
# expandem `$(...)`, entao o mesmo texto ali tem que PASSAR.
# Caso (ar): `echo "$(gh issue close 42)"` → exit 2
echo
echo "== (ar) echo \"\$(gh issue close 42)\" → exit 2 (P4, aspas duplas executam) =="
COMANDO_AR='echo "$(gh issue close 42)"'
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$COMANDO_AR")
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ar"
EXIT_AR=$?
[ $EXIT_AR -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AR)"

# Caso (as): `echo '$(gh issue close 42)'` (aspas simples) → exit 0
echo
echo "== (as) echo '\$(gh issue close 42)' → exit 0 (P4, aspas simples NAO executam) =="
COMANDO_AS=$'echo \'$(gh issue close 42)\''
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$COMANDO_AS")
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-as"
EXIT_AS=$?
[ $EXIT_AS -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AS)"

# R2 (rodada 9, lote 3, 2026-09-04): `Invoke-Expression`/`iex` (PowerShell)
# nao eram reconhecidos como wrapper de string sem flag (igual `eval`) — o
# conteudo era um token citado so, a busca por sequencia nao casava dentro
# dele, e `Invoke-Expression "gh issue close 42"` passava com exit 0.
# Caso (at): via PowerShell, `Invoke-Expression "gh issue close 42"` → exit 2
echo
echo "== (at) via PowerShell, Invoke-Expression \"gh issue close 42\" → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"PowerShell","tool_input":{"command":"Invoke-Expression \"gh issue close 42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-at"
EXIT_AT=$?
[ $EXIT_AT -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AT)"

# Caso (au): via PowerShell, `iex "gh issue close 42"` → exit 2 (alias curto)
echo
echo "== (au) via PowerShell, iex \"gh issue close 42\" → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"PowerShell","tool_input":{"command":"iex \"gh issue close 42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-au"
EXIT_AU=$?
[ $EXIT_AU -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AU)"

# Caso (av): via PowerShell, `iex "$cmd"` → exit 2 (conteudo ilegivel, variavel)
echo
echo "== (av) via PowerShell, iex \"\$cmd\" → exit 2 (ilegivel) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"PowerShell","tool_input":{"command":"iex \"$cmd\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-av"
EXIT_AV=$?
[ $EXIT_AV -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AV)"

# Caso (aw): via PowerShell, `Invoke-Expression "gh issue view 42"` → exit 0 (nao e close/create/merge)
echo
echo "== (aw) via PowerShell, Invoke-Expression \"gh issue view 42\" → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"PowerShell","tool_input":{"command":"Invoke-Expression \"gh issue view 42\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-aw"
EXIT_AW=$?
[ $EXIT_AW -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AW)"

# T1 (rodada 11, lote 3, 2026-09-04): `timeout -s`/`-k` (forma com espaco) na
# tabela de flags com valor — antes, `-s TERM`/`-k 5` faziam a posicao de
# comando cair na DURACAO (`30`), nao no comando de verdade.

# Caso (ax): `timeout -s TERM 30 gh issue close 12` → exit 2
echo
echo "== (ax) timeout -s TERM 30 gh issue close 12 → exit 2 (T1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout -s TERM 30 gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ax"
EXIT_AX=$?
[ $EXIT_AX -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AX)"

# Caso (ay): `timeout -k 5 30 gh issue close 12` → exit 2
echo
echo "== (ay) timeout -k 5 30 gh issue close 12 → exit 2 (T1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout -k 5 30 gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ay"
EXIT_AY=$?
[ $EXIT_AY -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_AY)"

# Caso (az): `timeout 30 gh issue view 12` → exit 0 (sem -s/-k, regressao)
echo
echo "== (az) timeout 30 gh issue view 12 → exit 0 (T1, regressao) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout 30 gh issue view 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-az"
EXIT_AZ=$?
[ $EXIT_AZ -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_AZ)"

# U1 (rodada 12, lote 3, 2026-09-04): flags curtas coladas a -c (bash -xc, sh -ec)
# Casos (ba, bb): bash -xc e sh -ec com gh issue close → exit 2

# Caso (ba): `bash -xc "gh issue close 12"` → exit 2
echo
echo "== (ba) bash -xc \"gh issue close 12\" → exit 2 (U1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -xc \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ba"
EXIT_BA=$?
[ $EXIT_BA -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BA)"

# Caso (bb): `sh -ec "gh issue close 12"` → exit 2
echo
echo "== (bb) sh -ec \"gh issue close 12\" → exit 2 (U1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"sh -ec \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bb"
EXIT_BB=$?
[ $EXIT_BB -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BB)"

# Caso (bc): `timeout 5 bash -c "gh issue close 12"` → exit 2 (P3, prefixo + wrapper de string compostos)
echo
echo "== (bc) timeout 5 bash -c \"gh issue close 12\" → exit 2 (P3) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout 5 bash -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bc"
EXIT_BC=$?
[ $EXIT_BC -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BC)"

# Caso (bd): `env FOO=1 eval "gh issue close 12"` → exit 2 (P3, prefixo env + wrapper eval)
echo
echo "== (bd) env FOO=1 eval \"gh issue close 12\" → exit 2 (P3) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"env FOO=1 eval \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bd"
EXIT_BD=$?
[ $EXIT_BD -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BD)"

# Caso (be): `nohup bash -c "gh issue view 12"` → exit 0 (P3, view nao e comando barrado)
echo
echo "== (be) nohup bash -c \"gh issue view 12\" → exit 0 (P3) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"nohup bash -c \"gh issue view 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-be"
EXIT_BE=$?
[ $EXIT_BE -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BE)"

# W1/W2 (auditor, 12a revisao, rodada 14, lote 3, 2026-09-04): flags COM VALOR
# antes do -c (bash -o pipefail), e comentario shell fora da rede de seguranca.
# Caso (bf): `bash -o pipefail -c "gh issue close 12"` → exit 2 (W1)
echo
echo "== (bf) bash -o pipefail -c \"gh issue close 12\" → exit 2 (W1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -o pipefail -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bf"
EXIT_BF=$?
[ $EXIT_BF -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BF)"

# Caso (bg): `timeout 5 bash -o pipefail -c "gh issue close 12"` → exit 2 (W1, prefixo composto)
echo
echo "== (bg) timeout 5 bash -o pipefail -c \"gh issue close 12\" → exit 2 (W1) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"timeout 5 bash -o pipefail -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bg"
EXIT_BG=$?
[ $EXIT_BG -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BG)"

# Caso (bh): comentario shell com `gh issue close` seguido de `ls` em outra linha → exit 0 (W2)
echo
echo "== (bh) comentario shell com gh issue close + ls PASSA (W2) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"# gh issue close 12 e tratado pelo fechar-issue\nls"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bh"
EXIT_BH=$?
[ $EXIT_BH -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BH)"

# Caso (bi): `ls # gh pr merge 7 --body "closes #7"` → exit 0 (W2, comentario na mesma linha)
echo
echo "== (bi) ls # gh pr merge 7 --body \"closes #7\" PASSA (W2) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"ls # gh pr merge 7 --body \"closes #7\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bi"
EXIT_BI=$?
[ $EXIT_BI -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BI)"

# Caso (bj): `gh issue close 12 # comentario` → exit 2 (W2, comando antes do # continua valendo)
echo
echo "== (bj) gh issue close 12 # comentario → exit 2 (W2) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh issue close 12 # comentario"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bj"
EXIT_BJ=$?
[ $EXIT_BJ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BJ)"

# Rodada 15, lote 3, 2026-09-04: `--body-file` resolvido contra o cwd
# EFETIVO do segmento (cwdPorSegmento), não contra o cwd do processo do hook.
mkdir -p "$SBP/principal" "$SBP/wt"
echo "sem closes aqui" > "$SBP/principal/corpo.txt"
echo "closes #12" > "$SBP/wt/corpo.txt"
SBP_WIN_PRINCIPAL="$(cygpath -m "$SBP/principal")"
SBP_WIN_WT="$(cygpath -m "$SBP/wt")"
SBP_WIN_WT_CORPO="$(cygpath -m "$SBP/wt/corpo.txt")"

# Caso (bk): cwd=principal, `cd <wt> && gh pr create --body-file corpo.txt`
# (relativo) — tem que ler wt/corpo.txt (closes #12), não principal/corpo.txt.
echo
echo "== (bk) cd <wt> && gh pr create --body-file corpo.txt (relativo) → lê o do wt, exit 2 citando #12 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_PRINCIPAL"'","tool_name":"Bash","tool_input":{"command":"cd '"$SBP_WIN_WT"' && gh pr create --body-file corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bk"
EXIT_BK=$?
[ $EXIT_BK -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BK)"
ERR_BK="$(cat "$SBP/err-bk")"
echo "$ERR_BK" | grep -q "#12" && test_ok "stderr cita #12 (leu o corpo do wt)" || test_fail "stderr não cita #12 ($ERR_BK)"

# Caso (bk2): mesmo cenário, `--body-file` com caminho ABSOLUTO do wt/corpo.txt
echo
echo "== (bk2) cd <wt> && gh pr create --body-file <absoluto do wt/corpo.txt> → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_PRINCIPAL"'","tool_name":"Bash","tool_input":{"command":"cd '"$SBP_WIN_WT"' && gh pr create --body-file '"$SBP_WIN_WT_CORPO"'"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bk2"
EXIT_BK2=$?
[ $EXIT_BK2 -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BK2)"

# Caso (bl): `cd $(pwd)/x && gh pr create --body-file corpo.txt` — cd incerto
# ($(...) no destino), --body-file relativo não pode ser lido com segurança.
echo
echo "== (bl) cd \$(pwd)/x && gh pr create --body-file corpo.txt (cd incerto) → exit 2 (ilegível) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_PRINCIPAL"'","tool_name":"Bash","tool_input":{"command":"cd $(pwd)/x && gh pr create --body-file corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bl"
EXIT_BL=$?
[ $EXIT_BL -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BL)"

# Caso (bm): regressão — sem `cd`, `gh pr create --body-file corpo.txt` no
# próprio cwd do evento continua lendo normalmente (exit 0 com marcador).
echo "closes #7" > "$SBP/corpo-regressao.txt"
echo
echo "== (bm) gh pr create --body-file corpo.txt (sem cd, cwd do evento) COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body-file corpo-regressao.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bm"
EXIT_BM=$?
[ $EXIT_BM -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BM)"

# Rodada 16, lote 3, 2026-09-04: `cwdDoSegmento` casa a K-ÉSIMA ocorrência
# de um texto de segmento repetido, não sempre a primeira (`.find`).
mkdir -p "$SBP/dirA" "$SBP/dirB"
echo "sem closes aqui tambem" > "$SBP/dirA/corpo.txt"
echo "Closes #999" > "$SBP/dirB/corpo.txt"
SBP_WIN_DIRA="$(cygpath -m "$SBP/dirA")"
SBP_WIN_DIRB="$(cygpath -m "$SBP/dirB")"

# Caso (bn): mesmo texto de segmento duas vezes, cwds diferentes (A sem
# closes, B com "Closes #999") — a SEGUNDA ocorrência tem que ler B/corpo.txt,
# não A/corpo.txt de novo.
echo
echo "== (bn) cd <A> && gh pr create --body-file corpo.txt ; cd <B> && gh pr create --body-file corpo.txt → exit 2 citando #999 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_DIRA"'","tool_name":"Bash","tool_input":{"command":"cd '"$SBP_WIN_DIRA"' && gh pr create --body-file corpo.txt ; cd '"$SBP_WIN_DIRB"' && gh pr create --body-file corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bn"
EXIT_BN=$?
[ $EXIT_BN -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BN)"
ERR_BN="$(cat "$SBP/err-bn")"
echo "$ERR_BN" | grep -q "#999" && test_ok "stderr cita #999 (leu a 2ª ocorrência, cwd B)" || test_fail "stderr não cita #999 ($ERR_BN)"

# Caso (bo): ordem invertida — o primeiro segmento já é o de B (closes
# #999), então já bloqueia ali (nem chega a processar o segundo).
echo
echo "== (bo) cd <B> && gh pr create --body-file corpo.txt ; cd <A> && gh pr create --body-file corpo.txt → exit 2 citando #999 (o primeiro já barra) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_DIRA"'","tool_name":"Bash","tool_input":{"command":"cd '"$SBP_WIN_DIRB"' && gh pr create --body-file corpo.txt ; cd '"$SBP_WIN_DIRA"' && gh pr create --body-file corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bo"
EXIT_BO=$?
[ $EXIT_BO -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BO)"
ERR_BO="$(cat "$SBP/err-bo")"
echo "$ERR_BO" | grep -q "#999" && test_ok "stderr cita #999 (bloqueou no primeiro)" || test_fail "stderr não cita #999 ($ERR_BO)"

# Caso (bp): regressão — três ocorrências IDÊNTICAS do mesmo texto de
# segmento, todas cwd=A, corpo sem closes: a K-ésima ocorrência tem que
# resolver certo (cwd de A) e não virar `null` por engano.
echo
echo "== (bp) cd <A> && gh pr create --body-file corpo.txt (repetido 3x) → exit 0 (regressão k-ésima) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  CMD="cd $SBP_WIN_DIRA && gh pr create --body-file corpo.txt ; cd $SBP_WIN_DIRA && gh pr create --body-file corpo.txt ; cd $SBP_WIN_DIRA && gh pr create --body-file corpo.txt"
  PAYLOAD='{"cwd":"'"$SBP_WIN_DIRA"'","tool_name":"Bash","tool_input":{"command":"'"$CMD"'"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bp"
EXIT_BP=$?
[ $EXIT_BP -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BP)"

# Caso (bq): subshell no meio — `cwdDoSegmento` continua devolvendo `null`
# (texto do sub-segmento não bate 1:1 com `mapaCwd`, que não desce em `(`/`)`)
# → `--body-file` relativo vira ilegível/bloqueia (comportamento atual, mantido).
echo
echo "== (bq) (cd <A> && gh pr create --body-file corpo.txt) → exit 2 (cwd incerto, subshell) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN_DIRA"'","tool_name":"Bash","tool_input":{"command":"(cd '"$SBP_WIN_DIRA"' && gh pr create --body-file corpo.txt)"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bq"
EXIT_BQ=$?
[ $EXIT_BQ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BQ)"

# Caso (br): `gh pr edit 5 --body "Closes #12"` SEM marcador → exit 2 citando #12
# (D15, 15ª revisão: `pr edit` vira gatilho igual `pr create` — é o segundo
# passo do furo: `pr create --body "wip"` (0) → `pr edit --body "Closes #12"`
# escapava sem checagem alguma antes deste conserto.)
echo
echo "== (br) gh pr edit 5 --body \"Closes #12\" SEM marcador → exit 2 citando #12 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr edit 5 --body \"Closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-br"
EXIT_BR=$?
[ $EXIT_BR -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BR)"
ERR_BR="$(cat "$SBP/err-br")"
echo "$ERR_BR" | grep -q "#12" && test_ok "stderr cita #12" || test_fail "stderr não cita #12 ($ERR_BR)"

# Caso (bs): `gh pr edit 5 --body "Closes #12"` COM marcador → exit 0
echo
echo "== (bs) gh pr edit 5 --body \"Closes #12\" COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr edit 5 --body \"Closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bs"
EXIT_BS=$?
[ $EXIT_BS -eq 0 ] && test_ok "exit 0 com marcador" || test_fail "exit code com marcador (foi $EXIT_BS)"

# Caso (bt): `gh pr edit 5 --title "x"` (sem corpo) → exit 0
echo
echo "== (bt) gh pr edit 5 --title \"x\" (sem corpo) → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr edit 5 --title \"x\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bt"
EXIT_BT=$?
[ $EXIT_BT -eq 0 ] && test_ok "exit 0 (sem --body/--body-file)" || test_fail "exit code (foi $EXIT_BT)"

# Caso (bu): `gh pr merge 5 --squash --body "msg"` — o stub de `pr view`
# devolve body `Closes #12` (a descrição REAL do PR, não o --body do merge
# commit) e SEM marcador → exit 2 citando #12
echo
echo "== (bu) gh pr merge 5 --squash --body \"msg\" com pr view devolvendo Closes #12 SEM marcador → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="Closes #12"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --squash --body \"msg\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bu"
EXIT_BU=$?
[ $EXIT_BU -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BU)"
ERR_BU="$(cat "$SBP/err-bu")"
echo "$ERR_BU" | grep -q "#12" && test_ok "stderr cita #12" || test_fail "stderr não cita #12 ($ERR_BU)"

# Caso (bv): mesmo caso, mas COM marcador → exit 0
echo
echo "== (bv) gh pr merge 5 --squash --body \"msg\" com pr view devolvendo Closes #12 COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  export GH_PR_VIEW_BODY="Closes #12"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --squash --body \"msg\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bv"
EXIT_BV=$?
[ $EXIT_BV -eq 0 ] && test_ok "exit 0 com marcador" || test_fail "exit code com marcador (foi $EXIT_BV)"

# Caso (bw): stub de `pr view` falhando (exit 1) → exit 2 (não conseguiu ler
# a descrição do PR — mesma postura de bloqueio conservador do --body-file
# ilegível)
echo
echo "== (bw) gh pr merge 5 com pr view falhando (exit 1) → exit 2 (não conseguiu ler) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_FAIL=1
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge 5"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bw"
EXIT_BW=$?
[ $EXIT_BW -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BW)"
ERR_BW="$(cat "$SBP/err-bw")"
echo "$ERR_BW" | grep -q "não consegui ler" && test_ok "stderr diz que não conseguiu ler" || test_fail "stderr sem a mensagem esperada ($ERR_BW)"

# Caso (bx): `gh pr merge 5` com body (via pr view) sem Issue citada → exit 0
echo
echo "== (bx) gh pr merge 5 com pr view devolvendo body sem Issue citada → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="descrição qualquer, sem palavra-chave de fechamento"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge 5"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bx"
EXIT_BX=$?
[ $EXIT_BX -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_BX)"

# Caso (by): R18 (auditor, 16a revisao, lote 3, 2026-09-04) — `source fechar.sh`
# executa um ARQUIVO opaco ao parser; mesma postura conservadora que
# `bash x.sh` (sem `-c`) ja recebe do laco W1 — exit 2.
echo
echo "== (by) source fechar.sh → exit 2 (R18, arquivo opaco) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"source fechar.sh"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-by"
EXIT_BY=$?
[ $EXIT_BY -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BY)"

# Rodada 19 (lote 3): injeção de comando via `ref` cru de `gh pr merge` —
# reproduzido pela janela principal em caixa de areia com `gh.cmd` de
# mentira: `executar("gh", ["pr","view", ref, ...])` liga `shell:true`
# porque o `gh` resolvido termina em `.cmd`, e `spawnSync(arquivo.cmd, args,
# {shell:true})` NÃO escapa os elementos do array contra os metacaracteres
# do `cmd.exe` no Windows — o hook que existe para só LER executava texto
# arbitrário.

# Caso (bz1): `gh pr merge "5 & echo INJETADO > pwned.txt" --squash` → exit 2
# (D16 valida o `ref` antes de chamar `gh pr view`) E nenhum arquivo novo
# aparece na caixa de areia — o caso só vale provando isso, não só o exit
# code (uma trava que bloqueia por acidente, mas ainda deixa o `executar`
# rodar o texto injetado depois, não provaria nada).
echo
echo "== (bz1) gh pr merge com ref carregando injeção de comando → exit 2, NADA criado no disco =="
# Snapshot ANTES/DEPOIS do diretório da caixa de areia — a saída de erro
# do próprio teste vai para uma variável (não para um arquivo DENTRO de
# $SBP), para o snapshot não confundir artefato do teste com prova real.
LISTA_ANTES_BZ1="$(ls -1 "$SBP" | sort)"
ERR_BZ1="$(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge \"5 & echo INJETADO > pwned.txt\" --squash"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs" 2>&1 1>/dev/null
)"
EXIT_BZ1=$?
[ $EXIT_BZ1 -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BZ1)"
LISTA_DEPOIS_BZ1="$(ls -1 "$SBP" | sort)"
if [ "$LISTA_ANTES_BZ1" = "$LISTA_DEPOIS_BZ1" ]; then
  test_ok "nenhum arquivo novo na caixa de areia (diretório idêntico antes/depois)"
else
  test_fail "a caixa de areia mudou — diff:
$(diff <(echo "$LISTA_ANTES_BZ1") <(echo "$LISTA_DEPOIS_BZ1"))"
fi
[ -f "$SBP/pwned.txt" ] && test_fail "pwned.txt foi criado (injeção funcionou!)" || test_ok "pwned.txt não existe"

# Caso (bz2): mesmo ataque, mas colado ao ref numérico (sem espaço, sem
# aspas na CLI de verdade — `gh pr merge 5&echo...`); confere que a defesa
# não depende do atacante ter usado espaço/aspas de um jeito específico.
echo
echo "== (bz2) gh pr merge com ref '5' + metacaractere colado → exit 2, NADA criado no disco =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge \"5&echo INJETADO2>pwned2.txt\" --squash"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bz2"
EXIT_BZ2=$?
[ $EXIT_BZ2 -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_BZ2)"
[ -f "$SBP/pwned2.txt" ] && test_fail "pwned2.txt foi criado (injeção funcionou!)" || test_ok "pwned2.txt não existe"

# Caso (bz3, regressão): `gh pr merge 5 --squash` (ref numérico limpo, sem
# marcador na descrição real do PR) continua funcionando como antes do
# conserto — exit 0, ninguém fica bloqueado por engano.
echo
echo "== (bz3) gh pr merge 5 --squash com ref limpo → continua passando (regressão) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="sem palavra-chave de fechamento"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --squash"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bz3"
EXIT_BZ3=$?
[ $EXIT_BZ3 -eq 0 ] && test_ok "exit 0 (não regrediu)" || test_fail "exit code (foi $EXIT_BZ3)"

# Caso (bz4, regressão): branch conservador (letras/números/./-/_//) como ref
# continua sendo aceito e verificado normalmente — a validação de D16 não
# pode recusar um nome de branch legítimo.
echo
echo "== (bz4) gh pr merge com ref de branch conservador (fluxo/guardas) → segue verificando (regressão) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  export GH_PR_VIEW_BODY="Closes #321"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr merge fluxo/guardas --squash"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-bz4"
EXIT_BZ4=$?
[ $EXIT_BZ4 -eq 2 ] && test_ok "exit 2 (Issue #321 sem marcador — a checagem de verdade rodou)" || test_fail "exit code (foi $EXIT_BZ4)"

# Caso (bz5): causa raiz — `executar()` de resolver-executavel.cjs recusa
# QUALQUER argumento com metacaractere de cmd.exe quando o alvo é .cmd/.bat,
# mesmo chamado diretamente (sem passar pela validação de `ref` do gate) —
# é a defesa em profundidade que o briefing pede ("os dois lados, porque a
# causa raiz é o executar"). Chamador real: `verificarComandoGh` (caso c),
# `hooks/gate-fechar-issue.cjs:~488` —
# `executar("gh", ["pr","view", ref, "--json","body"], ...)`.
echo
echo "== (bz5) causa raiz: executar() recusa argumento com metacaractere de cmd.exe =="
(
  export PATH="$SBP/bin:$PATH"
  cd "$SBP"
  node -e "
    const { executar } = require('$SRC_WIN/hooks/lib/resolver-executavel.cjs');
    const fs = require('fs');
    const antes = fs.existsSync('pwned3.txt');
    const r = executar('gh', ['pr','view','5 & echo INJETADO3 > pwned3.txt','--json','body']);
    const depois = fs.existsSync('pwned3.txt');
    console.log(JSON.stringify({ status: r.status, antes, depois }));
  "
) > "$SBP/out-bz5" 2>"$SBP/err-bz5"
RESULT_BZ5="$(cat "$SBP/out-bz5")"
echo "$RESULT_BZ5" | grep -q '"depois":false' && test_ok "pwned3.txt não foi criado (executar recusou antes do spawnSync)" || test_fail "pwned3.txt foi criado ou saída inesperada ($RESULT_BZ5)"
echo "$RESULT_BZ5" | grep -q '"status":1' && test_ok "executar() devolveu status != 0 para o argumento malicioso" || test_fail "status inesperado ($RESULT_BZ5)"

# Caso (bz6, contraprova de super-bloqueio): mesmo `executar()`, ref limpo
# (sem metacaractere) continua indo até o `gh.cmd` de mentira e voltando
# status 0 — a recusa é ESPECÍFICA do metacaractere, não de qualquer ref.
echo
echo "== (bz6) contraprova: executar() com ref limpo ('5') continua chamando gh normalmente =="
(
  export PATH="$SBP/bin:$PATH"
  cd "$SBP"
  node -e "
    const { executar } = require('$SRC_WIN/hooks/lib/resolver-executavel.cjs');
    const r = executar('gh', ['pr','view','5','--json','body']);
    console.log(JSON.stringify({ status: r.status }));
  "
) > "$SBP/out-bz6" 2>"$SBP/err-bz6"
RESULT_BZ6="$(cat "$SBP/out-bz6")"
echo "$RESULT_BZ6" | grep -q '"status":0' && test_ok "ref limpo continua funcionando (status 0)" || test_fail "ref limpo quebrou ($RESULT_BZ6)"

# R21 (rodada 15, lote 4, 2026-09-04): `desempacotarWrapperDeString` tratava
# QUALQUER token que nao comeca com `-`/`+` como ilegivel (W1 conservador). Mas
# um arquivo de script (tipo `bash testa-config.sh`) NAO e ilegivel — e igual
# a `node x.cjs`, `./script.sh`, que ninguem bloqueia. O token ali e um CAMINHO
# de script, nao conteudo encapsulado, e deve sair como `{ interno: null, ilegivel: false }`.

# Caso (ca): `bash hooks/testa-config.sh` → exit 0 (script nao e ilegivel)
echo
echo "== (ca) bash hooks/testa-config.sh → exit 0 (R21, script arquivo, nao string) =="
mkdir -p "$SBP/hooks"
cat > "$SBP/hooks/testa-config.sh" <<'SCRIPT'
#!/bin/bash
echo "config test"
exit 0
SCRIPT
chmod +x "$SBP/hooks/testa-config.sh"
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash hooks/testa-config.sh"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ca"
EXIT_CA=$?
[ $EXIT_CA -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CA)"

# Caso (cb): `bash -c "gh issue close 12"` → exit 2 (string COM comando barrado continua ilegivel)
echo
echo "== (cb) bash -c \"gh issue close 12\" → exit 2 (R21, contraprova: -c com gh issue close) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-cb"
EXIT_CB=$?
[ $EXIT_CB -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CB)"

# Caso (cc): `sh scripts/x.sh` → exit 0 (script arquivo via sh)
echo
echo "== (cc) sh scripts/x.sh → exit 0 (R21, sh + script) =="
mkdir -p "$SBP/scripts"
cat > "$SBP/scripts/x.sh" <<'SCRIPT'
#!/bin/sh
echo "test"
exit 0
SCRIPT
chmod +x "$SBP/scripts/x.sh"
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"sh scripts/x.sh"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-cc"
EXIT_CC=$?
[ $EXIT_CC -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CC)"

	# D17 (2026-09-04): palavras-chave falsas em português
	# Casos de teste para detectar quando a constante FALSA_CHAVE é desativada

	# Caso (cd): `gh pr create --body "Fecha #73"` (falsa chave) → exit 2
	echo
	echo "== (cd) gh pr create --body \"Fecha #73\" → exit 2 (falsa chave português) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Fecha #73\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cd"
	EXIT_CD=$?
	[ $EXIT_CD -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CD)"
	ERR_CD="$(cat "$SBP/err-cd")"
	echo "$ERR_CD" | grep -q "não é palavra-chave do GitHub" && test_ok "mensagem menciona que não é reconhecida" || test_fail "mensagem incorreta"

	# Caso (ce): `gh issue create --body "Encerra #99"` (falsa chave) → exit 2
	echo
	echo "== (ce) gh issue create --body \"Encerra #99\" → exit 2 (falsa chave português) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh issue create --title test --body \"Encerra #99\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ce"
	EXIT_CE=$?
	[ $EXIT_CE -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CE)"

	# Caso (cf): `gh issue comment 73 --body "Conclui #73"` (falsa chave) → exit 2
	echo
	echo "== (cf) gh issue comment --body \"Conclui #73\" → exit 2 (falsa chave português) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh issue comment 73 --body \"Conclui #73\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cf"
	EXIT_CF=$?
	[ $EXIT_CF -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CF)"

	# Caso (cg): `gh pr create --body "Segue #73"` (palavra neutra, sem falsa chave) → exit 0
	echo
	echo "== (cg) gh pr create --body \"Segue #73\" → exit 0 (referência neutra, sem falsa chave) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Segue #73\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cg"
	EXIT_CG=$?
	[ $EXIT_CG -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CG)"

	# Caso (ch): `gh pr create --body "Resolvida #88"` (falsa chave) → exit 2
	echo
	echo "== (ch) gh pr create --body \"Resolvida #88\" → exit 2 (falsa chave português) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Resolvida #88\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ch"
	EXIT_CH=$?
	[ $EXIT_CH -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CH)"


	# Caso (ci): o artigo entre o verbo e o numero. "Fecha a #73" e portugues tao
	# comum quanto "Fecha #73", o GitHub nao reconhece nenhum dos dois, e ate a
	# revisao do lote 4 a regex exigia o `#` colado no verbo — a primeira forma
	# passava calada e a Issue ficava aberta em silencio.
	echo
	echo "== (ci) gh pr create --body \"Fecha a #73\" -> exit 2 (falsa chave com artigo) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"Fecha a #73\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ci"
	EXIT_CI=$?
	[ $EXIT_CI -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CI)"

	# Caso (cj): wrapper conhecido com o comando numa VARIAVEL. D17 autorizou
	# parar de chamar de ilegivel a execucao de um ARQUIVO (`bash roda.sh`), que e
	# um caminho literal e legivel. Variavel nao resolvida nao e caminho: e
	# justamente o que ninguem consegue ler, e para wrapper conhecido nao existe a
	# rede de seguranca textual atras. Achado na revisao do lote 4: `bash -c` com
	# aspas barrava e a mesma variavel sem `-c` passava.
	echo
	echo "== (cj) bash \$CMD -> exit 2 (variavel nao resolvida continua ilegivel) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash $CMD"}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cj"
	EXIT_CJ=$?
	[ $EXIT_CJ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CJ)"

	# Contraprova (ck): o caminho de arquivo literal, que e o que D17 liberou,
	# continua passando. Sem ela o conserto acima viraria a volta do bloqueio
	# inteiro, e o defeito que D17 fechou voltaria.
	echo
	echo "== (ck) bash roda.sh -> exit 0 (caminho de arquivo continua legivel) =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash roda.sh"}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ck"
	EXIT_CK=$?
	[ $EXIT_CK -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CK)"

	# Caso (cl): parametro posicional dentro do wrapper. `$1` e tao ilegivel
	# quanto `$VAR`, e a classe de caracteres da checagem nao tinha digito — a
	# forma escapava. Lacuna apontada na revisao de 2026-09-05, na mesma linha que
	# D22 tocou.
	#
	# O comando interno e inofensivo de proposito. Com `gh issue close $1` la
	# dentro o caso saia exit 2 nos dois sentidos — barrado por ser `gh issue
	# close` quando legivel, barrado por ser ilegivel quando nao. Verde sob
	# mutacao, medindo nada: a catraca pegou isso na primeira rodada.
	echo
	echo "== (cl) bash -c com parametro posicional -> exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -c \"echo $1\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cl"
	EXIT_CL=$?
	[ $EXIT_CL -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CL)"

	# D1 (zerar-issues-3): casos novos de heredoc
	echo
	echo "== NOVOS CASOS DE HEREDOC (D1) =="

	# Caso (cm): cat > d.md <<'EOF' com (x). → exit 0
	echo
	echo "== (cm) cat <<'EOF' com (x). → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<'EOF'\\n(x).\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cm"
	EXIT_CM=$?
	[ $EXIT_CM -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CM)"

	# Caso (cn): cat <<'EOF' com (x). O que → exit 0
	echo
	echo "== (cn) cat <<'EOF' com (x). O que → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<'EOF'\\n(x). O que\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cn"
	EXIT_CN=$?
	[ $EXIT_CN -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CN)"

	# Caso (co): cat <<'EOF' com (x). o que (minuscula) → exit 0
	echo
	echo "== (co) cat <<'EOF' com (x). o que → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<'EOF'\\n(x). o que\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-co"
	EXIT_CO=$?
	[ $EXIT_CO -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CO)"

	# Caso (cp): cat <<'EOF' com (x) ; . O que → exit 0
	echo
	echo "== (cp) cat <<'EOF' com (x) ; . O que → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<'EOF'\\n(x) ; . O que\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cp"
	EXIT_CP=$?
	[ $EXIT_CP -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CP)"

	# Caso (cq): Medido em 2026-09-12 (folga de 2 B). Ele sobe. → exit 0
	echo
	echo "== (cq) cat <<'EOF' com folga de 2 B → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<'EOF'\\nMedido em 2026-09-12 (folga de 2 B). Ele sobe.\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cq"
	EXIT_CQ=$?
	[ $EXIT_CQ -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CQ)"

	# Caso (cr): delimitador com aspas duplas → exit 0
	echo
	echo "== (cr) delimitador com aspas duplas → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:'cat > d.md <<\"EOF\"\\nMedido em 2026-09-12 (folga de 2 B). Ele sobe.\\nEOF'}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cr"
	EXIT_CR=$?
	[ $EXIT_CR -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CR)"

	# Caso (cs): heredoc nu (sem aspas) → exit 0
	echo
	echo "== (cs) heredoc nu (sem aspas) → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<EOF\\nMedido em 2026-09-12 (folga de 2 B). Ele sobe.\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cs"
	EXIT_CS=$?
	[ $EXIT_CS -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CS)"

	# Caso (ct): cat <<'EOF' com corpo contendo gh issue close 12 → exit 2.
	# Sétima revisão (2026-09-13): o corpo é dado para a ESTRUTURA (não vira
	# segmento, `).` não é subshell), mas o texto ainda é varrido pelos
	# padrões diretos do gate — o corpo pode ser executado por caminhos que
	# o gate não rastreia (arquivo rodado depois, while read, mapfile), e a
	# main barrava este caso. Antes desta revisão o caso esperava 0.
	echo
	echo "== (ct) cat <<'EOF' com gh issue close literal no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ct"
	EXIT_CT=$?
	[ $EXIT_CT -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CT)"

	# Caso (cu): bash <<'EOF' com corpo contendo gh issue close 12 → exit 2 (bash executa)
	echo
	echo "== (cu) bash <<'EOF' com gh inside → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"bash <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cu"
	EXIT_CU=$?
	[ $EXIT_CU -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CU)"

	# Caso (cv): bash -c com gh issue close continua bloqueado → exit 2
	echo
	echo "== (cv) bash -c com gh issue close → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash -c \"gh issue close 12\""}}'
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cv"
	EXIT_CV=$?
	[ $EXIT_CV -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CV)"

	# Caso (cw): heredoc sem linha de fechamento (EOF nunca aparece) → exit 0
	echo
	echo "== (cw) heredoc sem fechamento → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF'\\n(x). texto sem fechamento\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cw"
	EXIT_CW=$?
	[ $EXIT_CW -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_CW)"

	# Caso (cx): gh FORA do heredoc após o EOF deve bloquear → exit 2
	echo
	echo "== (cx) gh depois do heredoc → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF'\\n(x). texto\\nEOF\\ngh issue close 12\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cx"
	EXIT_CX=$?
	[ $EXIT_CX -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CX)"

	# Revisão do zerar-issues-3 (2026-09-13): o resto da LINHA do heredoc é
	# comando, roda antes do corpo, e a primeira versão da D1 o engolia.
	# Caso (cy): cat <<EOF; gh issue close 12 na mesma linha → exit 2
	echo
	echo "== (cy) gh na mesma linha do heredoc, apos ';' → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<EOF; gh issue close 12\\n(x). corpo\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cy"
	EXIT_CY=$?
	[ $EXIT_CY -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CY)"

	# Caso (cz): cat <<EOF && gh issue close 12 → exit 2
	echo
	echo "== (cz) gh na mesma linha do heredoc, apos '&&' → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<EOF && gh issue close 12\\n(x). corpo\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-cz"
	EXIT_CZ=$?
	[ $EXIT_CZ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_CZ)"

	# Caso (da): cat <<'EOF' | gh pr create --body "closes #999" (sem evidência) → exit 2
	echo
	echo "== (da) heredoc entubado em gh pr create com closes sem evidencia → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF' | gh pr create --body \\\"closes #999\\\"\\n(x). corpo\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-da"
	EXIT_DA=$?
	[ $EXIT_DA -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DA)"

	# Segunda revisão do zerar-issues-3 (2026-09-13): com `<<-` o bash tira as
	# TABs da linha de fechamento — `\tEOF` fecha o heredoc de verdade, e o
	# `gh` da linha seguinte roda. A comparação exata lia tudo como corpo.
	# Caso (db): cat <<-EOF, fechamento com TAB, gh depois → exit 2
	echo
	echo "== (db) <<-EOF fechado por linha com TAB, gh depois → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<-EOF\\n\\tcorpo\\n\\tEOF\\ngh issue close 12\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-db"
	EXIT_DB=$?
	[ $EXIT_DB -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DB)"

	# Caso (dc): cat <<-'EOF' com prosa indentada por TAB e fechamento com TAB → exit 0
	echo
	echo "== (dc) <<-'EOF' com prosa (x). indentada e fechamento com TAB → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > d.md <<-'EOF'\\n\\t\\t(x). Ele sobe.\\n\\t\\tEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dc"
	EXIT_DC=$?
	[ $EXIT_DC -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DC)"

	# Terceira revisão do zerar-issues-3 (2026-09-13): `<<<` é here-string, não
	# heredoc — a string vem na mesma linha, não há fechamento, e a linha
	# seguinte é comando novo. O gate lia `<bar` como delimitador que nunca
	# fecha e engolia o `gh`.
	# Caso (dd): cat <<<bar, gh na linha seguinte → exit 2
	echo
	echo "== (dd) here-string <<< seguido de gh na linha seguinte → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<<bar\\ngh issue close 12\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dd"
	EXIT_DD=$?
	[ $EXIT_DD -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DD)"

	# Quarta revisão do zerar-issues-3 (2026-09-13): here-string dirigido a um
	# interpretador é script, como o heredoc de `bash <<EOF`.
	# Caso (de): bash <<<'gh issue close 12' → exit 2
	echo
	echo "== (de) bash <<<'gh issue close 12' → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"bash <<<'gh issue close 12'\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-de"
	EXIT_DE=$?
	[ $EXIT_DE -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DE)"

	# Caso (df): cat <<<'gh issue close 12' → exit 2 (oitava revisão: o texto do
	# here-string para sumidouro entra na varredura direta, como o corpo de
	# heredoc — `> s.sh` + `bash s.sh` executa; antes o caso esperava 0)
	echo
	echo "== (df) cat <<<'gh issue close 12' (texto com padrao direto) → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<<'gh issue close 12'\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-df"
	EXIT_DF=$?
	[ $EXIT_DF -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DF)"

	# Quinta revisão do zerar-issues-3 (2026-09-13): o interpretador pode vir
	# atrás de um wrapper que repassa stdin; o primeiro token era `env`, não
	# batia na lista, e o corpo virava dado (na main esses casos saíam 2).
	# Caso (dg): env bash <<'EOF' com gh no corpo → exit 2
	echo
	echo "== (dg) env bash <<'EOF' com gh issue close no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"env bash <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dg"
	EXIT_DG=$?
	[ $EXIT_DG -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DG)"

	# Caso (dh): timeout 5 bash <<<'gh issue close 12' → exit 2
	echo
	echo "== (dh) timeout 5 bash <<<'gh issue close 12' → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"timeout 5 bash <<<'gh issue close 12'\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dh"
	EXIT_DH=$?
	[ $EXIT_DH -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DH)"

	# Caso (di): bash <<<gh\ issue\ close\ 12 (palavra nua com escapes) → exit 2
	echo
	echo "== (di) here-string nu com espacos escapados para bash → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"bash <<<gh\\\\ issue\\\\ close\\\\ 12\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-di"
	EXIT_DI=$?
	[ $EXIT_DI -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DI)"

	# Caso (dj): env cat <<'EOF' com gh literal no corpo → exit 2 (texto varrido; sétima revisão — antes esperava 0)
	echo
	echo "== (dj) env cat <<'EOF' com gh issue close literal no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"env cat <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dj"
	EXIT_DJ=$?
	[ $EXIT_DJ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DJ)"

	# Sexta revisão do zerar-issues-3 (2026-09-13): o corpo é script se a
	# LINHA do heredoc tem interpretador em qualquer posição — agrupamento e
	# pipe para interpretador nu não têm `bash` como dono do `<<`.
	# Caso (dk): (bash) <<'EOF' com gh no corpo → exit 2
	echo
	echo "== (dk) (bash) <<'EOF' com gh issue close no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"(bash) <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dk"
	EXIT_DK=$?
	[ $EXIT_DK -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DK)"

	# Caso (dl): cat <<'EOF' | bash com gh no corpo → exit 2
	echo
	echo "== (dl) cat <<'EOF' | bash com gh issue close no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF' | bash\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dl"
	EXIT_DL=$?
	[ $EXIT_DL -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DL)"

	# Caso (dm): cat <<'EOF' > d.md com prosa continua dado → exit 0
	echo
	echo "== (dm) cat <<'EOF' > d.md com prosa (x). → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF' > d.md\\n(x). Ele sobe.\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dm"
	EXIT_DM=$?
	[ $EXIT_DM -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DM)"

	# Sétima revisão do zerar-issues-3 (2026-09-13): continuação de linha e
	# corpos executados por caminhos que o gate não rastreia.
	# Caso (dn): cat <<'EOF' \ + | bash na linha seguinte (linha lógica) → exit 2
	echo
	echo "== (dn) cat <<'EOF' com continuacao \\ e | bash na linha de baixo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF' \\\\\\\\\\n| bash\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dn"
	EXIT_DN=$?
	[ $EXIT_DN -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DN)"

	# Caso (do): corpo gravado em arquivo e executado na linha seguinte → exit 2 (texto varrido)
	echo
	echo "== (do) cat <<'EOF' > s.sh + bash s.sh na linha seguinte → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<'EOF' > s.sh\\ngh issue close 12\\nEOF\\nbash s.sh\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-do"
	EXIT_DO=$?
	[ $EXIT_DO -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DO)"

	# Caso (dp): while read executando cada linha do corpo → exit 2 (texto varrido)
	echo
	echo "== (dp) while read -r l; do \$l; done <<'EOF' com gh no corpo → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"while read -r l; do \$l; done <<'EOF'\\ngh issue close 12\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dp"
	EXIT_DP=$?
	[ $EXIT_DP -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DP)"

	# Caso (dq): prosa que MENCIONA o gate sem a sequência completa → exit 0
	echo
	echo "== (dq) prosa 'a sequencia gh issue e barrada' + \$(ls) + crase → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > x.md <<'EOF'\\nO gate le a sequencia gh issue e barra; saida de \$(ls) e \\\`pwd\\\` (x). fim\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dq"
	EXIT_DQ=$?
	[ $EXIT_DQ -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DQ)"

	# Caso (dr): comentário shell no corpo com a sequência → exit 0 (mesma regra da W2)
	echo
	echo "== (dr) '# gh issue close 12' comentado no corpo → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat > x.md <<'EOF'\\n# gh issue close 12 comentado\\nEOF\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dr"
	EXIT_DR=$?
	[ $EXIT_DR -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DR)"

	# Oitava revisão do zerar-issues-3 (2026-09-13): here-string gravado em
	# arquivo e executado na linha seguinte — o texto do here-string entra na
	# varredura direta, como o corpo de heredoc.
	# Caso (ds): cat <<<'gh issue close 12' > s.sh + bash s.sh → exit 2
	echo
	echo "== (ds) cat <<<'gh issue close 12' > s.sh + bash s.sh → exit 2 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<<'gh issue close 12' > s.sh\\nbash s.sh\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-ds"
	EXIT_DS=$?
	[ $EXIT_DS -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DS)"

	# Caso (dt): here-string de prosa para arquivo → exit 0
	echo
	echo "== (dt) cat <<<'Medido (x). Ele sobe.' > d.md → exit 0 =="
	(
	  export PATH="$SBP/bin:$PATH"
	  PAYLOAD=$(node -e "console.log(JSON.stringify({cwd:'$SBP_WIN',tool_name:'Bash',tool_input:{command:\"cat <<<'Medido (x). Ele sobe.' > d.md\"}}))")
	  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
	) 2>"$SBP/err-dt"
	EXIT_DT=$?
	[ $EXIT_DT -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DT)"

# bypass por palavra reservada (#309): `posicaoDeComando` (tokens-comando.cjs)
# nao pulava palavra reservada do shell (`do`/`then`/`else`/`elif`/`while`/
# `until`/`if`/`!`) antes de um wrapper de string — a busca parava NA PROPRIA
# palavra reservada (nao e atribuicao nem wrapper conhecido), e o `bash -c
# "gh issue close 12"` logo depois nunca era desempacotado. `{`/`(` ja saiam
# exit 2 sem mudanca nenhuma (medido): `segmentosParaGate` os consome como
# fronteira de SEGMENTO antes da tokenizacao — entram aqui so como controle.
echo
echo "== (du) for t in x; do bash -c \"gh issue close 12\"; done → exit 2 (bypass por palavra reservada #309, do) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"for t in x; do bash -c \"gh issue close 12\"; done"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-du"
EXIT_DU=$?
[ $EXIT_DU -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DU)"

echo
echo "== (dv) if true; then bash -c \"gh issue close 12\"; fi → exit 2 (bypass por palavra reservada #309, then) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"if true; then bash -c \"gh issue close 12\"; fi"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-dv"
EXIT_DV=$?
[ $EXIT_DV -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DV)"

echo
echo "== (dw) while true; do bash -c \"gh issue close 12\"; done → exit 2 (bypass por palavra reservada #309, while/do) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"while true; do bash -c \"gh issue close 12\"; done"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-dw"
EXIT_DW=$?
[ $EXIT_DW -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DW)"

echo
echo "== (dx) ! bash -c \"gh issue close 12\" → exit 2 (bypass por palavra reservada #309, !) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"! bash -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-dx"
EXIT_DX=$?
[ $EXIT_DX -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DX)"

echo
echo "== (dy) { bash -c \"gh issue close 12\"; } → exit 2 (bypass por palavra reservada #309, controle: ja passava) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"{ bash -c \"gh issue close 12\"; }"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-dy"
EXIT_DY=$?
[ $EXIT_DY -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_DY)"

echo
echo "== (dz) if true; then gh issue view 12; fi → exit 0 (regressao: view continua liberado atras de reservada) =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"if true; then gh issue view 12; fi"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-dz"
EXIT_DZ=$?
[ $EXIT_DZ -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_DZ)"

# (#309) bash "$t" como ultimo argumento: variavel citada com aspas DUPLAS,
# sozinha, como ULTIMO argumento (redirecionamento nao conta), e um CAMINHO
# DE SCRIPT — mesmo tratamento que `bash ./script.sh` ja recebe (D17). Antes
# deste conserto `contemConstrucaoIlegivel` marcava `"$t"` como ilegivel pela
# MESMA regra que pega `bash $CMD` (variavel de verdade, nao resolvida) —
# falso positivo diario: `for t in $(...); do bash "$t"; done` e o padrao
# real usado para rodar as proprias baterias deste repo. Mais argumento
# depois da variavel citada (`bash "$t" x`), ou variavel SEM aspas
# (`bash $t`), continuam ilegivel — a variavel ali pode ser qualquer coisa,
# inclusive um `-c` escondido.
echo
echo '== (fa) for t in $(grep -lE "CHANGELOG|badge|plugin.json" scripts/testa-*.sh hooks/testa-*.sh); do bash "$t"; done → exit 0 ((#309) bash "$t" como ultimo argumento) =='
(
  export PATH="$SBP/bin:$PATH"
  CMD_FA='for t in $(grep -lE "CHANGELOG|badge|plugin\.json" scripts/testa-*.sh hooks/testa-*.sh); do bash "$t"; done'
  PAYLOAD=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$CMD_FA")
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fa"
EXIT_FA=$?
[ $EXIT_FA -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FA)"

echo
echo '== (fb) bash "$t" → exit 0 ((#309) bash "$t" como ultimo argumento) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$t\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fb"
EXIT_FB=$?
[ $EXIT_FB -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FB)"

echo
echo '== (fc) bash "${t}" → exit 0 ((#309) bash "$t" como ultimo argumento) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"${t}\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fc"
EXIT_FC=$?
[ $EXIT_FC -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FC)"

echo
echo '== (fd) bash "$t" 2>&1 → exit 0 ((#309) bash "$t" como ultimo argumento) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$t\" 2>&1"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fd"
EXIT_FD=$?
[ $EXIT_FD -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FD)"

echo
echo '== (fe) bash "$t" > log → exit 0 ((#309) bash "$t" como ultimo argumento) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$t\" > log"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fe"
EXIT_FE=$?
[ $EXIT_FE -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FE)"

echo
echo '== (ff) bash "$f" "gh issue close 12" → exit 2 ((#309) bash "$t" como ultimo argumento, mais argumento depois) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$f\" \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-ff"
EXIT_FF=$?
[ $EXIT_FF -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FF)"

echo
echo '== (fg) bash $t → exit 2 ((#309) bash "$t" como ultimo argumento, sem aspas) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash $t"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fg"
EXIT_FG=$?
[ $EXIT_FG -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FG)"

echo
echo '== (fh) bash "$t" x → exit 2 ((#309) bash "$t" como ultimo argumento, mais argumento depois) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$t\" x"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fh"
EXIT_FH=$?
[ $EXIT_FH -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FH)"

echo
echo '== (fi) for t in x; do bash -c "gh issue close 12"; done → exit 2 ((#309) bash "$t" como ultimo argumento, controle T1) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"for t in x; do bash -c \"gh issue close 12\"; done"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fi"
EXIT_FI=$?
[ $EXIT_FI -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FI)"

# coproc (#309, revisao): mesmo bypass de `posicaoDeComando` que do/then/else/
# elif/while/until/if/! ja tinham — `coproc bash -c "..."` (sem nome) fazia
# a busca parar na propria palavra reservada, sem ver o `bash -c` depois.
# Medido na revisao de 2026-09-22: exit 0 antes de `coproc` entrar em
# PALAVRAS_RESERVADAS. Achado 1 da revisao.
echo
echo '== (fj) coproc bash -c "gh issue close 12" → exit 2 (coproc (#309, revisao)) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"coproc bash -c \"gh issue close 12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fj"
EXIT_FJ=$?
[ $EXIT_FJ -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FJ)"

# parametro especial (#309, revisao): `contemConstrucaoIlegivel` nao tratava
# `$@`/`$*`/`$#`/`$?`/`$$`/`$!`/`$-` como variavel — so identificador
# (`[A-Za-z_{0-9]`) entrava na classe. `set -- -c "gh issue close 12"; bash
# "$@"`, `bash "$*"`, `eval "$@"` e `eval $@` saiam exit 0 (ilegivel nunca
# detectado). Medido na revisao de 2026-09-22, antes do conserto: exit 0 nos
# quatro. `ehVariavelCitadaFinal` continua so aceitando `"$nome"`/`"${nome}"`
# (identificador), entao `"$@"`/`"$*"` nunca viram caminho de script por
# aquele ramo — ficam ilegivel, que bloqueia aqui. Achado 2 da revisao.
echo
echo '== (fk) set -- -c "gh issue close 12"; bash "$@" → exit 2 (parametro especial (#309, revisao)) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"set -- -c \"gh issue close 12\"; bash \"$@\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fk"
EXIT_FK=$?
[ $EXIT_FK -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FK)"

echo
echo '== (fl) bash "$*" → exit 2 (parametro especial (#309, revisao)) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$*\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fl"
EXIT_FL=$?
[ $EXIT_FL -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FL)"

echo
echo '== (fm) eval "$@" → exit 2 (parametro especial (#309, revisao)) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"eval \"$@\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fm"
EXIT_FM=$?
[ $EXIT_FM -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FM)"

echo
echo '== (fn) eval $@ → exit 2 (parametro especial (#309, revisao), sem aspas) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"eval $@"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fn"
EXIT_FN=$?
[ $EXIT_FN -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_FN)"

echo
echo '== (fo) bash "$t" → exit 0 continua (parametro especial (#309, revisao), regressao: caminho de script nao vira ilegivel) =='
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP_WIN"'","tool_name":"Bash","tool_input":{"command":"bash \"$t\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-fo"
EXIT_FO=$?
[ $EXIT_FO -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_FO)"

# Resultado final
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
