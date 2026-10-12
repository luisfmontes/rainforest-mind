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
trap 'rm -rf "$RAIZ"' EXIT

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
j(path.join(H, '.claude.json'), { numStartups: 2, oauthAccount: oauth('team@exemplo.invalid'), mcpServers: { whatsapp: WA }, projects: { '/falso/trabalho': {} } });
j(path.join(T, '.credentials.json'), { claudeAiOauth: { accessToken: 'falso-token-team', refreshToken: 'falso-refresh-team', expiresAt: VIDA, scopes: ['user:inference'], subscriptionType: 'max' } });
j(path.join(T, 'settings.json'), { model: 'falso' });
w(path.join(T, 'history.jsonl'), '{"display":"falso-linha-um"}\n');
w(path.join(T, 'projects', '-proj-x', 'memory', 'MEMORY.md'), '- [A](a.md) — trabalho\n');
w(path.join(T, 'projects', '-proj-x', 'memory', 'a.md'), 'trabalho a\n');
// Pasta pessoal (origem).
j(path.join(P, '.credentials.json'), { claudeAiOauth: { accessToken: 'falso-token-pessoal-cred', refreshToken: 'falso-refresh-pessoal-cred', expiresAt: VIDA, scopes: ['user:inference'], subscriptionType: 'max' } });
j(path.join(P, '.claude.json'), { numStartups: 1, oauthAccount: oauth('pessoal@exemplo.invalid'), mcpServers: { whatsapp: variante === 'whatsapp-divergente' ? WA_OUTRA : WA, github: { type: 'stdio', command: 'falso-gh', env: { GH_TOKEN_FALSO: 'falso-gh-token-xyz' } } }, projects: { '/falso/pessoal': {} } });
j(path.join(P, 'settings.json'), { enabledPlugins: { 'security-guidance@claude-plugins-official': true } });
w(path.join(P, 'history.jsonl'), '{"display":"falso-linha-um"}\n{"display":"falso-linha-dois"}\n{"display":"falso-linha-dois"}\n');
w(path.join(P, 'projects', '-proj-x', '11111111-1111-4111-8111-111111111111.jsonl'), '{"falso":"transcrito-pessoal"}\n');
w(path.join(P, 'projects', '-proj-x', 'memory', 'MEMORY.md'), '- [A2](a.md) — pessoal\n- [B](b.md) — nova\n');
w(path.join(P, 'projects', '-proj-x', 'memory', 'a.md'), 'pessoal a\n');
w(path.join(P, 'projects', '-proj-x', 'memory', 'b.md'), 'pessoal b\n');
w(path.join(P, 'file-history', 'h', '1.txt'), 'falso-historico\n');
w(path.join(P, 'cache', 'x.bin'), 'falso-cache\n');
w(path.join(P, 'sessions', 's.json'), '{}\n');
w(path.join(P, 'plugins', 'cache', 'p.txt'), 'falso-plugin-cache\n');
// Dados do rainforest.
j(path.join(D, 'contas', 'estado.json'), variante === 'estado-fora'
  ? { automatico: false, pastas: { pessoal: { conta: 'team' } }, contas: {} }
  : { automatico: false, contas: {} });
if (variante === 'reserva-pronta') {
  j(path.join(D, 'contas', 'reserva-pessoal.json'), { claudeAiOauth: { accessToken: 'falso-reserva-pronta', refreshToken: 'falso-refresh-reserva-pronta', expiresAt: VIDA } });
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
# CLI falsa: registra os argumentos em RFM_FAKE_LOG e sai 0. A claude real nunca roda.
cat > "$RAIZ/cli-falsa.cjs" <<'JS'
const fs = require('fs');
fs.appendFileSync(process.env.RFM_FAKE_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
JS
# Schtasks falso: registra os argumentos em RFM_SCHTASKS_LOG e sai 0. O schtasks real nunca roda.
cat > "$RAIZ/schtasks-falso.cjs" <<'JS'
const fs = require('fs');
fs.appendFileSync(process.env.RFM_SCHTASKS_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
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

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
