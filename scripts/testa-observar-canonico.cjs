#!/usr/bin/env node
'use strict';
/**
 * Bateria do gravador `observar` com projeto canônico (#435; design
 * docs/rainforest/design/2026-10-08-projeto-canonico.md, D7 e D8).
 *
 * Monta, numa pasta temporária, o que o harness faz: a mesma sessão `S1` em
 * `projects/C--Projetos-alfa` (principal) e em `projects/C--Projetos-alfa--claude-worktrees-w1`
 * (worktree). Cada pasta recebe sua marca pelo hook REAL `hooks/memoria-marca.cjs`,
 * e o gravador roda sem argumentos com o dublê de LLM. Nenhuma linha vai para
 * ~/.rainforest: RFM_ROOT e CLAUDE_CONFIG_DIR apontam para a pasta temporária.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SRC = path.resolve(__dirname, '..');
const HOOK = path.join(SRC, 'hooks', 'memoria-marca.cjs');
const OBSERVAR = path.join(SRC, 'scripts', 'observar.cjs');
const DUBLIADOR = path.join(SRC, 'scripts', 'dubliador-llm-ok.cjs');
const { abrirBanco } = require(path.join(SRC, 'scripts', 'memoria.cjs'));

const PASTA_PRINCIPAL = 'C--Projetos-alfa';
const PASTA_WORKTREE = 'C--Projetos-alfa--claude-worktrees-w1';
const SESSAO = 'S1';

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

const raiz = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'observar-canonico-')));
const ambiente = {
  ...process.env,
  RFM_ROOT: raiz,
  CLAUDE_CONFIG_DIR: raiz,
  TESTADOR_CHAMAR_LLM: DUBLIADOR,
};

const eventos = [
  {
    type: 'user',
    message: { role: 'user', content: 'Qual eh o capital da Franca?' },
    timestamp: '2026-10-08T10:00:00Z',
    sessionId: SESSAO,
    version: '2.1.0',
    cwd: 'alfa',
  },
  {
    type: 'assistant',
    message: { role: 'assistant', content: [{ type: 'text', text: 'O capital eh Paris' }] },
    timestamp: '2026-10-08T10:00:01Z',
    sessionId: SESSAO,
    version: '2.1.0',
    cwd: 'alfa',
  },
];
const conteudoTranscrito = eventos.map((e) => JSON.stringify(e)).join('\n') + '\n';

function transcritoDe(pasta) {
  const dir = path.join(raiz, 'projects', pasta);
  fs.mkdirSync(dir, { recursive: true });
  const arquivo = path.join(dir, `${SESSAO}.jsonl`);
  fs.writeFileSync(arquivo, conteudoTranscrito);
  return arquivo;
}

function rodarHookStop(arquivo, pasta) {
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({ session_id: SESSAO, transcript_path: arquivo, cwd: pasta }),
    env: ambiente,
    encoding: 'utf8',
    timeout: 60000,
  });
}

function rodarObservar() {
  return spawnSync(process.execPath, [OBSERVAR], {
    input: '',
    env: ambiente,
    encoding: 'utf8',
    timeout: 120000,
  });
}

function consultar(sql) {
  const db = abrirBanco(path.join(raiz, 'rainforest.db'));
  try {
    return db.prepare(sql).all();
  } finally {
    db.close();
  }
}

// Preparo: uma execução só, compartilhada pelas asserções abaixo.
const tamanho = Buffer.byteLength(conteudoTranscrito, 'utf8');
let erroPreparo = null;
let hookPrincipal = null;
let hookWorktree = null;
let obs1 = null;
let obs2 = null;
try {
  const arqPrincipal = transcritoDe(PASTA_PRINCIPAL);
  const arqWorktree = transcritoDe(PASTA_WORKTREE);
  hookPrincipal = rodarHookStop(arqPrincipal, path.join(raiz, 'projects', PASTA_PRINCIPAL));
  hookWorktree = rodarHookStop(arqWorktree, path.join(raiz, 'projects', PASTA_WORKTREE));
  obs1 = rodarObservar();
  obs2 = rodarObservar();
} catch (e) {
  erroPreparo = e;
}

function exigirPreparo() {
  if (erroPreparo) throw erroPreparo;
}

caso('hook Stop real grava uma marca em cada pasta de transcritos', () => {
  exigirPreparo();
  assert.strictEqual(hookPrincipal.status, 0, `hook principal saiu ${hookPrincipal.status}`);
  assert.strictEqual(hookWorktree.status, 0, `hook worktree saiu ${hookWorktree.status}`);
  const marcas = consultar('SELECT projeto, sessao, offset FROM marca_dagua ORDER BY projeto');
  assert.deepStrictEqual(
    marcas.map((m) => [m.projeto, m.sessao, m.offset]),
    [
      [PASTA_PRINCIPAL, SESSAO, tamanho],
      [PASTA_WORKTREE, SESSAO, tamanho],
    ]
  );
});

caso('mesma sessao na pasta principal e na de worktree com o mesmo offset grava duas linhas', () => {
  exigirPreparo();
  assert.strictEqual(obs1.status, 0, `observar saiu ${obs1.status}: ${obs1.stderr}`);
  const linhas = consultar('SELECT projeto, origem FROM observacoes ORDER BY origem');
  assert.strictEqual(linhas.length, 2, `esperado 2 observacoes, veio ${linhas.length}`);
  assert.ok(
    linhas.every((l) => l.projeto === PASTA_PRINCIPAL),
    `projeto deveria ser o canonico ${PASTA_PRINCIPAL}, veio ${JSON.stringify(linhas)}`
  );
  assert.deepStrictEqual(
    linhas.map((l) => l.origem).sort(),
    [`sessao:${SESSAO}:offset:${tamanho}`, `sessao:${SESSAO}:wt:w1:offset:${tamanho}`].sort()
  );
});

caso('as duas marcas avancam ate o offset e mantem o nome da pasta (D8)', () => {
  exigirPreparo();
  const marcas = consultar(
    'SELECT projeto, offset, offset_processado FROM marca_dagua ORDER BY projeto'
  );
  assert.deepStrictEqual(
    marcas.map((m) => [m.projeto, m.offset, m.offset_processado]),
    [
      [PASTA_PRINCIPAL, tamanho, tamanho],
      [PASTA_WORKTREE, tamanho, tamanho],
    ]
  );
});

caso('segunda execucao do gravador nao grava linha nova', () => {
  exigirPreparo();
  assert.strictEqual(obs2.status, 0, `segunda execucao saiu ${obs2.status}: ${obs2.stderr}`);
  const total = consultar('SELECT COUNT(*) AS n FROM observacoes')[0].n;
  assert.strictEqual(total, 2, `esperado 2 observacoes apos a segunda execucao, veio ${total}`);
});

try {
  fs.rmSync(raiz, { recursive: true, force: true });
} catch {
  // limpeza best-effort da pasta temporaria
}

// Issue #452, item 1: a migracao do #435 manteve a origem sem `:wt:` quando nao havia
// colisao, entao a linha (C--Projetos-alfa, sessao:S2:offset:N) pode ja existir quando a
// pasta principal grava a mesma sessao no mesmo offset. Antes, o INSERT estourava o
// UNIQUE(projeto, origem), a gravacao falhava e a marca d'agua nao avancava nunca.
{
  const raiz2 = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'observar-conflito-')));
  const amb2 = { ...process.env, RFM_ROOT: raiz2, CLAUDE_CONFIG_DIR: raiz2, TESTADOR_CHAMAR_LLM: DUBLIADOR };
  const S2 = 'S2';
  const conteudo2 = eventos.map((e) => JSON.stringify({ ...e, sessionId: S2 })).join('\n') + '\n';
  const tam2 = Buffer.byteLength(conteudo2, 'utf8');
  const dir2 = path.join(raiz2, 'projects', PASTA_PRINCIPAL);
  fs.mkdirSync(dir2, { recursive: true });
  const arq2 = path.join(dir2, `${S2}.jsonl`);
  fs.writeFileSync(arq2, conteudo2);
  let preparo2 = null;
  let obs3 = null;
  const banco2 = () => abrirBanco(path.join(raiz2, 'rainforest.db'));
  try {
    const h = spawnSync(process.execPath, [HOOK], {
      input: JSON.stringify({ session_id: S2, transcript_path: arq2, cwd: dir2 }),
      env: amb2, encoding: 'utf8', timeout: 60000,
    });
    if (h.status !== 0) throw new Error(`hook saiu ${h.status}: ${h.stderr}`);
    const db = banco2();
    try {
      db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
        .run(PASTA_PRINCIPAL, 'migrada do worktree', '2026-10-08T10:00:02Z', `sessao:${S2}:offset:${tam2}`);
    } finally {
      db.close();
    }
    obs3 = spawnSync(process.execPath, [OBSERVAR], { input: '', env: amb2, encoding: 'utf8', timeout: 120000 });
  } catch (e) {
    preparo2 = e;
  }

  caso('#452: origem ja gravada pela migracao nao trava a marca d agua da pasta principal', () => {
    if (preparo2) throw preparo2;
    assert.strictEqual(obs3.status, 0, `observar saiu ${obs3.status}: ${obs3.stderr}`);
    const db = banco2();
    try {
      const marca = db.prepare('SELECT offset_processado FROM marca_dagua WHERE projeto = ? AND sessao = ?')
        .get(PASTA_PRINCIPAL, S2);
      assert.strictEqual(marca && marca.offset_processado, tam2,
        `offset_processado deveria ser ${tam2}, veio ${JSON.stringify(marca)}; stderr: ${obs3.stderr}`);
      const n = db.prepare('SELECT COUNT(*) AS n FROM observacoes WHERE origem = ?').get(`sessao:${S2}:offset:${tam2}`).n;
      assert.strictEqual(n, 1, `esperado 1 linha com a origem, veio ${n}`);
    } finally {
      db.close();
    }
  });

  try {
    fs.rmSync(raiz2, { recursive: true, force: true });
  } catch {
    // limpeza best-effort
  }
}

console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
