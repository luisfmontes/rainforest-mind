#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria da migração para a pasta única (tarefa 2 de 2026-10-12-pasta-unica): conta.cjs unificar.
# Um caso por item (a) a (p) do "pronto quando" da tarefa, mais recusas extras. Cada caso tem fixtures
# próprias em mktemp -d, com trap. Tudo falso: RFM_TEST=1, homes falsos, CLI falsa (RFM_CONTA_CLAUDE_BIN)
# e schtasks falso (RFM_CONTA_SCHTASKS). Nunca toca ~/.claude*, ~/.claude.json, ~/.rainforest, a API
# real, o schtasks real nem o tasklist real.
set -euo pipefail
cd "$(dirname "$0")/.."
unset RFM_CONTA_PROCESSOS

win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
RAIZ="$(win "$(mktemp -d)")"
trap 'kill "${SRV_R1:-}" 2>/dev/null || true; rm -rf "$RAIZ"' EXIT

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
ler() { node "$RAIZ/ler.cjs" "$@" 2>/dev/null || printf 'AUSENTE\n'; }
hash_de() { node "$RAIZ/hash.cjs" "$(win "$1")"; }

# Fixtures no formato real, tudo falso. Argumentos: caso, variante (opcional).
cat > "$RAIZ/semear.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const [, , base, variante = ''] = process.argv;
const H = path.join(base, 'trabalho');
const T = path.join(H, '.claude');
const P = path.join(base, 'pessoal', '.claude-personal');
const D = path.join(base, 'dados');
const w = (arq, txt) => { fs.mkdirSync(path.dirname(arq), { recursive: true }); fs.writeFileSync(arq, txt); };
const j = (arq, obj) => w(arq, JSON.stringify(obj, null, 2) + '\n');
const VIDA = 4102444800000;
const oauth = (email) => ({ accountUuid: '00000000-0000-0000-0000-000000000001', emailAddress: email, organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa' });
const WA = { type: 'stdio', command: 'falso-whatsapp', args: ['--modo-falso'] };
const WA_OUTRA = { type: 'stdio', command: 'falso-whatsapp-outra', args: ['--modo-falso'] };
// Pasta de trabalho (destino).
j(path.join(H, '.claude.json'), { numStartups: 2, oauthAccount: oauth('team@exemplo.invalid'), mcpServers: { whatsapp: WA }, projects: variante === 'projeto-comum' ? { '/falso/trabalho': {}, '/falso/comum': {} } : { '/falso/trabalho': {} } });
j(path.join(T, '.credentials.json'), { claudeAiOauth: { accessToken: 'falso-token-team', refreshToken: 'falso-refresh-team', expiresAt: VIDA, scopes: ['user:inference'], subscriptionType: 'max' } });
j(path.join(T, 'settings.json'), { model: 'falso' });
w(path.join(T, 'history.jsonl'), '{"display":"falso-linha-um"}\n');
w(path.join(T, 'projects', '-proj-x', 'memory', 'MEMORY.md'), '- [A](a.md) — trabalho\n');
w(path.join(T, 'projects', '-proj-x', 'memory', 'a.md'), 'trabalho a\n');
// memoria-pre: b.md já foi copiada (igual à da pessoal) por uma rodada anterior, e o índice ainda não tem a linha.
if (variante === 'memoria-pre') {
  w(path.join(T, 'projects', '-proj-x', 'memory', 'b.md'), 'pessoal b\n');
  // A rodada anterior gravou o progresso da cópia (só o que copiou com o mesmo nome).
  w(path.join(D, 'contas', 'unificar-progresso.jsonl'), JSON.stringify('projects/-proj-x/memory/b.md') + '\n');
}
// a-identico: a.md já é igual ao da pessoal nas duas pastas desde o início (não foi copiado por ninguém).
if (variante === 'a-identico') w(path.join(T, 'projects', '-proj-x', 'memory', 'a.md'), 'pessoal a\n');
// Clone instalado (destino do reagendamento, D7). A variante sem-clone não o cria.
if (variante !== 'sem-clone') w(path.join(T, 'plugins', 'marketplaces', 'rainforest-mind', 'scripts', 'conta.cjs'), '// clone falso\n');
// Pasta pessoal (origem).
j(path.join(P, '.credentials.json'), { claudeAiOauth: { accessToken: 'falso-token-pessoal-cred', refreshToken: 'falso-refresh-pessoal-cred', expiresAt: VIDA, scopes: ['user:inference'], subscriptionType: 'max' }, mcpOAuth: { falso: { accessToken: 'falso-mcp-oauth' } } });
// #503 D2/D4: pessoal-sem-oauth não tem oauthAccount; pessoal-email-team tem o e-mail da team.
j(path.join(P, '.claude.json'), { numStartups: 1, ...(variante === 'pessoal-sem-oauth' ? {} : { oauthAccount: oauth(variante === 'pessoal-email-team' ? 'team@exemplo.invalid' : 'pessoal@exemplo.invalid') }), mcpServers: { whatsapp: variante === 'whatsapp-divergente' ? WA_OUTRA : WA, github: { type: 'stdio', command: 'falso-gh', env: { GH_TOKEN_FALSO: 'falso-gh-token-xyz' } } }, projects: variante === 'projeto-comum' ? { '/falso/pessoal': {}, '/falso/comum': {} } : { '/falso/pessoal': {} } });
j(path.join(P, 'settings.json'), { enabledPlugins: { 'security-guidance@claude-plugins-official': true } });
w(path.join(P, 'history.jsonl'), '{"display":"falso-linha-um"}\n{"display":"falso-linha-dois"}\n{"display":"falso-linha-dois"}\n');
w(path.join(P, 'projects', '-proj-x', '11111111-1111-4111-8111-111111111111.jsonl'), '{"falso":"transcrito-pessoal"}\n');
// indice-z: a linha aponta para um z.md que não existe em nenhuma pasta (não pode entrar, nem repetir).
w(path.join(P, 'projects', '-proj-x', 'memory', 'MEMORY.md'), '- [A2](a.md) — pessoal\n- [B](b.md) — nova\n' + (variante === 'indice-z' ? '- [Z](z.md) — sem alvo\n' : ''));
w(path.join(P, 'projects', '-proj-x', 'memory', 'a.md'), 'pessoal a\n');
w(path.join(P, 'projects', '-proj-x', 'memory', 'b.md'), 'pessoal b\n');
w(path.join(P, 'file-history', 'h', '1.txt'), 'falso-historico\n');
w(path.join(P, 'cache', 'x.bin'), 'falso-cache\n');
w(path.join(P, 'sessions', 's.json'), '{}\n');
w(path.join(P, 'plugins', 'cache', 'p.txt'), 'falso-plugin-cache\n');
// Dados do rainforest.
j(path.join(D, 'contas', 'estado.json'), variante === 'estado-fora'
  ? { automatico: false, pastas: { pessoal: { conta: 'team' } }, contas: {} }
  : variante === 'estado-fora-trabalho'
    ? { automatico: false, pastas: { trabalho: { conta: 'pessoal' } }, contas: {} }
    : variante === 'pessoal-email-team'
      ? { automatico: false, contas: { team: { email: 'team@exemplo.invalid' } } }
      : { automatico: false, contas: {} });
if (variante === 'reserva-pronta' || variante === 'reserva-mesmo-token') {
  // reserva-mesmo-token: a reserva já tem o MESMO refresh token da credencial pessoal.
  const refresh = variante === 'reserva-mesmo-token' ? 'falso-refresh-pessoal-cred' : 'falso-refresh-reserva-pronta';
  j(path.join(D, 'contas', 'reserva-pessoal.json'), { claudeAiOauth: { accessToken: 'falso-reserva-pronta', refreshToken: refresh, expiresAt: VIDA } });
}
if (variante === 'sessao-viva') {
  j(path.join(D, 'sessoes.json'), { 'falso-sessao': { cwd: '/falso/projeto', prompt_ts: Date.now() } });
}
JS
cat > "$RAIZ/ler.cjs" <<'JS'
const fs = require('fs');
const [, , arq, campo] = process.argv;
const o = JSON.parse(fs.readFileSync(arq, 'utf8'));
const v = campo.split('.').reduce((x, k) => (x == null ? undefined : x[k]), o);
console.log(v === undefined ? 'AUSENTE' : typeof v === 'object' ? JSON.stringify(v) : String(v));
JS
# Hash de um arquivo, ou de uma árvore inteira (caminho relativo + conteúdo, em ordem).
cat > "$RAIZ/hash.cjs" <<'JS'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const alvo = process.argv[2];
const h = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
function arvore(dir, base, saida) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) arvore(abs, base, saida);
    else saida.push(path.relative(base, abs).split(path.sep).join('/') + ' ' + h(fs.readFileSync(abs)));
  }
  return saida;
}
console.log(fs.statSync(alvo).isDirectory() ? h(arvore(alvo, alvo, []).join('\n')) : h(fs.readFileSync(alvo)));
JS
# CLI falsa: registra os argumentos em RFM_FAKE_LOG e, em RFM_FAKE_ENV, se chegou CLAUDE_CONFIG_DIR
# (SET) ou não (UNSET). RFM_FAKE_FALHA=1 faz a instalação de plugin sair 3. A claude real nunca roda.
cat > "$RAIZ/cli-falsa.cjs" <<'JS'
const fs = require('fs');
const argv = process.argv.slice(2);
fs.appendFileSync(process.env.RFM_FAKE_LOG, JSON.stringify(argv) + '\n');
const estado = process.env.CLAUDE_CONFIG_DIR === undefined ? 'UNSET' : 'SET';
fs.appendFileSync(process.env.RFM_FAKE_ENV, `${estado} ${argv.join(' ')}\n`);
if (process.env.RFM_FAKE_FALHA === '1' && argv[0] === 'plugin' && argv[1] === 'install') process.exit(3);
JS
# Schtasks falso: lembra se a tarefa existe entre chamadas (arquivo <log>.estado). Começa agendada, ou
# ausente com RFM_SCHTASKS_NAO_AGENDADO=1 (tarefa inexistente, medido em 2026-10-12). /Delete numa tarefa
# ausente sai 1, como o real; /Create agenda; /Query sai 0 se agendada e 1 se ausente. RFM_SCHTASKS_FALHA=1
# faz o /Delete sair 1 sem mudar nada. Só /Create e /Delete entram no log. O schtasks real nunca roda.
cat > "$RAIZ/schtasks-falso.cjs" <<'JS'
const fs = require('fs');
const log = process.env.RFM_SCHTASKS_LOG;
const arqEstado = log + '.estado';
const lido = fs.existsSync(arqEstado) ? fs.readFileSync(arqEstado, 'utf8').trim() : '';
const estado = lido || (process.env.RFM_SCHTASKS_NAO_AGENDADO === '1' ? 'ausente' : 'agendada');
const acao = process.argv.includes('/Query') ? 'query' : process.argv.includes('/Delete') ? 'delete' : 'create';
if (acao === 'query') process.exit(estado === 'ausente' ? 1 : 0);
if (acao === 'delete') {
  if (process.env.RFM_SCHTASKS_FALHA === '1' || estado === 'ausente') process.exit(1);
  fs.writeFileSync(arqEstado, 'ausente');
} else {
  fs.writeFileSync(arqEstado, 'agendada');
}
fs.appendFileSync(log, JSON.stringify(process.argv.slice(2)) + '\n');
JS

