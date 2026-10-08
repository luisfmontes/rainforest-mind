#!/usr/bin/env node
/**
 * Bateria de fazerBackupDoBanco (scripts/memoria.cjs) — backup como função.
 * Uso: node scripts/testa-memoria-backup-funcao.cjs
 *
 * O que prova, nesta ordem:
 *   1. a função devolve <raiz>/.rainforest-backups/rainforest-<timestamp>.db e o arquivo existe
 *   2. a cópia abre por abrirBancoSomenteLeitura e tem count(*) igual ao do banco, em cada tabela
 *   3. com uma conexão de escrita aberta (WAL) que acabou de inserir uma linha, a cópia contém a linha
 *   4. banco inexistente faz a função LANÇAR Error (sem process.exit)
 *   5. a rotação mantém 5 cópias e nunca apaga a mais recente
 *   6. o comando `backup` continua: exit 0 com `backup: <caminho>`; banco ausente, exit 1 com `ERRO: banco não existe em`
 *
 * Hermética: caixa de areia com fs.mkdtempSync; processos filhos recebem RFM_ROOT explícito.
 * Nunca toca ~/.rainforest.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const SRC = path.join(__dirname, '..');
const memoria = require('./memoria.cjs');
const {
  abrirBanco, abrirBancoSomenteLeitura, criarSchema, fazerBackupDoBanco,
} = memoria;

let ok = 0;
let falhou = 0;

function checa(nome, cond, detalhe = '') {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? `: ${detalhe}` : ''}`);
  }
}

// Contagem de linhas por tabela de um banco já aberto (somente leitura ou escrita).
function contagens(conexao) {
  const tabelas = conexao
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    .all()
    .map(r => r.name);
  const mapa = {};
  for (const t of tabelas) {
    mapa[t] = conexao.prepare(`SELECT COUNT(*) AS n FROM "${t}"`).get().n;
  }
  return mapa;
}

function semelhante(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-backup-funcao-'));
const caixa = path.join(sandbox, 'caixa');
fs.mkdirSync(caixa);
const caminhoDb = path.join(caixa, 'rainforest.db');
const dirBackup = path.join(caixa, '.rainforest-backups');

try {
  // Banco real via criarSchema, com 3 observações e 2 marcas d'água.
  const conexao = abrirBanco(caminhoDb);
  criarSchema(conexao);
  const insObs = conexao.prepare(
    'INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)'
  );
  insObs.run('projeto-teste', 'obs um', '2026-10-01T10:00:00', 'origem-1');
  insObs.run('projeto-teste', 'obs dois', '2026-10-01T10:01:00', 'origem-2');
  insObs.run('projeto-teste', 'obs tres', '2026-10-01T10:02:00', 'origem-3');
  const insMarca = conexao.prepare(
    'INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, ?, ?)'
  );
  insMarca.run('projeto-teste', 'sessao-1', 'a.jsonl', 10, 10, '2026-10-01T10:03:00');
  insMarca.run('projeto-teste', 'sessao-2', 'b.jsonl', 20, 20, '2026-10-01T10:04:00');
  const contagemOrigem = contagens(conexao);
  conexao.close();

  console.log('== 1. função devolve o caminho da cópia e o arquivo existe ==');
  const caminhoBackup = fazerBackupDoBanco(caminhoDb);
  const padrao = /rainforest-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$/;
  checa('caminho segue rainforest-<timestamp>.db', padrao.test(caminhoBackup), caminhoBackup);
  checa('caminho está em <raiz>/.rainforest-backups', path.dirname(caminhoBackup) === dirBackup, caminhoBackup);
  checa('arquivo de backup existe', fs.existsSync(caminhoBackup), caminhoBackup);

  console.log('== 2. cópia abre somente-leitura e tem as mesmas linhas por tabela ==');
  const ro = abrirBancoSomenteLeitura(caminhoBackup);
  if (!ro) {
    checa('cópia abre por abrirBancoSomenteLeitura', false, 'abrirBancoSomenteLeitura devolveu null');
  } else {
    const contagemCopia = contagens(ro);
    ro.close();
    checa('cópia abre por abrirBancoSomenteLeitura', true);
    checa(
      'backup tem as mesmas linhas do banco (count por tabela)',
      semelhante(contagemOrigem, contagemCopia),
      `origem=${JSON.stringify(contagemOrigem)} copia=${JSON.stringify(contagemCopia)}`
    );
    checa(
      'observacoes = 3 e marca_dagua = 2 na cópia',
      contagemCopia.observacoes === 3 && contagemCopia.marca_dagua === 2,
      JSON.stringify(contagemCopia)
    );
  }

  console.log('== 3. conexão de escrita aberta (WAL) com linha recém-inserida entra na cópia ==');
  const escritora = abrirBanco(caminhoDb);
  escritora.prepare(
    'INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)'
  ).run('projeto-teste', 'linha-wal-recem-inserida', '2026-10-02T09:00:00', 'origem-wal');
  const caminhoWal = fazerBackupDoBanco(caminhoDb);
  escritora.close();
  const roWal = abrirBancoSomenteLeitura(caminhoWal);
  if (!roWal) {
    checa('cópia com WAL abre somente-leitura', false, 'abrirBancoSomenteLeitura devolveu null');
  } else {
    const achou = roWal.prepare(
      "SELECT COUNT(*) AS n FROM observacoes WHERE conteudo = 'linha-wal-recem-inserida'"
    ).get().n;
    const totalWal = roWal.prepare('SELECT COUNT(*) AS n FROM observacoes').get().n;
    roWal.close();
    checa('cópia contém a linha inserida com WAL ativo', achou === 1, `achou=${achou}`);
    checa('cópia tem 4 observações (3 + a linha WAL)', totalWal === 4, `total=${totalWal}`);
  }

  console.log('== 4. banco inexistente faz a função LANÇAR Error ==');
  const inexistente = path.join(sandbox, 'nao-existe', 'rainforest.db');
  let lancou = null;
  try {
    fazerBackupDoBanco(inexistente);
  } catch (e) {
    lancou = e;
  }
  checa(
    'lança Error para banco ausente',
    lancou instanceof Error && /banco não existe/.test(lancou.message),
    lancou ? lancou.message : 'não lançou'
  );

  console.log('== 5. rotação mantém 5 cópias e nunca apaga a mais recente ==');
  // Cinco cópias antigas (2001) entram antes da chamada; a chamada cria uma sexta, a mais recente.
  for (let i = 1; i <= 5; i++) {
    fs.writeFileSync(path.join(dirBackup, `rainforest-2001-01-0${i}T00-00-00.db`), 'antiga');
  }
  const caminhoRotacao = fazerBackupDoBanco(caminhoDb);
  const restantes = fs.readdirSync(dirBackup).filter(f => f.startsWith('rainforest-') && f.endsWith('.db'));
  checa('mantém exatamente 5 cópias', restantes.length === 5, `restantes=${restantes.length}`);
  checa('a cópia mais recente continua existindo', fs.existsSync(caminhoRotacao), caminhoRotacao);
  checa(
    'a cópia mais antiga foi apagada',
    !fs.existsSync(path.join(dirBackup, 'rainforest-2001-01-01T00-00-00.db')),
    'rainforest-2001-01-01T00-00-00.db ainda existe'
  );

  console.log('== 6. comando backup: sucesso e banco ausente, via processo filho com RFM_ROOT ==');
  const env = { ...process.env, RFM_ROOT: caixa };
  const sucesso = cp.spawnSync(process.execPath, [path.join(SRC, 'scripts', 'memoria.cjs'), 'backup'], {
    env, cwd: caixa, encoding: 'utf8', timeout: 60000,
  });
  checa('backup com banco presente sai 0', sucesso.status === 0, `exit=${sucesso.status} stderr=${sucesso.stderr}`);
  checa(
    'backup com banco presente imprime "backup: <caminho>"',
    /^backup: .*\.db\s*$/m.test(sucesso.stdout || ''),
    `stdout=${sucesso.stdout}`
  );

  const vazia = path.join(sandbox, 'vazia');
  fs.mkdirSync(vazia);
  const ausente = cp.spawnSync(process.execPath, [path.join(SRC, 'scripts', 'memoria.cjs'), 'backup'], {
    env: { ...process.env, RFM_ROOT: vazia }, cwd: vazia, encoding: 'utf8', timeout: 60000,
  });
  checa('backup com banco ausente sai 1', ausente.status === 1, `exit=${ausente.status}`);
  checa(
    'backup com banco ausente imprime ERRO: banco não existe em no stderr',
    /ERRO: banco não existe em/.test(ausente.stderr || ''),
    `stderr=${ausente.stderr}`
  );
} catch (e) {
  falhou++;
  console.log(`  FALHA excecao inesperada: ${e && e.stack ? e.stack : e}`);
} finally {
  try { fs.rmSync(sandbox, { recursive: true, force: true }); } catch (_) {}
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou === 0 ? 0 : 1);
