#!/bin/bash
# Bateria do scripts/medir-injecao.py — os DOIS modos que o arquivo tem.
#
# Seções 1-6: --repartir, que REPARTE por fonte (skill_listing,
# deferred_tools_delta, agent_listing_delta, hook_additional_context) o custo
# real, em token medido pela API, do prompt de abertura de uma sessão.
#
# Seções 7-13: --entrega, que por hook de SessionStart compara o que foi
# ESCRITO (stdout) com o que CHEGOU ao modelo (content) e decide truncamento.
# Ficou sem rede (grep -rl -- "--entrega" scripts/*.sh hooks/*.sh voltava
# vazio) apesar de o próprio docstring do arquivo creditar este modo como "a
# tabela de 15 linhas que teria mostrado" o incidente de 50 de 50 sessões com
# payload cortado sem ninguém perceber — ver seção 7, que reproduz exatamente
# essa classe de defeito (emitido e chegou trocados de lugar).
#
# Nenhum gate cobria este arquivo (grep -rl "medir-injecao\|repartir" scripts/*.sh
# voltava vazio) e ele acumulou SEIS defeitos confirmados em duas rodadas de
# revisão. Esta bateria fecha essa lacuna. Cada seção abaixo:
#   1. monta uma fixture de transcript JSONL sintético em caixa de areia;
#   2. roda `python scripts/medir-injecao.py --repartir <fixture>` contra o
#      ORIGINAL e afirma o valor exato que o defeito, se reintroduzido, mudaria;
#   3. sabota uma CÓPIA do script (nunca o original) reintroduzindo aquele
#      defeito específico, roda a MESMA fixture contra a cópia, e mostra que o
#      valor medido se afasta do esperado — a prova de que a asserção pegaria.
#
# Os seis defeitos:
#   1. fatia rainforest-mind dos agentes zerada por nome derivado errado
#      (line[2:].split(":")[0] sempre devolve "rainforest-mind").
#   2. hook_additional_context nunca lido (branch do att_type não bate).
#   3. a linha "nao atribuido" é ESTIMADA (byte convertido de volta a partir do
#      token) e tem que vir marcada com "~" — sem a marca, parece medida.
#   4. byte de uma linha da tabela casado com token de OUTRA linha.
#   5. total_tokens do primeiro SessionStart, fontes vindas do último — a
#      distinção entre medir a ABERTURA e medir um RESUME.
#   6. hook_additional_context.content é uma LISTA; conteúdo de outro plugin
#      (ex.: claude-mem) não pode entrar na fatia rainforest-mind.
#
# Mais uma amarração (roda contra o HOOK REAL, não fixture): o RAINFOREST_MARKER
# que o script usa para reconhecer "qual item da lista é nosso" tem que continuar
# batendo com a primeira linha que `node hooks/foco-session-start.cjs` emite.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ALVO="$SRC/scripts/medir-injecao.py"

ok=0; falhou=0; pulou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# extratores de campo da tabela do --repartir. Formato de cada linha de fonte:
#   "{nome:28s} {bytes:>9,d} {tokens:>9,.0f}"  -> awk splita por espaço; o rótulo
# pode ter espaços dentro (ex. "dos quais rainforest-mind"), então os dois
# ÚLTIMOS campos são sempre bytes e tokens, não importa quantas palavras o rótulo tem.
campo()        { echo "$1" | grep -F -- "$2" | head -1 | awk '{print $(NF-1)}' | tr -d ','; }
campo_bruto()  { echo "$1" | grep -F -- "$2" | head -1 | awk '{print $(NF-1)}'; }
campo_tokens() { echo "$1" | grep -F -- "$2" | head -1 | awk '{print $NF}'     | tr -d ','; }
# "atribuido" é substring de "nao atribuido" — grep -F comum pegaria a linha errada.
campo_atrib_bytes()  { echo "$1" | grep -E '^atribuido[[:space:]]' | head -1 | awk '{print $(NF-1)}' | tr -d ','; }
campo_atrib_tokens() { echo "$1" | grep -E '^atribuido[[:space:]]' | head -1 | awk '{print $NF}'     | tr -d ','; }