novo_caso() { # $1 = nome; $2 = variante (opcional)
  local c="$RAIZ/caso-$1"
  mkdir -p "$c"
  node "$RAIZ/semear.cjs" "$(win "$c")" "${2:-}"
  printf '%s' "$c"
}
unif() { # $1 = caso; $2... = argumentos de conta.cjs unificar. PROCESSOS_TESTE vira RFM_CONTA_PROCESSOS.
  local c="$1"; shift
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_PROCESSOS="${PROCESSOS_TESTE:-}" \
  RFM_CONTA_SCHTASKS="$(win "$RAIZ/schtasks-falso.cjs")" \
  RFM_SCHTASKS_LOG="$(win "$c/schtasks-args.txt")" \
  RFM_CONTA_CLAUDE_BIN="$(win "$RAIZ/cli-falsa.cjs")" \
  RFM_FAKE_LOG="$(win "$c/cli-args.txt")" \
  RFM_FAKE_ENV="$(win "$c/cli-env.txt")" \
  node scripts/conta.cjs unificar "$@"
}

# Predicados dos casos (funções, para afirma receber um único comando).
caso_d() {
  [ "$(hash_de "$C_B/trabalho/.claude/projects/-proj-x/memory/a.pessoal.md")" = "$H_MEM_PES" ] &&
  [ "$(hash_de "$C_B/trabalho/.claude/projects/-proj-x/memory/a.md")" = "$H_MEM_DEST" ]
}
ordem_delete_create() {
  local d c
  d="$(grep -n '"/Delete"' "$C_B/schtasks-args.txt" | head -n1 | cut -d: -f1)"
  c="$(grep -n '"/Create"' "$C_B/schtasks-args.txt" | head -n1 | cut -d: -f1)"
  [ -n "$d" ] && [ -n "$c" ] && [ "$d" -lt "$c" ]
}
create_no_marketplace() { grep '"/Create"' "$C_B/schtasks-args.txt" | grep -qE 'plugins[\\/]+marketplaces'; }
sem_token() { ! grep -qE 'falso-(token|refresh|gh-token)' "$1"; }
cache_plugins_sessions_ausentes() {
  [ ! -e "$C_B/trabalho/.claude/cache" ] && [ ! -e "$C_B/trabalho/.claude/sessions" ] && [ ! -e "$C_B/trabalho/.claude/plugins/cache" ]
}
mesmo_hash() { [ "$(hash_de "$1")" = "$2" ]; }

# (a) sem --aplicar nenhum byte muda nos dois homes e o relatório lista o conflito.
C_A="$(novo_caso a)"
H_A_ANTES="$(hash_de "$C_A")"
RC_A=0
unif "$C_A" > "$RAIZ/a.txt" 2>&1 || RC_A=$?
H_A_DEPOIS="$(hash_de "$C_A")"
afirma "(a) sem --aplicar nenhum byte muda nos dois homes" test "$H_A_ANTES" = "$H_A_DEPOIS"
afirma "(a) sem --aplicar sai 0" test "$RC_A" -eq 0
afirma "(a) sem --aplicar lista o conflito de a.md" contem "$(cat "$RAIZ/a.txt")" "conflito: projects/-proj-x/memory/a.md -> projects/-proj-x/memory/a.pessoal.md"

