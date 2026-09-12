#!/bin/bash
# Bateria do scripts/conferir-duplicacao.cjs.
#
# Prova, nesta ordem:
#   1. dois arquivos byte a byte identicos -> exit 2, nomeando os dois em
#      ordem alfabetica, separados por ` == `;
#   2. arvore sem duplicata -> exit 0 e a mensagem CONFERIDO;
#   3. `.git/`, `node_modules/`, `fixtures/`, `.claude/worktrees/` e arquivo
#      vazio NAO entram na comparacao — copia identica dentro deles nao conta;
#   4. `--funcoes` lista homonimos reais entre `scripts/*.cjs` de uma arvore
#      de caixa de areia e sai 0 mesmo havendo homonimo;
#   5. `--json` sai JSON valido nos dois modos.
#
# A prova por MUTACAO (exit(2)->exit(0) no ramo de duplicata, revertido depois)
# roda direto no fonte de producao, fora desta bateria — ver o relatorio da
# tarefa. Um caso aqui que aplicasse a mutacao numa COPIA so provaria que a
# copia mudou, nunca que esta bateria acusa o fonte real quebrado.
#
# Uso: bash scripts/testa-conferir-duplicacao.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC/scripts/conferir-duplicacao.cjs"
# Caminho NATIVO (nao o /tmp/... do Git Bash): o Node no Windows precisa de um
# caminho que ele mesmo resolva — ver hooks/testa-gate-staging-total.sh.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

ok=0; falhou=0
checa() { # nome, esperado(exit), esperado(trecho|""), obtido(saida), obtido(exit)
  local nome="$1" esp_exit="$2" esp_trecho="$3" saida="$4" got_exit="$5"
  if [ "$got_exit" != "$esp_exit" ]; then
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp_exit, veio $got_exit"; echo "$saida" | sed 's/^/         /'
    return
  fi
  if [ -n "$esp_trecho" ] && ! echo "$saida" | grep -qF "$esp_trecho"; then
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava conter '$esp_trecho'"; echo "$saida" | sed 's/^/         /'
    return
  fi
  ok=$((ok+1)); echo "  ok   $nome"
}

# ---------------------------------------------------------------- caso 1
# dois .cjs identicos -> exit 2 nomeando os dois
C1="$RAIZ_POSIX/c1"
mkdir -p "$C1/dup"
printf 'conteudo identico\n' > "$C1/a.cjs"
printf 'conteudo identico\n' > "$C1/dup/b.cjs"
printf 'conteudo diferente\n' > "$C1/unico.cjs"
C1_NATIVO="$(cygpath -m "$C1" 2>/dev/null || printf '%s' "$C1")"
SAIDA1="$(node "$SCRIPT" --raiz "$C1_NATIVO" 2>&1)"; EXIT1=$?
checa "1. dois .cjs identicos -> exit 2 nomeando os dois" 2 "a.cjs == dup/b.cjs" "$SAIDA1" "$EXIT1"
LINHAS1="$(echo "$SAIDA1" | grep -c ' == ')"
if [ "$LINHAS1" = "1" ]; then ok=$((ok+1)); echo "  ok   1b. so um grupo de duplicata (unico.cjs de fora)"
else falhou=$((falhou+1)); echo "  FALHA 1b: esperava 1 linha de grupo, veio $LINHAS1"; echo "$SAIDA1" | sed 's/^/         /'; fi

# ---------------------------------------------------------------- caso 2
# arvore sem duplicata -> exit 0 e CONFERIDO
C2="$RAIZ_POSIX/c2"
mkdir -p "$C2"
printf 'a\n' > "$C2/a.cjs"
printf 'b\n' > "$C2/b.cjs"
C2_NATIVO="$(cygpath -m "$C2" 2>/dev/null || printf '%s' "$C2")"
SAIDA2="$(node "$SCRIPT" --raiz "$C2_NATIVO" 2>&1)"; EXIT2=$?
checa "2. sem duplicata -> exit 0, CONFERIDO" 0 "CONFERIDO — nenhuma duplicata byte a byte" "$SAIDA2" "$EXIT2"

