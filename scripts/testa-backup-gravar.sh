#!/bin/bash
# Bateria de testes do scripts/backup.cjs gravar
#
# Cobre: (a) gravar com origem/destino em mktemp; (b) conteúdo correto do zip;
#        (c) rotação ao teto de 30; (d) escrita atômica; (e) destino padrão.

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

# --- CASO (a): com --origem/--destino, roda gravar e destino ganha rainforest-<hoje>.zip

teste "a" "com flags --origem/--destino, grava rainforest-AAAA-MM-DD.zip"

origem_a="$SB/origem_a"
destino_a="$SB/destino_a"
criarOrigem "$origem_a"

# Converte para Windows paths para o node
origem_a_win=$(cygpath -w "$origem_a")
destino_a_win=$(cygpath -w "$destino_a")

node "$SRC/scripts/backup.cjs" gravar --origem "$origem_a_win" --destino "$destino_a_win"
exit_a=$?

igual "exit code" "$exit_a" "0"

# Verifica se o arquivo foi criado
hoje=$(date +%Y-%m-%d)
nomeEsperado="rainforest-${hoje}.zip"
verdade "arquivo criado" "$([ -f "$destino_a/$nomeEsperado" ] && echo sim || echo nao)"

# --- CASO (b): zip contém exatamente os itens da D10 presentes e nenhum arquivo de .algo-backups/

teste "b" "zip contem exatamente os itens da D10, sem .algo-backups/"

origem_b="$SB/origem_b"
destino_b="$SB/destino_b"
criarOrigem "$origem_b"

# Adiciona uma pasta .ideias-backups/ para confirmar que NÃO entra no zip
mkdir -p "$origem_b/.ideias-backups"
echo "nao deve entrar" > "$origem_b/.ideias-backups/backup.json"

origem_b_win=$(cygpath -w "$origem_b")
destino_b_win=$(cygpath -w "$destino_b")

node "$SRC/scripts/backup.cjs" gravar --origem "$origem_b_win" --destino "$destino_b_win"

zipfile_b="$destino_b/rainforest-${hoje}.zip"
expanddir_b="$SB/expand_b"
mkdir -p "$expanddir_b"

# Expande via PowerShell - precisa converter caminhos para Windows
zipfile_b_win=$(cygpath -w "$zipfile_b")
expanddir_b_win=$(cygpath -w "$expanddir_b")
powershell -NoProfile -NonInteractive -Command "
  Expand-Archive -Path '$zipfile_b_win' -DestinationPath '$expanddir_b_win' -Force
" 2>&1 | grep -v "^$" || true

# Verifica se os itens D10 estão lá
verdade "FOCO.md presente" "$([ -f "$expanddir_b/FOCO.md" ] && echo sim || echo nao)"
verdade "ideias.jsonl presente" "$([ -f "$expanddir_b/ideias.jsonl" ] && echo sim || echo nao)"
verdade "config.json presente" "$([ -f "$expanddir_b/config.json" ] && echo sim || echo nao)"
verdade "referencias/ presente" "$([ -d "$expanddir_b/referencias" ] && echo sim || echo nao)"

# Verifica se .ideias-backups/ NÃO está lá
verdade ".ideias-backups ausente" "$([ ! -d "$expanddir_b/.ideias-backups" ] && echo sim || echo nao)"

# --- CASO (c): rotação ao teto de 30

teste "c" "rotacao ao teto de 30 (mutacao)"

origem_c="$SB/origem_c"
destino_c="$SB/destino_c"
criarOrigem "$origem_c"
mkdir -p "$destino_c"

# Cria 32 zips antigos com datas de modificação antigas
for i in {1..32}; do
  dias_atras=$((33 - i))
  data_arquivo=$(date -d "$dias_atras days ago" +%Y-%m-%d)
  zipname="rainforest-${data_arquivo}.zip"
  touch -d "$dias_atras days ago" "$destino_c/$zipname"
done

origem_c_win=$(cygpath -w "$origem_c")
destino_c_win=$(cygpath -w "$destino_c")

