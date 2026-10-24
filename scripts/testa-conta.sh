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
  // Formato real: o .claude.json da pasta padrão mora no home, fora da pasta (~/.claude.json).
  escrever(path.join(destino, 'trabalho', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.team, projects: {} });
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
const homeT = path.join(caso, 'trabalho');
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
  const claudeT = ler(path.join(homeT, '.claude.json'));
  const oauthTeam = claudeT.oauthAccount;
  const oauthPessoal = ler(path.join(pastaP, '.claude.json')).oauthAccount;
  claudeT.oauthAccount = oauthPessoal;
  gravar(path.join(homeT, '.claude.json'), claudeT);
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
  const claudeT = ler(path.join(homeT, '.claude.json'));
  const oauthTeam = claudeT.oauthAccount;
  const oauthPessoal = ler(path.join(pastaP, '.claude.json')).oauthAccount;
  claudeT.oauthAccount = oauthPessoal;
  gravar(path.join(homeT, '.claude.json'), claudeT);
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
  RFM_CONTA_SERVIDOR_CONTAGEM="${CONTAGEM_POSTS:-}" \
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
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
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
# O servidor segura o /usage da primeira rodada enquanto o arquivo existir: a segunda bate na trava
# e termina sozinha; só então o arquivo sai e a primeira segue. Sem isso, a janela em que a trava
# fica ocupada dependia da velocidade da máquina.
RC_B2=0; wait "$P2" || RC_B2=$?
rm -f "$RAIZ/segurar"
RC_B1=0; wait "$P1" || RC_B1=$?
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
# falhou deixa isso): status NÃO reescreve contas.team. Desde a #585 o estado segue o login: com a
# trava, o status põe a pasta na conta pessoal (manual) e grava reconciliado, não identidade_divergente.
C_O="$(novo_caso o nao)"
node "$RAIZ/ajustar.cjs" divergente "$C_O"
EST_O="$C_O/dados/contas/estado.json"
EV_O="$C_O/dados/contas/eventos.jsonl"
cp "$EST_O" "$RAIZ/estado-o-antes.json"
RC_O=0
cli "$C_O" status > "$RAIZ/o.txt" 2>&1 || RC_O=$?
caso_o() {
  [ "$RC_O" -eq 0 ] && [ "$(ler "$EST_O" contas.team.email)" = team@exemplo.invalid ] \
    && [ "$(ler "$EST_O" pastas.trabalho.conta)" = pessoal ] && [ "$(ler "$EST_O" pastas.trabalho.manual)" = true ] \
    && grep -qF '"tipo":"reconciliado","pasta":"trabalho"' "$EV_O" \
    && ! grep -qF '"tipo":"identidade_divergente"' "$EV_O"
}
afirma "(o) status não sobrescreve o e-mail registrado e alinha o estado ao login (reconciliado)" caso_o

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
    RFM_CONTA_CLAUDE_JSON="$(win "$C_S/trabalho/.claude.json")" \
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
# Quem toma a trava fica preso no /usage até o arquivo sair: espera as outras três recusarem.
for _ in $(seq 1 200); do
  [ "$(cat "$RAIZ"/u[1-4].txt 2>/dev/null | grep -cF 'outra rodada em curso' || true)" = 3 ] && break
  sleep 0.1
done
rm -f "$RAIZ/segurar"
for p in "${PIDS_U[@]}"; do wait "$p" || true; done
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
const t = o('/trabalho/.claude.json');
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

