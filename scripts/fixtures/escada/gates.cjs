#!/usr/bin/env node
/**
 * Gates de correção para as tarefas da escada
 *
 * Exporta um objeto { tarefa_XX: { assert: function, descricao: string } }
 */

const gates = {
  'tarefa-01': {
    descricao: 'Fatorial deve existir e calcular corretamente',
    assert(codigo) {
      try {
        // Avaliar o código (contém a função factorial)
        eval(codigo);

        // Validar que factorial existe e é função
        if (typeof factorial !== 'function') {
          return { ok: false, erro: 'factorial não é uma função' };
        }

        // Testar alguns casos
        if (factorial(0) !== 1) return { ok: false, erro: 'factorial(0) deveria ser 1' };
        if (factorial(1) !== 1) return { ok: false, erro: 'factorial(1) deveria ser 1' };
        if (factorial(5) !== 120) return { ok: false, erro: 'factorial(5) deveria ser 120' };
        if (factorial(10) !== 3628800) return { ok: false, erro: 'factorial(10) deveria ser 3628800' };

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
        eval(codigo);

        if (typeof isPalindrome !== 'function') {
          return { ok: false, erro: 'isPalindrome não é uma função' };
        }

        // Testes
        if (isPalindrome('racecar') !== true) return { ok: false, erro: 'isPalindrome("racecar") deveria ser true' };
        if (isPalindrome('hello') !== false) return { ok: false, erro: 'isPalindrome("hello") deveria ser false' };
        if (isPalindrome('A man a plan a canal Panama') !== true) return { ok: false, erro: 'isPalindrome com espaços falhou' };
        if (isPalindrome('madam') !== true) return { ok: false, erro: 'isPalindrome("madam") deveria ser true' };

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
        eval(codigo);

        if (typeof Stack !== 'function') {
          return { ok: false, erro: 'Stack não é uma classe/função' };
        }

        const stack = new Stack();

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
        eval(codigo);

        if (typeof findMax !== 'function') {
          return { ok: false, erro: 'findMax não é uma função' };
        }

        // Testes
        if (findMax([1, 2, 3, 4, 5]) !== 5) return { ok: false, erro: 'findMax([1,2,3,4,5]) deveria ser 5' };
        if (findMax([5, 2, 8, 1]) !== 8) return { ok: false, erro: 'findMax([5,2,8,1]) deveria ser 8' };
        if (findMax([-10, -5, -20]) !== -5) return { ok: false, erro: 'findMax com negativos falhou' };
        if (findMax([]) !== null) return { ok: false, erro: 'findMax([]) deveria ser null' };

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
        eval(codigo);

        if (typeof decimalToBinary !== 'function') {
          return { ok: false, erro: 'decimalToBinary não é uma função' };
        }

        // Testes
        if (decimalToBinary(0) !== '0') return { ok: false, erro: 'decimalToBinary(0) deveria ser "0"' };
        if (decimalToBinary(1) !== '1') return { ok: false, erro: 'decimalToBinary(1) deveria ser "1"' };
        if (decimalToBinary(5) !== '101') return { ok: false, erro: 'decimalToBinary(5) deveria ser "101"' };
        if (decimalToBinary(10) !== '1010') return { ok: false, erro: 'decimalToBinary(10) deveria ser "1010"' };
        if (decimalToBinary(255) !== '11111111') return { ok: false, erro: 'decimalToBinary(255) deveria ser "11111111"' };

        return { ok: true };
      } catch (e) {
        return { ok: false, erro: `Erro ao executar: ${e.message}` };
      }
    }
  }
};

module.exports = gates;
