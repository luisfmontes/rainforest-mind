#!/bin/bash
# Bateria do scripts/atualizar-cli.sh. Nunca toca a instalacao real do Claude
# Code: a pasta do pacote e o executavel de atualizacao sao substituidos por
# variavel de ambiente (ATUALIZAR_CLI_PACOTE / ATUALIZAR_CLI_WINGET), e cada
# cenario aqui monta a sua propria arvore sintetica dentro de um unico
# `mktemp -d`, nunca na pasta real do WinGet. Bateria que rodasse o instalador
# de verdade ou renomeasse o executavel real reprovaria a tarefa inteira — por
# isso nenhuma linha deste arquivo chama o comando real de instalacao nem cita
# o caminho real do pacote.
#
# Armadilha ja registrada no briefing desta tarefa: o executavel de mentira
# precisa saber, em tempo de EXECUCAO, para qual pasta escrever o `claude.exe`
# novo — e essa pasta muda a cada cenario. Se o heredoc que grava esse
# executavel nao for citado (`<<'EOF'`), a variavel expande na hora em que o
# ARQUIVO E CRIADO, nao na hora em que ele RODA, e o mock nasce apontando para
# uma pasta que nem existe mais. Por isso o heredoc abaixo usa 'EOF' (citado) e
# o mock le a variavel do proprio ambiente quando e executado.
#
# Formato do executavel falso: sempre "N.N.N (Claude Code)", nunca so "N.N.N".
# E de proposito — a primeira entrega do atualizar-cli.sh so quebrou quando a
# versao veio nesse formato "sujo", e a bateria original dela usava o formato
# limpo e nunca viu o defeito. Aqui todo `claude.exe` de mentira, em todo
# cenario, sai no formato real.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALVO="$SRC/scripts/atualizar-cli.sh"

SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

# ------------------------------------------------------------- infraestrutura

CASOS_OK=0
CASOS_TOTAL=0
CASO_FALHOU=0
CASO_NOME=""

caso_inicio() {
  CASOS_TOTAL=$((CASOS_TOTAL + 1))
  CASO_NOME="$1"
  CASO_FALHOU=0
  echo
  echo "== caso $CASOS_TOTAL: $CASO_NOME =="
}

caso_fim() {
  if [ "$CASO_FALHOU" -eq 0 ]; then
    CASOS_OK=$((CASOS_OK + 1))
    echo "  -> caso OK"
  else
    echo "  -> caso FALHOU"
  fi
}

tem() {
  # nome, saida, trecho esperado
  if printf '%s' "$2" | grep -qF -- "$3"; then
    echo "  ok    $1"
  else
    echo "  FALHA $1 (esperava achar '$3', saida foi: $2)"
    CASO_FALHOU=1
  fi
}

nao_tem() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    echo "  FALHA $1 (achou '$3' e nao devia, saida foi: $2)"
    CASO_FALHOU=1
  else
    echo "  ok    $1"
  fi
}

igual() {
  # nome, valor obtido, valor esperado
  if [ "$2" = "$3" ]; then
    echo "  ok    $1"
  else
    echo "  FALHA $1 (esperava '$3', veio '$2')"
    CASO_FALHOU=1
  fi
}

# Executa o alvo com as variaveis dadas (formato VAR=val ...), guarda a saida
# combinada em $SAIDA e o exit code em $EXIT. Usa `env` para nao depender de
# `export` nem de subshell — as variaveis valem so para esta chamada.
rodar() {
  SAIDA="$(env "$@" bash "$ALVO" 2>&1)"
  EXIT=$?
}

# Monta uma pasta de pacote sintetica com um claude.exe falso que imprime a
# versao dada, sempre no formato real "N.N.N (Claude Code)".
novo_pacote() {
  local dir="$1" versao="$2"
  mkdir -p "$dir"
  printf '#!/bin/bash\necho "%s (Claude Code)"\n' "$versao" > "$dir/claude.exe"
  chmod +x "$dir/claude.exe"
}

