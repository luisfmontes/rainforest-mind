#!/bin/bash
# Bateria da busca com trecho e proximidade do scripts/memoria.cjs `buscar --texto` (D3, lote 4).
# Uso: bash scripts/testa-memoria-proximidade.sh
#
# Caixa de areia: o banco vive em RFM_ROOT=<mktemp -d>, nunca na raiz real. Casos:
#   0. pré-condição: o bm25 puro põe B (mais nova, termos espalhados) na frente de A; sem isso o
#      caso de proximidade não prova nada
#   1. termos juntos vêm antes de termos espalhados com bm25 parecido (A ganha pelo rerank)
#   2. um termo só mantém a ordem do bm25 (B primeiro, como hoje)
#   3. a saída humana mostra o trecho com o termo entre [ e ], mesmo depois do 100º caractere
#   4. --json traz o campo trecho e mantém conteudo inteiro
#   5. --limite 1 devolve A: o corte vem depois do rerank
#   6. --limite 0 sai "(nenhum resultado — --limite 0)" e --json sai []
#   7. sem --texto a ordem é a de recência e não há campo trecho
#   8. --limite negativo com --texto devolve todos os casamentos (LIMIT -1 do SQLite)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC" || exit 1
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"
export RFM_ROOT="$CAIXA"
MEMORIA="node $SRC/scripts/memoria.cjs"

A_TEXTO="deploy do servidor falhou na madrugada de terca quando a equipe estava em reuniao e o alerta chegou sem ninguem ver ate a manha seguinte com o painel de monitoramento parado durante toda a noite e depois disso o time ainda levou horas para entender o que tinha acontecido com a fila de tarefas que ficou presa sem aviso algum"
B_TEXTO="deploy deploy ontem a equipe revisou o plano com calma e decidiu que o proximo passo era rever a rotina de publicacao em homologacao com o time de infraestrutura e registrar as mudancas de todas as etapas combinadas nesta semana para acompanhar o fluxo inteiro com cuidado ate o fim do ciclo sem pressa nenhuma e com calma redobrada sobre o servidor"
C_TEXTO="relatorio do dia com bastante texto de contexto para empurrar o termo bem para depois da posicao cem do conteudo da observacao com mais palavras ate chegar zztermofundo no fim"

# Identifica qual observação do setup é cada linha: A (termos juntos), B (espalhados), C (termo longe).
IDENTIFICA_JS="const id = c => c.startsWith('deploy do servidor') ? 'A' : c.startsWith('deploy deploy') ? 'B' : c.startsWith('relatorio do dia') ? 'C' : '?';"

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

echo "== setup: banco temporario com A (termos juntos), B (mais nova, espalhados) e C (termo depois do 100o caractere) =="
esperado "iniciar" 0 $MEMORIA iniciar
A_TEXTO="$A_TEXTO" B_TEXTO="$B_TEXTO" C_TEXTO="$C_TEXTO" RFM_ROOT="$CAIXA" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  ins.run('p-prox', process.env.A_TEXTO, '2026-10-01T10:00:00Z', 'prox-a');
  ins.run('p-prox', process.env.B_TEXTO, '2026-10-02T10:00:00Z', 'prox-b');
  ins.run('p-prox', process.env.C_TEXTO, '2026-10-03T10:00:00Z', 'prox-c');
  for (let i = 0; i < 20; i++) ins.run('p-prox', 'bananas maduras amarelas frescas no mercado de domingo cedo pela manha ' + i, '2026-09-' + String(1 + i).padStart(2, '0') + 'T10:00:00Z', 'prox-f' + i);
  db.close();
" 2>/dev/null

