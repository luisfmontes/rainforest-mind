#!/bin/bash
# Bateria do `setup.cjs --plano-entrevista` (tarefa 3 de 2026-10-17-setup-entrevista-guiada;
# D1, D4, D8, D10 e D11 de docs/rainforest/design/2026-10-17-setup-entrevista-guiada.md).
# Uso: bash scripts/testa-setup-entrevista.sh
#
# Caixa de areia com mktemp -d. Nada aqui toca a pasta de dados real nem o ~/.claude:
# RFM_ROOT, CLAUDE_CONFIG_DIR, CLAUDE_PROJECT_DIR e USERPROFILE apontam para a caixa
# (no Windows o raiz.cjs le USERPROFILE antes de HOME).
#
# Dois cuidados que a caixa exige. RFM_ROOT definida faz o raiz.cjs devolver a raiz
# mesmo que a pasta nao exista, entao o caso "pasta de dados ausente" tira RFM_ROOT do
# ambiente. E o `codex` desta maquina e `codex.cmd` (npm): o caso "ferramenta ausente"
# tira a pasta dele do PATH mantendo a do node.
#
# Cada caso roda o modo, grava a saida em arquivo e olha o JSON com `node -e`. Nenhum
# caso le o texto do fonte do setup.cjs.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
w() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

SETUP_JS="$SRC/scripts/setup.cjs"
CONFIG_JS="$(w "$SRC/hooks/lib/config.cjs")"
NODE_BIN="$(command -v node)"

DADOS="$CAIXA/dados"; HOME_CX="$CAIXA/home"; CFG="$CAIXA/cfg"; PROJ="$CAIXA/proj"
REPO="$CAIXA/repo-de-caixa"; REPO_B="$CAIXA/repo-b"; SEM_GIT="$CAIXA/sem-git"
mkdir -p "$DADOS" "$HOME_CX" "$CFG/projects" "$PROJ"
# ehRepoGit so olha a EXISTENCIA de .git (pasta ou arquivo): basta a pasta.
mkdir -p "$REPO/.git" "$REPO_B/.git" "$SEM_GIT"
REPO_WIN="$(w "$REPO")"
# Setup feito: a pasta tem FOCO.md. Sem ele a pasta conta como primeira vez (D1), e a
# secao 9 espera primeira_vez false.
printf '# Foco\n' > "$DADOS/FOCO.md"

# Transcrito no formato real do Claude Code: as tres primeiras linhas nao tem `cwd`;
# a primeira que tem e a `attachment`.
transcrito() { # <pasta em projects/> <cwd>
  local dir="$CFG/projects/$1"; mkdir -p "$dir"
  {
    echo '{"type":"last-prompt","lastPrompt":"oi"}'
    echo '{"type":"mode","mode":"default"}'
    echo '{"type":"permission-mode","permissionMode":"default"}'
    printf '{"type":"attachment","cwd":"%s","sessionId":"s1"}\n' "$2"
  } > "$dir/sessao.jsonl"
}
transcrito x "$REPO_WIN"
transcrito w "$(w "$REPO_B")"
transcrito y "$(w "$SEM_GIT")"
transcrito z "$(w "$CAIXA/nao-existe")"

BASE=(RFM_ROOT="$(w "$DADOS")" USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ")")
SEM_RAIZ=(USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ")")

# PATH sem o codex: a pasta do node (onde ele mora) e o System32, nada de npm.
NODE_DIR_WIN="$(cygpath -w "$(dirname "$NODE_BIN")")"
SYS_WIN="${SYSTEMROOT:-C:/WINDOWS}/System32"
PATH_SEM_CODEX="$NODE_DIR_WIN;$SYS_WIN"
if command -v codex >/dev/null 2>&1; then ESP_CODEX=true; else ESP_CODEX=false; fi

plano() { # <saida> <args do env...>: roda o modo com o ambiente dado
  local saida="$1"; shift
  env "$@" "$NODE_BIN" "$SETUP_JS" --plano-entrevista > "$saida" 2> "$saida.err"
}

