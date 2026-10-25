#!/bin/bash
# Bateria do vazio explicado do scripts/memoria.cjs `buscar` (D7, lote 2 da apoio-ao-dev).
# Uso: bash scripts/testa-memoria-vazio-explicado.sh
#
# Caixa de areia: o banco vive em RFM_ROOT=<mktemp -d>, nunca em ~/.rainforest. Casos:
#   1. filtro que exclui tudo diz quantas observações existem no escopo (--texto)
#   2. --desde que exclui tudo diz o mesmo número de observações no escopo
#   3. banco iniciado sem observações diz "banco sem observações" (--texto x)
#   4. --json sai [] nos três casos de vazio
#   5. busca com resultado sai como antes: linha "[id] projeto - data", sem texto de vazio
#   6. --projeto conta só o projeto: proj-a (2 obs) com --texto que não casa diz 2, não 5
#   7. --projeto sem observação viva, com vivas em outro projeto, não diz "banco sem observações"
#   8. --limite 0 com duas observações que casam diz o limite, não os filtros; --json segue []

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

MEMORIA="node $SRC/scripts/memoria.cjs"

total=0
vermelhas=()
verde() { total=$((total+1)); echo "  ok   $1"; }
vermelha() { total=$((total+1)); vermelhas+=("$1"); echo "  FALHA $1: $2"; }

# Semeia observações num banco de RFM_ROOT: semear <raiz> <projeto> <conteudo> <criada_em>...
semear() {
  local raiz="$1" projeto="$2"; shift 2
  while [ "$#" -gt 0 ]; do
    SRC_MEM="$SRC/scripts/memoria.cjs" RAIZ="$raiz" PROJ="$projeto" CONTEUDO="$1" QUANDO="$2" node -e "
      const { abrirBanco } = require(process.env.SRC_MEM);
      const db = abrirBanco(require('path').join(process.env.RAIZ, 'rainforest.db'));
      db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
        .run(process.env.PROJ, process.env.CONTEUDO, process.env.QUANDO, 'teste-vazio-' + process.env.QUANDO);
      db.close();
    "
    shift 2
  done
}

echo "== caixa 1: duas observacoes de proj-vazio (2026-10-01 e 2026-10-10) =="
CAIXA="$(novo_sandbox)"
RFM_ROOT="$CAIXA" $MEMORIA iniciar >/dev/null 2>&1
semear "$CAIXA" proj-vazio "vazio DUASALFA observacao" "2026-10-01T12:00:00.000Z" "vazio DUASBETA observacao" "2026-10-10T12:00:00.000Z"

echo "== filtro que exclui tudo diz quantas observações existem no escopo =="
out=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto termoinexistente 2>/dev/null); c=$?
esperado='(nenhum resultado — 2 observação(ões) no escopo; os filtros excluíram todas)'
if [ "$c" = "0" ] && [ "$out" = "$esperado" ]; then verde "--texto sem casamento: exit 0 e a linha com 2 no escopo"
else vermelha "filtro que exclui tudo diz quantas observações existem no escopo" "esperava exit 0 e [$esperado], veio exit $c [$out]"; fi

echo "== --desde que exclui tudo diz o mesmo número =="
out=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --desde 2030-01-01 2>/dev/null); c=$?
if [ "$c" = "0" ] && [ "$out" = "$esperado" ]; then verde "--desde 2030-01-01: exit 0 e a mesma linha com 2"
else vermelha "--desde que exclui tudo diz o mesmo número" "esperava exit 0 e [$esperado], veio exit $c [$out]"; fi

echo "== --json continua [] no vazio com filtro =="
out=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto termoinexistente --json 2>/dev/null); c=$?
out2=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --desde 2030-01-01 --json 2>/dev/null); c2=$?
if [ "$c" = "0" ] && [ "$c2" = "0" ] && [ "$out" = "[]" ] && [ "$out2" = "[]" ]; then verde "--json com --texto e com --desde sai [] com exit 0"
else vermelha "--json continua []" "texto exit $c [$out], desde exit $c2 [$out2]"; fi

echo "== caixa 1: busca com resultado sai como antes =="
out=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto DUASALFA 2>/dev/null); c=$?
linha=$(printf '%s\n' "$out" | grep -c '^\[[0-9][0-9]*\] proj-vazio - ')
if [ "$c" = "0" ] && [ "$linha" = "1" ] && ! printf '%s' "$out" | grep -q 'nenhum resultado'; then
  verde "--texto DUASALFA devolve 1 linha '[id] proj-vazio - data' e nenhum texto de vazio"
else vermelha "busca com resultado sai como antes" "exit $c, linhas de resultado $linha, saída [$out]"; fi

echo "== banco iniciado sem observações: banco sem observações =="
VAZIA="$(novo_sandbox)"
RFM_ROOT="$VAZIA" $MEMORIA iniciar >/dev/null 2>&1
out=$(RFM_ROOT="$VAZIA" $MEMORIA buscar --texto x 2>/dev/null); c=$?
if [ "$c" = "0" ] && [ "$out" = "(nenhum resultado — banco sem observações)" ]; then
  verde "banco vazio, --texto x: exit 0 e 'banco sem observações'"
