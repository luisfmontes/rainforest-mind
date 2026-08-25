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
# Caminho em forma WINDOWS: o node daqui e o do Windows e nao enxerga o
# `/c/Users/...` do Git Bash. Terceira vez que este detalhe morde neste repo.
if node -e "
const m = require('$DADOS_WIN/projetos.json');
if (!m.solta) throw new Error('sem a entrada solta');
if (!m['projeto-de-teste']) throw new Error('sem o slug da pasta atual');
if (!m['projeto-de-teste'].caminho) throw new Error('slug da pasta sem caminho');
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
echo "== 5. PONTES: quais agentes recebem as regras (config, nao repo) =="
# "Quais agentes eu uso nesta maquina" e configuracao — e configuracao mora aqui.
# O repositorio de DESTINO nao mora aqui de proposito: ele e alvo explicito do
# `ponte.cjs`, com ensaio, porque o arquivo gerado vai ser commitado por terceiro.
contem "a secao existe" "PONTES" $SETUP
contem "  ... e diz que nao ha nenhuma ligada" "nenhuma ligada" $SETUP
esperado "ligar ponte-codex" 0 $SETUP --ligar ponte-codex --escopo usuario
contem "  ... a ligada aparece nomeando o arquivo" "AGENTS.md" $SETUP
contem "  ... e aparece o comando que gera" "ponte.cjs --alvo" $SETUP
nao_contem "  ... e a desligada nao se anuncia como ligada" "ligado    gemini" $SETUP
esperado "desligar ponte-codex" 0 $SETUP --desligar ponte-codex --escopo usuario
contem "  ... e volta a dizer que nao ha nenhuma" "nenhuma ligada" $SETUP

echo
echo "== 6. TODO arquivo que o setup semeia, o setup MOSTRA (a trava das duas portas) =="
# Este bloco existe porque o mesmo defeito aconteceu duas vezes em 2026-08-12:
# nasceu o `projetos.json`, o `--criar` aprendeu a semea-lo, e o estado nunca soube
# que ele existia — o usuario nao tinha onde ver a configuracao nova. Horas depois,
# o mesmo com a ponte. A regra ("arquivo novo nasce com tres portas: quem escreve,
# quem MOSTRA, quem checa") era uma observacao plantada, e observacao nao trava
# nada. Aqui ela vira comparacao entre o que existe no disco e o que a saida nomeia.
CAIXA6="$CAIXA/portas"; mkdir -p "$CAIXA6"
CAIXA6_WIN="$(cygpath -m "$CAIXA6" 2>/dev/null || printf '%s' "$CAIXA6")"
RFM_ROOT="$CAIXA6_WIN" node "$SRC/scripts/setup.cjs" --criar >/dev/null 2>&1
saida6=$(RFM_ROOT="$CAIXA6_WIN" node "$SRC/scripts/setup.cjs" 2>&1)
faltou6=""
for arq in $(ls "$CAIXA6"); do
  case "$arq" in .ideias-backups|.ideias.lock|*.tmp) continue ;; esac
  echo "$saida6" | grep -q -- "$arq" || faltou6="$faltou6 $arq"
done
if [ -z "$faltou6" ]; then
  ok=$((ok+1)); echo "  ok   todo arquivo semeado aparece NOMEADO no estado"
else
  falhou=$((falhou+1)); echo "  FALHA o estado nao nomeia:$faltou6 (semeou e nao mostra)"
fi
# E mostra o ESTADO de cada um, nao so o nome: ausente e vazio nao sao a mesma coisa
# que existe com conteudo.
contem "  ... com o estado de cada um (ausente/vazio/tamanho)" "(ausente)"   bash -c "RFM_ROOT='$CAIXA6_WIN' node '$SRC/scripts/setup.cjs'"

