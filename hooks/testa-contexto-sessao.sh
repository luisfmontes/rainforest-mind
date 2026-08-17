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
RFM_ROOT="$SRC_WIN" node "$SRC/hooks/foco-session-start.cjs" > "$RAIZ_POSIX/saida-hook.json" 2>/dev/null
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
console.log(`ok ${Buffer.byteLength(c, 'utf8')} ${lib.TETOS.ORCAMENTO_BYTES} ${regras} ${travou}`);
EOF
LEITURA="$(LIB_PATH="$LIB" SAIDA="$RAIZ_POSIX/saida-hook.json" node "$RAIZ_POSIX/checa-hook.cjs")"
FORMATO="$(echo "$LEITURA" | cut -d' ' -f1)"
BYTES="$(echo "$LEITURA" | cut -d' ' -f2)"
TETO="$(echo "$LEITURA" | cut -d' ' -f3)"
NREGRAS="$(echo "$LEITURA" | cut -d' ' -f4)"
TRAVOU="$(echo "$LEITURA" | cut -d' ' -f5)"

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

if [ -n "$BYTES_N" ] && [ "$BYTES_N" -le "$TETO_N" ] 2>/dev/null; then
  ok=$((ok+1)); echo "  ok    os nucleos cabem na catraca ($BYTES_N B <= $TETO_N B, folga $((TETO_N-BYTES_N)) B)"
else
  falhou=$((falhou+1)); echo "  FALHA os nucleos passaram da catraca ($BYTES_N B > $TETO_N B)"
  echo "         cada byte aqui e um byte a menos de FOCO.md em TODA sessao."
  echo "         pague por subtracao noutro nucleo, ou suba NUCLEOS_MAX_BYTES de proposito."
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
checa "cabecalho explica a seta"           tem     "Skill(rainforest-mind)"         "$S"
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
const agora = 1786000000000;   // epoch real: timestamp negativo vira 0 no Math.max e o fixture mente
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
const agora = 1786000000000;
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
const agora = 1786000000000;
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
SEM_DEP="$(ctx_hook -u WHATSAPP_API_BASE_URL "RFM_ROOT=$SRC_WIN" "CLAUDE_CONFIG_DIR=$CAIXA_DEP" "RFM_SETTINGS_PATH=$CAIXA_DEP/settings.json")"
checa "sem declaracao, nao ha bloco de dependencias" nao_tem "Dependências de ambiente" "$SEM_DEP"
checa "sem declaracao, nao fala de bridge"           nao_tem "bridge WhatsApp"           "$SEM_DEP"
checa "sem declaracao, nao fala de claude-mem"       nao_tem "claude-mem"                "$SEM_DEP"
checa "e as regras continuam chegando"               tem     "**17."                     "$SEM_DEP"

# Declarada e apontando para porta morta: o bloco volta, e volta dizendo FORA.
# Porta alta e improvavel de propósito — o teste nao pode depender do que a
# maquina tem de pe.
COM_DEP="$(ctx_hook "WHATSAPP_API_BASE_URL=http://127.0.0.1:59421" "RFM_ROOT=$SRC_WIN" "CLAUDE_CONFIG_DIR=$CAIXA_DEP" "RFM_SETTINGS_PATH=$CAIXA_DEP/settings.json")"
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
const agora = 1786000000000;
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

# Dado completo, condicao nenhuma satisfeita: nem veredito nem anuncio. Os DOIS
# saem vazios juntos tambem conta como "nunca saem juntos" — string vazia nao
# afirma nada, nem cobranca nem isencao.
S="$(veredito "$FOCO_COM_PASTAS" '[]' "$CONFIG_EXPEDIENTE" "$AGORA_SEG")"
if [ -z "$S" ]; then
  ok=$((ok+1)); echo "  ok    computarVeredito: dado completo sem condicao satisfeita devolve string vazia"
else
  falhou=$((falhou+1)); echo "  FALHA computarVeredito esperava vazio (dado completo, sem condicao), veio: '$S'"
fi

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
echo "17.1 MUTACOES — as quatro sabotagens do briefing, cada uma tem que quebrar a asserção correspondente"
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
S_MUT1="$(expediente '2026,8,10,10,0' '{}' "$RAIZ_POSIX/lib-mut-expediente.cjs")"
echo "  (saida do mutante: $S_MUT1 — a assercao real espera 'null')"
( checa "dentroDoExpediente: sem expediente no config devolve null (nao false)" tem "null" "$S_MUT1" )
if [ "$S_MUT1" != "null" ]; then
  ok=$((ok+1)); echo "  ok    mutacao expos o colapso null->false (D6 inteiro depende disso)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — null->false nao e o que a assercao mede"
fi

echo "  -- SABOTAGEM 2: focoAtivoEmOutraJanela compara caminho com includes (substring) em vez de igualdade"
cp "$LIB" "$RAIZ_POSIX/lib-mut-includes.cjs"
sed -i 's/cwdNormalizado === pasta/cwdNormalizado.includes(pasta)/' "$RAIZ_POSIX/lib-mut-includes.cjs"
S_MUT2="$(outra_janela "[{\"cwd\":\"C:/abc\",\"prompt_ts\":$((AGORA_FIXO-1000))}]" '["C:/a"]' 15 "$AGORA_FIXO" "$RAIZ_POSIX/lib-mut-includes.cjs")"
echo "  (saida do mutante: $S_MUT2 — a assercao real espera 'false')"
( checa "focoAtivoEmOutraJanela: C:/abc nao casa C:/a por prefixo" tem "false" "$S_MUT2" )
if [ "$S_MUT2" = "true" ]; then
  ok=$((ok+1)); echo "  ok    mutacao expos o casamento por prefixo (C:/abc passou a isentar contra C:/a)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — includes() nao e o que a assercao mede"
fi

echo "  -- SABOTAGEM 3: focoAtivoEmOutraJanela usa stop_ts em vez de prompt_ts como sinal humano"
cp "$LIB" "$RAIZ_POSIX/lib-mut-stopts.cjs"
sed -i 's/const { cwd, prompt_ts } = sessao;/const { cwd, stop_ts: prompt_ts } = sessao;/' "$RAIZ_POSIX/lib-mut-stopts.cjs"
FIX_STOP="[{\"cwd\":\"C:/a\",\"prompt_ts\":$((AGORA_FIXO - 999999999)),\"stop_ts\":$((AGORA_FIXO-1000))}]"
S_MUT3="$(outra_janela "$FIX_STOP" '["C:/a"]' 15 "$AGORA_FIXO" "$RAIZ_POSIX/lib-mut-stopts.cjs")"
echo "  (saida do mutante: $S_MUT3 — a assercao real espera 'false')"
( checa "focoAtivoEmOutraJanela: prompt_ts frio e o que conta, nao stop_ts" tem "false" "$S_MUT3" )
if [ "$S_MUT3" = "true" ]; then
  ok=$((ok+1)); echo "  ok    mutacao expos a troca prompt_ts->stop_ts (sinal errado passou a isentar)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — a troca de campo nao e o que a assercao mede"
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

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