# (z) renovarOciosos só renova o que o vigia guarda (reserva-* e estacionado-*), nunca o login de uma
# pasta: quem usa a pasta é uma sessão, que renova o próprio token, e o refresh token é de uso único
# (renovar por fora mataria o dela). O servidor falso conta os POSTs em /v1/oauth/token. As duas
# pastas estão a 25 min de vencer (menos de 1 h) e há um arquivo isca em contas/ com o mesmo login da
# pasta trabalho: sem o filtro do nome, o laço o renovaria. O controle (z2) tem a reserva-team a
# 25 min: aí o contador TEM de marcar 1, senão o zero do primeiro caso não provaria nada.
vence_em() { # $1 = arquivo; $2 = minutos até vencer (claudeAiOauth.expiresAt)
  node -e "
const fs = require('fs');
const j = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
j.claudeAiOauth.expiresAt = Date.now() + Number(process.argv[2]) * 60000;
fs.writeFileSync(process.argv[1], JSON.stringify(j, null, 2) + '\n');
" "$1" "$2"
}
posts() { if [ -s "$1" ]; then grep -c . "$1"; else echo 0; fi; }
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-z.json" "{\"refresh\":$GIROS}"
: > "$RAIZ/posts-z.txt"
CONTAGEM_POSTS="$(win "$RAIZ/posts-z.txt")"
iniciar_servidor "$RAIZ/mapa-z.json" "$RAIZ/porta-z.txt"
CONTAGEM_POSTS=""
API_Z="$API"
API="$API_PRINCIPAL"
C_Z="$(novo_caso z sim)"
vence_em "$C_Z/trabalho/.claude/.credentials.json" 25
vence_em "$C_Z/pessoal/.claude-personal/.credentials.json" 25
cp "$C_Z/trabalho/.claude/.credentials.json" "$C_Z/dados/contas/pasta-trabalho.json"
cp "$C_Z/trabalho/.claude/.credentials.json" "$RAIZ/cred-z-t.json"
cp "$C_Z/pessoal/.claude-personal/.credentials.json" "$RAIZ/cred-z-p.json"
cp "$C_Z/dados/contas/pasta-trabalho.json" "$RAIZ/isca-z.json"
POSTS_ANTES="$(posts "$RAIZ/posts-z.txt")"
RC_Z=0
API="$API_Z"
cli "$C_Z" vigiar > "$RAIZ/z.txt" 2>&1 || RC_Z=$?
API="$API_PRINCIPAL"
caso_z() {
  [ "$RC_Z" -eq 0 ] && [ "$POSTS_ANTES" = 0 ] && [ "$(posts "$RAIZ/posts-z.txt")" = 0 ] \
    && cmp -s "$C_Z/trabalho/.claude/.credentials.json" "$RAIZ/cred-z-t.json" \
    && cmp -s "$C_Z/pessoal/.claude-personal/.credentials.json" "$RAIZ/cred-z-p.json" \
    && cmp -s "$C_Z/dados/contas/pasta-trabalho.json" "$RAIZ/isca-z.json" \
    && contem "$(cat "$RAIZ/z.txt")" "esperar trabalho: trocar adiada: access token com menos de 30 min de vida" \
    && ! grep -qF '"tipo":"renovacao_falhou"' "$C_Z/dados/contas/eventos.jsonl" 2>/dev/null
}
afirma "renovarOciosos nunca renova o login de uma pasta" caso_z

POSTS_Z="$(posts "$RAIZ/posts-z.txt")"
C_Z2="$(novo_caso z2 sim)"
vence_em "$C_Z2/dados/contas/reserva-team.json" 25
REF_Z2="$(ler "$C_Z2/dados/contas/reserva-team.json" claudeAiOauth.refreshToken)"
RC_Z2=0
API="$API_Z"
cli "$C_Z2" vigiar > "$RAIZ/z2.txt" 2>&1 || RC_Z2=$?
API="$API_PRINCIPAL"
caso_z2() {
  [ "$RC_Z2" -eq 0 ] && [ "$(posts "$RAIZ/posts-z.txt")" = "$((POSTS_Z + 1))" ] \
    && [ "$(ler "$C_Z2/dados/contas/reserva-team.json" claudeAiOauth.refreshToken)" != "$REF_Z2" ]
}
afirma "renovarOciosos renova a reserva a menos de 1 h de vencer (o contador de POSTs conta)" caso_z2

# (w) com a trava fresca de outra rodada, o status só lê: nada de estado.json novo, nenhum evento, e
# a trava alheia segue lá. (w1) estado sem `contas` e dois arquivos com o mesmo login: com a trava, o
# status registraria as contas e gravaria credencial_duplicada. (w2) a pasta em casa com o login da
# outra conta: com a trava, gravaria identidade_divergente.
fresca() { node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({ pid: 999999, em: Date.now() }))" "$1/dados/contas/vigia.lock"; }
C_W="$(novo_caso w sim)"
node "$RAIZ/ajustar.cjs" duplicada "$C_W"
fresca "$C_W"
cp "$C_W/dados/contas/estado.json" "$RAIZ/estado-w-antes.json"
cp "$C_W/dados/contas/vigia.lock" "$RAIZ/lock-w-antes.json"
RC_W=0
cli "$C_W" status > "$RAIZ/w.txt" 2>&1 || RC_W=$?
caso_w() {
  [ "$RC_W" -eq 0 ] && cmp -s "$C_W/dados/contas/estado.json" "$RAIZ/estado-w-antes.json" \
    && [ "$(ler "$C_W/dados/contas/estado.json" contas)" = AUSENTE ] \
    && [ ! -e "$C_W/dados/contas/eventos.jsonl" ] \
    && cmp -s "$C_W/dados/contas/vigia.lock" "$RAIZ/lock-w-antes.json" \
    && contem "$(cat "$RAIZ/w.txt")" "aviso: o mesmo login"
}
afirma "status com trava fresca não grava estado.json nem eventos" caso_w

C_W2="$(novo_caso w2 nao)"
node "$RAIZ/ajustar.cjs" divergente "$C_W2"
fresca "$C_W2"
cp "$C_W2/dados/contas/estado.json" "$RAIZ/estado-w2-antes.json"
RC_W2=0
cli "$C_W2" status > "$RAIZ/w2.txt" 2>&1 || RC_W2=$?
caso_w2() {
  [ "$RC_W2" -eq 0 ] && cmp -s "$C_W2/dados/contas/estado.json" "$RAIZ/estado-w2-antes.json" \
    && [ ! -e "$C_W2/dados/contas/eventos.jsonl" ] && [ -e "$C_W2/dados/contas/vigia.lock" ]
}
afirma "status com trava fresca não grava identidade_divergente" caso_w2

# (t3) tomada de trava vencida com três processos, em uma ordem escolhida (um só processo, com as
# leituras e remoções da trava interceptadas): A toma a trava vencida DEPOIS que B a leu vencida, e C
# chega no instante em que o lugar da trava fica vazio. Só um dos três pode sair dono. Antes o B
# arrancava a trava nova do A e a devolvia com um link; nessa janela o C criava a sua.
cat > "$RAIZ/trava-corrida.cjs" <<'JS'
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pegarTrava } = require(process.argv[2]);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-trava-'));
const lock = path.join(dir, 'vigia.lock');
const velha = () => fs.writeFileSync(lock, JSON.stringify({ pid: 999999, em: 0 }));
const mesmo = (p) => path.resolve(String(p)) === path.resolve(lock);

