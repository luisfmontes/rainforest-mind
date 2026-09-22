#!/bin/bash
# Bateria do gate-mensagem-commit.cjs. Monta repos git de verdade e alimenta
# o hook com payloads reais de PreToolUse, conferindo o exit code.
# Uso: bash hooks/testa-gate-mensagem-commit.sh
#
# O que esta bateria precisa provar, nesta ordem:
#   1. que BARRA (exit 2) diff grande sem corpo, assunto invalido (vazio,
#      longo demais, com ponto final) e mensagem nao resolvivel (-F -,
#      heredoc, nem -m nem -F — inclusive `git commit` pelado);
#   2. que PASSA (exit 0) commit pequeno so com assunto, diff grande COM
#      corpo de verdade, `-F <arquivo>` com corpo, flag de reuso
#      (--amend --no-edit, -C, -c), comando sem `git commit`, e fora de
#      repo git;
#   3. que trailer (`Co-Authored-By:`) sozinho NAO conta como corpo.
#
# E-mail de git config e do trailer de teste: forma "usuario arroba dominio
# sem ponto" (o mesmo padrao de TODAS as outras baterias deste repo:
# testa-gate-staging-total.sh, testa-gate-git-verificacao.sh, ...) — o gate
# de publicacao deste repo recusa gravar arquivo versionado que contenha
# qualquer texto no FORMATO de e-mail com domino pontuado (barrou esta
# bateria na primeira tentativa, com um dominio de exemplo pontuado).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-mensagem-commit.cjs"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Mesmo mecanismo de testa-gate-staging-total.sh (Issue #160/#81): raiz de
# dados descartavel, nunca a config real de quem roda a bateria.
export RFM_ROOT="$RAIZ/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}
# Como `gate()`, mas confere tambem que o stderr contem um trecho literal.
gate_contendo() { # nome, exit esperado, trecho esperado, json
  local nome="$1" esp="$2" trecho="$3" json="$4"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; return; fi
  if printf '%s' "$saida" | grep -qF -- "$trecho"; then ok=$((ok+1)); echo "  ok   ... e o stderr contem '$trecho'"
  else falhou=$((falhou+1)); echo "  FALHA ... o stderr NAO contem '$trecho'"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

payload() { # cwd, tool_name, command
  node -e 'const [cwd,tool,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:tool,tool_input:{command:cmd}}))' "$1" "$2" "$3"
}

repo_novo() { # dir
  git init -q "$1"
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
  echo base > "$1/base.txt"; git -C "$1" add base.txt; git -C "$1" commit -qm base
}

# R4: repo com 4 arquivos em stage (dispara "mais de 3 arquivos").
R4="$RAIZ/repo4"; repo_novo "$R4"
for i in 1 2 3 4; do echo "linha $i" > "$R4/arquivo$i.txt"; git -C "$R4" add "arquivo$i.txt"; done

# R3: repo com 3 arquivos e 20 linhas em stage (nao dispara — 3 nao e >3, 20 nao e >150).
R3="$RAIZ/repo3"; repo_novo "$R3"
for j in $(seq 1 10); do echo "l$j" >> "$R3/a.txt"; done
for j in $(seq 1 5); do echo "l$j" >> "$R3/b.txt"; done
for j in $(seq 1 5); do echo "l$j" >> "$R3/c.txt"; done
git -C "$R3" add a.txt b.txt c.txt

# R1: repo minimo, 1 arquivo em stage — para os casos que nao dependem do limiar.
R1="$RAIZ/repo1"; repo_novo "$R1"
echo x > "$R1/d.txt"; git -C "$R1" add d.txt

# FORA: diretorio sem git nenhum.
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"

# Arquivo de mensagem com corpo de verdade, para -F <arquivo>.
MSGFILE="$R4/msg.txt"
printf 'Assunto valido\n\nCorpo que explica o motivo da mudanca.\n' > "$MSGFILE"

ASSUNTO80=$(printf 'a%.0s' $(seq 1 80))

echo "== (a) 4 arquivos + so assunto: BARRA (exit 2), cita '4 arquivo(s)' e a forma esperada =="
gate_contendo "4 arquivos, so assunto -> exit 2" 2 "4 arquivo(s)" \
  "$(payload "$R4" Bash 'git commit -m "Assunto valido"')"
saida_forma=$(printf '%s' "$(payload "$R4" Bash 'git commit -m "Assunto valido"')" | node "$GATE" 2>&1)
if printf '%s' "$saida_forma" | grep -qF -- "Forma esperada"; then
  ok=$((ok+1)); echo "  ok   ... e o stderr traz a forma esperada"
else
  falhou=$((falhou+1)); echo "  FALHA ... o stderr NAO traz a forma esperada"
fi

echo
echo "== (b) 3 arquivos e 20 linhas + so assunto: PASSA (limiar nao alcancado) =="
gate "3 arquivos, 20 linhas, so assunto -> exit 0" 0 "$(payload "$R3" Bash 'git commit -m "Assunto valido"')"

echo
echo "== (c) assunto com 80 colunas: BARRA =="
gate "assunto de 80 colunas -> exit 2" 2 "$(payload "$R1" Bash "git commit -m \"$ASSUNTO80\"")"

