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
REPO="$(win "$PWD")"
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

# Ajuda das rodadas 2 e seguintes. derivar.cjs copia um mapa e aplica um ajuste (tokens vencidos,
# refresh tokens girando, resets_at e uso por caso). post.cjs imprime o HTTP que o servidor falso
# devolve a uma renovação com o refresh token dado (prova que o antigo deixou de valer).
cat > "$RAIZ/derivar.cjs" <<'JS'
const fs = require('fs');
const [, , entrada, saida, ajuste] = process.argv;
const m = JSON.parse(fs.readFileSync(entrada, 'utf8'));
const a = JSON.parse(ajuste);
for (const t of a.venceu || []) m.tokens[t].venceu = true;
for (const [t, extra] of Object.entries(a.tokens || {})) Object.assign(m.tokens[t], extra);
if (a.refresh) m.refresh = a.refresh;
if (a.renovacaoStatus) m.renovacaoStatus = a.renovacaoStatus;
fs.writeFileSync(saida, JSON.stringify(m));
JS
cat > "$RAIZ/post.cjs" <<'JS'
const [, , api, velho] = process.argv;
const corpo = { grant_type: 'refresh_token', client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e', scope: 'user:inference user:profile', refresh_token: velho };
fetch(api + '/v1/oauth/token', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
  .then((r) => console.log(r.status));
JS
# ajustar.cjs trocado <caso>: põe a pasta trabalho (casa: team) na conta pessoal, com o login da
# reserva-pessoal; o login dela vai para estacionado-trabalho e a reserva-pessoal fica vazia.
# reserva-team e estacionado-trabalho ficam com o access token VENCIDO (expiresAt no passado).
cat > "$RAIZ/ajustar.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const [, , acao, caso] = process.argv;
const ler = (a) => JSON.parse(fs.readFileSync(a, 'utf8'));
const gravar = (a, o) => fs.writeFileSync(a, JSON.stringify(o, null, 2) + '\n');
const pastaT = path.join(caso, 'trabalho', '.claude');
const pastaP = path.join(caso, 'pessoal', '.claude-personal');
const contas = path.join(caso, 'dados', 'contas');
if (acao === 'trocado') {
  const passado = Date.now() - 60000;
  const credT = ler(path.join(pastaT, '.credentials.json'));
  const resP = ler(path.join(contas, 'reserva-pessoal.json'));
  gravar(path.join(contas, 'estacionado-trabalho.json'), { claudeAiOauth: { ...credT.claudeAiOauth, expiresAt: passado } });
  credT.claudeAiOauth = resP.claudeAiOauth;
  gravar(path.join(pastaT, '.credentials.json'), credT);
  gravar(path.join(contas, 'reserva-pessoal.json'), {});
  const resT = ler(path.join(contas, 'reserva-team.json'));
  resT.claudeAiOauth.expiresAt = passado;
  gravar(path.join(contas, 'reserva-team.json'), resT);
  const claudeT = ler(path.join(pastaT, '.claude.json'));
  const oauthTeam = claudeT.oauthAccount;
  const oauthPessoal = ler(path.join(pastaP, '.claude.json')).oauthAccount;
  claudeT.oauthAccount = oauthPessoal;
  gravar(path.join(pastaT, '.claude.json'), claudeT);
  gravar(path.join(contas, 'estado.json'), {
    automatico: true,
    pastas: { trabalho: { conta: 'pessoal', manual: false, travouPor: { limite: 'seven_day', resetsAt: new Date(Date.now() - 3600000).toISOString() } } },
    contas: { team: { email: oauthTeam.emailAddress, oauthAccount: oauthTeam }, pessoal: { email: oauthPessoal.emailAddress, oauthAccount: oauthPessoal } },
  });
}
const VIDA = 4102444800000;
const loginPessoalOutro = () => ({ accessToken: 'falso-pessoal-reserva', refreshToken: 'falso-refresh-pessoal-outro', expiresAt: VIDA, scopes: ['user:inference', 'user:profile'] });
// ocupada: depois de 'trocado', a reserva-pessoal (que deveria estar vazia) tem outro login.
if (acao === 'ocupada') {
  gravar(path.join(contas, 'reserva-pessoal.json'), { claudeAiOauth: loginPessoalOutro() });
}
// divergente: a pasta trabalho (em casa, conta team) tem o login de outro: o da conta pessoal.
// O estado já registra as duas contas.
if (acao === 'divergente') {
  const credT = ler(path.join(pastaT, '.credentials.json'));
  credT.claudeAiOauth = { ...credT.claudeAiOauth, ...loginPessoalOutro() };
  gravar(path.join(pastaT, '.credentials.json'), credT);
  const claudeT = ler(path.join(pastaT, '.claude.json'));
  const oauthTeam = claudeT.oauthAccount;
  const oauthPessoal = ler(path.join(pastaP, '.claude.json')).oauthAccount;
  claudeT.oauthAccount = oauthPessoal;
  gravar(path.join(pastaT, '.claude.json'), claudeT);
  gravar(path.join(contas, 'estado.json'), {
    automatico: false,
    contas: { team: { email: oauthTeam.emailAddress, oauthAccount: oauthTeam }, pessoal: { email: oauthPessoal.emailAddress, oauthAccount: oauthPessoal } },
  });
}
// duplicada: a reserva-team recebe o MESMO login da pasta trabalho (mesmo refresh token).
if (acao === 'duplicada') {
  const credT = ler(path.join(pastaT, '.credentials.json'));
  gravar(path.join(contas, 'reserva-team.json'), { claudeAiOauth: credT.claudeAiOauth });
}
JS
GIROS='{"falso-refresh-team-pasta":{"de":"falso-team-pasta"},"falso-refresh-team-reserva":{"de":"falso-team-reserva"}}'

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

# (k) volta automática com credencial VENCIDA: a pasta trabalho está na conta pessoal, o limite
# que a travou já resetou, e a reserva-team e o estacionado-trabalho têm o access token vencido
# (o servidor falso responde 401 a ele). O vigia renova os dois (o refresh token gira no mesmo
# arquivo e o antigo passa a ser recusado) e só então volta a pasta à conta team.
C_K="$(novo_caso k sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_K"
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-k.json" \
  "{\"venceu\":[\"falso-team-pasta\",\"falso-team-reserva\"],\"refresh\":$GIROS}"
iniciar_servidor "$RAIZ/mapa-k.json" "$RAIZ/porta-k.txt"
API_K="$API"
API="$API_PRINCIPAL"
EST_K="$C_K/dados/contas/estado.json"
EV_K="$C_K/dados/contas/eventos.jsonl"
PASTA_K="$C_K/trabalho/.claude/.credentials.json"
REF_ESTAC_K="$(ler "$C_K/dados/contas/estacionado-trabalho.json" claudeAiOauth.refreshToken)"
REF_RESERVA_K="$(ler "$C_K/dados/contas/reserva-team.json" claudeAiOauth.refreshToken)"
RC_K=0
API="$API_K"
cli "$C_K" vigiar > "$RAIZ/k.txt" 2>&1 || RC_K=$?
API="$API_PRINCIPAL"
AGORA_MS="$(node -e 'process.stdout.write(String(Date.now()))')"
caso_k() {
  [ "$RC_K" -eq 0 ] && [ "$(ler "$EST_K" pastas.trabalho.conta)" = team ] \
    && grep -qF '"tipo":"voltar"' "$EV_K" \
    && [ "$(ler "$PASTA_K" claudeAiOauth.refreshToken)" != "$REF_ESTAC_K" ] \
    && [ "$(ler "$C_K/dados/contas/reserva-team.json" claudeAiOauth.refreshToken)" != "$REF_RESERVA_K" ] \
    && [ "$(ler "$PASTA_K" claudeAiOauth.expiresAt)" -gt "$AGORA_MS" ] \
    && [ "$(ler "$C_K/dados/contas/reserva-team.json" claudeAiOauth.expiresAt)" -gt "$AGORA_MS" ] \
    && [ "$(node "$RAIZ/post.cjs" "$API_K" "$REF_ESTAC_K")" = 400 ] \
    && [ "$(node "$RAIZ/post.cjs" "$API_K" "$REF_RESERVA_K")" = 400 ]
}
afirma "(k) volta automática com reserva e estacionado vencidos" caso_k

# (k2) a renovação responde 500: a rodada não cai (sai 0), a pasta fica onde está, o evento
# renovacao_falhou é gravado sem credencial, e o status também funciona.
C_K2="$(novo_caso k2 sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_K2"
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-k2.json" \
  "{\"venceu\":[\"falso-team-pasta\",\"falso-team-reserva\"],\"refresh\":$GIROS,\"renovacaoStatus\":500}"
iniciar_servidor "$RAIZ/mapa-k2.json" "$RAIZ/porta-k2.txt"
API_K2="$API"
API="$API_PRINCIPAL"
EV_K2="$C_K2/dados/contas/eventos.jsonl"
cp "$C_K2/trabalho/.claude/.credentials.json" "$RAIZ/cred-k2-antes.json"
RC_K2=0; RC_K2S=0
API="$API_K2"
cli "$C_K2" vigiar > "$RAIZ/k2.txt" 2>&1 || RC_K2=$?
cli "$C_K2" status > "$RAIZ/k2-status.txt" 2>&1 || RC_K2S=$?
API="$API_PRINCIPAL"
caso_k2() {
  [ "$RC_K2" -eq 0 ] && [ "$RC_K2S" -eq 0 ] \
    && [ "$(ler "$C_K2/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && cmp -s "$C_K2/trabalho/.claude/.credentials.json" "$RAIZ/cred-k2-antes.json" \
    && grep -qF '"tipo":"renovacao_falhou"' "$EV_K2" \
    && contem "$(cat "$RAIZ/k2.txt")" "esperar trabalho"
}
afirma "(k2) renovação 500 não derruba a rodada: grava renovacao_falhou e espera" caso_k2
# A falha de renovação não pode ficar invisível: o status mostra a última, por login guardado, com o
# caminho para refazer a reserva, e o evento leva o login e o erro (sem credencial).
caso_k2_visivel() {
  contem "$(cat "$RAIZ/k2-status.txt")" "aviso: a renovação de reserva-team falhou em " \
    && contem "$(cat "$RAIZ/k2-status.txt")" "(token HTTP 500); se o servidor recusa, refaça: preparar trabalho --refazer" \
    && grep -F '"tipo":"renovacao_falhou"' "$EV_K2" | grep -qF '"motivo":"reserva-team: token HTTP 500"'
}
afirma "status mostra a última falha de renovação por login e como refazer" caso_k2_visivel

# (n) leitura de uso velha (429 devolve a última, de 3 h atrás, a 99%) não decide troca: a conta
# fica sem dado e a pasta fica onde está.
C_N="$(novo_caso n sim)"
node -e "
const fs = require('fs');
const velho = { five_hour: { utilization: 99, resets_at: new Date(Date.now() + 3600000).toISOString() }, seven_day: { utilization: 99, resets_at: new Date(Date.now() + 86400000).toISOString() } };
fs.writeFileSync(process.argv[1], JSON.stringify({ team: { esperaAte: Date.now() + 600000, leitura: { em: Date.now() - 3 * 3600000, dados: velho } } }));
" "$C_N/dados/contas/uso-cache.json"
RC_N=0
cli "$C_N" vigiar > "$RAIZ/n.txt" 2>&1 || RC_N=$?
caso_n() {
  [ "$RC_N" -eq 0 ] && [ "$(ler "$C_N/dados/contas/estado.json" pastas.trabalho.conta)" = team ] \
    && [ ! -e "$C_N/dados/contas/eventos.jsonl" ] && contem "$(cat "$RAIZ/n.txt")" "esperar trabalho: sem dado de uso de team"
}
afirma "(n) leitura de uso de 3 h atrás não decide troca" caso_n

# (o) o estado diz "em casa" mas a pasta trabalho tem o login da conta pessoal (um desfazer que
# falhou deixa isso): status NÃO reescreve contas.team, nem o estado, e grava identidade_divergente.
C_O="$(novo_caso o nao)"
node "$RAIZ/ajustar.cjs" divergente "$C_O"
EST_O="$C_O/dados/contas/estado.json"
EV_O="$C_O/dados/contas/eventos.jsonl"
cp "$EST_O" "$RAIZ/estado-o-antes.json"
RC_O=0
cli "$C_O" status > "$RAIZ/o.txt" 2>&1 || RC_O=$?
caso_o() {
  [ "$RC_O" -eq 0 ] && [ "$(ler "$EST_O" contas.team.email)" = team@exemplo.invalid ] \
    && cmp -s "$EST_O" "$RAIZ/estado-o-antes.json" \
    && grep -qF '"tipo":"identidade_divergente"' "$EV_O" && grep -qF '"pasta":"trabalho"' "$EV_O"
}
afirma "(o) status não sobrescreve o e-mail registrado e grava identidade_divergente" caso_o

# (p) o mesmo refresh token na pasta trabalho e na reserva-team: o vigia grava credencial_duplicada
# e não move nada (a team está a 97% na semana: sem a checagem, trocaria); o status avisa.
C_P="$(novo_caso p sim)"
node "$RAIZ/ajustar.cjs" duplicada "$C_P"
EV_P="$C_P/dados/contas/eventos.jsonl"
cp "$C_P/trabalho/.claude/.credentials.json" "$RAIZ/cred-p-antes.json"
cp "$C_P/dados/contas/reserva-team.json" "$RAIZ/reserva-p-antes.json"
RC_P=0
cli "$C_P" vigiar > "$RAIZ/p.txt" 2>&1 || RC_P=$?
cli "$C_P" status > "$RAIZ/p-status.txt" 2>&1 || true
caso_p() {
  [ "$RC_P" -eq 1 ] && grep -qF '"tipo":"credencial_duplicada"' "$EV_P" \
    && grep -qF 'pasta-trabalho e reserva-team' "$EV_P" \
    && [ "$(ler "$C_P/dados/contas/estado.json" pastas.trabalho.conta)" = team ] \
    && cmp -s "$C_P/trabalho/.claude/.credentials.json" "$RAIZ/cred-p-antes.json" \
    && cmp -s "$C_P/dados/contas/reserva-team.json" "$RAIZ/reserva-p-antes.json" \
    && ! grep -qF '"tipo":"trocar"' "$EV_P" \
    && contem "$(cat "$RAIZ/p-status.txt")" "aviso: o mesmo login"
}
afirma "(p) credencial_duplicada: o vigia grava o evento, não move e o status avisa" caso_p

# (q) volta que falha (a reserva-pessoal, que devia estar vazia, tem outro login → saida_ocupada)
# grava o evento falhou com o motivo, não só uma linha no stdout, e sai 1.
C_Q="$(novo_caso q sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_Q"
node "$RAIZ/ajustar.cjs" ocupada "$C_Q"
iniciar_servidor "$RAIZ/mapa-k.json" "$RAIZ/porta-q.txt"
API_Q="$API"
API="$API_PRINCIPAL"
EV_Q="$C_Q/dados/contas/eventos.jsonl"
cp "$C_Q/trabalho/.claude/.credentials.json" "$RAIZ/cred-q-antes.json"
RC_Q=0
API="$API_Q"
cli "$C_Q" vigiar > "$RAIZ/q.txt" 2>&1 || RC_Q=$?
API="$API_PRINCIPAL"
caso_q() {
  [ "$RC_Q" -eq 1 ] && [ "$(ler "$C_Q/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && cmp -s "$C_Q/trabalho/.claude/.credentials.json" "$RAIZ/cred-q-antes.json" \
    && grep -F '"tipo":"falhou"' "$EV_Q" | grep -qF 'saida_ocupada' \
    && contem "$(cat "$RAIZ/q.txt")" "não feita: saida_ocupada"
}
afirma "(q) volta que falha grava o evento falhou com o motivo" caso_q

# (m) a team a 99% nas duas janelas, a de 5 h resetando antes da semana: a volta espera o reset
# MAIS TARDIO. travouPor.limite tem de ser seven_day (e o evento, voltaEm = o reset da semana).
RESET5_M="$(node -e 'process.stdout.write(new Date(Date.now() + 3 * 3600000).toISOString())')"
RESET7_M="$(node -e 'process.stdout.write(new Date(Date.now() + 2 * 86400000).toISOString())')"
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-m.json" \
  "{\"tokens\":{\"falso-team-pasta\":{\"uso5\":99,\"uso7\":99,\"reset5\":\"$RESET5_M\",\"reset7\":\"$RESET7_M\"}}}"
iniciar_servidor "$RAIZ/mapa-m.json" "$RAIZ/porta-m.txt"
API_M="$API"
API="$API_PRINCIPAL"
C_M="$(novo_caso m sim)"
EST_M="$C_M/dados/contas/estado.json"
RC_M=0
API="$API_M"
cli "$C_M" vigiar > "$RAIZ/m.txt" 2>&1 || RC_M=$?
API="$API_PRINCIPAL"
caso_m() {
  [ "$RC_M" -eq 0 ] && [ "$(ler "$EST_M" pastas.trabalho.conta)" = pessoal ] \
    && [ "$(ler "$EST_M" pastas.trabalho.travouPor.limite)" = seven_day ] \
    && [ "$(ler "$EST_M" pastas.trabalho.travouPor.resetsAt)" = "$RESET7_M" ]
}
afirma "(m) com os dois limites passados, a volta espera o reset mais tardio" caso_m

# (r) recuo: o /profile da reserva-pessoal responde 500, então a conferência da troca falha e a
# troca é desfeita. Duas rodadas seguidas fazem UMA tentativa só (um evento falhou); a segunda
# espera o recuo de 15 min em vez de trocar e desfazer de novo.
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-r.json" '{"tokens":{"falso-pessoal-reserva":{"perfilStatus":500}}}'
iniciar_servidor "$RAIZ/mapa-r.json" "$RAIZ/porta-r.txt"
API_R="$API"
API="$API_PRINCIPAL"
C_R="$(novo_caso r sim)"
EV_R="$C_R/dados/contas/eventos.jsonl"
RC_R1=0; RC_R2=0
API="$API_R"
cli "$C_R" vigiar > "$RAIZ/r1.txt" 2>&1 || RC_R1=$?
cp "$C_R/trabalho/.claude/.credentials.json" "$RAIZ/cred-r-antes.json"
cli "$C_R" vigiar > "$RAIZ/r2.txt" 2>&1 || RC_R2=$?
API="$API_PRINCIPAL"
caso_r() {
  [ "$RC_R1" -eq 1 ] && [ "$RC_R2" -eq 0 ] \
    && [ "$(grep -cF '"tipo":"falhou"' "$EV_R")" = 1 ] \
    && contem "$(cat "$RAIZ/r2.txt")" "recuo de 15 min" \
    && cmp -s "$C_R/trabalho/.claude/.credentials.json" "$RAIZ/cred-r-antes.json" \
    && [ "$(ler "$C_R/dados/contas/estado.json" pastas.trabalho.conta)" = team ]
}
afirma "(r) com o /profile falhando, duas rodadas fazem uma tentativa só (recuo)" caso_r

# (s) a pasta de dados é a do usuário mesmo com o cwd num projeto que tem .rainforest/FOCO.md:
# o status lê as reservas do home, e nada é criado dentro do projeto.
C_S="$(novo_caso s nao)"
HOME_S="$C_S/home"
PROJ_S="$C_S/projeto"
mkdir -p "$HOME_S" "$PROJ_S/.rainforest"
cp -r "$C_S/dados" "$HOME_S/.rainforest"
: > "$HOME_S/.rainforest/FOCO.md"
: > "$PROJ_S/.rainforest/FOCO.md"
RC_S=0
( cd "$PROJ_S" && env -u RFM_ROOT -u RFM_CONTA_DADOS \
    HOME="$(win "$HOME_S")" USERPROFILE="$(win "$HOME_S")" CLAUDE_PROJECT_DIR="$(win "$PROJ_S")" \
    RFM_TEST=1 \
    RFM_CONTA_PASTA_TRABALHO="$(win "$C_S/trabalho/.claude")" \
    RFM_CONTA_PASTA_PESSOAL="$(win "$C_S/pessoal/.claude-personal")" \
    RFM_CONTA_API="$API" \
    node "$REPO/scripts/conta.cjs" status ) > "$RAIZ/s.txt" 2>&1 || RC_S=$?
caso_s() {
  [ "$RC_S" -eq 0 ] && contem "$(cat "$RAIZ/s.txt")" "reservas: trabalho presente · pessoal presente" \
    && [ ! -e "$PROJ_S/.rainforest/contas" ] && [ -d "$HOME_S/.rainforest/contas" ]
}
afirma "(s) a pasta de dados é a do usuário, não a do projeto com .rainforest/FOCO.md" caso_s

# (t) eventos com linhas corrompidas (lixo, null, número): sai 0 e lista só as válidas.
C_T="$(novo_caso t nao)"
mkdir -p "$C_T/dados/contas"
printf '%s\n' '{"em":100,"tipo":"trocar","pasta":"trabalho"}' 'isto{não é json' 'null' '42' '{"em":200,"tipo":"voltar","pasta":"trabalho"}' \
  > "$C_T/dados/contas/eventos.jsonl"
RC_T=0
cli "$C_T" eventos --desde 0 > "$RAIZ/t.txt" 2>&1 || RC_T=$?
caso_t() {
  [ "$RC_T" -eq 0 ] && [ "$(grep -c . "$RAIZ/t.txt")" = 2 ] && grep -qF '"em":200' "$RAIZ/t.txt"
}
afirma "(t) eventos com linha corrompida sai 0 e lista as válidas" caso_t

# (u) trava vencida: quatro rodadas largam juntas, todas a veem vencida, e só uma a toma. O resto
# imprime 'outra rodada em curso'; a troca acontece uma vez só e não sobra arquivo da tomada.
C_U="$(novo_caso u sim)"
mkdir -p "$C_U/dados/contas"
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({ pid: 999999, em: 0 }))" "$C_U/dados/contas/vigia.lock"
: > "$RAIZ/segurar"
PIDS_U=()
for n in 1 2 3 4; do
  cli "$C_U" vigiar > "$RAIZ/u$n.txt" 2>&1 &
  PIDS_U+=("$!")
  PIDS+=("$!")
done
for p in "${PIDS_U[@]}"; do wait "$p" || true; done
rm -f "$RAIZ/segurar"
caso_u() {
  local cont
  cont="$(cat "$RAIZ"/u[1-4].txt | grep -cF 'outra rodada em curso' || true)"
  [ "$cont" = 3 ] && [ "$(grep -c . "$C_U/dados/contas/eventos.jsonl")" = 1 ] \
    && [ -z "$(ls -A "$C_U/dados/contas" | grep -F 'tomada' || true)" ]
}
afirma "(u) trava vencida é tomada por um processo só" caso_u

# (v) o token da pasta pessoal (ociosa) venceu: o servidor responde 401 a ele. A reserva-pessoal
# está válida (a D13 a mantém renovada), então o uso da pessoal tem de ser lido com ela, a team a
# 97% na semana troca a pasta trabalho para a pessoal, e o status mostra os percentuais da pessoal.
# Antes o 401 virava "sem dado de uso de pessoal" e a troca nunca acontecia.
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-v.json" '{"venceu":["falso-pessoal-pasta"]}'
iniciar_servidor "$RAIZ/mapa-v.json" "$RAIZ/porta-v.txt"
API_V="$API"
API="$API_PRINCIPAL"
C_V="$(novo_caso v sim)"
EST_V="$C_V/dados/contas/estado.json"
# As duas contas já registradas (o status as registra com a pasta em casa e o token válido): com o
# token da pasta pessoal vencido, o registro dela não se refaz agora.
registrar_contas() { # $1 = caso
  node -e "
const fs = require('fs');
const j = (a) => JSON.parse(fs.readFileSync(a, 'utf8'));
const c = process.argv[1];
const o = (a) => j(c + a).oauthAccount;
const t = o('/trabalho/.claude/.claude.json');
const p = o('/pessoal/.claude-personal/.claude.json');
fs.writeFileSync(c + '/dados/contas/estado.json', JSON.stringify({ automatico: true, contas: { team: { email: t.emailAddress, oauthAccount: t }, pessoal: { email: p.emailAddress, oauthAccount: p } } }));
" "$1"
}
registrar_contas "$C_V"
RC_V=0
API="$API_V"
cli "$C_V" vigiar > "$RAIZ/v.txt" 2>&1 || RC_V=$?
C_VS="$(novo_caso vs nao)"
cli "$C_VS" status > "$RAIZ/vs.txt" 2>&1 || true
API="$API_PRINCIPAL"
caso_v() {
  [ "$RC_V" -eq 0 ] && [ "$(ler "$EST_V" pastas.trabalho.conta)" = pessoal ] \
    && grep -qF '"tipo":"trocar"' "$C_V/dados/contas/eventos.jsonl" \
    && ! contem "$(cat "$RAIZ/v.txt")" "sem dado de uso de pessoal"
}
afirma "uso cai para a reserva quando o token da pasta venceu" caso_v
afirma "uso cai para a reserva: o status mostra os percentuais da conta pessoal" contem "$(cat "$RAIZ/vs.txt")" "  pessoal: 5 h 2% · semana 7%"

# (v2) o mesmo, com o vencimento pelo RELÓGIO (expiresAt no passado na credencial da pasta pessoal):
# o token da pasta nem é mandado ao servidor, e a reserva responde pela conta.
C_V2="$(novo_caso v2 sim)"
node -e "
const fs = require('fs');
const arq = process.argv[1];
const j = JSON.parse(fs.readFileSync(arq, 'utf8'));
j.claudeAiOauth.expiresAt = Date.now() - 3600000;
fs.writeFileSync(arq, JSON.stringify(j));
" "$C_V2/pessoal/.claude-personal/.credentials.json"
registrar_contas "$C_V2"
RC_V2=0
cli "$C_V2" vigiar > "$RAIZ/v2.txt" 2>&1 || RC_V2=$?
caso_v2() {
  [ "$RC_V2" -eq 0 ] && [ "$(ler "$C_V2/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && ! contem "$(cat "$RAIZ/v2.txt")" "sem dado de uso de pessoal"
}
afirma "uso cai para a reserva quando a pasta tem o token vencido pelo relógio" caso_v2

# (v3) sem reserva e com o token da pasta vencido (401), a conta fica sem dado e o aviso não vaza o token.
C_V3="$(novo_caso v3 sim)"
rm -f "$C_V3/dados/contas/reserva-pessoal.json"
registrar_contas "$C_V3"
RC_V3=0
API="$API_V"
cli "$C_V3" vigiar > "$RAIZ/v3.txt" 2>&1 || RC_V3=$?
API="$API_PRINCIPAL"
caso_v3() {
  [ "$RC_V3" -eq 0 ] && [ "$(ler "$C_V3/dados/contas/estado.json" pastas.trabalho.conta)" = AUSENTE ] \
    && [ ! -e "$C_V3/dados/contas/eventos.jsonl" ] \
    && contem "$(cat "$RAIZ/v3.txt")" "aviso: uso de pessoal indisponível: usage HTTP 401" \
    && contem "$(cat "$RAIZ/v3.txt")" "esperar trabalho: sem dado de uso de pessoal"
}
afirma "sem reserva e com o token da pasta vencido, a conta fica sem dado e nada troca" caso_v3

# (x) troca que falha e NÃO consegue se desfazer. Um preload faz o rename para .claude.json falhar
# (a quarta gravação do mover) e o segundo rename para .credentials.json também (o desfazer da
# segunda gravação): sobra o arquivo da pasta sem restaurar. O evento falhou tem de levar o motivo
# desfazer_falhou e o NOME do arquivo pendente (nunca o caminho), e a saída tem de nomeá-lo. Antes o
# aplicarTroca jogava os pendentes fora e ninguém sabia qual arquivo limpar.
cat > "$RAIZ/falha-gravacao.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const original = fs.renameSync;
let credenciais = 0;
fs.renameSync = function renameSync(de, para) {
  const alvo = path.basename(String(para));
  const erro = () => Object.assign(new Error('EPERM simulado'), { code: 'EPERM' });
  if (alvo === '.claude.json') throw erro();
  if (alvo === '.credentials.json' && ++credenciais === 2) throw erro();
  return original.apply(this, arguments);
};
JS
C_X="$(novo_caso x sim)"
EV_X="$C_X/dados/contas/eventos.jsonl"
RC_X=0
NODE_OPTIONS="--require=$(win "$RAIZ/falha-gravacao.cjs")" cli "$C_X" vigiar > "$RAIZ/x.txt" 2>&1 || RC_X=$?
caso_x() {
  [ "$RC_X" -eq 1 ] \
    && grep -F '"tipo":"falhou"' "$EV_X" | grep -qF '"motivo":"desfazer_falhou"' \
    && grep -F '"tipo":"falhou"' "$EV_X" | grep -qF '"pendentes":[".credentials.json"]' \
    && contem "$(cat "$RAIZ/x.txt")" "não feita: desfazer_falhou (arquivos pendentes: .credentials.json)" \
    && ! grep -qE '[\\/][^"]*credentials' "$EV_X"
}
afirma "desfazer_falhou leva os arquivos pendentes (só o nome) no evento e na saída" caso_x

# (y) arquivo de credencial corrompido (texto que parece token, sem ser JSON): a mensagem do
# JSON.parse traz um trecho do texto, e ele não pode sair em stdout, stderr nem evento. Cada comando
# tem de nomear só o arquivo.
C_Y="$(novo_caso y sim)"
printf '%s' 'falso-trecho-secreto-0123456789' > "$C_Y/dados/contas/reserva-team.json"
RC_Y1=0; RC_Y2=0; RC_Y3=0
cli "$C_Y" status > "$RAIZ/y1.txt" 2>&1 || RC_Y1=$?
cli "$C_Y" vigiar > "$RAIZ/y2.txt" 2>&1 || RC_Y2=$?
cli "$C_Y" trocar trabalho --pasta pessoal > "$RAIZ/y3.txt" 2>&1 || RC_Y3=$?
# renovarOciosos lê tudo o que parece reserva-*.json: um arquivo que o resto não lê (reserva-extra)
# corrompido leva a mensagem do JSON.parse para o evento renovacao_falhou.
C_Y4="$(novo_caso y4 sim)"
printf '%s' 'falso-trecho-secreto-0123456789' > "$C_Y4/dados/contas/reserva-extra.json"
RC_Y4=0
cli "$C_Y4" vigiar > "$RAIZ/y4.txt" 2>&1 || RC_Y4=$?
# o mover (que lê o estacionado direto, sem passar pelo lerJson) levanta o SyntaxError cru: o
# trecho só deixa de sair porque o erro final passa pelo msgSegura.
C_Y6="$(novo_caso y6 nao)"
printf '%s' 'falso-trecho-secreto-0123456789' > "$C_Y6/dados/contas/estacionado-trabalho.json"
RC_Y6=0
cli "$C_Y6" trocar pessoal --pasta trabalho > "$RAIZ/y6.txt" 2>&1 || RC_Y6=$?
# a credencial da própria pasta corrompida
C_Y5="$(novo_caso y5 sim)"
printf '%s' 'falso-trecho-secreto-0123456789' > "$C_Y5/trabalho/.claude/.credentials.json"
RC_Y5=0
cli "$C_Y5" status > "$RAIZ/y5.txt" 2>&1 || RC_Y5=$?
caso_y() {
  local lixo=0
  cat "$RAIZ"/y[1-6].txt "$C_Y"/dados/contas/eventos.jsonl "$C_Y4"/dados/contas/eventos.jsonl > "$RAIZ/y-tudo.txt" 2>/dev/null || true
  [ -s "$RAIZ/y-tudo.txt" ] || return 1
  grep -qF -e "falso-trec" -e "secreto" "$RAIZ/y-tudo.txt" || lixo=$?
  [ "$lixo" -eq 1 ] \
    && [ "$RC_Y1" -eq 1 ] && contem "$(cat "$RAIZ/y1.txt")" "erro: JSON inválido em reserva-team.json" \
    && [ "$RC_Y2" -eq 1 ] && contem "$(cat "$RAIZ/y2.txt")" "erro: JSON inválido em reserva-team.json" \
    && [ "$RC_Y3" -eq 1 ] && contem "$(cat "$RAIZ/y3.txt")" "erro: JSON inválido em reserva-team.json" \
    && [ "$RC_Y4" -eq 0 ] && grep -F '"tipo":"renovacao_falhou"' "$C_Y4/dados/contas/eventos.jsonl" | grep -qF '"motivo":"reserva-extra: JSON inválido em reserva-extra.json"' \
    && [ "$RC_Y5" -eq 1 ] && contem "$(cat "$RAIZ/y5.txt")" "erro: JSON inválido em .credentials.json" \
    && [ "$RC_Y6" -eq 1 ] && contem "$(cat "$RAIZ/y6.txt")" "erro: JSON inválido" && [ ! -e "$C_Y6/dados/contas/eventos.jsonl" ]
}
afirma "trecho de token de arquivo corrompido não aparece em nenhuma saída nem evento" caso_y
afirma "arquivo corrompido: a trava é solta e nada é movido" test ! -e "$C_Y/dados/contas/vigia.lock" -a ! -e "$C_Y/dados/contas/eventos.jsonl"

# (g) nenhuma credencial (valor falso ou não) aparece na saída nem no log
caso_g() {
  local rc=0
  grep -qF "falso-" "$RAIZ/a-vigiar.txt" "$RAIZ/b1.txt" "$RAIZ/b2.txt" "$RAIZ/c1.txt" "$RAIZ/c2.txt" \
    "$RAIZ/f.txt" "$RAIZ/h.txt" "$RAIZ/status-a.txt" "$EV_A" "$EV_H" \
    "$RAIZ/k.txt" "$RAIZ/k2.txt" "$RAIZ/k2-status.txt" "$RAIZ/n.txt" "$EV_K" "$EV_K2" \
    "$RAIZ/o.txt" "$RAIZ/p.txt" "$RAIZ/p-status.txt" "$RAIZ/q.txt" "$EV_O" "$EV_P" "$EV_Q" \
    "$RAIZ/m.txt" "$RAIZ/r1.txt" "$RAIZ/r2.txt" "$RAIZ/s.txt" "$RAIZ/t.txt" "$RAIZ"/u[1-4].txt "$EV_R" \
    "$RAIZ/v.txt" "$RAIZ/vs.txt" "$RAIZ/v2.txt" "$RAIZ/v3.txt" "$C_V/dados/contas/eventos.jsonl" \
    "$RAIZ/x.txt" "$EV_X" || rc=$?
  [ "$rc" -eq 1 ]
}
afirma "(g) credencial nunca aparece na saída nem no log" caso_g

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
