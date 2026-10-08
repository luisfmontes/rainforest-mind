#!/usr/bin/env node
'use strict';
// Bateria do desempate por projeto atual em hooks/lib/memoria-assunto.cjs, com a
// caixa do slug diferente da caixa gravada em observacoes.projeto. Banco temporário
// com o criarSchema REAL; nenhum caso lê o texto do fonte. Não toca ~/.rainforest.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { buscarPorAssunto } = require('./lib/memoria-assunto.cjs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-peso-projeto-atual-'));
const db = new DatabaseSync(path.join(tmp, 'teste.db'));
criarSchema(db);

let seq = 0;
function inserir(projeto, conteudo) {
  seq += 1;
  const r = db.prepare(
    'INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)'
  ).run(projeto, conteudo, '2026-10-01T10:00:00.000Z', 'o' + seq);
  return Number(r.lastInsertRowid);
}
// Enchimento: o teto de df é fração do total de vivas; sem ele, todo termo do alvo passa do teto
// e a consulta vira null. Mesmo padrão de testa-memoria-assunto.cjs.
const ENCHIMENTO = 1000;
function limpar() {
  db.exec('DELETE FROM observacoes');
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  db.exec('BEGIN');
  for (let i = 0; i < ENCHIMENTO; i++) ins.run('enchimento', 'Fundo ' + i + '\n\nenchimento' + i + ' fundo' + i, '2026-10-01T10:00:00.000Z', 'f' + i);
  db.exec('COMMIT');
}

const PERMISSIVO = 1e9; // aceita qualquer bm25: isola o desempate que cada caso mede
const TEXTO = 'pendulo ressonante';
const CONTEUDO = 'Pendulo\n\npendulo ressonante amortecido';
let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}

// Duas observações de conteúdo idêntico (mesmo bm25): beta com id MENOR, alfa com id maior.
function corpusBetaAlfa() {
  limpar();
  const beta = inserir('C--Projetos-beta', CONTEUDO);
  const alfa = inserir('C--Projetos-Alfa', CONTEUDO);
  return { beta, alfa };
}

caso('desempate favorece o projeto atual mesmo com a caixa do slug diferente', () => {
  const { beta, alfa } = corpusBetaAlfa();
  const r = buscarPorAssunto(db, TEXTO, { projetoAtual: 'c--projetos-alfa', jaServidos: new Set(), max: 3, limiar: PERMISSIVO });
  return r.length === 2 && r[0].bm25 === r[1].bm25 && r[0].id === alfa && r[1].id === beta;
});

caso('projetoAtual igual em caixa: mesma ordem', () => {
  const { beta, alfa } = corpusBetaAlfa();
  const r = buscarPorAssunto(db, TEXTO, { projetoAtual: 'C--Projetos-Alfa', jaServidos: new Set(), max: 3, limiar: PERMISSIVO });
  return r.length === 2 && r[0].bm25 === r[1].bm25 && r[0].id === alfa && r[1].id === beta;
});

db.close();
try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforço */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
