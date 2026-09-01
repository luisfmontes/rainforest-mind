#!/usr/bin/env node
/**
 * Relatório de fase 0 da poda: gate de saída baseado em dias-calendário distintos.
 *
 * Uso:
 *   node scripts/relatorio-poda.cjs [--json]
 *
 * Exit 0: gate aberto (>=7 dias distintos)
 * Exit 1: gate fechado (<7 dias distintos)
 */

'use strict';

const fs = require('fs');
const { caminhoMetricas } = require('../hooks/lib/poda-dados.cjs');

/**
 * Lê e processa metricas.jsonl
 */
function lerMetricas(caminhoArq) {
  if (!caminhoArq || !fs.existsSync(caminhoArq)) {
    return [];
  }

  const linhas = fs.readFileSync(caminhoArq, 'utf8').trim().split('\n').filter(l => l);
  const metricas = [];

  for (const linha of linhas) {
    try {
      metricas.push(JSON.parse(linha));
    } catch {
      // linha inválida, ignora
    }
  }

  return metricas;
}

/**
 * Extrai dias-calendário distintos das métricas (AAAA-MM-DD)
 */
function extrairDiasDistintos(metricas) {
  const dias = new Set();

  for (const metrica of metricas) {
    if (metrica.timestamp) {
      // timestamp é ISO 8601: 2026-08-31T14:30:00.000Z
      // extrai apenas a data AAAA-MM-DD
      const data = metrica.timestamp.split('T')[0];
      dias.add(data);
    }
  }

  return Array.from(dias).sort();
}

/**
 * Calcula somas e estatísticas
 */
function calcularEstatisticas(metricas) {
  const porEstago = {};
  let totalRequisicoes = metricas.length;
  let somaDuracao = 0;
  let totalInputTokens = 0;
  let totalCacheRead = 0;

  for (const metrica of metricas) {
    const estagio = metrica.estagio || 'desconhecido';

    if (!porEstago[estagio]) {
      porEstago[estagio] = {
        requisicoes: 0,
        input_tokens: 0,
        output_tokens: 0,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
      };
    }

    porEstago[estagio].requisicoes++;
    porEstago[estagio].input_tokens += metrica.usage?.input_tokens || 0;
    porEstago[estagio].output_tokens += metrica.usage?.output_tokens || 0;
    porEstago[estagio].cache_read_input_tokens += metrica.usage?.cache_read_input_tokens || 0;
    porEstago[estagio].cache_creation_input_tokens += metrica.usage?.cache_creation_input_tokens || 0;

    somaDuracao += metrica.duracao_ms || 0;
    totalInputTokens += metrica.usage?.input_tokens || 0;
    totalCacheRead += metrica.usage?.cache_read_input_tokens || 0;
  }

  // Cache hit: cache_read / (cache_read + input)
  const percentualCacheHit =
    totalInputTokens + totalCacheRead > 0
      ? Math.round((totalCacheRead / (totalCacheRead + totalInputTokens)) * 10000) / 100
      : 0;

  const mediaDuracao =
    totalRequisicoes > 0 ? Math.round(somaDuracao / totalRequisicoes * 100) / 100 : 0;

  return {
    porEstago,
    requisicoes: totalRequisicoes,
    percentualCacheHit,
    mediaDuracao,
  };
}

/**
 * Formata relatório para texto
 */
function formatarRelatorioTexto(dias, stats) {
  let resultado = [];

  resultado.push(`GATE ABERTO (${dias.length} dias-calendário)`);
  resultado.push('');
  resultado.push('Uso por estágio:');

  for (const [estagio, dados] of Object.entries(stats.porEstago)) {
    resultado.push(
      `  ${estagio}: input=${dados.input_tokens}, output=${dados.output_tokens}, cache_read=${dados.cache_read_input_tokens}, requisicoes=${dados.requisicoes}`
    );
  }

  resultado.push('');
  resultado.push(`Cache hit agregado: ${stats.percentualCacheHit}%`);
  resultado.push(`Requisições totais: ${stats.requisicoes}`);
  resultado.push(`Duração média: ${stats.mediaDuracao}ms`);
  resultado.push('');
  resultado.push('Nota: comparação com "sem proxy" não é possível (impossível medir retroativamente).');

  return resultado.join('\n');
}

/**
 * Formata relatório para JSON
 */
function formatarRelatorioJson(dias, stats) {
  return {
    gate: 'ABERTO',
    dias_distintos: dias.length,
    datas: dias,
    por_estagio: stats.porEstago,
    cache_hit_percentual: stats.percentualCacheHit,
    requisicoes_totais: stats.requisicoes,
    duracao_media_ms: stats.mediaDuracao,
  };
}

// Main
const env = process.env;
const cwd = env.CLAUDE_PROJECT_DIR || process.cwd();
const caminhoArq = caminhoMetricas({ env, cwd });

const metricas = lerMetricas(caminhoArq);
const dias = extrairDiasDistintos(metricas);

const jsonMode = process.argv.includes('--json');

if (dias.length < 7) {
  const faltam = 7 - dias.length;
  const mensagem = `GATE FECHADO: ${dias.length} de 7 dias`;

  if (jsonMode) {
    console.log(JSON.stringify({ gate: 'FECHADO', dias_distintos: dias.length, faltam }));
  } else {
    console.log(mensagem);
  }

  process.exit(1);
} else {
  const stats = calcularEstatisticas(metricas);

  if (jsonMode) {
    console.log(JSON.stringify(formatarRelatorioJson(dias, stats)));
  } else {
    console.log(formatarRelatorioTexto(dias, stats));
  }

  process.exit(0);
}