# (b) a (p): uma migração com --aplicar sobre a mesma fixture.
C_B="$(novo_caso b)"
H_TRANSC="$(hash_de "$C_B/pessoal/.claude-personal/projects/-proj-x/11111111-1111-4111-8111-111111111111.jsonl")"
H_MEM_DEST="$(hash_de "$C_B/trabalho/.claude/projects/-proj-x/memory/a.md")"
H_MEM_PES="$(hash_de "$C_B/pessoal/.claude-personal/projects/-proj-x/memory/a.md")"
H_WA="$(ler "$C_B/trabalho/.claude.json" mcpServers.whatsapp)"
RC_B=0
unif "$C_B" --aplicar > "$RAIZ/b.txt" 2>&1 || RC_B=$?
afirma "(b) --aplicar sai 0" test "$RC_B" -eq 0
afirma "(b) --aplicar: .claude-personal some" test ! -e "$C_B/pessoal/.claude-personal"
afirma "(b) --aplicar: .claude-personal.aposentada existe" test -d "$C_B/pessoal/.claude-personal.aposentada"
afirma "(b) relatório termina com a linha pasta pessoal aposentada" grep -q '^pasta pessoal aposentada: ' "$RAIZ/b.txt"
afirma "(b) reserva-pessoal gravada com a credencial da pessoal (valor não impresso)" test "$(ler "$C_B/dados/contas/reserva-pessoal.json" claudeAiOauth.accessToken)" = falso-token-pessoal-cred
afirma "(b) credencial da pasta de trabalho não é trocada" test "$(ler "$C_B/trabalho/.claude/.credentials.json" claudeAiOauth.accessToken)" = falso-token-team
afirma "(c) transcrito pessoal no projeto da pasta trabalho" test "$(hash_de "$C_B/trabalho/.claude/projects/-proj-x/11111111-1111-4111-8111-111111111111.jsonl")" = "$H_TRANSC"
afirma "(d) memoria de mesmo nome e conteudo diferente vira .pessoal.md e o destino fica intacto" caso_d
MEM_DEST="$C_B/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(e) MEMORY.md de destino ganha a linha cujo alvo não estava lá" test "$(grep -cF '(b.md)' "$MEM_DEST")" -eq 1
afirma "(e) MEMORY.md de destino não ganha a linha cujo alvo já existia" test "$(grep -cF '[A2]' "$MEM_DEST")" -eq 0
afirma "(e) MEMORY.md de destino mantém a linha original" test "$(grep -cF '[A](a.md)' "$MEM_DEST")" -eq 1
afirma "(f) history.jsonl sem linha duplicada: linha nova entra uma vez" test "$(grep -cF 'falso-linha-dois' "$C_B/trabalho/.claude/history.jsonl")" -eq 1
afirma "(f) history.jsonl sem linha duplicada: linha já existente não repete" test "$(grep -cF 'falso-linha-um' "$C_B/trabalho/.claude/history.jsonl")" -eq 1
afirma "(g) github entra em .claude.json de trabalho" test "$(ler "$C_B/trabalho/.claude.json" mcpServers.github.command)" = falso-gh
afirma "(g) whatsapp em .claude.json fica igual" test "$(ler "$C_B/trabalho/.claude.json" mcpServers.whatsapp)" = "$H_WA"
afirma "(h) CLI falsa chamada com plugin install security-guidance@claude-plugins-official" grep -qF '"install","security-guidance@claude-plugins-official"' "$C_B/cli-args.txt"
afirma "(i) schtasks falso chamado com /Delete antes de /Create" ordem_delete_create
afirma "(i) /Create aponta para plugins/marketplaces da pasta de trabalho" create_no_marketplace
afirma "(o) nada de cache/, sessions/ e plugins/ copiado" cache_plugins_sessions_ausentes
afirma "(o) file-history copiado (controle positivo da cópia)" test -f "$C_B/trabalho/.claude/file-history/h/1.txt"
afirma "(p) stdout do --aplicar sem token falso de credencial" sem_token "$RAIZ/b.txt"

# Vigia NÃO agendado (/Query sai 1): a migração segue, sem /Delete nem /Create, e o relatório diz isso.
C_NA="$(novo_caso na)"
RC_NA=0
export RFM_SCHTASKS_NAO_AGENDADO=1
unif "$C_NA" --aplicar > "$RAIZ/na.txt" 2>&1 || RC_NA=$?
unset RFM_SCHTASKS_NAO_AGENDADO
afirma "(na) vigia não agendado: --aplicar sai 0" test "$RC_NA" -eq 0
afirma "(na) vigia não agendado: a pasta pessoal é aposentada" test -d "$C_NA/pessoal/.claude-personal.aposentada"
afirma "(na) vigia não agendado: nenhum /Delete" bash -c "! grep -qF '\"/Delete\"' '$C_NA/schtasks-args.txt'"
afirma "(na) vigia não agendado: nenhum /Create" bash -c "! grep -qF '\"/Create\"' '$C_NA/schtasks-args.txt'"
afirma "(na) vigia não agendado: o relatório diz que não estava agendado" grep -qF 'vigia não estava agendado: nada a desagendar nem reagendar' "$RAIZ/na.txt"

# (j) reserva-pessoal.json não é sobrescrita quando já existe pronta.
C_J="$(novo_caso j reserva-pronta)"
H_RES="$(hash_de "$C_J/dados/contas/reserva-pessoal.json")"
RC_J=0
unif "$C_J" --aplicar > "$RAIZ/j.txt" 2>&1 || RC_J=$?
afirma "(j) reserva-pessoal.json não é sobrescrita quando já existe pronta" mesmo_hash "$C_J/dados/contas/reserva-pessoal.json" "$H_RES"
afirma "(j) com reserva pronta, --aplicar ainda sai 0" test "$RC_J" -eq 0

# (k) processo claude vivo: exit 2 e nenhum byte muda.
C_K="$(novo_caso k)"
H_K="$(hash_de "$C_K")"
RC_K=0
PROCESSOS_TESTE=claude.exe unif "$C_K" --aplicar > "$RAIZ/k.txt" 2>&1 || RC_K=$?
afirma "(k) processo claude vivo sai 2" test "$RC_K" -eq 2
afirma "(k) processo claude vivo: nenhum byte muda" mesmo_hash "$C_K" "$H_K"

# (l) whatsapp divergente: exit 2 e nenhum byte muda.
C_L="$(novo_caso l whatsapp-divergente)"
H_L="$(hash_de "$C_L")"
RC_L=0
unif "$C_L" --aplicar > "$RAIZ/l.txt" 2>&1 || RC_L=$?
afirma "(l) whatsapp divergente sai 2" test "$RC_L" -eq 2
afirma "(l) whatsapp divergente: nenhum byte muda" mesmo_hash "$C_L" "$H_L"

# (m) pasta pessoal fora de casa no estado.json: exit 2.
C_M="$(novo_caso m estado-fora)"
RC_M=0
unif "$C_M" --aplicar > "$RAIZ/m.txt" 2>&1 || RC_M=$?
afirma "(m) pasta pessoal fora de casa no estado.json sai 2" test "$RC_M" -eq 2

# (n) --ajuda imprime as flags, uma por linha, e sai 0.
C_N="$(novo_caso n)"
RC_N=0
unif "$C_N" --ajuda > "$RAIZ/n.txt" 2>&1 || RC_N=$?
afirma "(n) unificar --ajuda sai 0" test "$RC_N" -eq 0
afirma "(n) unificar --ajuda lista --aplicar em linha própria" grep -qx -- '--aplicar' "$RAIZ/n.txt"
afirma "(n) unificar --ajuda lista --ajuda em linha própria" grep -qx -- '--ajuda' "$RAIZ/n.txt"

