#!/bin/bash
# Bateria de vigias/fila-de-repos.jsonl, lida por vigias/dados-batedor-repos.js.
# Uso: bash scripts/testa-fila-de-repos.sh
#
# Tarefa 1 do plano docs/rainforest/planos/2026-08-25-regua-do-batedor-enxertar.md
# (D4, D5 do design 2026-08-25-regua-do-batedor-enxertar.md).
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR: entrada sem `trilha` (ou com trilha
# fora do vocabulario fechado instalar|enxertar|ler) virar 'instalar' por
# default silencioso. O default natural seria esse — e' a regua de hoje —, e
# assumi-lo devolveria o desenho ao ponto de partida EM SILENCIO, justamente
# para as entradas que ninguem revisou (D5). Sem o bloco 1 abaixo, os demais
# blocos provariam so que o caminho feliz funciona.
#
# Toda fixture nasce em mktemp -d e morre no trap: esta bateria NUNCA toca a
# raiz de dados do usuario nem o vigias/fila-de-repos.jsonl real do repo.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALVO_REL="vigias/dados-batedor-repos.js"
[ -f "$RAIZ/$ALVO_REL" ] || { echo "FALHA: nao achei $RAIZ/$ALVO_REL"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT

# O alvo faz `require('../hooks/lib/raiz.cjs')` desde a #110 — a caixa precisa
# da dependencia junto, senao o node morre em "Cannot find module" e as
# asserçoes seguintes falham por JSON vazio, escondendo a causa real.
mkdir -p "$S/vigias" "$S/hooks/lib"
cp "$RAIZ/$ALVO_REL" "$S/vigias/dados-batedor-repos.js"
cp "$RAIZ/hooks/lib/raiz.cjs" "$S/hooks/lib/raiz.cjs"
export RFM_ROOT="$W"

fila() { # escreve a fila da caixa a partir do stdin (heredoc de quem chama)
  cat > "$S/vigias/fila-de-repos.jsonl"
}

rodar() { # roda o script contra a caixa e grava saida em $S/saida.json / .err
  node "$S/vigias/dados-batedor-repos.js" --json > "$S/saida.json" 2>"$S/saida.err"
  echo $?
}

PRELUDIO='const fs=require("fs");
const D=JSON.parse(fs.readFileSync(process.env.SAIDA,"utf8"));
const F=D.fila_de_repos;
const ok=(c,m)=>{if(!c)throw new Error(m||"assert falhou");};
'
export SAIDA="$S/saida.json"

prova() { # nome, script node que lanca Error se falhar (le $SAIDA via PRELUDIO)
  local nome="$1"; shift
  if node -e "$PRELUDIO$1" >/dev/null 2>&1; then
    ok=$((ok+1)); echo "  ok   $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome"
    node -e "$PRELUDIO$1" 2>&1 | grep -v "^ *at \|^Node.js v" | tail -6 | sed 's/^/         /'
  fi
}

echo "== 1. entrada sem trilha e recusada e nao vira instalar (fixture do plano) =="
# A fixture exata do criterio de sucesso: uma 'instalar', uma sem trilha e uma
# com trilha fora do vocabulario ('comprar').
fila <<'JSONL'
{"candidato": "repo-instalavel", "ancora": "resolve o problema ancorado A", "trilha": "instalar", "plantada_em": "2026-08-01"}
{"candidato": "repo-sem-trilha", "ancora": "resolve o problema ancorado B"}
{"candidato": "repo-trilha-invalida", "ancora": "resolve o problema ancorado C", "trilha": "comprar"}
JSONL
exit_1="$(rodar)"
if [ "$exit_1" = "0" ]; then ok=$((ok+1)); echo "  ok   script sai 0 mesmo com recusas (recusa e' por entrada, nao aborta a leitura)"
else falhou=$((falhou+1)); echo "  FALHA script saiu $exit_1"; cat "$S/saida.err" | sed 's/^/         /'; fi

prova "exatamente 1 utilizavel e 2 recusadas" '
ok(F.utilizaveis.length===1, "utilizaveis: "+F.utilizaveis.length);
ok(F.recusados.length===2, "recusados: "+F.recusados.length);'

prova "a utilizavel e' o repo-instalavel, com a trilha instalar" '
ok(F.utilizaveis[0].candidato==="repo-instalavel");
ok(F.utilizaveis[0].trilha==="instalar", F.utilizaveis[0].trilha);'

prova "as duas recusas nomeiam o candidato certo" '
const nomes=F.recusados.map((r)=>r.candidato);
ok(nomes.includes("repo-sem-trilha"), JSON.stringify(nomes));
ok(nomes.includes("repo-trilha-invalida"), JSON.stringify(nomes));'

prova "a recusa de repo-sem-trilha nomeia o que falta (o campo trilha)" '
const r=F.recusados.find((x)=>x.candidato==="repo-sem-trilha");
ok(r && /trilha/.test(r.motivo), JSON.stringify(r));'

prova "a recusa de repo-trilha-invalida nomeia o valor invalido" '
const r=F.recusados.find((x)=>x.candidato==="repo-trilha-invalida");
ok(r && r.motivo.includes("comprar"), JSON.stringify(r));'

# O ponto central do criterio de sucesso: a saida nao contem "instalar" para
# NENHUMA das duas recusadas — nem no --json nem no texto (D5). Sem este
# bloco, um default silencioso de 'instalar' escrito so no motivo passaria.
prova "a saida NAO contem a string 'instalar' em nenhuma das duas recusadas (JSON)" '
for (const r of F.recusados) {
  ok(!JSON.stringify(r).includes("instalar"), "recusa contaminada: "+JSON.stringify(r));
}'

saida_texto=$(node "$S/vigias/dados-batedor-repos.js" 2>&1)
echo "$saida_texto" > "$S/saida-texto.txt"
if echo "$saida_texto" | grep -q "RECUSADO repo-sem-trilha.*instalar"; then
  falhou=$((falhou+1)); echo "  FALHA a linha de recusa de repo-sem-trilha (texto) cita 'instalar'"
else ok=$((ok+1)); echo "  ok   a linha de recusa de repo-sem-trilha (texto) nao cita 'instalar'"
fi
if echo "$saida_texto" | grep -q "RECUSADO repo-trilha-invalida.*instalar"; then
  falhou=$((falhou+1)); echo "  FALHA a linha de recusa de repo-trilha-invalida (texto) cita 'instalar'"
else ok=$((ok+1)); echo "  ok   a linha de recusa de repo-trilha-invalida (texto) nao cita 'instalar'"
fi

echo
echo "== 2. as tres trilhas do vocabulario fechado passam =="
fila <<'JSONL'
{"candidato": "repo-instalar", "ancora": "ancora A", "trilha": "instalar"}
{"candidato": "repo-enxertar", "ancora": "ancora B", "trilha": "enxertar"}
{"candidato": "repo-ler", "ancora": "ancora C", "trilha": "ler"}
JSONL
rodar >/dev/null
prova "as tres entram como utilizaveis, cada uma com a trilha certa" '
ok(F.utilizaveis.length===3, "utilizaveis: "+F.utilizaveis.length);
ok(F.recusados.length===0, "recusados: "+F.recusados.length);
const porNome={}; for (const u of F.utilizaveis) porNome[u.candidato]=u.trilha;
ok(porNome["repo-instalar"]==="instalar");
ok(porNome["repo-enxertar"]==="enxertar");
ok(porNome["repo-ler"]==="ler");'

echo
echo "== 3. recusa e' por ENTRADA: JSON invalido numa linha nao derruba as outras =="
fila <<'JSONL'
{"candidato": "repo-ok-antes", "ancora": "ancora A", "trilha": "instalar"}
{isto nao e json valido}
{"candidato": "repo-ok-depois", "ancora": "ancora B", "trilha": "ler"}
JSONL
exit_3="$(rodar)"
if [ "$exit_3" = "0" ]; then ok=$((ok+1)); echo "  ok   script sai 0 mesmo com uma linha de JSON invalido"
else falhou=$((falhou+1)); echo "  FALHA script saiu $exit_3"; cat "$S/saida.err" | sed 's/^/         /'; fi
prova "as duas linhas validas passam, e a invalida vira 1 recusa nomeada" '
ok(F.utilizaveis.length===2, "utilizaveis: "+F.utilizaveis.length);
ok(F.recusados.length===1, "recusados: "+F.recusados.length);
const nomesUtil=F.utilizaveis.map((u)=>u.candidato);
ok(nomesUtil.includes("repo-ok-antes"), JSON.stringify(nomesUtil));
ok(nomesUtil.includes("repo-ok-depois"), JSON.stringify(nomesUtil));
ok(/JSON invalido/.test(F.recusados[0].motivo), JSON.stringify(F.recusados[0]));'

echo
echo "== 4. linha em branco e ignorada (nao conta como entrada nem recusa) =="
fila <<'JSONL'
{"candidato": "repo-unico", "ancora": "ancora A", "trilha": "instalar"}

JSONL
rodar >/dev/null
prova "so a linha real conta; a linha em branco nao vira recusa" '
ok(F.utilizaveis.length===1, "utilizaveis: "+F.utilizaveis.length);
ok(F.recusados.length===0, "recusados: "+F.recusados.length);'

echo
echo "== 5. fila ausente nao derruba o resto do apurador =="
rm -f "$S/vigias/fila-de-repos.jsonl"
exit_5="$(rodar)"
if [ "$exit_5" = "0" ]; then ok=$((ok+1)); echo "  ok   script sai 0 sem o arquivo da fila"
else falhou=$((falhou+1)); echo "  FALHA script saiu $exit_5 sem o arquivo da fila"; cat "$S/saida.err" | sed 's/^/         /'; fi
prova "fila vazia: zero utilizaveis, zero recusadas" '
ok(F.utilizaveis.length===0, "utilizaveis: "+F.utilizaveis.length);
ok(F.recusados.length===0, "recusados: "+F.recusados.length);'


echo
echo "== 6. a fila e CONTEUDO DO REPO: acha-se mesmo com RFM_ROOT em outro lugar =="
# Os cinco blocos acima nao distinguem as duas raizes, e nao e defeito deles: a
# caixa de areia serve de RFM_ROOT E de pasta do plugin ao mesmo tempo, entao
# ROOT e PLUGIN coincidem e qualquer uma das duas passa.
#
# So que em producao elas NAO coincidem, e medido em 2026-08-25 a fila nao era
# lida em nenhuma das duas invocacoes reais:
#   RFM_ROOT=~/.rainforest -> procurava em ~/.rainforest/vigias/ -> nao existe
#   sem RFM_ROOT           -> ROOT cravado no repo PRINCIPAL     -> worktree invisivel
# Nas duas, "0 utilizavel(is), 0 recusada(s)" com o arquivo em disco ao lado.
#
# Este bloco e o unico que separa as duas: a fila fica ao lado do script, e o
# RFM_ROOT aponta para uma pasta VAZIA. Quem le por ROOT acha zero; quem le pelo
# PLUGIN acha a entrada.
OUTRA="$(mktemp -d)"
OUTRA_W="$(cygpath -m "$OUTRA" 2>/dev/null || printf '%s' "$OUTRA")"
fila <<'JSONL'
{"candidato": "repo-ao-lado-do-script", "ancora": "prova que a fila e conteudo do repo", "trilha": "enxertar", "plantada_em": "2026-08-25"}
JSONL
RFM_ROOT="$OUTRA_W" node "$S/vigias/dados-batedor-repos.js" --json > "$S/saida.json" 2>"$S/saida.err"
rm -rf "$OUTRA"

prova "com RFM_ROOT em pasta vazia, a fila ao lado do script continua sendo lida" '
ok(F.utilizaveis.length===1, "utilizaveis: "+F.utilizaveis.length+" (0 = leu pelo RFM_ROOT, nao pela pasta do plugin)");
ok(F.utilizaveis[0].candidato==="repo-ao-lado-do-script", F.utilizaveis[0].candidato);
ok(F.utilizaveis[0].trilha==="enxertar", F.utilizaveis[0].trilha);'

echo
echo "== 7. SEM RFM_ROOT: o caminho default e o de PRODUCAO, e nao era testado =="
# Os 16 casos acima fazem `export RFM_ROOT="$W"` no topo do arquivo, entao NENHUM
# deles exercita o fallback. E o fallback e justamente a condicao real: a tarefa
# agendada chama `run-vigia.ps1` sem definir RFM_ROOT, e o `run-vigia.ps1` so LE a
# variavel, nunca a define para o node filho.
#
# O que essa cegueira deixou passar, em 2026-08-25: o literal do caminho cravado
# perdeu as barras escapadas numa reescrita. Em JS `\P` nao e escape e a barra
# SOME; `\r` E escape e vira carriage-return. `C:\Projetos\rainforest-mind` virou
# `C:Projetos<CR>ainforest-mind`, o `fs.readFileSync` passou a lancar, o `catch`
# silencioso devolveu [], e ideias/propostas/erros passaram a reportar ZERO com
# exit 0. A ancora inteira da ronda morreu calada, e as 16 assercoes seguiram
# verdes porque nenhuma roda sem a variavel.
#
# Este caso roda com `env -u RFM_ROOT` e prova que o default resolve para a pasta
# ACIMA do script — nao para um literal, que e o que nao ha mais como escapar errado.
mkdir -p "$S/relatorios"
cat > "$S/ideias.jsonl" <<'JSONL'
{"id":"prova-do-fallback","titulo":"ideia so para provar que o default acha o arquivo","status":"plantada","projeto":"rainforest-mind","tipo":"ideia","plantada_em":"2026-08-25"}
JSONL
fila <<'JSONL'
{"candidato": "repo-do-fallback", "ancora": "prova o caminho default", "trilha": "ler", "plantada_em": "2026-08-25"}
JSONL
# HOME/USERPROFILE apontam para uma pasta VAZIA da caixa. Sem isso, a cadeia de
# raizes (RFM_ROOT > <projeto>/.rainforest > ~/.rainforest > plugin) resolve no
# nivel 3 e o caso passa a ler o `~/.rainforest` REAL do usuario — a bateria
# escaparia da caixa de areia justamente no unico caso que roda sem RFM_ROOT,
# e o contrato do topo deste arquivo diz que ela NUNCA toca a maquina do usuario.
# Com o home vazio, a cadeia cai no nivel 4 (o plugin, que aqui e a caixa) e o
# `ideias.jsonl` ao lado do script volta a ser o que ela le.
mkdir -p "$S/home-vazio"
HOME="$W/home-vazio" USERPROFILE="$W/home-vazio" env -u RFM_ROOT -u CLAUDE_PROJECT_DIR node "$S/vigias/dados-batedor-repos.js" --json > "$S/saida.json" 2>"$S/saida.err"
rc_sem_root=$?
if [ "$rc_sem_root" = "0" ]; then ok=$((ok+1)); echo "  ok   roda sem RFM_ROOT sem estourar"
else falhou=$((falhou+1)); echo "  FALHA saiu $rc_sem_root sem RFM_ROOT"; sed 's/^/         /' "$S/saida.err"; fi

prova "sem RFM_ROOT, o ideias.jsonl ao lado do script E lido (o default nao esta quebrado)" '
ok(D.ideias.length===1, "ideias: "+D.ideias.length+" (0 = o caminho default nao resolve; foi assim que a ancora morreu calada em 2026-08-25)");
ok(D.ideias[0].id==="prova-do-fallback", D.ideias[0].id);'

prova "sem RFM_ROOT, a fila tambem continua sendo lida" '
ok(F.utilizaveis.length===1, "utilizaveis: "+F.utilizaveis.length);
ok(F.utilizaveis[0].trilha==="ler", F.utilizaveis[0].trilha);'
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
