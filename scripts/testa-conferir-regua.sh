#!/bin/bash
# Bateria de testes para scripts/conferir-regua.cjs
# Uso: bash scripts/testa-conferir-regua.sh
#
# Monta um repositório git de verdade em sandbox, comita um manifesto de régua,
# e testa que o conferidor detecta alterações e valida o formato.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Config GLOBAL de git isolada. Os achados de log.showSignature e log.follow
# passaram por 89 casos verdes porque a bateria herdava a config de quem roda,
# e nesta maquina nenhuma das duas esta setada. Os casos que dependem de config
# a setam explicitamente, por repositorio ou por GIT_CONFIG_COUNT. A config de
# SISTEMA fica — e dela que vem o autocrlf do Git for Windows, e o caso 9 o
# fixa por repositorio de todo modo.
export GIT_CONFIG_GLOBAL="$CAIXA/gitconfig-global-vazio"
: > "$GIT_CONFIG_GLOBAL"

SCRIPT="$SRC/scripts/conferir-regua.cjs"
REPO="$CAIXA/repo"
mkdir -p "$REPO"
cd "$REPO"

# Configura git
git init
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false

# Cria estrutura de diretórios
mkdir -p docs/rainforest/reguas

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}

contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  local saida; saida=$("$@" 2>&1)
  if echo "$saida" | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: não achei '$txt'"; echo "$saida" | sed 's/^/         /' | tail -3; fi
}

# ATENCAO: nada aqui passa a saida por $(...). A substituicao de comando
# REMOVE os newlines finais antes de qualquer contagem, e era isso que fazia
# "zero byte" e "byte a byte" medirem outra coisa: um `mostrar` que imprimisse
# so um newline antes de sair 1 era contado como 0 bytes, e uma regressao que
# sumisse com o newline final do manifesto passava por identica. A saida vai
# para arquivo, e quem julga e `wc -c` / `cmp` sobre o arquivo.
stdout_para() { # arquivo, comando...
  local alvo="$1"; shift
  "$@" >"$alvo" 2>/dev/null
}

stdout_bytes() { # comando...
  local tmp="$CAIXA/stdout-$$-$RANDOM.bin"
  "$@" >"$tmp" 2>/dev/null
  wc -c < "$tmp" | tr -d " "
  rm -f "$tmp"
}

echo "== 1. manifesto editado na arvore de trabalho recusa =="
# Cria um manifesto válido
cat > docs/rainforest/reguas/teste-1.md << 'EOF'
# Régua de teste

## Freios

### M1 — Primeiro mecanismo

Descrição aqui.

### M2 — Segundo mecanismo

Descrição aqui.

### M3 — Terceiro mecanismo

Descrição aqui.

### M4 — Quarto mecanismo

Descrição aqui.

### M5 — Quinto mecanismo

Descrição aqui.
EOF

git add docs/rainforest/reguas/teste-1.md
git commit -m "Adiciona manifesto de teste"

# Agora edita
echo "MODIFICADO" >> docs/rainforest/reguas/teste-1.md
esperado "detecta edição" 1 node "$SCRIPT" conferir --slug teste-1
contem "  ... menciona o arquivo na mensagem" "teste-1.md" node "$SCRIPT" conferir --slug teste-1

echo
echo "== 2. manifesto intacto sem ## Freios recusa =="
# Desfaz a edição anterior
git checkout docs/rainforest/reguas/teste-1.md

# Cria outro manifesto sem seção Freios
cat > docs/rainforest/reguas/teste-2.md << 'EOF'
# Régua de teste

### M1 — Primeiro mecanismo
### M2 — Segundo mecanismo
### M3 — Terceiro mecanismo
### M4 — Quarto mecanismo
### M5 — Quinto mecanismo
EOF

git add docs/rainforest/reguas/teste-2.md
git commit -m "Manifesto sem Freios"

esperado "rejeita sem seção Freios" 1 node "$SCRIPT" conferir --slug teste-2
contem "  ... menciona qual regra falhou" "Freios" node "$SCRIPT" conferir --slug teste-2

echo
echo "== 3. manifesto intacto com quatro M<n> recusa =="
# Cria manifesto com só 4 mecanismos
cat > docs/rainforest/reguas/teste-3.md << 'EOF'
# Régua de teste

## Freios

### M1 — Primeiro mecanismo
### M2 — Segundo mecanismo
### M3 — Terceiro mecanismo
### M4 — Quarto mecanismo
EOF

git add docs/rainforest/reguas/teste-3.md
git commit -m "Manifesto com 4 mecanismos"

esperado "rejeita com menos de 5 mecanismos" 1 node "$SCRIPT" conferir --slug teste-3
contem "  ... menciona quantidade" "4" node "$SCRIPT" conferir --slug teste-3

echo
echo "== 4. manifesto intacto, Freios + 5-7 M<n> sequenciais passa =="
# Cria manifesto válido com 6 mecanismos
cat > docs/rainforest/reguas/teste-4.md << 'EOF'
# Régua de teste

## Freios

Teto de rodadas aqui.

### M1 — Primeiro mecanismo

Conteúdo.

### M2 — Segundo mecanismo

Conteúdo.

### M3 — Terceiro mecanismo

Conteúdo.

### M4 — Quarto mecanismo

Conteúdo.

### M5 — Quinto mecanismo

Conteúdo.

### M6 — Sexto mecanismo

Conteúdo.
EOF

git add docs/rainforest/reguas/teste-4.md
git commit -m "Manifesto válido com 6 mecanismos"

esperado "aceita 6 mecanismos com Freios" 0 node "$SCRIPT" conferir --slug teste-4

echo
echo "== 5. slug inexistente sai 2 =="
esperado "slug inexistente retorna 2" 2 node "$SCRIPT" conferir --slug nao-existe
contem "  ... mensagem de arquivo não encontrado" "não encontrado\|inexistente" node "$SCRIPT" conferir --slug nao-existe

echo
echo "== 6. mostrar com manifesto editado nao imprime nada =="
# Cria um novo manifesto válido para testar edição
cat > docs/rainforest/reguas/teste-6.md << 'EOF'
# Régua de teste

## Freios

Teto aqui.

### M1 — Mecanismo 1

Descrição.

### M2 — Mecanismo 2

Descrição.

### M3 — Mecanismo 3

Descrição.

### M4 — Mecanismo 4

Descrição.

### M5 — Mecanismo 5

Descrição.
EOF

git add docs/rainforest/reguas/teste-6.md
git commit -m "Manifesto válido teste-6"

# Edita o manifesto
echo "EDITADO" >> docs/rainforest/reguas/teste-6.md

# Verifica que sai com exit 1
esperado "detecta edição no mostrar" 1 node "$SCRIPT" mostrar --slug teste-6

# Verifica que stdout tem zero bytes
bytes=$(stdout_bytes node "$SCRIPT" mostrar --slug teste-6)
if [ "$bytes" = "0" ]; then ok=$((ok+1)); echo "  ok   stdout vazio quando editado (0 bytes)"
else falhou=$((falhou+1)); echo "  FALHA stdout vazio: esperava 0 bytes, veio $bytes"; fi

