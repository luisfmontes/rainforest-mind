#!/bin/bash
# Bateria da leitura de regras implícitas do conferir-ancoras.cjs (D5 do lote 3).
# Monta um mapa e uma raiz PRÓPRIOS num diretório temporário. Cada caso roda o
# script de verdade e afirma sobre a SAÍDA e o exit code, nunca sobre o texto
# do fonte do script.
#
# Trechos: um trecho comum tem que aparecer na saída (substring fixa); um trecho
# com `!` na frente tem que NÃO aparecer; um trecho com `=` na frente tem que
# casar uma linha inteira da saída.
#
# Uso: bash scripts/testa-conferir-ancoras-regras.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
CONF="$SRC/scripts/conferir-ancoras.cjs"
REPO="$SB/repo"
mkdir -p "$REPO"
printf 'linha 1\nlinha 2\n' > "$REPO/a.cjs"
# o Teste: dos casos com R1 testada precisa existir e citar R1 (degrau testada, D5 do lote 6)
mkdir -p "$REPO/scripts"
printf '# caso R1, período fechado\n' > "$REPO/scripts/testa-x.sh"

ok=0
falhou=0

mapa() { # nome, texto -> grava $SB/<nome>.md e devolve o caminho
  printf '%b' "$2" > "$SB/$1.md"
  printf '%s' "$SB/$1.md"
}

