#!/usr/bin/env node
/**
 * Fixture de teste: CLI que trava (dorme além do timeout)
 * Dorme por 10 segundos e nunca retorna.
 * Uso sem argumentos.
 */

setTimeout(() => {
  // Nunca chega aqui — é cortado pelo timeout do rodarCli
  process.exit(0);
}, 10000);
