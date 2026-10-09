#!/usr/bin/env node
'use strict';
/**
 * Bateria de `criarSchema` com banco ocupado (#436, D6, tarefa 4).
 *
 * Monta, numa pasta temporária, um banco de caixa legado (`uso_memoria` sem
 * `canal`, `uso_memoria_sessoes` sem as 3 colunas de buscas) e segura outra
 * conexão em `BEGIN IMMEDIATE`. Prova o efeito: o BUSY do `ALTER` sobe até o
 * chamador (que o trata como transitório) em vez de ser engolido, e "coluna
 * duplicada" continua sendo ok. Nenhuma linha vai para ~/.rainforest: RFM_ROOT
 * e CLAUDE_CONFIG_DIR apontam para a pasta temporária.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SRC = path.resolve(__dirname, '..');
const HOOK = path.join(SRC, 'hooks', 'memoria-marca.cjs');
const { abrirBanco, criarSchema } = require(path.join(SRC, 'scripts', 'memoria.cjs'));
// Mesmo predicado de ehBancoOcupado (scripts/lib/utilidade.cjs), que nao e exportado.
function ehBancoOcupado(e) {
  return Boolean(e) && e.code === 'ERR_SQLITE_ERROR' && /database is (locked|busy)/.test(String(e.message || ''));
}

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHOU  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const raiz = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'esquema-ocupado-')));
const caminhoDb = path.join(raiz, 'rainforest.db');

// Banco legado: esquema real, depois as duas tabelas recriadas na forma antiga.
function montarLegado() {
  const db = abrirBanco(caminhoDb);
  try {
    criarSchema(db);
    db.exec('DROP TABLE uso_memoria');
    db.exec(`CREATE TABLE uso_memoria (
      origem TEXT NOT NULL, ref_id INTEGER NOT NULL, sessao TEXT NOT NULL,
      servida INTEGER NOT NULL, nota REAL, pontuada_em TEXT NOT NULL,
      UNIQUE(origem, ref_id, sessao))`);
    db.exec('CREATE INDEX IF NOT EXISTS idx_uso_memoria_sessao ON uso_memoria(sessao)');
    db.exec('DROP TABLE uso_memoria_sessoes');
    db.exec('CREATE TABLE uso_memoria_sessoes (sessao TEXT PRIMARY KEY, pontuada_em TEXT NOT NULL)');
    db.exec(`INSERT INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES ('S1', '2026-10-01T00:00:00.000Z')`);
    db.exec(`INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES
      ('observacao', 1, 'S1', 1, 0.5, '2026-10-01T00:00:00.000Z'),
      ('observacao', 2, 'S1', 1, 0.0, '2026-10-01T00:00:00.000Z')`);
  } finally {
    db.close();
  }
}

function colunas(tabela) {
  const db = abrirBanco(caminhoDb);
  try {
    return db.prepare(`PRAGMA table_info(${tabela})`).all().map((c) => c.name);
  } finally {
    db.close();
  }
}

function contar(sql) {
  const db = abrirBanco(caminhoDb);
  try {
    return db.prepare(sql).get().n;
  } finally {
    db.close();
  }
}

function chamarCriarSchema() {
  const db = abrirBanco(caminhoDb);
  try {
    criarSchema(db);
  } finally {
    db.close();
  }
}

let erroPreparo = null;
let trava = null;
try {
  montarLegado();
} catch (e) {
  erroPreparo = e;
}

caso('preparo: banco legado montado sem as 4 colunas', () => {
  if (erroPreparo) throw erroPreparo;
  assert.ok(!colunas('uso_memoria').includes('canal'));
  assert.deepStrictEqual(colunas('uso_memoria_sessoes'), ['sessao', 'pontuada_em']);
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria'), 2);
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria_sessoes'), 1);
});

// Trava: outra conexão segura o lock de escrita.
trava = abrirBanco(caminhoDb);
trava.exec('BEGIN IMMEDIATE');

caso('uso_memoria legado com banco ocupado: criarSchema lanca em vez de engolir', () => {
  let lancou = null;
  try {
    chamarCriarSchema();
  } catch (e) {
    lancou = e;
  }
  assert.ok(lancou, 'criarSchema deveria lancar com o banco ocupado');
  assert.ok(ehBancoOcupado(lancou), `erro deveria ser banco ocupado: ${lancou.code} ${lancou.message}`);
});

caso('banco ocupado: colunas seguem ausentes e as 3 linhas antigas intactas', () => {
  // A leitura passa por cima da trava (WAL: leitor nao bloqueia).
  assert.ok(!colunas('uso_memoria').includes('canal'));
  const sessoes = colunas('uso_memoria_sessoes');
  for (const nome of ['buscas_principal', 'buscas_subagente', 'subagentes']) assert.ok(!sessoes.includes(nome), nome);
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria'), 2);
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria_sessoes'), 1);
});

caso('hook real memoria-marca com banco ocupado: sai 0 e calado', () => {
  const dirProj = path.join(raiz, 'projects', 'C--Projetos-alfa');
  fs.mkdirSync(dirProj, { recursive: true });
  const transcrito = path.join(dirProj, 'S1.jsonl');
  fs.writeFileSync(transcrito, JSON.stringify({ type: 'user', message: { role: 'user', content: 'oi' } }) + '\n');
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({ session_id: 'S1', transcript_path: transcrito, cwd: dirProj, hook_event_name: 'Stop' }),
    env: { ...process.env, RFM_ROOT: raiz, CLAUDE_CONFIG_DIR: raiz },
    encoding: 'utf8',
    timeout: 60000,
  });
  assert.strictEqual(r.status, 0, `status ${r.status} stderr ${r.stderr}`);
  assert.strictEqual(r.stdout, '');
  assert.strictEqual(r.stderr, '');
});

try { trava.exec('ROLLBACK'); } catch (_) { /* trava ja solta */ }
try { trava.close(); } catch (_) { /* idem */ }

