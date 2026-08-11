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
export IDEIAS="${IDEIAS:-node scripts/ideias.cjs}"

mkdir -p "$SB/scripts"
cp "$SRC/scripts/ideias.py" "$SB/scripts/"
cp "$SRC/scripts/ideias.cjs" "$SB/scripts/"
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
esperado "recusa data vinda do input (o bug de UTC, por construcao)" 1 bash -c '$IDEIAS plantar < f.json'
echo "{\"id\":\"Teste_Maiusculo\",$base}" > f.json
esperado "recusa id fora do kebab-case" 1 bash -c '$IDEIAS plantar < f.json'
echo "{\"id\":\"gate-do-p1-e-hook-nao-texto\",$base}" > f.json
esperado "recusa id duplicado" 1 bash -c '$IDEIAS plantar < f.json'
echo '{"id":"teste-um","titulo":"t","descricao":"d"}' > f.json
esperado "recusa campo obrigatorio faltando" 1 bash -c '$IDEIAS plantar < f.json'
echo "{\"id\":\"teste-um\",$base,\"tipo\":\"invencao\"}" > f.json
esperado "recusa tipo desconhecido" 1 bash -c '$IDEIAS plantar < f.json'
esperado "recusa stdin vazio" 1 bash -c '$IDEIAS plantar < /dev/null'
esperado "recusa JSON malformado" 1 bash -c 'echo "{nao json" | $IDEIAS plantar'

