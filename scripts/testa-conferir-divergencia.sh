#!/bin/bash
# Bateria do conferir-divergencia.cjs. Monta fixtures PROPRIAS num diretorio
# temporario -- nunca le o rastro real de sessao nenhuma (aquilo e rastro de
# OUTRA execucao, pode sumir a qualquer momento, e o numero de agentes dentro
# dele muda de rodada pra rodada -- fixture que dependesse dele envelheceria
# sozinha).
#
# Os testes que importam sao os blocos 2 e 3: um adultera a linha de um
# frame FORA da linha da pergunta, o outro faz um frame conter a pergunta de
# outro. Sem eles o bloco 1 sozinho so provaria que o caminho feliz funciona
# -- e uma trava que nunca foi vista travando nao e evidencia de nada. A
# prova de mutacao (que sabota a comparacao dentro do .cjs e exige esta
# bateria inteira vermelha) fica documentada em separado, fora deste
# arquivo: ela edita o FONTE de producao, nao um destes fixtures.
#
# Uso: bash scripts/testa-conferir-divergencia.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
CONFERIR_CJS="$SRC/scripts/conferir-divergencia.cjs"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
esperado_diferente_de() { # nome, exit PROIBIDO, comando...  (para "exit != 0")
  local nome="$1" proibido="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" != "$proibido" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit != $proibido, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
contem() { # nome, texto_literal_esperado, comando...
  local nome="$1" alvo="$2"; shift 2
  local saida; saida=$("$@" 2>&1)
  if echo "$saida" | grep -qF "$alvo"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei \"$alvo\" na saida"; echo "$saida" | sed 's/^/         /'; fi
}
nao_contem() { # nome, texto_literal_proibido, comando...
  local nome="$1" alvo="$2"; shift 2
  local saida; saida=$("$@" 2>&1)
  if echo "$saida" | grep -qF "$alvo"; then falhou=$((falhou+1)); echo "  FALHA $nome: achou \"$alvo\" na saida (nao devia)"; echo "$saida" | sed 's/^/         /'
  else ok=$((ok+1)); echo "  ok   $nome"; fi
}

cd "$SB" || exit 1

# ------------------------------------------------------------- gerador comum
# Fica em JS, e nao em bash, porque o prompt tem linha, aspas e crase --
# escapar isso em bash so criaria bug de escaping em vez de testar o alvo.
cat > lib_fixture.js <<'JS'
const fs = require('fs');
const path = require('path');

const PERGUNTAS = [
  'Qual nome soa mais confiavel para um comprador enterprise?',
  'Qual nome e mais facil de lembrar depois de ouvir uma vez?',
  'Qual nome evita colisao com marcas ja registradas no Brasil?',
  'Qual nome funciona bem tanto em portugues quanto em ingles?',
  'Qual nome tem o dominio .com mais provavel de estar livre?',
  'Qual nome soa bem quando dito em voz alta numa reuniao?',
];

const CRITICO_PROMPT = [
  '# Divergir - Critico',
  '',
  'Voce recebeu as respostas de seis frames independentes sobre o nome de',
  'um produto novo de anotacoes para times remotos. Sintetize os pontos de',
  'consenso e as divergencias mais relevantes, sem inventar frame que nao',
  'foi mostrado a voce.',
  '',
  '## O que fazer',
  'Produza uma sintese estruturada com: consenso, divergencias e uma',
  'recomendacao final justificada.',
  '',
].join('\n');

function template(pergunta, quebra) {
  const L = quebra === 'crlf' ? '\r\n' : '\n';
  return [
    '# Divergir - Frame isolado',
    '',
    'Voce e um frame independente nesta rodada de divergencia. Nao veja a',
    'saida de nenhum outro frame, e nao mencione os outros frames na resposta.',
    '',
    '## Contexto',
    'Estamos decidindo o nome de um produto novo de anotacoes para times remotos.',
    '',
    '## Pergunta do frame',
    pergunta,
    '',
    '## O que fazer',
    'Responda com sua perspectiva isolada. Nao cite as perguntas dos outros frames.',
    '',
  ].join(L);
}

function escreveAgente(dir, id, prompt, opts) {
  opts = opts || {};
  const linha1 = JSON.stringify({
    parentUuid: null, isSidechain: true,
    promptId: `prompt-${id}`, agentId: id,
    type: 'user', message: { role: 'user', content: prompt },
  });
  const linha2 = JSON.stringify({
    parentUuid: `p-${id}`, isSidechain: true, agentId: id,
    type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'ok (fixture)' }] },
  });
  fs.writeFileSync(path.join(dir, `agent-${id}.jsonl`), `${linha1}\n${linha2}\n`, 'utf8');
  if (!opts.semMeta) {
    fs.writeFileSync(path.join(dir, `agent-${id}.meta.json`), JSON.stringify({
      agentType: 'workflow-subagent', spawnDepth: 1, worktreePath: `C:\\fixture\\wt-${id}`,
    }), 'utf8');
  }
}

