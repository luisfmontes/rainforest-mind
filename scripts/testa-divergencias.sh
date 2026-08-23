#!/bin/bash
# Bateria do divergencias.cjs. Roda numa caixa de areia isolada — nada aqui
# toca a pasta de dados real do usuario. Uso: bash scripts/testa-divergencias.sh
#
# Mesmo desenho da bateria irma, scripts/testa-ideias.sh: o teste que importa
# e o de mutacao, no bloco 3. Ele sabota a conferencia byte a byte de proposito
# e exige que a gravacao seja recusada e revertida. Sem ele, os demais
# provariam so que o caminho feliz funciona — e uma trava que nunca foi vista
# travando nao e evidencia de nada (regra 12).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)/sandbox"
trap 'rm -rf "$(dirname "$SB")"' EXIT
export DIV="${DIV:-node scripts/divergencias.cjs}"
# A CAIXA DE AREIA E A RAIZ, declarado e nao presumido — mesma razao do
# testa-ideias.sh (comentario la explica o incidente 2026-08-11). Os blocos
# abaixo NAO copiam hooks/lib/raiz.cjs: o require falha e o script cai na
# pasta acima dele, que na caixa e a propria caixa (__dirname = $SB/scripts).
# RFM_ROOT aponta para o MESMO lugar, entao a resolucao concorda com ou sem a
# lib presente — a cadeia de niveis (RFM_ROOT > projeto > usuario > plugin)
# ja e provada pela bateria irma; aqui o que importa e a escrita verificada.
export RFM_ROOT="$SB"

mkdir -p "$SB/scripts" "$SB/hooks/lib"
cp "$SRC/scripts/divergencias.cjs" "$SB/scripts/"
cd "$SB" || exit 1

# O jsonl da caixa e FIXTURE GERADA, nunca copia do arquivo do usuario (regra
# 12 outra vez: bateria que empresta dado real nao prova nada sobre o dia em
# que o real esta vazio ou ausente). Tres linhas pre-existentes, para que o
# criterio "contagem indo de 3 para 4" tenha uma base concreta.
node - <<'JS'
const fs = require("fs");
const linhas = [
  {
    id: "fixture-01", enunciado: "enunciado de fixture 1",
    shortlist: ["ideia a", "ideia b"], escolha_nao_obvia: "ideia b",
    refutacao: "a ideia obvia quebra sob carga", status: "fechado",
    aberta_em: "2026-08-01", fechada_em: "2026-08-02",
    escolha: "ideia b", bate_com_a_primeira_ideia: false,
  },
  {
    id: "fixture-02", enunciado: "enunciado de fixture 2",
    shortlist: ["ideia c", "ideia d"], escolha_nao_obvia: "ideia c",
    refutacao: "a ideia d nao escala", status: "aberta",
    aberta_em: "2026-08-05",
  },
  {
    id: "fixture-03", enunciado: "enunciado de fixture 3",
    shortlist: ["ideia e", "ideia f"], escolha_nao_obvia: "ideia f",
    refutacao: "a ideia e ja foi tentada e falhou", status: "fechado",
    aberta_em: "2026-08-06", fechada_em: "2026-08-07",
    escolha: "ideia e", bate_com_a_primeira_ideia: true,
  },
];
fs.writeFileSync("divergencias.jsonl", linhas.map((o) => JSON.stringify(o)).join("\n") + "\n", "utf8");
JS
export BASE=$(node -e "process.stdout.write(String(require('fs').readFileSync('divergencias.jsonl','utf8').split('\n').filter((l)=>l.trim()).length))")
echo "(base: $BASE linhas de fixture gerada — nao depende da casa de quem roda)"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
PRELUDIO='const fs=require("fs");
const L=(f)=>fs.readFileSync(f,"utf8").split("\n").filter((x)=>x.trim());
const O=(f)=>L(f).map((x)=>JSON.parse(x));
const acha=(l,id)=>{const o=l.find((x)=>x.id===id);if(!o)throw new Error("id nao achado: "+id);return o;};
const ok=(c,m)=>{if(!c)throw new Error(m||"assert falhou");};
const hoje=()=>{const d=new Date(),p=(n)=>String(n).padStart(2,"0");return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate());};
const igual=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
'
prova() { # nome, script node que lanca Error se falhar
  local nome="$1"; shift
  if node -e "$PRELUDIO$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; node -e "$PRELUDIO$1" 2>&1 | grep -v "^ *at \|^Node.js v" | tail -4 | sed 's/^/         /'; fi
}
# As 3 linhas de fixture NUNCA sao alvo de nenhuma operacao desta bateria —
# capturar o texto exato delas aqui e comparar depois e o que prova "byte a
# byte", nao so "contagem bate".
tres_nao_alvo() {
  node -e "console.log(require('fs').readFileSync('divergencias.jsonl','utf8').split('\n').filter((l)=>l.trim()).slice(0,3).join('\n'))"
}
confere_nao_alvo() { # nome, valor-antes
  local nome="$1" antes="$2"
  if [ "$antes" = "$(tres_nao_alvo)" ]
  then ok=$((ok+1)); echo "  ok   $nome (3 linhas de fixture byte a byte identicas)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: as linhas de fixture mudaram"; fi
}

