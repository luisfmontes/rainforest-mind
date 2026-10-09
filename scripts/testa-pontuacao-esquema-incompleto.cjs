#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria da pontuacao com o esquema de uso incompleto (D6 de
 * docs/rainforest/design/2026-10-09-assunto-regua.md; tarefa 8 do plano
 * docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * O defeito: se o `ALTER TABLE` da migracao pegou BUSY, a coluna `canal` (ou as de buscas) nao
 * nasceu, o INSERT seguinte falha com "no column named canal" -- que nao casa `ehBancoOcupado` --
 * e a sessao era marcada como falha definitiva, saindo da fila para sempre. Agora a passada
 * confere o esquema na entrada e devolve a fila inteira como adiada, sem marcar nenhuma.
 *
 * A caixa nasce do `criarSchema` real e e rebaixada ao formato legado (como em
 * testa-esquema-ocupado.cjs). Os transcritos sao a fixture real utilidade/transcrito-sessao.jsonl
 * copiada. Tudo em pasta temporaria; nunca toca ~/.rainforest. Nenhum caso le o texto do fonte.
 *
 * Uso: node scripts/testa-pontuacao-esquema-incompleto.cjs
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const { abrirBanco, criarSchema } = require(path.join(SRC, 'scripts', 'memoria.cjs'));
const { pontuarSessoesPendentes } = require(path.join(SRC, 'scripts', 'lib', 'utilidade.cjs'));
const FIXTURE = path.join(SRC, 'scripts', 'fixtures', 'utilidade', 'transcrito-sessao.jsonl');

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

const raiz = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-pontuacao-incompleta-')));

// Caixa com 3 sessoes pendentes na marca_dagua (transcritos reais copiados), nenhuma pontuada.
function montarCaixa(nome, { legado }) {
  const dir = path.join(raiz, nome);
  fs.mkdirSync(dir, { recursive: true });
  const caminhoDb = path.join(dir, 'rainforest.db');
  const db = abrirBanco(caminhoDb);
  criarSchema(db);
  if (legado) {
    db.exec('DROP TABLE uso_memoria');
    db.exec(`CREATE TABLE uso_memoria (
      origem TEXT NOT NULL, ref_id INTEGER NOT NULL, sessao TEXT NOT NULL,
      servida INTEGER NOT NULL, nota REAL, pontuada_em TEXT NOT NULL,
      UNIQUE(origem, ref_id, sessao))`);
    db.exec('DROP TABLE uso_memoria_sessoes');
    db.exec('CREATE TABLE uso_memoria_sessoes (sessao TEXT PRIMARY KEY, pontuada_em TEXT NOT NULL)');
  }
  const ins = db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)');
  const n = nome === 'ocupada' ? 1 : 3;
  for (let i = 0; i < n; i++) {
    const arquivo = path.join(dir, `t${i}.jsonl`);
    fs.copyFileSync(FIXTURE, arquivo);
    ins.run('fixture-utilidade-proj', `sessao-${nome}-${i}`, arquivo, 100, 100, `2026-10-09T00:00:0${i}.000Z`);
  }
  return { dir, caminhoDb, db };
}
const contar = (db, sql) => db.prepare(sql).get().n;

// ---- esquema legado: a fila inteira fica para a proxima passada ----
const legado = montarCaixa('legado', { legado: true });

caso('uso_memoria sem canal: a fila inteira fica para a proxima passada', () => {
  const r = pontuarSessoesPendentes(legado.db);
  assert.deepStrictEqual(
    { pontuadas: r.pontuadas, falharam: r.falharam, adiadas: r.adiadas, total: r.total },
    { pontuadas: 0, falharam: 0, adiadas: 3, total: 3 }
  );
  assert.strictEqual(contar(legado.db, 'SELECT COUNT(*) n FROM uso_memoria_sessoes'), 0, 'nenhuma sessao pode ser marcada');
});

caso('uso_memoria_sessoes sem as colunas de buscas tambem adia (esquema parcial)', () => {
  // canal presente, buscas ausentes
  legado.db.exec("ALTER TABLE uso_memoria ADD COLUMN canal TEXT NOT NULL DEFAULT 'abertura'");
  const r = pontuarSessoesPendentes(legado.db);
  assert.deepStrictEqual({ pontuadas: r.pontuadas, falharam: r.falharam, adiadas: r.adiadas }, { pontuadas: 0, falharam: 0, adiadas: 3 });
  assert.strictEqual(contar(legado.db, 'SELECT COUNT(*) n FROM uso_memoria_sessoes'), 0);
});

caso('depois de criarSchema a mesma fila e pontuada e gravada', () => {
  criarSchema(legado.db);
  const r = pontuarSessoesPendentes(legado.db);
  assert.deepStrictEqual({ pontuadas: r.pontuadas, falharam: r.falharam, adiadas: r.adiadas }, { pontuadas: 3, falharam: 0, adiadas: 0 });
  assert.strictEqual(contar(legado.db, 'SELECT COUNT(*) n FROM uso_memoria_sessoes'), 3);
});
legado.db.close();

// ---- caso vizinho legitimo: esquema completo e banco ocupado continua adiando 1, sem marcar ----
const ocupada = montarCaixa('ocupada', { legado: false });
caso('esquema completo com banco ocupado segue adiando a sessao, sem marcar', () => {
  const trava = new DatabaseSync(ocupada.caminhoDb);
  trava.exec('PRAGMA journal_mode = WAL;');
  trava.exec('BEGIN IMMEDIATE');
  try {
    const r = pontuarSessoesPendentes(ocupada.db);
    assert.deepStrictEqual({ pontuadas: r.pontuadas, falharam: r.falharam, adiadas: r.adiadas }, { pontuadas: 0, falharam: 0, adiadas: 1 });
    assert.strictEqual(contar(ocupada.db, 'SELECT COUNT(*) n FROM uso_memoria_sessoes'), 0);
  } finally {
    trava.exec('ROLLBACK');
    trava.close();
  }
});
ocupada.db.close();

try {
  fs.rmSync(raiz, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
