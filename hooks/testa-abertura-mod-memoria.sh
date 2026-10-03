#!/bin/bash
# Bateria do destino `mod` da memoria da abertura (memoria-session-start.cjs --destino mod).
# Uso: bash hooks/testa-abertura-mod-memoria.sh
#
# O que esta bateria precisa provar:
#   1. no destino mod, 14 observacoes de subtitulo longo chegam INTEIRAS (nenhuma
#      termina em `…`), dentro do teto de hooks/abertura-mod.json (orcamentoMemoriaBytes)
#   2. sem a flag, no mesmo banco, a saida e IDENTICA a do commit base d5d2a203
#      (golden extraido com git archive) e continua cortada pela escada de sempre
#   3. o systemMessage e o mesmo nos dois destinos
#
# Fixture: banco em diretorio temporario, no idioma de testa-memoria-session-start.sh
# (RFM_ROOT + chaveHarness da pasta); nunca o banco vivo do usuario.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/memoria-session-start.cjs"
COMMIT_BASE="d5d2a203"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

ok=0; falhou=0
passa() { ok=$((ok+1)); echo "  ok    $1"; }
falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

CAIXA_POSIX="$(novo_sandbox)"
CAIXA="$(cygpath -m "$CAIXA_POSIX" 2>/dev/null || printf '%s' "$CAIXA_POSIX")"
# Pasta com o nome de um projeto real: o rotulo da linha e o nome curto dela.
PASTA="$CAIXA_POSIX/rainforest-mind"
mkdir -p "$PASTA"
git init -q "$PASTA"

