#!/bin/bash
# Bateria do scripts/ponte.cjs — a ponte que leva as regras para Codex e Gemini CLI.
# Uso: bash scripts/testa-ponte.sh
#
# O que importa aqui nao e o texto gerado, e sim as tres promessas que ele faz:
#   1. e DERIVADO do SKILL.md (regenerar nao duplica, e SKILL.md quebrado nao gera)
#   2. nao apaga o que outra pessoa escreveu no arquivo
#   3. nao vaza caminho de home num arquivo que vai ser commitado por terceiro
# O bloco 5 e o de MUTACAO: sabota o SKILL.md e exige a recusa. Sem ele, os outros
# provariam so que o caminho feliz funciona (regra 12).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Copia do PLUGIN, para o bloco de mutacao poder sabotar o SKILL.md sem tocar no
# repo. A ponte resolve o proprio caminho por __dirname, entao a arvore precisa ter
# a mesma forma.
PLUG="$CAIXA/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/hooks/lib" "$PLUG/skills/rainforest-mind"
cp "$SRC/scripts/ponte.cjs" "$PLUG/scripts/"
cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs"    "$SRC/hooks/lib/projetos.cjs" "$PLUG/hooks/lib/"
cp "$SRC/scripts/setup.cjs" "$PLUG/scripts/"
cp "$SRC/skills/rainforest-mind/SKILL.md" "$PLUG/skills/rainforest-mind/"
# Pasta de DADOS propria: e nela que o /setup grava as chaves `ponte-*`, e e por
# elas que a ponte decide o default. Nada aqui toca a configuracao real.
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
SETUP="node $PLUG/scripts/setup.cjs"
PONTE="node $PLUG/scripts/ponte.cjs"
ALVO="$CAIXA/repo-de-outra-pessoa"
mkdir -p "$ALVO"
ALVO_WIN="$(cygpath -m "$ALVO" 2>/dev/null || printf '%s' "$ALVO")"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
prova() { # nome, comando de teste (bash -c)
  local nome="$1"; shift
  if bash -c "$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== 0. sem alvo declarado, a ponte RECUSA em vez de gerar os tres =="
# O default saiu de "todos" para "o que o /setup declarou": gerar arquivo em
# repositorio de terceiro nao e coisa que se faca por omissao.
esperado "recusa quando nada esta declarado" 1 $PONTE --alvo "$ALVO_WIN"
contem "  ... e ensina a ligar no setup" "setup.cjs --ligar ponte-" $PONTE --alvo "$ALVO_WIN"
prova "nao criou arquivo nenhum" "[ ! -e '$ALVO/AGENTS.md' ] && [ ! -e '$ALVO/CLAUDE.md' ] && [ ! -e '$ALVO/GEMINI.md' ]"
esperado "mas --agente explicito passa sem declaracao" 0 $PONTE --alvo "$ALVO_WIN" --agente codex
# Declara dois dos tres: e isso que a ponte tem que usar quando ninguem passa --agente.
esperado "declarar ponte-codex no setup" 0 $SETUP --ligar ponte-codex --escopo usuario
esperado "declarar ponte-gemini no setup" 0 $SETUP --ligar ponte-gemini --escopo usuario
contem "o setup MOSTRA as pontes ligadas" "PONTES" $SETUP
contem "  ... nomeando cada arquivo gerado" "AGENTS.md" $SETUP

echo
echo "== 1. ensaio nao grava =="
esperado "ensaio roda" 0 $PONTE --alvo "$ALVO_WIN"
prova "nenhum arquivo criado pelo ensaio" "[ ! -e '$ALVO/AGENTS.md' ] && [ ! -e '$ALVO/GEMINI.md' ]"

echo
echo "== 2. --aplicar escreve os DECLARADOS, com marcador =="
esperado "aplicar" 0 $PONTE --alvo "$ALVO_WIN" --aplicar
prova "AGENTS.md existe"  "[ -s '$ALVO/AGENTS.md' ]"
prova "GEMINI.md existe"  "[ -s '$ALVO/GEMINI.md' ]"
prova "marcador de inicio e fim presentes" "grep -q 'rainforest-mind:inicio' '$ALVO/AGENTS.md' && grep -q 'rainforest-mind:fim' '$ALVO/AGENTS.md'"
prova "as 17 regras chegam"                "grep -q '\*\*17\.' '$ALVO/AGENTS.md'"
prova "o nucleo vem marcado com a seta"    "grep -q '↳' '$ALVO/AGENTS.md'"
prova "diz o que NAO atravessa (PreToolUse)" "grep -q 'PreToolUse' '$ALVO/AGENTS.md'"
prova "aponta o gate que ATRAVESSA (exit 2)" "grep -q 'estado.cjs exigir' '$ALVO/AGENTS.md'"
prova "aponta a checagem da regra 12"        "grep -q 'conferir-entrega.cjs' '$ALVO/AGENTS.md'"
prova "cada arquivo se nomeia pelo agente certo" "grep -q 'Codex' '$ALVO/AGENTS.md' && grep -q 'Gemini' '$ALVO/GEMINI.md'"
# Tabela markdown: `|` dentro de code span quebra a celula. Toda linha da tabela
# tem que ter exatamente 2 separadores + as bordas.
# Linha bem formada de tabela (`| a | b |`) tem 4 campos com -F'|': vazio, a, b,
# vazio. Um `|` a mais dentro de code span vira 5, e a celula quebra na renderizacao.
prova "nenhuma celula da tabela quebrada por pipe" \
  "[ \$(grep -c '^| .node' '$ALVO/AGENTS.md') -gt 5 ] && [ \$(grep '^| .node' '$ALVO/AGENTS.md' | awk -F'|' 'NF!=4' | wc -l) -eq 0 ]"

echo
# O terceiro alvo: Claude Code SEM o plugin. Nao e redundante — quem nao instalou
# nao tem regra nenhuma —, e o texto sobre trava tem que ser DIFERENTE: ali a razao
# nao e "o host nao tem PreToolUse", e "o plugin nao esta instalado".
esperado "gera o CLAUDE.md quando pedido" 0 $PONTE --alvo "$ALVO_WIN" --agente claude --aplicar
prova "CLAUDE.md existe" "[ -s '$ALVO/CLAUDE.md' ]"
prova "e explica a falta de trava pelo PLUGIN, nao pelo host"   "grep -q 'sem o plugin instalado' '$ALVO/CLAUDE.md' && ! grep -q 'nao existe. neste host' '$ALVO/CLAUDE.md'"
prova "e o AGENTS.md continua explicando pelo HOST"   "grep -q 'neste host' '$ALVO/AGENTS.md'"
prova "GEMINI.md nao virou CLAUDE.md (cada alvo tem seu arquivo)"   "grep -q 'Gemini' '$ALVO/GEMINI.md' && grep -q 'Claude Code' '$ALVO/CLAUDE.md'"

echo
echo "== 3. NAO vaza caminho de home (o arquivo vai ser commitado por terceiro) =="
prova "sem C:\\Users no gerado"   "! grep -qi 'c:.users' '$ALVO/AGENTS.md'"
prova "sem /home/ no gerado"      "! grep -q '/home/' '$ALVO/AGENTS.md'"
prova "sem .rainforest chumbado"  "! grep -q '\.rainforest' '$ALVO/AGENTS.md'"
prova "mas ENSINA a descobrir"    "grep -q 'ideias.cjs conferir' '$ALVO/AGENTS.md'"

echo
echo "== 4. regenerar substitui o bloco, e o que e de outra pessoa fica =="
BYTES1=$(wc -c < "$ALVO/AGENTS.md")
$PONTE --alvo "$ALVO_WIN" --agente codex --aplicar >/dev/null 2>&1
BYTES2=$(wc -c < "$ALVO/AGENTS.md")
prova "regenerar nao duplica (mesmo tamanho)" "[ '$BYTES1' = '$BYTES2' ]"
prova "so um marcador de inicio"              "[ \$(grep -c 'rainforest-mind:inicio' '$ALVO/AGENTS.md') = 1 ]"

# Arquivo que JA existia, escrito a mao, sem marcador nenhum: nada dele pode sumir.
printf 'CONVENCOES DO MEU REPO\n\nUse pnpm, nunca npm.\n' > "$ALVO/GEMINI.md"
md5_mao=$(md5sum < "$ALVO/GEMINI.md" | cut -d' ' -f1)
esperado "aplicar sobre arquivo escrito a mao" 0 $PONTE --alvo "$ALVO_WIN" --agente gemini --aplicar
prova "o texto da outra pessoa continua la" "grep -q 'Use pnpm, nunca npm' '$ALVO/GEMINI.md'"
prova "e o bloco entrou depois dele"        "grep -q 'rainforest-mind:inicio' '$ALVO/GEMINI.md'"
prova "a linha dela vem ANTES do marcador"  \
  "[ \$(grep -n 'pnpm' '$ALVO/GEMINI.md' | cut -d: -f1) -lt \$(grep -n 'rainforest-mind:inicio' '$ALVO/GEMINI.md' | cut -d: -f1) ]"
# E na segunda passada, com marcador presente, o texto dela AINDA fica.
$PONTE --alvo "$ALVO_WIN" --agente gemini --aplicar >/dev/null 2>&1
prova "segunda passada preserva o texto dela" "grep -q 'Use pnpm, nunca npm' '$ALVO/GEMINI.md'"
prova "e continua com um marcador so"         "[ \$(grep -c 'rainforest-mind:inicio' '$ALVO/GEMINI.md') = 1 ]"
# Texto DEPOIS do bloco tambem sobrevive (o caso que a fatia ingenua apagaria).
printf '\nRODAPE QUE E MEU\n' >> "$ALVO/GEMINI.md"
$PONTE --alvo "$ALVO_WIN" --agente gemini --aplicar >/dev/null 2>&1
prova "texto depois do bloco sobrevive"       "grep -q 'RODAPE QUE E MEU' '$ALVO/GEMINI.md'"

echo
echo "== 5. MUTACAO — SKILL.md quebrado nao gera ponte pela metade =="
cp "$PLUG/skills/rainforest-mind/SKILL.md" "$CAIXA/SKILL.bak"
printf '# SKILL sem a secao\n\nnada aqui.\n' > "$PLUG/skills/rainforest-mind/SKILL.md"
ALVO2="$CAIXA/alvo-mutante"; mkdir -p "$ALVO2"
esperado "recusa quando nao acha as regras" 1 $PONTE --alvo "$(cygpath -m "$ALVO2" 2>/dev/null || printf '%s' "$ALVO2")" --aplicar
prova "e nao gravou nada"                   "[ ! -e '$ALVO2/AGENTS.md' ]"
# Meia secao tambem reprova: e o piso de caracteres que segura, nao a existencia.
{ echo '## As regras'; echo; echo '**1. Uma regra so.**'; echo; echo '## Comandos'; } > "$PLUG/skills/rainforest-mind/SKILL.md"
esperado "recusa com regra de menos (piso de caracteres)" 1 $PONTE --alvo "$(cygpath -m "$ALVO2" 2>/dev/null || printf '%s' "$ALVO2")" --aplicar
cp "$CAIXA/SKILL.bak" "$PLUG/skills/rainforest-mind/SKILL.md"
esperado "com o SKILL.md de volta, gera" 0 $PONTE --alvo "$(cygpath -m "$ALVO2" 2>/dev/null || printf '%s' "$ALVO2")" --aplicar

echo
echo "== 6. bordas =="
esperado "--alvo inexistente"   1 $PONTE --alvo "$CAIXA/nao-existe" --aplicar
esperado "--alvo que e arquivo" 1 $PONTE --alvo "$ALVO_WIN/AGENTS.md" --aplicar
esperado "--agente desconhecido" 1 $PONTE --alvo "$ALVO_WIN" --agente copilot
esperado "sem --alvo"            1 $PONTE

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
