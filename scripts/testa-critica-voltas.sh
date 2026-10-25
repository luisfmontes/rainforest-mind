#!/usr/bin/env bash
# Bateria das voltas de revisão (design
# docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-5.md, D4): o
# `exigir --estagio revisar` guarda a janela que fecha em `revisar.voltas`, e a
# crítica do revisor acrescenta a comparação com a volta anterior. Cada caso
# roda o script de verdade, numa caixa mktemp -d fora do worktree, com
# RFM_ESTADO_ROOT apontado para um repo git mínimo (o exigir captura snapshot).
set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
# O node não lê /tmp do Git Bash: a caixa vai para o node na forma Windows.
CAIXA_W="$(cd "$CAIXA" && pwd -W 2>/dev/null || pwd)"
RAIZ_W="$(pwd -W 2>/dev/null || pwd)"

# HOME e config do Claude isolados: nada do ledger ou do transcrito real.
export HOME="$CAIXA/home"
export CLAUDE_CONFIG_DIR="$CAIXA/cfg"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@teste
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@teste

REPO="$CAIXA/repo"
mkdir -p "$REPO"
(
  cd "$REPO" || exit 1
  git init -q
  echo inicial > inicial.txt
  git add . && git commit -qm inicial
) >/dev/null 2>&1
REPO_W="$(cd "$REPO" && pwd -W 2>/dev/null || pwd)"

# Texto de duas mensagens do revisor. A linha VEREDITO sai na comparação.
cat > "$CAIXA/ant.txt" <<'EOF'
**[media]** scripts/a.cjs:12 — defeito da volta anterior
**[media]** scripts/b.cjs:3 — defeito que some na volta atual
VEREDITO: reprovado
EOF
cat > "$CAIXA/atual.txt" <<'EOF'
**[media]** scripts/a.cjs:40 — defeito A, ainda aqui
**[alta]** scripts/c.cjs:1 — defeito novo
**[baixa]** item sem caminho citado
VEREDITO: reprovado
EOF
# O que a crítica atual deve imprimir: a mensagem sem a linha VEREDITO, mais a
# linha em branco que o script de hoje já acrescenta (a crítica termina em \n e
# o write soma outro). A saída sem volta tem de ser exatamente esta.
{ grep -v '^VEREDITO:' "$CAIXA/atual.txt"; echo; } > "$CAIXA/esperado-sem-volta.txt"

# texto.txt -> jsonl com uma mensagem do assistente (como o transcrito real)
jsonl() { # <txt> <jsonl>
  node -e 'const fs=require("fs");fs.writeFileSync(process.argv[2],JSON.stringify({type:"assistant",isSidechain:true,message:{role:"assistant",content:[{type:"text",text:fs.readFileSync(process.argv[1],"utf8")}]}})+"\n");' "$CAIXA_W/$1" "$CAIXA_W/$2"
}
jsonl ant.txt ant.jsonl
jsonl atual.txt atual.jsonl

# estado <slug> <json do bloco revisar>: design, plano e executar fechados.
estado() {
  mkdir -p "$REPO/docs/rainforest/estado"
  printf '{"design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":%s}\n' "$2" > "$REPO/docs/rainforest/estado/$1.json"
}

# pousa <slug> <json do array>: troca a janela atual (revisar.vereditos), mantém as voltas
pousa() {
  node -e 'const f=process.argv[1];const e=JSON.parse(require("fs").readFileSync(f,"utf8"));e.revisar.vereditos=JSON.parse(process.argv[2]);require("fs").writeFileSync(f,JSON.stringify(e,null,2)+"\n");' "$REPO_W/docs/rainforest/estado/$1.json" "$2"
}

# campo <slug> <expressão sobre r = estado.revisar>
# eval aqui é deliberado e seguro: a expressão é sempre um literal escrito nesta
# bateria (nunca dado de fora), e o alvo é um JSON de teste na caixa mktemp.
campo() {
  node -e 'const e=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const r=e.revisar;process.stdout.write(String(eval(process.argv[2])));' "$REPO_W/docs/rainforest/estado/$1.json" "$2"
}

# vered <veredito> <transcrito> <agente_id> -> um item de revisar.vereditos
vered() {
  printf '{"agente":"revisor","agente_id":"%s","veredito":"%s","em":"2026-10-25","transcrito":"%s"}' "$3" "$1" "$2"
}

# exige <slug> -> EXIT_E: exigir --estagio revisar com RFM_ESTADO_ROOT na caixa
exige() {
  RFM_ESTADO_ROOT="$REPO_W" node scripts/estado.cjs exigir --slug "$1" --estagio revisar >"$CAIXA/exige.out" 2>"$CAIXA/exige.err"
  EXIT_E=$?
}

# roda <slug> -> EXIT e o stdout em $CAIXA/out (bytes exatos)
roda() {
  RFM_ESTADO_ROOT="$REPO_W" node scripts/critica-do-revisor.cjs --slug "$1" >"$CAIXA/out" 2>"$CAIXA/err"
  EXIT=$?
}