RFM_ROOT="$CAIXA" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# 14 observacoes vivas, cada uma com subtitulo >= 190 B (ASCII, 200 caracteres), sob a
# chave EXATA que o harness usaria para a pasta.
(cd "$PASTA" && RFM_ROOT="$CAIXA" SRC="$SRC" node -e "
  const { DatabaseSync } = require('node:sqlite');
  const { chaveHarness } = require(process.env.SRC + '/scripts/memoria.cjs');
  const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  for (let i = 1; i <= 14; i++) {
    const dia = String(10 + i).padStart(2, '0');
    const sub = ('Subtitulo longo numero ' + i + ' com varias palavras para passar de cento e noventa bytes e forcar a escada de corte por linha ').padEnd(200, 'z').slice(0, 199) + String(i % 10);
    ins.run(chaveHarness(process.cwd()), '## Obs ' + i + '\n\n' + sub + '\n\n### Detalhe\n\ncorpo', '2026-09-' + dia + 'T10:00:00Z', 'sessao:teste:offset:' + i);
  }
  db.close();
")

# Golden: o hook do commit base, extraido com git archive (nunca git show ref:caminho).
BASE_POSIX="$(novo_sandbox)"
cd "$SRC"
git archive "$COMMIT_BASE" hooks scripts | tar -x -C "$BASE_POSIX"
HOOK_BASE="$BASE_POSIX/hooks/memoria-session-start.cjs"

roda() { # hook, args...  (mesma pasta e mesma raiz de dados para todos)
  local h="$1"; shift
  (cd "$PASTA" && RFM_ROOT="$CAIXA" node "$h" "$@" < /dev/null 2>/dev/null)
}
# Campo do JSON de saida: additionalContext | systemMessage | json inteiro normalizado.
campo() { # json, nome
  JSON_IN="$1" CAMPO="$2" SRC="$SRC" BASE="$BASE_POSIX" node -e "
    const d = JSON.parse(process.env.JSON_IN);
    if (process.env.CAMPO === 'ctx') process.stdout.write((d.hookSpecificOutput || {}).additionalContext || '');
    else if (process.env.CAMPO === 'msg') process.stdout.write(d.systemMessage || '');
    else {
      // Normaliza so a raiz do plugin, se aparecer na saida.
      let t = JSON.stringify(d);
      for (const r of [process.env.SRC, process.env.BASE]) t = t.split(JSON.stringify(r).slice(1, -1)).join('<RAIZ>');
      process.stdout.write(t);
    }"
}
linhas_obs() { printf '%s\n' "$1" | grep -c '^\[2026-' || true; }
linhas_corte() { printf '%s\n' "$1" | grep '^\[2026-' | grep -c '…$' || true; }
nbytes() { printf '%s' "$1" | wc -c | tr -d ' '; }

JSON_MOD="$(roda "$HOOK" --destino mod)"
JSON_SEM="$(roda "$HOOK")"
JSON_BASE="$(roda "$HOOK_BASE")"
CTX_MOD="$(campo "$JSON_MOD" ctx)"
CTX_SEM="$(campo "$JSON_SEM" ctx)"
TETO_MOD="$(node -e "process.stdout.write(String(require(process.argv[1]).carregar().memoria))" "$SRC/hooks/lib/abertura-mod.cjs")"
TETO_SEM=3000

echo
echo "1. 14 observacoes com subtitulo longo chegam inteiras no destino mod"
B_MOD="$(nbytes "$CTX_MOD")"; N_MOD="$(linhas_obs "$CTX_MOD")"; C_MOD="$(linhas_corte "$CTX_MOD")"
echo "  mod: $B_MOD B (teto $TETO_MOD), $N_MOD linhas de observacao, $C_MOD terminando em …"
[ "$N_MOD" = "14" ] && passa "14 linhas de observacao no destino mod" || falha "esperava 14 linhas no destino mod, veio $N_MOD"
[ "$C_MOD" = "0" ] && passa "nenhuma linha termina em … no destino mod" || falha "$C_MOD linha(s) cortada(s) com … no destino mod"
if [ "$B_MOD" -gt 0 ] && [ "$B_MOD" -le "$TETO_MOD" ]; then passa "additionalContext do mod cabe em $TETO_MOD B ($B_MOD B)"; else falha "additionalContext do mod fora do teto ($B_MOD B, teto $TETO_MOD B)"; fi
# Subtitulo inteiro: o fim de cada um dos 14 aparece na linha.
INTEIRAS="$(printf '%s\n' "$CTX_MOD" | grep -c '^\[2026-.*zzzzz[0-9]$' || true)"
[ "$INTEIRAS" = "14" ] && passa "o fim de cada um dos 14 subtitulos esta no additionalContext" || falha "so $INTEIRAS de 14 subtitulos chegaram ate o fim"

echo
echo "2. sem a flag: identico ao golden de $COMMIT_BASE e cortado pela escada atual"
B_SEM="$(nbytes "$CTX_SEM")"; N_SEM="$(linhas_obs "$CTX_SEM")"; C_SEM="$(linhas_corte "$CTX_SEM")"
echo "  sem flag: $B_SEM B (teto $TETO_SEM), $N_SEM linhas de observacao, $C_SEM terminando em …"
NORM_SEM="$(campo "$JSON_SEM" json)"; NORM_BASE="$(campo "$JSON_BASE" json)"
if [ -n "$NORM_BASE" ] && [ "$NORM_SEM" = "$NORM_BASE" ]; then passa "saida sem flag byte-identica ao golden de $COMMIT_BASE"; else
  falha "saida sem flag diverge do golden de $COMMIT_BASE"; echo "         base: ${NORM_BASE:0:200}"; echo "         head: ${NORM_SEM:0:200}"; fi
if [ "$B_SEM" -gt 0 ] && [ "$B_SEM" -le "$TETO_SEM" ]; then passa "sem flag cabe em $TETO_SEM B ($B_SEM B)"; else falha "sem flag fora do teto ($B_SEM B)"; fi
[ "$C_SEM" -gt 0 ] && passa "sem flag a escada corta linhas com … ($C_SEM de $N_SEM)" || falha "sem flag nenhuma linha foi cortada: a fixture nao exercita a escada"
[ "$CTX_MOD" != "$CTX_SEM" ] && passa "os dois destinos entregam textos diferentes na mesma fixture" || falha "mod e sem flag entregaram o mesmo texto"

echo
echo "3. o systemMessage e o mesmo nos dois destinos"
MSG_MOD="$(campo "$JSON_MOD" msg)"; MSG_SEM="$(campo "$JSON_SEM" msg)"; MSG_BASE="$(campo "$JSON_BASE" msg)"
if [ -n "$MSG_MOD" ] && [ "$MSG_MOD" = "$MSG_SEM" ] && [ "$MSG_SEM" = "$MSG_BASE" ]; then passa "systemMessage identico (mod, sem flag e golden)"; else falha "systemMessage difere entre destinos"; fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou   skipped: 0"
if [ "$falhou" = "0" ]; then echo "bateria passou"; else exit 1; fi
