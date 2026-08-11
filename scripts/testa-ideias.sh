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
# A CAIXA DE AREIA E A RAIZ, e isso precisa ser DECLARADO e nao presumido.
# Ate 2026-08-11 a caixa isolava por acidente: o script resolvia a raiz como "a
# pasta acima de mim", que na caixa era a propria caixa. No dia em que os dados do
# Luis sairam do repo para ~/.rainforest, a cadeia passou a achar a raiz GLOBAL
# antes — e a bateria escreveu `teste-com-gancho` dentro do ideias.jsonl de
# verdade. Isolamento que depende de coincidencia nao e isolamento.
export RFM_ROOT="$SB"

mkdir -p "$SB/scripts"
cp "$SRC/scripts/ideias.py" "$SB/scripts/"
cp "$SRC/scripts/ideias.cjs" "$SB/scripts/"
# O jsonl e DADO e saiu do repo em 2026-08-11. A caixa copia da raiz de dados
# real, resolvida pela mesma cadeia do hook - e continua sendo COPIA: o RFM_ROOT
# acima aponta para a caixa, entao nada aqui toca o arquivo de verdade.
# `env -u RFM_ROOT`: esta bateria exporta RFM_ROOT para a caixa de areia, e sem
# tirar a variavel a resolucao devolveria a propria caixa (nivel 1 vence tudo).
# Caminho em forma WINDOWS: o node daqui nao resolve `/c/Projetos/...` do Git Bash,
# e o require falha em silencio deixando a variavel vazia. Terceira vez hoje.
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
# `env -u RFM_ROOT`: quando a bateria exporta RFM_ROOT para a caixa de areia, sem
# tirar a variavel a resolucao devolveria a propria caixa (nivel 1 vence tudo).
DADOS_REAIS="$(env -u RFM_ROOT node -e "const r=require('$SRC_WIN/hooks/lib/raiz.cjs').resolverRaiz({plugin:'$SRC_WIN'});process.stdout.write(r.raiz||'')" 2>/dev/null)"
cp "$DADOS_REAIS/ideias.jsonl" "$SB/"
cd "$SB" || exit 1

export BASE=$(python -c "print(sum(1 for l in open('ideias.jsonl',encoding='utf-8') if l.strip()))")
echo "(base: $BASE linhas copiadas do arquivo real)"

# As 70 linhas reais ainda nao tem `gancho` (e essa lacuna e o motivo desta
# tarefa — ver o comentario em scripts/ideias.cjs). Migrar o arquivo real e
# trabalho a parte (reparar --id <id> --gancho "..." linha a linha, fora desta
# bateria — este script nunca toca ideias.jsonl de verdade). Aqui, na COPIA da
# caixa de areia, pre-preenche so para o restante da bateria poder testar o
# comportamento novo sem tropecar na migracao pendente das linhas antigas.
python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl")
linhas = [l for l in p.read_text(encoding="utf-8").split("\n") if l.strip()]
n = 0
for i, l in enumerate(linhas):
    o = json.loads(l)
    if not o.get("gancho"):
        o["gancho"] = "gancho de teste (seed da bateria, nao e dado real)"
        linhas[i] = json.dumps(o, ensure_ascii=False)
        n += 1
p.write_text("\n".join(linhas) + "\n", encoding="utf-8", newline="\n")
print(f"  (seed: gancho preenchido em {n} linha(s) da copia, so para a bateria rodar)")
PY

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
echo "{\"id\":\"teste-um\",\"titulo\":\"Ideia de teste\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"ao_colher\":\"nada\",\"gancho\":\"revisar quando a bateria rodar de novo\"}" > f.json
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
echo "{\"id\":\"teste-editar\",\"titulo\":\"Antes\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > fe.json
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