# Tarefa 4 (--aplicar): o ambiente da caixa com RFM_ROOT numa pasta dada, e payloads em arquivo.
ap() { # <pasta de dados> <comando...>
  local dados="$1"; shift
  env RFM_ROOT="$(w "$dados")" USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ")" "$@"
}
arq() { # <nome> <texto>: grava o payload na caixa e devolve o caminho
  local f="$CAIXA/$1"; printf '%s' "$2" > "$f"; printf '%s' "$f"
}
hash_de() { find "$1" -type f -exec sha1sum {} + | sort; }
resultado() { # nome, status (0 = passou)
  if [ "$2" = 0 ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1"; fi
}

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
verifica() { # nome, saida, expressao JS sobre `j` (o JSON da saida)
  local nome="$1" saida="$2" expr="$3"
  if node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); process.exit((${expr}) ? 0 : 1);" "$(w "$saida")" 2>/dev/null; then
    ok=$((ok+1)); echo "  ok   $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome"; head -c 600 "$saida" | sed 's/^/         /'; echo; head -3 "$saida.err" 2>/dev/null | sed 's/^/         stderr: /'
  fi
}
hash_dados() { find "$DADOS" -type f -exec sha1sum {} + | sort; }
chave_em_passos() { # chave -> expressao que devolve o item da chave em passos
  printf "j.passos.flatMap(p => p.chaves).find(c => c.chave === '%s')" "$1"
}

echo "== 1. pasta de dados ausente e primeira vez =="
A="$CAIXA/saida-1.json"
esperado "modo sai 0 sem RFM_ROOT e sem pasta de dados" 0 plano "$A" -u RFM_ROOT "${SEM_RAIZ[@]}"
verifica "primeira_vez true e nivel null sem nenhuma raiz" "$A" "j.primeira_vez === true && j.nivel === null"

echo
echo "== 2. passos na ordem de GRUPOS_ENTREVISTA, com os grupos vazios presentes =="
B="$CAIXA/saida-2.json"
plano "$B" "${BASE[@]}"
verifica "grupos de passos = GRUPOS_ENTREVISTA, na mesma ordem" "$B" \
  "JSON.stringify(j.passos.map(p => p.grupo)) === JSON.stringify(require('$CONFIG_JS').GRUPOS_ENTREVISTA)"
verifica "dados, projetos e estrategia aparecem com chaves: []" "$B" \
  "['dados','projetos','estrategia'].every(g => j.passos.find(p => p.grupo === g).chaves.length === 0)"
verifica "foco traz a chave foco (2.0.0: liga o radar, nasce false)" "$B" \
  "JSON.stringify(j.passos.find(p => p.grupo === 'foco').chaves.map(c => c.chave)) === '[\"foco\"]'"

echo
echo "== 3. ferramenta ausente no PATH nao vira pergunta =="
C="$CAIXA/saida-3.json"
plano "$C" "${BASE[@]}" PATH="$PATH_SEM_CODEX"
verifica "ponte-codex sem codex no PATH: detectado false e perguntar false" "$C" \
  "(c => c.detectado === false && c.perguntar === false)($(chave_em_passos ponte-codex))"
C2="$CAIXA/saida-3b.json"
plano "$C2" "${BASE[@]}"
verifica "controle: com o PATH cheio, ponte-codex segue o que a maquina tem ($ESP_CODEX)" "$C2" \
  "(c => c.detectado === $ESP_CODEX && c.perguntar === $ESP_CODEX)($(chave_em_passos ponte-codex))"

echo
echo "== 4. env ausente: conselho-gemini nao vira pergunta; env presente: vira =="
D="$CAIXA/saida-4a.json"
plano "$D" -u GEMINI_API_KEY "${BASE[@]}"
verifica "conselho-gemini sem GEMINI_API_KEY: detectado false e perguntar false" "$D" \
  "(c => c.detectado === false && c.perguntar === false)($(chave_em_passos conselho-gemini))"
E="$CAIXA/saida-4b.json"
plano "$E" "${BASE[@]}" GEMINI_API_KEY=x
verifica "conselho-gemini com GEMINI_API_KEY: detectado true e perguntar true" "$E" \
  "(c => c.detectado === true && c.perguntar === true)($(chave_em_passos conselho-gemini))"