contar_bak() {
  # `grep -c .` ja imprime 0 com entrada vazia — so sai com status 1 nesse
  # caso, e um `|| echo 0` depois disso DUPLICARIA a linha (imprimiria "0"
  # duas vezes). Por isso o resultado e capturado e so entao impresso.
  local n
  n="$(find "$1" -maxdepth 1 -name 'claude-*.exe.bak' -type f 2>/dev/null | grep -c .)"
  printf '%s' "$n"
}

# O executavel de "instalador" de mentira. Comportamento controlado por duas
# variaveis de ambiente lidas em tempo de execucao (herdadas do processo que
# chama o alvo, nunca expandidas na criacao deste arquivo):
#   MOCK_ATUALIZADOR_FALHA=1        -> sai 1 sem gravar nada (simula falha)
#   MOCK_ATUALIZADOR_VERSAO_NOVA=X  -> grava um claude.exe novo com versao X
# A pasta onde gravar vem de ATUALIZAR_CLI_PACOTE, a mesma variavel que o
# proprio scripts/atualizar-cli.sh usa e que este mock recebe herdada.
INSTALADOR_FALSO="$SBP/instalador-falso"
cat > "$INSTALADOR_FALSO" <<'EOF'
#!/bin/bash
if [ "${MOCK_ATUALIZADOR_FALHA:-0}" = "1" ]; then
  exit 1
fi
VERSAO="${MOCK_ATUALIZADOR_VERSAO_NOVA:-9.9.9}"
printf '#!/bin/bash\necho "%s (Claude Code)"\n' "$VERSAO" > "$ATUALIZAR_CLI_PACOTE/claude.exe"
chmod +x "$ATUALIZAR_CLI_PACOTE/claude.exe"
exit 0
EOF
chmod +x "$INSTALADOR_FALSO"

# ------------------------------------------------------------------- casos

# (a) feliz: o instalador falso grava versao nova, tudo sobe.
caso_inicio "feliz — versao sobe, um .bak so"
PACOTE="$SBP/caso-a/pacote"
novo_pacote "$PACOTE" "2.1.231"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=0 MOCK_ATUALIZADOR_VERSAO_NOVA=9.9.9
igual   "sai 0"                          "$EXIT" "0"
tem     "a saida cita a versao velha"    "$SAIDA" "2.1.231"
tem     "a saida cita a versao nova"     "$SAIDA" "9.9.9"
if [ -x "$PACOTE/claude.exe" ]; then
  echo "  ok    claude.exe existe na pasta"
  VNOVA="$("$PACOTE/claude.exe" --version 2>&1)"
  tem "e --version dele imprime a versao nova" "$VNOVA" "9.9.9"
else
  echo "  FALHA claude.exe nao existe na pasta"
  CASO_FALHOU=1
fi
igual "exatamente um .bak sobra" "$(contar_bak "$PACOTE")" "1"
BAK="$(find "$PACOTE" -maxdepth 1 -name 'claude-*.exe.bak' -type f 2>/dev/null | head -1)"
if [ -n "$BAK" ]; then
  igual "o .bak se chama claude-2.1.231.exe.bak" "$(basename "$BAK")" "claude-2.1.231.exe.bak"
  VBAK="$(bash "$BAK" --version 2>&1)"
  tem "e o .bak ainda imprime a versao velha" "$VBAK" "2.1.231"
fi
caso_fim

# (b) rollback: o instalador falso falha sem gravar nada.
caso_inicio "rollback — instalador falha, pasta volta ao estado original"
PACOTE="$SBP/caso-b/pacote"
novo_pacote "$PACOTE" "2.1.231"
cp "$PACOTE/claude.exe" "$SBP/caso-b/original.exe"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=1
[ "$EXIT" -ne 0 ] && echo "  ok    sai diferente de 0" || { echo "  FALHA sai 0 (esperava diferente de 0)"; CASO_FALHOU=1; }
if [ -f "$PACOTE/claude.exe" ]; then
  echo "  ok    claude.exe existe de volta"
  if diff -q "$SBP/caso-b/original.exe" "$PACOTE/claude.exe" >/dev/null 2>&1; then
    echo "  ok    conteudo identico ao original (diff)"
  else
    echo "  FALHA conteudo do claude.exe restaurado diverge do original"
    CASO_FALHOU=1
  fi
