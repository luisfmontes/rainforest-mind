#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria da nota nula (D3 de docs/rainforest/design/2026-10-09-assunto-regua.md; tarefa 6 do
 * plano docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * A servida dos canais `pedido` e `subagente` cujos termos raros estavam TODOS no texto que
 * disparou a injecao nao tem como ser medida (o uso repetiria o pedido). Ela fica gravada com
 * `nota` nula, para o relatorio tira-la da conta e dizer quantas sairam. A abertura nao muda.
 *
 * Os transcritos sao MONTADOS a partir das linhas reais do harness (as mesmas fixtures de
 * testa-nota-do-pedido.cjs), trocando so o texto. Quem pontua e o `pontuarSessao` real, sobre
 * uma caixa de `criarSchema` real, em pasta temporaria. Nunca toca ~/.rainforest. Nenhum caso
 * le o texto do fonte.
 *
 * Uso: node scripts/testa-nota-nula.cjs
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

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-nota-nula-')));
const db = new DatabaseSync(path.join(tmp, 'rainforest.db'));
memoria.criarSchema(db);

// ---- banco: so termos comuns (df > LIMIAR_DF) + dois raros por memoria ----
const PROJ = 'proj-nula';
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
function memoriaNova(chave, raros, criada = '2026-10-05T12:00:00.000Z') {
  const conteudo = 'titulo corpusfiller\nsubtitulo corpusfiller ' + raros.join(' ');
  const id = Number(ins.run(PROJ, conteudo, criada, 'obs-' + chave).lastInsertRowid);
  return { id, conteudo, raros, linha: formatarObservacao({ conteudo, projeto: PROJ, criada_em: criada }, null) };
}
const M1 = memoriaNova('m1', ['zzfeixe', 'zzmanga']); // pedido: todos os raros no pedido
const M2 = memoriaNova('m2', ['zzcarro', 'zzroda']); // subagente: os dois no briefing
const M3 = memoriaNova('m3', ['zzvela', 'zzremo']); // so no bloco injetado (pai)
const M4 = memoriaNova('m4', ['zzpeixe', 'zzbarco']); // so no bloco injetado (filho sem pai)
const M5 = memoriaNova('m5', ['zzlua', 'zzsol']); // parcial
const M6 = memoriaNova('m6', ['zztrem', 'zzponte']); // abertura com os raros no pedido
// memoria sem nenhum termo raro: so palavras comuns do corpus
const COMUM = memoriaNova('comum', [], '2026-10-06T12:00:00.000Z');
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
function linhaTool(name, input) {
  const a = JSON.parse(PAI[0]);
  a.message.content = [{ ...a.message.content[0], name, input }];
  delete a.wireToolInputs;
  return JSON.stringify(a);
}
function linhasPai(briefingCitado, anexo) {
  const user = JSON.parse(PAI[2]);
  user.toolUseResult.prompt = user.toolUseResult.prompt.replace('linha do meio', () => briefingCitado).replace('MARCA-AGENTE-9c1', () => anexo);
  return [PAI[0], PAI[1], JSON.stringify(user)];
}
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

const BRIEFING_CARRO = 'Instrucao: revise o zzcarro e o zzroda e responda.';
let nulosEsperados = 0;

// ---- canal pedido ----
caso('memoria cujos raros estavam todos no pedido grava a linha com nota nula', () => {
  const f = escrever('t-pedido-nulo', [linhaUser('trate de zzfeixe zzmanga'), linhaPedido([M1.linha])]);
  const r = pontuar('s-pedido-nulo', f);
  assert.deepStrictEqual(r, [{ ref_id: M1.id, canal: 'pedido', nota: null }]);
  const linha = db.prepare("SELECT servida, canal, nota FROM uso_memoria WHERE sessao = 's-pedido-nulo'").get();
  assert.strictEqual(linha.servida, 1);
  assert.strictEqual(linha.canal, 'pedido');
  assert.strictEqual(linha.nota, null);
  nulosEsperados++;
});

