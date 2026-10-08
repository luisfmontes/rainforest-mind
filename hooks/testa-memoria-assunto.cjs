#!/usr/bin/env node
'use strict';
// Bateria hermética de hooks/lib/memoria-assunto.cjs. Banco temporário com o
// criarSchema REAL; nenhum caso lê o texto do fonte.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { LIMIAR_BM25, construirQueryAssunto, buscarPorAssunto, montarBlocoAssunto } = require('./lib/memoria-assunto.cjs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-memoria-assunto-'));
const caminho = path.join(tmp, 'teste.db');
const db = new DatabaseSync(caminho);
criarSchema(db);

let seq = 0;
function inserir(projeto, conteudo, extra = {}) {
  seq += 1;
  const r = db.prepare(
    'INSERT INTO observacoes (projeto, conteudo, criada_em, origem, consolidada_em, substituida_por) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(projeto, conteudo, '2026-10-01T10:00:00.000Z', 'o' + seq, extra.consolidada || null, extra.substituida || null);
  return Number(r.lastInsertRowid);
}
function limpar() { db.exec('DELETE FROM observacoes'); }

const PERMISSIVO = 1e9; // aceita qualquer bm25: isola o que cada caso mede
let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}
const ids = (r) => r.map((x) => x.id);

caso('memoria ja servida na sessao nao volta', () => {
  limpar();
  const a = inserir('p1', 'Zebrafish pipeline\n\nzebrafish pipeline detalhes');
  const b = inserir('p1', 'Zebrafish outro\n\nzebrafish outro detalhes');
  const r = buscarPorAssunto(db, 'zebrafish', { projetoAtual: 'p1', jaServidos: new Set([a]), limiar: PERMISSIVO });
  return ids(r).length === 1 && ids(r)[0] === b;
});
caso('teto de 3 memorias', () => {
  limpar();
  for (let i = 0; i < 6; i++) inserir('p1', 'Quokka ' + i + '\n\nquokka assunto ' + i);
  return buscarPorAssunto(db, 'quokka', { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO }).length === 3;
});
caso('consolidada nao volta', () => {
  limpar();
  inserir('p1', 'Narval\n\nnarval consolidada', { consolidada: '2026-10-02T00:00:00Z' });
  return buscarPorAssunto(db, 'narval', { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO }).length === 0;
});
caso('substituida nao volta', () => {
  limpar();
  const nova = inserir('p1', 'Okapi nova\n\nokapi nova');
  inserir('p1', 'Okapi velha\n\nokapi velha', { substituida: nova });
  const r = buscarPorAssunto(db, 'okapi', { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO });
  return r.length === 1 && r[0].id === nova;
});
caso('bm25 acima do limiar nao entra', () => {
  limpar();
  inserir('p1', 'Axolote\n\naxolote regenera');
  const sem = buscarPorAssunto(db, 'axolote', { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO });
  const padrao = buscarPorAssunto(db, 'axolote', { projetoAtual: 'p1', jaServidos: new Set() });
  return LIMIAR_BM25 === -16 && sem.length === 1 && sem[0].bm25 > LIMIAR_BM25 && padrao.length === 0;
});
caso('texto sem termo util devolve vazio', () => {
  limpar();
  inserir('p1', 'Qualquer\n\ncoisa');
  const o = { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO };
  return buscarPorAssunto(db, '', o).length === 0 && buscarPorAssunto(db, '!!! ??? ---', o).length === 0;
});
caso('empate de relevancia: projeto atual primeiro', () => {
  limpar();
  const outro = inserir('p-outro', 'Capivara\n\ncapivara rio');
  const atual = inserir('p-atual', 'Capivara\n\ncapivara rio');
  const r = buscarPorAssunto(db, 'capivara', { projetoAtual: 'p-atual', jaServidos: new Set(), limiar: PERMISSIVO });
  return r.length === 2 && r[0].bm25 === r[1].bm25 && r[0].id === atual && r[1].id === outro;
});
caso('dois projetos aparecem (busca nao filtra por projeto)', () => {
  limpar();
  inserir('p-a', 'Tucano a\n\ntucano bico');
  inserir('p-b', 'Tucano b\n\ntucano bico grande');
  const r = buscarPorAssunto(db, 'tucano', { projetoAtual: 'p-a', jaServidos: new Set(), limiar: PERMISSIVO });
  return new Set(r.map((x) => x.projeto)).size === 2;
});
caso('bloco comeca por cabecalho e cabe em 1500 bytes', () => {
  const linhas = [];
  for (let i = 0; i < 40; i++) {
    linhas.push({ id: i, projeto: 'p1', criada_em: '2026-10-01T10:00:00.000Z', bm25: -20,
      conteudo: 'Titulo longo da memoria numero ' + i + ' com acentuação ção\n\n' + 'subtitulo '.repeat(20) });
  }
  const bloco = montarBlocoAssunto(linhas);
  const partes = bloco.split('\n');
  return bloco.startsWith('## Memória do assunto') && Buffer.byteLength(bloco, 'utf8') <= 1500 &&
    partes.length > 1 && partes.slice(1).every((p) => p.startsWith('['));
});
caso('lista vazia vira string vazia', () => montarBlocoAssunto([]) === '');
// Corpus do briefing longo: 150 palavras medias (cada uma em 80 de 200 memorias, idf baixo) +
// 2 alvos de termos raros. Com o limiar REAL: 30 termos medios somam < 16 (nao entra), mas os
// 150 somariam bem mais (entraria) — por isso o caso mede o LIMITE_TERMOS.
function corpusBriefingLongo() {
  limpar();
  const palavras = [];
  for (let i = 0; i < 150; i++) palavras.push('termo' + i + 'comum');
  for (let i = 0; i < 80; i++) inserir('p1', 'Registro amplo ' + i + '\n\n' + palavras.join(' '));
  for (let i = 0; i < 118; i++) inserir('p1', 'Nota curta ' + i + '\n\nnada a ver aqui ' + i);
  const alvo = inserir('p2', 'Reconciliacao zarquon\n\n' + 'zarquon flibbertigibbet quasar '.repeat(6));
  inserir('p2', 'Outro assunto\n\nbananeira jabuticaba ' + 'bananeira jabuticaba '.repeat(3));
  return { briefing: palavras.join(' '), alvo };
}
caso('briefing longo de termos comuns, sem termo raro de nenhum alvo, devolve vazio', () => {
  const { briefing } = corpusBriefingLongo();
  const o = { projetoAtual: 'p1', jaServidos: new Set() };
  return buscarPorAssunto(db, briefing, o).length === 0 &&
    // o corpus e valido: os 150 termos, sem corte, passariam do limiar (o limite de termos e que impede)
    buscarPorAssunto(db, briefing, { ...o, limiar: PERMISSIVO }).length > 0;
});
caso('o mesmo briefing com um termo raro de um alvo acha o alvo', () => {
  const { briefing, alvo } = corpusBriefingLongo();
  const r = buscarPorAssunto(db, briefing + ' zarquon flibbertigibbet', { projetoAtual: 'p1', jaServidos: new Set() });
  return ids(r).includes(alvo);
});
caso('construirQueryAssunto: 30 termos mais raros, df 0 fora, desempate estavel', () => {
  limpar();
  inserir('p1', 'a\n\nraroum raroum comum1 comum1 comum2');
  inserir('p1', 'b\n\ncomum1 comum2');
  inserir('p1', 'c\n\ncomum1');
  const q = construirQueryAssunto(db, 'comum1 comum2 raroum inexistente comum1');
  if (q !== '"raroum" OR "comum2" OR "comum1"') return false;
  const muitos = [];
  for (let i = 0; i < 40; i++) { inserir('p1', 'm' + i + '\n\nlote' + i); muitos.push('lote' + i); }
  const q2 = construirQueryAssunto(db, muitos.join(' '));
  return q2.split(' OR ').length === 30 && q2.startsWith('"lote0"') && construirQueryAssunto(db, 'so inexistentes') === null;
});
caso('FTS ausente devolve vazio sem lancar', () => {
  const nu = new DatabaseSync(':memory:');
  try {
    return buscarPorAssunto(nu, 'qualquer assunto', { projetoAtual: 'p1', jaServidos: new Set(), limiar: PERMISSIVO }).length === 0;
  } finally { nu.close(); }
});

db.close();
try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforço */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