echo
echo "== (d) assunto terminando em ponto: BARRA =="
gate "assunto termina em ponto -> exit 2" 2 "$(payload "$R1" Bash 'git commit -m "Assunto valido."')"

echo
echo "== (e) 4 arquivos, -m assunto -m corpo: PASSA =="
gate "4 arquivos, -m assunto -m corpo -> exit 0" 0 \
  "$(payload "$R4" Bash 'git commit -m "Assunto valido" -m "corpo que explica o motivo"')"

echo
echo "== (f) 4 arquivos, -F <arquivo> com corpo: PASSA =="
gate "4 arquivos, -F arquivo com corpo -> exit 0" 0 \
  "$(payload "$R4" Bash "git commit -F \"$MSGFILE\"")"

echo
echo "== (g) -F -, e heredoc de -F -: BARRA dizendo 'use -F <arquivo>' =="
gate_contendo "-F - -> exit 2" 2 "use -F <arquivo>" \
  "$(payload "$R1" Bash 'git commit -F -')"
CMD_HEREDOC=$'git commit -F - <<EOF\nmensagem qualquer\nEOF'
gate_contendo "heredoc git commit -F - <<EOF ... EOF -> exit 2" 2 "use -F <arquivo>" \
  "$(payload "$R1" Bash "$CMD_HEREDOC")"

echo
echo "== (h) --amend --no-edit, -C <rev>, -c <rev>: PASSA (reusa mensagem) =="
gate "--amend --no-edit -> exit 0" 0 "$(payload "$R1" Bash 'git commit --amend --no-edit')"
gate "-C HEAD -> exit 0" 0 "$(payload "$R1" Bash 'git commit -C HEAD')"
gate "-c HEAD -> exit 0" 0 "$(payload "$R1" Bash 'git commit -c HEAD')"

echo
echo "== (i) 4 arquivos, -m assunto -m trailer: BARRA (trailer nao e corpo) =="
gate "4 arquivos, segundo -m e so trailer -> exit 2" 2 \
  "$(payload "$R4" Bash 'git commit -m "Assunto valido" -m "Co-Authored-By: X <x@t>"')"

echo
echo "== (i2) git commit PELADO (abriria editor; e' o commit que fecha merge): BARRA e aponta MERGE_MSG =="
gate_contendo "git commit sem -m/-F/reuso -> exit 2" 2 "MERGE_MSG" "$(payload "$R1" Bash 'git commit')"

echo
echo "== (j) comando sem 'git commit': PASSA =="
gate "git status nao e git commit -> exit 0" 0 "$(payload "$R1" Bash 'git status --porcelain')"

echo
echo "== (k) fora de repo git: PASSA =="
gate "fora de repo git -> exit 0" 0 "$(payload "$FORA" Bash 'git commit -m "Assunto valido"')"

echo
echo "== (l) flag curta agrupada (Issue #263): -qm/-am/-qam e valor colado resolvem a mensagem =="
gate "git commit -qm \"teste\" -> exit 0" 0 "$(payload "$R1" Bash 'git commit -qm "teste"')"
gate "git commit -am \"teste\" -> exit 0" 0 "$(payload "$R1" Bash 'git commit -am "teste"')"
gate "git commit -qam \"teste\" -> exit 0" 0 "$(payload "$R1" Bash 'git commit -qam "teste"')"
gate "git commit -mteste (valor colado, sem espaco) -> exit 0" 0 "$(payload "$R1" Bash 'git commit -mteste')"
gate_contendo "git commit -a sozinho (sem m/F) continua barrando -> exit 2" 2 "nenhuma mensagem resolvivel" \
  "$(payload "$R1" Bash 'git commit -a')"

echo
echo "== (m) corpo de heredoc citando 'git commit' e dado, nao comando (Issue #263) =="
CMD_HEREDOC_GIT=$'cat > issue.md <<\x27MD\x27\ntexto explicando o defeito\ngit commit\nMD'
gate "heredoc com linha 'git commit' bare no corpo -> exit 0" 0 "$(payload "$R1" Bash "$CMD_HEREDOC_GIT")"

