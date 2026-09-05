#!/bin/bash
# Bateria do gate-publicacao-destino.cjs. Monta repo e worktree git de verdade e
# alimenta o hook com payloads reais de PreToolUse, conferindo exit code.
# Uso: bash hooks/testa-gate-publicacao-destino.sh
#
# O que esta bateria precisa provar:
#   1. arquivo versionado + conteúdo com telefone/JID → barrado (exit 2)
#   2. arquivo gitignorado + mesmo conteúdo → passa (exit 0)
#   3. fora de repo git → passa (exit 0)
#   4. conteúdo limpo em arquivo versionado → passa (exit 0)
#   5. escape (RAINFOREST_GATE_OFF=1) → passa mesmo com conteúdo sujo (exit 0)
#   6. progress.jsonl versionado recebendo JID → barrado (exit 2)
#   7. marcador "rainforest-gate: dados-de-exemplo" dispensa conferência (exit 0)
#   8. sem marcador, conteúdo sujo é barrado — marcador não vaza para vizinhos (exit 2)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-publicacao-destino.cjs"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -10; fi
}

# Prepara repo com git
R="$RAIZ/principal"
git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
echo "v1" > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base

# Prepare diretórios para testes fora de repo
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"

# Payload montado por `node` com os valores chegando em `argv`, nunca por printf.
# Em 2026-08-25 os casos do marcador ficaram VERDES com a guarda desligada: o
# printf com aspas triplamente escapadas entregava JSON invalido, o `JSON.parse`
# do hook caia no catch e saia 0 — o exit esperado, pelo motivo errado. Valor em
# argv nao tem nivel de escape para errar.
pay() { # tool, file_path, conteudo(content|new_string), [old_string]
  node -e 'const [t,fp,c,o]=process.argv.slice(1);const ti=t==="Write"?{file_path:fp,content:c}:{file_path:fp,old_string:o||"x",new_string:c};console.log(JSON.stringify({cwd:process.env.PAY_CWD||"",hook_event_name:"PreToolUse",tool_name:t,tool_input:ti}))' "$1" "$2" "$3" "${4:-}"
}

esc() { printf '%s' "$1" | sed 's|\\|/|g'; }

# Helpers de Write/Edit em cima do `pay` (node), nunca de `jq`. Issue #158:
# ate 2026-09-02 estes dois montavam o JSON com `jq -Rs`, e numa maquina sem jq
# o payload saia VAZIO — o gate recebia entrada vazia e saia 0 em todos os oito
# casos. Os quatro que esperavam 0 ficavam "ok" sem ter exercido nada. A regra
# do CONTRIBUTING (Node e a unica dependencia) vale para o caminho de teste.
write() { # arquivo, conteudo, [cwd]
  local arquivo="$1" conteudo="$2" cwd="${3:-$(esc "$R")}"
  PAY_CWD="$cwd" pay Write "$(esc "$arquivo")" "$conteudo"$'
'
}
edit() { # arquivo, novo, [cwd]
  local arquivo="$1" novo="$2" cwd="${3:-$(esc "$R")}"
  PAY_CWD="$cwd" pay Edit "$(esc "$arquivo")" "$novo"$'
' "old"
}

echo "== Preparação: dados sensíveis para testes =="
JID_REAL="5500900000001@s.whatsapp.net"
TEL_REAL="(00) 90000-0001"
EMAIL_REAL="teste@example.com"
CONTEUDO_LIMPO="arquivo normal sem dados sensíveis"

echo "  JID: $JID_REAL"
echo "  Tel: $TEL_REAL"
echo "  Email: $EMAIL_REAL"

echo
echo "== CASO 1: arquivo versionado + conteúdo com JID → barrado (exit 2) =="
git -C "$R" add -A 2>/dev/null || true
gate "Write em arquivo versionado com JID" 2 "$(write "$R/test-jid.txt" "contato: $JID_REAL")"

echo
echo "== CASO 2: arquivo gitignorado + conteúdo com JID → passa (exit 0) =="
mkdir -p "$R/.gitignore.d"
printf '%s\n' '*.ignored' >> "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "add gitignore" || true
gate "Write em arquivo gitignorado com JID" 0 "$(write "$R/test.ignored" "contato: $JID_REAL")"

echo
echo "== CASO 3: fora de repo git → passa (exit 0) =="
gate "Write fora de repo com JID" 0 "$(write "$FORA/arquivo.txt" "contato: $JID_REAL" "$(esc "$FORA")")"