echo
echo "== 7. mostrar manifesto intacto imprime conteudo da ancora =="

# Verifica que conferir passa (sanidade check)
conf_exit=0
node "$SCRIPT" conferir --slug teste-4 >/dev/null 2>&1 || conf_exit=$?
if [ "$conf_exit" = "0" ]; then ok=$((ok+1)); echo "  ok   conferir passa (sanidade)"
else falhou=$((falhou+1)); echo "  FALHA conferir: exit $conf_exit"; fi

# Byte a byte de verdade: arquivo contra arquivo, com `cmp`. Newline final
# inclusive — era ele que $(...) apagava dos dois lados.
ancora=$(git log --diff-filter=A --format=%H -- docs/rainforest/reguas/teste-4.md | tail -1)
MSYS_NO_PATHCONV=1 git show "$ancora":docs/rainforest/reguas/teste-4.md > "$CAIXA/esperado-7.bin"
stdout_para "$CAIXA/mostrar-7.bin" node "$SCRIPT" mostrar --slug teste-4

if cmp -s "$CAIXA/esperado-7.bin" "$CAIXA/mostrar-7.bin"; then
  ok=$((ok+1)); echo "  ok   mostrar imprime conteudo byte a byte identico ao da âncora"
else
  falhou=$((falhou+1))
  echo "  FALHA mostrar: conteúdo diverge da âncora"
  echo "         esperado: $(wc -c < "$CAIXA/esperado-7.bin") bytes, mostrar: $(wc -c < "$CAIXA/mostrar-7.bin") bytes"
  cmp "$CAIXA/esperado-7.bin" "$CAIXA/mostrar-7.bin" | sed "s/^/         /"
fi

echo
echo "== 8. mostrar manifesto sem ## Freios nao imprime nada =="
# Edita teste-2 para remover Freios (já existe sem Freios, mas vamos verificar)
esperado "rejeita sem Freios no mostrar" 1 node "$SCRIPT" mostrar --slug teste-2

bytes2=$(stdout_bytes node "$SCRIPT" mostrar --slug teste-2)
if [ "$bytes2" = "0" ]; then ok=$((ok+1)); echo "  ok   stdout vazio quando sem Freios (0 bytes)"
else falhou=$((falhou+1)); echo "  FALHA stdout vazio sem Freios: esperava 0 bytes, veio $bytes2"; fi

echo
echo "== 9. manifesto recheckado com autocrlf continua intacto =="
# Cria repositório novo com autocrlf=true
REPO2="$CAIXA/repo-autocrlf"
mkdir -p "$REPO2"
cd "$REPO2"
git init
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git config core.autocrlf true
mkdir -p docs/rainforest/reguas

# Cria manifesto em LF (git sempre usa LF internamente)
cat > docs/rainforest/reguas/autocrlf-test.md << 'EOF'
# Régua com autocrlf

## Freios

Teto de rodadas.

### M1 — Mecanismo 1

Descrição.

### M2 — Mecanismo 2

Descrição.

### M3 — Mecanismo 3

Descrição.

### M4 — Mecanismo 4

Descrição.

### M5 — Mecanismo 5

Descrição.
EOF

git add docs/rainforest/reguas/autocrlf-test.md
git commit -m "Manifesto com autocrlf"

# Remove o arquivo e reconstrói do git (força CRLF em disco)
rm docs/rainforest/reguas/autocrlf-test.md
git checkout -- docs/rainforest/reguas/autocrlf-test.md

# Verifica que o disco tem CRLF
bytes_disco=$(wc -c < docs/rainforest/reguas/autocrlf-test.md)
bytes_git=$(MSYS_NO_PATHCONV=1 git show HEAD:docs/rainforest/reguas/autocrlf-test.md | wc -c)
if [ "$bytes_disco" -gt "$bytes_git" ]; then
  ok=$((ok+1)); echo "  ok   arquivo em disco tem CRLF (expandido: $bytes_disco > git: $bytes_git)"
else
  falhou=$((falhou+1)); echo "  FALHA disco não tem CRLF (disco: $bytes_disco, git: $bytes_git)";
fi

# Agora valida que conferir passa (normalizou EOL)
esperado "conferir com autocrlf passa" 0 node "$SCRIPT" conferir --slug autocrlf-test

# E validar que mostrar imprime conteudo
mostrar_bytes=$(stdout_bytes node "$SCRIPT" mostrar --slug autocrlf-test)
if [ "$mostrar_bytes" -gt 0 ]; then ok=$((ok+1)); echo "  ok   mostrar imprime com autocrlf ($mostrar_bytes bytes)"
else falhou=$((falhou+1)); echo "  FALHA mostrar não imprimiu com autocrlf"; fi

# O mostrar entrega o COMMIT, nao a arvore — e aqui os dois diferem (CRLF no
# disco, LF no git), entao este e o unico caso da bateria em que `cmp`
# distingue "imprime a ancora" de "imprime a arvore". No caso 7 os dois sao
# identicos, e um `mostrar` que lesse o disco passaria nele.
MSYS_NO_PATHCONV=1 git show HEAD:docs/rainforest/reguas/autocrlf-test.md > "$CAIXA/ancora-9.bin"
stdout_para "$CAIXA/mostrar-9.bin" node "$SCRIPT" mostrar --slug autocrlf-test
if cmp -s "$CAIXA/ancora-9.bin" "$CAIXA/mostrar-9.bin"; then
  ok=$((ok+1)); echo "  ok   mostrar entrega o commit byte a byte, nao a arvore com CRLF"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar nao e o commit: $(wc -c < "$CAIXA/mostrar-9.bin") bytes contra $(wc -c < "$CAIXA/ancora-9.bin") da ancora"
fi

cd "$REPO"

echo
echo "== 10. ambiente sai 2, veredito sai 1 =="
# Dois casos distintos, e a distincao e o ponto do A2:
#   - slug inexistente        -> 2 (uso errado)
#   - git presente, sem commit -> 1 (veredito negativo sobre o trabalho)
#   - fora de repositorio git  -> 2 (ambiente), nunca 1
esperado "arquivo inexistente sai 2" 2 node "$SCRIPT" conferir --slug totalmente-inexistente

# Manifesto valido em disco, porem NUNCA commitado: veredito negativo, exit 1.
REPO3="$CAIXA/repo-sem-commit"
mkdir -p "$REPO3/docs/rainforest/reguas"
cd "$REPO3"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/sem-commit.md
esperado "manifesto nunca commitado sai 1 (veredito, nao ambiente)" 1 node "$SCRIPT" conferir --slug sem-commit

