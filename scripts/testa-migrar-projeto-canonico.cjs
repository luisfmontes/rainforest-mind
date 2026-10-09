#!/usr/bin/env node
'use strict';
/**
 * Bateria da migração 7 do esquema (#435; design D5, D6 e D7).
 * Uso: node scripts/testa-migrar-projeto-canonico.cjs
 *
 * Cada caso monta a própria caixa (fs.mkdtempSync) com a forma do banco real:
 * `criarSchema` da base, linhas inseridas à mão, `PRAGMA user_version = 1`.
 * Processos filhos recebem RFM_ROOT explícito. Nunca toca ~/.rainforest.
 * Nenhum caso lê o texto do fonte: tudo é conferido pelo efeito no banco e nos arquivos.
 */
const assert = require('assert');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const MEMORIA = path.join(__dirname, 'memoria.cjs');
const memoria = require(MEMORIA);
const { abrirBanco, abrirBancoSomenteLeitura, criarSchema } = memoria;
const { migrarProjetoCanonico, NOME_RELATORIO } = require(path.join(__dirname, 'lib', 'migrar-projeto-canonico.cjs'));

const T = '2026-10-08T10:00:00';
const PRINCIPAL = 'C--Projetos-alfa';
const WORKTREE = 'C--Projetos-alfa--claude-worktrees-w1';

let ok = 0;
let falhou = 0;

function novaCaixa() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-migra-canonico-'));
  const raiz = path.join(base, 'caixa');
  fs.mkdirSync(raiz);
  return { base, raiz, db: path.join(raiz, 'rainforest.db') };
}

function caso(nome, fn) {
  const caixa = novaCaixa();
  try {
    fn(caixa);
    ok++;
    console.log(`  ok    ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}: ${e.message}`);
  } finally {
    fs.rmSync(caixa.base, { recursive: true, force: true });
  }
}

// Forma do banco real: esquema da base, linhas à mão, user_version 1.
function semear(caixa) {
  const c = abrirBanco(caixa.db);
  try {
    criarSchema(c);
    const obs = c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
    const inserir = (projeto, origem, conteudo) => obs.run(projeto, conteudo || `conteudo ${projeto} ${origem}`, T, origem);
    for (const o of ['sessao:S0:offset:1', 'sessao:S1:offset:10', 'sessao:S1:offset:20', 'sessao:S3:offset:4']) {
      inserir(PRINCIPAL, o);
    }
    inserir(WORKTREE, 'sessao:S1:offset:10');
    inserir(WORKTREE, 'sessao:S2:offset:5', 'linha zetamigrada do worktree');
    inserir(WORKTREE, 'reconciliacao:1+2');
    inserir('c--projetos-alfa', 'sessao:S9:offset:1');
    for (const o of ['claude-mem:a1', 'claude-mem:a2', 'claude-mem:a3']) inserir('alfa', o);
    inserir('omega', 'claude-mem:o1');
    inserir('omega', 'claude-mem:o2');
    inserir('C--A-comum', 'sessao:SA:offset:1');
    inserir('C--B-comum', 'sessao:SB:offset:1');
    inserir('comum', 'claude-mem:c1');
    inserir('meu_alfa', 'claude-mem:m1');

    const res = c.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)');
    res.run('alfa', 'resumo alfa', 'texto alfa', T);
    res.run('omega', 'resumo omega', 'texto omega', T);

    const marca = c.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, ?, ?)');
    marca.run(PRINCIPAL, 'S1', 'C:/x/S1.jsonl', 10, 10, T);
    marca.run(WORKTREE, 'S1', 'C:/x/w1/S1.jsonl', 10, 10, T);
    marca.run(PRINCIPAL, 'S2', 'C:/x/S2.jsonl', 5, 5, T);

    const idPrincipal = c.prepare(`SELECT id FROM observacoes WHERE projeto = '${PRINCIPAL}' AND origem = 'sessao:S1:offset:10'`).get().id;
    const idResumo = c.prepare("SELECT id FROM resumos WHERE projeto = 'alfa'").get().id;
    const uso = c.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em) VALUES (?, ?, ?, ?, ?, ?)');
    uso.run('observacao', idPrincipal, 'S1', 1, 0.5, T);
    uso.run('resumo', idResumo, 'S5', 0, null, T);

    c.exec('PRAGMA user_version = 1;');
  } finally {
    c.close();
  }
}

