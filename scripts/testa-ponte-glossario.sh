#!/bin/bash
# Bateria da linha do GLOSSARIO.md na ponte (tarefa 2 do fluxo 2026-10-08-glossario-compartilhado).
# Uso: bash scripts/testa-ponte-glossario.sh
#
# As promessas que importam:
#   1. com GLOSSARIO.md na raiz do alvo, a linha entra UMA vez, antes de "## As regras",
#      nos tres agentes (codex, claude, gemini)
#   2. sem GLOSSARIO.md, a saida nao muda: nada contem a palavra GLOSSARIO, e
#      corpo(...,alvo) === corpo(...) byte a byte
#   3. pasta chamada GLOSSARIO.md nao conta como glossario
#   4. gerar duas vezes nao duplica a linha
#   5. o ensaio (sem --aplicar) nao grava arquivo
# Nenhum caso le o texto do fonte: cada um roda a ponte ou o corpo() e olha o resultado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Copia do PLUGIN, com a mesma forma de testa-ponte.sh: a ponte resolve o proprio
# caminho por __dirname, entao a arvore precisa ter o mesmo layout.
PLUG="$CAIXA/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/hooks/lib" "$PLUG/skills/rainforest-mind"
cp "$SRC/scripts/ponte.cjs" "$PLUG/scripts/"
cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/projetos.cjs" "$SRC/hooks/lib/ponte-corpo.cjs" "$SRC/hooks/lib/bytes.cjs" "$SRC/hooks/lib/resolver-executavel.cjs" "$PLUG/hooks/lib/"
cp "$SRC/scripts/setup.cjs" "$PLUG/scripts/"
cp "$SRC/scripts/conferir-ponte.cjs" "$PLUG/scripts/"
cp "$SRC/skills/rainforest-mind/SKILL.md" "$PLUG/skills/rainforest-mind/"
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
PONTE="node $PLUG/scripts/ponte.cjs"
PONTE_CORPO="$SRC/hooks/lib/ponte-corpo.cjs"

w() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
LINHA='termos de domínio: leia `GLOSSARIO.md`'

ok=0; falhou=0
afirma() { # nome, comando de teste...
  local nome="$1"; shift
  if "$@" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
conta() { # arquivo, texto fixo -> quantas linhas contem
  local n; n=$(grep -cF -- "$2" "$1" 2>/dev/null); echo "${n:-0}"
}
uma_vez() { [ "$(conta "$1" "$LINHA")" = "1" ]; }
nenhuma() { [ "$(conta "$1" "$LINHA")" = "0" ]; }
antes_das_regras() { # a linha do glossario vem antes de "## As regras"
  local a b
  a=$(grep -nF -- "$LINHA" "$1" | head -1 | cut -d: -f1)
  b=$(grep -nF -- "## As regras" "$1" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
sem_palavra() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
nao_existe() { [ ! -e "$1" ]; }

arquivo_do() { case "$1" in codex) echo AGENTS.md;; claude) echo CLAUDE.md;; gemini) echo GEMINI.md;; esac; }

echo "== 1. com GLOSSARIO.md, a linha entra uma vez antes de ## As regras, nos tres agentes =="
ALVO_G="$CAIXA/com-glossario"; mkdir -p "$ALVO_G"; printf '# Glossario\n' > "$ALVO_G/GLOSSARIO.md"
for ag in codex claude gemini; do
  arq="$(arquivo_do "$ag")"
  $PONTE --alvo "$(w "$ALVO_G")" --agente "$ag" --aplicar >/dev/null 2>&1
  afirma "alvo com GLOSSARIO.md recebe a linha nos tres agentes: $ag, $arq existe" test -s "$ALVO_G/$arq"
  afirma "alvo com GLOSSARIO.md recebe a linha nos tres agentes: $ag, uma vez" uma_vez "$ALVO_G/$arq"
  afirma "alvo com GLOSSARIO.md recebe a linha nos tres agentes: $ag, antes de ## As regras" antes_das_regras "$ALVO_G/$arq"