# afirma que bytes/3.11 ~= tokens da MESMA linha (tolerância 1, por causa do
# arredondamento ",.0f" do print). É a asserção do defeito 4.
bate_token() {
  local rotulo="$1" bytes="$2" tokens="$3" esperado diff
  esperado="$(python -c "print(round($bytes/3.11))" 2>/dev/null)"
  diff=$(( tokens - esperado )); diff=${diff#-}
  if [ "$diff" -le 1 ]; then
    ok=$((ok+1)); echo "  ok   $rotulo: ${bytes} B casa com ${tokens} tokens~ (esperado ~$esperado)"
  else
    falhou=$((falhou+1)); echo "  FALHA $rotulo: ${bytes} B NAO casa com ${tokens} tokens~ (esperado ~$esperado, diff $diff)"
  fi
}

# meta-asserções da perna vermelha: o valor sob mutação tem que DIVERGIR do
# valor correto medido contra o original. Divergir é o mutante "detectado".
mutante_detectado_num() {
  local rotulo="$1" correto="$2" sabotado="$3"
  if [ "$correto" != "$sabotado" ]; then
    ok=$((ok+1)); echo "  ok   mutante detectado — $rotulo (original: $correto | sabotado: $sabotado)"
  else
    falhou=$((falhou+1)); echo "  FALHA mutante NAO detectado — $rotulo continuou $sabotado mesmo sabotado"
  fi
}
mutante_detectado_se() {
  # $1 rotulo, $2 = "1" quando o sintoma do bug apareceu no output sabotado
  if [ "$2" = "1" ]; then ok=$((ok+1)); echo "  ok   mutante detectado — $1"; else falhou=$((falhou+1)); echo "  FALHA mutante NAO detectado — $1"; fi
}

# sabota uma linha específica (1-indexed) de uma CÓPIA do script, por
# substituição de trecho DENTRO da linha (confere a âncora antes de trocar, e
# copia do original só na primeira chamada — chamadas seguintes acumulam no
# mesmo arquivo mutante).
sabotar_linha() {
  local n="$1" achar="$2" trocar="$3" alvo="$4"
  if [ ! -f "$alvo" ]; then cp "$ALVO" "$alvo"; fi
  N="$n" ACHAR="$achar" TROCAR="$trocar" ALVO_PY="$alvo" python3 <<'PY'
import os
n = int(os.environ["N"]) - 1
achar = os.environ["ACHAR"]
trocar = os.environ["TROCAR"]
alvo = os.environ["ALVO_PY"]
with open(alvo, encoding="utf-8") as f:
    linhas = f.readlines()
if achar not in linhas[n]:
    raise SystemExit(f"ANCORA NAO BATE na linha {n+1}: esperava achar {achar!r}, linha era {linhas[n]!r}")
linhas[n] = linhas[n].replace(achar, trocar, 1)
with open(alvo, "w", encoding="utf-8") as f:
    f.writelines(linhas)
print(f"  (sabotagem: linha {n+1}: {achar!r} -> {trocar!r})")
PY
}

# sabota um INTERVALO de linhas (1-indexed, inclusive), substituindo o bloco
# inteiro pelo texto lido do stdin (heredoc do chamador).
sabotar_bloco() {
  local ini="$1" fim="$2" ancora="$3" alvo="$4"
  local novo; novo="$(cat)"
  if [ ! -f "$alvo" ]; then cp "$ALVO" "$alvo"; fi
  INI="$ini" FIM="$fim" ANCORA="$ancora" NOVO="$novo" ALVO_PY="$alvo" python3 <<'PY'
import os
ini = int(os.environ["INI"]) - 1
fim = int(os.environ["FIM"])
ancora = os.environ["ANCORA"]
novo = os.environ["NOVO"]
alvo = os.environ["ALVO_PY"]
with open(alvo, encoding="utf-8") as f:
    linhas = f.readlines()
bloco = "".join(linhas[ini:fim])
if ancora not in bloco:
    raise SystemExit(f"ANCORA NAO BATE nas linhas {ini+1}-{fim}: esperava achar {ancora!r}, bloco era {bloco!r}")
linhas[ini:fim] = [l + "\n" for l in novo.split("\n")]
with open(alvo, "w", encoding="utf-8") as f:
    f.writelines(linhas)
print(f"  (sabotagem: linhas {ini+1}-{fim} -> {novo!r})")
PY
}

rodar() { python "$ALVO" --repartir "$1" 2>&1; }
rodar_mutante() { python "$1" --repartir "$2" 2>&1; }

# =========================================================================
echo; echo "0. o marcador bate com o hook REAL (nao fixture)"
# O RAINFOREST_MARKER que o repartir() usa para reconhecer "qual item da lista
# é nosso" é lido do PRÓPRIO medir-injecao.py, não digitado aqui de novo — o
# que se afirma é que ele ainda bate com o que o hook de verdade emite hoje.
MARCADOR="$(ALVO_PY="$ALVO" python3 <<'PY'
import os, re
t = open(os.environ["ALVO_PY"], encoding="utf-8").read()
m = re.search(r'RAINFOREST_MARKER = "(.*)"', t)
print(m.group(1) if m else "")
PY
)"
if [ -z "$MARCADOR" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao encontrei RAINFOREST_MARKER em medir-injecao.py"
else
  CONTEXTO_HOOK="$(cd "$SRC" && node hooks/foco-session-start.cjs 2>&1 | node -e '
    let data = "";
    process.stdin.on("data", (c) => (data += c));
    process.stdin.on("end", () => {
      try {
        const j = JSON.parse(data);
        process.stdout.write(String(j.hookSpecificOutput.additionalContext).slice(0, 80));
      } catch (e) {
        process.stdout.write("ERRO_PARSE: " + e.message);
      }
    });
  ')"
  case "$CONTEXTO_HOOK" in
    "$MARCADOR"*) ok=$((ok+1)); echo "  ok   marcador '$MARCADOR' bate com o inicio do que o hook real emite" ;;
    *) falhou=$((falhou+1)); echo "  FALHA marcador '$MARCADOR' NAO bate — hook real comeca com: '${CONTEXTO_HOOK:0:60}'" ;;
  esac
fi

# =========================================================================
echo; echo "1. fatia rainforest-mind dos AGENTES nao pode zerar nem vazar de outro plugin"
AG1_ID="rainforest-mind:executor"
AG1_DESC="Agente padrao de execucao"
AG2_ID="rainforest-mind:revisor"
AG2_DESC="Agente de revisao"
OUT_ID="outro-plugin:tarefa"
OUT_DESC="Agente de outro plugin nao relacionado"
LINE1="- ${AG1_ID}: ${AG1_DESC}"
LINE2="- ${OUT_ID}: ${OUT_DESC}"
LINE3="- ${AG2_ID}: ${AG2_DESC}"
RF_BYTES_1="$(printf '%s\n%s' "$LINE1" "$LINE3" | wc -c)"

FX1="$SBP/1-agentes.jsonl"
LINES_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$LINE1" "$LINE2" "$LINE3")"
TYPES_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$AG1_ID" "$OUT_ID" "$AG2_ID")"
FIX_PATH="$FX1" LINES_JSON="$LINES_JSON" TYPES_JSON="$TYPES_JSON" python3 <<'PY'
import json, os
lines = json.loads(os.environ["LINES_JSON"])
types = json.loads(os.environ["TYPES_JSON"])
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"message": {"usage": {"input_tokens": 20000, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}}}) + "\n")
    f.write(json.dumps({"attachment": {"type": "agent_listing_delta", "addedLines": lines, "addedTypes": types}}) + "\n")
PY

SAIDA1="$(rodar "$FX1")"
FATIA1="$(campo "$SAIDA1" 'dos quais rainforest-mind')"
igual "fatia rainforest dos agentes bate exatamente (so os dois nossos, sem o de outro plugin)" "$FATIA1" "$RF_BYTES_1"