echo
echo "== CASO 4: conteúdo limpo em arquivo versionado → passa (exit 0) =="
gate "Write em versionado com conteúdo limpo" 0 "$(write "$R/limpo.txt" "$CONTEUDO_LIMPO")"

echo
echo "== CASO 5: escape RAINFOREST_GATE_OFF=1 → passa mesmo com conteúdo sujo (exit 0) =="
saida=$(printf '%s' "$(write "$R/escape.txt" "contato: $JID_REAL")" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera com conteúdo sujo (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF não liberou (exit $rc)"; echo "$saida" | sed 's/^/         /' | head -5; fi

echo
echo "== CASO 6: progress.jsonl versionado com JID → barrado (exit 2) =="
# Reproduz o caso real da Issue #83
mkdir -p "$R/_reversa_forward/004-teste"
PROGRESS="$R/_reversa_forward/004-teste/progress.jsonl"
PROGRESS_CONTEUDO=$(printf '{"status":"smoke test","contato":"%s","resultado":"ok"}\n' "$JID_REAL")
gate "progress.jsonl versionado com JID (Issue #83)" 2 "$(write "$PROGRESS" "$PROGRESS_CONTEUDO")"

echo
echo "== FALSIFICAÇÃO 1: Desligar o gate e deixar passar conteúdo sujo =="
echo "Esperado: com conteúdo sujo, exit 2 (barrado)"
msg=$(printf '%s' "$(write "$R/fake-test.txt" "contato: $JID_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ]; then
  ok=$((ok+1))
  echo "  ok   conteúdo sujo foi BARRADO (exit $rc)"
  echo "  Mensagem de bloqueio:"
  printf '%s' "$msg" | sed 's/^/    /' | head -15
else
  falhou=$((falhou+1))
  echo "  FALHA conteúdo sujo passou (exit $rc) — gate não funciona!"
fi

echo
echo "== FALSIFICAÇÃO 2: Telefone sem JID também é detectado =="
echo "Esperado: exit 2 (barrado por padrão 'telefone')"
msg=$(printf '%s' "$(write "$R/fake-tel.txt" "telefone do cliente: $TEL_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ]; then
  ok=$((ok+1))
  echo "  ok   telefone foi BARRADO (exit $rc)"
  echo "  Mensagem menciona padrão:"
  if printf '%s' "$msg" | grep -q "telefone\|phone"; then
    ok=$((ok+1))
    echo "    ✓ mensagem menciona 'telefone'"
  else
    falhou=$((falhou+1))
    echo "    ✗ mensagem NÃO menciona o padrão"
  fi
else
  falhou=$((falhou+1))
  echo "  FALHA telefone passou (exit $rc) — gate não funciona!"
fi

echo
echo "== Teste de escape com .rainforest-gate-off =="
touch "$R/.rainforest-gate-off"
msg=$(printf '%s' "$(write "$R/escape-arquivo.txt" "contato: $JID_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1))
  echo "  ok   .rainforest-gate-off libera gate (exit 0)"
else
  falhou=$((falhou+1))
  echo "  FALHA .rainforest-gate-off não liberou (exit $rc)"
fi
rm "$R/.rainforest-gate-off"

echo
echo "== Teste do marcador: le o DISCO, nao o conteudo que chega =="
# O arquivo real tem o marcador no topo; o fragmento do Edit nao tem. Se o gate
# lesse o conteudo que chega, este caso barraria — foi o furo de 5480ce4^.
gate "Edit em arquivo COM marcador em disco, fragmento sem marcador -> passa" 0   "$(pay Edit "$(esc "$SRC")/scripts/testa-conferir-publicacao.sh" 'jid="5500900000001@s.whatsapp.net"')"

# O espelho, e o que faz a mutacao doer dos dois lados: arquivo vizinho SEM
# marcador, mesmo conteudo, tem de barrar. Marcador que vazasse para o diretorio
# deixaria este verde.
gate "Edit em arquivo vizinho SEM marcador, mesmo conteudo -> barrado" 2   "$(pay Edit "$(esc "$SRC")/scripts/conferir-publicacao.cjs" 'jid="5500900000001@s.whatsapp.net"')"

# Arquivo novo trazendo o marcador no proprio conteudo: nao existe em disco,
# entao nao ha marcador — auto-isencao num unico write nao passa.
gate "Write de arquivo novo com marcador embutido -> barrado" 2   "$(pay Write "$(esc "$R")/arquivo-com-marcador.sh" '# rainforest-gate: dados-de-exemplo
jid="5500900000001@s.whatsapp.net"')"

# Entrada malformada nunca derruba a sessao: sai 0. E o comportamento certo, e
# tambem o que escondeu os casos acima quando o payload vinha quebrado — por isso
# ele fica travado por um caso proprio, e nao suposto.
gate "payload invalido -> sai 0 sem derrubar" 0 '{"invalid": json}'

echo
echo "== CASO 9: o gate julga o que o commit INTRODUZ, nao o conteudo total (defect a) =="
# Ate 2026-09-04 o gate lia `git show :<arquivo>` inteiro e barrava merge de
# conteudo que ja estava publicado na main ha dias — Issue #173. Estes casos
# rodam no caminho REAL: payload de `Bash` com `git commit`, que e o que o
# harness manda. O caminho de `Write`/`Edit` NAO tem isencao nenhuma e continua
# barrando conteudo sensivel escrito a mao (casos 1 a 8 acima) — a isencao vale
# so para o que ja esta num pai do commit.
payBash() { # comando, cwd
  node -e 'const [c,d]=process.argv.slice(1);console.log(JSON.stringify({cwd:d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:c}}))' "$1" "$2"
}

M="$RAIZ/pai"
git init -q -b main "$M"; git -C "$M" config user.email t@t; git -C "$M" config user.name t
git -C "$M" config commit.gpgsign false
printf 'contato: %s\nlinha comum\n' "$JID_REAL" > "$M/dados.txt"
git -C "$M" add dados.txt; git -C "$M" commit -qm "commit que introduziu o JID"

# 9a: o arquivo ja esta commitado e a alteracao nova NAO toca a linha do achado.
printf 'linha inocente\n' >> "$M/dados.txt"
git -C "$M" add dados.txt
gate "9a: achado que ja esta no pai nao barra o commit seguinte" 0 \
  "$(payBash 'git commit -m x' "$(esc "$M")")"

# 9b: linha NOVA com achado novo continua barrando — a isencao nao afrouxa nada.
printf 'outro: %s\n' "5500900000002@s.whatsapp.net" >> "$M/dados.txt"
git -C "$M" add dados.txt
gate "9b: linha nova com achado novo continua barrando" 2 \
  "$(payBash 'git commit -m x' "$(esc "$M")")"

# 9c: merge de verdade — o arquivo com o achado entra vindo do OUTRO pai, que e
# exatamente o caso de campo da Issue #173 (`git merge origin/main`).
N="$RAIZ/merge"
git init -q -b main "$N"; git -C "$N" config user.email t@t; git -C "$N" config user.name t
git -C "$N" config commit.gpgsign false
echo "base" > "$N/base.txt"; git -C "$N" add base.txt; git -C "$N" commit -qm base
git -C "$N" checkout -q -b lateral
echo "trabalho lateral" > "$N/lateral.txt"; git -C "$N" add lateral.txt
git -C "$N" commit -qm lateral
git -C "$N" checkout -q main
printf 'contato: %s\n' "$JID_REAL" > "$N/publicado.txt"
git -C "$N" add publicado.txt; git -C "$N" commit -qm "ja publicado na main"
git -C "$N" checkout -q lateral
git -C "$N" merge --no-commit --no-ff main > /dev/null 2>&1
gate "9c: merge que traz arquivo ja publicado no outro pai -> passa" 0 \
  "$(payBash 'git commit --no-edit' "$(esc "$N")")"

echo "== Verificação: gate-staging-total continua verde =="
echo "Rodando: bash hooks/testa-gate-staging-total.sh"
if bash "$SRC/hooks/testa-gate-staging-total.sh" > /tmp/test-staging.log 2>&1; then
  ok=$((ok+1))
  echo "  ok   gate-staging-total passou"
else
  falhou=$((falhou+1))
  echo "  FALHA gate-staging-total falhou"
  tail -20 /tmp/test-staging.log | sed 's/^/    /'
fi

echo
echo "== Verificação: conferir-publicacao.sh continua verde =="
echo "Rodando: bash scripts/testa-conferir-publicacao.sh"
if bash "$SRC/scripts/testa-conferir-publicacao.sh" > /tmp/test-conferir.log 2>&1; then
  ok=$((ok+1))
  echo "  ok   conferir-publicacao passou"
else
  falhou=$((falhou+1))
  echo "  FALHA conferir-publicacao falhou"
  tail -20 /tmp/test-conferir.log | sed 's/^/    /'
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
