#!/bin/bash
# Bateria do ideias.py. Roda numa caixa de areia com uma COPIA do jsonl —
# nada aqui toca o arquivo real. Uso: bash scripts/testa-ideias.sh
#
# O teste que importa e o de mutacao, no bloco 3: ele sabota a conferencia
# byte a byte de proposito e exige que a gravacao seja recusada e revertida.
# Sem ele, os demais provariam so que o caminho feliz funciona — e uma
# trava que nunca foi vista travando nao e evidencia de nada (regra 12).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)/sandbox"
trap 'rm -rf "$(dirname "$SB")"' EXIT

mkdir -p "$SB/scripts"
cp "$SRC/scripts/ideias.py" "$SB/scripts/"
cp "$SRC/ideias.jsonl" "$SB/"
cd "$SB" || exit 1

export BASE=$(python -c "print(sum(1 for l in open('ideias.jsonl',encoding='utf-8') if l.strip()))")
echo "(base: $BASE linhas copiadas do arquivo real)"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
prova() { # nome, script python que levanta AssertionError se falhar
  local nome="$1"; shift
  if python -c "$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; python -c "$1" 2>&1 | tail -3 | sed 's/^/         /'; fi
}

echo "== 1. entrada invalida e recusada ANTES de tocar o arquivo =="
md5_antes=$(md5sum ideias.jsonl | cut -d' ' -f1)
base='"titulo":"t","descricao":"d","contexto":"c","projeto":"p"'

echo "{\"id\":\"teste-um\",$base,\"plantada_em\":\"2030-01-01\"}" > f.json
esperado "recusa data vinda do input (o bug de UTC, por construcao)" 1 bash -c 'python scripts/ideias.py plantar < f.json'
echo "{\"id\":\"Teste_Maiusculo\",$base}" > f.json
esperado "recusa id fora do kebab-case" 1 bash -c 'python scripts/ideias.py plantar < f.json'
echo "{\"id\":\"gate-do-p1-e-hook-nao-texto\",$base}" > f.json
esperado "recusa id duplicado" 1 bash -c 'python scripts/ideias.py plantar < f.json'
echo '{"id":"teste-um","titulo":"t","descricao":"d"}' > f.json
esperado "recusa campo obrigatorio faltando" 1 bash -c 'python scripts/ideias.py plantar < f.json'
echo "{\"id\":\"teste-um\",$base,\"tipo\":\"invencao\"}" > f.json
esperado "recusa tipo desconhecido" 1 bash -c 'python scripts/ideias.py plantar < f.json'
esperado "recusa stdin vazio" 1 bash -c 'python scripts/ideias.py plantar < /dev/null'
esperado "recusa JSON malformado" 1 bash -c 'echo "{nao json" | python scripts/ideias.py plantar'

