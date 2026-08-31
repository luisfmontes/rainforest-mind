#!/usr/bin/env node
/**
 * Membro fixture para testes de fase 2 — escreve uma revisão válida.
 * Uso: node membro-revisor-ok.cjs <prompt> <saida>
 *
 * Lê arquivo de pacote-prompt JSON de fase2, extrai os apelidos dos pareceres,
 * escreve revisão com ranking completo (na ordem dos apelidos) e críticas.
 * exit 0 em sucesso, exit 1 em erro.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-revisor-ok.cjs <prompt> <saida>');
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

    // Parse JSON pacote-prompt
    let pacote;
    try {
      pacote = JSON.parse(prompt);
    } catch (e) {
      console.error(`Erro: prompt não é JSON válido: ${e.message}`);
      process.exit(1);
    }

    if (!Array.isArray(pacote.pareceres)) {
      console.error('Erro: pacote.pareceres não é array');
      process.exit(1);
    }

    // Extract apelidos in order they appear
    const apelidos = pacote.pareceres.map(p => p.apelido);

    // Generate valid revisao with ranking in order of appearance
    const revisao = {
      ranking: apelidos,
      criticas: {}
    };

    // Create a unique critique for each parecer
    for (let i = 0; i < apelidos.length; i++) {
      const apelido = apelidos[i];
      revisao.criticas[apelido] = `Crítica construtiva para ${apelido}: ponto bem argumentado.`;
    }

    // Write saida file
    fs.writeFileSync(caminhoSaida, JSON.stringify(revisao, null, 2) + '\n', 'utf8');
    process.exit(0);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
