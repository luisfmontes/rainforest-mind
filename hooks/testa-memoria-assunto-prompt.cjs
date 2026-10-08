#!/usr/bin/env node
'use strict';
// Bateria hermetica de hooks/memoria-assunto-prompt.cjs (UserPromptSubmit).
// Sandbox temporario com RFM_ROOT proprio; banco criado pelo criarSchema REAL; o hook roda
// como processo filho recebendo no stdin o JSON que o harness envia (prompt, session_id, cwd,
// transcript_path, hook_event_name — docs/rainforest/referencia/2026-10-08-harness-prompt-e-agent.md).
// Limiar: o corpus tem 400 memorias de enchimento + alvos de termos raros repetidos, entao os
// alvos passam do LIMIAR_BM25 (-16) de verdade; nenhuma variavel de ambiente afrouxa o limiar.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { formatarObservacao } = require('./lib/memoria-sessao.cjs');

const HOOK = path.join(__dirname, 'memoria-assunto-prompt.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-memoria-assunto-prompt-'));
const raiz = path.join(tmp, 'raiz');
const cwdSessao = path.join(tmp, 'projeto-teste');
fs.mkdirSync(raiz);
fs.mkdirSync(cwdSessao);

// ---- corpus ----
const caminhoDb = path.join(raiz, 'rainforest.db');
const db = new DatabaseSync(caminhoDb);
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 400; i++) {
  ins.run('projeto-teste', 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-10-01T10:00:00.000Z', 'f' + i);
}
const alvos = {};
for (const nome of ['Alfa', 'Bravo', 'Charlie', 'Delta']) {
  const r = ins.run(
    nome === 'Alfa' ? 'projeto-teste' : 'outro-projeto',
    'Reconciliacao ' + nome + ' zarquon flibbertigibbet\n\n' + ('zarquon flibbertigibbet zarquon flibbertigibbet quasar ' + nome + ' ').repeat(3),
    '2026-10-0' + (2 + Object.keys(alvos).length) + 'T10:00:00.000Z', 'alvo-' + nome);
  alvos[nome] = Number(r.lastInsertRowid);
}
db.close();

// Transcrito existente mas sem attachment de SessionStart: a abertura nao serviu nada.
const transcritoSemAbertura = path.join(tmp, 'sem-abertura.jsonl');
fs.writeFileSync(transcritoSemAbertura, JSON.stringify({ type: 'user', message: { role: 'user', content: 'oi' } }) + '\n');

const PEDIDO ='quero entender a reconciliacao zarquon flibbertigibbet quasar';

// ---- infraestrutura ----
function rodar(stdin, { raizAmbiente = raiz } = {}) {
  const env = { ...process.env, RFM_ROOT: raizAmbiente };
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, env, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr };
}
function payload(o) {
  return JSON.stringify(Object.assign({
    session_id: 'sessao-padrao', transcript_path: transcritoSemAbertura, cwd: cwdSessao,
    hook_event_name: 'UserPromptSubmit', prompt: PEDIDO,
  }, o));
}
function contexto(saida) {
  const j = JSON.parse(saida);
  if (j.hookSpecificOutput.hookEventName !== 'UserPromptSubmit') throw new Error('evento errado');
  return j.hookSpecificOutput.additionalContext;
}
function linhasDe(ctx) { return ctx.split('\n').slice(1); }
function transcritoComAbertura(arquivo, linhasServidas) {
  const bloco = '## Memória (corpus residentes)\n' + linhasServidas.join('\n') + '\nmais: 0 outras';
  const entrada = {
    type: 'attachment',
    attachment: {
      type: 'hook_success', hookEvent: 'SessionStart', hookName: 'SessionStart:startup',
      stdout: JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: bloco } }),
    },
  };
  fs.writeFileSync(arquivo, JSON.stringify(entrada) + '\n');
}
function linhaDoAlvo(nome) {
  const d = new DatabaseSync(caminhoDb, { readOnly: true });
  try {
    const row = d.prepare('SELECT conteudo, projeto, criada_em FROM observacoes WHERE id = ?').get(alvos[nome]);
    return formatarObservacao(row, null);
  } finally { d.close(); }
}

let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}
const vazioSaiu0 = (r) => r.codigo === 0 && r.saida === '';

