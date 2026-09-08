#!/usr/bin/env node
/**
 * Gates de correção para as tarefas da escada
 *
 * Exporta um objeto { tarefa_XX: { assert: function, descricao: string } }
 */

const vm = require('vm');

const gates = {
  'tarefa-01': {
    descricao: 'Fatorial deve existir e calcular corretamente',
    assert(codigo) {
      try {
        // Executar o código em contexto isolado com timeout
        const contexto = {};
        const globalObj = new Proxy(contexto, {
          set: (target, prop, value) => { target[prop] = value; return true; },
          get: (target, prop) => target[prop]
        });
        contexto.global = globalObj;
        vm.runInNewContext(codigo, contexto, { timeout: 5000 });

        // Validar que factorial existe e é função
        if (typeof contexto.factorial !== 'function') {
          return { ok: false, erro: 'factorial não é uma função' };
        }

        // Testar alguns casos
        if (contexto.factorial(0) !== 1) return { ok: false, erro: 'factorial(0) deveria ser 1' };
        if (contexto.factorial(1) !== 1) return { ok: false, erro: 'factorial(1) deveria ser 1' };
        if (contexto.factorial(5) !== 120) return { ok: false, erro: 'factorial(5) deveria ser 120' };
        if (contexto.factorial(10) !== 3628800) return { ok: false, erro: 'factorial(10) deveria ser 3628800' };

        return { ok: true };
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  },

  'tarefa-02': {
    descricao: 'isPalindrome deve detectar palíndromos corretamente',
    assert(codigo) {
      try {
        const contexto = {};
        const globalObj = new Proxy(contexto, {
          set: (target, prop, value) => { target[prop] = value; return true; },
          get: (target, prop) => target[prop]
        });
        contexto.global = globalObj;
        vm.runInNewContext(codigo, contexto, { timeout: 5000 });

        if (typeof contexto.isPalindrome !== 'function') {
          return { ok: false, erro: 'isPalindrome não é uma função' };
        }

        // Testes
        if (contexto.isPalindrome('racecar') !== true) return { ok: false, erro: 'isPalindrome("racecar") deveria ser true' };
        if (contexto.isPalindrome('hello') !== false) return { ok: false, erro: 'isPalindrome("hello") deveria ser false' };
        if (contexto.isPalindrome('A man a plan a canal Panama') !== true) return { ok: false, erro: 'isPalindrome com espaços falhou' };
        if (contexto.isPalindrome('madam') !== true) return { ok: false, erro: 'isPalindrome("madam") deveria ser true' };

        return { ok: true };
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  },

  'tarefa-03': {
    descricao: 'Stack deve implementar LIFO corretamente',
    assert(codigo) {
      try {
        const contexto = {};
        const globalObj = new Proxy(contexto, {
          set: (target, prop, value) => { target[prop] = value; return true; },
          get: (target, prop) => target[prop]
        });
        contexto.global = globalObj;
        vm.runInNewContext(codigo, contexto, { timeout: 5000 });

        if (typeof contexto.Stack !== 'function') {
          return { ok: false, erro: 'Stack não é uma classe/função' };
        }

        const stack = new contexto.Stack();

        // Testes básicos
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
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  },

  'tarefa-04': {
    descricao: 'findMax deve retornar o maior número',
    assert(codigo) {
      try {
        const contexto = {};
        const globalObj = new Proxy(contexto, {
          set: (target, prop, value) => { target[prop] = value; return true; },
          get: (target, prop) => target[prop]
        });
        contexto.global = globalObj;
        vm.runInNewContext(codigo, contexto, { timeout: 5000 });

        if (typeof contexto.findMax !== 'function') {
          return { ok: false, erro: 'findMax não é uma função' };
        }

        // Testes
        if (contexto.findMax([1, 2, 3, 4, 5]) !== 5) return { ok: false, erro: 'findMax([1,2,3,4,5]) deveria ser 5' };
        if (contexto.findMax([5, 2, 8, 1]) !== 8) return { ok: false, erro: 'findMax([5,2,8,1]) deveria ser 8' };
        if (contexto.findMax([-10, -5, -20]) !== -5) return { ok: false, erro: 'findMax com negativos falhou' };
        if (contexto.findMax([]) !== null) return { ok: false, erro: 'findMax([]) deveria ser null' };

        return { ok: true };
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  },

  'tarefa-05': {
    descricao: 'decimalToBinary deve converter corretamente',
    assert(codigo) {
      try {
        const contexto = {};
        const globalObj = new Proxy(contexto, {
          set: (target, prop, value) => { target[prop] = value; return true; },
          get: (target, prop) => target[prop]
        });
        contexto.global = globalObj;
        vm.runInNewContext(codigo, contexto, { timeout: 5000 });

        if (typeof contexto.decimalToBinary !== 'function') {
          return { ok: false, erro: 'decimalToBinary não é uma função' };
        }

        // Testes
        if (contexto.decimalToBinary(0) !== '0') return { ok: false, erro: 'decimalToBinary(0) deveria ser "0"' };
        if (contexto.decimalToBinary(1) !== '1') return { ok: false, erro: 'decimalToBinary(1) deveria ser "1"' };
        if (contexto.decimalToBinary(5) !== '101') return { ok: false, erro: 'decimalToBinary(5) deveria ser "101"' };
        if (contexto.decimalToBinary(10) !== '1010') return { ok: false, erro: 'decimalToBinary(10) deveria ser "1010"' };
        if (contexto.decimalToBinary(255) !== '11111111') return { ok: false, erro: 'decimalToBinary(255) deveria ser "11111111"' };

        return { ok: true };
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  }
};

module.exports = gates;
