#!/bin/bash
# Bateria do lib/contexto-sessao.cjs — o motor que monta o texto injetado em toda sessao.
# Uso: bash hooks/testa-contexto-sessao.sh
#
# O que esta bateria precisa provar, nesta ordem de importancia:
#   1. que o fallback DISPARA quando as regras nao carregam. O defeito que originou
#      este motor era silencioso: o hook antigo imprimia o cabecalho seguido de nada
#      e a sessao subia sem regra nenhuma. Protecao que nunca roda nao e protecao;
#   2. que ele NAO dispara no caso normal. Falso positivo aqui despeja um alarme
#      falso em TODA sessao boa, e alarme falso e desligado no primeiro dia;
#   3. que o resumo de "Avancos" mantem as entradas recentes E deixa ponteiro para
#      as omitidas — cortar em silencio e a mesma familia do defeito do item 1;
#   4. que o teto duro corta avisando.
#
# A ultima secao e MUTACAO: desliga o piso de tamanho na lib e exige que o teste do
# item 1 pare de pegar. Bateria que passa verde com a protecao removida esta testando
# outra coisa.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SRC/hooks/lib/contexto-sessao.cjs"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Driver: le os textos de env e imprime o contexto montado. Fica em arquivo (e nao
# em `node -e`) porque aspas de shell dentro de JS ja custaram uma rodada aqui.
cat > "$RAIZ_POSIX/driver.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.montarContexto({
  skillText: process.env.FIX_SKILL || '',
  focoText: process.env.FIX_FOCO || '',
  caminhoSkill: 'C:\\fake\\SKILL.md',
  root: 'C:\\fake',
}));
EOF

# Fixture de SKILL valido: precisa passar do piso de 500 chars.
REGRA_LONGA="$(printf 'Regra 1. Responder tudo, na ordem, e no fim do turno. %.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
SKILL_OK="# Skill
## As regras
$REGRA_LONGA
> incidente que deve sair da injecao: 2026-08-09, aconteceu X.
Regra 2. Escolha mais adicao vira as duas coisas.
## Comando
irrelevante"

SKILL_CURTO="# Skill
## As regras
Regra 1. Curta demais.
## Comando
x"

FOCO_MUITOS="# Foco

## Ativo

Foco de teste.

Avanços:
- 2026-08-01: primeira coisa feita.
- 2026-08-02: segunda coisa feita.
- 2026-08-03: terceira coisa feita.
- 2026-08-04: quarta coisa feita.
- 2026-08-05: quinta coisa feita.

## Fora de escopo
nada"

# roda o driver com fixtures e devolve a saida
montar() { # skill, foco, [lib]
  LIB_PATH="${3:-$LIB}" FIX_SKILL="$1" FIX_FOCO="$2" node "$RAIZ_POSIX/driver.cjs" 2>&1
}

checa() { # nome, modo(tem|nao_tem), padrao, saida
  local nome="$1" modo="$2" pad="$3" saida="$4"
  if echo "$saida" | grep -qF "$pad"; then achou=1; else achou=0; fi
  local esperado=1; [ "$modo" = "nao_tem" ] && esperado=0
  if [ "$achou" = "$esperado" ]; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome (modo=$modo, padrao='$pad')"
    echo "$saida" | sed 's/^/         /' | head -8
  fi
}

echo
echo "1. o fallback dispara quando as regras nao carregam"
S="$(montar '' '')"
checa "skill vazio aciona o alarme"        tem     "FALHA AO CARREGAR AS REGRAS" "$S"
checa "alarme manda avisar o Luis"         tem     "Diga isto ao Luís"           "$S"
checa "alarme cita a origem esperada"      tem     "fake"                        "$S"
S="$(montar "$SKILL_CURTO" '')"
checa "skill truncado aciona o alarme"     tem     "FALHA AO CARREGAR AS REGRAS" "$S"
checa "alarme diz quantos chars vieram"    tem     "piso:"                       "$S"

