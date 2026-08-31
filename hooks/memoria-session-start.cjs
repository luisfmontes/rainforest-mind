#!/usr/bin/env node
// SessionStart hook: injeta as observações residentes da memória do rainforest.
//
// Este arquivo é o ADAPTADOR: só faz I/O (ler banco, imprimir).
// A montagem do bloco de memória injetado mora em lib/memoria-sessao.cjs,
// que é puro e tem bateria própria (hooks/testa-memoria-session-start.sh).
const fs = require('fs');
const path = require('path');
const { montarMemoria, montarLegendaMemoria } = require('./lib/memoria-sessao.cjs');
const { tituloDoFocoAtivo } = require('./lib/contexto-sessao.cjs');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { abrirBanco, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

// Extrai termos de busca do título do foco ativo.
// Retorna array de termos (palavras com >2 caracteres, em minúsculas).
// Tarefa 3 (D2): os termos vêm do TÍTULO do foco ativo (primeira linha em negrito).
function extrairTermosDoBuscar(titulo) {
  if (!titulo) return [];

  // Stop words em português que não agregam significado na busca
  const stopWords = new Set([
    'a', 'o', 'de', 'da', 'do', 'e', 'ou', 'é', 'são', 'um', 'uma',
    'que', 'no', 'na', 'com', 'por', 'para', 'em', 'se', 'à', 'ao',
    'os', 'as', 'dos', 'das', 'ele', 'ela', 'eles', 'elas', 'nós',
    'me', 'te', 'lhe', 'nos', 'vos', 'lhes', 'meu', 'teu', 'seu',
    'nosso', 'vosso', 'dele', 'dela', 'deles', 'delas', 'este',
    'esse', 'aquele', 'isto', 'isso', 'aquilo', 'já', 'ainda',
    'quando', 'onde', 'como', 'qual', 'quais', 'quanto', 'quantos',
  ]);

  // Quebra o título em palavras, remove stop words e palavras curtas
  const termos = titulo
    .toLowerCase()
    .split(/\s+/)
    .map(p => p.replace(/[^a-záéíóúâêôãõçñ0-9]/g, '')) // Remove pontuação
    .filter(p => p.length > 2 && !stopWords.has(p))
    .slice(0, 5); // Máximo 5 termos para não explodir a busca FTS

  return termos;
}

// Consulta o banco por observações recentes + casadas por FTS com os termos do foco.
// Tarefa 3 (D2): 9 recentes + até 5 casadas com o foco (filtrando as já-recentes por id).
// C3: EXCLUIR observações consolidadas (consolidada_em IS NOT NULL) da disputa de vagas.
// Retorna array com até 14 observações. Sem termos ou FTS indisponível: 14 recentes.
function lerObservacoesComFTS(caminhoDb, projetosList, termos) {
  try {
    if (!fs.existsSync(caminhoDb)) return [];

    const conexao = abrirBanco(caminhoDb);
    if (!conexao) return [];

    try {
      // C3: Passo 1: Buscar 9 recentes, EXCLUINDO consolidadas
      const queryRecentes = projetosList && projetosList.length > 0
        ? `
          SELECT id, projeto, conteudo, criada_em
          FROM observacoes
          WHERE projeto IN (${projetosList.map(() => '?').join(', ')})
          AND consolidada_em IS NULL
          ORDER BY criada_em DESC
          LIMIT 9
        `
        : `
          SELECT id, projeto, conteudo, criada_em
          FROM observacoes
          WHERE consolidada_em IS NULL
          ORDER BY criada_em DESC
          LIMIT 9
        `;

      const stmtRecentes = conexao.prepare(queryRecentes);
      const recentes = projetosList && projetosList.length > 0
        ? stmtRecentes.all(...projetosList) || []
        : stmtRecentes.all() || [];

      // Passo 2: Buscar casadas por FTS (máximo 5), filtrando as já-recentes por id
      // C3: EXCLUIR consolidadas das casadas também
      // Se FTS falhar (tabela não existe ou corrompida), fazer fallback para 14 recentes
      let casadas = [];
      try {
        const idsRecentes = recentes.map(r => r.id);
        const placeholdersIds = idsRecentes.map(() => '?').join(', ');
        const termoFTS = termos.join(' OR '); // FTS5: termos separados por OR

        // A consulta FTS deve descartar as linhas que já estão em recentes
        // E também descartar consolidadas (C3)
        const queryCasadas = `
          SELECT o.id, o.projeto, o.conteudo, o.criada_em
          FROM observacoes o
          WHERE o.consolidada_em IS NULL
          AND o.id IN (
            SELECT rowid FROM observacoes_fts
            WHERE observacoes_fts MATCH ?
          )
          ${idsRecentes.length > 0 ? `AND o.id NOT IN (${placeholdersIds})` : ''}
          ORDER BY o.criada_em DESC
          LIMIT 5
        `;

        const stmtCasadas = conexao.prepare(queryCasadas);
        casadas = idsRecentes.length > 0
          ? stmtCasadas.all(termoFTS, ...idsRecentes) || []
          : stmtCasadas.all(termoFTS) || [];
      } catch (e) {
        // FTS indisponível (tabela não existe ou corrompida): fallback para 14 recentes
        // Retorna 14 recentes SEM aplicar FTS (comportamento byte-idêntico ao fallback sem foco)
        // C3: EXCLUIR consolidadas no fallback também
        if (projetosList && projetosList.length > 0) {
          const placeholders = projetosList.map(() => '?').join(', ');
          const queryFallback = `
            SELECT id, projeto, conteudo, criada_em
            FROM observacoes
            WHERE projeto IN (${placeholders})
            AND consolidada_em IS NULL
            ORDER BY criada_em DESC
            LIMIT 14
          `;
          const stmtFallback = conexao.prepare(queryFallback);
          const resultado = stmtFallback.all(...projetosList) || [];

          // Se temos 14, devolver. Senão, completar com outros
          if (resultado.length >= 14) {
            return resultado.slice(0, 14);
          }

          const vagas = 14 - resultado.length;
          const placeholdersNot = projetosList.map(() => '?').join(', ');
          const queryOutros = `
            SELECT id, projeto, conteudo, criada_em
            FROM observacoes
            WHERE projeto NOT IN (${placeholdersNot})
            AND consolidada_em IS NULL
            ORDER BY criada_em DESC
            LIMIT ?
          `;
          const stmtOutros = conexao.prepare(queryOutros);
          const outros = stmtOutros.all(...projetosList, vagas) || [];
          return resultado.concat(outros);
        } else {
          const queryFallback = `
            SELECT id, projeto, conteudo, criada_em
            FROM observacoes
            WHERE consolidada_em IS NULL
            ORDER BY criada_em DESC
            LIMIT 14
          `;
          const stmtFallback = conexao.prepare(queryFallback);
          return stmtFallback.all() || [];
        }
      }

      // Combinar: recentes + casadas (máximo 14)
      return recentes.concat(casadas);
    } finally {
      conexao.close();
    }
  } catch (e) {
    // Banco corrompido, erro ao abrir, etc.: degradação para array vazio.
    return [];
  }
}

// Lê observações recentes do banco de memória, filtrando por lista de projetos.
// Tarefa 3 (D3): top 5 dos projetos atuais (múltiplas chaves), completa com outros se houver menos.
// C3: EXCLUIR observações consolidadas (consolidada_em IS NOT NULL) da disputa de vagas.
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
      // C3: EXCLUIR consolidadas
      if (!projetosList || projetosList.length === 0) {
        const queryTudo = `
          SELECT id, projeto, conteudo, criada_em
          FROM observacoes
          WHERE consolidada_em IS NULL
          ORDER BY criada_em DESC
          LIMIT ?
        `;
        const stmtTudo = conexao.prepare(queryTudo);
        const resultado = stmtTudo.all(limiteTotal) || [];
        return resultado;
      }

      // Tarefa 3 (D3): Busca as observações dos projetos na lista, até o limite.
      // C3: EXCLUIR consolidadas
      // Monta dinamicamente: WHERE projeto IN (?, ?, ...)
      const placeholders = projetosList.map(() => '?').join(', ');
      const queryPropio = `
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE projeto IN (${placeholders})
        AND consolidada_em IS NULL
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
        AND consolidada_em IS NULL
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

// Função auxiliar para ler arquivo com segurança
function readSafe(p) {
  try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; }
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

// C3: Busca resumos recentes para entrar na disputa de vagas.
// Retorna array de resumos formatados como pseudo-observações com prefixo distinguível.
function buscarResumosRecentes(caminhoDb, projetosList, limite = 5) {
  try {
    if (!fs.existsSync(caminhoDb)) return [];

    const conexao = abrirBanco(caminhoDb);
    if (!conexao) return [];

    try {
      const placeholders = projetosList && projetosList.length > 0
        ? `WHERE projeto IN (${projetosList.map(() => '?').join(', ')})`
        : '';

      const query = `
        SELECT id, projeto, titulo, conteudo, criada_em
        FROM resumos
        ${placeholders}
        ORDER BY criada_em DESC
        LIMIT ?
      `;

      const stmt = conexao.prepare(query);
      const params = projetosList && projetosList.length > 0
        ? [...projetosList, limite]
        : [limite];

      const resumos = stmt.all(...params) || [];

      // Converter resumos para formato de pseudo-observação
      // com prefixo [resumo até <data>] no conteúdo para distinguir
      return resumos.map(r => ({
        id: `resumo_${r.id}`,  // ID único para resumos
        projeto: r.projeto,
        conteudo: `## [resumo até ${(r.criada_em || '').split('T')[0]}]\n\n${r.titulo}\n\n${r.conteudo}`,
        criada_em: r.criada_em,
      }));
    } finally {
      conexao.close();
    }
  } catch (e) {
    // Erro ao buscar resumos não bloqueia: degradação graceful
    return [];
  }
}