echo "{\"id\":\"teste-dois\",\"titulo\":\"Segunda\",\"descricao\":\"d2\",\"contexto\":\"c2\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > f2.json
esperado "plantar segunda" 0 bash -c '$IDEIAS plantar < f2.json'
echo "{\"id\":\"teste-tres\",\"titulo\":\"Terceira\",\"descricao\":\"d3\",\"contexto\":\"c3\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > f3.json
esperado "plantar terceira" 0 bash -c '$IDEIAS plantar < f3.json'
esperado "recusa absorver uma ja colhida" 1 bash -c 'echo "{\"id\":\"teste-dois\",\"titulo\":\"x\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"p\"}" | $IDEIAS unificar --manter teste-dois --absorver teste-um'
echo "{\"id\":\"teste-dois\",\"titulo\":\"Fundida\",\"descricao\":\"conteudo fundido\",\"contexto\":\"c2\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > fu.json
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
                    "contexto": "c", "projeto": "sandbox", "tipo": "observacao",
                    "gancho": "g"},
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
echo "{\"id\":\"teste-quatro\",$base,\"gancho\":\"g\"}" > f4.json
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
                    "contexto": "c", "projeto": "sandbox", "gancho": "g"}, ensure_ascii=False)
p.write_text(p.read_text(encoding="utf-8") + linha + "\n", encoding="utf-8", newline="\n")
PY
cp ideias.jsonl pre-reparo-mutante.jsonl
esperado "mutante recusado tambem no reparar" 1 $IDEIAS reparar --id teste-quebrada-mutante --plantada-em 2026-08-01
if cmp -s ideias.jsonl pre-reparo-mutante.jsonl
then ok=$((ok+1)); echo "  ok   reparar tambem reverteu byte a byte"
else falhou=$((falhou+1)); echo "  FALHA o reparar gravou por cima do mutante"; fi

echo
echo "== 4. cadeia de raiz: o projeto sobrescreve, e a escrita vai pro lugar certo =="
# Os blocos acima NAO copiam hooks/lib/raiz.cjs para a caixa — o require falha e o
# script cai na pasta acima dele, que e o comportamento antigo. E isso que mantem os
# blocos anteriores isolados. Aqui a lib entra de proposito, para exercitar o caminho
# novo: com um .rainforest/ marcado no diretorio de trabalho, a escrita tem que ir PARA
# LA, e o jsonl da raiz da caixa tem que ficar intocado. Sem esta prova, a cadeia estaria
# ligada no ideias.cjs e nunca vista funcionando por ali.
case "$IDEIAS" in
  *ideias.cjs*)
    # o mutante do bloco 3 segue instalado no .cjs da caixa; usar uma copia limpa
    mkdir -p "$SB/hooks/lib" "$SB/proj/.rainforest"
    cp "$SRC/hooks/lib/raiz.cjs" "$SB/hooks/lib/"
    cp "$SRC/scripts/ideias.cjs" "$SB/scripts/ideias-limpo.cjs"
    head -3 ideias.jsonl > "$SB/proj/.rainforest/ideias.jsonl"
    md5_caixa_antes=$(md5sum ideias.jsonl | cut -d' ' -f1)
    echo "{\"id\":\"teste-raiz-projeto\",$base,\"gancho\":\"g\"}" > "$SB/proj/nova.json"
    # RFM_ROOT venceria o nivel de projeto (e o nivel 1 da cadeia): sai so aqui,
    # para o teste exercitar exatamente o nivel que ele existe para provar.
    ( cd "$SB/proj" && env -u RFM_ROOT node ../scripts/ideias-limpo.cjs plantar < nova.json ) >/dev/null 2>&1
    got=$?
    esperado "plantar de dentro de um projeto com .rainforest" 0 bash -c "exit $got"
    # Caminho RELATIVO: o prova() roda python com cwd na raiz da caixa, e o python
    # daqui e o do Windows — caminho POSIX do mktemp ele nao enxerga.
    prova "gravou no .rainforest do projeto (4 linhas, com o id novo)" "