echo "  -- mutacao 1a: reintroduz split(\":\")[0] (bug medido: fatia sempre 0 B)"
MUT1A="$SBP/mut-1a.py"
sabotar_linha 244 '.split(": ", 1)' '.split(":")' "$MUT1A"
SAIDA1A="$(rodar_mutante "$MUT1A" "$FX1")"
FATIA1A="$(campo "$SAIDA1A" 'dos quais rainforest-mind')"
echo "  saida do mutante (linha da fatia): $(echo "$SAIDA1A" | grep -F 'dos quais rainforest-mind')"
mutante_detectado_num "fatia zera com split(\":\")[0]" "$RF_BYTES_1" "$FATIA1A"

echo "  -- mutacao 1b: comparacao sempre verdadeira (bug: fatia passa a incluir outro plugin)"
MUT1B="$SBP/mut-1b.py"
sabotar_linha 246 'if identifier in rainforest_types:' 'if True:' "$MUT1B"
SAIDA1B="$(rodar_mutante "$MUT1B" "$FX1")"
FATIA1B="$(campo "$SAIDA1B" 'dos quais rainforest-mind')"
echo "  saida do mutante (linha da fatia): $(echo "$SAIDA1B" | grep -F 'dos quais rainforest-mind')"
mutante_detectado_num "fatia infla incluindo linha de outro plugin" "$RF_BYTES_1" "$FATIA1B"

# =========================================================================
echo; echo "2, 3 e 4. hook_additional_context lido, 'nao atribuido' marcada, byte casado com token da mesma linha"
FX_GERAL="$SBP/geral.jsonl"
FIX_PATH="$FX_GERAL" python3 <<'PY'
import json, os
skill = 'k' * 700
deferred = 'l' * 250
agent = 'm' * 1300
hook = 'n' * 450
with open(os.environ["FIX_PATH"], 'w', encoding='utf-8') as f:
    f.write(json.dumps({'message': {'usage': {'input_tokens': 50000, 'cache_read_input_tokens': 0, 'cache_creation_input_tokens': 0}}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'skill_listing', 'content': skill, 'names': []}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'deferred_tools_delta', 'addedLines': [deferred]}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'agent_listing_delta', 'addedLines': [agent], 'addedTypes': []}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'hook_additional_context', 'content': hook}}) + "\n")
PY
SAIDA_G="$(rodar "$FX_GERAL")"

echo "-- defeito 2: hook_additional_context tem que ser lido"
HOOK_BYTES="$(campo "$SAIDA_G" 'hook_additional_context')"
igual "hook_additional_context mediu exatamente os 450 B da fixture" "$HOOK_BYTES" "450"

echo "-- defeito 3: 'nao atribuido' tem que vir marcada com ~"
NAOATR_BRUTO="$(campo_bruto "$SAIDA_G" 'nao atribuido')"
case "$NAOATR_BRUTO" in
  "~"*) ok=$((ok+1)); echo "  ok   'nao atribuido' vem marcada com ~ ($NAOATR_BRUTO)" ;;
  *) falhou=$((falhou+1)); echo "  FALHA 'nao atribuido' SEM marca de estimativa ($NAOATR_BRUTO)" ;;
esac

echo "-- defeito 4: byte de cada linha casa com token DA MESMA linha (exceto 'nao atribuido' e TOTAL)"
for rotulo in "skill_listing" "deferred_tools_delta" "agent_listing_delta" "hook_additional_context"; do
  B="$(campo "$SAIDA_G" "$rotulo")"; T="$(campo_tokens "$SAIDA_G" "$rotulo")"
  bate_token "$rotulo" "$B" "$T"
done
AB="$(campo_atrib_bytes "$SAIDA_G")"; AT="$(campo_atrib_tokens "$SAIDA_G")"
bate_token "atribuido" "$AB" "$AT"
RB="$(campo "$SAIDA_G" 'dos quais rainforest-mind')"; RT="$(campo_tokens "$SAIDA_G" 'dos quais rainforest-mind')"
bate_token "dos quais rainforest-mind" "$RB" "$RT"

echo "  -- mutacao 2: desliga o branch do att_type hook_additional_context"
MUT2="$SBP/mut-2.py"
sabotar_linha 257 '"hook_additional_context"' '"hook_additional_context_DESLIGADO"' "$MUT2"
SAIDA2M="$(rodar_mutante "$MUT2" "$FX_GERAL")"
HOOK_BYTES_M="$(campo "$SAIDA2M" 'hook_additional_context')"
echo "  saida do mutante (linha do hook): $(echo "$SAIDA2M" | grep -F 'hook_additional_context')"
mutante_detectado_num "hook_additional_context deixa de ser lido" "450" "${HOOK_BYTES_M:-0}"

echo "  -- mutacao 3: remove a marca ~ de 'nao atribuido'"
MUT3="$SBP/mut-3.py"
sabotar_linha 314 "'~' + f'{nao_atribuido_bytes_estimado:,d}'" "f'{nao_atribuido_bytes_estimado:,d}'" "$MUT3"
SAIDA3M="$(rodar_mutante "$MUT3" "$FX_GERAL")"
NAOATR_BRUTO_M="$(campo_bruto "$SAIDA3M" 'nao atribuido')"
echo "  saida do mutante (linha nao atribuido): $(echo "$SAIDA3M" | grep -F 'nao atribuido')"
case "$NAOATR_BRUTO_M" in
  "~"*) mutante_detectado_se "marca ~ removida de 'nao atribuido'" "0" ;;
  *) mutante_detectado_se "marca ~ removida de 'nao atribuido'" "1" ;;
esac

echo "  -- mutacao 4: token da linha usa sempre o byte do skill_listing (copia-e-cola)"
MUT4="$SBP/mut-4.py"
sabotar_linha 309 'b / BYTES_POR_TOKEN' 'skill_listing_bytes / BYTES_POR_TOKEN' "$MUT4"
SAIDA4M="$(rodar_mutante "$MUT4" "$FX_GERAL")"
echo "  saida do mutante (linhas da tabela):"
echo "$SAIDA4M" | grep -E 'skill_listing|deferred_tools_delta|agent_listing_delta|hook_additional_context' | sed 's/^/    /'
T4="$(campo_tokens "$SAIDA4M" 'hook_additional_context')"
ESPERADO4="$(python -c 'print(round(450/3.11))')"
mutante_detectado_num "token de hook_additional_context casado com o byte de outra linha" "$ESPERADO4" "$T4"

