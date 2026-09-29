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

  # Cria rainforest.db como SQLite real com uma tabela
  node -e "
    const { DatabaseSync } = require('node:sqlite');
    const path = require('path');
    const dbpath = path.join('$(cygpath -m "$dir")', 'rainforest.db');
    const db = new DatabaseSync(dbpath);
    db.exec('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
    db.exec('INSERT INTO test (value) VALUES (\"test\")');
    db.close();
  "
  [ -s "$dir/rainforest.db" ] || { echo "  FALHA criarOrigem nao criou o rainforest.db em $dir"; exit 1; }

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

# --- CASO (d): zip sem um item que existe na origem -> exit != 0 e nomeia o item (R5)

teste "d" "zip sem item que existe na origem: exit != 0 e nomeia o item"

origem_d="$SB/origem_d"
destino_d="$SB/destino_d"
criarOrigem "$origem_d"

origem_d_win=$(cygpath -w "$origem_d")
destino_d_win=$(cygpath -w "$destino_d")

# Grava o backup SEM projetos.json na origem (removido antes de compactar)
rm -f "$origem_d/projetos.json"
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_d_win" --destino "$destino_d_win" >/dev/null 2>&1

# Agora projetos.json passa a existir na origem, mas o zip ja foi gravado sem ele
echo '{"novo":true}' > "$origem_d/projetos.json"

saida_conferir_d=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_d_win" --destino "$destino_d_win" 2>&1)
exit_conferir_d=$?

if [ "$exit_conferir_d" != "0" ]; then
  ok=$((ok+1)); echo "  ok    conferir exit code != 0 (item ausente do zip)"
else
  falhou=$((falhou+1)); echo "  FALHA conferir exit code deveria ser != 0, veio 0"
fi

contem "conferir nomeia o item ausente" "$saida_conferir_d" "projetos.json"

# --- CASO (e): destino com apóstrofo no nome — conferir precisa escapar o
# apóstrofo no -Command do Expand-Archive (rodada 19, lote 3), do mesmo jeito
# que compactarSimples já escapa para o Compress-Archive. Sem o conserto,
# `Expand-Archive -Path '...\dest_o'brien\...'` fecha a aspa simples no meio
# do caminho e sai "A cadeia de caracteres nao tem o terminador: '." — a
# prova por restauração de D13 nunca chega a rodar. Nunca toca %OneDrive%
# real: origem e destino são caixas de areia dentro de $SB, passadas por
# --origem/--destino explícitos (o mesmo padrão que os casos (a)-(d) acima
# já usam) — resolverDestino() nunca é chamado sem --destino aqui.

teste "e" "destino com apostrofo no nome: conferir sai 0 (hoje sai 2)"

origem_e="$SB/origem_e"
destino_e="$SB/dest_o'brien"
criarOrigem "$origem_e"
mkdir -p "$destino_e"

origem_e_win=$(cygpath -w "$origem_e")
destino_e_win=$(cygpath -w "$destino_e")

node "$SRC/scripts/backup.cjs" gravar --origem "$origem_e_win" --destino "$destino_e_win" >/dev/null 2>&1
exit_gravar_e=$?
igual "gravar exit code (destino com apostrofo)" "$exit_gravar_e" "0"

saida_conferir_e=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_e_win" --destino "$destino_e_win" 2>&1)
exit_conferir_e=$?
igual "conferir exit code (destino com apostrofo)" "$exit_conferir_e" "0"
contem "conferir diz intacto (destino com apostrofo)" "$saida_conferir_e" "intacto"

# --- CASO (db-snapshot): zip recém-gravado, com o banco da origem alterado depois, conferir sai 0 (integrity_check, não hash)

teste "db-snapshot" "zip recém-gravado, banco alterado depois, conferir sai 0 (integrity_check, nao hash)"

origem_db_snapshot="$SB/origem_db_snapshot"
destino_db_snapshot="$SB/destino_db_snapshot"
criarOrigem "$origem_db_snapshot"

origem_db_snapshot_win=$(cygpath -w "$origem_db_snapshot")
destino_db_snapshot_win=$(cygpath -w "$destino_db_snapshot")

# Grava o backup
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_db_snapshot_win" --destino "$destino_db_snapshot_win" >/dev/null 2>&1
exit_grava_db_snapshot=$?
igual "gravar exit code (db-snapshot)" "$exit_grava_db_snapshot" "0"

# Altera o banco na origem (INSERT novo)
node -e "
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync('$(cygpath -m "$origem_db_snapshot")/rainforest.db');
  db.exec('INSERT INTO test (value) VALUES (\"altered\")');
  db.close();
" 2>/dev/null

# Confere — deve sair 0 apesar da alteração, porque confere por integrity_check
saida_conferir_db_snapshot=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_db_snapshot_win" --destino "$destino_db_snapshot_win" 2>&1)
exit_conferir_db_snapshot=$?
igual "conferir exit code (db-snapshot)" "$exit_conferir_db_snapshot" "0"
contem "conferir diz intacto (db-snapshot)" "$saida_conferir_db_snapshot" "intacto"

# --- CASO (db-corrompido): rainforest.db do zip é corrompido, conferir sai 1 com integrity_check

teste "db-corrompido" "rainforest.db do zip corrompido: conferir sai 1 com integrity_check"

origem_db_corrompido="$SB/origem_db_corrompido"
destino_db_corrompido="$SB/destino_db_corrompido"
criarOrigem "$origem_db_corrompido"

origem_db_corrompido_win=$(cygpath -w "$origem_db_corrompido")
destino_db_corrompido_win=$(cygpath -w "$destino_db_corrompido")

# Grava o backup
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_db_corrompido_win" --destino "$destino_db_corrompido_win" >/dev/null 2>&1
exit_grava_db_corrompido=$?
igual "gravar exit code (db-corrompido)" "$exit_grava_db_corrompido" "0"

# Define hoje para nomes de arquivo (necessário para os casos novos)
hoje=$(date +%Y-%m-%d)

# Extrai o zip, corrompe o rainforest.db, recompacta
zipfile_db_corrompido="$destino_db_corrompido/rainforest-${hoje}.zip"
expanddir_db_corrompido="$SB/expand_db_corrompido"
mkdir -p "$expanddir_db_corrompido"

zipfile_db_corrompido_win=$(cygpath -w "$zipfile_db_corrompido")
expanddir_db_corrompido_win=$(cygpath -w "$expanddir_db_corrompido")

# Extrai
powershell -NoProfile -NonInteractive -Command "Expand-Archive -Path '$zipfile_db_corrompido_win' -DestinationPath '$expanddir_db_corrompido_win' -Force" 2>&1 >/dev/null || true

# Corrompe o rainforest.db
echo "CORRUPTED_BYTES" > "$expanddir_db_corrompido/rainforest.db"

# Remove o zip antigo
rm "$zipfile_db_corrompido"

# Recompacta todos os arquivos
powershell -NoProfile -NonInteractive -Command "
  Get-ChildItem -Path '$expanddir_db_corrompido_win\\*' -Force |
  Compress-Archive -DestinationPath '$zipfile_db_corrompido_win' -Force
" 2>&1 >/dev/null || true

# Confere — deve sair 1 por causa do banco corrompido
saida_conferir_db_corrompido=$(node "$SRC/scripts/backup.cjs" conferir --origem "$origem_db_corrompido_win" --destino "$destino_db_corrompido_win" 2>&1)
exit_conferir_db_corrompido=$?
igual "conferir exit code (db-corrompido)" "$exit_conferir_db_corrompido" "1"
contem "conferir menciona integrity_check (db-corrompido)" "$saida_conferir_db_corrompido" "integrity_check"

# ==================== RESUMO ====================
echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="

if [ "$falhou" -eq 0 ]; then
  exit 0
else
  exit 1
fi