echo
echo "== extra: mesma forma via ferramenta PowerShell (o hook vale para as duas) =="
gate "PowerShell, 4 arquivos, so assunto -> exit 2" 2 "$(payload "$R4" PowerShell 'git commit -m "Assunto valido"')"
gate "PowerShell, 3 arquivos/20 linhas, so assunto -> exit 0" 0 "$(payload "$R3" PowerShell 'git commit -m "Assunto valido"')"

echo
echo "== bypass por palavra reservada (#309): posicaoDeComando pulando do/then/else/elif/while/until/if/! =="
gate "for t in x; do bash -c \"git commit -m x\"; done -> exit 2 (#309, do)"        2 "$(payload "$R4" Bash 'for t in x; do bash -c "git commit -m x"; done')"
gate "if true; then bash -c \"git commit -m x\"; fi -> exit 2 (#309, then)"        2 "$(payload "$R4" Bash 'if true; then bash -c "git commit -m x"; fi')"
gate "while true; do bash -c \"git commit -m x\"; done -> exit 2 (#309, while/do)" 2 "$(payload "$R4" Bash 'while true; do bash -c "git commit -m x"; done')"
gate "! bash -c \"git commit -m x\" -> exit 2 (#309, !)"                           2 "$(payload "$R4" Bash '! bash -c "git commit -m x"')"
gate "{ bash -c \"git commit -m x\"; } -> exit 2 (#309, controle: ja passava)"     2 "$(payload "$R4" Bash '{ bash -c "git commit -m x"; }')"
gate "if true; then git status; fi -> exit 0 (#309, regressao: nao e git commit)" 0 "$(payload "$R4" Bash 'if true; then git status; fi')"

echo
echo "== coproc (#309, revisao): mesmo bypass — coproc sem nome nao entrava em PALAVRAS_RESERVADAS =="
gate "coproc bash -c \"git commit -m x\" -> exit 2 (coproc (#309, revisao))" 2 "$(payload "$R4" Bash 'coproc bash -c "git commit -m x"')"

echo
echo '== (#309) bash "$t" como ultimo argumento: variavel citada com aspas DUPLAS =='
# Este gate e sobre FORMA de mensagem, nao sobre evasao (comentario de
# `analisaSegmentoCommit`, tokens-comando.cjs): conteudo ILEGIVEL de um
# wrapper (`ilegivel === true`, ou `interno === null` — inclusive um
# CAMINHO reconhecido por D2, que tambem tem `interno === null`) sempre
# devolve "nao achei um git commit aqui", NUNCA bloqueia. D2 (#309) troca
# `"$t"` de ilegivel para caminho, mas os dois braços do OR ja levavam ao
# mesmo `return null` — o comportamento OBSERVAVEL deste gate para estes
# casos e exit 0 tanto ANTES quanto DEPOIS do conserto (medido com o gate
# real); a secao aqui e o registro dessa nao-regressao, nao uma mudanca.
gate 'bash "$t" -> exit 0 (#309, caminho de script)'                          0 "$(payload "$R4" Bash 'bash "$t"')"
gate 'bash "${t}" -> exit 0 (#309, chaves)'                                   0 "$(payload "$R4" Bash 'bash "${t}"')"
gate 'bash "$t" 2>&1 -> exit 0 (#309, redirecionamento nao conta)'            0 "$(payload "$R4" Bash 'bash "$t" 2>&1')"
gate 'bash "$t" > log -> exit 0 (#309, redirecionamento nao conta)'           0 "$(payload "$R4" Bash 'bash "$t" > log')"
gate 'for t in $(grep -l x y.sh); do bash "$t"; done -> exit 0 (#309, padrao real de bateria)' 0 "$(payload "$R4" Bash 'for t in $(grep -l x y.sh); do bash "$t"; done')"
gate 'bash "$f" "git commit -m x" -> exit 0 (#309, mais argumento depois — gate nao adivinha)' 0 "$(payload "$R4" Bash 'bash "$f" "git commit -m x"')"
gate 'bash $t -> exit 0 (#309, sem aspas — gate nao adivinha)'                0 "$(payload "$R4" Bash 'bash $t')"
gate 'bash "$t" x -> exit 0 (#309, mais argumento depois — gate nao adivinha)' 0 "$(payload "$R4" Bash 'bash "$t" x')"

echo
echo "== extra: payload/ferramenta que nao trava o gate =="
gate "ferramenta que nao e Bash/PowerShell (Write) -> exit 0" 0 \
  "$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Write",tool_input:{file_path:"x"}}))')"
gate "payload vazio nunca trava" 0 "{}"
gate "payload ilegivel nunca trava" 0 "isto nao e json"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
