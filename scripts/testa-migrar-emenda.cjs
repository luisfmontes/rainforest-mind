#!/usr/bin/env node
'use strict';
/**
 * Bateria da emenda da migração 7 (#435, tarefa 12): backup conferido, nome curto só na
 * primeira passada, grafia estável e primeira passada relida dentro da transação.
 * Uso: node scripts/testa-migrar-emenda.cjs
 *
 * Cada caso monta a própria caixa (fs.mkdtempSync) com `criarSchema` da base, linhas à mão
 * e `PRAGMA user_version = 1`. Nunca toca ~/.rainforest. Nenhum caso lê o texto do fonte:
 * tudo é conferido pelo efeito no banco, nos arquivos e nos fluxos de saída.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const memoria = require(path.join(__dirname, 'memoria.cjs'));
const { abrirBanco, criarSchema, fazerBackupDoBanco } = memoria;
const { migrarProjetoCanonico, NOME_RELATORIO } = require(path.join(__dirname, 'lib', 'migrar-projeto-canonico.cjs'));

const T = '2026-10-08T10:00:00';
let ok = 0;
let falhou = 0;

function caso(nome, fn) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-emenda-'));
  const raiz = path.join(base, 'caixa');
  fs.mkdirSync(raiz);
  const caixa = { base, raiz, db: path.join(raiz, 'rainforest.db') };
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

// Esquema da base, linhas à mão, user_version 1. `linhas`: [[projeto, origem], ...].
function semear(caixa, linhas) {
  const c = abrirBanco(caixa.db);
  try {
    criarSchema(c);
    inserir(c, linhas);
    c.exec('PRAGMA user_version = 1;');
  } finally {
    c.close();
  }
}

function inserir(c, linhas) {
  const obs = c.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  for (const [projeto, origem] of linhas) obs.run(projeto, `conteudo ${projeto} ${origem}`, T, origem);
}

function numeradas(projeto, prefixo, quantas) {
  return Array.from({ length: quantas }, (_, i) => [projeto, `claude-mem:${prefixo}${i}`]);
}

const versao = (c) => c.prepare('PRAGMA user_version').get().user_version;
const quantas = (c, projeto) => c.prepare('SELECT COUNT(*) AS n FROM observacoes WHERE projeto = ?').get(projeto).n;
const total = (c) => c.prepare('SELECT COUNT(*) AS n FROM observacoes').get().n;

// Captura stdout e stderr durante `fn`, sempre restaurando. Devolve o que saiu e o que `fn` devolveu.
function capturar(fn) {
  const ow = process.stdout.write;
  const ew = process.stderr.write;
  const saida = { stdout: '', stderr: '', lancou: null, valor: undefined };
  process.stdout.write = (s) => { saida.stdout += String(s); return true; };
  process.stderr.write = (s) => { saida.stderr += String(s); return true; };
  try {
    saida.valor = fn();
  } catch (e) {
    saida.lancou = e;
  } finally {
    process.stdout.write = ow;
    process.stderr.write = ew;
  }
  return saida;
}

function relatorio(caixa) {
  const arq = path.join(caixa.raiz, NOME_RELATORIO);
  return fs.existsSync(arq) ? fs.readFileSync(arq, 'utf8') : null;
}

caso('backup sem as linhas do WAL nao deixa a migracao aplicar', (caixa) => {
  semear(caixa, [
    ['C--P-alfa', 'sessao:S1:offset:1'],
    ['c--p-alfa', 'sessao:S2:offset:1'],
    ['c--p-alfa', 'sessao:S2:offset:2'],
  ]);
  // Linha recém-inserida que fica só no WAL: a conexão de escrita segue aberta, sem checkpoint.
  const escritor = abrirBanco(caixa.db);
  const c = abrirBanco(caixa.db);
  try {
    inserir(escritor, [['C--P-alfa', 'sessao:S9:offset:9']]);
    let copiaCom = -1;
    // Backup defeituoso: copia só o arquivo .db, como o wal_checkpoint ocupado deixa.
    const fazerBackup = (caminhoDb) => {
      const destino = path.join(path.dirname(caminhoDb), 'copia-sem-wal.db');
      fs.copyFileSync(caminhoDb, destino);
      const leitura = abrirBanco(destino);
      try { copiaCom = total(leitura); } finally { leitura.close(); }
      return destino;
    };
    const r = capturar(() => criarSchema(c, { fazerBackup }));
    assert.strictEqual(r.lancou, null, `criarSchema lançou: ${r.lancou && r.lancou.message}`);
    assert.ok(copiaCom >= 0, 'o backup injetado não foi chamado');
    assert.ok(copiaCom < total(c), `a cópia tem ${copiaCom} linhas e o banco ${total(c)}: o caso não prova nada`);
    assert.strictEqual(r.stdout, '', `stdout não vazio: ${r.stdout}`);
    assert.ok(/backup incompleto/.test(r.stderr), `stderr sem aviso de backup incompleto: ${r.stderr}`);
    assert.strictEqual(versao(c), 1, 'user_version avançou com backup incompleto');
    assert.strictEqual(quantas(c, 'c--p-alfa'), 2, 'linha mudou de projeto com backup incompleto');
    assert.strictEqual(quantas(c, 'C--P-alfa'), 2, 'linha chegou em C--P-alfa com backup incompleto');
    assert.strictEqual(relatorio(caixa), null, 'relatório gravado sem migração');
  } finally {
    c.close();
    escritor.close();
  }
});

caso('backup real sem leitor concorrente: a migracao aplica', (caixa) => {
  semear(caixa, [
    ['C--P-alfa', 'sessao:S1:offset:1'],
    ['c--p-alfa', 'sessao:S2:offset:1'],
    ['c--p-alfa', 'sessao:S2:offset:2'],
  ]);
  const c = abrirBanco(caixa.db);
  try {
    const r = capturar(() => criarSchema(c, { fazerBackup: fazerBackupDoBanco }));
    assert.strictEqual(r.lancou, null, `criarSchema lançou: ${r.lancou && r.lancou.message}`);
    assert.strictEqual(r.stdout, '', `stdout não vazio: ${r.stdout}`);
    assert.ok(!/backup incompleto/.test(r.stderr), `aviso indevido: ${r.stderr}`);
    assert.strictEqual(versao(c), 2, 'user_version não avançou');
    assert.strictEqual(quantas(c, 'c--p-alfa'), 0);
    assert.strictEqual(quantas(c, 'C--P-alfa'), 3);
    const dir = path.join(caixa.raiz, '.rainforest-backups');
    const sobras = fs.readdirSync(dir).filter((f) => !f.endsWith('.db'));
    assert.deepStrictEqual(sobras, [], `a conferência deixou arquivos na pasta de backups: ${sobras}`);
  } finally {
    c.close();
  }
});

caso('orfao curto que ficou na primeira passada nao migra na passada seguinte', (caixa) => {
  semear(caixa, [
    ['C--Q-beta', 'sessao:S1:offset:1'],
    ['c--q-beta', 'sessao:S2:offset:1'],
    ['zeta', 'claude-mem:z1'],
    ['zeta', 'claude-mem:z2'],
  ]);
  const c = abrirBanco(caixa.db);
  try {
    criarSchema(c);
    assert.strictEqual(versao(c), 2, 'primeira passada não fechou');
    assert.strictEqual(quantas(c, 'zeta'), 2, 'zeta saiu do lugar sem correspondente');
    // Aparece o repositório de mesmo nome, depois da primeira passada.
    inserir(c, [['C--Q-zeta', 'sessao:S7:offset:1']]);
    const r = capturar(() => criarSchema(c));
    assert.strictEqual(r.lancou, null);
    assert.strictEqual(quantas(c, 'zeta'), 2, 'zeta foi absorvido numa passada posterior');
    assert.strictEqual(quantas(c, 'C--Q-zeta'), 1);
  } finally {
    c.close();
  }
});

caso('grafia: maiuscula com -- vence a de mais linhas, na mesma passada', (caixa) => {
  semear(caixa, [
    ...numeradas('C--P-alfa', 'a', 6),
    ...numeradas('c--p-alfa', 'b', 1),
    ...numeradas('c--p-alfa', 'c', 10),
  ]);
  const c = abrirBanco(caixa.db);
  try {
    const r = capturar(() => criarSchema(c));
    assert.strictEqual(r.lancou, null);
    assert.strictEqual(quantas(c, 'c--p-alfa'), 0, 'linhas ficaram na grafia minúscula');
    assert.strictEqual(quantas(c, 'C--P-alfa'), 17, 'as 11 de c--p-alfa não foram para C--P-alfa');
  } finally {
    c.close();
  }
});

caso('grafia: passada seguinte move as linhas do plugin antigo para a maiuscula, nunca o contrario', (caixa) => {
  semear(caixa, [...numeradas('C--P-alfa', 'a', 6), ...numeradas('c--p-alfa', 'b', 1)]);
  const c = abrirBanco(caixa.db);
  try {
    criarSchema(c);
    assert.strictEqual(quantas(c, 'C--P-alfa'), 7);
    // O plugin antigo segue gravando na grafia minúscula, e agora ela tem mais linhas.
    inserir(c, numeradas('c--p-alfa', 'c', 11));
    const r = capturar(() => criarSchema(c));
    assert.strictEqual(r.lancou, null);
    assert.strictEqual(quantas(c, 'c--p-alfa'), 0, 'a grafia minúscula ficou com linhas');
    assert.strictEqual(quantas(c, 'C--P-alfa'), 18, 'as 11 não foram para C--P-alfa');
  } finally {
    c.close();
  }
});

caso('grafia: sem maiuscula com --, vence a de mais linhas e depois a ordem alfabetica', (caixa) => {
  semear(caixa, [
    ...numeradas('c--p-beta', 'a', 3),
    ...numeradas('c--P-beta', 'b', 1),
    ...numeradas('c--p-gama', 'c', 2),
    ...numeradas('c--P-gama', 'd', 2),
  ]);
  const c = abrirBanco(caixa.db);
  try {
    criarSchema(c);
    assert.strictEqual(quantas(c, 'c--p-beta'), 4, 'mais linhas deveria vencer');
    // empate em linhas: a ordem alfabética ordinal põe `c--P-gama` antes de `c--p-gama`.
    assert.strictEqual(quantas(c, 'c--P-gama'), 4, 'empate deveria resolver pela ordem alfabética');
  } finally {
    c.close();
  }
});

caso('primeira passada concorrente: quem pega a trava depois nao reescreve o relatorio', (caixa) => {
  semear(caixa, [
    ['C--P-alfa', 'sessao:S1:offset:1'],
    ['c--p-alfa', 'sessao:S2:offset:1'],
    ['zeta', 'claude-mem:z1'],
  ]);
  const primeira = abrirBanco(caixa.db);
  const segunda = abrirBanco(caixa.db);
  const MARCA = 'RELATORIO DA PRIMEIRA ABERTURA, NAO REESCREVER\n';
  try {
    // A segunda abertura já leu user_version = 1 quando o backup dela roda; é aí que a
    // primeira abertura termina a migração inteira e deixa a sua marca no relatório.
    const fazerBackup = (caminhoDb) => {
      const copia = fazerBackupDoBanco(caminhoDb);
      const feita = migrarProjetoCanonico(primeira, { fazerBackup: () => copia });
      assert.ok(feita.aplicada, 'a primeira abertura não aplicou');
      assert.ok(relatorio(caixa) !== null, 'a primeira abertura não gravou relatório');
      fs.writeFileSync(path.join(caixa.raiz, NOME_RELATORIO), MARCA, 'utf8');
      return copia;
    };
    const r = capturar(() => migrarProjetoCanonico(segunda, { fazerBackup }));
    assert.strictEqual(r.lancou, null);
    assert.strictEqual(r.stdout, '');
    assert.strictEqual(relatorio(caixa), MARCA, 'a segunda abertura reescreveu o relatório');
    assert.strictEqual(versao(segunda), 2);
    assert.strictEqual(quantas(segunda, 'zeta'), 1, 'zeta migrou fora da primeira passada');
  } finally {
    segunda.close();
    primeira.close();
  }
});

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou === 0 ? 0 : 1);
