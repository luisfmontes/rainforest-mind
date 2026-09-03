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
LIB_FOLGA="$SRC/hooks/lib/folga.cjs"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
echo "(caixa de areia: $RAIZ)"

# Raiz gorda: sandbox com um FOCO.md de ~2.500 B para testes de mutacao
# (RAIZ_NEUTRA -> RAIZ_GORDA revela defeitos por conteudo, nao por medida de tamanho).
RAIZ_GORDA_POSIX="$(mktemp -d)"
node -e "const fs = require('fs'); fs.writeFileSync(process.argv[1]+'/FOCO.md','# Foco\n## Ativo\n\nConteudo para distinguir raiz com FOCO.md de raiz vazia.\n'.repeat(100))" "$RAIZ_GORDA_POSIX"
RAIZ_GORDA="$(cygpath -m "$RAIZ_GORDA_POSIX" 2>/dev/null || printf '%s' "$RAIZ_GORDA_POSIX")"

# Raiz neutra: sandbox vazia para testes que nao devem variar entre maquinas.
RAIZ_NEUTRA="$(mktemp -d)"

trap 'rm -rf "$RAIZ_POSIX" "$RAIZ_GORDA_POSIX" "$RAIZ_NEUTRA"' EXIT

# O IRMAO VAI JUNTO. Toda sabotagem deste arquivo faz `cp "$LIB" "$RAIZ_POSIX/..."`
# e roda a COPIA — e desde 2026-08-21 a lib faz `require('./raiz.cjs')`, que resolve
# ao lado do arquivo que a copia, nao ao lado do original. Sem esta linha o mutante
# morre com MODULE_NOT_FOUND antes de rodar uma linha de logica, e o pior e o que a
# bateria faz com isso: a secao de mutacao compara a saida do mutante com a esperada,
# ve que "diferiu" e credita `ok` — passa VERDE por nao ter conseguido executar nada,
# que e exatamente a familia de defeito que ela existe para pegar.
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_POSIX/raiz.cjs"

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
- 2026-08-01: primeira coisa feita, com texto do tamanho de um avanco real de dia
  produtivo, porque o teto do bloco e medido em BYTES e fixture de uma linha nao
  chega perto dele — passaria verde sem o resumo nunca disparar, que foi o defeito
  do parametro anterior (contagem de entradas com item de tamanho variavel).
- 2026-08-02: segunda coisa feita, com o mesmo peso da anterior para que o corte
  caia num lugar previsivel e o teste possa afirmar exatamente quais entradas
  sobrevivem ao teto e quais viram ponteiro, sem depender de sorte de tamanho.
- 2026-08-03: terceira coisa feita, mesmo peso, e esta e a mais antiga que ainda
  cabe nos novecentos bytes do teto — a asserção abaixo depende disso e quebra de
  proposito se o teto mudar sem o fixture acompanhar, que e o comportamento certo
  para um numero que e politica e nao detalhe de implementacao.
- 2026-08-04: quarta coisa feita, mesmo peso das anteriores, entrando na conta do
  teto como qualquer outra entrada datada do bloco de avancos deste fixture, sem
  tratamento especial de nenhum tipo por ser a penultima da lista.
- 2026-08-05: quinta coisa feita, a mais recente, que precisa sobreviver em
  qualquer cenario porque e dela que sai a linha de ultimo avanco datado, usada
  pela regra 3 para ver foco parado ha 7+ dias, e por isso o resumo garante ao
  menos uma entrada mesmo quando ela sozinha ja passa do teto.

## Fora de escopo
conteudo-fora-de-escopo"

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
checa "alarme manda avisar o usuario"         tem     "Diga isto ao usuario"           "$S"
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
# Secao nao-residente sai da injecao, mas SAI NOMEADA: o nome no ponteiro e o que
# separa omissao recuperavel de omissao silenciosa. As duas checagens andam juntas
# de proposito — so a primeira passaria com o corte mudo que originou tudo isto.
checa "secao nao-residente sai do texto"   nao_tem "conteudo-fora-de-escopo"     "$S"
checa "ponteiro nomeia a secao omitida"    tem     "Fora de escopo"              "$S"

# O teto e em BYTES desde 2026-08-10. Era contagem, calibrada com entradas de ~110
# tokens; entradas de 1,5 KB fizeram "3 entradas" custar 2.271 B sem que o
# parametro mudasse de valor. Estas provas sao sobre a UNIDADE, nao sobre o numero.
cat > "$RAIZ_POSIX/driver-avancos.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.resumirAvancos(process.env.FIX_FOCO));
EOF
avancos() { LIB_PATH="${2:-$LIB}" FIX_FOCO="$1" node "$RAIZ_POSIX/driver-avancos.cjs" 2>&1; }

# Uma entrada gigante sozinha: o teto nao pode zerar o bloco. Sem entrada nenhuma,
# some a data que a regra 3 usa para ver foco parado, e o bloco fica so ponteiro.
GIGANTE="- 2026-08-10: $(printf 'palavra %.0s' $(seq 1 300))"
S="$(avancos "# Foco

## Ativo

Avanços:
$GIGANTE")"
checa "entrada unica gigante sobrevive"    tem     "2026-08-10"                  "$S"

# Data com sufixo antes dos dois-pontos e como o FOCO.md real escreve o segundo
# avanco do dia. O padrao antigo exigia ':' colado na data e simplesmente nao via
# a linha — a injecao subia sem "Último avanço datado".
S="$(montar "$SKILL_OK" "# Foco

## Ativo

Avanços:
- 2026-08-07 (tarde): entrada com sufixo entre a data e os dois-pontos.")"
checa "data com sufixo vira ultimo avanco" tem     "Último avanço datado: 2026-08-07" "$S"

# A linha de historico escrita pelo `scripts/foco.cjs` quando ele move entradas para
# o AVANCOS.md: ela e RESIDENTE e nao conta como omitida. Sem isso o ponteiro desta
# funcao — "elas continuam no FOCO.md" — passa a mentir para as entradas rotacionadas,
# e a sessao nem fica sabendo que existe outro arquivo.
GRANDE1="- 2026-08-08: $(printf 'palavra %.0s' $(seq 1 120))"
GRANDE2="- 2026-08-09: $(printf 'palavra %.0s' $(seq 1 120))"
GRANDE3="- 2026-08-10: $(printf 'palavra %.0s' $(seq 1 120))"
S="$(avancos "# Foco

## Ativo

Avanços:
- (histórico: 11 avanços de 2026-07-20 a 2026-08-07 em AVANCOS.md.)
$GRANDE1
$GRANDE2
$GRANDE3")"
checa "ponteiro de historico e residente"    tem     "AVANCOS.md"                  "$S"
checa "historico nao conta como omitida"     tem     "2 entradas anteriores"       "$S"
checa "o avanco mais recente fica"           tem     "2026-08-10"                  "$S"

cp "$LIB" "$RAIZ_POSIX/lib-sem-teto-avancos.cjs"
sed -i 's/AVANCOS_MAX_BYTES: [0-9]*/AVANCOS_MAX_BYTES: 99999999/' "$RAIZ_POSIX/lib-sem-teto-avancos.cjs"
S="$(montar "$SKILL_OK" "$FOCO_MUITOS" "$RAIZ_POSIX/lib-sem-teto-avancos.cjs")"
if echo "$S" | grep -qF "2026-08-01"; then
  ok=$((ok+1)); echo "  ok    com o teto em 99MB o resumo para de cortar (o teto e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e o teto em bytes que faz o resumo cortar"
fi

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
const foco = rd(path.join(process.env.DADOS, 'FOCO.md'));
const saida = lib.montarContexto({ skillText: skill, focoText: foco, caminhoSkill: 'x', root: raiz });
const bruto = skill.length + foco.length;
process.stdout.write(saida);
process.stderr.write(`\nMEDIDO bruto=${bruto} injetado=${saida.length}\n`);
EOF
# SKILL.md e CODIGO e continua vindo do repo — e determinista, todo mundo tem o
# mesmo. FOCO.md e DADO, e ate 2026-08-17 esta bateria lia o **FOCO.md de verdade**
# do usuario. Duas consequencias, as duas medidas:
#
#   - no CI (Issue #16) nao existe `~/.rainforest`, entao os dois `checa` abaixo
#     ficavam vermelhos por ausencia de dado, nao por regressao;
#   - e na propria maquina do dono ela era INSTAVEL: `ok: 169 falhou: 0` as ~14h
#     e dois vermelhos as ~18h do MESMO dia, porque o FOCO.md mudou no meio.
#
# Teste que muda de resultado sem ninguem mexer no codigo e teste que se aprende a
# ignorar. O que estes casos existem para provar e o MECANISMO — que um FOCO.md
# com varias secoes dispara o resumo, e que o avanco mais recente sobrevive a
# compressao. Isso se prova com uma fixture que tem a FORMA do arquivo real, e a
# forma esta reproduzida abaixo: `## Ativo` com linhas de avanco datadas, mais as
# outras secoes que a injecao precisa omitir para ter o que resumir.
#
# O que se perde de proposito: esta bateria nao vigia mais o FOCO.md do usuario.
# Vigiar o dado vivo dele e trabalho de `scripts/saude.cjs`, que roda contra a
# maquina — nao de bateria, que roda em qualquer maquina e tem de dar o mesmo.
DADOS_REAIS="$RAIZ_POSIX/dados-fixture"
mkdir -p "$DADOS_REAIS"
cat > "$DADOS_REAIS/FOCO.md" <<'FOCOEOF'
# Foco

## Ativo
Último avanço datado: 2026-08-12.

**Trabalho de fixture — V1 funcionando** `[trabalho]` — declarado 2026-08-01.
Projeto: pasta de fixture, usada so por esta bateria.
Pastas: C:/fixture/projeto
Ociosidade máxima: 15 min.
Prioridade 00 na palavra do gestor; prazo final 2026-09-30.

- 2026-08-05: **primeiro avanço da fixture**, escrito com prosa suficiente para
  ocupar espaço e obrigar a injeção a decidir o que corta, que é exatamente o
  comportamento sob teste aqui.
- 2026-08-09: **segundo avanço da fixture**, também com prosa, pelo mesmo motivo
  do anterior — sem volume não há compressão a observar.
- 2026-08-12: **avanço mais recente da fixture**, e é esta data que os casos
  abaixo exigem que sobreviva à compressão.

## Não especificado ainda
- o que entra no mínimo viável da fixture, a detalhar.

## Fora de escopo
- tudo que não for a fixture.

## Compromissos com prazo
- 2026-09-30: entrega da fixture.

## Contexto de calendário
- semana de fixture, sem feriado.

## Frentes
- frente única, de fixture.

## Concluídos
- nada — é fixture.
FOCOEOF
S="$(LIB_PATH="$LIB" REPO="$SRC" DADOS="$DADOS_REAIS" node "$RAIZ_POSIX/driver-real.cjs" 2>/dev/null)"
MED="$(LIB_PATH="$LIB" REPO="$SRC" DADOS="$DADOS_REAIS" node "$RAIZ_POSIX/driver-real.cjs" 2>&1 >/dev/null | grep MEDIDO)"
checa "SKILL.md real passa do piso"          nao_tem "FALHA AO CARREGAR"      "$S"
checa "FOCO.md de fixture dispara o resumo"  tem     "omitidas desta injeção" "$S"
# A data continua saindo do arquivo, nao de uma constante repetida aqui — a versao
# de 2026-08-08 fixava a data no proprio `checa` e ficava vermelha sozinha no
# primeiro avanco novo. Agora o arquivo e a fixture logo acima, entao a data e
# estavel; ler dela em vez de repetir o literal mantem os dois lados em sincronia
# quando alguem editar a fixture.
ULTIMO_AVANCO="$(awk '/^## /{dentro=($0=="## Ativo")} dentro' "$DADOS_REAIS/FOCO.md" \
  | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9-]{10}' | sort | tail -1)"
checa "avanco mais recente sobrevive"        tem     "Último avanço datado: $ULTIMO_AVANCO" "$S"
echo "  ---   $MED"

echo
echo "7. ORCAMENTO DE ENTREGA — o teto em bytes, que e o que faz a regra chegar"
# Este bloco e o teste que faltava em 2026-08-10. Os itens 1 a 6 verificam o
# CONTEUDO montado; nenhum verificava o TAMANHO — e o defeito era de tamanho.
# O hook emitia 32 KB, o harness entregava 2,2 KB e saia com exit 0, e a bateria
# inteira passava verde enquanto as regras 4 a 17 nao chegavam a sessao nenhuma.
#
# Roda o HOOK de verdade, nao o motor: o que quebrou foi o formato de saida
# (texto cru em vez de JSON) e o tamanho final com dependencias e sessoes juntas.
# Testar so o motor deixaria os dois de fora (regra 12: valide o artefato real).
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
RFM_ROOT="$RAIZ_NEUTRA" node "$SRC/hooks/foco-session-start.cjs" > "$RAIZ_POSIX/saida-hook.json" 2>/dev/null
EXIT_HOOK=$?

cat > "$RAIZ_POSIX/checa-hook.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
let j;
try { j = JSON.parse(fs.readFileSync(process.env.SAIDA, 'utf8')); }
catch { console.log('json_invalido 0 0 0'); process.exit(0); }
const c = (j.hookSpecificOutput || {}).additionalContext;
if (typeof c !== 'string') { console.log('sem_contexto 0 0 0'); process.exit(0); }
const regras = (c.match(/\*\*\d+\./g) || []).length;
const travou = c.includes('ACIMA DO ORÇAMENTO') ? 'travou' : 'coube';
fs.writeFileSync(process.env.CONTEXTO, c);
console.log(`ok ${Buffer.byteLength(c, 'utf8')} ${lib.TETOS.ORCAMENTO_BYTES} ${regras} ${travou}`);
EOF
LEITURA="$(LIB_PATH="$LIB" SAIDA="$RAIZ_POSIX/saida-hook.json" CONTEXTO="$RAIZ_POSIX/contexto.txt" node "$RAIZ_POSIX/checa-hook.cjs")"
FORMATO="$(echo "$LEITURA" | cut -d' ' -f1)"
BYTES="$(echo "$LEITURA" | cut -d' ' -f2)"
TETO="$(echo "$LEITURA" | cut -d' ' -f3)"
NREGRAS="$(echo "$LEITURA" | cut -d' ' -f4)"
TRAVOU="$(echo "$LEITURA" | cut -d' ' -f5)"
CONTEXTO_COMPLETO="$(cat "$RAIZ_POSIX/contexto.txt" 2>/dev/null)"

if [ "$EXIT_HOOK" = "0" ]; then ok=$((ok+1)); echo "  ok    o hook real roda com exit 0"
else falhou=$((falhou+1)); echo "  FALHA o hook real saiu com exit $EXIT_HOOK"; fi

# Formato: JSON com additionalContext. Texto cru E a entrega e passa do limite do
# harness; JSON faz o harness ler so o campo de dentro. Era o defeito de origem.
if [ "$FORMATO" = "ok" ]; then ok=$((ok+1)); echo "  ok    emite JSON com hookSpecificOutput.additionalContext"
else falhou=$((falhou+1)); echo "  FALHA saida do hook nao e o JSON esperado ($FORMATO)"; fi