# Ramo de AMBIENTE: manifesto em disco, mas fora de qualquer repositorio git.
# Sabotar o PATH com um `git` falso nao serve aqui: no Windows o Node resolve o
# binario por PATHEXT e ignora um `git` sem extensao num PATH estilo Unix — a
# versao anterior deste caso passava sem nunca ter usado o falso, que e
# exatamente o "verde pelo motivo errado" que esta bateria existe para impedir.
FORA="$CAIXA/fora-de-repo/docs/rainforest/reguas"
mkdir -p "$FORA"
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" "$FORA/orfa.md"
cd "$CAIXA/fora-de-repo"
saida_fora=$(node "$SCRIPT" conferir --slug orfa 2>&1); ec_fora=$?
if [ "$ec_fora" = "2" ]; then
  ok=$((ok+1)); echo "  ok   fora de repositorio git sai 2, nao 1 (exit $ec_fora)"
else
  falhou=$((falhou+1)); echo "  FALHA fora de repositorio: esperava exit 2, veio $ec_fora"
  echo "$saida_fora" | sed 's/^/         /' | tail -4
fi
if echo "$saida_fora" | grep -q "git indisponivel ou fora de repositorio"; then
  ok=$((ok+1)); echo "  ok     ... nomeia o ambiente, nao acusa adulteracao"
else
  falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeia o ambiente"
  echo "$saida_fora" | sed 's/^/         /' | tail -4
fi

# O caso 10 saiu do repositorio de proposito; volta antes de seguir, senao o
# caso seguinte roda fora de repo e reprova por 2 em vez de 1.
cd "$REPO2"

echo "== 11. manifesto com cabecalho ### M1: x recheckado com mensagem nova =="
# Cria manifesto com formato errado
cat > docs/rainforest/reguas/formato-errado.md << 'EOF'
# Régua com formato errado

## Freios

Teto.

### M1: Mecanismo com dois-pontos

Descrição.

### M2: Segundo com dois-pontos

Descrição.

### M3: Terceiro

Descrição.

### M4: Quarto

Descrição.

### M5: Quinto

Descrição.
EOF

git add docs/rainforest/reguas/formato-errado.md
git commit -m "Manifesto com formato de cabecalho errado"

esperado "rejeita cabecalho com ':' em vez de espaço" 1 node "$SCRIPT" conferir --slug formato-errado
contem "  ... mensagem menciona formato" "formato" node "$SCRIPT" conferir --slug formato-errado

echo
echo "== 12. historico ilegivel (objeto corrompido) sai 2, nao 1 =="
# O caso 10 cobre "repositorio sem commit nenhum" (veredito, 1). Este cobre o
# outro lado: o historico EXISTE e o git nao consegue le-lo. Uma sonda que so
# resolva o caminho do .git responde 0 aqui e classifica corrupcao como
# "nunca commitado" — foi o achado B1.
REPO4="$CAIXA/repo-corrompido"
mkdir -p "$REPO4/docs/rainforest/reguas"
cd "$REPO4"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/corrompido.md
git add -A >/dev/null 2>&1
git commit -q -m "manifesto" >/dev/null 2>&1
SHA_HEAD=$(git rev-parse HEAD)
OBJ=".git/objects/${SHA_HEAD:0:2}/${SHA_HEAD:2}"
if [ -f "$OBJ" ]; then
  # Objeto solto nasce read-only (444): sem remover antes, o redirecionamento
  # falha com "Permission denied" e o caso mede o repositorio INTACTO.
  rm -f "$OBJ"
  echo "lixo que nao e um objeto git" > "$OBJ"
  if git cat-file -t HEAD >/dev/null 2>&1; then
    falhou=$((falhou+1)); echo "  FALHA nao consegui corromper o objeto do HEAD — caso nao mediu nada"
  fi
  saida_corr=$(node "$SCRIPT" conferir --slug corrompido 2>&1); ec_corr=$?
  if [ "$ec_corr" = "2" ]; then
    ok=$((ok+1)); echo "  ok   objeto corrompido sai 2, nao 1 (exit $ec_corr)"
  else
    falhou=$((falhou+1)); echo "  FALHA objeto corrompido: esperava exit 2, veio $ec_corr"
    echo "$saida_corr" | sed 's/^/         /' | tail -4
  fi
  # A assercao e sobre o SENTIDO da mensagem, nao sobre a camada da sonda que
  # pegou o caso: qualquer "git falhou" serve, desde que NAO acuse de nunca
  # commitado — que e a confusao que os achados A2/B1/C1 apontaram.
  if echo "$saida_corr" | grep -q "git falhou" && ! echo "$saida_corr" | grep -q "nunca foi commitado"; then
    ok=$((ok+1)); echo "  ok     ... nomeia falha do git e nao acusa de nunca commitado"
  else
    falhou=$((falhou+1)); echo "  FALHA mensagem nao distingue historico ilegivel de ausencia de commit"
    echo "$saida_corr" | sed 's/^/         /' | tail -4
  fi
else
  falhou=$((falhou+1)); echo "  FALHA nao achei o objeto solto do HEAD em $OBJ — caso nao mediu nada"
fi

cd "$REPO2"

echo
echo "== 13. cabecalho ### M<n> sem descricao e rejeitado (doc e codigo batem) =="
# references/formato-manifesto.md promete que `### M1` sem espaco reprova. O
# regex antigo aceitava, porque fim de linha satisfazia a alternativa `$` —
# achado B2. Doc que promete mais rigor que o codigo e pior que doc ausente.
cat > docs/rainforest/reguas/sem-descricao.md << 'FIMMANIFESTO'
# Régua sem descrição nos mecanismos

## Freios

Teto de rodadas: 5.

### M1
### M2
### M3
### M4
### M5
FIMMANIFESTO
git add -A >/dev/null 2>&1
git commit -q -m "manifesto sem descricao" >/dev/null 2>&1
esperado "### M1 sem descricao reprova" 1 node "$SCRIPT" conferir --slug sem-descricao
contem "  ... mensagem cita o formato exigido" "fora do formato" node "$SCRIPT" conferir --slug sem-descricao
bytes_semdesc=$(stdout_bytes node "$SCRIPT" mostrar --slug sem-descricao)
if [ "$bytes_semdesc" = "0" ]; then
  ok=$((ok+1)); echo "  ok     ... mostrar nao imprime nada nesse caso"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar imprimiu $bytes_semdesc bytes com formato invalido"
fi

