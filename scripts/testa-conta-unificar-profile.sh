#!/bin/bash
# rainforest-gate: dados-de-exemplo — tokens e identificadores FALSOS; nenhum valor real.
# Bateria do perfil do PowerShell (tarefa 3 de 2026-10-12-pasta-unica): conta.cjs unificar --profile.
# Tudo falso e gerado em mktemp -d: RFM_TEST=1, homes de exemplo, CLI falsa (RFM_CONTA_CLAUDE_BIN),
# schtasks falso (RFM_CONTA_SCHTASKS), perfil de exemplo no formato do perfil real, e um claude.cmd
# falso à frente no PATH para os casos de PowerShell. Nunca toca o $PROFILE real, ~/.claude*,
# ~/.rainforest, a API real nem o schtasks real. O PowerShell dos casos (f) e (g) roda com USERPROFILE
# apontando para uma pasta falsa: o Update-ClaudePlugins lê o registro falso, nunca o real.
set -euo pipefail
cd "$(dirname "$0")/.."
unset RFM_CONTA_PROCESSOS

win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
RAIZ="$(win "$(mktemp -d)")"
trap 'rm -rf "$RAIZ"' EXIT

OK=0
FALHOU=0
PULADO=0
afirma() {
  local nome="$1"; shift
  if "$@"; then
    OK=$((OK + 1)); echo "ok   $nome"
  else
    FALHOU=$((FALHOU + 1)); echo "FALHA $nome"
  fi
}
pula() { PULADO=$((PULADO + 1)); echo "skip $1"; }
hash_de() { node "$RAIZ/hash.cjs" "$(win "$1")"; }

# Perfil de exemplo no formato do perfil real (ASCII; mesmas funções e mesmas linhas `& claude `).
cat > "$RAIZ/perfil-original.ps1" <<'PS'
# Contas do Claude Code - perfil de exemplo (falso) no formato do perfil real.
# claude-pessoal  -> conta pessoal  (config em ~\.claude-personal)
# claude-trabalho -> conta de trabalho (config padrao ~\.claude)

function Update-ClaudePlugins {
    $cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$env:USERPROFILE\.claude" }
    $registro = Join-Path $cfg 'plugins\installed_plugins.json'
    if (-not (Test-Path $registro)) { return }

    $desejados = @(
        'rainforest-mind@rainforest-mind',
        'apontamento-horas@tbcagro'
    )

    $alvos = @()
    try {
        $reg = Get-Content -Raw -Encoding UTF8 $registro | ConvertFrom-Json
        foreach ($id in $desejados) {
            $inst = $reg.plugins.$id
            if ($inst | Where-Object { $_.scope -eq 'user' }) { $alvos += $id }
        }
    } catch { return }
    if (-not $alvos) { return }

    foreach ($mkt in ($alvos | ForEach-Object { ($_ -split '@')[1] } | Select-Object -Unique)) {
        & claude plugin marketplace update $mkt
    }
    foreach ($p in $alvos) { & claude plugin update $p --scope user }
}

function claude-pessoal {
    $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-personal"
    Update-ClaudePlugins
    & claude --dangerously-skip-permissions @args
}
function claude-trabalho {
    Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    Update-ClaudePlugins
    & claude --dangerously-skip-permissions @args
}
PS

