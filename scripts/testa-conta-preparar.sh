#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria do preparar (tarefa 5 de 2026-10-10-troca-de-conta): scripts/conta.cjs preparar.
# Casos: (a) dono bate: reserva gravada, pasta temporária some, sem automático enquanto falta a
# reserva de pessoal; (b) login da conta errada não grava reserva: exit 3, a saída cita o e-mail
# que veio, pasta temporária some; (c) reserva já existente: exit 1, arquivo intacto (sha256), claude
# nem roda; (d) com as duas reservas, estado.json fica automatico true; (e) a credencial falsa não
# aparece na saída; (f) pasta sem oauthAccount: exit 1, claude nem roda.
# Tudo em mktemp -d com trap; o servidor é node local, morto no trap pelo PID dele. O claude é um
# script node falso (RFM_CONTA_CLAUDE). Nunca toca ~/.claude nem a pasta de dados real.
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
ler() { node "$RAIZ/ler.cjs" "$@"; }
sha() { node -e "process.stdout.write(require('crypto').createHash('sha256').update(require('fs').readFileSync(process.argv[1])).digest('hex'))" "$1"; }
sem_login() { [ -d "$1" ] && ! ls -A "$1" | grep -q '^login-'; }

# Fixtures: pastas de conta com .claude.json (oauthAccount falso), reservas opcionais e um
# estado vazio. Reservas: lista 'team' e/ou 'pessoal'. Terceiro argumento 'trabalho' = pasta sem oauthAccount.
cat > "$RAIZ/semear.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const [, , destino, reservas = '', semOauth = ''] = process.argv;
const escrever = (arq, obj) => { fs.mkdirSync(path.dirname(arq), { recursive: true }); fs.writeFileSync(arq, JSON.stringify(obj, null, 2) + '\n'); };
const oauth = (email) => ({ accountUuid: '00000000-0000-0000-0000-000000000000', emailAddress: email, organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa' });
// Formato real: o .claude.json da pasta padrão mora no home, fora da pasta (~/.claude.json).
escrever(path.join(destino, 'trabalho', '.claude.json'),
  semOauth === 'trabalho' ? { numStartups: 1 } : { numStartups: 1, oauthAccount: oauth('team@exemplo.invalid') });
escrever(path.join(destino, 'pessoal', '.claude-personal', '.claude.json'), { numStartups: 1, oauthAccount: oauth('pessoal@exemplo.invalid') });
// Estado como o status o deixa: as contas registradas (e-mail), que é de onde o preparar tira o
// e-mail esperado. Pasta sem oauthAccount nunca teve a conta registrada.
const contasRegistradas = { pessoal: { email: 'pessoal@exemplo.invalid' } };
if (semOauth !== 'trabalho') contasRegistradas.team = { email: 'team@exemplo.invalid' };
escrever(path.join(destino, 'dados', 'contas', 'estado.json'), { contas: contasRegistradas });
for (const conta of reservas.split(',').filter(Boolean)) {
  escrever(path.join(destino, 'dados', 'contas', `reserva-${conta}.json`),
    { claudeAiOauth: { accessToken: 'falso-reserva-' + conta, refreshToken: 'falso-refresh-reserva-' + conta, expiresAt: 4102444800000 } });
}
JS
cat > "$RAIZ/ler.cjs" <<'JS'
const fs = require('fs');
const [, , arq, campo] = process.argv;
const o = JSON.parse(fs.readFileSync(arq, 'utf8'));
const v = campo.split('.').reduce((x, k) => (x == null ? undefined : x[k]), o);
console.log(v === undefined ? 'AUSENTE' : typeof v === 'object' ? JSON.stringify(v) : String(v));
JS

# Claude falso: grava .credentials.json no formato real em CLAUDE_CONFIG_DIR, com o token de
# RFM_FAKE_TOKEN, e guarda os argumentos recebidos em RFM_FAKE_LOG (prova o chamador).
cat > "$RAIZ/claude-falso.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
fs.appendFileSync(process.env.RFM_FAKE_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
const tok = process.env.RFM_FAKE_TOKEN;
const cred = {
  mcpOAuth: { 'servidor-falso': { accessToken: 'falso-mcp-' + tok, refreshToken: 'falso-mcp-refresh-' + tok, expiresAt: 1, scope: 'a b' } },
  claudeAiOauth: { accessToken: tok, refreshToken: 'falso-refresh-' + tok, expiresAt: 4102444800000, refreshTokenExpiresAt: 4102444800000, scopes: ['user:inference', 'user:profile'], subscriptionType: 'max', rateLimitTier: 'default_claude_max_20x' },
  trustedDeviceToken: 'falso-tdt-' + tok,
};
fs.writeFileSync(path.join(process.env.CLAUDE_CONFIG_DIR, '.credentials.json'), JSON.stringify(cred, null, 2) + '\n');
JS

# Mapa token -> dono no servidor de teste. 'falso-login-outro' é o login de outra conta.
cat > "$RAIZ/mapa.json" <<'JSON'
{ "tokens": {
  "falso-login-team": { "email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": "team" },
  "falso-login-pessoal": { "email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": "pessoal" },
  "falso-login-outro": { "email": "outro@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000c", "uso": "pessoal" }
} }
JSON

RFM_CONTA_SERVIDOR_MAPA="$(win "$RAIZ/mapa.json")" \
  node scripts/fixtures/conta/servidor.cjs > "$RAIZ/porta.txt" 2> "$RAIZ/servidor-erro.txt" &
PIDS+=("$!")
for _ in $(seq 1 100); do [ -s "$RAIZ/porta.txt" ] && break; sleep 0.1; done
API="http://127.0.0.1:$(head -n1 "$RAIZ/porta.txt")"

novo_caso() { # $1 = nome; $2 = reservas; $3 = 'trabalho' para pasta sem oauthAccount
  local c="$RAIZ/caso-$1"
  mkdir -p "$c"
  node "$RAIZ/semear.cjs" "$(win "$c")" "$2" "${3:-}"
  printf '%s' "$c"
}
preparar() { # $1 = caso; $2 = token que o claude falso grava; $3... = argumentos de conta.cjs
  local c="$1" tok="$2"; shift 2
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_API="$API" \
  RFM_CONTA_CLAUDE="$(win "$RAIZ/claude-falso.cjs")" \
  RFM_FAKE_TOKEN="$tok" \
  RFM_FAKE_LOG="$(win "$c/claude-args.txt")" \
  node scripts/conta.cjs preparar "$@"
}

# (a) dono bate: reserva gravada, pasta temporária some, sem automático com uma reserva só
C_A="$(novo_caso a "")"
RC_A=0
preparar "$C_A" falso-login-team trabalho > "$RAIZ/a.txt" 2>&1 || RC_A=$?
afirma "(a) dono bate: preparar trabalho sai 0" test "$RC_A" -eq 0
afirma "(a) dono bate: reserva-team gravada com o login" test "$(ler "$C_A/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-login-team
afirma "(a) dono bate: pediu o login com --claudeai e o e-mail da conta" grep -qF -- '"--email","team@exemplo.invalid"' "$C_A/claude-args.txt"
afirma "(a) dono bate: pasta temporária sumiu" sem_login "$C_A/dados/contas"
afirma "(a) sem a reserva de pessoal, estado.json não liga o automático" test "$(ler "$C_A/dados/contas/estado.json" automatico)" = AUSENTE
afirma "(a) imprime qual reserva falta" contem "$(cat "$RAIZ/a.txt")" "falta a reserva de pessoal"

# (b) login da conta errada não grava reserva: exit 3, a saída cita o e-mail que veio
C_B="$(novo_caso b "")"
RC_B=0
preparar "$C_B" falso-login-outro trabalho > "$RAIZ/b.txt" 2>&1 || RC_B=$?
afirma "(b) login da conta errada não grava reserva: sai 3" test "$RC_B" -eq 3
afirma "(b) login da conta errada não grava reserva: a saída cita o e-mail que veio" contem "$(cat "$RAIZ/b.txt")" "o navegador autorizou outro@exemplo.invalid"
afirma "(b) login da conta errada não grava reserva: reserva-team ausente" test ! -f "$C_B/dados/contas/reserva-team.json"
afirma "(b) login da conta errada não grava reserva: pasta temporária sumiu" sem_login "$C_B/dados/contas"

# (c) reserva já existente: exit 1, arquivo intacto, claude nem roda
C_C="$(novo_caso c team)"
SHA_C="$(sha "$C_C/dados/contas/reserva-team.json")"
RC_C=0
preparar "$C_C" falso-login-team trabalho > "$RAIZ/c.txt" 2>&1 || RC_C=$?
afirma "(c) reserva já existente: sai 1" test "$RC_C" -eq 1
afirma "(c) reserva já existente: arquivo intacto (sha256)" test "$(sha "$C_C/dados/contas/reserva-team.json")" = "$SHA_C"
afirma "(c) reserva já existente: o claude nem roda" test ! -f "$C_C/claude-args.txt"

# (d) com as duas reservas, estado.json fica automatico true
C_D="$(novo_caso d pessoal)"
RC_D=0
preparar "$C_D" falso-login-team trabalho > "$RAIZ/d.txt" 2>&1 || RC_D=$?
afirma "(d) com as duas reservas: sai 0" test "$RC_D" -eq 0
afirma "(d) com as duas reservas: estado.json automatico true" test "$(ler "$C_D/dados/contas/estado.json" automatico)" = true
afirma "(d) com as duas reservas: imprime que a troca automática foi ligada" contem "$(cat "$RAIZ/d.txt")" "troca automática ligada"

# (e) a credencial falsa não aparece na saída de nenhum caso
caso_e() {
  local rc=0
  grep -qF "falso-" "$RAIZ/a.txt" "$RAIZ/b.txt" "$RAIZ/c.txt" "$RAIZ/d.txt" "$RAIZ/f.txt" || rc=$?
  [ "$rc" -eq 1 ]
}
# (f) pasta sem oauthAccount: exit 1, nada gravado, claude nem roda
C_F="$(novo_caso f "" trabalho)"
RC_F=0
preparar "$C_F" falso-login-team trabalho > "$RAIZ/f.txt" 2>&1 || RC_F=$?
afirma "(f) conta sem registro (pasta sem oauthAccount): sai 1" test "$RC_F" -eq 1
afirma "(f) conta sem registro: a saída manda rodar o status" contem "$(cat "$RAIZ/f.txt")" "sem registro: rode status"
afirma "(f) conta sem registro: o claude nem roda" test ! -f "$C_F/claude-args.txt"
afirma "(f) conta sem registro: nada gravado" test ! -f "$C_F/dados/contas/reserva-team.json"
afirma "(e) a credencial falsa não aparece na saída" caso_e

# (g) a pasta trabalho (casa: team) foi trocada para a conta pessoal: a reserva-pessoal está
# esvaziada (o login dela está na pasta). preparar pessoal recusa com a frase e não grava nada
# (gravar ali faria a volta devolver saida_ocupada rodada após rodada).
C_G="$(novo_caso g "")"
mkdir -p "$C_G/dados/contas"
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({ pastas: { trabalho: { conta: 'pessoal' } }, contas: { team: { email: 'team@exemplo.invalid' }, pessoal: { email: 'pessoal@exemplo.invalid' } } }))" "$C_G/dados/contas/estado.json"
echo '{}' > "$C_G/dados/contas/reserva-pessoal.json"
SHA_G="$(sha "$C_G/dados/contas/reserva-pessoal.json")"
RC_G=0
preparar "$C_G" falso-login-pessoal pessoal > "$RAIZ/g.txt" 2>&1 || RC_G=$?
caso_g_slot() {
  [ "$RC_G" -eq 1 ] \
    && contem "$(cat "$RAIZ/g.txt")" "a reserva de pessoal está em uso numa pasta trocada: volte a pasta antes de preparar" \
    && [ ! -f "$C_G/claude-args.txt" ] \
    && [ "$(sha "$C_G/dados/contas/reserva-pessoal.json")" = "$SHA_G" ] \
    && sem_login "$C_G/dados/contas" && [ ! -e "$C_G/dados/contas/vigia.lock" ]
}
afirma "preparar recusa o slot esvaziado pela troca" caso_g_slot

# (h) preparar roda sob a trava: com outra rodada em curso (trava recente de outro processo), sai 1
# sem rodar o claude e sem mexer na trava alheia.
C_H="$(novo_caso h "")"
mkdir -p "$C_H/dados/contas"
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({ pid: 999999, em: Date.now() }))" "$C_H/dados/contas/vigia.lock"
RC_H=0
preparar "$C_H" falso-login-team trabalho > "$RAIZ/h.txt" 2>&1 || RC_H=$?
caso_h_trava() {
  [ "$RC_H" -eq 1 ] && contem "$(cat "$RAIZ/h.txt")" "outra rodada em curso" \
    && [ ! -f "$C_H/claude-args.txt" ] && [ -e "$C_H/dados/contas/vigia.lock" ] \
    && [ ! -f "$C_H/dados/contas/reserva-team.json" ]
}
afirma "preparar roda sob a trava: outra rodada em curso recusa sem rodar o claude" caso_h_trava

# poe_oauth <caso> <pasta> <email>: o oauthAccount do .claude.json da pasta passa a dizer <email>
# (o que o mover faz com a pasta trocada: grava ali a conta que entrou).
poe_oauth() {
  node -e "
const fs = require('fs');
const j = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
j.oauthAccount.emailAddress = process.argv[2];
fs.writeFileSync(process.argv[1], JSON.stringify(j));
" "$1" "$2"
}

# (i) a pasta trabalho (casa: team) está na conta pessoal, e o .claude.json dela já diz pessoal
# (o mover o reescreveu). A reserva-team está ausente. preparar trabalho tem de recusar sem rodar
# o claude: antes tirava o e-mail esperado desse .claude.json, o navegador autorizava a pessoal, o
# servidor confirmava, e a reserva de trabalho era gravada com o login pessoal (D10).
C_I="$(novo_caso i "")"
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({ pastas: { trabalho: { conta: 'pessoal' } }, contas: { team: { email: 'team@exemplo.invalid' }, pessoal: { email: 'pessoal@exemplo.invalid' } } }))" "$C_I/dados/contas/estado.json"
poe_oauth "$C_I/trabalho/.claude.json" pessoal@exemplo.invalid
SHA_I="$(sha "$C_I/dados/contas/estado.json")"
RC_I=0
preparar "$C_I" falso-login-pessoal trabalho > "$RAIZ/i.txt" 2>&1 || RC_I=$?
caso_i_fora() {
  [ "$RC_I" -eq 1 ] \
    && contem "$(cat "$RAIZ/i.txt")" "a pasta trabalho está fora de casa: volte a pasta antes de preparar" \
    && [ ! -f "$C_I/claude-args.txt" ] && [ ! -f "$C_I/dados/contas/reserva-team.json" ] \
    && [ "$(sha "$C_I/dados/contas/estado.json")" = "$SHA_I" ] \
    && sem_login "$C_I/dados/contas" && [ ! -e "$C_I/dados/contas/vigia.lock" ]
}
afirma "preparar com a pasta trocada recusa" caso_i_fora