function abrir(caixa) {
  return abrirBanco(caixa.db);
}

function contagens(c) {
  const n = (tabela) => c.prepare(`SELECT COUNT(*) AS n FROM ${tabela}`).get().n;
  return {
    observacoes: n('observacoes'),
    resumos: n('resumos'),
    marca_dagua: n('marca_dagua'),
    uso_memoria: n('uso_memoria'),
    ids: c.prepare('SELECT id FROM observacoes ORDER BY id').all().map((r) => r.id).join(','),
  };
}

// Instantâneo de todas as colunas, na ordem do rowid.
function instantaneo(c, tabela) {
  return JSON.stringify(c.prepare(`SELECT * FROM ${tabela} ORDER BY rowid`).all());
}

function instantaneoTodas(c) {
  return {
    observacoes: instantaneo(c, 'observacoes'),
    resumos: instantaneo(c, 'resumos'),
    marca_dagua: instantaneo(c, 'marca_dagua'),
    uso_memoria: instantaneo(c, 'uso_memoria'),
  };
}

function versao(c) {
  return c.prepare('PRAGMA user_version').get().user_version;
}

function backups(caixa) {
  const dir = path.join(caixa.raiz, '.rainforest-backups');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => f.startsWith('rainforest-') && f.endsWith('.db'));
}

function relatorio(caixa) {
  const arq = path.join(caixa.raiz, NOME_RELATORIO);
  return fs.existsSync(arq) ? fs.readFileSync(arq, 'utf8') : null;
}

function ambiente(caixa) {
  return { ...process.env, RFM_ROOT: caixa.raiz };
}

function cli(caixa, args) {
  return cp.spawnSync(process.execPath, [MEMORIA, ...args], {
    cwd: caixa.base, env: ambiente(caixa), encoding: 'utf8', timeout: 120000,
  });
}

function contar(c, sql) {
  return c.prepare(sql).get().n;
}

// 1. A regra da mutação: VERSAO_ESQUEMA = 1 mantém a marca d'água na migração 1 para 2.
caso('marca_dagua intacta na migracao 1 para 2', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  let antes;
  let depois;
  try {
    antes = instantaneo(c, 'marca_dagua');
    criarSchema(c);
    depois = instantaneo(c, 'marca_dagua');
  } finally {
    c.close();
  }
  assert.strictEqual(JSON.parse(antes).length, 3, 'a semente tem 3 marcas');
  assert.strictEqual(depois, antes, 'marca_dagua mudou na migração');
});

caso('(1) criarSchema: contagens, ids e user_version 2', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    const antes = contagens(c);
    criarSchema(c);
    const depois = contagens(c);
    assert.deepStrictEqual(depois, antes, 'contagens ou ids mudaram');
    assert.strictEqual(versao(c), 2);
  } finally {
    c.close();
  }
});

caso('(1) memoria.cjs iniciar: contagens, ids e user_version 2', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  let antes;
  try {
    antes = contagens(c);
  } finally {
    c.close();
  }
  const r = cli(caixa, ['iniciar']);
  assert.strictEqual(r.status, 0, `iniciar saiu ${r.status}: ${r.stderr}`);
  const d = abrir(caixa);
  try {
    assert.deepStrictEqual(contagens(d), antes, 'contagens ou ids mudaram no iniciar');
    assert.strictEqual(versao(d), 2);
  } finally {
    d.close();
  }
});

