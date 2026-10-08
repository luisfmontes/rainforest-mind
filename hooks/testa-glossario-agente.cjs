#!/usr/bin/env node
'use strict';
// Bateria hermetica do glossario no hook do subagente (hooks/memoria-assunto-agente.cjs, PreToolUse Agent).
// Cada caso roda o hook como processo filho recebendo no stdin o payload no formato do Agent real
// (tool_input com description, subagent_type, model, run_in_background e prompt; session_id; cwd;
// hook_event_name). Repos de caixa sao criados com `git init` em diretorio temporario; a raiz de dados
// vem de RFM_ROOT. Nenhum caso escreve fora do temporario.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

const HOOK = path.join(__dirname, 'memoria-assunto-agente.cjs');
const PORTARIA = path.join(__dirname, 'portaria.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-glossario-agente-'));

const GLOSSARIO = [
  '# Glossário do repo',
  '',
  '## fluxo',
  'Definição: sequência de estágios que uma demanda percorre até o PR.',
  'Onde mora: hooks/lib/estado.cjs, campo estado.',
  'Cenário: a branch fluxo/x passa de design a fechar antes do merge.',
  'Evite: esteira',
  '',
].join('\n');

function criarRepo(nome, comGlossario) {
  const dir = path.join(tmp, nome);
  fs.mkdirSync(dir);
  execFileSync('git', ['init', '-q', dir], { stdio: 'ignore' });
  if (comGlossario) fs.writeFileSync(path.join(dir, 'GLOSSARIO.md'), GLOSSARIO);
  return dir;
}

const caixa = criarRepo('caixa-com-glossario', true);
const caixaSem = criarRepo('caixa-sem-glossario', false);

const raizVazia = path.join(tmp, 'raiz-vazia');
fs.mkdirSync(raizVazia);

