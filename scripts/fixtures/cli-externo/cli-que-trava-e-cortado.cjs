#!/usr/bin/env node
/**
 * Fixture de teste: CLI que trava (dorme além do timeout)
 * Dorme por 60 segundos e nunca retorna.
 * Uso sem argumentos.
 *
 * Por que 60s e não 10s: o teste que usa esta fixture afirma "foi cortado"
 * comparando a duração contra um teto, e esse teto subiu de 2s para 8s quando
 * o rodarCli passou a pagar matarDescendencia no ramo de timeout (a consulta
 * CIM via powershell.exe custa ~1s). Com a fixture em 10s sobrava margem de 2s
 * entre "cortado" e "dormiu tudo" — pouco numa máquina com várias sessões
 * rodando. Em 60s a distinção volta a ser inequívoca sem afrouxar o teto.
 */

setTimeout(() => {
  // Nunca chega aqui — é cortado pelo timeout do rodarCli
  process.exit(0);
}, 60000);