if [ -n "$BYTES" ] && [ "$BYTES" -le "$TETO" ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    payload real cabe no orcamento ($BYTES B <= $TETO B)"
else
  falhou=$((falhou+1)); echo "  FALHA payload real estoura o orcamento ($BYTES B > $TETO B)"
  echo "         reduza os nucleos no SKILL.md (texto antes de <!-- detalhe -->)"
fi

# "cabe no teto" sozinho passaria verde com a trava tendo cortado o payload ate o
# teto — o numero bate justamente porque foi cortado. Sem esta checagem, o teste de
# tamanho mediria o proprio corte em vez do que ele deveria impedir.
if [ "$TRAVOU" = "coube" ]; then
  ok=$((ok+1)); echo "  ok    coube sem a trava precisar cortar"
else
  falhou=$((falhou+1)); echo "  FALHA a trava teve de cortar o payload real ($TRAVOU)"
fi

if [ -n "$NREGRAS" ] && [ "$NREGRAS" -ge 17 ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    as 17 regras cabem no orcamento (chegaram $NREGRAS)"
else
  falhou=$((falhou+1)); echo "  FALHA so $NREGRAS regras no payload — alguma nao esta valendo em sessao nenhuma"
fi

# Asserção de conteudo: RAIZ_NEUTRA (vazia) produz sempre "nenhum foco declarado".
# A mutação trocando para RAIZ_GORDA (com FOCO.md) revela o defeito (conteudo muda).
if echo "$CONTEXTO_COMPLETO" | grep -q "(nenhum foco declarado"; then
  ok=$((ok+1)); echo "  ok    raiz neutra (vazia) nao injeta foco (nenhum foco declarado)"
else
  falhou=$((falhou+1)); echo "  FALHA raiz neutra deveria produzir 'nenhum foco declarado' mas nao produziu"
fi

# CATRACA DOS NUCLEOS. As duas checagens acima nao dao retorno a quem EDITA regra,
# e foi assim que 2026-08-12 aconteceu: um nucleo ganhou ~60 B e nada reclamou. Nao
# reclama porque as regras entram ANTES do foco -- `sobra = ORCAMENTO - fixo`, e o
# foco leva o que restar. Nucleo que engorda nao estoura o orcamento: come o espaco
# do foco, calado, e o sintoma aparece numa sessao futura com o FOCO.md mais pobre.
# E o teste de cima roda com a FIXTURE do repo (~6,3 KB), nao com dados reais
# (7.924 B medidos na maquina do autor no mesmo dia, 76 B de folga) -- ele passaria
# verde ate o dia em que o usuario perdesse conteudo de abertura.
cat > "$RAIZ_POSIX/checa-nucleos.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
const skill = fs.readFileSync(process.env.SKILL, 'utf8');
const nucleos = lib.extrairNucleo(lib.filtrarRegras(skill));
console.log(`${Buffer.byteLength(nucleos, 'utf8')} ${lib.TETOS.NUCLEOS_MAX_BYTES}`);
EOF
LEITURA_N="$(LIB_PATH="$LIB" SKILL="$SRC/skills/rainforest-mind/SKILL.md" node "$RAIZ_POSIX/checa-nucleos.cjs")"
BYTES_N="$(echo "$LEITURA_N" | cut -d' ' -f1)"
TETO_N="$(echo "$LEITURA_N" | cut -d' ' -f2)"

# Avaliar folga com a biblioteca, decisao D4/D5.
cat > "$RAIZ_POSIX/avalia-folga.cjs" <<'EOF'
const folga = require(process.env.FOLGA_LIB);
const valor = parseInt(process.argv[2], 10);
const teto = parseInt(process.argv[3], 10);
const nome = process.argv[4] || 'teto';
const alternativas = process.argv.slice(5);
const resultado = folga.avaliarFolga(valor, teto, { nome, alternativas });
console.log(`${resultado.estado}|${resultado.folga}|${resultado.limiar}|${resultado.mensagem}`);
EOF
AVALIACAO="$(FOLGA_LIB="$LIB_FOLGA" node "$RAIZ_POSIX/avalia-folga.cjs" "$BYTES_N" "$TETO_N" "nucleos" "tirar do FOCO" "subir o agregado" "adicionar regra noutro nucleo")"
ESTADO_N="$(echo "$AVALIACAO" | cut -d'|' -f1)"
FOLGA_N="$(echo "$AVALIACAO" | cut -d'|' -f2)"
LIMIAR_N="$(echo "$AVALIACAO" | cut -d'|' -f3)"
MSG_N="$(echo "$AVALIACAO" | cut -d'|' -f4-)"

if [ "$ESTADO_N" = "ok" ] || [ "$ESTADO_N" = "aviso" ]; then
  ok=$((ok+1)); echo "  ok    os nucleos cabem na catraca ($BYTES_N B <= $TETO_N B, folga $FOLGA_N B)"
  if [ "$ESTADO_N" = "aviso" ]; then
    echo "         $MSG_N"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA os nucleos passaram da catraca ($BYTES_N B > $TETO_N B)"
  echo "         $MSG_N"
fi

# A catraca so vale se ela for o que reprova. Com uma regra gorda a mais, o mesmo
# calculo tem de acusar -- senao o numero acima esta passando por folga, nao por medida.
cat > "$RAIZ_POSIX/checa-nucleos-mutado.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
const skill = fs.readFileSync(process.env.SKILL, 'utf8');
const gorda = '\n\n**18. Regra inventada pelo teste.** ' + 'x'.repeat(700) + '\n';
const mutado = skill.replace('## Comando', gorda + '\n## Comando');
const n = lib.extrairNucleo(lib.filtrarRegras(mutado));
console.log(Buffer.byteLength(n, 'utf8') > lib.TETOS.NUCLEOS_MAX_BYTES ? 'acusou' : 'passou');
EOF
MUT_N="$(LIB_PATH="$LIB" SKILL="$SRC/skills/rainforest-mind/SKILL.md" node "$RAIZ_POSIX/checa-nucleos-mutado.cjs")"
if [ "$MUT_N" = "acusou" ]; then
  ok=$((ok+1)); echo "  ok    com uma regra gorda a mais a catraca acusa (o teto e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA regra gorda a mais e a catraca nao acusou — o teto nao esta medindo nada"
fi

# CRLF NAO PODE CUSTAR BYTE. No Windows o `core.autocrlf=true` (padrao) reescreve
# o SKILL.md no checkout. Em 2026-08-13 o arquivo voltou de um merge com 827 CRLF
# e os nucleos pularam de 5592 para 5648 B -- 56 bytes em toda sessao, sem uma
# linha de regra ter mudado, e a catraca reprovou uma branch que nao tocou em
# regra nenhuma. O defeito de verdade nao era o teto: era o MESMO commit custar
# bytes diferentes em maquinas diferentes, calado.
cat > "$RAIZ_POSIX/checa-crlf.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
const lf = fs.readFileSync(process.env.SKILL, 'utf8').replace(/\r\n/g, '\n');
const crlf = lf.replace(/\n/g, '\r\n');
const bLf = Buffer.byteLength(lib.extrairNucleo(lib.filtrarRegras(lf)), 'utf8');
const bCrlf = Buffer.byteLength(lib.extrairNucleo(lib.filtrarRegras(crlf)), 'utf8');
console.log(`${bLf} ${bCrlf}`);
EOF
LEITURA_C="$(LIB_PATH="$LIB" SKILL="$SRC/skills/rainforest-mind/SKILL.md" node "$RAIZ_POSIX/checa-crlf.cjs")"
B_LF="$(echo "$LEITURA_C" | cut -d' ' -f1)"
B_CRLF="$(echo "$LEITURA_C" | cut -d' ' -f2)"
if [ -n "$B_LF" ] && [ "$B_LF" = "$B_CRLF" ]; then
  ok=$((ok+1)); echo "  ok    o mesmo texto em CRLF custa os mesmos $B_LF B (fim de linha nao entra na conta)"
else
  falhou=$((falhou+1)); echo "  FALHA CRLF custa diferente de LF ($B_CRLF B vs $B_LF B) — o mesmo commit pesa"
  echo "         diferente em maquinas diferentes, e o teto vira loteria de checkout."
fi

echo
echo "7.5. CATRACA DE REFERENCES E SKILL.md — custo de CONSULTAR uma regra (D9)"
# O criterio da issue #73 e "consultar a elaboracao de uma regra custa menos de
# 3k tokens, MEDIDO". Sem teste esse numero vale no dia da entrega e apodrece
# depois -- foi assim que o "~16,8k tokens" do description do SKILL.md virou um
# numero que nao deriva de nada e nao e verificado por nada. Esta catraca mede
# dois artefatos reais contra dois tetos: o MAIOR arquivo de references/ (o que
# se paga para consultar UMA regra) e o SKILL.md inteiro (o que se paga para
# decidir QUAL regra abrir).
cat > "$RAIZ_POSIX/checa-references.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const lib = require(process.env.LIB_PATH);
const dir = process.env.REFERENCES_DIR;
let maiorArq = '(nenhum)';
let maiorBytes = 0;
for (const f of fs.readdirSync(dir)) {
  if (!f.endsWith('.md')) continue;
  const b = fs.statSync(path.join(dir, f)).size;
  if (b > maiorBytes) { maiorBytes = b; maiorArq = f; }
}
const skillBytes = fs.statSync(process.env.SKILL).size;
console.log(`${maiorArq} ${maiorBytes} ${lib.TETOS.REFERENCE_MAX_BYTES} ${skillBytes} ${lib.TETOS.SKILL_MAX_BYTES}`);
EOF
REFERENCES_REAIS="$SRC/skills/rainforest-mind/references"
SKILL_REAL="$SRC/skills/rainforest-mind/SKILL.md"
LEITURA_R="$(LIB_PATH="$LIB" REFERENCES_DIR="$REFERENCES_REAIS" SKILL="$SKILL_REAL" node "$RAIZ_POSIX/checa-references.cjs")"
MAIOR_ARQ="$(echo "$LEITURA_R" | cut -d' ' -f1)"
MAIOR_BYTES="$(echo "$LEITURA_R" | cut -d' ' -f2)"
TETO_REF="$(echo "$LEITURA_R" | cut -d' ' -f3)"
SKILL_BYTES="$(echo "$LEITURA_R" | cut -d' ' -f4)"
TETO_SKILL="$(echo "$LEITURA_R" | cut -d' ' -f5)"

if [ -n "$MAIOR_BYTES" ] && [ "$MAIOR_BYTES" -le "$TETO_REF" ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    maior reference ($MAIOR_ARQ, $MAIOR_BYTES B) cabe na catraca (<= $TETO_REF B, folga $((TETO_REF-MAIOR_BYTES)) B)"
else
  falhou=$((falhou+1)); echo "  FALHA $MAIOR_ARQ passou da catraca de reference ($MAIOR_BYTES B > $TETO_REF B)"
  echo "         consultar essa regra deixou de custar menos de 3k tokens (D9/issue #73)."
  echo "         encurte $MAIOR_ARQ, ou suba REFERENCE_MAX_BYTES de proposito, com a conta escrita."
fi

if [ -n "$SKILL_BYTES" ] && [ "$SKILL_BYTES" -le "$TETO_SKILL" ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    SKILL.md cabe na catraca ($SKILL_BYTES B <= $TETO_SKILL B, folga $((TETO_SKILL-SKILL_BYTES)) B)"
else
  falhou=$((falhou+1)); echo "  FALHA SKILL.md passou da catraca ($SKILL_BYTES B > $TETO_SKILL B)"
  echo "         o indice ficou pesado demais para decidir qual references/regra-NN.md abrir."
fi

# MUTACAO -- a catraca de reference so vale se ela for o que reprova. Roda numa
# COPIA sandbox dentro do worktree (nunca no arquivo rastreado: o teste normal
# acima ja usa o artefato real, regra 12; a mutacao segue o mesmo padrao das
# outras deste arquivo -- copia, nunca o original). Engordar regra-12.md em
# 3.000 B tem que fazer a MESMA medicao acusar, citando o arquivo pelo nome.
REFS_MUTADO="$RAIZ_POSIX/references-mutado"
rm -rf "$REFS_MUTADO"
cp -r "$REFERENCES_REAIS" "$REFS_MUTADO"
node -e "require('fs').appendFileSync(process.argv[1], 'x'.repeat(3000))" "$REFS_MUTADO/regra-12.md"
LEITURA_RM="$(LIB_PATH="$LIB" REFERENCES_DIR="$REFS_MUTADO" SKILL="$SKILL_REAL" node "$RAIZ_POSIX/checa-references.cjs")"
MAIOR_ARQ_M="$(echo "$LEITURA_RM" | cut -d' ' -f1)"
MAIOR_BYTES_M="$(echo "$LEITURA_RM" | cut -d' ' -f2)"
echo "  (saida do mutante: $LEITURA_RM — regra-12.md com +3.000 B)"
if [ "$MAIOR_ARQ_M" = "regra-12.md" ] && [ -n "$MAIOR_BYTES_M" ] && [ "$MAIOR_BYTES_M" -gt "$TETO_REF" ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    regra-12.md engordada em 3.000 B faz a catraca acusar, citando o arquivo (o teto e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA engordar regra-12.md nao fez a catraca acusar — o teto nao esta medindo nada"
fi
rm -rf "$REFS_MUTADO"

echo
echo "7.6. AS QUATRO INVARIANTES DA QUEBRA (D4/D5/D6/D7) — contra o SKILL.md REAL"
# A tarefa 5 do plano trava quatro coisas que a quebra em references/ prometeu nao
# alterar. As tres primeiras medem o SKILL.md e o parser reais (nao fixture); a
# quarta (cabecalho cita references/) e o item 0 deste arquivo, reescrito la
# embaixo na secao 8 -- listada aqui so para nao se perder no meio da leitura.

# D6 -- seta unica: o nucleo emitido nao pode conter "seta dupla" (↳ ↳). O defeito
# historico era extrairNucleo() acrescentar UMA seta a um nucleo que ja terminava
# com ↳ literal no arquivo -- a regra 15 chegava como "↳ ↳" em toda sessao.
cat > "$RAIZ_POSIX/checa-invariantes.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
const skill = fs.readFileSync(process.env.SKILL, 'utf8');
const nucleo = lib.extrairNucleo(lib.filtrarRegras(skill));
const setasDuplas = (nucleo.match(/↳\s↳/g) || []).length;
console.log(`${Buffer.byteLength(nucleo, 'utf8')} ${setasDuplas}`);
EOF
LEITURA_INV="$(LIB_PATH="$LIB" SKILL="$SKILL_REAL" node "$RAIZ_POSIX/checa-invariantes.cjs")"
NUCLEO_BYTES_REAL="$(echo "$LEITURA_INV" | cut -d' ' -f1)"
SETAS_DUPLAS_REAL="$(echo "$LEITURA_INV" | cut -d' ' -f2)"

if [ "$SETAS_DUPLAS_REAL" = "0" ]; then
  ok=$((ok+1)); echo "  ok    D6: nucleo emitido nao contem seta dupla (↳ ↳) — 0 ocorrencias"
else
  falhou=$((falhou+1)); echo "  FALHA D6: nucleo emitido contem $SETAS_DUPLAS_REAL ocorrencia(s) de seta dupla (↳ ↳)"
  echo "         a regra 15 voltou a terminar com ↳ literal no SKILL.md — extrairNucleo acrescenta a segunda."
fi

# D7 -- nucleo inalterado: a quebra em references/ prometeu nao devolver folga
# nenhuma ao orcamento de nucleo. O numero e o contrato (issue #79), e esta
# asercao existe para acusar se algum dia alguem, de boa fe, "aproveitar" bytes
# que a quebra teria liberado.
#
# 2026-09-01, fluxo 9 (portaria): 5.589 -> 5.597 B. A regra 10 passou a afirmar a
# admissao por manifesto + estagio ativo (tarefa 7 do plano), o que e conteudo
# NOVO, nao byte reaproveitado. A primeira redacao custava +280 B e estourou a
# catraca (5.869 > 5.600) -- a entrada aqui e a segunda, que compensou o texto
# novo encolhendo o resto da regra 10: a lista dos sete agentes saiu do nucleo
# (continua em references/regra-10.md, e agora o manifesto e que e a lista viva)
# e o caminho `.rainforest/agentes.json` desceu para a elaboracao -- este ultimo
# tambem porque `scripts/testa-ponte.sh` proibe o literal `.rainforest` no
# arquivo que a ponte gera para terceiros.
#
# A folga sobre NUCLEOS_MAX_BYTES (5.600) caiu de 11 para 3 B. Quem for mexer
# aqui de novo: nao ha espaco: ou encolhe outra regra, ou sobe a catraca sabendo
# que `tetoFoco = ORCAMENTO - fixo` e cada byte de nucleo sai do FOCO.md do
# usuario.
# 2026-09-02: 5597 -> 5595 — a regra 12 ganhou "exit ≠ 0 nunca é sucesso" (fluxo 7, T6) e cedeu 2 B no proprio texto.
NUCLEO_ESPERADO=5595
if [ "$NUCLEO_BYTES_REAL" = "$NUCLEO_ESPERADO" ]; then
  ok=$((ok+1)); echo "  ok    D7: nucleo emitido mede exatamente $NUCLEO_BYTES_REAL B (contrato: $NUCLEO_ESPERADO B)"
else
  falhou=$((falhou+1)); echo "  FALHA D7: nucleo emitido mede $NUCLEO_BYTES_REAL B, o contrato exige exatamente $NUCLEO_ESPERADO B"
  echo "         a quebra em references/ nao pode mudar nem 1 byte do que ja era injetado antes dela."
fi

# D5 -- literais estruturais. '## As regras' e o mais importante: verificado por
# mutacao no design, troca-lo zera o payload de nucleo e a sessao sobe com
# "FALHA AO CARREGAR AS REGRAS". '## Comando /foco' e o ponto de injecao do teste
# de mutacao da catraca (secao 12 deste arquivo). 'Ultima revisao:' e lida por
# hooks/foco-session-start.cjs:167 num `if` sem `else` -- some dali e o aviso
# bimestral desliga em silencio.
SKILL_REAL_TXT="$(cat "$SKILL_REAL")"
checa "D5: SKILL.md real contem o literal '## As regras'"        tem "## As regras"       "$SKILL_REAL_TXT"
checa "D5: SKILL.md real contem o literal '## Comando /foco'"    tem "## Comando /foco"   "$SKILL_REAL_TXT"
checa "D5: SKILL.md real contem o literal 'Ultima revisao:'"     tem "Última revisão:"    "$SKILL_REAL_TXT"

echo
echo "7.7. FORMATO DO H1 EM references/ — titulo sintetizado, nao prosa truncada com ** orfao"
# Cada regra-NN.md recebeu um H1 sintetizado a partir da regra que ele elabora. O
# defeito real (achado por revisor humano-equivalente, nao pego pelas 233 assercoes
# que ja existiam nesta bateria): em 15 dos 17, o H1 saiu truncado no meio da prosa
# do corpo, com um ** orfao emendado logo apos o primeiro ponto final --
#   # Regra 1 — Responder tudo, na ordem — e no FIM do turno.** N pedidos → N respostas
# em vez de um titulo curto de verdade. E' exatamente o texto que um agente le ao
# consultar uma regra pelo cabecalho (D4/D9) -- titulo quebrado, 17 lugares para
# desconfiar.
#
# O ** orfao e' o sinal mais confiavel de truncagem, entao a assercao ASTERISCOS
# abaixo e' a principal. O bullet "titulo nao termina em ponto final" do contrato
# original foi implementado como PONTOORFAO, restrito a essa mesma assinatura
# (ponto-final colado a ** orfao) -- nao a qualquer titulo que termine em ponto.
#
# HISTORICO DO ACHADO: na base em que esta secao nasceu, regra-17.md terminava em
# ponto por design ("...janela parada e' o alerta.") e era um dos dois titulos sãos
# -- um check literal de "nunca termina em ponto" teria acusado um titulo correto.
# Isso foi reportado como achado de premissa, e a rodada que consertou os 15 titulos
# truncados (commit 9a62232, branch design/skills-finas-com-references) padronizou
# regra-17.md removendo o ponto por causa dele: hoje TODOS os 17 titulos terminam
# sem ponto. PONTOORFAO continua restrito (nao virou "nunca termina em ponto")
# porque este worktree segue isolado da base 9a62232 (regra 11: subagente nao
# funde a propria branch) -- apertar o check aqui acusaria regra-17.md so' porque
# ESTE worktree ainda carrega o titulo antigo, um falso positivo local, nao um
# defeito do artefato. Depois que as duas branches integrarem, "nunca termina em
# ponto" vira o check mais simples e correto — mas isso e' trabalho de quem integra,
# nao desta asserção isolada.
cat > "$RAIZ_POSIX/checa-titulos.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const dir = process.env.REFERENCES_DIR;
const arquivos = fs.readdirSync(dir).filter(f => /^regra-\d+(-acervo)?\.md$/.test(f)).sort();
const linhas = [];
const acusados = new Set();
for (const f of arquivos) {
  const numeroArquivo = parseInt(f.match(/^regra-(\d+)(-acervo)?\.md$/)[1], 10);
  const conteudo = fs.readFileSync(path.join(dir, f), 'utf8');
  const primeiraLinha = conteudo.split(/\r?\n/, 1)[0];
  const m = primeiraLinha.match(/^# Regra (\d+)(?: — (.+))?$/);
  if (!m) {
    acusados.add(f);
    linhas.push(`FORMATO ${f}: primeira linha nao casa com "# Regra <n> — <titulo>" (ou "# Regra <n>" sem titulo) — linha: ${primeiraLinha}`);
    continue;
  }
  const numeroTitulo = parseInt(m[1], 10);
  const titulo = m[2]; // undefined quando o arquivo nao tem titulo (ex.: regra-04.md)
  if (numeroTitulo !== numeroArquivo) {
    acusados.add(f);
    linhas.push(`NUMERO ${f}: titulo abre com "Regra ${numeroTitulo}" mas o arquivo e' o da regra ${numeroArquivo} — linha: ${primeiraLinha}`);
  }
  if (titulo !== undefined) {
    if (titulo.includes('**')) {
      acusados.add(f);
      linhas.push(`ASTERISCOS ${f}: titulo contem ** (cabecalho truncado, com o inicio da prosa do corpo colado) — linha: ${primeiraLinha}`);
    }
    if (/\.\*\*/.test(titulo)) {
      acusados.add(f);
      linhas.push(`PONTOORFAO ${f}: titulo tem ponto final seguido de ** orfao (assinatura da truncagem) — linha: ${primeiraLinha}`);
    }
  }
}
console.log(`TOTAL=${arquivos.length} ACUSADOS=${acusados.size} ARQUIVOS=${[...acusados].join(',')}`);
for (const l of linhas) console.log(l);
EOF
SAIDA_TITULOS="$(REFERENCES_DIR="$REFERENCES_REAIS" node "$RAIZ_POSIX/checa-titulos.cjs")"
RESUMO_TITULOS="$(echo "$SAIDA_TITULOS" | head -1)"
echo "  (leitura: $RESUMO_TITULOS)"

LINHAS_FORMATO="$(echo "$SAIDA_TITULOS" | grep '^FORMATO ' || true)"
if [ -z "$LINHAS_FORMATO" ]; then
  ok=$((ok+1)); echo "  ok    todo H1 de references/ casa com \"# Regra <n> — <titulo>\" ou \"# Regra <n>\" sem titulo"
else
  falhou=$((falhou+1)); echo "  FALHA H1 fora do formato esperado em references/:"
  echo "$LINHAS_FORMATO" | sed 's/^/         /'
fi

LINHAS_ASTERISCOS="$(echo "$SAIDA_TITULOS" | grep '^ASTERISCOS ' || true)"
QTD_ASTERISCOS="$(echo "$SAIDA_TITULOS" | grep -c '^ASTERISCOS ' || true)"
if [ -z "$LINHAS_ASTERISCOS" ]; then
  ok=$((ok+1)); echo "  ok    nenhum titulo de references/ contem ** (0 cabecalhos truncados)"
else
  falhou=$((falhou+1)); echo "  FALHA $QTD_ASTERISCOS titulo(s) de references/ contem ** — cabecalho truncado com prosa do corpo colada:"
  echo "$LINHAS_ASTERISCOS" | sed 's/^/         /'
fi

LINHAS_PONTOORFAO="$(echo "$SAIDA_TITULOS" | grep '^PONTOORFAO ' || true)"
if [ -z "$LINHAS_PONTOORFAO" ]; then
  ok=$((ok+1)); echo "  ok    nenhum titulo de references/ termina em ponto final colado a ** orfao"
else
  falhou=$((falhou+1)); echo "  FALHA titulo(s) com ponto final + ** orfao (assinatura da truncagem):"
  echo "$LINHAS_PONTOORFAO" | sed 's/^/         /'
fi

LINHAS_NUMERO="$(echo "$SAIDA_TITULOS" | grep '^NUMERO ' || true)"
if [ -z "$LINHAS_NUMERO" ]; then
  ok=$((ok+1)); echo "  ok    o numero do titulo bate com o numero do nome do arquivo, em todo references/"
else
  falhou=$((falhou+1)); echo "  FALHA numero do titulo nao bate com o do nome do arquivo:"
  echo "$LINHAS_NUMERO" | sed 's/^/         /'
fi
# MUTACAO desta assercao: secao 17.1, SABOTAGEM 11 (corrompe o titulo de regra-17.md,
# hoje um dos dois sãos, numa copia — checa-titulos.cjs e $REFERENCES_REAIS ja existem
# aqui em diante).

echo
echo "8. NUCLEO E DETALHE — a elaboracao fica fora, e a regra cortada se anuncia"
SKILL_NUCLEO="# Skill
## As regras

**1. Regra de teste.** Nucleo que precisa chegar em toda sessao, com texto
suficiente para passar do piso de quinhentos caracteres exigido pelo motor, o que
obriga esta frase a se estender bem alem do que seria natural para um fixture.
Note que o piso e medido DEPOIS da extracao do nucleo: um SKILL.md cujos nucleos
somados nao passem de quinhentos caracteres aciona o alarme de falha, e e por isso
que este fixture precisa ser longo apesar de ter uma regra so com detalhe.
<!-- detalhe -->
ELABORACAO-QUE-NAO-DEVE-CHEGAR: incidente longo, comandos exatos, historia.

**2. Outra regra.** Esta nao tem marca de detalhe e entra inteira.
## Comando
x"
S="$(montar "$SKILL_NUCLEO" '')"
checa "nucleo da regra chega"              tem     "Nucleo que precisa chegar"      "$S"
checa "elaboracao NAO chega"               nao_tem "ELABORACAO-QUE-NAO-DEVE-CHEGAR" "$S"
checa "regra cortada ganha a seta"         tem     "↳"                              "$S"
checa "D4: cabecalho manda ler o arquivo da regra"   tem     "regra-<n>.md"         "$S"
checa "D4: cabecalho NAO manda carregar a skill inteira" nao_tem "Skill(rainforest-mind)" "$S"
checa "regra sem marca entra inteira"      tem     "entra inteira"                  "$S"

echo
echo "9. RADAR MULTI-JANELA — uma linha por pasta, e o bloco tem teto"
# Este bloco e o que estourou a injecao em 2026-08-10: 21 janelas vivas em 7
# pastas, 1.373 B de linhas, nove delas da MESMA pasta. E o unico pedaco do
# payload que cresce com o uso da maquina e nao com texto que alguem escreveu —
# ninguem revisa quantas janelas abriu no dia, entao o teto tem de ser do codigo.
cat > "$RAIZ_POSIX/driver-sessoes.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const entradas = JSON.parse(process.env.FIX_SESSOES);
const bloco = lib.resumirSessoes(entradas, '15');
process.stdout.write(bloco + `\nBYTES=${Buffer.byteLength(bloco, 'utf8')}\n`);
EOF
sessoes() { LIB_PATH="${2:-$LIB}" FIX_SESSOES="$1" node "$RAIZ_POSIX/driver-sessoes.cjs" 2>&1; }

# Nove janelas da mesma pasta respondem a mesma pergunta da regra 17 nove vezes.
REPETIDAS='[{"cwd":"C:\\Projetos\\rfm","trabalhando":false,"minutos":300},
            {"cwd":"C:\\Projetos\\rfm","trabalhando":false,"minutos":40},
            {"cwd":"C:\\Projetos\\rfm","trabalhando":false,"minutos":355},
            {"cwd":"C:\\Projetos\\outro","trabalhando":true,"minutos":2}]'
S="$(sessoes "$REPETIDAS")"
checa "uma linha por pasta"                tem     "[3 janelas nesta pasta"      "$S"
checa "estado e o da janela mais recente"  tem     "esperando o usuario há 40 min"  "$S"
checa "a janela fria some da lista"        nao_tem "355 min"                     "$S"
checa "pasta com turno em curso aparece"   tem     "Claude trabalhando"          "$S"
checa "a ociosidade do foco vai junto"     tem     "Ociosidade máxima deste foco: 15 min" "$S"
checa "sem janela viva, bloco vazio"       nao_tem "radar multi-janela"          "$(sessoes '[]')"

# Muitas PASTAS distintas: a deducao nao resolve, e o teto precisa morder avisando.
MUITAS="$(node -e "
const p = Array.from({length: 20}, (_, i) => ({cwd: 'C:\\\\Projetos\\\\pasta-numero-' + i, trabalhando: false, minutos: i * 10}));
process.stdout.write(JSON.stringify(p));
")"
S="$(sessoes "$MUITAS")"
BYTES_SESSOES="$(echo "$S" | grep -oE 'BYTES=[0-9]+' | cut -d= -f2)"
TETO_SESSOES="$(LIB_PATH="$LIB" node -e "process.stdout.write(String(require(process.env.LIB_PATH).TETOS.SESSOES_MAX_BYTES))")"
if [ -n "$BYTES_SESSOES" ] && [ "$BYTES_SESSOES" -le $((TETO_SESSOES + 250)) ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    20 pastas cabem no teto do bloco ($BYTES_SESSOES B, teto de linhas $TETO_SESSOES B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco de sessoes sem teto efetivo ($BYTES_SESSOES B)"
fi
checa "corte de pasta se anuncia"          tem     "outra(s) pasta(s)" "$S"
checa "a pasta mais recente sobrevive"     tem     "pasta-numero-0"                "$S"
checa "a mais fria e a que sai"            nao_tem "pasta-numero-19 —"             "$S"

# Mutacao: com o teto em 99MB o corte para de acontecer. Sem isto, "cabe no teto"
# passaria verde num bloco que nunca chega perto do limite.
cp "$LIB" "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs"
# Precisa afrouxar OS DOIS cortes: o de bytes e o de quantidade de pastas. Com
# so um deles solto o corte continua acontecendo pelo outro, e a mutacao nao
# provaria nada sobre o teto que ela diz estar testando.
sed -i 's/SESSOES_MAX_BYTES: [0-9]*/SESSOES_MAX_BYTES: 99999999/' "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs"
sed -i 's/SESSOES_PASTAS_LISTADAS: [0-9]*/SESSOES_PASTAS_LISTADAS: 9999/' "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs"
S="$(sessoes "$MUITAS" "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs")"
if echo "$S" | grep -qF "outra(s) pasta(s)"; then
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e o teto que faz o bloco cortar"
else
  ok=$((ok+1)); echo "  ok    com o teto em 99MB o bloco para de cortar (o teto e load-bearing)"
fi

echo
echo "9a. SESSOES CO-LOCADAS — marcadas, em primeiro lugar, sobrevivem ao corte"
# Driver para testar resumirSessoes com cwdAtual (novo parâmetro P3)
cat > "$RAIZ_POSIX/driver-colocadas.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const entradas = JSON.parse(process.env.FIX_SESSOES);
const cwdAtual = process.env.CWD_ATUAL;
const bloco = lib.resumirSessoes(entradas, '15', undefined, cwdAtual);
process.stdout.write(bloco + `\nBYTES=${Buffer.byteLength(bloco, 'utf8')}\n`);
EOF
sessoes_colocadas() { LIB_PATH="${2:-$LIB}" FIX_SESSOES="$1" CWD_ATUAL="$3" node "$RAIZ_POSIX/driver-colocadas.cjs" 2>&1; }

# Teste 9a.1: sessão co-locada marcada e em primeiro lugar
COLOCADAS_TEST='[{"cwd":"C:\\Projetos\\outra","trabalhando":false,"minutos":100},
                 {"cwd":"C:\\Projetos\\rfm","trabalhando":false,"minutos":50},
                 {"cwd":"C:\\Projetos\\outra","trabalhando":false,"minutos":200}]'
S="$(sessoes_colocadas "$COLOCADAS_TEST" "$LIB" "C:\\Projetos\\rfm")"
checa "co-locada aparece com marca MESMO DIRETORIO"  tem     "MESMO DIRETORIO"              "$S"
checa "co-locada menciona efeito prático (git checkout)" tem "git checkout aqui move"     "$S"
PRIMEIRA_LINHA="$(echo "$S" | grep "Outras sess" -A 1 | tail -1)"
if echo "$PRIMEIRA_LINHA" | grep -q "MESMO DIRETORIO"; then
  ok=$((ok+1)); echo "  ok    co-locada vem PRIMEIRA na lista"
else
  falhou=$((falhou+1)); echo "  FALHA co-locada vem PRIMEIRA na lista"
  echo "         primeira linha: $PRIMEIRA_LINHA"
fi

# Teste 9a.2: compatibilidade — sem cwdAtual comportamento igual ao de hoje
S_SEM_CWD="$(sessoes "$COLOCADAS_TEST")"
S_COM_CWD_OUTRA="$(sessoes_colocadas "$COLOCADAS_TEST" "$LIB" "C:\\Projetos\\pasta-inexistente")"
checa "sem cwdAtual ou cwdAtual ausente, sem marca"   nao_tem "MESMO DIRETORIO"            "$S_SEM_CWD"
checa "cwdAtual que nao existe, sem marca"            nao_tem "MESMO DIRETORIO"            "$S_COM_CWD_OUTRA"

# Teste 9a.3: co-locada sobrevive ao corte com muitas pastas
MUITAS_COM_COLOCADA="$(node -e "
const p = Array.from({length: 15}, (_, i) => ({
  cwd: 'C:\\\\Projetos\\\\pasta-numero-' + i,
  trabalhando: false,
  minutos: i * 10 + 5
}));
p.push({cwd: 'C:\\\\Projetos\\\\rfm', trabalhando: true, minutos: 1});
process.stdout.write(JSON.stringify(p));
")"
S="$(sessoes_colocadas "$MUITAS_COM_COLOCADA" "$LIB" "C:\\Projetos\\rfm")"
PRIMEIRA_LINHA_COM_TUR="$(echo "$S" | grep "Outras sess" -A 1 | tail -1)"
if echo "$PRIMEIRA_LINHA_COM_TUR" | grep -q "MESMO DIRETORIO"; then
  ok=$((ok+1)); echo "  ok    co-locada com turno em curso aparece primeiro"
else
  falhou=$((falhou+1)); echo "  FALHA co-locada com turno em curso aparece primeiro"
fi
checa "co-locada sobrevive ao corte de teto"         tem     "MESMO DIRETORIO"              "$S"
# Mesmo que haja corte de outras pastas, a co-locada NAO aparece na msg de omissão
if echo "$S" | grep -q "C:\\\\Projetos\\\\rfm.*outra(s) pasta"; then
  falhou=$((falhou+1)); echo "  FALHA co-locada nao aparece na mensagem de omissao"
else
  ok=$((ok+1)); echo "  ok    co-locada nao aparece na mensagem de omissao de pastas"
fi

echo
echo "10. FOCO POR PRIORIDADE — o que a regra 3 mede sobrevive ao corte"
# O corte do foco era por POSICAO e parava no meio do "Criterio de pronto": os
# marcos e prazos nao chegavam a sessao nenhuma, enquanto a prosa do topo (que
# documenta o formato do arquivo) sobrevivia inteira. Medido em 2026-08-10 com o
# FOCO.md real: 855 B entregues, zero prazo dentro.
cat > "$RAIZ_POSIX/driver-foco.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.priorizarFoco(process.env.FIX_FOCO, Number(process.env.TETO)));
EOF
FOCO_BLOCOS="## Ativo
Último avanço datado: 2026-08-09.

Prosa que documenta o formato do arquivo e nao diz nada sobre entrega. PROSA-META.

**Foco de teste** \`[trabalho]\` — prazo final 2026-08-25.

Marcos (as datas sao as reunioes):
- **Entrega 1 — 14/08**: o marco que a regra 3 precisa ver.

Avanços:
- 2026-08-09: AVANCO-QUE-PODE-SAIR, texto longo o bastante para ser o primeiro a
  ser sacrificado quando o orcamento aperta, que e exatamente o ponto do bloco."
prioriza() { LIB_PATH="$LIB" FIX_FOCO="$1" TETO="$2" node "$RAIZ_POSIX/driver-foco.cjs" 2>&1; }

S="$(prioriza "$FOCO_BLOCOS" 400)"
checa "prazo do foco sobrevive"            tem     "prazo final 2026-08-25"     "$S"
checa "marco sobrevive ao corte"           tem     "Entrega 1 — 14/08"          "$S"
checa "avanco sai antes do marco"          nao_tem "AVANCO-QUE-PODE-SAIR"       "$S"
checa "prosa-meta sai antes de tudo"       nao_tem "PROSA-META"                 "$S"
checa "o que saiu e nomeado"               tem     "Fora desta injeção"         "$S"
checa "cabecalho da secao fica"            tem     "## Ativo"                   "$S"

# MARCO VENCE LISTA PEQUENA. Ate 2026-08-11 os dois empatavam em rank 2, e o
# preenchimento guloso levava a lista de 30 B e deixava os marcos de fora: com o
# FOCO.md real, o `- (nenhum alem do foco ativo)` entrava e a entrega de sexta
# nao. Empate resolvido pela ordem no arquivo nao e prioridade, e acaso.
# A lista pequena vem ANTES dos marcos no arquivo de proposito: empatados em rank,
# quem vem primeiro ganha, e e isso que o rank proprio tem de derrubar. O bloco de
# Avancos existe so para o teto morder — sem ele o texto inteiro cabe e a disputa
# nunca acontece.
FOCO_DISPUTA="## Ativo
Último avanço datado: 2026-08-09.

**Foco de teste** \`[trabalho]\` — prazo final 2026-08-25.

## Compromissos com prazo

- LISTA-PEQUENA-QUE-NAO-PODE-GANHAR

Marcos (as datas sao as reunioes):
- **Entrega 1 — 14/08**: o marco que a regra 3 precisa ver.

Avanços:
- 2026-08-09: bloco sacrificial, longo o bastante para o teto morder e a disputa
  entre o marco e a lista solta acontecer de verdade, em vez de tudo caber."
# SO O CORPO. O ponteiro de omissao NOMEIA quem saiu, entao procurar o nome no
# texto inteiro responde o contrario da verdade — custou duas rodadas de medicao
# errada nesta bateria antes de alguem olhar a saida de perto.
CORPO_D="$(prioriza "$FOCO_DISPUTA" 380 | sed '/Fora desta injeção/,$d')"
checa "marco vence a lista pequena"        tem     "Entrega 1 — 14/08"                "$CORPO_D"
checa "a lista pequena cede a vez"         nao_tem "LISTA-PEQUENA-QUE-NAO-PODE-GANHAR" "$CORPO_D"
# Ordem: prioridade decide QUEM fica, nao ONDE fica. Bloco reordenado na saida
# faria o foco chegar com os marcos antes da declaracao, que le errado.
POS_DECL="$(echo "$S" | grep -n "Foco de teste" | cut -d: -f1)"
POS_MARCO="$(echo "$S" | grep -n "Entrega 1" | cut -d: -f1)"
if [ -n "$POS_DECL" ] && [ -n "$POS_MARCO" ] && [ "$POS_DECL" -lt "$POS_MARCO" ]; then
  ok=$((ok+1)); echo "  ok    a ordem original do arquivo e preservada"
else
  falhou=$((falhou+1)); echo "  FALHA blocos sairam reordenados (decl=$POS_DECL marco=$POS_MARCO)"
fi
S="$(prioriza "$FOCO_BLOCOS" 99999)"
checa "cabendo tudo, nada e omitido"       nao_tem "Fora desta injeção"         "$S"

# Marcos: cumprido nao volta, porque prazo cumprido nao dispara a regra 3.
cat > "$RAIZ_POSIX/driver-marcos.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.resumirFoco(process.env.FIX_FOCO));
EOF
FOCO_MARCOS="## Ativo
**Foco** \`[trabalho]\`

Marcos (as datas sao as reunioes com o cliente):
- ✅ Marco cumprido — MARCO-CUMPRIDO.
- Marco proximo — PRIMEIRO-DE-PE.
- Marco seguinte — SEGUNDO-DE-PE.
- Marco distante — TERCEIRO-DE-PE.
- Marco final — QUARTO-DE-PE."
S="$(LIB_PATH="$LIB" FIX_FOCO="$FOCO_MARCOS" node "$RAIZ_POSIX/driver-marcos.cjs" 2>&1)"
checa "marco cumprido sai da injecao"      nao_tem "MARCO-CUMPRIDO"             "$S"
checa "os dois proximos ficam"             tem     "SEGUNDO-DE-PE"              "$S"
checa "o terceiro sai"                     nao_tem "TERCEIRO-DE-PE"             "$S"
checa "conta o que saiu, dos dois tipos"   tem     "2 marcos adiante e 1 já cumprido" "$S"
checa "regra de leitura da data fica"      tem     "datas sao as reunioes"      "$S"

echo
echo
echo "10.5 O CORTE QUE ANUNCIA O CORTE, e o cabecalho que nao fica sozinho"
# Tres defeitos medidos em 2026-08-13 (00h), quando outra sessao escreveu um
# compromisso novo no FOCO.md e o arquivo foi de 8.412 para 10.946 B.
#
# (a) O ponteiro das SECOES omitidas tinha rank 4 — o mais baixo — e era o PRIMEIRO
#     a cair. Ele e o unico aviso de que "Fora de escopo", "Frentes" e "Concluidos"
#     existem no arquivo: sem ele a sessao afirma escopo sem saber que ha uma secao
#     de escopo. Agora e residente, com reserva propria dentro do teto.
# (b) `## Compromissos com prazo` ficou na injecao SEM o conteudo dele, e cabecalho
#     sem conteudo le como "nao ha compromisso" — afirmacao, e falsa: havia um prazo
#     para o dia seguinte.
# (c) O preenchimento era guloso e a prosa-meta de 160 B (rank 9) ficou enquanto o
#     compromisso de 456 B (com data) saiu.
FOCO_PONTEIRO="## Ativo
Último avanço datado: 2026-08-12.

**Foco de teste** \`[trabalho]\` — prazo final 2026-08-25.

Marcos (as datas sao as reunioes):
- **Entrega 1 — 14/08**: marco de cronograma, com texto do tamanho de um marco real
  para que a disputa por espaco aconteca de verdade em vez de tudo caber e o teste
  nao medir nada — foi assim que a primeira versao deste bloco passou verde sem
  cortar uma linha.

## Compromissos com prazo

- **PRAZO-DE-AMANHA até 2026-08-13**: o compromisso com data, que e o mais proximo,
  tambem com o peso de um compromisso real escrito por quem tem uma entrega no dia
  seguinte e precisa que ela chegue na abertura da sessao, nao no ponteiro.

(Seções do FOCO.md omitidas desta injeção: Fora de escopo, Frentes, Concluídos. Elas continuam no arquivo — **leia o FOCO.md antes de afirmar**.)"
P="$(prioriza "$FOCO_PONTEIRO" 700)"
checa "(a) ponteiro das SECOES sobrevive ao teto"   tem     "omitidas desta injeção"  "$P"
checa "(c) compromisso COM DATA entra"              tem     "PRAZO-DE-AMANHA"         "$P"
checa "(c) e o marco de cronograma cede a vez"      nao_tem "Entrega 1 — 14/08"       "$P"
checa "o que saiu continua nomeado"                 tem     "Fora desta injeção"      "$P"

# (b) Secao INTEIRA fora => o cabecalho vai com ela. Teto minusculo para forcar.
Q="$(prioriza "$FOCO_PONTEIRO" 380)"
if printf '%s' "$Q" | grep -q "## Compromissos com prazo" && ! printf '%s' "$Q" | grep -q "PRAZO-DE-AMANHA"; then
  falhou=$((falhou+1)); echo "  FALHA (b) cabecalho ficou orfao — le como 'nao ha compromisso'"
else
  ok=$((ok+1)); echo "  ok    (b) cabecalho nao fica sem o conteudo da secao"
fi
# ...mas cabecalho cuja secao AINDA TEM conteudo mantido nao pode cair. Foi o erro
# da primeira versao desta regra: ela olhava o vizinho imediato (a prosa-meta) e
# derrubava `## Ativo`, levando junto a linha `Último avanço datado`.
checa "cabecalho com conteudo mantido FICA"         tem     "## Ativo"                "$P"
checa "e a linha do avanco datado vai com ele"      tem     "Último avanço datado"    "$P"

# MUTACAO: sem a promocao do compromisso datado, quem entra e o marco — e o prazo
# mais proximo sai. E o que prova que a regra nova governa o veredito.
# MUTACAO com fixture PROPRIO e blocos gordos, de proposito: reaproveitando o de
# cima a decisao ficava no fio da navalha (em 700 nem o marco cabia; em 900 os dois
# cabiam) e o teste mediria o APERTO em vez da PRIORIDADE. Com dois blocos de ~600 B
# e teto 800, exatamente um dos dois entra — a margem e de ~180 B, nao de ~20, e o
# unico fator que muda entre as duas rodadas e a presenca da data.
ENCHE="texto de enchimento para o bloco ter o peso de um bloco real, porque disputa
  por espaco medida com bloco de duas linhas nao mede disputa nenhuma — foi assim
  que a primeira versao deste teste passou verde sem cortar uma unica linha, e
  bateria que passa sem exercitar o mecanismo esta testando outra coisa."
FOCO_DISPUTA_DATA="## Ativo
Último avanço datado: 2026-08-12.

**Foco de teste** \`[trabalho]\` — prazo final 2026-08-25.

Marcos (as datas sao as reunioes):
- **Entrega 1 — 14/08**: marco de cronograma. $ENCHE

## Compromissos com prazo

- **PRAZO-DE-AMANHA até 2026-08-13**: CORPO-DO-COMPROMISSO. $ENCHE"
FOCO_SEM_DATA="${FOCO_DISPUTA_DATA/PRAZO-DE-AMANHA até 2026-08-13/PRAZO-SEM-DATA-NENHUMA}"
# Os dois blocos em disputa pesam ~380 B cada e a base ~130: com 800 (menos 120 de
# reserva do ponteiro) cabe a base + UM deles, nunca os dois. Conta feita, nao chutada.
COM="$(prioriza "$FOCO_DISPUTA_DATA" 800)"
SEM="$(prioriza "$FOCO_SEM_DATA" 800)"
checa "com data: o compromisso entra"               tem     "PRAZO-DE-AMANHA"      "$COM"
checa "com data: o marco cede"                      nao_tem "Entrega 1 — 14/08"    "$COM"
checa "sem data: o MARCO entra"                     tem     "Entrega 1 — 14/08"    "$SEM"
# A assercao olha o CORPO do bloco, nao o nome: o nome aparecer no ponteiro e o
# comportamento certo — foi o que esta checagem acusou como falha na primeira rodada,
# e quem estava errado era ela.
checa "sem data: o compromisso cede"                nao_tem "CORPO-DO-COMPROMISSO"  "$SEM"
checa "sem data: mas o ponteiro NOMEIA quem saiu"   tem     "PRAZO-SEM-DATA"        "$SEM"
checa "com data: o corpo do compromisso chega"      tem     "CORPO-DO-COMPROMISSO"  "$COM"

echo "11. SESSAO ENCERRADA — janela fechada some do radar"
# A raiz do estouro de 2026-08-10: o sessoes.json nao tinha nocao de sessao
# ENCERRADA. Media: 3 claude.exe rodando contra 18 entradas contadas como vivas.
# Sao dois mecanismos e os dois precisam de prova — o SessionEnd cobre o
# encerramento limpo, o PID cobre o que nao gera evento (X, crash, reboot).
MORTO=999999
S="$(LIB_PATH="$LIB" node -e "
const lib = require(process.env.LIB_PATH);
const agora = 1786e9;   // = 1786000000000, escrito assim porque 13 digitos casam a forma de telefone no gate de publicacao. Epoch real: timestamp negativo vira 0 no Math.max e o fixture mente
const state = {
  viva:      { cwd: 'C:/viva',   pid: process.pid, prompt_ts: agora - 1000 },
  morta:     { cwd: 'C:/morta',  pid: $MORTO,      prompt_ts: agora - 1000 },
  antiga:    { cwd: 'C:/antiga', pid: process.pid, prompt_ts: agora - 9 * 3600 * 1000 },
  sem_pid:   { cwd: 'C:/sempid',                   prompt_ts: agora - 1000 },
};
const vivas = lib.sessoesVivas(state, agora, 6 * 3600 * 1000).map(([id]) => id);
process.stdout.write(vivas.join(','));
" 2>&1)"
checa "sessao com processo vivo fica"      tem     "viva"                       "$S"
checa "sessao com processo morto sai"      nao_tem "morta"                      "$S"
checa "sessao velha continua saindo"       nao_tem "antiga"                     "$S"
checa "entrada antiga sem pid sobrevive"   tem     "sem_pid"                    "$S"

# Subagente em worktree abre sessao propria e NAO e janela paralela do usuario: a
# regra 17 mede o paralelismo dele, nao o meu rastro. Em 2026-08-11 uma sessao de
# worktree estava no radar, e o bloco de sessoes disputa orcamento com o foco —
# no mesmo dia a injecao chegou a 7992 B de 8000 e o prazo mais proximo ja tinha
# caido fora uma vez.
W="$(LIB_PATH="$LIB" node -e "
const lib = require(process.env.LIB_PATH);
const agora = 1786e9;   // = 1786000000000 (ver comentario acima)
const state = {
  janela_real: { cwd: 'C:/Projetos/algo',                              pid: process.pid, prompt_ts: agora - 1000 },
  wt_windows:  { cwd: 'C:\\\\Projetos\\\\algo\\\\.claude\\\\worktrees\\\\agent-x', pid: process.pid, prompt_ts: agora - 1000 },
  wt_posix:    { cwd: 'C:/Projetos/algo/.claude/worktrees/agent-y',    pid: process.pid, prompt_ts: agora - 1000 },
  quase:       { cwd: 'C:/Projetos/worktrees-de-verdade',              pid: process.pid, prompt_ts: agora - 1000 },
};
const vivas = lib.sessoesVivas(state, agora, 6 * 3600 * 1000).map(([id]) => id);
process.stdout.write(vivas.join(','));
" 2>&1)"
checa "janela de verdade continua no radar"   tem     "janela_real"  "$W"
checa "worktree de agente sai (caminho Windows)" nao_tem "wt_windows" "$W"
checa "worktree de agente sai (caminho POSIX)"   nao_tem "wt_posix"   "$W"
checa "pasta so parecida NAO e filtrada"      tem     "quase"        "$W"

# AJUSTE 2026-08-14: Filtro estreitado para exigir "agent-" como prefixo do
# segmento após "worktrees/". O usuario pode ter seus próprios worktrees (ex.:
# gestao-projetos-template) em .claude/worktrees/, e esses NÃO devem sair do radar.
# Apenas worktrees criadas pelo harness (agent-*) devem sair. O test e por limite
# de segmento, não substring.
X="$(LIB_PATH="$LIB" node -e "
const lib = require(process.env.LIB_PATH);
const agora = 1786e9;   // = 1786000000000 (ver comentario acima)
const state = {
  agent_simples: { cwd: 'C:/Projetos/rainforest-mind/.claude/worktrees/agent-a1b2c3', pid: process.pid, prompt_ts: agora - 1000 },
  agent_subpasta: { cwd: 'C:/Projetos/rainforest-mind/.claude/worktrees/agent-a1b2c3/templates/FIN', pid: process.pid, prompt_ts: agora - 1000 },
  usuario_simples: { cwd: 'C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template', pid: process.pid, prompt_ts: agora - 1000 },
  usuario_subpasta: { cwd: 'C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template/templates/FIN/Gestao_Projetos', pid: process.pid, prompt_ts: agora - 1000 },
  parecido: { cwd: 'C:/Projetos/rainforest-mind/.claude/worktrees/agente-do-cliente', pid: process.pid, prompt_ts: agora - 1000 },
};
const vivas = lib.sessoesVivas(state, agora, 6 * 3600 * 1000).map(([id]) => id);
process.stdout.write(vivas.join(','));
" 2>&1)"
checa "agent-abc simples sai (agent- requerido)"           nao_tem "agent_simples"  "$X"
checa "agent-abc em subpasta sai (agent- requerido)"       nao_tem "agent_subpasta" "$X"
checa "usuario gestao-projetos-template FICA no radar"     tem     "usuario_simples" "$X"
checa "usuario em subpasta de seu worktree FICA"           tem     "usuario_subpasta" "$X"
checa "agente-do-cliente (sem agent-) FICA no radar"       tem     "parecido"       "$X"

# O hook de verdade, com stdin de verdade: o evento "end" tem de apagar a linha.
HB_RAIZ="$RAIZ_POSIX/hb"
mkdir -p "$HB_RAIZ"
HB_WIN="$(cygpath -m "$HB_RAIZ" 2>/dev/null || printf '%s' "$HB_RAIZ")"
printf '{"session_id":"s1","cwd":"C:/a"}' | RFM_ROOT="$HB_WIN" node "$SRC/hooks/heartbeat.cjs" prompt
DEPOIS_PROMPT="$(cat "$HB_RAIZ/sessoes.json" 2>/dev/null)"
printf '{"session_id":"s1","cwd":"C:/a"}' | RFM_ROOT="$HB_WIN" node "$SRC/hooks/heartbeat.cjs" end
DEPOIS_END="$(cat "$HB_RAIZ/sessoes.json" 2>/dev/null)"
checa "heartbeat grava a sessao"           tem     '"s1"'                       "$DEPOIS_PROMPT"
checa "heartbeat NAO grava pid (poda por idade, nao por pid)" nao_tem '"pid"'  "$DEPOIS_PROMPT"
checa "SessionEnd apaga a sessao"          nao_tem '"s1"'                       "$DEPOIS_END"

# O hook so vale se estiver REGISTRADO — arquivo certo, evento nao declarado, e
# nada roda. E o mesmo defeito silencioso de sempre, uma camada acima.
checa "SessionEnd declarado no hooks.json" tem     '"SessionEnd"'               "$(cat "$SRC/hooks/hooks.json")"
checa "SessionEnd chama o heartbeat end"   tem     'heartbeat.cjs\" end'        "$(cat "$SRC/hooks/hooks.json")"

echo
echo "12. MUTACAO — desligar a trava de orcamento tem que quebrar o item 7"
# Mesma logica do item 5: se o teto virar infinito e o teste de tamanho continuar
# verde, ele nao esta medindo o teto. Fixture gigante para forcar o estouro.
REGRA_GIGANTE="$(printf 'Regra de teste com texto muito longo para estourar qualquer orcamento razoavel. %.0s' $(seq 1 200))"
SKILL_GIGANTE="# Skill
## As regras
$REGRA_GIGANTE
## Comando
x"
S="$(montar "$SKILL_GIGANTE" '')"
checa "payload gigante dispara a trava"    tem     "ACIMA DO ORÇAMENTO"          "$S"
# A posicao importa: o corte do harness leva o COMECO do texto, entao aviso que
# mora no rodape e mais uma regra que nunca chega. Esta checagem e a que impede
# de "consertar" a trava movendo o aviso para o fim.
PRIMEIRAS="$(echo "$S" | head -3)"
checa "aviso da trava vem no TOPO"         tem     "ACIMA DO ORÇAMENTO"          "$PRIMEIRAS"
checa "trava manda carregar a skill"       tem     "Skill(rainforest-mind)"      "$S"

cp "$LIB" "$RAIZ_POSIX/lib-sem-trava.cjs"
sed -i 's/ORCAMENTO_BYTES: [0-9]*/ORCAMENTO_BYTES: 99999999/' "$RAIZ_POSIX/lib-sem-trava.cjs"
S="$(montar "$SKILL_GIGANTE" '' "$RAIZ_POSIX/lib-sem-trava.cjs")"
if echo "$S" | grep -qF "ACIMA DO ORÇAMENTO"; then
  falhou=$((falhou+1))
  echo "  FALHA mutacao nao teve efeito — o teto nao e o que faz a trava disparar"
else
  ok=$((ok+1))
  echo "  ok    com o teto em 99MB a trava para de disparar (o teto e load-bearing)"
fi

echo
echo "13. RAIZ — cadeia de 4 niveis, projeto sobrescreve global"
# O defeito que esta secao existe para impedir: ate 2026-08-11 a raiz era
# `RFM_ROOT || 'C:\Projetos\rainforest-mind'` — caminho da maquina do usuario cravado
# no codigo, e RFM_ROOT nao esta definida nela. Funcionava para o usuario numero um
# e para mais ninguem.
RZP="$RAIZ_POSIX/raizes"
mkdir -p "$RZP/proj/.rainforest" "$RZP/lar/.rainforest" "$RZP/plugin" \
         "$RZP/vazio/.rainforest" "$RZP/declarada" "$RZP/soideias/.rainforest"
echo "# foco do projeto"  > "$RZP/proj/.rainforest/FOCO.md"
echo "# foco global"      > "$RZP/lar/.rainforest/FOCO.md"
echo "# foco do plugin"   > "$RZP/plugin/FOCO.md"
echo '{}'                 > "$RZP/soideias/.rainforest/ideias.jsonl"
# $RZP/vazio/.rainforest existe mas nao tem marcador — nao pode sequestrar o foco.

# O Node aqui e o do Windows: caminho POSIX do mktemp nao existe para ele. Converter
# uma vez, e passar so a forma Windows adiante. Custou uma rodada desta bateria.
RZ="$(cygpath -m "$RZP" 2>/dev/null || printf '%s' "$RZP")"

resolve() { # env_json, cwd, plugin -> "nivel escopo"
  RJ="$1" RC="$2" RP="$3" node -e '
    const { resolverRaiz } = require(process.env.LIB_RAIZ);
    const r = resolverRaiz({
      env: JSON.parse(process.env.RJ),
      cwd: process.env.RC,
      plugin: process.env.RP,
    });
    process.stdout.write(r.nivel + " " + (r.escopo || "-"));
  '
}
export LIB_RAIZ="$(cygpath -m "$SRC/hooks/lib/raiz.cjs" 2>/dev/null || printf '%s' "$SRC/hooks/lib/raiz.cjs")"

# Igualdade exata, nao substring: "plugin usuario" contem "usuario", e um teste que
# aceita substring aprovaria o nivel errado sem reclamar.
checa_igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}

checa_igual "RFM_ROOT vence tudo"             "RFM_ROOT usuario" \
  "$(resolve "{\"RFM_ROOT\":\"$RZ/declarada\"}" "$RZ/proj" "$RZ/plugin")"
checa_igual "sem RFM_ROOT, o projeto vence"   "projeto projeto" \
  "$(resolve "{}" "$RZ/proj" "$RZ/plugin")"
checa_igual "sem projeto, cai no global"      "global usuario" \
  "$(resolve "{\"USERPROFILE\":\"$RZ/lar\"}" "$RZ/semnada" "$RZ/plugin")"
checa_igual "sem global, cai no plugin"       "plugin usuario" \
  "$(resolve "{\"USERPROFILE\":\"$RZ/inexistente\"}" "$RZ/semnada" "$RZ/plugin")"
checa_igual "sem plugin, nao ha raiz"        "nenhum -" \
  "$(resolve "{\"USERPROFILE\":\"$RZ/inexistente\"}" "$RZ/semnada" "$RZ/semplugin")"
checa_igual "sem nada, devolve nenhum"        "nenhum -" \
  "$(resolve "{\"USERPROFILE\":\"$RZ/inexistente\"}" "$RZ/semnada" "$RZ/semplugin")"
# O marcador e o que separa "pasta de dados" de "pasta que alguem criou por engano".
checa_igual ".rainforest VAZIO nao sequestra" "plugin usuario" \
  "$(resolve "{\"USERPROFILE\":\"$RZ/inexistente\"}" "$RZ/vazio" "$RZ/plugin")"
# ideias.jsonl sozinho tambem marca — senao um projeto que so planta ideia nao e visto.
checa_igual "so ideias.jsonl ja marca a raiz" "projeto projeto" \
  "$(resolve "{}" "$RZ/soideias" "$RZ/plugin")"

# MUTACAO: sem a checagem de marcador, a pasta vazia passa a sequestrar o foco.
cp "$SRC/hooks/lib/raiz.cjs" "$RAIZ_POSIX/raiz-sem-marcador.cjs"
sed -i 's/return MARCADORES.some((m) => fs.existsSync(path.join(dir, m)));/return fs.existsSync(dir);/' "$RAIZ_POSIX/raiz-sem-marcador.cjs"
MUT="$(LIB_RAIZ="$(cygpath -m "$RAIZ_POSIX/raiz-sem-marcador.cjs" 2>/dev/null || printf '%s' "$RAIZ_POSIX/raiz-sem-marcador.cjs")" resolve "{\"USERPROFILE\":\"$RZ/inexistente\"}" "$RZ/vazio" "$RZ/plugin")"
if [ "$MUT" = "projeto projeto" ]; then
  ok=$((ok+1)); echo "  ok    sem o marcador a pasta vazia sequestra (o marcador e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao teve efeito — o marcador nao e o que decide"
fi

echo
echo "14. CODIGO vs DADOS — o hook de verdade, com a raiz de dados sem skills/"
# O defeito, cometido e pego em 2026-08-11: ao separar os dados do codigo, o hook
# passou a procurar o SKILL.md dentro da pasta de DADOS. A injecao caiu de 7.967 B
# para 3.047 B e o fallback disparou em TODA sessao — "esta sessao esta SEM o
# rainforest-mind". Este bloco roda o HOOK DE VERDADE (nao a lib) contra uma raiz
# de dados que so tem FOCO.md, que e exatamente o caso real depois da separacao.
DADOS="$RAIZ_POSIX/so-dados"
mkdir -p "$DADOS"
printf '# Foco

## Ativo

**Foco de teste** `[trabalho]` — prazo final 2026-12-31.
' > "$DADOS/FOCO.md"
H="$(RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")" node "$SRC/hooks/foco-session-start.cjs" 2>&1)"
checa "as regras carregam mesmo assim"     tem     "Responder tudo"              "$H"
checa "o fallback NAO dispara"             nao_tem "FALHA AO CARREGAR AS REGRAS" "$H"
checa "o foco vem da raiz de DADOS"        tem     "Foco de teste"               "$H"
# E a prova de que o caminho da skill aponta para o CODIGO, nao para os dados:
checa "a skill e apontada no plugin"       nao_tem "so-dados\\skills"        "$H"

echo
echo "15. RADAR CORTADO — o foco nao paga a conta das janelas abertas"
# Em 2026-08-11 o bloco de sessoes chegou a 691 B com 11 janelas em 8 pastas e
# empurrou os Marcos para fora da injecao: a entrega de sexta parou de chegar na
# abertura porque `repo-de-trabalho` aparecia tres vezes. A regra 17 pergunta "tem
# paralelo?" e "o foco esfriou?", e as duas se respondem com as pastas RECENTES.
cat > "$RAIZ_POSIX/driver-sessoes.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const ent = JSON.parse(process.env.FIX_SESSOES);
process.stdout.write(lib.resumirSessoes(ent, 15));
EOF
sess() { LIB_PATH="$LIB" FIX_SESSOES="$1" node "$RAIZ_POSIX/driver-sessoes.cjs" 2>&1; }

MUITAS='[{"cwd":"C:/a/pasta-quente","trabalhando":true,"minutos":1},
{"cwd":"C:/b/segunda","trabalhando":false,"minutos":5},
{"cwd":"C:/c/terceira","trabalhando":false,"minutos":9},
{"cwd":"C:/d/quarta-fria","trabalhando":false,"minutos":100},
{"cwd":"C:/e/quinta-fria","trabalhando":false,"minutos":200},
{"cwd":"C:/f/sexta-fria","trabalhando":false,"minutos":300}]'
R="$(sess "$MUITAS")"
checa "a pasta mais recente fica"          tem     "pasta-quente"   "$R"
checa "pasta fria sai por NOME"            nao_tem "sexta-fria"     "$R"
checa "o que saiu vira NUMERO"             tem     "outra(s) pasta" "$R"
# O teto governa a SOMA das linhas, ponteiro incluso. Sem a reserva o bloco saia
# com 351 B sob um teto de 300 — parametro que nao governa o numero que nomeia.
SOMA="$(printf '%s' "$R" | grep '^- ' | awk '{s+=length($0)+1} END {print s}')"
TETO="$(node -e "process.stdout.write(String(require('$SRC_WIN/hooks/lib/contexto-sessao.cjs').TETOS.SESSOES_MAX_BYTES))")"
if [ "$SOMA" -le "$TETO" ]; then
  ok=$((ok+1)); echo "  ok    a soma das linhas ($SOMA B) respeita o teto ($TETO B), ponteiro incluso"
else
  falhou=$((falhou+1)); echo "  FALHA soma $SOMA B passa do teto $TETO B — a reserva do ponteiro nao esta valendo"
fi
# Poucas pastas: nao pode aparecer ponteiro nenhum.
POUCAS='[{"cwd":"C:/a/unica","trabalhando":true,"minutos":2}]'
checa "com uma pasta so, sem ponteiro"     nao_tem "outra(s) pasta" "$(sess "$POUCAS")"

echo
echo "16. DEPENDENCIA SO SE CHECA QUANDO ALGUEM DECLAROU"
# Ate 2026-08-12 o hook sondava localhost:3005 por TCP em TODA sessao de TODA
# maquina e imprimia "bridge WhatsApp FORA" para quem nunca instalou bridge
# nenhuma — mais o claude-mem "ausente neste projeto". Abertura de usuario novo
# como propaganda de dependencia opcional, dentro de um orcamento em que 330 B
# sao uma regra inteira. A declaracao e a WHATSAPP_API_BASE_URL no ambiente.
#
# Roda o HOOK real: o que mudou foi o adaptador de I/O, e o motor (lib) nem sabe
# que existe sonda. Testar o motor aqui provaria a coisa errada.
CAIXA_DEP="$RAIZ_POSIX/dep"
mkdir -p "$CAIXA_DEP"
printf '{}\n' > "$CAIXA_DEP/settings.json"
ctx_hook() { # $@ = env extra; imprime o additionalContext
  env "$@" node "$SRC/hooks/foco-session-start.cjs" 2>/dev/null \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{process.stdout.write(JSON.parse(s).hookSpecificOutput.additionalContext)}catch{process.stdout.write('SEM_CONTEXTO')}})"
}
SEM_DEP="$(ctx_hook -u WHATSAPP_API_BASE_URL "RFM_ROOT=$RAIZ_NEUTRA" "CLAUDE_CONFIG_DIR=$CAIXA_DEP" "RFM_SETTINGS_PATH=$CAIXA_DEP/settings.json")"
checa "sem declaracao, nao ha bloco de dependencias" nao_tem "Dependências de ambiente" "$SEM_DEP"
checa "sem declaracao, nao fala de bridge"           nao_tem "bridge WhatsApp"           "$SEM_DEP"
checa "sem declaracao, nao fala de claude-mem"       nao_tem "claude-mem"                "$SEM_DEP"
checa "e as regras continuam chegando"               tem     "**17."                     "$SEM_DEP"

# Declarada e apontando para porta morta: o bloco volta, e volta dizendo FORA.
# Porta alta e improvavel de propósito — o teste nao pode depender do que a
# maquina tem de pe.
COM_DEP="$(ctx_hook "WHATSAPP_API_BASE_URL=http://127.0.0.1:59421" "RFM_ROOT=$RAIZ_NEUTRA" "CLAUDE_CONFIG_DIR=$CAIXA_DEP" "RFM_SETTINGS_PATH=$CAIXA_DEP/settings.json")"
checa "declarada, o bloco existe"                    tem     "Dependências de ambiente" "$COM_DEP"
checa "declarada e morta, diz FORA"                  tem     "bridge WhatsApp FORA"     "$COM_DEP"
checa "declarada, a URL declarada e a que aparece"   tem     "127.0.0.1:59421"          "$COM_DEP"
checa "claude-mem ausente segue fora do bloco"       nao_tem "claude-mem"               "$COM_DEP"

echo
echo "17. ISENCOES MECANIZADAS — pastasDoFoco, dentroDoExpediente, focoAtivoEmOutraJanela, computarVeredito"
# D6: "sem dado, cobra — e a ausencia se anuncia". As quatro funcoes deste bloco
# decidem se o radar de desvio de escopo pode ficar QUIETO nesta sessao. Erro
# aqui e o pior tipo: silencioso. Ninguem reclama de NAO ser cobrado por engano.

cat > "$RAIZ_POSIX/driver-pastas.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(JSON.stringify(lib.pastasDoFoco(process.env.FIX_FOCO)));
EOF
pastas() { LIB_PATH="${2:-$LIB}" FIX_FOCO="$1" node "$RAIZ_POSIX/driver-pastas.cjs" 2>&1; }

checa "pastasDoFoco: campo presente vira lista"    tem "[\"C:/a\",\"C:/b\"]" \
  "$(pastas 'Pastas: C:/a, C:/b

## Ativo
')"
checa "pastasDoFoco: campo ausente devolve []"     tem "[]" \
  "$(pastas '# Foco

## Ativo
')"
# ACHADO 7: esta e a forma EXATA que o `scripts/setup.cjs` semeia no FOCO_MODELO —
# "Pastas:" sozinho na linha, seguido de linha em branco. O regex antigo (`\s*`
# atravessa quebra de linha) casava ate o proximo texto nao-vazio e devolvia
# `["## Ativo"]`: pasta configurada de mentira, e a isencao 1 (D6/regra 17) nunca
# mais anuncia dado ausente para uma instalacao nova. Reproduzido antes do conserto:
# `pastasDoFoco("Pastas:\n\n## Ativo\n")` -> `["## Ativo"]`.
checa "pastasDoFoco: campo VAZIO (forma do FOCO_MODELO) devolve []" tem "[]" \
  "$(pastas 'Pastas:

## Ativo
')"
checa "pastasDoFoco: campo so com espacos devolve []" tem "[]" \
  "$(pastas "$(printf 'Pastas:   \n\n## Ativo\n')")"

# ISSUE #63 (2026-08-23): o FOCO.md real declara a segunda pasta numa linha de
# CONTINUACAO indentada, e o regex antigo (`^Pastas:[ \t]*(.*)$` numa unica
# linha) devolvia 1 de 2 em silencio — a isencao 1 nunca disparava para quem
# trabalhava o foco na segunda pasta. Forma exata da issue:
#   Pastas: C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template
#           C:/Microsiga/protheus-totvs-agro/tbc-licensing
checa "pastasDoFoco: continuacao indentada devolve as DUAS pastas" tem \
  '["C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template","C:/Microsiga/protheus-totvs-agro/tbc-licensing"]' \
  "$(pastas 'Pastas: C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template
        C:/Microsiga/protheus-totvs-agro/tbc-licensing

## Ativo
')"
# A continuacao PARA na primeira linha nao indentada — nao pode atravessar para
# o proximo heading e engolir "## Ativo" como se fosse uma terceira pasta.
checa "pastasDoFoco: continuacao nao atravessa para o heading seguinte" nao_tem "## Ativo" \
  "$(pastas 'Pastas: C:/a
        C:/b
## Ativo
')"
checa "pastasDoFoco: continuacao para no heading, as duas pastas de cima ficam" tem '["C:/a","C:/b"]' \
  "$(pastas 'Pastas: C:/a
        C:/b
## Ativo
')"
# O GUARDA DOCUMENTADO no comentario original continua valendo depois da
# reescrita: `pastasDoFoco("Pastas:\n\n## Ativo\n")` -> `[]`. Ja coberto acima
# ("campo VAZIO"), reafirmado aqui com o texto literal do comentario da lib.
checa "pastasDoFoco: guarda de linha em branco nao atravessa (forma do comentario da lib)" tem "[]" \
  "$(pastas "$(printf 'Pastas:\n\n## Ativo\n')")"

echo "17.2 MUTACAO — desligar a leitura de continuacao tem que voltar a perder a 2a pasta"
cp "$LIB" "$RAIZ_POSIX/lib-mut-pastas.cjs"
sed -i 's#if (/\^\[ \\t\]+\\S/.test(linhas\[i\])) partes.push(linhas\[i\]);#if (/^NUNCA-CASA-Issue63$/.test(linhas[i])) partes.push(linhas[i]);#' "$RAIZ_POSIX/lib-mut-pastas.cjs"
S_MUT_PASTAS="$(pastas 'Pastas: C:/Microsiga/protheus-totvs-agro/inovacao/.claude/worktrees/gestao-projetos-template
        C:/Microsiga/protheus-totvs-agro/tbc-licensing

## Ativo
' "$RAIZ_POSIX/lib-mut-pastas.cjs")"
if echo "$S_MUT_PASTAS" | grep -qF "tbc-licensing"; then
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — a leitura de continuacao nao e o que traz a 2a pasta (saida: $S_MUT_PASTAS)"
else
  ok=$((ok+1)); echo "  ok    mutacao expos a leitura de continuacao (sem ela a 2a pasta some em silencio, saida: $S_MUT_PASTAS)"
fi

cat > "$RAIZ_POSIX/driver-expediente.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const [y, m, d, h, mi] = process.env.FIX_QUANDO.split(',').map(Number);
const agora = new Date(y, m - 1, d, h, mi);
const config = JSON.parse(process.env.FIX_CONFIG);
process.stdout.write(JSON.stringify(lib.dentroDoExpediente(agora, config)));
EOF
expediente() { LIB_PATH="${3:-$LIB}" FIX_QUANDO="$1" FIX_CONFIG="$2" node "$RAIZ_POSIX/driver-expediente.cjs" 2>&1; }

# 2026-08-10 = segunda; 2026-08-15 = sabado (conferido com node antes de escrever
# o fixture — Date.getDay() e o que a funcao usa, e o dia da semana e o ponto
# inteiro deste caso).
CONFIG_EXPEDIENTE='{"expediente":{"dias":[1,2,3,4,5],"de":"08:00","ate":"18:00"}}'
checa "dentroDoExpediente: dentro da faixa (seg 10:00)"            tem "true"  "$(expediente '2026,8,10,10,0' "$CONFIG_EXPEDIENTE")"
checa "dentroDoExpediente: fora da faixa, mesmo dia (seg 20:00)"   tem "false" "$(expediente '2026,8,10,20,0' "$CONFIG_EXPEDIENTE")"
checa "dentroDoExpediente: dia fora dos dias (sab 10:00)"          tem "false" "$(expediente '2026,8,15,10,0' "$CONFIG_EXPEDIENTE")"
# A MAIS IMPORTANTE DO ARQUIVO: sem `expediente` no config, a resposta e NULL
# ("nao sei"), nunca false ("nao e expediente"). Colapsar os dois faz o D6
# nunca disparar o anuncio, e o radar cobra desvio de escopo sem avisar que o
# dado sumiu — silencio dentro de silencio.
checa "dentroDoExpediente: sem expediente no config devolve null (nao false)" tem "null" "$(expediente '2026,8,10,10,0' '{}')"

# Forma NOVA: `faixas` (N faixas), caso concreto que motivou a mudanca — seg-sex
# 8h-12h e 14h-18h, com o almoco (12h-14h) fora do expediente. Antes desta
# mudanca so existia uma faixa, e 13h em dia util virava expediente por engano.
CONFIG_EXPEDIENTE_FAIXAS='{"expediente":{"dias":[1,2,3,4,5],"faixas":[{"de":"08:00","ate":"12:00"},{"de":"14:00","ate":"18:00"}]}}'
checa "dentroDoExpediente: faixas - dentro da 1a faixa (seg 10:00)"        tem "true"  "$(expediente '2026,8,10,10,0' "$CONFIG_EXPEDIENTE_FAIXAS")"
checa "dentroDoExpediente: faixas - almoco fora das duas faixas (seg 13:00)" tem "false" "$(expediente '2026,8,10,13,0' "$CONFIG_EXPEDIENTE_FAIXAS")"
checa "dentroDoExpediente: faixas - dentro da 2a faixa (seg 15:00)"        tem "true"  "$(expediente '2026,8,10,15,0' "$CONFIG_EXPEDIENTE_FAIXAS")"
checa "dentroDoExpediente: faixas - fora de todas as faixas (seg 20:00)"  tem "false" "$(expediente '2026,8,10,20,0' "$CONFIG_EXPEDIENTE_FAIXAS")"
checa "dentroDoExpediente: faixas - dia fora dos dias (dom 10:00)"        tem "false" "$(expediente '2026,8,9,10,0' "$CONFIG_EXPEDIENTE_FAIXAS")"

cat > "$RAIZ_POSIX/driver-outra-janela.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const sessoes = JSON.parse(process.env.FIX_SESSOES);
const pastas = JSON.parse(process.env.FIX_PASTAS);
const oci = Number(process.env.FIX_OCI);
const agora = Number(process.env.FIX_AGORA);
process.stdout.write(String(lib.focoAtivoEmOutraJanela(sessoes, pastas, oci, agora)));
EOF
outra_janela() { LIB_PATH="${5:-$LIB}" FIX_SESSOES="$1" FIX_PASTAS="$2" FIX_OCI="$3" FIX_AGORA="$4" node "$RAIZ_POSIX/driver-outra-janela.cjs" 2>&1; }

AGORA_FIXO=1786000000000
checa "focoAtivoEmOutraJanela: sinal recente na pasta do foco isenta" tem "true" \
  "$(outra_janela "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"
checa "focoAtivoEmOutraJanela: mesma pasta, sinal alem da ociosidade nao isenta" tem "false" \
  "$(outra_janela "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_FIXO - 20*60*1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"
checa "focoAtivoEmOutraJanela: pasta diferente nao isenta"           tem "false" \
  "$(outra_janela "[{\"cwd\":\"C:/b\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"
# O CASO DE PREFIXO. `C:/abc` nao pode casar `C:/a` — erro aqui e invisivel,
# ninguem reclama de nao ser cobrado.
checa "focoAtivoEmOutraJanela: C:/abc nao casa C:/a por prefixo"     tem "false" \
  "$(outra_janela "[{\"cwd\":\"C:/abc\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"
# SUBPASTA: a sessao em uma SUBPASTA da pasta do foco deve isenta, porque o foco
# esta sendo trabalhado ali. Este era o defeito: a comparacao usava === exata e
# nunca casava subpasta. Realidade: usuario declara a raiz da pasta no FOCO.md
# mas a sessao roda em template/FIN/Gestao_Projetos dentro dela.
checa "focoAtivoEmOutraJanela: sessao em subpasta isenta"               tem "true" \
  "$(outra_janela "[{\"cwd\":\"C:/a/templates/FIN/Gestao_Projetos\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"
# Sinal humano e o prompt_ts (o usuario digitou algo), nao o stop_ts (Claude
# parou de responder). Sessao com prompt frio mas stop recente nao esta sendo
# TRABALHADA por ninguem — nao pode isentar.
checa "focoAtivoEmOutraJanela: prompt_ts frio e o que conta, nao stop_ts" tem "false" \
  "$(outra_janela "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_FIXO - 999999999)),\"stop_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO")"

# CAMINHO WINDOWS DE VERDADE: barra invertida + maiuscula, contra o foco
# declarado com barra normal e minuscula. A barra e construida com
# String.fromCharCode(92) e o valor e IMPRESSO antes de afirmar o resultado —
# o aviso do briefing e literal: aspas de shell e heredoc comem a barra
# invertida sem avisar, e isso ja rendeu medicao errada hoje.
cat > "$RAIZ_POSIX/driver-outra-janela-win.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const BS = String.fromCharCode(92);
const cwdSessao = 'C:' + BS + 'A';
process.stderr.write('CWD_CONSTRUIDO=' + JSON.stringify(cwdSessao) + '\n');
const agora = 1786e9;   // = 1786000000000 (ver comentario acima)
const r = lib.focoAtivoEmOutraJanela([{ cwd: cwdSessao, prompt_ts: agora - 1000 }], ['C:/a'], 15, agora);
process.stdout.write(String(r));
EOF
CONFIRMA_WIN="$RAIZ_POSIX/confirma-win.log"
SAIDA_WIN="$(LIB_PATH="$LIB" node "$RAIZ_POSIX/driver-outra-janela-win.cjs" 2>"$CONFIRMA_WIN")"
echo "  (confirmando o valor antes de afirmar: $(cat "$CONFIRMA_WIN"))"
checa "focoAtivoEmOutraJanela: C:\\A (barra invertida + maiuscula) normaliza e casa com C:/a" tem "true" "$SAIDA_WIN"

cat > "$RAIZ_POSIX/driver-veredito.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const foco = process.env.FIX_FOCO;
const sessoes = JSON.parse(process.env.FIX_SESSOES || '[]');
const config = JSON.parse(process.env.FIX_CONFIG || '{}');
const agora = Number(process.env.FIX_AGORA);
process.stdout.write(lib.computarVeredito(foco, sessoes, config, agora));
EOF
veredito() { LIB_PATH="${5:-$LIB}" FIX_FOCO="$1" FIX_SESSOES="$2" FIX_CONFIG="$3" FIX_AGORA="$4" node "$RAIZ_POSIX/driver-veredito.cjs" 2>&1; }

FOCO_SEM_PASTAS="# Foco

## Ativo

**Foco de teste** \`[trabalho]\`

Ociosidade máxima: 15 min"
FOCO_COM_PASTAS="Pastas: C:/a

## Ativo

**Foco de teste** \`[trabalho]\`

Ociosidade máxima: 15 min"
AGORA_SEG="$(node -e "process.stdout.write(String(new Date(2026,7,10,10,0).getTime()))")"
AGORA_SAB="$(node -e "process.stdout.write(String(new Date(2026,7,15,10,0).getTime()))")"

S="$(veredito "$FOCO_SEM_PASTAS" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
checa "computarVeredito: sem dado (Pastas ausente), anuncia"       tem     "Pastas: ausente no FOCO.md" "$S"
checa "computarVeredito: sem dado, NAO isenta (sem veredito junto)" nao_tem "NÃO cobrar desvio"          "$S"

S="$(veredito "$FOCO_COM_PASTAS" "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_SEG-1000))}]" "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
checa "computarVeredito: com dado e condicao satisfeita, emite veredito" tem     "NÃO cobrar desvio de escopo" "$S"
checa "computarVeredito: so isencao 1 ativa, sem anuncio da 2"         nao_tem "ausente"                     "$S"
checa "computarVeredito: isencao 1 dispara emite diretiva de prazo"    tem     "Apresentar avisos de prazo"   "$S"

# Teste (c): Pastas ausente → a diretiva de prazo NÃO sai
S="$(veredito "$FOCO_SEM_PASTAS" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
checa "computarVeredito: Pastas ausente, nao sai diretiva de prazo"    nao_tem "Apresentar avisos de prazo"   "$S"

# Dado completo, condicao nenhuma satisfeita: nem veredito nem anuncio. Os DOIS
# saem vazios juntos tambem conta como "nunca saem juntos" — string vazia nao
# afirma nada, nem cobranca nem isencao.
S="$(veredito "$FOCO_COM_PASTAS" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
if [ -z "$S" ]; then
  ok=$((ok+1)); echo "  ok    computarVeredito: dado completo sem condicao satisfeita devolve string vazia"
else
  falhou=$((falhou+1)); echo "  FALHA computarVeredito esperava vazio (dado completo, sem condicao), veio: '$S'"
fi
checa "computarVeredito: nada se aplica, nao sai diretiva de prazo"      nao_tem "Apresentar avisos de prazo" "$S"

# CASO REAL: Pastas: presente, expediente ausente, janela viva na pasta do foco
# → sai veredito (isenção 1 determinada) E anúncio (isenção 2 indeterminada)
S="$(veredito "$FOCO_COM_PASTAS" "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_SEG-1000))}]" '{}' "$AGORA_SEG")"
checa "caso real: Pastas presente, expediente ausente → veredito + anuncio" tem "NÃO cobrar desvio de escopo nesta sessão" "$S"
checa "caso real: veredito menciona foco ativo em outra janela" tem "foco ativo em outra janela" "$S"
checa "caso real: anuncio menciona expediente ausente" tem "expediente: ausente no config.json" "$S"

# ACHADO 1: Foco com boilerplate + foco ativo [pessoal], fora do expediente
# Não deve isentar por "tempo pessoal" porque o foco é [pessoal]
FOCO_BOILERPLATE_PESSOAL="# FOCO — Memória externa de trabalho

A cada virada de foco, troque o texto abaixo pelo novo. Tudo que não for
a seção Ativo continua vivo no arquivo mesmo que saia da injeção — e não é
decoração: o radar de escopo mede contra o foco ATIVO, que é a linha em
negrito. Todo foco declara a natureza — \`[trabalho]\` ou \`[pessoal]\` —, e as
regras usam isso para ajustar o que cobrar (regra 3).

Pastas: C:/projetos/meu-foco

## Ativo

**Projeto pessoal** \`[pessoal]\` — prazo final 2026-12-31.

Avanços:
- 2026-08-14: comecei a trabalhar nisso."
S="$(veredito "$FOCO_BOILERPLATE_PESSOAL" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SAB")"
checa "ACHADO 1: foco [pessoal] com boilerplate, fora do expediente" nao_tem "tempo pessoal" "$S"
checa "ACHADO 1: confirma que nao isenta (string vazia ou outra razao)" nao_tem "NÃO cobrar desvio" "$S"

# ACHADO 1 caso feliz: foco com boilerplate + foco ativo [trabalho], fora do expediente
# Deve isentar por "tempo pessoal"
FOCO_BOILERPLATE_TRABALHO="# FOCO — Memória externa de trabalho

A cada virada de foco, troque o texto abaixo pelo novo. Tudo que não for
a seção Ativo continua vivo no arquivo mesmo que saia da injeção — e não é
decoração: o radar de escopo mede contra o foco ATIVO, que é a linha em
negrito. Todo foco declara a natureza — \`[trabalho]\` ou \`[pessoal]\` —, e as
regras usam isso para ajustar o que cobrar (regra 3).

Pastas: C:/projetos/meu-foco

## Ativo

**Projeto trabalho** \`[trabalho]\` — prazo final 2026-12-31.

Ociosidade máxima: 15 min

Avanços:
- 2026-08-14: comecei a trabalhar nisso."
S="$(veredito "$FOCO_BOILERPLATE_TRABALHO" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SAB")"
checa "ACHADO 1 feliz: foco [trabalho] com boilerplate, fora do expediente" tem "tempo pessoal" "$S"
checa "ACHADO 1 feliz: emite veredito" tem "NÃO cobrar desvio" "$S"
checa "computarVeredito: so isencao 2 (tempo pessoal), sem diretiva de prazo" nao_tem "Apresentar avisos de prazo" "$S"

# ACHADO 2 / ACHADO 6: sem config.json, com Pastas: ausente
# Deve sair anúncio da isenção indeterminada
S="$(veredito "$FOCO_SEM_PASTAS" '[]' '{}' "$AGORA_SEG")"
checa "ACHADO 2: sem config.json, sem Pastas, sai anuncio" tem "ausente" "$S"

# ACHADO 6: o defeito corrigido (try ÚNICO engolindo a leitura do config.json
# junto com o cálculo do veredito) mora em hooks/foco-session-start.cjs, não no
# motor — a asserção do ACHADO 2 acima chama `computarVeredito` direto na lib e
# não prova nada sobre o chicote. Roda o HOOK real, mesma lógica da seção 14:
# testar o motor aqui provaria a coisa errada.
#
# A asserção antiga também era CEGA ao argumento `config`: passava com config
# vazio e com config completo, porque a fixture reaproveitada já era "Pastas:
# ausente" e QUALQUER anúncio (o da isenção 1) fazia "ausente" bater. Este bloco
# usa um FOCO com Pastas E Ociosidade preenchidas (isenção 1 totalmente
# determinada e QUIETA) para que o único jeito de "ausente"/"expediente" aparecer
# seja o config.json — discrimina de verdade.
CAIXA_A6="$RAIZ_POSIX/achado6"
CAIXA_A6_INVALIDO="$RAIZ_POSIX/achado6-invalido"
mkdir -p "$CAIXA_A6" "$CAIXA_A6_INVALIDO"
printf '%s\n' \
  '# Foco' \
  '' \
  'Pastas: C:/a' \
  '' \
  '## Ativo' \
  '' \
  '**Foco de teste** `[trabalho]` — prazo final 2026-12-31.' \
  '' \
  'Ociosidade máxima: 15 min' \
  > "$CAIXA_A6/FOCO.md"
cp "$CAIXA_A6/FOCO.md" "$CAIXA_A6_INVALIDO/FOCO.md"
printf 'isto nao e JSON valido {' > "$CAIXA_A6_INVALIDO/config.json"

A6_ROOT="$(cygpath -m "$CAIXA_A6" 2>/dev/null || printf '%s' "$CAIXA_A6")"
A6_ROOT_INVALIDO="$(cygpath -m "$CAIXA_A6_INVALIDO" 2>/dev/null || printf '%s' "$CAIXA_A6_INVALIDO")"

# config.json AUSENTE: o hook não pode quebrar, e tem que sair o anúncio de
# expediente (o único jeito da isenção 2 ficar indeterminada é o config faltar).
SAIDA_A6="$(RFM_ROOT="$A6_ROOT" CLAUDE_CONFIG_DIR="$CAIXA_DEP" RFM_SETTINGS_PATH="$CAIXA_DEP/settings.json" node "$SRC/hooks/foco-session-start.cjs" > "$RAIZ_POSIX/a6-saida.json" 2>"$RAIZ_POSIX/a6-stderr.log"; echo "EXIT=$?")"
EXIT_A6="${SAIDA_A6#EXIT=}"
CTX_A6="$(node -e "try{process.stdout.write(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).hookSpecificOutput.additionalContext)}catch{process.stdout.write('SEM_CONTEXTO')}" "$RAIZ_POSIX/a6-saida.json")"
if [ "$EXIT_A6" = "0" ]; then ok=$((ok+1)); echo "  ok    ACHADO 6: hook real com config.json ausente sai com exit 0"
else falhou=$((falhou+1)); echo "  FALHA ACHADO 6: hook real com config.json ausente saiu com exit $EXIT_A6"; fi
checa "ACHADO 6: config.json ausente, sai anuncio de expediente"  tem     "expediente: ausente no config.json" "$CTX_A6"
checa "ACHADO 6: config.json ausente, isencao 1 fica quieta"      nao_tem "Pastas: ausente"                    "$CTX_A6"

# config.json PRESENTE MAS CORROMPIDO (JSON inválido): mesmo anúncio, e o hook
# não pode quebrar — é o defeito de origem (um try único que engolia os dois).
SAIDA_A6B="$(RFM_ROOT="$A6_ROOT_INVALIDO" CLAUDE_CONFIG_DIR="$CAIXA_DEP" RFM_SETTINGS_PATH="$CAIXA_DEP/settings.json" node "$SRC/hooks/foco-session-start.cjs" > "$RAIZ_POSIX/a6b-saida.json" 2>"$RAIZ_POSIX/a6b-stderr.log"; echo "EXIT=$?")"
EXIT_A6B="${SAIDA_A6B#EXIT=}"
CTX_A6B="$(node -e "try{process.stdout.write(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).hookSpecificOutput.additionalContext)}catch{process.stdout.write('SEM_CONTEXTO')}" "$RAIZ_POSIX/a6b-saida.json")"
if [ "$EXIT_A6B" = "0" ]; then ok=$((ok+1)); echo "  ok    ACHADO 6: hook real com config.json corrompido sai com exit 0 (nao quebra)"
else falhou=$((falhou+1)); echo "  FALHA ACHADO 6: hook real com config.json corrompido saiu com exit $EXIT_A6B"; fi
checa "ACHADO 6: config.json corrompido, sai anuncio de expediente" tem     "expediente: ausente no config.json" "$CTX_A6B"
checa "ACHADO 6: config.json corrompido, isencao 1 fica quieta"     nao_tem "Pastas: ausente"                    "$CTX_A6B"

# ACHADO 3: sem Ociosidade máxima, sessão parada há 30 min na pasta do foco
# Não deve isentar (a ociosidade é indeterminada, logo não pode decidir)
FOCO_SEM_OCI="Pastas: C:/a

## Ativo

**Foco de teste** \`[trabalho]\`

Avanços:
- 2026-08-14: um avanco"
S="$(veredito "$FOCO_SEM_OCI" "[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_SEG - 30*60*1000))}]" "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
checa "ACHADO 3: sem Ociosidade maxima, nao isenta por foco em outra janela" nao_tem "foco ativo em outra janela" "$S"
checa "ACHADO 3: anuncia a indeterminacao" tem "Ociosidade máxima: ausente" "$S"

# ACHADO 4: C:/projetos/a/../a-secreto/x contra C:/projetos/a não deve casar
# (testando que path.normalize resolve ..)
S="$(outra_janela "[{\"cwd\":\"C:/projetos/a/../a-secreto/x\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/projetos/a"]' 15 "$AGORA_FIXO")"
checa "ACHADO 4: C:/projetos/a/../a-secreto/x nao casa C:/projetos/a (.. resolvido)" tem "false" "$S"

echo
echo "18. SESSAO CO-LOCADA — quem MAIS esta neste mesmo cwd (D1, D3, D4)"
# O incidente (2026-08-21): duas janelas no mesmo diretorio, `git checkout -b` numa
# delas arrancou a outra da branch em que ela trabalhava, e ela commitou tres vezes
# na branch alheia sem saber. As tres coisas que este bloco tem que provar sao as
# tres que fariam a trava mentir:
#   a) quem pergunta nunca se conta como co-locada (as duas entradas do incidente
#      tinham `cwd` IDENTICO — sem excluir a propria, toda sessao acha co-locada);
#   b) sessao PARADA continua dona (D3): dono de branch dura mais que atencao, e
#      uma janela pausada foi exatamente o caso real;
#   c) a fonte e o `sessoes.json` da raiz de DADOS, nunca o do repositorio (D4) —
#      o versionado tem uma entrada de 2026-08-12 e nao recebe escrita, entao quem
#      ler dele fica verde para sempre sem nunca ter olhado o dado vivo.
# Fixture PROPRIO: o arquivo real do usuario muda a cada heartbeat, e bateria que
# depende dele passa ou falha conforme quantas janelas estavam abertas na hora.

COL_DADOS_POSIX="$RAIZ_POSIX/dados-colocada"; mkdir -p "$COL_DADOS_POSIX"
COL_DADOS="$(cygpath -m "$COL_DADOS_POSIX" 2>/dev/null || printf '%s' "$COL_DADOS_POSIX")"
COL_REPO_POSIX="$RAIZ_POSIX/repo-com-sessoes-morto"; mkdir -p "$COL_REPO_POSIX"
COL_REPO="$(cygpath -m "$COL_REPO_POSIX" 2>/dev/null || printf '%s' "$COL_REPO_POSIX")"
COL_VAZIO_POSIX="$RAIZ_POSIX/dados-sem-sessoes"; mkdir -p "$COL_VAZIO_POSIX"
COL_VAZIO="$(cygpath -m "$COL_VAZIO_POSIX" 2>/dev/null || printf '%s' "$COL_VAZIO_POSIX")"
COL_QUEBRADO_POSIX="$RAIZ_POSIX/dados-json-quebrado"; mkdir -p "$COL_QUEBRADO_POSIX"
COL_QUEBRADO="$(cygpath -m "$COL_QUEBRADO_POSIX" 2>/dev/null || printf '%s' "$COL_QUEBRADO_POSIX")"
printf '{ isto nao e json' > "$COL_QUEBRADO_POSIX/sessoes.json"

AGORA_COL=1787356000000

# A semeadura e feita por node, e nao por heredoc de shell, porque o dado que
# importa aqui e a BARRA INVERTIDA: o harness manda `C:\Projetos\x`, o resto do
# mundo manda `C:/Projetos/x`, e o ponto do fixture e que os dois sejam a mesma
# pasta. Aspas de shell comem `\` sem avisar — ja custou uma medicao errada neste
# mesmo arquivo (secao 17), e por isso o cwd construido e IMPRESSO antes de qualquer
# afirmacao sobre ele.
cat > "$RAIZ_POSIX/semear-colocada.cjs" <<'EOF'
const fs = require('fs');
const BS = String.fromCharCode(92);
const agora = Number(process.env.FIX_AGORA);
const RM = 'C:' + BS + 'Projetos' + BS + 'rainforest-mind';
const estado = {
  // Trabalhando (prompt_ts mais novo), cwd na forma do harness.
  'sess-a': { cwd: RM, prompt_ts: agora - 60000, stop_ts: agora - 120000 },
  // PARADA (stop_ts mais novo) e em outra grafia do MESMO caminho. Conta (D3).
  'sess-b-parada': { cwd: 'c:/projetos/rainforest-mind', prompt_ts: agora - 500000, stop_ts: agora - 1000 },
  'sess-c-sabia': { cwd: 'C:' + BS + 'Projetos' + BS + 'sabia', prompt_ts: agora - 1000, stop_ts: 0 },
  // Fora da janela de 4h: nao e mais dona de nada.
  'sess-velha': { cwd: RM, prompt_ts: agora - 5 * 3600 * 1000, stop_ts: agora - 5 * 3600 * 1000 },
  // Exatamente no limite. A janela e aberta (`< janelaMs`), entao esta ja saiu.
  'sess-no-limite': { cwd: RM, prompt_ts: agora - 4 * 3600 * 1000, stop_ts: 0 },
  // Rastro de subagente, nao janela do usuario.
  'sess-de-agente': { cwd: RM + BS + '.claude' + BS + 'worktrees' + BS + 'agent-abc', prompt_ts: agora - 1000, stop_ts: 0 },
  'sess-viva-no-repo': { cwd: process.env.FIX_REPO, prompt_ts: agora - 1000, stop_ts: 0 },
};
fs.writeFileSync(process.env.FIX_DADOS + '/sessoes.json', JSON.stringify(estado, null, 1));
// O sessoes.json MORTO que mora na raiz do repositorio. Quem resolver o caminho por
// conta propria le este e nao ve nenhuma das sessoes vivas acima.
fs.writeFileSync(process.env.FIX_REPO + '/sessoes.json', JSON.stringify({
  'sess-do-repo-morto': { cwd: process.env.FIX_REPO, prompt_ts: agora - 1000, stop_ts: 0 },
}, null, 1));
process.stdout.write(JSON.stringify({ cwd_de_sess_a: estado['sess-a'].cwd }));
EOF
CWD_COL="$(FIX_AGORA=$AGORA_COL FIX_DADOS="$COL_DADOS" FIX_REPO="$COL_REPO" node "$RAIZ_POSIX/semear-colocada.cjs")"
echo "  (confirmando o fixture antes de afirmar: $CWD_COL)"

cat > "$RAIZ_POSIX/driver-colocada.cjs" <<'EOF'
const fs = require('fs');
const lib = require(process.env.LIB_PATH);
const estado = JSON.parse(fs.readFileSync(process.env.FIX_DADOS + '/sessoes.json', 'utf8'));
const r = lib.sessoesColocadas(estado, {
  cwd: process.env.FIX_CWD,
  sessionId: process.env.FIX_ID,
  agora: Number(process.env.FIX_AGORA),
});
// Ordem alfabetica na SAIDA: a ordem de verdade e por recencia, e travar as duas
// coisas na mesma assercao faz a checagem de conteudo quebrar por motivo de ordem.
process.stdout.write(
  'ids=[' + r.map((s) => s.session_id).sort().join(',') + ']' +
  ' paradas=[' + r.filter((s) => s.parada).map((s) => s.session_id).sort().join(',') + ']'
);
EOF
colocada() { # cwd, session_id, [agora], [lib]
  LIB_PATH="${4:-$LIB}" FIX_CWD="$1" FIX_ID="$2" FIX_AGORA="${3:-$AGORA_COL}" FIX_DADOS="$COL_DADOS" \
    node "$RAIZ_POSIX/driver-colocada.cjs" 2>&1
}

S_COL1="$(colocada 'C:/Projetos/rainforest-mind' 'sess-a')"
checa "co-locada: session_id de uma das duas devolve EXATAMENTE a outra" tem "ids=[sess-b-parada]" "$S_COL1"
# D3 literal: a que sobrou esta PARADA, e e por isso que ela ainda e dona.
checa "co-locada: entrada parada (stop_ts > prompt_ts) dentro da janela CONTA" tem "paradas=[sess-b-parada]" "$S_COL1"
# A grafia das duas entradas e diferente (`C:\Projetos\...` vs `c:/projetos/...`).
# Comparar cru trataria as duas janelas do incidente como pastas diferentes.
checa "co-locada: barra invertida e caixa alta casam com barra normal e minuscula" nao_tem "ids=[]" "$S_COL1"

S_COL2="$(colocada 'C:/Projetos/rainforest-mind' 'nao-existe-0000')"
checa "co-locada: session_id inexistente devolve AS DUAS"           tem     "ids=[sess-a,sess-b-parada]" "$S_COL2"
checa "co-locada: entrada fora das 4h nao conta"                    nao_tem "sess-velha"                 "$S_COL2"
checa "co-locada: entrada exatamente nas 4h nao conta"              nao_tem "sess-no-limite"             "$S_COL2"
checa "co-locada: worktree de subagente nao e janela do usuario"    nao_tem "sess-de-agente"             "$S_COL2"

checa "co-locada: cwd de C:/Projetos/sabia devolve VAZIO" tem "ids=[] paradas=[]" \
  "$(colocada 'C:/Projetos/sabia' 'sess-c-sabia')"
# cwd vazio nao pode virar coringa: casar todo mundo faria o gate barrar sempre, e
# trava que barra sempre e trava desligada no primeiro dia.
checa "co-locada: cwd vazio devolve vazio (nao casa todo mundo)" tem "ids=[]" \
  "$(colocada '' 'sess-a')"

# O ADAPTADOR: resolve a raiz de dados e le o arquivo de la.
cat > "$RAIZ_POSIX/driver-colocada-adaptador.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const r = lib.sessaoColocada({
  cwd: process.env.FIX_CWD,
  sessionId: process.env.FIX_ID,
  agora: Number(process.env.FIX_AGORA),
});
process.stdout.write('ids=[' + r.map((s) => s.session_id).sort().join(',') + ']');
EOF
adaptador() { # RFM_ROOT, cwd, session_id
  RFM_ROOT="$1" LIB_PATH="$LIB" FIX_CWD="$2" FIX_ID="$3" FIX_AGORA="$AGORA_COL" \
    node "$RAIZ_POSIX/driver-colocada-adaptador.cjs" 2>&1
}
checa "co-locada: adaptador le o sessoes.json da raiz de dados resolvida" tem "ids=[sess-b-parada]" \
  "$(adaptador "$COL_DADOS" 'C:/Projetos/rainforest-mind' 'sess-a')"
# D4, o tropeço de heartbeat.cjs:13-17 pela terceira vez: o cwd da pergunta TEM um
# sessoes.json ao lado, com uma entrada que casaria. Ler dele e o defeito.
S_COL_D4="$(adaptador "$COL_DADOS" "$COL_REPO" 'nao-existe-0000')"
checa "co-locada: le a raiz de DADOS, nao o sessoes.json ao lado do cwd" tem     "ids=[sess-viva-no-repo]" "$S_COL_D4"
checa "co-locada: a entrada do sessoes.json morto do repo nao aparece"   nao_tem "sess-do-repo-morto"      "$S_COL_D4"

# FAIL-OPEN. Trava que barra por nao conseguir medir e trava que o usuario desliga.
SAIDA_COL_SEM="$(adaptador "$COL_VAZIO" 'C:/Projetos/rainforest-mind' 'sess-a'; echo "EXIT=$?")"
checa "co-locada: sessoes.json ausente devolve vazio (fail-open)"    tem "ids=[]"  "$SAIDA_COL_SEM"
checa "co-locada: sessoes.json ausente nao quebra o processo"        tem "EXIT=0"  "$SAIDA_COL_SEM"
SAIDA_COL_QBR="$(adaptador "$COL_QUEBRADO" 'C:/Projetos/rainforest-mind' 'sess-a'; echo "EXIT=$?")"
checa "co-locada: sessoes.json corrompido devolve vazio (fail-open)" tem "ids=[]"  "$SAIDA_COL_QBR"
checa "co-locada: sessoes.json corrompido nao quebra o processo"     tem "EXIT=0"  "$SAIDA_COL_QBR"

echo
echo "19. IDENTIDADE DO FOCO NAO E DESCARTADA INTEIRA (Issue #63)"
# Defeito medido em 2026-08-23: `priorizarFoco` preenche por rank de forma
# gulosa e descartava o bloco INTEIRO quando ele nao cabia. O primeiro
# paragrafo de "## Ativo" (identidade: titulo, natureza, projeto, pastas,
# prioridade, prazo final, criterio de pronto) e o bloco de MAIOR prioridade
# (rank 1) e o que mais chegava a ~1,3 KB contra um teto de ~1,2 KB — entao
# era exatamente ele que caia fora, e os ponteiros de rank 4 (bem mais
# baratos) entravam no lugar. NAO e estouro de orcamento: e composicao.
#
# ARMADILHA DA ISSUE: "Template ABAPA" ja aparece HOJE dentro do ponteiro
# "(Fora desta injeção por espaço: ...)" — um grep pela string do bloco que
# saiu passa com o defeito intacto. A prova certa e uma string que so existe
# DENTRO do bloco de identidade (aqui, a data do prazo) aparecendo como
# CONTEUDO, fora do trecho do ponteiro.

# 19.1 — teste DIRETO de priorizarFoco, teto fixo e independente dos tetos
# globais (ORCAMENTO_BYTES/FOCO_MAX_BYTES): a identidade sozinha pesa ~991 B
# (conferido com node antes de escrever o fixture), o essencial (titulo +
# linha de prazo) pesa bem menos que 450 — a margem e de sobra, nao de fio da
# navalha, e o unico fator que muda contra o codigo antigo e a presenca do
# corte por dentro.
FILLER_CRITERIO="$(printf 'Criterio de pronto bem detalhado, com texto de enchimento. %.0s' $(seq 1 15))"
FOCO_IDENTIDADE_DIRETA="## Ativo
Último avanço datado: 2026-08-09.

**Identidade grande de teste** \`[trabalho]\`
Prioridade: alta
Critério de pronto: $FILLER_CRITERIO
Prazo final: 2026-08-25.

Marcos (as datas sao as reunioes):
- **Entrega 1 — 14/08**: marco de cronograma."
S_ID="$(prioriza "$FOCO_IDENTIDADE_DIRETA" 450)"
checa "(a) prazo da identidade chega como CONTEUDO"      tem     "2026-08-25"                    "$S_ID"
checa "(a) titulo da identidade sobrevive"               tem     "Identidade grande de teste"    "$S_ID"
checa "(a) o criterio de pronto (gordo) cede a vez"      nao_tem "Criterio de pronto bem"        "$S_ID"
checa "(a) o corte por dentro e anunciado"               tem     "identidade cortada por espaço" "$S_ID"
checa "(a) o resto do bloco (Marcos) continua cabendo"   tem     "Entrega 1 — 14/08"             "$S_ID"

# 19.2 — fim a fim via montarContexto, com a MESMA forma do FOCO.md real: um
# SKILL grande o bastante para deixar ~1,2 KB de sobra para o foco (a conta
# real da issue), e uma identidade multi-linha que passa de 1,2 KB. Numero
# tunado contra os tetos de HOJE (ORCAMENTO_BYTES=8000, FOCO_MAX_BYTES=2600):
# quebra de proposito se os tetos mudarem sem o fixture acompanhar.
REGRA_GRANDE="$(printf 'Regra numerada de teste, com texto representativo do tamanho real de uma regra do SKILL.md. %.0s' $(seq 1 68))"
SKILL_GRANDE="# Skill
## As regras
$REGRA_GRANDE
## Comando
irrelevante"
ENCHIMENTO_ID="$(printf 'Critério de pronto detalhado com bastante texto para engordar o parágrafo. %.0s' $(seq 1 18))"
FOCO_IDENTIDADE_GRANDE="# Foco

## Ativo

**Foco real de teste** \`[trabalho]\`
Projeto: Y
Pastas: Z
Prioridade: alta
Critério de pronto: $ENCHIMENTO_ID
Prazo final: 2026-08-25.

## Fora de escopo
conteudo-fora-de-escopo"
S_E2E="$(montar "$SKILL_GRANDE" "$FOCO_IDENTIDADE_GRANDE")"
checa "(a) e2e: prazo chega na injecao como conteudo"    tem "2026-08-25"          "$S_E2E"
checa "(a) e2e: cabecalho ## Ativo nao fica orfao"       tem "## Ativo"            "$S_E2E"
# SO O CORPO (antes do ponteiro "Fora desta injeção"): garante que o prazo
# nao esta so dentro do NOME de um bloco que saiu, e sim como conteudo real.
CORPO_E2E="$(echo "$S_E2E" | sed '/Fora desta injeção/,$d')"
checa "(a) e2e: o prazo esta no CORPO, nao so no ponteiro" tem "2026-08-25"        "$CORPO_E2E"

# 19.3 — invariante (b): quando NEM o essencial cabe (titulo sozinho, numa
# unica linha, maior que qualquer teto possivel), o bloco NUNCA sai
# so-cabecalho-e-ponteiro — vale o mesmo aviso explicito do caso abaixo do
# piso.
TITULO_FILLER="$(printf 'Foco com titulo enorme de proposito %.0s' $(seq 1 30))"
FOCO_TITULO_GIGANTE="# Foco

## Ativo

**${TITULO_FILLER}** \`[trabalho]\` prazo final 2026-08-25.

## Fora de escopo
X"
S_TIT="$(montar "$SKILL_GRANDE" "$FOCO_TITULO_GIGANTE")"
checa "(b) nem o essencial cabendo, dispara o aviso explicito"   tem     "O foco saiu com só ponteiros nesta injeção"    "$S_TIT"
checa "(b) o aviso para ponteiro-only tem a instrucao"           tem     "Leia o FOCO.md antes de medir desvio de escopo" "$S_TIT"
checa "(b) NUNCA emite bloco so-cabecalho-e-ponteiro"            nao_tem "Fora desta injeção"                             "$S_TIT"
# Prova da distinção entre os dois casos: cada causa produz sua frase
checa "(b) caso ponteiro-only NAO usa a frase do piso"            nao_tem "B livres, piso"                                "$S_TIT"
checa "(b.1) o aviso piso menciona o piso (num crítico)"          tem     "piso 700"                                       "$(node -e "const lib = require('./hooks/lib/contexto-sessao.cjs'); console.log(lib.avisoFocoNaoCoube(650, 'piso'))" 2>&1)"
checa "(b.1) o aviso piso NAO menciona priorização"               nao_tem "priorização"                                   "$(node -e "const lib = require('./hooks/lib/contexto-sessao.cjs'); console.log(lib.avisoFocoNaoCoube(650, 'piso'))" 2>&1)"

# 19.4 — unidade de focoSoTemPonteiro: cabecalho + os dois ponteiros de
# omissao, sem nenhuma linha de conteudo real, e "so ponteiro"; a mesma forma
# com uma linha de conteudo no meio, nao e.
cat > "$RAIZ_POSIX/driver-so-ponteiro.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(String(lib.focoSoTemPonteiro(process.env.FIX_TEXTO)));
EOF
so_ponteiro() { LIB_PATH="${2:-$LIB}" FIX_TEXTO="$1" node "$RAIZ_POSIX/driver-so-ponteiro.cjs" 2>&1; }
SO_PONTEIRO_TXT="# Foco

(Seções do FOCO.md omitidas desta injeção: X, Y. Elas continuam no arquivo — leia.)

(Fora desta injeção por espaço: A; B. **Leia o FOCO.md** antes de afirmar prazo, marco ou avanço.)"
checa "focoSoTemPonteiro: so cabecalho + ponteiros -> true"  tem "true"  "$(so_ponteiro "$SO_PONTEIRO_TXT")"
COM_CONTEUDO_TXT="# Foco

**Foco de teste** \`[trabalho]\` — prazo final 2026-08-25.

(Fora desta injeção por espaço: A; B. **Leia o FOCO.md** antes de afirmar prazo, marco ou avanço.)"
checa "focoSoTemPonteiro: com uma linha de conteudo -> false" tem "false" "$(so_ponteiro "$COM_CONTEUDO_TXT")"

echo
echo "19.5 MUTACAO — desfazer o corte por dentro tem que quebrar o item 19.1/19.2"
# Sabota uma COPIA: desliga a marcacao de identidade (a condicao nunca casa
# "Ativo"), o que devolve `priorizarFoco` ao comportamento antigo — descarte
# do bloco inteiro quando ele nao cabe.
cp "$LIB" "$RAIZ_POSIX/lib-mut-identidade.cjs"
sed -i "s/secaoAtual === 'Ativo' \&\&/secaoAtual === 'NUNCA-CASA-Issue63' \&\&/" "$RAIZ_POSIX/lib-mut-identidade.cjs"
S_MUT_ID="$(LIB_PATH="$RAIZ_POSIX/lib-mut-identidade.cjs" FIX_FOCO="$FOCO_IDENTIDADE_DIRETA" TETO=450 node "$RAIZ_POSIX/driver-foco.cjs" 2>&1)"
if echo "$S_MUT_ID" | grep -qF "2026-08-25"; then
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — o corte por dentro nao e o que faz o prazo sobreviver (saida: $S_MUT_ID)"
else
  ok=$((ok+1)); echo "  ok    mutacao expos o corte por dentro (sem ele o prazo volta a cair fora)"
fi

echo
echo "19.6 MUTACAO — desligar a invariante do item 19.3 tem que voltar o pointer-only"
cp "$LIB" "$RAIZ_POSIX/lib-mut-invariante.cjs"
sed -i "s/if (focoSoTemPonteiro(foco)) foco = avisoFocoNaoCoube(tetoFoco, 'ponteiro');/if (false \&\& focoSoTemPonteiro(foco)) foco = avisoFocoNaoCoube(tetoFoco, 'ponteiro');/" "$RAIZ_POSIX/lib-mut-invariante.cjs"
# Guarda: verifica se a mutacao realmente aplicou
if diff "$LIB" "$RAIZ_POSIX/lib-mut-invariante.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed nao encontrou a linha a mutar — mutacao nao aplicou nada, teste invalhdo"
else
  S_MUT_INV="$(montar "$SKILL_GRANDE" "$FOCO_TITULO_GIGANTE" "$RAIZ_POSIX/lib-mut-invariante.cjs")"
  if echo "$S_MUT_INV" | grep -qF "O foco saiu com só ponteiros"; then
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — a invariante nao e o que substitui o bloco pointer-only (saida: $S_MUT_INV)"
  else
    ok=$((ok+1)); echo "  ok    mutacao expos a invariante (sem ela o bloco pointer-only volta a sair calado)"
  fi
fi

echo
echo "17.1 MUTACOES — as sabotagens do briefing, cada uma tem que quebrar a asserção correspondente"
# Padrao: sabota uma COPIA da lib (nunca o LIB original), roda a MESMA fixture
# contra ela, e mostra a saida divergindo. A chamada de `checa` dentro de um
# SUBSHELL `( ... )` imprime a linha "FALHA ..." de verdade (prova textual de
# que a assercao pega o defeito) sem contaminar o ok/falhou do arquivo inteiro
# — subshell tem copia propria das variaveis, o incremento nao vaza para fora.
# O veredito sobre "mutacao e load-bearing" quem da e o if/else logo depois,
# no mesmo estilo das secoes 5, 9 e 12 deste arquivo.

echo "  -- SABOTAGEM 1: dentroDoExpediente devolve false em vez de null quando falta expediente"
cp "$LIB" "$RAIZ_POSIX/lib-mut-expediente.cjs"
sed -i 's/if (!config || !config.expediente) return null;/if (!config || !config.expediente) return false;/' "$RAIZ_POSIX/lib-mut-expediente.cjs"
# Guarda: verifica se a mutacao realmente aplicou
if diff "$LIB" "$RAIZ_POSIX/lib-mut-expediente.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed nao encontrou a linha a mutar — mutacao nao aplicou nada, teste invalido"
else
  S_MUT1="$(expediente '2026,8,10,10,0' '{}' "$RAIZ_POSIX/lib-mut-expediente.cjs")"
  echo "  (saida do mutante: $S_MUT1 — a assercao real espera 'null')"
  ( checa "dentroDoExpediente: sem expediente no config devolve null (nao false)" tem "null" "$S_MUT1" )
  if [ "$S_MUT1" != "null" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos o colapso null->false (D6 inteiro depende disso)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — null->false nao e o que a assercao mede"
  fi
fi

echo "  -- SABOTAGEM 2: focoAtivoEmOutraJanela compara caminho com includes (substring) em vez de igualdade"
cp "$LIB" "$RAIZ_POSIX/lib-mut-includes.cjs"
sed -i 's/cwdNormalizado === pasta/cwdNormalizado.includes(pasta)/' "$RAIZ_POSIX/lib-mut-includes.cjs"
# Guarda: verifica se a mutacao realmente aplicou
if diff "$LIB" "$RAIZ_POSIX/lib-mut-includes.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed nao encontrou a linha a mutar — mutacao nao aplicou nada, teste invalido"
else
  S_MUT2="$(outra_janela "[{\"cwd\":\"C:/abc\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO" "$RAIZ_POSIX/lib-mut-includes.cjs")"
  echo "  (saida do mutante: $S_MUT2 — a assercao real espera 'false')"
  ( checa "focoAtivoEmOutraJanela: C:/abc nao casa C:/a por prefixo" tem "false" "$S_MUT2" )
  if [ "$S_MUT2" = "true" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos o casamento por prefixo (C:/abc passou a isentar contra C:/a)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — includes() nao e o que a assercao mede"
  fi
fi

echo "  -- SABOTAGEM 3: focoAtivoEmOutraJanela usa stop_ts em vez de prompt_ts como sinal humano"
cp "$LIB" "$RAIZ_POSIX/lib-mut-stopts.cjs"
sed -i 's/const { cwd, prompt_ts } = sessao;/const { cwd, stop_ts: prompt_ts } = sessao;/' "$RAIZ_POSIX/lib-mut-stopts.cjs"
# Guarda: verifica se a mutacao realmente aplicou
if diff "$LIB" "$RAIZ_POSIX/lib-mut-stopts.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed nao encontrou a linha a mutar — mutacao nao aplicou nada, teste invalido"
else
  FIX_STOP="[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_FIXO - 999999999)),\"stop_ts\":$((AGORA_FIXO-1000))}]"
  S_MUT3="$(outra_janela "$FIX_STOP" '["C:/a"]' 15 "$AGORA_FIXO" "$RAIZ_POSIX/lib-mut-stopts.cjs")"
  echo "  (saida do mutante: $S_MUT3 — a assercao real espera 'false')"
  ( checa "focoAtivoEmOutraJanela: prompt_ts frio e o que conta, nao stop_ts" tem "false" "$S_MUT3" )
  if [ "$S_MUT3" = "true" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos a troca prompt_ts->stop_ts (sinal errado passou a isentar)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — a troca de campo nao e o que a assercao mede"
  fi
fi

echo "  -- SABOTAGEM 4: anuncio de uma isenção suprime o veredito da outra (defeito do D6 original)"
cat > "$RAIZ_POSIX/sabotar-veredito.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
// Transforma o novo código que analisa isenções independentemente em código que
// retorna cedo quando acha anúncio (comportamento do D6 original, errado).
// Ancora reescrita em 2026-08-14: a variavel "ociosidadePar" virou "ociosidade" e
// a isenção 1 ganhou um segundo ramo (ociosidade === null) — ancora presa na forma
// antiga nunca batia, o mutador saia com exit 1 e o `.sh` seguia usando a copia
// intocada. Regra 12: se a ancora nao bate no arquivo de verdade, ela nao prova nada.
const achar = [
  '  // Analisa cada isenção INDEPENDENTEMENTE (D6 corrigido)',
  '  const vereditos = [];',
  '  const anuncios = [];',
  '',
  '  // ISENÇÃO 1: Foco ativo em outra janela (regra 17)',
  '  // Precisa de: Pastas: configurado E Ociosidade máxima: declarada',
  '  if (!pastas.length) {',
  '    // Indeterminada: faltam dados',
  "    anuncios.push('Pastas: ausente no FOCO.md — o radar vai cobrar desvio mesmo com o foco aberto em outra janela.');",
  "  } else if (ociosidade === null) {",
  '    // Indeterminada: faltam dados (ociosidade)',
  "    anuncios.push('Ociosidade máxima: ausente no FOCO.md — o radar não pode determinar se o foco está ativo em outra janela.');",
  '  } else {',
  '    // Determinada: pode decidir',
  '    if (focoAtivoEmOutraJanela(sessoes, pastas, ociosidade, agora)) {',
  "      vereditos.push('foco ativo em outra janela');",
  '    }',
  '  }',
].join('\n');
const trocar = [
  '  // SABOTAGEM: retorna cedo se acha anúncio (defeito do D6 original)',
  '  // ISENÇÃO 1: Foco ativo em outra janela (regra 17)',
  '  // Precisa de: Pastas: configurado E Ociosidade máxima: declarada',
  '  if (!pastas.length) {',
  "    return 'Pastas: ausente no FOCO.md — o radar vai cobrar desvio mesmo com o foco aberto em outra janela.';",
  '  }',
  '  const vereditos = [];',
  '  const anuncios = [];',
  '  if (ociosidade !== null && focoAtivoEmOutraJanela(sessoes, pastas, ociosidade, agora)) {',
  "    vereditos.push('foco ativo em outra janela');",
  '  }',
].join('\n');
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.replace(achar, trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
cp "$LIB" "$RAIZ_POSIX/lib-mut-veredito.cjs"
node "$RAIZ_POSIX/sabotar-veredito.cjs" "$RAIZ_POSIX/lib-mut-veredito.cjs"
EXIT_SABOTA4=$?
if [ "$EXIT_SABOTA4" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 4 (exit $EXIT_SABOTA4) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que a independencia das isencoes e load-bearing"
else
  # Discriminante de verdade: Pastas AUSENTE e config SEM expediente. So assim o
  # codigo correto tem as DUAS isencoes indeterminadas e emite os DOIS anuncios —
  # com Pastas presente (fixture antiga) o codigo correto ja para no primeiro
  # anuncio sozinho, e a checagem passava com ou sem sabotagem (o proprio Achado 5).
  S_MUT4="$(veredito "$FOCO_SEM_PASTAS" '[]' '{}' "$AGORA_SEG" "$RAIZ_POSIX/lib-mut-veredito.cjs")"
  echo "  (saida do mutante com sabotagem, Pastas ausente + config {}: $S_MUT4)"
  if echo "$S_MUT4" | grep -qF "expediente: ausente"; then
    falhou=$((falhou+1))
    echo "  FALHA sabotagem sem efeito — o anuncio da 2a isencao sobreviveu ao return cedo"
  else
    ok=$((ok+1)); echo "  ok    sabotagem expos que o return cedo suprime o anuncio da 2a isencao (independência e load-bearing)"
  fi
fi

echo "  -- SABOTAGEM 5: sessoesColocadas nunca acha co-locada (a comparacao de cwd vira false)"
cp "$LIB" "$RAIZ_POSIX/lib-mut-colocada.cjs"
sed -i 's/normalizarCwd(s\.cwd) === alvo/false/' "$RAIZ_POSIX/lib-mut-colocada.cjs"
if grep -qF 'normalizarCwd(s.cwd) === alvo' "$RAIZ_POSIX/lib-mut-colocada.cjs"; then
  falhou=$((falhou+1)); echo "  FALHA ANCORA NAO BATE na sabotagem 5 — a comparacao nao foi trocada, a copia intocada"
  echo "         nao prova que a co-locacao e load-bearing"
else
  S_MUT5="$(colocada 'C:/Projetos/rainforest-mind' 'sess-a' "$AGORA_COL" "$RAIZ_POSIX/lib-mut-colocada.cjs")"
  echo "  (saida do mutante: $S_MUT5 — a assercao real espera 'ids=[sess-b-parada]')"
  ( checa "co-locada: session_id de uma das duas devolve EXATAMENTE a outra" tem "ids=[sess-b-parada]" "$S_MUT5" )
  if [ "$S_MUT5" = "ids=[] paradas=[]" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos a co-locacao (o gate de checkout ficaria mudo no caso das Issues #25 e #38)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — a comparacao de cwd nao e o que a assercao mede (saida: $S_MUT5)"
  fi
fi

echo "  -- SABOTAGEM 6: dentroDoExpediente so considera a 1a faixa quando ha N faixas"
cp "$LIB" "$RAIZ_POSIX/lib-mut-faixas.cjs"
sed -i 's/? exp\.faixas/? [exp.faixas[0]]/' "$RAIZ_POSIX/lib-mut-faixas.cjs"
# Guarda: verifica se a mutacao realmente aplicou
if diff "$LIB" "$RAIZ_POSIX/lib-mut-faixas.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed nao encontrou a linha a mutar — mutacao nao aplicou nada, teste invalido"
else
  S_MUT6="$(expediente '2026,8,10,15,0' "$CONFIG_EXPEDIENTE_FAIXAS" "$RAIZ_POSIX/lib-mut-faixas.cjs")"
  echo "  (saida do mutante em seg 15:00, 2a faixa 14-18: $S_MUT6 — a assercao real espera 'true')"
  ( checa "dentroDoExpediente: faixas - dentro da 2a faixa (seg 15:00)" tem "true" "$S_MUT6" )
  if [ "$S_MUT6" = "false" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos que so a 1a faixa valia (a 2a faixa, com o almoco no meio, ficaria sempre fora)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — restringir a 1a faixa nao e o que a assercao mede (saida: $S_MUT6)"
  fi
fi

echo "  -- SABOTAGEM 7: devolver a seta (↳) literal ao nucleo da regra 15 (D6)"
# Padrao identico as sabotagens 4/5: copia o artefato REAL (aqui, o SKILL.md, nao
# a lib), sabota com um script node que confere a ancora antes de trocar, roda a
# MESMA medicao (checa-invariantes.cjs) contra a copia mutada, e exige que a
# contagem de seta dupla deixe de ser zero.
cat > "$RAIZ_POSIX/sabotar-seta.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
const achar = 'nunca dump filtrado.\n<!-- detalhe -->';
const trocar = 'nunca dump filtrado. ↳\n<!-- detalhe -->';
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.split(achar).join(trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
cp "$SKILL_REAL" "$RAIZ_POSIX/skill-mut-seta.md"
node "$RAIZ_POSIX/sabotar-seta.cjs" "$RAIZ_POSIX/skill-mut-seta.md"
EXIT_SABOTA7=$?
if [ "$EXIT_SABOTA7" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 7 (exit $EXIT_SABOTA7) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que a seta unica e load-bearing"
else
  LEITURA_MUT7="$(LIB_PATH="$LIB" SKILL="$RAIZ_POSIX/skill-mut-seta.md" node "$RAIZ_POSIX/checa-invariantes.cjs")"
  SETAS_DUPLAS_MUT7="$(echo "$LEITURA_MUT7" | cut -d' ' -f2)"
  echo "  (saida do mutante: setas-duplas=$SETAS_DUPLAS_MUT7 — a assercao real espera 0)"
  if [ -n "$SETAS_DUPLAS_MUT7" ] && [ "$SETAS_DUPLAS_MUT7" != "0" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos a seta dupla (D6: o ↳ literal de volta a regra 15 vira ↳ ↳ na injecao)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — devolver o ↳ literal nao produziu seta dupla"
  fi
fi
rm -f "$RAIZ_POSIX/skill-mut-seta.md"

echo "  -- SABOTAGEM 8: acrescentar ~100 B ao nucleo da regra 1 (D7)"
cat > "$RAIZ_POSIX/sabotar-nucleo.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
const achar = 'todo turno**.\n<!-- detalhe -->';
const trocar = 'todo turno**. ' + 'x'.repeat(100) + '\n<!-- detalhe -->';
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.split(achar).join(trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
cp "$SKILL_REAL" "$RAIZ_POSIX/skill-mut-nucleo.md"
node "$RAIZ_POSIX/sabotar-nucleo.cjs" "$RAIZ_POSIX/skill-mut-nucleo.md"
EXIT_SABOTA8=$?
if [ "$EXIT_SABOTA8" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 8 (exit $EXIT_SABOTA8) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que o numero do nucleo e load-bearing"
else
  LEITURA_MUT8="$(LIB_PATH="$LIB" SKILL="$RAIZ_POSIX/skill-mut-nucleo.md" node "$RAIZ_POSIX/checa-invariantes.cjs")"
  NUCLEO_BYTES_MUT8="$(echo "$LEITURA_MUT8" | cut -d' ' -f1)"
  echo "  (saida do mutante: nucleo=$NUCLEO_BYTES_MUT8 B — a assercao real exige exatamente $NUCLEO_ESPERADO B)"
  if [ -n "$NUCLEO_BYTES_MUT8" ] && [ "$NUCLEO_BYTES_MUT8" != "$NUCLEO_ESPERADO" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos o desvio do nucleo (D7: a quebra em references/ nao pode mudar 1 byte sequer)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — engordar o nucleo da regra 1 nao mudou a medicao"
  fi
fi
rm -f "$RAIZ_POSIX/skill-mut-nucleo.md"

echo "  -- SABOTAGEM 9: trocar '## As regras' por outro texto (D5)"
cat > "$RAIZ_POSIX/sabotar-secao.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
const achar = '## As regras';
const trocar = '## As diretrizes';
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.split(achar).join(trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
cp "$SKILL_REAL" "$RAIZ_POSIX/skill-mut-secao.md"
node "$RAIZ_POSIX/sabotar-secao.cjs" "$RAIZ_POSIX/skill-mut-secao.md"
EXIT_SABOTA9=$?
if [ "$EXIT_SABOTA9" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 9 (exit $EXIT_SABOTA9) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que '## As regras' e load-bearing"
else
  # Roda o parser DE VERDADE (montarContexto), nao so grep no texto: o que
  # importa e' que trocar o literal derruba o carregamento na sessao real.
  SKILL_MUTADO_TXT="$(cat "$RAIZ_POSIX/skill-mut-secao.md")"
  S_MUT9="$(montar "$SKILL_MUTADO_TXT" '')"
  if echo "$S_MUT9" | grep -qF "FALHA AO CARREGAR AS REGRAS"; then
    echo "  (saida do mutante: FALHA AO CARREGAR AS REGRAS — a assercao real nao pode ver isto)"
    ok=$((ok+1)); echo "  ok    mutacao expos que '## As regras' e load-bearing (sem ele a sessao sobe sem regra nenhuma)"
  else
    echo "  (saida do mutante: nao disparou o alarme)"
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — trocar '## As regras' nao derrubou o carregamento"
  fi
fi
rm -f "$RAIZ_POSIX/skill-mut-secao.md"

echo "  -- SABOTAGEM 10: devolver 'Skill(rainforest-mind)' ao cabecalho (D4)"
cat > "$RAIZ_POSIX/sabotar-cabecalho.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
// O arquivo fonte e' um template literal JS (backtick), entao os backticks QUE
// APARECEM DENTRO dele vem escapados com backslash no arquivo -- \` literal, nao
// backtick nu. A ancora e a troca tem de casar com os bytes reais do arquivo,
// nao com o que o template produziria depois de avaliado.
const achar = '\\`${pastaReferences}/regra-<n>.md\\` (onde \\`<n>\\` é o número da regra).';
const trocar = 'carregue \\`Skill(rainforest-mind)\\` antes de aplicar a regra marcada.';
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.split(achar).join(trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
cp "$LIB" "$RAIZ_POSIX/lib-mut-cabecalho.cjs"
node "$RAIZ_POSIX/sabotar-cabecalho.cjs" "$RAIZ_POSIX/lib-mut-cabecalho.cjs"
EXIT_SABOTA10=$?
if [ "$EXIT_SABOTA10" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 10 (exit $EXIT_SABOTA10) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que o cabecalho citar references/ e load-bearing"
else
  S_MUT10="$(montar "$SKILL_OK" '' "$RAIZ_POSIX/lib-mut-cabecalho.cjs")"
  echo "  (saida do mutante contem 'Skill(rainforest-mind)': $(echo "$S_MUT10" | grep -qF 'Skill(rainforest-mind)' && echo sim || echo nao))"
  if echo "$S_MUT10" | grep -qF "Skill(rainforest-mind)"; then
    ok=$((ok+1)); echo "  ok    mutacao expos o cabecalho voltando a mandar carregar a skill inteira (D4)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — devolver a instrucao antiga nao apareceu no cabecalho"
  fi
fi

echo "  -- SABOTAGEM 11: corromper o titulo de regra-17.md, hoje um dos dois sãos (secao 7.7)"
# Prova que a assercao de formato do H1 pega corrupcao NOVA, e nao so re-declara o
# que ja sabia sobre os 15 arquivos ja quebrados. Copia $REFERENCES_REAIS inteiro
# (nunca o original rastreado), cola um ** orfao no titulo de regra-17.md com o
# mesmo padrao dos 15 -- ponto final seguido de ** e prosa colada -- e roda a MESMA
# checa-titulos.cjs contra a copia mutada.
cat > "$RAIZ_POSIX/sabotar-titulo-regra17.cjs" <<'SABOTA_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let texto = fs.readFileSync(alvo, 'utf8');
// Ancora SEM o ponto final de proposito: o titulo de regra-17.md mudou de
// "...o alerta." para "...o alerta" quando os 15 titulos truncados foram
// consertados (commit 9a62232, branch design/skills-finas-com-references) --
// o proprio achado desta secao motivou a padronizacao. .includes()/.replace()
// casam por substring, entao a ancora sem ponto bate nas DUAS formas (com ou
// sem o ponto sobrando depois dela); so a presenca de "** " apos "alerta" e'
// o que importa para o mutante.
const achar = '# Regra 17 — Multi-janela: paralelo é intenção, janela parada é o alerta';
const trocar = '# Regra 17 — Multi-janela: paralelo é intenção, janela parada é o alerta** O usuário';
if (!texto.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
texto = texto.replace(achar, trocar);
fs.writeFileSync(alvo, texto);
SABOTA_EOF
REFS_MUT_R17="$RAIZ_POSIX/references-mut-r17"
rm -rf "$REFS_MUT_R17"
cp -r "$REFERENCES_REAIS" "$REFS_MUT_R17"
node "$RAIZ_POSIX/sabotar-titulo-regra17.cjs" "$REFS_MUT_R17/regra-17.md"
EXIT_SABOTA11=$?
if [ "$EXIT_SABOTA11" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 11 (exit $EXIT_SABOTA11) — mutador nao mutou nada,"
  echo "         a copia intocada nao prova que a assercao morde titulo novo corrompido"
else
  SAIDA_MUT11="$(REFERENCES_DIR="$REFS_MUT_R17" node "$RAIZ_POSIX/checa-titulos.cjs")"
  echo "  (saida do mutante: $(echo "$SAIDA_MUT11" | head -1) — a assercao real espera regra-17.md FORA da lista)"
  echo "$SAIDA_MUT11" | grep '^ASTERISCOS regra-17\.md' | sed 's/^/  /'
  if echo "$SAIDA_MUT11" | grep -q '^ASTERISCOS regra-17\.md:'; then
    ok=$((ok+1)); echo "  ok    mutacao expos que a assercao pega corrupcao NOVA, mesmo num titulo hoje são (regra-17.md)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — corromper o titulo de regra-17.md nao fez a assercao acusa-lo"
  fi
fi
rm -rf "$REFS_MUT_R17"


echo
echo "8. a LEGENDA VISIVEL (systemMessage) — o unico canal que o usuario VE na abertura"
# Por que esta secao existe: ate 2026-08-25 os dois hooks de SessionStart emitiam so
# `additionalContext`, que vai para o contexto do modelo e NAO aparece na tela. O
# usuario abria a sessao e via nada — sem saber se o plugin subiu, qual foco estava
# ativo, ou se havia janela dele parada esperando resposta. O estado existia e nao
# chegava a quem decide com ele.
#
# O que esta secao precisa provar:
#   1. que a legenda diz de qual foco se trata, com a natureza;
#   2. que ela responde "esta janela esta no foco?" pela PASTA, e que ela CALA
#      quando o FOCO.md nao declara `Pastas:` — afirmar qualquer das duas ali seria
#      inventar estado;
#   3. que ela conta janela parada esperando o usuario (regra 17);
#   4. que dependencia bloqueada aparece na TELA e nao so no contexto (regra 14);
#   5. que ela nao carrega as regras — isso e' do outro canal, e repetir custaria a
#      tela inteira sem mudar nenhuma decisao dele.
# A mutacao no fim desliga a comparacao de pasta e exige que o item 2 pare de pegar.

cat > "$RAIZ_POSIX/driver-legenda.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.montarLegenda({
  focoText: process.env.FIX_FOCO || '',
  entradas: JSON.parse(process.env.FIX_ENTRADAS || '[]'),
  cwdAtual: process.env.FIX_CWD || '',
  bloqueios: JSON.parse(process.env.FIX_BLOQUEIOS || '[]'),
}));
EOF

legenda() { # foco, entradas(json), cwd, bloqueios(json)
  LIB_PATH="${LIB_LEGENDA:-$LIB}" FIX_FOCO="$1" FIX_ENTRADAS="${2:-[]}" FIX_CWD="${3:-}" \
    FIX_BLOQUEIOS="${4:-[]}" node "$RAIZ_POSIX/driver-legenda.cjs"
}

FOCO_COM_PASTAS='# Foco

## Ativo

**Template ABAPA — V1 funcionando** `[trabalho]` — declarado 2026-08-06.
Pastas: C:/Microsiga/protheus-totvs-agro/inovacao
        C:/Microsiga/protheus-totvs-agro/tbc-licensing
Ociosidade máxima: 15 min.
'

FOCO_SEM_PASTAS='# Foco

## Ativo

**Descanso do rainforest** `[pessoal]` — declarado 2026-08-20.
'

S="$(legenda "$FOCO_COM_PASTAS" '[]' 'C:\Projetos\rainforest-mind')"
checa "legenda nomeia o foco ativo"          tem     "Template ABAPA"            "$S"
checa "legenda traz a natureza do foco"      tem     "[trabalho]"                "$S"
checa "janela fora das pastas se declara"    tem     "esta janela está fora dele" "$S"
checa "legenda NAO repete as regras"         nao_tem "Responder tudo, na ordem"  "$S"

S="$(legenda "$FOCO_COM_PASTAS" '[]' 'C:\Microsiga\protheus-totvs-agro\inovacao\worktrees\x')"
checa "subpasta do foco conta como dentro"   tem     "esta janela está NO foco"  "$S"

S="$(legenda "$FOCO_SEM_PASTAS" '[]' 'C:\Projetos\rainforest-mind')"
checa "sem Pastas: a legenda nao afirma dentro" nao_tem "NO foco"                "$S"
checa "sem Pastas: a legenda nao afirma fora"   nao_tem "fora dele"              "$S"
checa "foco pessoal aparece com a natureza"     tem     "[pessoal]"              "$S"

S="$(legenda '' '[]' 'C:\Projetos\rainforest-mind')"
checa "sem foco declarado a legenda ainda pinta" tem    "rainforest-mind ativo"  "$S"
checa "sem foco declarado ensina o comando"      tem    "/foco"                  "$S"

ENTRADAS='[{"cwd":"C:/a","trabalhando":true,"minutos":7},{"cwd":"C:/b","trabalhando":false,"minutos":81},{"cwd":"C:/c","trabalhando":false,"minutos":5}]'
S="$(legenda "$FOCO_COM_PASTAS" "$ENTRADAS" 'C:\Projetos\rainforest-mind')"
checa "conta as janelas vivas"               tem     "3 janelas"                 "$S"
checa "separa quem esta trabalhando"         tem     "1 trabalhando"             "$S"
checa "conta quem espera o usuario"          tem     "2 esperando você"          "$S"
checa "diz ha quanto tempo a mais parada"    tem     "81 min"                    "$S"

S="$(legenda "$FOCO_COM_PASTAS" '[]' 'C:\Projetos\rainforest-mind' '["bridge WhatsApp FORA (http://localhost:3005/api) — envio indisponível"]')"
checa "bloqueio da regra 14 aparece na tela" tem     "bridge WhatsApp FORA"      "$S"
checa "bloqueio diz o efeito pratico"        tem     "envio indisponível"        "$S"

# Teto: a legenda e' o que o usuario le de relance. Parede de texto para de ser lida,
# e a partir dai ela custa atencao sem devolver estado.
S="$(legenda "$FOCO_COM_PASTAS" '[]' 'C:\Projetos\rainforest-mind')"
BYTES="$(printf '%s' "$S" | wc -c)"
if [ "$BYTES" -le 700 ]; then
  ok=$((ok+1)); echo "  ok    legenda cabe no teto de 700 B (mediu $BYTES B)"
else
  falhou=$((falhou+1)); echo "  FALHA legenda estourou o teto de 700 B (mediu $BYTES B)"
fi

MUITAS="$(node -e 'const a=[];for(let i=0;i<40;i++)a.push({cwd:"C:/p"+i,trabalhando:false,minutos:i});process.stdout.write(JSON.stringify(a))')"
S="$(legenda "$FOCO_COM_PASTAS" "$MUITAS" 'C:\Projetos\rainforest-mind')"
BYTES="$(printf '%s' "$S" | wc -c)"
if [ "$BYTES" -le 700 ]; then
  ok=$((ok+1)); echo "  ok    40 janelas nao estouram o teto (mediu $BYTES B)"
else
  falhou=$((falhou+1)); echo "  FALHA 40 janelas estouraram o teto (mediu $BYTES B)"
fi

# Largura: a legenda e a UNICA coisa que ele VE, e quem corta na tela e o terminal,
# que conta CARACTERE. O harness ainda prefixa `SessionStart:startup says: ` (27
# caracteres) na primeira linha do bloco. Ate 2026-08-25 o teto era em BYTES (150), e
# na captura de tela dele a linha saiu com 143 caracteres + 27 de prefixo = 170 de
# largura, cortada com `…` no meio da frase. Parametro cuja unidade nao e a unidade do
# problema continua parecendo certo enquanto mente — mesma familia do AVANCOS_MAX_BYTES.
FOCO_TITULO_LONGO='# Foco

## Ativo

**Um titulo de foco deliberadamente longo para estourar qualquer teto razoavel de largura de terminal e forcar o corte** `[trabalho]` — declarado 2026-08-25.
Pastas: C:/algum/lugar
Ociosidade máxima: 15 min.
'
S="$(legenda "$FOCO_TITULO_LONGO" "$MUITAS" 'C:\Projetos\rainforest-mind' '["bridge WhatsApp FORA (http://localhost:3005/api) — envio de mensagem indisponivel para sempre e ainda por cima com um texto longo demais"]')"
LARGURA_MAX=0
while IFS= read -r linha; do
  n="$(printf '%s' "$linha" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(String(Array.from(s).length)))")"
  [ "$n" -gt "$LARGURA_MAX" ] && LARGURA_MAX="$n"
done <<< "$S"
if [ "$LARGURA_MAX" -le 90 ]; then
  ok=$((ok+1)); echo "  ok    nenhuma linha da legenda passa de 90 caracteres (maior: $LARGURA_MAX)"
else
  falhou=$((falhou+1)); echo "  FALHA linha de $LARGURA_MAX caracteres — o terminal vai cortar com reticencia"
fi

if echo "$S" | grep -q "…"; then
  ok=$((ok+1)); echo "  ok    o corte de largura e ANUNCIADO com reticencia (nao some calado)"
else
  falhou=$((falhou+1)); echo "  FALHA titulo longo nao foi cortado, ou foi cortado em silencio"
fi

echo "  -- SABOTAGEM 12: fazer a legenda afirmar SEMPRE que a janela esta no foco"
# A assercao que importa aqui nao e' "tem texto", e' "o texto e' VERDADE". Uma legenda
# que diz "esta janela esta NO foco" para toda janela passaria em qualquer checagem de
# presenca, e mentiria justamente na sessao em que ele precisa do aviso de desvio.
# O mutante troca a comparacao de pasta por `true` e o teste do item 2 tem que cair.
LIB_MUT_LEGENDA="$RAIZ_POSIX/contexto-sessao-mut-legenda.cjs"
cp "$LIB" "$LIB_MUT_LEGENDA"
node -e '
const fs = require("fs");
const alvo = process.argv[1];
let t = fs.readFileSync(alvo, "utf8");
const achar = "const dentro = pastas.some((p) => aqui === p || aqui.startsWith(p + \u0027/\u0027));";
const trocar = "const dentro = true;";
if (!t.includes(achar)) { console.error("ANCORA NAO BATE"); process.exit(1); }
fs.writeFileSync(alvo, t.replace(achar, trocar));
' "$LIB_MUT_LEGENDA"
EXIT_SABOTA12=$?
if [ "$EXIT_SABOTA12" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na sabotagem 12 (exit $EXIT_SABOTA12) — a copia intocada nao prova nada"
else
  S_MUT="$(LIB_LEGENDA="$LIB_MUT_LEGENDA" legenda "$FOCO_COM_PASTAS" '[]' 'C:\Projetos\rainforest-mind')"
  echo "  (saida do mutante: $(echo "$S_MUT" | head -1))"
  if echo "$S_MUT" | grep -qF "esta janela está NO foco"; then
    ok=$((ok+1)); echo "  ok    mutacao expos que a assercao mede a PASTA, e nao so a presenca de texto"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — desligar a comparacao de pasta nao mudou a legenda"
  fi
fi
rm -f "$LIB_MUT_LEGENDA"

echo
echo "20. ESTRATEGIA.md — ponteiro residente e compatibilidade para trás (Issue #74)"
# O split físico (scripts/foco.cjs separar) tira as seções não-residentes de
# dentro do FOCO.md; o motor só precisa saber SE `ESTRATEGIA.md` existe para
# acrescentar UMA linha curta apontando pra lá — quem lê disco é o adaptador,
# `montarContexto` recebe `temEstrategia`/`estrategiaPath` já prontos.
# SEM `ESTRATEGIA.md` (temEstrategia omitido ou false) o comportamento tem que
# ser IDÊNTICO ao de hoje — nem um byte a mais: é a mesma garantia que o resto
# desta bateria já cobre para FOCO.md monolítico.

cat > "$RAIZ_POSIX/driver-estrategia.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.montarContexto({
  skillText: process.env.FIX_SKILL || '',
  focoText: process.env.FIX_FOCO || '',
  caminhoSkill: 'C:\\fake\\SKILL.md',
  root: 'C:\\fake',
  temEstrategia: process.env.FIX_TEM_ESTRATEGIA === '1',
  estrategiaPath: process.env.FIX_ESTRATEGIA_PATH || undefined,
}));
EOF
contexto_estrategia() { # skill, foco, temEstrategia(0|1), estrategiaPath, [lib]
  LIB_PATH="${5:-$LIB}" FIX_SKILL="$1" FIX_FOCO="$2" FIX_TEM_ESTRATEGIA="$3" FIX_ESTRATEGIA_PATH="$4" node "$RAIZ_POSIX/driver-estrategia.cjs" 2>&1
}

# 20.1 — SEM ESTRATEGIA.md: saída IDÊNTICA ao `montar()` de sempre, byte a byte.
S_SEM="$(montar "$SKILL_OK" "$FOCO_MUITOS")"
S_SEM_EXPLICITO="$(contexto_estrategia "$SKILL_OK" "$FOCO_MUITOS" "0" "")"
checa "20.1 sem ESTRATEGIA.md: nenhum ponteiro novo aparece"        nao_tem "📎 Estratégia" "$S_SEM"
checa_igual "20.1 omitir temEstrategia == passar false explícito (compat)" "$S_SEM" "$S_SEM_EXPLICITO"

# 20.2 — COM ESTRATEGIA.md: ganha a linha residente, curta, com o caminho.
S_COM="$(contexto_estrategia "$SKILL_OK" "$FOCO_MUITOS" "1" 'C:\fake\ESTRATEGIA.md')"
checa "20.2 com ESTRATEGIA.md: ganha a linha residente"  tem "📎 Estratégia" "$S_COM"
checa "20.2 a linha aponta pro caminho recebido"         tem 'C:\fake\ESTRATEGIA.md' "$S_COM"

# 20.3 — pós-split de verdade: seção que SAIU do FOCO.md (fisicamente ausente
# do texto, como faz `scripts/foco.cjs separar`) não gera mais o ponteiro
# GORDO de "seções omitidas" — ele só existe quando a seção ESTÁ no texto e o
# resumo a troca por ponteiro (`resumirFoco`); seção ausente não tem o que
# omitir.
FOCO_SEM_FORA_DE_ESCOPO="# Foco

## Ativo

Foco de teste, já dividido — sem a seção Fora de escopo aqui dentro."
S_POS_SPLIT="$(contexto_estrategia "$SKILL_OK" "$FOCO_SEM_FORA_DE_ESCOPO" "1" 'C:\fake\ESTRATEGIA.md')"
checa "20.3 pós-split: some o ponteiro gordo de seções omitidas" nao_tem "Seções do FOCO.md omitidas" "$S_POS_SPLIT"
checa "20.3 pós-split: o ponteiro curto do ESTRATEGIA.md continua" tem "📎 Estratégia" "$S_POS_SPLIT"

# 20.4 — o ponteiro é RESERVADO no orçamento antes do foco ser priorizado
# (mesma lógica do `reserva` em `priorizarFoco`) — nunca sai cortado no meio,
# mesmo com um FOCO.md grande o bastante para o resto do bloco ser priorizado.
S_GRANDE="$(contexto_estrategia "$SKILL_OK" "$FOCO_MUITOS" "1" 'C:\fake\ESTRATEGIA.md')"
LINHA_ESTRATEGIA="$(echo "$S_GRANDE" | grep '📎 Estratégia')"
if [[ "$LINHA_ESTRATEGIA" == *"ESTRATEGIA.md" ]]; then
  ok=$((ok+1)); echo "  ok    20.4 a linha do ESTRATEGIA.md fecha completa mesmo com o foco grande"
else
  falhou=$((falhou+1)); echo "  FALHA 20.4 linha do ESTRATEGIA.md saiu truncada: $LINHA_ESTRATEGIA"
fi

echo
echo "20.5 MUTAÇÃO — desligar o append do ponteiro tem que derrubar o item 20.2"
cp "$LIB" "$RAIZ_POSIX/lib-mut-estrategia.cjs"
sed -i "s/if (pastaEstrategia) foco += pastaEstrategia;/if (false) foco += pastaEstrategia;/" "$RAIZ_POSIX/lib-mut-estrategia.cjs"
if diff "$LIB" "$RAIZ_POSIX/lib-mut-estrategia.cjs" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA o sed não encontrou a linha a mutar — mutação não aplicou nada, teste inválido"
else
  S_MUT_EST="$(contexto_estrategia "$SKILL_OK" "$FOCO_MUITOS" "1" 'C:\fake\ESTRATEGIA.md' "$RAIZ_POSIX/lib-mut-estrategia.cjs")"
  echo "  (o mutante ainda tem '📎 Estratégia'? $(echo "$S_MUT_EST" | grep -qF '📎 Estratégia' && echo sim || echo não))"
  if echo "$S_MUT_EST" | grep -qF "📎 Estratégia"; then
    falhou=$((falhou+1)); echo "  FALHA mutação sem efeito — desligar o append não tirou o ponteiro"
  else
    ok=$((ok+1)); echo "  ok    mutação expôs que o ponteiro depende do append (sem ele, some calado)"
  fi
fi
rm -f "$RAIZ_POSIX/lib-mut-estrategia.cjs"

echo
echo "== 21. CRLF no FOCO.md nao pode desligar o corte por prioridade (Issue #74) =="
# O `priorizarFoco` separa blocos por LINHA EM BRANCO, e o split exige dois avancos
# de linha adjacentes. Em arquivo CRLF a linha em branco nao tem os dois adjacentes,
# entao a secao "## Ativo" inteira chega como UM bloco: nada cabe no teto e o foco
# degrada para "so ponteiros" em TODA sessao. Medido no FOCO.md real em 2026-08-25:
# 3 blocos com CRLF contra 9 com LF.
#
# Este caso compara os DOIS mundos com o MESMO conteudo — so o fim de linha muda.
# Comparar contra um numero fixo nao serviria: o resultado depende do teto, e o
# defeito nao e "saiu pequeno", e "saiu identico ao de um arquivo vazio".
FOCO_LF=$(printf '# Foco\n\n## Ativo\n\n**Projeto de Teste** `[trabalho]` — declarado 2026-08-01.\nCriterio de pronto: a bateria passar.\n\nMarcos:\n- Marco unico em 2026-09-01.\n')
FOCO_CRLF=$(printf '%s' "$FOCO_LF" | sed 's/$/\r/')

saida_lf=$(node -e '
const L=require(process.argv[1]);
const r=L.resumirFoco(process.argv[2]).trim();
console.log(JSON.stringify({blocos:r.split(/\n{2,}/).length, soPonteiro:L.focoSoTemPonteiro(L.priorizarFoco(r,250))}));
' "$LIB" "$FOCO_LF")
saida_crlf=$(node -e '
const L=require(process.argv[1]);
const r=L.resumirFoco(process.argv[2]).trim();
console.log(JSON.stringify({blocos:r.split(/\n{2,}/).length, soPonteiro:L.focoSoTemPonteiro(L.priorizarFoco(r,250))}));
' "$LIB" "$FOCO_CRLF")

checa "21.1 com LF o foco se divide em blocos"      nao_tem '"blocos":1' "$saida_lf"
checa "21.2 com CRLF divide igual ao LF"            tem     "$saida_lf"  "$saida_crlf"
# Nao existe um "21.3 com CRLF o foco nao vira so ponteiro". Ele foi escrito, passou
# limpo, e passou TAMBEM com a normalizacao removida — nao discriminava nada, e teste
# que fica verde com a protecao desligada e ruido que da falsa confianca. Quem carrega
# a prova aqui e o 21.2: com CRLF a divisao tem que dar o MESMO resultado que com LF.

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
