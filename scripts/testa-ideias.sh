#!/bin/bash
# Bateria de scripts/ideias.cjs. Roda numa caixa de areia com uma COPIA do jsonl —
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
# o usuario sairam do repo para ~/.rainforest, a cadeia passou a achar a raiz GLOBAL
# antes — e a bateria escreveu `teste-com-gancho` dentro do ideias.jsonl de
# verdade. Isolamento que depende de coincidencia nao e isolamento.
export RFM_ROOT="$SB"

mkdir -p "$SB/scripts" "$SB/hooks/lib"
cp "$SRC/scripts/ideias.cjs" "$SB/scripts/"
# O vocabulario de projeto virou lib em 2026-08-12 (o setup.cjs tambem mexe no
# projetos.json, e duas implementacoes divergem em silencio). O require dela e DURO
# de proposito — lib ausente e instalacao quebrada, nao caso de fallback —, entao a
# caixa de areia tem que espelhar a forma do plugin. `raiz.cjs` NAO entra aqui: o
# bloco 4 a copia de proposito no meio da bateria, para exercitar a cadeia.
cp "$SRC/hooks/lib/projetos.cjs" "$SB/hooks/lib/"
# Trava e leitura viraram lib comum com o divergencias.cjs em 2026-08-23 — o
# require dela tambem e DURO (sem try/catch), entao falta aqui derruba a
# bateria inteira, nao so o teste que dependeria dela.
cp "$SRC/hooks/lib/trava-jsonl.cjs" "$SB/hooks/lib/"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
# O jsonl da caixa e FIXTURE GERADA, e nao copia do arquivo do usuario.
#
# Ate 2026-08-17 estas linhas resolviam a raiz de dados REAL e copiavam o
# `ideias.jsonl` de verdade para dentro da caixa. Nada era escrito no arquivo do
# usuario — o RFM_ROOT acima ja garantia isso —, mas a bateria dependia dele
# EXISTIR e do que tinha dentro. Duas consequencias, as duas medidas no mesmo dia:
#
#   $ bash scripts/testa-ideias.sh                        # com a casa real
#     == resultado: 138 ok, 0 falha(s) ==
#   $ USERPROFILE=<pasta vazia> bash scripts/testa-ideias.sh
#     FALHA plantar: esperava exit 0, veio 1     (a bateria inteira desaba)
#
# Foi assim que ela ficou vermelha no CI (Issue #16) e verde aqui. Uma bateria que
# so passa porque a maquina de quem roda tem dado nao e evidencia de nada — e o
# `$BASE` vindo do arquivo real fazia a contagem esperada mudar conforme o dia.
#
# O seed logo abaixo ja normalizava TODO o conteudo copiado (projeto=sandbox,
# gancho preenchido, schema completado), entao o arquivo real nunca foi fixture de
# verdade: so emprestava a contagem e a existencia. A fixture abaixo entrega as
# mesmas FORMAS de proposito — inclusive a linha legada sem `id` e com `data`, e a
# linha sem `gancho` — para que os tres caminhos do seed continuem exercitados.
#
# O `cd` vem ANTES de gerar, e nao e detalhe: o gerador escreve `ideias.jsonl` no
# diretorio corrente, e com o `cd` depois ele cairia na raiz do REPOSITORIO.
cd "$SB" || exit 1
node - <<'JS'
const fs = require("fs");
const linhas = [];
const base = (i) => ({
  id: `fixture-${String(i).padStart(2, "0")}`,
  titulo: `ideia de fixture ${i}`,
  descricao: "descricao de fixture, gerada pela bateria",
  contexto: "contexto de fixture, gerado pela bateria",
  projeto: "sandbox",
  ao_colher: "nada — e fixture",
  gancho: "gancho de fixture",
  tipo: "ideia",
  status: "plantada",
  plantada_em: "2026-08-01",
});
for (let i = 1; i <= 9; i += 1) linhas.push(base(i));
// Linha legada: sem `id`, com o campo antigo `data` no lugar de `plantada_em`.
// Existe uma assim no arquivo real (vista em 2026-08-14), e o seed tem um ramo so
// para ela — sem esta forma aqui, esse ramo nunca rodaria.
//
// Ela traz `contexto`, `ao_colher` e `tipo` de proposito: o seed preenche `id`,
// `titulo`, `descricao`, `status`, `plantada_em` e `gancho`, e SO esses. O que ele
// nao preenche tem de vir da fixture, senao o `conferir` dos blocos seguintes
// reprova a linha por campo obrigatorio vazio — que foi o que aconteceu na
// primeira versao desta fixture.
linhas.push({
  data: "2026-07-30",
  descricao: "linha legada sem id",
  contexto: "contexto de fixture",
  projeto: "sandbox",
  ao_colher: "nada — e fixture",
  tipo: "ideia",
});
// Sem `gancho`: exercita o ramo `n` do seed.
{ const o = base(10); delete o.gancho; linhas.push(o); }
// Projeto fora do vocabulario: exercita o ramo `c` do seed.
{ const o = base(11); o.projeto = "Projeto Qualquer\tcom tab"; linhas.push(o); }
fs.writeFileSync("ideias.jsonl", linhas.map((o) => JSON.stringify(o)).join("\n") + "\n", "utf8");
JS

export BASE=$(node -e "process.stdout.write(String(require('fs').readFileSync('ideias.jsonl','utf8').split('\n').filter((l)=>l.trim()).length))")
echo "(base: $BASE linhas de fixture gerada — nao depende da casa de quem roda)"

