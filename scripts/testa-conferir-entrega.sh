#!/bin/bash
# Bateria do conferir-entrega. Monta um repo git de verdade com worktree de
# verdade e ENCENA cada uma das seis falhas dos dois relatorios, exigindo que
# cada uma reprove. Uso: bash scripts/testa-conferir-entrega.sh
#
# Por que encenar em vez de simular saida: o script existe justamente porque
# relato nao e evidencia. Testa-lo com git falso repetiria o erro que ele
# conserta (regra 12).
#
# Roda contra o .cjs por padrao (o que as regras 11 e 12 chamam) e contra o gemeo
# em Python por escolha:
#   CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh
# E isso que prova que o port nao perdeu checagem — mesmo desenho de testa-ideias.sh.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFERIR="${CONFERIR:-node scripts/conferir-entrega.cjs}"
# O comando vem como string com espaco ("node scripts/x.cjs"): parte em palavras
# uma vez aqui, em vez de deixar cada chamada lidar com isso.
read -r -a CONF_CMD <<< "$CONFERIR"
CONF_CMD[1]="$SRC/${CONF_CMD[1]}"
echo "(alvo: ${CONF_CMD[*]})"
RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | tail -12
  fi
}
contem() { # nome, texto, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -qi -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}

# ---------------------------------------------------------------- cenario
novo_repo() { # $1 = nome
  local R="$RAIZ/$1"
  git init -q "$R"
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  echo v1 > "$R/a.txt"; git -C "$R" add .; git -C "$R" commit -qm base
  echo v1 > "$R/rastreado.txt"; git -C "$R" add .; git -C "$R" commit -qm segundo
  echo "$R"
}

R=$(novo_repo principal)
BASE=$(git -C "$R" rev-parse HEAD)
HEAD_ANTES=$BASE
WT="$RAIZ/wt-bom"
git -C "$R" worktree add -q -b trabalho "$WT" >/dev/null 2>&1
echo novo > "$WT/feito.txt"; git -C "$WT" add .; git -C "$WT" commit -qm "entrega"

echo "== entrega correta =="
esperado "worktree real, base certa, tudo limpo -> aprovado" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"

echo
echo "== as seis falhas dos relatorios =="

# 1 — trabalhou no diretorio principal em vez do worktree
esperado "agente no repo principal (nao e worktree linkado)" 1 \
  "${CONF_CMD[@]}" --worktree "$R" --base "$BASE" --head-antes "$HEAD_ANTES"
contem "  ... e diz que faltou 'worktrees' no git-dir" "worktrees" \
  "${CONF_CMD[@]}" --worktree "$R" --base "$BASE"

# 2 — commit sobre base errada
OUTRA=$(git -C "$R" rev-parse HEAD~1)
WT2="$RAIZ/wt-base-errada"
git -C "$R" worktree add -q -b desviada "$WT2" "$OUTRA" >/dev/null 2>&1
echo x > "$WT2/x.txt"; git -C "$WT2" add .; git -C "$WT2" commit -qm "sobre base velha"
esperado "commit fora da historia da base do briefing" 1 \
  "${CONF_CMD[@]}" --worktree "$WT2" --base "$BASE"
contem "  ... e recusa a auto-absolvicao" "conclusao da janela principal" \
  "${CONF_CMD[@]}" --worktree "$WT2" --base "$BASE"

# 3 — sujeira nao commitada
echo sujo > "$WT/solto.txt"
esperado "entrega com arquivo nao commitado" 1 "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE"
esperado "  ... dispensavel por --permite-sujeira" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --permite-sujeira
rm "$WT/solto.txt"

# 4 — arquivo rastreado apagado (N3)
rm "$WT/rastreado.txt"
esperado "arquivo rastreado apagado como dano colateral" 1 "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE"
contem "  ... nomeando a falha N3" "N3" "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE"
git -C "$WT" checkout -q -- rastreado.txt

# 5 — mexeu no diretorio principal (N1)
# Captura porcelain ANTES (deve estar vazio neste ponto)
PORCELAIN_ANTES_5="$RAIZ/porcelain-antes-5.txt"
git -C "$R" status --porcelain > "$PORCELAIN_ANTES_5"
echo intruso > "$R/intruso.txt"
esperado "alteracao no diretorio principal do usuario" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --sujo-antes "$PORCELAIN_ANTES_5"
rm "$R/intruso.txt"

# 6 — HEAD do principal movido (N1, o stash/pop)
git -C "$R" checkout -q HEAD~1
esperado "HEAD do repo principal movido durante a tarefa" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
git -C "$R" checkout -q "$HEAD_ANTES"

# 6b — HEAD do principal AVANCOU no caminho DEFAULT, sem --paralelo. Buraco de
# cobertura achado por revisao independente em 2026-08-15: a logica de
# ancestralidade do .cjs (por volta das linhas 345-365) decide "avancou vira
# aviso, recuou ou lateral vira falha" e NAO e condicionada por a.paralelo —
# ela vale sempre, inclusive aqui no caminho default. Antes deste caso, o
# unico exercicio do caminho default com HEAD movido era o caso 6 acima, que e
# recuo; e o unico exercicio do ramo "avancou" era o caso `a` la embaixo, que
# so roda com --paralelo. Alguem podia trocar o merge-base --is-ancestor por
# uma comparacao de identidade pura (== em vez de ancestral) e a bateria
# inteira continuava verde, porque nenhum caso sem --paralelo jamais avancava
# o HEAD do principal para testar esse ramo especifico.
git -C "$R" commit -q --allow-empty -m "avanco no caminho default"
esperado "caminho default (sem --paralelo): HEAD do principal avancou -> aprovado com aviso" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
contem "  ... e o aviso menciona o avanco mesmo sem --paralelo" "avancou" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
git -C "$R" reset -q --hard "$HEAD_ANTES"

echo
echo "== checagem 6: o arquivo esta no COMMIT, nao no disco (Issue #4) =="
# Encena o defeito EXATO: .gitignore com '*' dentro do proprio diretorio ignora
# a si mesmo, o `git add -A` nunca o adiciona, e ele nunca chega ao commit.
# `ls`/`cat` mostram o arquivo; `git status --porcelain` nao mostra nada.
mkdir -p "$WT/gerado"
printf '*\n' > "$WT/gerado/.gitignore"
git -C "$WT" add -A >/dev/null 2>&1; git -C "$WT" commit -qm "vendoriza (gitignore some)" 2>/dev/null || true

esperado "  o worktree parece LIMPO mesmo com o arquivo faltando no commit" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
esperado "arquivo prometido que nunca entrou no commit -> reprova" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --espera "gerado/.gitignore"
contem "  ... e nomeia a regra de ignore que o comeu" "gitignore o excluiu" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --espera "gerado/.gitignore"
contem "  ... e diz que ls/cat provam o disco, nunca o commit" "provam o disco" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --espera "gerado/.gitignore"

esperado "arquivo que nunca foi criado -> reprova por outro motivo" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --espera "nunca-existiu.txt"
contem "  ... dizendo que nem no disco esta" "nao existe no disco" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --espera "nunca-existiu.txt"

esperado "arquivo realmente commitado -> aprova" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --espera "feito.txt"
esperado "  --espera repetivel: dois caminhos, um quebrado, reprova" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --espera "feito.txt" --espera "gerado/.gitignore"

# MUTACAO: com o idioma correto (`*` + `!.gitignore`) o arquivo entra no commit
# e a MESMA checagem tem que aprovar — senao ela reprova tudo e nao prova nada.
printf '*\n!.gitignore\n' > "$WT/gerado/.gitignore"
git -C "$WT" add -A >/dev/null 2>&1; git -C "$WT" commit -qm "corrige o idioma do gitignore" >/dev/null 2>&1
esperado "  MUTACAO: corrigido o idioma, a mesma checagem aprova" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --espera "gerado/.gitignore"

echo
echo "== bordas =="
esperado "worktree inexistente -> exit 2, nao 0" 2 \
  "${CONF_CMD[@]}" --worktree "$RAIZ/nao-existe" --base "$BASE"
esperado "sem --base ainda roda, com aviso" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --head-antes "$HEAD_ANTES"
contem "  ... e o aviso diz que o briefing devia ter fixado a base" "briefing devia ter fixado" \
  "${CONF_CMD[@]}" --worktree "$WT" --head-antes "$HEAD_ANTES"

echo
echo "== --paralelo: checagem 5 vira ancestralidade, checagem 4 vira cruzamento =="

# a — HEAD do principal avancou (commit novo na mesma linha) + --paralelo -> aviso, exit 0
git -C "$R" commit -q --allow-empty -m "avanco depois do despacho"
esperado "paralelo: HEAD do principal avancou -> aprovado com aviso" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
contem "  ... e o aviso menciona o avanco" "avancou" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
git -C "$R" reset -q --hard "$HEAD_ANTES"

# b — HEAD do principal recuou + --paralelo -> continua reprovado (avanco != qualquer movimento)
git -C "$R" checkout -q HEAD~1
esperado "paralelo: HEAD do principal recuou -> reprovado mesmo assim" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
git -C "$R" checkout -q "$HEAD_ANTES"

# c — sujeira no principal fora dos arquivos do agente + --paralelo -> aviso, exit 0
echo sujo > "$R/nao-tocado-pelo-agente.txt"
esperado "paralelo: sujeira no principal fora dos arquivos do agente -> aprovado com aviso" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
contem "  ... e o aviso diz que nenhuma caiu nos arquivos do agente" "nenhuma nos arquivos do agente" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
rm "$R/nao-tocado-pelo-agente.txt"

# d — sujeira no principal EM arquivo que o agente tocou (feito.txt) + --paralelo -> reprova
echo sujo > "$R/feito.txt"
esperado "paralelo: sujeira no principal em arquivo tocado pelo agente -> reprovado" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" --paralelo
rm "$R/feito.txt"

echo
echo "== o mesmo worktree escrito nas duas grafias do Windows (8.3) =="
# Achado pelo CI em 2026-08-17 (Issue #16). O TEMP do runner do GitHub e
# `C:/Users/RUNNER~1/...`; o git responde sempre na forma longa
# (`C:/Users/runneradmin/...`). O `norm()` do .cjs usava `fs.realpathSync`, que
# no Windows NAO expande 8.3 — entao as duas grafias do MESMO diretorio nao
# batiam, e a conferencia cuspia:
#
#   REPROVADO — 1 falha(s):
#     - 1. o toplevel (C:/Users/runneradmin/.../wt-bom)
#          nao e o worktree do briefing (C:/Users/RUNNER~1/.../wt-bom)
#
# Ou seja: a peca que decide se a entrega de um subagente pode ser integrada
# mandava NAO INTEGRAR uma entrega correta. O gemeo em Python nunca teve o
# defeito — `Path.resolve()` ja canoniza.
#
# O alias 8.3 nao pode ser fabricado: depende do `fsutil 8dot3name` da maquina e
# de o nome ser longo o bastante. Quando nao houver alias, este bloco ANUNCIA que
# pulou. Pular calado seria pior que nao ter o teste — leria como cobertura.
LONGA="$RAIZ/pasta-com-nome-suficientemente-longo-para-ter-alias-curto"
mkdir -p "$LONGA"
R83="$LONGA/principal"
git init -q "$R83"
git -C "$R83" config user.email t@t; git -C "$R83" config user.name t
git -C "$R83" config commit.gpgsign false
echo v1 > "$R83/a.txt"; git -C "$R83" add .; git -C "$R83" commit -qm base
BASE83=$(git -C "$R83" rev-parse HEAD)
WT83="$LONGA/wt83"
git -C "$R83" worktree add -q -b trabalho-83 "$WT83" >/dev/null 2>&1
echo novo > "$WT83/feito.txt"; git -C "$WT83" add .; git -C "$WT83" commit -qm "entrega 83"

WT83_LONGO="$(cygpath -m "$WT83" 2>/dev/null || printf '%s' "$WT83")"
WT83_CURTO="$(cygpath -m -s "$WT83" 2>/dev/null || printf '%s' "$WT83")"

if [ "$WT83_CURTO" = "$WT83_LONGO" ]; then
  echo "  PULADO sem alias 8.3 nesta maquina ($WT83_CURTO) — nao da para encenar as duas grafias."
  echo "         (nao conta como ok: o caso fica sem cobertura aqui, e o CI cobre)"
else
  echo "  (longo: $WT83_LONGO)"
  echo "  (curto: $WT83_CURTO)"
  esperado "worktree passado na forma 8.3 -> aprovado igual a forma longa" 0 \
    "${CONF_CMD[@]}" --worktree "$WT83_CURTO" --base "$BASE83"
  esperado "  ... e a forma longa segue aprovando (controle)" 0 \
    "${CONF_CMD[@]}" --worktree "$WT83_LONGO" --base "$BASE83"
fi

echo
echo "== --sujo-antes: cenario real de sujeira pre-existente =="

# Caso 1: suja o principal ANTES, captura o porcelain, agente NAO toca -> exit 0
echo intruso-pre > "$R/intruso-pre.txt"
PORCELAIN_ANTES="$RAIZ/porcelain-antes.txt"
git -C "$R" status --porcelain > "$PORCELAIN_ANTES"
# (agente nao toca em intruso-pre.txt, a worktree so toca feito.txt que ja foi commitado)
esperado "sujo-antes: sujeira pre-existente, agente nao toca -> exit 0" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --sujo-antes "$PORCELAIN_ANTES"

# Caso 2: mesma situacao, mas agente TOCA novo arquivo no principal -> exit 1 (novo)
echo novo-do-agente > "$R/novo-do-agente.txt"
esperado "sujo-antes: agente toca novo arquivo no principal -> reprova" 1 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES" \
  --sujo-antes "$PORCELAIN_ANTES"
contem "  ... dizendo que e NEW" "NEW" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --sujo-antes "$PORCELAIN_ANTES"
rm "$R/novo-do-agente.txt"

# Caso 3 (controle): mesmo cenario do caso 1 SEM --sujo-antes -> aviso, exit 0
esperado "SEM sujo-antes: sujeira pre-existente vira AVISO, nao falha" 0 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"
contem "  ... com aviso explicando que nao trava sem --sujo-antes" "nao trava" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" --head-antes "$HEAD_ANTES"

# Caso 4: arquivo inexistente em --sujo-antes -> erro de uso, exit 2
esperado "--sujo-antes inexistente -> erro de uso, exit 2" 2 \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" \
  --sujo-antes "$RAIZ/arquivo-que-nao-existe.txt"
contem "  ... mencionando arquivo inexistente" "inexistente" \
  "${CONF_CMD[@]}" --worktree "$WT" --base "$BASE" \
  --sujo-antes "$RAIZ/arquivo-que-nao-existe.txt"

rm "$R/intruso-pre.txt"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
