#!/usr/bin/env bash
# Bateria de scripts/rodar-longo.cjs (tarefa 2 do plano
# docs/rainforest/planos/2026-10-13-executar-autonomo.md; D7 do design).
#
# Os PIDs que esta bateria registra (o do comando e o do vigia) são conferidos
# no fim por process.kill(pid, 0), nunca por nome de processo.
set -u

cd "$(dirname "$0")/.." || exit 1

RL="node scripts/rodar-longo.cjs"
ok=0
falhou=0

# Pasta temporária fora do worktree. Node recebe caminho Windows (cygpath -m).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP="$(cygpath -m "$TMP")"; fi

PIDS_REGISTRADOS=()

# Marca desta execucao, posta em todo comando que a bateria sobe (D1 do design
# 2026-10-29-rodar-longo-flaky). Aparece na linha de comando do vigia e do bash
# do comando, e e o que separa processo da bateria de outro que herdou o PID.
MARCA="rl-bateria-$$-$RANDOM$RANDOM"

caso() {
  local nome="$1" resultado="$2"
  if [ "$resultado" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome"
  fi
}

ehPidNumerico() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# Lê o PID do vigia e do comando que o iniciar gravou em <saida>.pid e os
# registra para a checagem final. Devolve o PID do comando em stdout.
registra_pids_do_arquivo() {
  local saida="$1"
  node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.vigia);console.log(d.comando)' "$saida.pid" 2>/dev/null | while read -r p; do echo "$p"; done
}

registra() {
  local p
  for p in "$@"; do
    [ -n "$p" ] && PIDS_REGISTRADOS+=("$p")
  done
}

# Processo vivo? 0 = vivo, 1 = morto. Pelo PID, nunca pelo nome.
esta_vivo() {
  node -e 'try{process.kill(Number(process.argv[1]),0);process.exit(0)}catch(e){process.exit(e.code==="EPERM"?0:1)}' "$1"
}

# Linha de comando do processo: no Windows pelo CIM, fora dele pelo ps.
linha_de_comando() {
  # CONSULTA_MUDA=1 simula a consulta que nao responde (caso de controle do D4).
  [ -n "${CONSULTA_MUDA:-}" ] && return 0
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=$1').CommandLine" 2>/dev/null | tr -d ''
  else
    ps -o args= -p "$1" 2>/dev/null
  fi
}

# 0 = o processo e desta bateria (a linha de comando traz a MARCA).
# 2 = a consulta nao respondeu e o processo segue vivo: conta como vivo, para
#     fechar para o lado do vermelho (D4), mas nao morre, porque pode ser alheio.
# 1 = nao achou o processo, ou achou outro sem a marca.
eh_da_bateria() {
  local linha
  linha="$(linha_de_comando "$1")"
  case "$linha" in
    *"$MARCA"*) return 0 ;;
  esac
  if [ -z "$linha" ] && esta_vivo "$1"; then return 2; fi
  return 1
}

# Espera o estado deixar de ser `rodando` (até ~20 s). Imprime a última saída.
esperar_fim() {
  local saida="$1" t=0 out rc
  while [ "$t" -lt 200 ]; do
    out="$($RL estado --saida "$saida")"; rc=$?
    if [ "$rc" -eq 0 ]; then echo "$out"; return 0; fi
    sleep 0.1
    t=$((t+1))
  done
  echo "rodando"
  return 1
}

echo "== iniciar sem --saida ou sem comando recusa com exit 2"
$RL iniciar --saida "$TMP/sem-comando.txt" >/dev/null 2>&1
rc=$?
caso "iniciar sem '--' recusa com exit 2 (rc=$rc)" $([ "$rc" -eq 2 ] && echo 0 || echo 1)

echo "== estado de arquivo inexistente recusa com exit 2"
$RL estado --saida "$TMP/nao-existe.txt" >/dev/null 2>&1
rc=$?
caso "estado de saida inexistente sai 2 (rc=$rc)" $([ "$rc" -eq 2 ] && echo 0 || echo 1)