# Extra: sessão viva no sessoes.json recusa com exit 2 e nenhum byte muda.
C_Q="$(novo_caso q sessao-viva)"
H_Q="$(hash_de "$C_Q")"
RC_Q=0
unif "$C_Q" --aplicar > "$RAIZ/q.txt" 2>&1 || RC_Q=$?
afirma "(extra) sessão viva no sessoes.json sai 2 e nenhum byte muda" test "$RC_Q" -eq 2
afirma "(extra) sessão viva: nenhum byte muda" mesmo_hash "$C_Q" "$H_Q"

# ---------------------------------------------------------------------------------------------
# Achados 1 a 8 da revisão (rodada 2). Cada achado tem ao menos um caso que fica VERMELHO no código
# da base. Os casos marcados "guarda" já passam na base: travam um comportamento que não pode regredir.

# Achado 1: a credencial da pessoal sai da aposentada (vai só para a reserva); as outras chaves ficam.
C_1="$(novo_caso ach1)"
unif "$C_1" --aplicar > "$RAIZ/ach1.txt" 2>&1 || true
APOS_1="$C_1/pessoal/.claude-personal.aposentada/.credentials.json"
afirma "(achado 1) após --aplicar, a aposentada não tem claudeAiOauth" test "$(ler "$APOS_1" claudeAiOauth)" = AUSENTE
afirma "(achado 1) após --aplicar, a aposentada mantém as outras chaves (mcpOAuth)" test "$(ler "$APOS_1" mcpOAuth.falso.accessToken)" = falso-mcp-oauth
afirma "(achado 1) o refresh token da pessoal fica em um arquivo só (reserva ou aposentada)" test "$(grep -rl -F falso-refresh-pessoal-cred "$C_1/dados/contas" "$C_1/pessoal/.claude-personal.aposentada" | wc -l)" -eq 1

# Achado 1, reserva já pronta com o MESMO refresh token: a aposentada também perde a credencial.
C_1B="$(novo_caso ach1b reserva-mesmo-token)"
unif "$C_1B" --aplicar > "$RAIZ/ach1b.txt" 2>&1 || true
afirma "(achado 1) reserva pronta com o mesmo refresh token: a aposentada perde a claudeAiOauth" test "$(ler "$C_1B/pessoal/.claude-personal.aposentada/.credentials.json" claudeAiOauth)" = AUSENTE

# Achado 1, guarda: reserva pronta com OUTRO refresh token: a aposentada guarda a credencial dela (não está na reserva).
C_1C="$(novo_caso ach1c reserva-pronta)"
unif "$C_1C" --aplicar > "$RAIZ/ach1c.txt" 2>&1 || true
afirma "(achado 1, guarda) reserva pronta com outro refresh token: a aposentada guarda a credencial dela" test "$(ler "$C_1C/pessoal/.claude-personal.aposentada/.credentials.json" claudeAiOauth.refreshToken)" = falso-refresh-pessoal-cred

# Achado 2: reexecutar depois de renomear a aposentada de volta sai 0 e não duplica nada.
C_2="$(novo_caso ach2)"
H_2_PES="$(hash_de "$C_2/pessoal/.claude-personal/projects/-proj-x/memory/a.md")"
unif "$C_2" --aplicar > "$RAIZ/ach2a.txt" 2>&1 || true
mv "$C_2/pessoal/.claude-personal.aposentada" "$C_2/pessoal/.claude-personal"
RC_2=0
unif "$C_2" --aplicar > "$RAIZ/ach2b.txt" 2>&1 || RC_2=$?
afirma "(achado 2) reexecutar depois de renomear a aposentada de volta sai 0" test "$RC_2" -eq 0
afirma "(achado 2) o .pessoal.md já gravado é reconhecido como igual (não duplica)" mesmo_hash "$C_2/trabalho/.claude/projects/-proj-x/memory/a.pessoal.md" "$H_2_PES"
afirma "(achado 2) reexecutar não repete a linha do histórico" test "$(grep -cF 'falso-linha-dois' "$C_2/trabalho/.claude/history.jsonl")" -eq 1

# Achado 3: falha no rename da pasta (injeção só com RFM_TEST=1): diz o que foi feito, que o vigia está
# desagendado e o comando para continuar; sai diferente de 0. Rodar o comando de novo termina com 0.
C_3="$(novo_caso ach3)"
export RFM_CONTA_FALHA=renomear
RC_3=0
unif "$C_3" --aplicar > "$RAIZ/ach3.txt" 2>&1 || RC_3=$?
unset RFM_CONTA_FALHA
afirma "(achado 3) falha no meio da migração sai com exit diferente de 0" test "$RC_3" -ne 0
afirma "(achado 3) a falha diz que o vigia está desagendado" grep -qF 'desagendado' "$RAIZ/ach3.txt"
afirma "(achado 3) a falha diz o comando para continuar" grep -qF 'unificar --aplicar' "$RAIZ/ach3.txt"
RC_3B=0
unif "$C_3" --aplicar > "$RAIZ/ach3b.txt" 2>&1 || RC_3B=$?
afirma "(achado 3) o comando indicado, rodado de novo, termina com exit 0" test "$RC_3B" -eq 0
afirma "(achado 3) depois de rodar de novo, a pasta pessoal está aposentada" test -d "$C_3/pessoal/.claude-personal.aposentada"

# Achado 4: com a trava do vigia ocupada (lock fresco de outro processo), --aplicar recusa e nada muda.
C_4="$(novo_caso ach4)"
printf '{"pid":1,"em":%s}\n' "$(node -e 'console.log(Date.now())')" > "$C_4/dados/contas/vigia.lock"
H_4="$(hash_de "$C_4")"
RC_4=0
unif "$C_4" --aplicar > "$RAIZ/ach4.txt" 2>&1 || RC_4=$?
afirma "(achado 4) com a trava do vigia ocupada, --aplicar sai 2" test "$RC_4" -eq 2
afirma "(achado 4) com a trava do vigia ocupada, nenhum byte muda" mesmo_hash "$C_4" "$H_4"

# Achado 4, complemento: o status do /Delete não é ignorado. Falhou: --aplicar sai diferente de 0 antes de escrever.
C_4B="$(novo_caso ach4b)"
H_4B="$(hash_de "$C_4B")"
export RFM_SCHTASKS_FALHA=1
RC_4B=0
unif "$C_4B" --aplicar > "$RAIZ/ach4b.txt" 2>&1 || RC_4B=$?
unset RFM_SCHTASKS_FALHA
afirma "(achado 4) /Delete que falha: --aplicar sai diferente de 0" test "$RC_4B" -ne 0
afirma "(achado 4) /Delete que falha: nenhum byte muda" mesmo_hash "$C_4B" "$H_4B"

# Achado 5: o relatório agrupa por classe mesmo com separador Windows (\), nunca um item por arquivo.
C_5="$(novo_caso ach5)"
unif "$C_5" > "$RAIZ/ach5.txt" 2>&1 || true
afirma "(achado 5) relatório agrupa a memória numa linha de classe" grep -qx 'copiar memoria: 2 arquivo(s)' "$RAIZ/ach5.txt"
afirma "(achado 5) relatório agrupa os transcritos numa linha de classe" grep -qx 'copiar transcritos: 1 arquivo(s)' "$RAIZ/ach5.txt"