if [ "$md5_antes" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   arquivo intocado apos 7 recusas (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA o arquivo mudou apesar de todas as recusas"; fi

echo
echo "== 2. caminho feliz =="
echo "{\"id\":\"teste-um\",\"titulo\":\"Ideia de teste\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"ao_colher\":\"nada\"}" > f.json
esperado "plantar" 0 bash -c '$IDEIAS plantar < f.json'
prova "data carimbada pelo script (local) e status plantada" '
import json,datetime,os
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-um"][0]
assert o["status"]=="plantada" and o["plantada_em"]==datetime.date.today().isoformat()
assert len(l)==int(os.environ["BASE"])+1'

esperado "iniciar (plantada -> em-colheita)" 0 $IDEIAS iniciar --id teste-um --andamento "metade feita"
esperado "recusa iniciar duas vezes" 1 $IDEIAS iniciar --id teste-um
prova "iniciar grava colheita_iniciada_em e andamento" '
import json,datetime
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-um"][0]
assert o["status"]=="em-colheita" and o["andamento"]=="metade feita"
assert o["colheita_iniciada_em"]==datetime.date.today().isoformat()'
echo '{"resultado":"entregue no teste"}' > r.json
esperado "colher" 0 bash -c '$IDEIAS colher --id teste-um < r.json'
esperado "recusa colher duas vezes" 1 bash -c '$IDEIAS colher --id teste-um < r.json'
esperado "recusa colher sem resultado" 1 bash -c 'echo "{}" | $IDEIAS colher --id teste-um'
esperado "recusa id inexistente" 1 bash -c '$IDEIAS colher --id nao-existe < r.json'

# editar: ideia muda antes de ser colhida. Sem este comando a correcao virava
# edicao a mao no jsonl, que e o que o ideias.py existe para impedir.
echo "{\"id\":\"teste-editar\",\"titulo\":\"Antes\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\"}" > fe.json
esperado "plantar a que sera editada" 0 bash -c '$IDEIAS plantar < fe.json'
echo '{"titulo":"Depois","ao_colher":"passo novo"}' > ed.json
esperado "editar ideia aberta" 0 bash -c '$IDEIAS editar --id teste-editar < ed.json'
prova "editar troca so o que veio, carimba editada_em e preserva plantada_em" '
import json,datetime,os
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-editar"][0]
assert o["titulo"]=="Depois" and o["ao_colher"]=="passo novo"
assert o["descricao"]=="d" and o["contexto"]=="c", "campo nao enviado foi alterado"
assert o["status"]=="plantada", "editar nao deve mexer no status"
assert o["editada_em"]==datetime.date.today().isoformat()
assert o["plantada_em"]==datetime.date.today().isoformat()
assert len(l)==int(os.environ["BASE"])+2, "editar nao pode mudar a contagem"'
esperado "recusa editar o que ja foi colhido" 1 bash -c 'echo "{\"titulo\":\"x\"}" | $IDEIAS editar --id teste-um'
esperado "recusa editar sem nada para mudar" 1 bash -c 'echo "{}" | $IDEIAS editar --id teste-editar'
esperado "recusa trocar o id pela entrada" 1 bash -c 'echo "{\"id\":\"outro\",\"titulo\":\"x\"}" | $IDEIAS editar --id teste-editar'
esperado "recusa carimbar data pela entrada tambem no editar" 1 bash -c 'echo "{\"plantada_em\":\"2030-01-01\"}" | $IDEIAS editar --id teste-editar'
esperado "recusa editar id inexistente" 1 bash -c 'echo "{\"titulo\":\"x\"}" | $IDEIAS editar --id nao-existe-mesmo'

echo "{\"id\":\"teste-dois\",\"titulo\":\"Segunda\",\"descricao\":\"d2\",\"contexto\":\"c2\",\"projeto\":\"sandbox\"}" > f2.json
esperado "plantar segunda" 0 bash -c '$IDEIAS plantar < f2.json'
echo "{\"id\":\"teste-tres\",\"titulo\":\"Terceira\",\"descricao\":\"d3\",\"contexto\":\"c3\",\"projeto\":\"sandbox\"}" > f3.json
esperado "plantar terceira" 0 bash -c '$IDEIAS plantar < f3.json'
esperado "recusa absorver uma ja colhida" 1 bash -c 'echo "{\"id\":\"teste-dois\",\"titulo\":\"x\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"p\"}" | $IDEIAS unificar --manter teste-dois --absorver teste-um'
echo "{\"id\":\"teste-dois\",\"titulo\":\"Fundida\",\"descricao\":\"conteudo fundido\",\"contexto\":\"c2\",\"projeto\":\"sandbox\"}" > fu.json
esperado "unificar (duas linhas, contagem igual)" 0 bash -c '$IDEIAS unificar --manter teste-dois --absorver teste-tres < fu.json'
esperado "recusa unificar consigo mesmo" 1 bash -c '$IDEIAS unificar --manter teste-dois --absorver teste-dois < fu.json'
prova "absorvida aponta pra sobrevivente, conteudo fundido gravado, contagem base+4" '
import json,os
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
a=[x for x in l if x["id"]=="teste-tres"][0]; b=[x for x in l if x["id"]=="teste-dois"][0]
assert a["status"]=="unificada" and a["unificada_em_id"]=="teste-dois"
assert b["absorveu"]==["teste-tres"] and b["titulo"]=="Fundida"
# base+4 e nao base+3 desde que o bloco do editar plantou teste-editar antes daqui.
assert len(l)==int(os.environ["BASE"])+4'

echo
echo "== 2.5 reparar: linha que entrou no arquivo sem passar pelo script =="
# O caso real: em 2026-08-10 uma observacao foi gravada a mao, sem status nem
# plantada_em, e so apareceu no conferir. O editar nao conserta (status e
# plantada_em sao CAMPOS_PROIBIDOS_NO_INPUT, e devem continuar sendo).
python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl")
linha = json.dumps({"id": "teste-quebrada", "titulo": "Gravada a mao", "descricao": "d",
                    "contexto": "c", "projeto": "sandbox", "tipo": "observacao"},
                   ensure_ascii=False)
p.write_text(p.read_text(encoding="utf-8") + linha + "\n", encoding="utf-8", newline="\n")
PY
esperado "conferir acusa a linha sem status" 1 $IDEIAS conferir
esperado "recusa reparar sem --id nem --todas" 1 $IDEIAS reparar
md5_pre_reparo=$(md5sum ideias.jsonl | cut -d' ' -f1)
esperado "--conferir descreve o reparo" 0 $IDEIAS reparar --todas --conferir
if [ "$md5_pre_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   --conferir nao gravou nada (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA --conferir escreveu no arquivo"; fi

# A sandbox nao e repo git: data_do_git devolve None, que e exatamente a
# condicao em que carimbar hoje seria inventar historia. Recusar aqui e o
# comportamento certo, e e o unico jeito de provar que ele nao chuta.
esperado "recusa reparar quando o git nao sabe a data (nao chuta hoje)" 1 $IDEIAS reparar --todas
if [ "$md5_pre_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   e a recusa deixou o arquivo intocado"
else falhou=$((falhou+1)); echo "  FALHA gravou apesar de nao saber a data"; fi

esperado "recusa --plantada-em no futuro" 1 $IDEIAS reparar --id teste-quebrada --plantada-em 2099-01-01
esperado "recusa --plantada-em fora do formato ISO" 1 $IDEIAS reparar --id teste-quebrada --plantada-em 10/08/2026
esperado "recusa --plantada-em junto de --todas" 1 $IDEIAS reparar --todas --plantada-em 2026-08-01
esperado "reparar com a data informada" 0 $IDEIAS reparar --id teste-quebrada --plantada-em 2026-08-01
prova "status inferido, data preservada, reparo deixa rastro" '
import json, datetime
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-quebrada"][0]
assert o["status"]=="plantada", o.get("status")
assert o["plantada_em"]=="2026-08-01", "a data informada foi trocada"
assert o["reparada_em"]==datetime.date.today().isoformat()
assert o["reparo"]==["plantada_em","status"], o.get("reparo")
assert o["titulo"]=="Gravada a mao" and o["tipo"]=="observacao", "reparo mexeu no conteudo"'
esperado "conferir volta a passar depois do reparo" 0 $IDEIAS conferir
esperado "reparar de novo nao encontra nada (idempotente)" 0 $IDEIAS reparar --todas
md5_pos_reparo=$(md5sum ideias.jsonl | cut -d' ' -f1)
esperado "reparar linha sadia nao a toca" 0 $IDEIAS reparar --id teste-editar
if [ "$md5_pos_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   linha sadia ficou byte a byte igual"
else falhou=$((falhou+1)); echo "  FALHA reparou o que nao estava quebrado"; fi

# Reparo nao e conserto de valor errado: para isso existe o editar, que deixa
# rastro de decisao. Status errado (mas conhecido) nao e buraco.
python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl"); linhas=[l for l in p.read_text(encoding="utf-8").split("\n") if l.strip()]
for i,l in enumerate(linhas):
    o=json.loads(l)
    if o["id"]=="teste-quebrada":
        o["status"]="em-colheita"; linhas[i]=json.dumps(o, ensure_ascii=False)
p.write_text("\n".join(linhas)+"\n", encoding="utf-8", newline="\n")
PY
md5_status_trocado=$(md5sum ideias.jsonl | cut -d' ' -f1)
esperado "reparar ignora status errado porem conhecido" 0 $IDEIAS reparar --id teste-quebrada
if [ "$md5_status_trocado" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   valor existente nao foi reescrito (isso e trabalho do editar)"
else falhou=$((falhou+1)); echo "  FALHA reparar sobrescreveu valor que ja existia"; fi

esperado "listar" 0 $IDEIAS listar

# Data no futuro fabricada AQUI, nao herdada do arquivo real: em 2026-08-09 esta
# bateria ficou vermelha na virada da meia-noite, porque as datas "de amanha" do
# jsonl viraram "de hoje" e o conferir parou de acusar. Teste que depende de
# condicao transitoria mente nos dois sentidos.
esperado "conferir passa quando o arquivo esta saudavel" 0 $IDEIAS conferir
python - <<'PY'
import datetime, json, pathlib
p = pathlib.Path("ideias.jsonl"); linhas = [l for l in p.read_text(encoding="utf-8").split("\n") if l.strip()]
o = json.loads(linhas[-1]); o["plantada_em"] = (datetime.date.today() + datetime.timedelta(days=30)).isoformat()
linhas[-1] = json.dumps(o, ensure_ascii=False)
p.write_text("\n".join(linhas) + "\n", encoding="utf-8", newline="\n")
PY
esperado "conferir acusa data no futuro (o bug de UTC, detectado depois do fato)" 1 $IDEIAS conferir
contem_saida() { if $IDEIAS conferir 2>&1 | grep -q "NO FUTURO"; then ok=$((ok+1)); echo "  ok   ... e diz NO FUTURO, nomeando a linha"; else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha"; fi; }
contem_saida

echo
echo "== 3. mutacao: a conferencia byte a byte trava mesmo? =="
cp ideias.jsonl pre-mutacao.jsonl
# O mutante tem que sabotar a implementacao que $IDEIAS de fato roda — senao o
# bloco vira teatro: sabota o .py, roda o .cjs, e a gravacao passa limpa.
case "$IDEIAS" in
  *ideias.cjs*) MUTANTE_ALVO="scripts/ideias.cjs" ;;
  *)            MUTANTE_ALVO="scripts/ideias.py"  ;;
esac
echo "  (mutando $MUTANTE_ALVO — o que \$IDEIAS executa)"
MUTANTE_ALVO="$MUTANTE_ALVO" python - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["MUTANTE_ALVO"]); s = p.read_text(encoding="utf-8")
if p.suffix == ".py":
    alvo = '    tmp = ALVO.with_suffix(".jsonl.tmp")'
    veneno = '    linhas_depois = list(linhas_depois); linhas_depois[0] = linhas_depois[0].replace("{", "{\\"MUTACAO\\": 1, ", 1)\n'
else:
    alvo = '  const tmp = ALVO.replace(/\\.jsonl$/, ".jsonl.tmp");'
    veneno = '  linhasDepois = linhasDepois.slice(); linhasDepois[0] = linhasDepois[0].replace("{", "{\\"MUTACAO\\": 1, ");\n'
assert alvo in s, f"ancora da mutacao sumiu em {p} — o teste precisa ser reajustado"
s = s.replace(alvo, veneno + alvo, 1)
p.write_text(s, encoding="utf-8")
print("  (mutante instalado: corrompe a linha 1, que nunca e alvo de um plantar)")
PY
echo "{\"id\":\"teste-quatro\",$base}" > f4.json
esperado "mutante recusado (a trava reverte e sai != 0)" 1 bash -c '$IDEIAS plantar < f4.json'
if cmp -s ideias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   arquivo restaurado do backup, byte a byte igual ao de antes"
else falhou=$((falhou+1)); echo "  FALHA o mutante corrompeu o arquivo e nada reverteu"; fi

# O editar grava pelo mesmo gravar(), mas com UMA linha como alvo em vez de
# nenhuma. Alvo diferente e caminho diferente: se a conferencia so travasse no
# plantar, o editar passaria batido — e ele e o unico comando que reescreve
# conteudo no lugar. O mutante segue instalado do bloco acima.
esperado "mutante recusado tambem no editar (alvo e uma linha, nao zero)" 1 bash -c 'echo "{\"titulo\":\"nao deve entrar\"}" | $IDEIAS editar --id teste-editar'
if cmp -s ideias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   editar tambem reverteu byte a byte"
else falhou=$((falhou+1)); echo "  FALHA o editar gravou por cima do mutante"; fi

# Terceiro caminho de escrita, terceira forma de alvo: o reparar pode ter varias
# linhas como alvo de uma vez. Mutante segue instalado.
python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl")
linha = json.dumps({"id": "teste-quebrada-mutante", "titulo": "t", "descricao": "d",
                    "contexto": "c", "projeto": "sandbox"}, ensure_ascii=False)
p.write_text(p.read_text(encoding="utf-8") + linha + "\n", encoding="utf-8", newline="\n")
PY
cp ideias.jsonl pre-reparo-mutante.jsonl
esperado "mutante recusado tambem no reparar" 1 $IDEIAS reparar --id teste-quebrada-mutante --plantada-em 2026-08-01
if cmp -s ideias.jsonl pre-reparo-mutante.jsonl
then ok=$((ok+1)); echo "  ok   reparar tambem reverteu byte a byte"
else falhou=$((falhou+1)); echo "  FALHA o reparar gravou por cima do mutante"; fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