# Utilitários falsos: a CLI, o schtasks e o hash. Nenhum deles é o real.
cat > "$RAIZ/cli-falsa.cjs" <<'JS'
const fs = require('fs');
fs.appendFileSync(process.env.RFM_FAKE_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
JS
cat > "$RAIZ/schtasks-falso.cjs" <<'JS'
const fs = require('fs');
fs.appendFileSync(process.env.RFM_SCHTASKS_LOG, JSON.stringify(process.argv.slice(2)) + '\n');
JS
cat > "$RAIZ/hash.cjs" <<'JS'
const fs = require('fs');
const crypto = require('crypto');
console.log(crypto.createHash('sha256').update(fs.readFileSync(process.argv[2])).digest('hex'));
JS

# Home de exemplo: pasta de trabalho, pasta pessoal (com um plugin só nela), dados do rainforest.
semear_home() { # $1 = caso
  local c="$RAIZ/caso-$1"
  mkdir -p "$c/trabalho/.claude" "$c/pessoal/.claude-personal" "$c/dados/contas"
  printf '{}\n' > "$c/trabalho/.claude/settings.json"
  printf '{}\n' > "$c/trabalho/.claude.json"
  # Clone instalado (destino do reagendamento): sem ele, unificar --aplicar recusa (clone_ausente).
  mkdir -p "$c/trabalho/.claude/plugins/marketplaces/rainforest-mind/scripts"
  printf '// clone falso\n' > "$c/trabalho/.claude/plugins/marketplaces/rainforest-mind/scripts/conta.cjs"
  printf '{"enabledPlugins":{"security-guidance@claude-plugins-official":true}}\n' > "$c/pessoal/.claude-personal/settings.json"
  # Pessoal com login: sem oauthAccount o unificar recusa (rodada 6, achado 1).
  printf '{"oauthAccount":{"emailAddress":"pessoal@exemplo.invalid","accountUuid":"00000000-0000-0000-0000-000000000001"}}\n' > "$c/pessoal/.claude-personal/.claude.json"
  printf '{"automatico":false,"contas":{}}\n' > "$c/dados/contas/estado.json"
  printf '%s' "$c"
}

unif() { # $1 = caso; $2... = argumentos de conta.cjs unificar
  local c="$1"; shift
  RFM_TEST=1 \
  RFM_CONTA_PASTA_TRABALHO="$(win "$c/trabalho/.claude")" \
  RFM_CONTA_PASTA_PESSOAL="$(win "$c/pessoal/.claude-personal")" \
  RFM_CONTA_CLAUDE_JSON="$(win "$c/trabalho/.claude.json")" \
  RFM_CONTA_DADOS="$(win "$c/dados")" \
  RFM_CONTA_PROCESSOS="" \
  RFM_CONTA_SCHTASKS="$(win "$RAIZ/schtasks-falso.cjs")" \
  RFM_SCHTASKS_LOG="$(win "$c/schtasks-args.txt")" \
  RFM_CONTA_CLAUDE_BIN="$(win "$RAIZ/cli-falsa.cjs")" \
  RFM_FAKE_LOG="$(win "$c/cli-args.txt")" \
  node scripts/conta.cjs unificar "$@"
}

# Predicados dos casos (funções, para afirma receber um único comando).
bloco_claude() { awk '/^function claude \{/{f=1} f{print} f && /^\}/{exit}' "$1"; }
bloco_plugins() { awk '/^function Update-ClaudePlugins/{f=1} f{print} f && /^\}/{exit}' "$1"; }

caso_a_ok() {
  local p="$C_A/perfil.ps1" b
  b="$(bloco_claude "$p")"
  ! grep -qF 'function claude-pessoal' "$p" &&
  ! grep -qF 'function claude-trabalho' "$p" &&
  grep -qF 'function claude {' "$p" &&
  printf '%s\n' "$b" | grep -qF 'Remove-Item Env:CLAUDE_CONFIG_DIR' &&
  printf '%s\n' "$b" | grep -qF -- '-CommandType Application' &&
  printf '%s\n' "$b" | grep -qF 'Update-ClaudePlugins'
}

caso_b_ok() {
  local bo bn dif fora n_lt n_gt
  bo="$(bloco_plugins "$RAIZ/perfil-original.ps1")"
  bn="$(bloco_plugins "$C_A/perfil.ps1")"
  [ -n "$bn" ] || return 1
  dif="$(diff <(printf '%s\n' "$bo") <(printf '%s\n' "$bn") | grep '^[<>]' || true)"
  [ -n "$dif" ] || return 1
  fora="$(printf '%s\n' "$dif" | grep '^<' | grep -v -F '& claude ' || true)"
  [ -z "$fora" ] || return 1
  fora="$(printf '%s\n' "$dif" | grep '^>' | grep -v -F -- '-CommandType Application' || true)"
  [ -z "$fora" ] || return 1
  n_lt="$(printf '%s\n' "$dif" | grep -c '^<' || true)"
  n_gt="$(printf '%s\n' "$dif" | grep -c '^>' || true)"
  [ "$n_lt" -gt 0 ] && [ "$n_lt" = "$n_gt" ]
}

caso_d_ok() {
  [ "$(hash_de "$C_D/perfil.ps1")" = "$H_D" ] &&
  grep -q '^- .*& claude plugin marketplace update' "$RAIZ/d.txt" &&
  grep -q '^+ .*-CommandType Application' "$RAIZ/d.txt"
}

caso_e_ok() {
  [ "$RC_E" -eq 2 ] &&
  [ "$(hash_de "$C_E/perfil.ps1")" = "$H_E" ] &&
  grep -q 'não tem as funções' "$RAIZ/e.txt" &&
  grep -q 'nada foi alterado' "$RAIZ/e.txt" &&
  [ -d "$C_E/pessoal/.claude-personal" ]
}

# (a) migração com perfil: o perfil real é reescrito e o original vai para o backup.
C_A="$(semear_home a)"
cp "$RAIZ/perfil-original.ps1" "$C_A/perfil.ps1"
RC_A=0
unif "$C_A" --profile "$(win "$C_A/perfil.ps1")" --aplicar > "$RAIZ/a.txt" 2>&1 || RC_A=$?
afirma "profile real reescrito: claude unico remove CLAUDE_CONFIG_DIR e chama o binario" caso_a_ok
afirma "(a) --profile --aplicar sai 0" [ "$RC_A" -eq 0 ]
afirma "(a) pasta pessoal migrada: .claude-personal.aposentada existe" test -d "$C_A/pessoal/.claude-personal.aposentada"

# (b) Update-ClaudePlugins muda só nas linhas `& claude `; o resto do bloco fica igual.
afirma "(b) Update-ClaudePlugins mudou só nas linhas & claude (demais linhas iguais)" caso_b_ok

# (c) o backup é byte a byte o original.
afirma "(c) backup <perfil>.bak-pasta-unica igual ao original (hash)" \
  [ "$(hash_de "$C_A/perfil.ps1.bak-pasta-unica")" = "$(hash_de "$RAIZ/perfil-original.ps1")" ]

# (d) sem --aplicar: nenhum byte do perfil muda e o diff é impresso.
C_D="$(semear_home d)"
cp "$RAIZ/perfil-original.ps1" "$C_D/perfil.ps1"
H_D="$(hash_de "$C_D/perfil.ps1")"
RC_D=0
unif "$C_D" --profile "$(win "$C_D/perfil.ps1")" > "$RAIZ/d.txt" 2>&1 || RC_D=$?
afirma "(d) sem --aplicar nenhum byte do perfil muda e o diff é impresso" caso_d_ok
afirma "(d) sem --aplicar sai 0 e não migra a pasta pessoal" bash -c "[ '$RC_D' -eq 0 ] && [ -d '$C_D/pessoal/.claude-personal' ]"

# (e) perfil sem as duas funções: nada muda e a saída diz isso.
C_E="$(semear_home e)"
awk '/^function claude-pessoal/{exit} {print}' "$RAIZ/perfil-original.ps1" > "$C_E/perfil.ps1"
H_E="$(hash_de "$C_E/perfil.ps1")"
RC_E=0
unif "$C_E" --profile "$(win "$C_E/perfil.ps1")" --aplicar > "$RAIZ/e.txt" 2>&1 || RC_E=$?
afirma "(e) profile sem as duas funções: nada muda e a saída diz isso" caso_e_ok

# (x1) backup de perfil já existente: recusa antes de qualquer escrita (não sobrescreve o backup).
C_X="$(semear_home x1)"
cp "$RAIZ/perfil-original.ps1" "$C_X/perfil.ps1"
printf 'backup antigo\n' > "$C_X/perfil.ps1.bak-pasta-unica"
H_X="$(hash_de "$C_X/perfil.ps1")"
RC_X=0
unif "$C_X" --profile "$(win "$C_X/perfil.ps1")" --aplicar > "$RAIZ/x1.txt" 2>&1 || RC_X=$?
afirma "(extra) backup de perfil já existente sai 2, nada muda e o backup antigo fica" bash -c "[ '$RC_X' -eq 2 ] && [ '$(hash_de "$C_X/perfil.ps1")' = '$H_X' ] && [ -d '$C_X/pessoal/.claude-personal' ] && grep -q 'backup antigo' '$C_X/perfil.ps1.bak-pasta-unica'"

# (x2) --profile sem caminho: exit 2.
C_Y="$(semear_home x2)"
RC_Y=0
unif "$C_Y" --profile > "$RAIZ/x2.txt" 2>&1 || RC_Y=$?
afirma "(extra) --profile sem caminho sai 2" [ "$RC_Y" -eq 2 ]

# (x3) --ajuda lista --profile <arquivo> em linha própria.
C_Z="$(semear_home x3)"
unif "$C_Z" --ajuda > "$RAIZ/x3.txt" 2>&1 || true
afirma "(extra) unificar --ajuda lista --profile <arquivo> em linha própria" grep -qx -- '--profile <arquivo>' "$RAIZ/x3.txt"

# (f) e (g): PowerShell de verdade, com o perfil reescrito de (a). Pulam só se powershell não existir.
FIX="$C_A/perfil.ps1"
if command -v powershell >/dev/null 2>&1; then
  saida_f="$(timeout 30 powershell -NoProfile -Command ". '$(win "$FIX")'; (Get-Command claude -CommandType Function).Name" 2>&1 | tr -d '\r' || true)"
  afirma "(f) PowerShell: claude é função depois do dot-source do perfil reescrito" [ "$saida_f" = "claude" ]

  # Claude falso (claude.cmd) à frente no PATH; registro falso com um plugin do usuário, para o
  # Update-ClaudePlugins de fato atualizar antes de chamar a aplicação.
  # Dentro de RAIZ (o trap EXIT apaga): um segundo mktemp -d exigiria o idioma SANDBOXES.
  FAKE_POSIX="$(cygpath -u "$RAIZ")/fake-bin"
  mkdir -p "$FAKE_POSIX"
  FAKE="$(win "$FAKE_POSIX")"
  NODE_WIN="$(win "$(command -v node)")"
  cat > "$FAKE_POSIX/claude.cmd" <<CMD
@echo off
"$NODE_WIN" "$RAIZ/cli-falsa.cjs" %*
CMD
  C_G="$(semear_home g)"
  HOME_G="$C_G/home-falsa"
  mkdir -p "$HOME_G/.claude/plugins"
  printf '{"plugins":{"rainforest-mind@rainforest-mind":[{"scope":"user"}]}}\n' > "$HOME_G/.claude/plugins/installed_plugins.json"
  LOG_G="$C_G/cli-claude.txt"
  RC_G=0
  INI_G=$SECONDS
  USERPROFILE="$(win "$HOME_G")" PATH="$FAKE_POSIX:$PATH" RFM_FAKE_LOG="$(win "$LOG_G")" \
    timeout 30 powershell -NoProfile -Command ". '$(win "$FIX")'; claude --version" > "$C_G/saida-g.txt" 2>&1 || RC_G=$?
  DUR_G=$((SECONDS - INI_G))
  # Sem log, a aplicação falsa nunca foi chamada: o caso falha, não passa com contagem zero.
  LOG_EXISTE_G=0
  [ -f "$LOG_G" ] && LOG_EXISTE_G=1
  LINHAS_G=0
  VERSOES_G=0
  if [ "$LOG_EXISTE_G" -eq 1 ]; then
    LINHAS_G="$(wc -l < "$LOG_G")"
    VERSOES_G="$(grep -c -F '"--version"' "$LOG_G" || true)"
  fi
  afirma "(g) claude --version termina em até 30 s, com exit 0 (duração ${DUR_G} s)" bash -c "[ '$RC_G' -eq 0 ] && [ '$DUR_G' -le 30 ]"
  afirma "(g) a aplicação falsa recebeu --version exatamente uma vez" bash -c "[ '$LOG_EXISTE_G' -eq 1 ] && [ '$VERSOES_G' = '1' ]"
  afirma "(g) as atualizações chamaram a aplicação antes (marketplace antes de plugin)" bash -c "[ -f '$LOG_G' ] && grep -q -F '\"marketplace\",\"update\"' '$LOG_G' && grep -q -F '\"plugin\",\"update\"' '$LOG_G'"
  afirma "(g) nenhuma chamada repetiu indefinidamente (até 10 chamadas no log)" bash -c "[ '$LOG_EXISTE_G' -eq 1 ] && [ '$LINHAS_G' -le 10 ]"
  rm -rf "$FAKE_POSIX"
else
  pula "(f) PowerShell: claude é função depois do dot-source (powershell ausente no PATH)"
  pula "(g) PowerShell: claude --version chama a aplicação uma vez (powershell ausente no PATH)"
fi

# ---------------------------------------------------------------------------------------------
# Revisão 3: achado 3 (flags), achado 5 (retomada com --profile) e lacuna (a) (codificação do perfil).
mesmo_hash() { [ "$(hash_de "$1")" = "$2" ]; }
# Bloco do claude novo, e a linha que o chama (a aplicação, não a função).
linha_app_claude() { bloco_claude "$1" | grep -F 'CommandType Application'; }

# Codificação: gera o perfil em UTF-8 com BOM, UTF-16 LE com BOM ou CP-1252 sem BOM, com "ação" no comentário.
cat > "$RAIZ/codif.cjs" <<'JS'
const fs = require('fs');
const [, , origem, cod, destino] = process.argv;
const txt = fs.readFileSync(origem, 'utf8') + '# Configuração de ação (perfil de exemplo)\n';
let buf;
if (cod === 'utf8bom') buf = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(txt, 'utf8')]);
else if (cod === 'utf16') buf = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(txt, 'utf16le')]);
else buf = Buffer.from(txt, 'latin1');
fs.writeFileSync(destino, buf);
JS
# Lê o perfil com a codificação esperada e confere o BOM (sai 3 se não bater): a leitura é independente do fonte.
cat > "$RAIZ/ler-perfil.cjs" <<'JS'
const fs = require('fs');
const [, , arq, cod] = process.argv;
const b = fs.readFileSync(arq);
const bomUtf8 = b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf;
const bomUtf16 = b[0] === 0xff && b[1] === 0xfe;
let texto;
if (cod === 'utf8bom') { if (!bomUtf8) process.exit(3); texto = new TextDecoder('utf-8').decode(b.subarray(3)); }
else if (cod === 'utf16') { if (!bomUtf16) process.exit(3); texto = b.subarray(2).toString('utf16le'); }
else { if (bomUtf8 || bomUtf16) process.exit(3); texto = new TextDecoder('windows-1252').decode(b); }
process.stdout.write(texto);
JS
perfil_cod_ok() { node "$RAIZ/ler-perfil.cjs" "$1/perfil.ps1" "$2" 2>/dev/null | grep -qF 'Configuração de ação'; }
backup_igual() { [ "$(hash_de "$1/perfil.ps1.bak-pasta-unica")" = "$2" ]; }

