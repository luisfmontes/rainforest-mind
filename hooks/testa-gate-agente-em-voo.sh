#!/bin/bash
# Bateria do gate-agente-em-voo.cjs (Stop). Monta um repositorio de FIXTURE, com
# branch e arquivo de estado proprios, e alimenta o hook com o payload real de
# `Stop`. O cwd do evento e sempre o da fixture: bateria que aponta para o
# repositorio de quem a roda mede a maquina, nao o codigo — e este lote inteiro
# existe por causa dessa familia de defeito (Issues #170 e #176).
# Uso: bash hooks/testa-gate-agente-em-voo.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/gate-agente-em-voo.cjs"
ESTADO="$SRC/scripts/estado.cjs"

# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o hook libera — a bateria passaria verde testando
# nada. Mesma armadilha registrada em testa-gate-worktree.sh.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

# Raiz de dados descartavel (Issue #160): quem desligou o gate pelo `/setup` no
# escopo usuario nao pode deixar esta bateria verde por acidente.
export RFM_ROOT="$RAIZ/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0

# Payload de Stop montado por node, com os valores chegando por argv — printf
# com aspas aninhadas ja produziu JSON invalido neste repo, e JSON invalido faz
# o hook sair 0: o exit esperado pelo motivo errado.
pay() { # cwd, stop_hook_active(true|false)
  node -e 'const [c,s]=process.argv.slice(1);process.stdout.write(JSON.stringify({session_id:"s1",cwd:c,hook_event_name:"Stop",stop_hook_active:s==="true"}))' "$1" "$2"
}

checa() { # nome, exit esperado, payload, [trecho que a mensagem deve conter]
  local nome="$1" esp="$2" json="$3" trecho="${4:-}"
  local saida; saida=$(printf '%s' "$json" | node "$HOOK" 2>&1); local got=$?
  if [ "$got" != "$esp" ]; then
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | head -6
    return
  fi
  if [ -n "$trecho" ] && ! printf '%s' "$saida" | grep -qF "$trecho"; then
    falhou=$((falhou+1)); echo "  FALHA $nome: a mensagem nao cita '$trecho'"
    echo "$saida" | sed 's/^/         /' | head -8
    return
  fi
  ok=$((ok+1)); echo "  ok   $nome (exit $got)"
}

# ---------------------------------------------------------------- a fixture
# A resolucao por branch (hooks/lib/estagio-ativo.cjs) casa o nome da branch com
# o slug sem o prefixo de data: branch `fluxo/lote-teste` <-> slug
# `2026-09-04-lote-teste`.
R="$RAIZ/repo"
git init -q -b fluxo/lote-teste "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
mkdir -p "$R/docs/rainforest/estado" "$R/docs/rainforest/design" "$R/docs/rainforest/planos"
echo base > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base

SLUG="2026-09-04-lote-teste"
JSON="$R/docs/rainforest/estado/$SLUG.json"

# O estado da fixture e escrito direto, e nao pelo `estado.cjs`: o contrato que
# esta bateria exercita e "o hook enxerga `em_voo` no estagio aberto da branch",
# nao a maquina de estados — essa tem bateria propria, e amarrar as duas faria
# esta ficar vermelha por motivo que nao e dela.
escreve_estado() { # bloco JSON do estagio `executar`
  node -e '
const fs = require("fs"), [p, slug, executar] = process.argv.slice(1);
fs.writeFileSync(p, JSON.stringify({
  slug, titulo: "Fixture da bateria do gate de agente em voo", criado_em: "2026-09-04",
  arqueologia: { status: "dispensada" },
  design: { status: "aprovado", em: "2026-09-04", doc: "x" },
  plano: { status: "ok", em: "2026-09-04" },
  executar: JSON.parse(executar),
  revisar: { status: "pendente" },
  verificar: { status: "pendente" },
  fechar: { status: "pendente" },
}, null, 2) + "\n");
' "$JSON" "$SLUG" "$1"
}