echo "== 1. entrada invalida e recusada ANTES de tocar o arquivo (abrir) =="
md5_antes=$(md5sum divergencias.jsonl | cut -d' ' -f1)
base='"enunciado":"e","shortlist":["a","b"],"escolha_nao_obvia":"a","refutacao":"r","critico_bateu_na_primeira_da_rodada":true,"ideias":[{"frame":"restricao-dura","ideia":"a","porque":"pa"},{"frame":"inversao","ideia":"b","porque":"pb"}]'

esperado "recusa stdin vazio" 1 bash -c '$DIV abrir < /dev/null'
esperado "recusa JSON malformado" 1 bash -c 'echo "{nao json" | $DIV abrir'
echo "{\"id\":\"Teste_Maiusculo\",$base}" > f.json
esperado "recusa id fora do kebab-case" 1 bash -c '$DIV abrir < f.json'
echo '{"id":"teste-um","enunciado":"e"}' > f.json
esperado "recusa campo obrigatorio faltando (shortlist/escolha/refutacao)" 1 bash -c '$DIV abrir < f.json'
echo "{\"id\":\"teste-um\",$base,\"status\":\"aberta\"}" > f.json
esperado "recusa status vindo da entrada (quem carimba e o script)" 1 bash -c '$DIV abrir < f.json'
echo "{\"id\":\"fixture-01\",$base}" > f.json
esperado "recusa id duplicado (ja existe na fixture)" 1 bash -c '$DIV abrir < f.json'
echo "{\"id\":\"teste-campo-inventado\",$base,\"origem\":\"nao existe em schema nenhum\"}" > f.json
esperado "tarefa 7: recusa abrir com campo inventado (allowlist, nao so denylist)" 1 bash -c '$DIV abrir < f.json'
echo '{"id":"teste-sem-ideias","enunciado":"e","shortlist":["a","b"],"escolha_nao_obvia":"a","refutacao":"r","critico_bateu_na_primeira_da_rodada":true}' > f.json
esperado "tarefa 8: recusa abrir sem ideias (campo obrigatorio novo)" 1 bash -c '$DIV abrir < f.json'
echo '{"id":"teste-ideias-vazia","enunciado":"e","shortlist":["a","b"],"escolha_nao_obvia":"a","refutacao":"r","critico_bateu_na_primeira_da_rodada":true,"ideias":[]}' > f.json
esperado "tarefa 8: recusa abrir com ideias vazia (array truthy, mas sem ideia nenhuma)" 1 bash -c '$DIV abrir < f.json'
echo '{"id":"teste-critico-nao-booleano","enunciado":"e","shortlist":["a","b"],"escolha_nao_obvia":"a","refutacao":"r","critico_bateu_na_primeira_da_rodada":"sim","ideias":[{"frame":"x","ideia":"i","porque":"p"}]}' > f.json
esperado "tarefa 8: recusa abrir com critico_bateu_na_primeira_da_rodada fora do booleano" 1 bash -c '$DIV abrir < f.json'