# (j) o e-mail esperado vem do registro (estado.contas.team = team@), não do .claude.json da pasta,
# que aqui diz pessoal@. O claude é chamado com o e-mail registrado; o navegador autoriza a
# pessoal: sai 3 e nada é gravado.
C_J="$(novo_caso j "")"
poe_oauth "$C_J/trabalho/.claude.json" pessoal@exemplo.invalid
RC_J=0
preparar "$C_J" falso-login-pessoal trabalho > "$RAIZ/j.txt" 2>&1 || RC_J=$?
caso_j_registro() {
  [ "$RC_J" -eq 3 ] && contem "$(cat "$RAIZ/j.txt")" "o navegador autorizou pessoal@exemplo.invalid" \
    && grep -qF -- '"--email","team@exemplo.invalid"' "$C_J/claude-args.txt" \
    && [ ! -f "$C_J/dados/contas/reserva-team.json" ] && sem_login "$C_J/dados/contas"
}
afirma "preparar confere a conta pelo registro" caso_j_registro

# (j2) o lado oposto: mesmo .claude.json adulterado, mas o login que o navegador autoriza é o da
# conta registrada (team): a reserva é gravada.
C_J2="$(novo_caso j2 "")"
poe_oauth "$C_J2/trabalho/.claude.json" pessoal@exemplo.invalid
RC_J2=0
preparar "$C_J2" falso-login-team trabalho > "$RAIZ/j2.txt" 2>&1 || RC_J2=$?
caso_j2_registro() {
  [ "$RC_J2" -eq 0 ] && [ "$(ler "$C_J2/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-login-team ] \
    && grep -qF -- '"--email","team@exemplo.invalid"' "$C_J2/claude-args.txt"
}
afirma "preparar com o login da conta registrada grava a reserva mesmo com o .claude.json adulterado" caso_j2_registro

