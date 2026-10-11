#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria da troca de conta (tarefa 4 de 2026-10-10-troca-de-conta): scripts/conta.cjs.
# Casos: (a) vigiar troca a pasta trabalho para a pessoal, grava 1 evento e o status mostra;
# (b) duas rodadas de vigiar simultâneas fazem uma troca só (a trava se prova pela mensagem
# 'outra rodada em curso' e pelo evento único); (c) trocar manual e a volta desmarcam manual;
# (d) status em texto mostra por pasta a conta em uso e os percentuais; (e) eventos --desde
# filtra pelo tempo; (f) sem automatico, vigiar não troca; (g) credencial não aparece na saída.
# Tudo em mktemp -d com trap; o servidor é node local, morto no trap pelo PID dele. Nunca toca
# ~/.claude nem a pasta de dados real.
set -euo pipefail
cd "$(dirname "$0")/.."

win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
RAIZ="$(win "$(mktemp -d)")"
PIDS=()
trap 'for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null || true; done; rm -rf "$RAIZ"' EXIT

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
ler() { node "$RAIZ/ler.cjs" "$@"; }

# Fixtures: pastas no formato real, reservas e mapa token -> conta, tudo falso.
cat > "$RAIZ/semear.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const VIDA = 4102444800000;
const TOKENS = {
  'falso-team-pasta': { email: 'team@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000a', uso: 'team' },
  'falso-team-reserva': { email: 'team@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000a', uso: 'team' },
  'falso-pessoal-pasta': { email: 'pessoal@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000b', uso: 'pessoal' },
  'falso-pessoal-reserva': { email: 'pessoal@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000b', uso: 'pessoal' },
};
const OAUTH = {
  team: { accountUuid: '00000000-0000-0000-0000-00000000000a', emailAddress: 'team@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Team' },
  pessoal: { accountUuid: '00000000-0000-0000-0000-00000000000b', emailAddress: 'pessoal@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Pessoal' },
};
function cred(tok, refresh) {
  return {
    mcpOAuth: { 'servidor-falso': { accessToken: 'falso-mcp-' + tok, refreshToken: 'falso-mcp-refresh-' + tok, expiresAt: 1, scope: 'a b' } },
    claudeAiOauth: { accessToken: tok, refreshToken: refresh, expiresAt: VIDA, refreshTokenExpiresAt: VIDA, scopes: ['user:inference', 'user:profile'], subscriptionType: 'max', rateLimitTier: 'default_claude_max_20x' },
    trustedDeviceToken: 'falso-tdt-' + tok,
  };
}
const escrever = (arq, obj) => { fs.mkdirSync(path.dirname(arq), { recursive: true }); fs.writeFileSync(arq, JSON.stringify(obj, null, 2) + '\n'); };
const [, , modo, destino, auto] = process.argv;
if (modo === 'mapa') {
  escrever(destino, { tokens: TOKENS });
} else {
  escrever(path.join(destino, 'trabalho', '.claude', '.credentials.json'), cred('falso-team-pasta', 'falso-refresh-team-pasta'));
  escrever(path.join(destino, 'trabalho', '.claude', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.team, projects: {} });
  escrever(path.join(destino, 'pessoal', '.claude-personal', '.credentials.json'), cred('falso-pessoal-pasta', 'falso-refresh-pessoal-pasta'));
  escrever(path.join(destino, 'pessoal', '.claude-personal', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.pessoal, projects: {} });
  escrever(path.join(destino, 'dados', 'contas', 'reserva-team.json'), { claudeAiOauth: cred('falso-team-reserva', 'falso-refresh-team-reserva').claudeAiOauth });
  escrever(path.join(destino, 'dados', 'contas', 'reserva-pessoal.json'), { claudeAiOauth: cred('falso-pessoal-reserva', 'falso-refresh-pessoal-reserva').claudeAiOauth });
  escrever(path.join(destino, 'dados', 'contas', 'estado.json'), { automatico: auto === 'sim' });
}
JS
cat > "$RAIZ/ler.cjs" <<'JS'
const fs = require('fs');
const [, , arq, campo] = process.argv;
const o = JSON.parse(fs.readFileSync(arq, 'utf8'));
const v = campo.split('.').reduce((x, k) => (x == null ? undefined : x[k]), o);
console.log(v === undefined ? 'AUSENTE' : typeof v === 'object' ? JSON.stringify(v) : String(v));
JS
node "$RAIZ/semear.cjs" mapa "$RAIZ/mapa.json"
node -e "const fs=require('fs');const m=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));m.tokens['falso-pessoal-reserva'].email='outro@exemplo.invalid';fs.writeFileSync(process.argv[2],JSON.stringify(m))" "$RAIZ/mapa.json" "$RAIZ/mapa-h.json"