echo
echo "== 5. nenhuma chave de entrevista null em passos, todas em fixas =="
F="$CAIXA/saida-5.json"
plano "$F" "${BASE[@]}"
verifica "passos so com chaves de entrevista; fixas so com null; juntas = CHAVES" "$F" \
  "(() => {
    const C = require('$CONFIG_JS').CHAVES;
    const emP = j.passos.flatMap(p => p.chaves.map(c => c.chave));
    const emF = j.fixas.map(f => f.chave);
    const todas = [...emP, ...emF];
    return emP.every(k => C[k].entrevista !== null)
      && emF.every(k => C[k].entrevista === null)
      && todas.length === Object.keys(C).length
      && new Set(todas).size === Object.keys(C).length;
  })()"

echo
echo "== 6. transcrito real sugere o projeto =="
G="$CAIXA/saida-6.json"
plano "$G" "${BASE[@]}"
verifica "sugestoes.projetos traz o repo de caixa (slug e caminho)" "$G" \
  "j.sugestoes.projetos.some(p => p.caminho === '$REPO_WIN' && p.slug === 'repo-de-caixa')"

echo
echo "== 7. cwd sem .git ou inexistente nao e sugerido =="
H="$CAIXA/saida-7.json"
plano "$H" "${BASE[@]}"
verifica "pasta sem .git e pasta inexistente ficam fora; o repo-b (controle) entra" "$H" \
  "!j.sugestoes.projetos.some(p => /sem-git|nao-existe/.test(p.caminho)) && j.sugestoes.projetos.some(p => p.slug === 'repo-b')"

echo
echo "== 8. projeto ja registrado nao e sugerido de novo =="
esperado "registra outro-slug com o caminho do repo de caixa" 0 env "${BASE[@]}" "$NODE_BIN" "$SETUP_JS" --projeto outro-slug --caminho "$REPO_WIN"
esperado "registra repo-b com caminho diferente (so o slug conta)" 0 env "${BASE[@]}" "$NODE_BIN" "$SETUP_JS" --projeto repo-b --caminho "$(w "$CAIXA/lugar-diferente")"
I="$CAIXA/saida-8.json"
plano "$I" "${BASE[@]}"
verifica "caminho ja registrado sob outro slug fica de fora" "$I" \
  "!j.sugestoes.projetos.some(p => p.caminho === '$REPO_WIN')"
verifica "slug ja registrado fica de fora, mesmo com caminho diferente" "$I" \
  "!j.sugestoes.projetos.some(p => p.slug === 'repo-b')"

echo
echo "== 9. nada e gravado =="
esperado "liga ponte-codex para existir um config.json de usuario" 0 env "${BASE[@]}" "$NODE_BIN" "$SETUP_JS" --ligar ponte-codex
cfg_antes="$(sha1sum < "$DADOS/config.json")"
arvore_antes="$(hash_dados)"
J="$CAIXA/saida-9.json"
plano "$J" "${BASE[@]}"
cfg_depois="$(sha1sum < "$DADOS/config.json")"
arvore_depois="$(hash_dados)"
if [ "$cfg_antes" = "$cfg_depois" ]; then ok=$((ok+1)); echo "  ok   hash do config.json igual antes e depois"
else falhou=$((falhou+1)); echo "  FALHA hash do config.json mudou"; fi
if [ "$arvore_antes" = "$arvore_depois" ]; then ok=$((ok+1)); echo "  ok   nenhum arquivo da pasta de dados mudou"
else falhou=$((falhou+1)); echo "  FALHA a pasta de dados mudou"; fi
verifica "e a saida continua sendo o JSON da entrevista" "$J" "j.primeira_vez === false && Array.isArray(j.passos)"

echo
echo "== 10. worktree de agente nao e sugerido como projeto =="
mkdir -p "$REPO/.claude/worktrees/agent-x/.git" "$CAIXA/repo-c/.git"
transcrito v "$(w "$REPO/.claude/worktrees/agent-x")"
transcrito u "$(w "$CAIXA/repo-c")"
K="$CAIXA/saida-10.json"
plano "$K" "${BASE[@]}"
verifica "worktree de agente fica de fora; repo-c (controle) entra" "$K" \
  "!j.sugestoes.projetos.some(p => /worktrees/.test(p.caminho) || p.slug === 'agent-x') && j.sugestoes.projetos.some(p => p.slug === 'repo-c')"