for cod in utf8bom utf16 cp1252; do
  C_C="$(semear_home cod-$cod)"
  node "$RAIZ/codif.cjs" "$RAIZ/perfil-original.ps1" "$cod" "$C_C/perfil.ps1"
  H_C="$(hash_de "$C_C/perfil.ps1")"
  RC_C=0
  unif "$C_C" --profile "$(win "$C_C/perfil.ps1")" --aplicar > "$RAIZ/cod-$cod.txt" 2>&1 || RC_C=$?
  afirma "(lacuna a) perfil $cod: --aplicar sai 0" test "$RC_C" -eq 0
  afirma "(lacuna a) perfil $cod: o perfil novo mantém a codificação e o acento de ação" perfil_cod_ok "$C_C" "$cod"
  afirma "(lacuna a) perfil $cod: o backup é o original, byte a byte" backup_igual "$C_C" "$H_C"
done

# Achado 3: a flag do claude-trabalho é copiada para o claude novo. Aqui, --model opus no lugar do bypass.
C_F="$(semear_home x4)"
awk '/^function claude-trabalho/{t=1} t && /& claude --dangerously-skip-permissions/{sub(/--dangerously-skip-permissions/,"--model opus"); t=0} {print}' "$RAIZ/perfil-original.ps1" > "$C_F/perfil.ps1"
unif "$C_F" --profile "$(win "$C_F/perfil.ps1")" --aplicar > "$RAIZ/x4.txt" 2>&1 || true
caso_x4_ok() { linha_app_claude "$C_F/perfil.ps1" | grep -qF -- '--model opus @args' && ! linha_app_claude "$C_F/perfil.ps1" | grep -qF -- '--dangerously-skip-permissions'; }
afirma "(achado 3) claude novo traz --model opus do claude-trabalho e não o bypass fixo" caso_x4_ok