else vermelha "banco iniciado sem observações diz banco sem observações" "esperava exit 0 e [(nenhum resultado — banco sem observações)], veio exit $c [$out]"; fi

echo "== banco vazio com --json: []  =="
out=$(RFM_ROOT="$VAZIA" $MEMORIA buscar --texto x --json 2>/dev/null); c=$?
if [ "$c" = "0" ] && [ "$out" = "[]" ]; then verde "banco vazio, --json: exit 0 e []"
else vermelha "banco vazio com --json sai []" "exit $c [$out]"; fi

echo "== caixa 2: proj-a com 2 observacoes e proj-b com 3 =="
CAIXA2="$(novo_sandbox)"
RFM_ROOT="$CAIXA2" $MEMORIA iniciar >/dev/null 2>&1
semear "$CAIXA2" proj-a "escopo A1 observacao" "2026-10-01T12:00:00.000Z" "escopo A2 observacao" "2026-10-02T12:00:00.000Z"
semear "$CAIXA2" proj-b "escopo B1 observacao" "2026-10-03T12:00:00.000Z" "escopo B2 observacao" "2026-10-04T12:00:00.000Z" "escopo B3 observacao" "2026-10-05T12:00:00.000Z"

echo "== --projeto conta só o projeto: proj-a com --texto que não casa diz 2 =="
out=$(RFM_ROOT="$CAIXA2" $MEMORIA buscar --projeto proj-a --texto termoinexistente 2>/dev/null); c=$?
if [ "$c" = "0" ] && [ "$out" = "(nenhum resultado — 2 observação(ões) no escopo; os filtros excluíram todas)" ]; then
  verde "--projeto proj-a --texto que não casa: 2 no escopo, não 5"
else vermelha "--projeto conta só o projeto" "esperava 2 no escopo, veio exit $c [$out]"; fi

echo "== caixa 3: proj-q so com observacao substituida; proj-r com uma viva =="
CAIXA3="$(novo_sandbox)"
RFM_ROOT="$CAIXA3" $MEMORIA iniciar >/dev/null 2>&1
SRC_MEM="$SRC/scripts/memoria.cjs" RAIZ="$CAIXA3" node -e "
  const { abrirBanco } = require(process.env.SRC_MEM);
  const db = abrirBanco(require('path').join(process.env.RAIZ, 'rainforest.db'));
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  const antiga = ins.run('proj-q', 'q SUBSTITUIDA observacao', '2026-10-01T12:00:00.000Z', 'teste-vazio-q').lastInsertRowid;
  const nova = ins.run('proj-r', 'r VIVA observacao', '2026-10-02T12:00:00.000Z', 'teste-vazio-r').lastInsertRowid;
  db.prepare('UPDATE observacoes SET substituida_por = ? WHERE id = ?').run(nova, antiga);
  db.close();
"

echo "== --projeto sem observacao viva, com vivas em outro projeto: nenhuma observacao viva no escopo =="
out=$(RFM_ROOT="$CAIXA3" $MEMORIA buscar --projeto proj-q --texto termoinexistente 2>/dev/null); c=$?
if [ "$c" = "0" ] && [ "$out" = "(nenhum resultado — nenhuma observação viva no escopo)" ]; then
  verde "--projeto proj-q (só substituída, proj-r tem viva): frase nova, não 'banco sem observações'"
else vermelha "--projeto sem viva com vivas em outro projeto diz nenhuma observação viva no escopo" "esperava exit 0 e a frase nova, veio exit $c [$out]"; fi

echo "== caixa 4: duas observacoes casam com alfa; --limite 0 diz o limite, não os filtros =="
CAIXA4="$(novo_sandbox)"
RFM_ROOT="$CAIXA4" $MEMORIA iniciar >/dev/null 2>&1
semear "$CAIXA4" proj-lim "alfa um observacao" "2026-10-01T12:00:00.000Z" "alfa dois observacao" "2026-10-02T12:00:00.000Z"

out=$(RFM_ROOT="$CAIXA4" $MEMORIA buscar --texto alfa --limite 0 2>/dev/null); c=$?
out2=$(RFM_ROOT="$CAIXA4" $MEMORIA buscar --texto alfa --limite 0 --json 2>/dev/null); c2=$?
if [ "$c" = "0" ] && [ "$out" = "(nenhum resultado — --limite 0)" ] && [ "$c2" = "0" ] && [ "$out2" = "[]" ]; then
  verde "--texto alfa --limite 0 (2 casam): frase do limite, e --json segue []"
else vermelha "--limite 0 diz o limite, não os filtros" "esperava exit 0 e [(nenhum resultado — --limite 0)] com --json [], veio exit $c [$out], json exit $c2 [$out2]"; fi

echo
echo "total=$total vermelhas:[$(IFS=,; echo "${vermelhas[*]:-}")]"
if [ "${#vermelhas[@]}" -eq 0 ]; then exit 0; else exit 1; fi
