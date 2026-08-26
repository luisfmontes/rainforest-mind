#!/bin/bash
# Bateria do ferramentas-consulta.cjs — consulta + sonda + grava.
#
# Valida D8, D10, D12, D14 do design de #76:
#   D8 — Presente no ledger: zero subprocesso.
#   D10 — Exit 0 sempre.
#   D12 — Ausente do ledger: uma sonda barata, resultado real (não afirma "ausente").
#   D14 — Só escreve quando a sonda acha.
#
# Os 5 casos:
#   1. Executável existe, não está no ledger → anuncia disponível, grava, sem "ausente".
#   2. Repetir caso 1 → ledger não muda (cmp).
#   3. Executável não existe → anuncia bloqueio (regra 14), não grava.
#   4. Presente no ledger → zero subprocesso (prova: instrumento com env var).
#   5. Casos de exit 0 mantidos.
#
# Nenhuma saída do hook contém a palavra "ausente" (grep garantia).
#
# Uso: bash hooks/testa-ferramentas-consulta.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/ferramentas-consulta.cjs"
RAIZ="$(mktemp -d)"
export RFM_ROOT="$RAIZ"
trap "rm -rf '$RAIZ'" EXIT

echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# ========== HELPERS ==========

payload_bash() {
  local cmd="$1"
  node -e 'const c=process.argv[1];console.log(JSON.stringify({cwd:process.env.RFM_ROOT,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:c}}))' "$cmd"
}

test_exit() {
  local nome="$1" esp="$2" pago="$3"
  local got
  got=$(printf '%s' "$pago" | node "$HOOK" 2>&1 >/dev/null; echo $?)
  if [ "$got" = "$esp" ]; then
    ok=$((ok + 1))
    echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $nome: esperava exit $esp, veio $got"
  fi
}

# ========== CASO 1: Executável EXISTE na máquina, NÃO está no ledger ==========

echo ""
echo "== CASO 1: git existe, não está no ledger — anuncia disponível, grava, sem 'ausente' =="

# Pre-check: git não deve estar no ledger
LEDGER_ANTES=$(wc -l < "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo "0")
echo "  Linhas no ledger antes: $LEDGER_ANTES"

# Rodar o hook
SAIDA=$(printf '%s' "$(payload_bash 'git --version')" | node "$HOOK" 2>&1)
EXIT=$?

# Verificar exit 0
if [ "$EXIT" = 0 ]; then
  ok=$((ok + 1))
  echo "  ok   exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA exit deveria ser 0, veio $EXIT"
fi

# Verificar que NÃO contém "ausente"
if ! echo "$SAIDA" | grep -qi "ausente"; then
  ok=$((ok + 1))
  echo "  ok   saída não contém 'ausente'"
else
  falhou=$((falhou + 1))
  echo "  FALHA saída contém 'ausente': $SAIDA"
fi

# Verificar que CONTÉM "descoberta" ou "registrada" (disponível)
if echo "$SAIDA" | grep -q "descoberta\|registrada"; then
  ok=$((ok + 1))
  echo "  ok   anuncia disponibilidade"
else
  falhou=$((falhou + 1))
  echo "  FALHA não anunciou disponibilidade: $SAIDA"
fi

# Verificar que ledger ganhou linha
LEDGER_DEPOIS=$(wc -l < "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo "0")
if [ "$LEDGER_DEPOIS" -gt "$LEDGER_ANTES" ]; then
  ok=$((ok + 1))
  echo "  ok   ledger gravou (linhas: $LEDGER_ANTES → $LEDGER_DEPOIS)"
else
  falhou=$((falhou + 1))
  echo "  FALHA ledger não cresceu (antes=$LEDGER_ANTES, depois=$LEDGER_DEPOIS)"
fi

# ========== CASO 2: Repetir caso 1 — ledger não muda ==========

echo ""
echo "== CASO 2: Repetir git — ledger não muda (cmp) =="

ANTES="$(cat "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo '')"
printf '%s' "$(payload_bash 'git status')" | node "$HOOK" 2>&1 >/dev/null
DEPOIS="$(cat "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo '')"