# Servidores extras para o --refazer: o principal não conhece nenhum refresh token (recusa toda
# renovação com 400, como um login morto); o "vivo" renova o refresh token da reserva-team; o
# "mudo" responde 500 a toda renovação (não dá para saber se o login morreu).
node -e "
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
m.refresh = { 'falso-refresh-reserva-team': { de: 'falso-login-team' } };
fs.writeFileSync(process.argv[2], JSON.stringify(m));
m.refresh = {};
m.renovacaoStatus = 500;
fs.writeFileSync(process.argv[3], JSON.stringify(m));
" "$RAIZ/mapa.json" "$RAIZ/mapa-vivo.json" "$RAIZ/mapa-500.json"
iniciar_extra() { # $1 = mapa; $2 = arquivo da porta; sai com a URL em API_EXTRA
  RFM_CONTA_SERVIDOR_MAPA="$(win "$1")" node scripts/fixtures/conta/servidor.cjs > "$2" 2> "$RAIZ/servidor-extra-erro.txt" &
  PIDS+=("$!")
  for _ in $(seq 1 100); do [ -s "$2" ] && break; sleep 0.1; done
  API_EXTRA="http://127.0.0.1:$(head -n1 "$2")"
}
API_PRINCIPAL="$API"
iniciar_extra "$RAIZ/mapa-vivo.json" "$RAIZ/porta-vivo.txt"; API_VIVO="$API_EXTRA"
iniciar_extra "$RAIZ/mapa-500.json" "$RAIZ/porta-500.txt"; API_500="$API_EXTRA"