function escreveJournal(dir, ids) {
  const linhas = ids.map((id) => JSON.stringify({ type: 'started', key: `v2:${id}`, agentId: id }));
  fs.writeFileSync(path.join(dir, 'journal.jsonl'), linhas.join('\n') + '\n', 'utf8');
}

// Monta um wf_ completo e saudavel: 6 frames (ids frame-1..frame-6) + 1
// critico (id critico). `mods` deixa um teste alterar so o que precisa,
// pelo indice do frame (0-based) ou pelo id 'critico'.
function montaWorkflowSaudavel(dir, mods) {
  mods = mods || {};
  fs.mkdirSync(dir, { recursive: true });
  const ids = [];
  for (let i = 0; i < 6; i += 1) {
    const id = `frame-${i + 1}`;
    ids.push(id);
    const mod = mods[i] || {};
    let prompt = mod.promptCru !== undefined ? mod.promptCru : template(mod.pergunta || PERGUNTAS[i], mod.quebra);
    escreveAgente(dir, id, prompt, { semMeta: !!mod.semMeta });
  }
  ids.push('critico');
  const modCritico = mods.critico || {};
  escreveAgente(dir, 'critico', modCritico.promptCru !== undefined ? modCritico.promptCru : CRITICO_PROMPT, {});
  escreveJournal(dir, ids);
}

module.exports = { PERGUNTAS, CRITICO_PROMPT, template, escreveAgente, escreveJournal, montaWorkflowSaudavel };
JS

echo "== 1. caso positivo: 7 agentes bem formados =="
node -e "require('./lib_fixture.js').montaWorkflowSaudavel('wf_ok')"
esperado "7 agentes bem formados sai 0" 0 node "$CONFERIR_CJS" wf_ok
contem "... conta os 7 agentes" "agentes encontrados: 7" node "$CONFERIR_CJS" wf_ok
contem "... identifica o critico certo" "critico candidato: critico" node "$CONFERIR_CJS" wf_ok
contem "... aponta a linha da pergunta (linha 10 do molde)" "linha 10" node "$CONFERIR_CJS" wf_ok
contem "... fecha com PASSOU" "PASSOU" node "$CONFERIR_CJS" wf_ok

echo
echo "== 2. prompt de frame adulterado (uma linha alem da pergunta diverge) =="
# frame-3 tem o paragrafo de contexto trocado -- isso NAO e a linha da
# pergunta (que continua so dele, como sempre), e por isso quebra o molde:
# agora ha DUAS linhas divergentes nesse frame, nao uma.
node -e "
const { template, montaWorkflowSaudavel } = require('./lib_fixture.js');
const prompt3 = template('Qual nome evita colisao com marcas ja registradas no Brasil?')
  .replace('Estamos decidindo o nome de um produto novo de anotacoes para times remotos.',
           'Estamos decidindo o nome de um produto DIFERENTE, de gestao de estoque.');
montaWorkflowSaudavel('wf_adulterado', { 2: { promptCru: prompt3 } });
"
esperado_diferente_de "frame adulterado nao sai 0" 0 node "$CONFERIR_CJS" wf_adulterado
contem "... e nomeia o agente adulterado (frame-3)" "frame-3" node "$CONFERIR_CJS" wf_adulterado
contem "... e diz RECUSADO" "RECUSADO" node "$CONFERIR_CJS" wf_adulterado

echo
echo "== 3. frame contendo a pergunta de outro (quebra de isolamento) =="
# frame-5 tem, dentro da PROPRIA linha de pergunta, o texto exato da
# pergunta do frame-2 colado junto -- o formato mais direto de "viu o que
# outro frame recebeu". A contagem de linhas dele continua igual (a
# contaminacao mora dentro da mesma linha, nao numa linha extra), entao os
# itens 2/3 nem deviam acusar nada -- quem tem que pegar isto e o item 4.
node -e "
const { PERGUNTAS, template, montaWorkflowSaudavel } = require('./lib_fixture.js');
const perguntaContaminada = PERGUNTAS[4] + ' (ver tambem: \"' + PERGUNTAS[1] + '\")';
montaWorkflowSaudavel('wf_contaminado', { 4: { pergunta: perguntaContaminada } });
"
esperado_diferente_de "frame contaminado nao sai 0" 0 node "$CONFERIR_CJS" wf_contaminado
contem "... e nomeia o agente contaminado (frame-5)" "agente frame-5" node "$CONFERIR_CJS" wf_contaminado
contem "... e nomeia de QUEM veio o vazamento (frame-2)" "pergunta do agente frame-2" node "$CONFERIR_CJS" wf_contaminado
# Controle negativo: o MESMO fixture nao pode acusar um frame saudavel --
# senao o item 4 estaria classificando tudo como contaminado (ruido, nao
# deteccao). so frame-5 pode aparecer como o CONTAMINADO.
saida_contaminado=$(node "$CONFERIR_CJS" wf_contaminado 2>&1)
if echo "$saida_contaminado" | grep -q "agente frame-1:"
then falhou=$((falhou+1)); echo "  FALHA acusou frame-1, que esta saudavel, de contaminacao"
else ok=$((ok+1)); echo "  ok   nao acusou frame-1 (que esta saudavel) de contaminacao"
fi