escreve_estado '{"status":"parcial","em":"2026-09-04","em_voo":[{"agente":"rainforest-mind:revisor","tarefa":7,"desde":"2026-09-04"}]}'

echo "== com agente em voo =="
checa "stop_hook_active falso BARRA e nomeia o agente" 2 "$(pay "$R" false)" "rainforest-mind:revisor"
checa "a mensagem nomeia o estagio"                    2 "$(pay "$R" false)" "executar"
checa "a mensagem nomeia o fluxo"                      2 "$(pay "$R" false)" "$SLUG"
checa "stop_hook_active verdadeiro NAO barra (sem laco)" 0 "$(pay "$R" true)"

echo
echo "== saidas de emergencia =="
RAINFOREST_GATE_OFF=1 bash -c 'true'  # documenta a forma; o teste abaixo usa env inline
saida_off=$(printf '%s' "$(pay "$R" false)" | RAINFOREST_GATE_OFF=1 node "$HOOK" 2>&1); got_off=$?
if [ "$got_off" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF=1 libera: veio $got_off"; fi

touch "$R/.rainforest-gate-off"
checa ".rainforest-gate-off na raiz libera"            0 "$(pay "$R" false)"
rm -f "$R/.rainforest-gate-off"
checa "  ... e volta a barrar quando o arquivo sai"    2 "$(pay "$R" false)"

echo
echo "== sem nada em voo =="
escreve_estado '{"status":"parcial","em":"2026-09-04","em_voo":[]}'
checa "em_voo vazio nao barra"                         0 "$(pay "$R" false)"

escreve_estado '{"status":"parcial","em":"2026-09-04"}'
checa "estagio sem o campo em_voo nao barra"           0 "$(pay "$R" false)"

echo
echo "== o campo e efemero: fechar o estagio com ok apaga o em_voo =="
# Esta e a metade que o hook NAO faz e o `estado.cjs` faz: `em_voo` esta em
# CAMPOS_EFEMEROS, entao o fechamento terminal-positivo do estagio o remove.
# Sem isso, o registro de despacho atravessaria o fechamento e o gate barraria
# um turno que ja terminou o trabalho.
escreve_estado '{"status":"parcial","em":"2026-09-04","em_voo":[{"agente":"x","tarefa":1}]}'
# O `marcar ok` de um estagio de execucao so fecha com a catraca de mutacao
# armada, e quem arma e o `exigir` — a fixture passa por ele como o fluxo real.
RFM_ESTADO_ROOT="$R" node "$ESTADO" exigir --slug "$SLUG" --estagio executar > /dev/null 2>&1
RFM_ESTADO_ROOT="$R" node "$ESTADO" marcar --slug "$SLUG" --estagio executar --status ok \
  --json '{"comando":"bash x.sh","saida":"ok: 1 caso","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"n/a","motivo":"fixture"}]}' > "$RAIZ/marcar.log" 2>&1
if grep -q '"em_voo"' "$JSON"; then
  falhou=$((falhou+1)); echo "  FALHA em_voo sobreviveu ao fechamento do estagio"
  head -5 "$RAIZ/marcar.log" | sed 's/^/         /'
else
  ok=$((ok+1)); echo "  ok   em_voo sai do estado quando o estagio fecha (CAMPOS_EFEMEROS)"
fi
checa "  ... e o gate volta a liberar depois disso"    0 "$(pay "$R" false)"

echo
echo "== fora de fluxo, fora de git, e payload quebrado =="
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"
checa "cwd fora de repositorio git nao barra"          0 "$(pay "$FORA" false)"
checa "payload vazio nao barra"                        0 '{}'
checa "payload ilegivel nao barra"                     0 'isto nao e json'

R2="$RAIZ/sem-fluxo"
git init -q -b main "$R2"; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
git -C "$R2" config commit.gpgsign false
echo x > "$R2/a.txt"; git -C "$R2" add a.txt; git -C "$R2" commit -qm base
checa "repositorio sem fluxo aberto nao barra"         0 "$(pay "$R2" false)"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
