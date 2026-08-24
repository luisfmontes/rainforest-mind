// Avalia folga de um valor contra um teto usando a função avaliarFolga.
// Uso: node avalia-folga.cjs <valor> <teto> <nome> [alternativa1] [alternativa2] ...
const folga = require('./folga.cjs');
const valor = parseInt(process.argv[2], 10);
const teto = parseInt(process.argv[3], 10);
const nome = process.argv[4] || 'teto';
const alternativas = process.argv.slice(5);

const resultado = folga.avaliarFolga(valor, teto, { nome, alternativas });
console.log(`${resultado.estado}|${resultado.folga}|${resultado.limiar}|${resultado.mensagem}`);
