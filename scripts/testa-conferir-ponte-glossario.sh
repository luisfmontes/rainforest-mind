#!/bin/bash
# Bateria da linha do GLOSSARIO.md no conferidor da ponte (tarefa 6 do fluxo 2026-10-08-glossario-compartilhado).
# Uso: bash scripts/testa-conferir-ponte-glossario.sh
#
# As promessas que importam:
#   1. ponte gerada com GLOSSARIO.md confere verde (a linha do glossario NAO vira "editado a mao")
#   2. ponte gerada sem GLOSSARIO.md continua verde
#   3. glossario que SURGE depois da geracao: exit 2, mensagem do glossario, sem "editado"
#   4. glossario que SUMIU depois da geracao: exit 2, mensagem inversa, sem "editado"
#   5. edicao a mao de outra linha, com glossario presente: segue RECUSADO editado a mao
#   6. edicao a mao MAIS glossario surgido: o veredito e' edicao (a linha do glossario nao esconde outra edicao)
#   7. pasta chamada GLOSSARIO.md nao conta como glossario
#   8. --json traz situacao glossario-surgiu / glossario-sumiu
#   9. stdin (-): sai 1 antes de chegar no corpo (comportamento observado e fixado)
# Nenhum caso le o texto do fonte: cada um roda a ponte ou o conferidor e olha o resultado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

PONTE="$SRC/scripts/ponte.cjs"
CONF="$SRC/scripts/conferir-ponte.cjs"
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"

w() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