echo
echo "== 11. --aplicar: payload invalido nao grava nada =="
AP1="$CAIXA/ap1"
ap "$AP1" "$NODE_BIN" "$SETUP_JS" --ligar ponte-gemini > /dev/null
AP1_ANTES="$(sha1sum < "$AP1/config.json")"
ap "$AP1" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq inv.json '{"chaves":{"ponte-codex":true,"chave-inexistente":true}}')" > "$CAIXA/inv.out" 2> "$CAIXA/inv.err"; got=$?
[ "$got" = 2 ]; resultado "payload com uma chave invalida: exit 2" $?
grep -q "chave-inexistente" "$CAIXA/inv.err"; resultado "payload com uma chave invalida: stderr nomeia chave-inexistente" $?
grep -q "^erro: " "$CAIXA/inv.err"; resultado "payload com uma chave invalida: erro sai com o prefixo 'erro: '" $?
[ "$(sha1sum < "$AP1/config.json")" = "$AP1_ANTES" ]; resultado "payload com uma chave invalida: config.json de usuario com o mesmo hash" $?
ap "$AP1" "$NODE_BIN" "$SETUP_JS" --ligado ponte-codex > /dev/null; got=$?
[ "$got" = 1 ]; resultado "payload com uma chave invalida: --ligado ponte-codex continua 1" $?

ap "$AP1" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq tipo.json '{"chaves":{"ponte-codex":"sim"}}')" > "$CAIXA/tipo.out" 2> "$CAIXA/tipo.err"; got=$?
[ "$got" = 2 ]; resultado "valor de tipo errado (\"sim\" em ponte-codex): exit 2" $?
grep -q "ponte-codex" "$CAIXA/tipo.err"; resultado "valor de tipo errado: stderr nomeia ponte-codex" $?
[ "$(sha1sum < "$AP1/config.json")" = "$AP1_ANTES" ]; resultado "valor de tipo errado: config.json com o mesmo hash" $?

LONGO="$(printf '%061d' 0)"
ap "$AP1" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq longo.json "{\"chaves\":{\"idioma\":\"$LONGO\"}}")" > "$CAIXA/longo.out" 2> "$CAIXA/longo.err"; got=$?
[ "$got" = 2 ]; resultado "texto com 61 caracteres (limite e 60): exit 2" $?
[ "$(sha1sum < "$AP1/config.json")" = "$AP1_ANTES" ]; resultado "texto com 61 caracteres: config.json com o mesmo hash" $?

ap "$AP1" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq pastas.json '{"chaves":{"pastas":{"design":"docs/plans"}}}')" > /dev/null 2>&1; got=$?
[ "$got" = 0 ]; resultado "pastas valido: exit 0" $?
LIDO="$(node -e "process.stdout.write(JSON.stringify(require(process.argv[1]).resolverConfig({ dados: process.argv[2], projeto: process.argv[3] }).valores.pastas))" "$CONFIG_JS" "$(w "$AP1")" "$(w "$PROJ")")"
[ "$LIDO" = '{"design":"docs/plans"}' ]; resultado "pastas gravado pelo --aplicar volta igual pelo resolverConfig" $?

echo
echo "== 12. --ensaio mostra antes e depois e nao grava =="
AP3="$CAIXA/ap3"
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --criar > /dev/null
ENS="$(arq ensaio.json "{\"chaves\":{\"ponte-codex\":true,\"idioma\":\"portugues do Brasil\"},\"projetos\":[{\"slug\":\"meu-repo\",\"caminho\":\"$REPO_WIN\"}],\"estrategia\":\"Frente unica\"}")"
ARV_ANTES="$(hash_de "$AP3")"
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$ENS" --ensaio > "$CAIXA/ens.out" 2> "$CAIXA/ens.err"; got=$?
[ "$got" = 0 ]; resultado "--aplicar --ensaio sai 0" $?
grep -q "^ponte-codex: false -> true$" "$CAIXA/ens.out"; resultado "ensaio mostra 'ponte-codex: false -> true'" $?
grep -q "^idioma: null -> " "$CAIXA/ens.out"; resultado "ensaio mostra antes e depois de idioma" $?
grep -q "^projeto meu-repo: .* (novo)$" "$CAIXA/ens.out"; resultado "ensaio diz que o projeto e novo" $?
grep -q "^ESTRATEGIA.md: cria$" "$CAIXA/ens.out"; resultado "ensaio diz que ESTRATEGIA.md seria criada" $?
grep -q "^escopo: usuario " "$CAIXA/ens.out"; resultado "ensaio traz o escopo em que gravaria" $?
[ "$(hash_de "$AP3")" = "$ARV_ANTES" ]; resultado "ensaio nao muda nenhum arquivo da pasta de dados" $?

