#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria do vigia com pasta sem credencial (conta-reserva-avisa, D1): scripts/conta.cjs.
# Casos: (d1-1) pasta pessoal sem credencial não derruba a rodada e a decisão da trabalho sai;
# (d1-2) duas rodadas gravam um só pasta_sem_credencial e nenhum vigia_falhou; (d1-3) a credencial
# volta e a rodada seguinte grava pasta_com_credencial; (d1-4) a credencial some de novo e status
# mostra sem credencial; (d1-5) pasta renomeada (fora de pastasAtivas) grava pasta_com_credencial
# com o motivo 'pasta saiu de uso'.
# Casos D2 (conta-reserva-avisa, tarefa 3): (d2-1) estado.json inválido sai 1, grava um vigia_falhou
# e não repete com o mesmo erro; (d2-2) .credentials.json inválido grava outro vigia_falhou sem vazar
# o texto do arquivo; (d2-3) rodada que decidiu cria vigia-ok e o mesmo erro depois grava de novo;
# (d2-4) troca automática desligada sai 0 sem criar vigia-ok; (d2-5) essa rodada não toca vigia-ok.
# Casos D4 (conta-reserva-avisa, tarefa 6): (d4-1) a primeira rodada com uso ilegível de pasta fora
# de casa grava semUsoDesde e nenhum uso_ilegivel; (d4-2) 29 min sem uso não grava; (d4-3) 31 min
# grava um, e a rodada seguinte no mesmo período não grava outro; (d4-4) dado de volta zera
# semUsoDesde; (d4-5) novo período grava o segundo; (d4-6) pasta em casa não grava nada.
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
# Conta eventos do log: contar.cjs <eventos> <tipo> [pasta] [motivo]; vazio conta qualquer um.
cat > "$RAIZ/contar.cjs" <<'JS'
const fs = require('fs');
const [, , arq, tipo, pasta, motivo] = process.argv;
let bruto = '';
try { bruto = fs.readFileSync(arq, 'utf8'); } catch { bruto = ''; }
let n = 0;
for (const linha of bruto.split('\n')) {
  if (!linha.trim()) continue;
  let ev;
  try { ev = JSON.parse(linha); } catch { continue; }
  if (ev.tipo === tipo && (!pasta || ev.pasta === pasta) && (!motivo || ev.motivo === motivo)) n++;
}
console.log(n);
JS
cat > "$RAIZ/derivar.cjs" <<'JS'
const fs = require('fs');
const [, , entrada, saida, ajuste] = process.argv;
const m = JSON.parse(fs.readFileSync(entrada, 'utf8'));
const a = JSON.parse(ajuste);
for (const [t, extra] of Object.entries(a.tokens || {})) Object.assign(m.tokens[t], extra);
fs.writeFileSync(saida, JSON.stringify(m));
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
JS

node "$RAIZ/semear.cjs" mapa "$RAIZ/mapa.json"
# Pessoal a 100% na semana: o uso da conta pessoal é lido pelos dois tokens dela (o da pasta
# trabalho depois da troca é o falso-pessoal-reserva; o da pessoal some na fixture).
LIMITE_D1='{"tokens":{"falso-pessoal-pasta":{"uso7":100,"reset7":"2026-11-20T11:00:00.000Z"},"falso-pessoal-reserva":{"uso7":100,"reset7":"2026-11-20T11:00:00.000Z"}}}'
node "$RAIZ/derivar.cjs" "$RAIZ/mapa.json" "$RAIZ/mapa-d1.json" "$LIMITE_D1"

# Servidor de teste: porta livre, morto no trap.
API=""
iniciar_servidor() { # $1 = mapa token -> conta; $2 = arquivo onde sai a porta
  RFM_CONTA_SERVIDOR_MAPA="$(win "$1")" \
  RFM_CONTA_SERVIDOR_CONTROLE="$(win "$RAIZ/segurar")" \
    node scripts/fixtures/conta/servidor.cjs > "$2" 2> "$RAIZ/servidor-erro.txt" &
  PIDS+=("$!")
  for _ in $(seq 1 100); do [ -s "$2" ] && break; sleep 0.1; done
  API="http://127.0.0.1:$(head -n1 "$2")"
}
iniciar_servidor "$RAIZ/mapa-d1.json" "$RAIZ/porta-d1.txt"

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

