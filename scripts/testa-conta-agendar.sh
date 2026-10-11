#!/bin/bash
# rainforest-gate: dados-de-exemplo — credenciais FALSAS (falso-*), e-mails exemplo.invalid e timestamps de teste; nenhum valor real.
# Bateria do agendamento do vigia da troca de conta (tarefa 7): agendar/desagendar, atalho pessoal|trabalho e config.json.
# Casos: (a) 'agendar --imprimir roda a cada 1 minuto' (/SC MINUTE /MO 1, --headless, caminhos absolutos, sem /ED);
# (b) sem as duas reservas, agendar sai 1 e o schtasks falso não é chamado; (c) com as duas reservas, agendar chama o
# schtasks falso com os argumentos esperados; (d) desagendar chama /Delete; (e) 'pessoal' troca igual a 'trocar pessoal';
# (f) config.json com trocarEm 50 faz o vigiar trocar a team em 53%; trocarEm 150 cai no padrão 97 com aviso no stderr.
# O schtasks é um script falso (RFM_CONTA_SCHTASKS) que grava os argumentos; o schtasks real nunca roda.
# Tudo em mktemp -d com trap; o servidor de uso é node local, morto no trap pelo PID dele. Nunca toca ~/.claude
# nem a pasta de dados real.
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

# Fixtures falsas: pastas no formato real, reservas, estado e config. Argumentos:
# destino, reservas (ambas | team | nenhuma), automatico (sim | nao), config JSON (ou -).
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
const [, , destino, reservas, auto, config] = process.argv;
escrever(path.join(destino, 'trabalho', '.claude', '.credentials.json'), cred('falso-team-pasta', 'falso-refresh-team-pasta'));
escrever(path.join(destino, 'trabalho', '.claude', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.team, projects: {} });
escrever(path.join(destino, 'pessoal', '.claude-personal', '.credentials.json'), cred('falso-pessoal-pasta', 'falso-refresh-pessoal-pasta'));
escrever(path.join(destino, 'pessoal', '.claude-personal', '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.pessoal, projects: {} });
if (reservas !== 'nenhuma') escrever(path.join(destino, 'dados', 'contas', 'reserva-team.json'), { claudeAiOauth: cred('falso-team-reserva', 'falso-refresh-team-reserva').claudeAiOauth });
if (reservas === 'ambas') escrever(path.join(destino, 'dados', 'contas', 'reserva-pessoal.json'), { claudeAiOauth: cred('falso-pessoal-reserva', 'falso-refresh-pessoal-reserva').claudeAiOauth });
escrever(path.join(destino, 'dados', 'contas', 'estado.json'), { automatico: auto === 'sim' });
if (config !== '-') fs.writeFileSync(path.join(destino, 'dados', 'contas', 'config.json'), config + '\n');
JS

cat > "$RAIZ/ler.cjs" <<'JS'
const fs = require('fs');
const [, , arq, campo] = process.argv;
const o = JSON.parse(fs.readFileSync(arq, 'utf8'));
const v = campo.split('.').reduce((x, k) => (x == null ? undefined : x[k]), o);
console.log(v === undefined ? 'AUSENTE' : typeof v === 'object' ? JSON.stringify(v) : String(v));
JS

# Servidor de uso falso: team com 53% na 5 h (o fixture compartilhado só tem 97% na semana).
cat > "$RAIZ/mapa.json" <<'JSON'
{
  "falso-team-pasta": {"email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": {"five_hour": {"utilization": 53, "resets_at": "2030-01-01T00:00:00+00:00"}, "seven_day": {"utilization": 10, "resets_at": "2030-01-01T00:00:00+00:00"}}},
  "falso-team-reserva": {"email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": {"five_hour": {"utilization": 53, "resets_at": "2030-01-01T00:00:00+00:00"}, "seven_day": {"utilization": 10, "resets_at": "2030-01-01T00:00:00+00:00"}}},
  "falso-pessoal-pasta": {"email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": {"five_hour": {"utilization": 2, "resets_at": "2030-01-01T00:00:00+00:00"}, "seven_day": {"utilization": 7, "resets_at": "2030-01-01T00:00:00+00:00"}}},
  "falso-pessoal-reserva": {"email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": {"five_hour": {"utilization": 2, "resets_at": "2030-01-01T00:00:00+00:00"}, "seven_day": {"utilization": 7, "resets_at": "2030-01-01T00:00:00+00:00"}}}
}
JSON
cat > "$RAIZ/servidor.cjs" <<'JS'
const fs = require('fs');
const http = require('http');
const mapa = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const srv = http.createServer((req, res) => {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  const id = m && mapa[m[1]];
  const enviar = (codigo, obj) => { res.writeHead(codigo, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };
  if (!id) return enviar(401, {});
  if (req.url === '/api/oauth/profile') return enviar(200, { account: { uuid: id.uuid, email: id.email } });
  if (req.url === '/api/oauth/usage') return enviar(200, id.uso);
  return enviar(404, {});
});
srv.listen(0, '127.0.0.1', () => process.stdout.write(srv.address().port + '\n'));
JS
node "$RAIZ/servidor.cjs" "$RAIZ/mapa.json" > "$RAIZ/porta.txt" 2> "$RAIZ/servidor-erro.txt" &
PIDS+=("$!")
for _ in $(seq 1 100); do [ -s "$RAIZ/porta.txt" ] && break; sleep 0.1; done
API="http://127.0.0.1:$(head -n1 "$RAIZ/porta.txt")"

# schtasks falso: grava um argumento por linha em <caso>/args.txt e nunca toca o real.
cat > "$RAIZ/schtasks-falso.cjs" <<'JS'
const fs = require('fs');
fs.writeFileSync(process.env.RFM_FALSO_ARGS, process.argv.slice(2).join('\n') + '\n');
JS

novo_caso() { # $1 = nome, $2 = reservas, $3 = automatico, $4 = config JSON (ou -)
  local c="$RAIZ/caso-$1"
  mkdir -p "$c"
  node "$RAIZ/semear.cjs" "$(win "$c")" "$2" "$3" "${4:--}"
  printf '%s' "$c"
}
cli() {
  local c="$1"; shift
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_API="$API" \
  RFM_CONTA_SCHTASKS="$(win "$RAIZ/schtasks-falso.cjs")" \
  RFM_FALSO_ARGS="$(win "$c/args.txt")" \
  node scripts/conta.cjs "$@"
}
TAREFA_ESPERADA="$(printf '%s\n' '/Create' '/TN' '\ClaudeVigias\troca-de-conta' '/SC' 'MINUTE' '/MO' '1' '/F' '/TR')"
NODE_ABS="$(node -p 'process.execPath')"
CONTA_ABS="$(node -p "require('path').resolve('scripts/conta.cjs')")"

# (a) agendar --imprimir roda a cada 1 minuto
C_A="$(novo_caso a ambas nao)"
RC_A=0
SAIDA_A="$(cli "$C_A" agendar --imprimir)" || RC_A=$?
caso_a() {
  [ "$RC_A" -eq 0 ] \
    && contem "$SAIDA_A" "/SC MINUTE /MO 1" \
    && contem "$SAIDA_A" "--headless" \
    && contem "$SAIDA_A" "$NODE_ABS" \
    && contem "$SAIDA_A" "$CONTA_ABS" \
    && ! contem "$SAIDA_A" "/ED" \
    && [ ! -e "$C_A/args.txt" ]
}
afirma "agendar --imprimir roda a cada 1 minuto" caso_a

# (b) sem as duas reservas, agendar recusa e não chama o schtasks
C_B="$(novo_caso b nenhuma nao)"
RC_B=0
cli "$C_B" agendar > "$RAIZ/b.txt" 2>&1 || RC_B=$?
caso_b() {
  [ "$RC_B" -eq 1 ] && contem "$(cat "$RAIZ/b.txt")" "não agendo" && [ ! -e "$C_B/args.txt" ]
}
afirma "sem as duas reservas, agendar recusa sem chamar o schtasks" caso_b

# (c) com as duas reservas, agendar chama o schtasks com os argumentos esperados
C_C="$(novo_caso c ambas nao)"
RC_C=0
cli "$C_C" agendar > "$RAIZ/c.txt" 2>&1 || RC_C=$?
caso_c() {
  [ "$RC_C" -eq 0 ] && [ -f "$C_C/args.txt" ] \
    && [ "$(sed -n 1,9p "$C_C/args.txt")" = "$TAREFA_ESPERADA" ] \
    && contem "$(sed -n 10p "$C_C/args.txt")" "--headless"
}
afirma "com as duas reservas, agendar chama o schtasks com /Create /SC MINUTE /MO 1" caso_c

# (d) desagendar chama /Delete
C_D="$(novo_caso d nenhuma nao)"
RC_D=0
cli "$C_D" desagendar > "$RAIZ/d.txt" 2>&1 || RC_D=$?
caso_d() {
  [ "$RC_D" -eq 0 ] && [ "$(cat "$C_D/args.txt")" = "$(printf '%s\n' '/Delete' '/TN' '\ClaudeVigias\troca-de-conta' '/F')" ]
}
afirma "desagendar chama /Delete" caso_d

# (e) o atalho 'pessoal' troca como 'trocar pessoal'
C_E1="$(novo_caso e1 ambas nao)"
RC_E1=0
SAIDA_E1="$(cli "$C_E1" trocar pessoal)" || RC_E1=$?
C_E2="$(novo_caso e2 ambas nao)"
RC_E2=0
SAIDA_E2="$(cli "$C_E2" pessoal)" || RC_E2=$?
caso_e() {
  [ "$RC_E1" -eq 0 ] && [ "$RC_E2" -eq 0 ] \
    && [ "$SAIDA_E1" = "$SAIDA_E2" ] \
    && [ "$(ler "$C_E1/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ] \
    && [ "$(ler "$C_E2/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ]
}
afirma "conta.cjs pessoal troca como trocar pessoal" caso_e

# (f) config.json com trocarEm 50 troca a team a 53%; chave inválida cai no padrão com aviso
C_F="$(novo_caso f ambas sim '{"trocarEm": 50}')"
RC_F=0
SAIDA_F="$(cli "$C_F" vigiar 2> "$RAIZ/f-erro.txt")" || RC_F=$?
caso_f() {
  [ "$RC_F" -eq 0 ] \
    && contem "$SAIDA_F" "trocar trabalho: team -> pessoal" \
    && [ "$(ler "$C_F/dados/contas/estado.json" pastas.trabalho.conta)" = pessoal ]
}
afirma "config trocarEm 50 faz o vigiar trocar a team em 53%" caso_f

C_F2="$(novo_caso f2 ambas sim '{"trocarEm": 150}')"
RC_F2=0
SAIDA_F2="$(cli "$C_F2" vigiar 2> "$RAIZ/f2-erro.txt")" || RC_F2=$?
caso_f2() {
  [ "$RC_F2" -eq 0 ] \
    && contem "$SAIDA_F2" "sem ação" \
    && contem "$(cat "$RAIZ/f2-erro.txt")" "trocarEm=150 inválido" \
    && contem "$(cat "$RAIZ/f2-erro.txt")" "usando 97" \
    && [ ! -e "$C_F2/dados/contas/eventos.jsonl" ]
}
afirma "chave inválida do config.json cai no padrão 97 com aviso no stderr" caso_f2

echo "ok: $OK falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
