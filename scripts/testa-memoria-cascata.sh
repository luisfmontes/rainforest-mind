#!/bin/bash
# Bateria da invalidação de resumo em cascata (lote 4, tarefa 2, D4).
# Uso: bash scripts/testa-memoria-cascata.sh
#
# Quando o reconciliar supera uma observação consolidada, o resumo derivado do
# mesmo instante sai da abertura se a fração superada chegou a 1/4. O que esta
# bateria prova, nesta ordem:
#   0. iniciar cria o banco isolado em RFM_ROOT (mktemp -d)
#   1. superar 1 de 4 observações de R invalida R (aplicarDecisaoReconciliacao, sem LLM)
#   2. superar 1 de 8 observações de R3 NÃO invalida R3 (1/8 < 1/4)
#   3. R2, sem observação superada, nunca é invalidado
#   4. a abertura NÃO serve R ("resumo de observação superada não entra na abertura")
#   5. a abertura serve R2 e R3
#   5b. merge também invalida: o resumo do alvo consolidado e o da sondada consolidada
#   6. banco antigo (sem invalidado_em): a abertura serve R_LEGADO como hoje, a
#      reconciliação grava substituida_por sem erro (guarda por PRAGMA), e a
#      migração de iniciar ganha a coluna e a abertura segue servindo
#
# Mutação: scripts/testa-memoria-cascata.sh é a bateria que pega a linha
# `const filtroInvalidado = '';` em hooks/memoria-session-start.cjs (item 4).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/memoria-session-start.cjs"
MEMORIA="$SRC/scripts/memoria.cjs"
LIB_CANONICO="$SRC/scripts/lib/projeto-canonico.cjs"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

# Caminho em forma Windows para o node (o Git Bash não converte variável de ambiente).
caminho_node() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

ok=0; falhou=0
checa() { # nome, comando...
  local nome="$1"; shift
  if "$@"; then ok=$((ok+1)); echo "  ok    $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}

# Drivers node ficam numa caixa própria, fora do repositório.
DRV="$(novo_sandbox)"
cat > "$DRV/seed.cjs" <<'EOF'
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');
const [, , raiz, libCanonico] = process.argv;
const db = new DatabaseSync(raiz + '/rainforest.db');
const projeto = require(libCanonico).slugDoCaminho(fs.realpathSync.native(raiz));
const T1 = '2026-08-01T00:00:00.000Z';
const T2 = '2026-08-02T00:00:00.000Z';
const T3 = '2026-08-03T00:00:00.000Z';
const insRes = db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)');
const insObs = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem, consolidada_em) VALUES (?, ?, ?, ?, ?)');
const insViva = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
const saida = {};
function grupo(prefixo, titulo, instante, n) {
  insRes.run(projeto, titulo, 'conteudo de ' + titulo, instante);
  for (let i = 1; i <= n; i++) {
    const r = insObs.run(projeto, 'observacao ' + prefixo + i, '2026-07-' + String(i).padStart(2, '0') + 'T10:00:00.000Z', prefixo + '-' + i, instante);
    saida[prefixo + i] = Number(r.lastInsertRowid);
  }
}
grupo('A', 'R_SUPERADO', T1, 4);
grupo('B', 'R2_VIVO', T2, 4);
grupo('C', 'R3_VALIDO', T3, 8);
saida.N1 = Number(insViva.run(projeto, 'observacao nova sobre A', '2026-08-05T10:00:00.000Z', 'nova-1').lastInsertRowid);
saida.N2 = Number(insViva.run(projeto, 'observacao nova sobre C', '2026-08-05T11:00:00.000Z', 'nova-2').lastInsertRowid);
db.close();
for (const [k, v] of Object.entries(saida)) console.log(k + '=' + v);
EOF

cat > "$DRV/legado.cjs" <<'EOF'
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');
const [, , raiz, libCanonico] = process.argv;
const db = new DatabaseSync(raiz + '/rainforest.db');
const projeto = require(libCanonico).slugDoCaminho(fs.realpathSync.native(raiz));
// Banco do esquema antigo: sem invalidado_em em resumos.
db.exec('ALTER TABLE resumos DROP COLUMN invalidado_em');
const T1 = '2026-08-01T00:00:00.000Z';
db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)')
  .run(projeto, 'R_LEGADO', 'conteudo de R_LEGADO', T1);
const insObs = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem, consolidada_em) VALUES (?, ?, ?, ?, ?)');
const L1 = Number(insObs.run(projeto, 'observacao legado 1', '2026-07-01T10:00:00.000Z', 'leg-1', T1).lastInsertRowid);
const LN = Number(db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
  .run(projeto, 'observacao legado nova', '2026-08-05T10:00:00.000Z', 'leg-nova').lastInsertRowid);
db.close();
console.log('L1=' + L1);
console.log('LN=' + LN);
EOF

