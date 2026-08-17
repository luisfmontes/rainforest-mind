#!/usr/bin/env node
/**
 * Gerenciador do banco de dados da memória do rainforest.
 *
 * Por que existe: o rainforest precisa de seu próprio store de memória para
 * sair da dependência frágil do claude-mem. O banco é consultável,
 * versionável e não sofre com os ~3.800 spawns diários que o caminho
 * de escrita do claude-mem provoca (decisão D2).
 *
 * Driver: node:sqlite (decisão D8). Zero dependência externa; experimental
 * em Node 22, mas isolado neste adaptador para absorver mudanças de API.
 *
 * Raiz de dados: cadeia de 4 níveis resolvida por hooks/lib/raiz.cjs
 * (decisão D9) — RFM_ROOT > projeto/.rainforest > ~/.rainforest > plugin.
 *
 * Uso:
 *   node scripts/memoria.cjs iniciar                 criar/abrir o banco
 *   node scripts/memoria.cjs esquema [--json]        listar schema do banco
 *   node scripts/memoria.cjs buscar [opções]         buscar observações
 *   node scripts/memoria.cjs backup                  fazer backup do banco
 *   node scripts/memoria.cjs reindexar               reconstruir índices
 */

const fs = require('fs');
const path = require('path');

// node:sqlite — built-in desde Node 22.0.0. Status: estável (Node 23.1+),
// experimental antes disso. O adaptador deste arquivo absorve mudanças.
let sqlite3 = null;
try {
  sqlite3 = require('node:sqlite');
} catch (e) {
  console.error('ERRO: node:sqlite não disponível');
  console.error('Requer: Node.js 22.0.0 ou superior');
  process.exit(1);
}

// Resolve a raiz de dados e o projeto — cadeia de 4 níveis (D9).
// RFM_ROOT > projeto/.rainforest > ~/.rainforest > plugin
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

function resolverCaminhos() {
  const { raiz } = resolverRaiz({
    plugin: path.resolve(__dirname, '..'),
  });

  if (!raiz) {
    console.error('ERRO: Nenhuma raiz de dados encontrada');
    console.error('Configure RFM_ROOT, use .rainforest no projeto, ou rode o setup');
    process.exit(1);
  }

  // Coluna `projeto` dentro de observacoes (D9) — precisa saber de quem
  // é a raiz. Se vier de RFM_ROOT, a raiz é só um caminho; se vier do
  // projeto, temos que guardar qual projeto. Padrão: nome da pasta da raiz.
  const projeto = path.basename(raiz) === '.rainforest'
    ? path.basename(path.dirname(raiz))
    : path.basename(raiz);

  const caminhoDb = path.join(raiz, 'rainforest.db');

  return { raiz, caminhoDb, projeto };
}

// Abre conexão com o banco. Cria se não existe. Retorna a conexão.
function abrirBanco(caminhoDb) {
  // sqlite3.open retorna uma Promise; aqui usamos await em contexto
  // async, ou podemos usar synchronous method se disponível. Node 22
  // oferece sync via openSync no namespace sqlite.
  //
  // Para Node 22 + 23, usamos DatabaseSync (synchronous).
  try {
    const DatabaseSync = require('node:sqlite').DatabaseSync;
    const conexao = new DatabaseSync(caminhoDb);
    // WAL mode para concorrência: leitura não bloqueia escrita.
    conexao.exec('PRAGMA journal_mode = WAL;');
    return conexao;
  } catch (e) {
    // Fallback para versões antigas de Node 22 que não têm DatabaseSync
    console.error('ERRO: Não consegui abrir DatabaseSync do node:sqlite');
    console.error(`Detalhes: ${e.message}`);
    process.exit(1);
  }
}

// Executa o schema SQL no banco.
function criarSchema(conexao) {
  const caminhoSchema = path.resolve(__dirname, 'esquema-memoria.sql');
  if (!fs.existsSync(caminhoSchema)) {
    console.error(`ERRO: ${caminhoSchema} não encontrado`);
    process.exit(1);
  }

  const sql = fs.readFileSync(caminhoSchema, 'utf8');
  // Dividir por `;` não é parsing robusto, mas o arquivo é nosso e controlado.
  // Para arquivos SQL arbitrários isso falharia com comentários dentro de strings,
  // mas aqui temos apenas CREATE TABLE IF NOT EXISTS (idempotentes).
  const statements = sql
    .split(';')
    .map(s => s.trim())
    .filter(s => s.length > 0);

  for (const stmt of statements) {
    try {
      conexao.exec(stmt);
    } catch (e) {
      // Ignorar erro de "já existe" para IF NOT EXISTS
      if (!e.message.includes('already exists')) {
        throw e;
      }
    }
  }
}