else
  echo "  FALHA claude.exe nao existe apos o rollback"
  CASO_FALHOU=1
fi
igual "zero .bak sobrando" "$(contar_bak "$PACOTE")" "0"
# O script tem um trap de emergencia (EXIT) que restaura o exe sozinho se ele
# sumir e o .bak existir — rede de seguranca para situacao ANORMAL, nao o
# caminho normal de erro tratado. Sem esta checagem, apagar o `mv` explicito
# do rollback controlado passa DESPERCEBIDO: o trap cobre a ausencia e o
# estado final da pasta fica identico, ainda que o rollback "de verdade" (o
# controlado, sem o texto "Emergencia") nunca tenha rodado. So o texto da
# saida distingue os dois caminhos.
nao_tem "o rollback controlado resolveu sozinho, sem cair no trap de emergencia" \
        "$SAIDA" "Emergencia"
caso_fim

# (c) rollback por versao que nao subiu: instalador grava a MESMA versao.
caso_inicio "rollback por versao igual — nao subiu, desfaz"
PACOTE="$SBP/caso-c/pacote"
novo_pacote "$PACOTE" "2.1.231"
cp "$PACOTE/claude.exe" "$SBP/caso-c/original.exe"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=0 MOCK_ATUALIZADOR_VERSAO_NOVA=2.1.231
[ "$EXIT" -ne 0 ] && echo "  ok    sai diferente de 0" || { echo "  FALHA sai 0 (esperava diferente de 0)"; CASO_FALHOU=1; }
if [ -f "$PACOTE/claude.exe" ] && diff -q "$SBP/caso-c/original.exe" "$PACOTE/claude.exe" >/dev/null 2>&1; then
  echo "  ok    claude.exe restaurado, conteudo identico ao original (diff)"
else
  echo "  FALHA claude.exe restaurado diverge do original (ou nao existe)"
  CASO_FALHOU=1
fi
igual "zero .bak sobrando" "$(contar_bak "$PACOTE")" "0"
nao_tem "o rollback controlado resolveu sozinho, sem cair no trap de emergencia" \
        "$SAIDA" "Emergencia"
caso_fim

# (d) poda: dois .bak antigos ja presentes antes da execucao feliz, so 1 sobra.
caso_inicio "poda — dois .bak antigos viram um so"
PACOTE="$SBP/caso-d/pacote"
novo_pacote "$PACOTE" "2.1.231"
printf '#!/bin/bash\necho "2.1.200 (Claude Code)"\n' > "$PACOTE/claude-2.1.200.exe.bak"
printf '#!/bin/bash\necho "2.1.210 (Claude Code)"\n' > "$PACOTE/claude-2.1.210.exe.bak"
igual "comeca com dois .bak" "$(contar_bak "$PACOTE")" "2"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=0 MOCK_ATUALIZADOR_VERSAO_NOVA=9.9.9
igual "sai 0" "$EXIT" "0"
igual "sobra exatamente um .bak" "$(contar_bak "$PACOTE")" "1"
nao_tem "o .bak de 2.1.200 nao sobrou (procurando na listagem)" \
        "$(find "$PACOTE" -maxdepth 1 -name 'claude-*.exe.bak' 2>/dev/null)" "2.1.200"
nao_tem "o .bak de 2.1.210 nao sobrou" \
        "$(find "$PACOTE" -maxdepth 1 -name 'claude-*.exe.bak' 2>/dev/null)" "2.1.210"
tem "o .bak que sobrou e o da versao que acabou de ser trocada (2.1.231)" \
    "$(find "$PACOTE" -maxdepth 1 -name 'claude-*.exe.bak' 2>/dev/null)" "2.1.231"