cat > "$DRV/seed-merge.cjs" <<'EOF'
// Dois resumos de 4 observações: no merge, D1 entra como alvo e E1 como sondada.
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');
const [, , raiz, libCanonico] = process.argv;
const db = new DatabaseSync(raiz + '/rainforest.db');
const projeto = require(libCanonico).slugDoCaminho(fs.realpathSync.native(raiz));
const insRes = db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)');
const insObs = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem, consolidada_em) VALUES (?, ?, ?, ?, ?)');
const insViva = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
const saida = {};
function grupo(prefixo, titulo, instante) {
  insRes.run(projeto, titulo, 'conteudo de ' + titulo, instante);
  for (let i = 1; i <= 4; i++) {
    const r = insObs.run(projeto, 'observacao ' + prefixo + i, '2026-07-' + String(i).padStart(2, '0') + 'T10:00:00.000Z', prefixo + '-' + i, instante);
    saida[prefixo + i] = Number(r.lastInsertRowid);
  }
}
grupo('D', 'R_ALVO_DO_MERGE', '2026-08-01T00:00:00.000Z');
grupo('E', 'R_SONDADA_DO_MERGE', '2026-08-02T00:00:00.000Z');
saida.N3 = Number(insViva.run(projeto, 'observacao nova que funde com D1', '2026-08-05T10:00:00.000Z', 'nova-3').lastInsertRowid);
saida.N4 = Number(insViva.run(projeto, 'observacao nova que funde com E1', '2026-08-05T11:00:00.000Z', 'nova-4').lastInsertRowid);
db.close();
for (const [k, v] of Object.entries(saida)) console.log(k + '=' + v);
EOF

cat > "$DRV/decide.cjs" <<'EOF'
// Aplica uma decisão update ou merge (sem LLM) com a função real de scripts/memoria.cjs.
const [, , src, raiz, sondada, alvo, acao] = process.argv;
const { abrirBanco, aplicarDecisaoReconciliacao } = require(src + '/scripts/memoria.cjs');
const conexao = abrirBanco(raiz + '/rainforest.db');
const obs = conexao.prepare('SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE id = ?').get(Number(sondada));
const ok = aplicarDecisaoReconciliacao(conexao, obs, { acao: acao || 'update', alvo_id: Number(alvo) }, [{ id: Number(alvo) }]);
conexao.close();
console.log(String(ok));
EOF

cat > "$DRV/consulta.cjs" <<'EOF'
const { DatabaseSync } = require('node:sqlite');
const [, , raiz, sql] = process.argv;
const db = new DatabaseSync(raiz + '/rainforest.db');
const linha = db.prepare(sql).get();
db.close();
process.stdout.write(linha ? String(Object.values(linha)[0] ?? 'NULL') : 'SEM');
EOF

# Bloco que a abertura injeta, com o hook real (mesmo modo de hooks/testa-memoria-session-start.sh).
abertura() { # caixa_posix
  ( cd "$1" && echo '{}' | RFM_ROOT="$(caminho_node "$1")" node "$HOOK" 2>/dev/null ) \
    | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')"
}
consulta() { node "$DRV/consulta.cjs" "$(caminho_node "$1")" "$2" 2>/dev/null; }

echo "== 0. iniciar cria o banco isolado =="
CAIXA="$(novo_sandbox)"
git init -q "$CAIXA"
(cd "$CAIXA" && RFM_ROOT="$(caminho_node "$CAIXA")" node "$MEMORIA" iniciar > /dev/null 2>&1)
checa "banco criado em RFM_ROOT" [ -f "$CAIXA/rainforest.db" ]

echo
echo "== seed: R_SUPERADO (4 obs, uma será superada), R2_VIVO (4), R3_VALIDO (8) =="
eval "$(node "$DRV/seed.cjs" "$(caminho_node "$CAIXA")" "$(caminho_node "$LIB_CANONICO")")"
checa "seed gravou A1 e N1" [ -n "${A1:-}" ] && [ -n "${N1:-}" ]

echo
echo "== 1-2. decisões update que superam A1 (1/4) e C1 (1/8) =="
got=$(node "$DRV/decide.cjs" "$(caminho_node "$SRC")" "$(caminho_node "$CAIXA")" "$N1" "$A1" 2>&1)
checa "update de N1 sobre A1 aplicado (retorna true): $got" [ "$got" = "true" ]
checa "R_SUPERADO recebe invalidado_em (1 de 4 >= 0.25)" [ "$(consulta "$CAIXA" "SELECT invalidado_em IS NOT NULL FROM resumos WHERE titulo = 'R_SUPERADO'")" = "1" ]
got=$(node "$DRV/decide.cjs" "$(caminho_node "$SRC")" "$(caminho_node "$CAIXA")" "$N2" "$C1" 2>&1)
checa "update de N2 sobre C1 aplicado (retorna true): $got" [ "$got" = "true" ]
checa "R3_VALIDO NÃO recebe invalidado_em (1 de 8 < 0.25)" [ "$(consulta "$CAIXA" "SELECT invalidado_em IS NULL FROM resumos WHERE titulo = 'R3_VALIDO'")" = "1" ]
checa "R2_VIVO sem observação superada segue sem invalidado_em" [ "$(consulta "$CAIXA" "SELECT invalidado_em IS NULL FROM resumos WHERE titulo = 'R2_VIVO'")" = "1" ]
checa "substituida_por gravado em A1 (decisão aplicada de fato)" [ "$(consulta "$CAIXA" "SELECT substituida_por = $N1 FROM observacoes WHERE id = $A1")" = "1" ]