caso('(2) backup em .rainforest-backups abre com as contagens de antes', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  let antes;
  try {
    antes = contagens(c);
    criarSchema(c);
  } finally {
    c.close();
  }
  const lista = backups(caixa);
  assert.strictEqual(lista.length, 1, `esperava 1 backup, achei ${lista.length}`);
  const b = abrirBancoSomenteLeitura(path.join(caixa.raiz, '.rainforest-backups', lista[0]));
  assert.ok(b, 'backup não abre');
  try {
    const dos = contagens(b);
    assert.strictEqual(dos.observacoes, antes.observacoes);
    assert.strictEqual(dos.resumos, antes.resumos);
    assert.strictEqual(dos.marca_dagua, antes.marca_dagua);
    assert.strictEqual(dos.uso_memoria, antes.uso_memoria);
    assert.strictEqual(versao(b), 1, 'o backup é de antes da migração');
    assert.strictEqual(contar(b, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'c--projetos-alfa'"), 1,
      'o backup ainda tem a grafia c-- antiga');
  } finally {
    b.close();
  }
});

caso('(3) grafias e colisões: c-- e worktree viram C--Projetos-alfa; colisão reescrita; resto intacto', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'c--projetos-alfa'"), 0);
    assert.strictEqual(contar(c, `SELECT COUNT(*) AS n FROM observacoes WHERE projeto = '${WORKTREE}'`), 0);
    const origens = c.prepare(`SELECT origem FROM observacoes WHERE projeto = '${PRINCIPAL}' ORDER BY origem`).all().map((r) => r.origem);
    assert.deepStrictEqual(origens, [
      'claude-mem:a1',
      'claude-mem:a2',
      'claude-mem:a3',
      'reconciliacao:1+2',
      'sessao:S0:offset:1',
      'sessao:S1:offset:10',
      'sessao:S1:offset:20',
      'sessao:S1:wt:w1:offset:10',
      'sessao:S2:offset:5',
      'sessao:S3:offset:4',
      'sessao:S9:offset:1',
    ]);
    const linhaPrincipal = c.prepare(`SELECT origem FROM observacoes WHERE projeto = '${PRINCIPAL}' AND origem = 'sessao:S1:offset:10'`).all();
    assert.strictEqual(linhaPrincipal.length, 1, 'a linha da principal não pode mudar de origem');
  } finally {
    c.close();
  }
});

caso('(4) curtos: alfa e resumo alfa vão para C--Projetos-alfa; omega e comum ficam; meu_alfa fica', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'alfa'"), 0);
    assert.strictEqual(contar(c, `SELECT COUNT(*) AS n FROM observacoes WHERE projeto = '${PRINCIPAL}' AND origem LIKE 'claude-mem:a%'`), 3);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM resumos WHERE projeto = 'alfa'"), 0);
    assert.strictEqual(contar(c, `SELECT COUNT(*) AS n FROM resumos WHERE projeto = '${PRINCIPAL}' AND titulo = 'resumo alfa'`), 1);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'omega'"), 2);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM resumos WHERE projeto = 'omega'"), 1);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'comum'"), 1);
    assert.strictEqual(contar(c, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'meu_alfa'"), 1);
  } finally {
    c.close();
  }
});

caso('(5) integrity-check do FTS passa e a busca acha linha migrada', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    c.exec("INSERT INTO observacoes_fts(observacoes_fts) VALUES('integrity-check')");
    const achou = c.prepare(`
      SELECT o.projeto AS projeto FROM observacoes_fts f
      JOIN observacoes o ON o.id = f.rowid
      WHERE observacoes_fts MATCH 'zetamigrada'
    `).all();
    assert.strictEqual(achou.length, 1, `busca achou ${achou.length}`);
    assert.strictEqual(achou[0].projeto, PRINCIPAL);
  } finally {
    c.close();
  }
});