caso('o Read posterior nao muda a nota nula do pedido', () => {
  const f = escrever('t-pedido-nulo-read', [
    linhaUser('trate de zzfeixe zzmanga'),
    linhaPedido([M1.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzfeixe.cjs' }),
  ]);
  const r = pontuar('s-pedido-nulo-read', f);
  assert.deepStrictEqual(r, [{ ref_id: M1.id, canal: 'pedido', nota: null }]);
  nulosEsperados++;
});

// ---- canal subagente ----
caso('subagente: os dois raros no briefing original dao nota nula', () => {
  const f = escrever('t-sub-nulo', [linhaUser('um pedido qualquer'), ...linhasPai(BRIEFING_CARRO, bloco([M2.linha]))]);
  escreverFilho(f, BRIEFING_CARRO, bloco([M2.linha]), 'cat zzcarro.cjs');
  const r = pontuar('s-sub-nulo', f);
  assert.deepStrictEqual(r, [{ ref_id: M2.id, canal: 'subagente', nota: null }]);
  nulosEsperados++;
});

caso('subagente: raros so no bloco injetado (caminho do pai) dao nota numerica, nao nula', () => {
  const f = escrever('t-sub-bloco-pai', [linhaUser('um pedido qualquer'), ...linhasPai('Instrucao: revise o resto e responda.', bloco([M3.linha]))]);
  escreverFilho(f, 'Instrucao: revise o resto e responda.', bloco([M3.linha]), 'cat nada.cjs');
  const r = pontuar('s-sub-bloco-pai', f);
  assert.deepStrictEqual(r, [{ ref_id: M3.id, canal: 'subagente', nota: 0 }]);
});

caso('subagente: raros so no bloco injetado (filho sem pai) dao nota numerica, nao nula', () => {
  const f = escrever('t-sub-bloco-solo', [linhaUser('um pedido qualquer')]);
  escreverFilho(f, 'Instrucao: revise o resto e responda.', bloco([M4.linha]), 'cat nada.cjs');
  const r = pontuar('s-sub-bloco-solo', f);
  assert.deepStrictEqual(r, [{ ref_id: M4.id, canal: 'subagente', nota: 0 }]);
});

// ---- sem termo raro nenhum (A10 / U2) ----
caso('memoria sem termo raro nenhum: nota nula no pedido e 0 na abertura', () => {
  const fp = escrever('t-comum-pedido', [linhaUser('trate de titulo corpusfiller'), linhaPedido([COMUM.linha])]);
  const rp = pontuar('s-comum-pedido', fp);
  assert.deepStrictEqual(rp, [{ ref_id: COMUM.id, canal: 'pedido', nota: null }]);
  nulosEsperados++;
  const fa = escrever('t-comum-abertura', [linhaSessionStart([COMUM.linha]), linhaUser('trate de titulo corpusfiller')]);
  const ra = pontuar('s-comum-abertura', fa);
  assert.deepStrictEqual(ra, [{ ref_id: COMUM.id, canal: 'abertura', nota: 0 }]);
});

// ---- parcial e abertura ----
caso('memoria com um raro no pedido e outro fora grava um numero', () => {
  const f = escrever('t-parcial', [
    linhaUser('revise o zzlua agora'),
    linhaPedido([M5.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzsol.cjs' }),
  ]);
  const r = pontuar('s-parcial', f);
  assert.deepStrictEqual(r, [{ ref_id: M5.id, canal: 'pedido', nota: 1 }]);
});

caso('abertura com os raros no pedido continua numerica (o desconto nao se aplica)', () => {
  const f = escrever('t-abertura', [
    linhaSessionStart([M6.linha]),
    linhaUser('revise o zztrem agora'),
    linhaTool('Read', { file_path: 'C:/repo/src/zztrem.cjs' }),
  ]);
  const r = pontuar('s-abertura', f);
  assert.deepStrictEqual(r, [{ ref_id: M6.id, canal: 'abertura', nota: 0.5 }]);
});

// ---- esquema e total ----
caso('gravarUso aceita nota null e a coluna segue REAL nula (sem migracao)', () => {
  const col = db.prepare('PRAGMA table_info(uso_memoria)').all().find((c) => c.name === 'nota');
  assert.strictEqual(col.type, 'REAL');
  assert.strictEqual(col.notnull, 0);
});

caso('o total de servidas nulas da caixa e o dos casos nulos da bateria', () => {
  const n = db.prepare('SELECT count(*) c FROM uso_memoria WHERE servida = 1 AND nota IS NULL').get().c;
  assert.strictEqual(n, nulosEsperados);
  assert.strictEqual(nulosEsperados, 4);
});

caso('calcularNota: 3 argumentos nunca devolve null', () => {
  assert.strictEqual(U.calcularNota(db, 'titulo corpusfiller', 'titulo'), 0);
  assert.strictEqual(U.calcularNota(db, M6.conteudo, 'zztrem'), 0.5);
  assert.strictEqual(U.calcularNota(db, M6.conteudo, 'zztrem', 'zztrem zzponte'), null);
});

db.close();
try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