if [ "$md5_antes" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   arquivo intocado apos 7 recusas (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA o arquivo mudou apesar de todas as recusas"; fi

echo
echo "== 2. caminho feliz =="
echo "{\"id\":\"teste-um\",\"titulo\":\"Ideia de teste\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"ao_colher\":\"nada\"}" > f.json
esperado "plantar" 0 bash -c 'python scripts/ideias.py plantar < f.json'
prova "data carimbada pelo script (local) e status plantada" '
import json,datetime,os
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-um"][0]
assert o["status"]=="plantada" and o["plantada_em"]==datetime.date.today().isoformat()
assert len(l)==int(os.environ["BASE"])+1'

esperado "iniciar (plantada -> em-colheita)" 0 python scripts/ideias.py iniciar --id teste-um
esperado "recusa iniciar duas vezes" 1 python scripts/ideias.py iniciar --id teste-um
echo '{"resultado":"entregue no teste"}' > r.json
esperado "colher" 0 bash -c 'python scripts/ideias.py colher --id teste-um < r.json'
esperado "recusa colher duas vezes" 1 bash -c 'python scripts/ideias.py colher --id teste-um < r.json'
esperado "recusa colher sem resultado" 1 bash -c 'echo "{}" | python scripts/ideias.py colher --id teste-um'
esperado "recusa id inexistente" 1 bash -c 'python scripts/ideias.py colher --id nao-existe < r.json'

echo "{\"id\":\"teste-dois\",\"titulo\":\"Segunda\",\"descricao\":\"d2\",\"contexto\":\"c2\",\"projeto\":\"sandbox\"}" > f2.json
esperado "plantar segunda" 0 bash -c 'python scripts/ideias.py plantar < f2.json'
echo "{\"id\":\"teste-tres\",\"titulo\":\"Terceira\",\"descricao\":\"d3\",\"contexto\":\"c3\",\"projeto\":\"sandbox\"}" > f3.json
esperado "plantar terceira" 0 bash -c 'python scripts/ideias.py plantar < f3.json'
esperado "recusa absorver uma ja colhida" 1 bash -c 'echo "{\"id\":\"teste-dois\",\"titulo\":\"x\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"p\"}" | python scripts/ideias.py unificar --manter teste-dois --absorver teste-um'
echo "{\"id\":\"teste-dois\",\"titulo\":\"Fundida\",\"descricao\":\"conteudo fundido\",\"contexto\":\"c2\",\"projeto\":\"sandbox\"}" > fu.json
esperado "unificar (duas linhas, contagem igual)" 0 bash -c 'python scripts/ideias.py unificar --manter teste-dois --absorver teste-tres < fu.json'
esperado "recusa unificar consigo mesmo" 1 bash -c 'python scripts/ideias.py unificar --manter teste-dois --absorver teste-dois < fu.json'
prova "absorvida aponta pra sobrevivente, conteudo fundido gravado, contagem base+3" '
import json,os
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
a=[x for x in l if x["id"]=="teste-tres"][0]; b=[x for x in l if x["id"]=="teste-dois"][0]
assert a["status"]=="unificada" and a["unificada_em_id"]=="teste-dois"
assert b["absorveu"]==["teste-tres"] and b["titulo"]=="Fundida"
assert len(l)==int(os.environ["BASE"])+3'

esperado "listar" 0 python scripts/ideias.py listar

# Data no futuro fabricada AQUI, nao herdada do arquivo real: em 2026-08-09 esta
# bateria ficou vermelha na virada da meia-noite, porque as datas "de amanha" do
# jsonl viraram "de hoje" e o conferir parou de acusar. Teste que depende de
# condicao transitoria mente nos dois sentidos.
esperado "conferir passa quando o arquivo esta saudavel" 0 python scripts/ideias.py conferir
python - <<'PY'
import datetime, json, pathlib
p = pathlib.Path("ideias.jsonl"); linhas = [l for l in p.read_text(encoding="utf-8").split("\n") if l.strip()]
o = json.loads(linhas[-1]); o["plantada_em"] = (datetime.date.today() + datetime.timedelta(days=30)).isoformat()
linhas[-1] = json.dumps(o, ensure_ascii=False)
p.write_text("\n".join(linhas) + "\n", encoding="utf-8", newline="\n")
PY
esperado "conferir acusa data no futuro (o bug de UTC, detectado depois do fato)" 1 python scripts/ideias.py conferir
contem_saida() { if python scripts/ideias.py conferir 2>&1 | grep -q "NO FUTURO"; then ok=$((ok+1)); echo "  ok   ... e diz NO FUTURO, nomeando a linha"; else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha"; fi; }
contem_saida

echo
echo "== 3. mutacao: a conferencia byte a byte trava mesmo? =="
cp ideias.jsonl pre-mutacao.jsonl
python - <<'PY'
import pathlib
p = pathlib.Path("scripts/ideias.py"); s = p.read_text(encoding="utf-8")
alvo = '    tmp = ALVO.with_suffix(".jsonl.tmp")'
assert alvo in s, "ancora da mutacao sumiu — o teste precisa ser reajustado"
s = s.replace(alvo, '    linhas_depois = list(linhas_depois); linhas_depois[0] = linhas_depois[0].replace("{", "{\\"MUTACAO\\": 1, ", 1)\n' + alvo, 1)
p.write_text(s, encoding="utf-8")
print("  (mutante instalado: corrompe a linha 1, que nunca e alvo de um plantar)")
PY
echo "{\"id\":\"teste-quatro\",$base}" > f4.json
esperado "mutante recusado (a trava reverte e sai != 0)" 1 bash -c 'python scripts/ideias.py plantar < f4.json'
if cmp -s ideias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   arquivo restaurado do backup, byte a byte igual ao de antes"
else falhou=$((falhou+1)); echo "  FALHA o mutante corrompeu o arquivo e nada reverteu"; fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
