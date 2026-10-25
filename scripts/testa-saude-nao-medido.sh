#!/bin/bash
# Teste de "não medido" nos erros de ferramenta (D6): log que existe e não abre
# não vira "nenhum erro". Cobre erros.cjs (recentes, listar, contar) e saude.cjs (checarErros).
# O log é sempre um diretório temporário (RFM_ROOT), nunca o log real do usuário.
# Uso: bash scripts/testa-saude-nao-medido.sh
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA_POSIX="$(mktemp -d)"
trap 'rm -rf "$CAIXA_POSIX"' EXIT
CAIXA="$(cygpath -m "$CAIXA_POSIX" 2>/dev/null || printf '%s' "$CAIXA_POSIX")"
SRCW="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
export CAIXA SRCW
ok=0; falhou=0
checa() { if [ "$2" = "$3" ]; then echo "ok   $1"; ok=$((ok+1)); else echo "FALHA $1: esperado [$3], veio [$2]"; falhou=$((falhou+1)); fi; }

# fixtures: log ilegível (diretório com o nome do arquivo), log ausente, log com erro recente, log só velho
node -e '
const fs = require("fs"), p = require("path"), R = process.env.CAIXA;
fs.mkdirSync(p.join(R, "ilegivel", "erros.jsonl"), { recursive: true });
fs.mkdirSync(p.join(R, "ausente"), { recursive: true });
fs.mkdirSync(p.join(R, "recente"), { recursive: true });
fs.writeFileSync(p.join(R, "recente", "erros.jsonl"), JSON.stringify({ ts: new Date().toISOString(), tipo: "erro", ferramenta: "Bash" }) + "\n");
fs.mkdirSync(p.join(R, "velho"), { recursive: true });
fs.writeFileSync(p.join(R, "velho", "erros.jsonl"), JSON.stringify({ ts: new Date(Date.now() - 48 * 3600e3).toISOString(), tipo: "erro", ferramenta: "Bash" }) + "\n");
'

# saude.cjs: checarErros devolve o achado da linha "erros de ferramenta", caminho do log trocado por <raiz>
achado() {
  RFM_ROOT="$CAIXA/$1" node -e '
const path = require("path");
const s = require(process.env.SRCW + "/scripts/saude.cjs");
s.checarErros();
const a = s.achados.find((x) => x.item === "erros de ferramenta");
if (!a) { console.log("ausente"); process.exit(0); }
const raiz = path.normalize(process.env.RFM_ROOT);
console.log(a.nivel + " " + a.detalhe.split(raiz).join("<raiz>"));
'
}

checa "log ilegível sai aviso não medido" "$(achado ilegivel)" "aviso não medido: o log <raiz>\\erros.jsonl não pôde ser lido"
checa "log ausente sai ok nenhum registrado" "$(achado ausente)" "ok nenhum registrado"
checa "log com erro recente mantém o texto de hoje" "$(achado recente)" "aviso 1 nas ultimas 24 h (1 erro(s), 0 bloqueio(s))"
checa "log só com linha velha sai ok nenhum nas ultimas 24 h" "$(achado velho)" "ok nenhum nas ultimas 24 h"

# erros.cjs: os outros chamadores de recentes() tratam null sem lançar
E="$SRCW/scripts/erros.cjs"
RFM_ROOT="$CAIXA/ilegivel" node "$E" listar > "$CAIXA_POSIX/l.out" 2> "$CAIXA_POSIX/l.err"; checa "listar com log ilegível sai 1" "$?" "1"
checa "listar com log ilegível não lança" "$(grep -c 'TypeError' "$CAIXA_POSIX/l.err")" "0"
checa "listar com log ilegível não imprime listagem" "$(wc -c < "$CAIXA_POSIX/l.out" | tr -d ' ')" "0"
checa "listar com log ilegível diz a causa no stderr" "$(grep -c 'log ilegível' "$CAIXA_POSIX/l.err")" "1"

RFM_ROOT="$CAIXA/ilegivel" node "$E" contar > "$CAIXA_POSIX/c.out" 2> "$CAIXA_POSIX/c.err"; checa "contar com log ilegível sai 1" "$?" "1"
checa "contar com log ilegível não lança" "$(grep -c 'TypeError' "$CAIXA_POSIX/c.err")" "0"
checa "contar com log ilegível não imprime JSON de zero" "$(wc -c < "$CAIXA_POSIX/c.out" | tr -d ' ')" "0"

# erros.cjs: ausente e com erro recente continuam saindo como hoje
checa "listar com log ausente sai 0 e diz nenhum erro" "$(RFM_ROOT="$CAIXA/ausente" node "$E" listar)" "Nenhum erro de ferramenta nas últimas 24 h."
checa "contar com log ausente sai 0 e zero" "$(RFM_ROOT="$CAIXA/ausente" node "$E" contar)" '{"total":0,"erro":0,"bloqueio":0}'
checa "contar com erro recente sai como hoje" "$(RFM_ROOT="$CAIXA/recente" node "$E" contar)" '{"total":1,"erro":1,"bloqueio":0}'

echo "placar: $ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ]