# Achado 3: claude-trabalho sem flag nenhuma gera claude sem flag.
C_G3="$(semear_home x5)"
awk '/^function claude-trabalho/{t=1} t && /& claude --dangerously-skip-permissions/{sub(/ --dangerously-skip-permissions/,""); t=0} {print}' "$RAIZ/perfil-original.ps1" > "$C_G3/perfil.ps1"
unif "$C_G3" --profile "$(win "$C_G3/perfil.ps1")" --aplicar > "$RAIZ/x5.txt" 2>&1 || true
caso_x5_ok() { linha_app_claude "$C_G3/perfil.ps1" | grep -qF '@args' && ! linha_app_claude "$C_G3/perfil.ps1" | grep -qF -- '--'; }
afirma "(achado 3) claude-trabalho sem flag: o claude novo não ganha flag nenhuma" caso_x5_ok

# Achado 5: a falha com --profile repete o comando exato, com --profile <arquivo>.
C_R="$(semear_home x6)"
cp "$RAIZ/perfil-original.ps1" "$C_R/perfil.ps1"
export RFM_CONTA_FALHA=renomear
RC_R=0
unif "$C_R" --aplicar --profile "$(win "$C_R/perfil.ps1")" > "$RAIZ/x6.txt" 2>&1 || RC_R=$?
unset RFM_CONTA_FALHA
afirma "(achado 5) falha com --profile sai diferente de 0" test "$RC_R" -ne 0
afirma "(achado 5) a retomada repete o comando com --profile <arquivo>" grep -qF "unificar --aplicar --profile $(win "$C_R/perfil.ps1")" "$RAIZ/x6.txt"

