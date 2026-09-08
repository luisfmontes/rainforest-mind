#!/usr/bin/env node
/**
 * Dublê de LLM que gera código funcional, responde diferente conforme tenha escada.
 *
 * Uso: RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/dublador-com-escada.cjs"
 * Entrada via stdin: o prompt (com ou sem escada separada por ---)
 */

const readline = require('readline');

async function chamarLLM(texto) {
  // Detecção: tem escada?
  const temEscada = texto.includes('---');

  // Simples heurística: qual tarefa pedir? (mesmo que dubliador-llm-ok.cjs)
  let codigoLongo = '';
  let codigoCurto = '';

  if (texto.includes('fatorial') || texto.includes('factorial')) {
    codigoLongo = `// Calcula o fatorial recursivamente
(global.factorial = function factorial(n) {
  // Validação e caso base
  if (n < 0) throw new Error('Fatorial de número negativo não existe');
  if (n === 0 || n === 1) return 1;
  // Recursão: n! = n * (n-1)!
  return n * factorial(n - 1);
})`;
    codigoCurto = `(global.factorial = function factorial(n) { return n <= 1 ? 1 : n * factorial(n-1); })`;
  } else if (texto.includes('palíndromo') || texto.includes('palindrome')) {
    codigoLongo = `// Verifica se uma string é palíndroma
(global.isPalindrome = function isPalindrome(s) {
  // Remove espaços e converte para minúsculas
  const clean = s.toLowerCase().replace(/\\s/g, '');
  // Compara com a versão invertida
  const reversed = clean.split('').reverse().join('');
  return clean === reversed;
})`;
    codigoCurto = `(global.isPalindrome = function isPalindrome(s) { const clean = s.toLowerCase().replace(/\\s/g, ''); return clean === clean.split('').reverse().join(''); })`;
  } else if (texto.includes('Stack')) {
    codigoLongo = `// Implementação de uma pilha (Stack)
(global.Stack = class Stack {
  constructor() {
    // Array interno para armazenar os elementos
    this.items = [];
  }

  // Adiciona um elemento ao topo da pilha
  push(x) {
    this.items.push(x);
  }

  // Remove e retorna o elemento do topo
  pop() {
    return this.items.pop();
  }

  // Verifica se a pilha está vazia
  isEmpty() {
    return this.items.length === 0;
  }

  // Retorna o número de elementos
  size() {
    return this.items.length;
  }
})`;
    codigoCurto = `(global.Stack = class Stack { constructor() { this.items = []; } push(x) { this.items.push(x); } pop() { return this.items.pop(); } isEmpty() { return this.items.length === 0; } size() { return this.items.length; } })`;
  } else if (texto.includes('máximo') || texto.includes('maximum') || texto.includes('findMax')) {
    codigoLongo = `// Encontra o número máximo em um array
(global.findMax = function findMax(arr) {
  // Valida entrada
  if (!arr || arr.length === 0) {
    return null;
  }
  // Usa Math.max para encontrar o máximo
  return Math.max(...arr);
})`;
    codigoCurto = `(global.findMax = function findMax(arr) { if (arr.length === 0) return null; return Math.max(...arr); })`;
  } else if (texto.includes('decimal') || texto.includes('binário') || texto.includes('binary')) {
    codigoLongo = `// Converte um número decimal para binário
(global.decimalToBinary = function decimalToBinary(n) {
  let result = '';
  // Loop enquanto n > 0
  while (n > 0) {
    // Adiciona o bit de menor ordem
    result = (n % 2) + result;
    // Divide por 2 (shift right)
    n = Math.floor(n / 2);
  }
  // Retorna '0' se o resultado estiver vazio
  return result || '0';
})`;
    codigoCurto = `(global.decimalToBinary = function decimalToBinary(n) { let result = ''; while (n > 0) { result = (n % 2) + result; n = Math.floor(n / 2); } return result || '0'; })`;
  } else {
    // Fallback: algo genérico
    codigoLongo = `// Função genérica para teste
(global.test = function test() {
  return 42;
})`;
    codigoCurto = `(global.test = function test() { return 42; })`;
  }

  // Retorna a versão apropriada
  return temEscada ? codigoCurto : codigoLongo;
}

// Ler entrada do stdin
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

let entrada = '';

rl.on('line', (line) => {
  entrada += line + '\n';
});

rl.on('close', async () => {
  try {
    const resultado = await chamarLLM(entrada);
    if (resultado) {
      console.log(resultado);
    }
  } catch (e) {
    console.error(`Erro: ${e.message}`);
    process.exit(1);
  }
});