# =========================================================================
echo; echo "5. total_tokens do PRIMEIRO SessionStart, fontes do MESMO primeiro (nao do ultimo)"
FX5="$SBP/5-duplo.jsonl"
FIX_PATH="$FX5" python3 <<'PY'
import json, os
skill1 = 'p' * 600
hook1 = 'q' * 300
skill2 = 'r' * 2000
hook2 = 's' * 900
with open(os.environ["FIX_PATH"], 'w', encoding='utf-8') as f:
    # primeiro SessionStart
    f.write(json.dumps({'message': {'usage': {'input_tokens': 12345, 'cache_read_input_tokens': 0, 'cache_creation_input_tokens': 0}}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'skill_listing', 'content': skill1, 'names': []}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'hook_additional_context', 'content': hook1}}) + "\n")
    # segundo SessionStart (ex.: resume) — total e fontes BEM diferentes, de proposito
    f.write(json.dumps({'message': {'usage': {'input_tokens': 99999, 'cache_read_input_tokens': 0, 'cache_creation_input_tokens': 0}}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'skill_listing', 'content': skill2, 'names': []}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'hook_additional_context', 'content': hook2}}) + "\n")
PY
SAIDA5="$(rodar "$FX5")"
TOTAL5="$(campo_tokens "$SAIDA5" 'TOTAL DA ABERTURA')"
SKILL5="$(campo "$SAIDA5" 'skill_listing')"
HOOK5="$(campo "$SAIDA5" 'hook_additional_context')"
igual "TOTAL DA ABERTURA e do PRIMEIRO SessionStart (12345), nao do segundo (99999)" "$TOTAL5" "12345"
igual "skill_listing e do PRIMEIRO bloco (600 B), nao do segundo (2000 B)" "$SKILL5" "600"
igual "hook_additional_context e do PRIMEIRO bloco (300 B), nao do segundo (900 B)" "$HOOK5" "300"

echo "  -- mutacao 5: guardas 'so a primeira ocorrencia' viram 'sempre sobrescreve' (fontes passam a vir do ultimo)"
MUT5="$SBP/mut-5.py"
sabotar_linha 185 '_bytes == 0:' '_bytes >= 0:' "$MUT5"
sabotar_linha 219 '_bytes == 0:' '_bytes >= 0:' "$MUT5"
sabotar_linha 226 '_bytes == 0:' '_bytes >= 0:' "$MUT5"
sabotar_linha 259 '_bytes == 0:' '_bytes >= 0:' "$MUT5"
SAIDA5M="$(rodar_mutante "$MUT5" "$FX5")"
echo "  saida do mutante:"
echo "$SAIDA5M" | grep -E 'skill_listing|hook_additional_context|TOTAL DA ABERTURA' | sed 's/^/    /'
TOTAL5M="$(campo_tokens "$SAIDA5M" 'TOTAL DA ABERTURA')"
SKILL5M="$(campo "$SAIDA5M" 'skill_listing')"
# invariante: o total NAO deve mudar com esta sabotagem (ela so afeta as fontes) —
# se mudasse, a fixture estaria testando outra coisa, nao o defeito 5.
igual "total continua do primeiro mesmo sabotado (a sabotagem so afeta as fontes)" "$TOTAL5M" "12345"
mutante_detectado_num "skill_listing passa a vir do ULTIMO bloco (2000), nao do primeiro (600)" "600" "$SKILL5M"

# =========================================================================
echo; echo "6. hook_additional_context.content e LISTA — conteudo de outro plugin nao pode contar como nosso"
MARCADOR_6="${MARCADOR:-RAINFOREST MIND ATIVO}"
FX6="$SBP/6-conteudo.jsonl"
FIX_PATH="$FX6" MARCADOR_ENV="$MARCADOR_6" python3 <<'PY'
import json, os
marcador = os.environ["MARCADOR_ENV"]
item_a = marcador + 'a' * (500 - len(marcador.encode('utf-8')))
item_b = '# [rainforest-mind] recent context' + 'b' * (300 - len('# [rainforest-mind] recent context'.encode('utf-8')))
with open(os.environ["FIX_PATH"], 'w', encoding='utf-8') as f:
    f.write(json.dumps({'message': {'usage': {'input_tokens': 20000, 'cache_read_input_tokens': 0, 'cache_creation_input_tokens': 0}}}) + "\n")
    f.write(json.dumps({'attachment': {'type': 'hook_additional_context', 'content': [item_a, item_b]}}) + "\n")
PY
SAIDA6="$(rodar "$FX6")"
HOOK6="$(campo "$SAIDA6" 'hook_additional_context')"
FATIA6="$(campo "$SAIDA6" 'dos quais rainforest-mind')"
igual "hook_additional_context soma os DOIS itens da lista (500+300+1 separador)" "$HOOK6" "801"
igual "fatia rainforest-mind leva SO o item nosso (500 B), nao o do claude-mem (300 B)" "$FATIA6" "500"

echo "  -- mutacao 6: fatia rainforest passa a ser o total do attachment (conta o item do outro plugin como nosso)"
MUT6="$SBP/mut-6.py"
sabotar_bloco 273 276 'for item in content_raw' "$MUT6" <<'NOVOBLOCO'
                        hook_additional_context_rainforest_bytes = hook_additional_context_bytes
NOVOBLOCO
SAIDA6M="$(rodar_mutante "$MUT6" "$FX6")"
FATIA6M="$(campo "$SAIDA6M" 'dos quais rainforest-mind')"
echo "  saida do mutante (linha da fatia): $(echo "$SAIDA6M" | grep -F 'dos quais rainforest-mind')"
mutante_detectado_num "fatia passa a incluir o item do claude-mem" "500" "$FATIA6M"