let gancho = null;
let dentro = false;
const original = { read: fs.readFileSync, rename: fs.renameSync, rm: fs.rmSync };
const avisa = (evento, p) => { if (!dentro && gancho && mesmo(p)) gancho(evento); };
fs.readFileSync = function (p, ...resto) { const v = original.read.call(this, p, ...resto); avisa('leu', p); return v; };
fs.renameSync = function (de, para) { const v = original.rename.call(this, de, para); avisa('saiu', de); return v; };
fs.rmSync = function (p, ...resto) { const v = original.rm.call(this, p, ...resto); avisa('saiu', p); return v; };
const intercepta = (fn) => (evento) => { dentro = true; try { fn(evento); } finally { dentro = false; } };

function cenario(nome, montar, confere) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  velha();
  const r = {};
  gancho = intercepta(montar(r));
  r.B = pegarTrava(lock);
  gancho = null;
  console.log(nome + ' ' + (confere(r) ? 'ok' : 'FALHA') + ' ' + JSON.stringify(r));
}

// A toma depois da leitura velha do B; C chega quando a trava de A (ou a velha) sai do lugar.
cenario('tres-processos', (r) => {
  let leu = false;
  let saiu = false;
  return (evento) => {
    if (evento === 'leu' && !leu) { leu = true; r.A = pegarTrava(lock); }
    if (evento === 'saiu' && !saiu) { saiu = true; r.C = pegarTrava(lock); }
  };
}, (r) => r.A === true && r.B === false && r.C !== true);

// Sem A: C cria a trava no instante em que B tirou a velha do lugar; B não pode ficar dono também.
cenario('c-entre-remover-e-criar', (r) => {
  let saiu = false;
  return (evento) => { if (evento === 'saiu' && !saiu) { saiu = true; r.C = pegarTrava(lock); } };
}, (r) => [r.B, r.C].filter((v) => v === true).length === 1);

// Guarda esquecida (processo morto dentro dela) já vencida: recolhida, e a rodada seguinte toma.
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });
velha();
fs.writeFileSync(lock + '.tomada', JSON.stringify({ pid: 999999, em: Date.now() - 60000 }));
const esquecida1 = pegarTrava(lock);
const esquecida2 = pegarTrava(lock);
console.log('guarda-esquecida ' + (esquecida1 === false && esquecida2 === true && !fs.existsSync(lock + '.tomada') ? 'ok' : 'FALHA') + ' ' + esquecida1 + ' ' + esquecida2);

// Guarda fresca (alguém está tomando agora): não entra, e não mexe na guarda alheia.
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });
velha();
fs.writeFileSync(lock + '.tomada', JSON.stringify({ pid: 999999, em: Date.now() }));
const fresca = pegarTrava(lock);
console.log('guarda-fresca ' + (fresca === false && fs.existsSync(lock + '.tomada') ? 'ok' : 'FALHA') + ' ' + fresca);
fs.rmSync(dir, { recursive: true, force: true });
JS
node "$RAIZ/trava-corrida.cjs" "$REPO/scripts/conta.cjs" > "$RAIZ/trava.txt" 2>&1 || true
afirma "trava vencida com três processos: A toma, B com leitura antiga não a derruba e C não entra" contem "$(cat "$RAIZ/trava.txt")" "tres-processos ok"
afirma "trava vencida: C criando entre a remoção e a criação deixa um dono só" contem "$(cat "$RAIZ/trava.txt")" "c-entre-remover-e-criar ok"
afirma "trava vencida: guarda esquecida é recolhida e a rodada seguinte toma" contem "$(cat "$RAIZ/trava.txt")" "guarda-esquecida ok"
afirma "trava vencida: guarda fresca de outro processo é respeitada" contem "$(cat "$RAIZ/trava.txt")" "guarda-fresca ok"

# (mv) a troca manual aplica a guarda de vida da D11, igual ao vigia. snap resume todos os arquivos
# de credencial (as duas pastas, as reservas e os estacionados): recusar tem de deixar o resumo igual.
snap() { # $1 = caso
  local c="$1"
  { cat "$c"/trabalho/.claude/.credentials.json "$c"/trabalho/.claude.json \
      "$c"/pessoal/.claude-personal/.credentials.json "$c"/pessoal/.claude-personal/.claude.json
    cat "$c"/dados/contas/reserva-*.json
    cat "$c"/dados/contas/estacionado-*.json 2>/dev/null || true
  } | cksum
}
manual_vida() { # $1 = nome; $2 = minutos até vencer o login da pasta trabalho; $3 = idem a reserva-pessoal
  local c
  c="$(novo_caso "$1" nao)"
  vence_em "$c/trabalho/.claude/.credentials.json" "$2"
  vence_em "$c/dados/contas/reserva-pessoal.json" "$3"
  registrar_contas "$c"
  printf '%s' "$c"
}
HORA_RE='depois das [0-9][0-9]:[0-9][0-9], quando ele completa 10 min vencido'

# o login que SAI da pasta a 2 min de vencer: recusa, diz quando voltar e não move nada
C_MV1="$(manual_vida mv1 2 600)"
SNAP_MV1="$(snap "$C_MV1")"
RC_MV1=0
cli "$C_MV1" trocar pessoal --pasta trabalho > "$RAIZ/mv1.txt" 2>&1 || RC_MV1=$?
caso_mv1() {
  [ "$RC_MV1" -eq 1 ] && [ "$(snap "$C_MV1")" = "$SNAP_MV1" ] \
    && [ "$(ler "$C_MV1/dados/contas/estado.json" pastas.trabalho.conta)" = AUSENTE ] \
    && [ ! -e "$C_MV1/dados/contas/eventos.jsonl" ] \
    && contem "$(cat "$RAIZ/mv1.txt")" "troca adiada: o login da pasta trabalho (conta trabalho) tem menos de 30 min de vida" \
    && printf '%s\n' "$(cat "$RAIZ/mv1.txt")" | grep -qE "$HORA_RE"
}
afirma "troca manual com o login da pasta a 2 min de vencer recusa e não move" caso_mv1
echo "     recusa (login que sai): $(cat "$RAIZ/mv1.txt")"