# Servidores de teste: porta livre, mortos no trap. A rodada (b) segura o /usage com o arquivo
# 'segurar'. O segundo servidor (caso h) confere outro e-mail para a reserva de pessoal.
API=""
iniciar_servidor() { # $1 = mapa token -> conta; $2 = arquivo onde sai a porta
  RFM_CONTA_SERVIDOR_MAPA="$(win "$1")" \
  RFM_CONTA_SERVIDOR_CONTROLE="$(win "$RAIZ/segurar")" \
    node scripts/fixtures/conta/servidor.cjs > "$2" 2> "$RAIZ/servidor-erro.txt" &
  PIDS+=("$!")
  for _ in $(seq 1 100); do [ -s "$2" ] && break; sleep 0.1; done
  API="http://127.0.0.1:$(head -n1 "$2")"
}
iniciar_servidor "$RAIZ/mapa.json" "$RAIZ/porta.txt"
API_PRINCIPAL="$API"
iniciar_servidor "$RAIZ/mapa-h.json" "$RAIZ/porta-h.txt"
API_H="$API"
API="$API_PRINCIPAL"

novo_caso() {
  local c="$RAIZ/caso-$1"
  mkdir -p "$c"
  node "$RAIZ/semear.cjs" caso "$c" "$2"
  printf '%s' "$c"
}
cli() {
  local c="$1"; shift
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_API="$API" \
  node scripts/conta.cjs "$@"
}

# (a) vigiar troca trabalho -> pessoal
C_A="$(novo_caso a sim)"
EST_A="$C_A/dados/contas/estado.json"
EV_A="$C_A/dados/contas/eventos.jsonl"
RC_A=0
cli "$C_A" vigiar > "$RAIZ/a-vigiar.txt" 2>&1 || RC_A=$?
afirma "(a) vigiar sai 0" test "$RC_A" -eq 0
afirma "(a) vigiar troca a pasta trabalho para a conta pessoal" test "$(ler "$EST_A" pastas.trabalho.conta)" = pessoal
afirma "(a) vigiar grava 1 linha em eventos.jsonl" test -f "$EV_A" -a "$(wc -l < "$EV_A" | tr -d ' ')" = 1
afirma "(a) trava solta no fim da rodada" test ! -e "$C_A/dados/contas/vigia.lock"
ST_A="$(cli "$C_A" status)"
printf '%s\n' "$ST_A" > "$RAIZ/status-a.txt"
afirma "(a) status mostra a pasta trabalho na conta pessoal" contem "$ST_A" "pasta trabalho: conta em uso pessoal"

# (b) duas rodadas simultâneas: a primeira segura a trava (o servidor segura o /usage); a segunda
# tem de bater na trava e imprimir 'outra rodada em curso'. Sem a trava, nenhuma imprime isso.
C_B="$(novo_caso b sim)"
EV_B="$C_B/dados/contas/eventos.jsonl"
: > "$RAIZ/segurar"
cli "$C_B" vigiar > "$RAIZ/b1.txt" 2>&1 &
P1=$!
PIDS+=("$P1")
for _ in $(seq 1 30); do [ -e "$C_B/dados/contas/vigia.lock" ] && break; sleep 0.1; done
cli "$C_B" vigiar > "$RAIZ/b2.txt" 2>&1 &
P2=$!
PIDS+=("$P2")
RC_B1=0; wait "$P1" || RC_B1=$?
RC_B2=0; wait "$P2" || RC_B2=$?
rm -f "$RAIZ/segurar"
caso_b() {
  contem "$(cat "$RAIZ/b1.txt" "$RAIZ/b2.txt")" "outra rodada em curso" \
    && [ -f "$EV_B" ] && [ "$(wc -l < "$EV_B" | tr -d ' ')" = 1 ]
}
afirma "duas rodadas de vigiar simultâneas fazem uma troca só" caso_b