# =========================================================================
# --entrega: a metade do arquivo sem rede (grep -rl -- "--entrega" scripts/*.sh
# hooks/*.sh volta vazio). entregas()/relatar_entrega() leem, por hook de
# SessionStart, o par (stdout emitido, content que chegou) e decidem se houve
# truncamento — via marcador <persisted-output> OU via 0 < chegou < emitido.
# Mesmo padrao das secoes 1-6: fixture em caixa de areia, roda contra o
# ORIGINAL, sabota uma COPIA, roda a MESMA fixture na copia, mostra que o
# valor diverge.
#   7. emitido e chegou nao podem inverter (a sabotagem que motivou este
#      trabalho: linhas 121-122 trocadas de lugar).
#   8. truncamento pelo marcador <persisted-output>, mesmo com chegou > emitido.
#   9. truncamento por tamanho (0 < chegou < emitido), sem marcador.
#  10. NAO truncado quando chegou == emitido, sem marcador (pega inversao de
#      sinal na comparacao: < virando <=).
#  11. hook que nao e SessionStart fica de fora da tabela.
#  12. dedup por (command, emitido, chegou).
#  13. a varredura por forma (_varrer) desce em profundidade arbitraria.
#  14. (achado 9, rodada de revisao) hookEvent real NUNCA traz sufixo — o
#      sufixo (":startup"/":clear"/":resume") mora em hookName. As fixtures
#      acima foram corrigidas para essa forma; esta secao ancora contra
#      TRANSCRIPT REAL de ~/.claude/projects/ para a fixture nao poder
#      divergir da realidade de novo em silencio.
#  15. (achado 10, rodada de revisao) campo_entrega() nao pode corromper
#      numero grande so porque ele estoura a largura nominal da coluna.

rodar_entrega() { python "$ALVO" --entrega "$1" 2>&1; }
rodar_entrega_mutante() { python "$1" --entrega "$2" 2>&1; }
# extrai a linha da tabela de --entrega que contem o nome do hook.
linha_entrega() { printf '%s\n' "$1" | grep -F -- "$2" | head -1; }
# quando(20) e hook(28) sao SEMPRE largura fixa por construcao da propria
# producao (timestamp tem tamanho fixo; nome do hook e truncado em [:28] antes
# de imprimir) — fatiar por indice ali e seguro. emitido/chegou NAO sao: sao
# numeros formatados com ">8,d"/">8s", que o Python nunca TRUNCA quando o
# valor e mais largo que 8 (ex.: "1,200,000" tem 9 caracteres) — so estica o
# campo. Fatiar aquilo por indice fixo (achado 10) desloca tudo que vem depois
# e corrompe o numero em silencio. A partir do fim do campo hook (posicao 50)
# o resto da linha e tokenizado por espaco com limite 3: os tres primeiros
# tokens (emitido, chegou, pcts) nunca tem espaco dentro; o quarto pedaco é
# "estado" inteiro, que PODE ter espaco dentro ("sem corte") — por isso o
# maxsplit para exatamente ai e nao mais.
campo_entrega() {
  LINHA="$1" CAMPO="$2" python3 <<'PY'
import os
linha = os.environ["LINHA"]
campo = os.environ["CAMPO"]
resto = linha[50:].split(None, 3)
while len(resto) < 4:
    resto.append("")
emitido, chegou, pcts, estado = resto
vals = {
    "quando": linha[0:20].strip(),
    "hook": linha[21:49].strip(),
    "emitido": emitido.replace(",", ""),
    "chegou": chegou.replace(",", ""),
    "pcts": pcts,
    "estado": estado,
}
print(vals.get(campo, ""))
PY
}

# =========================================================================
echo; echo "7. emitido e chegou NAO PODEM INVERTER (a sabotagem que motivou este trabalho)"
FX7="$SBP/7-inversao.jsonl"
FIX_PATH="$FX7" python3 <<'PY'
import json, os
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:00Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:startup", "stdout": "A" * 12, "content": "B" * 7,
        "command": "node hooks/inversao-emitido-chegou.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA7="$(rodar_entrega "$FX7")"
LINHA7="$(linha_entrega "$SAIDA7" "inversao-emitido-chegou.cjs")"
EMITIDO7="$(campo_entrega "$LINHA7" emitido)"
CHEGOU7="$(campo_entrega "$LINHA7" chegou)"
igual "emitido mede o STDOUT (12 chars), nao o content" "$EMITIDO7" "12"
igual "chegou mede o CONTENT (7 chars), nao o stdout" "$CHEGOU7" "7"

echo "  -- mutacao 7: linhas 121-122 trocadas de lugar (emitido <-> chegou)"
MUT7="$SBP/mut-7.py"
sabotar_bloco 121 122 'emitido = len(h.get("stdout") or "")' "$MUT7" <<'NOVOBLOCO'
                chegou = len(h.get("stdout") or "")
                emitido = len(h.get("content") or "")
NOVOBLOCO
SAIDA7M="$(rodar_entrega_mutante "$MUT7" "$FX7")"
LINHA7M="$(linha_entrega "$SAIDA7M" "inversao-emitido-chegou.cjs")"
EMITIDO7M="$(campo_entrega "$LINHA7M" emitido)"
echo "  saida do mutante (linha do hook): $LINHA7M"
mutante_detectado_num "emitido passa a valer o tamanho do content, nao do stdout" "12" "$EMITIDO7M"

# =========================================================================
echo; echo "8. truncamento pelo MARCADOR <persisted-output>, mesmo com chegou > emitido"
FX8="$SBP/8-marcador.jsonl"
FIX_PATH="$FX8" python3 <<'PY'
import json, os
content = "<persisted-output>" + "D" * 60
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:01Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:clear", "stdout": "C" * 10, "content": content,
        "command": "node hooks/marcador-conteudo-maior.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA8="$(rodar_entrega "$FX8")"
LINHA8="$(linha_entrega "$SAIDA8" "marcador-conteudo-maior.cjs")"
ESTADO8="$(campo_entrega "$LINHA8" estado)"
igual "marcador presente -> TRUNCADO mesmo com chegou (79) > emitido (10)" "$ESTADO8" "TRUNCADO"

