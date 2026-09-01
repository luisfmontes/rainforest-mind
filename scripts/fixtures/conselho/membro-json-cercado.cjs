#!/usr/bin/env node
// Fixture: membro que responde JSON valido DENTRO de cerca de codigo ```json —
// o que modelos reais fazem mesmo instruidos a nao fazer. O parse tolerante
// (parseJsonDeMembro) tem que aceitar; sem ele a fase 1 reprovaria membro real.
// Interface: argv[2] = caminho do prompt, argv[3] = caminho da saida.
const fs = require('fs');
const saida = process.argv[3];
if (!saida) { console.error('uso: membro-json-cercado.cjs <prompt> <saida>'); process.exit(1); }
const parecer = {
  posicao: 'Posicao do membro cercado',
  argumentos: ['argumento unico'],
  objecoes: ['objecao unica'],
  riscos: ['risco unico'],
};
fs.writeFileSync(saida, '```json\n' + JSON.stringify(parecer, null, 2) + '\n```\n', 'utf8');