echo
echo "== 14. HEAD destacado sem branch, objeto podre: ambiente (2) =="
# Contraexemplo da sonda por "existe alguma ref": HEAD destacado nao aparece em
# for-each-ref, entao um repositorio com historico corrompido e sem branch
# local era classificado como "nunca commitado" (1).
REPO5="$CAIXA/repo-detach"
mkdir -p "$REPO5/docs/rainforest/reguas"
cd "$REPO5"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/detach.md
git add -A >/dev/null 2>&1
git commit -q -m "manifesto" >/dev/null 2>&1
git checkout -q --detach >/dev/null 2>&1
rm -f .git/refs/heads/* 2>/dev/null
SHA5=$(git rev-parse HEAD)
OBJ5=".git/objects/${SHA5:0:2}/${SHA5:2}"
if [ -f "$OBJ5" ]; then
  rm -f "$OBJ5"; echo "lixo" > "$OBJ5"
  saida5=$(node "$SCRIPT" conferir --slug detach 2>&1); ec5=$?
  if [ "$ec5" = "2" ]; then
    ok=$((ok+1)); echo "  ok   HEAD destacado com objeto podre sai 2 (exit $ec5)"
  else
    falhou=$((falhou+1)); echo "  FALHA HEAD destacado podre: esperava 2, veio $ec5"
    echo "$saida5" | sed 's/^/         /' | tail -3
  fi
else
  falhou=$((falhou+1)); echo "  FALHA objeto do HEAD nao estava solto — caso nao mediu nada"
fi

echo
echo "== 15. fetch sem checkout: refs/remotes cheio, mas veredito (1) =="
# O outro sentido do mesmo erro: `fetch` enche refs/remotes/ num repositorio
# que nunca commitou nada, e a sonda antiga chamava isso de ambiente.
BARE="$CAIXA/bare.git"
git init -q --bare "$BARE" >/dev/null 2>&1
cd "$REPO2"
git push -q "$BARE" HEAD:refs/heads/main >/dev/null 2>&1
REPO6="$CAIXA/repo-fetch"
mkdir -p "$REPO6/docs/rainforest/reguas"
cd "$REPO6"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git remote add origin "$BARE" >/dev/null 2>&1
git fetch -q origin >/dev/null 2>&1
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/soremoto.md
n_remotas=$(git for-each-ref --count=1 --format='%(refname)' | wc -l)
if [ "$n_remotas" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok   o fetch deixou ref remota (a sonda antiga veria 'tem ref')"
else
  falhou=$((falhou+1)); echo "  FALHA o fetch nao criou ref — caso nao mediu nada"
fi
esperado "manifesto nunca commitado localmente sai 1, nao 2" 1 node "$SCRIPT" conferir --slug soremoto

cd "$REPO2"

echo
echo "== 16. packed-refs ilegivel: ambiente (2), pela camada do show-ref =="
# Os casos 12 e 14 param nas camadas 1 e 2 da sonda. Este exercita a 3.
# Objeto ausente NAO serve de gatilho: `rev-parse --verify HEAD` le o ref e
# resolve sem tocar no objeto, entao a camada 1 ja decide. O gatilho real e o
# ref ficar ilegivel: refs empacotadas e o packed-refs corrompido. Sem este
# caso, fazer a camada 3 devolver sempre "nunca commitado" passa despercebido
# — foi o que a catraca de mutacao acusou.
REPO7="$CAIXA/repo-packed"
mkdir -p "$REPO7/docs/rainforest/reguas"
cd "$REPO7"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/empacotado.md
git add -A >/dev/null 2>&1
git commit -q -m "manifesto" >/dev/null 2>&1
git pack-refs --all >/dev/null 2>&1
rm -f .git/refs/heads/* 2>/dev/null
printf 'isto nao e um packed-refs valido
' > .git/packed-refs
if git rev-parse --quiet --verify HEAD >/dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA HEAD ainda resolve — o caso nao alcanca a camada 3"
else
  ok=$((ok+1)); echo "  ok   HEAD deixou de resolver com packed-refs ilegivel (camada 3)"
fi
saida7=$(node "$SCRIPT" conferir --slug empacotado 2>&1); ec7=$?
if [ "$ec7" = "2" ]; then
  ok=$((ok+1)); echo "  ok   packed-refs ilegivel sai 2 (exit $ec7)"
else
  falhou=$((falhou+1)); echo "  FALHA packed-refs ilegivel: esperava 2, veio $ec7"
  echo "$saida7" | sed 's/^/         /' | tail -3
fi

cd "$REPO2"

echo
echo "== 17. --slug com ../ nao escapa de docs/rainforest/reguas/ =="
# O selo tem UM ponto por onde burlar (design D3): quem nao chama o script.
# Sem validar o slug haveria DOIS — `--slug ../fora` monta
# docs/rainforest/reguas/../fora.md, e `fs.existsSync`/`fs.readFileSync`
# normalizam o `..`: o conferidor passa a LER e a dar VEREDITO sobre arquivo de
# fora da pasta de reguas.
#
# O que ele NAO faz, e medir isso e o ponto deste bloco: imprimir o conteudo.
# `git show <sha>:<caminho com ..>` nao normaliza e falha, entao sem a
# validacao o script ja saia 2 ali — por acidente, e com a mensagem errada
# ("erro ao ler conteudo do commit"). Por isso as assercoes de exit code
# sozinhas NAO discriminam: sob mutacao seis das sete passam. Quem separa os
# dois mundos e a MENSAGEM e a ausencia de `..` na saida — e por isso elas
# existem aqui, nao como zelo.
#
# O alvo abaixo e um manifesto VALIDO e COMMITADO, com um gemeo dentro da
# pasta, para que o caso meça a recusa e nao a ausencia do arquivo.
REPO8="$CAIXA/repo-travessia"
mkdir -p "$REPO8/docs/rainforest/reguas"
cd "$REPO8"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/fora.md
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/dentro.md
git add -A >/dev/null 2>&1
git commit -q -m "alvo fora da pasta de reguas" >/dev/null 2>&1

# Contraprova: o mesmo manifesto, dentro da pasta, passa. Sem ela o caso
# poderia estar verde porque o conferidor recusa tudo.
esperado "slug legitimo ao lado do alvo segue passando" 0 node "$SCRIPT" conferir --slug dentro

esperado "conferir --slug ../fora recusa" 2 node "$SCRIPT" conferir --slug ../fora
contem "conferir --slug ../fora diz por que" "slug invalido" node "$SCRIPT" conferir --slug ../fora
esperado "mostrar --slug ../fora recusa" 2 node "$SCRIPT" mostrar --slug ../fora

bytes8=$(stdout_bytes node "$SCRIPT" mostrar --slug ../fora)
if [ "$bytes8" = "0" ]; then
  ok=$((ok+1)); echo "  ok   mostrar --slug ../fora nao imprime byte nenhum"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar --slug ../fora imprimiu $bytes8 bytes de fora da pasta de reguas"
fi

saida8=$(node "$SCRIPT" conferir --slug ../fora 2>&1)
if echo "$saida8" | grep -q -- 'reguas/\.\./'; then
  falhou=$((falhou+1)); echo "  FALHA a saida ainda carrega caminho montado com ..: $saida8"
else
  ok=$((ok+1)); echo "  ok   a saida nao menciona caminho montado com .."
fi

# Exit 2 sozinho NAO discrimina aqui: slug inexistente tambem sai 2 (caso 5),
# e os dois abaixo montam caminho que nao existe. Sem a assercao de mensagem
# eles ficariam verdes com a validacao removida — passavam por coincidencia.
esperado "slug com barra recusa" 2 node "$SCRIPT" conferir --slug "reguas/dentro"
contem "slug com barra recusa PELO motivo certo" "slug invalido" node "$SCRIPT" conferir --slug "reguas/dentro"
esperado "slug com dois-pontos recusa" 2 node "$SCRIPT" conferir --slug "dentro:stream"
contem "slug com dois-pontos recusa PELO motivo certo" "slug invalido" node "$SCRIPT" conferir --slug "dentro:stream"

cd "$REPO2"

echo
echo "== 18. clone raso nao ancora: ambiente (2), nunca 0 sobre regua adulterada =="
# O achado bloqueante da rodada 5. Num clone raso o unico commit visivel e a
# fronteira, e o conteudo dela e o que esta no checkout: a comparacao de
# integridade comparava o arquivo consigo mesmo. O caso monta o cenario
# inteiro — regua selada, depois adulterada E COMMITADA — para que o repo
# completo e o clone raso sejam medidos lado a lado. Sem a guarda, o raso sai
# 0 e o `mostrar` entrega a regua afrouxada ao critico cego.
REPO9="$CAIXA/repo-fundo"
mkdir -p "$REPO9/docs/rainforest/reguas"
cd "$REPO9"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/fundo.md
git add -A >/dev/null 2>&1
git commit -q -m "regua selada" >/dev/null 2>&1
sed -i "s/^### M1 .*/### M1 criterio afrouxado/" docs/rainforest/reguas/fundo.md
git add -A >/dev/null 2>&1
git commit -q -m "adultera a regua depois de selada" >/dev/null 2>&1