echo
echo "== 0. pre-condicao: bm25 puro poe B na frente de A =="
ordem_bm25=$(RFM_ROOT="$CAIXA" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  const linhas = db.prepare(\"SELECT o.origem, bm25(observacoes_fts) AS score FROM observacoes_fts JOIN observacoes o ON o.id = observacoes_fts.rowid WHERE observacoes_fts MATCH ? AND o.origem IN ('prox-a','prox-b') ORDER BY bm25(observacoes_fts), o.criada_em DESC\").all('deploy servidor');
  console.log(linhas.map(l => l.origem + '=' + l.score.toFixed(4)).join(' '));
  db.close();
" 2>/dev/null)
echo "  comando: bm25 puro sobre 'deploy servidor' -> $ordem_bm25"
if echo "$ordem_bm25" | grep -q "^prox-b="; then
  ok=$((ok+1)); echo "  ok   pre-condicao: bm25 puro devolve B primeiro"
else
  falhou=$((falhou+1)); echo "  FALHA pre-condicao: bm25 puro nao devolve B primeiro: $ordem_bm25"
fi

echo
echo "== 1. termos juntos vêm antes de termos espalhados com bm25 parecido =="
primeiro=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy servidor" --json 2>/dev/null | node -e "$IDENTIFICA_JS"'const a=JSON.parse(require("fs").readFileSync(0,"utf8")||"[]");process.stdout.write(a[0] ? id(a[0].conteudo) : "vazio")')
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto \"deploy servidor\" --json -> primeiro: $primeiro"
if [ "$primeiro" = "A" ]; then
  ok=$((ok+1)); echo "  ok   termos juntos (A) vem antes de termos espalhados (B) com bm25 parecido"
else
  falhou=$((falhou+1)); echo "  FALHA termos juntos nao vieram primeiro: primeiro=$primeiro"
fi

echo
echo "== 2. um termo so mantem a ordem do bm25 =="
primeiro_um=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy" --json 2>/dev/null | node -e "$IDENTIFICA_JS"'const a=JSON.parse(require("fs").readFileSync(0,"utf8")||"[]");process.stdout.write(a[0] ? id(a[0].conteudo) : "vazio")')
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto \"deploy\" --json -> primeiro: $primeiro_um"
if [ "$primeiro_um" = "B" ]; then
  ok=$((ok+1)); echo "  ok   um termo: ordem do bm25 (B primeiro)"
else
  falhou=$((falhou+1)); echo "  FALHA um termo nao segue o bm25: primeiro=$primeiro_um"
fi

echo
echo "== 3. saida humana mostra o trecho com o termo entre [ e ] =="
humano=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "zztermofundo" 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto zztermofundo"
echo "  saida: $humano"
if echo "$humano" | grep -q "\[zztermofundo\]"; then
  ok=$((ok+1)); echo "  ok   trecho mostra [zztermofundo] depois do 100o caractere"
else
  falhou=$((falhou+1)); echo "  FALHA trecho nao mostra o termo entre colchetes"
fi

echo
echo "== 4. --json traz trecho e mantem conteudo inteiro =="
json_campos=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy servidor" --json 2>/dev/null | node -e "$IDENTIFICA_JS"'
  const a = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const a0 = a.find(x => id(x.conteudo) === "A");
  const ok = a0 && a0.trecho.includes("[deploy]") && a0.trecho.includes("[servidor]") && a0.conteudo.endsWith("sem aviso algum");
  process.stdout.write(ok ? "sim" : "nao");
' 2>/dev/null)
if [ "$json_campos" = "sim" ]; then
  ok=$((ok+1)); echo "  ok   --json: trecho com [deploy] e [servidor], conteudo inteiro"
else
  falhou=$((falhou+1)); echo "  FALHA --json sem trecho ou com conteudo truncado: $json_campos"
fi

echo
echo "== 5. --limite 1 devolve A (o corte vem depois do rerank) =="
um=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy servidor" --limite 1 --json 2>/dev/null | node -e "$IDENTIFICA_JS"'const a=JSON.parse(require("fs").readFileSync(0,"utf8")||"[]");process.stdout.write(a.length + ":" + (a[0] ? id(a[0].conteudo) : "vazio"))')
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto \"deploy servidor\" --limite 1 --json -> $um"
if [ "$um" = "1:A" ]; then
  ok=$((ok+1)); echo "  ok   --limite 1 devolve A"
else
  falhou=$((falhou+1)); echo "  FALHA --limite 1 nao devolveu A: $um"
fi

echo
echo "== 6. --limite 0 continua vazio explicado e --json []=="
zero_humano=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy servidor" --limite 0 2>/dev/null)
zero_json=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --texto "deploy servidor" --limite 0 --json 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto \"deploy servidor\" --limite 0 -> $zero_humano"
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto \"deploy servidor\" --limite 0 --json -> $zero_json"
if [ "$zero_humano" = "(nenhum resultado — --limite 0)" ] && [ "$(echo "$zero_json" | tr -d '[:space:]')" = "[]" ]; then
  ok=$((ok+1)); echo "  ok   --limite 0: vazio explicado e [] no json"
else
  falhou=$((falhou+1)); echo "  FALHA --limite 0 mudou a saida"
fi

echo
echo "== 7. sem --texto: recencia e sem campo trecho =="
recente=$(RFM_ROOT="$CAIXA" $MEMORIA buscar --projeto p-prox --limite 3 --json 2>/dev/null | node -e "$IDENTIFICA_JS"'
  const a = JSON.parse(require("fs").readFileSync(0, "utf8"));
  process.stdout.write(id(a[0].conteudo) + "|" + a.some(x => "trecho" in x));
' 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --projeto p-prox --limite 3 --json -> primeiro|tem trecho: $recente"
if [ "$recente" = "C|false" ]; then
  ok=$((ok+1)); echo "  ok   sem --texto: mais recente primeiro e sem campo trecho"
else
  falhou=$((falhou+1)); echo "  FALHA sem --texto mudou: $recente"
fi

echo
echo "== 8. --limite negativo com --texto devolve todos, como o LIMIT -1 de antes =="
# Caixa PRÓPRIA do caso 8 (os casos 1 a 7 usam a caixa de A, B e C). Aqui 60 observações
# casam com o termo, mais que o teto de 50 que o limite positivo impõe: se o limite negativo
# cair no teto, a contagem sai 50 e o caso fica vermelho.
CAIXA8="$(novo_sandbox)"
RFM_ROOT="$CAIXA8" $MEMORIA iniciar >/dev/null 2>&1
RFM_ROOT="$CAIXA8" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  for (let i = 0; i < 60; i++) ins.run('p-lim', 'deploy numero ' + i + ' do servico de catalogo com registro proprio', '2026-08-' + String(1 + (i % 28)).padStart(2, '0') + 'T10:00:00Z', 'lim-' + i);
  db.close();
" 2>/dev/null
conta_js='process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")||"[]").length))'
todos=$(RFM_ROOT="$CAIXA8" $MEMORIA buscar --texto "deploy" --limite 100 --json 2>/dev/null | node -e "$conta_js")
neg=$(RFM_ROOT="$CAIXA8" $MEMORIA buscar --texto "deploy" --limite -1 --json 2>/dev/null | node -e "$conta_js")
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto deploy --limite -1 --json -> $neg (com --limite 100: $todos)"
if [ "$neg" = 60 ] && [ "$todos" = 60 ]; then
  ok=$((ok+1)); echo "  ok   --limite -1 devolve os 60 casamentos"
else
  falhou=$((falhou+1)); echo "  FALHA --limite -1 devolveu $neg (com --limite 100: $todos), esperado 60"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