# As 70 linhas reais ainda nao tem `gancho` (e essa lacuna e o motivo desta
# tarefa — ver o comentario em scripts/ideias.cjs). Migrar o arquivo real e
# trabalho a parte (reparar --id <id> --gancho "..." linha a linha, fora desta
# bateria — este script nunca toca ideias.jsonl de verdade). Aqui, na COPIA da
# caixa de areia, pre-preenche so para o restante da bateria poder testar o
# comportamento novo sem tropecar na migracao pendente das linhas antigas.
node - <<'JS'
const fs = require("fs");
const p = "ideias.jsonl";
const linhas = fs.readFileSync(p, "utf8").split("\n").filter((l) => l.trim());
let n = 0, c = 0, e = 0;
linhas.forEach((l, i) => {
  const o = JSON.parse(l);
  let mudou = false;
  // Registro real fora do schema atual (sem id/titulo/descricao — visto em
  // 2026-08-14: uma linha gravada por outro caminho, com o campo antigo `data`
  // no lugar de `plantada_em`). E um dos problemas de DADO que o `conferir`
  // real ja acusa contra o arquivo do usuario — fora do escopo desta bateria.
  // Sem este seed, o registro vaza para a caixa de areia e derruba os testes
  // de reparar/conferir dos blocos seguintes, que nada tem a ver com ele.
  // Mesma razao do seed de gancho/projeto logo abaixo: e FIXTURE, nao dado.
  if (!o.id) {
    o.id = `linha-real-sem-id-${i}`;
    if (!o.titulo) o.titulo = "registro real sem titulo (seed da bateria, nao e dado real)";
    if (!o.descricao) o.descricao = "registro real sem descricao (seed da bateria, nao e dado real)";
    if (!o.status) o.status = "plantada";
    if (!o.plantada_em) {
      o.plantada_em = /^\d{4}-\d{2}-\d{2}$/.test(o.data || "") ? o.data : "2026-08-01";
    }
    e += 1; mudou = true;
  }
  if (!o.gancho) {
    o.gancho = "gancho de teste (seed da bateria, nao e dado real)";
    n += 1; mudou = true;
  }
  // Mesma razao do gancho, para o campo `projeto`: a copia e FIXTURE, nao dado.
  // Todo valor real vira o slug `sandbox` — e isso resolve tres coisas de uma
  // vez. (1) O `conferir` passou a acusar CR/LF/TAB no campo, e 4 linhas reais
  // tem esse rastro: sem o seed a bateria falharia pelo DADO do usuario e nao
  // por regressao, e teste que falha por dado ensina a ignorar teste. (2) O
  // bloco 6 precisa que a prosa a normalizar seja SO a que ele mesmo cria.
  // (3) Nome de projeto do usuario para de entrar na saida da bateria.
  // A migracao real e `normalizar-projetos`, fora daqui.
  if (o.projeto !== "sandbox") {
    o.projeto = "sandbox";
    delete o.projeto_nota;
    c += 1; mudou = true;
  }
  if (mudou) linhas[i] = JSON.stringify(o);
});
fs.writeFileSync(p, linhas.join("\n") + "\n", "utf8");
console.log(`  (seed: gancho em ${n} linha(s), projeto=sandbox em ${c}, e schema completo em ${e}, so para a bateria rodar)`);
JS

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
# Preludio dos asserts: ler o jsonl, achar linha por id, comparar data local e um
# `ok()` que fala. Vive AQUI, uma vez, em vez de repetido em 16 snippets — e e Node,
# como todo o resto do plugin. Esta bateria nao usa mais Python: o runtime ja era
# unico no caminho de execucao, e passou a ser unico no caminho de TESTE tambem, para
# que quem contribui com so Node consiga validar a propria mudanca.
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

echo "== 1. entrada invalida e recusada ANTES de tocar o arquivo =="
md5_antes=$(md5sum ideias.jsonl | cut -d' ' -f1)
# `projeto` do fixture e o mesmo slug que o bloco 6 registra: assim o vocabulario,
# quando entra em cena, ja vale para tudo que os blocos anteriores plantaram.
base='"titulo":"t","descricao":"d","contexto":"c","projeto":"sandbox"'

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
const l=O("ideias.jsonl"), o=acha(l,"teste-um");
ok(o.status==="plantada" && o.plantada_em===hoje());
ok(l.length===Number(process.env.BASE)+1);'

esperado "iniciar (plantada -> em-colheita)" 0 $IDEIAS iniciar --id teste-um --andamento "metade feita"
esperado "recusa iniciar duas vezes" 1 $IDEIAS iniciar --id teste-um
prova "iniciar grava colheita_iniciada_em e andamento" '
const l=O("ideias.jsonl"), o=acha(l,"teste-um");
ok(o.status==="em-colheita" && o.andamento==="metade feita");
ok(o.colheita_iniciada_em===hoje());'
echo '{"resultado":"entregue no teste"}' > r.json
esperado "colher" 0 bash -c '$IDEIAS colher --id teste-um < r.json'
esperado "recusa colher duas vezes" 1 bash -c '$IDEIAS colher --id teste-um < r.json'
esperado "recusa colher sem resultado" 1 bash -c 'echo "{}" | $IDEIAS colher --id teste-um'
esperado "recusa id inexistente" 1 bash -c '$IDEIAS colher --id nao-existe < r.json'

# editar: ideia muda antes de ser colhida. Sem este comando a correcao virava
# edicao a mao no jsonl, que e o que a porta unica de escrita existe para impedir.
echo "{\"id\":\"teste-editar\",\"titulo\":\"Antes\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > fe.json
esperado "plantar a que sera editada" 0 bash -c '$IDEIAS plantar < fe.json'
echo '{"titulo":"Depois","ao_colher":"passo novo"}' > ed.json
esperado "editar ideia aberta" 0 bash -c '$IDEIAS editar --id teste-editar < ed.json'
prova "editar troca so o que veio, carimba editada_em e preserva plantada_em" '
const l=O("ideias.jsonl"), o=acha(l,"teste-editar");
ok(o.titulo==="Depois" && o.ao_colher==="passo novo");
ok(o.descricao==="d" && o.contexto==="c", "campo nao enviado foi alterado");
ok(o.status==="plantada", "editar nao deve mexer no status");
ok(o.editada_em===hoje());
ok(o.plantada_em===hoje());
ok(l.length===Number(process.env.BASE)+2, "editar nao pode mudar a contagem");'
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
const l=O("ideias.jsonl"), a=acha(l,"teste-tres"), b=acha(l,"teste-dois");
ok(a.status==="unificada" && a.unificada_em_id==="teste-dois");
ok(igual(b.absorveu,["teste-tres"]) && b.titulo==="Fundida");
// base+4 e nao base+3 desde que o bloco do editar plantou teste-editar antes daqui.
ok(l.length===Number(process.env.BASE)+4);'

echo
echo "== 2.5 reparar: linha que entrou no arquivo sem passar pelo script =="
# O caso real: em 2026-08-10 uma observacao foi gravada a mao, sem status nem
# plantada_em, e so apareceu no conferir. O editar nao conserta (status e
# plantada_em sao CAMPOS_PROIBIDOS_NO_INPUT, e devem continuar sendo).
node - <<'JS'
const fs = require("fs");
fs.appendFileSync("ideias.jsonl", JSON.stringify({
  id: "teste-quebrada", titulo: "Gravada a mao", descricao: "d",
  contexto: "c", projeto: "sandbox", tipo: "observacao", gancho: "g",
}) + "\n", "utf8");
JS
esperado "conferir acusa a linha sem status" 1 $IDEIAS conferir
esperado "recusa reparar sem --id nem --todas" 1 $IDEIAS reparar
md5_pre_reparo=$(md5sum ideias.jsonl | cut -d' ' -f1)
esperado "--conferir descreve o reparo" 0 $IDEIAS reparar --todas --conferir
if [ "$md5_pre_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   --conferir nao gravou nada (md5 igual)"
else falhou=$((falhou+1)); echo "  FALHA --conferir escreveu no arquivo"; fi

# A sandbox nao e repo git: data_do_git devolve None, que e exatamente a
# condicao em que carimbar hoje seria inventar historia.
#
# Ate 2026-08-12 a varredura ABORTAVA aqui, e com isso nao consertava mais nada em
# nenhuma linha — `reparar --todas` estava morto desde que uma linha sem data
# existisse (Issue #3). Agora ela conserta o que infere, RELATA o que precisa de
# texto humano, e sai 1 porque reparo parcial nao e reparo pronto. O que continua
# valendo, e e o que este teste protege: a data NAO foi inventada.
# O gemeo em Python fica no contrato ANTIGO de proposito (ele existe para provar as
# oito garantias do port, nao para receber recurso novo): la a varredura recusa em
# bloco e nao grava nada. Os dois caminhos exigem a MESMA coisa no que importa — a
# data nao e inventada — e diferem no que a varredura faz com o resto.
esperado "varredura sai 1 quando ha pendencia" 1 $IDEIAS reparar --todas
case "$IDEIAS" in
  *ideias.cjs*)
    prova "nao inventou a data, e consertou o status na mesma passada" '