echo "== comando que sai 3 registra exit 3"
SAIDA3="$TMP/sai3.txt"
pid3="$($RL iniciar --saida "$SAIDA3" -- bash -c ": $MARCA; exit 3")"; rc=$?
caso "iniciar do comando que sai 3 sai 0 e imprime PID (rc=$rc pid=$pid3)" $([ "$rc" -eq 0 ] && ehPidNumerico "$pid3" && echo 0 || echo 1)
registra "$pid3"
registra $(registra_pids_do_arquivo "$SAIDA3")
final3="$(esperar_fim "$SAIDA3")"; rc=$?
caso "estado depois do fim imprime 'exit 3' e sai 0 (saida='$final3' rc=$rc)" $([ "$final3" = "exit 3" ] && [ "$rc" -eq 0 ] && echo 0 || echo 1)

echo "== iniciar volta na hora, estado acompanha, arquivo guarda saida e exit"
SAIDA="$TMP/longo.txt"
t0=$(date +%s%3N)
pid="$($RL iniciar --saida "$SAIDA" -- bash -c ": $MARCA; sleep 3; echo oi; exit 3")"; rc=$?
t1=$(date +%s%3N)
dt=$((t1 - t0))
caso "iniciar sai 0 com PID numerico em menos de 2 s (rc=$rc, ${dt} ms)" $([ "$rc" -eq 0 ] && ehPidNumerico "$pid" && [ "$dt" -lt 2000 ] && echo 0 || echo 1)
registra "$pid"
registra $(registra_pids_do_arquivo "$SAIDA")

out="$($RL estado --saida "$SAIDA")"; rc=$?
caso "estado logo depois imprime 'rodando' e sai 3 (saida='$out' rc=$rc)" $([ "$out" = "rodando" ] && [ "$rc" -eq 3 ] && echo 0 || echo 1)

final="$(esperar_fim "$SAIDA")"; rc=$?
caso "estado depois do fim imprime 'exit 3' e sai 0 (saida='$final' rc=$rc)" $([ "$final" = "exit 3" ] && [ "$rc" -eq 0 ] && echo 0 || echo 1)
caso "arquivo contem a saida do comando (linha 'oi')" $(grep -q '^oi$' "$SAIDA" && echo 0 || echo 1)
caso "a ultima linha do arquivo e 'exit 3'" $([ "$(tail -n 1 "$SAIDA")" = "exit 3" ] && echo 0 || echo 1)

echo "== comando inexistente registra exit diferente de zero sem travar"
SAIDA_X="$TMP/inexistente.txt"
pidx="$($RL iniciar --saida "$SAIDA_X" -- comando-que-nao-existe-rodar-longo-xyz "$MARCA")"; rc=$?
caso "iniciar do comando inexistente sai 0 (rc=$rc)" $([ "$rc" -eq 0 ] && ehPidNumerico "$pidx" && echo 0 || echo 1)
registra "$pidx"
registra $(registra_pids_do_arquivo "$SAIDA_X")
finalx="$(esperar_fim "$SAIDA_X")"; rc=$?
caso "estado final do comando inexistente e exit N com N diferente de 0 (saida='$finalx')" $(echo "$finalx" | grep -Eq '^exit [1-9][0-9]*$' && [ "$rc" -eq 0 ] && echo 0 || echo 1)

echo "== linha 'exit N' impressa pelo comando nao e confundida com o fim"
SAIDA_F="$TMP/falso.txt"
pidf="$($RL iniciar --saida "$SAIDA_F" -- bash -c ": $MARCA; "'echo "exit 5"; sleep 2; exit 0')"
registra "$pidf"
registra $(registra_pids_do_arquivo "$SAIDA_F")
sleep 0.5
out="$($RL estado --saida "$SAIDA_F")"; rc=$?
caso "com 'exit 5' na saida e o comando vivo, estado diz rodando (saida='$out' rc=$rc)" $([ "$out" = "rodando" ] && [ "$rc" -eq 3 ] && echo 0 || echo 1)
finalf="$(esperar_fim "$SAIDA_F")"; rc=$?
caso "no fim, estado diz o exit real 'exit 0' (saida='$finalf')" $([ "$finalf" = "exit 0" ] && [ "$rc" -eq 0 ] && echo 0 || echo 1)

