#!/usr/bin/env node
/**
 * Fixture de teste: retorna JSON dentro de ```json ... ```
 * Lê do stdin, ignora, e retorna um JSON válido dentro de crases.
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  const resultado = {
    opinion: 'válida',
    detalhes: 'JSON cercado por crase'
  };

  // Retorna JSON entre crases com texto que quebra a segunda regex
  // A segunda regex (/{[\s\S]*}/) falhará porque não há { isolado
  const json = JSON.stringify(resultado, null, 2);
  process.stdout.write('```json\n' + json + '\n```\nTexto após as crases com }}}}\n');
  process.exit(0);
});

// Fallback para quando não há stdin
setTimeout(() => {
  if (!entrada) {
    const resultado = {
      opinion: 'válida',
      detalhes: 'JSON cercado por crase (sem stdin)'
    };
    const json = JSON.stringify(resultado, null, 2);
    process.stdout.write('```json\n' + json + '\n```\nTexto após as crases com }}}}\n');
    process.exit(0);
  }
}, 500);