const o=acha(O("ideias.jsonl"),"teste-quebrada");
ok(!o.plantada_em, "carimbou data que o git nao sabia");
ok(o.status==="plantada", "deixou de consertar o status que sabia inferir");
ok(igual(o.reparo,["status"]), JSON.stringify(o.reparo));'
    saida_pend=$($IDEIAS reparar --todas 2>&1)
    if echo "$saida_pend" | grep -q "SEM plantada_em"; then
      ok=$((ok+1)); echo "  ok   e RELATOU a linha que ficou sem data"
    else
      falhou=$((falhou+1)); echo "  FALHA nao relatou a pendencia de data"; echo "$saida_pend" | sed 's/^/         /' | tail -4
    fi
    ;;
  *)
    if [ "$md5_pre_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   (gemeo) a recusa em bloco deixou o arquivo intocado"
    else falhou=$((falhou+1)); echo "  FALHA (gemeo) gravou apesar de nao saber a data"; fi
    ;;
esac

esperado "recusa --plantada-em no futuro" 1 $IDEIAS reparar --id teste-quebrada --plantada-em 2099-01-01
esperado "recusa --plantada-em fora do formato ISO" 1 $IDEIAS reparar --id teste-quebrada --plantada-em 10/08/2026
esperado "recusa --plantada-em junto de --todas" 1 $IDEIAS reparar --todas --plantada-em 2026-08-01
esperado "reparar com a data informada" 0 $IDEIAS reparar --id teste-quebrada --plantada-em 2026-08-01
prova "status inferido, data preservada, reparo deixa rastro" '
const o=acha(O("ideias.jsonl"),"teste-quebrada");
ok(o.status==="plantada", o.status);
ok(o.plantada_em==="2026-08-01", "a data informada foi trocada");
ok(o.reparada_em===hoje());
// No .cjs a varredura acima ja consertou o status, entao aqui sobra a data; no
// gemeo, que recusou em bloco, os dois campos vem juntos.
const esperado=(process.env.IDEIAS||"").includes("ideias.cjs")?["plantada_em"]:["plantada_em","status"];
ok(igual(o.reparo,esperado), JSON.stringify(o.reparo));
ok(o.titulo==="Gravada a mao" && o.tipo==="observacao", "reparo mexeu no conteudo");'
esperado "conferir volta a passar depois do reparo" 0 $IDEIAS conferir
esperado "reparar de novo nao encontra nada (idempotente)" 0 $IDEIAS reparar --todas
md5_pos_reparo=$(md5sum ideias.jsonl | cut -d' ' -f1)
esperado "reparar linha sadia nao a toca" 0 $IDEIAS reparar --id teste-editar
if [ "$md5_pos_reparo" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
then ok=$((ok+1)); echo "  ok   linha sadia ficou byte a byte igual"
else falhou=$((falhou+1)); echo "  FALHA reparou o que nao estava quebrado"; fi

# Reparo nao e conserto de valor errado: para isso existe o editar, que deixa
# rastro de decisao. Status errado (mas conhecido) nao e buraco.
node - <<'JS'
const fs = require("fs");
const p = "ideias.jsonl";
const linhas = fs.readFileSync(p, "utf8").split("\n").filter((l) => l.trim());
linhas.forEach((l, i) => {
  const o = JSON.parse(l);
  if (o.id === "teste-quebrada") { o.status = "em-colheita"; linhas[i] = JSON.stringify(o); }
});
fs.writeFileSync(p, linhas.join("\n") + "\n", "utf8");
JS
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
node - <<'JS'
const fs = require("fs");
const p = "ideias.jsonl";
const linhas = fs.readFileSync(p, "utf8").split("\n").filter((l) => l.trim());
const o = JSON.parse(linhas[linhas.length - 1]);
const d = new Date(Date.now() + 30 * 86400000);
const dp = (n) => String(n).padStart(2, "0");
o.plantada_em = `${d.getFullYear()}-${dp(d.getMonth() + 1)}-${dp(d.getDate())}`;
linhas[linhas.length - 1] = JSON.stringify(o);
fs.writeFileSync(p, linhas.join("\n") + "\n", "utf8");
JS
esperado "conferir acusa data no futuro (o bug de UTC, detectado depois do fato)" 1 $IDEIAS conferir
contem_saida() { if $IDEIAS conferir 2>&1 | grep -q "NO FUTURO"; then ok=$((ok+1)); echo "  ok   ... e diz NO FUTURO, nomeando a linha"; else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha"; fi; }
contem_saida

echo
echo "== 3. mutacao: a conferencia byte a byte trava mesmo? =="
cp ideias.jsonl pre-mutacao.jsonl
# O mutante sabota a implementacao que $IDEIAS de fato roda. O gemeo em Python
# foi aposentado em 2026-08-22 — scripts/ideias.cjs e a unica implementacao
# agora, entao o alvo nao depende mais de ramificar por $IDEIAS.
MUTANTE_ALVO="scripts/ideias.cjs"
echo "  (mutando $MUTANTE_ALVO — o que \$IDEIAS executa)"
MUTANTE_ALVO="$MUTANTE_ALVO" node - <<'JS'
const fs = require("fs");
const path = require("path");
const alvo = process.env.MUTANTE_ALVO;
const s = fs.readFileSync(alvo, "utf8");
let ancora, veneno;
if (path.extname(alvo) === ".py") {
  ancora = '    tmp = ALVO.with_suffix(".jsonl.tmp")';
  veneno = '    linhas_depois = list(linhas_depois); linhas_depois[0] = linhas_depois[0].replace("{", "{\\"MUTACAO\\": 1, ", 1)\n';
} else {
  ancora = '  const tmp = ALVO.replace(/\\.jsonl$/, ".jsonl.tmp");';
  veneno = '  linhasDepois = linhasDepois.slice(); linhasDepois[0] = linhasDepois[0].replace("{", "{\\"MUTACAO\\": 1, ");\n';
}
if (!s.includes(ancora)) throw new Error(`ancora da mutacao sumiu em ${alvo} — o teste precisa ser reajustado`);
fs.writeFileSync(alvo, s.replace(ancora, veneno + ancora), "utf8");
console.log("  (mutante instalado: corrompe a linha 1, que nunca e alvo de um plantar)");
JS
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
node - <<'JS'
const fs = require("fs");
fs.appendFileSync("ideias.jsonl", JSON.stringify({
  id: "teste-quebrada-mutante", titulo: "t", descricao: "d",
  contexto: "c", projeto: "sandbox", gancho: "g",
}) + "\n", "utf8");
JS
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
    # Caminho RELATIVO: o prova() roda node com cwd na raiz da caixa, e o node
    # daqui e o do Windows — caminho POSIX do mktemp ele nao enxerga.
    prova "gravou no .rainforest do projeto (4 linhas, com o id novo)" '
const l=L("proj/.rainforest/ideias.jsonl");
const ids=l.map((x)=>JSON.parse(x).id);
ok(ids.includes("teste-raiz-projeto"), ids.join(","));
ok(l.length===4, String(l.length));'
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
# Gancho e exigencia que nunca existiu no gemeo em Python (aposentado em
# 2026-08-22) — nasceu direto no .cjs. Mesmo padrao do bloco 4: pula quando
# $IDEIAS aponta para outra implementacao.
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
const o=acha(O("ideias.jsonl"),"teste-com-gancho");
ok(o.gancho==="revisar em 2026-09-01", o.gancho);'

    echo '{"gancho":"trocado: revisar em 2026-10-01"}' > edg.json
    esperado "editar troca o gancho de ideia aberta" 0 bash -c '$IDEIAS_LIMPO editar --id teste-com-gancho < edg.json'
    prova "gancho editado chega gravado" '
const o=acha(O("ideias.jsonl"),"teste-com-gancho");
ok(o.gancho==="trocado: revisar em 2026-10-01", o.gancho);'

    # linha gravada a mao (bypassa o script), sem gancho — o caso real das 70
    # linhas existentes que motivou a tarefa. Guarda tambem o conteudo exato de
    # OUTRA linha (nao-alvo do reparo que vem a seguir) para provar depois que
    # o reparo --gancho nao mexeu nela.
    node - <<'JS'
const fs = require("fs");
const p = "ideias.jsonl";
fs.appendFileSync(p, JSON.stringify({
  id: "teste-sem-gancho-existente", titulo: "t", descricao: "d",
  contexto: "c", projeto: "sandbox", status: "plantada", plantada_em: "2026-08-01",
}) + "\n", "utf8");
const outra = fs.readFileSync(p, "utf8").split("\n").filter((x) => x.trim())
  .find((x) => JSON.parse(x).id === "teste-com-gancho");
fs.writeFileSync("linha-outra-antes-reparo-gancho.txt", outra, "utf8");
JS
    esperado "conferir acusa a linha sem gancho" 1 $IDEIAS_LIMPO conferir
    saida_conferir_gancho=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_conferir_gancho" | grep -q "teste-sem-gancho-existente.*gancho"
    then ok=$((ok+1)); echo "  ok   ... e nomeia a linha especifica"
    else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha sem gancho"; echo "$saida_conferir_gancho" | sed 's/^/         /'; fi

    esperado "recusa --gancho sem --id (uma linha por vez, como --plantada-em)" 1 $IDEIAS_LIMPO reparar --todas --gancho "nao vale"
    esperado "reparar --gancho preenche a linha" 0 $IDEIAS_LIMPO reparar --id teste-sem-gancho-existente --gancho "revisar em 2026-11-01"
    prova "gancho reparado gravado, reparo deixa rastro" '
const o=acha(O("ideias.jsonl"),"teste-sem-gancho-existente");
ok(o.gancho==="revisar em 2026-11-01", o.gancho);
ok((o.reparo||[]).includes("gancho"), JSON.stringify(o.reparo));'
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
const outra=L("ideias.jsonl").find((x)=>JSON.parse(x).id==="teste-com-gancho");
const antes=fs.readFileSync("linha-outra-antes-reparo-gancho.txt","utf8").replace(/\n+$/,"");
ok(outra===antes, "a linha nao-alvo mudou");'

    # Gancho e gatilho de RETORNO: so ideia ABERTA precisa dele. Cobrar gatilho de
    # quem ja voltou seria ruido, e ruido ensina a ignorar o conferir. Sem este
    # teste, a regra viveria so no comentario do codigo.
    node - <<'JS'
const fs = require("fs");
fs.appendFileSync("ideias.jsonl", JSON.stringify({
  id: "teste-colhida-sem-gancho", titulo: "t", descricao: "d", contexto: "c",
  projeto: "sandbox", status: "colhida", plantada_em: "2026-08-01",
  colhida_em: "2026-08-02", resultado: "feito",
}) + "\n", "utf8");
JS
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
echo "== 6. projeto e slug de vocabulario fechado, e o caminho sai do dado =="
# O campo guardava caminho do Windows dentro de string JSON e a barra + `r` virou
# escape de CR em 4 registros. Vocabulario fechado mata a classe: slug nao tem
# barra para o escape comer. Recurso novo, so do .cjs (mesmo padrao dos blocos 4 e 5).
case "$IDEIAS" in
  *ideias.cjs*)
    export IDEIAS_LIMPO="node scripts/ideias-limpo.cjs"
    # 6a. sem projetos.json a validacao esta DESLIGADA — e se anuncia. Silencio
    # aqui faria o usuario de instalacao nova crer que o campo foi validado.
    echo "{\"id\":\"teste-sem-vocab\",$base,\"gancho\":\"g\"}" > pv0.json
    saida_sem_vocab=$($IDEIAS_LIMPO plantar < pv0.json 2>&1)
    got=$?
    esperado "sem projetos.json, plantar passa (instalacao nova nao trava)" 0 bash -c "exit $got"
    if echo "$saida_sem_vocab" | grep -q "sem projetos.json"
    then ok=$((ok+1)); echo "  ok   ... e o aviso de regra desligada aparece"
    else falhou=$((falhou+1)); echo "  FALHA validacao desligada em silencio"; echo "$saida_sem_vocab" | sed 's/^/         /'; fi

    # 6b. o vocabulario nasce pelo comando, nao a mao
    esperado "recusa slug com barra (o que causou o bug)" 1 $IDEIAS_LIMPO projetos --registrar 'C:\Projetos\x'
    # Caminho com DRIVE e barra normal: caminho POSIX absoluto ('/tmp/x') o Git
    # Bash converte antes de o node ver, e a barra invertida do Windows some dentro
    # do fixture Python — as duas coisas medem a camada de escape, nao o script.
    # (A segunda aconteceu escrevendo este teste: 'C:	mp' virou 'C:' + TAB. E o
    # mesmo defeito que o vocabulario existe para matar, uma camada acima.)
    esperado "registrar slug" 0 $IDEIAS_LIMPO projetos --registrar sandbox --caminho 'C:/tmp/sandbox'
    esperado "registrar com apelidos" 0 $IDEIAS_LIMPO projetos --registrar outro-projeto --apelido 'apelido-um,apelido-dois'
    prova "projetos.json gravado com caminho e apelidos ordenados" '
const m=JSON.parse(fs.readFileSync("projetos.json","utf8"));
ok(m.sandbox.caminho==="C:/tmp/sandbox", JSON.stringify(m.sandbox));
ok(igual(m["outro-projeto"].apelidos,["apelido-dois","apelido-um"]), JSON.stringify(m["outro-projeto"]));'

    # 6b'. remover: o vocabulario tambem erra, e slug em uso nao sai calado
    esperado "registrar o que vai ser removido" 0 $IDEIAS_LIMPO projetos --registrar slug-temporario
    esperado "remover slug sem nenhuma linha apontando" 0 $IDEIAS_LIMPO projetos --remover slug-temporario
    esperado "recusa remover slug que nao existe" 1 $IDEIAS_LIMPO projetos --remover nunca-existiu
    prova "o removido saiu do arquivo e os outros ficaram" '
const m=JSON.parse(fs.readFileSync("projetos.json","utf8"));
ok(!("slug-temporario" in m), JSON.stringify(Object.keys(m)));
ok("sandbox" in m && "outro-projeto" in m, JSON.stringify(Object.keys(m)));'

    # 6c. com vocabulario, prosa e recusada ANTES de tocar o arquivo
    md5_vocab=$(md5sum ideias.jsonl | cut -d' ' -f1)
    echo "{\"id\":\"teste-prosa\",\"titulo\":\"t\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox (pasta de teste)\",\"gancho\":\"g\"}" > pv1.json
    esperado "recusa projeto em prosa quando ha vocabulario" 1 bash -c '$IDEIAS_LIMPO plantar < pv1.json'
    saida_prosa=$($IDEIAS_LIMPO plantar < pv1.json 2>&1)
    if echo "$saida_prosa" | grep -q "Quis dizer 'sandbox'"
    then ok=$((ok+1)); echo "  ok   ... e sugere o slug certo em vez de so recusar"
    else falhou=$((falhou+1)); echo "  FALHA recusou sem sugerir o slug"; echo "$saida_prosa" | sed 's/^/         /'; fi
    echo "{\"id\":\"teste-slug-novo\",\"titulo\":\"t\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"nao-registrado\",\"gancho\":\"g\"}" > pv2.json
    esperado "recusa slug fora do vocabulario" 1 bash -c '$IDEIAS_LIMPO plantar < pv2.json'
    if [ "$md5_vocab" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   arquivo intocado apos as recusas de vocabulario"
    else falhou=$((falhou+1)); echo "  FALHA recusa de vocabulario alterou o arquivo"; fi
    esperado "aceita slug do vocabulario" 0 bash -c 'echo "{\"id\":\"teste-slug-ok\",\"titulo\":\"t\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" | $IDEIAS_LIMPO plantar'

    # 6d. a migracao: prosa vira slug, ensaio nao grava, sobra vira projeto_nota
    node - <<'JS'
const fs = require("fs");
const novas = [
  { id: "teste-migra-simples", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox (C:/tmp/sandbox)", status: "plantada",
    plantada_em: "2026-08-01", gancho: "g" },
  { id: "teste-migra-com-nota", titulo: "t", descricao: "d", contexto: "c",
    projeto: "apelido-um (~/outro) - branch teste-de-branch", status: "plantada",
    plantada_em: "2026-08-01", gancho: "g" },
  { id: "teste-migra-so-caminho", titulo: "t", descricao: "d", contexto: "c",
    projeto: "C:\\Projetos\\sandbox", status: "plantada",
    plantada_em: "2026-08-01", gancho: "g" },
  { id: "teste-migra-perdida", titulo: "t", descricao: "d", contexto: "c",
    projeto: "projeto-que-ninguem-registrou", status: "plantada",
    plantada_em: "2026-08-01", gancho: "g" },
];
fs.appendFileSync("ideias.jsonl", novas.map((o) => JSON.stringify(o) + "\n").join(""), "utf8");
JS
    md5_pre_migra=$(md5sum ideias.jsonl | cut -d' ' -f1)
    esperado "migracao recusa quando uma linha nao resolve (parcial esconde o resto)" 1 $IDEIAS_LIMPO normalizar-projetos --aplicar
    if [ "$md5_pre_migra" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   arquivo intocado apos a recusa da migracao"
    else falhou=$((falhou+1)); echo "  FALHA a migracao gravou apesar da linha sem resolucao"; fi
    saida_pend=$($IDEIAS_LIMPO normalizar-projetos --aplicar 2>&1)
    if echo "$saida_pend" | grep -q "teste-migra-perdida"
    then ok=$((ok+1)); echo "  ok   ... e nomeia a linha que nao resolveu"
    else falhou=$((falhou+1)); echo "  FALHA nao nomeou a linha sem resolucao"; echo "$saida_pend" | sed 's/^/         /'; fi

    esperado "ensaio (sem --aplicar) nao grava" 0 $IDEIAS_LIMPO normalizar-projetos --mapear teste-migra-perdida=sandbox
    if [ "$md5_pre_migra" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   ensaio deixou o arquivo byte a byte igual"
    else falhou=$((falhou+1)); echo "  FALHA o ensaio gravou"; fi

    node -e "
const fs=require('fs');
const alvo=fs.readFileSync('ideias.jsonl','utf8').split('\n').filter((x)=>x.trim())
  .find((x)=>JSON.parse(x).id==='teste-slug-ok');
fs.writeFileSync('linha-nao-alvo-antes-migra.txt', alvo, 'utf8');
"
    esperado "migracao com --mapear e --aplicar" 0 $IDEIAS_LIMPO normalizar-projetos --mapear teste-migra-perdida=sandbox --aplicar
    prova "prosa virou slug, sobra virou projeto_nota, caminho puro nao virou nota" '
const d={}; for (const o of O("ideias.jsonl")) d[o.id]=o;
ok(d["teste-migra-simples"].projeto==="sandbox", JSON.stringify(d["teste-migra-simples"]));
ok(!("projeto_nota" in d["teste-migra-simples"]), "caminho entre parenteses nao devia sobrar");
ok(d["teste-migra-com-nota"].projeto==="outro-projeto", JSON.stringify(d["teste-migra-com-nota"]));
ok(d["teste-migra-com-nota"].projeto_nota.includes("branch teste-de-branch"));
ok(!d["teste-migra-com-nota"].projeto_nota.includes("~/outro"), "caminho ficou na nota");
ok(d["teste-migra-so-caminho"].projeto==="sandbox", JSON.stringify(d["teste-migra-so-caminho"]));
ok(!("projeto_nota" in d["teste-migra-so-caminho"]), "valor que era SO caminho nao vira nota");
ok(d["teste-migra-perdida"].projeto==="sandbox", JSON.stringify(d["teste-migra-perdida"]));'
    prova "migracao nao mexeu em linha nao-alvo (byte a byte)" '
const agora=L("ideias.jsonl").find((x)=>JSON.parse(x).id==="teste-slug-ok");
const antes=fs.readFileSync("linha-nao-alvo-antes-migra.txt","utf8").replace(/\n+$/,"");
ok(agora===antes, "a linha nao-alvo mudou");'
    md5_pos_migra=$(md5sum ideias.jsonl | cut -d' ' -f1)
    esperado "segunda passada e inocua (idempotente)" 0 $IDEIAS_LIMPO normalizar-projetos --aplicar
    if [ "$md5_pos_migra" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   nada mudou na segunda passada"
    else falhou=$((falhou+1)); echo "  FALHA a segunda passada reescreveu o arquivo"; fi

    # 6e. conferir passa a enxergar os dois defeitos, e o listar passa a agrupar
    node - <<'JS'
const fs = require("fs");
fs.appendFileSync("ideias.jsonl", JSON.stringify({
  id: "teste-projeto-com-cr", titulo: "t", descricao: "d", contexto: "c",
  projeto: "C:\\Projetos\rainforest",
  status: "plantada", plantada_em: "2026-08-01", gancho: "g",
}) + "\n", "utf8");
JS
    saida_conf_proj=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_conf_proj" | grep -q "teste-projeto-com-cr.*caractere de controle"
    then ok=$((ok+1)); echo "  ok   conferir acusa caractere de controle no projeto"
    else falhou=$((falhou+1)); echo "  FALHA conferir nao viu o CR no projeto"; echo "$saida_conf_proj" | sed 's/^/         /'; fi

    esperado "recusa remover slug que ainda e o projeto de alguma linha" 1 $IDEIAS_LIMPO projetos --remover sandbox
    saida_remover=$($IDEIAS_LIMPO projetos --remover sandbox 2>&1)
    if echo "$saida_remover" | grep -q "linha(s)"
    then ok=$((ok+1)); echo "  ok   ... e diz quantas linhas o impedem"
    else falhou=$((falhou+1)); echo "  FALHA recusou sem dizer quem usa o slug"; echo "$saida_remover" | sed 's/^/         /'; fi

    esperado "listar --projeto filtra por slug" 0 $IDEIAS_LIMPO listar --status todos --tipo todos --projeto outro-projeto
    saida_filtro=$($IDEIAS_LIMPO listar --status todos --tipo todos --projeto outro-projeto 2>&1)
    if echo "$saida_filtro" | grep -q "teste-migra-com-nota" &&
       ! echo "$saida_filtro" | grep -q "teste-migra-simples"
    then ok=$((ok+1)); echo "  ok   ... e leva so o que e do projeto pedido"
    else falhou=$((falhou+1)); echo "  FALHA o filtro por projeto nao separou"; echo "$saida_filtro" | sed 's/^/         /'; fi
    esperado "recusa filtrar por slug inexistente (lista vazia enganaria)" 1 $IDEIAS_LIMPO listar --projeto nao-existe
    ;;
  *)
    echo "  (pulado: vocabulario de projeto e recurso novo so do .cjs)"
    ;;
esac

echo
echo "== 7. divida HERDADA nao derruba o gate, e problema NOVO derruba (Issue #3) =="
# `gancho` virou obrigatorio em 81b125e (11/08) sem backfill: o `conferir` ficou
# vermelho com 35 linhas antigas, nenhuma delas causada pela sessao que rodava o
# comando. Gate sempre vermelho nao e gate — ensina a ignorar. A anistia e por DATA
# declarada em constante, e a divida continua impressa.
case "$IDEIAS" in
  *ideias.cjs*)
    # RAIZ PROPRIA para este bloco. Os blocos 2.5, 3 e 6 deixam destrocos de
    # proposito na caixa (data no futuro, linha sem status, CR no projeto), e a
    # afirmacao daqui e "SO divida herdada" — medida em cima de arquivo sujo, ela
    # nao mede nada. Cada teste tem o direito de declarar o estado inicial dele.
    export IDEIAS_LIMPO="node scripts/ideias-limpo.cjs"
    mkdir -p "$SB/b7"
    head -3 ideias.jsonl > "$SB/b7/ideias.jsonl"
    B7="env RFM_ROOT=$(cygpath -m "$SB/b7" 2>/dev/null || printf '%s' "$SB/b7") node scripts/ideias-limpo.cjs"
    node - <<'JS'
const fs = require("fs");
const novas = [
  // anterior ao corte: divida herdada, nao bloqueia
  { id: "teste-herdada-sem-gancho", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox", status: "plantada", plantada_em: "2026-08-06" },
  // NO dia do corte: `plantada_em` tem granularidade de dia e a regra entrou no
  // meio dele, entao nao da para provar que nasceu depois — anistiada tambem
  { id: "teste-no-dia-do-corte", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox", status: "plantada", plantada_em: "2026-08-11" },
  // colhida sem gancho: nao entra em conta nenhuma (ja voltou)
  { id: "teste-colhida-sem-gancho-7", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox", status: "colhida", plantada_em: "2026-08-01",
    colhida_em: "2026-08-02", resultado: "feito" },
];
fs.appendFileSync("b7/ideias.jsonl", novas.map((o) => JSON.stringify(o) + "\n").join(""), "utf8");
JS
    esperado "so divida herdada: o gate fica VERDE" 0 $B7 conferir
    saida_h=$($B7 conferir 2>&1)
    if echo "$saida_h" | grep -q "teste-herdada-sem-gancho"; then
      ok=$((ok+1)); echo "  ok   ... e a divida herdada continua IMPRESSA (anistia nao esconde)"
    else
      falhou=$((falhou+1)); echo "  FALHA anistiou e escondeu a divida"; echo "$saida_h" | sed 's/^/         /' | tail -5
    fi
    if echo "$saida_h" | grep -q "teste-no-dia-do-corte"; then
      ok=$((ok+1)); echo "  ok   ... o dia do corte entra na anistia (dia nao discrimina)"
    else
      falhou=$((falhou+1)); echo "  FALHA a linha do dia do corte ficou fora da anistia"
    fi
    if echo "$saida_h" | grep -q "teste-colhida-sem-gancho-7"; then
      falhou=$((falhou+1)); echo "  FALHA cobrou gancho de ideia colhida"
    else
      ok=$((ok+1)); echo "  ok   colhida sem gancho nao entra em nenhum dos dois blocos"
    fi
    # P2: cada contagem diz de que conjunto saiu.
    if echo "$saida_h" | grep -qE "[0-9]+ de [0-9]+ abertas"; then
      ok=$((ok+1)); echo "  ok   a contagem declara o universo (N de M abertas)"
    else
      falhou=$((falhou+1)); echo "  FALHA contagem sem universo declarado"
    fi

    # Problema NOVO: depois do corte, sem gancho -> BLOQUEIA. Sem isto a anistia
    # teria desligado a regra em vez de datar a divida.
    node - <<'JS'
const fs = require("fs");
const novas = [
  { id: "teste-nova-sem-gancho", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox", status: "plantada", plantada_em: "2026-08-12" },
  // sem data NENHUMA: ausencia de prova nao e prova, entao bloqueia
  { id: "teste-sem-data-sem-gancho", titulo: "t", descricao: "d", contexto: "c",
    projeto: "sandbox", status: "plantada" },
];
fs.appendFileSync("b7/ideias.jsonl", novas.map((o) => JSON.stringify(o) + "\n").join(""), "utf8");
JS
    esperado "linha NOVA sem gancho derruba o gate" 1 $B7 conferir
    saida_n=$($B7 conferir 2>&1)
    if echo "$saida_n" | sed -n '/BLOQUEIAM/,$p' | grep -q "teste-nova-sem-gancho"; then
      ok=$((ok+1)); echo "  ok   ... e ela aparece no bloco que BLOQUEIA"
    else
      falhou=$((falhou+1)); echo "  FALHA a linha nova nao foi para o bloco bloqueante"
    fi
    if echo "$saida_n" | sed -n '/BLOQUEIAM/,$p' | grep -q "teste-sem-data-sem-gancho"; then
      ok=$((ok+1)); echo "  ok   linha SEM data bloqueia (ausencia de prova nao anistia)"
    else
      falhou=$((falhou+1)); echo "  FALHA linha sem data foi anistiada"
    fi

    # MUTACAO: com o corte no futuro, TODA linha e herdada e o gate volta a passar.
    # E o que prova que a constante governa o veredito, e nao o acaso do fixture.
    node - <<'JS'
const fs = require("fs");
const p = "scripts/ideias-limpo.cjs";
const t = fs.readFileSync(p, "utf8");
const de = 'const GANCHO_EXIGIDO_DESDE = "2026-08-11"';
if (!t.includes(de)) throw new Error("constante da anistia nao encontrada");
fs.writeFileSync(p, t.replace(de, 'const GANCHO_EXIGIDO_DESDE = "2099-01-01"'), "utf8");
JS
    # O exit code nao serve de sinal aqui: `teste-sem-data-sem-gancho` bloqueia com
    # qualquer corte (sem data, sem anistia). O que a mutacao tem que mostrar e a
    # RECLASSIFICACAO: a linha nova sai do bloco que bloqueia e vira divida herdada.
    if $B7 conferir 2>&1 | sed -n '/HERDADA/,/BLOQUEIAM/p' | grep -q "teste-nova-sem-gancho"; then
      ok=$((ok+1)); echo "  ok   com o corte em 2099 a linha nova vira herdada (a constante governa)"
    else
      falhou=$((falhou+1)); echo "  FALHA mover a constante nao mudou a classificacao"
    fi
    node - <<'JS'
const fs = require("fs");
const p = "scripts/ideias-limpo.cjs";
const t = fs.readFileSync(p, "utf8");
fs.writeFileSync(p, t.replace('const GANCHO_EXIGIDO_DESDE = "2099-01-01"',
                              'const GANCHO_EXIGIDO_DESDE = "2026-08-11"'), "utf8");
JS
    esperado "restaurada a constante, o gate volta a acusar" 1 $B7 conferir

    # O `reparar --todas` estava MORTO: abortava na primeira linha sem gancho, e
    # com isso nao consertava `status` de nenhuma outra.
    node - <<'JS'
const fs = require("fs");
fs.appendFileSync("b7/ideias.jsonl", JSON.stringify({
  id: "teste-sem-status-7", titulo: "t", descricao: "d",
  contexto: "c", projeto: "sandbox", plantada_em: "2026-08-05", gancho: "g",
}) + "\n", "utf8");
JS
    esperado "varredura NAO aborta por gancho ausente (sai 1, mas trabalha)" 1 $B7 reparar --todas
    prova "consertou o status da outra linha na mesma passada" '
const o=acha(O("b7/ideias.jsonl"),"teste-sem-status-7");
ok(o.status==="plantada", JSON.stringify(o));'
    prova "e NAO carimbou reparada_em em quem nao foi reparado" '
const o=acha(O("b7/ideias.jsonl"),"teste-herdada-sem-gancho");
ok(!("reparada_em" in o), JSON.stringify(o));'
    saida_r=$($B7 reparar --todas 2>&1)
    if echo "$saida_r" | grep -q "ficaram SEM gancho"; then
      ok=$((ok+1)); echo "  ok   a varredura RELATA o que precisa de texto humano"
    else
      falhou=$((falhou+1)); echo "  FALHA varredura silenciou as pendencias de gancho"
    fi
    esperado "mas --id explicito sem --gancho continua recusando" 1 \
      $B7 reparar --id teste-herdada-sem-gancho
    # E o universo tambem aparece no reparar (era 72 contra 35 do conferir).
    if $B7 reparar --todas --conferir 2>&1 | grep -qE "[0-9]+ de [0-9]+ abertas sem gancho"; then
      ok=$((ok+1)); echo "  ok   o reparar declara o mesmo universo do conferir"
    else
      falhou=$((falhou+1)); echo "  FALHA reparar conta sem dizer o conjunto"
    fi
    ;;
  *)
    echo "  (pulado: anistia por data e recurso novo so do .cjs)"
    ;;
esac

echo
echo "== 8. descartar: a ideia que NAO vai acontecer sai da lista sem virar colhida =="
# O buraco que este bloco fecha: o usuario pediu "remove essa ideia" em 2026-08-12 e
# nao havia como. `colher` significa ENTREGUE — usar para descarte infla a contagem
# de colhidas com uma nao-entrega. E editar o jsonl a mao e o que a porta unica de
# escrita existe para impedir. Descartada tambem nao e apagada: a linha fica.
case "$IDEIAS" in
  *ideias.cjs*)
    export IDEIAS_LIMPO="node scripts/ideias-limpo.cjs"
    echo "{\"id\":\"teste-descartar\",$base,\"gancho\":\"g\"}" > fd.json
    esperado "plantar a que sera descartada" 0 bash -c '$IDEIAS_LIMPO plantar < fd.json'
    md5_pre_desc=$(md5sum ideias.jsonl | cut -d' ' -f1)
    esperado "recusa descartar sem --motivo" 2 $IDEIAS_LIMPO descartar --id teste-descartar
    esperado "recusa descartar com motivo vazio" 1 $IDEIAS_LIMPO descartar --id teste-descartar --motivo "   "
    if [ "$md5_pre_desc" = "$(md5sum ideias.jsonl | cut -d' ' -f1)" ]
    then ok=$((ok+1)); echo "  ok   arquivo intocado apos as recusas"
    else falhou=$((falhou+1)); echo "  FALHA recusa de descarte alterou o arquivo"; fi

    esperado "descartar com motivo" 0 $IDEIAS_LIMPO descartar --id teste-descartar --motivo "nao vale o custo: o book-to-skill ja resolve"
    prova "status, data e motivo gravados — e a linha CONTINUA no arquivo" '
const l=O("ideias.jsonl"), o=acha(l,"teste-descartar");
ok(o.status==="descartada", o.status);
ok(o.descartada_em===hoje(), o.descartada_em);
ok(o.motivo.includes("book-to-skill"), o.motivo);
ok(o.titulo==="t" && o.contexto==="c", "descartar mexeu no conteudo");'
    esperado "recusa descartar duas vezes (fechado nao se descarta)" 1       $IDEIAS_LIMPO descartar --id teste-descartar --motivo "de novo"
    esperado "recusa descartar o que ja foi colhido" 1       $IDEIAS_LIMPO descartar --id teste-um --motivo "colhida nao se descarta"

    # A descartada nao e ABERTA: o conferir nao cobra gancho dela, e ela sai da lista
    # de plantadas sem entrar na de colhidas — que era o ponto todo.
    saida_desc=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_desc" | grep -q "teste-descartar.*gancho"
    then falhou=$((falhou+1)); echo "  FALHA cobrou gancho de ideia descartada"
    else ok=$((ok+1)); echo "  ok   descartada nao e cobrada por gancho (nao e aberta)"; fi
    prova "nao entrou na conta de colhidas" '
const l=O("ideias.jsonl"), o=acha(l,"teste-descartar");
ok(!o.colhida_em && !o.resultado, "descarte virou colheita");'
    if $IDEIAS_LIMPO listar --status descartada --tipo todos 2>&1 | grep -q "teste-descartar"
    then ok=$((ok+1)); echo "  ok   listar --status descartada a mostra"
    else falhou=$((falhou+1)); echo "  FALHA a descartada nao aparece no listar"; fi

    # MUTACAO do proprio contrato: descartada SEM motivo tem que derrubar o conferir.
    # E o motivo que separa "decidido" de "esquecido" — sem ele a ideia volta igual.
    node - <<'JS'
const fs = require("fs");
fs.appendFileSync("ideias.jsonl", JSON.stringify({
  id: "teste-descartada-sem-motivo", titulo: "t", descricao: "d", contexto: "c",
  projeto: "sandbox", status: "descartada", plantada_em: "2026-08-01",
  descartada_em: "2026-08-02",
}) + "\n", "utf8");
JS
    esperado "conferir derruba descartada SEM motivo" 1 $IDEIAS_LIMPO conferir
    saida_sem_motivo=$($IDEIAS_LIMPO conferir 2>&1)
    if echo "$saida_sem_motivo" | sed -n '/BLOQUEIAM/,$p' | grep -q "teste-descartada-sem-motivo.*sem motivo"
    then ok=$((ok+1)); echo "  ok   ... e nomeia a linha, no bloco que bloqueia"
    else falhou=$((falhou+1)); echo "  FALHA nao acusou a descartada sem motivo"; fi
    # E o reparar sabe inferir o status de uma linha com descartada_em.
    esperado "reparar infere status descartada de quem tem descartada_em" 1       $IDEIAS_LIMPO reparar --todas
    ;;
  *)
    echo "  (pulado: descartada e status novo, so do .cjs)"
    ;;
esac

echo
echo "== 9. defeito A: parseLinhas tolera a ULTIMA linha invalida, recusa a do meio nomeando onde =="
# Usa a copia LIMPA (scripts/ideias-limpo.cjs): o bloco 3 deixou o mutante
# instalado em scripts/ideias.cjs de proposito, e este bloco nao tem nada a
# ver com aquele teste.
cp ideias.jsonl pre-defeito-a.jsonl
n_base=$(node -e "process.stdout.write(String(require('fs').readFileSync('pre-defeito-a.jsonl','utf8').split('\n').filter((l)=>l.trim()).length))")

# ultima linha truncada, SEM newline final — o caso real de escrita em
# andamento (outra sessao no meio do fs.writeFileSync).
printf '{"id":"truncada-em-andamento","titulo":"me' >> ideias.jsonl
esperado "ultima linha truncada e TOLERADA (listar segue funcionando)" 0 $IDEIAS_LIMPO listar --status todos --tipo todos
saida_tol=$($IDEIAS_LIMPO listar --status todos --tipo todos 2>&1)
if echo "$saida_tol" | grep -qE "^${n_base} no total"
then ok=$((ok+1)); echo "  ok   a linha truncada NAO entrou na contagem ($n_base no total) — ignorada, nao lancada"
else falhou=$((falhou+1)); echo "  FALHA contagem nao bate com $n_base"; echo "$saida_tol" | sed 's/^/         /' | tail -3; fi
cp pre-defeito-a.jsonl ideias.jsonl

# linha do MEIO corrompida — continua erro, agora nomeando linha, arquivo e
# o trecho ofensor (o erro de antes dizia so "para sempre", sem dizer onde).
node - <<'JS'
const fs = require("fs");
const linhas = fs.readFileSync("ideias.jsonl", "utf8").split("\n").filter((l) => l.trim());
const meio = Math.floor(linhas.length / 2);
linhas.splice(meio, 0, '{"id":"corrompida-no-meio-do-arquivo", quebrada de proposito');
fs.writeFileSync("ideias.jsonl", linhas.join("\n") + "\n", "utf8");
fs.writeFileSync("linha-do-meio.txt", String(meio + 1), "utf8");
JS
linha_meio=$(cat linha-do-meio.txt)
esperado "linha do MEIO corrompida continua erro" 1 $IDEIAS_LIMPO listar --status todos --tipo todos
saida_meio=$($IDEIAS_LIMPO listar --status todos --tipo todos 2>&1)
if echo "$saida_meio" | grep -q "linha $linha_meio "
then ok=$((ok+1)); echo "  ok   a mensagem nomeia o numero da linha ($linha_meio)"
else falhou=$((falhou+1)); echo "  FALHA a mensagem nao nomeou a linha $linha_meio"; echo "$saida_meio" | sed 's/^/         /'; fi
if echo "$saida_meio" | grep -q "ideias.jsonl"
then ok=$((ok+1)); echo "  ok   a mensagem nomeia o caminho do arquivo"
else falhou=$((falhou+1)); echo "  FALHA a mensagem nao nomeou o arquivo"; echo "$saida_meio" | sed 's/^/         /'; fi
if echo "$saida_meio" | grep -q "corrompida-no-meio-do-arquivo"
then ok=$((ok+1)); echo "  ok   a mensagem traz o trecho ofensor"
else falhou=$((falhou+1)); echo "  FALHA a mensagem nao trouxe o trecho ofensor"; echo "$saida_meio" | sed 's/^/         /'; fi
cp pre-defeito-a.jsonl ideias.jsonl
rm -f linha-do-meio.txt pre-defeito-a.jsonl

echo
echo "== 10. defeito B: a trava so morre com PROVA de que o dono morreu =="
cat > teste-defeito-b.js <<'JS'
const { Trava } = require("./hooks/lib/trava-jsonl.cjs");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

function falha(msg) { console.error("FALHA: " + msg); process.exit(1); }

// 1) dono VIVO (esta propria sessao node), lock envelhecido de proposito para
// alem dos 120s — prova que a IDADE sozinha nao derruba mais o lock.
const lockViva = path.resolve("trava-teste-viva.lock");
fs.writeFileSync(lockViva, `${process.pid} ${new Date().toISOString()}\n`, "utf8");
const bemVelho = new Date(Date.now() - 200 * 1000);
fs.utimesSync(lockViva, bemVelho, bemVelho);

const t1 = new Trava(lockViva, 0.5); // espera curta so para o teste nao travar
let roubou = false;
try {
  t1.entrar();
  roubou = true;
} catch (e) {
  if (!/outra sessao/.test(e.message)) falha("erro inesperado no dono vivo: " + e.message);
}
if (roubou) { fs.unlinkSync(lockViva); falha("lock de dono VIVO foi roubado mesmo com 200s de idade"); }
if (!fs.existsSync(lockViva)) falha("lock de dono vivo desapareceu sem ter sido roubado por este teste");
fs.unlinkSync(lockViva);
console.log("ok-dono-vivo-preservado");

// 2) dono MORTO — pid de um processo ja encerrado, lock FRESCO (idade bem
// menor que 120s), para provar que quem derruba e a PROVA de morte, nunca a
// idade sozinha.
const filho = spawnSync(process.execPath, ["-e", "process.exit(0)"]);
const pidMorto = filho.pid;
const lockMorta = path.resolve("trava-teste-morta.lock");
fs.writeFileSync(lockMorta, `${pidMorto} ${new Date().toISOString()}\n`, "utf8");
const t2 = new Trava(lockMorta, 5);
t2.entrar(); // nao pode lancar — recupera o lock do pid morto mesmo fresco
t2.sair();
if (fs.existsSync(lockMorta)) falha("lock de dono morto nao foi liberado apos sair()");
console.log("ok-dono-morto-recuperado");
JS
saida_b=$(node teste-defeito-b.js 2>&1); got_b=$?
if [ "$got_b" = 0 ] && echo "$saida_b" | grep -q "ok-dono-vivo-preservado" && echo "$saida_b" | grep -q "ok-dono-morto-recuperado"
then
  ok=$((ok+2))
  echo "  ok   trava de dono VIVO nao e roubada mesmo passando dos 120s"
  echo "  ok   trava de PID morto e recuperada mesmo com lock fresco (idade nao e o criterio)"
else
  falhou=$((falhou+1)); echo "  FALHA defeito B (exit $got_b):"; echo "$saida_b" | sed 's/^/         /'
fi
rm -f teste-defeito-b.js trava-teste-viva.lock trava-teste-morta.lock

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
