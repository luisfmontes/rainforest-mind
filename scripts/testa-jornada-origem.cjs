#!/usr/bin/env node
// @categoria: bateria
/**
 * Bateria do criterio de presenca humana por origem (#485, tarefa 1).
 *
 * jornada.cjs so pode contar como presenca o que o usuario digitou. Esta bateria
 * monta transcripts SINTETICOS numa caixa temporaria (nunca copia transcript
 * real), roda `node scripts/jornada.cjs --json --transcript <arquivo>` como
 * subprocesso e afirma sobre o campo `mensagens` da saida.
 *
 * Cada transcript tem uma ancora humana (origin.kind = human, entrypoint = cli),
 * para que a saida seja sempre JSON valido; o esperado de cada caso inclui essa
 * ancora. Um caso "nao conta" falha se o filtro deixar a entrada passar.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const JORNADA = path.join(__dirname, 'jornada.cjs');
let ok = 0;
let falhou = 0;
const skipped = 0;
const vermelhas = [];

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    vermelhas.push(nome);
    console.log(`  FALHA ${nome}${detalhe ? ' :: ' + detalhe : ''}`);
  }
}

const T0 = Date.parse('2026-10-10T10:00:00Z');
function carimbo(i) {
  return new Date(T0 + i * 60000).toISOString();
}

// Ancora humana: sempre presente, conta sempre.
const ANCORA = {
  type: 'user',
  entrypoint: 'cli',
  origin: { kind: 'human' },
  message: { role: 'user', content: 'ancora humana' },
};

// Monta o transcript: duas ancoras primeiro, depois as entradas do caso, cada uma
// com carimbo proprio (um minuto de intervalo). Sao duas porque medir() devolve
// ultimo=null com uma unica mensagem, e --json quebra nesse caso (defeito
// anterior a #485, nao corrigido aqui: fora dos arquivos desta tarefa).
function transcrito(entradas) {
  const todas = [ANCORA, ANCORA, ...entradas];
  return todas
    .map((e, i) => JSON.stringify({ type: 'user', timestamp: carimbo(i), ...e }))
    .join('\n') + '\n';
}

// Conta as mensagens que jornada.cjs aceita no transcript.
function contar(arquivo) {
  const r = cp.spawnSync(process.execPath, [JORNADA, '--json', '--transcript', arquivo], { encoding: 'utf8' });
  let j;
  try {
    j = JSON.parse(r.stdout.trim());
  } catch {
    return { mensagens: null, detalhe: `saida nao e JSON (exit ${r.status}): ${r.stdout}${r.stderr}` };
  }
  return { mensagens: j.mensagens, maquina: j.maquina_descartadas, detalhe: `exit ${r.status}` };
}

// Saida em modo texto, linha a linha (#485, tarefa 2).
function linhasTexto(arquivo) {
  const r = cp.spawnSync(process.execPath, [JORNADA, '--transcript', arquivo], { encoding: 'utf8' });
  return r.stdout.split('\n');
}

// Cada caso: `entradas` extras ao lado das duas ancoras, e `esperado` = total
// aceito (ancoras incluidas).
const casos = [
  {
    nome: 'task-notification nao conta',
    esperado: 2,
    entradas: [
      {
        origin: { kind: 'task-notification' },
        entrypoint: 'cli',
        message: { role: 'user', content: '<task-notification>sub-agente terminou</task-notification>' },
      },
      {
        entrypoint: 'cli',
        message: { role: 'user', content: [{ type: 'text', text: '<task-notification>x</task-notification>' }] },
      },
    ],
  },
  {
    nome: 'headless sdk-cli nao conta',
    esperado: 2,
    entradas: [
      { entrypoint: 'sdk-cli', message: { role: 'user', content: 'Responda apenas com OK' } },
    ],
  },
  {
    nome: 'sdk-py nao conta',
    esperado: 2,
    entradas: [
      { entrypoint: 'sdk-py', message: { role: 'user', content: 'prompt de programa Python' } },
    ],
  },
  {
    nome: 'plugin nao conta',
    esperado: 2,
    entradas: [
      { origin: { kind: 'plugin' }, entrypoint: 'cli', message: { role: 'user', content: 'prompt de plugin' } },
    ],
  },
  {
    nome: 'humano com origin human conta',
    esperado: 3,
    entradas: [
      { origin: { kind: 'human' }, entrypoint: 'cli', message: { role: 'user', content: 'segunda mensagem humana' } },
    ],
  },
  {
    nome: 'sem origin com cli conta',
    esperado: 3,
    entradas: [
      { entrypoint: 'cli', message: { role: 'user', content: 'oi, sem origin' } },
    ],
  },
  {
    nome: 'interrupcao Esc sem origin conta',
    esperado: 3,
    entradas: [
      // Formato real: o Esc chega como array de blocos, nao como string.
      { entrypoint: 'cli', message: { role: 'user', content: [{ type: 'text', text: '[Request interrupted by user]' }] } },
    ],
  },
  {
    nome: 'origin null cai no ramo de entrypoint',
    esperado: 3,
    entradas: [
      { origin: null, entrypoint: 'cli', message: { role: 'user', content: 'origin nulo' } },
      { origin: null, entrypoint: 'sdk-cli', message: { role: 'user', content: 'origin nulo headless' } },
    ],
  },
  {
    nome: 'sem origin com sdk-cli nao conta',
    esperado: 2,
    entradas: [
      { entrypoint: 'sdk-cli', message: { role: 'user', content: [{ type: 'text', text: 'Ola de sdk' }] } },
    ],
  },
  {
    nome: 'isSidechain nao conta',
    esperado: 2,
    entradas: [
      {
        origin: { kind: 'human' },
        entrypoint: 'cli',
        isSidechain: true,
        message: { role: 'user', content: 'mensagem de subagente' },
      },
    ],
  },
];

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), 'jornada-origem-'));
try {
  for (const c of casos) {
    const arquivo = path.join(caixa, c.nome.replace(/[^a-zA-Z0-9]+/g, '_') + '.jsonl');
    fs.writeFileSync(arquivo, transcrito(c.entradas));
    const r = contar(arquivo);
    caso(c.nome, r.mensagens === c.esperado, `mensagens=${r.mensagens} esperado=${c.esperado} (${r.detalhe})`);
  }

  // Tres entradas de maquina (sdk-cli, task-notification, plugin) e duas que os
  // filtros antigos descartam antes da contagem (toolUseResult e isMeta).
  const arqMaquina = path.join(caixa, 'linha_descartados.jsonl');
  fs.writeFileSync(
    arqMaquina,
    transcrito([
      { entrypoint: 'sdk-cli', message: { role: 'user', content: 'Responda apenas com OK' } },
      {
        origin: { kind: 'task-notification' },
        entrypoint: 'cli',
        message: { role: 'user', content: '<task-notification>sub-agente terminou</task-notification>' },
      },
      { origin: { kind: 'plugin' }, entrypoint: 'cli', message: { role: 'user', content: 'prompt de plugin' } },
      { toolUseResult: { ok: true }, entrypoint: 'cli', message: { role: 'user', content: 'retorno de tool' } },
      { isMeta: true, entrypoint: 'cli', message: { role: 'user', content: 'meta' } },
    ])
  );
  const linhas = linhasTexto(arqMaquina);
  const iMensagens = linhas.findIndex((l) => l.startsWith('mensagens do usuario'));
  const jsonMaquina = contar(arqMaquina);
  caso(
    'linha de descartados mostra a contagem de entradas de maquina',
    iMensagens >= 0 &&
      linhas[iMensagens + 1] === 'sinais de maquina descartados ..... 3' &&
      jsonMaquina.maquina === 3 &&
      jsonMaquina.mensagens === 2,
    `linha=${JSON.stringify(linhas[iMensagens + 1])} json.maquina=${jsonMaquina.maquina} json.mensagens=${jsonMaquina.mensagens}`
  );

  // So toolUseResult e isMeta, ambos com entrypoint sdk-cli: se o filtro antigo
  // deixasse passar, eles virariam maquina e a contagem sairia 2, nao 0.
  const arqSoDescartes = path.join(caixa, 'so_descartes.jsonl');
  fs.writeFileSync(
    arqSoDescartes,
    transcrito([
      { toolUseResult: { ok: true }, entrypoint: 'sdk-cli', message: { role: 'user', content: 'retorno' } },
      { isMeta: true, origin: { kind: 'plugin' }, entrypoint: 'cli', message: { role: 'user', content: 'meta' } },
    ])
  );
  const linhasSo = linhasTexto(arqSoDescartes);
  const jsonSo = contar(arqSoDescartes);
  caso(
    'toolUseResult e isMeta nao entram na contagem de maquina',
    linhasSo.includes('sinais de maquina descartados ..... 0') && jsonSo.maquina === 0,
    `linhas=${JSON.stringify(linhasSo.filter((l) => l.startsWith('sinais')))} json.maquina=${jsonSo.maquina}`
  );

  // Dia so de maquina: zero humanos e o modo texto ainda mostra quantos sinais
  // foram descartados (e o caso em que um filtro quebrado zeraria a jornada).
  const arqSoMaquina = path.join(caixa, 'so_maquina.jsonl');
  fs.writeFileSync(
    arqSoMaquina,
    [
      { entrypoint: 'sdk-cli', message: { role: 'user', content: 'Responda apenas com OK' } },
      { origin: { kind: 'task-notification' }, entrypoint: 'cli', message: { role: 'user', content: '<task-notification>x</task-notification>' } },
    ].map((e, i) => JSON.stringify({ type: 'user', timestamp: carimbo(i), ...e })).join('\n') + '\n'
  );
  const linhasSoMaq = linhasTexto(arqSoMaquina);
  caso(
    'sem humanos o modo texto ainda mostra os descartados',
    linhasSoMaq.includes('sinais de maquina descartados ..... 2'),
    `linhas=${JSON.stringify(linhasSoMaq)}`
  );
} finally {
  fs.rmSync(caixa, { recursive: true, force: true });
}

const total = ok + falhou;
console.log(`\ntotal=${total} skipped=${skipped} vermelhas:[${vermelhas.join(', ')}]`);
process.exit(falhou ? 1 : 0);