echo "== vigia morto sem registrar o exit: estado diz morto"
SAIDA_M="$TMP/morto.txt"
$RL iniciar --saida "$SAIDA_M" -- bash -c ": $MARCA; sleep 30" >/dev/null
pids_m="$(registra_pids_do_arquivo "$SAIDA_M")"
registra $pids_m
for p in $pids_m; do node -e 'try{process.kill(Number(process.argv[1]))}catch{}' "$p"; done
sleep 0.5
out="$($RL estado --saida "$SAIDA_M")"; rc=$?
caso "estado com o vigia morto imprime 'morto' e sai 4 (saida='$out' rc=$rc)" $([ "$out" = "morto" ] && [ "$rc" -eq 4 ] && echo 0 || echo 1)

echo "== a checagem final reconhece o processo pela marca, nao so pelo PID (D5)"
SAIDA_C="$TMP/controle.txt"
$RL iniciar --saida "$SAIDA_C" -- bash -c ": $MARCA; sleep 20" >/dev/null
pids_c="$(registra_pids_do_arquivo "$SAIDA_C")"
comando_c="$(echo "$pids_c" | tail -n 1)"
eh_da_bateria "$comando_c"; rc=$?
caso "controle: processo vivo com a marca e reconhecido como da bateria (rc=$rc)" $([ "$rc" -eq 0 ] && echo 0 || echo 1)
for p in $pids_c; do node -e 'try{process.kill(Number(process.argv[1]))}catch{}' "$p"; done
alheio="$(node -e 'const c=require("child_process").spawn(process.execPath,["-e","setTimeout(()=>{},20000)"],{detached:true,stdio:"ignore"});console.log(c.pid);c.unref()')"
eh_da_bateria "$alheio"; rc=$?
caso "controle: processo vivo sem a marca nao e da bateria (rc=$rc)" $([ "$rc" -eq 1 ] && echo 0 || echo 1)
CONSULTA_MUDA=1 eh_da_bateria "$alheio"; rc=$?
caso "controle: consulta sem resposta com o processo vivo conta como vivo sem dono (rc=$rc)" $([ "$rc" -eq 2 ] && echo 0 || echo 1)
node -e 'try{process.kill(Number(process.argv[1]))}catch{}' "$alheio"

# Um processo alheio vivo entra na lista, como um PID que outro processo herdou:
# o laco final tem de ignora-lo e deixa-lo vivo (#632, D3).
alheio_final="$(node -e 'const c=require("child_process").spawn(process.execPath,["-e","setTimeout(()=>{},20000)"],{detached:true,stdio:"ignore"});console.log(c.pid);c.unref()')"
registra "$alheio_final"

echo "-- nenhum processo registrado pela bateria fica vivo no fim"
vivos=0
for p in "${PIDS_REGISTRADOS[@]}"; do
  if esta_vivo "$p"; then
    # PID vivo pode ser outro processo que herdou o numero (#632): so conta, e
    # so morre, o que traz a marca desta execucao (D3).
    eh_da_bateria "$p"; dono=$?
    if [ "$dono" -eq 0 ]; then
      vivos=$((vivos+1))
      echo "  vivo: PID $p"
      node -e 'try{process.kill(Number(process.argv[1]))}catch{}' "$p"
    elif [ "$dono" -eq 2 ]; then
      vivos=$((vivos+1))
      echo "  vivo: PID $p (linha de comando sem resposta; nao morto, pode ser alheio)"
    else
      echo "  PID $p reaproveitado por outro processo, ignorado"
    fi
  fi
done
echo "  PIDs registrados: ${#PIDS_REGISTRADOS[@]}   vivos no fim: $vivos"
caso "nenhum PID registrado segue vivo (vivos=$vivos)" $([ "$vivos" -eq 0 ] && echo 0 || echo 1)
esta_vivo "$alheio_final"; rc=$?
caso "o laco final nao conta nem mata o processo alheio registrado (vivo rc=$rc)" $([ "$rc" -eq 0 ] && echo 0 || echo 1)
node -e 'try{process.kill(Number(process.argv[1]))}catch{}' "$alheio_final"

rm -rf "$TMP"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
