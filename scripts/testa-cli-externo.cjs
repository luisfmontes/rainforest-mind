#!/usr/bin/env node
/**
 * Bateria para cli-externo.cjs — transporte de CLI externo
 * Testa rodarCli e extrairJson contra fixtures.
 */

const fs = require('fs');
const path = require('path');
const { rodarCli, extrairJson } = require('../hooks/lib/cli-externo.cjs');

const SRC = path.join(__dirname, '..');
const FIXTURES = path.join(SRC, 'scripts', 'fixtures', 'cli-externo');

let ok = 0;
let falhou = 0;

function testa(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}`);
    console.log(`         ${e.message}`);
  }
}

console.log('==== Bateria: cli-externo ====\n');

// ---- Teste 1: rodarCli recusa sem timeoutMs ----
console.log('Teste 1: timeout obrigatório');
testa('recusa sem timeoutMs', () => {
  try {
    rodarCli({ cmd: 'echo ok', entrada: '' });
    throw new Error('Deveria ter lançado erro');
  } catch (e) {
    if (!e.message.includes('timeoutMs')) {
      throw new Error(`Mensagem de erro incorreta: ${e.message}`);
    }
  }
});

console.log('');

// ---- Teste 2: prompt-com-aspas-e-quebra-de-linha ----
console.log('Teste 2: prompt-com-aspas-e-quebra-de-linha');
const TEMP_DIR = fs.mkdtempSync(path.join(require('os').tmpdir(), 'test-'));
const PROMPT_FILE = path.join(TEMP_DIR, 'prompt.txt');
const EXPECTED = 'Olá, mundo!\nE uma "aspas" aqui.';
fs.writeFileSync(PROMPT_FILE, EXPECTED, 'utf8');

testa('eco exato do stdin', () => {
  const cmd = `node "${path.join(FIXTURES, 'prompt-com-aspas-e-quebra-de-linha.cjs')}"`;
  const resultado = rodarCli({
    cmd,
    entrada: EXPECTED,
    timeoutMs: 2000
  });

  if (resultado.stdout !== EXPECTED) {
    throw new Error(
      `Mismatch: entrada e stdout não batem\n` +
      `  Entrada: ${JSON.stringify(EXPECTED)}\n` +
      `  Stdout:  ${JSON.stringify(resultado.stdout)}`
    );
  }
  if (resultado.status !== 0) {
    throw new Error(`Exit code: ${resultado.status}`);
  }
});

console.log('');

// ---- Teste 3: cli-que-trava-e-cortado ----
console.log('Teste 3: cli-que-trava-e-cortado (timeout)');
testa('cortado por timeout', () => {
  const cmd = `node "${path.join(FIXTURES, 'cli-que-trava-e-cortado.cjs')}"`;
  const inicio = Date.now();
  const resultado = rodarCli({
    cmd,
    entrada: '',
    timeoutMs: 1500
  });
  const duracao = Date.now() - inicio;

  // Deve ter sido cortado (status é null quando killed ou saída vazia)
  if (duracao >= 2000) {
    throw new Error(`Não foi cortado: duração ${duracao}ms >= 2000ms`);
  }
});

console.log('');

// ---- Teste 4: json-cercado-por-crase ----
console.log('Teste 4: json-cercado-por-crase');
testa('extrai JSON dentro de crases', () => {
  const cmd = `node "${path.join(FIXTURES, 'json-cercado-por-crase.cjs')}"`;
  const resultado = rodarCli({
    cmd,
    entrada: 'prompt qualquer',
    timeoutMs: 2000
  });

  if (resultado.status !== 0) {
    throw new Error(`Exit code ${resultado.status}, stdout: ${resultado.stdout}`);
  }

  const obj = extrairJson(resultado.stdout);
  if (!obj || obj.opinion !== 'válida' || obj.detalhes !== 'JSON cercado por crase') {
    throw new Error(
      `JSON não extraído ou inválido\n` +
      `  Stdout: ${JSON.stringify(resultado.stdout)}\n` +
      `  Objeto: ${JSON.stringify(obj)}`
    );
  }
});

console.log('');

// ---- Teste 5: extrairJson retorna null em JSON inválido ----
console.log('Teste 5: extrairJson com JSON inválido');
testa('retorna null em JSON inválido', () => {
  const result = extrairJson('isso não é json {{{');
  if (result !== null) {
    throw new Error(`Esperava null, recebeu: ${JSON.stringify(result)}`);
  }
});

console.log('');

// ---- Teste 6: extrairJson com stdout vazio ----
console.log('Teste 6: extrairJson com stdout vazio');
testa('retorna null com stdout vazio', () => {
  const result = extrairJson('');
  if (result !== null) {
    throw new Error(`Esperava null, recebeu: ${JSON.stringify(result)}`);
  }
});

console.log('');

// ---- Teste 7: rodarCli propaga exit code ----
console.log('Teste 7: rodarCli propaga exit code');
testa('propagando exit ≠ 0', () => {
  const resultado = rodarCli({
    cmd: 'exit 42',
    entrada: '',
    timeoutMs: 1000
  });

  if (resultado.status !== 42) {
    throw new Error(`Status esperado 42, recebido: ${resultado.status}`);
  }
});

console.log('');

// ---- Teste 8: extrairJson com JSON simples {...} ----
console.log('Teste 8: extrairJson com JSON simples {...}');
testa('extrai JSON simples {...}', () => {
  const stdout = 'Texto com {"key": "value"} no meio';
  const obj = extrairJson(stdout);
  if (!obj || obj.key !== 'value') {
    throw new Error(`JSON simples não extraído: ${JSON.stringify(obj)}`);
  }
});

console.log('');

// ---- Teste 9: fallback-array-toplevel (exercita fallback do extrairJson) ----
console.log('Teste 9: extrairJson com array top-level (fallback)');
testa('extrai array JSON válido (exercita fallback)', () => {
  // Array top-level puro: não tem "{" (segunda regex não casa)
  // e não tem ```json``` (primeira regex não casa)
  // Portanto só o fallback (const json = match ? match[1] : stdout) consegue parseá-lo
  const stdout = '[1, 2, 3, 4, 5]';
  const obj = extrairJson(stdout);
  if (!Array.isArray(obj) || obj.length !== 5 || obj[0] !== 1) {
    throw new Error(
      `Array JSON não extraído via fallback: ${JSON.stringify(obj)}\n` +
      `  Esperava: [1, 2, 3, 4, 5]`
    );
  }
});

console.log('');

// ---- Cleanup ----
fs.rmSync(TEMP_DIR, { recursive: true, force: true });

// ---- Resumo ----
const total = ok + falhou;
console.log('==== Resultado ====');
console.log(`ok: ${ok}`);
console.log(`falhou: ${falhou}`);
console.log(`total: ${total}`);

if (falhou > 0) {
  console.log('');
  console.log(`Vermelhas: [${falhou}]`);
  process.exit(1);
} else {
  process.exit(0);
}
