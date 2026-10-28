'use strict';
// Leitor do cabeçalho `teto-despachos: N` de um plano (Tarefa 7 do plano flaky-teto, D9/D14).
// Não lê disco: recebe o texto do plano. O hook `gate-teto-despachos.cjs` e a `cobertura`
// (`conferir-fluxo.cjs`) chamam este mesmo leitor, para aceitarem e recusarem os mesmos textos.
// Cabeçalho = as linhas antes do primeiro `## `. Valor válido: inteiro de 1 a 9999.

const VALOR_VALIDO = /^[1-9][0-9]{0,3}$/;
const TETO_MINIMO = 40;

// Teto padrão de um plano sem `teto-despachos:` (D5 do lote B, #612): max(40, ceil(1,5 × tarefas)).
// `tarefas` vem do `extrairTarefas` do conferir-fluxo.cjs; não numérico ou negativo conta como 0.
function tetoPadrao(tarefas) {
  if (!Number.isFinite(tarefas) || tarefas < 0) tarefas = 0;
  return Math.max(TETO_MINIMO, Math.ceil(1.5 * tarefas));
}

// { teto } (`padrao`, quando não há a linha) ou { erro } com o texto lido.
function lerTetoDeclarado(textoDoPlano, padrao = TETO_MINIMO) {
  if (typeof textoDoPlano !== 'string') return { erro: 'plano ilegível: o texto não é uma string' };
  const linhas = textoDoPlano.split(/\r?\n/);
  const fim = linhas.findIndex((l) => l.startsWith('## '));
  const cabecalho = fim === -1 ? linhas : linhas.slice(0, fim);
  const achadas = cabecalho.filter((l) => /^\s*teto-despachos\s*:/i.test(l));
  if (achadas.length === 0) return { teto: padrao };
  if (achadas.length > 1) {
    return { erro: `cabeçalho com ${achadas.length} linhas 'teto-despachos:' (só uma é aceita); li: ${achadas.map((l) => JSON.stringify(l.trim())).join(' e ')}` };
  }
  const valor = achadas[0].slice(achadas[0].indexOf(':') + 1).trim();
  if (!VALOR_VALIDO.test(valor)) {
    return { erro: `'teto-despachos:' ilegível; li ${JSON.stringify(valor)} e só aceito inteiro de 1 a 9999` };
  }
  return { teto: Number(valor) };
}

module.exports = { lerTetoDeclarado, tetoPadrao, TETO_MINIMO };