# Contraprova: no repo COMPLETO a adulteracao e pega.
esperado "repo completo pega a regua adulterada" 1 node "$SCRIPT" conferir --slug fundo

RASO="$CAIXA/clone-raso"
rm -rf "$RASO"
git clone -q --depth 1 "file://$REPO9" "$RASO" >/dev/null 2>&1
cd "$RASO"
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  ok=$((ok+1)); echo "  ok   o clone e mesmo raso (o caso alcanca a guarda)"
else
  falhou=$((falhou+1)); echo "  FALHA o clone nao ficou raso — o caso nao mede nada"
fi
esperado "clone raso e AMBIENTE (2), nao veredito" 2 node "$SCRIPT" conferir --slug fundo
contem "clone raso diz por que e o que fazer" "clone raso" node "$SCRIPT" conferir --slug fundo
esperado "mostrar tambem recusa em clone raso" 2 node "$SCRIPT" mostrar --slug fundo

bytes9=$(stdout_bytes node "$SCRIPT" mostrar --slug fundo)
if [ "$bytes9" = "0" ]; then
  ok=$((ok+1)); echo "  ok   o critico cego nao recebe a regua afrouxada"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar imprimiu $bytes9 bytes em clone raso"
fi

cd "$REPO2"

echo
echo "== 19. ### M<n> malformado REPROVA mesmo com 5 bem formados =="
# O teto de 5-7 era burlavel: o laco so contava o que casava a regex, e o
# resto virava uma variavel que so era lida quando NENHUM casava. Cinco bem
# formados + `### M6:` e `### M7:` davam cinco, dentro da faixa, exit 0 — com
# dois mecanismos que o validador nunca viu. O caso 13 nao cobre isto: la os
# malformados sao a totalidade.
REPO10="$CAIXA/repo-teto"
mkdir -p "$REPO10/docs/rainforest/reguas"
cd "$REPO10"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
{
  printf "# Regua misturada

## Freios

"
  for n in 1 2 3 4 5; do printf "### M%s mecanismo
corpo

" "$n"; done
  printf "### M6: sexto invisivel
corpo

### M7: setimo invisivel
corpo
"
} > docs/rainforest/reguas/misturado.md
git add -A >/dev/null 2>&1
git commit -q -m "cinco validos e dois malformados" >/dev/null 2>&1

cabecalhos=$(grep -c "^### M" docs/rainforest/reguas/misturado.md)
if [ "$cabecalhos" = "7" ]; then
  ok=$((ok+1)); echo "  ok   o manifesto tem mesmo 7 cabecalhos ### M (5 validos + 2 malformados)"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 7 cabecalhos, achei $cabecalhos — o caso nao mede nada"
fi
esperado "5 validos + 2 malformados REPROVA" 1 node "$SCRIPT" conferir --slug misturado
contem "e a mensagem nomeia o cabecalho ofensor" "### M6: sexto invisivel" node "$SCRIPT" conferir --slug misturado
esperado "mostrar tambem recusa" 1 node "$SCRIPT" mostrar --slug misturado

cd "$REPO2"

echo
echo "== 20. manifesto selado e apagado da arvore e VEREDITO (1), nao ambiente (2) =="
# Sumir com o manifesto e da mesma familia de edita-lo. Classificar como uso
# errado (2) mandava o operador para o remedio de ambiente — refazer o checkout
# com historico — quando o que houve foi o manifesto deixar a arvore.
#
# O exit code sozinho NAO discrimina este caso, e a catraca mostrou por que:
# sem a guarda, o `readFileSync` do arquivo ausente lanca excecao e o node
# morre com exit 1 e stack trace — o mesmo codigo do veredito, por acidente.
# Quem separa os dois mundos e a mensagem "removido da arvore".
REPO11="$CAIXA/repo-apagado"
mkdir -p "$REPO11/docs/rainforest/reguas"
cd "$REPO11"
git init >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
cp "$REPO2/docs/rainforest/reguas/autocrlf-test.md" docs/rainforest/reguas/some.md
git add -A >/dev/null 2>&1
git commit -q -m "regua selada" >/dev/null 2>&1

# Contraprova: antes de apagar, passa.
esperado "com o manifesto na arvore, passa" 0 node "$SCRIPT" conferir --slug some
rm -f docs/rainforest/reguas/some.md
esperado "apagado da arvore: veredito (1), nao ambiente" 1 node "$SCRIPT" conferir --slug some
contem "e diz que foi removido, nao que o arquivo nunca existiu" "removido da arvore" node "$SCRIPT" conferir --slug some
esperado "slug que nunca existiu continua sendo 2" 2 node "$SCRIPT" conferir --slug nunca-existiu

cd "$REPO2"