ok=0; falhou=0
afirma() { # nome, comando de teste...
  local nome="$1"; shift
  if "$@" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
SAIDA=""; GOT=""
conferir() { SAIDA=$(node "$CONF" "$@" 2>&1); GOT=$?; }
saiu() { [ "$GOT" = "$1" ]; }
diz() { printf '%s' "$SAIDA" | grep -qF -- "$1"; }
nao_diz() { ! printf '%s' "$SAIDA" | grep -qF -- "$1"; }
gera() { node "$PONTE" --alvo "$(w "$1")" --agente codex --aplicar >/dev/null 2>&1; }
sem_editado() { nao_diz "editado"; }

# Cada caso cria a sua caixa, para que um caso nao herde arquivo do outro.
nova_caixa() { local d="$CAIXA/$1"; rm -rf "$d"; mkdir -p "$d"; echo "$d"; }

echo "== 1. ponte gerada com GLOSSARIO.md confere verde =="
A="$(nova_caixa com-glossario)"; printf '# Glossario\n' > "$A/GLOSSARIO.md"
gera "$A"
conferir "$(w "$A/AGENTS.md")"
afirma "ponte gerada com GLOSSARIO.md confere verde (exit 0)" saiu 0
afirma "ponte gerada com GLOSSARIO.md confere verde (imprime CONFERIDO)" diz "CONFERIDO"
afirma "ponte gerada com GLOSSARIO.md confere verde (nao acusa edicao)" sem_editado

echo
echo "== 2. ponte gerada sem GLOSSARIO.md continua verde =="
B="$(nova_caixa sem-glossario)"
gera "$B"
conferir "$(w "$B/AGENTS.md")"
afirma "sem GLOSSARIO.md: exit 0" saiu 0
afirma "sem GLOSSARIO.md: imprime CONFERIDO" diz "CONFERIDO"

echo
echo "== 3. GLOSSARIO.md que SURGE depois da geracao =="
C="$(nova_caixa surgiu)"
gera "$C"
printf '# Glossario\n' > "$C/GLOSSARIO.md"
conferir "$(w "$C/AGENTS.md")"
afirma "surgiu: exit 2" saiu 2
afirma "surgiu: diz que o GLOSSARIO.md existe" diz "GLOSSARIO.md existe na raiz do alvo"
afirma "surgiu: diz que a ponte nao aponta para ele" diz "a ponte não aponta para ele"
afirma "surgiu: traz o comando de regeracao com o agente certo" diz "node scripts/ponte.cjs --alvo . --agente codex --aplicar"
afirma "surgiu: NAO diz editado" sem_editado

echo
echo "== 4. GLOSSARIO.md que SUMIU depois da geracao =="
D="$(nova_caixa sumiu)"; printf '# Glossario\n' > "$D/GLOSSARIO.md"
gera "$D"
rm -f "$D/GLOSSARIO.md"
conferir "$(w "$D/AGENTS.md")"
afirma "sumiu: exit 2" saiu 2
afirma "sumiu: diz que a ponte aponta para o glossario que nao existe mais" diz "não existe mais na raiz do alvo"
afirma "sumiu: traz o comando de regeracao" diz "node scripts/ponte.cjs --alvo . --agente codex --aplicar"
afirma "sumiu: NAO diz editado" sem_editado

echo
echo "== 5. edicao a mao de outra linha, com glossario presente =="
E="$(nova_caixa editado-com-glossario)"; printf '# Glossario\n' > "$E/GLOSSARIO.md"
gera "$E"
sed -i 's/## O que NAO vale/## TESTE MODIFICADO/' "$E/AGENTS.md"
grep -qF "TESTE MODIFICADO" "$E/AGENTS.md" || echo "   AVISO: sed nao alterou o arquivo do caso 5"
conferir "$(w "$E/AGENTS.md")"
afirma "editado com glossario: exit 2" saiu 2
afirma "editado com glossario: diz RECUSADO editado a mao" diz "RECUSADO — bloco foi editado à mão"

echo
echo "== 6. edicao a mao MAIS glossario surgido: o veredito e' a edicao =="
F="$(nova_caixa editado-e-surgiu)"
gera "$F"
printf '# Glossario\n' > "$F/GLOSSARIO.md"
sed -i 's/## O que NAO vale/## TESTE MODIFICADO/' "$F/AGENTS.md"
conferir "$(w "$F/AGENTS.md")"
afirma "editado + glossario surgido: exit 2" saiu 2
afirma "editado + glossario surgido: diz RECUSADO editado a mao" diz "RECUSADO — bloco foi editado à mão"
afirma "editado + glossario surgido: NAO esconde a edicao atras do glossario" nao_diz "a ponte não aponta"

echo
echo "== 7. pasta chamada GLOSSARIO.md nao conta =="
G="$(nova_caixa pasta)"; mkdir -p "$G/GLOSSARIO.md"
gera "$G"
conferir "$(w "$G/AGENTS.md")"
afirma "pasta GLOSSARIO.md: exit 0" saiu 0
afirma "pasta GLOSSARIO.md: imprime CONFERIDO" diz "CONFERIDO"

echo
echo "== 8. --json traz a situacao do glossario =="
conferir --json "$(w "$C/AGENTS.md")"
afirma "json surgiu: situacao glossario-surgiu" diz '"situacao": "glossario-surgiu"'
rm -f "$D/GLOSSARIO.md"
conferir --json "$(w "$D/AGENTS.md")"
afirma "json sumiu: situacao glossario-sumiu" diz '"situacao": "glossario-sumiu"'
gera "$D"; printf '# Glossario\n' > "$D/GLOSSARIO.md"
conferir --json "$(w "$D/AGENTS.md")"
afirma "json apos regerar sem glossario e criar o arquivo: situacao glossario-surgiu" diz '"situacao": "glossario-surgiu"'

echo
echo "== 9. stdin (-) sai 1 antes do corpo, com glossario no arquivo =="
SAIDA=$(node "$CONF" - < "$(w "$A/AGENTS.md")" 2>&1); GOT=$?
afirma "stdin: exit 1" saiu 1
afirma "stdin: recusa o arquivo - como nao sendo CLAUDE/AGENTS/GEMINI" diz "não é CLAUDE.md, AGENTS.md ou GEMINI.md"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
