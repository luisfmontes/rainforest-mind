#!/bin/bash
# @categoria: bateria
# Bateria do scripts/relogio-sessoes.cjs (janelas esperando o usuario e ociosidade).
#
# EXECUTA o script real. Nunca le o ~/.rainforest vivo: HOME e USERPROFILE apontam
# para uma caixa e RFM_ROOT para outra, entao a cadeia de resolverRaiz so ve o que a
# bateria montou. O sessoes.json segue o formato real (chave por sessao; cwd,
# prompt_ts, stop_ts em ms).
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC/scripts/relogio-sessoes.cjs"

SANDBOXES=()
novo_sandbox() {
  local d; d=$(mktemp -d)
  if command -v cygpath >/dev/null 2>&1; then d=$(cygpath -m "$d"); fi
  SANDBOXES+=("$d"); echo "$d"
}
limpar() { local d; for d in "${SANDBOXES[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap limpar EXIT

OK=0; FALHA=0
passa() { OK=$((OK + 1)); echo "ok   $1"; }
falha() { FALHA=$((FALHA + 1)); echo "FALHA $1"; [ -n "${2:-}" ] && echo "     $2"; }

CAIXA_HOME=$(novo_sandbox)
RAIZ=$(novo_sandbox)

# rodar [args...]: stdout em $SAIDA, stderr em $ERRO, exit em $CODIGO
rodar() {
  SAIDA=$(env -u CLAUDE_PROJECT_DIR -u FORCE_COLOR HOME="$CAIXA_HOME" USERPROFILE="$CAIXA_HOME" RFM_ROOT="$RAIZ" \
    node "$SCRIPT" "$@" 2>"$CAIXA_HOME/stderr.txt")
  CODIGO=$?
  ERRO=$(cat "$CAIXA_HOME/stderr.txt")
}

# checa <nome> <expressao js sobre d>: verdadeira = passa
checa() {
  local nome="$1" expr="$2"
  if [ "$CODIGO" -ne 0 ]; then falha "$nome" "exit=$CODIGO stderr=$ERRO"; return; fi
  if printf '%s' "$SAIDA" | env -u FORCE_COLOR node -e "
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    if (!($expr)) { console.error(JSON.stringify(d)); process.exit(1); }
  " 2>"$CAIXA_HOME/asserta.txt"; then passa "$nome"; else falha "$nome" "$(cat "$CAIXA_HOME/asserta.txt")"; fi
}

# Monta o sessoes.json com tempos relativos a agora (minutos atras).
# Sem pid: sessoesVivas so checa processo quando ha pid.
env -u FORCE_COLOR node -e "
  const min = (n) => Date.now() - n * 60000;
  const igual = min(120); // prompt_ts == stop_ts: espera, e desde cai no mesmo valor
  const s = {
    'eu-1':     { cwd: 'C:/p/propria',  prompt_ts: min(100), stop_ts: min(90) },
    'parada-a': { cwd: 'C:/p/antiga',   prompt_ts: min(200), stop_ts: min(180) },
    'parada-b': { cwd: 'C:/p/recente',  prompt_ts: min(60),  stop_ts: min(50) },
    'so-prompt':{ cwd: 'C:/p/semstop',  prompt_ts: igual, stop_ts: igual },
    'agente-1': { cwd: 'C:/p/x/.claude/worktrees/agent-abc123', prompt_ts: min(70), stop_ts: min(60) },
    'trab-1':   { cwd: 'C:/p/trabalhando', prompt_ts: min(5), stop_ts: min(30) },
    'velha-1':  { cwd: 'C:/p/velha',    prompt_ts: min(500), stop_ts: min(400) },
  };
  require('fs').writeFileSync(process.argv[1], JSON.stringify(s));
" "$RAIZ/sessoes.json"

rodar --cwd "$RAIZ" --sessao eu-1
checa "a propria janela nao entra" "!d.janelas.some(j => j.cwd === 'C:/p/propria')"
checa "agent-* fora" "!d.janelas.some(j => /agent-/.test(j.cwd))"
checa "janela trabalhando fora" "!d.janelas.some(j => j.cwd === 'C:/p/trabalhando')"
checa "parada ha mais de 6 h fora" "!d.janelas.some(j => j.cwd === 'C:/p/velha')"
checa "so quem espera entra, mais antiga primeiro" \
  "JSON.stringify(d.janelas.map(j => j.cwd)) === JSON.stringify(['C:/p/antiga','C:/p/semstop','C:/p/recente'])"
checa "desde = stop_ts (e prompt_ts == stop_ts tambem espera)" \
  "(() => { const a = d.janelas[0], b = d.janelas[1], agora = Date.now(); return Math.abs((agora - a.desde) / 60000 - 180) < 2 && Math.abs((agora - b.desde) / 60000 - 120) < 2; })()"
checa "sem linha de ociosidade: 45" "d.ociosidade_min === 45"
rodar --cwd "$RAIZ" --sessao outra-sessao
checa "a propria so sai pela chave de --sessao" "d.janelas.some(j => j.cwd === 'C:/p/propria')"

printf '# Foco\n\nOciosidade máxima: 20 min\n' > "$RAIZ/FOCO.md"
rodar --cwd "$RAIZ" --sessao eu-1
checa "Ociosidade maxima: 20 min vira 20" "d.ociosidade_min === 20"

rodar --cwd "$RAIZ"
if [ "$CODIGO" -eq 2 ]; then passa "--sessao ausente: exit 2"; else falha "--sessao ausente: exit 2" "exit=$CODIGO"; fi

printf '{quebrado' > "$RAIZ/sessoes.json"
rodar --cwd "$RAIZ" --sessao eu-1
if [ "$CODIGO" -eq 1 ]; then passa "JSON quebrado: exit 1"; else falha "JSON quebrado: exit 1" "exit=$CODIGO"; fi

rm -f "$RAIZ/sessoes.json"
rodar --cwd "$RAIZ" --sessao eu-1
if [ "$CODIGO" -eq 1 ]; then passa "sessoes.json ausente: exit 1"; else falha "sessoes.json ausente: exit 1" "exit=$CODIGO"; fi

# Caso novo: sessoes.json acima de 256 KB sai 1 sem ler
env -u FORCE_COLOR node -e "
  const min = (n) => Date.now() - n * 60000;
  const s = {};
  // Gera dados suficientes para passar de 300 KB
  for (let i = 0; i < 2000; i++) {
    const longPath = 'C:/p/projeto-' + i + '-' + 'x'.repeat(50);
    s['sessao-' + i] = {
      cwd: longPath,
      prompt_ts: min(100 + i % 50),
      stop_ts: min(90 + i % 50)
    };
  }
  require('fs').writeFileSync(process.argv[1], JSON.stringify(s));
" "$RAIZ/sessoes.json"
rodar --cwd "$RAIZ" --sessao eu-1
if [ "$CODIGO" -eq 1 ] && echo "$ERRO" | grep -q "sessoes.json" && [ -z "$SAIDA" ]; then
  passa "sessoes.json acima de 256 KB sai 1 sem ler"
else
  falha "sessoes.json acima de 256 KB sai 1 sem ler" "exit=$CODIGO stderr=$ERRO saida=$SAIDA"
fi

# Limpa FOCO.md (foi deixado do teste anterior)
rm -f "$RAIZ/FOCO.md"

# Restaura arquivo pequeno e verifica que segue funcionando
env -u FORCE_COLOR node -e "
  const min = (n) => Date.now() - n * 60000;
  const s = {
    'teste': { cwd: 'C:/p/teste', prompt_ts: min(50), stop_ts: min(40) }
  };
  require('fs').writeFileSync(process.argv[1], JSON.stringify(s));
" "$RAIZ/sessoes.json"
rodar --cwd "$RAIZ" --sessao eu-1
checa "sessoes.json pequeno ainda funciona" "d.ociosidade_min === 45"

echo "$OK ok, $FALHA falha(s), 0 skipped"
[ "$FALHA" -eq 0 ]