// Retorna schema como JSON (comando `esquema --json`).
function extrairSchema(conexao) {
  const tabelas = {};

  // Listar todas as tabelas criadas por nós (excluir sqlite_* internas).
  const resultado = conexao.prepare(
    `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`
  ).all();

  for (const { name: tabela } of resultado) {
    // PRAGMA table_info retorna info de cada coluna.
    const colunas = conexao.prepare(`PRAGMA table_info(${tabela})`).all();
    const colunasFormatadas = {};

    for (const { name: nome, type: tipo, notnull, pk } of colunas) {
      colunasFormatadas[nome] = {
        tipo,
        naoNulo: notnull === 1,
        chavePrimaria: pk === 1,
      };
    }

    tabelas[tabela] = colunasFormatadas;
  }

  return tabelas;
}

// Popula o índice FTS5 com observações existentes no banco.
function popularFts5(conexao) {
  try {
    // Limpar índice anterior se existe (para reindexação).
    try {
      conexao.exec('DELETE FROM observacoes_fts');
    } catch (e) {
      // Ignorar se tabela não existe ainda (primeira execução).
    }

    // Inserir todas as observações no índice FTS5.
    const linhas = conexao.prepare('SELECT id, conteudo FROM observacoes').all();
    const stmt = conexao.prepare('INSERT INTO observacoes_fts(rowid, conteudo) VALUES (?, ?)');

    for (const { id, conteudo } of linhas) {
      stmt.run(id, conteudo);
    }
  } catch (e) {
    // Não é crítico falhar aqui; FTS5 pode ser reconstruída depois.
    // Mas logamos para debug.
    console.error(`AVISO: não consegui popular FTS5: ${e.message}`);
  }
}

// Comando: iniciar — criar/abrir o banco, verificar schema.
function cmdIniciar() {
  const { raiz, caminhoDb, projeto } = resolverCaminhos();

  // Criar diretório se não existe.
  fs.mkdirSync(raiz, { recursive: true });

  const conexao = abrirBanco(caminhoDb);
  criarSchema(conexao);

  // Popular índice FTS5 (idempotente).
  popularFts5(conexao);

  console.log(`ok: banco em ${caminhoDb} (projeto: ${projeto})`);

  // Retornar exit 0 implicitamente.
  conexao.close();
}

// Comando: esquema [--json] — listar o schema do banco.
function cmdEsquema() {
  const { caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    console.error(`ERRO: banco não existe em ${caminhoDb}`);
    console.error('rode: node scripts/memoria.cjs iniciar');
    process.exit(1);
  }

  const conexao = abrirBanco(caminhoDb);
  const schema = extrairSchema(conexao);
  conexao.close();

  // Verificar se --json foi passado (segunda linha de CLI).
  const args = process.argv.slice(3);
  const ehJson = args.includes('--json');

  if (ehJson) {
    console.log(JSON.stringify(schema, null, 2));
  } else {
    // Formato legível para humanos.
    for (const [tabela, colunas] of Object.entries(schema)) {
      console.log(`\n${tabela}:`);
      for (const [nome, info] of Object.entries(colunas)) {
        const flags = [
          info.chavePrimaria ? 'PK' : '',
          info.naoNulo ? 'NOT NULL' : 'NULL',
        ].filter(f => f).join(' ');
        console.log(`  ${nome}: ${info.tipo} (${flags})`);
      }
    }
  }
}