# roda_cmp <slug> -> o bloco de comparação sozinho (D10a do lote 6): EXIT e stdout
roda_cmp() {
  RFM_ESTADO_ROOT="$REPO_W" node scripts/critica-do-revisor.cjs --slug "$1" --comparacao >"$CAIXA/out" 2>"$CAIXA/err"
  EXIT=$?
}

registra() { # $1 = caso, $2 = 0 se passou, 1 se falhou
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (exit=${EXIT:-?})"
    echo "    stdout: $(cat "$CAIXA/out" 2>/dev/null)"; echo "    stderr: $(cat "$CAIXA/err" 2>/dev/null)"
  fi
}

echo "== critica-do-revisor: voltas de revisão (D4 do lote 5) =="

echo "-- (1) exigir revisar guarda a janela como volta 1 e zera vereditos --"
estado v1 "{\"status\":\"pendente\",\"vereditos\":[$(vered reprovado "$CAIXA_W/ant.jsonl" ant-1)]}"
exige v1
r=1
if [ "$EXIT_E" -eq 0 ] && [ "$(campo v1 'r.voltas.length+" "+r.voltas[0].volta+" "+r.voltas[0].vereditos[0].agente_id+" "+r.vereditos.length+" "+Object.keys(r.voltas[0]).join(",")')" = "1 1 ant-1 0 volta,vereditos" ]; then r=0; fi
EXIT=$EXIT_E
registra "(1) exigir revisar grava volta 1 com os vereditos e zera a janela" $r

echo "-- (2) segundo exigir acrescenta volta 2 sem perder a 1 --"
pousa v1 "[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]"
exige v1
r=1
if [ "$EXIT_E" -eq 0 ] && [ "$(campo v1 'r.voltas.map(v=>v.volta).join(",")+" "+r.voltas[0].vereditos[0].agente_id+" "+r.voltas[1].vereditos[0].agente_id+" "+r.vereditos.length')" = "1,2 ant-1 atual-1 0" ]; then r=0; fi
EXIT=$EXIT_E
registra "(2) volta 2 acrescentada, volta 1 preservada" $r

echo "-- (3) janela vazia não cria volta --"
exige v1
r=1
if [ "$EXIT_E" -eq 0 ] && [ "$(campo v1 'r.voltas.length')" = "2" ]; then r=0; fi
EXIT=$EXIT_E
registra "(3) exigir com janela vazia mantém as 2 voltas" $r
estado v0 '{"status":"pendente","vereditos":[]}'
exige v0
r=1
if [ "$EXIT_E" -eq 0 ] && [ "$(campo v0 'String(r.voltas)')" = "undefined" ]; then r=0; fi
EXIT=$EXIT_E
registra "(3b) janela vazia sem voltas não cria o campo" $r

echo "-- (4) achado no mesmo arquivo da volta anterior sai persiste --"
estado c1 "{\"status\":\"reprovado\",\"voltas\":[{\"volta\":1,\"vereditos\":[$(vered reprovado "$CAIXA_W/ant.jsonl" ant-1)]}],\"vereditos\":[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]}"
roda_cmp c1
r=1
if [ "$EXIT" -eq 0 ] && grep -qxF -- '- [media] scripts/a.cjs — persiste (mesmo arquivo)' "$CAIXA/out"; then r=0; fi
registra "achado no mesmo arquivo da volta anterior sai persiste" $r

echo "-- (5) marcas novo, persiste e sumiu, e a contagem fora da comparação --"
r=1
roda_cmp c1
if [ "$EXIT" -eq 0 ] \
  && grep -qxF -- '## Comparação com a volta anterior' "$CAIXA/out" \
  && grep -qxF -- '- [alta] scripts/c.cjs — novo' "$CAIXA/out" \
  && grep -qxF -- '- [media] scripts/b.cjs — sumiu — confirmar se foi corrigido' "$CAIXA/out" \
  && grep -qxF -- 'achados sem caminho:linha, fora da comparação: 1 na crítica atual, 0 na volta anterior' "$CAIXA/out"; then r=0; fi
registra "(5) novo, sumiu (só arquivo que sumiu) e contagem fora da comparação" $r

echo "-- (6) volta sem reprovado com transcrito é pulada --"
estado c4 "{\"status\":\"reprovado\",\"voltas\":[{\"volta\":1,\"vereditos\":[$(vered reprovado "$CAIXA_W/ant.jsonl" ant-1)]},{\"volta\":2,\"vereditos\":[{\"agente_id\":\"x\",\"veredito\":\"ok\",\"transcrito\":\"$CAIXA_W/ant.jsonl\"}]}],\"vereditos\":[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]}"
roda_cmp c4
r=1
if [ "$EXIT" -eq 0 ] && grep -qxF -- '- [media] scripts/a.cjs — persiste (mesmo arquivo)' "$CAIXA/out"; then r=0; fi
registra "(6) a comparação usa a última volta com reprovado e transcrito" $r

