#!/bin/bash
# Bateria do conferir-ancoras.cjs. Monta um repositório PRÓPRIO num diretório
# temporário: um .prw de 210 linhas gravado em CP-1252 (bytes \xe7\xe3o fora de
# UTF-8) com `User Function MontaNFe()` na linha 120 e um comentário com acento
# na linha 30. Os mapas seguem o formato real da arqueologia.
#
# Nenhum caso afirma sobre o TEXTO do fonte: o fonte é só o terreno. O que cada
# caso prova é o status que o script devolve para uma citação, com o exit code.
#
# Uso: bash scripts/testa-conferir-ancoras.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
CONF="$SRC/scripts/conferir-ancoras.cjs"
REPO="$SB/repo"
mkdir -p "$REPO"

# fonte CP-1252: linha 30 com acento em latin1, linha 120 com a função, 210 linhas
{
  for i in $(seq 1 210); do
    if [ "$i" = 30 ]; then printf '// observa\xe7\xe3o: n\xe3o alterar a ordem\n'
    elif [ "$i" = 120 ]; then printf 'User Function MontaNFe()\n'
    else printf '// linha %d\n' "$i"; fi
  done
} > "$REPO/zfiscal01.prw"

mapa() { # nome, texto -> grava $SB/<nome>.md e devolve o caminho
  printf '%s\n' "$2" > "$SB/$1.md"
  printf '%s' "$SB/$1.md"
}

vermelhas=""
total=0
registra() { # caso, passou(1|0), descricao
  total=$((total+1))
  if [ "$2" = 1 ]; then
    echo "  ok    [$1] $3"
  else
    echo "  FALHA [$1] $3"
    case " $vermelhas " in *" $1 "*) ;; *) vermelhas="$vermelhas $1";; esac
  fi
}

# verifica CASO NOME EXIT_ESPERADO TRECHO -- comando...   (TRECHO "-" = não exige)
verifica() {
  local caso="$1" nome="$2" esp="$3" trecho="$4"; shift 4
  local saida; saida=$("$@" 2>&1); local got=$?
  local p=1
  [ "$got" = "$esp" ] || p=0
  if [ "$trecho" != "-" ] && ! printf '%s\n' "$saida" | grep -qF -- "$trecho"; then p=0; fi
  registra "$caso" "$p" "$nome (exit $got)"
  if [ "$p" = 0 ]; then printf '%s\n' "$saida" | sed 's/^/         /'; fi
}

# nao_contem CASO NOME TEXTO_PROIBIDO -- comando...
nao_contem() {
  local caso="$1" nome="$2" proibido="$3"; shift 3
  local saida; saida=$("$@" 2>&1)
  local p=1
  if printf '%s\n' "$saida" | grep -qF -- "$proibido"; then p=0; fi
  registra "$caso" "$p" "$nome"
  if [ "$p" = 0 ]; then printf '%s\n' "$saida" | sed 's/^/         /'; fi
}

M1=$(mapa c1-linha-fora 'Ver `zfiscal01.prw:500` e `zfiscal01.prw:0`.')
verifica 1-linha-alem-do-fim "linha além do fim e linha zero saem linha-fora" 1 "linha-fora zfiscal01.prw:500" node "$CONF" "$M1" --repo "$REPO"
verifica 1-linha-alem-do-fim "linha zero sai linha-fora" 1 "linha-fora zfiscal01.prw:0" node "$CONF" "$M1" --repo "$REPO"

M2=$(mapa c2-arquivo-ausente 'Ver `nao-existe.prw:10`.')
verifica 2-arquivo-ausente "arquivo inexistente sai arquivo-ausente" 1 "arquivo-ausente nao-existe.prw:10" node "$CONF" "$M2" --repo "$REPO"