# (k) --refazer com a reserva-team morta (o servidor recusa a renovação): o login novo substitui o velho.
C_K="$(novo_caso k team)"
RC_K=0
preparar "$C_K" falso-login-team trabalho --refazer > "$RAIZ/k.txt" 2>&1 || RC_K=$?
caso_k_refazer() {
  [ "$RC_K" -eq 0 ] && [ "$(ler "$C_K/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-login-team ] \
    && grep -qF -- '"--email","team@exemplo.invalid"' "$C_K/claude-args.txt" \
    && contem "$(cat "$RAIZ/k.txt")" "reserva de trabalho refeita" && sem_login "$C_K/dados/contas" \
    && [ ! -e "$C_K/dados/contas/vigia.lock" ]
}
afirma "preparar --refazer substitui a reserva morta" caso_k_refazer

# (k2) sem --refazer a reserva existente continua intocada, e a saída diz o caminho.
C_K2="$(novo_caso k2 team)"
SHA_K2="$(sha "$C_K2/dados/contas/reserva-team.json")"
RC_K2=0
preparar "$C_K2" falso-login-team trabalho > "$RAIZ/k2.txt" 2>&1 || RC_K2=$?
caso_k2_sem() {
  [ "$RC_K2" -eq 1 ] && contem "$(cat "$RAIZ/k2.txt")" "use --refazer" && [ ! -f "$C_K2/claude-args.txt" ] \
    && [ "$(sha "$C_K2/dados/contas/reserva-team.json")" = "$SHA_K2" ]
}
afirma "preparar sem --refazer deixa a reserva existente intocada e aponta o --refazer" caso_k2_sem

