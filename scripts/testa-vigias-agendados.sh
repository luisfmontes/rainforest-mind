#!/bin/bash
# Bateria do checador de vigias (`checarVigias` em scripts/saude.cjs).
#
# POR QUE EXISTE, com numero. Em 2026-09-01 mediu-se que `vigia-tickets-manha` e
# `vigia-tickets-tarde` estavam mortos desde 11/08 - VINTE DIAS - por um gatilho
# com `EndBoundary` vencido em 12/08. O Agendador de Tarefas do Windows nao
# desabilita a tarefa nem marca erro nesse caso:
#
#     State: Ready      Enabled: True      LastTaskResult: 0
#
# Os tres campos que uma pessoa checa dizem "saudavel". O UNICO que denuncia e o
# `NextRunTime`, que fica VAZIO - e campo em branco le-se como "nada de errado".
# Ninguem percebeu por vinte dias, e nenhuma bateria olhava para la.
#
# ELA NASCE VERMELHA, E ISSO E O RESULTADO CERTO. As duas tarefas estao mortas
# de verdade nesta maquina. Quem a torna verde e a tarefa T7 desta entrega
# (reagendar sem EndBoundary), que altera ambiente do usuario e por isso depende
# da palavra dele - nao desta bateria. Uma bateria que nascesse verde num
# ambiente com dois vigias mortos nao estaria medindo nada.
#
# SO LEITURA. Ela nunca registra, altera, habilita, desabilita nem dispara
# tarefa agendada. Mexer no Agendador e ambiente do usuario.
#
# E ela EXECUTA o artefato real - `checarVigias` importado de scripts/saude.cjs
# - em vez de reimplementar a consulta. As caixas de areia recebem uma COPIA do
# saude.cjs, e por isso o `RAIZ_CODIGO` dele (path.resolve(__dirname, '..'))
# resolve para a caixa: e assim que se testa o caminho de leitura do ERROS.md
# sem tocar no arquivo real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

ok=0; falhou=0
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }

command -v node >/dev/null 2>&1 || { echo "FALHA node nao esta no PATH"; exit 1; }

# --- PULO LIMPO, e nao falso vermelho. Este plugin e publico e roda na maquina
#     de outra gente: sem PowerShell nao ha Agendador de Tarefas do Windows para
#     consultar, e reprovar por isso seria acusar o ambiente de um defeito que
#     ele nao tem.
if ! command -v powershell >/dev/null 2>&1; then
  echo "PULADO: powershell nao esta no PATH — nao ha Agendador de Tarefas para consultar."
  exit 0
fi
# --- Mesmo raciocinio para o toggle: as rondas nascem DESLIGADAS, e quem nao
#     agendou nada nao pode receber cobranca sobre agendamento inexistente.
if ! node "$SRC/scripts/setup.cjs" --ligado vigias >/dev/null 2>&1; then
  echo "PULADO: o toggle 'vigias' esta desligado — nao ha ronda agendada a conferir."
  exit 0
fi

# Roda uma expressao com o saude.cjs de uma raiz escolhida (a real ou uma caixa).
com_saude() { node -e "$2" "$1"; }

echo "== 1. a maquina real: nenhum vigia agendado pode estar sem proxima execucao =="
# O caso que faltava, e que deixou dois vigias mortos por vinte dias.
TAREFAS="$(com_saude "$SRC/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  const ts = m.tarefasDeVigia();
  if (ts === null) { console.log("INDISPONIVEL"); process.exit(0); }
  for (const t of ts) console.log(t.nome + "\t" + (t.proxima || ""));
')"
if [ "$TAREFAS" = "INDISPONIVEL" ]; then
  echo "PULADO: nao consegui consultar o Agendador (PowerShell respondeu com erro)."
  exit 0
fi
if [ -z "$TAREFAS" ]; then
  echo "PULADO: nenhuma tarefa agendada aponta para run-vigia.ps1 nesta maquina."
  exit 0
fi

total=$(printf '%s\n' "$TAREFAS" | wc -l | tr -d ' ')
vivas=$(printf '%s\n' "$TAREFAS" | awk -F'\t' 'NF>1 && $2 != "" {n++} END{print n+0}')
mortas=$(printf '%s\n' "$TAREFAS" | awk -F'\t' '$2 == "" {n++} END{print n+0}')

echo "  -- tarefas de vigia nesta maquina ($total):"
printf '%s\n' "$TAREFAS" | awk -F'\t' '{ printf "     %-24s proxima: %s\n", $1, ($2=="" ? "(VAZIA)" : $2) }'

