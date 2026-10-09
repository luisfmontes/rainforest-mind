#!/usr/bin/env node
'use strict';
// Bateria hermetica (#436, D5): a memoria que o teto de 1.500 B do bloco cortou nao pode
// virar "ja servida". Sandbox temporario com RFM_ROOT proprio; banco do criarSchema REAL;
// o hook roda como processo filho recebendo no stdin o payload de UserPromptSubmit
// (prompt, session_id, cwd, transcript_path, hook_event_name), como em testa-memoria-assunto-prompt.cjs.
// Corpus: 3 observacoes do assunto cujas linhas formatadas (300 caracteres acentuados, 2 B cada)
// estouram o teto na terceira, mais 400 de enchimento para o limiar do bm25.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { slugDoCaminho } = require(path.join(__dirname, '..', 'scripts', 'lib', 'projeto-canonico.cjs'));

const HOOK = path.join(__dirname, 'memoria-assunto-prompt.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-prompt-so-o-que-entrou-'));
const raiz = path.join(tmp, 'raiz');
const cwdSessao = path.join(tmp, 'projeto-teste');
const PROJ_ATUAL = slugDoCaminho(cwdSessao);
fs.mkdirSync(raiz);
fs.mkdirSync(cwdSessao);

// ---- corpus ----
const db = new DatabaseSync(path.join(raiz, 'rainforest.db'));
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 400; i++) {
  ins.run(PROJ_ATUAL, 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-10-01T10:00:00.000Z', 'f' + i);
}
const MARCADORES = ['marcaum', 'marcadois', 'marcatres'];
const acentuado = 'ãéõçâêíóúàüãéõçâêíóúàü '.repeat(4); // palavras longas, 2 B por caractere
const alvos = {};
MARCADORES.forEach((m, i) => {
  const corpo = 'zarquon flibbertigibbet quasar ' + acentuado.repeat(4);
  const r = ins.run(PROJ_ATUAL, 'Reconciliacao ' + m + ' zarquon flibbertigibbet\n\n' + corpo,
    '2026-10-0' + (2 + i) + 'T10:00:00.000Z', 'alvo-' + m);
  alvos[m] = Number(r.lastInsertRowid);
});
db.close();

const transcrito = path.join(tmp, 'sem-abertura.jsonl');
fs.writeFileSync(transcrito, JSON.stringify({ type: 'user', message: { role: 'user', content: 'oi' } }) + '\n');
const PEDIDO = 'quero entender a reconciliacao zarquon flibbertigibbet quasar';

function rodar(sessao) {
  const env = { ...process.env, RFM_ROOT: raiz };
  delete env.CLAUDE_PROJECT_DIR;
  const stdin = JSON.stringify({
    session_id: sessao, transcript_path: transcrito, cwd: cwdSessao,
    hook_event_name: 'UserPromptSubmit', prompt: PEDIDO,
  });
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, env, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout };
}
function linhas(saida) {
  const ctx = JSON.parse(saida).hookSpecificOutput.additionalContext;
  return ctx.split('\n').slice(1);
}
function marcadoresDe(ls) { return MARCADORES.filter((m) => ls.some((l) => l.includes(m))); }
function idsDoArquivo(sessao) {
  return JSON.parse(fs.readFileSync(path.join(raiz, 'memoria-assunto', sessao + '.json'), 'utf8')).sort((a, b) => a - b);
}

let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}

const SID = 'sessao-teto';
let primeiro = null;
let faltante = null;

caso('primeiro pedido: bloco com 2 linhas e arquivo com exatamente esses 2 ids', () => {
  const r = rodar(SID);
  if (r.codigo !== 0) return false;
  const ls = linhas(r.saida);
  primeiro = marcadoresDe(ls);
  faltante = MARCADORES.filter((m) => !primeiro.includes(m));
  const esperados = primeiro.map((m) => alvos[m]).sort((a, b) => a - b);
  const gravados = idsDoArquivo(SID);
  return ls.length === 2 && primeiro.length === 2 && JSON.stringify(gravados) === JSON.stringify(esperados);
});
caso('memoria cortada pelo teto de 1500 B volta no pedido seguinte da sessao', () => {
  const r = rodar(SID);
  if (r.codigo !== 0 || !r.saida) return false;
  const ls = linhas(r.saida);
  const marc = marcadoresDe(ls);
  const gravados = idsDoArquivo(SID);
  return ls.length === 1 && faltante && faltante.length === 1 && marc[0] === faltante[0] &&
    gravados.length === 3 && MARCADORES.every((m) => gravados.includes(alvos[m]));
});
caso('terceiro pedido sai vazio com exit 0, as 3 ja foram servidas', () => {
  const r = rodar(SID);
  return r.codigo === 0 && r.saida === '' && idsDoArquivo(SID).length === 3;
});

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforco */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