caso('depois do ROLLBACK: criarSchema cria as 4 colunas e as linhas antigas leem abertura', () => {
  chamarCriarSchema();
  assert.ok(colunas('uso_memoria').includes('canal'));
  const sessoes = colunas('uso_memoria_sessoes');
  for (const nome of ['buscas_principal', 'buscas_subagente', 'subagentes']) assert.ok(sessoes.includes(nome), nome);
  assert.strictEqual(contar(`SELECT COUNT(*) AS n FROM uso_memoria WHERE canal = 'abertura'`), 2);
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria_sessoes'), 1);
});

caso('terceira chamada nao lanca: coluna duplicada segue sendo engolida', () => {
  chamarCriarSchema();
  assert.strictEqual(contar('SELECT COUNT(*) AS n FROM uso_memoria'), 2);
});

// #460: migrações 1 (marca_dagua.offset_processado) e 4 (observacoes.consolidada_em).
// Banco próprio: esquema completo, depois a coluna da migração removida.
function bancoSem(nome, tabela, coluna) {
  const arq = path.join(raiz, nome);
  const db = abrirBanco(arq);
  try {
    criarSchema(db);
    if (tabela) db.exec(`ALTER TABLE ${tabela} DROP COLUMN ${coluna}`);
  } finally {
    db.close();
  }
  return arq;
}
function colunasDe(arq, tabela) {
  const db = abrirBanco(arq);
  try {
    return db.prepare(`PRAGMA table_info(${tabela})`).all().map((c) => c.name);
  } finally {
    db.close();
  }
}
// Roda criarSchema com outra conexão segurando BEGIN IMMEDIATE; devolve o erro (ou null).
function criarSchemaTravado(arq) {
  const t = abrirBanco(arq);
  t.exec('BEGIN IMMEDIATE');
  try {
    const db = abrirBanco(arq);
    try {
      criarSchema(db);
      return null;
    } catch (e) {
      return e;
    } finally {
      db.close();
    }
  } finally {
    try { t.exec('ROLLBACK'); } catch (_) { /* solta */ }
    t.close();
  }
}

for (const [tabela, coluna] of [['marca_dagua', 'offset_processado'], ['observacoes', 'consolidada_em']]) {
  caso(`#460: ${tabela} sem ${coluna} com banco ocupado: criarSchema lanca banco ocupado`, () => {
    const arq = bancoSem(`sem-${coluna}.db`, tabela, coluna);
    assert.ok(!colunasDe(arq, tabela).includes(coluna), 'preparo: coluna deveria faltar');
    const e = criarSchemaTravado(arq);
    assert.ok(e, 'criarSchema deveria lancar com o banco ocupado');
    assert.ok(ehBancoOcupado(e), `erro deveria ser banco ocupado: ${e.code} ${e.message}`);
    assert.ok(!colunasDe(arq, tabela).includes(coluna), 'coluna nao pode nascer com o banco ocupado');
    const db = abrirBanco(arq);
    try { criarSchema(db); } finally { db.close(); }
    assert.ok(colunasDe(arq, tabela).includes(coluna), 'depois da trava a coluna nasce');
  });
}

// Guarda de regressão: hoje passa com ou sem o PRAGMA antes do ALTER (o SQLite acusa a
// coluna duplicada antes de pedir a trava). Fica para pegar o dia em que isso mudar.
caso('#460: banco ja migrado com outra conexao escrevendo: criarSchema nao lanca', () => {
  const arq = bancoSem('completo.db', null, null);
  const e = criarSchemaTravado(arq);
  assert.strictEqual(e, null, e && `${e.code} ${e.message}`);
});

try { fs.rmSync(raiz, { recursive: true, force: true }); } catch (_) { /* limpeza best-effort */ }

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
