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

# fixtures dos casos novos (rodada 2): subpasta com nome único, nome duplicado,
# pastas ignoradas, fonte .js (caixa sensível) e um arquivo FORA da raiz
mkdir -p "$REPO/Fontes/Gestao" "$REPO/dup/a1" "$REPO/dup/a2" "$REPO/dup/a3" "$REPO/dup/a4" \
  "$REPO/node_modules/pacote" "$REPO/.git"
printf '// cabeçalho\n\nUser Function ZContrato()\n' > "$REPO/Fontes/Gestao/zcontrato.prw"
for d in a1 a2 a3 a4; do printf '// dup\n' > "$REPO/dup/$d/dup.prw"; done
printf '// ztrap\n' > "$REPO/node_modules/pacote/ztrap.prw"
printf '// zoculto\n' > "$REPO/.git/zoculto.prw"
printf 'const a = 1;\nfunction MontaNFe() {}\n' > "$REPO/app.js"
printf 'linha um\nTOKEN_SECRETO=1\n' > "$SB/segredo.txt"

# fixtures da rodada 3 (achado do revisor): diretório oculto e ./ inicial
mkdir -p "$REPO/.github/workflows" "$REPO/src"
printf 'name: ci\non: push\njobs: {}\n' > "$REPO/.github/workflows/ci.yml"
printf 'const x = 1;\n' > "$REPO/src/x.cjs"

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

# --- rodada 2 (achados 3, 5, 6, 8 do revisor) ---

# achado 3: citação só pelo nome resolve se for único, sem diferenciar caixa
M8=$(mapa c8-nome-unico 'Ver `ZCONTRATO.PRW:3` (`zcontrato`) e `zcontrato.prw#ZContrato`.')
verifica 8-nome-unico "citação pelo nome sem caixa resolve e mostra o caminho achado" 0 "ok Fontes/Gestao/zcontrato.prw:3 \`zcontrato\`" node "$CONF" "$M8" --repo "$REPO"
verifica 8-nome-unico "forma #Simbolo pelo nome resolve e mostra o caminho achado" 0 "ok Fontes/Gestao/zcontrato.prw#ZContrato" node "$CONF" "$M8" --repo "$REPO"

# achado 3: nome em mais de um lugar é ambíguo, com até 3 candidatos listados
M9=$(mapa c9-ambiguo 'Ver `dup.prw:1`.')
verifica 9-ambiguo "nome em mais de um lugar sai ambiguo e falha" 1 "ambiguo dup.prw:1" node "$CONF" "$M9" --repo "$REPO"
verifica 9-ambiguo "a lista de candidatos mostra três e conta o resto (+1)" 1 "(+1)" node "$CONF" "$M9" --repo "$REPO"

# achado 3: pastas .git e node_modules não entram na busca por nome
M10=$(mapa c10-pastas-ignoradas 'Ver `ztrap.prw:1` (só em node_modules) e `zoculto.prw#X` (só em .git).')
verifica 10-ignoradas "arquivo só em node_modules sai arquivo-ausente" 1 "arquivo-ausente ztrap.prw:1" node "$CONF" "$M10" --repo "$REPO"
verifica 10-ignoradas "arquivo só em .git sai arquivo-ausente" 1 "arquivo-ausente zoculto.prw#X" node "$CONF" "$M10" --repo "$REPO"

# achado 5: intervalo invertido é linha-fora
M11=$(mapa c11-ini-maior 'Intervalo invertido: `zfiscal01.prw:20-10`.')
verifica 11-ini-maior "intervalo com início maior que o fim sai linha-fora" 1 "linha-fora zfiscal01.prw:20-10" node "$CONF" "$M11" --repo "$REPO"