# Caso: trabalho na conta pessoal, manual e sem travouPor; a pessoal SEM .credentials.json (o
# caso que hoje derruba a rodada). Deixa o diretório em $CASO e a credencial guardada em
# $RAIZ/cred-pessoal-<nome>.json, para os casos que a devolvem.
novo_caso_d1() {
  CASO="$RAIZ/caso-$1"
  mkdir -p "$CASO"
  node "$RAIZ/semear.cjs" caso "$CASO" sim
  node "$RAIZ/ajustar.cjs" trocado "$CASO"
  node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$CASO/dados/contas/estado.json"
  cp "$CASO/pessoal/.claude-personal/.credentials.json" "$RAIZ/cred-pessoal-$1.json"
  rm -f "$CASO/pessoal/.claude-personal/.credentials.json"
}
# Uma rodada de vigiar no caso: código de saída em RC, saída em $RAIZ/<caso>-<rodada>.txt.
rodar() { # $1 = nome do caso; $2 = rótulo da rodada
  RC=0
  cli "$CASO" vigiar > "$RAIZ/$1-$2.txt" 2>&1 || RC=$?
}
contar() { node "$RAIZ/contar.cjs" "$CASO/dados/contas/eventos.jsonl" "$@"; }

# (d1-1) pessoal sem credencial: a rodada sai 0 e a decisão da pasta que tem credencial sai.
novo_caso_d1 d1-1
rodar d1-1 r1
SAIDA_D1_1="$(cat "$RAIZ/d1-1-r1.txt")"
afirma "(d1-1) vigiar sai 0 com a pessoal sem credencial" test "$RC" -eq 0
afirma "(d1-1) a decisão da trabalho sai: avisar trabalho: seven_day de pessoal em 100%" contem "$SAIDA_D1_1" "avisar trabalho: seven_day de pessoal em 100%"

# (d1-2) duas rodadas: um só pasta_sem_credencial da pessoal, nenhum vigia_falhou, e a segunda sai 0.
novo_caso_d1 d1-2
rodar d1-2 r1
rodar d1-2 r2
afirma "(d1-2) um só pasta_sem_credencial da pessoal depois de duas rodadas" test "$(contar pasta_sem_credencial pessoal)" = 1
afirma "(d1-2) nenhum vigia_falhou" test "$(contar vigia_falhou)" = 0
afirma "(d1-2) a segunda rodada sai 0" test "$RC" -eq 0

# (d1-3) a credencial volta: a rodada seguinte grava pasta_com_credencial; a terceira não grava outro.
novo_caso_d1 d1-3
rodar d1-3 r1
cp "$RAIZ/cred-pessoal-d1-3.json" "$CASO/pessoal/.claude-personal/.credentials.json"
rodar d1-3 r2
afirma "(d1-3) a rodada seguinte grava um pasta_com_credencial da pessoal" test "$(contar pasta_com_credencial pessoal)" = 1
rodar d1-3 r3
afirma "(d1-3) a rodada depois dela não grava outro pasta_com_credencial" test "$(contar pasta_com_credencial pessoal)" = 1
afirma "(d1-3) o pasta_sem_credencial continua um só" test "$(contar pasta_sem_credencial pessoal)" = 1

# (d1-4) a credencial some de novo: o segundo pasta_sem_credencial, a rodada sai 0 e status diz sem credencial.
novo_caso_d1 d1-4
rodar d1-4 r1
cp "$RAIZ/cred-pessoal-d1-4.json" "$CASO/pessoal/.claude-personal/.credentials.json"
rodar d1-4 r2
rm -f "$CASO/pessoal/.claude-personal/.credentials.json"
rodar d1-4 r3
ST_D1_4="$(cli "$CASO" status 2>&1 || true)"
afirma "(d1-4) o segundo pasta_sem_credencial da pessoal" test "$(contar pasta_sem_credencial pessoal)" = 2
afirma "(d1-4) a rodada sai 0" test "$RC" -eq 0
afirma "(d1-4) status imprime pasta pessoal: sem credencial" contem "$ST_D1_4" "pasta pessoal: sem credencial"