echo
echo "== 4. contagem errada de agentes =="
node -e "
const { montaWorkflowSaudavel } = require('./lib_fixture.js');
montaWorkflowSaudavel('wf_seis');
"
node -e "require('fs').unlinkSync('wf_seis/agent-frame-6.jsonl'); require('fs').unlinkSync('wf_seis/agent-frame-6.meta.json');"
esperado_diferente_de "6 agentes (faltou 1 frame) nao sai 0" 0 node "$CONFERIR_CJS" wf_seis
contem "... e diz quantos achou (6)" "encontrei 6" node "$CONFERIR_CJS" wf_seis

node -e "
const { escreveAgente, montaWorkflowSaudavel } = require('./lib_fixture.js');
montaWorkflowSaudavel('wf_oito');
escreveAgente('wf_oito', 'frame-extra', 'prompt de um oitavo agente que nao devia existir nesta rodada.', {});
"
esperado_diferente_de "8 agentes (um a mais) nao sai 0" 0 node "$CONFERIR_CJS" wf_oito
contem "... e diz quantos achou (8)" "encontrei 8" node "$CONFERIR_CJS" wf_oito

echo
echo "== 5. bordas =="
# 5a. .meta.json ausente e AVISO, nao bloqueio -- o item 1 conta pelo
# .jsonl, que e a unica peca que os 4 itens do contrato realmente usam.
node -e "
const { montaWorkflowSaudavel } = require('./lib_fixture.js');
montaWorkflowSaudavel('wf_sem_meta', { 1: { semMeta: true } });
"
esperado "meta.json ausente num frame ainda sai 0" 0 node "$CONFERIR_CJS" wf_sem_meta
contem "... e avisa qual agente ficou sem meta.json" "sem .meta.json: frame-2" node "$CONFERIR_CJS" wf_sem_meta

# 5b. pergunta curta (abaixo do limiar) nao pode gerar falso positivo de
# contaminacao so por coincidir, por acaso, com um pedaco de outra pergunta.
# frame-1 pergunta so "Nome?" (5 chars); frame-2 pergunta algo que CONTEM
# "Nome?" ao acaso -- sem o limiar, isso pareceria frame-2 ter visto a
# pergunta do frame-1. As duas continuam sendo SO a linha da pergunta (a
# unica que ja tem licenca pra variar), entao os itens 2/3 nem entram em
# jogo: e o item 4, sozinho, que precisa saber ignorar coincidencia curta.
node -e "
const { montaWorkflowSaudavel } = require('./lib_fixture.js');
montaWorkflowSaudavel('wf_curta', {
  0: { pergunta: 'Nome?' },
  1: { pergunta: 'Qual Nome? soa melhor para um produto B2B?' },
});
"
esperado "pergunta curta nao derruba por falso positivo de contaminacao" 0 node "$CONFERIR_CJS" wf_curta

# 5c. CRLF: um frame com todas as linhas em \r\n continua sendo o MESMO
# molde -- se a normalizacao de quebra de linha nao existisse, toda linha
# dele pareceria divergente por causa do \r sobrando, nao do conteudo.
node -e "
const { montaWorkflowSaudavel } = require('./lib_fixture.js');
montaWorkflowSaudavel('wf_crlf', { 3: { quebra: 'crlf' } });
"
esperado "frame gravado em CRLF ainda bate no molde (so a quebra de linha muda)" 0 node "$CONFERIR_CJS" wf_crlf

# 5d. uso sem argumento e diretorio inexistente sao erro de uso (exit 1),
# nao "isolamento violado" (exit 2) -- quem chama de outro script precisa
# poder distinguir as duas coisas.
esperado "sem argumento e erro de uso" 1 node "$CONFERIR_CJS"
esperado "diretorio inexistente e erro de uso" 1 node "$CONFERIR_CJS" "$SB/isto-nao-existe"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