# Rodada 4, achado 3: a gravação do perfil falha (falha injetada só com RFM_TEST=1) depois da migração. O .bak que
# esta rodada criou não pode ficar, e a retomada indicada (o mesmo comando) tem de funcionar.
C_B3="$(semear_home ach3p)"
cp "$RAIZ/perfil-original.ps1" "$C_B3/perfil.ps1"
H_B3="$(hash_de "$C_B3/perfil.ps1")"
RC_B31=0
export RFM_CONTA_FALHA=perfil
unif "$C_B3" --aplicar --profile "$(win "$C_B3/perfil.ps1")" > "$RAIZ/ach3p1.txt" 2>&1 || RC_B31=$?
unset RFM_CONTA_FALHA
# Estado logo depois da 1ª rodada (antes da retomada, que mudaria os dois).
BAK_B31=1
[ -e "$C_B3/perfil.ps1.bak-pasta-unica" ] || BAK_B31=0
H_B31="$(hash_de "$C_B3/perfil.ps1")"
RC_B32=0
unif "$C_B3" --aplicar --profile "$(win "$C_B3/perfil.ps1")" > "$RAIZ/ach3p2.txt" 2>&1 || RC_B32=$?
afirma "(rodada 4, achado 3) gravação do perfil falha: sai diferente de 0" test "$RC_B31" -ne 0
afirma "(rodada 4, achado 3) gravação do perfil falha: o .bak que a rodada criou não fica" test "$BAK_B31" -eq 0
afirma "(rodada 4, achado 3) gravação do perfil falha: o perfil fica como estava (hash)" test "$H_B31" = "$H_B3"
afirma "(rodada 4, achado 3) a retomada indicada (o mesmo comando) sai 0" test "$RC_B32" -eq 0
afirma "(rodada 4, achado 3) a retomada troca o perfil e deixa o .bak da retomada" bash -c "[ -f '$C_B3/perfil.ps1.bak-pasta-unica' ] && ! grep -qF 'function claude-pessoal' '$C_B3/perfil.ps1'"

echo "ok: $OK   falhou: $FALHOU   pulado: $PULADO"
if [ "$FALHOU" -ne 0 ]; then exit 1; fi