caso('(6) segunda abertura altera 0 linhas e não reescreve o relatório', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    const instantaneoAntes = instantaneoTodas(c);
    const relatorioAntes = relatorio(caixa);
    assert.ok(relatorioAntes, 'a primeira migração grava o relatório');
    criarSchema(c);
    assert.deepStrictEqual(instantaneoTodas(c), instantaneoAntes, 'a segunda abertura mudou linhas');
    assert.strictEqual(relatorio(caixa), relatorioAntes, 'a segunda abertura reescreveu o relatório');
    assert.strictEqual(backups(caixa).length, 1, 'a segunda abertura criou backup');
    assert.strictEqual(versao(c), 2);
  } finally {
    c.close();
  }
});

caso('(7) linha gravada depois pelo plugin antigo é recolhida; sem backup novo e sem nova versão', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    // Simula a conta com plugin antigo: a principal já tem S7:3; o worktree grava o mesmo offset.
    c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run(PRINCIPAL, 'principal tardia', T, 'sessao:S7:offset:3');
    c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run(WORKTREE, 'worktree tardio', T, 'sessao:S7:offset:3');
    c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run(WORKTREE, 'worktree tardio sem colisao', T, 'sessao:S8:offset:2');
    const backupsAntes = backups(caixa).length;
    const relatorioAntes = relatorio(caixa);
    criarSchema(c);
    const r = c.prepare("SELECT projeto, origem FROM observacoes WHERE conteudo = 'worktree tardio'").get();
    assert.strictEqual(r.projeto, PRINCIPAL);
    assert.strictEqual(r.origem, 'sessao:S7:wt:w1:offset:3');
    const s = c.prepare("SELECT projeto, origem FROM observacoes WHERE conteudo = 'worktree tardio sem colisao'").get();
    assert.strictEqual(s.projeto, PRINCIPAL);
    assert.strictEqual(s.origem, 'sessao:S8:offset:2', 'sem colisão, a origem não ganha :wt:');
    assert.strictEqual(backups(caixa).length, backupsAntes, 'criou backup novo');
    assert.strictEqual(relatorio(caixa), relatorioAntes, 'reescreveu o relatório');
    assert.strictEqual(versao(c), 2);
  } finally {
    c.close();
  }
});

caso('(7b) linha de worktree com origem que o :wt: já ocupa fica onde está (desvio do literal)', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
    // Literal do critério: (worktree, 'sessao:S1:offset:10'). A principal já tem essa origem, e a
    // forma com :wt: já existe (caso 3). Pela D7 a linha não sai: fica onde está.
    c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run(WORKTREE, 'worktree literal', T, 'sessao:S1:offset:10');
    const backupsAntes = backups(caixa).length;
    criarSchema(c);
    const r = c.prepare("SELECT projeto, origem FROM observacoes WHERE conteudo = 'worktree literal'").get();
    assert.strictEqual(r.projeto, WORKTREE);
    assert.strictEqual(r.origem, 'sessao:S1:offset:10');
    assert.strictEqual(backups(caixa).length, backupsAntes);
  } finally {
    c.close();
  }
});

caso('(8) backup que falha: nenhuma linha muda, user_version 1 e criarSchema não lança', (caixa) => {
  semear(caixa);
  // Backup impossível de criar: .rainforest-backups existe como arquivo.
  fs.writeFileSync(path.join(caixa.raiz, '.rainforest-backups'), 'bloqueio');
  const c = abrir(caixa);
  try {
    const antes = instantaneoTodas(c);
    const contAntes = contagens(c);
    assert.doesNotThrow(() => criarSchema(c), 'criarSchema lançou com o backup impossível');
    assert.deepStrictEqual(instantaneoTodas(c), antes, 'linhas mudaram com o backup falho');
    assert.deepStrictEqual(contagens(c), contAntes);
    assert.strictEqual(versao(c), 1, 'user_version avançou sem backup');
    assert.strictEqual(relatorio(caixa), null, 'gravou relatório sem migrar');
  } finally {
    c.close();
  }
});