if [ "$md5_antes" = "$(md5sum divergencias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   arquivo intocado apos as 10 recusas (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA o arquivo mudou apesar de todas as recusas"; fi

echo
echo "== 2. caminho feliz: abrir + fechar =="
antes_2=$(tres_nao_alvo)
echo "{\"id\":\"rodada-um\",\"enunciado\":\"onde por o cache do agregado diario\",\"shortlist\":[\"tabela materializada\",\"view indexada\",\"cache em memoria\"],\"escolha_nao_obvia\":\"view indexada\",\"refutacao\":\"a tabela materializada parece obvia mas duplica a fonte da verdade e cria deriva de dado\",\"critico_bateu_na_primeira_da_rodada\":true,\"ideias\":[{\"frame\":\"restricao-dura\",\"ideia\":\"tabela materializada\",\"porque\":\"p1\"},{\"frame\":\"inversao\",\"ideia\":\"view indexada\",\"porque\":\"p2\"},{\"frame\":\"incentivo\",\"ideia\":\"cache em memoria\",\"porque\":\"p3\"}]}" > rodada.json
esperado "abrir (contagem 3 -> 4)" 0 bash -c '$DIV abrir < rodada.json'
prova "linha aberta com status e data carimbada pelo script (local)" '
const l=O("divergencias.jsonl"), o=acha(l,"rodada-um");
ok(o.status==="aberta" && o.aberta_em===hoje(), JSON.stringify(o));
ok(o.escolha_nao_obvia==="view indexada", o.escolha_nao_obvia);
ok(l.length===Number(process.env.BASE)+1, String(l.length));'
prova "tarefa 8: critico_bateu_na_primeira_da_rodada e ideias persistidos pelo abrir" '
const l=O("divergencias.jsonl"), o=acha(l,"rodada-um");
ok(o.critico_bateu_na_primeira_da_rodada===true, "critico_bateu_na_primeira_da_rodada nao persistiu: "+JSON.stringify(o.critico_bateu_na_primeira_da_rodada));
ok(Array.isArray(o.ideias) && o.ideias.length===3, "ideias nao persistiu ou veio com tamanho errado: "+JSON.stringify(o.ideias));'
confere_nao_alvo "depois do abrir" "$antes_2"

antes_fechar=$(tres_nao_alvo)
echo '{"escolha":"view indexada","bate_com_a_primeira_ideia":false}' > escolha.json
esperado "fechar (contagem continua 4)" 0 bash -c '$DIV fechar --id rodada-um < escolha.json'
prova "linha fechada com escolha, booleano e data — nao criou linha nova" '
const l=O("divergencias.jsonl"), o=acha(l,"rodada-um");
ok(o.status==="fechado" && o.fechada_em===hoje(), JSON.stringify(o));
ok(o.escolha==="view indexada" && o.bate_com_a_primeira_ideia===false, JSON.stringify(o));
ok(o.enunciado==="onde por o cache do agregado diario", "fechar mexeu em campo que nao era dele");
ok(l.length===Number(process.env.BASE)+1, String(l.length));'
prova "tarefa 8: as duas medidas de ancoragem convivem, com valores distintos, na linha fechada" '
const l=O("divergencias.jsonl"), o=acha(l,"rodada-um");
ok(o.critico_bateu_na_primeira_da_rodada===true, "critico_bateu_na_primeira_da_rodada sumiu ou mudou no fechar: "+JSON.stringify(o.critico_bateu_na_primeira_da_rodada));
ok(o.bate_com_a_primeira_ideia===false, "bate_com_a_primeira_ideia nao veio do fechar: "+JSON.stringify(o.bate_com_a_primeira_ideia));
ok(o.critico_bateu_na_primeira_da_rodada!==o.bate_com_a_primeira_ideia, "as duas medidas vieram com o mesmo valor — o teste nao discrimina os dois campos");
ok(Array.isArray(o.ideias) && o.ideias.length===3, "ideias nao sobreviveu ao fechar: "+JSON.stringify(o.ideias));'
confere_nao_alvo "depois do fechar" "$antes_fechar"

echo
echo "== 3. os quatro erros exigidos, e a entrada invalida de fechar =="
antes_3=$(tres_nao_alvo)
esperado "recusa fechar id inexistente" 1 bash -c '$DIV fechar --id nao-existe < escolha.json'
esperado "recusa fechar linha ja fechada" 1 bash -c '$DIV fechar --id rodada-um < escolha.json'
esperado "recusa fechar sem stdin" 1 bash -c '$DIV fechar --id fixture-02 < /dev/null'
esperado "recusa fechar com JSON malformado" 1 bash -c 'echo "{nao json" | $DIV fechar --id fixture-02'
esperado "recusa fechar sem escolha" 1 bash -c 'echo "{\"bate_com_a_primeira_ideia\":true}" | $DIV fechar --id fixture-02'
esperado "recusa fechar com bate_com_a_primeira_ideia fora do booleano" 1 bash -c 'echo "{\"escolha\":\"x\",\"bate_com_a_primeira_ideia\":\"sim\"}" | $DIV fechar --id fixture-02'
esperado "recusa abrir id duplicado (o que acabou de ser aberto)" 1 bash -c '$DIV abrir < rodada.json'
confere_nao_alvo "depois dos seis erros" "$antes_3"
prova "fixture-02 continua aberta — nenhuma das recusas fechou por engano" '
const o=acha(O("divergencias.jsonl"),"fixture-02");
ok(o.status==="aberta", JSON.stringify(o));'

echo
echo "== 3b. tarefa 7: fechar recusa payload forjado (id/shortlist tentando sequestrar a linha) =="
antes_3b=$(tres_nao_alvo)
saida_forjada=$(echo '{"escolha":"y","bate_com_a_primeira_ideia":true,"id":"FORJADO","shortlist":["sequestrada"]}' | $DIV fechar --id fixture-02 2>&1)
got_forjada=$?
if [ "$got_forjada" != 0 ] && echo "$saida_forjada" | grep -q "id" && echo "$saida_forjada" | grep -q "shortlist"
then ok=$((ok+1)); echo "  ok   fechar recusa payload forjado nomeando id e shortlist (exit $got_forjada)"
else falhou=$((falhou+1)); echo "  FALHA fechar aceitou ou nao nomeou os campos forjados (exit $got_forjada)"; echo "$saida_forjada" | sed 's/^/         /'
fi
confere_nao_alvo "depois do payload forjado (fixture-02 e as demais nao-alvo intocadas)" "$antes_3b"
prova "fixture-02 continua com id e shortlist originais — nao foi sequestrada" '
const o=acha(O("divergencias.jsonl"),"fixture-02");
ok(o.id==="fixture-02", "id foi sequestrado: "+JSON.stringify(o.id));
ok(igual(o.shortlist,["ideia c","ideia d"]), "shortlist foi sequestrada: "+JSON.stringify(o.shortlist));
ok(o.status==="aberta", "status mudou por engano: "+o.status);'

echo
echo "== 3c. tarefa 9: fechar recusa registro legado que nao passa no schema completo =="
# Fixture sintetica da linha real do usuario: anterior a D11, sem 'ideias' e
# sem 'critico_bateu_na_primeira_da_rodada', com o nome improvisado
# 'critico_viu_ancoragem' e 'origem' — reproducao do defeito que o `revisar`
# achou (fechar uma linha assim saia exit 0, sem o lastro que a D4 exige).
node - <<'JS'
const fs = require("fs");
const legada = {"id":"legada","enunciado":"e","shortlist":["s"],"escolha_nao_obvia":"x","refutacao":"r","critico_viu_ancoragem":false,"origem":"run wf_xxx","status":"aberta","aberta_em":"2026-08-23"};
fs.appendFileSync("divergencias.jsonl", JSON.stringify(legada) + "\n", "utf8");
JS
antes_9=$(cat divergencias.jsonl)
saida_legada=$(echo '{"escolha":"y","bate_com_a_primeira_ideia":true}' | $DIV fechar --id legada 2>&1)
got_legada=$?
if [ "$got_legada" != 0 ] \
  && echo "$saida_legada" | grep -q "critico_viu_ancoragem" \
  && echo "$saida_legada" | grep -q "critico_bateu_na_primeira_da_rodada" \
  && echo "$saida_legada" | grep -q "ideias"
then ok=$((ok+1)); echo "  ok   fechar recusa linha legada nomeando o que esta fora do schema (exit $got_legada)"
else falhou=$((falhou+1)); echo "  FALHA fechar nao recusou a linha legada ou nao nomeou os campos (exit $got_legada)"; echo "$saida_legada" | sed 's/^/         /'
fi
if [ "$antes_9" = "$(cat divergencias.jsonl)" ]
then ok=$((ok+1)); echo "  ok   arquivo inteiro intocado apos a recusa (byte a byte)"
else falhou=$((falhou+1)); echo "  FALHA o arquivo mudou apesar da recusa"; fi
prova "legada continua 'aberta', sem os campos novos, com o nome velho intacto" '
const o=acha(O("divergencias.jsonl"),"legada");
ok(o.status==="aberta", "status mudou: "+JSON.stringify(o.status));
ok(o.critico_viu_ancoragem===false, "critico_viu_ancoragem sumiu ou mudou: "+JSON.stringify(o.critico_viu_ancoragem));
ok(!("critico_bateu_na_primeira_da_rodada" in o), "critico_bateu_na_primeira_da_rodada nao deveria existir ainda");
ok(!("ideias" in o), "ideias nao deveria existir ainda");'

echo
echo "== 3d. tarefa 10: reparar migra a linha legada, e so entao fechar sai 0 =="
antes_10=$(tres_nao_alvo)
# critico_bateu_na_primeira_da_rodada vai TRUE no stdin, DIFERENTE do valor
# real (false, em critico_viu_ancoragem) — de proposito: se o reparo so
# copiasse o valor do stdin em vez de renomear o campo velho, a prova abaixo
# pegaria a farsa (o valor gravado teria que ser false, o original, nao o
# true que mandei).
echo '{"ideias":[{"frame":"restricao-dura","ideia":"i1","porque":"p1"},{"frame":"inversao","ideia":"i2","porque":"p2"}],"critico_bateu_na_primeira_da_rodada":true}' > reparo.json
esperado "reparar migra a linha legada" 0 bash -c '$DIV reparar --id legada < reparo.json'
confere_nao_alvo "depois do reparar" "$antes_10"
prova "reparar RENOMEIA preservando o valor original (false), nao o padrao do stdin (true)" '
const o=acha(O("divergencias.jsonl"),"legada");
ok(o.critico_bateu_na_primeira_da_rodada===false, "valor nao preservado, veio: "+JSON.stringify(o.critico_bateu_na_primeira_da_rodada));
ok(!("critico_viu_ancoragem" in o), "critico_viu_ancoragem deveria ter sumido");
ok(o.origem==="run wf_xxx", "origem deveria ter sido mantido: "+JSON.stringify(o.origem));
ok(Array.isArray(o.ideias) && o.ideias.length===2, "ideias nao chegou: "+JSON.stringify(o.ideias));
ok(o.status==="aberta", "reparar nao deveria mudar o status: "+o.status);'
esperado "fechar na linha reparada agora sai 0" 0 \
  bash -c 'echo "{\"escolha\":\"y\",\"bate_com_a_primeira_ideia\":true}" | $DIV fechar --id legada'
prova "legada fechada com sucesso, schema completo, valor do critico intacto" '
const o=acha(O("divergencias.jsonl"),"legada");
ok(o.status==="fechado", "nao fechou: "+JSON.stringify(o.status));
ok(o.critico_bateu_na_primeira_da_rodada===false, "valor mudou durante o fechar: "+JSON.stringify(o.critico_bateu_na_primeira_da_rodada));'

echo
echo "== 4. mutacao: a conferencia byte a byte trava mesmo? =="
# Linha ABERTA e com o schema COMPLETO (ideias + critico_bateu_na_primeira_da_
# rodada), so para este bloco: fixture-02 e legada como fixture-01/03 (sem os
# campos da D11) e a tarefa 9 a recusaria no `fechar` por schema incompleto —
# o que provaria a validacao nova, nao a conferencia byte a byte que este
# bloco existe para testar.
echo "{\"id\":\"rodada-para-fechar-mutante\",$base}" > fpm.json
esperado "abrir linha completa para o teste de mutacao do fechar" 0 bash -c '$DIV abrir < fpm.json'
cp divergencias.jsonl pre-mutacao.jsonl
echo "  (mutando scripts/divergencias.cjs na caixa — o que \$DIV executa)"
node - <<'JS'
const fs = require("fs");
const alvo = "scripts/divergencias.cjs";
const s = fs.readFileSync(alvo, "utf8");
const ancora = '  const tmp = ALVO.replace(/\\.jsonl$/, ".jsonl.tmp");';
const veneno = '  linhasDepois = linhasDepois.slice(); linhasDepois[0] = linhasDepois[0].replace("{", "{\\"MUTACAO\\": 1, ");\n';
if (!s.includes(ancora)) throw new Error("ancora da mutacao sumiu — o teste precisa ser reajustado");
fs.writeFileSync(alvo, s.replace(ancora, veneno + ancora), "utf8");
console.log("  (mutante instalado: corrompe a linha 1 na escrita, que nunca e alvo de abrir/fechar aqui)");
JS
echo "{\"id\":\"rodada-mutante\",$base}" > fm.json
esperado "mutante recusado no abrir (a trava reverte e sai != 0)" 1 bash -c '$DIV abrir < fm.json'
if cmp -s divergencias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   arquivo restaurado do backup, byte a byte igual ao de antes"
else falhou=$((falhou+1)); echo "  FALHA o mutante corrompeu o arquivo e nada reverteu"; fi

# Segundo caminho de escrita, alvo diferente (uma linha existente, nao uma
# nova ao final): se a conferencia so travasse no abrir, o fechar passaria
# batido — e ele e o unico comando que reescreve conteudo no lugar.
esperado "mutante recusado tambem no fechar (alvo e uma linha, nao o fim do arquivo)" 1 \
  bash -c 'echo "{\"escolha\":\"x\",\"bate_com_a_primeira_ideia\":true}" | $DIV fechar --id rodada-para-fechar-mutante'
if cmp -s divergencias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   fechar tambem reverteu byte a byte"
else falhou=$((falhou+1)); echo "  FALHA o fechar gravou por cima do mutante"; fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