done
# A linha entra no alvo mesmo quando o repo nao tinha nenhum GLOSSARIO antes (caixa limpa).
ALVO_G2="$CAIXA/com-glossario-2"; mkdir -p "$ALVO_G2"; printf 'x\n' > "$ALVO_G2/GLOSSARIO.md"
$PONTE --alvo "$(w "$ALVO_G2")" --agente codex --aplicar >/dev/null 2>&1
afirma "alvo com GLOSSARIO.md recebe a linha nos tres agentes: caixa limpa, codex" uma_vez "$ALVO_G2/AGENTS.md"

echo
echo "== 2. sem GLOSSARIO.md, nada contem a palavra GLOSSARIO =="
ALVO_S="$CAIXA/sem-glossario"; mkdir -p "$ALVO_S"
for ag in codex claude gemini; do
  $PONTE --alvo "$(w "$ALVO_S")" --agente "$ag" --aplicar >/dev/null 2>&1
  arq="$(arquivo_do "$ag")"
  afirma "$ag sem glossario: $arq existe" test -s "$ALVO_S/$arq"
  afirma "$ag sem glossario: nenhuma linha GLOSSARIO" sem_palavra "$ALVO_S/$arq" GLOSSARIO
done

echo
echo "== 3. corpo com alvo sem glossario === corpo sem alvo (em processo) =="
afirma "corpo(alvo sem glossario) === corpo(sem alvo), byte a byte" node -e '
  const c = require(process.argv[1]);
  const ag = c.AGENTES.codex;
  const a = c.corpo(ag, "NUCLEO-DE-TESTE", null, process.argv[2]);
  const b = c.corpo(ag, "NUCLEO-DE-TESTE", null);
  process.exit(a === b ? 0 : 1);
' "$(w "$PONTE_CORPO")" "$(w "$ALVO_S")"
afirma "corpo(alvo com glossario) contem a linha (controle, nao vacuo)" node -e '
  const c = require(process.argv[1]);
  const a = c.corpo(c.AGENTES.codex, "NUCLEO-DE-TESTE", null, process.argv[2]);
  const b = c.corpo(c.AGENTES.codex, "NUCLEO-DE-TESTE", null);
  process.exit(a !== b && a.includes(c.LINHA_GLOSSARIO) && !b.includes("GLOSSARIO") ? 0 : 1);
' "$(w "$PONTE_CORPO")" "$(w "$ALVO_G")"

echo
echo "== 4. gerar duas vezes nao duplica a linha =="
$PONTE --alvo "$(w "$ALVO_G")" --agente codex --aplicar >/dev/null 2>&1
esperado "segunda geracao roda" 0 $PONTE --alvo "$(w "$ALVO_G")" --agente codex --aplicar
afirma "depois de duas geracoes a linha continua uma vez" uma_vez "$ALVO_G/AGENTS.md"

echo
echo "== 5. GLOSSARIO.md como pasta nao conta =="
ALVO_P="$CAIXA/pasta"; mkdir -p "$ALVO_P/GLOSSARIO.md"
$PONTE --alvo "$(w "$ALVO_P")" --agente codex --aplicar >/dev/null 2>&1
afirma "pasta GLOSSARIO.md: AGENTS.md existe" test -s "$ALVO_P/AGENTS.md"
afirma "pasta GLOSSARIO.md: linha NAO entra" nenhuma "$ALVO_P/AGENTS.md"
afirma "pasta GLOSSARIO.md: nenhuma palavra GLOSSARIO" sem_palavra "$ALVO_P/AGENTS.md" GLOSSARIO

echo
echo "== 6. ensaio (sem --aplicar) nao grava =="
ALVO_E="$CAIXA/ensaio"; mkdir -p "$ALVO_E"; printf '# Glossario\n' > "$ALVO_E/GLOSSARIO.md"
esperado "ensaio roda" 0 $PONTE --alvo "$(w "$ALVO_E")" --agente codex
afirma "ensaio: AGENTS.md nao foi criado" nao_existe "$ALVO_E/AGENTS.md"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
