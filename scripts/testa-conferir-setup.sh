#!/bin/bash
# Bateria do scripts/conferir-setup.cjs — D7 e D12 do design
# docs/rainforest/design/2026-10-17-setup-entrevista-guiada.md.
# Uso: bash scripts/testa-conferir-setup.sh
#
# Caixa de areia com mktemp -d: nada aqui toca o SKILL.md real nem a pasta de dados.
# Os catálogos e SKILL.md de teste saem do require do hooks/lib/config.cjs REAL, pelo
# gera.cjs da própria caixa. Cada caso só roda o conferidor e olha exit e saída — nenhum
# caso lê ou afirma sobre o texto do fonte do conferidor.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
CAIXA_WIN="$(cygpath -m "$CAIXA" 2>/dev/null || printf '%s' "$CAIXA")"
CONFIG_WIN="$(cygpath -m "$SRC/hooks/lib/config.cjs" 2>/dev/null || printf '%s' "$SRC/hooks/lib/config.cjs")"

cat > "$CAIXA/gera.cjs" <<'JS'
// gera.cjs <tipo> <modo> <saida> <config.cjs real>
const fs = require('fs');
const [tipo, modo, saida, configReal] = process.argv.slice(2);
const c = require(configReal);
const CH = JSON.parse(JSON.stringify(c.CHAVES));
const G = c.GRUPOS_ENTREVISTA;
if (tipo === 'json') {
  if (modo === 'real') {
    // catalogo real, sem alteração
  } else if (modo === 'sem-campo-ponte-codex') {
    delete CH['ponte-codex'].entrevista;
  } else if (modo === 'grupo-invalido') {
    CH.idioma.entrevista = { grupo: 'grupo-inexistente', detectar: {} };
  } else if (modo === 'integracao-inexistente') {
    CH['integracao-sabia'].entrevista = { grupo: 'ferramentas', detectar: { integracao: 'inexistente' } };
  } else {
    throw new Error('modo json desconhecido: ' + modo);
  }
  fs.writeFileSync(saida, JSON.stringify({ CHAVES: CH, GRUPOS_ENTREVISTA: G }));
} else if (tipo === 'skill') {
  let chaves = Object.keys(c.CHAVES);
  if (modo === 'sem-idioma') chaves = chaves.filter((k) => k !== 'idioma');
  if (modo === 'sobra') chaves.push('chave-fantasma');
  const grupos = modo === 'ordem-trocada' ? [G[1], G[0], ...G.slice(2)] : G;
  const linhas = ['# Skill de teste', '', '## Tabela', '', '| Chave | Faz |', '|---|---|'];
  for (const k of chaves) linhas.push('| `' + k + '` | teste |');
  linhas.push('', '## Ordem da entrevista', '');
  for (const g of grupos) linhas.push('### ' + g.charAt(0).toUpperCase() + g.slice(1) + ' — teste', 'texto', '');
  fs.writeFileSync(saida, linhas.join('\n'));
} else {
  throw new Error('tipo desconhecido: ' + tipo);
}
JS

ok=0; falhou=0
gerar() { # tipo, modo, saida
  node "$CAIXA/gera.cjs" "$1" "$2" "$CAIXA_WIN/$3" "$CONFIG_WIN"
}
caso() { # nome, exit esperado, agulha ("" = nao exige), argumentos do conferidor...
  local nome="$1" esp="$2" txt="$3"; shift 3
  local saida; saida=$(node "$SRC/scripts/conferir-setup.cjs" "$@" 2>&1); local got=$?
  if [ "$got" != "$esp" ]; then
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; return
  fi
  if [ -n "$txt" ] && ! echo "$saida" | grep -q -- "$txt"; then
    falhou=$((falhou+1)); echo "  FALHA $nome: saida nao traz '$txt'"; echo "$saida" | sed 's/^/         /' | head -8; return
  fi
  ok=$((ok+1)); echo "  ok   $nome (exit $got)"
}

echo "== 1. catalogo: (a) campo entrevista, (b) grupo, (c) detectar e integracao =="
caso "catalogo real passa com --so-catalogo" 0 "ok:" --so-catalogo
gerar json sem-campo-ponte-codex "sem-campo.json"
caso "catalogo com ponte-codex sem campo entrevista e recusado" 1 "ponte-codex" --so-catalogo --config "$CAIXA_WIN/sem-campo.json"
gerar json grupo-invalido "grupo-invalido.json"
caso "grupo fora de GRUPOS_ENTREVISTA e recusado" 1 "grupo-inexistente" --so-catalogo --config "$CAIXA_WIN/grupo-invalido.json"
gerar json integracao-inexistente "integracao-inexistente.json"
caso "integracao inexistente e recusada" 1 "inexistente" --so-catalogo --config "$CAIXA_WIN/integracao-inexistente.json"

echo "== 2. SKILL.md: tabela (d) e ordem da entrevista (e) =="
gerar skill sem-idioma "sem-idioma.md"
caso "tabela do skill sem uma chave e recusada, nomeando-a" 1 "idioma" --skill "$CAIXA_WIN/sem-idioma.md"
gerar skill sobra "sobra.md"
caso "tabela com chave sobrando e recusada" 1 "chave-fantasma" --skill "$CAIXA_WIN/sobra.md"
gerar skill ordem-trocada "ordem-trocada.md"
caso "ordem da entrevista trocada e recusada" 1 "difere" --skill "$CAIXA_WIN/ordem-trocada.md"
gerar skill coerente "coerente.md"
caso "skill coerente com o catalogo passa" 0 "ok:" --skill "$CAIXA_WIN/coerente.md"
# O SKILL.md e o catalogo REAIS, sem caixa: e este caso que faz o CI reprovar quando
# alguem acrescenta chave em hooks/lib/config.cjs e esquece a linha da tabela da skill.
caso "SKILL.md real coerente com o catalogo real" 0 "ok:"

echo "== 3. uso =="
caso "arquivo de --config inexistente sai 2" 2 "" --so-catalogo --config "$CAIXA_WIN/nao-existe.json"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