# Achado 6: sem o clone instalado (destino do reagendamento), --aplicar recusa antes de escrever.
C_6="$(novo_caso ach6 sem-clone)"
H_6="$(hash_de "$C_6")"
RC_6=0
unif "$C_6" --aplicar > "$RAIZ/ach6.txt" 2>&1 || RC_6=$?
afirma "(achado 6) sem o clone instalado, --aplicar sai 2" test "$RC_6" -eq 2
afirma "(achado 6) sem o clone instalado, nenhum byte muda" mesmo_hash "$C_6" "$H_6"
afirma "(achado 6) a recusa nomeia clone_ausente" grep -qF 'clone_ausente' "$RAIZ/ach6.txt"

# Achado 7: com a pasta pessoal já aposentada, --profile refaz só o perfil.
C_7="$(novo_caso ach7)"
unif "$C_7" --aplicar > "$RAIZ/ach7a.txt" 2>&1 || true
PERF_7="$C_7/perfil.ps1"
cat > "$PERF_7" <<'PS'
function claude-pessoal {
    $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-personal"
    & claude @args
}
function claude-trabalho {
    Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    & claude @args
}
function Update-ClaudePlugins {
    & claude plugin update rainforest-mind@rainforest-mind --scope user
}
PS
RC_7=0
unif "$C_7" --profile "$(win "$PERF_7")" --aplicar > "$RAIZ/ach7.txt" 2>&1 || RC_7=$?
afirma "(achado 7) com a pasta pessoal já aposentada, --profile refaz só o perfil: exit 0" test "$RC_7" -eq 0
afirma "(achado 7) o perfil ficou com a função claude e sem claude-pessoal" bash -c "grep -q '^function claude {' '$PERF_7' && ! grep -q 'function claude-pessoal' '$PERF_7'"
afirma "(achado 7) o original do perfil fica em .bak-pasta-unica" test -f "$PERF_7.bak-pasta-unica"

# Achado 7: plugin que não instala faz a migração sair diferente de 0 e diz o comando para repetir a instalação.
C_7B="$(novo_caso ach7b)"
export RFM_FAKE_FALHA=1
RC_7B=0
unif "$C_7B" --aplicar > "$RAIZ/ach7b.txt" 2>&1 || RC_7B=$?
unset RFM_FAKE_FALHA
afirma "(achado 7) plugin que não instala: sai diferente de 0" test "$RC_7B" -ne 0
afirma "(achado 7) plugin que não instala: a saída traz o comando para repetir a instalação" grep -qF 'claude plugin install security-guidance@claude-plugins-official --scope user' "$RAIZ/ach7b.txt"

# Achado 8: plugin install recebe a CLI SEM CLAUDE_CONFIG_DIR no ambiente (o remover, não o definir).
C_8="$(novo_caso ach8)"
export CLAUDE_CONFIG_DIR="$(win "$C_8/pessoal/.claude-personal")"
unif "$C_8" --aplicar > "$RAIZ/ach8.txt" 2>&1 || true
unset CLAUDE_CONFIG_DIR
afirma "(achado 8) plugin install recebe a CLI sem CLAUDE_CONFIG_DIR no ambiente" bash -c "grep -q '^UNSET plugin install security-guidance@claude-plugins-official' '$C_8/cli-env.txt' && ! grep -q '^SET ' '$C_8/cli-env.txt'"

# ---------------------------------------------------------------------------------------------
# Revisão 3 (rodada 3 de 2026-10-12-pasta-unica): um caso por achado 1 a 6 e por lacuna (a) a (c) que cabe aqui.
# Predicados tolerantes a arquivo ausente: nenhum comando fora de afirma pode abortar a bateria (set -e).
um_create() { [ "$(grep -c '"/Create"' "$1" || true)" = "1" ]; }
sem_linha_repetida() { [ "$(grep -cF "$2" "$1" || true)" -le 1 ]; }

# Achado 1: a 1ª rodada apaga a tarefa e falha no rename. A 2ª tem de reagendar (/Create), mesmo com o
# /Query devolvendo 1 (a tarefa já foi apagada pela 1ª rodada).
C_1R="$(novo_caso ach1r)"
export RFM_CONTA_FALHA=renomear
RC_1R1=0
unif "$C_1R" --aplicar > "$RAIZ/ach1r1.txt" 2>&1 || RC_1R1=$?
unset RFM_CONTA_FALHA
RC_1R2=0
unif "$C_1R" --aplicar > "$RAIZ/ach1r2.txt" 2>&1 || RC_1R2=$?
afirma "(achado 1) a 1ª rodada, com rename que falha depois do /Delete, sai diferente de 0" test "$RC_1R1" -ne 0
afirma "(achado 1) a 2ª rodada, com a tarefa já apagada, sai 0" test "$RC_1R2" -eq 0
afirma "(achado 1) a 2ª rodada reagenda: exatamente um /Create no log" um_create "$C_1R/schtasks-args.txt"

# Achado 2: pasta de trabalho fora de casa (login de outra conta) recusa antes de escrever.
C_T="$(novo_caso trab-fora estado-fora-trabalho)"
H_T="$(hash_de "$C_T")"
RC_T=0
unif "$C_T" --aplicar > "$RAIZ/trab.txt" 2>&1 || RC_T=$?
afirma "(achado 2) pasta de trabalho fora de casa sai 2" test "$RC_T" -eq 2
afirma "(achado 2) pasta de trabalho fora de casa: nenhum byte muda" mesmo_hash "$C_T" "$H_T"

# Achado 4: b.md já copiada numa rodada anterior (igual à da pessoal) e a linha (b.md) ainda fora do índice:
# a linha entra, uma vez.
C_M4="$(novo_caso ach4m memoria-pre)"
RC_M4=0
unif "$C_M4" --aplicar > "$RAIZ/ach4m.txt" 2>&1 || RC_M4=$?
afirma "(achado 4) b.md copiada antes: --aplicar sai 0" test "$RC_M4" -eq 0
afirma "(achado 4) b.md copiada antes: a linha (b.md) entra no índice, exatamente uma vez" test "$(grep -cF '(b.md)' "$C_M4/trabalho/.claude/projects/-proj-x/memory/MEMORY.md")" -eq 1

# Achado 4: linha do índice cujo alvo não existe em lugar nenhum: a 1ª rodada falha depois do índice e a 2ª
# roda de novo. A linha não pode aparecer duas vezes.
C_Z4="$(novo_caso ach4z indice-z)"
export RFM_CONTA_FALHA=renomear
unif "$C_Z4" --aplicar > "$RAIZ/ach4z1.txt" 2>&1 || true
unset RFM_CONTA_FALHA
RC_Z4=0
unif "$C_Z4" --aplicar > "$RAIZ/ach4z2.txt" 2>&1 || RC_Z4=$?
afirma "(achado 4) linha sem alvo, com retomada: a 2ª rodada sai 0" test "$RC_Z4" -eq 0
afirma "(achado 4) linha sem alvo, com retomada: nunca duplicada no índice" sem_linha_repetida "$C_Z4/trabalho/.claude/projects/-proj-x/memory/MEMORY.md" '(z.md)'

# Achado 5: --aplicar sem --profile diz que o perfil ficou intocado (e a linha exata do briefing).
afirma "(achado 5) --aplicar sem --profile diz que o perfil não foi tocado" grep -qF 'perfil do PowerShell: não tocado (passe --profile <arquivo> para trocar)' "$RAIZ/b.txt"