# (d1-5) pasta renomeada (sai de pastasAtivas) com pasta_sem_credencial em aberto: a rodada grava
# pasta_com_credencial com o motivo 'pasta saiu de uso', e a seguinte não grava outro.
novo_caso_d1 d1-5
rodar d1-5 r1
mv "$CASO/pessoal/.claude-personal" "$CASO/pessoal/.claude-personal.stub-teste"
rodar d1-5 r2
afirma "(d1-5) a rodada com a pasta renomeada sai 0" test "$RC" -eq 0
afirma "(d1-5) grava pasta_com_credencial da pessoal com o motivo 'pasta saiu de uso'" test "$(contar pasta_com_credencial pessoal 'pasta saiu de uso')" = 1
rodar d1-5 r3
afirma "(d1-5) a rodada seguinte não grava outro" test "$(contar pasta_com_credencial pessoal 'pasta saiu de uso')" = 1

# Caso D2 (conta-reserva-avisa): mesmo caso das pastas, com as duas pastas com credencial.
novo_caso_d2() {
  CASO="$RAIZ/caso-$1"
  mkdir -p "$CASO"
  node "$RAIZ/semear.cjs" caso "$CASO" sim
  node "$RAIZ/ajustar.cjs" trocado "$CASO"
  node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$CASO/dados/contas/estado.json"
}
# Arquivo corrompido: texto falso que não pode sair em evento nem em saída.
corromper() { printf '%s' '{ "falso-segredo-xyz' > "$1"; }
mudar_automatico() { node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.automatico=process.argv[2]==='sim';fs.writeFileSync(a,JSON.stringify(e))" "$1" "$2"; }
mtime() { node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$1"; }

# (d2-1) estado.json com JSON inválido: a rodada sai 1 com 'erro: JSON inválido' (como hoje) e grava
# um vigia_falhou; a rodada seguinte, com o mesmo erro, não grava outro.
novo_caso_d2 d2-1
corromper "$CASO/dados/contas/estado.json"
rodar d2-1 r1
afirma "(d2-1) a rodada com estado.json inválido sai 1" test "$RC" -eq 1
afirma "(d2-1) stderr traz 'erro: JSON inválido'" contem "$(cat "$RAIZ/d2-1-r1.txt")" "erro: JSON inválido"
rodar d2-1 r2
afirma "(d2-1) a rodada seguinte, com o mesmo erro, não grava outro vigia_falhou" test "$(contar vigia_falhou '' 'JSON inválido em estado.json')" = 1

# (d2-2) estado válido e .credentials.json da trabalho inválido: um segundo vigia_falhou, e nem o
# evento nem a saída trazem o texto do arquivo corrompido.
novo_caso_d2 d2-2
corromper "$CASO/trabalho/.claude/.credentials.json"
rodar d2-2 r1
afirma "(d2-2) grava vigia_falhou com o motivo 'JSON inválido em .credentials.json'" test "$(contar vigia_falhou '' 'JSON inválido em .credentials.json')" = 1
afirma "(d2-2) nem o evento nem a saída trazem o texto do arquivo corrompido" test "$(cat "$CASO/dados/contas/eventos.jsonl" "$RAIZ/d2-2-r1.txt" | grep -c 'falso-segredo-xyz' || true)" = 0

# (d2-3) rodada com tudo válido sai 0 e cria vigia-ok; o mesmo erro depois dela grava outro evento.
novo_caso_d2 d2-3
cp "$CASO/trabalho/.claude/.credentials.json" "$RAIZ/d2-3-cred-bom.json"
corromper "$CASO/trabalho/.claude/.credentials.json"
rodar d2-3 r1
cp "$RAIZ/d2-3-cred-bom.json" "$CASO/trabalho/.claude/.credentials.json"
rodar d2-3 r2
afirma "(d2-3) a rodada com tudo válido sai 0" test "$RC" -eq 0
afirma "(d2-3) a rodada que decidiu cria vigia-ok" test -f "$CASO/dados/contas/vigia-ok"
corromper "$CASO/trabalho/.claude/.credentials.json"
rodar d2-3 r3
afirma "(d2-3) o mesmo erro depois da rodada concluída grava um segundo vigia_falhou de .credentials.json" test "$(contar vigia_falhou '' 'JSON inválido em .credentials.json')" = 2

# (d2-4) troca automática desligada: a rodada sai 0 com a frase e não cria vigia-ok.
novo_caso_d2 d2-4
mudar_automatico "$CASO/dados/contas/estado.json" nao
rodar d2-4 r1
afirma "(d2-4) a rodada com a troca desligada sai 0" test "$RC" -eq 0
afirma "(d2-4) a saída diz troca automática desligada" contem "$(cat "$RAIZ/d2-4-r1.txt")" "troca automática desligada"
afirma "(d2-4) não cria vigia-ok" test ! -e "$CASO/dados/contas/vigia-ok"

# (d2-5) vigia-ok existe de uma rodada que decidiu; a rodada com a troca desligada não o toca.
novo_caso_d2 d2-5
rodar d2-5 r1
ANTES_D2_5="$(mtime "$CASO/dados/contas/vigia-ok")"
mudar_automatico "$CASO/dados/contas/estado.json" nao
rodar d2-5 r2
afirma "(d2-5) a rodada com a troca desligada não toca o mtime de vigia-ok" test "$(mtime "$CASO/dados/contas/vigia-ok")" = "$ANTES_D2_5"

# Caso D4 (conta-reserva-avisa, tarefa 6): trabalho manual na pessoal com o login da pasta vencido
# (é o login que loginsDaConta põe primeiro para a conta pessoal: trabalho vem antes de pessoal) e
# reserva-pessoal vazia, então o uso da pessoal fica ilegível. A casa (team) não entra aqui.
novo_caso_d4() {
  CASO="$RAIZ/caso-$1"
  mkdir -p "$CASO"
  node "$RAIZ/semear.cjs" caso "$CASO" sim
  node "$RAIZ/ajustar.cjs" trocado "$CASO"
  node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas.trabalho.manual=true;e.pastas.trabalho.travouPor=null;fs.writeFileSync(a,JSON.stringify(e))" "$CASO/dados/contas/estado.json"
  expirar "$CASO/trabalho/.claude/.credentials.json" 1
}
# Pasta em casa (team): o login da pasta e a reserva-team vencidos, então o uso da casa fica ilegível.
novo_caso_d4_casa() {
  CASO="$RAIZ/caso-$1"
  mkdir -p "$CASO"
  node "$RAIZ/semear.cjs" caso "$CASO" sim
  expirar "$CASO/trabalho/.claude/.credentials.json" 1
  expirar "$CASO/dados/contas/reserva-team.json" 1
}
# expirar <arquivo> <epoch-ms>: põe claudeAiOauth.expiresAt do arquivo.
expirar() {
  node -e "const fs=require('fs');const a=process.argv[1];const o=JSON.parse(fs.readFileSync(a,'utf8'));o.claudeAiOauth.expiresAt=Number(process.argv[2]);fs.writeFileSync(a,JSON.stringify(o,null,2)+'\n')" "$1" "$2"
}
# definir_sem_uso <pasta> <minutos>: semUsoDesde = agora - minutos, no estado.json do caso.
definir_sem_uso() {
  node -e "const fs=require('fs');const a=process.argv[1];const e=JSON.parse(fs.readFileSync(a,'utf8'));e.pastas[process.argv[2]].semUsoDesde=Date.now()-Number(process.argv[3])*60000;fs.writeFileSync(a,JSON.stringify(e))" "$CASO/dados/contas/estado.json" "$1" "$2"
}
# recuar_eventos: os uso_ilegivel do log passam para 3 h atrás (um período novo começa depois do
# evento do anterior, como na vida real; a rodada de teste roda em segundos).
recuar_eventos() {
  node -e "const fs=require('fs');const a=process.argv[1];const l=fs.readFileSync(a,'utf8').split('\n').filter(Boolean).map((x)=>{const e=JSON.parse(x);if(e.tipo==='uso_ilegivel')e.em=Date.now()-3*3600000;return JSON.stringify(e)});fs.writeFileSync(a,l.join('\n')+'\n')" "$CASO/dados/contas/eventos.jsonl"
}
estado_pasta() { node "$RAIZ/ler.cjs" "$CASO/dados/contas/estado.json" "pastas.$1.$2"; }
numerico() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Os casos D4 usam o mapa base (uso da pessoal legível quando o login volta), não o de D1 a 100%.
iniciar_servidor "$RAIZ/mapa.json" "$RAIZ/porta-d4.txt"

# (d4-1) primeira rodada: semUsoDesde numérico e nenhum uso_ilegivel.
novo_caso_d4 d4-1
rodar d4-1 r1
afirma "(d4-1) a primeira rodada grava semUsoDesde numérico na trabalho" numerico "$(estado_pasta trabalho semUsoDesde)"
afirma "(d4-1) a primeira rodada não grava uso_ilegivel" test "$(contar uso_ilegivel)" = 0

# (d4-2) 29 min sem uso: nenhum evento.
definir_sem_uso trabalho 29
rodar d4-2 r1
afirma "(d4-2) com 29 min sem uso não grava uso_ilegivel" test "$(contar uso_ilegivel)" = 0

# (d4-3) 31 min sem uso: um evento; a rodada seguinte, no mesmo período, não grava outro.
definir_sem_uso trabalho 31
rodar d4-3 r1
afirma "(d4-3) com 31 min sem uso grava um uso_ilegivel da trabalho" test "$(contar uso_ilegivel trabalho)" = 1
rodar d4-3 r2
afirma "(d4-3) a rodada seguinte, no mesmo período, não grava outro" test "$(contar uso_ilegivel trabalho)" = 1

# (d4-4) o dado de uso volta (o login da pasta volta a valer): semUsoDesde some do estado.
expirar "$CASO/trabalho/.claude/.credentials.json" 4102444800000
rodar d4-4 r1
afirma "(d4-4) com o dado de uso de volta, semUsoDesde some do estado" test "$(estado_pasta trabalho semUsoDesde)" = AUSENTE

# (d4-5) o dado some de novo: o período novo, com 31 min, grava o segundo uso_ilegivel.
expirar "$CASO/trabalho/.claude/.credentials.json" 1
recuar_eventos
definir_sem_uso trabalho 31
rodar d4-5 r1
afirma "(d4-5) um período novo grava o segundo uso_ilegivel" test "$(contar uso_ilegivel trabalho)" = 2

# (d4-6) pasta em casa com uso ilegível: nem semUsoDesde nem evento.
novo_caso_d4_casa d4-6
rodar d4-6 r1
afirma "(d4-6) pasta em casa não grava semUsoDesde" test "$(estado_pasta trabalho semUsoDesde)" = AUSENTE
afirma "(d4-6) pasta em casa não grava uso_ilegivel" test "$(contar uso_ilegivel)" = 0

# (st-1) status da pasta manual diz a condição da volta (D3), e nunca "sem volta automática".
novo_caso_d1 st-1
RC=0
cli "$CASO" status > "$RAIZ/st-1.txt" 2>&1 || RC=$?
LINHA_ST_1="$(grep -F 'pasta trabalho' "$RAIZ/st-1.txt" || true)"
afirma "(st-1) a linha da pasta trabalho diz a condição da volta" contem "$LINHA_ST_1" "troca manual (volta se a conta em uso chegar ao limite e a de casa tiver folga)"
afirma "(st-1) o status não diz sem volta automática" bash -c '! grep -qF "sem volta automática" "$1"' _ "$RAIZ/st-1.txt"

echo "ok: $OK   falhou: $FALHOU"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
