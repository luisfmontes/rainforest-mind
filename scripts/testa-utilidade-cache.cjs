#!/usr/bin/env node
'use strict';
/**
 * Bateria do cache de acharAlvo (#509; design docs/rainforest/design/2026-10-13-timeout-memoria-assunto).
 *
 * Caixa SQLite criada numa pasta temporaria pelo criarSchema REAL de scripts/memoria.cjs.
 * As linhas servidas saem do formatador REAL (formatarObservacao, o mesmo que acharAlvo usa),
 * nas tres formas (com apelido, cru com TETO_LINHA_ASSUNTO, cru) e a de um resumo.
 * Nunca toca ~/.rainforest. Nenhum caso le o texto do fonte.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const memoria = require(path.join(SRC, 'scripts', 'memoria.cjs'));
const { formatarObservacao } = require(path.join(SRC, 'hooks', 'lib', 'memoria-sessao.cjs'));
const { acharAlvo, resumoComoPseudoObservacao } = require(path.join(SRC, 'scripts', 'lib', 'utilidade.cjs'));

const TETO_ASSUNTO = 300;
const DIA = '2026-09-15';
const CRIADA_EM = `${DIA}T12:00:00.000Z`;
const PROJETOS = ['C--Projetos-alfa', 'C--Projetos-beta', 'C--Projetos-gama'];
const APELIDOS = { 'C--Projetos-alfa': 'alfa', 'C--Projetos-beta': 'beta', 'C--Projetos-gama': 'gama' };

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

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-utilidade-cache-'));
let db;
try {
  db = new DatabaseSync(path.join(tmp, 'memoria.db'));
  memoria.criarSchema(db);

  const inserirObs = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  for (let i = 0; i < 14; i++) {
    // Titulo acima de 300 caracteres em parte das linhas: so assim a forma "cru com teto" difere da "cru",
    // e uma chave de memo de formatacao que ignore o teto devolveria a forma errada.
    const longo = i % 3 === 2 ? ' ' + 'detalhe longo do titulo '.repeat(15) : '';
    const titulo = `Observacao ${i} sobre assunto distinto numero ${i}${longo}`;
    const corpo = `# ${titulo}\n\nSubtitulo da observacao ${i}\n\nCorpo com algum texto para a linha.`;
    inserirObs.run(PROJETOS[i % PROJETOS.length], corpo, CRIADA_EM, `origem-${i}`);
  }
  db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)').run(
    PROJETOS[0],
    'Resumo do dia de teste',
    'Conteudo do resumo do dia para a bateria de cache.',
    CRIADA_EM
  );

  const obsRows = db.prepare('SELECT id, projeto, conteudo, criada_em FROM observacoes ORDER BY id').all();
  const resumoRow = db.prepare('SELECT id, projeto, titulo, conteudo, criada_em FROM resumos').get();

  // Linhas servidas: as tres formas de observacao e a do resumo, geradas pelo formatador real.
  const linhas = obsRows.map((row, i) => {
    if (i % 3 === 0) return formatarObservacao(row, APELIDOS);
    if (i % 3 === 1) return formatarObservacao(row, null, TETO_ASSUNTO);
    return formatarObservacao(row, null);
  });
  linhas.push(formatarObservacao(resumoComoPseudoObservacao(resumoRow), APELIDOS));
  assert.strictEqual(linhas.length, 15, 'esperava 14 observacoes e 1 resumo');
  const linhasObs = linhas.slice(0, 14);

  // Contador de SQL: envolve prepare da instancia so durante o caso, e restaura ao fim.
  function contandoObsLike(conexao, fn) {
    const contador = { obs: 0 };
    const original = conexao.prepare;
    conexao.prepare = function (sql) {
      if (sql.includes('FROM observacoes WHERE criada_em LIKE')) contador.obs++;
      return original.call(this, sql);
    };
    try {
      fn();
    } finally {
      conexao.prepare = original;
    }
    return contador.obs;
  }

  caso('14 linhas do mesmo dia com cache fazem no maximo 3 consultas LIKE em observacoes', () => {
    const cache = new Map();
    const n = contandoObsLike(db, () => {
      for (const linha of linhasObs) acharAlvo(db, linha, APELIDOS, cache);
    });
    assert.ok(n <= 3, `consultas LIKE com cache: ${n} (esperava <= 3)`);
  });

  caso('controle: 14 linhas sem cache fazem 42 consultas LIKE em observacoes', () => {
    const n = contandoObsLike(db, () => {
      for (const linha of linhasObs) acharAlvo(db, linha, APELIDOS);
    });
    assert.strictEqual(n, 42, `consultas LIKE sem cache: ${n}`);
  });

  caso('com e sem cache devolvem o mesmo alvo, linha a linha, e todo alvo nao-nulo', () => {
    const cache = new Map();
    const comCache = linhas.map((linha) => acharAlvo(db, linha, APELIDOS, cache));
    const semCache = linhas.map((linha) => acharAlvo(db, linha, APELIDOS));
    comCache.forEach((alvo, i) => {
      assert.ok(alvo, `linha ${i} sem alvo: ${linhas[i]}`);
      assert.deepStrictEqual(alvo, semCache[i], `linha ${i} difere entre com e sem cache`);
    });
    assert.strictEqual(comCache[14].origem, 'resumo', 'a linha do resumo devia achar o resumo');
  });

  caso('linha que nao casa devolve null com e sem cache', () => {
    const cache = new Map();
    const naoCasa = `[${DIA}] linha inventada que nao existe no banco`;
    assert.strictEqual(acharAlvo(db, naoCasa, APELIDOS, cache), null);
    assert.strictEqual(acharAlvo(db, naoCasa, APELIDOS), null);
  });
} finally {
  try {
    if (db) db.close();
  } catch {
    // limpeza best-effort
  }
  try {
    fs.rmSync(tmp, { recursive: true, force: true });
  } catch {
    // limpeza best-effort: pasta temporaria
  }
}
console.log(`${ok} ok, ${falhou} falha(s)`);
process.exit(falhou === 0 ? 0 : 1);