# Achado 6: a falha em que a credencial já saiu da pasta pessoal (rename depois dela) diz que a pasta ficou sem login.
afirma "(achado 6) falha depois de a credencial sair da pasta pessoal diz que ela ficou sem login" grep -qF 'sem login' "$RAIZ/ach3.txt"

# Lacuna (b): processo claude vivo recusa com a instrução de uma linha para rodar num terminal sem Claude.
afirma "(lacuna b) processo claude vivo: a recusa diz para rodar num terminal sem Claude aberto" grep -qF 'terminal sem Claude aberto' "$RAIZ/k.txt"

# Lacuna (c): caminho de projects que já existe nas duas pastas aparece no relatório como não mesclado.
C_PC="$(novo_caso comum projeto-comum)"
unif "$C_PC" > "$RAIZ/comum.txt" 2>&1 || true
afirma "(lacuna c) relatório lista o caminho de projects já existente nas duas pastas como não mesclado" grep -qF 'não mesclados: /falso/comum' "$RAIZ/comum.txt"

# Rodada 4, achado 1: retomada com conflito de memória. O índice tem de sair igual ao de uma rodada única limpa:
# o alvo que ficou em conflito (a.md -> a.pessoal.md) não entra no MEMORY.md, nem na 2ª rodada.
C_REF="$(novo_caso ach1ref)"
RC_REF=0
unif "$C_REF" --aplicar > "$RAIZ/ach1ref.txt" 2>&1 || RC_REF=$?
C_1X="$(novo_caso ach1x)"
export RFM_CONTA_FALHA=renomear
unif "$C_1X" --aplicar > "$RAIZ/ach1x1.txt" 2>&1 || true
unset RFM_CONTA_FALHA
RC_1X=0
unif "$C_1X" --aplicar > "$RAIZ/ach1x2.txt" 2>&1 || RC_1X=$?
MEM_REF="$C_REF/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
MEM_1X="$C_1X/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(rodada 4, achado 1) referência de rodada única: --aplicar sai 0" test "$RC_REF" -eq 0
afirma "(rodada 4, achado 1) retomada com conflito: a 2ª rodada sai 0" test "$RC_1X" -eq 0
afirma "(rodada 4, achado 1) retomada com conflito: MEMORY.md igual ao de uma rodada única limpa" mesmo_hash "$MEM_1X" "$(hash_de "$MEM_REF")"
afirma "(rodada 4, achado 1) retomada com conflito: a linha do alvo renomeado (a.md) não entra no índice" test "$(grep -cF '[A2]' "$MEM_1X")" -eq 0

# Rodada 4, achado 1, variante: a.md idêntico nas duas pastas desde o início. Numa rodada limpa, a linha pessoal
# de a.md não entra (o destino já tinha o alvo); a de b.md (copiado agora) entra.
C_AI="$(novo_caso ach1ident a-identico)"
RC_AI=0
unif "$C_AI" --aplicar > "$RAIZ/ach1ident.txt" 2>&1 || RC_AI=$?
MEM_AI="$C_AI/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(rodada 4, achado 1, variante) a.md idêntico nas duas pastas: --aplicar sai 0" test "$RC_AI" -eq 0
afirma "(rodada 4, achado 1, variante) a.md idêntico desde o início: nenhuma linha pessoal de a.md entra no índice" test "$(grep -cF '[A2]' "$MEM_AI")" -eq 0
afirma "(rodada 4, achado 1, variante) a linha de b.md (copiado agora) continua entrando" test "$(grep -cF '(b.md)' "$MEM_AI")" -eq 1

# Rodada 5, achado 4: o processo morre no meio da cópia. Um preload de teste (--require) faz process.exit logo depois
# de copiar b.md (memória copiada com o mesmo nome), sem finally, como um kill. A retomada tem de deixar o MEMORY.md
# igual ao de uma rodada única limpa: o que já foi copiado tem de estar no progresso antes da cópia seguinte.
cat > "$RAIZ/morte5.cjs" <<'JS'
// Morte de processo no meio da cópia (rodada 5, achado 4): sai logo depois de copiar b.md, sem finally.
const fs = require('fs');
const copiar = fs.copyFileSync;
fs.copyFileSync = function (origem, destino, modo) {
  const r = copiar.call(fs, origem, destino, modo);
  if (/[\\/]memory[\\/]b\.md$/.test(String(destino))) process.exit(9);
  return r;
};
JS
C_M5="$(novo_caso morte5)"
RC_M5=0
export NODE_OPTIONS="--require $(win "$RAIZ/morte5.cjs")"
unif "$C_M5" --aplicar > "$RAIZ/morte5-1.txt" 2>&1 || RC_M5=$?
unset NODE_OPTIONS
RC_M5R=0
# A trava que o processo morto deixou sai pela regra de validade (caso u de testa-conta.sh); aqui ela é apagada
# para a retomada não esperar o relógio. O resto da retomada não depende dela.
rm -f "$C_M5/dados/contas/vigia.lock"
unif "$C_M5" --aplicar > "$RAIZ/morte5-2.txt" 2>&1 || RC_M5R=$?
MEM_M5="$C_M5/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(rodada 5, achado 4) a morte injetada no meio da cópia sai ≠ 0 (a injeção disparou)" test "$RC_M5" -ne 0
afirma "(rodada 5, achado 4) retomada depois da morte: a 2ª rodada sai 0" test "$RC_M5R" -eq 0
[ "$RC_M5R" -eq 0 ] || { echo "      saída da 2ª rodada:"; tail -n 3 "$RAIZ/morte5-2.txt"; }
afirma "(rodada 5, achado 4) retomada depois da morte: MEMORY.md igual ao de uma rodada única limpa" mesmo_hash "$MEM_M5" "$(hash_de "$MEM_REF")"

# Rodada 6, achado 3: o progresso virou append-only (uma linha por cópia). A morte agora vem na cópia SEGUINTE à de
# b.md: o progresso tem de guardar b.md E as cópias posteriores. Se cada gravação substituísse o arquivo, só a
# última sobraria, b.md voltaria como "já existia no destino" e a linha dele sumiria do índice.
cat > "$RAIZ/morte6.cjs" <<'JS'
// Morte de processo na cópia seguinte à de b.md (rodada 6, achado 3), sem finally.
const fs = require('fs');
const copiar = fs.copyFileSync;
let depoisDeB = false;
fs.copyFileSync = function (origem, destino, modo) {
  if (depoisDeB) process.exit(9);
  const r = copiar.call(fs, origem, destino, modo);
  if (/[\\/]memory[\\/]b\.md$/.test(String(destino))) depoisDeB = true;
  return r;
};
JS
C_M6="$(novo_caso morte6)"
RC_M6=0
export NODE_OPTIONS="--require $(win "$RAIZ/morte6.cjs")"
unif "$C_M6" --aplicar > "$RAIZ/morte6-1.txt" 2>&1 || RC_M6=$?
unset NODE_OPTIONS
rm -f "$C_M6/dados/contas/vigia.lock"
RC_M6R=0
unif "$C_M6" --aplicar > "$RAIZ/morte6-2.txt" 2>&1 || RC_M6R=$?
MEM_M6="$C_M6/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(rodada 6, achado 3) a morte na cópia seguinte à de b.md sai ≠ 0 (a injeção disparou)" test "$RC_M6" -ne 0
afirma "(rodada 6, achado 3) retomada: a 2ª rodada sai 0" test "$RC_M6R" -eq 0
afirma "(rodada 6, achado 3) retomada: MEMORY.md igual ao de uma rodada única limpa (b.md continua no progresso)" mesmo_hash "$MEM_M6" "$(hash_de "$MEM_REF")"

