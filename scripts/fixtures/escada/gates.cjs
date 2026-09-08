#!/usr/bin/env node
/**
 * Gates de correção para as tarefas da escada
 *
 * Exporta um objeto { tarefa_XX: { assert: function, descricao: string } }
 *
 * O código avaliado aqui vem de um modelo, e é código arbitrário. Duas
 * fronteiras seguram isso, e as duas precisam existir:
 *
 *   1. Isolamento — `vm.runInNewContext` num contexto vazio. Sem `require`,
 *      sem `process`, sem `fs`. O que o código pode tocar é o que está no
 *      objeto de contexto, e ele começa vazio.
 *
 *   2. Relógio — `timeout`. E o relógio só vale para o que roda *dentro* da
 *      chamada: uma função definida no vm e chamada depois, do lado de fora,
 *      roda no host, sem relógio nenhum. Por isso as provas de cada tarefa
 *      entram no mesmo script do código do modelo, e não em volta dele.
 *      `function factorial(n){ while(true){} }` pendurava a bateria para
 *      sempre quando as provas chamavam do host.
 *
 * A consequência de (2) é que as provas são *fonte*, não closure: elas são
 * serializadas com `toString()` e não enxergam nada deste arquivo.
 */

const vm = require('vm');

// 5 s é o teto para código de modelo de verdade. A bateria baixa isso por
// RFM_GATE_TIMEOUT_MS no caso do laço infinito, que é 100% espera parada: o
// que ele prova é que EXISTE relógio, e 500 ms provam o mesmo que 5000.
const TIMEOUT_MS = Number(process.env.RFM_GATE_TIMEOUT_MS) || 5000;

/**
 * Roda o código do modelo e as provas no MESMO contexto isolado, sob um
 * único relógio.
 *
 * @param {string} codigo  código gerado pelo modelo
 * @param {Function} provas  função sem closure que devolve { ok, erro? }
 * @returns {{ok: boolean, erro?: string}}
 */
function avaliarIsolado(codigo, provas) {
  const contexto = { __resultado: null };
  const script =
    'var global = globalThis;\n' +
    codigo +
    '\n;__resultado = (' + provas.toString() + ')();';

  try {
    vm.runInNewContext(script, contexto, { timeout: TIMEOUT_MS });
  } catch (e) {
    return { ok: false, erro: `Erro ao executar: ${e.message}` };
  }

  const resultado = contexto.__resultado;
  if (!resultado || typeof resultado !== 'object') {
    return { ok: false, erro: 'provas não devolveram veredito' };
  }
  return resultado;
}

const gates = {
  'tarefa-01': {
    descricao: 'Fatorial deve existir e calcular corretamente',
    assert(codigo) {
      return avaliarIsolado(codigo, function () {
        if (typeof factorial !== 'function') {
          return { ok: false, erro: 'factorial não é uma função' };
        }
        if (factorial(0) !== 1) return { ok: false, erro: 'factorial(0) deveria ser 1' };
        if (factorial(1) !== 1) return { ok: false, erro: 'factorial(1) deveria ser 1' };
        if (factorial(5) !== 120) return { ok: false, erro: 'factorial(5) deveria ser 120' };
        if (factorial(10) !== 3628800) return { ok: false, erro: 'factorial(10) deveria ser 3628800' };
        return { ok: true };
      });
    }
  },

  'tarefa-02': {
    descricao: 'isPalindrome deve detectar palíndromos corretamente',
    assert(codigo) {
      return avaliarIsolado(codigo, function () {
        if (typeof isPalindrome !== 'function') {
          return { ok: false, erro: 'isPalindrome não é uma função' };
        }
        if (isPalindrome('racecar') !== true) return { ok: false, erro: 'isPalindrome("racecar") deveria ser true' };
        if (isPalindrome('hello') !== false) return { ok: false, erro: 'isPalindrome("hello") deveria ser false' };
        if (isPalindrome('A man a plan a canal Panama') !== true) return { ok: false, erro: 'isPalindrome com espaços falhou' };
        if (isPalindrome('madam') !== true) return { ok: false, erro: 'isPalindrome("madam") deveria ser true' };
        return { ok: true };
      });
    }
  },

  'tarefa-03': {
    descricao: 'Stack deve implementar LIFO corretamente',
    assert(codigo) {
      return avaliarIsolado(codigo, function () {
        if (typeof Stack !== 'function') {
          return { ok: false, erro: 'Stack não é uma classe/função' };
        }
        const stack = new Stack();
        if (!stack.isEmpty()) return { ok: false, erro: 'Stack nova deveria estar vazia' };

        stack.push(1);
        stack.push(2);
        stack.push(3);

        if (stack.isEmpty()) return { ok: false, erro: 'Stack com elementos não deveria estar vazia' };
        if (stack.size() !== 3) return { ok: false, erro: `stack.size() deveria ser 3, foi ${stack.size()}` };

        if (stack.pop() !== 3) return { ok: false, erro: 'Primeiro pop deveria devolver 3' };
        if (stack.pop() !== 2) return { ok: false, erro: 'Segundo pop deveria devolver 2' };
        if (stack.size() !== 1) return { ok: false, erro: `Após 2 pops, size deveria ser 1, foi ${stack.size()}` };

        return { ok: true };
      });
    }
  },

  'tarefa-04': {
    descricao: 'findMax deve retornar o maior número',
    assert(codigo) {
      return avaliarIsolado(codigo, function () {
        if (typeof findMax !== 'function') {
          return { ok: false, erro: 'findMax não é uma função' };
        }
        if (findMax([1, 2, 3, 4, 5]) !== 5) return { ok: false, erro: 'findMax([1,2,3,4,5]) deveria ser 5' };
        if (findMax([5, 2, 8, 1]) !== 8) return { ok: false, erro: 'findMax([5,2,8,1]) deveria ser 8' };
        if (findMax([-10, -5, -20]) !== -5) return { ok: false, erro: 'findMax com negativos falhou' };
        if (findMax([]) !== null) return { ok: false, erro: 'findMax([]) deveria ser null' };
        return { ok: true };
      });
    }
  },

  'tarefa-05': {
    descricao: 'decimalToBinary deve converter corretamente',
    assert(codigo) {
      return avaliarIsolado(codigo, function () {
        if (typeof decimalToBinary !== 'function') {
          return { ok: false, erro: 'decimalToBinary não é uma função' };
        }
        if (decimalToBinary(0) !== '0') return { ok: false, erro: 'decimalToBinary(0) deveria ser "0"' };
        if (decimalToBinary(1) !== '1') return { ok: false, erro: 'decimalToBinary(1) deveria ser "1"' };
        if (decimalToBinary(5) !== '101') return { ok: false, erro: 'decimalToBinary(5) deveria ser "101"' };
        if (decimalToBinary(10) !== '1010') return { ok: false, erro: 'decimalToBinary(10) deveria ser "1010"' };
        if (decimalToBinary(255) !== '11111111') return { ok: false, erro: 'decimalToBinary(255) deveria ser "11111111"' };
        return { ok: true };
      });
    }
  }
};

module.exports = gates;