# (k3) --refazer com a reserva VIVA: o servidor renova, o par novo vai para o mesmo arquivo (o refresh
# token antigo deixou de valer) e nada é refeito: o claude nem roda.
C_K3="$(novo_caso k3 team)"
RC_K3=0
API="$API_VIVO"
preparar "$C_K3" falso-login-team trabalho --refazer > "$RAIZ/k3.txt" 2>&1 || RC_K3=$?
API="$API_PRINCIPAL"
caso_k3_viva() {
  [ "$RC_K3" -eq 1 ] && contem "$(cat "$RAIZ/k3.txt")" "está viva" && [ ! -f "$C_K3/claude-args.txt" ] \
    && [ "$(ler "$C_K3/dados/contas/reserva-team.json" claudeAiOauth.refreshToken)" = falso-renovado-refresh-1 ] \
    && [ "$(ler "$C_K3/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-renovado-acesso-1 ]
}
afirma "preparar --refazer com a reserva viva grava a renovada e não refaz" caso_k3_viva

# (k4) --refazer sem saber se morreu (o servidor responde 500): nada muda, o claude nem roda.
C_K4="$(novo_caso k4 team)"
SHA_K4="$(sha "$C_K4/dados/contas/reserva-team.json")"
RC_K4=0
API="$API_500"
preparar "$C_K4" falso-login-team trabalho --refazer > "$RAIZ/k4.txt" 2>&1 || RC_K4=$?
API="$API_PRINCIPAL"
caso_k4_incerta() {
  [ "$RC_K4" -eq 1 ] && contem "$(cat "$RAIZ/k4.txt")" "não consegui confirmar que a reserva de trabalho morreu" \
    && [ ! -f "$C_K4/claude-args.txt" ] && [ "$(sha "$C_K4/dados/contas/reserva-team.json")" = "$SHA_K4" ]
}
afirma "preparar --refazer sem confirmar a morte da reserva não troca nada" caso_k4_incerta