// Lê observações residentes.
// Tarefa 3 (D2): Se houver foco ativo, busca 9 recentes + até 5 casadas com os termos do foco.
// C3: Combina observações com resumos recentes; ambos disputam as 14 vagas.
// Sem foco, sem termos ou FTS indisponível: 14 recentes como hoje (fallback).
let observacoes = [];
try {
  // Extrai os termos do foco ativo para FTS
  const focoText = readSafe(path.join(ROOT, 'FOCO.md'));
  const tituloFoco = tituloDoFocoAtivo(focoText);
  const termosBusca = extrairTermosDoBuscar(tituloFoco);

  // Se tem termos, usa a consulta com FTS (9 + até 5)
  // Senão, usa o fallback de 14 recentes
  let obsRecentes = [];
  if (termosBusca && termosBusca.length > 0) {
    obsRecentes = lerObservacoesComFTS(caminhoDb, projetosList, termosBusca);
  } else {
    obsRecentes = lerObservacoes(caminhoDb, projetosList, 14);
  }

  // C3: Buscar resumos e combinar com observações
  // Ambos disputam as 14 vagas; ordenar por data descrescente e pegar top 14
  const resumosRecentes = buscarResumosRecentes(caminhoDb, projetosList, 5);

  // Combinar observações e resumos, ordenar por criada_em DESC, pegar top 14
  const combinado = obsRecentes.concat(resumosRecentes);
  observacoes = combinado
    .sort((a, b) => (b.criada_em || '').localeCompare(a.criada_em || ''))
    .slice(0, 14);
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
