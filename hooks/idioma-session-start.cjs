#!/usr/bin/env node
// @categoria: guia
/**
 * Hook SessionStart: injeta idioma preferido na compactação.
 *
 * Com a chave `idioma` no config do projeto, emite uma linha de
 * additionalContext para o modelo responder no idioma preferido.
 * Matcher: "compact" — só dispara na compactação de contexto.
 *
 * Qualquer exceção sai 0 — SessionStart não pode derrubar a sessão.
 */

const fs = require('fs');
const { resolverConfig } = require('./lib/config.cjs');
const { cortarBytes } = require('./lib/bytes.cjs');

function lerEvento() {
  try {
    const input = fs.readFileSync(0, 'utf8');
    return JSON.parse(input);
  } catch {
    return {};
  }
}

function main() {
  try {
    const evento = lerEvento();
    const { source, cwd } = evento;

    // Só dispara na compactação
    if (source !== 'compact') {
      process.exit(0);
    }

    // Resolve a config do projeto
    const config = resolverConfig({ projeto: cwd });
    const idioma = config.valores.idioma;

    // Sem idioma configurado, sai silencioso
    if (!idioma) process.exit(0);

    // Monta o texto do aviso cortado em 200 B
    const texto = `Responda ao usuário em ${idioma}.`;
    const textoCortado = cortarBytes(texto, 200);

    const saida = {
      hookSpecificOutput: {
        hookEventName: 'SessionStart',
        additionalContext: textoCortado,
      },
    };

    console.log(JSON.stringify(saida));
    process.exit(0);
  } catch {
    // Qualquer erro sai silencioso
    process.exit(0);
  }
}

main();