// Comando: buscar [--texto "..."] [--projeto "..."] [--limite N] [--json]
// Busca observações usando FTS5. Degradação: banco ausente/vazio/corrompido
// devolve resultado vazio com exit 0, nunca erro.
function cmdBuscar() {
  const { caminhoDb } = resolverCaminhos();

  // Parser de argumentos simples.
  function arg(nome) {
    const i = process.argv.indexOf(`--${nome}`);
    if (i === -1 || i + 1 >= process.argv.length) return null;
    return process.argv[i + 1];
  }

  const texto = arg('texto') || '';
  const projeto = arg('projeto') || null;
  const limite = parseInt(arg('limite') || '10', 10);
  const ehJson = process.argv.includes('--json');

  // Resultado padrão: array vazio (degradação).
  let resultados = [];

  try {
    // Degradação: banco não existe — devolver array vazio, exit 0.
    if (!fs.existsSync(caminhoDb)) {
      if (ehJson) {
        console.log(JSON.stringify(resultados, null, 2));
      } else {
        console.log('(banco não existe)');
      }
      return;
    }

    const conexao = abrirBanco(caminhoDb);

    // Se há texto, usar FTS5; senão, listar recentes.
    let query;
    const params = { limite };

    if (texto) {
      // Busca FTS5: combinar conteúdo com projeto se fornecido.
      query = `
        SELECT o.id, o.projeto, o.conteudo, o.criada_em
        FROM observacoes o
        WHERE o.id IN (
          SELECT rowid FROM observacoes_fts WHERE conteudo MATCH :fts_query
        )
      `;
      params.fts_query = texto; // FTS5 syntax: "palavra" ou "palavra1 AND palavra2"

      if (projeto) {
        query += ' AND o.projeto = :projeto';
        params.projeto = projeto;
      }
    } else {
      // Sem texto: listar recentes de um projeto (se fornecido).
      query = 'SELECT id, projeto, conteudo, criada_em FROM observacoes';

      if (projeto) {
        query += ' WHERE projeto = :projeto';
        params.projeto = projeto;
      }
    }

    query += ' ORDER BY criada_em DESC LIMIT :limite';

    const stmt = conexao.prepare(query);
    resultados = stmt.all(params);
    conexao.close();
  } catch (e) {
    // Degradação: banco corrompido ou outro erro — resultado vazio, exit 0.
    // Aviso só no stderr para não poluir JSON de saída.
    if (!ehJson) {
      console.error(`AVISO: não consegui buscar no banco: ${e.message}`);
    }
    resultados = [];
  }

  // Saída.
  if (ehJson) {
    console.log(JSON.stringify(resultados, null, 2));
  } else {
    if (!resultados.length) {
      console.log('(nenhum resultado)');
      return;
    }
    for (const obs of resultados) {
      console.log(`[${obs.id}] ${obs.projeto} - ${obs.criada_em}`);
      console.log(`  ${obs.conteudo.substring(0, 100)}`);
    }
  }
}

// Comando: backup — copiar o banco para pasta de backup com timestamp.
function cmdBackup() {
  const { raiz, caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    console.error(`ERRO: banco não existe em ${caminhoDb}`);
    process.exit(1);
  }

  const dirBackup = path.join(raiz, '.rainforest-backups');
  fs.mkdirSync(dirBackup, { recursive: true });

  // Timestamp ISO local (não UTC).
  const agora = new Date();
  const ano = agora.getFullYear();
  const mes = String(agora.getMonth() + 1).padStart(2, '0');
  const dia = String(agora.getDate()).padStart(2, '0');
  const horas = String(agora.getHours()).padStart(2, '0');
  const minutos = String(agora.getMinutes()).padStart(2, '0');
  const segundos = String(agora.getSeconds()).padStart(2, '0');

  const timestamp = `${ano}-${mes}-${dia}T${horas}-${minutos}-${segundos}`;
  const caminhoBackup = path.join(dirBackup, `rainforest-${timestamp}.db`);

  // Copiar arquivo binário.
  fs.copyFileSync(caminhoDb, caminhoBackup);

  console.log(`backup: ${caminhoBackup}`);

  // Manter apenas os 5 backups mais recentes.
  const teto = 5;
  const arquivos = fs.readdirSync(dirBackup)
    .filter(f => f.startsWith('rainforest-') && f.endsWith('.db'))
    .sort()
    .reverse();

  for (let i = teto; i < arquivos.length; i++) {
    const antigo = path.join(dirBackup, arquivos[i]);
    fs.unlinkSync(antigo);
  }
}

// Comando: reindexar — reconstruir índice FTS5 do zero.
// Útil se FTS5 ficar desincronizado ou corrompido.
function cmdReindexar() {
  const { caminhoDb } = resolverCaminhos();

  // Degradação: banco não existe — exit 0 com mensagem clara.
  if (!fs.existsSync(caminhoDb)) {
    console.log(`(banco não existe em ${caminhoDb}; nada a reindexar)`);
    return;
  }

  try {
    const conexao = abrirBanco(caminhoDb);

    // Apagar índice FTS antigo.
    try {
      conexao.exec('DELETE FROM observacoes_fts');
    } catch (e) {
      // Ignorar se não existe.
    }

    // Reconstruir do zero.
    popularFts5(conexao);

    console.log(`ok: índice FTS5 reconstruído (${caminhoDb})`);
    conexao.close();
  } catch (e) {
    // Degradação: erro ao reindexar — exit 0 com aviso.
    console.error(`AVISO: não consegui reindexar: ${e.message}`);
  }
}

// ---- CLI

function main() {
  const cmd = process.argv[2];

  switch (cmd) {
    case 'iniciar':
      return cmdIniciar();
    case 'esquema':
      return cmdEsquema();
    case 'buscar':
      return cmdBuscar();
    case 'backup':
      return cmdBackup();
    case 'reindexar':
      return cmdReindexar();
    default:
      console.error(`Comando desconhecido: ${cmd}`);
      console.error('Use: iniciar | esquema | buscar | backup | reindexar');
      process.exit(1);
  }
}

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error(`ERRO: ${e.message}`);
    process.exit(1);
  }
}

module.exports = { abrirBanco, criarSchema, extrairSchema, resolverCaminhos };