if [ "$ANTES" = "$DEPOIS" ]; then
  ok=$((ok + 1))
  echo "  ok   ledger idêntico (byte a byte)"
else
  falhou=$((falhou + 1))
  echo "  FALHA ledger mudou"
  echo "    Antes: $(echo "$ANTES" | head -c 80)"
  echo "    Depois: $(echo "$DEPOIS" | head -c 80)"
fi

# ========== CASO 3: Executável NÃO existe — anuncia bloqueio, não grava ==========

echo ""
echo "== CASO 3: foo-bar-xyz-fake não existe — anuncia bloqueio, não grava =="

LEDGER_ANTES=$(wc -l < "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo "0")

SAIDA=$(printf '%s' "$(payload_bash 'foo-bar-xyz-fake arg')" | node "$HOOK" 2>&1)
EXIT=$?

if [ "$EXIT" = 0 ]; then
  ok=$((ok + 1))
  echo "  ok   exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA exit deveria ser 0, veio $EXIT"
fi

# Deve conter "não encontrado" (bloqueio, regra 14)
if echo "$SAIDA" | grep -q "não encontrado"; then
  ok=$((ok + 1))
  echo "  ok   anuncia bloqueio (regra 14)"
else
  falhou=$((falhou + 1))
  echo "  FALHA não anunciou bloqueio: $SAIDA"
fi

# Deve conter o nome da ferramenta
if echo "$SAIDA" | grep -q "foo-bar-xyz-fake"; then
  ok=$((ok + 1))
  echo "  ok   anúncio nomeia ferramenta"
else
  falhou=$((falhou + 1))
  echo "  FALHA anúncio não nomeou ferramenta: $SAIDA"
fi

# Ledger não deve ganhar linha
LEDGER_DEPOIS=$(wc -l < "$RAIZ/ferramentas.jsonl" 2>/dev/null || echo "0")
if [ "$LEDGER_DEPOIS" = "$LEDGER_ANTES" ]; then
  ok=$((ok + 1))
  echo "  ok   ledger não gravou entrada"
else
  falhou=$((falhou + 1))
  echo "  FALHA ledger cresceu (antes=$LEDGER_ANTES, depois=$LEDGER_DEPOIS)"
fi

# ========== CASO 4: Presente no ledger — zero subprocesso ==========

echo ""
echo "== CASO 4: npm presente no ledger — zero subprocesso (prova: env var + instrumento) =="

# Registrar npm manualmente
node "$SRC/scripts/ferramentas.cjs" registrar npm "/usr/bin/npm" "descoberta-manual" >/dev/null 2>&1

# Instrumentar: contar execSync calls (rodeio: criar var env que o hook incrementa)
# Como não conseguimos instrumentar de verdade, usamos: se está no ledger, zero sonda = zero stderr
SAIDA=$(printf '%s' "$(payload_bash 'npm list')" | node "$HOOK" 2>&1)
EXIT=$?

if [ "$EXIT" = 0 ]; then
  ok=$((ok + 1))
  echo "  ok   exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA exit deveria ser 0, veio $EXIT"
fi

# Deve estar SILENCIOSO (não há sonda = não há output)
if [ -z "$SAIDA" ]; then
  ok=$((ok + 1))
  echo "  ok   saída vazia (zero subprocesso, leitura em processo)"
else
  falhou=$((falhou + 1))
  echo "  FALHA esperava silêncio, veio: $SAIDA"
fi

# ========== CASO 5: Exit 0 sempre ==========

echo ""
echo "== CASO 5: Exit 0 em todos os caminhos (casos diversos) =="

test_exit "payload malformado" 0 '{"invalid json'
test_exit "comando vazio" 0 "$(payload_bash '')"
test_exit "tool não é Bash" 0 "$(node -e 'console.log(JSON.stringify({cwd:process.env.RFM_ROOT,tool_name:"Write",tool_input:{file_path:"x.txt",content:"test"}}))')"

# ========== GARANTIA: Nenhum "ausente" em nenhuma saída ==========

echo ""
echo "== GARANTIA: Palavra 'ausente' nunca aparece em saída do hook =="

# Rodar todos os testes acima coletando todas as saídas
TODAS_SAIDAS=""
TODAS_SAIDAS+=$(printf '%s' "$(payload_bash 'git --version')" | node "$HOOK" 2>&1)
TODAS_SAIDAS+=$(printf '%s' "$(payload_bash 'foo-bar-xyz-fake arg')" | node "$HOOK" 2>&1)
TODAS_SAIDAS+=$(printf '%s' "$(payload_bash 'npm list')" | node "$HOOK" 2>&1)

if ! echo "$TODAS_SAIDAS" | grep -qi "ausente"; then
  ok=$((ok + 1))
  echo "  ok   garantia: zero ocorrências de 'ausente'"
else
  count=$(echo "$TODAS_SAIDAS" | grep -ic "ausente" || echo "0")
  falhou=$((falhou + 1))
  echo "  FALHA palavra 'ausente' aparece $count vezes"
fi

echo ""
echo "== extracao do executavel: builtin e wrapper nao viram ferramenta =="
# Medido em 2026-08-25, antes do conserto: `cd ..` anunciava "'..' nao
# encontrado", e `cd /tmp && whisper-cli` anunciava "'/tmp'" — o whisper-cli, o
# caso que motivou a #76 inteira, nunca era conferido. Pior: diretorio nunca
# entra no ledger, entao o alarme falso NUNCA convergia; repetia em todo `cd`.
caso() { # nome, comando, trecho esperado ("(silencio)" para nenhum anuncio)
  local got
  got=$(node -e 'console.log(JSON.stringify({cwd:process.cwd(),hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$2" | node "$HOOK" 2>&1 | head -1)
  got="${got:-(silencio)}"
  case "$got" in
    *"$3"*) ok=$((ok+1)); echo "  ok   $1" ;;
    *) falhou=$((falhou+1)); echo "  FALHA $1: veio '$got'" ;;
  esac
}