import json
l=[x for x in open('proj/.rainforest/ideias.jsonl',encoding='utf-8') if x.strip()]
ids=[json.loads(x)['id'] for x in l]
assert 'teste-raiz-projeto' in ids, ids
assert len(l)==4, len(l)
"
    if [ "$(md5sum ideias.jsonl | cut -d' ' -f1)" = "$md5_caixa_antes" ]; then
      ok=$((ok+1)); echo "  ok   o jsonl da raiz da caixa ficou intocado"
    else
      falhou=$((falhou+1)); echo "  FALHA escreveu na raiz da caixa em vez do projeto"
    fi
    ;;
  *)
    echo "  (pulado: a cadeia de raiz e do .cjs; \$IDEIAS aponta para outra implementacao)"
    ;;
esac

echo
echo "== 5. gancho: o gatilho de retorno vira campo obrigatorio (regra 6) =="
# Regra 6 da skill exige que toda ideia plantada leve o gancho de retorno
# concreto — ate aqui isso vivia sem validacao, dentro da prosa do ao_colher.
# O ideias.py fica congelado no contrato antigo de proposito (ver comentario
# em scripts/ideias.cjs); gancho e recurso novo, so do .cjs. Mesmo padrao do
# bloco 4: pula quando $IDEIAS aponta para outra implementacao.
case "$IDEIAS" in
  *ideias.cjs*)
    # O bloco 3 deixa o mutante instalado em scripts/ideias.cjs de proposito (a
    # caixa inteira e descartada no fim). $IDEIAS ainda aponta pra ele aqui —
    # por isso o bloco 4 usa a copia limpa que ele mesmo criou, e este bloco
    # reusa a MESMA copia (scripts/ideias-limpo.cjs), pelo mesmo motivo.
    export IDEIAS_LIMPO="node scripts/ideias-limpo.cjs"
    md5_antes_gancho=$(md5sum ideias.jsonl | cut -d' ' -f1)
    echo "{\"id\":\"teste-sem-gancho\",$base}" > fg.json
    esperado "plantar sem gancho e recusado" 1 bash -c '$IDEIAS_LIMPO plantar < fg.json'
    if [ "$md5_antes_gancho" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   arquivo intocado apos a recusa por falta de gancho"
    else falhou=$((falhou+1)); echo "  FALHA plantar sem gancho alterou o arquivo"; fi

    echo "{\"id\":\"teste-com-gancho\",$base,\"gancho\":\"revisar em 2026-09-01\"}" > fg2.json
    esperado "plantar com gancho passa" 0 bash -c '$IDEIAS_LIMPO plantar < fg2.json'
    prova "gancho chega gravado na linha" '
import json
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-com-gancho"][0]
assert o["gancho"]=="revisar em 2026-09-01", o.get("gancho")'

    echo '{"gancho":"trocado: revisar em 2026-10-01"}' > edg.json
    esperado "editar troca o gancho de ideia aberta" 0 bash -c '$IDEIAS_LIMPO editar --id teste-com-gancho < edg.json'
    prova "gancho editado chega gravado" '
import json
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-com-gancho"][0]
assert o["gancho"]=="trocado: revisar em 2026-10-01", o.get("gancho")'

    # linha gravada a mao (bypassa o script), sem gancho — o caso real das 70
    # linhas existentes que motivou a tarefa. Guarda tambem o conteudo exato de
    # OUTRA linha (nao-alvo do reparo que vem a seguir) para provar depois que
    # o reparo --gancho nao mexeu nela.
    python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl")
linha = json.dumps({"id": "teste-sem-gancho-existente", "titulo": "t", "descricao": "d",
                    "contexto": "c", "projeto": "sandbox", "status": "plantada",
                    "plantada_em": "2026-08-01"}, ensure_ascii=False)
p.write_text(p.read_text(encoding="utf-8") + linha + "\n", encoding="utf-8", newline="\n")
l = [x for x in p.read_text(encoding="utf-8").split("\n") if x.strip()]
outra = [x for x in l if json.loads(x)["id"] == "teste-com-gancho"][0]
pathlib.Path("linha-outra-antes-reparo-gancho.txt").write_text(outra, encoding="utf-8")
PY
    esperado "conferir acusa a linha sem gancho" 1 $IDEIAS_LIMPO conferir
    saida_conferir_gancho=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_conferir_gancho" | grep -q "teste-sem-gancho-existente.*gancho"
    then ok=$((ok+1)); echo "  ok   ... e nomeia a linha especifica"
    else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha sem gancho"; echo "$saida_conferir_gancho" | sed 's/^/         /'; fi

    esperado "recusa --gancho sem --id (uma linha por vez, como --plantada-em)" 1 $IDEIAS_LIMPO reparar --todas --gancho "nao vale"
    esperado "reparar --gancho preenche a linha" 0 $IDEIAS_LIMPO reparar --id teste-sem-gancho-existente --gancho "revisar em 2026-11-01"
    prova "gancho reparado gravado, reparo deixa rastro" '
import json
l=[json.loads(x) for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
o=[x for x in l if x["id"]=="teste-sem-gancho-existente"][0]
assert o["gancho"]=="revisar em 2026-11-01", o.get("gancho")
assert "gancho" in o["reparo"], o.get("reparo")'
    # "conferir para de acusar": checagem pontual da linha reparada, nao do
    # arquivo inteiro — o bloco 3 deixou teste-quebrada-mutante propositalmente
    # quebrada (a mutacao foi revertida ANTES do reparo dela chegar a gravar),
    # entao "conferir" sozinho nunca mais volta a exit 0 nesta caixa. O que
    # este item do briefing pede e que a ACUSACAO de gancho suma, nao que o
    # arquivo inteiro fique perfeito.
    saida_pos_reparo_gancho=$($IDEIAS_LIMPO conferir 2>&1)
    if ! echo "$saida_pos_reparo_gancho" | grep -q "teste-sem-gancho-existente.*gancho"
    then ok=$((ok+1)); echo "  ok   conferir para de acusar a linha reparada"
    else falhou=$((falhou+1)); echo "  FALHA conferir ainda acusa gancho na linha ja reparada"; echo "$saida_pos_reparo_gancho" | sed 's/^/         /'; fi

    prova "reparar --gancho nao mexeu em linha nao-alvo (byte a byte)" '
import json
l=[x.rstrip("\n") for x in open("ideias.jsonl",encoding="utf-8") if x.strip()]
outra=[x for x in l if json.loads(x)["id"]=="teste-com-gancho"][0]
antes=open("linha-outra-antes-reparo-gancho.txt",encoding="utf-8").read().rstrip("\n")
assert outra == antes, (outra, antes)'

    # Gancho e gatilho de RETORNO: so ideia ABERTA precisa dele. Cobrar gatilho de
    # quem ja voltou seria ruido, e ruido ensina a ignorar o conferir. Sem este
    # teste, a regra viveria so no comentario do codigo.
    python - <<'PY'
import json, pathlib
p = pathlib.Path("ideias.jsonl")
linha = json.dumps({"id": "teste-colhida-sem-gancho", "titulo": "t", "descricao": "d",
                    "contexto": "c", "projeto": "sandbox", "status": "colhida",
                    "plantada_em": "2026-08-01", "colhida_em": "2026-08-02",
                    "resultado": "feito"}, ensure_ascii=False)
p.write_text(p.read_text(encoding="utf-8") + linha + "\n", encoding="utf-8", newline="\n")
PY
    saida_colhida=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_colhida" | grep -q "teste-colhida-sem-gancho.*gancho"
    then falhou=$((falhou+1)); echo "  FALHA cobrou gancho de ideia ja colhida"
    else ok=$((ok+1)); echo "  ok   colhida sem gancho NAO e cobrada (gancho e de quem espera voltar)"
    fi
    # e a checagem segue valendo para as abertas — o teste acima nao pode ter
    # desligado a cobranca inteira.
    if echo "$saida_colhida" | grep -q "teste-sem-gancho-existente.*gancho"
    then falhou=$((falhou+1)); echo "  FALHA a linha aberta reparada ainda e cobrada"
    else ok=$((ok+1)); echo "  ok   a aberta reparada saiu da cobranca, e a regra continua ligada"
    fi
    ;;
  *)
    echo "  (pulado: gancho e recurso novo so do .cjs; \$IDEIAS aponta para outra implementacao)"
    ;;
esac

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
