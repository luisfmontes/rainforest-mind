#!/bin/bash
# rainforest-gate: dados-de-exemplo
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
#   9. .rainforest-gate-off no checkout principal libera o gate rodando de um
#      worktree linkado do mesmo repo (Issue #265)
#  10. mensagem de bloqueio cita setup.cjs --desligar gate-publicacao antes das
#      saídas de emergência (Issue #268)
#  11. marcador só conta nas 5 primeiras linhas do arquivo — marcador na
#      linha 6 não dispensa a conferência (Issue #293)

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
echo "== CASO NOVO (Issue #265): .rainforest-gate-off do checkout principal libera gate rodando de worktree linkado =="
WT="$RAIZ/worktree-linkado"
git -C "$R" worktree add -q "$WT" -b wt-gate-off-branch >/dev/null 2>&1
echo "v1" > "$WT/b.txt"
msg=$(printf '%s' "$(write "$WT/escape-worktree.txt" "contato: $JID_REAL" "$(esc "$WT")")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ]; then
  ok=$((ok+1)); echo "  ok   sem .rainforest-gate-off, worktree barra normalmente (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA worktree passou sem gate-off (exit $rc) — sanidade do caso quebrada"
fi
touch "$R/.rainforest-gate-off"
msg=$(printf '%s' "$(write "$WT/escape-worktree.txt" "contato: $JID_REAL" "$(esc "$WT")")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1)); echo "  ok   .rainforest-gate-off do principal libera gate a partir do worktree (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA nao herdou o gate-off do principal (exit $rc)"; echo "$msg" | sed 's/^/         /' | head -10
fi
rm "$R/.rainforest-gate-off"
git -C "$R" worktree remove --force "$WT" >/dev/null 2>&1

echo
echo "== CASO NOVO (Issue #268): mensagem de bloqueio oferece setup.cjs --desligar antes das saidas de emergencia =="
msg=$(printf '%s' "$(write "$R/mensagem-toggle.txt" "contato: $JID_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ] && printf '%s' "$msg" | grep -q "setup.cjs --desligar gate-publicacao"; then
  ok=$((ok+1)); echo "  ok   mensagem cita setup.cjs --desligar gate-publicacao"
else
  falhou=$((falhou+1)); echo "  FALHA mensagem nao cita o toggle do setup.cjs"; echo "$msg" | sed 's/^/         /' | head -15
fi
if printf '%s' "$msg" | grep -qE "setup\.cjs.*RAINFOREST_GATE_OFF" ; then
  falhou=$((falhou+1)); echo "  FALHA ordem errada: RAINFOREST_GATE_OFF nao pode vir antes do setup.cjs"
else
  # ordem certa: a linha do setup.cjs aparece ANTES da linha do RAINFOREST_GATE_OFF
  linha_setup=$(printf '%s' "$msg" | grep -n "setup.cjs --desligar gate-publicacao" | head -1 | cut -d: -f1)
  linha_env=$(printf '%s' "$msg" | grep -n "RAINFOREST_GATE_OFF=1 no ambiente da sessão" | head -1 | cut -d: -f1)
  if [ -n "$linha_setup" ] && [ -n "$linha_env" ] && [ "$linha_setup" -lt "$linha_env" ]; then
    ok=$((ok+1)); echo "  ok   setup.cjs aparece antes de RAINFOREST_GATE_OFF (ordem preco-crescente)"
  else
    falhou=$((falhou+1)); echo "  FALHA ordem preco-crescente nao respeitada (setup=$linha_setup env=$linha_env)"
  fi
fi

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

echo
echo "== CASO 11: marcador so conta nas 5 primeiras linhas (Issue #293) =="
# Arquivo com o marcador so na linha 6 (fora da janela de 5 primeiras linhas).
# Antes do conserto, temMarcadorDados varria o arquivo inteiro e este caso
# passava (exit 0) mesmo trazendo credencial nova pelo Edit.
printf 'linha um\nlinha dois\nlinha tres\nlinha quatro\nlinha cinco\n# rainforest-gate: dados-de-exemplo\n' > "$R/marcador-tardio.sh"
git -C "$R" add marcador-tardio.sh; git -C "$R" commit -qm "marcador tardio"
gate "Edit em arquivo com marcador so na linha 6 -> barrado" 2   "$(pay Edit "$(esc "$R")/marcador-tardio.sh" 'jid="5500900000001@s.whatsapp.net"')"

# Entrada malformada nunca derruba a sessao: sai 0. E o comportamento certo, e
# tambem o que escondeu os casos acima quando o payload vinha quebrado — por isso
# ele fica travado por um caso proprio, e nao suposto.
gate "payload invalido -> sai 0 sem derrubar" 0 '{"invalid": json}'

echo
echo "== CASO 10: conteúdo sensível com agent_id (subagente) — barrado, sem nomear saídas =="
# Subagente que tenta escrever dados sensíveis: barrado com exit 2, mas a mensagem
# não nomeia as saídas de emergência (.rainforest-gate-off e RAINFOREST_GATE_OFF).
payWithAgent() { # tool, file_path, conteudo, agent_id
  node -e 'const [t,fp,c,a]=process.argv.slice(1);const ti=t==="Write"?{file_path:fp,content:c}:{file_path:fp,old_string:"x",new_string:c};console.log(JSON.stringify({cwd:process.env.PAY_CWD||"",hook_event_name:"PreToolUse",tool_name:t,tool_input:ti,agent_id:a,agent_type:"executor"}))' "$1" "$2" "$3" "$4"
}
msg=$(printf '%s' "$(PAY_CWD="$(esc "$R")" payWithAgent Write "$(esc "$R")/test-agent.txt" "contato: $JID_REAL" "agent-xyz")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then
  ok=$((ok+1))
  echo "  ok   subagente com dados sensíveis foi BARRADO (exit 2)"
  # Verifica que a mensagem não contém as saídas de emergência nomeadas
  if ! printf '%s' "$msg" | grep -q "\.rainforest-gate-off\|RAINFOREST_GATE_OFF"; then
    ok=$((ok+1))
    echo "  ok   mensagem não nomeia saídas de emergência"
  else
    falhou=$((falhou+1))
    echo "  FALHA mensagem nomeia saídas (que não deveria)"
    printf '%s' "$msg" | sed 's/^/    /'
  fi
  # Verifica que a mensagem contém "PARE e reporte"
  if printf '%s' "$msg" | grep -q "PARE e reporte"; then
    ok=$((ok+1))
    echo "  ok   mensagem contém 'PARE e reporte'"
  else
    falhou=$((falhou+1))
    echo "  FALHA mensagem não contém 'PARE e reporte'"
  fi
else
  falhou=$((falhou+1))
  echo "  FALHA esperava exit 2 para subagente, veio $rc"
  echo "$msg" | sed 's/^/    /'
fi

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
#
# A fixture PUBLICA a main num remoto de verdade, e nao so a chama de publicada:
# a isencao do outro pai vale para commit que ja existe em ramo remoto, e nao
# para qualquer branch local. Sem o remoto, este caso media a palavra do
# comentario em vez do estado do repositorio.
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
git init -q --bare "$RAIZ/remoto.git"
git -C "$N" remote add origin "$RAIZ/remoto.git"
git -C "$N" push -q origin main
git -C "$N" checkout -q lateral
git -C "$N" merge --no-commit --no-ff main > /dev/null 2>&1
gate "9c: merge que traz arquivo ja publicado no outro pai -> passa" 0 \
  "$(payBash 'git commit --no-edit' "$(esc "$N")")"
git -C "$N" merge --abort > /dev/null 2>&1

# 9d: a contraprova que o 9c sozinho nao da. O outro pai e uma branch LOCAL, que
# nunca foi publicada e cujos commits nunca passaram por gate nenhum: o segredo
# e novo para o destino, e merge nao pode virar a porta de entrada dele. Sem
# esta distincao bastava commitar o segredo numa branch e mergear para publicar.
git -C "$N" checkout -q main
git -C "$N" checkout -q -b naopublicada
printf 'contato: %s\n' "5500900000003@s.whatsapp.net" > "$N/de-fora.txt"
git -C "$N" add de-fora.txt; git -C "$N" commit -qm "segredo em branch local"
git -C "$N" checkout -q main
git -C "$N" merge --no-commit --no-ff naopublicada > /dev/null 2>&1
gate "9d: merge de branch NAO publicada com achado novo continua barrando" 2 \
  "$(payBash 'git commit --no-edit' "$(esc "$N")")"
git -C "$N" merge --abort > /dev/null 2>&1

# 9e: "publicado" e no remoto de DESTINO, nao em qualquer remoto cadastrado.
# Reproduzido na revisao de 2026-09-05: bastava `git remote add espelho <bare
# descartavel>` e um push para la, e o merge seguinte tratava o segredo como ja
# publicado — a mesma porta que o 9d fecha, reaberta por outro caminho. Nenhum
# gate deste lote olha `remote add` nem `push`, entao a porta era de uma linha.
git init -q --bare "$RAIZ/espelho.git"
git -C "$N" remote add espelho "$RAIZ/espelho.git"
git -C "$N" checkout -q main
git -C "$N" checkout -q -b so-no-espelho
printf 'contato: %s\n' "5500900000004@s.whatsapp.net" > "$N/de-espelho.txt"
git -C "$N" add de-espelho.txt; git -C "$N" commit -qm "segredo empurrado so para o espelho"
git -C "$N" push -q espelho so-no-espelho
git -C "$N" fetch -q espelho
git -C "$N" checkout -q main
git -C "$N" merge --no-commit --no-ff so-no-espelho > /dev/null 2>&1
gate "9e: publicado so num remoto que nao e o destino continua barrando" 2 \
  "$(payBash 'git commit --no-edit' "$(esc "$N")")"
git -C "$N" merge --abort > /dev/null 2>&1

echo
echo "== NOVOS TESTES: visibilidade de repositório (D6) =="

# Preparar sandbox para os testes de visibilidade
SANDBOX_DATA="$RAIZ/rainforest-data"
mkdir -p "$SANDBOX_DATA"
SANDBOX_BIN="$RAIZ/bin"
mkdir -p "$SANDBOX_BIN"
GH_INVOCATIONS="$SANDBOX_BIN/gh-invocations"

# Criar o dublê gh em Node.js
cat > "$SANDBOX_BIN/gh" << 'GHSTUB'
#!/usr/bin/env node
const fs = require('fs');
const invocFile = process.env.GH_INVOCATIONS_FILE;
if (invocFile) {
  fs.appendFileSync(invocFile, JSON.stringify(process.argv.slice(2)) + '\n', 'utf8');
}
if (process.argv[2] === 'repo' && process.argv[3] === 'view') {
  const response = process.env.GH_RESPONSE || '{"isPrivate":false}';
  if (process.env.GH_EXIT_CODE) process.exit(parseInt(process.env.GH_EXIT_CODE));
  console.log(response);
  process.exit(0);
}
process.exit(0);
GHSTUB
chmod +x "$SANDBOX_BIN/gh"


# Teste (a): gh diz isPrivate:true → sai 0
echo "== (a) repo privado → passa =="
: > "$GH_INVOCATIONS"
TEST_A="$RAIZ/vis-a"
git init -q "$TEST_A"; git -C "$TEST_A" config user.email t@t; git -C "$TEST_A" config user.name t; git -C "$TEST_A" config commit.gpgsign false
echo "x" > "$TEST_A/f.txt"; git -C "$TEST_A" add f.txt; git -C "$TEST_A" commit -qm x
git -C "$TEST_A" remote add origin "https://github.com/test/a.git"
PA=$(PAY_CWD="$(esc "$TEST_A")" pay Write "$(esc "$TEST_A/d.txt")" "contato: $JID_REAL")
SA=$(printf '%s' "$PA" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":true}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC=$?
if [ "$RC" = 0 ]; then ok=$((ok+1)); echo "  ok   (a) exit 0"
else falhou=$((falhou+1)); echo "  FALHA (a): $RC"; fi

# Teste (b): gh diz isPrivate:false → sai 2
echo "== (b) repo público → bloqueia =="
: > "$GH_INVOCATIONS"
TEST_B="$RAIZ/vis-b"
git init -q "$TEST_B"; git -C "$TEST_B" config user.email t@t; git -C "$TEST_B" config user.name t; git -C "$TEST_B" config commit.gpgsign false
echo "x" > "$TEST_B/f.txt"; git -C "$TEST_B" add f.txt; git -C "$TEST_B" commit -qm x
git -C "$TEST_B" remote add origin "https://github.com/test/b.git"
PB=$(PAY_CWD="$(esc "$TEST_B")" pay Write "$(esc "$TEST_B/d.txt")" "contato: $JID_REAL")
SB=$(printf '%s' "$PB" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC=$?
if [ "$RC" = 2 ]; then ok=$((ok+1)); echo "  ok   (b) exit 2"; if printf '%s' "$SB" | grep -q "pública"; then ok=$((ok+1)); echo "    ok   cita 'pública'"; else falhou=$((falhou+1)); echo "    FALHA sem 'pública'"; fi
else falhou=$((falhou+1)); echo "  FALHA (b): $RC"; fi

# Teste (c): sem gh → sai 2
echo "== (c) sem gh → bloqueia =="
: > "$GH_INVOCATIONS"
TEST_C="$RAIZ/vis-c"
git init -q "$TEST_C"; git -C "$TEST_C" config user.email t@t; git -C "$TEST_C" config user.name t; git -C "$TEST_C" config commit.gpgsign false
echo "x" > "$TEST_C/f.txt"; git -C "$TEST_C" add f.txt; git -C "$TEST_C" commit -qm x
git -C "$TEST_C" remote add origin "https://github.com/test/c.git"
PC=$(PAY_CWD="$(esc "$TEST_C")" pay Write "$(esc "$TEST_C/d.txt")" "contato: $JID_REAL")
SC=$(printf '%s' "$PC" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" RAINFOREST_GH="$SANDBOX_BIN/gh-inexistente" node "$GATE" 2>&1); RC=$?
if [ "$RC" = 2 ]; then ok=$((ok+1)); echo "  ok   (c) exit 2"; if printf '%s' "$SC" | grep -q "desconhecida"; then ok=$((ok+1)); echo "    ok   cita 'desconhecida'"; else falhou=$((falhou+1)); echo "    FALHA sem 'desconhecida'"; fi
else falhou=$((falhou+1)); echo "  FALHA (c): $RC"; fi

# Teste (d): gh sai 1 → sai 2
echo "== (d) gh sai 1 → bloqueia =="
: > "$GH_INVOCATIONS"
TEST_D="$RAIZ/vis-d"
git init -q "$TEST_D"; git -C "$TEST_D" config user.email t@t; git -C "$TEST_D" config user.name t; git -C "$TEST_D" config commit.gpgsign false
echo "x" > "$TEST_D/f.txt"; git -C "$TEST_D" add f.txt; git -C "$TEST_D" commit -qm x
git -C "$TEST_D" remote add origin "https://github.com/test/d.git"
PD=$(PAY_CWD="$(esc "$TEST_D")" pay Write "$(esc "$TEST_D/d.txt")" "contato: $JID_REAL")
SD=$(printf '%s' "$PD" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_EXIT_CODE="1" RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC=$?
if [ "$RC" = 2 ]; then ok=$((ok+1)); echo "  ok   (d) exit 2"
  # Sem esta segunda assercao o caso e decoracao: 14c471ed tambem sai 2,
  # porque la nao existe consulta de visibilidade nenhuma. O que separa as
  # duas arvores e a linha da mensagem.
  if printf '%s' "$SD" | grep -q "desconhecida"; then ok=$((ok+1)); echo "    ok   cita 'desconhecida'"; else falhou=$((falhou+1)); echo "    FALHA sem 'desconhecida'"; fi
else falhou=$((falhou+1)); echo "  FALHA (d): $RC"; fi

# Teste (e): gh lixo → sai 2
echo "== (e) gh lixo JSON → bloqueia =="
: > "$GH_INVOCATIONS"
TEST_E="$RAIZ/vis-e"
git init -q "$TEST_E"; git -C "$TEST_E" config user.email t@t; git -C "$TEST_E" config user.name t; git -C "$TEST_E" config commit.gpgsign false
echo "x" > "$TEST_E/f.txt"; git -C "$TEST_E" add f.txt; git -C "$TEST_E" commit -qm x
git -C "$TEST_E" remote add origin "https://github.com/test/e.git"
PE=$(PAY_CWD="$(esc "$TEST_E")" pay Write "$(esc "$TEST_E/d.txt")" "contato: $JID_REAL")
SE=$(printf '%s' "$PE" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE="lixo" RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC=$?
if [ "$RC" = 2 ]; then ok=$((ok+1)); echo "  ok   (e) exit 2"
  # Sem esta segunda assercao o caso e decoracao: 14c471ed tambem sai 2,
  # porque la nao existe consulta de visibilidade nenhuma. O que separa as
  # duas arvores e a linha da mensagem.
  if printf '%s' "$SE" | grep -q "desconhecida"; then ok=$((ok+1)); echo "    ok   cita 'desconhecida'"; else falhou=$((falhou+1)); echo "    FALHA sem 'desconhecida'"; fi
else falhou=$((falhou+1)); echo "  FALHA (e): $RC"; fi

# Teste (f): cache - 2x mesmo repo PUBLICO = 1 invocação.
# Media `publica` de proposito: a partir da revisao do zerar-issues-4, `privada`
# NAO e cacheada (ver (h) a (k) abaixo), entao so a resposta que mantem o
# bloqueio economiza chamada.
echo "== (f) cache de repo publico: 2 invocações = 1 chamada gh =="
: > "$GH_INVOCATIONS"
TEST_F="$RAIZ/vis-f"
git init -q "$TEST_F"; git -C "$TEST_F" config user.email t@t; git -C "$TEST_F" config user.name t; git -C "$TEST_F" config commit.gpgsign false
echo "x" > "$TEST_F/f.txt"; git -C "$TEST_F" add f.txt; git -C "$TEST_F" commit -qm x
git -C "$TEST_F" remote add origin "https://github.com/test/f.git"
PF=$(PAY_CWD="$(esc "$TEST_F")" pay Write "$(esc "$TEST_F/d.txt")" "contato: $JID_REAL")
printf '%s' "$PF" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1 > /dev/null
printf '%s' "$PF" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1 > /dev/null
CNT=$(wc -l < "$GH_INVOCATIONS" 2>/dev/null || echo 0)
if [ "$CNT" = "1" ]; then ok=$((ok+1)); echo "  ok   (f) cache: $CNT invocação"
else falhou=$((falhou+1)); echo "  FALHA (f): $CNT invocações (esperava 1)"; fi

# Testes (h) a (k): o cache de visibilidade nao pode DESLIGAR a trava.
#
# O arquivo `<raiz de dados>/cache-visibilidade-repo.json` fica fora de repo
# git e nenhum gate confere escrita nele. Enquanto `privada` era aceita do
# disco, plantar uma entrada liberava o gate -- e com `em` no futuro,
# liberava para sempre, porque `Date.now() - em < TTL` e verdade para
# qualquer instante futuro. Medido em 2026-09-15 contra o gate que o commit
# 5e43b525 introduziu: sem cache exit 2, plantado privada exit 0.
echo "== (h)-(k) cache plantado nao libera a trava =="
CACHE_VIS="$SANDBOX_DATA/cache-visibilidade-repo.json"
TEST_H="$RAIZ/vis-h"
git init -q "$TEST_H"; git -C "$TEST_H" config user.email t@t; git -C "$TEST_H" config user.name t; git -C "$TEST_H" config commit.gpgsign false
echo "x" > "$TEST_H/f.txt"; git -C "$TEST_H" add f.txt; git -C "$TEST_H" commit -qm x
git -C "$TEST_H" remote add origin "https://github.com/test/h.git"
PH=$(PAY_CWD="$(esc "$TEST_H")" pay Write "$(esc "$TEST_H/d.txt")" "contato: $JID_REAL")

# Roda o gate com o cache ja plantado. $1 = ms a somar em `em`.
planta_e_roda() {
  node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'test/h': {visibilidade: process.argv[2], em: Date.now() + Number(process.argv[3])}}))" "$CACHE_VIS" "$1" "$2"
  : > "$GH_INVOCATIONS"
  printf '%s' "$PH" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1
  echo $?
}

RC_H=$(planta_e_roda privada 0)
if [ "$RC_H" = 2 ]; then ok=$((ok+1)); echo "  ok   (h) privada plantada nao libera repo publico (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA (h): exit=$RC_H (esperava 2)"; fi

RC_I=$(planta_e_roda privada 3153600000000)
if [ "$RC_I" = 2 ]; then ok=$((ok+1)); echo "  ok   (i) privada com em no FUTURO nao libera (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA (i): exit=$RC_I (esperava 2)"; fi

# E `publica` com `em` no futuro tambem nao vale: entrada adiantada nunca
# expira, entao o clamp vale para as duas direcoes.
RC_J=$(planta_e_roda publica 3153600000000)
CNT_J=$(wc -l < "$GH_INVOCATIONS" 2>/dev/null || echo 0)
if [ "$RC_J" = 2 ] && [ "$CNT_J" = "1" ]; then ok=$((ok+1)); echo "  ok   (j) publica com em no FUTURO e ignorada, gh e re-perguntado"
else falhou=$((falhou+1)); echo "  FALHA (j): exit=$RC_J cnt=$CNT_J (esperava 2,1)"; fi

# (k) repo PRIVADO de verdade continua liberando, e a resposta NAO fica no
# disco: duas escritas seguidas perguntam ao `gh` duas vezes.
rm -f "$CACHE_VIS"
: > "$GH_INVOCATIONS"
printf '%s' "$PH" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":true}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1; RC_K=$?
printf '%s' "$PH" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":true}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1
CNT_K=$(wc -l < "$GH_INVOCATIONS" 2>/dev/null || echo 0)
GRAVOU=$(grep -c privada "$CACHE_VIS" 2>/dev/null || echo 0)
if [ "$RC_K" = 0 ] && [ "$CNT_K" = "2" ] && [ "$GRAVOU" = "0" ]; then ok=$((ok+1)); echo "  ok   (k) privada libera, re-pergunta ao gh e nao vai para o disco"
else falhou=$((falhou+1)); echo "  FALHA (k): exit=$RC_K cnt=$CNT_K gravou=$GRAVOU (esperava 0,2,0)"; fi
rm -f "$CACHE_VIS"

# Teste (n): `em` como STRING tambem nao vale. A coercao de `"123" <= agora`
# fazia a entrada plantada passar pela guarda de validade.
echo "== (n) em como string e ignorado =="
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'test/h': {visibilidade: 'publica', em: String(Date.now())}}))" "$CACHE_VIS"
: > "$GH_INVOCATIONS"
printf '%s' "$PH" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1; RC_N=$?
CNT_N=$(wc -l < "$GH_INVOCATIONS" 2>/dev/null || echo 0)
if [ "$RC_N" = 2 ] && [ "$CNT_N" = "1" ]; then ok=$((ok+1)); echo "  ok   (n) em como string e ignorado, gh e re-perguntado"
else falhou=$((falhou+1)); echo "  FALHA (n): exit=$RC_N cnt=$CNT_N (esperava 2,1)"; fi
rm -f "$CACHE_VIS"

# Testes (l) e (m): a visibilidade olha TODOS os remotos do GitHub.
#
# A primeira versao perguntava ao `@{upstream}` e caia em `origin` quando nao
# havia. Branch nova sem upstream e o caso comum: com `origin` privado e um
# fork publico cadastrado, o gate consultava `origin`, liberava, o segredo
# entrava no commit, e `git push fork main` publicava. Medido em 2026-09-15
# contra a arvore de 5e43b525, que introduziu a checagem: exit 0 la, exit 2
# aqui, e o `gh` consultado passa de `org/priv` para `me/pub`.
#
# Falha fechada: um remoto publico basta para bloquear. `remotoDeDestino`
# continua intacta, porque `paiJaPublicado` depende dela querer dizer outra
# coisa (D19 -- so o remoto de destino conta para 'ja publicado').
echo "== (l)-(m) visibilidade olha todos os remotos =="
TEST_L="$RAIZ/vis-l"
git init -q "$TEST_L"; git -C "$TEST_L" config user.email t@t; git -C "$TEST_L" config user.name t; git -C "$TEST_L" config commit.gpgsign false
echo "x" > "$TEST_L/f.txt"; git -C "$TEST_L" add f.txt; git -C "$TEST_L" commit -q -m x
git -C "$TEST_L" remote add origin "https://github.com/test/priv.git"
git -C "$TEST_L" remote add fork "https://github.com/test/pub.git"
PL=$(PAY_CWD="$(esc "$TEST_L")" pay Write "$(esc "$TEST_L/d.txt")" "contato: $JID_REAL")

# O duble responde pelo NOME do repositorio: `priv` privado, o resto publico.
cat > "$SANDBOX_BIN/gh-por-nome" << "GHNOME"
#!/usr/bin/env node
const fs = require('fs');
const invocFile = process.env.GH_INVOCATIONS_FILE;
const alvo = process.argv[4] || '';
if (invocFile) fs.appendFileSync(invocFile, alvo + '\n', 'utf8');
console.log(JSON.stringify({ isPrivate: /\/priv$/.test(alvo) }));
GHNOME
chmod +x "$SANDBOX_BIN/gh-por-nome"

rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"
: > "$GH_INVOCATIONS"
printf '%s' "$PL" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" RAINFOREST_GH="node $SANDBOX_BIN/gh-por-nome" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1; RC_L=$?
if [ "$RC_L" = 2 ]; then ok=$((ok+1)); echo "  ok   (l) fork publico bloqueia mesmo com origin privado (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA (l): exit=$RC_L (esperava 2); consultou: $(tr '\n' ' ' < "$GH_INVOCATIONS")"; fi

# (m) sem o fork, o mesmo repo privado continua liberando -- a mudanca nao
# pode transformar todo repo privado em bloqueio.
git -C "$TEST_L" remote remove fork
rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"
: > "$GH_INVOCATIONS"
printf '%s' "$PL" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" RAINFOREST_GH="node $SANDBOX_BIN/gh-por-nome" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" > /dev/null 2>&1; RC_M=$?
if [ "$RC_M" = 0 ]; then ok=$((ok+1)); echo "  ok   (m) so origin privado continua liberando (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA (m): exit=$RC_M (esperava 0)"; fi
rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"

# Teste (o): o preambulo da Issue #165 so sai quando ha bloqueio de verdade.
#
# Ele era escrito no stderr ANTES de `bloqueia`, e em repositorio privado o
# gate segue para exit 0: o usuario lia "este conteudo entraria no COMMIT" e
# nada tinha sido barrado. Medido contra 5e43b525, o commit que introduziu a
# saida por visibilidade: preambulo presente nos DOIS casos la, so no publico
# aqui.
echo "== (o) preambulo do commit so sai bloqueando =="
TEST_O="$RAIZ/vis-o"
git init -q -b main "$TEST_O"; git -C "$TEST_O" config user.email t@t; git -C "$TEST_O" config user.name t; git -C "$TEST_O" config commit.gpgsign false
echo "x" > "$TEST_O/f.txt"; git -C "$TEST_O" add f.txt; git -C "$TEST_O" commit -q -m x
git -C "$TEST_O" remote add origin "https://github.com/test/o.git"
# Arquivo com JID no indice: e o que o gate le no caminho do commit.
printf 'contato: %s\n' "$JID_REAL" > "$TEST_O/novo.txt"
git -C "$TEST_O" add novo.txt
PO=$(payBash "git commit -q -m x" "$(esc "$TEST_O")")

rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"
SO_PRIV=$(printf '%s' "$PO" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":true}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC_OP=$?
rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"
SO_PUB=$(printf '%s' "$PO" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC_OU=$?
rm -f "$SANDBOX_DATA/cache-visibilidade-repo.json"

if [ "$RC_OP" = 0 ] && ! printf '%s' "$SO_PRIV" | grep -q "entraria no COMMIT"; then
  ok=$((ok+1)); echo "  ok   (o) repo privado: exit 0 e SEM preambulo"
else falhou=$((falhou+1)); echo "  FALHA (o) privado: exit=$RC_OP; saida: $SO_PRIV"; fi
if [ "$RC_OU" = 2 ] && printf '%s' "$SO_PUB" | grep -q "entraria no COMMIT"; then
  ok=$((ok+1)); echo "  ok   (o) repo publico: exit 2 e COM preambulo"
else falhou=$((falhou+1)); echo "  FALHA (o) publico: exit=$RC_OU; saida: $SO_PUB"; fi

# Teste (g): RAINFOREST_GATE_SEM_REDE=1 → 0 invocações
echo "== (g) RAINFOREST_GATE_SEM_REDE=1 → sem rede =="
: > "$GH_INVOCATIONS"
TEST_G="$RAIZ/vis-g"
git init -q "$TEST_G"; git -C "$TEST_G" config user.email t@t; git -C "$TEST_G" config user.name t; git -C "$TEST_G" config commit.gpgsign false
echo "x" > "$TEST_G/f.txt"; git -C "$TEST_G" add f.txt; git -C "$TEST_G" commit -qm x
git -C "$TEST_G" remote add origin "https://github.com/test/g.git"
PG=$(PAY_CWD="$(esc "$TEST_G")" pay Write "$(esc "$TEST_G/d.txt")" "contato: $JID_REAL")
SG=$(printf '%s' "$PG" | env HOME="$RAIZ" RFM_ROOT="$SANDBOX_DATA" RAINFOREST_GATE_SEM_REDE="1" RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS" node "$GATE" 2>&1); RC=$?
CNT_G=$(wc -l < "$GH_INVOCATIONS" 2>/dev/null || echo 0)
if [ "$RC" = 2 ] && [ "$CNT_G" = "0" ]; then ok=$((ok+1)); echo "  ok   (g) exit 2, $CNT_G invocações"
  # "0 invocações" sozinho nao mede nada: em 14c471ed nao havia invocacao
  # nenhuma para contar. A visibilidade citada e o que distingue.
  if printf '%s' "$SG" | grep -q "desconhecida"; then ok=$((ok+1)); echo "    ok   cita 'desconhecida'"; else falhou=$((falhou+1)); echo "    FALHA sem 'desconhecida'"; fi
else falhou=$((falhou+1)); echo "  FALHA (g): exit=$RC cnt=$CNT_G (esperava 2,0)"; fi

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