# Rodada 6, achado 1: estado.json sem contas.pessoal. --aplicar registra a conta pessoal (do oauthAccount da pasta
# pessoal) ANTES de a pasta sair; depois, trocar pessoal não diz "sem registro". A API falsa só existe neste bloco
# (trocar confere a identidade por ela); sem RFM_CONTA_API a bateria cairia na rede real.
cat > "$RAIZ/servidor-r1.cjs" <<'JS'
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
USO_R1='{"five_hour": {"utilization": 2, "resets_at": "2030-01-01T00:00:00+00:00"}, "seven_day": {"utilization": 7, "resets_at": "2030-01-01T00:00:00+00:00"}}'
cat > "$RAIZ/mapa-r1.json" <<JSON
{
  "falso-token-team": {"email": "team@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000a", "uso": $USO_R1},
  "falso-token-pessoal-cred": {"email": "pessoal@exemplo.invalid", "uuid": "00000000-0000-0000-0000-00000000000b", "uso": $USO_R1}
}
JSON
node "$RAIZ/servidor-r1.cjs" "$RAIZ/mapa-r1.json" > "$RAIZ/porta-r1.txt" 2> "$RAIZ/servidor-r1-erro.txt" &
SRV_R1=$!
for _ in $(seq 1 100); do [ -s "$RAIZ/porta-r1.txt" ] && break; sleep 0.1; done
API_R1="http://127.0.0.1:$(head -n1 "$RAIZ/porta-r1.txt")"
C_R1="$(novo_caso r1)"
RC_R1=0
unif "$C_R1" --aplicar > "$RAIZ/r1.txt" 2>&1 || RC_R1=$?
afirma "(rodada 6, achado 1) fixture sem contas.pessoal: --aplicar sai 0" test "$RC_R1" -eq 0
afirma "(rodada 6, achado 1) após --aplicar, estado.json tem contas.pessoal.email" test "$(ler "$C_R1/dados/contas/estado.json" contas.pessoal.email)" = pessoal@exemplo.invalid
afirma "(rodada 6, achado 1) após --aplicar, o oauthAccount registrado é o da pessoal" test "$(ler "$C_R1/dados/contas/estado.json" contas.pessoal.oauthAccount.emailAddress)" = pessoal@exemplo.invalid
RC_R1T=0
RFM_TEST=1 \
RFM_CONTA_PASTA_TRABALHO="$(win "$C_R1/trabalho/.claude")" \
RFM_CONTA_PASTA_PESSOAL="$(win "$C_R1/pessoal/.claude-personal")" \
RFM_CONTA_CLAUDE_JSON="$(win "$C_R1/trabalho/.claude.json")" \
RFM_CONTA_DADOS="$(win "$C_R1/dados")" \
RFM_CONTA_API="$API_R1" \
node scripts/conta.cjs trocar pessoal --pasta trabalho > "$RAIZ/r1-trocar.txt" 2>&1 || RC_R1T=$?
echo "      trocar pessoal (saída, exit $RC_R1T):"; sed 's/^/        /' "$RAIZ/r1-trocar.txt"
afirma "(rodada 6, achado 1) trocar pessoal não diz 'sem registro'" bash -c "! grep -qF 'sem registro' '$RAIZ/r1-trocar.txt'"
kill "$SRV_R1" 2>/dev/null || true
unset SRV_R1

# Rodada 6, achado 2: uma sessão grava o .claude.json de trabalho DEPOIS do planejar e ANTES da etapa dele.
# Um preload de teste (--require) faz essa gravação na primeira cópia: a chave nova e o numStartups da sessão têm
# de sobreviver, e os mcpServers/projects da pessoal têm de entrar.
cat > "$RAIZ/sessao2.cjs" <<'JS'
// Gravação concorrente do .claude.json de trabalho (rodada 6, achado 2): na primeira cópia, a "sessão" escreve.
const fs = require('fs');
const copiar = fs.copyFileSync;
let feito = false;
fs.copyFileSync = function (...args) {
  if (!feito && process.env.RFM_GANCHO_CLAUDE) {
    feito = true;
    const atual = JSON.parse(fs.readFileSync(process.env.RFM_GANCHO_CLAUDE, 'utf8'));
    atual.chaveDaSessao = 1;
    atual.numStartups = 7;
    fs.writeFileSync(process.env.RFM_GANCHO_CLAUDE, JSON.stringify(atual, null, 2) + '\n');
  }
  return copiar.apply(fs, args);
};
JS
C_2B="$(novo_caso ach2b)"
export RFM_GANCHO_CLAUDE="$(win "$C_2B/trabalho/.claude.json")"
export NODE_OPTIONS="--require $(win "$RAIZ/sessao2.cjs")"
RC_2B=0
unif "$C_2B" --aplicar > "$RAIZ/ach2b.txt" 2>&1 || RC_2B=$?
unset NODE_OPTIONS RFM_GANCHO_CLAUDE
CJ_2B="$C_2B/trabalho/.claude.json"
afirma "(rodada 6, achado 2) --aplicar sai 0" test "$RC_2B" -eq 0
afirma "(rodada 6, achado 2) a chave nova gravada pela sessão sobrevive" test "$(ler "$CJ_2B" chaveDaSessao)" = 1
afirma "(rodada 6, achado 2) o numStartups gravado pela sessão (7) sobrevive, não volta ao valor antigo (2)" test "$(ler "$CJ_2B" numStartups)" = 7
afirma "(rodada 6, achado 2) mcpServers da pessoal entram (github)" test "$(ler "$CJ_2B" mcpServers.github.command)" = falso-gh
afirma "(rodada 6, achado 2) projects da pessoal entram (/falso/pessoal)" test "$(ler "$CJ_2B" 'projects./falso/pessoal')" != AUSENTE
afirma "(rodada 6, achado 2) o whatsapp do destino continua igual" test "$(ler "$CJ_2B" mcpServers.whatsapp.command)" = falso-whatsapp

# #503 D1: linha rasgada no progresso (sem aspa de fecho e sem \n), deixada por uma morte no meio da escrita.
# Uma rodada única não lê o progresso (ele só é lido na retomada e apagado ao fim), então o caso morre na cópia
# seguinte à de b.md (morte6.cjs) e a 2ª rodada retoma. Sem o \n na frente de cada gravação, a entrada de b.md cai
# na linha rasgada, a retomada não a reconhece e a linha do índice some. MEMORY.md tem de sair igual à rodada limpa.
# O transcrito já vem igual no destino (não grava progresso), para que a primeira gravação depois da linha rasgada
# seja a de b.md: com o \n que falta, ela cai na linha rasgada (um transcrito copiado antes lhe daria um \n de sobra).
C_D1="$(novo_caso d1)"
mkdir -p "$C_D1/trabalho/.claude/projects/-proj-x"
cp "$C_D1/pessoal/.claude-personal/projects/-proj-x/11111111-1111-4111-8111-111111111111.jsonl" "$C_D1/trabalho/.claude/projects/-proj-x/"
printf '%s' '"projects/-proj-x/memory/b.md' > "$C_D1/dados/contas/unificar-progresso.jsonl"
RC_D1=0
export NODE_OPTIONS="--require $(win "$RAIZ/morte6.cjs")"
unif "$C_D1" --aplicar > "$RAIZ/d1-1.txt" 2>&1 || RC_D1=$?
unset NODE_OPTIONS
rm -f "$C_D1/dados/contas/vigia.lock"
RC_D1R=0
unif "$C_D1" --aplicar > "$RAIZ/d1-2.txt" 2>&1 || RC_D1R=$?
MEM_D1="$C_D1/trabalho/.claude/projects/-proj-x/memory/MEMORY.md"
afirma "(#503 D1) a morte injetada sai ≠ 0 (a injeção disparou)" test "$RC_D1" -ne 0
afirma "(#503 D1) retomada sobre progresso com linha rasgada: a 2ª rodada sai 0" test "$RC_D1R" -eq 0
afirma "(#503 D1) retomada: MEMORY.md igual ao de uma rodada única limpa" mesmo_hash "$MEM_D1" "$(hash_de "$MEM_REF")"

