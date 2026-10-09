#!/usr/bin/env node
'use strict';
/**
 * Bateria de scripts/importar-claude-mem.cjs na gravação do projeto canônico (#435, D10).
 *
 * Caixa hermética: destino e origem numa pasta de mkdtemp, RFM_ROOT explícito para o
 * processo filho e nenhuma leitura de ~/.rainforest nem ~/.claude-mem. O importador roda
 * como processo filho, com cwd num repositório git real, para que o canônico do cwd
 * seja o de verdade. Nenhum caso lê o texto do fonte.
 *
 * Uso: node scripts/testa-importar-canonico.cjs
 * Exit: 0 com "0 falha(s)"; 1 com falha.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const IMPORTADOR = path.join(__dirname, 'importar-claude-mem.cjs');
const { abrirBanco, abrirBancoSomenteLeitura, criarSchema } = require(path.join(__dirname, 'memoria.cjs'));
const { slugDoCaminho } = require(path.join(__dirname, 'lib', 'projeto-canonico.cjs'));

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

const base = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'importar-canonico-')));
const caixa = path.join(base, 'caixa');
const caminhoDb = path.join(caixa, 'rainforest.db');
const origem = path.join(base, 'origem-claude-mem.db');
const repo = path.join(base, 'gama');

function linhasOrigemMapa() {
  const c = abrirBancoSomenteLeitura(caminhoDb);
  if (!c) throw new Error('nao abriu o banco de destino');
  try {
    const mapa = new Map();
    for (const r of c.prepare('SELECT projeto, origem FROM observacoes').all()) mapa.set(r.origem, r.projeto);
    return mapa;
  } finally {
    c.close();
  }
}

function contarLinhas() {
  const c = abrirBancoSomenteLeitura(caminhoDb);
  if (!c) throw new Error('nao abriu o banco de destino');
  try {
    return c.prepare('SELECT COUNT(*) AS n FROM observacoes').get().n;
  } finally {
    c.close();
  }
}

try {
  // Destino: schema real e três linhas já gravadas, como numa caixa de uso.
  fs.mkdirSync(caixa, { recursive: true });
  const destino = abrirBanco(caminhoDb);
  criarSchema(destino);
  const semente = destino.prepare(
    'INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)'
  );
  semente.run('C--Projetos-alfa', 'semente do alfa', '2026-10-01T00:00:00Z', 'seed:alfa');
  semente.run('C--A-comum', 'semente do comum A', '2026-10-01T00:00:00Z', 'seed:comum-a');
  semente.run('C--B-comum', 'semente do comum B', '2026-10-01T00:00:00Z', 'seed:comum-b');
  destino.close();

  // Origem: forma real do claude-mem (tabela observations), uma linha por caso.
  const o = new DatabaseSync(origem);
  o.exec(`CREATE TABLE observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT, memory_session_id TEXT, project TEXT,
    text TEXT NOT NULL, type TEXT, title TEXT, subtitle TEXT, facts TEXT, narrative TEXT,
    concepts TEXT, files_read TEXT, files_modified TEXT, prompt_number INTEGER,
    created_at TEXT NOT NULL, created_at_epoch INTEGER, content_hash TEXT, agent_type TEXT
  );`);
  const ins = o.prepare('INSERT INTO observations (project, text, created_at, content_hash) VALUES (?, ?, ?, ?)');
  ins.run('grupo/alfa', 'obs do grupo alfa', '2026-09-01T10:00:00Z', 'h-grupo-alfa');
  ins.run('alfa', 'obs do alfa simples', '2026-09-01T10:00:00Z', 'h-alfa');
  ins.run('omega', 'obs do omega orfao', '2026-09-01T10:00:00Z', 'h-omega');
  ins.run('comum', 'obs do comum ambiguo', '2026-09-01T10:00:00Z', 'h-comum');
  ins.run(null, 'obs sem projeto', '2026-09-01T10:00:00Z', 'h-sem-projeto');
  o.close();

  // Repositório git real: o canônico do cwd sai daqui.
  fs.mkdirSync(repo, { recursive: true });
  execFileSync('git', ['init', '-q'], { cwd: repo, stdio: ['ignore', 'pipe', 'pipe'] });

  const env = { ...process.env, RFM_ROOT: caixa, TESTADOR_ORIGEM_CLAUDE_MEM: origem };
  delete env.CLAUDE_PROJECT_DIR;
  const importar = () =>
    spawnSync(process.execPath, [IMPORTADOR], {
      cwd: repo,
      env,
      encoding: 'utf8',
      timeout: 120000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

  const primeira = importar();
  const porOrigemDepois1 = linhasOrigemMapa();

  caso('primeira importacao sai 0 e grava as 5 observacoes', () => {
    assert.strictEqual(primeira.status, 0, `exit ${primeira.status}: ${primeira.stderr}`);
    assert.match(primeira.stdout, /importadas: 5, duplicadas \(já existentes\): 0/);
  });

  caso('projeto relativo com barra casa o slug canonico unico', () => {
    assert.strictEqual(porOrigemDepois1.get('claude-mem:1:h-grupo-alfa'), 'C--Projetos-alfa');
  });

  caso('valor simples casa o slug canonico unico', () => {
    assert.strictEqual(porOrigemDepois1.get('claude-mem:2:h-alfa'), 'C--Projetos-alfa');
  });

  caso('nome sem correspondencia fica como esta (ultimo segmento)', () => {
    assert.strictEqual(porOrigemDepois1.get('claude-mem:3:h-omega'), 'omega');
  });

  caso('nome ambiguo entre dois canonicos fica como esta', () => {
    assert.strictEqual(porOrigemDepois1.get('claude-mem:4:h-comum'), 'comum');
  });

  caso('observacao sem project grava no canonico do cwd, nao no nome curto', () => {
    const esperado = slugDoCaminho(repo);
    assert.strictEqual(porOrigemDepois1.get('claude-mem:5:h-sem-projeto'), esperado);
    assert.notStrictEqual(esperado, 'gama');
  });

  caso('linhas que ja estavam no destino seguem como estavam', () => {
    assert.strictEqual(porOrigemDepois1.get('seed:alfa'), 'C--Projetos-alfa');
    assert.strictEqual(porOrigemDepois1.get('seed:comum-a'), 'C--A-comum');
    assert.strictEqual(porOrigemDepois1.get('seed:comum-b'), 'C--B-comum');
  });

  const segunda = importar();
  caso('segunda importacao sai 0, grava 0 e conta as 5 como duplicadas', () => {
    assert.strictEqual(segunda.status, 0, `exit ${segunda.status}: ${segunda.stderr}`);
    assert.match(segunda.stdout, /importadas: 0, duplicadas \(já existentes\): 5/);
    assert.strictEqual(contarLinhas(), 8, 'destino deveria ter 3 semeadas + 5 importadas');
  });
} catch (e) {
  falhou++;
  console.log(`FALHOU  preparo da caixa\n  ${String(e.message).split('\n')[0]}`);
} finally {
  try {
    fs.rmSync(base, { recursive: true, force: true, maxRetries: 3 });
  } catch {
    // limpeza best-effort: pasta temporária da própria bateria
  }
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou === 0 ? 0 : 1);
