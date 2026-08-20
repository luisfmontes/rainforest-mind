#!/usr/bin/env node
// SessionStart hook: injeta as observações residentes da memória do rainforest.
//
// Este arquivo é o ADAPTADOR: só faz I/O (ler banco, imprimir).
// A montagem do bloco de memória injetado mora em lib/memoria-sessao.cjs,
// que é puro e tem bateria própria (hooks/testa-memoria-session-start.sh).
const fs = require('fs');
const path = require('path');
const { montarMemoria } = require('./lib/memoria-sessao.cjs');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { abrirBanco } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

// Lê observações recentes do banco de memória.
// Banco ausente, vazio ou corrompido: retorna array vazio (degradação graceful).
function lerObservacoes(caminhoDb, limite = 5) {
  try {
    // Se o banco não existe, array vazio é o resultado esperado.
    if (!fs.existsSync(caminhoDb)) {
      return [];
    }

    // Abre o banco (read-only, não cria se não existir).
    const conexao = abrirBanco(caminhoDb);
    if (!conexao) {
      return [];
    }

    try {
      // Busca as observações mais recentes.
      const query = 'SELECT id, projeto, conteudo, criada_em FROM observacoes ORDER BY criada_em DESC LIMIT ?';
      const stmt = conexao.prepare(query);
      const resultado = stmt.all(limite);
      return resultado || [];
    } finally {
      conexao.close();
    }
  } catch (e) {
    // Banco corrompido, erro ao abrir, etc.: degradação para array vazio.
    // A invariante do plano: memória indisponível nunca bloqueia a sessão.
    return [];
  }
}

// Resolve caminhos da raiz de dados.
const { raiz: RAIZ_RESOLVIDA } = resolverRaiz({
  plugin: path.resolve(__dirname, '..'),
});

const ROOT = RAIZ_RESOLVIDA || path.resolve(__dirname, '..');
const caminhoDb = path.join(ROOT, 'rainforest.db');

// Lê observações residentes.
// Decisão D11: carregar múltiplas observações curtas (título + subtítulo)
// em vez de uma observação completa. Número calibrado pela medição.
let observacoes = [];
try {
  observacoes = lerObservacoes(caminhoDb, 14);
} catch {
  // Qualquer erro imprevisto: bloco vazio, nunca erro.
  observacoes = [];
}

// Monta o bloco de memória.
const bloco = montarMemoria({ observacoes });

// JSON, não texto cru (regra 12 do hook foco-session-start).
// O harness lê `additionalContext` e o stdout ao redor não conta para o teto.
console.log(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'SessionStart',
    additionalContext: bloco,
  },
}));