# achado 6: caminho que sai da raiz é fora-da-raiz, sem ler o arquivo (nada de linha-fora nem símbolo)
M12=$(mapa c12-fora-da-raiz 'Ver `sub/../../segredo.txt:2`, `sub/../../segredo.txt:99`, `sub/../../segredo.txt#TOKEN_SECRETO` e `sub/../../nao-existe.txt:2`.')
verifica 12-fora-da-raiz "citação que sai da raiz sai fora-da-raiz" 1 "fora-da-raiz sub/../../segredo.txt:2" node "$CONF" "$M12" --repo "$REPO"
verifica 12-fora-da-raiz "as quatro citações fora da raiz falham e nenhuma passa" 1 "4 âncoras: 0 ok, 4 falhas" node "$CONF" "$M12" --repo "$REPO"
nao_contem 12-fora-da-raiz "fora da raiz não vaza linha-fora (oráculo de tamanho)" "linha-fora" node "$CONF" "$M12" --repo "$REPO"
nao_contem 12-fora-da-raiz "fora da raiz não vaza simbolo-ausente nem arquivo-ausente" "simbolo-ausente" node "$CONF" "$M12" --repo "$REPO"

# achado 8: URL e host:porta não viram âncora; horário também não
M13=$(mapa c13-host-porta 'Endereço https://x.com/a.js:10, host.com:8080, example.com:8080 e horário 10:30.')
verifica 13-host-porta "URL, host:porta e horário dão zero âncoras" 0 "0 âncoras: 0 ok, 0 falhas" node "$CONF" "$M13" --repo "$REPO"
nao_contem 13-host-porta "host:porta não sai arquivo-ausente" "arquivo-ausente" node "$CONF" "$M13" --repo "$REPO"

# achado 8: símbolo de ADVPL (.prw) sem diferenciar caixa
M14=$(mapa c14-caixa-advpl 'Ver `zfiscal01.prw:120` (`montanfe`) e `zfiscal01.prw#montanfe`.')
verifica 14-caixa-advpl "símbolo em .prw sem a caixa certa sai ok" 0 "2 âncoras: 2 ok, 0 falhas" node "$CONF" "$M14" --repo "$REPO"

# achado 8: símbolo em outras extensões continua sensível a caixa
M15=$(mapa c15-caixa-js 'Ver `app.js#montanfe` e `app.js#MontaNFe`.')
verifica 15-caixa-js "símbolo em .js é sensível a caixa: minúsculo falha, certo passa" 1 "1 ok, 1 falhas" node "$CONF" "$M15" --repo "$REPO"
verifica 15-caixa-js "o minúsculo sai simbolo-ausente" 1 "simbolo-ausente app.js#montanfe" node "$CONF" "$M15" --repo "$REPO"

# --- rodada 3 (achado do revisor: caminho que começa com ponto) ---

# diretório oculto: o ponto inicial faz parte do caminho e aparece no rótulo
M16=$(mapa c16-dir-oculto 'Workflow: `.github/workflows/ci.yml:2`.')
verifica 16-dir-oculto "diretório oculto (.github) sai ok e o rótulo preserva o ponto" 0 "ok .github/workflows/ci.yml:2" node "$CONF" "$M16" --repo "$REPO"
M17=$(mapa c17-dir-oculto-ausente 'Ver `.github/inexistente.yml:1`.')
verifica 17-dir-oculto-ausente "arquivo inexistente em diretório oculto sai arquivo-ausente" 1 "arquivo-ausente .github/inexistente.yml:1" node "$CONF" "$M17" --repo "$REPO"

# ./ inicial: normalizado para o caminho relativo à raiz
M18=$(mapa c18-dot-slash 'Ver `./src/x.cjs:1`.')
verifica 18-dot-slash "./ inicial sai ok e o rótulo sai relativo à raiz" 0 "ok src/x.cjs:1" node "$CONF" "$M18" --repo "$REPO"

# controle: ../ que sai da raiz continua fora-da-raiz, mesmo com o ponto inicial aceito
M19=$(mapa c19-fora-controle 'Ver `../fora.cjs:1`.')
verifica 19-fora-controle "../ que sai da raiz continua fora-da-raiz" 1 "fora-da-raiz ../fora.cjs:1" node "$CONF" "$M19" --repo "$REPO"

echo "total=$total vermelhas:[$(echo "$vermelhas" | sed 's/^ //; s/ /, /g')]"
if [ -z "$vermelhas" ]; then exit 0; fi
exit 1