echo
echo "== 13. --aplicar grava no escopo usuario; FOCO.md nao e tocado; ESTRATEGIA.md nasce =="
FOCO_ANTES="$(sha1sum < "$AP3/FOCO.md")"
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$ENS" > "$CAIXA/apl.out" 2> "$CAIXA/apl.err"; got=$?
[ "$got" = 0 ]; resultado "--aplicar grava e sai 0" $?
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --ligado ponte-codex > /dev/null; got=$?
[ "$got" = 0 ]; resultado "aplicar grava no escopo usuario: --ligado ponte-codex sai 0" $?
[ ! -e "$PROJ/.rainforest/config.json" ]; resultado "aplicar grava no escopo usuario: .rainforest/config.json do projeto continua inexistente" $?
[ "$(sha1sum < "$AP3/FOCO.md")" = "$FOCO_ANTES" ]; resultado "FOCO.md com o mesmo hash depois do --aplicar" $?
grep -q "^Frente unica$" "$AP3/ESTRATEGIA.md"; resultado "estrategia nasce se ausente, com o texto do payload" $?
H_EST="$(sha1sum < "$AP3/ESTRATEGIA.md")"
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq est2.json '{"estrategia":"outro texto"}')" > /dev/null 2>&1; got=$?
[ "$got" = 0 ]; resultado "estrategia com ESTRATEGIA.md existente: exit 0" $?
[ "$(sha1sum < "$AP3/ESTRATEGIA.md")" = "$H_EST" ]; resultado "estrategia existente mantem o hash" $?

echo
echo "== 14. primeira vez: aplicar cria a pasta antes de gravar; FOCO.md so vem do criar =="
REF="$CAIXA/ref"
ap "$REF" "$NODE_BIN" "$SETUP_JS" --criar > /dev/null
NOVA="$CAIXA/dados-novos"
ap "$NOVA" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq novo.json '{"chaves":{"ponte-codex":true},"estrategia":"TEXTO-DO-PAYLOAD"}')" > "$CAIXA/nova.out" 2> "$CAIXA/nova.err"; got=$?
[ "$got" = 0 ]; resultado "primeira vez: --aplicar sai 0" $?
[ -f "$NOVA/config.json" ] && [ -f "$NOVA/FOCO.md" ]; resultado "primeira vez: a pasta de dados e criada e recebe config.json" $?
[ "$(sha1sum < "$NOVA/FOCO.md")" = "$(sha1sum < "$REF/FOCO.md")" ]; resultado "primeira vez: FOCO.md tem o conteudo que o --criar semeia" $?
! grep -q "TEXTO-DO-PAYLOAD" "$NOVA/FOCO.md"; resultado "primeira vez: FOCO.md nao recebe texto do payload" $?
grep -q "TEXTO-DO-PAYLOAD" "$NOVA/ESTRATEGIA.md"; resultado "primeira vez: ESTRATEGIA.md nasce com o texto do payload" $?

echo
echo "== 15. pasta vazia conta como primeira vez; pasta do projeto nao recebe config de usuario =="
VAZIA="$CAIXA/dados-vazios"; mkdir -p "$VAZIA"
ap "$VAZIA" "$NODE_BIN" "$SETUP_JS" --plano-entrevista > "$CAIXA/vazia.json" 2> "$CAIXA/vazia.err"
verifica "pasta de dados vazia conta como primeira vez" "$CAIXA/vazia.json" "j.primeira_vez === true"
PROJ2="$CAIXA/proj2"; mkdir -p "$PROJ2/.rainforest"; printf '# Foco\n' > "$PROJ2/.rainforest/FOCO.md"
env -u RFM_ROOT USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ2")" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq p2.json '{"chaves":{"ponte-codex":true}}')" > "$CAIXA/p2.out" 2> "$CAIXA/p2.err"; got=$?
[ "$got" = 2 ]; resultado "pasta do projeto e a sessao: 'usuario' recusado, exit 2" $?
[ ! -e "$PROJ2/.rainforest/config.json" ]; resultado "pasta do projeto segue sem config.json" $?

