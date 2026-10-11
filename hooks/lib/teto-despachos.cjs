'use strict';
// Leitor do cabeçalho `teto-despachos: N` de um plano (Tarefa 7 do plano flaky-teto, D9/D14).
// Não lê disco: recebe o texto do plano. O hook `gate-teto-despachos.cjs` e a `cobertura`
// (`conferir-fluxo.cjs`) chamam este mesmo leitor, para aceitarem e recusarem os mesmos textos.
// Cabeçalho = as linhas antes do primeiro `## `. Valor válido: inteiro de 1 a 9999.

const VALOR_VALIDO = /^[1-9][0-9]{0,3}$/;

// { teto } (`padrao`, 40, quando não há a linha) ou { erro } com o texto lido.
function lerTetoDeclarado(textoDoPlano, padrao = 40) {
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

module.exports = { lerTetoDeclarado };
