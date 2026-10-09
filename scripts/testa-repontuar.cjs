#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria do `utilidade --repontuar --desde` (D8 de docs/rainforest/design/2026-10-09-assunto-regua.md;
 * tarefa 9 do plano docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * O comando refaz a nota das sessoes da janela com as regras atuais (D1 a D3), sem tocar o resto,
 * preservando o `pontuada_em` original, com backup antes e saida em linhas fixas.
 *
 * Os transcritos sao MONTADOS a partir das linhas reais do harness (as mesmas fixtures de
 * testa-nota-nula.cjs), trocando so o texto. Quem roda e o COMANDO real
 * (`RFM_ROOT=<caixa> node scripts/memoria.cjs utilidade --repontuar ...`) sobre uma caixa de
 * `criarSchema` real, em pasta temporaria. Nunca toca ~/.rainforest; o backup cai dentro da caixa.
 * Nenhum caso le o texto do fonte.
 *
 * Uso: node scripts/testa-repontuar.cjs
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const MEMORIA = path.join(SRC, 'scripts', 'memoria.cjs');
const memoria = require(MEMORIA);
const { formatarObservacao } = require(path.join(SRC, 'hooks', 'lib', 'memoria-sessao.cjs'));

const FIX = path.join(SRC, 'scripts', 'fixtures');
const lerLinhas = (f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
const PEDIDO = lerLinhas(path.join(FIX, 'memoria-assunto', 'prompt-submit.jsonl'))[0];
const PAI = lerLinhas(path.join(FIX, 'memoria-assunto', 'agente-pai.jsonl'));
const SINT = lerLinhas(path.join(FIX, 'utilidade', 'transcrito-sessao.jsonl')).map((l) => JSON.parse(l));
const USER_PROMPT = SINT.find((o) => o.type === 'user' && typeof o.message.content === 'string');
assert.ok(PEDIDO.includes('MARCA-ASSUNTO-7f3'), 'fixture prompt-submit sem a marca');

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHA  ${nome}\n  ${String(e.message).split('\n').slice(0, 4).join('\n  ')}`);
  }
}

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-repontuar-')));
const PROJ = 'proj-repontuar';

// ---- montagem de transcritos a partir das fixtures reais ----
const esc = (s) => JSON.stringify(s).slice(1, -1);
const bloco = (linhas) => '## Memória do assunto\n' + linhas.join('\n') + '\n';
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
const HEREDOC = "git commit -F - <<'EOF'\nnode scripts/memoria.cjs buscar --texto zeta\nEOF";

// ---- caixa: criarSchema real + memorias de termos raros ----
function novaCaixa(nome) {
  const raiz = path.join(tmp, nome);
  fs.mkdirSync(raiz, { recursive: true });
  const db = new DatabaseSync(path.join(raiz, 'rainforest.db'));
  memoria.criarSchema(db);
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  const nova = (chave, raros) => {
    const conteudo = 'titulo corpusfiller\nsubtitulo corpusfiller ' + raros.join(' ');
    const criada = '2026-10-05T12:00:00.000Z';
    const id = Number(ins.run(PROJ, conteudo, criada, 'obs-' + chave).lastInsertRowid);
    return { id, linha: formatarObservacao({ conteudo, projeto: PROJ, criada_em: criada }, null) };
  };
  const M1 = nova('m1', ['zzfeixe', 'zzmanga']);
  const M2 = nova('m2', ['zzcarro', 'zzroda']);
  for (let i = 0; i < 4; i++) {
    ins.run(PROJ, 'titulo corpusfiller\nsubtitulo corpusfiller fillerrarox' + i, '2026-10-01T09:0' + i + ':00.000Z', 'filler-' + i);
  }
  const escrever = (n, linhas) => {
    const f = path.join(raiz, n + '.jsonl');
    fs.writeFileSync(f, linhas.join('\n') + '\n');
    return f;
  };
  const semear = (sessao, pontuadaEm, arquivo, buscas) => {
    db.prepare('INSERT INTO uso_memoria_sessoes (sessao, pontuada_em, buscas_principal, buscas_subagente, subagentes) VALUES (?, ?, ?, 0, 0)').run(sessao, pontuadaEm, buscas);
    db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, processada_em) VALUES (?, ?, ?, ?)').run(PROJ, sessao, arquivo, pontuadaEm);
  };
  const uso = (sessao, id, servida, nota, pontuadaEm, canal = 'pedido') => {
    db.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal) VALUES (?, ?, ?, ?, ?, ?, ?)').run('observacao', id, sessao, servida, nota, pontuadaEm, canal);
  };
  return { raiz, db, M1, M2, escrever, semear, uso };
}

const instantaneo = (db, sessoes) => {
  const ph = sessoes.map(() => '?').join(',');
  const u = db.prepare(`SELECT origem, ref_id, sessao, servida, nota, pontuada_em, canal FROM uso_memoria WHERE sessao IN (${ph}) ORDER BY sessao, origem, ref_id`).all(...sessoes);
  const s = db.prepare(`SELECT * FROM uso_memoria_sessoes WHERE sessao IN (${ph}) ORDER BY sessao`).all(...sessoes);
  return JSON.stringify({ u: u.map((r) => ({ ...r })), s: s.map((r) => ({ ...r })) });
};

function rodar(raiz, args) {
  const r = spawnSync(process.execPath, [MEMORIA, 'utilidade', ...args], {
    env: { ...process.env, RFM_ROOT: raiz },
    cwd: raiz,
    encoding: 'utf8',
    timeout: 120000,
  });
  return { status: r.status, out: r.stdout || '', err: r.stderr || '' };
}

// ---- a caixa principal: quatro sessoes ----
const T_ANTES = '2026-10-02T09:00:00.000Z';
const T_TAUT = '2026-10-09T08:00:00.000Z';
const T_NULA = '2026-10-09T09:00:00.000Z';
const T_SEM = '2026-10-09T10:00:00.000Z';
const SESSOES = ['s-antes', 's-taut', 's-nula', 's-sem'];
const ORFA = 999001;

function semearPrincipal(c) {
  const { M1, M2 } = c;
  // fora da janela: tem transcrito e linha com nota 0.3 que a regra nova mudaria
  const fa = c.escrever('t-antes', [linhaUser('revise o zzfeixe agora'), linhaPedido([M1.linha]), linhaTool('Read', { file_path: 'C:/repo/src/zzfeixe.cjs' })]);
  c.semear('s-antes', T_ANTES, fa, 2);
  c.uso('s-antes', M1.id, 1, 0.3, T_ANTES);
  // tautologia (Read do arquivo citado), orfa que nenhuma regra nova produz, busca so em heredoc
  const ft = c.escrever('t-taut', [
    linhaUser('revise o zzfeixe agora'),
    linhaPedido([M1.linha]),
    linhaTool('Read', { file_path: 'C:/repo/src/zzfeixe.cjs' }),
    linhaTool('Bash', { command: HEREDOC }),
  ]);
  c.semear('s-taut', T_TAUT, ft, 1);
  c.uso('s-taut', M1.id, 1, 0.5, T_TAUT);
  c.uso('s-taut', ORFA, 1, 0.9, T_TAUT);
  // todos os raros no pedido
  const fn = c.escrever('t-nula', [linhaUser('trate de zzcarro zzroda'), linhaPedido([M2.linha])]);
  c.semear('s-nula', T_NULA, fn, 0);
  c.uso('s-nula', M2.id, 1, 0, T_NULA);
  // transcrito inexistente
  c.semear('s-sem', T_SEM, path.join(c.raiz, 'nao-existe.jsonl'), 3);
  c.uso('s-sem', M1.id, 1, 0.4, T_SEM);
}

const A = novaCaixa('caixa-a');
semearPrincipal(A);
const antes = instantaneo(A.db, SESSOES);
A.db.close();

let saida1;
let apos1;
const LINHAS_ESPERADAS = [
  'repontuar desde 2026-10-08',
  /^backup: .+\.rainforest-backups[\\/]rainforest-.+\.db$/,
  'sessões na janela: 3',
  'refeitas: 2',
  'sem transcrito (mantidas com a nota antiga): 1',
  'falharam (mantidas com a nota antiga): 0',
  'adiadas (banco ocupado): 0',
  'servidas fora da conta pela regra nova nas refeitas: 1',
];

caso('o comando real sai 0 e imprime as linhas do pronto quando, nesta ordem', () => {
  saida1 = rodar(A.raiz, ['--repontuar', '--desde', '2026-10-08']);
  console.log(saida1.out.split('\n').filter(Boolean).map((l) => '    | ' + l).join('\n'));
  assert.strictEqual(saida1.status, 0, saida1.err);
  const linhas = saida1.out.split('\n').filter(Boolean);
  assert.strictEqual(linhas.length, LINHAS_ESPERADAS.length, linhas.join(' // '));
  LINHAS_ESPERADAS.forEach((esperada, i) => {
    if (esperada instanceof RegExp) assert.ok(esperada.test(linhas[i]), linhas[i]);
    else assert.strictEqual(linhas[i], esperada);
  });
});

caso('o backup cai dentro da caixa e abre com as contagens de antes', () => {
  const caminho = saida1.out.split('\n').find((l) => l.startsWith('backup: ')).slice('backup: '.length);
  assert.ok(path.resolve(caminho).startsWith(path.resolve(A.raiz) + path.sep), caminho);
  const b = new DatabaseSync(caminho, { readOnly: true });
  try {
    assert.strictEqual(b.prepare('SELECT count(*) c FROM uso_memoria_sessoes').get().c, 4);
    assert.strictEqual(b.prepare('SELECT count(*) c FROM uso_memoria').get().c, 5);
    assert.strictEqual(b.prepare("SELECT nota FROM uso_memoria WHERE sessao = 's-taut' AND ref_id = ?").get(A.M1.id).nota, 0.5);
  } finally {
    b.close();
  }
});

caso('s-taut: nota do pedido 0 (era 0,5), a linha orfa sumiu, buscas_principal 0', () => {
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    const servidas = db.prepare("SELECT ref_id, nota, canal FROM uso_memoria WHERE sessao = 's-taut' AND servida = 1 ORDER BY ref_id").all().map((r) => ({ ...r }));
    assert.deepStrictEqual(servidas, [{ ref_id: A.M1.id, nota: 0, canal: 'pedido' }]);
    assert.strictEqual(db.prepare("SELECT buscas_principal b FROM uso_memoria_sessoes WHERE sessao = 's-taut'").get().b, 0);
  } finally {
    db.close();
  }
});

caso('linha velha que as regras novas nao produzem some da sessao refeita', () => {
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    assert.strictEqual(db.prepare("SELECT count(*) c FROM uso_memoria WHERE sessao = 's-taut' AND ref_id = ?").get(ORFA).c, 0);
  } finally {
    db.close();
  }
});

caso('s-nula: nota IS NULL', () => {
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    const r = db.prepare("SELECT nota FROM uso_memoria WHERE sessao = 's-nula' AND servida = 1").all();
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].nota, null);
  } finally {
    db.close();
  }
});

caso('pontuada_em de s-taut e s-nula e o original, nas duas tabelas', () => {
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    for (const [s, t] of [['s-taut', T_TAUT], ['s-nula', T_NULA]]) {
      assert.strictEqual(db.prepare('SELECT pontuada_em p FROM uso_memoria_sessoes WHERE sessao = ?').get(s).p, t);
      const datas = db.prepare('SELECT DISTINCT pontuada_em p FROM uso_memoria WHERE sessao = ?').all(s).map((r) => r.p);
      assert.deepStrictEqual(datas, [t]);
    }
  } finally {
    db.close();
  }
});

caso('s-antes e s-sem ficam identicas, linha a linha', () => {
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    apos1 = instantaneo(db, SESSOES);
    const pega = (j, s) => {
      const o = JSON.parse(j);
      return JSON.stringify({ u: o.u.filter((r) => r.sessao === s), s: o.s.filter((r) => r.sessao === s) });
    };
    assert.strictEqual(pega(apos1, 's-antes'), pega(antes, 's-antes'));
    assert.strictEqual(pega(apos1, 's-sem'), pega(antes, 's-sem'));
    assert.notStrictEqual(pega(apos1, 's-taut'), pega(antes, 's-taut'));
  } finally {
    db.close();
  }
});

caso('idempotencia: a segunda execucao devolve o mesmo e deixa as tabelas iguais', () => {
  const r2 = rodar(A.raiz, ['--repontuar', '--desde', '2026-10-08']);
  assert.strictEqual(r2.status, 0, r2.err);
  const sem = (o) => o.split('\n').filter((l) => !l.startsWith('backup: ')).join('\n');
  assert.strictEqual(sem(r2.out), sem(saida1.out));
  const db = new DatabaseSync(path.join(A.raiz, 'rainforest.db'), { readOnly: true });
  try {
    assert.strictEqual(instantaneo(db, SESSOES), apos1);
  } finally {
    db.close();
  }
});

caso('o relatorio depois sai 0 e traz as linhas da tarefa 7', () => {
  const r = rodar(A.raiz, ['--relatorio']);
  assert.strictEqual(r.status, 0, r.err);
  assert.ok(r.out.includes('sessões pontuadas: 4'), r.out);
  assert.ok(r.out.includes('servidas fora da conta (toda a memória estava no pedido): 1 em 1 sessão(ões)'), r.out);
});

// ---- banco ocupado ----
const B = novaCaixa('caixa-b');
semearPrincipal(B);
const antesB = instantaneo(B.db, SESSOES);
caso('banco ocupado: exit 2, adiadas 2, s-sem segue como sem transcrito, banco igual ao de antes', () => {
  const trava = new DatabaseSync(path.join(B.raiz, 'rainforest.db'));
  trava.exec('PRAGMA journal_mode = WAL;');
  trava.exec('BEGIN IMMEDIATE');
  let r;
  try {
    r = rodar(B.raiz, ['--repontuar', '--desde', '2026-10-08']);
  } finally {
    trava.exec('ROLLBACK');
    trava.close();
  }
  assert.strictEqual(r.status, 2, r.out + r.err);
  assert.ok(r.out.includes('\nadiadas (banco ocupado): 2\n'), r.out);
  assert.ok(r.out.includes('\nsem transcrito (mantidas com a nota antiga): 1\n'), r.out);
  assert.ok(r.out.includes('\nrefeitas: 0\n'), r.out);
  assert.strictEqual(instantaneo(B.db, SESSOES), antesB);
});
B.db.close();

// ---- uso invalido ----
caso('uso invalido: sem --desde, 2026-13-45 e ontem saem 1 com uma linha de uso no stderr', () => {
  const C = path.join(tmp, 'caixa-uso');
  fs.mkdirSync(C, { recursive: true });
  for (const args of [['--repontuar'], ['--repontuar', '--desde', '2026-13-45'], ['--repontuar', '--desde', 'ontem'], ['--repontuar', '--desde']]) {
    const r = rodar(C, args);
    assert.strictEqual(r.status, 1, args.join(' '));
    assert.strictEqual(r.err.trim().split('\n').length, 1, r.err);
    assert.ok(r.err.includes('--desde AAAA-MM-DD'), r.err);
    assert.strictEqual(r.out, '');
  }
  assert.deepStrictEqual(fs.readdirSync(C), [], 'uso invalido nao pode criar nada na caixa');
});

caso('utilidade sem argumentos sai 1 e lista --repontuar no uso', () => {
  const C = path.join(tmp, 'caixa-uso');
  const r = rodar(C, []);
  assert.strictEqual(r.status, 1);
  assert.ok(r.err.includes('--repontuar'), r.err);
});

// ---- janela de 35 sessoes: sem o teto de 30 ----
caso('janela de 35 sessoes: refeitas = 35, e pendentes alheias nao entram na conta', () => {
  const D = novaCaixa('caixa-d');
  for (let i = 0; i < 35; i++) {
    const n = String(i).padStart(2, '0');
    const f = D.escrever('t-' + n, [linhaUser('sessao minima ' + n)]);
    D.semear('s-' + n, `2026-10-09T${String(Math.floor(i / 6) + 1).padStart(2, '0')}:${String((i % 6) * 10).padStart(2, '0')}:00.000Z`, f, 0);
  }
  // sessoes alheias: na marca_dagua, sem linha em uso_memoria_sessoes (pendentes)
  for (const n of ['pend-1', 'pend-2']) {
    const f = D.escrever('t-' + n, [linhaUser('pendente ' + n)]);
    D.db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, processada_em) VALUES (?, ?, ?, ?)').run(PROJ, n, f, '2026-10-09T01:00:00.000Z');
  }
  D.db.close();
  const r = rodar(D.raiz, ['--repontuar', '--desde', '2026-10-08']);
  assert.strictEqual(r.status, 0, r.err);
  assert.ok(r.out.includes('\nsessões na janela: 35\n'), r.out);
  assert.ok(r.out.includes('\nrefeitas: 35\n'), r.out);
  // Progresso no stderr, a cada 5 e na última; o stdout continua só com o resumo.
  const progresso = r.err.split('\n').filter((l) => l.startsWith('repontuar: '));
  assert.deepStrictEqual(progresso, [5, 10, 15, 20, 25, 30, 35].map((k) => `repontuar: ${k} de 35 sessões com transcrito`), r.err);
  assert.ok(!r.out.includes('repontuar: '), r.out);
  const db = new DatabaseSync(path.join(D.raiz, 'rainforest.db'), { readOnly: true });
  try {
    assert.strictEqual(db.prepare('SELECT count(*) c FROM uso_memoria_sessoes').get().c, 35);
    assert.strictEqual(db.prepare("SELECT count(*) c FROM uso_memoria_sessoes WHERE sessao LIKE 'pend-%'").get().c, 0);
  } finally {
    db.close();
  }
});

try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
