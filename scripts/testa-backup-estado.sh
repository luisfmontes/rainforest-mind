#!/bin/bash
# Bateria do vigias/backup-estado.ps1 — o backup do sentinela.
#
# Ela EXECUTA o arquivo real, nao o le. A primeira tentativa desta bateria
# (2026-08-26, Issue #118) fabricava uma copia do bloco numa caixa e rodava a
# copia: com `git push origin main` reintroduzido no arquivo de verdade ela saia
# `9 ok, 0 falha(s)`. Bateria que nao executa o artefato certifica um arquivo que
# nunca leu.
#
# O que ela cobre, e por que cada um:
#   1. Nenhum commit nasce, em raiz nenhuma — e as caixas TEM commit antes, senao
#      `git log` falha nas duas pontas e a comparacao passa por vazio. Foi assim
#      que a primeira versao ficou verde: `fatal: your current branch 'master'
#      does not have any commits yet` dos dois lados.
#   2. Nenhum push e tentado — a remota e uma pasta local, e o bare e conferido.
#   3. Falha de backup FALA: uma linha no ERROS.md, no formato do run-vigia.ps1.
#   4. `-Teste` nao escreve backup nenhum.
#   5. O caminho feliz cria a copia de verdade.
#
# INCIDENTE N1 (2026-09-03/04): esta bateria gravou rainforest-2026-09-03.zip e
# rainforest-2026-09-04.zip no %OneDrive%\rainforest-backup REAL do usuario (14
# bytes de FOCO.md de caixa cada, achados e removidos manualmente pela janela).
# Causa: rodar()/rodar_sem_rfm_root()/rodar_capturando() isolavam RFM_ROOT,
# USERPROFILE e HOME, mas nunca RFM_BACKUP_DESTINO nem OneDrive/ONEDRIVE - e o
# resolverDestino de scripts/backup.cjs cai em env.OneDrive quando
# RFM_BACKUP_DESTINO esta vazia. Conserto: toda chamada ao backup-estado.ps1
# nesta bateria agora passa RFM_BACKUP_DESTINO para uma pasta de mktemp -d e
# roda com `env -u OneDrive -u ONEDRIVE`; uma trava (verificar_destino_seguro,
# abaixo) aborta a bateria inteira se algum call site deixar de isolar; e o
# caso 18 confere, ao final, que nada novo apareceu no OneDrive de verdade.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }

command -v powershell >/dev/null 2>&1 || { echo "FALHA powershell nao esta no PATH — esta bateria nao significaria nada"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FALHA node nao esta no PATH"; exit 1; }

win() { cygpath -w "$1"; }

# --- trava anti-OneDrive-real (N1, 2026-09-03/04) -------------------------
# Toda invocacao do backup-estado.ps1 nesta bateria chama esta funcao logo
# antes de montar o comando, com o RFM_BACKUP_DESTINO de caixa que vai usar (ou
# vazio, se algum call site regredir e deixar de isolar). DECISAO: a trava
# aborta a bateria INTEIRA (exit 1) sempre que o destino de caixa vier vazio -
# INCONDICIONAL, sem checar se OneDrive/ONEDRIVE estao definidas no momento.
# Uma versao condicionada a "OneDrive esta alcancavel" nao pega a mutacao que
# so remove a linha do RFM_BACKUP_DESTINO em rodar(): o `env -u OneDrive
# -u ONEDRIVE` que fica ao lado, na mesma chamada, continua de pe e blinda o
# processo filho de qualquer jeito, entao um cheque condicional nunca via a
# ausencia como perigo. Incondicional fecha essa lacuna e nao depende de o
# OneDrive estar ou nao setado na maquina de quem roda a bateria.
#
# RFM_ONEDRIVE_FALSO e a valvula documentada para quem quer, deliberadamente,
# ver a chamada mutada prosseguir ate o resolverDestino de verdade (que ainda
# assim so alcancaria um OneDrive FALSO combinado por quem chama, nunca o
# real, porque o `env -u OneDrive -u ONEDRIVE` da chamada continua ativo) -
# usada so por quem esta deliberadamente testando o mecanismo por fora desta
# trava. Sem a flag (o caso normal, inclusive da catraca de mutacao do N1),
# a trava aborta assim que o primeiro call site regredir, sem escrever nada em
# canto nenhum.
verificar_destino_seguro() {  # verificar_destino_seguro <RFM_BACKUP_DESTINO-desta-chamada>
  local destino="$1"
  [ -n "$destino" ] && return 0
  [ -n "${RFM_ONEDRIVE_FALSO:-}" ] && return 0
  echo "FALHA trava anti-OneDrive-real: RFM_BACKUP_DESTINO nao foi passada de caixa nesta chamada - abortando ANTES de rodar caso nenhum a mais (N1, 2026-09-03/04)" >&2
  exit 1
}

# --- checagem (c): snapshot do OneDrive real ANTES de qualquer caso rodar --
# Compara com o snapshot de depois no caso 18. `$OneDrive` aqui e o ambiente
# HERDADO pelo processo desta bateria - o real, a menos que o operador da
# catraca de mutacao o tenha substituido de proposito (ver RFM_ONEDRIVE_FALSO
# acima).
_onedrive_pasta_backup() {
  local base="${OneDrive:-${ONEDRIVE:-}}"
  [ -z "$base" ] && return 1
  local unix; unix="$(cygpath -u "$base" 2>/dev/null || printf '%s' "$base")"
  printf '%s/rainforest-backup' "$unix"
}
ONEDRIVE_BACKUP_DIR="$(_onedrive_pasta_backup || true)"
ONEDRIVE_ANTES=""
if [ -n "$ONEDRIVE_BACKUP_DIR" ] && [ -d "$ONEDRIVE_BACKUP_DIR" ]; then
  ONEDRIVE_ANTES="$(ls -1 "$ONEDRIVE_BACKUP_DIR" 2>/dev/null | sort)"
fi

# --- caixa: um "plugin" e uma "raiz de dados", cada um repo git COM commit,
#     cada um com uma remota que e outra pasta local (nunca a internet).
montar() {
  rm -rf "$SB/plugin" "$SB/dados" "$SB/plugin-bare" "$SB/dados-bare"
  for par in "plugin" "dados"; do
    git init --bare -q -b main "$SB/$par-bare"
    git init -q -b main "$SB/$par"
    ( cd "$SB/$par" && git config user.email t@t && git config user.name t &&
      mkdir -p vigias && echo base > vigias/ERROS.md && git add vigias/ERROS.md &&
      git commit -qm base && git remote add origin "$SB/$par-bare" && git push -q -u origin main )
  done
  # A caixa precisa das dependencias do foco.cjs, nao so dele. Copiar o script
  # solto foi o defeito que a #110 ja tinha ensinado: o modulo some, o erro vira
  # `Cannot find module`, e a bateria mede a caixa em vez do artefato.
  mkdir -p "$SB/plugin/scripts" "$SB/plugin/vigias" "$SB/plugin/hooks/lib"
  cp "$SRC/scripts/foco.cjs" "$SB/plugin/scripts/foco.cjs"
  cp "$SRC/scripts/backup.cjs" "$SB/plugin/scripts/backup.cjs"
  cp "$SRC/hooks/lib/raiz.cjs" "$SB/plugin/hooks/lib/raiz.cjs"
  cp "$SRC/hooks/lib/resolver-executavel.cjs" "$SB/plugin/hooks/lib/resolver-executavel.cjs"
  cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SB/plugin/hooks/lib/contexto-sessao.cjs"
  cp "$SRC/vigias/backup-estado.ps1" "$SB/plugin/vigias/backup-estado.ps1"
  # O erros.ps1 e dependencia de EXECUCAO, nao acessorio: o backup-estado.ps1
  # faz dot-source dele. Sem a copia, o dot-source morre e o script inteiro
  # cala - foi o que aconteceu quando a porta unica de escrita nasceu, e a
  # bateria caiu de 28 para 25 medindo uma caixa quebrada em vez do artefato.
  # E a mesma licao da #110 que o comentario acima ja registra.
  cp "$SRC/vigias/erros.ps1" "$SB/plugin/vigias/erros.ps1"
  printf 'foco de caixa\n' > "$SB/dados/FOCO.md"

  # Caixa do caminho de PRODUCAO (caso 8): um "projeto" com `.rainforest/FOCO.md`,
  # que e o nivel 2 da cadeia, e um HOME falso e VAZIO para o nivel 3 nao ter onde
  # cair. Vazio de proposito: se o nivel 3 respondesse, o caso 8 passaria sem
  # provar que o nivel 2 funciona.
  rm -rf "$SB/projeto" "$SB/home-falso"
  mkdir -p "$SB/projeto/.rainforest" "$SB/home-falso"
  printf 'foco do projeto de caixa\n' > "$SB/projeto/.rainforest/FOCO.md"
}

contar() { ( cd "$1" && git log --oneline 2>/dev/null | wc -l ); }

# O backup-estado.ps1 NAO recebe mais -Root: ele deixa o foco.cjs resolver a raiz
# de dados pela cadeia canonica de 4 niveis (hooks/lib/raiz.cjs). Entao a caixa
# passa a dirigir por RFM_ROOT, que e o nivel 1 dessa cadeia.
#
# Isto nao e detalhe de encanamento, e o conserto do furo que deixava esta
# bateria VERDE enquanto a producao estava quebrada: ate 2026-09-01 ela passava
# `-Root "$SB/dados"` — ou seja, entregava a resposta certa de bandeja — e nunca
# exercitava a pergunta "de onde sai a raiz?". Na producao quem respondia era o
# run-vigia.ps1, com a raiz do PLUGIN, e o backup nunca achou o FOCO.md.
rodar() {  # rodar <raiz-de-dados> [-Teste]
  local dst; dst="$(mktemp -d)"
  local -x RFM_BACKUP_DESTINO="$(win "$dst")"
  verificar_destino_seguro "${RFM_BACKUP_DESTINO:-}"
  RFM_ROOT="$(win "$1")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
    -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
    -Log "$(win "$SB/plugin/vigias/log.txt")" ${2:-} > /dev/null 2>&1
  local codigo=$?
  rm -rf "$dst"
  echo $codigo
}

# O caminho de PRODUCAO: sem RFM_ROOT nenhuma, que e como a tarefa agendada roda
# (`printenv RFM_ROOT` sai 1 nesta maquina). A raiz tem de sair do nivel 2 da
# cadeia — `<projeto>/.rainforest` —, e o `env -u` garante que o nivel 1 nao
# entra em campo e mascara o resultado. USERPROFILE tambem e desviado para a
# caixa: sem isso o nivel 3 poderia alcancar o ~/.rainforest REAL do usuario, e
# bateria que escreve nos dados do usuario nao e bateria.
rodar_sem_rfm_root() {  # rodar_sem_rfm_root <dir-de-projeto>
  local dst; dst="$(mktemp -d)"
  local -x RFM_BACKUP_DESTINO="$(win "$dst")"
  verificar_destino_seguro "${RFM_BACKUP_DESTINO:-}"
  env -u RFM_ROOT -u OneDrive -u ONEDRIVE \
      CLAUDE_PROJECT_DIR="$(win "$1")" \
      USERPROFILE="$(win "$SB/home-falso")" \
      HOME="$SB/home-falso" \
    powershell -NoProfile -ExecutionPolicy Bypass \
      -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
      -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
      -Log "$(win "$SB/plugin/vigias/log.txt")" > /dev/null 2>&1
  local codigo=$?
  rm -rf "$dst"
  echo $codigo
}

echo "== 0. a caixa tem commit — senao a comparacao passa por vazio =="
montar
igual "plugin-local nasce com 1 commit" "$(contar "$SB/plugin")" "1"
igual "dados-local nasce com 1 commit"  "$(contar "$SB/dados")"  "1"
igual "plugin-bare recebeu o push"      "$(contar "$SB/plugin-bare")" "1"
igual "dados-bare recebeu o push"       "$(contar "$SB/dados-bare")"  "1"

echo
echo "== 1. o sentinela nao commita nem empurra em raiz nenhuma =="
montar
A_P=$(contar "$SB/plugin"); A_D=$(contar "$SB/dados")
A_PB=$(contar "$SB/plugin-bare"); A_DB=$(contar "$SB/dados-bare")
rodar "$SB/dados" > /dev/null
D_P=$(contar "$SB/plugin"); D_D=$(contar "$SB/dados")
D_PB=$(contar "$SB/plugin-bare"); D_DB=$(contar "$SB/dados-bare")
if [ "$A_P" = "$D_P" ] && [ "$A_D" = "$D_D" ] && [ "$A_PB" = "$D_PB" ] && [ "$A_DB" = "$D_DB" ]; then
  ok=$((ok+1)); echo "  ok    o sentinela nao commita nem empurra em raiz nenhuma"
else
  falhou=$((falhou+1))
  echo "  FALHA o sentinela nao commita nem empurra em raiz nenhuma"
  echo "        plugin $A_P->$D_P  dados $A_D->$D_D  plugin-bare $A_PB->$D_PB  dados-bare $A_DB->$D_DB"
fi

echo
echo "== 2. o caminho feliz faz o backup de verdade =="
montar
rodar "$SB/dados" > /dev/null
n=$(ls "$SB/dados/.foco-backups" 2>/dev/null | wc -l)
igual "criou exatamente uma copia" "$n" "1"
copia=$(ls "$SB/dados/.foco-backups"/*.md 2>/dev/null | head -1)
if [ -n "$copia" ] && cmp -s "$SB/dados/FOCO.md" "$copia"; then
  ok=$((ok+1)); echo "  ok    a copia e byte a byte igual ao FOCO.md"
else
  falhou=$((falhou+1)); echo "  FALHA a copia nao confere com o FOCO.md"
fi

echo
echo "== 3. -Teste nao escreve backup nenhum =="
montar
rodar "$SB/dados" "-Teste" > /dev/null
if [ -d "$SB/dados/.foco-backups" ]; then
  falhou=$((falhou+1)); echo "  FALHA -Teste criou backup"
else
  ok=$((ok+1)); echo "  ok    -Teste nao criou backup"
fi
grep -q 'modo teste' "$SB/plugin/vigias/log.txt" 2>/dev/null && r=sim || r=nao
verdade "-Teste registrou 'modo teste' no log" "$r"

echo
echo "== 4. falha de backup FALA no ERROS.md =="
montar
codigo=$(rodar "$SB/nao-existe")
igual "sai diferente de zero quando a raiz nao existe" "$codigo" "1"
conteudo=$(cat "$SB/plugin/vigias/ERROS.md")
echo "  -- ERROS.md depois da falha:"
printf '%s\n' "$conteudo" | sed 's/^/     /'
printf '%s' "$conteudo" | grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \[sentinela-foco\]: ' && r=sim || r=nao
verdade "a linha esta no formato do run-vigia.ps1" "$r"
printf '%s' "$conteudo" | grep -q 'FOCO.md' && r=sim || r=nao
verdade "a linha diz o que falhou" "$r"

echo
echo "== 5. nenhum git no backup-estado.ps1, fora de comentario =="
if grep -vE '^\s*#' "$SRC/vigias/backup-estado.ps1" | grep -qE '\bgit\b'; then
  falhou=$((falhou+1)); echo "  FALHA achei git em linha de execucao"
else
  ok=$((ok+1)); echo "  ok    nenhum git em linha de execucao"
fi

echo
echo "== 6. o run-vigia.ps1 nao volta a commitar nem empurrar =="
# A trava. Ela olha LINHA DE EXECUCAO, nao o arquivo inteiro: o comentario que
# explica por que o bloco saiu cita `git add`, `git commit` e `git push` de
# proposito, e apagar esse comentario para a trava passar seria apagar a razao.
exec_do_vigia="$(grep -vE '^\s*#' "$SRC/vigias/run-vigia.ps1")"
for proibido in 'git .*add' 'git .*commit' 'git .*push'; do
  if printf '%s' "$exec_do_vigia" | grep -qE "$proibido"; then
    falhou=$((falhou+1)); echo "  FALHA achei '$proibido' em linha de execucao do run-vigia.ps1"
  else
    ok=$((ok+1)); echo "  ok    nenhum '$proibido' em linha de execucao do run-vigia.ps1"
  fi
done
# E o contrario: a mesma string em COMENTARIO nao pode acender a trava.
if printf '%s' "$(grep -E '^\s*#' "$SRC/vigias/run-vigia.ps1")" | grep -qE 'git .*push'; then
  ok=$((ok+1)); echo "  ok    o comentario cita 'git push' e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar 'git push' — sem isso a trava nao esta provada nos dois sentidos"
fi

echo
echo "== 7. o _comum.md nao pode divergir do codigo =="
# Nao e teste de prosa: e o UNICO numero do backup que aparece em dois lugares.
# O teto vive no backup-estado.ps1 e e prometido no _comum.md; se um mudar e o
# outro nao, o vigia le uma promessa que o codigo nao cumpre.
teto_codigo="$(grep -oE '^\$TETO_COPIAS = [0-9]+' "$SRC/vigias/backup-estado.ps1" | grep -oE '[0-9]+')"
if [ -z "$teto_codigo" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei \$TETO_COPIAS no backup-estado.ps1"
else
  ok=$((ok+1)); echo "  ok    o codigo declara o teto ($teto_codigo)"
  if grep -qE "\*\*${teto_codigo}\*\*" "$SRC/vigias/_comum.md"; then
    ok=$((ok+1)); echo "  ok    o _comum.md promete o mesmo teto ($teto_codigo)"
  else
    falhou=$((falhou+1)); echo "  FALHA o _comum.md nao promete o teto $teto_codigo que o codigo usa"
  fi
fi
if grep -q 'commita nem empurra' "$SRC/vigias/_comum.md"; then
  ok=$((ok+1)); echo "  ok    o _comum.md diz que o sentinela nao commita nem empurra"
else
  falhou=$((falhou+1)); echo "  FALHA o _comum.md nao diz que o sentinela nao commita nem empurra"
fi

echo
echo "== 8. SEM RFM_ROOT o backup acha o FOCO.md — o caminho da tarefa agendada =="
# O caso que faltava, e que deixou o defeito vivo por 20 dias. Os casos 0 a 7
# entregam a raiz de bandeja (antes por -Root, hoje por RFM_ROOT) e por isso
# nunca perguntam "de onde sai a raiz quando ninguem diz?". Essa e exatamente a
# pergunta da producao: a tarefa agendada roda sem RFM_ROOT, e ate 2026-09-01 a
# resposta era a raiz do PLUGIN, onde nao ha FOCO.md nenhum.
montar
codigo=$(rodar_sem_rfm_root "$SB/projeto")
igual "sai zero sem RFM_ROOT no ambiente" "$codigo" "0"
n=$(ls "$SB/projeto/.rainforest/.foco-backups" 2>/dev/null | wc -l | tr -d ' ')
igual "criou a copia na raiz de DADOS resolvida pela cadeia" "$n" "1"
copia=$(ls "$SB/projeto/.rainforest/.foco-backups"/*.md 2>/dev/null | head -1)
echo "  -- copia criada: ${copia:-<nenhuma>}"
if [ -n "$copia" ] && cmp -s "$SB/projeto/.rainforest/FOCO.md" "$copia"; then
  ok=$((ok+1)); echo "  ok    a copia e byte a byte igual ao FOCO.md do projeto"
else
  falhou=$((falhou+1)); echo "  FALHA a copia nao confere com o FOCO.md do projeto"
fi
# E a prova pela negativa: nada foi escrito na raiz do PLUGIN, que era o destino
# errado que o defeito produzia.
if [ -d "$SB/plugin/.foco-backups" ]; then
  falhou=$((falhou+1)); echo "  FALHA escreveu backup na raiz do PLUGIN"
else
  ok=$((ok+1)); echo "  ok    nada foi escrito na raiz do plugin"
fi
# A asserção casa 'achei o FOCO.md', SEM o 'nao' na frente — e isso não é
# desleixo, é cicatriz. A primeira versão procurava 'nao achei o FOCO.md' e
# passou VERDE debaixo da mutação, porque a linha que o vigia grava de verdade é
# `n├úo achei o FOCO.md` (rf-encoding-exemplo: assinatura citada de
# proposito, e o sintoma que esta linha existe para explicar). O texto sai do
# node em UTF-8, o PowerShell decodifica
# no codepage OEM do console e regrava mojibake (o defeito V4 desta entrega).
# Ou seja, o mojibake derrotou o teste que procurava o próprio defeito. O trecho
# ASCII puro é o que sobrevive aos dois lados da corrupção.
if [ -f "$SB/plugin/vigias/ERROS.md" ] && grep -q 'achei o FOCO.md' "$SB/plugin/vigias/ERROS.md"; then
  falhou=$((falhou+1)); echo "  FALHA registrou 'achei o FOCO.md' — o defeito de 20 dias voltou"
  sed 's/^/     /' "$SB/plugin/vigias/ERROS.md"
else
  ok=$((ok+1)); echo "  ok    nenhum 'achei o FOCO.md' no ERROS.md"
fi

echo
echo "== 9. a trava: ninguem devolve a raiz de repositorio para o foco.cjs =="
# Trava de regressao do caso 8. Ela olha LINHA DE EXECUCAO, nao o arquivo
# inteiro: os comentarios dos dois arquivos citam `-Root` e `--raiz` de
# proposito, para explicar por que sairam, e apagar essa explicacao para a trava
# passar seria apagar a razao. Mesmo desenho do caso 6.
exec_backup="$(grep -vE '^\s*#' "$SRC/vigias/backup-estado.ps1")"
exec_vigia="$(grep -vE '^\s*#' "$SRC/vigias/run-vigia.ps1")"
if printf '%s' "$exec_backup" | grep -qE '\-\-raiz'; then
  falhou=$((falhou+1)); echo "  FALHA o backup-estado.ps1 voltou a passar --raiz para o foco.cjs"
else
  ok=$((ok+1)); echo "  ok    o backup-estado.ps1 nao passa --raiz"
fi
if printf '%s' "$exec_vigia" | grep -qE "'-Root'"; then
  falhou=$((falhou+1)); echo "  FALHA o run-vigia.ps1 voltou a passar -Root para o backup"
else
  ok=$((ok+1)); echo "  ok    o run-vigia.ps1 nao passa -Root"
fi
if printf '%s' "$(grep -E '^\s*#' "$SRC/vigias/backup-estado.ps1")" | grep -qE '\-\-raiz'; then
  ok=$((ok+1)); echo "  ok    o comentario cita '--raiz' e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar '--raiz' — sem isso a trava nao esta provada nos dois sentidos"
fi

echo
echo "== 10. o stdout sai LIMPO — o retorno do Write-LinhaEmLf nao vaza =="
# O Write-LinhaEmLf devolve $true/$false de proposito, para o chamador decidir
# (ver o comentario dele no erros.ps1). Quem nao consome esse retorno o joga no
# stdout: em 2026-09-02 uma execucao manual do backup saiu com um `True` solto
# antes da linha de log, e no run-vigia.ps1 o ForEach-Object da saida do claude
# multiplicava isso por UMA LINHA DE RELATORIO. O Agendador descarta stdout,
# entao nada quebrava — e por isso nenhuma bateria pegava. Este caso executa e
# olha o stdout de verdade, que e o unico lugar onde o defeito aparecia.
rodar_capturando() {  # rodar_capturando <raiz-de-dados>
  local dst; dst="$(mktemp -d)"
  local -x RFM_BACKUP_DESTINO="$(win "$dst")"
  verificar_destino_seguro "${RFM_BACKUP_DESTINO:-}"
  RFM_ROOT="$(win "$1")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass     -File "$(win "$SB/plugin/vigias/backup-estado.ps1")"     -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")"     -Log "$(win "$SB/plugin/vigias/log.txt")" 2>/dev/null
  rm -rf "$dst"
}
montar
saida_stdout="$(rodar_capturando "$SB/dados")"
igual "o backup nao imprime nada no stdout" "$saida_stdout" ""
# E a caixa precisa provar que o backup REALMENTE rodou nesta passada, senao
# stdout vazio por script morto passaria como stdout limpo.
if [ -n "$(find "$SB/dados/.foco-backups" -name 'foco-*.md' 2>/dev/null)" ]; then
  ok=$((ok+1)); echo "  ok    e o backup aconteceu — stdout vazio nao e script morto"
else
  falhou=$((falhou+1)); echo "  FALHA nenhum backup nesta passada: o stdout vazio nao prova nada"
fi

echo
echo "== 11. a trava: nenhum Write-LinhaEmLf solto nos dois .ps1 =="
# Mesmo desenho do caso 9: comentario nao acende a trava. Os dois arquivos
# CITAM o Write-LinhaEmLf em comentario de proposito, para explicar por que o
# log passa por ele em vez de Out-File — apagar a citacao para a trava passar
# seria apagar a explicacao.
for alvo in backup-estado run-vigia; do
  soltas="$(grep -vE '^\s*#' "$SRC/vigias/$alvo.ps1" | grep -n 'Write-LinhaEmLf' | grep -v '\[void\](' | grep -v '=\s*Write-LinhaEmLf' || true)"
  if [ -n "$soltas" ]; then
    falhou=$((falhou+1)); echo "  FALHA $alvo.ps1 tem chamada solta: $soltas"
  else
    ok=$((ok+1)); echo "  ok    $alvo.ps1 consome todo retorno de Write-LinhaEmLf"
  fi
done
if grep -E '^\s*#' "$SRC/vigias/run-vigia.ps1" | grep -q 'Write-LinhaEmLf'; then
  ok=$((ok+1)); echo "  ok    o comentario cita 'Write-LinhaEmLf' e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar 'Write-LinhaEmLf' — sem isso a trava nao esta provada nos dois sentidos"
fi

echo
echo "== 12. (a) caminho feliz - o destino sandbox ganha o zip do dia =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
rm -f "$SB/plugin/vigias/log.txt"
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
  -Log "$(win "$SB/plugin/vigias/log.txt")" > /dev/null 2>&1
n=$(ls "$SB_BACKUP"/rainforest-*.zip 2>/dev/null | wc -l)
igual "o destino recebeu um rainforest-*.zip" "$n" "1"
# Se falhou, imprime o log para debug
if [ "$n" != "1" ] && [ -f "$SB/plugin/vigias/log.txt" ]; then
  echo "  -- log.txt:"
  sed 's/^/     /' "$SB/plugin/vigias/log.txt"
fi
if [ $n -gt 0 ]; then
  ok=$((ok+1)); echo "  ok    o zip foi criado no destino sandbox"
else
  falhou=$((falhou+1)); echo "  FALHA nenhum zip no destino"
fi

echo
echo "== 13. (b) backup local do FOCO.md continua igual, sem regressao =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" 2>&1 | grep -v 'warning:' || true
n=$(ls "$SB/dados/.foco-backups" 2>/dev/null | wc -l)
igual "criou exatamente uma copia local" "$n" "1"
copia=$(ls "$SB/dados/.foco-backups"/*.md 2>/dev/null | head -1)
if [ -n "$copia" ] && cmp -s "$SB/dados/FOCO.md" "$copia"; then
  ok=$((ok+1)); echo "  ok    a copia local e byte a byte igual ao FOCO.md"
else
  falhou=$((falhou+1)); echo "  FALHA a copia local nao confere com o FOCO.md"
fi

echo
echo "== 14. (c) -Teste nao grava nem backup local nem externo =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
  -Teste 2>&1 | grep -v 'warning:' || true
if [ ! -d "$SB/dados/.foco-backups" ]; then
  ok=$((ok+1)); echo "  ok    -Teste nao criou backup local"
else
  falhou=$((falhou+1)); echo "  FALHA -Teste criou backup local"
fi
n=$(ls "$SB_BACKUP"/rainforest-*.zip 2>/dev/null | wc -l)
if [ "$n" = "0" ]; then
  ok=$((ok+1)); echo "  ok    -Teste nao criou backup externo"
else
  falhou=$((falhou+1)); echo "  FALHA -Teste criou backup externo ($n zip)"
fi

echo
echo "== 15. (d) backup externo falhando registra erro e script continua =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
rm -f "$SB/plugin/vigias/log.txt"
# Cria um backup.cjs quebrado que sai com erro
cat > "$SB/plugin/scripts/backup.cjs" << 'EOF'
#!/usr/bin/env node
process.exit(2);
EOF
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
  -Log "$(win "$SB/plugin/vigias/log.txt")" > /dev/null 2>&1
codigo=$?
# Script deve sair com 0 mesmo com falha do backup externo (backup local ja foi feito)
igual "script sai com 0 apesar da falha do backup externo" "$codigo" "0"
# O backup local tem de ter sido feito mesmo assim
n=$(ls "$SB/dados/.foco-backups" 2>/dev/null | wc -l)
igual "backup local aconteceu mesmo com falha do externo" "$n" "1"
# O erro tem de estar registrado no ERROS.md
conteudo=$(cat "$SB/plugin/vigias/ERROS.md" 2>/dev/null)
if printf '%s' "$conteudo" | grep -q 'backup externo falhou'; then
  ok=$((ok+1)); echo "  ok    erro do backup externo foi registrado em ERROS.md"
else
  falhou=$((falhou+1)); echo "  FALHA erro nao foi registrado em ERROS.md"
  echo "  -- ERROS.md:"
  printf '%s\n' "$conteudo" | sed 's/^/     /'
  echo "  -- log.txt:"
  cat "$SB/plugin/vigias/log.txt" 2>/dev/null | sed 's/^/     /'
fi

echo
echo "== 16. (e) destino invalido nao expoe caminhos absolutos do usuario, mesmo com espaco e UNC =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
rm -f "$SB/plugin/vigias/log.txt"
# Cria um backup.cjs que emite, na ultima linha, um caminho Windows COM ESPACO
# no meio (pasta com espaco no nome) e um caminho UNC tambem com espaco — trava
# de regressao para o Get-MotivoSaneado (vigias/erros.ps1), que e quem de fato
# sanitiza aqui (chamado dentro de Write-ErroDeVigia, dentro de Registrar-Erro).
cat > "$SB/plugin/scripts/backup.cjs" << 'EOF'
#!/usr/bin/env node
console.error('RECUSADO: destino primario \\\\servidor\\Compartilhamento Publico\\backup (indisponivel) e alternativo C:\\Users\\Nome Com Espaco\\pasta (permissao negada)');
process.exit(2);
EOF
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
  -Log "$(win "$SB/plugin/vigias/log.txt")" > /dev/null 2>&1
codigo=$?
# Script deve sair com 0 mesmo com falha (backup local ja foi feito)
igual "script sai com 0 apesar da falha" "$codigo" "0"
# O erro tem de estar registrado no ERROS.md
conteudo=$(cat "$SB/plugin/vigias/ERROS.md" 2>/dev/null)
if printf '%s' "$conteudo" | grep -q 'backup externo falhou'; then
  ok=$((ok+1)); echo "  ok    erro do backup externo foi registrado"
else
  falhou=$((falhou+1)); echo "  FALHA erro nao foi registrado em ERROS.md"
fi
# Nao pode conter caminho absoluto Windows nem UNC cru
if printf '%s' "$conteudo" | grep -qE '[A-Za-z]:\\|\\\\[A-Za-z]'; then
  falhou=$((falhou+1)); echo "  FALHA ERROS.md contem caminho absoluto ou UNC"
  printf '%s\n' "$conteudo" | sed 's/^/     /'
else
  ok=$((ok+1)); echo "  ok    ERROS.md nao contem caminho absoluto nem UNC"
fi
# Nao pode vazar o segmento com espaco no meio do caminho (nome de pasta)
if printf '%s' "$conteudo" | grep -qE 'Nome Com Espaco|Compartilhamento Publico'; then
  falhou=$((falhou+1)); echo "  FALHA ERROS.md vaza segmento de caminho com espaco"
  printf '%s\n' "$conteudo" | sed 's/^/     /'
else
  ok=$((ok+1)); echo "  ok    ERROS.md nao vaza segmento de caminho com espaco"
fi
# O marcador <caminho> tem de aparecer no lugar dos caminhos originais
if printf '%s' "$conteudo" | grep -q '<caminho>'; then
  ok=$((ok+1)); echo "  ok    marcador <caminho> presente"
else
  falhou=$((falhou+1)); echo "  FALHA marcador <caminho> ausente"
fi

echo
echo "== 17. (f) linha de erro gigante do backup externo e truncada em 200 chars =="
montar
SB_BACKUP="$(mktemp -d)"
trap "rm -rf $SB_BACKUP" RETURN
rm -f "$SB/plugin/vigias/log.txt"
# Sem caminho nenhum aqui de proposito: isola o TRUNCAMENTO do saneamento de
# caminho (que e responsabilidade do Get-MotivoSaneado, ja coberto no caso 16).
# O marcador fica depois da posicao 200 - so aparece se ninguem cortar a linha.
MARCADOR_LONGE="MARCADOR-DEPOIS-DE-200-NAO-PODE-APARECER"
cat > "$SB/plugin/scripts/backup.cjs" << EOF
#!/usr/bin/env node
console.error('$(printf 'X%.0s' $(seq 1 250))${MARCADOR_LONGE}');
process.exit(2);
EOF
RFM_ROOT="$(win "$SB/dados")" RFM_BACKUP_DESTINO="$(win "$SB_BACKUP")" env -u OneDrive -u ONEDRIVE powershell -NoProfile -ExecutionPolicy Bypass \
  -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
  -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" \
  -Log "$(win "$SB/plugin/vigias/log.txt")" > /dev/null 2>&1
codigo=$?
igual "script sai com 0 apesar da falha" "$codigo" "0"
conteudo=$(cat "$SB/plugin/vigias/ERROS.md" 2>/dev/null)
if printf '%s' "$conteudo" | grep -q "$MARCADOR_LONGE"; then
  falhou=$((falhou+1)); echo "  FALHA linha gigante NAO foi truncada (marcador vazou)"
  printf '%s\n' "$conteudo" | sed 's/^/     /'
else
  ok=$((ok+1)); echo "  ok    linha gigante foi truncada (marcador nao aparece)"
fi

echo
echo "== 18. (c) checagem final: nada novo apareceu no OneDrive real =="
# Compara com o snapshot ONEDRIVE_ANTES tirado antes do caso 0 rodar. Se a
# pasta nao existia antes, ela nao pode existir agora; se existia, nenhum
# arquivo NOVO pode ter surgido nela. E o mecanismo (c) do N1: mesmo que todo
# call site desta bateria isole corretamente, esta e a rede de seguranca que
# prova o resultado observavel, nao so a intencao do codigo.
ONEDRIVE_DEPOIS=""
if [ -n "$ONEDRIVE_BACKUP_DIR" ] && [ -d "$ONEDRIVE_BACKUP_DIR" ]; then
  ONEDRIVE_DEPOIS="$(ls -1 "$ONEDRIVE_BACKUP_DIR" 2>/dev/null | sort)"
fi
if [ -z "$ONEDRIVE_BACKUP_DIR" ]; then
  ok=$((ok+1)); echo "  ok    nenhum OneDrive no ambiente desta bateria - nada a conferir"
elif [ -z "$ONEDRIVE_ANTES" ] && [ -n "$ONEDRIVE_DEPOIS" ]; then
  falhou=$((falhou+1)); echo "  FALHA a pasta $ONEDRIVE_BACKUP_DIR nao existia antes e existe agora - vazamento para o OneDrive real"
  printf '%s\n' "$ONEDRIVE_DEPOIS" | sed 's/^/     /'
elif [ "$ONEDRIVE_ANTES" != "$ONEDRIVE_DEPOIS" ]; then
  novos="$(comm -13 <(printf '%s\n' "$ONEDRIVE_ANTES") <(printf '%s\n' "$ONEDRIVE_DEPOIS"))"
  if [ -n "$novos" ]; then
    falhou=$((falhou+1)); echo "  FALHA apareceu arquivo novo em $ONEDRIVE_BACKUP_DIR durante esta bateria"
    printf '%s\n' "$novos" | sed 's/^/     /'
  else
    ok=$((ok+1)); echo "  ok    nenhum arquivo novo em $ONEDRIVE_BACKUP_DIR (so sumiram, o que nao e vazamento)"
  fi
else
  ok=$((ok+1)); echo "  ok    $ONEDRIVE_BACKUP_DIR ficou identico do inicio ao fim desta bateria"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