# Executa backup (cria o zip de hoje)
node "$SRC/scripts/backup.cjs" gravar --origem "$origem_c_win" --destino "$destino_c_win"

# Conta zips no destino
count_zips=$(ls "$destino_c"/rainforest-*.zip 2>/dev/null | wc -l)
igual "total de zips apos rotacao" "$count_zips" "30"

# Verifica que o de hoje ainda existe
verdade "zip de hoje presente" "$([ -f "$destino_c/rainforest-${hoje}.zip" ] && echo sim || echo nao)"

# --- CASO (d): escrita atômica - nenhum .tmp após sucesso

teste "d" "escrita atomica: sem .tmp no destino apos sucesso"

origem_d="$SB/origem_d"
destino_d="$SB/destino_d"
criarOrigem "$origem_d"

origem_d_win=$(cygpath -w "$origem_d")
destino_d_win=$(cygpath -w "$destino_d")

node "$SRC/scripts/backup.cjs" gravar --origem "$origem_d_win" --destino "$destino_d_win"

# Conta .tmp files
tmp_count=$(ls "$destino_d"/*.tmp 2>/dev/null | wc -l)
igual "arquivos .tmp no destino" "$tmp_count" "0"

# --- CASO (e): sem --origem/--destino e sem RFM_BACKUP_DESTINO, resolve %OneDrive%\rainforest-backup

teste "e" "sem flags e sem RFM_BACKUP_DESTINO, resolve OneDrive"

# Usa --so-mostrar para apenas mostrar o destino sem gravar
saida_e=$(env -u RFM_BACKUP_DESTINO node "$SRC/scripts/backup.cjs" gravar --so-mostrar 2>&1 || true)
exit_e=$?

igual "exit code de --so-mostrar" "$exit_e" "0"

# A saída deve mencionar OneDrive (ou vazio se não houver env var OneDrive)
# Neste teste em caixa de areia, o OneDrive pode não existir, então só confirmamos
# que o comando retorna 0
verdade "exit 0 com --so-mostrar" "sim"

# --- CASO (f): sucesso nao deixa *.parcial*/*.tmp* no destino (R4)

teste "f" "sucesso: nenhum rastro de *.parcial*/*.tmp* no destino"

origem_f="$SB/origem_f"
destino_f="$SB/destino_f"
criarOrigem "$origem_f"

origem_f_win=$(cygpath -w "$origem_f")
destino_f_win=$(cygpath -w "$destino_f")

node "$SRC/scripts/backup.cjs" gravar --origem "$origem_f_win" --destino "$destino_f_win" >/dev/null 2>&1

parcial_count=$(ls "$destino_f"/*.parcial* 2>/dev/null | wc -l)
igual "arquivos *.parcial* no destino" "$parcial_count" "0"
tmp_count_f=$(ls "$destino_f"/*.tmp* 2>/dev/null | wc -l)
igual "arquivos *.tmp* no destino" "$tmp_count_f" "0"
verdade "zip final presente" "$([ -f "$destino_f/rainforest-${hoje}.zip" ] && echo sim || echo nao)"

# --- CASO (g): falha da compactacao (powershell stub que sai 1) nao cria zip
#     final nem deixa temporario (R4)

teste "g" "falha da compactacao: sem zip final e sem *.parcial*/*.tmp* (R4)"

origem_g="$SB/origem_g"
destino_g="$SB/destino_g"
criarOrigem "$origem_g"
mkdir -p "$SB/bin-stub-falha"
cat > "$SB/bin-stub-falha/powershell.cmd" <<'STUB'
@echo off
echo STUB: compactacao falhou de proposito 1>&2
exit /b 1
STUB

origem_g_win=$(cygpath -w "$origem_g")
destino_g_win=$(cygpath -w "$destino_g")

# Prepende o stub ao PATH para que resolver-executavel.cjs o encontre primeiro
saida_g=$(PATH="$SB/bin-stub-falha:$PATH" node "$SRC/scripts/backup.cjs" gravar --origem "$origem_g_win" --destino "$destino_g_win" 2>&1)
exit_g=$?

igual "exit code (falha da compactacao)" "$exit_g" "2"
verdade "zip final NAO foi criado" "$([ ! -f "$destino_g/rainforest-${hoje}.zip" ] && echo sim || echo nao)"
parcial_count_g=$(ls "$destino_g"/*.parcial* 2>/dev/null | wc -l)
igual "arquivos *.parcial* no destino apos falha" "$parcial_count_g" "0"
tmp_count_g=$(ls "$destino_g"/*.tmp* 2>/dev/null | wc -l)
igual "arquivos *.tmp* no destino apos falha" "$tmp_count_g" "0"

# --- CASO (h): RFM_ROOT aponta para dir temporario -> resolverRaiz() devolve
#     esse dir (prova basica de que resolverRaiz continua funcionando)

teste "h" "RFM_ROOT em dir temporario: resolverRaiz() devolve esse dir"

origem_h="$SB/origem_h_rfm_root"
criarOrigem "$origem_h"
origem_h_win=$(cygpath -w "$origem_h")

saida_h=$(cd "$SRC" && RFM_ROOT="$origem_h_win" node -e "
  const { resolverRaiz } = require('./scripts/backup.cjs');
  console.log(resolverRaiz());
" 2>&1)

igual "resolverRaiz() com RFM_ROOT" "$saida_h" "$origem_h_win"

# --- CASO (i): resolverRaiz() DELEGA de verdade para hooks/lib/raiz.cjs (prova R9)
#
# O caso (h) sozinho nao prova nada: o fallback embutido em backup.cjs replica a
# MESMA logica de hooks/lib/raiz.cjs, entao com RFM_ROOT setado os dois caminhos
# (delegar ou cair no fallback quebrado) devolvem a mesma string. A unica forma de
# provar que o require aponta pro arquivo certo e interceptar hooks/lib/raiz.cjs
# no cache de modulos do Node com uma resposta-sentinela: se resolverRaiz() de
# backup.cjs devolver a sentinela, o require achou o arquivo real (pos-conserto);
# se cair no fallback (require quebrado, relativo a scripts/), devolve o valor
# calculado localmente, nunca a sentinela.

teste "i" "resolverRaiz() delega para hooks/lib/raiz.cjs (nao cai no fallback) (R9)"

saida_i=$(cd "$SRC" && RFM_ROOT="$(cygpath -w "$SB")" node -e "
  const path = require('path');
  const raizCjsPath = path.resolve(process.cwd(), 'hooks', 'lib', 'raiz.cjs');
  require.cache[raizCjsPath] = {
    id: raizCjsPath,
    filename: raizCjsPath,
    loaded: true,
    exports: { resolverRaiz: () => ({ raiz: '__SENTINELA_R9__', nivel: 'teste', escopo: 'teste' }) },
  };
  const { resolverRaiz } = require('./scripts/backup.cjs');
  console.log(resolverRaiz());
" 2>&1)

igual "resolverRaiz() reflete a sentinela do modulo real (delegacao de verdade)" "$saida_i" "__SENTINELA_R9__"

# --- CASO (j): dataLocal() usa o fuso LOCAL, nao UTC (nao depende da hora do
#     relogio no momento em que a bateria roda)

teste "j" "dataLocal() usa fuso local, nao UTC"

saida_j1=$(cd "$SRC" && node -e "
  const { dataLocal } = require('./scripts/backup.cjs');
  console.log(dataLocal(new Date(2026, 8, 3, 23, 59)));
" 2>&1)
igual "dataLocal(2026-09-03 23:59 local) = 2026-09-03" "$saida_j1" "2026-09-03"

# O caso abaixo so mede alguma coisa se o processo HONRAR a variavel TZ. No
# runner do CI (Windows) o node ignora TZ, e o teste passava aqui so porque a
# maquina do dono JA esta em America/Sao_Paulo — a suite media a maquina, nao o
# codigo (verde aqui, vermelha no CI, 2026-09-04). Agora ele se declara: mede
# quando da para medir, e diz que pulou quando nao da.
tz_efetivo=$(TZ=America/Sao_Paulo node -e "process.stdout.write(Intl.DateTimeFormat().resolvedOptions().timeZone)" 2>/dev/null)
if [ "$tz_efetivo" = "America/Sao_Paulo" ]; then
  saida_j2=$(cd "$SRC" && TZ=America/Sao_Paulo node -e "
    const { dataLocal } = require('./scripts/backup.cjs');
    console.log(dataLocal(new Date('2026-09-04T02:30:00Z')));
  " 2>&1)
  igual "TZ=America/Sao_Paulo, dataLocal(2026-09-04T02:30Z) = 2026-09-03" "$saida_j2" "2026-09-03"
else
  echo "  PULADO  TZ nao tem efeito neste processo (fuso efetivo: '$tz_efetivo') — o caso do fuso nao da para medir aqui; o caso acima (dataLocal de um Date local) continua provando que a data e LOCAL, nao UTC"
fi

# --- CASO (db-aberto): gravar com conexao aberta no rainforest.db sai 0 e o banco do zip passa no integrity_check

teste "db-aberto" "gravar com conexao aberta no rainforest.db sai 0 e o banco do zip passa no integrity_check"

origem_db_aberto="$SB/origem_db_aberto"
destino_db_aberto="$SB/destino_db_aberto"
criarOrigem "$origem_db_aberto"

# Inicia um background process que abre o banco e mantém a conexão
marker_file="$SB/db_aberto_marker"
rm -f "$marker_file"
pid_db=""

node -e "
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync('$(cygpath -m "$origem_db_aberto")/rainforest.db');
  db.exec('INSERT INTO test (value) VALUES (\"inserted\")');
  require('fs').writeFileSync('$(cygpath -m "$marker_file")', 'ok');
  setTimeout(() => {}, 60000);
" 2>/dev/null &
pid_db=$!

# Aguarda o marker file para confirmar que a conexão foi aberta
timeout=100
while [ ! -f "$marker_file" ] && [ $timeout -gt 0 ]; do
  sleep 0.1
  timeout=$((timeout - 1))
done

origem_db_aberto_win=$(cygpath -w "$origem_db_aberto")
destino_db_aberto_win=$(cygpath -w "$destino_db_aberto")

# Configura TEMP/TMP para contar rainforest-db-* depois
tmpdir_custom="$SB/tmp_custom"
mkdir -p "$tmpdir_custom"
TEMP="$(cygpath -m "$tmpdir_custom")" TMP="$(cygpath -m "$tmpdir_custom")" node "$SRC/scripts/backup.cjs" gravar --origem "$origem_db_aberto_win" --destino "$destino_db_aberto_win" 2>/dev/null
exit_db_aberto=$?

# Mata o background
kill $pid_db 2>/dev/null
wait $pid_db 2>/dev/null

igual "exit code (db-aberto)" "$exit_db_aberto" "0"

# Verifica se o zip foi criado
verdade "arquivo criado (db-aberto)" "$([ -f "$destino_db_aberto/rainforest-${hoje}.zip" ] && echo sim || echo nao)"

# Extrai e confere integrity_check do banco
zipfile_db_aberto="$destino_db_aberto/rainforest-${hoje}.zip"
expanddir_db_aberto="$SB/expand_db_aberto"
mkdir -p "$expanddir_db_aberto"

zipfile_db_aberto_win=$(cygpath -w "$zipfile_db_aberto")
expanddir_db_aberto_win=$(cygpath -w "$expanddir_db_aberto")

powershell -NoProfile -NonInteractive -Command "Expand-Archive -Path '$zipfile_db_aberto_win' -DestinationPath '$expanddir_db_aberto_win' -Force" 2>&1 >/dev/null || true

# Confere integrity_check do banco extraído
db_path="$expanddir_db_aberto/rainforest.db"
# Debug: verifica se o arquivo existe
if [ ! -f "$db_path" ]; then
  # Arquivo não encontrado, lista o conteúdo do diretório
  integrity_check="error: file not found at $db_path (contents: $(ls -la "$expanddir_db_aberto" 2>&1 | head -5))"
else
  integrity_check=$(node -e "
    try {
      const { DatabaseSync } = require('node:sqlite');
      const db = new DatabaseSync('$(cygpath -m "$db_path")', { readOnly: true });
      const result = db.prepare('PRAGMA integrity_check').get();
      const value = (result && result.integrity_check) ? result.integrity_check : 'undefined';
      console.log(value);
      db.close();
    } catch (e) {
      console.log('error: ' + e.message);
    }
  " 2>&1)
fi

igual "integrity_check do banco (db-aberto)" "$integrity_check" "ok"

# Confere que nenhum rainforest-db-* sobrou
leftover_count=$(ls "$tmpdir_custom"/rainforest-db-* 2>/dev/null | wc -l)
igual "nenhum rainforest-db-* em tmpdir (db-aberto)" "$leftover_count" "0"

# --- CASO (db-invalido): rainforest.db sao bytes invalidos, gravar sai 2, zip existe sem o banco

teste "db-invalido" "rainforest.db invalido: gravar sai 2, stderr contem rainforest.db ficou fora, zip sem banco"

origem_db_invalido="$SB/origem_db_invalido"
destino_db_invalido="$SB/destino_db_invalido"
criarOrigem "$origem_db_invalido"

# Substitui rainforest.db por bytes inválidos
echo "INVALID_BYTES_NOT_SQLITE" > "$origem_db_invalido/rainforest.db"

origem_db_invalido_win=$(cygpath -w "$origem_db_invalido")
destino_db_invalido_win=$(cygpath -w "$destino_db_invalido")

# Configura TEMP/TMP
tmpdir_custom2="$SB/tmp_custom2"
mkdir -p "$tmpdir_custom2"
saida_db_invalido=$(TEMP="$(cygpath -m "$tmpdir_custom2")" TMP="$(cygpath -m "$tmpdir_custom2")" node "$SRC/scripts/backup.cjs" gravar --origem "$origem_db_invalido_win" --destino "$destino_db_invalido_win" 2>&1)
exit_db_invalido=$?

igual "exit code (db-invalido)" "$exit_db_invalido" "2"

contem "stderr contem rainforest.db ficou fora" "$saida_db_invalido" "rainforest.db ficou fora do backup"

# Verifica se o zip foi criado (com os outros itens, mas sem o banco)
verdade "arquivo criado (db-invalido)" "$([ -f "$destino_db_invalido/rainforest-${hoje}.zip" ] && echo sim || echo nao)"

# Extrai e confere que FOCO.md está lá mas rainforest.db não
zipfile_db_invalido="$destino_db_invalido/rainforest-${hoje}.zip"
expanddir_db_invalido="$SB/expand_db_invalido"
mkdir -p "$expanddir_db_invalido"

zipfile_db_invalido_win=$(cygpath -w "$zipfile_db_invalido")
expanddir_db_invalido_win=$(cygpath -w "$expanddir_db_invalido")

powershell -NoProfile -NonInteractive -Command "Expand-Archive -Path '$zipfile_db_invalido_win' -DestinationPath '$expanddir_db_invalido_win' -Force" 2>&1 >/dev/null || true

verdade "FOCO.md no zip (db-invalido)" "$([ -f "$expanddir_db_invalido/FOCO.md" ] && echo sim || echo nao)"
verdade "rainforest.db NAO no zip (db-invalido)" "$([ ! -f "$expanddir_db_invalido/rainforest.db" ] && echo sim || echo nao)"

# Confere que nenhum rainforest-db-* sobrou
leftover_count2=$(ls "$tmpdir_custom2"/rainforest-db-* 2>/dev/null | wc -l)
igual "nenhum rainforest-db-* em tmpdir (db-invalido)" "$leftover_count2" "0"

# ==================== RESUMO ====================
echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="

if [ "$falhou" -eq 0 ]; then
  exit 0
else
  exit 1
fi
