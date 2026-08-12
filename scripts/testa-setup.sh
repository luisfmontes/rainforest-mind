#!/bin/bash
# Bateria do scripts/setup.cjs — o que o SETUP passou a fazer em 2026-08-12, a
# pedido do usuario: configurar CAMINHO de projeto, e ligar/desligar os vigias para
# nao dar erro em quem nao os tem. Uso: bash scripts/testa-setup.sh
#
# Caixa de areia com RFM_ROOT proprio: nada aqui toca a pasta de dados real.
# O bloco 4 e o que importa mais: prova que o `run-vigia.ps1` PARA no toggle, e
# para limpo (exit 0, sem escrever em ERROS.md) — desligado nao e erro.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"
DADOS_WIN="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
PROJ="$CAIXA/projeto-de-teste"; mkdir -p "$PROJ"
PROJ_WIN="$(cygpath -m "$PROJ" 2>/dev/null || printf '%s' "$PROJ")"
export RFM_ROOT="$DADOS_WIN"
export CLAUDE_PROJECT_DIR="$PROJ_WIN"
SETUP="node $SRC/scripts/setup.cjs"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; "$@" 2>&1 | sed 's/^/         /' | tail -6; fi
}
nao_contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then falhou=$((falhou+1)); echo "  FALHA $nome: achei '$txt' e nao devia"
  else ok=$((ok+1)); echo "  ok   $nome"; fi
}

echo "== 1. --criar semeia o vocabulario, e nao sobrescreve na segunda vez =="
# A primeira criacao e a que anuncia; a segunda TEM de dizer que nao sobrescreveu.
saida_criar=$($SETUP --criar 2>&1); got=$?
esperado "criar" 0 bash -c "exit $got"
if echo "$saida_criar" | grep -q "projetos.json (solta"; then
  ok=$((ok+1)); echo "  ok   ... e diz que semeou o projetos.json"
else
  falhou=$((falhou+1)); echo "  FALHA nao anunciou a semente"; echo "$saida_criar" | sed 's/^/         /' | head -4
fi
contem "segunda passada nao sobrescreve" "nada foi sobrescrito" $SETUP --criar
if [ -s "$DADOS/projetos.json" ]; then ok=$((ok+1)); echo "  ok   projetos.json existe"
else falhou=$((falhou+1)); echo "  FALHA projetos.json nao foi criado"; fi
# Caminho em forma WINDOWS: o python daqui e o do Windows e nao enxerga o
# `/c/Users/...` do Git Bash. Terceira vez que este detalhe morde neste repo.
if python -c "
import json
m=json.load(open('$DADOS_WIN/projetos.json',encoding='utf-8'))
assert 'solta' in m, m
assert 'projeto-de-teste' in m, m
assert m['projeto-de-teste']['caminho'], m
" 2>/dev/null; then ok=$((ok+1)); echo "  ok   nasce com solta + o slug da pasta atual"
else falhou=$((falhou+1)); echo "  FALHA a semente do projetos.json nao tem solta + a pasta"; fi

echo
echo "== 2. caminho de projeto e assunto do setup =="
esperado "registrar projeto novo" 0 $SETUP --projeto outro-repo --caminho "$PROJ_WIN"
contem "  ... aparece no estado, com o caminho" "outro-repo" $SETUP
esperado "registrar com apelidos" 0 $SETUP --projeto com-apelido --apelido "um,dois"
contem "  ... e os apelidos aparecem" "apelidos: dois, um" $SETUP
esperado "recusa slug com barra (o bug que o slug mata)" 1 $SETUP --projeto 'C:\x\y' --caminho "$PROJ_WIN"

# O aviso que nasceu de um erro real em 2026-08-12: caminho deduzido do nome, pasta
# inexistente, e o semear devolvendo vazio sem dizer por que.
contem "avisa quando o caminho NAO existe no disco" "nao existe nesta maquina" \
  $SETUP --projeto fantasma --caminho "$CAIXA/pasta-que-nunca-existiu"
contem "  ... e o estado marca a pendencia" "NAO EXISTE" $SETUP
nao_contem "  ... e nao marca quem existe" "$PROJ_WIN  <- NAO EXISTE" $SETUP

echo
echo "== 3. remover projeto, com a trava do que esta em uso =="
esperado "remover slug sem uso" 0 $SETUP --remover-projeto fantasma
esperado "recusa remover o que nao existe" 1 $SETUP --remover-projeto nunca-existiu
printf '%s\n' '{"id":"ideia-de-teste","titulo":"t","descricao":"d","contexto":"c","projeto":"outro-repo","gancho":"g","status":"plantada","plantada_em":"2026-08-01"}' > "$DADOS/ideias.jsonl"
esperado "recusa remover slug em uso por uma ideia" 1 $SETUP --remover-projeto outro-repo
contem "  ... e nomeia a ideia que o impede" "ideia-de-teste" $SETUP --remover-projeto outro-repo

echo
echo "== 4. vigias: toggle novo, e a ronda PARA nele =="
contem "vigias nasce DESLIGADO" "DESLIGADO vigias" $SETUP
esperado "--ligado vigias devolve 1 quando desligado" 1 $SETUP --ligado vigias
esperado "--ligado gate-worktree devolve 0 (ligado por padrao)" 0 $SETUP --ligado gate-worktree
esperado "--ligado de chave desconhecida devolve 2" 2 $SETUP --ligado nao-existe
esperado "ligar vigias" 0 $SETUP --ligar vigias --escopo usuario
esperado "--ligado vigias devolve 0 depois de ligado" 0 $SETUP --ligado vigias

# Config ILEGIVEL: para chave cujo ligado DISPARA acao, o lado seguro e desligado.
cp "$DADOS/config.json" "$CAIXA/config.bak"
printf '{ isto nao e json\n' > "$DADOS/config.json"
esperado "config quebrada conta como DESLIGADO (falha fecha)" 1 $SETUP --ligado vigias
cp "$CAIXA/config.bak" "$DADOS/config.json"

if command -v powershell.exe >/dev/null 2>&1; then
  # O gate de verdade, no runner real. Sem destino de envio configurado a ronda
  # falharia mais adiante — o que se prova aqui e que com o toggle DESLIGADO ela
  # nem chega la, e sai LIMPA.
  ERROS="$SRC/vigias/ERROS.md"
  antes_erros=$(wc -c < "$ERROS" 2>/dev/null || echo 0)
  $SETUP --desligar vigias --escopo usuario >/dev/null 2>&1
  saida_ps=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SRC/vigias/run-vigia.ps1" -Vigia sentinela-foco 2>&1)
  got=$?
  esperado "run-vigia.ps1 sai 0 com vigias desligado" 0 bash -c "exit $got"
  if echo "$saida_ps" | grep -q "vigias desligado"; then
    ok=$((ok+1)); echo "  ok   ... e diz como ligar, em vez de falhar"
  else
    falhou=$((falhou+1)); echo "  FALHA a ronda nao anunciou o toggle desligado"; echo "$saida_ps" | sed 's/^/         /' | tail -5
  fi
  depois_erros=$(wc -c < "$ERROS" 2>/dev/null || echo 0)
  if [ "$antes_erros" = "$depois_erros" ]; then
    ok=$((ok+1)); echo "  ok   ... e NAO escreveu em ERROS.md (desligado nao e erro)"
  else
    falhou=$((falhou+1)); echo "  FALHA desligado virou linha em ERROS.md"
  fi
else
  echo "  (pulado: powershell.exe nao esta no PATH — o gate do runner nao pode ser exercitado aqui)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
