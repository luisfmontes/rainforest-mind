#!/bin/bash
# Bateria do `conferir-comparacao.cjs` — a catraca de comparacao.
# Uso: bash scripts/testa-conferir-comparacao.sh
#
# Issue #101 (P6 da #61): "rodei na main e deu verde" so vale com o pwd e o
# HEAD colados junto, porque o cwd do shell PERSISTE entre chamadas e a
# comparacao degenera EM SILENCIO para branch contra ela mesma. O script
# testado nao LE uma afirmacao de comparacao — ele RODA a comparacao e
# carimba onde cada lado rodou. Esta bateria prova que ele sabe recusar os
# tres jeitos de a evidencia ser falsa (degenerada, lado que nao e repo,
# resultado contrario ao esperado) e que o caminho feliz de verdade aprova.
#
# Fixture PROPRIO, de proposito: dois worktrees reais de um repo git escrato,
# criados em segundos, sem depender de nenhum commit deste repositorio
# continuar alcancavel.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-comparacao.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"; W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT
SAIDA="$S/saida.txt"

echo "(caixa de areia: $W)"

# ------------------------------------------------------------------ o fixture
# Um repo com dois commits (v1 e v2 no conteudo de f.txt), e dois WORKTREES
# reais — um preso em cada commit. E exatamente a forma do caminho feliz: dois
# lugares de verdade, em commits diferentes.
REPO="$W/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.email "teste@example.com"
git -C "$REPO" config user.name "teste"
git -C "$REPO" config commit.gpgsign false
printf 'v1\n' > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -q -m v1
printf 'v2\n' > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -q -m v2

HASH_V1="$(git -C "$REPO" log --format=%H --all | tail -1)"
HASH_V2="$(git -C "$REPO" rev-parse HEAD)"

WT_ANTIGO="$W/wt-antigo"
WT_NOVO="$W/wt-novo"
git -C "$REPO" worktree add -q --detach "$WT_ANTIGO" "$HASH_V1" >/dev/null 2>&1
git -C "$REPO" worktree add -q --detach "$WT_NOVO" "$HASH_V2" >/dev/null 2>&1
[ -d "$WT_ANTIGO/.git" ] || [ -f "$WT_ANTIGO/.git" ] || { echo "FALHA: worktree antigo nao foi criado"; exit 1; }
[ -d "$WT_NOVO/.git" ] || [ -f "$WT_NOVO/.git" ] || { echo "FALHA: worktree novo nao foi criado"; exit 1; }

# diretorio que nao e repo git NENHUM (fora de qualquer arvore .git)
FORA_DE_REPO="$W/fora-de-repo"
mkdir -p "$FORA_DE_REPO"

# subdiretorio de um repo git DE VERDADE, mas que nao e, ele mesmo, a raiz —
# o modo de falha exato do incidente de 2026-08-19: git sobe para o repo
# ancestral em silencio se alguem nao conferir o toplevel devolvido.
SUBDIR_DE_REPO="$REPO/sub"
mkdir -p "$SUBDIR_DE_REPO"

# comando que discrimina os dois commits: falha em v1 ("antigo"), passa em v2 ("novo")
COMANDO_DISCRIMINA="grep -q v2 f.txt"

# ----------------------------------------------------------------- utilidades
CHK(){ node "$SCRIPT" "$@"; }

# exige <exit-esperado> <rotulo> <comando...>
exige(){
  local esperado="$1" rotulo="$2"; shift 2
  "$@" > "$SAIDA" 2>&1
  local got=$?
  if [ "$got" -eq "$esperado" ]; then
    ok=$((ok+1)); printf '  ok    %s (exit=%s)\n' "$rotulo" "$got"
  else
    falhou=$((falhou+1)); printf '  FALHA %s: esperado exit=%s, veio exit=%s\n' "$rotulo" "$esperado" "$got"
    sed 's/^/        | /' "$SAIDA" | tail -12
  fi
}

tem(){ if grep -q -- "$2" "$SAIDA"; then ok=$((ok+1)); printf '  ok    %s\n' "$1";
       else falhou=$((falhou+1)); printf '  FALHA %s: nao achei %s na saida\n' "$1" "$2"; fi; }
nao_tem(){ if grep -q -- "$2" "$SAIDA"; then falhou=$((falhou+1)); printf '  FALHA %s: achei %s na saida\n' "$1" "$2";
           else ok=$((ok+1)); printf '  ok    %s\n' "$1"; fi; }

echo
echo "== 1. A PROVA CENTRAL: heranca de cwd colapsa antes/depois no MESMO lado =="
# Cenario real: uma chamada de shell anterior faz 'cd' para dentro do worktree
# e o cwd PERSISTE para a chamada seguinte (o defeito exato da Issue #101). O
# agente acha que capturou dois lugares diferentes, mas os dois --antes/--depois
# colapsam no mesmo diretorio, no mesmo commit. Reproduzido aqui SEM cd (o cwd
# do shell deste script nao muda) justamente porque o defeito e no VALOR que
# chega em --antes/--depois, nao em qual comando o produziu:
CWD_QUE_VAZOU="$WT_ANTIGO"      # 1a chamada: 'cd' para o worktree A, captura pwd
# ... nenhum 'cd' de volta acontece entre uma chamada e outra (o cwd persiste) ...
CWD_DA_CHAMADA_SEGUINTE="$CWD_QUE_VAZOU"   # 2a chamada: o mesmo pwd herdado, sem querer