# o login da pasta vencido há 20 min: ninguém usa a pasta, a guarda se dispensa e a troca sai
C_MV2="$(manual_vida mv2 -20 600)"
RC_MV2=0
cli "$C_MV2" trocar pessoal --pasta trabalho > "$RAIZ/mv2.txt" 2>&1 || RC_MV2=$?
caso_mv2() {
  [ "$RC_MV2" -eq 0 ] && [ "$(ler "$C_MV2/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && grep -qF '"tipo":"trocar"' "$C_MV2/dados/contas/eventos.jsonl"
}
afirma "troca manual com o login da pasta vencido há 20 min troca" caso_mv2

# a reserva que ENTRA a 2 min de vencer: recusa e diz que o vigia a renova (em 1 min)
C_MV3="$(manual_vida mv3 600 2)"
SNAP_MV3="$(snap "$C_MV3")"
RC_MV3=0
cli "$C_MV3" trocar pessoal --pasta trabalho > "$RAIZ/mv3.txt" 2>&1 || RC_MV3=$?
caso_mv3() {
  [ "$RC_MV3" -eq 1 ] && [ "$(snap "$C_MV3")" = "$SNAP_MV3" ] \
    && [ ! -e "$C_MV3/dados/contas/eventos.jsonl" ] \
    && contem "$(cat "$RAIZ/mv3.txt")" "troca adiada: a reserva de pessoal tem menos de 30 min de vida" \
    && contem "$(cat "$RAIZ/mv3.txt")" "o vigia o renova na próxima rodada, tente de novo em 1 min"
}
afirma "troca manual com a reserva que entra a 2 min de vencer recusa e não move" caso_mv3
echo "     recusa (login que entra): $(cat "$RAIZ/mv3.txt")"

# o login da pasta vencido há 20 min não salva um login que entra curto
C_MV4="$(manual_vida mv4 -20 2)"
SNAP_MV4="$(snap "$C_MV4")"
RC_MV4=0
cli "$C_MV4" trocar pessoal --pasta trabalho > "$RAIZ/mv4.txt" 2>&1 || RC_MV4=$?
caso_mv4() {
  [ "$RC_MV4" -eq 1 ] && [ "$(snap "$C_MV4")" = "$SNAP_MV4" ] \
    && contem "$(cat "$RAIZ/mv4.txt")" "troca adiada: a reserva de pessoal"
}
afirma "troca manual com o login da pasta vencido há 20 min mas a reserva a 2 min recusa" caso_mv4

# (g) nenhuma credencial (valor falso ou não) aparece na saída nem no log
caso_g() {
  local rc=0
  grep -qF "falso-" "$RAIZ/a-vigiar.txt" "$RAIZ/b1.txt" "$RAIZ/b2.txt" "$RAIZ/c1.txt" "$RAIZ/c2.txt" \
    "$RAIZ/f.txt" "$RAIZ/h.txt" "$RAIZ/status-a.txt" "$EV_A" "$EV_H" \
    "$RAIZ/k.txt" "$RAIZ/k2.txt" "$RAIZ/k2-status.txt" "$RAIZ/n.txt" "$EV_K" "$EV_K2" \
    "$RAIZ/o.txt" "$RAIZ/p.txt" "$RAIZ/p-status.txt" "$RAIZ/q.txt" "$EV_O" "$EV_P" "$EV_Q" \
    "$RAIZ/m.txt" "$RAIZ/r1.txt" "$RAIZ/r2.txt" "$RAIZ/s.txt" "$RAIZ/t.txt" "$RAIZ"/u[1-4].txt "$EV_R" \
    "$RAIZ/v.txt" "$RAIZ/vs.txt" "$RAIZ/v2.txt" "$RAIZ/v3.txt" "$C_V/dados/contas/eventos.jsonl" \
    "$RAIZ/x.txt" "$EV_X" "$RAIZ/z.txt" "$RAIZ/z2.txt" "$RAIZ/w.txt" "$RAIZ/w2.txt" "$RAIZ/trava.txt" "$RAIZ"/mv[1-4].txt || rc=$?
  [ "$rc" -eq 1 ]
}
afirma "(g) credencial nunca aparece na saída nem no log" caso_g

# (z) recusa (rodada 5, achado 1): com a pasta de trabalho sobrescrita e SEM RFM_CONTA_CLAUDE_JSON, a CLI sai
# com erro antes de ler ou gravar qualquer .claude.json. O home é falso e tem um canário: nada pode mudar nele.
C_ZP="$(novo_caso zp nao)"
CAN_ZP="$RAIZ/home-canario-zp"
mkdir -p "$CAN_ZP"
printf '%s\n' '{"canario":true,"oauthAccount":{"emailAddress":"canario@exemplo.invalido"}}' > "$CAN_ZP/.claude.json"
HASH_CAN_ZP="$(sha256sum "$CAN_ZP/.claude.json" | cut -d' ' -f1)"
RC_ZP=0
HOME="$(win "$CAN_ZP")" USERPROFILE="$(win "$CAN_ZP")" RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$C_ZP/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$C_ZP/pessoal/.claude-personal")" \
  RFM_CONTA_DADOS="$(win "$C_ZP/dados")" \
  RFM_CONTA_API="$API" \
  node scripts/conta.cjs trocar pessoal --pasta trabalho > "$RAIZ/zp.txt" 2>&1 || RC_ZP=$?
caso_zp() { [ "$RC_ZP" -ne 0 ] && [ "$(sha256sum "$CAN_ZP/.claude.json" | cut -d' ' -f1)" = "$HASH_CAN_ZP" ]; }
afirma "(zp) sem RFM_CONTA_CLAUDE_JSON a CLI recusa (exit ≠ 0) e o .claude.json do home fica intacto" caso_zp

# (zq) rodada 6, achado 5: só RFM_CONTA_PASTA_PESSOAL definida e SEM RFM_CONTA_CLAUDE_JSON. A guarda antiga olhava só
# a de trabalho, e a pessoal passava para o home de quem roda. Recusa com exit 2 antes de qualquer leitura de .claude.json.
C_ZQ="$(novo_caso zq nao)"
CAN_ZQ="$RAIZ/home-canario-zq"
mkdir -p "$CAN_ZQ"
printf '%s\n' '{"canario":true,"oauthAccount":{"emailAddress":"canario@exemplo.invalido"}}' > "$CAN_ZQ/.claude.json"
HASH_CAN_ZQ="$(sha256sum "$CAN_ZQ/.claude.json" | cut -d' ' -f1)"
RC_ZQ=0
HOME="$(win "$CAN_ZQ")" USERPROFILE="$(win "$CAN_ZQ")" RFM_TEST=1 \
  RFM_CONTA_PASTA_PESSOAL="$(win "$C_ZQ/pessoal/.claude-personal")" \
  RFM_CONTA_DADOS="$(win "$C_ZQ/dados")" \
  node scripts/conta.cjs status > "$RAIZ/zq.txt" 2>&1 || RC_ZQ=$?
caso_zq() { [ "$RC_ZQ" -eq 2 ] && [ "$(sha256sum "$CAN_ZQ/.claude.json" | cut -d' ' -f1)" = "$HASH_CAN_ZQ" ] && contem "$(cat "$RAIZ/zq.txt")" "RFM_CONTA_CLAUDE_JSON"; }
afirma "(zq) só RFM_CONTA_PASTA_PESSOAL, sem RFM_CONTA_CLAUDE_JSON: exit 2, a recusa nomeia a variável, e o .claude.json do home fica intacto" caso_zq

# (p2) modo duas pastas (rodada 5, achado 2): trocar trabalho --pasta pessoal grava o oauthAccount no .claude.json
# de DENTRO da pasta pessoal, e o .claude.json de trabalho (fora da pasta) fica byte a byte igual.
C_P2="$(novo_caso p2 nao)"
HASH_TR_P2="$(sha256sum "$C_P2/trabalho/.claude.json" | cut -d' ' -f1)"
RC_P2=0
cli "$C_P2" trocar trabalho --pasta pessoal > "$RAIZ/p2.txt" 2>&1 || RC_P2=$?
caso_p2() {
  [ "$RC_P2" -eq 0 ] \
    && [ "$(ler "$C_P2/pessoal/.claude-personal/.claude.json" oauthAccount.emailAddress)" = team@exemplo.invalid ] \
    && [ "$(sha256sum "$C_P2/trabalho/.claude.json" | cut -d' ' -f1)" = "$HASH_TR_P2" ]
}
afirma "(p2) duas pastas: trocar trabalho --pasta pessoal grava o oauthAccount no .claude.json de dentro da pasta pessoal; o de trabalho fica igual" caso_p2

# #584: pasta manual no limite. A pasta trabalho foi trocada na mão para a pessoal (manual, sem
# travouPor) e a pessoal chegou a 100% da semana. O vigia não move nada (D8), mas registra
# manual_no_limite uma vez por estouro: a segunda rodada com o mesmo resets_at não registra outro, e
# um resets_at novo (estouro seguinte) registra.
echo "== #584: pasta manual no limite =="
C_ML="$(novo_caso ml sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_ML"
node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$C_ML/dados/contas/estado.json"
EV_ML="$C_ML/dados/contas/eventos.jsonl"
HASH_ML="$(sha256sum "$C_ML/trabalho/.claude/.credentials.json" | cut -d' ' -f1)"
LIMITE_ML='{"tokens":{"falso-pessoal-pasta":{"uso7":100,"reset7":"2026-10-25T11:00:00.000Z"},"falso-pessoal-reserva":{"uso7":100,"reset7":"2026-10-25T11:00:00.000Z"}}}'
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-ml.json" "$LIMITE_ML"
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-ml2.json" "${LIMITE_ML//2026-10-25/2026-11-01}"
# O mesmo estouro relido com o resets_at 1 ms adiante (a leitura volta com microssegundos).
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-ml1ms.json" "${LIMITE_ML//11:00:00.000Z/11:00:00.001Z}"
iniciar_servidor "$RAIZ/mapa-ml.json" "$RAIZ/porta-ml.txt"
API_ML="$API"
iniciar_servidor "$RAIZ/mapa-ml2.json" "$RAIZ/porta-ml2.txt"
API_ML2="$API"
iniciar_servidor "$RAIZ/mapa-ml1ms.json" "$RAIZ/porta-ml1ms.txt"
API_ML1MS="$API"
API="$API_ML"
cli "$C_ML" vigiar > "$RAIZ/ml1.txt" 2>&1 || true
cli "$C_ML" vigiar > "$RAIZ/ml2.txt" 2>&1 || true
API="$API_ML1MS"
rm -f "$C_ML/dados/contas/uso-cache.json"
cli "$C_ML" vigiar > "$RAIZ/ml2b.txt" 2>&1 || true
contar_ml() { grep -c '"tipo":"manual_no_limite"' "$EV_ML" 2>/dev/null || true; }
N_ML1="$(contar_ml)"
API="$API_ML2"
# A leitura de uso fica em cache por minutos: sem apagá-lo, a rodada seguinte relê o estouro velho.
rm -f "$C_ML/dados/contas/uso-cache.json"
cli "$C_ML" vigiar > "$RAIZ/ml3.txt" 2>&1 || true
API="$API_PRINCIPAL"
N_ML2="$(contar_ml)"
afirma "#584: a primeira rodada registra manual_no_limite da pasta trabalho" \
  grep -qF '"tipo":"manual_no_limite","pasta":"trabalho"' "$EV_ML"
afirma "segunda rodada com o mesmo estouro nao registra outro manual_no_limite" test "$N_ML1" = 1
afirma "#584: com login guardado da casa, o aviso não marca sem_login_guardado" \
  test "$(grep -c 'sem_login_guardado' "$EV_ML" || true)" = 0
afirma "#584: resets_at novo (estouro seguinte) registra outro" test "$N_ML2" = 2
afirma "#584: o vigia não move credencial nem tira a pasta da conta pessoal" \
  test "$(sha256sum "$C_ML/trabalho/.claude/.credentials.json" | cut -d' ' -f1)" = "$HASH_ML" -a "$(ler "$C_ML/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal
afirma "#584: a saída do vigia diz avisar trabalho" contem "$(cat "$RAIZ/ml1.txt")" "avisar trabalho: seven_day de pessoal em 100%"

# Sem login guardado da casa (o /login por cima o apagou), o aviso leva causa sem_login_guardado: é
# ela que faz o mod mandar refazer o /login em vez do /conta.
C_ML3="$(novo_caso ml3 sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_ML3"
node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$C_ML3/dados/contas/estado.json"
rm -f "$C_ML3/dados/contas/estacionado-trabalho.json"
API="$API_ML"
cli "$C_ML3" vigiar > "$RAIZ/ml3b.txt" 2>&1 || true
API="$API_PRINCIPAL"
afirma "#584: sem login guardado da casa, o manual_no_limite leva causa sem_login_guardado" \
  grep -qE '"tipo":"manual_no_limite","pasta":"trabalho".*"causa":"sem_login_guardado"' "$C_ML3/dados/contas/eventos.jsonl"

# Revisão 2: estouro sem resets_at (null). Duas rodadas seguem sendo o mesmo estouro: um aviso só.
C_ML4="$(novo_caso ml4 sim)"
node "$RAIZ/ajustar.cjs" trocado "$C_ML4"
node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$C_ML4/dados/contas/estado.json"
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-mlnull.json" '{"tokens":{"falso-pessoal-pasta":{"uso7":100,"reset7":null},"falso-pessoal-reserva":{"uso7":100,"reset7":null}}}'
iniciar_servidor "$RAIZ/mapa-mlnull.json" "$RAIZ/porta-mlnull.txt"
cli "$C_ML4" vigiar > "$RAIZ/ml4a.txt" 2>&1 || true
rm -f "$C_ML4/dados/contas/uso-cache.json"
cli "$C_ML4" vigiar > "$RAIZ/ml4b.txt" 2>&1 || true
API="$API_PRINCIPAL"
afirma "#584: estouro sem resets_at registra um manual_no_limite só, em duas rodadas" \
  test "$(grep -c '"tipo":"manual_no_limite"' "$C_ML4/dados/contas/eventos.jsonl" 2>/dev/null || true)" = 1

# #585: /login feito fora do conta.cjs. O estado diz trabalho na conta pessoal (troca manual), mas
# a pasta recebeu um login novo da team (o /login grava .credentials.json e o oauthAccount). O
# estacionado-trabalho.json ainda guarda o login antigo da team. O estado tem de seguir o login sem
# mover credencial, e o estacionado órfão é arquivado (sem isso a próxima troca falha com
# saida_ocupada).
echo "== #585: estado segue o login =="
node -e "const fs=require('fs');const m=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));m.tokens['falso-team-login-novo']={...m.tokens['falso-team-pasta']};fs.writeFileSync(process.argv[2],JSON.stringify(m))" "$RAIZ/mapa.json" "$RAIZ/mapa-r585.json"
iniciar_servidor "$RAIZ/mapa-r585.json" "$RAIZ/porta-r585.txt"
API_R5="$API"
API="$API_PRINCIPAL"
cat > "$RAIZ/login-fora.cjs" <<'JS'
// Depois de 'trocado': marca a troca como manual e simula o /login da team na pasta trabalho.
const fs = require('fs');
const path = require('path');
const [, , caso, auto] = process.argv;
const ler = (a) => JSON.parse(fs.readFileSync(a, 'utf8'));
const gravar = (a, o) => fs.writeFileSync(a, JSON.stringify(o, null, 2) + '\n');
const contas = path.join(caso, 'dados', 'contas');
const est = ler(path.join(contas, 'estado.json'));
est.automatico = auto === 'sim';
est.pastas.trabalho.manual = true;
est.pastas.trabalho.travouPor = null;
gravar(path.join(contas, 'estado.json'), est);
const credArq = path.join(caso, 'trabalho', '.claude', '.credentials.json');
const cred = ler(credArq);
cred.claudeAiOauth = { ...cred.claudeAiOauth, accessToken: 'falso-team-login-novo', refreshToken: 'falso-refresh-team-login-novo', expiresAt: 4102444800000 };
gravar(credArq, cred);
const claudeArq = path.join(caso, 'trabalho', '.claude.json');
const claude = ler(claudeArq);
claude.oauthAccount = est.contas.team.oauthAccount;
gravar(claudeArq, claude);
JS
hash() { sha256sum "$1" | cut -d' ' -f1; }
preparar_r() { # $1 = nome do caso, $2 = automatico (sim|nao)
  local c; c="$(novo_caso "$1" nao)"
  node "$RAIZ/ajustar.cjs" trocado "$c"
  node "$RAIZ/login-fora.cjs" "$c" "$2"
  printf '%s' "$c"
}
API="$API_R5"

C_R1="$(preparar_r r1 nao)"
CT_R1="$C_R1/dados/contas"
H_CRED_R1="$(hash "$C_R1/trabalho/.claude/.credentials.json")"
H_RT_R1="$(hash "$CT_R1/reserva-team.json")"; H_RP_R1="$(hash "$CT_R1/reserva-pessoal.json")"
H_EST_R1="$(hash "$CT_R1/estacionado-trabalho.json")"
RC_R1=0
cli "$C_R1" trocar trabalho --pasta trabalho > "$RAIZ/r1.txt" 2>&1 || RC_R1=$?
caso_r1() {
  [ "$RC_R1" -eq 0 ] && contem "$(cat "$RAIZ/r1.txt")" "já está na conta trabalho" \
    && [ "$(hash "$C_R1/trabalho/.claude/.credentials.json")" = "$H_CRED_R1" ] \
    && [ "$(hash "$CT_R1/reserva-team.json")" = "$H_RT_R1" ] && [ "$(hash "$CT_R1/reserva-pessoal.json")" = "$H_RP_R1" ] \
    && [ "$(ler "$CT_R1/estado.json" pastas.trabalho.conta)" = team ] \
    && [ "$(ler "$CT_R1/estado.json" pastas.trabalho.manual)" = false ] \
    && [ "$(ler "$CT_R1/estado.json" pastas.trabalho.travouPor)" = null ] \
    && grep -qF '"tipo":"reconciliado","pasta":"trabalho","de":"pessoal","para":"team"' "$CT_R1/eventos.jsonl"
}
afirma "trocar trabalho com o login ja da conta team nao move credencial" caso_r1
ORFAO_R1="$(ls "$CT_R1" | grep -E '^estacionado-trabalho\.orfao-[0-9]{8}-[0-9]{6}\.json$' || true)"
caso_r1_orfao() {
  [ ! -e "$CT_R1/estacionado-trabalho.json" ] && [ -n "$ORFAO_R1" ] \
    && [ "$(hash "$CT_R1/$ORFAO_R1")" = "$H_EST_R1" ] && grep -qF "arquivado em $ORFAO_R1" "$CT_R1/eventos.jsonl"
}
afirma "#585: o estacionado órfão vira estacionado-trabalho.orfao-<carimbo>.json, com o mesmo conteúdo, citado no evento" caso_r1_orfao

# Depois de reconciliar para casa, a troca automática seguinte tem de acontecer: a team está a 97% da
# semana, a pessoal tem folga e uma reserva nova. Com o estacionado órfão no lugar, o mover recusaria.
node -e "const fs=require('fs');const p=require('path');const c=process.argv[1];const e=JSON.parse(fs.readFileSync(p.join(c,'estado.json'),'utf8'));e.automatico=true;fs.writeFileSync(p.join(c,'estado.json'),JSON.stringify(e));fs.writeFileSync(p.join(c,'reserva-pessoal.json'),JSON.stringify({claudeAiOauth:{accessToken:'falso-pessoal-reserva',refreshToken:'falso-refresh-pessoal-nova',expiresAt:4102444800000,scopes:['user:inference','user:profile']}}))" "$CT_R1"
rm -f "$CT_R1/uso-cache.json"
cli "$C_R1" vigiar > "$RAIZ/r1b.txt" 2>&1 || true
caso_r1b() {
  [ "$(ler "$CT_R1/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && grep -qF '"tipo":"trocar","pasta":"trabalho"' "$CT_R1/eventos.jsonl" \
    && ! grep -qF 'saida_ocupada' "$CT_R1/eventos.jsonl"
}
afirma "depois de reconciliar para casa a troca automatica seguinte nao falha com saida_ocupada" caso_r1b

# Revisão 2: o arquivamento falha (antivírus segurando o arquivo). O estado segue o login mesmo assim,
# o evento diz que o órfão ficou, e a rodada seguinte tenta de novo e arquiva.
C_R6="$(preparar_r r6 nao)"
CT_R6="$C_R6/dados/contas"
H_EST_R6="$(hash "$CT_R6/estacionado-trabalho.json")"
export RFM_CONTA_FALHA=arquivar
cli "$C_R6" vigiar > "$RAIZ/r6a.txt" 2>&1 || true
cli "$C_R6" vigiar > "$RAIZ/r6b.txt" 2>&1 || true
unset RFM_CONTA_FALHA
caso_r6_falha() {
  [ "$(ler "$CT_R6/estado.json" pastas.trabalho.conta)" = team ] \
    && [ "$(hash "$CT_R6/estacionado-trabalho.json")" = "$H_EST_R6" ] \
    && grep -qF '"tipo":"reconciliado","pasta":"trabalho","de":"pessoal","para":"team","motivo":"não consegui arquivar o login guardado antigo (EBUSY)"' "$CT_R6/eventos.jsonl" \
    && [ "$(grep -c 'não consegui arquivar' "$CT_R6/eventos.jsonl")" = 1 ]
}
afirma "#585: arquivamento que falha deixa o estado alinhado e o órfão no lugar, e a nova tentativa que falha não repete o aviso na mesma hora" caso_r6_falha
cli "$C_R6" vigiar > "$RAIZ/r6c.txt" 2>&1 || true
ORFAO_R6="$(ls "$CT_R6" | grep -E '^estacionado-trabalho\.orfao-[0-9]{8}-[0-9]{6}\.json$' || true)"
caso_r6_retenta() {
  [ ! -e "$CT_R6/estacionado-trabalho.json" ] && [ -n "$ORFAO_R6" ] \
    && [ "$(hash "$CT_R6/$ORFAO_R6")" = "$H_EST_R6" ] \
    && grep -qF "\"tipo\":\"reconciliado\",\"pasta\":\"trabalho\",\"de\":\"team\",\"para\":\"team\",\"motivo\":\"login guardado antigo arquivado em $ORFAO_R6\"" "$CT_R6/eventos.jsonl"
}
afirma "#585: a rodada seguinte tenta arquivar o órfão de novo e consegue" caso_r6_retenta

# Com a troca automática desligada: o vigia não troca nada, mas o estado segue o login mesmo assim.
C_R2="$(preparar_r r2 nao)"
H_CRED_R2="$(hash "$C_R2/trabalho/.claude/.credentials.json")"
cli "$C_R2" vigiar > "$RAIZ/r2.txt" 2>&1 || true
caso_r2() {
  contem "$(cat "$RAIZ/r2.txt")" "troca automática desligada" \
    && [ "$(ler "$C_R2/dados/contas/estado.json" pastas.trabalho.conta)" = team ] \
    && [ "$(ler "$C_R2/dados/contas/estado.json" pastas.trabalho.manual)" = false ] \
    && [ "$(hash "$C_R2/trabalho/.claude/.credentials.json")" = "$H_CRED_R2" ] \
    && grep -qF '"tipo":"reconciliado","pasta":"trabalho"' "$C_R2/dados/contas/eventos.jsonl"
}
afirma "#585: o vigia também alinha o estado ao login, sem mover credencial, mesmo com a troca automática desligada" caso_r2

C_R3="$(preparar_r r3 nao)"
fresca "$C_R3"
cp "$C_R3/dados/contas/estado.json" "$RAIZ/estado-r3-antes.json"
cli "$C_R3" status > "$RAIZ/r3.txt" 2>&1 || true
LINHA_R3="$(grep '^pasta trabalho:' "$RAIZ/r3.txt" || true)"
caso_r3() {
  cmp -s "$C_R3/dados/contas/estado.json" "$RAIZ/estado-r3-antes.json" \
    && [ ! -e "$C_R3/dados/contas/eventos.jsonl" ] \
    && contem "$LINHA_R3" "estado diverge: diz conta pessoal, o login é da conta trabalho" \
    && ! contem "$LINHA_R3" "troca manual"
}
afirma "#585: status sem a trava não grava e mostra a divergência na linha da pasta" caso_r3
API="$API_PRINCIPAL"

# Sentido inverso pelo vigia: estado em casa, login da outra conta registrada.
C_R4="$(novo_caso r4 nao)"
node "$RAIZ/ajustar.cjs" divergente "$C_R4"
node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.automatico=true;fs.writeFileSync(a,JSON.stringify(e))" "$C_R4/dados/contas/estado.json"
cli "$C_R4" vigiar > "$RAIZ/r4.txt" 2>&1 || true
caso_r4() {
  [ "$(ler "$C_R4/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && [ "$(ler "$C_R4/dados/contas/estado.json" pastas.trabalho.manual)" = true ] \
    && grep -qF '"tipo":"reconciliado","pasta":"trabalho","de":"team","para":"pessoal"' "$C_R4/dados/contas/eventos.jsonl" \
    && grep -qF 'sem_login_guardado' "$C_R4/dados/contas/eventos.jsonl"
}
afirma "#585: em casa com o login da outra conta registrada, o vigia põe a pasta fora de casa (manual)" caso_r4

# Login de conta NÃO registrada: nada muda no estado e o aviso segue identidade_divergente.
C_R5="$(novo_caso r5 nao)"
node "$RAIZ/ajustar.cjs" divergente "$C_R5"
node -e "const fs=require('fs');const a=process.argv[1];const o=JSON.parse(fs.readFileSync(a,'utf8'));o.oauthAccount={...o.oauthAccount,emailAddress:'outro@exemplo.invalid'};fs.writeFileSync(a,JSON.stringify(o))" "$C_R5/trabalho/.claude.json"
cp "$C_R5/dados/contas/estado.json" "$RAIZ/estado-r5-antes.json"
API="$API_H"
cli "$C_R5" status > "$RAIZ/r5.txt" 2>&1 || true
API="$API_PRINCIPAL"
caso_r5() {
  cmp -s "$C_R5/dados/contas/estado.json" "$RAIZ/estado-r5-antes.json" \
    && grep -qF '"tipo":"identidade_divergente"' "$C_R5/dados/contas/eventos.jsonl" \
    && ! grep -qF '"tipo":"reconciliado"' "$C_R5/dados/contas/eventos.jsonl"
}
afirma "#585: login de conta não registrada não reconcilia e segue identidade_divergente" caso_r5

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
