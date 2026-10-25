#!/bin/bash
# Bateria dos degraus da regra implícita do conferir-ancoras.cjs (D5 do lote 6) e do
# parágrafo em negrito antes dos campos (D10b do lote 6). Monta um repo git PRÓPRIO num
# diretório temporário, com um commit (para ter sha real), e uma raiz sem git. Cada caso
# roda o script de verdade e afirma sobre a SAÍDA e o exit code, nunca sobre o texto do fonte.
#
# Trechos: um trecho comum tem que aparecer na saída (substring fixa); um trecho com `!` na
# frente tem que NÃO aparecer; um trecho com `=` na frente tem que casar uma linha inteira.
#
# Uso: bash scripts/testa-conferir-ancoras-degraus.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
CONF="$SRC/scripts/conferir-ancoras.cjs"
REPO="$SB/repo"
SEMGIT="$SB/semgit"
mkdir -p "$REPO/scripts" "$SEMGIT/scripts"

# testes-alvo: um cita R1, um não cita id nenhum, um cita só R10
printf '# caso R1, período fechado\n' > "$REPO/scripts/testa-cita.sh"
printf '# bateria sem o id da regra\n' > "$REPO/scripts/testa-sem-id.sh"
printf '# caso R10 apenas\n' > "$REPO/scripts/testa-r10.sh"
printf '# caso R1, período fechado\n' > "$SEMGIT/scripts/testa-cita.sh"

# repo git com um commit: o sha real que a regra pode citar
(cd "$REPO" && git init -q && git add -A && git -c user.email=teste@teste -c user.name=teste commit -q -m base)
SHA=$(cd "$REPO" && git rev-parse HEAD)
FALSO=0123456789abcdef0123456789abcdef01234567

ok=0
falhou=0

mapa() { # nome, texto -> grava $SB/<nome>.md e devolve o caminho
  printf '%b' "$2" > "$SB/$1.md"
  printf '%s' "$SB/$1.md"
}

verifica() { # id, descrição, exit esperado, raiz, mapa, trechos...
  local id="$1" desc="$2" esp="$3" raiz="$4" mapa="$5" saida exit_real motivo="" t
  shift 5
  saida=$(node "$CONF" "$mapa" --repo "$raiz" 2>&1)
  exit_real=$?
  if [ "$exit_real" != "$esp" ]; then motivo="exit $exit_real, esperado $esp"; fi
  for t in "$@"; do
    case "$t" in
      '!'*)
        if grep -qF -- "${t:1}" <<< "$saida"; then motivo="$motivo; apareceu '${t:1}'"; fi ;;
      '='*)
        if ! grep -qxF -- "${t:1}" <<< "$saida"; then motivo="$motivo; faltou a linha '${t:1}'"; fi ;;
      *)
        if ! grep -qF -- "$t" <<< "$saida"; then motivo="$motivo; faltou '$t'"; fi ;;
    esac
  done
  if [ -z "$motivo" ]; then
    ok=$((ok+1))
    echo "  ok    [$id] $desc"
  else
    falhou=$((falhou+1))
    echo "  FALHA [$id] $desc —$motivo"
    echo "        saída:"
    sed 's/^/          /' <<< "$saida"
  fi
}

# --- degrau 1: teste ausente ---
M1=$(mapa d1-ausente '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-nao-existe.sh\n')
verifica d1 "Teste: que não existe sai teste-ausente, exit 0" 0 "$REPO" "$M1" \
  "regra R1 teste-ausente" \
  "!regra R1 testada" \
  "· regras: 0 testada, 0 sem-teste, 0 sem-campos, 0 sem-id, 1 teste-ausente, 0 teste-sem-id, 0 sha-desconhecido"

# --- degrau 1b: o campo é `<bateria ou caso>` — crase e caso depois do caminho não viram teste-ausente ---
M1B=$(mapa d1b-caso '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: `scripts/testa-cita.sh` caso 3\n')
verifica d1b "Teste: com crase e caso depois do caminho sai testada" 0 "$REPO" "$M1B" \
  "=regra R1 testada" \
  "!regra R1 teste-ausente"

# --- degrau 2: o arquivo existe e não cita o id ---
M2=$(mapa d2-sem-id '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-sem-id.sh\n')
verifica d2 "Teste: que existe e não cita R1 sai teste-sem-id" 0 "$REPO" "$M2" \
  "regra R1 teste-sem-id" \
  "!regra R1 testada" \
  "· regras: 0 testada, 0 sem-teste, 0 sem-campos, 0 sem-id, 0 teste-ausente, 1 teste-sem-id, 0 sha-desconhecido"

