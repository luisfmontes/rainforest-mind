#!/bin/bash
# Bateria do scripts/conferir-glossario.cjs — o conferidor do GLOSSARIO.md.
#
# O QUE PRECISA PROVAR (cada grupo é um item do "pronto quando" da tarefa 3 do
# plano 2026-10-08-glossario-compartilhado):
#   1. verbete conforme sai 0, e cada legítimo vizinho NÃO é recusado;
#   2. cada defeito sai 1 e a mensagem nomeia GLOSSARIO.md:<linha>, o termo, o
#      campo e o formato esperado;
#   3. --exigir, --listar e --caminhos fazem o que o plano manda;
#   4. MUTAÇÃO: trocar `const duplicado = vistos.has(v.chave);` por
#      `const duplicado = false;` tem que derrubar esta bateria (caso
#      "Territorio e territorio sao o mesmo termo (duplicado recusa)").
#
# Uso: bash scripts/testa-conferir-glossario.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-glossario.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
SB_POSIX="$(mktemp -d)"
# Caminho NATIVO para o Node no Windows resolver (ver testa-conferir-categoria.sh).
SB="$(cygpath -m "$SB_POSIX" 2>/dev/null || printf '%s' "$SB_POSIX")"
trap 'rm -rf "$SB_POSIX"' EXIT

