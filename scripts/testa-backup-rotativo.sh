#!/bin/bash
# Bateria de scripts/lib/backup-rotativo.cjs
# Testa rodízio: 11 escritas em ideias/divergencias/ferramentas deixam exatamente 10 backups
# e o mais antigo é removido.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)/sandbox"
trap 'rm -rf "$(dirname "$SB")"' EXIT
export RFM_ROOT="$SB"

mkdir -p "$SB/scripts/lib" "$SB/hooks/lib"
cp "$SRC/scripts/ideias.cjs" "$SB/scripts/"
cp "$SRC/scripts/divergencias.cjs" "$SB/scripts/"
cp "$SRC/scripts/ferramentas.cjs" "$SB/scripts/"
cp "$SRC/scripts/lib/backup-rotativo.cjs" "$SB/scripts/lib/"
cp "$SRC/hooks/lib/trava-jsonl.cjs" "$SB/hooks/lib/"
cp "$SRC/hooks/lib/projetos.cjs" "$SB/hooks/lib/"

cd "$SB" || exit 1

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

echo "== 1. ideias.cjs: 11 escritas deixam exatamente 10 backups, mais antigo removido =="
# Cria fixture inicial
node - <<'JS'
const fs = require("fs");
const linhas = [];
for (let i = 1; i <= 3; i += 1) {
  linhas.push(JSON.stringify({
    id: `fixture-ideias-${i}`,
    titulo: `ideia ${i}`,
    descricao: "d",
    contexto: "c",
    projeto: "sandbox",
    gancho: "g",
    status: "plantada",
    plantada_em: "2026-08-01",
  }));
}
fs.writeFileSync("ideias.jsonl", linhas.join("\n") + "\n", "utf8");
JS

primeiro_backup_nome=""

for i in {1..11}; do
  echo "{\"id\":\"teste-ideias-$i\",\"titulo\":\"Ideia $i\",\"descricao\":\"d\",\"contexto\":\"c\",\"projeto\":\"sandbox\",\"gancho\":\"g\"}" > novo.json
  node scripts/ideias.cjs plantar < novo.json >/dev/null 2>&1

  if [ $i -eq 1 ]; then
    primeiro_backup_nome=$(ls -1 .ideias-backups/ 2>/dev/null | head -1)
  fi
done

num_backups=$(ls -1 .ideias-backups/ 2>/dev/null | wc -l)
if [ "$num_backups" = "10" ]; then
  ok=$((ok+1)); echo "  ok   ideias: exatamente 10 backups após 11 escritas"
else
  falhou=$((falhou+1)); echo "  FALHA ideias: esperava 10 backups, achou $num_backups"
fi

if [ ! -z "$primeiro_backup_nome" ] && [ ! -f ".ideias-backups/$primeiro_backup_nome" ]; then
  ok=$((ok+1)); echo "  ok   ideias: mais antigo foi removido"
else
  falhou=$((falhou+1)); echo "  FALHA ideias: primeiro backup ainda existe"
fi

echo
echo "== 2. divergencias.cjs: 11 escritas deixam exatamente 10 backups, mais antigo removido =="

primeiro_backup_nome=""

for i in {1..11}; do
  node - <<JS
const fs = require("fs");
const entrada = {
  id: "rodada-$i",
  enunciado: "Teste de rodízio",
  shortlist: ["a", "b"],
  escolha_nao_obvia: true,
  refutacao: "teste",
  critico_bateu_na_primeira_da_rodada: false,
  ideias: ["ideia-1", "ideia-2"]
};
fs.writeFileSync("entrada-div.json", JSON.stringify(entrada), "utf8");
JS

  node scripts/divergencias.cjs abrir < entrada-div.json >/dev/null 2>&1

  if [ $i -eq 1 ]; then
    primeiro_backup_nome=$(ls -1 .divergencias-backups/ 2>/dev/null | head -1)
  fi
done

num_backups=$(ls -1 .divergencias-backups/ 2>/dev/null | wc -l)
if [ "$num_backups" = "10" ]; then
  ok=$((ok+1)); echo "  ok   divergencias: exatamente 10 backups após 11 escritas"
else
  falhou=$((falhou+1)); echo "  FALHA divergencias: esperava 10 backups, achou $num_backups"
fi

if [ ! -z "$primeiro_backup_nome" ] && [ ! -f ".divergencias-backups/$primeiro_backup_nome" ]; then
  ok=$((ok+1)); echo "  ok   divergencias: mais antigo foi removido"
else
  falhou=$((falhou+1)); echo "  FALHA divergencias: primeiro backup ainda existe"
fi

echo
echo "== 3. ferramentas.cjs: 11 escritas deixam exatamente 10 backups, mais antigo removido =="

primeiro_backup_nome=""

for i in {1..11}; do
  node scripts/ferramentas.cjs registrar "Ferramenta-$i" "receita-$i" "descoberta-$i" >/dev/null 2>&1

  if [ $i -eq 1 ]; then
    primeiro_backup_nome=$(ls -1 .ferramentas-backups/ 2>/dev/null | head -1)
  fi
done

num_backups=$(ls -1 .ferramentas-backups/ 2>/dev/null | wc -l)
if [ "$num_backups" = "10" ]; then
  ok=$((ok+1)); echo "  ok   ferramentas: exatamente 10 backups após 11 escritas"
else
  falhou=$((falhou+1)); echo "  FALHA ferramentas: esperava 10 backups, achou $num_backups"
fi

if [ ! -z "$primeiro_backup_nome" ] && [ ! -f ".ferramentas-backups/$primeiro_backup_nome" ]; then
  ok=$((ok+1)); echo "  ok   ferramentas: mais antigo foi removido"
else
  falhou=$((falhou+1)); echo "  FALHA ferramentas: primeiro backup ainda existe"
fi

echo
echo "== resultado =="
echo "$ok ok, $falhou falha(s)"
exit $([ "$falhou" -eq 0 ] && echo 0 || echo 1)
