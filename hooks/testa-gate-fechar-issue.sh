#!/bin/bash
# Bateria para hooks/gate-fechar-issue.cjs com trava

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Criar versão .cmd para Windows (fallback)
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
echo
echo "== (j) C:\\qualquer\\gh.exe pr merge com closes (sem marcador) → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
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
echo
echo "== (ah) true & gh pr merge 7 com closes #7 sem marcador → exit 2 (K1) =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
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

# Resultado final
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