caso_fim

# (e) pasta inexistente: sai diferente de 0 sem tocar em nada.
caso_inicio "pasta inexistente — nao toca em nada"
PACOTE="$SBP/caso-e/nao-existe"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO"
[ "$EXIT" -ne 0 ] && echo "  ok    sai diferente de 0" || { echo "  FALHA sai 0 (esperava diferente de 0)"; CASO_FALHOU=1; }
if [ ! -e "$PACOTE" ]; then
  echo "  ok    a pasta continua nao existindo"
else
  echo "  FALHA a pasta foi criada, o script tocou nela"
  CASO_FALHOU=1
fi
tem "a saida avisa que a pasta nao existe" "$SAIDA" "nao existe"
caso_fim

# (f) ADVERSARIAL: instalador "sobe" para uma versao mais BAIXA (downgrade).
# Nenhum dos cinco cenarios do plano cobre este ramo: (c) testa igualdade, este
# aqui testa o outro lado da comparacao (nova menor que atual, nao so "nao
# maior"). Se version_subiu() em algum ramo tratar "nao subiu" so como "nao
# maior" sem cobrir corretamente o caso estritamente menor, este e o caso que
# pega.
caso_inicio "ADVERSARIAL — instalador grava versao mais baixa, rollback"
PACOTE="$SBP/caso-f/pacote"
novo_pacote "$PACOTE" "2.1.231"
cp "$PACOTE/claude.exe" "$SBP/caso-f/original.exe"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=0 MOCK_ATUALIZADOR_VERSAO_NOVA=2.1.100
[ "$EXIT" -ne 0 ] && echo "  ok    sai diferente de 0" || { echo "  FALHA sai 0 (esperava diferente de 0)"; CASO_FALHOU=1; }
if [ -f "$PACOTE/claude.exe" ] && diff -q "$SBP/caso-f/original.exe" "$PACOTE/claude.exe" >/dev/null 2>&1; then
  echo "  ok    claude.exe restaurado, conteudo identico ao original (diff)"
else
  echo "  FALHA claude.exe restaurado diverge do original (ou nao existe)"
  CASO_FALHOU=1
fi
igual "zero .bak sobrando" "$(contar_bak "$PACOTE")" "0"
nao_tem "o rollback controlado resolveu sozinho, sem cair no trap de emergencia" \
        "$SAIDA" "Emergencia"
caso_fim

# (g) ADVERSARIAL: fronteira numerica 2.1.9 -> 2.1.10. Se a comparacao de
# versao fosse textual em vez de numerica por componente (o mesmo bug que a
# tarefa 4 deste plano precisa evitar na barra), "2.1.10" perderia de "2.1.9"
# na comparacao de string ('1' < '9' na terceira posicao) e o script faria
# rollback de uma atualizacao que na verdade subiu. Aqui o esperado e SUCESSO.
caso_inicio "ADVERSARIAL — fronteira numerica 2.1.9 -> 2.1.10 nao pode virar rollback"
PACOTE="$SBP/caso-g/pacote"
novo_pacote "$PACOTE" "2.1.9"
rodar ATUALIZAR_CLI_PACOTE="$PACOTE" ATUALIZAR_CLI_WINGET="$INSTALADOR_FALSO" \
      MOCK_ATUALIZADOR_FALHA=0 MOCK_ATUALIZADOR_VERSAO_NOVA=2.1.10
igual "sai 0 (comparacao numerica, nao textual)" "$EXIT" "0"
tem   "a saida confirma o sucesso" "$SAIDA" "Sucesso"
igual "exatamente um .bak sobra" "$(contar_bak "$PACOTE")" "1"
caso_fim

# ------------------------------------------------------------------ resultado
echo
echo "-----------------------------------------"
echo "$CASOS_OK/$CASOS_TOTAL casos passaram"
[ "$CASOS_OK" -eq "$CASOS_TOTAL" ]