saiu()    { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()     { if printf '%s' "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; fi; }
nao_tem() { if printf '%s' "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (nao esperava '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }

# Roda o conferidor: a saida (stdout+stderr) vai para $S, o exit para $C.
rodar() { S="$(node "$SCRIPT" "$@" 2>&1)"; C=$?; }
# Escreve um GLOSSARIO.md de teste na pasta $1 a partir do stdin.
mk()    { mkdir -p "$SB/$1"; cat > "$SB/$1/GLOSSARIO.md"; }

# ---------------------------------------------------------------- fixtures
mk d7 <<'EOF'
# Glossário

Termos de domínio do repo. Cada verbete tem definição, onde mora e um cenário real.

## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: skills/ e hooks/ do plugin, estado em `.rainforest/estagio`.
Cenário: o Luís pede "brainstorm" e o fluxo começa no estágio brainstorm.
Evite: esteira; pipeline

## território
Definição: área de arquivos que um agente pode tocar numa entrega.
Onde mora: o campo "território" de cada tarefa do plano.
Cenário: a tarefa 3 declara o território em que pode editar.

## worktree de agente
Definição: diretório temporário de git criado para um subagente
trabalhar isolado do checkout principal.
Onde mora: .claude/worktrees/ na raiz do repo.
Cenário: o despacho cria um worktree por tarefa paralela.
Evite: clone; cópia do repo
EOF
sed 's/$/\r/' "$SB/d7/GLOSSARIO.md" > "$SB/d7crlf.tmp" && mkdir -p "$SB/d7crlf" && mv "$SB/d7crlf.tmp" "$SB/d7crlf/GLOSSARIO.md"

mk semevite <<'EOF'
# Glossário

## território
Definição: área de arquivos que um agente pode tocar numa entrega.
Onde mora: o campo "território" de cada tarefa do plano.
Cenário: a tarefa 3 declara o território em que pode editar.
EOF

mk evitevazio <<'EOF'
## território
Definição: área de arquivos que um agente pode tocar.
Onde mora: o campo "território" de cada tarefa.
Cenário: a tarefa 3 declara o território em que pode editar.
Evite:
EOF

mk cenario2 <<'EOF'
## território
Definição: área de arquivos.
Onde mora: o campo "território" de cada tarefa.
Cenário: a tarefa 3 declara o território
em que o agente pode editar, e o conferidor aceita
o texto que continua na linha seguinte.
EOF

mk ordem <<'EOF'
## fluxo
Cenário: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
Onde mora: skills/ e hooks/ do plugin.
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
EOF

mk rotulos_var <<'EOF'
## fluxo
Definicao: a sequência de sete estágios que vai de uma ideia até o PR.
ONDE MORA: skills/ e hooks/ do plugin.
cenario: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
EOF

mk intro <<'EOF'
# Glossário

Termos de domínio do repo. Cada verbete tem definição, onde mora e um cenário real.
Esta introdução vem antes do primeiro cabeçalho e não conta como verbete.

## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: skills/ do plugin.
Cenário: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
EOF

mk frase_definicao <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: skills/ do plugin.
Cenário: o Luís lê o campo
a palavra Definição: no meio de uma frase, e nada muda.
EOF

mk subsecao <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
### exemplo prático
Onde mora: skills/ do plugin.
Cenário: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
EOF

mk parecidos <<'EOF'
## estágio
Definição: o intervalo de um fluxo entre dois marcos.
Onde mora: hooks/ do plugin.
Cenário: o estágio atual é brainstorm, e o fluxo está nele.

## estágio zero
Definição: a arqueologia opcional antes do brainstorm.
Onde mora: skills/arqueologia/.
Cenário: o Luís roda o estágio zero antes de planejar a demanda.
EOF

mk til <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: `~/.rainforest/ideias.jsonl`, fora do repo.
Cenário: a ideia cai em `~/.rainforest/ideias.jsonl` e o fluxo segue.
EOF

mkdir -p "$SB/existe/hooks/lib" && echo "// existe" > "$SB/existe/hooks/lib/x.cjs"
mk existe <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: `hooks/lib/x.cjs`.
Cenário: o hook `hooks/lib/x.cjs` injeta o fluxo no pedido.
EOF

mk ignorados <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: `<arquivo>.md`, `skills/*.md` e `https://ex.com/a.md`.
Cenário: a tabela `C5_NOTA` e o campo `ideias` não são caminho.
EOF

mk semcaminho <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: `hooks/nao-existe.cjs`.
Cenário: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
EOF

mk caminho_inexistente <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: `hooks/nao-existe.cjs`.
Cenário: o Luís pede brainstorm e o fluxo começa no estágio brainstorm.
EOF

mk caminho_cenario <<'EOF'
## fluxo
Definição: a sequência de sete estágios que vai de uma ideia até o PR.
Onde mora: skills/ do plugin.
Cenário: a tarefa roda `scripts/sumiu.cjs` antes do commit.
EOF

mk semdef <<'EOF'
# Glossário

## t
Onde mora: o
Cenário: c
EOF

mk semonde <<'EOF'
## t
Definição: d
Cenário: c
EOF

mk semcen <<'EOF'
## t
Definição: d
Onde mora: o
EOF

mk vazio_texto <<'EOF'
## t
Definição:
Onde mora: o
Cenário: c
EOF

mk tbd <<'EOF'
## t
Definição: TBD
Onde mora: o
Cenário: c
EOF

mk adefinir <<'EOF'
## t
Definição: d
Onde mora: a definir
Cenário: c
EOF

mk nsa <<'EOF'
## t
Definição: d
Onde mora: o
Cenário: n/a
EOF

mk reticencias <<'EOF'
## t
Definição: ...
Onde mora: o
Cenário: c
EOF

mk defininicao <<'EOF'
## t
Defininição: d
Onde mora: o
Cenário: c
EOF

mk negrito <<'EOF'
## t
**Definição:** d
Onde mora: o
Cenário: c
EOF

mk dup <<'EOF'
## território
Definição: d
Onde mora: o
Cenário: c

## territorio
Definição: d
Onde mora: o
Cenário: c
EOF

mk dupworktree <<'EOF'
## worktree
Definição: d
Onde mora: o
Cenário: c

## Worktrees
Definição: d
Onde mora: o
Cenário: c
EOF

mk evite_proprio <<'EOF'
## fluxo
Definição: d
Onde mora: o
Cenário: c
Evite: Fluxo
EOF

mk evite_outro <<'EOF'
## fluxo
Definição: d
Onde mora: o
Cenário: c
Evite: território

## território
Definição: d
Onde mora: o
Cenário: c
EOF

LONGO="$(printf 'a%.0s' $(seq 1 950))"
mkdir -p "$SB/longo" && printf '## t\nDefinição: %s\nOnde mora: o\nCenário: c\n' "$LONGO" > "$SB/longo/GLOSSARIO.md"

mk semverbete <<'EOF'
# Glossário

Só introdução, sem nenhum cabeçalho de verbete.
EOF

mk so_cerca <<'EOF'
# Glossário

```
## falso
Definição: d
Onde mora: o
Cenário: c
```
EOF

mk listainv <<'EOF'
## bom
Definição: d
Onde mora: o
Cenário: c

## ruim
Definição: d
Onde mora: o
EOF

mkdir -p "$SB/vazio"

echo "== 1. verbete conforme sai 0 e legitimos vizinhos NAO sao recusados =="
rodar --raiz "$SB/d7"
saiu "D7 em LF: exit 0"                          "$C" 0
tem  "D7 em LF: diz 3 verbetes conformes"        "$S" "GLOSSARIO.md: 3 verbete(s) conforme(s)"
rodar --raiz "$SB/d7crlf"
saiu "D7 em CRLF: exit 0"                        "$C" 0
tem  "D7 em CRLF: diz 3 verbetes conformes"      "$S" "GLOSSARIO.md: 3 verbete(s) conforme(s)"
rodar --raiz "$SB/semevite"
saiu "verbete sem Evite: exit 0"                 "$C" 0
rodar --raiz "$SB/evitevazio"
saiu "Evite: vazio: exit 0"                      "$C" 0
rodar --raiz "$SB/cenario2"
saiu "Cenario de duas linhas: exit 0"            "$C" 0
rodar --raiz "$SB/ordem"
saiu "campos em outra ordem: exit 0"             "$C" 0
rodar --raiz "$SB/rotulos_var"
saiu "rotulo sem acento e em outra caixa: exit 0" "$C" 0
rodar --raiz "$SB/intro"
saiu "texto de introducao antes do ##: exit 0"   "$C" 0
rodar --raiz "$SB/frase_definicao"
saiu "a palavra Definicao no meio de frase: exit 0" "$C" 0
rodar --raiz "$SB/subsecao"
saiu "### dentro do verbete: exit 0"             "$C" 0
rodar --raiz "$SB/parecidos"
saiu "estagio e estagio zero nao sao duplicata: exit 0" "$C" 0
rodar --raiz "$SB/til" --caminhos
saiu "~/.rainforest/ideias.jsonl em crase com --caminhos: exit 0" "$C" 0
rodar --raiz "$SB/existe" --caminhos
saiu "caminho que existe no repo com --caminhos: exit 0" "$C" 0
rodar --raiz "$SB/ignorados" --caminhos
saiu "<arquivo>, glob, URL e nome sem extensao nao sao checados: exit 0" "$C" 0
rodar --raiz "$SB/semcaminho"
saiu "sem --caminhos, caminho inexistente passa: exit 0" "$C" 0
rodar --raiz "$SB/vazio"
saiu "sem GLOSSARIO.md sem --exigir: exit 0"     "$C" 0
tem  "sem GLOSSARIO.md sem --exigir: diz sem GLOSSARIO.md" "$S" "sem GLOSSARIO.md"

echo
echo "== 2. cada defeito sai 1 e a mensagem nomeia GLOSSARIO.md:<linha>, termo, campo e formato =="
rodar --raiz "$SB/semdef"
saiu "verbete sem Definicao: exit 1"             "$C" 1
tem  "sem Definicao: nomeia GLOSSARIO.md:3"      "$S" "GLOSSARIO.md:3:"
tem  "sem Definicao: diz o termo"                "$S" 'verbete "t"'
tem  "sem Definicao: diz o campo e o formato"    "$S" 'Formato: Definição: uma a duas frases.'
rodar --raiz "$SB/semonde"
saiu "verbete sem Onde mora: exit 1"             "$C" 1
tem  "sem Onde mora: formato esperado"           "$S" 'Formato: Onde mora: arquivo, rotina, tabela ou campo.'
rodar --raiz "$SB/semcen"
saiu "verbete sem Cenario: exit 1"               "$C" 1
tem  "sem Cenario: nomeia GLOSSARIO.md:1"        "$S" "GLOSSARIO.md:1:"
tem  "sem Cenario: diz o campo que falta"        "$S" 'falta a linha "Cenário:"'
tem  "sem Cenario: formato esperado em uma linha" "$S" 'Formato: Cenário: um caso real, concreto.'
rodar --raiz "$SB/vazio_texto"
saiu "campo com rotulo e texto vazio: exit 1"    "$C" 1
tem  "rotulo sem texto: nomeia a linha do rotulo (GLOSSARIO.md:2)" "$S" "GLOSSARIO.md:2:"
tem  "rotulo sem texto: diz o motivo"            "$S" "rótulo sem texto"
rodar --raiz "$SB/tbd"
saiu "placeholder TBD em Definicao: exit 1"      "$C" 1
tem  "placeholder TBD: diz o valor"              "$S" 'placeholder "TBD"'
rodar --raiz "$SB/adefinir"
saiu "placeholder 'a definir' em Onde mora: exit 1" "$C" 1
tem  "placeholder 'a definir': diz o valor"      "$S" 'placeholder "a definir"'
rodar --raiz "$SB/nsa"
saiu "placeholder 'n/a' em Cenario: exit 1"      "$C" 1
tem  "placeholder 'n/a': diz o valor"            "$S" 'placeholder "n/a"'
rodar --raiz "$SB/reticencias"
saiu "placeholder '...' em Definicao: exit 1"    "$C" 1
tem  "placeholder '...': diz o valor"            "$S" 'placeholder "..."'
rodar --raiz "$SB/defininicao"
saiu "rotulo digitado errado (Defininicao): exit 1" "$C" 1
tem  "rotulo errado: aponta a linha 2 e o rotulo digitado" "$S" 'a linha 2 tem "Defininição:"'
tem  "rotulo errado: diz qual e o rotulo certo"  "$S" 'o rótulo é "Definição:"'
rodar --raiz "$SB/negrito"
saiu "rotulo em negrito (**Definicao:**): exit 1" "$C" 1
tem  "rotulo em negrito: diz que o parser nao le negrito" "$S" "em negrito"
rodar --raiz "$SB/dup"
saiu "Territorio e territorio sao o mesmo termo (duplicado recusa)" "$C" 1
tem  "duplicado: nomeia a linha do segundo verbete (GLOSSARIO.md:6)" "$S" "GLOSSARIO.md:6:"
tem  "duplicado: diz qual termo repete"          "$S" 'repete "território" (linha 1)'
rodar --raiz "$SB/dupworktree"
saiu "worktree e Worktrees sao o mesmo termo (duplicado recusa)" "$C" 1
tem  "duplicado worktree: diz qual termo repete" "$S" 'repete "worktree" (linha 1)'
rodar --raiz "$SB/evite_proprio"
saiu "Evite igual ao proprio termo: exit 1"      "$C" 1
tem  "Evite proprio: diz que e o proprio termo"  "$S" 'é o próprio termo do verbete'
rodar --raiz "$SB/evite_outro"
saiu "Evite igual ao termo de OUTRO verbete: exit 1" "$C" 1
tem  "Evite de outro: diz qual verbete cita (linha 7)" "$S" 'é o termo de outro verbete ("território", linha 7)'
rodar --raiz "$SB/longo"
saiu "verbete com linha acima de 900 B: exit 1"  "$C" 1
tem  "linha acima de 900 B: diz o limite"        "$S" "passa de 900 B"
rodar --raiz "$SB/semverbete"
saiu "arquivo sem nenhum verbete: exit 1"        "$C" 1
tem  "arquivo sem verbete: diz que nenhum verbete foi lido" "$S" "nenhum verbete lido"
rodar --raiz "$SB/so_cerca"
saiu "verbete so dentro de cerca de codigo: exit 1" "$C" 1
tem  "so em cerca: diz que nenhum verbete foi lido" "$S" "nenhum verbete lido"
rodar --raiz "$SB/caminho_inexistente" --caminhos
saiu "--caminhos recusa caminho que nao existe em Onde mora: exit 1" "$C" 1
tem  "caminho em Onde mora: nomeia o caminho"    "$S" 'caminho "hooks/nao-existe.cjs" não existe'
rodar --raiz "$SB/caminho_cenario" --caminhos
saiu "--caminhos recusa caminho que nao existe em Cenario: exit 1" "$C" 1
tem  "caminho em Cenario: nomeia o campo e o caminho" "$S" 'campo Cenário: caminho "scripts/sumiu.cjs" não existe'

echo
echo "== 3. --exigir, --listar e --caminhos =="
rodar --raiz "$SB/ausente" --exigir
saiu "--exigir sem GLOSSARIO.md: exit 1"         "$C" 1
tem  "--exigir sem GLOSSARIO.md: diz que esta ausente" "$S" "ausente"
rodar --raiz "$SB/d7" --listar
saiu "--listar: exit 0"                          "$C" 0
tem  "--listar: lista fluxo com o evite"         "$S" "fluxo | evite: esteira, pipeline"
tem  "--listar: lista worktree de agente com o evite" "$S" "worktree de agente | evite: clone, cópia do repo"
tem  "--listar: lista territorio sem evite"      "$S" "território"
rodar --raiz "$SB/listainv" --listar
saiu "--listar com verbete invalido: exit 0"     "$C" 0
tem  "--listar: avisa quantos ignorou"           "$S" "1 verbete(s) inválido(s) ignorado(s)"
nao_tem "--listar: nao lista o verbete invalido" "$S" "ruim"
tem  "--listar: lista o verbete valido"          "$S" "bom"
rodar --raiz
saiu "--raiz sem valor: exit 2 (uso)"            "$C" 2
rodar --raiz "$SB/caminho_inexistente"
saiu "sem --caminhos, o mesmo caminho nao e checado: exit 0" "$C" 0

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
echo "$falhou falha(s)"
[ "$falhou" -eq 0 ]