# #503 D5: uma sessão grava mcpServers.github com outra definição DEPOIS do planejar e ANTES da etapa .claude.json.
# A definição do destino tem de sobreviver, a saída tem de dizer que github foi mantido, e a linha de gravados não
# pode listar github.
cat > "$RAIZ/sessao503.cjs" <<'JS'
// Gravação concorrente do .claude.json de trabalho (#503 D5): na primeira cópia, a "sessão" grava mcpServers.github.
const fs = require('fs');
const copiar = fs.copyFileSync;
let feito = false;
fs.copyFileSync = function (...args) {
  if (!feito && process.env.RFM_GANCHO_CLAUDE) {
    feito = true;
    const atual = JSON.parse(fs.readFileSync(process.env.RFM_GANCHO_CLAUDE, 'utf8'));
    atual.mcpServers = { ...(atual.mcpServers || {}), github: { type: 'stdio', command: 'outro-gh' } };
    fs.writeFileSync(process.env.RFM_GANCHO_CLAUDE, JSON.stringify(atual, null, 2) + '\n');
  }
  return copiar.apply(fs, args);
};
JS
C_D5="$(novo_caso d5)"
export RFM_GANCHO_CLAUDE="$(win "$C_D5/trabalho/.claude.json")"
export NODE_OPTIONS="--require $(win "$RAIZ/sessao503.cjs")"
RC_D5=0
unif "$C_D5" --aplicar > "$RAIZ/d5.txt" 2>&1 || RC_D5=$?
unset NODE_OPTIONS RFM_GANCHO_CLAUDE
afirma "(#503 D5) --aplicar sai 0" test "$RC_D5" -eq 0
afirma "(#503 D5) a definição do destino (outro-gh) sobrevive ao mesclar" test "$(ler "$C_D5/trabalho/.claude.json" mcpServers.github.command)" = outro-gh
afirma "(#503 D5) a saída diz que github foi mantido do destino" grep -qF 'mcp mantido do destino: github' "$RAIZ/d5.txt"
afirma "(#503 D5) a linha 'mcp em .claude.json' não lista github como gravado" bash -c "grep '^mcp em .claude.json:' '$RAIZ/d5.txt' | grep -qvF '(github)'"

# #503 D2/D3: pessoal sem oauthAccount. O relatório (sem --aplicar) já recusa com a mensagem que manda fazer login na
# pasta pessoal; o --aplicar recusa com a mesma mensagem. Nada é gravado: os hashes de antes valem depois. A mensagem
# não manda para preparar nem status: com as duas pastas, os dois devolvem à mesma recusa.
C_D23="$(novo_caso d23 pessoal-sem-oauth)"
H_D23_ESTADO="$(hash_de "$C_D23/dados/contas/estado.json")"
H_D23_CJ="$(hash_de "$C_D23/trabalho/.claude.json")"
RC_D23R=0
unif "$C_D23" > "$RAIZ/d23-rel.txt" 2>&1 || RC_D23R=$?
RC_D23=0
unif "$C_D23" --aplicar > "$RAIZ/d23-apl.txt" 2>&1 || RC_D23=$?
afirma "(#503 D2) relatório sem --aplicar com pessoal sem oauthAccount sai 2" test "$RC_D23R" -eq 2
afirma "(#503 D2) a recusa do relatório manda fazer login na pasta pessoal" grep -qF '/login' "$RAIZ/d23-rel.txt"
afirma "(#503 D2) a recusa do relatório não manda rodar status" bash -c "! grep -qF 'rode status' '$RAIZ/d23-rel.txt'"
afirma "(#503 D3) a recusa do relatório não manda rodar preparar" bash -c "! grep -qF 'preparar' '$RAIZ/d23-rel.txt'"
afirma "(#503 D3) --aplicar com pessoal sem oauthAccount sai 2" test "$RC_D23" -eq 2
afirma "(#503 D3) a recusa do --aplicar manda fazer login na pasta pessoal" grep -qF '/login' "$RAIZ/d23-apl.txt"
afirma "(#503 D2/D3) estado.json igual ao de antes da recusa" mesmo_hash "$C_D23/dados/contas/estado.json" "$H_D23_ESTADO"
afirma "(#503 D2/D3) .claude.json de trabalho igual ao de antes da recusa" mesmo_hash "$C_D23/trabalho/.claude.json" "$H_D23_CJ"
# O caminho que a mensagem indica termina: o login grava oauthAccount no .claude.json da pasta pessoal, e o unificar
# seguinte aceita (relatório sai 0) sem pedir outro passo.
node -e "const fs=require('fs');const a=process.argv[1];const o=JSON.parse(fs.readFileSync(a,'utf8'));o.oauthAccount={accountUuid:'00000000-0000-0000-0000-000000000002',emailAddress:'pessoal@exemplo.invalid',organizationUuid:'00000000-0000-0000-0000-000000000000',displayName:'Conta Falsa'};fs.writeFileSync(a,JSON.stringify(o,null,2)+'\n');" "$(win "$C_D23/pessoal/.claude-personal/.claude.json")"
RC_D23L=0
unif "$C_D23" > "$RAIZ/d23-login.txt" 2>&1 || RC_D23L=$?
afirma "(#503 D3) depois do login na pasta pessoal, o relatório do unificar sai 0" test "$RC_D23L" -eq 0
afirma "(#503 D3) depois do login, a saída não recusa mais a conta pessoal" bash -c "! grep -qF 'sem oauthAccount' '$RAIZ/d23-login.txt'"

# #503 D4: a pessoal tem o mesmo e-mail da team registrada. Recusa no relatório e no --aplicar, sem registrar a pessoal.
C_D4="$(novo_caso d4 pessoal-email-team)"
RC_D4R=0
unif "$C_D4" > "$RAIZ/d4-rel.txt" 2>&1 || RC_D4R=$?
RC_D4=0
unif "$C_D4" --aplicar > "$RAIZ/d4-apl.txt" 2>&1 || RC_D4=$?
afirma "(#503 D4) relatório sem --aplicar com e-mail da team sai 2" test "$RC_D4R" -eq 2
afirma "(#503 D4) a recusa do relatório nomeia team@exemplo.invalid" grep -qF 'team@exemplo.invalid' "$RAIZ/d4-rel.txt"
afirma "(#503 D4) --aplicar com e-mail da team sai 2" test "$RC_D4" -eq 2
afirma "(#503 D4) estado.json não ganha contas.pessoal" test "$(ler "$C_D4/dados/contas/estado.json" contas.pessoal.email)" = AUSENTE

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
