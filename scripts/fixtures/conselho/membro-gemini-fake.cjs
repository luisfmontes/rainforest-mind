#!/usr/bin/env node
/**
 * Fixture para CLI Gemini — imprime JSON no stdout (como CLI real).
 * Uso: node membro-gemini-fake.cjs <prompt> <saida>
 *
 * Simula o comportamento de um CLI Gemini real: lê arquivo de prompt,
 * imprime JSON de parecer no stdout (o adaptador escreve no arquivo).
 * exit 0 em sucesso, exit 1 em erro.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Erro: Uso: membro-gemini-fake.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    const prompt = fs.readFileSync(caminhoPrompt, 'utf8');

    // Generate a valid parecer JSON (Gemini persona)
    const parecer = {
      posicao: 'A decisão deve priorizar flexibilidade e adaptação a mudanças futuras.',
      argumentos: [
        'Arquitetura flexível reduz risco de retrabalho',
        'Modularidade facilita testes e manutenção',
        'Design extensível suporta crescimento futuro'
      ],
      objecoes: [
        'Flexibilidade excessiva pode adicionar complexidade desnecessária',
        'Otimização prematura para casos futuros não é sabedoria'
      ],
      riscos: [
        'Over-engineering pode retardar time to market',
        'Flexibilidade pode mascarar decisões de design fracas'
      ]
    };

    // Imprime JSON no stdout (como CLI real faria)
    // O adaptador extrai isso e escreve no arquivo de saída
    console.log(JSON.stringify(parecer, null, 2));
    process.exit(0);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
