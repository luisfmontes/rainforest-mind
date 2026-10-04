#!/usr/bin/env node
// @categoria: bateria
/**
 * Bateria do filtro por mtime do jornada.cjs (tarefa 1 do plano do relogio).
 *
 * jornada.cjs lia os ~3.900 transcripts do usuario para medir um dia; transcript
 * com mtime anterior a meia-noite local do --dia nao pode ter mensagem desse dia,
 * entao nao entra na lista. Esta bateria monta uma caixa temporaria com
 * transcripts SINTETICOS (nunca copia transcript real) e a apaga ao fim.
 *
 * Quatro arquivos, de proposito:
 *   A  mtime agora,        2 mensagens de hoje
 *   B  mtime -3 dias,      2 mensagens de hoje + 2 do dia D3 (sintetico: so ele
 *      separa "filtrou" de "leu tudo" quando o dia e hoje)
 *   C  mtime meio-dia D3,  2 mensagens de D3
 *   D  mtime agora,        2 mensagens de D3 (arquivo novo com mensagem antiga:
 *      contra filtro demais)
 * --dia hoje  => 2 (so A; B e velho demais). --dia D3 => 6 (B, C e D lidos).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const JORNADA = path.join(__dirname, 'jornada.cjs');
let ok = 0;
let falhou = 0;
const skipped = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ' :: ' + detalhe : ''}`);
  }
}

function pad2(n) { return String(n).padStart(2, '0'); }
function dia(d) { return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; }
function transcrito(...datas) {
  return datas.map((d) => JSON.stringify({ type: 'user', timestamp: d.toISOString(), message: { role: 'user' } })).join('\n') + '\n';
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), 'jornada-filtro-'));
try {
  const pasta = path.join(caixa, '.claude-personal', 'projects', 'proj');
  fs.mkdirSync(pasta, { recursive: true });

  const agora = new Date();
  const hojeMeioDia = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate(), 12, 0);
  const d3MeioDia = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() - 3, 12, 0);
  const min = (d, m) => new Date(d.getTime() + m * 60000);
  const DIA_HOJE = dia(agora);
  const DIA_D3 = dia(d3MeioDia);

  const grava = (nome, texto, mtime) => {
    const f = path.join(pasta, nome);
    fs.writeFileSync(f, texto);
    fs.utimesSync(f, mtime, mtime);
    return f;
  };
  const hojeMsgs = [hojeMeioDia, min(hojeMeioDia, 10)];
  const d3Msgs = [d3MeioDia, min(d3MeioDia, 10)];
  const tresDiasAtras = new Date(agora.getTime() - 3 * 86400000);
  grava('A.jsonl', transcrito(...hojeMsgs), agora);
  grava('B.jsonl', transcrito(...hojeMsgs, ...d3Msgs), tresDiasAtras);
  grava('C.jsonl', transcrito(...d3Msgs), d3MeioDia);
  grava('D.jsonl', transcrito(...d3Msgs), agora);

  const env = { ...process.env, USERPROFILE: caixa, HOME: caixa };
  delete env.FORCE_COLOR;
  const roda = (...args) => {
    const r = cp.spawnSync(process.execPath, [JORNADA, ...args], { env, encoding: 'utf8' });
    let json = null;
    try { json = JSON.parse(r.stdout); } catch { /* fica null */ }
    return { json, saida: r.stdout + r.stderr };
  };

  console.log('== filtro por mtime do transcript ==');
  const hoje = roda('--json', '--dia', DIA_HOJE);
  caso('transcript mais velho que o dia nao e lido', hoje.json && hoje.json.mensagens === 2, hoje.saida.trim());

  const d3 = roda('--json', '--dia', DIA_D3);
  caso('B lido com --dia de 3 dias atras conta as suas (e C e D)', d3.json && d3.json.mensagens === 6, d3.saida.trim());
  caso('arquivo com mtime de agora e mensagens antigas segue contando em --dia antigo (D entra nos 6)',
    d3.json && d3.json.mensagens - 4 === 2, d3.saida.trim());
  const soB = roda('--json', '--transcript', path.join(pasta, 'B.jsonl'));
  caso('--transcript nao passa pelo filtro (B velho le as 4)', soB.json && soB.json.mensagens === 4, soB.saida.trim());

  console.log('== exportacao compativel ==');
  const mod = require(JORNADA);
  const nomes = (l) => l.map((f) => path.basename(f)).sort().join(',');
  const antes = process.env.USERPROFILE;
  process.env.USERPROFILE = caixa;
  try {
    caso('transcriptsDisponiveis() sem argumento lista todos', nomes(mod.transcriptsDisponiveis()) === 'A.jsonl,B.jsonl,C.jsonl,D.jsonl', nomes(mod.transcriptsDisponiveis()));
    caso('transcriptsDisponiveis(desde) corta pela mtime', nomes(mod.transcriptsDisponiveis(agora.getTime() - 3600000)) === 'A.jsonl,D.jsonl', nomes(mod.transcriptsDisponiveis(agora.getTime() - 3600000)));
  } finally {
    if (antes === undefined) delete process.env.USERPROFILE; else process.env.USERPROFILE = antes;
  }

  console.log('== --dia fora do formato nao filtra ==');
  const livre = roda('--json', '--dia', 'ontem');
  caso('--dia malformado nao quebra nem filtra (nenhuma mensagem com esse dia, exit sem erro de leitura)',
    livre.json && livre.json.mensagens === 0, livre.saida.trim());
} finally {
  fs.rmSync(caixa, { recursive: true, force: true });
}

console.log(`\n${ok} ok, ${falhou} falha(s), ${skipped} skipped`);
process.exit(falhou ? 1 : 0);
