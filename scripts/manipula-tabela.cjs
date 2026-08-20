#!/usr/bin/env node
/**
 * Manipula dados em rainforest.db — insere registros, limpa tabelas, conta linhas.
 * Adaptador para testes (D8 — driver isolado).
 *
 * Uso:
 *   node scripts/manipula-tabela.cjs insere-resumo <projeto> <titulo> <conteudo>
 *   node scripts/manipula-tabela.cjs insere-observacao <projeto> <conteudo>
 *   node scripts/manipula-tabela.cjs limpa <tabela>
 *   node scripts/manipula-tabela.cjs conta <tabela>
 *   node scripts/manipula-tabela.cjs conta-multi <tab1> <tab2> [<tab3>...]
 */

const path = require('path');
const { abrirBanco, abrirBancoSomenteLeitura, resolverCaminhos } = require('./memoria.cjs');

function main() {
  const cmd = process.argv[2];
  const conexao = abrirBanco(resolverCaminhos().caminhoDb);

  try {
    switch (cmd) {
      case 'insere-resumo': {
        const projeto = process.argv[3];
        const titulo = process.argv[4];
        const conteudo = process.argv[5];
        if (!projeto || !titulo || !conteudo) {
          console.error('Uso: manipula-tabela.cjs insere-resumo <projeto> <titulo> <conteudo>');
          process.exit(1);
        }
        conexao.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)')
          .run(projeto, titulo, conteudo, new Date().toISOString());
        console.log('ok');
        break;
      }

      case 'insere-observacao': {
        const projeto = process.argv[3];
        const conteudo = process.argv[4];
        if (!projeto || !conteudo) {
          console.error('Uso: manipula-tabela.cjs insere-observacao <projeto> <conteudo>');
          process.exit(1);
        }
        conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em) VALUES (?, ?, ?)')
          .run(projeto, conteudo, new Date().toISOString());
        console.log('ok');
        break;
      }

      case 'limpa': {
        const tabela = process.argv[3];
        if (!tabela || !/^[a-z_]+$/i.test(tabela)) {
          console.error('Uso: manipula-tabela.cjs limpa <tabela>');
          process.exit(1);
        }
        conexao.exec(`DELETE FROM ${tabela}`);
        console.log('ok');
        break;
      }

      case 'conta': {
        const tabela = process.argv[3];
        if (!tabela || !/^[a-z_]+$/i.test(tabela)) {
          console.error('Uso: manipula-tabela.cjs conta <tabela>');
          process.exit(1);
        }
        const resultado = conexao.prepare(`SELECT COUNT(*) as cnt FROM ${tabela}`).get();
        console.log(resultado.cnt || 0);
        break;
      }

      case 'conta-multi': {
        const tabelas = process.argv.slice(3);
        if (tabelas.length === 0) {
          console.error('Uso: manipula-tabela.cjs conta-multi <tab1> [<tab2> ...]');
          process.exit(1);
        }
        const resultados = [];
        for (const tabela of tabelas) {
          if (!/^[a-z_]+$/i.test(tabela)) continue;
          const r = conexao.prepare(`SELECT COUNT(*) as cnt FROM ${tabela}`).get();
          resultados.push(`${tabela}=${r.cnt || 0}`);
        }
        console.log(resultados.join(' '));
        break;
      }

      case 'insere-observacao-fixture': {
        const projeto = process.argv[3];
        const conteudo = process.argv[4];
        if (!projeto || !conteudo) {
          console.error('Uso: manipula-tabela.cjs insere-observacao-fixture <projeto> <conteudo>');
          process.exit(1);
        }
        conexao.exec('PRAGMA journal_mode = WAL;');
        conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em) VALUES (?, ?, ?)')
          .run(projeto, conteudo, '2026-08-17T10:00:00');
        conexao.exec('PRAGMA wal_checkpoint(TRUNCATE);');
        console.log('ok');
        break;
      }

      case 'conta-observacoes-backup': {
        const caminhoBackup = process.argv[3];
        if (!caminhoBackup) {
          console.error('Uso: manipula-tabela.cjs conta-observacoes-backup <caminho-backup>');
          process.exit(1);
        }
        const dbBackup = abrirBancoSomenteLeitura(caminhoBackup);
        if (!dbBackup) {
          console.error('erro: nao consegui abrir o backup');
          process.exit(1);
        }
        try {
          const result = dbBackup.prepare('SELECT COUNT(*) as cnt FROM observacoes').get();
          console.log(result.cnt);
        } finally {
          dbBackup.close();
        }
        break;
      }

      default:
        console.error('Comando desconhecido: ' + cmd);
        process.exit(1);
    }
  } catch (e) {
    console.error('erro: ' + e.message);
    process.exit(1);
  } finally {
    conexao.close();
  }
}

if (require.main === module) {
  main();
}

module.exports = {};
