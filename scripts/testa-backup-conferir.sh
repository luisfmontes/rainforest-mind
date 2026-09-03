#!/bin/bash
# Bateria de testes do scripts/backup.cjs conferir
#
# Cobre: (a) backup íntegro; (b) arquivo de origem editado (mesmo tamanho);
#        (c) sem zip no destino; (d) frase mágica em ambos os casos.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# Prepend common tool paths to PATH before anything else runs
export PATH="/c/Program Files/nodejs:/usr/bin:/usr/local/bin:/c/Windows/System32:/c/Program Files/PowerShell:$PATH"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
contem() { if echo "$2" | grep -F "$3" >/dev/null; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: nao encontrou '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }
teste() { echo ""; echo "($1) $2"; }

# Função auxiliar: cria uma origem com itens da lista D10
criarOrigem() {
  local dir="$1"
  mkdir -p "$dir"
  echo "foco de teste" > "$dir/FOCO.md"
  echo "estrategia" > "$dir/ESTRATEGIA.md"
  echo "avancos" > "$dir/AVANCOS.md"
  echo '{"id":1}' > "$dir/ideias.jsonl"
  echo '{}' > "$dir/divergencias.jsonl"
  echo '{}' > "$dir/ferramentas.jsonl"
  echo '{}' > "$dir/projetos.json"
  echo '{}' > "$dir/config.json"
  dd if=/dev/zero bs=1024 count=100 of="$dir/rainforest.db" 2>/dev/null
  mkdir -p "$dir/referencias" "$dir/relatorios"
  echo "ref1" > "$dir/referencias/ref1.txt"
  echo "rel1" > "$dir/relatorios/rel1.txt"
}

# --- CASO (a): backup íntegro, conferir sai 0 e diz "intacto"

teste "a1" "backup intacro: conferir sai 0 e diz intacto"

origem_a="$SB/origem_a"
destino_a="$SB/destino_a"
criarOrigem "$origem_a"

origem_a_win=$(cygpath -w "$origem_a")
destino_a_win=$(cygpath -w "$destino_a")

# Grava o backup
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_a_win" --destino "$destino_a_win" >/dev/null 2>&1
exit_grava=$?
igual "gravar exit code" "$exit_grava" "0"

# Confere
saida_conferir=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_a_win" --destino "$destino_a_win" 2>&1)
exit_conferir=$?
igual "conferir exit code (intacto)" "$exit_conferir" "0"

contem "conferir diz intacto" "$saida_conferir" "intacto"

# --- CASO (a2): a saída contém a frase mágica (caso feliz)

teste "a2" "saida contem a frase magica no caso feliz"

contem "frase magica (caso feliz)" "$saida_conferir" "sincronizacao e do OneDrive, nao conferida aqui"

# --- CASO (b): arquivo de origem editado (mesmo tamanho), conferir sai 1

teste "b1" "arquivo editado (mesmo tamanho): conferir sai 1 e nomeia arquivo"

origem_b="$SB/origem_b"
destino_b="$SB/destino_b"
criarOrigem "$origem_b"

origem_b_win=$(cygpath -w "$origem_b")
destino_b_win=$(cygpath -w "$destino_b")

# Grava o backup
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_b_win" --destino "$destino_b_win" >/dev/null 2>&1

# Edita um arquivo na origem, mantendo o mesmo tamanho
# FOCO.md tem "foco de teste\n" (14 bytes)
# Vou substituir por 14 bytes de outro conteúdo: "foco alterado\n"
echo "foco alterado" > "$origem_b/FOCO.md"

# Confere
saida_conferir_b=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_b_win" --destino "$destino_b_win" 2>&1)
exit_conferir_b=$?
igual "conferir exit code (divergencia)" "$exit_conferir_b" "1"

contem "conferir nomeia arquivo" "$saida_conferir_b" "FOCO.md"

# --- CASO (b2): a saída contém a frase mágica (caso falha)

teste "b2" "saida contem a frase magica no caso de falha"

contem "frase magica (caso falha)" "$saida_conferir_b" "sincronizacao e do OneDrive, nao conferida aqui"

# --- CASO (c): sem zip no destino, conferir sai 2

teste "c" "sem zip no destino: sai 2 com mensagem nada para conferir"

origem_c="$SB/origem_c"
destino_c="$SB/destino_c"
criarOrigem "$origem_c"
mkdir -p "$destino_c"

origem_c_win=$(cygpath -w "$origem_c")
destino_c_win=$(cygpath -w "$destino_c")

# Tenta conferir sem zip
saida_conferir_c=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_c_win" --destino "$destino_c_win" 2>&1)
exit_conferir_c=$?
igual "conferir exit code (sem zip)" "$exit_conferir_c" "2"

contem "conferir diz nada para conferir" "$saida_conferir_c" "nada para conferir"

# ==================== RESUMO ====================
echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="

if [ "$falhou" -eq 0 ]; then
  exit 0
else
  exit 1
fi
