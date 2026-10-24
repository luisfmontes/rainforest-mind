#!/bin/bash
# Bateria da captura sem bloco injetado — scripts/observar.cjs (D3 do lote 1 apoio-ao-dev).
# Uso: bash scripts/testa-observar-injetado.sh
#
# O que esta bateria prova, por efeito em formatarParaLLM (nenhum caso lê o fonte):
#   1. task-notification vira linha Agente e system-reminder some
#   2. system-reminder sem fechamento fica intacto e o texto depois dele não some
#   3. prompt só com bloco injetado não gera linha Prompt:
#   4. command-name/message/args e local-command-stdout/stderr somem
#   5. só a linha exata do marcador [SYSTEM NOTIFICATION - NOT USER INPUT] sai; o parágrafo seguinte fica
#   6. a < b e Map<string> saem iguais
#   7. achado 1: marcador citado no meio de uma linha não remove nada; fala real logo abaixo fica
#   8. achado 2: bloco com a mesma tag aninhada sai inteiro e não vaza o resultado
#   9. achado 4: fala do usuário que começa com "Agente: " sai como Prompt:
#  10. achado 5: 4000 aberturas sem fechamento e um fechamento no fim terminam em menos de 5 s
#      (removerBlocosInjetados), e só a última abertura some
#
# Sai ≠ 0 se qualquer caso falha. Imprime "total=N vermelhas:[...]" no fim.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVAR="$SRC/scripts/observar.cjs"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"
CASOS="$CAIXA/casos.cjs"

cat > "$CASOS" <<'JS'
'use strict';
// Cada caso devolve null (ok) ou o motivo da falha. Saída: uma linha por caso, "ok|nome" ou "FALHA|nome|motivo".
const OBSERVAR = process.argv[2];
const resultados = [];
function caso(nome, fn) {
  try {
    const motivo = fn();
    resultados.push(motivo ? 'FALHA|' + nome + '|' + motivo : 'ok|' + nome);
  } catch (e) {
    resultados.push('FALHA|' + nome + '|excecao: ' + e.message);
  }
}

let formatarParaLLM, removerBlocosInjetados;
try {
  ({ formatarParaLLM, removerBlocosInjetados } = require(OBSERVAR));
} catch (e) {
  console.log('FALHA|carregar observar.cjs|' + e.message);
  process.exit(0);
}

// Evento no formato real do transcrito do Claude Code: type "user", content string.
function saida(conteudo) {
  return formatarParaLLM([{ type: 'user', message: { role: 'user', content: conteudo } }]);
}

caso('task-notification vira linha Agente e system-reminder some', () => {
  const out = saida(
    '<system-reminder>\nLembrete do harness SEGREDO-LEMBRETE\n</system-reminder>\n' +
    '<task-notification>\n<task-id>x1</task-id>\n<summary>Bateria verde no CI</summary>\n' +
    '<result>RESULTADO-LONGO-SEGREDO linha 1\nlinha 2</result>\n</task-notification>\n' +
    'lembre de trocar de conta'
  );
  const erros = [];
  if (!out.split('\n').includes('Agente: Bateria verde no CI')) erros.push('sem linha "Agente: Bateria verde no CI"');
  if (/<task-notification>|<system-reminder>/.test(out)) erros.push('tag de bloco sobrou');
  if (/SEGREDO/.test(out)) erros.push('conteudo de bloco sobrou');
  if (!out.includes('lembre de trocar de conta')) erros.push('fala do usuario sumiu');
  if (out.indexOf('Agente: ') > out.indexOf('Prompt: ')) erros.push('linha Agente veio depois do Prompt');
  const semResumo = saida('<task-notification><result>so resultado</result></task-notification>');
  if (semResumo !== 'Agente: (sem resumo)') erros.push('sem summary: ' + JSON.stringify(semResumo));
  return erros.join('; ') || null;
});

caso('system-reminder sem fechamento fica intacto e o texto depois dele nao some', () => {
  const x = '<system-reminder>\nabre e nunca fecha\n\nfala do usuario depois do bloco aberto';
  const erros = [];
  if (saida(x) !== 'Prompt: ' + x) erros.push('nao ficou intacto: ' + JSON.stringify(saida(x)));
  // Abertura órfã seguida de bloco fechado: o órfão fica, o fechado sai, a fala final fica.
  const y = '<system-reminder>\nabre sem fechar\n<system-reminder>bloco fechado</system-reminder>\nfala final';
  const outY = saida(y);
  if (!outY.includes('abre sem fechar')) erros.push('orfao comeu o texto');
  if (!outY.includes('fala final')) erros.push('fala final sumiu');
  if (outY.includes('bloco fechado')) erros.push('bloco fechado sobrou');
  return erros.join('; ') || null;
});

caso('prompt so com bloco injetado nao gera linha Prompt:', () => {
  const erros = [];
  const a = saida('<system-reminder>\nso bloco injetado\n</system-reminder>\n<command-name>/clear</command-name>');
  if (/^Prompt:/m.test(a)) erros.push('system-reminder+command-name gerou Prompt: ' + JSON.stringify(a));
  const b = saida('<task-notification><summary>so resumo</summary></task-notification>');
  if (/^Prompt:/m.test(b)) erros.push('task-notification gerou Prompt: ' + JSON.stringify(b));
  return erros.join('; ') || null;
});