echo "-- (7) transcrito anterior ausente: sem --comparacao a crítica sai intacta; com ele, o bloco diz isso --"
estado c2 "{\"status\":\"reprovado\",\"voltas\":[{\"volta\":1,\"vereditos\":[$(vered reprovado "$CAIXA_W/nao-existe.jsonl" ant-1)]}],\"vereditos\":[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]}"
roda c2
r=1
if [ "$EXIT" -eq 0 ] && cmp -s "$CAIXA/out" "$CAIXA/esperado-sem-volta.txt"; then
  roda_cmp c2
  if [ "$EXIT" -eq 0 ] \
    && grep -qxF -- 'transcrito da volta anterior ausente' "$CAIXA/out" \
    && [ "$(wc -l < "$CAIXA/out" | tr -d ' ')" -eq 2 ]; then r=0; fi
fi
registra "(7) transcrito anterior ausente: crítica intacta, e o bloco só com --comparacao diz o aviso" $r

echo "-- (8) sem volta anterior: saída byte a byte igual à de hoje --"
estado c3 "{\"status\":\"reprovado\",\"vereditos\":[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]}"
roda c3
r=1
if [ "$EXIT" -eq 0 ] && cmp -s "$CAIXA/out" "$CAIXA/esperado-sem-volta.txt"; then r=0; fi
registra "(8) exit 0 e stdout identico ao da crítica sem bloco" $r

echo "-- (9) [design] com volta anterior continua exit 3, sem bloco --"
estado c5 "{\"status\":\"reprovado\",\"voltas\":[{\"volta\":1,\"vereditos\":[$(vered reprovado "$CAIXA_W/ant.jsonl" ant-1)]}],\"vereditos\":[$(vered reprovado "$RAIZ_W/scripts/fixtures/critica-do-revisor/achado-design.jsonl" design-1)]}"
roda c5
r=1
if [ "$EXIT" -eq 3 ] && ! grep -q 'Comparação com a volta anterior' "$CAIXA/out"; then r=0; fi
registra "(9) exit 3 sem o bloco de comparação" $r

echo "-- (10) listarAchados: sev, arquivo e a régua de contarAchados --"
LA_ESPERADO='[{"sev":"media","arquivo":"scripts/a.cjs","preexistente":false},{"sev":"design","arquivo":null,"preexistente":false},{"sev":"alta","arquivo":"hooks/x.cjs","preexistente":false},{"sev":"media","arquivo":"scripts/a.cjs","preexistente":false}]'
LA_OBTIDO="$(node -e '
const { listarAchados } = require(process.argv[1]);
const texto = [
  "**[media]** scripts/a.cjs:12 — defeito",
  "- [design] sem caminho",
  "Citado no meio **[alta]** não abre",
  "**A1.** [alta] hooks/x.cjs:9 — ok",
  "**[media]** [design] scripts/a.cjs:1 — x",
].join("\n");
process.stdout.write(JSON.stringify(listarAchados(texto)));
' "$RAIZ_W/hooks/lib/achados-revisor.cjs" 2>"$CAIXA/err")"
r=1
if [ "$LA_OBTIDO" = "$LA_ESPERADO" ]; then r=0; fi
EXIT=0
registra "(10) listarAchados devolve sev e arquivo (esperado: $LA_ESPERADO; obtido: $LA_OBTIDO)" $r

echo "-- (11) --comparacao com veredito ok na janela: sai 0 e compara com a volta anterior (D10a do lote 6) --"
estado c6 "{\"status\":\"ok\",\"voltas\":[{\"volta\":1,\"vereditos\":[$(vered reprovado "$CAIXA_W/ant.jsonl" ant-1)]}],\"vereditos\":[$(vered ok "$CAIXA_W/atual.jsonl" ok-1)]}"
roda_cmp c6
r=1
if [ "$EXIT" -eq 0 ] \
  && grep -qxF -- '## Comparação com a volta anterior' "$CAIXA/out" \
  && grep -qxF -- '- [media] scripts/b.cjs — sumiu — confirmar se foi corrigido' "$CAIXA/out" \
  && ! grep -q 'VEREDITO' "$CAIXA/out"; then r=0; fi
registra "(11) --comparacao com veredito ok: exit 0 e o bloco com o que sumiu" $r

echo "-- (12) --comparacao sem volta anterior: imprime a frase e sai 0 --"
estado c7 "{\"status\":\"reprovado\",\"vereditos\":[$(vered reprovado "$CAIXA_W/atual.jsonl" atual-1)]}"
roda_cmp c7
r=1
if [ "$EXIT" -eq 0 ] && [ "$(cat "$CAIXA/out")" = "(sem volta anterior)" ]; then r=0; fi
registra "(12) --comparacao sem volta anterior imprime (sem volta anterior)" $r

echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