# MUTACAO: um arquivo que existe no disco e sai da lista para de ser mostrado, e o
# teste acima TEM que reprovar. Sem isto, a comparacao poderia estar passando por
# coincidencia de substring em outra parte da saida.
# O mutante mora numa ARVORE espelhada: o setup.cjs resolve as libs por
# `../hooks/lib/...`, entao copia solta nao roda (foi o segundo motivo errado pelo
# qual este teste quase passou).
MUT="$CAIXA/plugin-mutante"
mkdir -p "$MUT/scripts" "$MUT/hooks/lib"
cp "$SRC/scripts/setup.cjs" "$MUT/scripts/setup.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/projetos.cjs" "$MUT/hooks/lib/"
# Caminho por ENV, nao por interpolacao: o heredoc e quoted (nao expande $), e a
# primeira versao deste teste passou pelo motivo errado — o mutante nunca foi criado,
# o node falhou, a saida nao continha "projetos.json" e o assert deu verde. Falso
# verde e o defeito que este repo persegue; ele apareceu aqui dentro.
MUTANTE="$MUT/scripts/setup.cjs" node - <<'JS'
const fs = require("fs");
const alvo = process.env.MUTANTE;
const t = fs.readFileSync(alvo, "utf8");
const de = "  {\n    nome: 'projetos.json',";
if (!t.includes(de)) throw new Error("entrada do projetos.json nao encontrada para mutar");
fs.writeFileSync(alvo, t.replace(de, "  {\n    nome: 'projetos-MUTADO.json',"), "utf8");
console.log("mutante escrito");
JS
if [ $? != 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui escrever o mutante"; fi
saida_mut=$(RFM_ROOT="$CAIXA6_WIN" node "$MUT/scripts/setup.cjs" 2>&1)
# O mutante tem que ter RODADO: mutante que quebra tambem "nao imprime o arquivo",
# e ai a mutacao provaria nada. Duas condicoes, nao uma.
if ! echo "$saida_mut" | grep -q "PASTA DE DADOS"; then
  falhou=$((falhou+1)); echo "  FALHA o mutante nao rodou (a mutacao nao provaria nada)"; echo "$saida_mut" | sed 's/^/         /' | tail -4
elif echo "$saida_mut" | grep -q "projetos.json"; then
  falhou=$((falhou+1)); echo "  FALHA a mutacao nao mudou a saida (a lista nao governa o que e mostrado)"
else
  ok=$((ok+1)); echo "  ok   tirando o arquivo da lista, ele DESAPARECE do estado (a lista e load-bearing)"
fi

echo
echo "== 7. versionar: transforma raiz em repositorio git =="
CAIXA7="$CAIXA/versionamento"; mkdir -p "$CAIXA7"
CAIXA7_WIN="$(cygpath -m "$CAIXA7" 2>/dev/null || printf '%s' "$CAIXA7")"
export RFM_ROOT="$CAIXA7_WIN"
# A pasta de dados tem que existir para versionar
$SETUP --criar >/dev/null 2>&1

# Faz backup ANTES de versionar para provar que o .gitignore cobre backups
# Este é exatamente o padrão que causava o vazamento (Achado 1): backup + versionar.
node "$SRC/scripts/memoria.cjs" backup >/dev/null 2>&1

esperado "versionar em pasta que ja tem setup" 0 $SETUP versionar
if [ -d "$CAIXA7/.git" ]; then ok=$((ok+1)); echo "  ok   criou .git"
else falhou=$((falhou+1)); echo "  FALHA nao criou .git"; fi

if [ -f "$CAIXA7/.gitignore" ]; then ok=$((ok+1)); echo "  ok   criou .gitignore"
else falhou=$((falhou+1)); echo "  FALHA nao criou .gitignore"; fi

if grep -q "rainforest.db" "$CAIXA7/.gitignore"; then
  ok=$((ok+1)); echo "  ok   .gitignore menciona rainforest.db"
else
  falhou=$((falhou+1)); echo "  FALHA .gitignore nao menciona rainforest.db"; cat "$CAIXA7/.gitignore" | sed 's/^/         /'
fi

# Verifica que NENHUM arquivo .db e rastreado (esta e a prova real, nao apenas texto)
db_files=$(git -C "$CAIXA7" ls-files | grep -E '\.db' | tr '\n' ' ')
if [ -z "$db_files" ]; then
  ok=$((ok+1)); echo "  ok   nenhum arquivo .db e rastreado (banco + backups ignorados)"
else
  falhou=$((falhou+1)); echo "  FALHA arquivos .db foram rastreados: $db_files"
fi

# git status --short deve estar vazio logo apos versionar
saida_status=$(git -C "$CAIXA7" status --short 2>&1); got=$?
if [ "$got" = 0 ] && [ -z "$saida_status" ]; then
  ok=$((ok+1)); echo "  ok   git status --short fica vazio apos versionar"
else
  falhou=$((falhou+1)); echo "  FALHA git status --short nao ficou vazio"; echo "       $saida_status" | sed 's/^/       /'
fi

# Idempotencia: rodar de novo nao quebra
esperado "versionar (segunda vez) e idempotente" 0 $SETUP versionar
saida_status2=$(git -C "$CAIXA7" status --short 2>&1); got2=$?
if [ "$got2" = 0 ] && [ -z "$saida_status2" ]; then
  ok=$((ok+1)); echo "  ok   git status --short continua vazio apos segunda passada"
else
  falhou=$((falhou+1)); echo "  FALHA segunda passada quebrou o estado"; echo "       $saida_status2" | sed 's/^/       /'
fi

# Nome de arquivo que SEPARA `execFileSync` de `execSync` interpolado — e, medido
# em 2026-08-25, o UNICO que separa. Issue #100.
#
# O conserto trocou `execSync(\`git rm --cached "${arquivo}"\`)` por
# `execFileSync('git', ['rm', '--cached', arquivo])`. Para o teste provar a troca, o
# nome precisa ser um que o SHELL estrague e o argv nao. No Windows `execSync` roda
# pelo `cmd.exe`, e la dentro:
#   - espaco, `&` e `$( )` sao TODOS protegidos pelas aspas duplas -> NAO separam;
#   - `%VAR%` e expandido MESMO dentro das aspas -> separa.
# Com o mutante, `git rm --cached "rainforest.db%PATH%"` vira o PATH inteiro
# expandido, o git erra, o erro morre no `catch` do bloco, e o arquivo CONTINUA
# rastreado. Com `execFileSync` o nome chega literal e o arquivo sai.
#
# O `add -f` nao e detalhe: `versionar` ja escreveu `rainforest.db*` no .gitignore,
# entao `git add` sem `-f` recusa o arquivo em SILENCIO — e o teste ficaria verde
# nos dois lados sem nunca ter rastreado nada. Foi assim que a primeira tentativa
# deste caso nasceu vazia. Dai a checagem de cenario montado abaixo ser um FALHA e
# nao um skip: teste que nao montou o cenario nao esta testando.
CAIXA7c="$CAIXA/versionamento-nome-shell"; mkdir -p "$CAIXA7c"
CAIXA7c_WIN="$(cygpath -m "$CAIXA7c" 2>/dev/null || printf '%s' "$CAIXA7c")"
export RFM_ROOT="$CAIXA7c_WIN"
$SETUP versionar >/dev/null 2>&1
NOME_SHELL='rainforest.db%PATH%'
: > "$CAIXA7c/$NOME_SHELL"
git -C "$CAIXA7c" add -f "$NOME_SHELL" >/dev/null 2>&1
git -C "$CAIXA7c" -c user.email=t@t -c user.name=t commit -m "rastreia nome com %VAR%" >/dev/null 2>&1
if [ -z "$(git -C "$CAIXA7c" ls-files | grep -F "$NOME_SHELL")" ]; then
  falhou=$((falhou+1)); echo "  FALHA cenario nao montou: '$NOME_SHELL' nunca foi rastreado (faltou add -f?)"
else
  $SETUP versionar >/dev/null 2>&1
  if [ -z "$(git -C "$CAIXA7c" ls-files | grep -F "$NOME_SHELL")" ]; then
    ok=$((ok+1)); echo "  ok   nome com %VAR% e desrastreado (execFileSync nao passa pelo shell)"
  else
    falhou=$((falhou+1)); echo "  FALHA '$NOME_SHELL' continua rastreado — o nome foi pelo shell"
  fi
fi
export RFM_ROOT="$CAIXA7_WIN"

# MUTACAO: verifica que o padrão antigo causaria o vazamento (prova inversa)
CAIXA7m="$CAIXA/versionamento-mutante"; mkdir -p "$CAIXA7m/.rainforest-backups"
CAIXA7m_WIN="$(cygpath -m "$CAIXA7m" 2>/dev/null || printf '%s' "$CAIXA7m")"
cd "$CAIXA7m"
git init >/dev/null 2>&1
# Cria arquivos de dados
touch rainforest.db ".rainforest-backups/rainforest-2026-08-19T14-14-14.db"
# Padrão ANTIGO (só rainforest.db*)
echo "rainforest.db*" > .gitignore
git add -A >/dev/null 2>&1
db_files_mut=$(git ls-files | grep -E '\.db' | tr '\n' ' ')
cd "$SRC"
if [ -n "$db_files_mut" ]; then
  ok=$((ok+1)); echo "  ok   MUTACAO: padrão antigo deixaria backups rastreados ($db_files_mut)"
else
  falhou=$((falhou+1)); echo "  FALHA MUTACAO: padrão antigo nao causou vazamento conforme esperado"
fi

# .gitignore nao sobrescreve se ja existe
CAIXA7b="$CAIXA/versionamento-b"; mkdir -p "$CAIXA7b"
CAIXA7b_WIN="$(cygpath -m "$CAIXA7b" 2>/dev/null || printf '%s' "$CAIXA7b")"
export RFM_ROOT="$CAIXA7b_WIN"
$SETUP --criar >/dev/null 2>&1
# Escreve conteudo customizado no .gitignore
echo "# Custom comment" > "$CAIXA7b/.gitignore"
echo "rainforest.db*" >> "$CAIXA7b/.gitignore"
$SETUP versionar >/dev/null 2>&1
# Checa que o custom comment continua (nao foi sobrescrito)
if grep -q "Custom comment" "$CAIXA7b/.gitignore"; then
  ok=$((ok+1)); echo "  ok   .gitignore pre-existente nao e sobrescrito"
else
  falhou=$((falhou+1)); echo "  FALHA .gitignore foi sobrescrito"; cat "$CAIXA7b/.gitignore" | sed 's/^/         /'
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
