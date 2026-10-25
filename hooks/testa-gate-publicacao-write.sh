#!/bin/bash
# rainforest-gate: dados-de-exemplo
# Bateria do Write no gate-publicacao-destino.cjs (D8 do lote 6). O Write usa o
# conteudo atual do disco como `antigo`, e so o que a escrita introduz barra.
# Monta repo git de verdade com remoto GitHub publico simulado (gh stub) e alimenta
# o hook com payloads montados por `node`, conferindo exit code.
# Uso: bash hooks/testa-gate-publicacao-write.sh
#
# O que esta bateria precisa provar:
#   1. Write que reescreve arquivo com a linha sensivel ja existente passa
#   2. Write que acrescenta uma segunda ocorrencia nova barra
#   3. Write de arquivo novo com a linha sensivel barra
#   4. Write com caminho relativo resolve contra o cwd do evento (passa)
#   5. o commit com a linha nova segue barrado (o gate do commit nao muda)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-publicacao-destino.cjs"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Dublê de gh: responde a visibilidade do remoto (publico por padrao).
SANDBOX_BIN="$RAIZ/bin"; mkdir -p "$SANDBOX_BIN"
cat > "$SANDBOX_BIN/gh" << 'GHSTUB'
#!/usr/bin/env node
if (process.argv[2] === 'repo' && process.argv[3] === 'view') {
  console.log(process.env.GH_RESPONSE || '{"isPrivate":false}');
  process.exit(0);
}
process.exit(0);
GHSTUB
chmod +x "$SANDBOX_BIN/gh"

# Ambiente isolado de cada chamada do gate: sem HOME, dados ou gh reais.
AMBIENTE=(env HOME="$RAIZ/home" RFM_ROOT="$RAIZ/dados" GH_RESPONSE='{"isPrivate":false}' RAINFOREST_GH="node $SANDBOX_BIN/gh")

# Repo com remoto GitHub publico e um arquivo versionado que ja tem a linha sensivel.
R="$RAIZ/repo"
git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
git -C "$R" remote add origin "https://github.com/test/write-lote6.git"
mkdir -p "$R/docs"
printf '%s\n' "# Contatos" "telefone do cliente: (00) 90000-0001" "nota: versao um" > "$R/docs/contato.md"
git -C "$R" add -A; git -C "$R" commit -qm base

# Payloads montados por `node` (nunca printf): valor em argv, sem nivel de escape.
payWrite() { # arquivo, conteudo, cwd
  node -e 'const [fp,c,cwd]=process.argv.slice(1);console.log(JSON.stringify({cwd,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:fp,content:c}}))' "$1" "$2" "$3"
}
payBash() { # comando, cwd
  node -e 'const [cmd,cwd]=process.argv.slice(1);console.log(JSON.stringify({cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:cmd}}))' "$1" "$2"
}

gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | "${AMBIENTE[@]}" node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -10; fi
}

TEL="(00) 90000-0001"

echo
echo "== CASO 1: Write que reescreve arquivo com a linha sensivel ja existente passa =="
gate "Write que reescreve arquivo com a linha sensível já existente passa" 0 \
  "$(payWrite "$R/docs/contato.md" "$(printf '%s\n' "# Contatos" "telefone do cliente: $TEL" "nota: versao dois")" "$R")"

echo
echo "== CASO 2: Write que acrescenta uma segunda ocorrencia nova barra (exit 2) =="
gate "Write que acrescenta segunda ocorrência do telefone barra" 2 \
  "$(payWrite "$R/docs/contato.md" "$(printf '%s\n' "# Contatos" "telefone do cliente: $TEL" "nota: versao um" "telefone do cliente: $TEL")" "$R")"

echo
echo "== CASO 3: Write de arquivo novo com a linha sensivel barra (exit 2) =="
gate "Write de arquivo novo com telefone barra" 2 \
  "$(payWrite "$R/docs/novo.md" "$(printf '%s\n' "# Novo" "telefone do cliente: $TEL")" "$R")"

echo
echo "== CASO 4: caminho relativo resolve contra o cwd do evento (exit 0) =="
gate "Write com caminho relativo reescrevendo a linha existente passa" 0 \
  "$(payWrite "docs/contato.md" "$(printf '%s\n' "# Contatos" "telefone do cliente: $TEL" "nota: versao tres")" "$R")"

echo
echo "== CASO 5: o commit com a linha nova segue barrado (exit 2) =="
printf '%s\n' "# Commit" "telefone do cliente: $TEL" > "$R/docs/commit.md"
git -C "$R" add docs/commit.md
gate "commit com telefone novo staged segue barrado" 2 "$(payBash "git commit -m x" "$R")"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
if [ "$falhou" = 0 ]; then exit 0; else exit 1; fi