# --- degrau 2: cita R10 e não R1: o id é palavra inteira ---
M3=$(mapa d3-r10-nao-r1 '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-r10.sh\n')
verifica d3 "Teste: que cita só R10 não conta como R1: sai teste-sem-id" 0 "$REPO" "$M3" \
  "regra R1 teste-sem-id" \
  "!regra R1 testada"

# --- degrau 2: a regra R10 cita o arquivo que cita R10 ---
M4=$(mapa d4-r10-cita '## Regras implícitas\n\n**R10 — Regra dez**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-r10.sh\n')
verifica d4 "regra R10 com teste que cita R10 sai testada" 0 "$REPO" "$M4" \
  "regra R10 testada"

# --- degrau 3: arquivo existe e cita o id ---
M5=$(mapa d5-cita '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-cita.sh\n')
verifica d5 "Teste: que existe e cita R1 sai testada, exit 0, sem aviso de sha" 0 "$REPO" "$M5" \
  "regra R1 testada" \
  "!regra R1 sha-desconhecido" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id, 0 teste-ausente, 0 teste-sem-id, 0 sha-desconhecido"

# --- sha que não resolve: aviso extra, o estado da regra não muda ---
M6=$(mapa d6-sha-falso '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$FALSO"'\nTeste: scripts/testa-cita.sh\n')
verifica d6 "sha que não resolve sai regra R1 sha-desconhecido e a regra segue testada, exit 0" 0 "$REPO" "$M6" \
  "regra R1 testada" \
  "=regra R1 sha-desconhecido" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id, 0 teste-ausente, 0 teste-sem-id, 1 sha-desconhecido"

# --- sha real, curto: resolve e não avisa ---
M7=$(mapa d7-sha-curto '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"${SHA:0:7}"'\nTeste: scripts/testa-cita.sh\n')
verifica d7 "sha curto real resolve por git cat-file e não avisa" 0 "$REPO" "$M7" \
  "regra R1 testada" \
  "!regra R1 sha-desconhecido"

# --- raiz sem git: a checagem de sha sai de fora, sem aviso ---
M8=$(mapa d8-sem-git '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$FALSO"'\nTeste: scripts/testa-cita.sh\n')
verifica d8 "raiz que não é repo git não confere nem avisa sha" 0 "$SEMGIT" "$M8" \
  "regra R1 testada" \
  "!regra R1 sha-desconhecido"

# --- D10b: negrito sem id antes dos campos é corpo da regra ---
M9=$(mapa d9-atencao-antes-dos-campos '## Regras implícitas\n\n**R1 — Período fechado barra**\n\n**Atenção:** o teste cobre só a data.\nVerificada em: '"$SHA"'\nTeste: scripts/testa-cita.sh\n')
verifica d9 "**Atenção:** antes dos campos é corpo da regra: R1 testada, sem sem-id, exit 0" 0 "$REPO" "$M9" \
  "regra R1 testada" \
  "!regra sem-id" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id, 0 teste-ausente, 0 teste-sem-id, 0 sha-desconhecido"

# --- D10b: negrito sem id depois dos campos fecha a regra e sai sem-id ---
M10=$(mapa d10-negrito-depois '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: '"$SHA"'\nTeste: scripts/testa-cita.sh\n\n**Regra antiga sem id**\nTexto que não é corpo da R1.\n')
verifica d10 "negrito sem id depois dos campos da R1 sai sem-id e fecha a regra" 0 "$REPO" "$M10" \
  "regra R1 testada" \
  "regra sem-id: **Regra antiga sem id**" \
  "!Texto que não é corpo" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 1 sem-id, 0 teste-ausente, 0 teste-sem-id, 0 sha-desconhecido"

# --- sem-campos tem precedência sobre teste-ausente: falha, exit 1 ---
M11=$(mapa d11-sem-campos-antes '## Regras implícitas\n\n**R1 — Sem verificada**\nTeste: scripts/testa-nao-existe.sh\n')
verifica d11 "regra sem Verificada em sai sem-campos mesmo com Teste: ausente, exit 1" 1 "$REPO" "$M11" \
  "regra R1 sem-campos" \
  "!regra R1 teste-ausente"

echo "== resultado: $ok ok, $falhou falha(s) =="
if [ "$falhou" -gt 0 ]; then exit 1; fi
exit 0
