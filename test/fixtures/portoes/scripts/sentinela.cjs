// Fixture: cria o arquivo passado como argv[2]. Existir = este script rodou.
// E a prova de nao-execucao do `status` e do `lint`: eles nao podem criar isto.
const fs = require('fs');
fs.writeFileSync(process.argv[2], 'rodou\n');
console.log('SENTINELA CRIADA');