M3A=$(mapa c3-simbolo-presente 'Função `zfiscal01.prw#MontaNFe`, linha `zfiscal01.prw:120` (`MontaNFe`).')
verifica 3-simbolo "símbolo presente na forma #Simbolo e na forma linha sai ok" 0 "ok zfiscal01.prw#MontaNFe" node "$CONF" "$M3A" --repo "$REPO"
verifica 3-simbolo "símbolo presente na forma linha sai ok" 0 "ok zfiscal01.prw:120 \`MontaNFe\`" node "$CONF" "$M3A" --repo "$REPO"
M3B=$(mapa c3-simbolo-ausente 'Função `zfiscal01.prw#NaoExiste`.')
verifica 3-simbolo "símbolo ausente na forma #Simbolo sai simbolo-ausente" 1 "simbolo-ausente zfiscal01.prw#NaoExiste" node "$CONF" "$M3B" --repo "$REPO"

M4A=$(mapa c4-janela-80 'Dentro da janela: `zfiscal01.prw:200` (`MontaNFe`) e `zfiscal01.prw:200 `MontaNFe``.')
verifica 4-janela-80 "símbolo 80 linhas acima da citada sai ok (forma com parênteses e sem)" 0 "ok zfiscal01.prw:200 \`MontaNFe\`" node "$CONF" "$M4A" --repo "$REPO"
M4B=$(mapa c4-janela-81 'Fora da janela: `zfiscal01.prw:201` (`MontaNFe`).')
verifica 4-janela-81 "símbolo 81 linhas acima da citada sai simbolo-ausente" 1 "simbolo-ausente zfiscal01.prw:201 \`MontaNFe\`" node "$CONF" "$M4B" --repo "$REPO"

M5A=$(mapa c5-intervalo 'Intervalo válido: `zfiscal01.prw:10-20`.')
verifica 5-intervalo "intervalo válido sai ok" 0 "ok zfiscal01.prw:10-20" node "$CONF" "$M5A" --repo "$REPO"
M5B=$(mapa c5-intervalo-fora 'Intervalo estourado: `zfiscal01.prw:10-999`.')
verifica 5-intervalo "intervalo com ponta fora sai linha-fora" 1 "linha-fora zfiscal01.prw:10-999" node "$CONF" "$M5B" --repo "$REPO"

M6=$(mapa c6-cp1252 'Linha com acento: `zfiscal01.prw:30`. Função: `zfiscal01.prw:120` (`MontaNFe`).')
verifica 6-cp1252 "fonte CP-1252 sai ok e não derruba o script" 0 "ok zfiscal01.prw:30" node "$CONF" "$M6" --repo "$REPO"
nao_contem 6-cp1252 "a leitura não lança nem vira erro" "Error" node "$CONF" "$M6" --repo "$REPO"
verifica 6-cp1252 "as duas citações do fonte CP-1252 saem ok no resumo" 0 "2 âncoras: 2 ok, 0 falhas" node "$CONF" "$M6" --repo "$REPO"

M7A=$(mapa c7-tudo-ok 'Ok: `zfiscal01.prw:120` e `zfiscal01.prw#MontaNFe`.')
verifica 7-exit-0 "tudo ok sai 0 com resumo" 0 "2 âncoras: 2 ok, 0 falhas" node "$CONF" "$M7A" --repo "$REPO"
M7B=$(mapa c7-com-falha 'Ok: `zfiscal01.prw:120`. Falha: `zfiscal01.prw:999`.')
verifica 7-exit-1 "alguma falha sai 1 com resumo" 1 "2 âncoras: 1 ok, 1 falhas" node "$CONF" "$M7B" --repo "$REPO"
verifica 7-exit-2-sem-argumento "sem argumento sai 2 com uso no stderr" 2 "uso:" node "$CONF"
verifica 7-exit-2-mapa-inexistente "mapa inexistente sai 2 com uso" 2 "uso:" node "$CONF" "$SB/nao-existe.md" --repo "$REPO"
M7C=$(mapa c7-sem-ancora 'Texto sem citação nenhuma, só CONFIRMADO e INFERIDO.')
verifica 7-zero-ancoras "mapa sem âncora sai 0 com 0 âncoras" 0 "0 âncoras" node "$CONF" "$M7C" --repo "$REPO"

echo "total=$total vermelhas:[$(echo "$vermelhas" | sed 's/^ //; s/ /, /g')]"
if [ -z "$vermelhas" ]; then exit 0; fi
exit 1
