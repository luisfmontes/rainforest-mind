#!/usr/bin/env bash
# Catraca das Issues #157, #158 e #159: bateria nao pode depender de ferramenta
# que a maquina de quem instala nao tem.
#
# O runner do Actions (windows-latest) traz `jq` preinstalado e cria `python3`
# alem de `python`; o instalador oficial do Windows cria so `python.exe`, e `jq`
# nao vem com nada. Em 2026-09-01, na primeira instalacao numa maquina de
# terceiro, duas baterias cairam por isso — e o CI NAO as veria nem ligado,
# porque a maquina dele e mais rica que a de quem instala. O CONTRIBUTING diz
# que Node e a unica dependencia; esta catraca faz a frase valer para o caminho
# de teste, que e onde ela nao valia.
#
# O que recusa, em linha que nao e comentario:
#   - chamada a `jq` ou `rg` (ripgrep) em qualquer bateria;
#   - `python`/`python3` chamado pelo NOME. A unica bateria cujo alvo E Python
#     (testa-medir-injecao.sh) resolve o interprete uma vez em `$PY`, testando
#     que o binario roda, e PULA com exit 3 quando nao ha Python 3 nenhum — o
#     resolvedor e as linhas que usam "$PY" sao as unicas formas admitidas.
#
# Uso: bash scripts/testa-dependencias-de-bateria.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok=0; falhou=0

# varre <arquivo...>; imprime uma linha por infracao; exit 1 se houve alguma.
# Em Node, nao em grep por linha: 82 baterias x centenas de linhas x um processo
# grep por linha passava de 15 minutos no Windows (medido em 2026-09-02).
varrer() {
  node -e '
    const fs = require("fs");
    let infracoes = 0;
    for (const f of process.argv.slice(1)) {
      const linhas = fs.readFileSync(f, "utf8").split(/\r?\n/);
      linhas.forEach((linha, i) => {
        if (/^\s*#/.test(linha)) return;                                   // comentario
        // posicao de COMANDO: inicio de linha, depois de ; | & ( ou $( — nunca dentro
        // de string (echo "cite python -m venv" nao e chamada)
        if (/(^|[;|&(]|\$\()\s*(!\s*)?(command -v\s+)?(jq|rg)(\s|$)/.test(linha)) {
          console.log("  " + f + ":" + (i + 1) + ": chama jq/rg: " + linha.trim()); infracoes++; return;
        }
        if (/(^|[;|&(]|\$\()\s*(!\s*)?(command -v\s+)?python3?(\s|$)/.test(linha)) {
          // formas admitidas: o resolvedor e a mensagem de PULADA
          if (/for cand in python3 python|"\$cand"|PULADA:/.test(linha)) return;
          console.log("  " + f + ":" + (i + 1) + ": chama python pelo nome (use o resolvedor $PY): " + linha.trim()); infracoes++;
        }
      });
    }
    process.exit(infracoes === 0 ? 0 : 1);
  ' "$@"
}

echo "== 1. as baterias do repositorio nao chamam jq, rg nem python pelo nome =="
# Esta bateria fica fora da propria varredura: as fixtures da secao 2 SAO as
# formas proibidas, escritas por printf, e se acusariam a si mesmas.
BATERIAS=$(ls "$SRC"/scripts/testa-*.sh "$SRC"/hooks/testa-*.sh | grep -v '/testa-dependencias-de-bateria\.sh$')
TOTAL=$(printf '%s\n' "$BATERIAS" | grep -c .)
if [ "$TOTAL" -lt 15 ]; then
  falhou=$((falhou+1)); echo "  FALHA achei $TOTAL baterias — glob quebrado"
fi
if SAIDA="$(varrer $BATERIAS)"; then
  ok=$((ok+1)); echo "  ok   $TOTAL baterias varridas, nenhuma dependencia fora de Node"
else
  falhou=$((falhou+1)); echo "  FALHA dependencia externa em bateria:"; echo "$SAIDA"
fi

echo
echo "== 2. a varredura acende (mutacao: fixture com cada forma proibida) =="
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
printf '#!/bin/bash\n# jq aqui e comentario, nao conta\nx=$(printf x | jq -Rs .)\n' > "$SB/testa-a.sh"
printf '#!/bin/bash\npython3 -c "print(1)"\n' > "$SB/testa-b.sh"
printf '#!/bin/bash\nV="$(python -c "print(1)")"\n' > "$SB/testa-c.sh"
printf '#!/bin/bash\nrg -n foo .\n' > "$SB/testa-d.sh"
printf '#!/bin/bash\nfor cand in python3 python; do command -v "$cand"; done\n"$PY" -c "print(1)"\necho "PULADA: falta python3"\n' > "$SB/testa-limpa.sh"
for caso in a b c d; do
  if varrer "$SB/testa-$caso.sh" >/dev/null; then
    falhou=$((falhou+1)); echo "  FALHA fixture $caso deveria ser recusada"
  else
    ok=$((ok+1)); echo "  ok   fixture $caso recusada: $(varrer "$SB/testa-$caso.sh" | head -1 | sed 's/^ *//')"
  fi
done
if varrer "$SB/testa-limpa.sh" >/dev/null; then
  ok=$((ok+1)); echo "  ok   resolvedor \$PY e PULADA sao admitidos"
else
  falhou=$((falhou+1)); echo "  FALHA o resolvedor \$PY foi recusado:"; varrer "$SB/testa-limpa.sh"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