echo
echo "2. nao dispara no caso normal (falso positivo aqui e o pior defeito)"
S="$(montar "$SKILL_OK" "$FOCO_MUITOS")"
checa "skill valido nao aciona alarme"     nao_tem "FALHA AO CARREGAR AS REGRAS" "$S"
checa "as regras aparecem na injecao"      tem     "Responder tudo, na ordem"    "$S"
checa "citacao em blockquote sai fora"     nao_tem "incidente que deve sair"     "$S"
checa "conteudo pos-## Comando fica fora"  nao_tem "irrelevante"                 "$S"

echo
echo "3. resumo de Avancos: mantem os recentes e deixa ponteiro"
checa "mantem a entrada mais recente"      tem     "2026-08-05"                  "$S"
checa "mantem 3 residentes (08-03)"        tem     "2026-08-03"                  "$S"
checa "omite a mais antiga"                nao_tem "2026-08-01"                  "$S"
checa "ponteiro anuncia o corte"           tem     "entradas anteriores"         "$S"
checa "ponteiro manda ler o arquivo"       tem     "leia o arquivo"              "$S"
checa "resto do FOCO sobrevive ao corte"   tem     "Fora de escopo"              "$S"

echo
echo "4. foco ausente cai na mensagem propria, nao no alarme de regras"
S="$(montar "$SKILL_OK" '')"
checa "sem foco, sugere /foco"             tem     "sugira /foco"                "$S"
checa "sem foco NAO aciona alarme"         nao_tem "FALHA AO CARREGAR"           "$S"

echo
echo "5. MUTACAO — desligar o piso tem que quebrar o item 1"
cp "$LIB" "$RAIZ_POSIX/lib-mutada.cjs"
sed -i 's/REGRAS_MIN_CHARS: 500/REGRAS_MIN_CHARS: 0/' "$RAIZ_POSIX/lib-mutada.cjs"
S="$(montar "$SKILL_CURTO" '' "$RAIZ_POSIX/lib-mutada.cjs")"
if echo "$S" | grep -qF "FALHA AO CARREGAR AS REGRAS"; then
  falhou=$((falhou+1))
  echo "  FALHA mutacao nao teve efeito — o piso nao e o que faz o alarme disparar"
else
  ok=$((ok+1))
  echo "  ok    com o piso em 0 o alarme para de disparar (o piso e load-bearing)"
fi

echo
echo "6. ARQUIVOS REAIS — fixture que nao casa com o arquivo de verdade nao prova nada"
# Este bloco existe porque o fixture desta bateria ja passou verde escrevendo
# "Avancos:" sem cedilha, enquanto o FOCO.md real escreve "Avanços:". O marcador
# errado fazia o resumo nao disparar e o teste nao percebia. Regra 12: rode contra
# o artefato real.
cat > "$RAIZ_POSIX/driver-real.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const lib = require(process.env.LIB_PATH);
const raiz = process.env.REPO;
const rd = (p) => { try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; } };
const skill = rd(path.join(raiz, 'skills', 'rainforest-mind', 'SKILL.md'));
const foco = rd(path.join(raiz, 'FOCO.md'));
const saida = lib.montarContexto({ skillText: skill, focoText: foco, caminhoSkill: 'x', root: raiz });
const bruto = skill.length + foco.length;
process.stdout.write(saida);
process.stderr.write(`\nMEDIDO bruto=${bruto} injetado=${saida.length}\n`);
EOF
S="$(LIB_PATH="$LIB" REPO="$SRC" node "$RAIZ_POSIX/driver-real.cjs" 2>/dev/null)"
MED="$(LIB_PATH="$LIB" REPO="$SRC" node "$RAIZ_POSIX/driver-real.cjs" 2>&1 >/dev/null | grep MEDIDO)"
checa "SKILL.md real passa do piso"        nao_tem "FALHA AO CARREGAR"      "$S"
checa "FOCO.md real dispara o resumo"      tem     "omitidas desta injeção" "$S"
checa "avanco mais recente sobrevive"      tem     "2026-08-08"             "$S"
echo "  ---   $MED"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
