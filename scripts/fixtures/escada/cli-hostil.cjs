#!/usr/bin/env node
/**
 * CLI dublê HOSTIL — devolve payload adversarial em vez de código honesto.
 *
 * Existe para uma coisa só: dar à bateria um caso em que a fronteira de
 * isolamento de `gates.cjs` decide o veredito. Com o isolamento no lugar
 * (base64 na passagem + `vm.runInNewContext` com timeout) todo payload aqui
 * dá FAIL. Sem ele, o payload `injecao` e o `escape` dão PASS e o `laco`
 * pendura o processo — que é exatamente a diferença que a catraca mede.
 *
 * Nenhum payload apaga arquivo, escreve em disco ou chama rede: o que eles
 * exercitam é *poder* (interpolação, `require`, tempo), não dano.
 *
 * Payload escolhido por RFM_MEDIR_PAYLOAD:
 *   injecao — texto que só vira código se a passagem interpolar template
 *   escape  — fatorial correto que depende de `require` existir no escopo
 *   laco    — fatorial que nunca retorna; só o timeout do vm o mata
 *
 * Só responde ao prompt do fatorial (tarefa-01). Para os demais devolve
 * vazio, que a bateria já sabe reportar como FAIL.
 */

const ABRE = '$' + '{';

const PAYLOADS = {
  // Chega ao gate como texto inerte quando a passagem é base64.
  // Se a passagem interpolar template literal, vira um fatorial que passa.
  injecao: ABRE + '"function factorial(n){return n<2?1:n*factorial(n-1)}"}',

  // Correto *desde que* `require` exista. Dentro do vm não existe.
  escape: "function factorial(n){ return require('os') ? (n < 2 ? 1 : n * factorial(n - 1)) : 0 }",

  // Nunca retorna. Sem timeout no avaliador, pendura quem chamou.
  laco: 'function factorial(n){ while (true) {} }'
};

const escolhido = process.env.RFM_MEDIR_PAYLOAD || 'injecao';
const payload = PAYLOADS[escolhido];

if (!payload) {
  console.error('ERRO: payload desconhecido: ' + escolhido);
  process.exit(1);
}

let entrada = '';
process.stdin.on('data', chunk => { entrada += chunk.toString(); });
process.stdin.on('end', () => {
  console.log(/fatorial/i.test(entrada) ? payload : '');
});