# ---------------------------------------------------------------- caso 3
# .git/, node_modules/, fixtures/, .claude/worktrees/ e arquivo vazio ficam
# FORA da comparacao — copia identica so dentro deles nao conta.
C3="$RAIZ_POSIX/c3"
mkdir -p "$C3/.git" "$C3/node_modules" "$C3/fixtures" "$C3/.claude/worktrees/agent-x"
printf 'conteudo raiz\n' > "$C3/raiz.cjs"
printf 'conteudo raiz\n' > "$C3/.git/copia.cjs"
printf 'conteudo raiz\n' > "$C3/node_modules/copia.cjs"
printf 'conteudo raiz\n' > "$C3/fixtures/copia.cjs"
printf 'conteudo raiz\n' > "$C3/.claude/worktrees/agent-x/copia.cjs"
: > "$C3/vazio1.cjs"
: > "$C3/vazio2.cjs"
C3_NATIVO="$(cygpath -m "$C3" 2>/dev/null || printf '%s' "$C3")"
SAIDA3="$(node "$SCRIPT" --raiz "$C3_NATIVO" 2>&1)"; EXIT3=$?
checa "3. dirs ignorados e arquivo vazio nao contam -> exit 0" 0 "CONFERIDO" "$SAIDA3" "$EXIT3"

# ---------------------------------------------------------------- caso 4
# --funcoes: homonimos entre scripts/*.cjs, inventario, sai 0 sempre
C4="$RAIZ_POSIX/c4"
mkdir -p "$C4/scripts"
cat > "$C4/scripts/f1.cjs" <<'EOF'
function foo() {}
exports.helper = function () {};
EOF
cat > "$C4/scripts/f2.cjs" <<'EOF'
function foo() {}
function solo() {}
EOF
cat > "$C4/scripts/f3.cjs" <<'EOF'
module.exports = { helper };
EOF
C4_NATIVO="$(cygpath -m "$C4" 2>/dev/null || printf '%s' "$C4")"
SAIDA4="$(node "$SCRIPT" --funcoes --raiz "$C4_NATIVO" 2>&1)"; EXIT4=$?
checa "4a. --funcoes acha 'foo' em f1 e f2" 0 "foo: scripts/f1.cjs, scripts/f2.cjs" "$SAIDA4" "$EXIT4"
if echo "$SAIDA4" | grep -qF "helper: scripts/f1.cjs, scripts/f3.cjs"; then
  ok=$((ok+1)); echo "  ok   4b. --funcoes acha 'helper' em f1 (exports.) e f3 (module.exports)"
else
  falhou=$((falhou+1)); echo "  FALHA 4b: esperava 'helper: scripts/f1.cjs, scripts/f3.cjs'"; echo "$SAIDA4" | sed 's/^/         /'
fi
if echo "$SAIDA4" | grep -q "^solo:"; then
  falhou=$((falhou+1)); echo "  FALHA 4c: 'solo' aparece so uma vez, nao devia listar"
else
  ok=$((ok+1)); echo "  ok   4c. 'solo' (uma so ocorrencia) nao aparece na lista"
fi

# --json coerente nos dois modos
SAIDA_JSON1="$(node "$SCRIPT" --raiz "$C1_NATIVO" --json 2>&1)"; EXIT_JSON1=$?
if [ "$EXIT_JSON1" = "2" ] && echo "$SAIDA_JSON1" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const o=JSON.parse(d);process.exit(Array.isArray(o.duplicados)&&o.duplicados.length?0:1)}catch{process.exit(1)}})'; then
  ok=$((ok+1)); echo "  ok   5a. --json (duplicacao) e JSON valido com duplicados[]"
else
  falhou=$((falhou+1)); echo "  FALHA 5a: --json duplicacao invalido ou exit errado (exit=$EXIT_JSON1)"; echo "$SAIDA_JSON1" | sed 's/^/         /'
fi

SAIDA_JSON2="$(node "$SCRIPT" --funcoes --raiz "$C4_NATIVO" --json 2>&1)"; EXIT_JSON2=$?
if [ "$EXIT_JSON2" = "0" ] && echo "$SAIDA_JSON2" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const o=JSON.parse(d);process.exit(Array.isArray(o.homonimos)?0:1)}catch{process.exit(1)}})'; then
  ok=$((ok+1)); echo "  ok   5b. --funcoes --json e JSON valido com homonimos[]"
else
  falhou=$((falhou+1)); echo "  FALHA 5b: --funcoes --json invalido ou exit errado (exit=$EXIT_JSON2)"; echo "$SAIDA_JSON2" | sed 's/^/         /'
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