echo
echo "== 21. git AUSENTE do PATH sai 2 pelo ramo do ENOENT =="
# O `pronto quando` da tarefa 6 prometia isto e nenhum caso media. O caso 10
# mede "fora de repositorio", que chega ao mesmo exit 2 por OUTRO ramo
# (`res.status !== 0`); aqui o gatilho e `res.error` ENOENT, o do spawn que nem
# acha o binario. Regressao que tratasse os dois de forma diferente passava a
# bateria inteira.
#
# Sabotar o PATH com um `git` falso nao funciona no Windows (o Node resolve por
# PATHEXT e ignora um extensionless). Esvaziar o PATH funciona, e por isso o
# node e chamado pelo caminho absoluto.
NODE_ABS=$(command -v node)
cd "$REPO9" 2>/dev/null || cd "$REPO2"
if [ -n "$NODE_ABS" ] && ! env PATH= "$NODE_ABS" -e "require('child_process').execSync('git --version')" >/dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   com PATH vazio o git realmente nao e encontrado (o caso alcanca o ramo)"
  saida21=$(env PATH= "$NODE_ABS" "$SCRIPT" conferir --slug fundo 2>&1); ec21=$?
  if [ "$ec21" = "2" ]; then
    ok=$((ok+1)); echo "  ok   git ausente do PATH sai 2, nao 1 (exit $ec21)"
  else
    falhou=$((falhou+1)); echo "  FALHA git ausente do PATH: esperava 2, veio $ec21"
    echo "$saida21" | sed "s/^/         /" | tail -3
  fi
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui montar um ambiente sem git — o caso nao mede nada"
fi

cd "$REPO2"

