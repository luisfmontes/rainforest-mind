#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria da conta em modo uma pasta (tarefa 1 de 2026-10-12-pasta-unica): scripts/conta.cjs.
# Casos: (a) sem ~/.claude-personal, status lista só a pasta trabalho e vigiar troca para a reserva
# pessoal (estacionado-trabalho.json gravado); (b) agendar real com schtasks falso: sai 0 com a reserva
# pessoal e sai 1 sem ela, sem chamar o schtasks; (c) trocar pessoal --pasta pessoal sai 2 (a pasta não
# existe); (d) preparar pessoal sem a conta registrada registra pelo /profile do login recém-feito;
# (e) login da conta de trabalho é recusado, nada gravado; (f) login sem oauthAccount é recusado, nada gravado.
# Tudo em mktemp -d com trap; o servidor é node local, morto no trap pelo PID dele. O claude e o
# schtasks são scripts node falsos (RFM_CONTA_CLAUDE, RFM_CONTA_SCHTASKS). Nunca toca ~/.claude,
# ~/.rainforest, a API real nem o schtasks real.
set -euo pipefail
cd "$(dirname "$0")/.."

win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
RAIZ="$(win "$(mktemp -d)")"
PIDS=()
trap 'for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done; rm -rf "$RAIZ"' EXIT

OK=0
FALHOU=0
afirma() {
  local nome="$1"; shift
  if "$@"; then
    OK=$((OK + 1)); echo "ok   $nome"
  else
    FALHOU=$((FALHOU + 1)); echo "FALHA $nome"
  fi
}
contem() { printf '%s\n' "$1" | grep -qF -- "$2"; }
ausente_no_arquivo() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
ler() { node "$RAIZ/ler.cjs" "$@" 2>/dev/null || printf 'AUSENTE\n'; }
sem_login() { [ -d "$1" ] && ! ls -A "$1" | grep -q '^login-'; }

# Fixtures: pastas no formato real, reservas e estado, tudo falso. Argumentos: destino, pasta pessoal
# (sim | nao), reservas (csv de team,pessoal ou vazio), contas registradas (ambas | pessoal | nenhuma),
# automático (sim | nao).
cat > "$RAIZ/semear.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const VIDA = 4102444800000;
const OAUTH = {
  team: { accountUuid: '00000000-0000-0000-0000-00000000000a', emailAddress: 'team@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Team' },
  pessoal: { accountUuid: '00000000-0000-0000-0000-00000000000b', emailAddress: 'pessoal@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Pessoal' },
};
function cred(tok, refresh) {
  return { claudeAiOauth: { accessToken: tok, refreshToken: refresh, expiresAt: VIDA, refreshTokenExpiresAt: VIDA, scopes: ['user:inference', 'user:profile'], subscriptionType: 'max', rateLimitTier: 'default_claude_max_20x' } };
}
const escrever = (arq, obj) => { fs.mkdirSync(path.dirname(arq), { recursive: true }); fs.writeFileSync(arq, JSON.stringify(obj, null, 2) + '\n'); };
const [, , destino, pessoal, reservas, contas, auto] = process.argv;
escrever(path.join(destino, 'trabalho', '.claude', '.credentials.json'), cred('falso-team-pasta', 'falso-refresh-team-pasta'));
// Formato real: o .claude.json da pasta padrão mora no home, fora da pasta (~/.claude.json), não dentro dela.
escrever(path.join(destino, 'trabalho', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.team, projects: {} });
if (pessoal === 'sim') {
  escrever(path.join(destino, 'pessoal', '.claude-personal', '.credentials.json'), cred('falso-pessoal-pasta', 'falso-refresh-pessoal-pasta'));
  escrever(path.join(destino, 'pessoal', '.claude-personal', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.pessoal, projects: {} });
}
for (const conta of reservas.split(',').filter(Boolean)) {
  escrever(path.join(destino, 'dados', 'contas', `reserva-${conta}.json`), { claudeAiOauth: cred(`falso-${conta}-reserva`, `falso-refresh-${conta}-reserva`).claudeAiOauth });
}
const estado = { automatico: auto === 'sim', contas: {} };
if (contas === 'ambas' || contas === 'pessoal') estado.contas.pessoal = { email: OAUTH.pessoal.emailAddress, oauthAccount: OAUTH.pessoal };
if (contas === 'ambas') estado.contas.team = { email: OAUTH.team.emailAddress, oauthAccount: OAUTH.team };
escrever(path.join(destino, 'dados', 'contas', 'estado.json'), estado);
JS
cat > "$RAIZ/ler.cjs" <<'JS'
const fs = require('fs');
const [, , arq, campo] = process.argv;
const o = JSON.parse(fs.readFileSync(arq, 'utf8'));
const v = campo.split('.').reduce((x, k) => (x == null ? undefined : x[k]), o);
console.log(v === undefined ? 'AUSENTE' : typeof v === 'object' ? JSON.stringify(v) : String(v));
JS