# (c) trocar manual; trocar de volta desfaz e desmarca manual
C_C="$(novo_caso c nao)"
EST_C="$C_C/dados/contas/estado.json"
RC_C1=0
cli "$C_C" trocar pessoal --pasta trabalho > "$RAIZ/c1.txt" 2>&1 || RC_C1=$?
caso_c1() {
  [ "$RC_C1" -eq 0 ] && [ "$(ler "$EST_C" pastas.trabalho.conta)" = pessoal ] && [ "$(ler "$EST_C" pastas.trabalho.manual)" = true ]
}
afirma "(c) trocar pessoal --pasta trabalho põe a pasta na conta pessoal, marcada manual" caso_c1
RC_C2=0
cli "$C_C" trocar trabalho --pasta trabalho > "$RAIZ/c2.txt" 2>&1 || RC_C2=$?
caso_c2() {
  [ "$RC_C2" -eq 0 ] && [ "$(ler "$EST_C" pastas.trabalho.conta)" = team ] \
    && [ "$(ler "$EST_C" pastas.trabalho.manual)" = false ] && [ "$(ler "$EST_C" pastas.trabalho.travouPor)" = null ]
}
afirma "(c) trocar trabalho --pasta trabalho desfaz e desmarca manual" caso_c2

# (d) status em texto: por pasta, a conta em uso; e os dois percentuais das duas contas
caso_d() {
  contem "$ST_A" "pasta trabalho: conta em uso pessoal (pessoal@exemplo.invalid)" \
    && contem "$ST_A" "· fora de casa" \
    && contem "$ST_A" "pasta pessoal: conta em uso pessoal" \
    && contem "$ST_A" "  trabalho: 5 h 2% · semana 97%" \
    && contem "$ST_A" "  pessoal: 5 h 2% · semana 7%" \
    && ! contem "$ST_A" "{"
}
afirma "(d) status em texto mostra, por pasta, a conta em uso e os percentuais das duas contas" caso_d

# (e) eventos --desde filtra pelo tempo
EM_A="$(head -n1 "$EV_A" | node -e 'let s="";process.stdin.on("data",(d)=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).em)))')"
caso_e() {
  [ "$(cli "$C_A" eventos --desde "$((EM_A - 1))" | grep -c .)" = 1 ] \
    && [ "$(cli "$C_A" eventos --desde "$EM_A" | grep -c . || true)" = 0 ]
}
afirma "(e) eventos --desde filtra pelo tempo" caso_e

# (f) sem automatico, vigiar não troca
C_F="$(novo_caso f nao)"
cp "$C_F/trabalho/.claude/.credentials.json" "$RAIZ/cred-f-antes.json"
RC_F=0
cli "$C_F" vigiar > "$RAIZ/f.txt" 2>&1 || RC_F=$?
caso_f() {
  [ "$RC_F" -eq 0 ] && contem "$(cat "$RAIZ/f.txt")" "troca automática desligada" \
    && [ ! -e "$C_F/dados/contas/eventos.jsonl" ] \
    && cmp -s "$C_F/trabalho/.claude/.credentials.json" "$RAIZ/cred-f-antes.json" \
    && contem "$(cli "$C_F" status)" "pasta trabalho: conta em uso trabalho"
}
afirma "(f) sem automatico, vigiar não troca" caso_f

# (h) a conferência no servidor não bate (a reserva de pessoal responde outro e-mail): a troca
# é desfeita, a pasta fica na conta de origem e o evento 'falhou' é gravado.
C_H="$(novo_caso h sim)"
EST_H="$C_H/dados/contas/estado.json"
EV_H="$C_H/dados/contas/eventos.jsonl"
cp "$C_H/trabalho/.claude/.credentials.json" "$RAIZ/cred-h-antes.json"
RC_H=0
API="$API_H"
cli "$C_H" vigiar > "$RAIZ/h.txt" 2>&1 || RC_H=$?
API="$API_PRINCIPAL"
caso_h() {
  [ "$RC_H" -eq 1 ] && [ "$(ler "$EST_H" pastas.trabalho.conta)" = team ] \
    && cmp -s "$C_H/trabalho/.claude/.credentials.json" "$RAIZ/cred-h-antes.json" \
    && grep -qF '"tipo":"falhou"' "$EV_H"
}
afirma "(h) conferência diferente no servidor desfaz a troca e registra falhou" caso_h