caso('command-name/message/args e local-command-stdout/stderr somem', () => {
  const blocos = [
    '<command-name>/clear</command-name>',
    '<command-message>clear</command-message>',
    '<command-args>CMDARG-SEGREDO</command-args>',
    '<local-command-stdout>STDOUT-SEGREDO</local-command-stdout>',
    '<local-command-stderr>STDERR-SEGREDO</local-command-stderr>',
  ];
  const erros = [];
  for (const b of blocos) {
    const nome = b.slice(1, b.indexOf('>'));
    const out = saida(b + '\nfala do usuario apos ' + nome);
    if (!out.includes('fala do usuario apos ' + nome)) erros.push(nome + ' comeu a fala');
    if (/SEGREDO|<command-|<local-command-/.test(out)) erros.push(nome + ' sobrou: ' + JSON.stringify(out));
  }
  return erros.join('; ') || null;
});

caso('linha [SYSTEM NOTIFICATION - NOT USER INPUT] sai e o paragrafo seguinte fica', () => {
  const out = saida(
    '[SYSTEM NOTIFICATION - NOT USER INPUT]\nEsta mensagem e do harness, o usuario nao escreveu isto.\n\nfala real do usuario'
  );
  const esperado = 'Prompt: Esta mensagem e do harness, o usuario nao escreveu isto.\n\nfala real do usuario';
  if (out !== esperado) return 'saida ' + JSON.stringify(out);
  return null;
});

caso('achado 1: so a linha exata do marcador sai; citacao no meio da linha nao remove nada', () => {
  const erros = [];
  const a = saida('[SYSTEM NOTIFICATION - NOT USER INPUT]\naviso\nFALA-REAL-SEM-VAZIA');
  if (a !== 'Prompt: aviso\nFALA-REAL-SEM-VAZIA') erros.push('sonda 1 saiu ' + JSON.stringify(a));
  const b = 'o texto "[SYSTEM NOTIFICATION - NOT USER INPUT]" aparece no log\nFALA-REAL-1\nFALA-REAL-2\n\noutro paragrafo';
  if (saida(b) !== 'Prompt: ' + b) erros.push('sonda 2 saiu ' + JSON.stringify(saida(b)));
  const c = '  [SYSTEM NOTIFICATION - NOT USER INPUT]  \nFALA-C';
  if (saida(c) !== 'Prompt: FALA-C') erros.push('linha so com marcador (com espacos) saiu ' + JSON.stringify(saida(c)));
  return erros.join('; ') || null;
});

caso('achado 2: bloco com a mesma tag aninhada sai inteiro e nao vaza o resultado', () => {
  const erros = [];
  const t1 = '<task-notification>\n<summary>S</summary>\n<result>HEAD abc <task-notification> interno </task-notification> cauda</result>\n</task-notification>\nfala depois';
  const o1 = saida(t1);
  if (o1 !== 'Agente: S\nPrompt: fala depois') erros.push('task-notification aninhado saiu ' + JSON.stringify(o1));
  const t2 = '<system-reminder>A <system-reminder>B</system-reminder> C SEGREDO</system-reminder>';
  const o2 = saida(t2);
  if (o2 !== '') erros.push('system-reminder aninhado saiu ' + JSON.stringify(o2));
  const t3 = '<task-notification>\n<summary>S3</summary>\n<result>sem fechar';
  if (saida(t3) !== 'Prompt: ' + t3) erros.push('task-notification sem fechamento nao ficou intacto');
  return erros.join('; ') || null;
});

caso('achado 5: 4000 aberturas sem fechamento e um fechamento no fim terminam em menos de 5 s e so a ultima some', () => {
  // Varredura antiga refazia a busca do fechamento a cada abertura orfa: cubica, mais de 100 s com N=4000.
  // O fechamento do fim fecha a ultima abertura (pilha); as N-1 anteriores nao tem fechamento e ficam.
  const N = 4000;
  const entrada = '<system-reminder>x '.repeat(N) + '</system-reminder>';
  const inicio = Date.now();
  const out = removerBlocosInjetados(entrada);
  const tempo = Date.now() - inicio;
  const esperado = '<system-reminder>x '.repeat(N - 1).trim();
  const erros = [];
  if (tempo >= 5000) erros.push('demorou ' + tempo + ' ms');
  if (out !== esperado) erros.push('saida de ' + out.length + ' caracteres difere da esperada de ' + esperado.length);
  return erros.join('; ') || null;
});

caso('achado 4: fala do usuario que comeca com "Agente: " sai como Prompt:', () => {
  const out = saida('Agente: faça X por favor\nFALA-REAL');
  if (out !== 'Prompt: Agente: faça X por favor\nFALA-REAL') return 'saida ' + JSON.stringify(out);
  return null;
});

caso('a < b e Map<string> saem iguais', () => {
  const textos = ['compare a < b e use Map<string> com <br>', 'x <y e z>w, sem fechar <br>'];
  const erros = [];
  for (const t of textos) {
    const out = saida(t);
    if (out !== 'Prompt: ' + t) erros.push(JSON.stringify(t) + ' saiu ' + JSON.stringify(out));
  }
  return erros.join('; ') || null;
});

for (const r of resultados) console.log(r);
JS

saida=$(node "$CASOS" "$OBSERVAR" 2>&1)
rc=$?

total=0
vermelhas=()
if [ "$rc" -ne 0 ]; then
  echo "  FALHA node saiu com rc=$rc"
  vermelhas+=("node")
  total=$((total+1))
fi
while IFS= read -r linha; do
  case "$linha" in
    ok\|*)
      total=$((total+1))
      echo "  ok    ${linha#ok|}"
      ;;
    FALHA\|*)
      total=$((total+1))
      nome="${linha#FALHA|}"
      nome="${nome%%|*}"
      echo "  $linha"
      vermelhas+=("$nome")
      ;;
  esac
done <<< "$saida"

lista=""
for v in "${vermelhas[@]}"; do lista="${lista:+$lista, }$v"; done
echo
echo "total=$total vermelhas:[$lista]"
[ "${#vermelhas[@]}" -eq 0 ] && [ "$total" -gt 0 ]