echo
echo "== 16. --aplicar: caminho inexistente e escopo invalido recusados sem gravar =="
REJ="$(arq rej.json "{\"projetos\":[{\"slug\":\"ok-slug\",\"caminho\":\"$(w "$CAIXA/nao-existe")\"}]}")"
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$REJ" > "$CAIXA/rej.out" 2> "$CAIXA/rej.err"; got=$?
[ "$got" = 2 ]; resultado "caminho de projeto inexistente: exit 2" $?
grep -q "nao existe" "$CAIXA/rej.err"; resultado "caminho de projeto inexistente: stderr diz que nao existe" $?
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$ENS" --escopo outro > /dev/null 2> "$CAIXA/esc.err"; got=$?
[ "$got" = 2 ]; resultado "escopo invalido: exit 2" $?

echo
echo "== 17. --escopo projeto grava no projeto e avisa do commit =="
ap "$AP3" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq proj.json '{"chaves":{"ponte-codex":true}}')" --escopo projeto > "$CAIXA/pj.out" 2> "$CAIXA/pj.err"; got=$?
[ "$got" = 0 ]; resultado "--escopo projeto sai 0" $?
[ -f "$PROJ/.rainforest/config.json" ]; resultado "--escopo projeto grava em <projeto>/.rainforest/config.json" $?
grep -q "pode ir para o commit" "$CAIXA/pj.out"; resultado "--escopo projeto avisa que o config pode ir para o commit" $?

echo
echo "== 18. ensaio com raiz do plugin mostra o destino real =="
# Raiz do plugin = uma copia do setup e do hooks/lib com FOCO.md e ESTRATEGIA.md. Sem RFM_ROOT
# e com o home vazio, o resolverRaiz cai no nivel plugin. O ensaio tem de mostrar onde o
# --aplicar VAI gravar (o home), nao a pasta do plugin.
PLG="$CAIXA/plugin-cx"; mkdir -p "$PLG/scripts" "$PLG/hooks"
cp "$SETUP_JS" "$PLG/scripts/setup.cjs"; cp -r "$SRC/hooks/lib" "$PLG/hooks/lib"
printf '# Foco\n' > "$PLG/FOCO.md"; printf '# Estrategia do plugin\n' > "$PLG/ESTRATEGIA.md"
# O plugin ja tem o slug que o payload registra: se o ensaio lesse o vocabulario do plugin, diria "ja registrado".
printf '%s\n' '{"repo-pl":{"caminho":"/caminho/de/outro","apelidos":[]}}' > "$PLG/projetos.json"
HOME_PL="$CAIXA/home-plugin"; PROJ5="$CAIXA/proj5"; mkdir -p "$HOME_PL" "$PROJ5"
PLG_SETUP="$PLG/scripts/setup.cjs"
pl() { env -u RFM_ROOT USERPROFILE="$(w "$HOME_PL")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ5")" "$@"; }
pl "$NODE_BIN" "$PLG_SETUP" --plano-entrevista > "$CAIXA/pl-plano.json" 2> "$CAIXA/pl-plano.err"
verifica "pre-condicao: a raiz do plugin resolve como nivel plugin" "$CAIXA/pl-plano.json" "j.primeira_vez === true && j.nivel === 'plugin'"
PAY_PL="$(arq pl.json "{\"chaves\":{\"ponte-codex\":true},\"estrategia\":\"TEXTO-PLUGIN\",\"projetos\":[{\"slug\":\"repo-pl\",\"caminho\":\"$REPO_WIN\"}]}")"
PL_HASH="$(hash_de "$PLG")"
DEST_PL="$(node -e 'process.stdout.write(require("path").join(process.argv[1], ".rainforest"))' "$(w "$HOME_PL")")"
pl "$NODE_BIN" "$PLG_SETUP" --aplicar "$PAY_PL" --ensaio > "$CAIXA/pl-ens.out" 2> "$CAIXA/pl-ens.err"; got=$?
[ "$got" = 0 ]; resultado "ensaio com raiz do plugin sai 0" $?
grep -qxF "ESTRATEGIA.md: cria" "$CAIXA/pl-ens.out"; resultado "ensaio com raiz do plugin mostra o destino real: ESTRATEGIA.md cria" $?
grep -qxF "escopo: usuario ($DEST_PL)" "$CAIXA/pl-ens.out"; resultado "ensaio com raiz do plugin mostra o destino real: escopo no home de caixa" $?
grep -qxF "projeto repo-pl: $REPO_WIN (novo)" "$CAIXA/pl-ens.out"; resultado "ensaio com raiz do plugin mostra o destino real: projeto novo no home de caixa" $?
[ ! -e "$HOME_PL/.rainforest" ] && [ "$(hash_de "$PLG")" = "$PL_HASH" ]; resultado "ensaio com raiz do plugin nao grava nada" $?
pl "$NODE_BIN" "$PLG_SETUP" --aplicar "$PAY_PL" > "$CAIXA/pl-apl.out" 2> "$CAIXA/pl-apl.err"; got=$?
[ "$got" = 0 ]; resultado "ensaio com raiz do plugin: --aplicar sai 0" $?
grep -q "TEXTO-PLUGIN" "$HOME_PL/.rainforest/ESTRATEGIA.md" 2>/dev/null; resultado "ensaio com raiz do plugin: o --aplicar grava o ESTRATEGIA.md onde o ensaio disse" $?
[ -f "$HOME_PL/.rainforest/config.json" ] && [ -f "$HOME_PL/.rainforest/FOCO.md" ]; resultado "ensaio com raiz do plugin: o --aplicar grava config.json e FOCO.md no mesmo destino" $?
[ "$(hash_de "$PLG")" = "$PL_HASH" ]; resultado "ensaio com raiz do plugin: a pasta do plugin fica intacta depois do --aplicar" $?