verifica() { # id, descrição, exit esperado, mapa, trechos...
  local id="$1" desc="$2" esp="$3" mapa="$4" saida exit_real motivo="" t
  shift 4
  saida=$(node "$CONF" "$mapa" --repo "$REPO" 2>&1)
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

# --- R1 testada, R2 sem-teste, R3 sem campos ---
M1=$(mapa c1-tres-estados '# Mapa\n\n## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n\n**R2 — Outra**\nVerificada em: abc1234\nTeste: nenhum\n\n**R3 — Terceira**\n')
verifica c1 "regra R3 sem Verificada em sai sem-campos e exit 1 (R1 testada, R2 sem-teste, resumo conta as três)" 1 "$M1" \
  "regra R1 testada" "regra R2 sem-teste" "regra R3 sem-campos" \
  "0 âncoras: 0 ok, 0 falhas · regras: 1 testada, 1 sem-teste, 1 sem-campos, 0 sem-id"

# --- sem R3 o exit é 0; R2 (sem-teste) é só aviso ---
M2=$(mapa c2-sem-r3 '# Mapa\n\n## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n\n**R2 — Outra**\nVerificada em: abc1234\nTeste: nenhum\n')
verifica c2 "sem R3 sai 0 e R2 sem-teste é aviso" 0 "$M2" \
  "regra R1 testada" "regra R2 sem-teste" "!regra R3" \
  "0 âncoras: 0 ok, 0 falhas · regras: 1 testada, 1 sem-teste, 0 sem-campos, 0 sem-id"

# --- regra com Teste mas sem Verificada em é sem-campos ---
M3=$(mapa c3-sem-verificada '## Regras implícitas\n\n**R1 — Sem sha**\nTeste: scripts/testa-x.sh\n')
verifica c3 "regra com Teste e sem Verificada em sai sem-campos e exit 1" 1 "$M3" \
  "regra R1 sem-campos"

# --- regra com Verificada em mas sem Teste é sem-campos ---
M4=$(mapa c4-sem-teste '## Regras implícitas\n\n**R1 — Sem teste**\nVerificada em: abc1234\n')
verifica c4 "regra com Verificada em e sem Teste sai sem-campos e exit 1" 1 "$M4" \
  "regra R1 sem-campos"

# --- formato antigo: parágrafo sem marcador é sem-id e não muda o exit ---
M5=$(mapa c5-formato-antigo '## Regras implícitas\n\n**Período fiscal fechado barra operação** — lê `GetSX8Recesso()` no topo, confere\nse a data está na faixa bloqueada. `INFERIDO`.\n')
verifica c5 "formato antigo sai regra sem-id como aviso e exit 0" 0 "$M5" \
  "regra sem-id: **Período fiscal fechado barra operação**" \
  "!regra R" \
  "0 âncoras: 0 ok, 0 falhas · regras: 0 testada, 0 sem-teste, 0 sem-campos, 1 sem-id"

# --- formato antigo misturado com regra nova: o sem-id não muda o exit ---
M6=$(mapa c6-misto '## Regras implícitas\n\n**Regra antiga** — texto sem marcador\n\n**R1 — Nova**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n')
verifica c6 "formato antigo misturado com regra nova sai 0 com sem-id e R1 testada" 0 "$M6" \
  "regra R1 testada" "regra sem-id: **Regra antiga** — texto sem marcador" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 1 sem-id"

# --- hífen aceito no lugar do travessão; seção termina no próximo `## ` ---
M7=$(mapa c7-hifen-e-fim '## Regras implícitas\n\n**R1 - Hífen**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n\n## Outra seção\n\n**R9 — Fora**\nVerificada em: abc1234\nTeste: nenhum\n')
verifica c7 "hífen vira regra, e regra depois do próximo ## fica fora da seção" 0 "$M7" \
  "regra R1 testada" "!regra R9" "!regra sem-id" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id"

# --- mapa sem a seção sai como hoje: uma âncora ok, sem linha de regra e sem sufixo ---
M8=$(mapa c8-sem-secao '# Mapa\n\n## Superfície\n\nVer `a.cjs:1`.\n')
verifica c8 "mapa sem a seção sai como hoje: âncora ok e resumo sem sufixo de regras" 0 "$M8" \
  "=ok a.cjs:1" \
  "=1 âncoras: 1 ok, 0 falhas" \
  "!regra" \
  "!regras:"

# --- mapa sem âncora e sem seção sai como hoje ---
M9=$(mapa c9-vazio '# Mapa\n\nSem citação nenhuma.\n')
verifica c9 "mapa sem seção e sem âncora sai 0 com o resumo de sempre" 0 "$M9" \
  "=0 âncoras: 0 ok, 0 falhas" \
  "!regra"

# --- parágrafo de descrição depois de linha em branco é corpo da regra aberta, não sem-id ---
M10=$(mapa c10-corpo-depois-de-linha-em-branco '## Regras implícitas\n\n**R1 — Título**\n\nDescrição da regra, sem citação.\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n')
verifica c10 "parágrafo depois de linha em branco é corpo da regra aberta: R1 testada, sem sem-id, exit 0" 0 "$M10" \
  "regra R1 testada" \
  "!regra sem-id" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id"

# --- Teste: Nenhum em qualquer caixa é sem-teste ---
M11=$(mapa c11-nenhum-caixa '## Regras implícitas\n\n**R1 — Maiúscula**\nVerificada em: abc1234\nTeste: Nenhum\n\n**R2 — Caixa alta**\nVerificada em: abc1234\nTeste: NENHUM\n')
verifica c11 "Teste: Nenhum e NENHUM são sem-teste, exit 0" 0 "$M11" \
  "regra R1 sem-teste" \
  "regra R2 sem-teste" \
  "!regra R1 testada" \
  "· regras: 0 testada, 2 sem-teste, 0 sem-campos, 0 sem-id"

# --- parágrafo em negrito sem id depois de regra R1 fecha a R1 e sai sem-id (D7 do lote 5) ---
M12=$(mapa c12-negrito-depois-de-r1 '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n\n**Regra antiga sem id**\nTexto que não é corpo da R1.\n')
verifica c12 "parágrafo em negrito sem id depois de regra R1 sai sem-id" 0 "$M12" \
  "regra R1 testada" \
  "regra sem-id: **Regra antiga sem id**" \
  "!Texto que não é corpo" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 1 sem-id"

# --- parágrafo comum depois da R1 (sem ** na abertura) segue corpo dela, sem sem-id ---
M13=$(mapa c13-comum-depois-de-r1 '## Regras implícitas\n\n**R1 — Período fechado barra**\nVerificada em: abc1234\nTeste: scripts/testa-x.sh\n\nParágrafo comum, sem negrito na abertura.\n')
verifica c13 "parágrafo comum depois da R1 segue corpo dela: R1 testada, sem sem-id, exit 0" 0 "$M13" \
  "regra R1 testada" \
  "!regra sem-id" \
  "· regras: 1 testada, 0 sem-teste, 0 sem-campos, 0 sem-id"

echo "ok: $ok   falhou: $falhou"
if [ "$falhou" -gt 0 ]; then exit 1; fi
exit 0
