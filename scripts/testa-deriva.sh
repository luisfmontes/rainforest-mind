#!/bin/bash
# Bateria do `conferir-fluxo.cjs deriva` (design 2026-11-07-deriva-design, D1 a D5).
# Uso: bash scripts/testa-deriva.sh
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR: um relatório de deriva que diz "intacta" para a âncora
# que um commit tirou, ou que perde o commit que a tirou. Cada caso lê a SAÍDA do subcomando numa
# fixture git montada aqui; nenhum lê o texto do fonte.
#
# Fixture: dois planos (x com cinco decisões, y com uma) e três arquivos de código. A âncora de
# src/a.js sai num commit, src/c.js é apagado noutro, src/b.js fica. O hash esperado vem do git
# da própria fixture.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-fluxo.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }
SCRIPTW="$(cygpath -m "$SCRIPT" 2>/dev/null || printf '%s' "$SCRIPT")"

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
F="$S/fixture"
FW="$(cygpath -m "$F" 2>/dev/null || printf '%s' "$F")"

conf(){
  if [ "$2" = "$3" ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"
  else falhou=$((falhou+1)); printf '  FALHA %s: esperava [%s], veio [%s]\n' "$1" "$2" "$3"; fi
}
linha(){
  if grep -qxF -- "$3" <<<"$2"; then ok=$((ok+1)); printf '  ok    %s\n' "$1"
  else falhou=$((falhou+1)); printf '  FALHA %s: esperava a linha [%s]\n' "$1" "$3"; printf '%s\n' "$2" | sed 's/^/          /'; fi
}
nao(){
  if grep -qF -- "$3" <<<"$2"; then falhou=$((falhou+1)); printf '  FALHA %s: nao esperava [%s]\n' "$1" "$3"
  else ok=$((ok+1)); printf '  ok    %s\n' "$1"; fi
}
# w <caminho relativo à fixture> <conteúdo com \n literal>
w(){ mkdir -p "$(dirname "$F/$1")"; node -e 'require("fs").writeFileSync(process.argv[1], process.argv[2].replace(/\\n/g, "\n"))' "$FW/$1" "$2"; }
deriva(){ ( cd "$F" && RFM_ESTADO_ROOT="$FW" CLAUDE_PROJECT_DIR="$FW" node "$SCRIPTW" deriva "$@" ); }

mkdir -p "$F"
( cd "$F" && git init -q -b principal && git config user.email t@t && git config user.name Teste && git config core.autocrlf false ) || { echo "FALHA: git init"; exit 1; }

DESIGN_X='# Design: x\n\n## Objetivo\no.\n\n## Decisões fechadas\n- **D1 — a** — porquê: p.\n- **D2 — b** — porquê: p.\n- **D3 — c** — porquê: p.\n- **D4 — d** — porquê: p.\n- **D5 — e** — porquê: p.\n\n## Avaliado e descartado\n- n.\n\n## Fora de escopo\n- n.\n\n## Em aberto\n- n.\n'
DESIGN_Y='# Design: y\n\n## Objetivo\no.\n\n## Decisões fechadas\n- **D1 — a** — porquê: p.\n\n## Avaliado e descartado\n- n.\n\n## Fora de escopo\n- n.\n\n## Em aberto\n- n.\n'
tarefa(){ printf '### %s. t%s [tipo: implementar]\\natende: %s\\narquivos: `%s`\\ndepende de: nenhuma\\nmutacao:\\n  arquivo: `%s`\\n  de: %s\\n  para: `x`\\n  bateria: `true`\\n  fixture: `f`\\npronto quando: x\\n\\n' "$1" "$1" "$2" "$3" "$3" "$4"; }
PLANO_X="# Plano: x\\n\\nDesign: docs/rainforest/design/x.md\\n\\n## Tarefas\\n\\n$(tarefa 1 'D1, D2' src/a.js '`return alvo;`')$(tarefa 2 D3 src/b.js '`const fica = 1;`')$(tarefa 3 D4 src/c.js '`const some = 2;`')$(tarefa 4 D5 src/a.js 'o trecho em prosa que devolve o alvo')### 5. t5 [tipo: docs]\\natende: D5\\narquivos: \`README.md\`\\ndepende de: nenhuma\\nmutacao: n/a\\n  motivo: m\\npronto quando: x\\n"
PLANO_Y="# Plano: y\\n\\nDesign: \`docs/rainforest/design/y.md\` (com prosa depois do caminho)\\n\\n## Tarefas\\n\\n$(tarefa 1 D1 src/b.js '`const fica = 1;`')$(tarefa 2 D1 src/d.js '`const viaMerge = 3;`')"

w docs/rainforest/design/x.md "$DESIGN_X"
w docs/rainforest/design/y.md "$DESIGN_Y"
w docs/rainforest/planos/x.md "$PLANO_X"
w docs/rainforest/planos/y.md "$PLANO_Y"
w src/a.js 'function a(alvo) {\n  return alvo;\n}\n'
w src/b.js 'const fica = 1;\n'
w src/c.js 'const some = 2;\n'
w src/d.js 'const viaMerge = 3;\n'
( cd "$F" && git add -A && git commit -q -m base ) || { echo "FALHA: commit base"; exit 1; }
w src/a.js 'function a(alvo) {\n  return 0;\n}\n'
( cd "$F" && git add -A && git commit -q -m "tira a âncora" ) || { echo "FALHA: commit tira"; exit 1; }
H_TIRA="$(cd "$F" && git log -1 --format=%h)"
w src/a.js 'function a(alvo) {\n  return 1;\n}\n'
( cd "$F" && git add -A && git commit -q -m "mexe de novo sem a âncora" ) || { echo "FALHA: commit mexe"; exit 1; }
( cd "$F" && git rm -q src/c.js && git commit -q -m "apaga c" ) || { echo "FALHA: commit apaga"; exit 1; }
H_APAGA="$(cd "$F" && git log -1 --format=%h)"
# A âncora de src/d.js sai num ramo e entra na principal por merge: é o merge que a tirou dela.
( cd "$F" && git checkout -q -b ramo && w src/d.js 'const outra = 4;\n' && git add -A && git commit -q -m "tira no ramo" \
  && git checkout -q principal && git merge -q --no-ff ramo -m "junta o ramo" ) || { echo "FALHA: merge"; exit 1; }
H_MERGE="$(cd "$F" && git log -1 --format=%h)"

echo "== deriva sem filtro"
SAI="$(deriva)"; EXIT=$?
conf "sai 0" 0 "$EXIT"
linha "âncora tirada por um commit sai como sumiu, com o commit" "$SAI" "x D1, D2: src/a.js — sumiu em $H_TIRA tira a âncora"
linha "arquivo apagado sai como arquivo sumiu, com o commit" "$SAI" "x D4: src/c.js — arquivo sumiu em $H_APAGA apaga c"
nao "âncora intacta não aparece sem --arquivo" "$SAI" "src/b.js"
nao "de: em prosa não é âncora" "$SAI" "D5"
linha "commit posterior que toca o arquivo sem a âncora não é o culpado" "$SAI" "x D1, D2: src/a.js — sumiu em $H_TIRA tira a âncora"
linha "âncora tirada num ramo sai no merge que a trouxe" "$SAI" "y D1: src/d.js — sumiu em $H_MERGE junta o ramo"
linha "placar: D5 sem âncora medível; y D1 mista (intacta e perdida) conta como perdida" "$SAI" "decisões: 5 com âncora (1 intactas, 4 com âncora perdida), 1 sem âncora medível"
conf "o placar é a última linha" "decisões: 5 com âncora (1 intactas, 4 com âncora perdida), 1 sem âncora medível" "$(tail -1 <<<"$SAI")"

echo "== --slug"
SAI="$(deriva --slug y)"; EXIT=$?
conf "--slug y sai 0" 0 "$EXIT"
conf "--slug y: só y, com o design lido apesar da prosa na linha Design:" "y D1: src/d.js — sumiu em $H_MERGE junta o ramo|decisões: 1 com âncora (0 intactas, 1 com âncora perdida), 0 sem âncora medível" "$(tr '\n' '|' <<<"$SAI" | sed 's/|$//')"
deriva --slug nao-existe >/dev/null 2>&1; EXIT=$?
conf "--slug sem plano sai 1" 1 "$EXIT"

echo "== --arquivo"
SAI="$(deriva --arquivo src/b.js)"; EXIT=$?
conf "--arquivo sai 0" 0 "$EXIT"
linha "--arquivo lista a intacta de x" "$SAI" "x D3: src/b.js — intacta"
linha "--arquivo lista a intacta de y" "$SAI" "y D1: src/b.js — intacta"
nao "--arquivo deixa de fora âncora de outro arquivo" "$SAI" "src/a.js"
linha "--arquivo: placar só das decisões daquele arquivo" "$SAI" "decisões: 2 com âncora (2 intactas, 0 com âncora perdida), 0 sem âncora medível"
SAI="$(deriva --arquivo 'src\a.js')"
linha "--arquivo com contrabarra casa o caminho com barra" "$SAI" "x D1, D2: src/a.js — sumiu em $H_TIRA tira a âncora"
SAI="$(deriva --arquivo ./src/b.js)"
linha "--arquivo com ./ casa" "$SAI" "x D3: src/b.js — intacta"
SAI="$(deriva --arquivo "$FW/src/b.js")"
linha "--arquivo absoluto casa" "$SAI" "y D1: src/b.js — intacta"
ERR="$(deriva --arquivo nada.js 2>&1 >/dev/null)"
conf "--arquivo que não casa avisa no stderr" "aviso: nenhuma âncora de plano aponta para nada.js" "$ERR"

echo "== uso"
ERR="$(deriva --foo 1 2>&1 >/dev/null)"; EXIT=$?
conf "opção desconhecida sai 1" 1 "$EXIT"
conf "e é nomeada" "erro: opção desconhecida: --foo" "$ERR"
ERR="$(deriva --arquivo 2>&1 >/dev/null)"; EXIT=$?
conf "--arquivo sem valor sai 1" 1 "$EXIT"
conf "e diz o que falta" "erro: falta valor para --arquivo" "$ERR"

echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
exit 0