# (i) troca automática e depois volta manual: a pasta volta com o login original dela, as duas
# reservas ficam com os refreshToken de antes e os dois estacionados ficam vazios.
ler_ou_ausente() { if [ -f "$1" ]; then ler "$1" claudeAiOauth.refreshToken; else echo AUSENTE; fi; }
C_I="$(novo_caso i sim)"
EST_I="$C_I/dados/contas/estado.json"
RES_TEAM_I="$C_I/dados/contas/reserva-team.json"
RES_PES_I="$C_I/dados/contas/reserva-pessoal.json"
PASTA_CRED_I="$C_I/trabalho/.claude/.credentials.json"
REF_PASTA_I="$(ler "$PASTA_CRED_I" claudeAiOauth.refreshToken)"
REF_TEAM_I="$(ler "$RES_TEAM_I" claudeAiOauth.refreshToken)"
REF_PES_I="$(ler "$RES_PES_I" claudeAiOauth.refreshToken)"
RC_I1=0
cli "$C_I" vigiar > "$RAIZ/i-vigiar.txt" 2>&1 || RC_I1=$?
MEIO_I="$(ler "$EST_I" pastas.trabalho.conta)"
RC_I2=0
cli "$C_I" trocar trabalho --pasta trabalho > "$RAIZ/i-trocar.txt" 2>&1 || RC_I2=$?
caso_i() {
  [ "$RC_I1" -eq 0 ] && [ "$MEIO_I" = pessoal ] && [ "$RC_I2" -eq 0 ] \
    && [ "$(ler "$PASTA_CRED_I" claudeAiOauth.refreshToken)" = "$REF_PASTA_I" ] \
    && [ "$(ler "$RES_TEAM_I" claudeAiOauth.refreshToken)" = "$REF_TEAM_I" ] \
    && [ "$(ler "$RES_PES_I" claudeAiOauth.refreshToken)" = "$REF_PES_I" ] \
    && [ "$(ler_ou_ausente "$C_I/dados/contas/estacionado-trabalho.json")" = AUSENTE ] \
    && [ "$(ler_ou_ausente "$C_I/dados/contas/estacionado-pessoal.json")" = AUSENTE ]
}
afirma "troca e volta preservam as duas reservas" caso_i

# (j) sem --pasta, a troca manual age na pasta da sessão que chamou (CLAUDE_CONFIG_DIR)
C_J="$(novo_caso j nao)"
EST_J="$C_J/dados/contas/estado.json"
RC_J=0
CLAUDE_CONFIG_DIR="$(win "$C_J/pessoal/.claude-personal")" cli "$C_J" trabalho > "$RAIZ/j.txt" 2>&1 || RC_J=$?
caso_j() {
  [ "$RC_J" -eq 0 ] && [ "$(ler "$EST_J" pastas.pessoal.conta)" = team ]     && [ "$(ler "$EST_J" pastas.trabalho.conta)" = team ]
}
afirma "(j) sessão da pasta pessoal: /conta trabalho troca a pasta pessoal, não a de trabalho" caso_j

# (g) nenhuma credencial (valor falso ou não) aparece na saída nem no log
caso_g() {
  local rc=0
  grep -qF "falso-" "$RAIZ/a-vigiar.txt" "$RAIZ/b1.txt" "$RAIZ/b2.txt" "$RAIZ/c1.txt" "$RAIZ/c2.txt" \
    "$RAIZ/f.txt" "$RAIZ/h.txt" "$RAIZ/status-a.txt" "$EV_A" "$EV_H" || rc=$?
  [ "$rc" -eq 1 ]
}
afirma "(g) credencial nunca aparece na saída nem no log" caso_g

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