echo
echo "== 3-4. abertura sobre o banco novo =="
BLOCO="$(abertura "$CAIXA")"
checa "resumo de observação superada não entra na abertura" bash -c '! printf "%s" "$1" | grep -q "R_SUPERADO"' _ "$BLOCO"
checa "abertura serve R2_VIVO (sem observação superada)" bash -c 'printf "%s" "$1" | grep -q "R2_VIVO"' _ "$BLOCO"
checa "abertura serve R3_VALIDO (1 de 8 não invalida)" bash -c 'printf "%s" "$1" | grep -q "R3_VALIDO"' _ "$BLOCO"

echo
echo "== 5b. decisões merge invalidam o resumo do alvo e o da sondada =="
FUSAO="$(novo_sandbox)"
git init -q "$FUSAO"
(cd "$FUSAO" && RFM_ROOT="$(caminho_node "$FUSAO")" node "$MEMORIA" iniciar > /dev/null 2>&1)
eval "$(node "$DRV/seed-merge.cjs" "$(caminho_node "$FUSAO")" "$(caminho_node "$LIB_CANONICO")")"
got=$(node "$DRV/decide.cjs" "$(caminho_node "$SRC")" "$(caminho_node "$FUSAO")" "$N3" "$D1" merge 2>&1)
checa "merge de N3 com D1 aplicado (retorna true): $got" [ "$got" = "true" ]
checa "merge com o alvo D1 consolidado invalida R_ALVO_DO_MERGE (1 de 4)" [ "$(consulta "$FUSAO" "SELECT invalidado_em IS NOT NULL FROM resumos WHERE titulo = 'R_ALVO_DO_MERGE'")" = "1" ]
got=$(node "$DRV/decide.cjs" "$(caminho_node "$SRC")" "$(caminho_node "$FUSAO")" "$E1" "$N4" merge 2>&1)
checa "merge de E1 com N4 aplicado (retorna true): $got" [ "$got" = "true" ]
checa "merge com a sondada E1 consolidada invalida R_SONDADA_DO_MERGE (1 de 4)" [ "$(consulta "$FUSAO" "SELECT invalidado_em IS NOT NULL FROM resumos WHERE titulo = 'R_SONDADA_DO_MERGE'")" = "1" ]

echo
echo "== 6. banco do esquema antigo (sem invalidado_em) =="
LEGADO="$(novo_sandbox)"
git init -q "$LEGADO"
(cd "$LEGADO" && RFM_ROOT="$(caminho_node "$LEGADO")" node "$MEMORIA" iniciar > /dev/null 2>&1)
eval "$(node "$DRV/legado.cjs" "$(caminho_node "$LEGADO")" "$(caminho_node "$LIB_CANONICO")")"
checa "banco antigo sem a coluna invalidado_em" [ "$(consulta "$LEGADO" "SELECT COUNT(*) FROM pragma_table_info('resumos') WHERE name = 'invalidado_em'")" = "0" ]
BLOCO_LEG="$(abertura "$LEGADO")"
checa "abertura sem a coluna serve R_LEGADO como hoje" bash -c 'printf "%s" "$1" | grep -q "R_LEGADO"' _ "$BLOCO_LEG"
got=$(node "$DRV/decide.cjs" "$(caminho_node "$SRC")" "$(caminho_node "$LEGADO")" "$LN" "$L1" 2>&1)
checa "reconciliação sobre banco sem a coluna não quebra (retorna true): $got" [ "$got" = "true" ]
checa "substituida_por gravado sobre banco sem a coluna" [ "$(consulta "$LEGADO" "SELECT substituida_por = $LN FROM observacoes WHERE id = $L1")" = "1" ]
(cd "$LEGADO" && RFM_ROOT="$(caminho_node "$LEGADO")" node "$MEMORIA" iniciar > /dev/null 2>&1)
checa "iniciar migra e ganha a coluna invalidado_em" [ "$(consulta "$LEGADO" "SELECT COUNT(*) FROM pragma_table_info('resumos') WHERE name = 'invalidado_em'")" = "1" ]
BLOCO_LEG2="$(abertura "$LEGADO")"
checa "após a migração a abertura segue servindo R_LEGADO" bash -c 'printf "%s" "$1" | grep -q "R_LEGADO"' _ "$BLOCO_LEG2"

echo
echo "ok=$ok falhou=$falhou"
if [ "$falhou" -gt 0 ]; then exit 1; fi
