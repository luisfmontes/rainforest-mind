#!/bin/bash
# Testa scripts/sugerir-elaboracoes.cjs: ranking das regras por observacoes que as
# citam, marca das que ja estao em hooks/abertura-mod.json, e somente-leitura.
# Fixture em diretorio temporario; o ideias.jsonl real nunca e tocado.
set -euo pipefail
cd "$(dirname "$0")/.."

node - <<'JS'
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-sugerir-elab-'));
const config = path.resolve('hooks', 'abertura-mod.json');
const script = path.resolve('scripts', 'sugerir-elaboracoes.cjs');
const hash = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
let ok = 0, falhas = 0;

function caso(nome, cond, detalhe = '') {
  if (cond) { ok++; console.log(`ok   ${nome}`); }
  else { falhas++; console.log(`FALHA ${nome}${detalhe ? ': ' + detalhe : ''}`); }
}
function rodar(args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
}

try {
  const linhas = [];
  const obs = (texto) => linhas.push(JSON.stringify({ id: 'o' + linhas.length, tipo: 'observacao', descricao: texto }));
  // 30 / 28 / 17 / 14 observacoes. A primeira da regra 16 a cita tres vezes (conta uma).
  obs('regra 16 falhou; a Regra 16 de novo, e regras 16 outra vez');
  for (let i = 1; i < 30; i++) obs(`a regra 16 mordeu (${i})`);
  for (let i = 0; i < 28; i++) obs(`a regra 12 mordeu (${i})`);
  for (let i = 0; i < 17; i++) obs(`a regra 11 mordeu (${i})`);
  for (let i = 0; i < 14; i++) obs(`a regra17 mordeu (${i})`);
  // fronteira: "regra 1" dentro de "regra 16" nao conta; regra 18 fora da faixa; "regra 160" idem.
  obs('so a regra 16 aqui, regra 18 e regra 160 nao contam');
  // regra 3 citada 2 vezes em observacoes distintas e uma vez em varios campos da mesma.
  obs('regra 3 apareceu');
  linhas.push(JSON.stringify({ id: 'o-multi', tipo: 'observacao', titulo: 'regra 3', descricao: 'regra 3', contexto: 'regra 3' }));
  // linhas de outro tipo (e sem tipo) nao contam, por mais que citem.
  for (let i = 0; i < 50; i++) linhas.push(JSON.stringify({ id: 'i' + i, tipo: 'ideia', descricao: 'regra 5 e regra 9' }));
  linhas.push(JSON.stringify({ id: 'sem-tipo', descricao: 'regra 5' }));
  // JSON invalido no meio: conta e avisa, nao derruba.
  linhas.push('{isto nao e json');
  const jsonl = path.join(raiz, 'ideias.jsonl');
  fs.writeFileSync(jsonl, linhas.join('\n') + '\n');

  const antesCfg = hash(config), antesJsonl = hash(jsonl);
  const r = rodar([jsonl]);
  const depoisCfg = hash(config), depoisJsonl = hash(jsonl);
  const saida = r.stdout;
  const linhaDe = (n) => saida.split('\n').findIndex((l) => l.startsWith(`regra ${n}:`));

  caso('sai com 0', r.status === 0, `status ${r.status} stderr ${r.stderr}`);
  caso('ranking por citacoes: r16 antes de r12 antes de r11',
    linhaDe(16) >= 0 && linhaDe(16) < linhaDe(12) && linhaDe(12) < linhaDe(11) && linhaDe(11) < linhaDe(17),
    saida);
  caso('contagens exatas 31/28/17/14 (r16 conta uma vez por observacao)',
    /^regra 16: 31\b/m.test(saida) && /^regra 12: 28\b/m.test(saida) &&
    /^regra 11: 17\b/m.test(saida) && /^regra 17: 14\b/m.test(saida), saida);
  caso('regra 1, 18 e 160 nao aparecem (fronteira de palavra e faixa 1 a 17)',
    linhaDe(1) === -1 && linhaDe(18) === -1 && linhaDe(160) === -1, saida);
  caso('regra 3 contada uma vez por observacao: 2',
    /^regra 3: 2\b/m.test(saida), saida);
  caso('linhas de outro tipo nao contam (r5 e r9 ausentes)',
    linhaDe(5) === -1 && linhaDe(9) === -1, saida);
  caso('conta so as 92 observacoes validas e avisa da linha invalida',
    /^observacoes: 92$/m.test(saida) && /AVISO: 1 linha\(s\) com JSON invalido/.test(saida), saida);
  caso('marca as que ja estao em abertura-mod.json e so elas',
    /^regra 16: .*\[ja em abertura-mod\.json\]/m.test(saida) &&
    /^regra 17: .*\[ja em abertura-mod\.json\]/m.test(saida) &&
    !/^regra 3: .*\[ja em/m.test(saida), saida);
  caso('somente leitura: hash de abertura-mod.json igual antes e depois', antesCfg === depoisCfg);
  caso('somente leitura: hash do ideias.jsonl igual antes e depois', antesJsonl === depoisJsonl);

  const ausente = rodar([path.join(raiz, 'nao-existe.jsonl')]);
  caso('arquivo inexistente: exit 1 com mensagem', ausente.status === 1 && /nao consegui ler/.test(ausente.stderr));
  const ajuda = rodar(['--help']);
  caso('--help imprime o uso e sai com 0', ajuda.status === 0 && /^Uso:/m.test(ajuda.stdout));
} finally {
  fs.rmSync(raiz, { recursive: true, force: true });
}
console.log(`${ok} ok, ${falhas} falha(s), 0 skipped`);
process.exit(falhas ? 1 : 0);
JS
