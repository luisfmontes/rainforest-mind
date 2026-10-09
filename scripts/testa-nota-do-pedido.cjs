#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria da nota do canal do assunto sem a tautologia do pedido (D2 de
 * docs/rainforest/design/2026-10-09-assunto-regua.md; tarefa 5 do plano
 * docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * O defeito: o `Read` do arquivo que o pedido citou repete os termos raros do pedido, e a
 * memoria ganhava nota sem ter sido usada. Com o texto do pedido (canal `pedido`) ou o
 * briefing cortado antes do bloco injetado (canal `subagente`), a nota mede so o que NAO
 * estava ali. A abertura nao muda.
 *
 * Os transcritos sao MONTADOS a partir das linhas reais do harness:
 *   - memoria-assunto/prompt-submit.jsonl  (attachment hook_additional_context)
 *   - memoria-assunto/agente-pai.jsonl     (assistant com tool_use; user com toolUseResult.prompt)
 *   - memoria-assunto/agente-filho.jsonl   (primeira linha user do filho)
 *   - utilidade/transcrito-sessao.jsonl    (SessionStart, prompt do usuario)
 * trocando so o texto. Quem pontua e o `pontuarSessao` real, sobre uma caixa criada pelo
 * `criarSchema` real, em pasta temporaria. Nunca toca ~/.rainforest. Nenhum caso le o texto
 * do fonte.
 *
 * Uso: node scripts/testa-nota-do-pedido.cjs
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const memoria = require(path.join(SRC, 'scripts', 'memoria.cjs'));
const { formatarObservacao } = require(path.join(SRC, 'hooks', 'lib', 'memoria-sessao.cjs'));
const U = require(path.join(SRC, 'scripts', 'lib', 'utilidade.cjs'));

const FIX = path.join(SRC, 'scripts', 'fixtures');
const lerLinhas = (f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
const PEDIDO = lerLinhas(path.join(FIX, 'memoria-assunto', 'prompt-submit.jsonl'))[0];
const PAI = lerLinhas(path.join(FIX, 'memoria-assunto', 'agente-pai.jsonl'));
const FILHO = lerLinhas(path.join(FIX, 'memoria-assunto', 'agente-filho.jsonl'))[0];
const SINT = lerLinhas(path.join(FIX, 'utilidade', 'transcrito-sessao.jsonl')).map((l) => JSON.parse(l));
const SESSION_START = SINT.find((o) => o.type === 'attachment' && o.attachment.hookEvent === 'SessionStart');
const USER_PROMPT = SINT.find((o) => o.type === 'user' && typeof o.message.content === 'string');
const AGENT_ID = JSON.parse(PAI[2]).toolUseResult.agentId;

assert.ok(PEDIDO.includes('MARCA-ASSUNTO-7f3'), 'fixture prompt-submit sem a marca');
assert.ok(PAI[2].includes('MARCA-AGENTE-9c1') && FILHO.includes('MARCA-AGENTE-9c1'), 'fixture de agente sem a marca');
assert.ok(JSON.parse(PAI[2]).toolUseResult.prompt.includes('linha do meio'), 'fixture de agente sem a linha do meio');

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHA  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-nota-do-pedido-')));
const db = new DatabaseSync(path.join(tmp, 'rainforest.db'));
memoria.criarSchema(db);

// ---- banco: so termos comuns (df > LIMIAR_DF) + dois raros por memoria ----
const PROJ = 'proj-nota';
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
function memoriaNova(chave, raros) {
  const conteudo = 'titulo corpusfiller\nsubtitulo corpusfiller ' + raros.join(' ');
  const criada = '2026-10-05T12:00:00.000Z';
  const id = Number(ins.run(PROJ, conteudo, criada, 'obs-' + chave).lastInsertRowid);
  return { id, conteudo, raros, linha: formatarObservacao({ conteudo, projeto: PROJ, criada_em: criada }, null) };
}
const M1 = memoriaNova('m1', ['zzfeixe', 'zzmanga']);
const M2 = memoriaNova('m2', ['zzcarro', 'zzroda']);
const M3 = memoriaNova('m3', ['zzvela', 'zzremo']);
const M4 = memoriaNova('m4', ['zzpeixe', 'zzbarco']);
const M5 = memoriaNova('m5', ['zzlua', 'zzsol']);
const M6 = memoriaNova('m6', ['zztrem', 'zzponte']);
for (let i = 0; i < 4; i++) {
  ins.run(PROJ, 'titulo corpusfiller\nsubtitulo corpusfiller fillerrarox' + i, '2026-10-01T09:0' + i + ':00.000Z', 'filler-' + i);
}

// ---- montagem de transcritos a partir das fixtures reais ----
const esc = (s) => JSON.stringify(s).slice(1, -1);
const bloco = (linhas) => '## Memória do assunto\n' + linhas.join('\n') + '\n';
const blocoAbertura = (linhas) => '## Memória (corpus residentes)\n' + linhas.join('\n') + '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"';

function linhaSessionStart(linhas) {
  const o = JSON.parse(JSON.stringify(SESSION_START));
  o.attachment.stdout = JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: blocoAbertura(linhas) } });
  return JSON.stringify(o);
}
function linhaUser(texto) {
  const o = JSON.parse(JSON.stringify(USER_PROMPT));
  o.message.content = texto;
  return JSON.stringify(o);
}
function linhaPedido(linhas) {
  return PEDIDO.split('contexto de teste MARCA-ASSUNTO-7f3 fim').join(esc(bloco(linhas)));
}
// linha assistant real (a do pai) com um unico tool_use; so name e input mudam
function linhaTool(name, input) {
  const a = JSON.parse(PAI[0]);
  a.message.content = [{ ...a.message.content[0], name, input }];
  delete a.wireToolInputs;
  return JSON.stringify(a);
}
// pai real: user/toolUseResult.prompt recebe o briefing citado + o bloco no lugar da marca
function linhasPai(briefingCitado, anexo) {
  const user = JSON.parse(PAI[2]);
  user.toolUseResult.prompt = user.toolUseResult.prompt.replace('linha do meio', () => briefingCitado).replace('MARCA-AGENTE-9c1', () => anexo);
  return [PAI[0], PAI[1], JSON.stringify(user)];
}
// filho real: primeira linha user com o briefing citado + o anexo; opcionalmente um tool_use do filho
function escreverFilho(transcrito, briefingCitado, anexo, toolFilho) {
  const dir = transcrito.replace(/\.jsonl$/, '') + '/subagents';
  fs.mkdirSync(dir, { recursive: true });
  const f = JSON.parse(FILHO);
  f.message.content = f.message.content.replace('linha do meio', () => briefingCitado).replace('MARCA-AGENTE-9c1', () => anexo);
  const saida = [JSON.stringify(f)];
  if (toolFilho !== null) {
    const a = JSON.parse(linhaTool('Bash', { command: toolFilho }));
    a.isSidechain = true;
    a.agentId = AGENT_ID;
    saida.push(JSON.stringify(a));
  }
  fs.writeFileSync(path.join(dir, 'agent-' + AGENT_ID + '.jsonl'), saida.join('\n') + '\n');
}
function escrever(nome, linhas) {
  const f = path.join(tmp, nome + '.jsonl');
  fs.writeFileSync(f, linhas.join('\n') + '\n');
  return f;
}