if [ "$mortas" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    nenhuma tarefa com proxima execucao vazia"
else
  falhou=$((falhou+1))
  echo "  FALHA $mortas de $total tarefa(s) sem proxima execucao — elas aparecem Ready e nunca rodam:"
  printf '%s\n' "$TAREFAS" | awk -F'\t' '$2 == "" { print "        " $1 }'
  echo "        causa provavel: gatilho com EndBoundary vencido. Reagendar altera"
  echo "        ambiente do usuario e depende da palavra dele."
fi

echo
echo "== 2. e ela nao e cega: reconhece como VIVA a tarefa que tem proxima execucao =="
# Sem este caso, um checador que dissesse "morta" para tudo passaria no caso 1
# sempre que houvesse alguma morta, e ninguem saberia.
if [ "$vivas" -gt 0 ]; then
  ok=$((ok+1)); echo "  ok    $vivas de $total tarefa(s) reconhecidas como vivas"
else
  falhou=$((falhou+1)); echo "  FALHA nenhuma tarefa reconhecida como viva — o checador pode estar respondendo 'morta' para tudo"
fi

echo
echo "== 3. o achado que sobe: alerta nomeia as mortas, e nao so conta =="
ACHADOS="$(com_saude "$SRC/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  m.checarVigias();
  for (const a of m.achados) console.log(a.nivel + "\t" + a.item + "\t" + a.detalhe);
')"
echo "$ACHADOS" | sed 's/^/     /'
if [ "$mortas" -gt 0 ]; then
  printf '%s' "$ACHADOS" | grep -q '^alerta' && r=sim || r=nao
  verdade "com tarefa morta, o nivel e ALERTA (nao aviso)" "$r"
  primeira_morta=$(printf '%s\n' "$TAREFAS" | awk -F'\t' '$2 == "" { print $1; exit }')
  printf '%s' "$ACHADOS" | grep -qF "$primeira_morta" && r=sim || r=nao
  verdade "o alerta NOMEIA a tarefa morta ($primeira_morta)" "$r"
else
  printf '%s' "$ACHADOS" | grep -q '^ok	vigias' && r=sim || r=nao
  verdade "sem tarefa morta, o nivel e ok" "$r"
fi

# ---------------------------------------------------------------------------
# Caixas de areia: o caminho de leitura do ERROS.md, sem tocar no arquivo real.
# ---------------------------------------------------------------------------
caixa() {  # caixa <nome> -> imprime a raiz criada
  local dir="$SB/$1"
  rm -rf "$dir"
  mkdir -p "$dir/scripts" "$dir/vigias"
  cp "$SRC/scripts/saude.cjs" "$dir/scripts/saude.cjs"
  echo "$dir"
}

echo
echo "== 4. ERROS.md sem erro recente: sobe ok, nao aviso =="
C4="$(caixa erros-vazio)"
printf -- '# Erros dos vigias\n\n- 2020-01-01 08:00 [sentinela-foco]: erro antigo, fora da janela\n' > "$C4/vigias/ERROS.md"
S4="$(com_saude "$C4/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  const e = m.errosRecentes(7);
  console.log(e === null ? "NULL" : String(e.length));
')"
igual "nenhum erro dentro da janela de 7 dias" "$S4" "0"

echo
echo "== 5. ERROS.md com erro de ontem: e contado, e o vigia e identificado =="
C5="$(caixa erros-recentes)"
ONTEM="$(date -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)"
{
  printf -- '# Erros dos vigias\n\n'
  printf -- '- %s 09:01 [batedor-repos]: backup do FOCO.md falhou (exit 1)\n' "$ONTEM"
  printf -- '- %s 15:52 [jardineiro-ideias]: backup do FOCO.md falhou (exit 1)\n' "$ONTEM"
  printf -- '- 2020-01-01 08:00 [sentinela-foco]: erro antigo, fora da janela\n'
} > "$C5/vigias/ERROS.md"
S5="$(com_saude "$C5/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  const e = m.errosRecentes(7);
  console.log(e.length + " " + e.map(x => x.vigia).join(","));
')"
igual "conta so os da janela, e nomeia os vigias" "$S5" "2 batedor-repos,jardineiro-ideias"

echo
echo "== 6. linha malformada nao vira erro fantasma =="
# O parser casa o formato exato que o vigias/erros.ps1 grava. Prosa solta no
# arquivo - e ha bastante, o ERROS.md e lido por gente - nao pode inflar a
# contagem, senao o aviso vira ruido e volta a ser ignorado.
C6="$(caixa erros-malformado)"
{
  printf -- '# Erros dos vigias\n\n'
  printf -- 'Uma anotacao a mao, sem formato nenhum.\n'
  printf -- '- data invalida [vigia]: nao casa\n'
  printf -- '- %s 09:01 [batedor-repos]: este casa\n' "$ONTEM"
} > "$C6/vigias/ERROS.md"
S6="$(com_saude "$C6/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  console.log(String(m.errosRecentes(7).length));
')"
igual "so a linha no formato do erros.ps1 conta" "$S6" "1"

echo
echo "== 7. ERROS.md ausente devolve null, e null nao vira 'zero erros' =="
# Distincao que importa: "perguntei e nao ha erro" e "nao consegui perguntar"
# nao podem virar o mesmo achado. Confundir os dois e o modo de falha que esta
# bateria inteira existe para pegar, um andar acima.
C7="$(caixa sem-arquivo)"
S7="$(com_saude "$C7/scripts/saude.cjs" '
  const m = require(process.argv[1]);
  console.log(m.errosRecentes(7) === null ? "NULL" : "LISTA");
')"
igual "sem ERROS.md, errosRecentes devolve null" "$S7" "NULL"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