caso('(8b) fazerBackup que lança: a migração não aplica, não lança e deixa o banco como estava', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    const antes = instantaneoTodas(c);
    let r;
    assert.doesNotThrow(() => {
      r = migrarProjetoCanonico(c, { fazerBackup: () => { throw new Error('falha simulada do backup'); } });
    });
    assert.strictEqual(r.aplicada, false);
    assert.deepStrictEqual(instantaneoTodas(c), antes);
    assert.strictEqual(versao(c), 1);
  } finally {
    c.close();
  }
});

caso('(9) outra conexão segurando BEGIN IMMEDIATE: criarSchema não lança nem altera; liberada, migra', (caixa) => {
  semear(caixa);
  const c1 = abrir(caixa);
  const c2 = abrir(caixa);
  try {
    c2.exec('BEGIN IMMEDIATE');
    const antes = instantaneoTodas(c1);
    assert.doesNotThrow(() => criarSchema(c1), 'criarSchema lançou com o banco travado');
    assert.deepStrictEqual(instantaneoTodas(c1), antes, 'linhas mudaram com o banco travado');
    assert.strictEqual(versao(c1), 1);
    assert.strictEqual(backups(caixa).length, 0, 'criou backup com o banco travado');
    c2.exec('ROLLBACK');
    criarSchema(c1);
    assert.strictEqual(versao(c1), 2, 'a abertura seguinte não migrou');
    assert.strictEqual(contar(c1, "SELECT COUNT(*) AS n FROM observacoes WHERE projeto = 'alfa'"), 0);
  } finally {
    c2.close();
    c1.close();
  }
});

caso('(10) criarSchema como processo filho não escreve nada em stdout', (caixa) => {
  semear(caixa);
  const script = `const m = require(${JSON.stringify(MEMORIA)}); const c = m.abrirBanco(${JSON.stringify(caixa.db)}); m.criarSchema(c); c.close();`;
  const r = cp.spawnSync(process.execPath, ['-e', script], {
    cwd: caixa.base, env: ambiente(caixa), encoding: 'utf8', timeout: 120000,
  });
  assert.strictEqual(r.status, 0, `filho saiu ${r.status}: ${r.stderr}`);
  assert.strictEqual(r.stdout, '', `stdout não vazio: ${JSON.stringify(r.stdout)}`);
  const c = abrir(caixa);
  try {
    assert.strictEqual(versao(c), 2, 'o filho não migrou');
  } finally {
    c.close();
  }
});

caso('relatorio: backup, movidas, colisões, omega com contagem e comum com os dois candidatos', (caixa) => {
  semear(caixa);
  const c = abrir(caixa);
  try {
    criarSchema(c);
  } finally {
    c.close();
  }
  const texto = relatorio(caixa);
  assert.ok(texto, 'sem relatório');
  const nomeBackup = backups(caixa)[0];
  assert.ok(nomeBackup, 'sem backup');
  assert.ok(texto.includes(nomeBackup), 'relatório sem o caminho do backup');
  assert.ok(texto.includes(WORKTREE), 'relatório sem a pasta de worktree');
  assert.ok(texto.includes('sessao:S1:offset:10 -> sessao:S1:wt:w1:offset:10'), 'relatório sem a colisão reescrita');
  assert.ok(/omega: 2 observações, 1 resumos/.test(texto), 'relatório sem omega com contagem');
  assert.ok(texto.includes('comum: 1 observações, 0 resumos; candidatos: C--A-comum, C--B-comum'), 'relatório sem comum com os candidatos');
});

caso('banco novo sem linhas: sem backup, sem relatório, user_version 2', (caixa) => {
  const c = abrir(caixa);
  try {
    criarSchema(c);
    assert.strictEqual(versao(c), 2);
  } finally {
    c.close();
  }
  assert.strictEqual(backups(caixa).length, 0, 'criou backup sem nada a mover');
  assert.strictEqual(relatorio(caixa), null, 'criou relatório sem nada a mover');
});

console.log('');
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