echo
echo "== 22. merge TREESAME nao troca a ancora: mais de uma adicao e VEREDITO (1) =="
# Achado bloqueante da rodada 7. Regua estrita selada na main; uma branch
# nascida ANTES dela tambem adiciona o arquivo, frouxo; o merge conflita
# (add/add) e e resolvido com o lado da branch. Sem `--full-history`, o git
# simplifica o historico, segue so o pai TREESAME e devolve so a adicao da
# branch: `conferir` saia 0 e `mostrar` entregava a regua frouxa.
REPO12="$CAIXA/repo-merge"
mkdir -p "$REPO12"
cd "$REPO12"
git init -q -b main >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git config core.autocrlf false
echo base > LEIA; git add -A >/dev/null 2>&1; git commit -q -m C0 >/dev/null 2>&1
manifesto12() { # adjetivo
  mkdir -p docs/rainforest/reguas
  { printf "# Regua

## Freios

"; for n in 1 2 3 4 5; do printf "### M%s %s
x

" "$n" "$1"; done; } > docs/rainforest/reguas/merge.md
}
git checkout -q -b frouxa
manifesto12 frouxo; git add -A >/dev/null 2>&1; git commit -q -m "E1 frouxa" >/dev/null 2>&1
git checkout -q main
manifesto12 estrito; git add -A >/dev/null 2>&1; git commit -q -m "C1 estrita, a selada" >/dev/null 2>&1

# Contraprova: antes do merge, a regua selada passa.
esperado "antes do merge a regua selada passa" 0 node "$SCRIPT" conferir --slug merge

git merge frouxa >/dev/null 2>&1
git checkout --theirs docs/rainforest/reguas/merge.md >/dev/null 2>&1
git add -A >/dev/null 2>&1
git commit -q -m "merge resolvido com a frouxa" >/dev/null 2>&1
if grep -q "### M1 frouxo" docs/rainforest/reguas/merge.md; then
  ok=$((ok+1)); echo "  ok   o merge deixou a regua frouxa na arvore (o caso monta o ataque)"
else
  falhou=$((falhou+1)); echo "  FALHA o merge nao deixou a frouxa — o caso nao mede nada"
fi
esperado "depois do merge: veredito (1), nao 0" 1 node "$SCRIPT" conferir --slug merge
contem "e nomeia o selo ambiguo" "selo ambiguo" node "$SCRIPT" conferir --slug merge
bytes12=$(stdout_bytes node "$SCRIPT" mostrar --slug merge)
if [ "$bytes12" = "0" ]; then
  ok=$((ok+1)); echo "  ok   o critico cego nao recebe a regua frouxa"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar entregou $bytes12 bytes depois do merge"
fi

cd "$REPO2"

echo
echo "== 23. git replace nao troca o conteudo que o selo le =="
# `git replace` troca o objeto que `git show` devolve sem reescrever
# historico: o commit selado continua la, com o mesmo SHA, e o que se le dele
# e outro blob. Aqui o blob da regua estrita e substituido pelo da frouxa, e a
# arvore fica com a frouxa — sem `GIT_NO_REPLACE_OBJECTS` as duas batem e o
# `conferir` sai 0.
REPO13="$CAIXA/repo-replace"
mkdir -p "$REPO13/docs/rainforest/reguas"
cd "$REPO13"
git init -q >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git config core.autocrlf false
{ printf "# Regua

## Freios

"; for n in 1 2 3 4 5; do printf "### M%s estrito
x

" "$n"; done; } > docs/rainforest/reguas/troca.md
git add -A >/dev/null 2>&1; git commit -q -m "regua selada" >/dev/null 2>&1
blob_estrito=$(git rev-parse HEAD:docs/rainforest/reguas/troca.md)
sed -i "s/estrito/frouxo/" docs/rainforest/reguas/troca.md
blob_frouxo=$(git hash-object -w docs/rainforest/reguas/troca.md)
git replace "$blob_estrito" "$blob_frouxo" >/dev/null 2>&1
if MSYS_NO_PATHCONV=1 git show HEAD:docs/rainforest/reguas/troca.md | grep -q frouxo; then
  ok=$((ok+1)); echo "  ok   sem a guarda o git show ja entrega a frouxa (o caso monta o ataque)"
else
  falhou=$((falhou+1)); echo "  FALHA o replace nao pegou — o caso nao mede nada"
fi
esperado "com replace: veredito (1), nao 0" 1 node "$SCRIPT" conferir --slug troca
bytes13=$(stdout_bytes node "$SCRIPT" mostrar --slug troca)
if [ "$bytes13" = "0" ]; then
  ok=$((ok+1)); echo "  ok   o critico cego nao recebe o conteudo substituido"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar entregou $bytes13 bytes com o replace ativo"
fi

cd "$REPO2"

echo
echo "== 24. validar confere o formato ANTES de selar, sem imprimir o manifesto =="
# Sem este subcomando, manifesto selado com erro de formato ficava sem
# conserto: a ancora e a primeira adicao, a quebrada. Nenhum dos arquivos
# abaixo e commitado — e o ponto: validar tem de funcionar SEM ancora.
REPO14="$CAIXA/repo-validar"
mkdir -p "$REPO14/docs/rainforest/reguas"
cd "$REPO14"
git init -q >/dev/null 2>&1
{ printf "# Regua

## Freios

"; for n in 1 2 3 4 5; do printf "### M%s bom
x

" "$n"; done; } > docs/rainforest/reguas/bom.md
{ printf "# Regua

## Freios

"; for n in 1 2 3 4 5; do printf "### M%s: ruim
x

" "$n"; done; } > docs/rainforest/reguas/ruim.md
esperado "manifesto bom, nunca commitado: validar sai 0" 0 node "$SCRIPT" validar --slug bom
contem "e diz que pode selar" "pode selar" node "$SCRIPT" validar --slug bom
esperado "manifesto fora do formato: validar sai 1" 1 node "$SCRIPT" validar --slug ruim
contem "e nomeia o cabecalho ofensor" "### M1: ruim" node "$SCRIPT" validar --slug ruim
esperado "slug inexistente: validar sai 2" 2 node "$SCRIPT" validar --slug nao-ha
# Contraprova: o mesmo manifesto bom, sem commit, o `conferir` recusa — e a
# diferenca entre as duas rotas que o caso existe para medir.
esperado "o conferir do mesmo arquivo recusa (nunca commitado)" 1 node "$SCRIPT" conferir --slug bom
bytes14=$(stdout_bytes node "$SCRIPT" validar --slug bom)
if [ "$bytes14" = "0" ]; then
  ok=$((ok+1)); echo "  ok   validar nao imprime o manifesto (o mostrar segue o unico que imprime)"
else
  falhou=$((falhou+1)); echo "  FALHA validar imprimiu $bytes14 bytes em stdout"
fi

cd "$REPO2"

echo
echo "== 25. cabecalho que o markdown RENDERIZA e a regex estrita nao ve e recusa =="
# Achado bloqueante da rodada 8. A deteccao era `/^### M/`, e `###  M8` (dois
# espacos), ` ### M8` (recuado) e `#### M8` renderizavam como cabecalho sem o
# validador ver: 7 validos + 2 invisiveis saiam 0, com 9 mecanismos na tela do
# critico cego. Sem git: `validar` le a arvore.
REPO15="$CAIXA/repo-render"
mkdir -p "$REPO15/docs/rainforest/reguas"
cd "$REPO15"
sete15() { printf '# Regua\n\n## Freios\n\n'; for n in 1 2 3 4 5 6 7; do printf '### M%s ok\nx\n\n' "$n"; done; }
{ sete15; printf '###  M8 dois espacos\n'; } > docs/rainforest/reguas/dois.md
{ sete15; printf ' ### M8 recuado\n'; } > docs/rainforest/reguas/recuo.md
{ sete15; printf '#### M8 nivel quatro\n'; } > docs/rainforest/reguas/nivel.md
{ sete15; printf '    ### M8 bloco de codigo por recuo\n'; } > docs/rainforest/reguas/codigo.md
esperado "###  M8 (dois espacos) recusa" 1 node "$SCRIPT" validar --slug dois
contem "e nomeia o ofensor" "###  M8" node "$SCRIPT" validar --slug dois
esperado " ### M8 (recuado) recusa" 1 node "$SCRIPT" validar --slug recuo
esperado "#### M8 (nivel quatro) recusa" 1 node "$SCRIPT" validar --slug nivel
# Contraprova: quatro espacos de recuo sao bloco de codigo no markdown, nao
# renderizam como cabecalho — recusar ali seria reprovar manifesto bom.
esperado "quatro espacos de recuo e codigo: nao conta, 7 validos passam" 0 node "$SCRIPT" validar --slug codigo

cd "$REPO2"

echo
echo "== 26. cerca de codigo nao e manifesto =="
# `### M6 exemplo` dentro de uma cerca contava como mecanismo: furava o teto
# (5 + exemplo davam 6) e reprovava manifesto bom (7 + exemplo davam 8).
REPO16="$CAIXA/repo-cerca"
mkdir -p "$REPO16/docs/rainforest/reguas"
cd "$REPO16"
mecs16() { for n in $(seq 1 "$1"); do printf '### M%s ok\nx\n\n' "$n"; done; }
{ printf '# Regua\n\n## Freios\n\n'; mecs16 7; printf '```\n### M8 exemplo cercado\n```\n'; } > docs/rainforest/reguas/crase.md
{ printf '# Regua\n\n## Freios\n\n'; mecs16 7; printf '~~~\n### M8 exemplo em til\n~~~\n'; } > docs/rainforest/reguas/til.md
{ printf '# Regua\n\n```\n## Freios\n```\n\n'; mecs16 5; } > docs/rainforest/reguas/freios-cercado.md
esperado "7 reais + exemplo em cerca de crases: passa" 0 node "$SCRIPT" validar --slug crase
esperado "7 reais + exemplo em cerca de til: passa" 0 node "$SCRIPT" validar --slug til
esperado "## Freios so dentro de cerca nao conta: recusa" 1 node "$SCRIPT" validar --slug freios-cercado

cd "$REPO2"

echo
echo "== 27. .git/info/grafts nao corta o historico que o selo le =="
# Com o HEAD enxertado como raiz, a adicao selada sumia do `git log` e
# `conferir` saia 0 sobre regua adulterada e commitada. GIT_NO_REPLACE_OBJECTS
# nao cobre grafts; GIT_GRAFT_FILE apontando para arquivo inexistente cobre.
REPO17="$CAIXA/repo-grafts"
mkdir -p "$REPO17/docs/rainforest/reguas"
cd "$REPO17"
git init -q >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git config core.autocrlf false
{ printf '# Regua\n\n## Freios\n\n'; for n in 1 2 3 4 5; do printf '### M%s estrito\nx\n\n' "$n"; done; } > docs/rainforest/reguas/enxerto.md
git add -A >/dev/null 2>&1; git commit -q -m "regua selada" >/dev/null 2>&1
sed -i "s/estrito/frouxo/" docs/rainforest/reguas/enxerto.md
git add -A >/dev/null 2>&1; git commit -q -m "adultera" >/dev/null 2>&1
esperado "sem grafts, a adulteracao e pega" 1 node "$SCRIPT" conferir --slug enxerto
git rev-parse HEAD > .git/info/grafts
if [ "$(git log --format=%h 2>/dev/null | wc -l | tr -d ' ')" = "1" ]; then
  ok=$((ok+1)); echo "  ok   com grafts o git log enxerga so um commit (o caso monta o ataque)"
else
  falhou=$((falhou+1)); echo "  FALHA o graft nao cortou o historico — o caso nao mede nada"
fi
esperado "com grafts: veredito (1), nao 0" 1 node "$SCRIPT" conferir --slug enxerto
bytes17=$(stdout_bytes node "$SCRIPT" mostrar --slug enxerto)
if [ "$bytes17" = "0" ]; then
  ok=$((ok+1)); echo "  ok   o critico cego nao recebe a regua frouxa"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar entregou $bytes17 bytes com grafts"
fi

cd "$REPO2"

echo
echo "== 28. diretorio no lugar do manifesto e AUSENCIA (2), sem stack trace =="
# O `validar` fazia `existsSync` e depois `readFileSync`: diretorio passa no
# primeiro e explode no segundo, com exit 1 por acidente — o codigo que o
# cabecalho reserva para formato.
REPO18="$CAIXA/repo-diretorio"
mkdir -p "$REPO18/docs/rainforest/reguas/pasta.md"
cd "$REPO18"
esperado "diretorio no caminho: validar sai 2" 2 node "$SCRIPT" validar --slug pasta
saida18=$(node "$SCRIPT" validar --slug pasta 2>&1)
if echo "$saida18" | grep -qE "node:fs|at Object|Error:"; then
  falhou=$((falhou+1)); echo "  FALHA validar vazou stack trace: $(echo "$saida18" | head -1)"
else
  ok=$((ok+1)); echo "  ok   sem stack trace"
fi

cd "$REPO2"

echo
echo "== 29. log.showSignature=true nao polui a ancora =="
# Com a config ligada, o `git log` poe as linhas da verificacao de assinatura
# no STDOUT, antes do hash. Um manifesto intacto em commit assinado virava
# "adicionado N vezes no historico" — acusacao falsa, e o loop travava.
# Assinatura por chave SSH gerada aqui, para nao depender de GPG na maquina.
REPO19="$CAIXA/repo-assinado"
mkdir -p "$REPO19/docs/rainforest/reguas"
cd "$REPO19"
git init -q >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config core.autocrlf false
ssh-keygen -t ed25519 -N "" -f "$CAIXA/chave-assinatura" -q >/dev/null 2>&1
git config gpg.format ssh
git config user.signingkey "$CAIXA/chave-assinatura.pub"
{ printf '# Regua\n\n## Freios\n\n'; for n in 1 2 3 4 5; do printf '### M%s ok\nx\n\n' "$n"; done; } > docs/rainforest/reguas/assinada.md
git add -A >/dev/null 2>&1
git commit -q -S -m "regua selada, commit assinado" >/dev/null 2>&1
linhas19=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.showSignature GIT_CONFIG_VALUE_0=true git log --format=%H 2>/dev/null | grep -c .)
if [ "$linhas19" -gt 1 ]; then
  ok=$((ok+1)); echo "  ok   com a config, o git log poe $linhas19 linhas no stdout (o caso monta o ataque)"
else
  falhou=$((falhou+1)); echo "  FALHA o commit nao ficou assinado ou a config nao pegou — o caso nao mede nada"
fi
esperado "com log.showSignature=true, manifesto intacto passa" 0 env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.showSignature GIT_CONFIG_VALUE_0=true node "$SCRIPT" conferir --slug assinada

cd "$REPO2"

echo
echo "== 30. log.follow=true nao troca a ancora de um git mv =="
# Manifesto posto no lugar com `git mv` e caminho de boa-fe. Com log.follow, o
# git segue o arquivo de origem e a ancora vira um commit em que o caminho do
# manifesto nao existe: `git show` falhava e o `conferir` saia 2 falso.
REPO20="$CAIXA/repo-follow"
mkdir -p "$REPO20/docs/rainforest/reguas"
cd "$REPO20"
git init -q >/dev/null 2>&1
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false
git config core.autocrlf false
{ printf '# Regua\n\n## Freios\n\n'; for n in 1 2 3 4 5; do printf '### M%s ok\nx\n\n' "$n"; done; } > docs/rainforest/reguas/rascunho.md
git add -A >/dev/null 2>&1; git commit -q -m "rascunho" >/dev/null 2>&1
git mv docs/rainforest/reguas/rascunho.md docs/rainforest/reguas/movida.md >/dev/null 2>&1
git commit -q -m "a regua e esta" >/dev/null 2>&1
esperado "sem a config, manifesto movido passa" 0 node "$SCRIPT" conferir --slug movida
esperado "com log.follow=true, continua passando" 0 env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.follow GIT_CONFIG_VALUE_0=true node "$SCRIPT" conferir --slug movida

cd "$REPO2"

echo
echo "== 31. mecanismo comentado com <!-- --> nao conta =="
# Comentar o rascunho de um mecanismo e edicao comum de boa-fe. O comentado
# contava: 4 reais + 1 comentado passavam o piso de 5, e o critico recebia 4.
REPO21="$CAIXA/repo-comentario"
mkdir -p "$REPO21/docs/rainforest/reguas"
cd "$REPO21"
mecs21() { for n in $(seq 1 "$1"); do printf '### M%s ok\nx\n\n' "$n"; done; }
{ printf '# Regua\n\n## Freios\n\n'; mecs21 4; printf '<!--\n### M5 rascunho comentado\n-->\n'; } > docs/rainforest/reguas/quatro.md
{ printf '# Regua\n\n## Freios\n\n'; mecs21 7; printf '<!--\n### M8 rascunho comentado\n-->\n'; } > docs/rainforest/reguas/sete.md
{ printf '# Regua\n\n## Freios\n\n'; mecs21 7; printf '<!-- ### M8 comentado na mesma linha -->\n'; } > docs/rainforest/reguas/uma-linha.md
esperado "4 reais + 1 comentado: recusa (sao 4)" 1 node "$SCRIPT" validar --slug quatro
contem "e diz que sao 4" "quantidade invalida de mecanismos: 4" node "$SCRIPT" validar --slug quatro
esperado "7 reais + 1 comentado: passa" 0 node "$SCRIPT" validar --slug sete
esperado "7 reais + comentario de uma linha: passa" 0 node "$SCRIPT" validar --slug uma-linha

cd "$REPO2"

echo
echo "== 32. cerca aninhada fecha como no CommonMark =="
# A cerca fechava so pelo caractere. Uma cerca de quatro crases com um exemplo
# de tres dentro fechava no exemplo, e o `### M1 exemplo` de dentro contava:
# 7 reais viravam 8 e o manifesto bom reprovava.
REPO22="$CAIXA/repo-aninhada"
mkdir -p "$REPO22/docs/rainforest/reguas"
cd "$REPO22"
mecs22() { for n in $(seq 1 "$1"); do printf '### M%s ok\nx\n\n' "$n"; done; }
{ printf '# Regua\n\n## Freios\n\n'; mecs22 7; printf '````\n```\n### M1 exemplo\n```\n````\n'; } > docs/rainforest/reguas/quatro-crases.md
{ printf '# Regua\n\n## Freios\n\n'; mecs22 7; printf '```\n```js\n### M1 exemplo\n```\n'; } > docs/rainforest/reguas/info-string.md
esperado "cerca de 4 crases com exemplo de 3 dentro: passa" 0 node "$SCRIPT" validar --slug quatro-crases
esperado "linha com info string nao fecha a cerca: passa" 0 node "$SCRIPT" validar --slug info-string

cd "$REPO2"

echo
echo "== 33. slug com metacaractere de glob e slug inexistente (2) =="
# Sem pathspec literal, `--slug '*'` casava todos os manifestos no `git log` e
# saia 1 ("selado e removido") — veredito sobre um slug que nao existe.
cd "$REPO"
esperado "--slug '*' sai 2, nao 1" 2 node "$SCRIPT" conferir --slug '*'
esperado "--slug 'teste-?' sai 2, nao 1" 2 node "$SCRIPT" conferir --slug 'teste-?'

cd "$REPO2"

echo "== Resumo =="
resultado=$((ok+falhou))
if [ "$falhou" = "0" ]; then
  echo "resultado: $ok ok, 0 falha(s)"
  exit 0
else
  echo "resultado: $ok ok, $falhou falha(s)"
  exit 1
fi
