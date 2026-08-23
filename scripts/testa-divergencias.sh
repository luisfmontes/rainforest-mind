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
base='"enunciado":"e","shortlist":["a","b"],"escolha_nao_obvia":"a","refutacao":"r"'

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

if [ "$md5_antes" = "$(md5sum divergencias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   arquivo intocado apos as 7 recusas (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA o arquivo mudou apesar de todas as recusas"; fi

echo
echo "== 2. caminho feliz: abrir + fechar =="
antes_2=$(tres_nao_alvo)
echo "{\"id\":\"rodada-um\",\"enunciado\":\"onde por o cache do agregado diario\",\"shortlist\":[\"tabela materializada\",\"view indexada\",\"cache em memoria\"],\"escolha_nao_obvia\":\"view indexada\",\"refutacao\":\"a tabela materializada parece obvia mas duplica a fonte da verdade e cria deriva de dado\"}" > rodada.json
esperado "abrir (contagem 3 -> 4)" 0 bash -c '$DIV abrir < rodada.json'
prova "linha aberta com status e data carimbada pelo script (local)" '
const l=O("divergencias.jsonl"), o=acha(l,"rodada-um");
ok(o.status==="aberta" && o.aberta_em===hoje(), JSON.stringify(o));
ok(o.escolha_nao_obvia==="view indexada", o.escolha_nao_obvia);
ok(l.length===Number(process.env.BASE)+1, String(l.length));'
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
echo "== 4. mutacao: a conferencia byte a byte trava mesmo? =="
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
  bash -c 'echo "{\"escolha\":\"x\",\"bate_com_a_primeira_ideia\":true}" | $DIV fechar --id fixture-02'
if cmp -s divergencias.jsonl pre-mutacao.jsonl
then ok=$((ok+1)); echo "  ok   fechar tambem reverteu byte a byte"
else falhou=$((falhou+1)); echo "  FALHA o fechar gravou por cima do mutante"; fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