echo "  -- mutacao 8: 'truncado' deixa de considerar o marcador, so o tamanho"
MUT8="$SBP/mut-8.py"
sabotar_linha 137 '"truncado": marcado or (0 < chegou < emitido),' '"truncado": (0 < chegou < emitido),' "$MUT8"
SAIDA8M="$(rodar_entrega_mutante "$MUT8" "$FX8")"
LINHA8M="$(linha_entrega "$SAIDA8M" "marcador-conteudo-maior.cjs")"
ESTADO8M="$(campo_entrega "$LINHA8M" estado)"
echo "  saida do mutante (linha do hook): $LINHA8M"
mutante_detectado_num "marcador ignorado -> deixa de ser TRUNCADO" "TRUNCADO" "$ESTADO8M"

# =========================================================================
echo; echo "9. truncamento POR TAMANHO (0 < chegou < emitido), sem marcador"
FX9="$SBP/9-tamanho.jsonl"
FIX_PATH="$FX9" python3 <<'PY'
import json, os
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:02Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:resume", "stdout": "E" * 10, "content": "F" * 4,
        "command": "node hooks/truncado-por-tamanho.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA9="$(rodar_entrega "$FX9")"
LINHA9="$(linha_entrega "$SAIDA9" "truncado-por-tamanho.cjs")"
ESTADO9="$(campo_entrega "$LINHA9" estado)"
igual "sem marcador, chegou (4) < emitido (10) -> TRUNCADO" "$ESTADO9" "TRUNCADO"

echo "  -- mutacao 9: 'truncado' deixa de considerar o tamanho, so o marcador"
MUT9="$SBP/mut-9.py"
sabotar_linha 137 '"truncado": marcado or (0 < chegou < emitido),' '"truncado": marcado,' "$MUT9"
SAIDA9M="$(rodar_entrega_mutante "$MUT9" "$FX9")"
LINHA9M="$(linha_entrega "$SAIDA9M" "truncado-por-tamanho.cjs")"
ESTADO9M="$(campo_entrega "$LINHA9M" estado)"
echo "  saida do mutante (linha do hook): $LINHA9M"
mutante_detectado_num "tamanho ignorado -> deixa de ser TRUNCADO" "TRUNCADO" "$ESTADO9M"

# =========================================================================
echo; echo "10. NAO truncado quando chegou == emitido, sem marcador (pega inversao de sinal)"
FX10="$SBP/10-igual.jsonl"
FIX_PATH="$FX10" python3 <<'PY'
import json, os
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:03Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:startup", "stdout": "G" * 10, "content": "H" * 10,
        "command": "node hooks/nao-truncado-igual.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA10="$(rodar_entrega "$FX10")"
LINHA10="$(linha_entrega "$SAIDA10" "nao-truncado-igual.cjs")"
ESTADO10="$(campo_entrega "$LINHA10" estado)"
igual "chegou == emitido (10 == 10), sem marcador -> sem corte" "$ESTADO10" "sem corte"

echo "  -- mutacao 10: '<' vira '<=' (sinal da comparacao invertido na fronteira)"
MUT10="$SBP/mut-10.py"
sabotar_linha 137 '(0 < chegou < emitido)' '(0 < chegou <= emitido)' "$MUT10"
SAIDA10M="$(rodar_entrega_mutante "$MUT10" "$FX10")"
LINHA10M="$(linha_entrega "$SAIDA10M" "nao-truncado-igual.cjs")"
ESTADO10M="$(campo_entrega "$LINHA10M" estado)"
echo "  saida do mutante (linha do hook): $LINHA10M"
mutante_detectado_num "igualdade passa a contar como TRUNCADO" "sem corte" "$ESTADO10M"

# =========================================================================
echo; echo "11. hook que NAO E SessionStart fica de fora da tabela"
FX11="$SBP/11-filtro.jsonl"
FIX_PATH="$FX11" python3 <<'PY'
import json, os
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:04Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:clear", "stdout": "I" * 10, "content": "I" * 10,
        "command": "node hooks/controle-session-start.cjs", "exitCode": 0}]}}) + "\n")
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:05Z", "toolUseResult": {"hooks": [{
        "hookEvent": "PreToolUse", "stdout": "J" * 10, "content": "J" * 2,
        "command": "node hooks/ignorar-pretooluse.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA11="$(rodar_entrega "$FX11")"
tem "hook SessionStart aparece na tabela" "$SAIDA11" "controle-session-start.cjs"
nao_tem "hook PreToolUse NAO aparece na tabela" "$SAIDA11" "ignorar-pretooluse.cjs"

echo "  -- mutacao 11: filtro perde o 'not' (passa a excluir SessionStart e deixar passar o resto)"
MUT11="$SBP/mut-11.py"
sabotar_linha 119 'if not str(h.get("hookEvent", "")).startswith("SessionStart"):' 'if str(h.get("hookEvent", "")).startswith("SessionStart"):' "$MUT11"
SAIDA11M="$(rodar_entrega_mutante "$MUT11" "$FX11")"
echo "  saida do mutante:"
echo "$SAIDA11M" | grep -E 'controle-session-start|ignorar-pretooluse|entrega\(s\)' | sed 's/^/    /'
case "$SAIDA11M" in
  *ignorar-pretooluse.cjs*) mutante_detectado_se "hook PreToolUse passa a aparecer na tabela" "1" ;;
  *) mutante_detectado_se "hook PreToolUse passa a aparecer na tabela" "0" ;;
esac