// Raiz com banco, para o caso em que a memoria tambem casa.
const raizComBanco = path.join(tmp, 'raiz-com-banco');
fs.mkdirSync(raizComBanco);
const db = new DatabaseSync(path.join(raizComBanco, 'rainforest.db'));
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 400; i++) {
  ins.run('projeto-teste', 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-10-01T10:00:00.000Z', 'f' + i);
}
let n = 0;
for (const nome of ['Alfa', 'Bravo', 'Charlie', 'Delta']) {
  ins.run(
    nome === 'Alfa' ? 'projeto-teste' : 'outro-projeto',
    'Reconciliacao ' + nome + ' zarquon flibbertigibbet\n\n' + ('zarquon flibbertigibbet zarquon flibbertigibbet quasar ' + nome + ' ').repeat(3),
    '2026-10-0' + (2 + n++) + 'T10:00:00.000Z', 'alvo-' + nome);
}
db.close();

const transcrito = path.join(tmp, 'sem-abertura.jsonl');
fs.writeFileSync(transcrito, JSON.stringify({ type: 'user', message: { role: 'user', content: 'oi' } }) + '\n');

const PEDIDO_ESTEIRA = 'Instrucao: refaca a esteira de contratos e responda.\nFIM-DO-BRIEFING';
const PEDIDO_MEMORIA = 'Instrucao: investigue a reconciliacao zarquon flibbertigibbet quasar e responda.\nFIM-DO-BRIEFING';
const PEDIDO_SEM_TERMO = 'qual a previsao do tempo amanha cedo';

function spawnar(alvo, stdin, raizAmbiente = raizVazia) {
  const env = { ...process.env, RFM_ROOT: raizAmbiente };
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync(process.execPath, [alvo], { input: stdin, env, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr };
}
const rodar = (stdin, raizAmbiente) => spawnar(HOOK, stdin, raizAmbiente);

function entradaAgente(prompt, extra) {
  return Object.assign({
    description: 'Refazer o briefing', subagent_type: 'general-purpose',
    model: 'haiku', run_in_background: false, prompt,
  }, extra);
}
function payload(o) {
  const { prompt = PEDIDO_ESTEIRA, extraEntrada, ...resto } = o;
  return JSON.stringify(Object.assign({
    session_id: 'sessao-padrao', transcript_path: transcrito, cwd: caixa,
    hook_event_name: 'PreToolUse', tool_name: 'Agent', tool_input: entradaAgente(prompt, extraEntrada),
  }, resto));
}
function saidaJson(saida) { return JSON.parse(saida).hookSpecificOutput; }
const BLOCO_GLOSSARIO_LINHA = '- **fluxo**: sequência de estágios que uma demanda percorre até o PR. | onde mora: hooks/lib/estado.cjs, campo estado. | cenário: a branch fluxo/x passa de design a fechar antes do merge. | evite: esteira';

let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}
const vazioSaiu0 = (r) => r.codigo === 0 && r.saida === '';

// ---- casos ----
caso('briefing com termo do glossario ganha o verbete no fim do prompt', () => {
  const r = rodar(payload({ session_id: 'sessao-a' }), raizVazia);
  if (r.codigo !== 0 || !r.saida) return false;
  const p = saidaJson(r.saida).updatedInput.prompt;
  const bloco = '## Glossário do repo\n' + BLOCO_GLOSSARIO_LINHA;
  return p === PEDIDO_ESTEIRA + '\n\n' + bloco && p.includes('**fluxo**');
});

caso('campos do tool_input (description, subagent_type, model, extras) ficam iguais; so prompt muda', () => {
  const extra = { campo_futuro: { a: [1, 2] }, isolation: 'worktree' };
  const r = rodar(payload({ session_id: 'sessao-b', extraEntrada: extra }), raizVazia);
  const h = saidaJson(r.saida);
  const u = h.updatedInput;
  const o = entradaAgente(PEDIDO_ESTEIRA, extra);
  return r.codigo === 0 && h.hookEventName === 'PreToolUse' &&
    u.description === o.description && u.subagent_type === o.subagent_type && u.model === o.model &&
    u.run_in_background === false && u.isolation === 'worktree' &&
    JSON.stringify(u.campo_futuro) === JSON.stringify(extra.campo_futuro) &&
    Object.keys(u).sort().join() === Object.keys(o).sort().join() &&
    !('permissionDecision' in h) && Object.keys(h).sort().join() === 'hookEventName,updatedInput';
});

caso('duas chamadas na mesma sessao recebem o mesmo bloco do glossario (sem deduplicacao)', () => {
  const r1 = rodar(payload({ session_id: 'sessao-c' }), raizVazia);
  const r2 = rodar(payload({ session_id: 'sessao-c' }), raizVazia);
  const p1 = saidaJson(r1.saida).updatedInput.prompt;
  const p2 = saidaJson(r2.saida).updatedInput.prompt;
  return p1 === p2 && p1.includes('**fluxo**');
});

caso('nao cria nem le <raiz>/memoria-assunto/*.glossario.json (arquivo pre-existente nao vira dedupe)', () => {
  const dirMem = path.join(raizVazia, 'memoria-assunto');
  fs.mkdirSync(dirMem, { recursive: true });
  const arq = path.join(dirMem, 'sessao-d.glossario.json');
  fs.writeFileSync(arq, JSON.stringify({ chaves: ['fluxo'] }));
  const antes = fs.readFileSync(arq, 'utf8');
  const r = rodar(payload({ session_id: 'sessao-d' }), raizVazia);
  const recebeu = r.codigo === 0 && saidaJson(r.saida).updatedInput.prompt.includes('**fluxo**');
  const soArquivos = fs.readdirSync(dirMem).filter(f => f.endsWith('.glossario.json'));
  return recebeu && fs.readFileSync(arq, 'utf8') === antes && soArquivos.join() === 'sessao-d.glossario.json';
});

caso('com banco: glossario antes da memoria; memoria fica por ultimo, separada por linha em branco', () => {
  const r = rodar(payload({ session_id: 'sessao-e', prompt: PEDIDO_MEMORIA + ' Tambem o fluxo.' }), raizComBanco);
  if (r.codigo !== 0 || !r.saida) return false;
  const p = saidaJson(r.saida).updatedInput.prompt;
  const iG = p.indexOf('\n\n## Glossário do repo');
  const iM = p.indexOf('\n\n## Memória do assunto');
  if (iG < 0 || iM < 0 || iG >= iM) return false;
  const entreBlocos = p.slice(iG + 2, iM);
  return entreBlocos.startsWith('## Glossário do repo\n') && entreBlocos.includes('**fluxo**') &&
    p.startsWith(PEDIDO_MEMORIA + ' Tambem o fluxo.\n\n## Glossário do repo\n') &&
    p.slice(iM + 2).split('\n').length >= 2;
});

caso('briefing sem termo do glossario sai vazio (sem banco)', () =>
  vazioSaiu0(rodar(payload({ session_id: 'sessao-f', prompt: PEDIDO_SEM_TERMO }), raizVazia)));

caso('repo sem GLOSSARIO.md sai vazio mesmo com o termo no briefing (sem banco)', () =>
  vazioSaiu0(rodar(payload({ session_id: 'sessao-g', cwd: caixaSem }), raizVazia)));

caso('tool_name diferente de Agent/Task nao injeta', () =>
  vazioSaiu0(rodar(payload({ session_id: 'sessao-h', tool_name: 'Bash' }), raizVazia)) &&
  vazioSaiu0(rodar(payload({ session_id: 'sessao-h', tool_name: 'Read' }), raizVazia)));

caso('stdin invalido sai 0 e calado', () =>
  vazioSaiu0(rodar('isto nao e json {', raizVazia)) && vazioSaiu0(rodar('', raizVazia)));

caso('session_id invalido sai 0 e calado (e nao escreve fora da raiz)', () => {
  const r = rodar(payload({ session_id: '../fuga' }), raizVazia);
  return vazioSaiu0(r) && !fs.existsSync(path.join(tmp, 'fuga.json'));
});

caso('portaria decide igual com o prompt original e com o prompt resultante', () => {
  const orig = payload({ session_id: 'sessao-i' });
  const r = rodar(orig, raizVazia);
  const atualizado = JSON.stringify(Object.assign(JSON.parse(orig), { tool_input: saidaJson(r.saida).updatedInput }));
  const p1 = spawnar(PORTARIA, orig);
  const p2 = spawnar(PORTARIA, atualizado);
  console.log('  portaria(original):     exit=' + p1.codigo + ' stdout=' + JSON.stringify(p1.saida));
  console.log('  portaria(updatedInput): exit=' + p2.codigo + ' stdout=' + JSON.stringify(p2.saida));
  return r.codigo === 0 && p1.codigo === p2.codigo && p1.saida === p2.saida;
});

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforco */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
