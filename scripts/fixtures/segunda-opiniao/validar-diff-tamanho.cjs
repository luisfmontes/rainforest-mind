#!/usr/bin/env node
/**
 * Fixture para validar que o prompt carrega o diff correto
 * Lê stdin (prompt), extrai apenas o bloco de diff, e conta linhas
 * Formato de resposta: "Total de linhas no diff do prompt: <N>\n\nconcordo"
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Extrair bloco de diff que está entre ```...```
  const diffStart = entrada.indexOf('```\n');
  const diffEnd = entrada.indexOf('```', diffStart + 4);

  if (diffStart !== -1 && diffEnd !== -1) {
    const diffBlock = entrada.substring(diffStart + 4, diffEnd);
    // Trim whitespace and count newlines
    // git diff | wc -l conta as linhas que terminam com \n
    // Se o bloco tem "line1\nline2\nline3\n", tem 3 \n = 3 linhas
    // Se tem "line1\nline2\nline3\n\n" (extra), tem 4 \n. Trim remove a \n extra.
    const trimmed = diffBlock.trim();
    const lines = (trimmed.match(/\n/g) || []).length + 1;
    const resposta = `Total de linhas no diff do prompt: ${lines}\n\nconcordo\n`;
    process.stdout.write(resposta);
  } else {
    // Se não conseguir extrair, contar quebras de linha
    const lines = (entrada.match(/\n/g) || []).length;
    const resposta = `Total de linhas no diff do prompt: ${lines}\n\nconcordo\n`;
    process.stdout.write(resposta);
  }
  process.exit(0);
});

// Fallback
setTimeout(() => {
  const resposta = `Total de linhas no diff do prompt: 0\n\nconcordo\n`;
  process.stdout.write(resposta);
  process.exit(0);
}, 500);