echo
echo "== 19. ensaio avisa quando o projeto vence o escopo usuario =="
PROJ6="$CAIXA/proj6"; mkdir -p "$PROJ6/.rainforest"; printf '%s' '{"ponte-codex": false}' > "$PROJ6/.rainforest/config.json"
ENS6="$(arq ens6.json '{"chaves":{"ponte-codex":true,"idioma":"portugues do Brasil"}}')"
env RFM_ROOT="$(w "$DADOS")" USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ6")" "$NODE_BIN" "$SETUP_JS" --aplicar "$ENS6" --ensaio > "$CAIXA/ens6.out" 2> "$CAIXA/ens6.err"; got=$?
[ "$got" = 0 ]; resultado "ensaio com projeto vencendo sai 0" $?
grep -q "^ponte-codex: false -> true (AVISO: .*vence o escopo usuario" "$CAIXA/ens6.out"; resultado "ensaio avisa quando o projeto vence o escopo usuario" $?
! grep -q "^idioma: .*AVISO" "$CAIXA/ens6.out"; resultado "ensaio avisa quando o projeto vence o escopo usuario: sem aviso onde o valor nao vem do projeto" $?
env RFM_ROOT="$(w "$DADOS")" USERPROFILE="$(w "$HOME_CX")" CLAUDE_CONFIG_DIR="$(w "$CFG")" CLAUDE_PROJECT_DIR="$(w "$PROJ6")" "$NODE_BIN" "$SETUP_JS" --aplicar "$ENS6" --ensaio --escopo projeto > "$CAIXA/ens7.out" 2>&1
! grep -q "AVISO" "$CAIXA/ens7.out"; resultado "ensaio avisa quando o projeto vence o escopo usuario: com --escopo projeto nao ha aviso" $?

echo
echo "== 20. config.json ilegivel recusa sem sobrescrever =="
ILEG="$CAIXA/dados-ileg"; mkdir -p "$ILEG"; printf '# Foco\n' > "$ILEG/FOCO.md"
printf '%s' '{"gate-staging": false, "fluxo": false,}' > "$ILEG/config.json"
ILEG_HASH="$(sha1sum < "$ILEG/config.json")"
ap "$ILEG" "$NODE_BIN" "$SETUP_JS" --aplicar "$(arq ileg.json '{"chaves":{"ponte-codex":true}}')" > "$CAIXA/ileg.out" 2> "$CAIXA/ileg.err"; got=$?
[ "$got" = 2 ]; resultado "config.json ilegivel recusa sem sobrescrever: exit 2" $?
[ "$(sha1sum < "$ILEG/config.json")" = "$ILEG_HASH" ]; resultado "config.json ilegivel recusa sem sobrescrever: hash igual antes e depois" $?
grep -q "nao e JSON valido; corrija ou apague antes de aplicar" "$CAIXA/ileg.err"; resultado "config.json ilegivel recusa sem sobrescrever: stderr aponta a recusa" $?

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
