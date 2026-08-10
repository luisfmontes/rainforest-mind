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
# Secao nao-residente sai da injecao, mas SAI NOMEADA: o nome no ponteiro e o que
# separa omissao recuperavel de omissao silenciosa. As duas checagens andam juntas
# de proposito — so a primeira passaria com o corte mudo que originou tudo isto.
checa "secao nao-residente sai do texto"   nao_tem "conteudo-fora-de-escopo"     "$S"
checa "ponteiro nomeia a secao omitida"    tem     "Fora de escopo"              "$S"

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
# A data sai do FOCO.md AGORA, nao de uma constante: a versao anterior fixava
# "2026-08-08" e ficou vermelha sozinha no primeiro avanco novo. Teste que quebra
# quando o arquivo evolui normalmente vira teste que se aprende a ignorar.
ULTIMO_AVANCO="$(awk '/^## /{dentro=($0=="## Ativo")} dentro' "$SRC/FOCO.md" \
  | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9-]{10}' | sort | tail -1)"
checa "avanco mais recente sobrevive"      tem     "Último avanço datado: $ULTIMO_AVANCO" "$S"
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
checa "estado e o da janela mais recente"  tem     "esperando o Luís há 40 min"  "$S"
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
checa "corte de pasta se anuncia"          tem     "pastas omitidas desta injeção" "$S"
checa "a pasta mais recente sobrevive"     tem     "pasta-numero-0"                "$S"
checa "a mais fria e a que sai"            nao_tem "pasta-numero-19 —"             "$S"

# Mutacao: com o teto em 99MB o corte para de acontecer. Sem isto, "cabe no teto"
# passaria verde num bloco que nunca chega perto do limite.
cp "$LIB" "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs"
sed -i 's/SESSOES_MAX_BYTES: [0-9]*/SESSOES_MAX_BYTES: 99999999/' "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs"
S="$(sessoes "$MUITAS" "$RAIZ_POSIX/lib-sem-teto-sessoes.cjs")"
if echo "$S" | grep -qF "pastas omitidas desta injeção"; then
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

# O hook de verdade, com stdin de verdade: o evento "end" tem de apagar a linha.
HB_RAIZ="$RAIZ_POSIX/hb"
mkdir -p "$HB_RAIZ"
HB_WIN="$(cygpath -m "$HB_RAIZ" 2>/dev/null || printf '%s' "$HB_RAIZ")"
printf '{"session_id":"s1","cwd":"C:/a"}' | RFM_ROOT="$HB_WIN" node "$SRC/hooks/heartbeat.cjs" prompt
DEPOIS_PROMPT="$(cat "$HB_RAIZ/sessoes.json" 2>/dev/null)"
printf '{"session_id":"s1","cwd":"C:/a"}' | RFM_ROOT="$HB_WIN" node "$SRC/hooks/heartbeat.cjs" end
DEPOIS_END="$(cat "$HB_RAIZ/sessoes.json" 2>/dev/null)"
checa "heartbeat grava a sessao"           tem     '"s1"'                       "$DEPOIS_PROMPT"
checa "heartbeat grava o pid"              tem     '"pid"'                      "$DEPOIS_PROMPT"
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
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