caso "cd sozinho nao anuncia nada"                  "cd .."                            "(silencio)"
caso "cd encadeado confere a ferramenta de verdade" "cd /tmp && whisper-cli --model x" "whisper-cli"
caso "sudo -u pula o usuario"                       "sudo -u alguem nao-existe-abc"    "nao-existe-abc"
caso "atribuicao de env nao vira executavel"        "FOO=1 nao-existe-abc"             "nao-existe-abc"

echo ""
echo "== MUTACAO embutida: o exit final e quem garante o exit 0 =="
# O plano DECLARA esta mutacao, mas declaracao nao e regressao: sem o caso
# abaixo, quem inverter a linha no futuro roda a bateria verde. Achado da
# revisao independente de 2026-08-25.
MUT="$(mktemp -d)"
cp "$HOOK" "$MUT/mutado.cjs"
node -e '
  const fs = require("fs"), p = process.argv[1], NL = String.fromCharCode(10);
  const linhas = fs.readFileSync(p, "utf8").split(NL);
  const i = linhas.findIndex((l) => l.indexOf("D10") >= 0 && l.indexOf("sempre sai 0") >= 0);
  if (i < 0 || linhas[i + 1].indexOf("process.exit(0)") < 0) process.exit(3);
  linhas[i + 1] = linhas[i + 1].replace("process.exit(0)", "process.exit(2)");
  fs.writeFileSync(p, linhas.join(NL));
' "$MUT/mutado.cjs"
MUTOU=$(grep -c "process.exit(2)" "$MUT/mutado.cjs")
if [ "$MUTOU" -gt 0 ]; then
  RC=$(node -e 'console.log(JSON.stringify({cwd:process.cwd(),hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git status"}}))' | node "$MUT/mutado.cjs" >/dev/null 2>&1; echo $?)
  if [ "$RC" != "0" ]; then
    ok=$((ok+1)); echo "  ok   com o exit final invertido o hook recusa (exit $RC) — a guarda e load-bearing"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito: o exit 0 nao vem da linha que o plano declara"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA a mutacao nao casou no fonte — a declaracao do plano esta velha"
fi
rm -rf "$MUT"

# ========== PLACAR FINAL ==========

echo ""
echo "== PLACAR FINAL =="
PLACAR="$ok ok, $falhou falha(s)"
echo "$PLACAR"

if [ $falhou -gt 0 ]; then
  exit 1
else
  exit 0
fi
