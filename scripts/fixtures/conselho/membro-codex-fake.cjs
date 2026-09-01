#!/usr/bin/env node
/**
 * Fixture para CLI Codex — imprime JSON no stdout (como CLI real).
 * Uso: node membro-codex-fake.cjs <prompt> <saida>
 *
 * Simula o comportamento de um CLI Codex real: lê arquivo de prompt,
 * imprime JSON de parecer no stdout (o adaptador escreve no arquivo).
 * exit 0 em sucesso, exit 1 em erro.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Erro: Uso: membro-codex-fake.cjs <prompt> <saida>');
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

    // Generate a valid parecer JSON (Codex persona)
    const parecer = {
      posicao: 'A decisão deve balancear pragmatismo com boas práticas de engenharia.',
      argumentos: [
        'Pragmatismo entrega valor mais rápido ao usuário',
        'Boas práticas reduzem débito técnico no longo prazo',
        'Balance entre velocidade e qualidade é chave para sucesso sustentável'
      ],
      objecoes: [
        'Pragmatismo excessivo pode comprometer qualidade estrutural',
        'Boas práticas podem inchar escopo e prazos'
      ],
      riscos: [
        'Débito técnico acumulado reduz velocidade futura',
        'Qualidade comprometida prejudica experiência do usuário'
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