// grava via pontuarSessao real e devolve a(s) linha(s) servida(s) do uso_memoria
function pontuar(sessao, f) {
  db.prepare('DELETE FROM uso_memoria WHERE sessao = ?').run(sessao);
  U.pontuarSessao(db, sessao, f);
  return db.prepare('SELECT ref_id, canal, nota FROM uso_memoria WHERE sessao = ? AND servida = 1 ORDER BY ref_id').all(sessao).map((r) => ({ ...r }));
}
// a nota de antes (3 argumentos) sobre o texto que o canal usa, para mostrar a tautologia
function notaBase(f, canal, memoriaAlvo) {
  const s = U.extrairSessao(f).servidasCanal.find((x) => x.canal === canal);
  return U.calcularNota(db, memoriaAlvo.conteudo, s.texto);
}

// ---- canal pedido ----
caso('Read do arquivo que o pedido citou nao pontua a memoria', () => {
  const f = escrever('t-pedido-read', [
    linhaUser('revise o zzfeixe agora'),
    linhaPedido([M1.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzfeixe.cjs' }),
  ]);
  const base = notaBase(f, 'pedido', M1);
  const r = pontuar('s-pedido-read', f);
  assert.strictEqual(base, 0.5, 'a base (3 argumentos) deveria ser 0,5, veio ' + base);
  assert.deepStrictEqual(r, [{ ref_id: M1.id, canal: 'pedido', nota: 0 }]);
});

caso('segundo pedido que cita o outro raro da nota 1', () => {
  const f = escrever('t-pedido-seg', [
    linhaUser('revise o zzfeixe agora'),
    linhaPedido([M1.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzfeixe.cjs' }),
    linhaUser('agora olhe o zzmanga'),
  ]);
  const base = notaBase(f, 'pedido', M1);
  const r = pontuar('s-pedido-seg', f);
  assert.strictEqual(base, 1, 'a base deveria ser 1, veio ' + base);
  assert.deepStrictEqual(r, [{ ref_id: M1.id, canal: 'pedido', nota: 1 }]);
});

caso('tool_use posterior com o raro que o pedido nao citou da nota 1', () => {
  const f = escrever('t-pedido-tool', [
    linhaUser('revise o zzfeixe agora'),
    linhaPedido([M1.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzmanga.cjs' }),
  ]);
  const r = pontuar('s-pedido-tool', f);
  assert.deepStrictEqual(r, [{ ref_id: M1.id, canal: 'pedido', nota: 1 }]);
});

// ---- canal subagente ----
const BRIEFING_CARRO = 'Instrucao: revise o zzcarro e responda.';

caso('subagente: so o termo do briefing no tool_use do filho nao pontua', () => {
  const f = escrever('t-sub-carro', [linhaUser('um pedido qualquer'), ...linhasPai(BRIEFING_CARRO, bloco([M2.linha]))]);
  escreverFilho(f, BRIEFING_CARRO, bloco([M2.linha]), 'cat zzcarro.cjs');
  const base = notaBase(f, 'subagente', M2);
  const r = pontuar('s-sub-carro', f);
  assert.strictEqual(base, 0.5, 'a base deveria ser 0,5, veio ' + base);
  assert.deepStrictEqual(r, [{ ref_id: M2.id, canal: 'subagente', nota: 0 }]);
});

caso('subagente: o termo que so veio no bloco injetado e usado pelo filho pontua', () => {
  const f = escrever('t-sub-roda', [linhaUser('um pedido qualquer'), ...linhasPai(BRIEFING_CARRO, bloco([M2.linha]))]);
  escreverFilho(f, BRIEFING_CARRO, bloco([M2.linha]), 'cat zzroda.cjs');
  const base = notaBase(f, 'subagente', M2);
  const r = pontuar('s-sub-roda', f);
  assert.strictEqual(base, 0.5, 'a base deveria ser 0,5, veio ' + base);
  assert.deepStrictEqual(r, [{ ref_id: M2.id, canal: 'subagente', nota: 1 }]);
});

caso('subagente sem o pai (so o agent-<id>.jsonl) desconta o mesmo briefing cortado', () => {
  const briefing = 'Instrucao: revise o zzpeixe e responda.';
  const f = escrever('t-sub-solo', [linhaUser('um pedido qualquer')]);
  escreverFilho(f, briefing, bloco([M4.linha]), 'cat zzbarco.cjs');
  const r = pontuar('s-sub-solo', f);
  assert.deepStrictEqual(r, [{ ref_id: M4.id, canal: 'subagente', nota: 1 }]);
  const g = escrever('t-sub-solo2', [linhaUser('um pedido qualquer')]);
  escreverFilho(g, briefing, bloco([M4.linha]), 'cat zzpeixe.cjs');
  const r2 = pontuar('s-sub-solo2', g);
  assert.deepStrictEqual(r2, [{ ref_id: M4.id, canal: 'subagente', nota: 0 }]);
});

caso('briefing e cortado no glossario do repo, que vem antes da memoria do assunto', () => {
  const glossario = '## Glossário do repo\n- zzlua: termo do glossario que o filho usa\n\n';
  const anexo = glossario + bloco([M5.linha]);
  const f = escrever('t-sub-glos', [linhaUser('um pedido qualquer'), ...linhasPai('Instrucao: revise o zzsol e responda.', anexo)]);
  escreverFilho(f, 'Instrucao: revise o zzsol e responda.', anexo, 'cat zzlua.cjs');
  const r = pontuar('s-sub-glos', f);
  assert.deepStrictEqual(r, [{ ref_id: M5.id, canal: 'subagente', nota: 1 }]);
});

// ---- abertura e compatibilidade ----
caso('abertura mantem a nota de antes (o desconto nao se aplica)', () => {
  const f = escrever('t-abertura', [
    linhaSessionStart([M3.linha]),
    linhaUser('revise o zzvela agora'),
    linhaTool('Read', { file_path: 'C:/repo/src/zzvela.cjs' }),
  ]);
  const base = notaBase(f, 'abertura', M3);
  const r = pontuar('s-abertura', f);
  assert.strictEqual(base, 0.5, 'a base deveria ser 0,5, veio ' + base);
  assert.deepStrictEqual(r, [{ ref_id: M3.id, canal: 'abertura', nota: 0.5 }]);
});

caso('calcularNota de 3 argumentos devolve o mesmo numero de antes', () => {
  const a = U.calcularNota(db, M6.conteudo, 'zztrem');
  const b = U.calcularNota(db, M6.conteudo, 'zztrem zzponte');
  const c = U.calcularNota(db, M6.conteudo, 'nada a ver');
  const d = U.calcularNota(db, M6.conteudo, 'zztrem', undefined);
  assert.deepStrictEqual([a, b, c, d], [0.5, 1, 0, 0.5]);
  // com o pedido citando um raro, so o outro conta
  assert.strictEqual(U.calcularNota(db, M6.conteudo, 'zztrem', 'zztrem'), 0);
  assert.strictEqual(U.calcularNota(db, M6.conteudo, 'zztrem zzponte', 'zztrem'), 1);
  // e sem nenhum termo raro a nota segue 0
  assert.strictEqual(U.calcularNota(db, 'titulo corpusfiller', 'titulo', 'x'), 0);
});

db.close();
try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