# (k5) reserva-team corrompida, com um trecho que parece token: sem --refazer sai 1 só com o NOME do
# arquivo; com --refazer ela é refeita. O trecho não aparece em nenhuma saída.
C_K5="$(novo_caso k5 "")"
printf '%s' 'falso-trecho-secreto-0123456789' > "$C_K5/dados/contas/reserva-team.json"
RC_K5=0; RC_K5R=0
preparar "$C_K5" falso-login-team trabalho > "$RAIZ/k5.txt" 2>&1 || RC_K5=$?
preparar "$C_K5" falso-login-team trabalho --refazer > "$RAIZ/k5r.txt" 2>&1 || RC_K5R=$?
caso_k5_corrompida() {
  [ "$RC_K5" -eq 1 ] && contem "$(cat "$RAIZ/k5.txt")" "JSON inválido em reserva-team.json" \
    && [ "$RC_K5R" -eq 0 ] && contem "$(cat "$RAIZ/k5r.txt")" "reserva de trabalho refeita" \
    && [ "$(ler "$C_K5/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-login-team ] \
    && ! grep -qF -e "falso-trec" -e "secreto" "$RAIZ/k5.txt" "$RAIZ/k5r.txt"
}
afirma "preparar com a reserva corrompida: erro só com o nome do arquivo e --refazer a refaz" caso_k5_corrompida

# (k6) --refazer sem reserva nenhuma: igual ao preparar (grava, sem dizer "refeita").
C_K6="$(novo_caso k6 "")"
RC_K6=0
preparar "$C_K6" falso-login-team --refazer trabalho > "$RAIZ/k6.txt" 2>&1 || RC_K6=$?
caso_k6_sem_reserva() {
  [ "$RC_K6" -eq 0 ] && contem "$(cat "$RAIZ/k6.txt")" "reserva de trabalho gravada" \
    && [ "$(ler "$C_K6/dados/contas/reserva-team.json" claudeAiOauth.accessToken)" = falso-login-team ]
}
afirma "preparar --refazer sem reserva grava como o preparar comum" caso_k6_sem_reserva

caso_e2() {
  local rc=0
  grep -qF "falso-" "$RAIZ/g.txt" "$RAIZ/h.txt" "$RAIZ/i.txt" "$RAIZ/j.txt" "$RAIZ/j2.txt" \
    "$RAIZ/k.txt" "$RAIZ/k2.txt" "$RAIZ/k3.txt" "$RAIZ/k4.txt" "$RAIZ/k5.txt" "$RAIZ/k5r.txt" "$RAIZ/k6.txt" || rc=$?
  [ "$rc" -eq 1 ]
}
afirma "(e) a credencial falsa não aparece na saída das recusas" caso_e2

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