# Claude falso: grava .credentials.json (token de RFM_FAKE_TOKEN) e, como o CLI real, o .claude.json
# com o oauthAccount do login (e-mail de RFM_FAKE_EMAIL), salvo RFM_FAKE_OAUTH=sem-oauth.
# Guarda os argumentos recebidos em RFM_FAKE_LOG.
cat > "$RAIZ/claude-falso.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
fs.appendFileSync(process.env.RFM_FAKE_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
const tok = process.env.RFM_FAKE_TOKEN;
const dir = process.env.CLAUDE_CONFIG_DIR;
const VIDA = 4102444800000;
fs.writeFileSync(path.join(dir, '.credentials.json'), JSON.stringify({
  claudeAiOauth: { accessToken: tok, refreshToken: 'falso-refresh-' + tok, expiresAt: VIDA, refreshTokenExpiresAt: VIDA, scopes: ['user:inference', 'user:profile'], subscriptionType: 'max', rateLimitTier: 'default_claude_max_20x' },
}, null, 2) + '\n');
if (process.env.RFM_FAKE_OAUTH !== 'sem-oauth') {
  fs.writeFileSync(path.join(dir, '.claude.json'), JSON.stringify({
    numStartups: 1,
    oauthAccount: { accountUuid: '00000000-0000-0000-0000-000000000000', emailAddress: process.env.RFM_FAKE_EMAIL, organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa' },
  }, null, 2) + '\n');
}
JS

# Schtasks falso: grava os argumentos em RFM_SCHTASKS_LOG e sai 0. O schtasks real nunca roda.
cat > "$RAIZ/schtasks-falso.cjs" <<'JS'
const fs = require('fs');
fs.appendFileSync(process.env.RFM_SCHTASKS_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
JS

# Mapa token -> dono no servidor de teste. uso5/uso7 são os percentuais das duas janelas.
cat > "$RAIZ/mapa.json" <<'JSON'
{ "tokens": {
  "falso-team-pasta": { "email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": "team", "uso5": 98, "uso7": 10 },
  "falso-team-reserva": { "email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": "team", "uso5": 98, "uso7": 10 },
  "falso-pessoal-reserva": { "email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": "pessoal", "uso5": 10, "uso7": 10 },
  "falso-login-pessoal": { "email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": "pessoal", "uso5": 10, "uso7": 10 },
  "falso-login-team": { "email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": "team", "uso5": 98, "uso7": 10 }
} }
JSON

RFM_CONTA_SERVIDOR_MAPA="$(win "$RAIZ/mapa.json")" \
  node scripts/fixtures/conta/servidor.cjs > "$RAIZ/porta.txt" 2> "$RAIZ/servidor-erro.txt" &
PIDS+=("$!")
for _ in $(seq 1 100); do [ -s "$RAIZ/porta.txt" ] && break; sleep 0.1; done
API="http://127.0.0.1:$(head -n1 "$RAIZ/porta.txt")"

novo_caso() { # $1 = nome; $2 = pasta pessoal (sim|nao); $3 = reservas; $4 = contas; $5 = automático
  local c="$RAIZ/caso-$1"
  mkdir -p "$c"
  node "$RAIZ/semear.cjs" "$(win "$c")" "$2" "$3" "$4" "$5"
  printf '%s' "$c"
}
cli() { # $1 = caso; $2... = argumentos de conta.cjs (com RFM_TEST=1: pastas e API falsas)
  local c="$1"; shift
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
  RFM_CONTA_API="$API" \
  RFM_CONTA_SCHTASKS="$(win "$RAIZ/schtasks-falso.cjs")" \
  RFM_SCHTASKS_LOG="$(win "$c/schtasks-args.txt")" \
  node scripts/conta.cjs "$@"
}
preparar_pessoal() { # $1 = caso; $2 = token do login falso; $3 = e-mail do login; $4 = sem-oauth (opcional)
  local c="$1"
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_API="$API" \
  RFM_CONTA_CLAUDE="$(win "$RAIZ/claude-falso.cjs")" \
  RFM_FAKE_TOKEN="$2" \
  RFM_FAKE_EMAIL="$3" \
  RFM_FAKE_OAUTH="${4:-}" \
  RFM_FAKE_LOG="$(win "$c/claude-args.txt")" \
  node scripts/conta.cjs preparar pessoal
}

# (a) uma pasta: status lista só trabalho; vigiar troca para a reserva pessoal.
a_completo() {
  local c="$1" st
  [ ! -d "$c/pessoal/.claude-personal" ] || return 1
  st="$(cli "$c" 2>&1)" || return 1
  [ "$(printf '%s\n' "$st" | grep -c '^pasta ')" -eq 1 ] || return 1
  printf '%s\n' "$st" | grep -q '^pasta trabalho:' || return 1
  cli "$c" vigiar > "$RAIZ/a-vigiar.txt" 2>&1 || return 1
  [ "$(ler "$c/trabalho/.claude/.credentials.json" claudeAiOauth.accessToken)" = falso-pessoal-reserva ] || return 1
  [ "$(ler "$c/dados/contas/estacionado-trabalho.json" claudeAiOauth.accessToken)" = falso-team-pasta ] || return 1
  [ "$(ler "$c/dados/contas/reserva-pessoal.json" claudeAiOauth.accessToken)" = AUSENTE ] || return 1
}
C_A="$(novo_caso a nao 'team,pessoal' ambas sim)"
afirma "uma pasta: status lista só trabalho e vigiar troca para a reserva pessoal" a_completo "$C_A"

# Pasta padrão (achado 2, rodada 4): o .claude.json dela mora fora da pasta, em <home>/.claude.json. A troca tem de
# gravar o oauthAccount da pessoal nesse arquivo e não criar <pasta>/.claude.json (que o Claude Code não lê).
C_G="$(novo_caso g nao 'team,pessoal' ambas sim)"
RC_G=0
cli "$C_G" vigiar > "$RAIZ/g.txt" 2>&1 || RC_G=$?
troca_grava_fora_da_pasta() {
  [ "$RC_G" -eq 0 ] &&
  [ "$(ler "$C_G/trabalho/.claude.json" oauthAccount.emailAddress)" = pessoal@exemplo.invalid ] &&
  [ ! -e "$C_G/trabalho/.claude/.claude.json" ]
}
afirma "pasta padrão: a troca grava o oauthAccount no .claude.json de fora da pasta" troca_grava_fora_da_pasta

# (b) agendar real com schtasks falso.
C_B1="$(novo_caso b1 nao 'pessoal' nenhuma nao)"
RC_B1=0
cli "$C_B1" agendar > "$RAIZ/b1.txt" 2>&1 || RC_B1=$?
afirma "uma pasta: agendar com a reserva pessoal sai 0" test "$RC_B1" -eq 0
afirma "uma pasta: agendar com a reserva pessoal chama o schtasks com /Create" contem "$(cat "$C_B1/schtasks-args.txt" 2>/dev/null || true)" '"/Create"'
C_B2="$(novo_caso b2 nao '' nenhuma nao)"
RC_B2=0
cli "$C_B2" agendar > "$RAIZ/b2.txt" 2>&1 || RC_B2=$?
afirma "uma pasta: agendar sem a reserva pessoal sai 1" test "$RC_B2" -eq 1
afirma "uma pasta: agendar sem a reserva pessoal não chama o schtasks" test ! -f "$C_B2/schtasks-args.txt"

# (c) trocar pessoal --pasta pessoal: a pasta não existe.
C_C="$(novo_caso c nao 'team,pessoal' ambas sim)"
RC_C=0
cli "$C_C" trocar pessoal --pasta pessoal > "$RAIZ/c.txt" 2>&1 || RC_C=$?
afirma "uma pasta: trocar pessoal --pasta pessoal sai 2" test "$RC_C" -eq 2
afirma "uma pasta: trocar pessoal --pasta pessoal diz que a pasta não existe" contem "$(cat "$RAIZ/c.txt")" "não existe"

# (d) preparar pessoal sem a conta registrada: registra pelo /profile do login recém-feito.
C_D="$(novo_caso d nao '' nenhuma nao)"
RC_D=0
preparar_pessoal "$C_D" falso-login-pessoal pessoal@exemplo.invalid > "$RAIZ/d.txt" 2>&1 || RC_D=$?
afirma "uma pasta: preparar pessoal sem registro sai 0" test "$RC_D" -eq 0
afirma "uma pasta: preparar pessoal grava reserva-pessoal com o login" test "$(ler "$C_D/dados/contas/reserva-pessoal.json" claudeAiOauth.accessToken)" = falso-login-pessoal
afirma "uma pasta: preparar pessoal registra a conta pessoal em estado.json" test "$(ler "$C_D/dados/contas/estado.json" contas.pessoal.email)" = pessoal@exemplo.invalid
afirma "uma pasta: preparar pessoal sem registro não pede e-mail ao login" ausente_no_arquivo "$C_D/claude-args.txt" '--email'
afirma "uma pasta: preparar pessoal sem registro não imprime a credencial" ausente_no_arquivo "$RAIZ/d.txt" falso-login-pessoal
afirma "uma pasta: preparar pessoal sem registro deixa a pasta temporária sumir" sem_login "$C_D/dados/contas"

# (e) adicional: login da conta de trabalho é recusado, nada gravado.
C_E="$(novo_caso e nao '' nenhuma nao)"
RC_E=0
preparar_pessoal "$C_E" falso-login-team team@exemplo.invalid > "$RAIZ/e.txt" 2>&1 || RC_E=$?
afirma "uma pasta: login da conta de trabalho sai 3" test "$RC_E" -eq 3
afirma "uma pasta: login da conta de trabalho não grava reserva-pessoal" test ! -f "$C_E/dados/contas/reserva-pessoal.json"
afirma "uma pasta: login da conta de trabalho não registra a conta pessoal" test "$(ler "$C_E/dados/contas/estado.json" contas.pessoal)" = AUSENTE

# (f) adicional: login sem oauthAccount é recusado, nada gravado.
C_F="$(novo_caso f nao '' nenhuma nao)"
RC_F=0
preparar_pessoal "$C_F" falso-login-pessoal pessoal@exemplo.invalid sem-oauth > "$RAIZ/f.txt" 2>&1 || RC_F=$?
afirma "uma pasta: login sem oauthAccount sai 1" test "$RC_F" -eq 1
afirma "uma pasta: login sem oauthAccount não grava reserva-pessoal" test ! -f "$C_F/dados/contas/reserva-pessoal.json"
afirma "uma pasta: login sem oauthAccount não registra a conta pessoal" test "$(ler "$C_F/dados/contas/estado.json" contas.pessoal)" = AUSENTE

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
