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

stdout_bytes() { # comando...
  local saida; saida=$("$@" 2>/dev/null)
  echo -n "$saida" | wc -c
}

stdout_conteudo() { # comando...
  "$@" 2>/dev/null
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
if [ "$conf_exit" = "0" ]; then echo "  ok   conferir passa (sanidade)"
else echo "  FALHA conferir: exit $conf_exit"; fi

# Captura o conteúdo esperado (do commit)
ancora=$(git log --diff-filter=A --format=%H -- docs/rainforest/reguas/teste-4.md | tail -1)
esperado_conteudo=$(MSYS_NO_PATHCONV=1 git show "$ancora":docs/rainforest/reguas/teste-4.md)

# Captura o conteúdo do mostrar
mostrar_conteudo=$(stdout_conteudo node "$SCRIPT" mostrar --slug teste-4)

# Compara byte a byte
if [ "$esperado_conteudo" = "$mostrar_conteudo" ]; then ok=$((ok+1)); echo "  ok   mostrar imprime conteudo idêntico da âncora"
else
  falhou=$((falhou+1))
  echo "  FALHA mostrar: conteúdo diverge da âncora"
  exp_len=$(echo -n "$esperado_conteudo" | wc -c)
  most_len=$(echo -n "$mostrar_conteudo" | wc -c)
  echo "         esperado: $exp_len bytes, mostrar: $most_len bytes"
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
saida_semdesc=$(node "$SCRIPT" mostrar --slug sem-descricao 2>/dev/null)
if [ -z "$saida_semdesc" ]; then
  ok=$((ok+1)); echo "  ok     ... mostrar nao imprime nada nesse caso"
else
  falhou=$((falhou+1)); echo "  FALHA mostrar imprimiu ${#saida_semdesc} bytes com formato invalido"
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

echo "== Resumo =="
resultado=$((ok+falhou))
if [ "$falhou" = "0" ]; then
  echo "resultado: $ok ok, 0 falha(s)"
  exit 0
else
  echo "resultado: $ok ok, $falhou falha(s)"
  exit 1
fi
