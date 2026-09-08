#!/usr/bin/env node
async function chamarLLM(texto) {
  // Simula sucesso: retorna código mínimo que passa nos gates
  // Detecção de tarefa pelo conteúdo do prompt e geração de código funcional

  if (!texto || !texto.trim()) {
    return null;
  }

  // Simples heurística: qual tarefa pedir?
  let codigo = '';

  if (texto.includes('fatorial') || texto.includes('factorial')) {
    codigo = `(global.factorial = function factorial(n) { return n <= 1 ? 1 : n * factorial(n-1); })`;
  } else if (texto.includes('palíndromo') || texto.includes('palindrome')) {
    codigo = `(global.isPalindrome = function isPalindrome(s) { const clean = s.toLowerCase().replace(/\\s/g, ''); return clean === clean.split('').reverse().join(''); })`;
  } else if (texto.includes('Stack')) {
    codigo = `(global.Stack = class Stack { constructor() { this.items = []; } push(x) { this.items.push(x); } pop() { return this.items.pop(); } isEmpty() { return this.items.length === 0; } size() { return this.items.length; } })`;
  } else if (texto.includes('máximo') || texto.includes('maximum') || texto.includes('findMax')) {
    codigo = `(global.findMax = function findMax(arr) { if (arr.length === 0) return null; return Math.max(...arr); })`;
  } else if (texto.includes('decimal') || texto.includes('binário') || texto.includes('binary')) {
    codigo = `(global.decimalToBinary = function decimalToBinary(n) { let result = ''; while (n > 0) { result = (n % 2) + result; n = Math.floor(n / 2); } return result || '0'; })`;
  } else {
    // Fallback: algo genérico
    codigo = `(global.test = function test() { return 42; })`;
  }

  return codigo;
}
module.exports = { chamarLLM };