// ---- casos ----
caso('injeta com cabecalho e no maximo 3 linhas', () => {
  const r = rodar(payload({ session_id: 'sessao-a' }));
  const ctx = contexto(r.saida);
  const linhas = linhasDe(ctx);
  return r.codigo === 0 && ctx.startsWith('## Memória do assunto') && linhas.length >= 1 && linhas.length <= 3 &&
    linhas.every((l) => l.startsWith('['));
});
caso('segunda chamada na mesma sessao nao repete o que ja serviu', () => {
  const r1 = rodar(payload({ session_id: 'sessao-b' }));
  const r2 = rodar(payload({ session_id: 'sessao-b' }));
  const l1 = linhasDe(contexto(r1.saida));
  const l2 = linhasDe(contexto(r2.saida));
  const r3 = rodar(payload({ session_id: 'sessao-b' }));
  return l1.length === 3 && l2.length === 1 && l2.every((l) => !l1.includes(l)) && vazioSaiu0(r3);
});
caso('sessao diferente recebe de novo', () => {
  const a = rodar(payload({ session_id: 'sessao-c1' }));
  const b = rodar(payload({ session_id: 'sessao-c2' }));
  return linhasDe(contexto(a.saida)).length === 3 && linhasDe(contexto(b.saida)).length === 3;
});
caso('primeira chamada nao repete o que a abertura serviu (semeia do transcrito)', () => {
  const transcrito = path.join(tmp, 'sessao-d.jsonl');
  const servida = linhaDoAlvo('Alfa');
  transcritoComAbertura(transcrito, [servida]);
  const r = rodar(payload({ session_id: 'sessao-d', transcript_path: transcrito }));
  const linhas = linhasDe(contexto(r.saida));
  return linhas.length === 3 && !linhas.includes(servida) && !/Alfa/.test(linhas.join('\n'));
});
caso('arquivo da sessao so tem ids (inclui o semeado pela abertura)', () => {
  const arq = path.join(raiz, 'memoria-assunto', 'sessao-d.json');
  const dado = JSON.parse(fs.readFileSync(arq, 'utf8'));
  return Array.isArray(dado) && dado.length === 4 && dado.every((n) => Number.isInteger(n)) &&
    dado.includes(alvos.Alfa) && !/[A-Za-z]/.test(fs.readFileSync(arq, 'utf8'));
});
caso('pedido sem acerto grava o arquivo da sessao e o segundo nao rele o transcrito', () => {
  const grande = path.join(tmp, 'sessao-m.jsonl');
  const servida = linhaDoAlvo('Alfa');
  transcritoComAbertura(grande, [servida]);
  const enchimento = JSON.stringify({ type: 'user', message: { role: 'user', content: 'x'.repeat(1000) } }) + '\n';
  const bloco = enchimento.repeat(1000); // ~1 MB
  for (let i = 0; i < 40; i++) fs.appendFileSync(grande, bloco);
  if (fs.statSync(grande).size < 40 * 1000 * 1000) return false;
  const arq = path.join(raiz, 'memoria-assunto', 'sessao-m.json');
  const semAcerto = { session_id: 'sessao-m', transcript_path: grande, prompt: 'qual a previsao do tempo amanha cedo' };
  const t1 = Date.now();
  const r1 = rodar(payload(semAcerto));
  const d1 = Date.now() - t1;
  const existeApos1 = fs.existsSync(arq);
  const t2 = Date.now();
  const r2 = rodar(payload(semAcerto));
  const d2 = Date.now() - t2;
  console.log('  tempos (ms): 1a=' + d1 + ' 2a=' + d2);
  const ids = existeApos1 ? JSON.parse(fs.readFileSync(arq, 'utf8')) : [];
  const r3 = rodar(payload({ session_id: 'sessao-m', transcript_path: grande }));
  const linhas3 = linhasDe(contexto(r3.saida));
  return vazioSaiu0(r1) && vazioSaiu0(r2) && d1 < 1500 && d2 < 1500 && existeApos1 &&
    ids.includes(alvos.Alfa) && linhas3.length === 3 && !linhas3.includes(servida);
});
caso('pedido que comeca por barra nao injeta', () => vazioSaiu0(rodar(payload({ session_id: 'sessao-e', prompt: '/zarquon flibbertigibbet quasar reconciliacao' }))));
caso('pedido curto (menos de 3 termos uteis) nao injeta', () => vazioSaiu0(rodar(payload({ session_id: 'sessao-f', prompt: 'zarquon flibbertigibbet' }))));
caso('pedido sem assunto no corpus nao injeta', () => vazioSaiu0(rodar(payload({ session_id: 'sessao-g', prompt: 'qual a previsao do tempo amanha cedo' }))));
caso('banco ausente sai 0 e calado', () => {
  const vazia = path.join(tmp, 'raiz-sem-banco');
  fs.mkdirSync(vazia);
  return vazioSaiu0(rodar(payload({ session_id: 'sessao-h' }), { raizAmbiente: vazia }));
});
caso('banco travado sai 0 e calado', () => {
  const trava = new DatabaseSync(caminhoDb);
  try {
    trava.exec('BEGIN EXCLUSIVE');
    let travou = false;
    const leitor = new DatabaseSync(caminhoDb, { readOnly: true });
    try { leitor.prepare('SELECT COUNT(*) FROM observacoes').get(); } catch (e) { travou = /locked|busy/i.test(e.message); }
    try { leitor.close(); } catch (e) { /* ja fechado */ }
    if (!travou) return false; // sem trava efetiva o caso nao prova nada
    return vazioSaiu0(rodar(payload({ session_id: 'sessao-i' })));
  } finally {
    try { trava.exec('ROLLBACK'); } catch (e) { /* melhor esforco */ }
    trava.close();
  }
});
caso('stdin invalido sai 0 e calado', () => vazioSaiu0(rodar('isto nao e json {')) && vazioSaiu0(rodar('')));
caso('transcrito ausente na primeira chamada sai 0 e calado', () =>
  vazioSaiu0(rodar(payload({ session_id: 'sessao-j', transcript_path: path.join(tmp, 'fantasma.jsonl') }))));
caso('session_id fora do padrao nao escreve fora da raiz e sai calado', () => {
  const r = rodar(payload({ session_id: '../fuga' }));
  return vazioSaiu0(r) && !fs.existsSync(path.join(raiz, 'fuga.json')) && !fs.existsSync(path.join(tmp, 'fuga.json'));
});

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforco */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
