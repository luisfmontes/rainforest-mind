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
const { abrirBanco, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

// Lê observações recentes do banco de memória, filtrando por projeto.
// Tarefa 3 (D3): top 5 do projeto atual, completa com outros se houver menos.
// Banco ausente, vazio ou corrompido: retorna array vazio (degradação graceful).
function lerObservacoes(caminhoDb, projetoAtual, limiteTotal = 5) {
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
      // Tarefa 3 (D3): Busca as observações do projeto atual, até o limite.
      const queryPropio = `
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE projeto = ?
        ORDER BY criada_em DESC
        LIMIT ?
      `;
      const stmtPropio = conexao.prepare(queryPropio);
      const obsProprio = stmtPropio.all(projetoAtual, limiteTotal) || [];

      // Se temos o limite, devolver só as próprias.
      if (obsProprio.length >= limiteTotal) {
        return obsProprio.slice(0, limiteTotal);
      }

      // Senão, completar com outras mais recentes (de outros projetos).
      const vagas = limiteTotal - obsProprio.length;
      const queryOutros = `
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE projeto != ?
        ORDER BY criada_em DESC
        LIMIT ?
      `;
      const stmtOutros = conexao.prepare(queryOutros);
      const obsOutros = stmtOutros.all(projetoAtual, vagas) || [];

      // Combinar: próprias primeiro (mais importantes), depois outros.
      // O projeto já está marcado no campo `projeto`, então formatarObservacao
      // vai mostrar [data (projeto)] para observações de outros projetos.
      return obsProprio.concat(obsOutros);
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

// Tarefa 3 (D3): Resolve o projeto da sessão atual para filtro.
// Se não conseguir resolver (fora de repositório), usa null e a consulta devolve todas.
let projetoAtual = null;
try {
  const { projeto } = resolverCaminhos();
  projetoAtual = projeto;
} catch {
  // Não conseguir resolver não é erro — continua sem filtro.
}

// Lê observações residentes.
// Tarefa 3 (D3): Filtra por projeto, completa com outros se houver vagas.
// Decisão D11: carregar múltiplas observações curtas (título + subtítulo)
// em vez de uma observação completa. Número calibrado pela medição.
let observacoes = [];
try {
  observacoes = lerObservacoes(caminhoDb, projetoAtual, 14);
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