# =========================================================================
echo; echo "12. DEDUPLICACAO por (command, emitido, chegou)"
FX12="$SBP/12-dedup.jsonl"
FIX_PATH="$FX12" python3 <<'PY'
import json, os
registro = {"hookEvent": "SessionStart", "hookName": "SessionStart:resume", "stdout": "K" * 10, "content": "K" * 2,
            "command": "node hooks/duplicado.cjs", "exitCode": 0}
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:06Z", "toolUseResult": {"hooks": [registro]}}) + "\n")
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:07Z", "toolUseResult": {"hooks": [registro]}}) + "\n")
PY
SAIDA12="$(rodar_entrega "$FX12")"
CONT12="$(printf '%s\n' "$SAIDA12" | grep -c -F -- 'duplicado.cjs')"
igual "dois registros identicos (mesmo command/emitido/chegou) viram UMA linha" "$CONT12" "1"
QTD12="$(printf '%s\n' "$SAIDA12" | grep -oE '^[0-9]+ entrega\(s\)' | grep -oE '^[0-9]+')"
igual "contagem total tambem reflete o dedup (1 entrega, nao 2)" "$QTD12" "1"

echo "  -- mutacao 12: chave de dedup passa a incluir o timestamp (nunca mais colide)"
MUT12="$SBP/mut-12.py"
sabotar_linha 127 'chave = (h.get("command"), emitido, chegou)' 'chave = (h.get("command"), emitido, chegou, quando)' "$MUT12"
SAIDA12M="$(rodar_entrega_mutante "$MUT12" "$FX12")"
CONT12M="$(printf '%s\n' "$SAIDA12M" | grep -c -F -- 'duplicado.cjs')"
echo "  saida do mutante: $(printf '%s\n' "$SAIDA12M" | grep -c -F -- 'duplicado.cjs') linha(s) de 'duplicado.cjs'"
mutante_detectado_num "dedup quebrada -> duas linhas em vez de uma" "1" "$CONT12M"

# =========================================================================
echo; echo "13. a varredura por forma (_varrer) desce em PROFUNDIDADE ARBITRARIA"
FX13="$SBP/13-profundo.jsonl"
FIX_PATH="$FX13" python3 <<'PY'
import json, os
# hook enterrado 4 niveis abaixo, dentro de dict->dict->list->dict — nenhum
# caminho fixo, so a FORMA (hookEvent + stdout) identifica o registro.
fundo = {"hookEvent": "SessionStart", "hookName": "SessionStart:startup", "stdout": "L" * 10, "content": "L" * 2,
         "command": "node hooks/profundo-de-verdade.cjs", "exitCode": 0}
estrutura = {"timestamp": "2026-01-01T10:00:08Z",
             "nivel1": {"nivel2": {"nivel3": [{"nivel4": fundo}]}}}
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps(estrutura) + "\n")
PY
SAIDA13="$(rodar_entrega "$FX13")"
tem "hook enterrado 4 niveis abaixo e encontrado pela varredura por forma" "$SAIDA13" "profundo-de-verdade.cjs"

echo "  -- mutacao 13: _varrer para de descer em dict (so olha o nivel de cima)"
MUT13="$SBP/mut-13.py"
sabotar_linha 98 'for v in no.values():' 'for v in []:' "$MUT13"
SAIDA13M="$(rodar_entrega_mutante "$MUT13" "$FX13")"
echo "  saida do mutante: $(echo "$SAIDA13M" | head -3 | tr '\n' ' ')"
case "$SAIDA13M" in
  *profundo-de-verdade.cjs*) mutante_detectado_se "hook enterrado deixa de ser encontrado" "0" ;;
  *) mutante_detectado_se "hook enterrado deixa de ser encontrado" "1" ;;
esac

# =========================================================================
echo; echo "14. ANCORAGEM contra transcript REAL (nao fixture): hookEvent nunca traz sufixo"
# Achado 9 (revisao): as fixtures das secoes 7-13 escreviam
# "hookEvent": "SessionStart:startup" — forma que NUNCA ocorre em producao.
# hookEvent so assume PostToolUse/Stop/SessionStart/PreToolUse/UserPromptSubmit,
# sempre SEM sufixo; o sufixo (":startup"/":clear"/":resume") mora em hookName.
# Corrigimos as fixtures acima; esta secao AMARRA essa forma contra dado real,
# para a fixture nao poder divergir da realidade de novo em silencio — mesmo
# proposito da secao 0, que roda contra o hook real em vez de reafirmar uma
# constante digitada aqui.
#
# Degrada com honestidade: maquina sem transcript nenhum nao falha nem passa
# calada — conta em "pulou", visivel no relatorio final, nunca em ok/falhou
# (o estado da maquina de quem roda o teste nao pode fazer o gate oscilar).
RAIZ_TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
RESULTADO14="$(RAIZ="$RAIZ_TRANSCRIPTS" python3 <<'PY'
import json, os
from pathlib import Path

raiz = Path(os.environ["RAIZ"])
arquivos = list(raiz.glob("**/*.jsonl")) if raiz.is_dir() else []

total_hookevent = 0
com_dois_pontos = set()
sessionstart_sem_sufixo = 0
sufixos_vistos = set()

def varrer(no):
    # Mesma FORMA que o _varrer() de medir-injecao.py usa para reconhecer um
    # registro de hook de verdade: hookEvent E stdout juntos no mesmo dict —
    # nao so hookEvent (que tambem aparece solto em objetos que nao sao
    # execucao de hook, e conta ruido que nao existe do ponto de vista do
    # script que estamos ancorando).
    global total_hookevent, sessionstart_sem_sufixo
    if isinstance(no, dict):
        if "hookEvent" in no and "stdout" in no:
            total_hookevent += 1
            he = str(no.get("hookEvent", ""))
            if ":" in he:
                com_dois_pontos.add(he)
            if he == "SessionStart":
                hn = str(no.get("hookName", ""))
                if ":" in hn:
                    sufixos_vistos.add(hn.split(":", 1)[1])
                else:
                    sessionstart_sem_sufixo += 1
        for v in no.values():
            varrer(v)
    elif isinstance(no, list):
        for v in no:
            varrer(v)

for arq in arquivos:
    try:
        with arq.open(encoding="utf-8", errors="replace") as f:
            for linha in f:
                try:
                    d = json.loads(linha)
                except json.JSONDecodeError:
                    continue
                varrer(d)
    except OSError:
        continue