exige 2 "antes e depois colapsam no mesmo dir/commit por heranca de cwd" \
  CHK --antes "$CWD_QUE_VAZOU" --depois "$CWD_DA_CHAMADA_SEGUINTE" --comando "$COMANDO_DISCRIMINA"
tem "nomeia comparacao DEGENERADA" "comparacao DEGENERADA"
tem "diz que e o MESMO lado" "MESMO lado"
tem "mostra o toplevel que coincide" "toplevel coincide"
tem "mostra o HEAD que coincide" "HEAD coincide"
tem "cita a Issue #101 / o mecanismo do cwd" "cwd de uma chamada de shell anterior vazou"
EXIT_DEGENERADA=2


echo
echo "== 1b. O VETOR REAL DA HERANCA: lado omitido nao pode virar process.cwd() =="
# O caso 1 acima prova que dois lados IGUAIS sao recusados. Mas a heranca de cwd
# da Issue #101 nao chega como dois caminhos iguais escritos de proposito: ela
# chega como caminho NENHUM. Alguem roda `cd <worktree> && bateria`, e a chamada
# seguinte roda so `bateria` — o shell ainda esta la, e os dois lados viram um so
# sem ninguem digitar nada.
#
# A defesa e estrutural: `--antes` e `--depois` sao OBRIGATORIOS, e nao ha default
# para `process.cwd()`. Este caso existe para que ela nao seja desfeita por
# conveniencia depois — "se nao passar, usa o diretorio atual" e uma linha que
# parece gentileza e reabre a issue inteira em silencio, sem quebrar nenhum outro
# teste desta bateria.
#
# Rodado de DENTRO de um worktree valido de proposito: se houvesse fallback para
# cwd, os dois lados resolveriam para um repositorio de verdade e a chamada
# passaria — e o defeito so apareceria em producao.
exige 1 "sem --depois recusa (nao cai no cwd herdado)" \
  env -C "$WT_ANTIGO" node "$SCRIPT" --antes "$WT_ANTIGO" --comando "$COMANDO_DISCRIMINA"
tem "diz qual lado faltou" "falta --depois"
nao_tem "nao inventou um lado a partir do cwd" "toplevel coincide"

exige 1 "sem --antes recusa (nao cai no cwd herdado)" \
  env -C "$WT_ANTIGO" node "$SCRIPT" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"
tem "diz qual lado faltou (antes)" "falta --antes"

exige 1 "sem nenhum dos dois recusa" \
  env -C "$WT_ANTIGO" node "$SCRIPT" --comando "$COMANDO_DISCRIMINA"
echo
echo "== 2. CAMINHO FELIZ: dois worktrees de verdade, comandos que discriminam =="
exige 0 "worktrees diferentes, comando falha no antigo e passa no novo" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"
tem "evidencia do lado antes: toplevel" "toplevel : $(printf '%s' "$WT_ANTIGO" | sed 's/[\/&]/\\&/g')"
tem "evidencia do lado antes: HEAD" "HEAD     : $HASH_V1"
tem "evidencia do lado depois: HEAD" "HEAD     : $HASH_V2"
tem "evidencia do lado antes: exit 1 (v1 nao tem v2)" "exit     : 1"
tem "evidencia do lado depois: exit 0 (v2 tem v2)" "exit     : 0"
tem "veredito final de sucesso" "ok: resultado bate com --espera"

echo
echo "== 3. LADO QUE NAO E REPOSITORIO GIT: recusa ANTES de aceitar qualquer hash =="
# 3a: diretorio totalmente fora de qualquer arvore .git
exige 3 "diretorio fora de qualquer repo git recusa" \
  CHK --antes "$FORA_DE_REPO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"
tem "diz que nao e repositorio git" "nao e repositorio git"
nao_tem "nunca chega a rodar o comando (sem bloco de execucao)" "resultado bate com"

# 3b: O CASO DO INCIDENTE DE 2026-08-19. Um subdiretorio de um repo de verdade
# NAO e, ele mesmo, a raiz — git sobe e devolve o toplevel do ANCESTRAL. A
# checagem tem que RECUSAR, nunca aceitar o hash do pai calado.
exige 3 "subdiretorio de um repo real (nao e a raiz) recusa, nao aceita o hash do pai" \
  CHK --antes "$SUBDIR_DE_REPO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"
tem "nomeia o modo de falha do incidente de 2026-08-19" "incidente de 2026-08-19"
tem "diz que o toplevel devolvido e um ANCESTRAL" "ANCESTRAL do diretorio informado"
EXIT_NAO_E_REPO=3

