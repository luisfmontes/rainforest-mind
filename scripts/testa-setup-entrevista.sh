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
verifica "dados, projetos, estrategia e foco aparecem com chaves: []" "$B" \
  "['dados','projetos','estrategia','foco'].every(g => j.passos.find(p => p.grupo === g).chaves.length === 0)"

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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