print(f"ARQUIVOS={len(arquivos)}")
print(f"TOTAL_HOOKEVENT={total_hookevent}")
print(f"COM_DOIS_PONTOS={len(com_dois_pontos)}")
print(f"COM_DOIS_PONTOS_VALORES={sorted(com_dois_pontos)}")
print(f"SESSIONSTART_SEM_SUFIXO={sessionstart_sem_sufixo}")
print(f"SUFIXOS_VISTOS={sorted(sufixos_vistos)}")
PY
)"
echo "$RESULTADO14" | sed 's/^/  /'
val14() { echo "$RESULTADO14" | grep "^$1=" | head -1 | cut -d= -f2-; }
ARQUIVOS14="$(val14 ARQUIVOS)"
TOTAL14="$(val14 TOTAL_HOOKEVENT)"
if [ "${ARQUIVOS14:-0}" -eq 0 ] || [ "${TOTAL14:-0}" -eq 0 ]; then
  pulou=$((pulou+1))
  echo "  PULADA — sem dado de producao em $RAIZ_TRANSCRIPTS (nenhum registro de hook achado). Isto NAO conta como ok nem como falha."
else
  COM_DOIS_PONTOS14="$(val14 COM_DOIS_PONTOS)"
  SEM_SUFIXO14="$(val14 SESSIONSTART_SEM_SUFIXO)"
  echo "  (amostra: $TOTAL14 registros de hookEvent em $ARQUIVOS14 transcript(s) reais)"

  # Esta ancora AVISA, nao reprova — de proposito, e a diferenca importa.
  #
  # Ela le `~/.claude/projects/` inteiro, ou seja, transcript de TODOS os
  # projetos da maquina, nao so deste repo. Isso e o que da forca a ela: 26 mil
  # registros dizem mais sobre a forma real do harness do que qualquer fixture.
  # Mas e tambem o que a tornaria um gate que quebra sozinho: um transcript de
  # outro projeto, de outra versao do Claude Code, ou importado de outra
  # maquina, faria a suite DESTE repo falhar por motivo sem relacao nenhuma com
  # o codigo que alguem esta tentando integrar. E o CONTRIBUTING.md:11 pede a
  # suite inteira verde antes de abrir PR.
  #
  # Reproduzido em 2026-08-14 na revisao da rodada 5: um .jsonl sintetico com
  # `"hookEvent": "SessionStart:startup"` sob um CLAUDE_CONFIG_DIR de teste
  # levou a bateria a 45 ok / 1 falha, exit 1. Nos dados reais da maquina
  # (26.008 registros, 895 arquivos, varios projetos) a contagem e zero.
  #
  # Entao ela avisa alto e nao reprova. Divergencia aqui nao significa "o codigo
  # esta errado" — significa "a forma do harness mudou, va conferir as fixtures".
  # Isso e informacao para um humano, nao veredito sobre um diff.
  if [ "${COM_DOIS_PONTOS14:-0}" != "0" ] || [ "${SEM_SUFIXO14:-0}" != "0" ]; then
    echo "  AVISO — a forma real do transcript DIVERGIU da que as fixtures assumem:"
    echo "     hookEvent contendo ':' ......... $COM_DOIS_PONTOS14  $(val14 COM_DOIS_PONTOS_VALORES)"
    echo "     SessionStart sem sufixo ........ $SEM_SUFIXO14"
    echo "     As fixtures das secoes 7-13 podem ter envelhecido. Isto NAO reprova"
    echo "     esta bateria: a divergencia pode vir de transcript de OUTRO projeto"
    echo "     ou de outra versao do harness, e nao do codigo sob teste."
  else
    igual "forma real do transcript continua batendo com a das fixtures ($TOTAL14 registros)" "$COM_DOIS_PONTOS14:$SEM_SUFIXO14" "0:0"
  fi
fi

# =========================================================================
echo; echo "15. campo_entrega() NAO CORROMPE numero grande que estoura a largura nominal (achado 10)"
FX15="$SBP/15-numero-grande.jsonl"
FIX_PATH="$FX15" python3 <<'PY'
import json, os
with open(os.environ["FIX_PATH"], "w", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": "2026-01-01T10:00:09Z", "toolUseResult": {"hooks": [{
        "hookEvent": "SessionStart", "hookName": "SessionStart:startup",
        "stdout": "M" * 1200000, "content": "N" * 500000,
        "command": "node hooks/numero-grande.cjs", "exitCode": 0}]}}) + "\n")
PY
SAIDA15="$(rodar_entrega "$FX15")"
LINHA15="$(linha_entrega "$SAIDA15" "numero-grande.cjs")"
echo "  linha real da tabela: $LINHA15"
EMITIDO15="$(campo_entrega "$LINHA15" emitido)"
CHEGOU15="$(campo_entrega "$LINHA15" chegou)"
igual "emitido de 1.200.000 (9 digitos com virgula) nao corrompe, extrai 1200000 inteiro" "$EMITIDO15" "1200000"
igual "chegou de 500.000 (7 digitos com virgula) nao corrompe, extrai 500000 inteiro" "$CHEGOU15" "500000"

echo "  -- mutacao 15: volta ao fatiamento por indice fixo (achado 10 original)"
mutacao_campo_entrega_fixo() {
  LINHA="$1" CAMPO="$2" python3 <<'PY'
import os
linha = os.environ["LINHA"]
campo = os.environ["CAMPO"]
vals = {
    "emitido": linha[50:58].strip().replace(",", ""),
    "chegou": linha[59:67].strip().replace(",", ""),
}
print(vals.get(campo, ""))
PY
}
EMITIDO15M="$(mutacao_campo_entrega_fixo "$LINHA15" emitido)"
echo "  saida da extracao sabotada (fatiamento fixo): emitido='$EMITIDO15M'"
mutante_detectado_num "extracao por indice fixo corrompe o numero grande" "1200000" "$EMITIDO15M"

# =========================================================================
echo; echo "guarda final — o original nao pode ter sido tocado"
GITSTATUS="$(cd "$SRC" && git status --porcelain -- scripts/medir-injecao.py)"
igual "scripts/medir-injecao.py continua intocado" "$GITSTATUS" ""

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou   pulou: $pulou"
[ "$falhou" -eq 0 ] || exit 1