echo
echo "  -> exit degenerada=$EXIT_DEGENERADA vs exit nao-e-repo=$EXIT_NAO_E_REPO (tem que ser distintos)"
if [ "$EXIT_DEGENERADA" != "$EXIT_NAO_E_REPO" ]; then
  ok=$((ok+1)); printf '  ok    degenerada (%s) e nao-e-repo (%s) sao codigos DIFERENTES\n' "$EXIT_DEGENERADA" "$EXIT_NAO_E_REPO"
else
  falhou=$((falhou+1)); printf '  FALHA degenerada e nao-e-repo saem com o MESMO exit code\n'
fi

echo
echo "== 4. RESULTADO CONTRARIO ao --espera: exit proprio, distinto da recusa degenerada =="
# --espera diferente exige antes FALHA e depois PASSA. Aqui os dois worktrees
# tem o MESMO exit (o comando "sempre falha") — a comparacao existe e rodou,
# so nao bateu com o esperado.
exige 4 "os dois lados dao o mesmo resultado, mas --espera diferente exigia contraste" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "grep -q so-existe-em-nenhum-lado f.txt"
tem "nomeia resultado CONTRARIO" "resultado CONTRARIO"
tem "mostra os dois exit codes" "antes  exit="
EXIT_CONTRARIO=4
echo "  -> exit degenerada=$EXIT_DEGENERADA vs exit contrario=$EXIT_CONTRARIO (tem que ser distintos)"
if [ "$EXIT_DEGENERADA" != "$EXIT_CONTRARIO" ]; then
  ok=$((ok+1)); printf '  ok    degenerada (%s) e contrario (%s) sao codigos DIFERENTES\n' "$EXIT_DEGENERADA" "$EXIT_CONTRARIO"
else
  falhou=$((falhou+1)); printf '  FALHA degenerada e contrario saem com o MESMO exit code\n'
fi

# --espera igual: os dois worktrees dao exit IGUAL (comando falha nos dois) -> aprova
exige 0 "--espera igual aprova quando os dois lados dao o mesmo exit" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "grep -q so-existe-em-nenhum-lado f.txt" --espera igual

# --espera igual: os dois worktrees dao exit DIFERENTE (comando discrimina) -> recusa
exige 4 "--espera igual recusa quando os dois lados divergem" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA" --espera igual

echo
echo "== 5. FILHO SEM STDIN E COM TETO =="
# 5a: comando que le stdin ate EOF nao pendura (fecha em ms, nao esgota o teto)
INICIO_MS=$(( $(date +%s%3N 2>/dev/null || echo 0) ))
exige 4 "comando que le stdin recebe EOF e nao pendura" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" \
      --comando "bash -c \"cat > /dev/null; echo li-stdin-ate-eof; exit 1\"" --timeout 8000
FIM_MS=$(( $(date +%s%3N 2>/dev/null || echo 0) ))
DURACAO_MS=$((FIM_MS - INICIO_MS))
tem "os dois lados leram o stdin ate o fim" "li-stdin-ate-eof"
if [ "$DURACAO_MS" -lt 6000 ] && [ "$DURACAO_MS" -gt 0 ]; then
  ok=$((ok+1)); printf '  ok    nao pendurou: %s ms (bem abaixo do teto de 8000 ms)\n' "$DURACAO_MS"
else
  falhou=$((falhou+1)); printf '  FALHA duracao suspeita ou nao medida: %s ms\n' "$DURACAO_MS"
fi

# 5b: estouro de tempo devolve o exit code documentado (1), com SEM VEREDITO
exige 1 "comando mais lento que o teto estoura e sai SEM VEREDITO (exit=1)" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" \
      --comando "bash -c \"sleep 10; exit 1\"" --timeout 1500
tem "diz SEM VEREDITO" "SEM VEREDITO"
tem "cita o teto estourado" "estourou o teto"
nao_tem "nunca aprova por estouro" "ok: resultado bate"

echo
echo "== 6. erro de uso: nunca silencioso, nunca 0 =="
exige 1 "sem argumento nenhum imprime o uso" node "$SCRIPT"
tem "o uso nomeia --antes" "--antes"
tem "o uso nomeia --depois" "--depois"
tem "o uso nomeia --comando" "--comando"

exige 1 "falta --antes recusa" CHK --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"
exige 1 "falta --depois recusa" CHK --antes "$WT_ANTIGO" --comando "$COMANDO_DISCRIMINA"
exige 1 "falta --comando recusa" CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO"
exige 1 "--comando vazio recusa" CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando ""
exige 1 "--espera invalido recusa" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA" --espera "sei-la"
exige 1 "--timeout invalido recusa" \
  CHK --antes "$WT_ANTIGO" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA" --timeout "abc"
exige 3 "--antes apontando para pasta inexistente recusa" \
  CHK --antes "$W/nao-existe" --depois "$WT_NOVO" --comando "$COMANDO_DISCRIMINA"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
