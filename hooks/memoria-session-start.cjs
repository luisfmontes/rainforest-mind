#!/usr/bin/env node
// SessionStart hook: injeta as observações residentes da memória do rainforest.
//
// Este arquivo é o ADAPTADOR: só faz I/O (ler banco, imprimir).
// A montagem do bloco de memória injetado mora em lib/memoria-sessao.cjs,
// que é puro e tem bateria própria (hooks/testa-memoria-session-start.sh).
const fs = require('fs');
const path = require('path');
const { montarMemoria, montarLegendaMemoria } = require('./lib/memoria-sessao.cjs');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { abrirBanco, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

// Lê observações recentes do banco de memória, filtrando por lista de projetos.
// Tarefa 3 (D3): top 5 dos projetos atuais (múltiplas chaves), completa com outros se houver menos.
// Correção D13b: leitor consulta AMBAS as chaves (harness e curta) para não perder histórico.
// Banco ausente, vazio ou corrompido: retorna array vazio (degradação graceful).
// Parâmetro `projetosList`: array de strings (chaves), ou null/vazio → sem filtro.
function lerObservacoes(caminhoDb, projetosList, limiteTotal = 5) {
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
      // Tarefa 3 (D3): Se lista de projetos está vazia ou nula, busca sem filtro (fallback).
      if (!projetosList || projetosList.length === 0) {
        const queryTudo = `
          SELECT id, projeto, conteudo, criada_em
          FROM observacoes
          ORDER BY criada_em DESC
          LIMIT ?
        `;
        const stmtTudo = conexao.prepare(queryTudo);
        const resultado = stmtTudo.all(limiteTotal) || [];
        return resultado;
      }

      // Tarefa 3 (D3): Busca as observações dos projetos na lista, até o limite.
      // Monta dinamicamente: WHERE projeto IN (?, ?, ...)
      const placeholders = projetosList.map(() => '?').join(', ');
      const queryPropio = `
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE projeto IN (${placeholders})
        ORDER BY criada_em DESC
        LIMIT ?
      `;
      const stmtPropio = conexao.prepare(queryPropio);
      const obsProprio = stmtPropio.all(...projetosList, limiteTotal) || [];

      // Se temos o limite, devolver só as próprias.
      if (obsProprio.length >= limiteTotal) {
        return obsProprio.slice(0, limiteTotal);
      }

      // Senão, completar com outras mais recentes (de outros projetos).
      const vagas = limiteTotal - obsProprio.length;
      const placeholdersNot = projetosList.map(() => '?').join(', ');
      const queryOutros = `
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE projeto NOT IN (${placeholdersNot})
        ORDER BY criada_em DESC
        LIMIT ?
      `;
      const stmtOutros = conexao.prepare(queryOutros);
      const obsOutros = stmtOutros.all(...projetosList, vagas) || [];

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

// Tarefa 3 (D3): Resolve os projetos da sessão atual para filtro.
// Retorna array com chave harness + chave curta (sem duplicatas).
// Se não conseguir resolver (fora de repositório), usa null e a consulta devolve todas.
// Correção D13b: consultar ambas as chaves para não perder histórico sob chave curta.
let projetosList = null;
// Apelidos de exibição: o banco guarda a chave de pasta do harness, que é longa.
// O rótulo mostra o nome curto do projeto, e o teto de bytes rende mais linhas.
let apelidos = null;
try {
  const { projetos } = resolverCaminhos();
  projetosList = projetos;
  if (Array.isArray(projetos) && projetos.length > 1) {
    // projetos = [chaveHarness, nomeCurto]; o primeiro exibe como o segundo.
    apelidos = { [projetos[0]]: projetos[projetos.length - 1] };
  }
} catch {
  // Não conseguir resolver não é erro — continua sem filtro.
}

// Lê observações residentes.
// Tarefa 3 (D3): Filtra por lista de projetos, completa com outros se houver vagas.
// Decisão D11: carregar múltiplas observações curtas (título + subtítulo)
// em vez de uma observação completa. Número calibrado pela medição.
let observacoes = [];
try {
  observacoes = lerObservacoes(caminhoDb, projetosList, 14);
} catch {
  // Qualquer erro imprevisto: bloco vazio, nunca erro.
  observacoes = [];
}

// Monta o bloco de memória.
const bloco = montarMemoria({ observacoes, apelidos });

// JSON, não texto cru (regra 12 do hook foco-session-start).
// O harness lê `additionalContext` e o stdout ao redor não conta para o teto.
// A legenda é o MESMO corpus, outro público: `additionalContext` é o que o modelo
// recebe (14 marcas), `systemMessage` é o que o usuario VÊ (as 2 mais recentes).
// Até 2026-08-25 só existia o primeiro, e a abertura era muda para ele.
const legenda = montarLegendaMemoria({ observacoes, apelidos });

const saida = {
  hookSpecificOutput: {
    hookEventName: 'SessionStart',
    additionalContext: bloco,
  },
};
// Sem marca nenhuma, campo ausente: caixa vazia na tela é pior que tela limpa.
if (legenda) saida.systemMessage = legenda;
console.log(JSON.stringify(saida));
