'use strict';
// @categoria: sensor
/**
 * Busca ativa na memória = instrução, não texto (D1 do design
 * docs/rainforest/design/2026-10-09-assunto-regua.md).
 *
 * `ehBuscaAtiva(comando)` diz se alguma INSTRUÇÃO do comando de shell começa pela
 * chamada `node <caminho>memoria.cjs buscar`. Corpo de heredoc, argumento citado
 * (`grep "memoria.cjs buscar"`, `echo "..."`) e texto de mensagem de commit não contam.
 *
 * Função pura, sem I/O. Limites declarados: caminho entre aspas
 * (`node "x/memoria.cjs" buscar`), prefixos `time`/`timeout` e here-string do PowerShell.
 */

// Início da instrução: atribuições de ambiente opcionais, depois `node <caminho sem espaço>memoria.cjs buscar`.
const CHAMADA_BUSCA = /^\s*(?:[A-Za-z_]\w*=\S*\s+)*node\s+[^\s"']*memoria\.cjs\s+buscar(?![\w-])/;

// `<<`, `<<-`, delimitador com ou sem aspas. `<<<` (here-string) não é heredoc.
const ABRE_HEREDOC = /(?<!<)<<(?!<)(-?)\s*(?:'([^']+)'|"([^"]+)"|\\?([A-Za-z_]\w*))/g;

// Tira o corpo dos heredocs e o delimitador final; a linha que abre o heredoc fica.
function semCorpoDeHeredoc(comando) {
  const saida = [];
  const pendentes = []; // heredocs abertos, na ordem em que o shell os lê
  for (const linha of comando.split('\n')) {
    if (pendentes.length) {
      const { delimitador, indentado } = pendentes[0];
      const cru = linha.replace(/\r$/, '');
      if ((indentado ? cru.replace(/^\t+/, '') : cru) === delimitador) pendentes.shift();
      continue;
    }
    saida.push(linha);
    for (const m of linha.matchAll(ABRE_HEREDOC)) {
      pendentes.push({ delimitador: m[2] || m[3] || m[4], indentado: m[1] === '-' });
    }
  }
  return saida.join('\n');
}

// Texto entre aspas vira `""`: separador dentro de aspas não parte a instrução.
function semTextoCitado(texto) {
  return texto.replace(/"(?:[^"\\]|\\[\s\S])*"|'[^']*'/g, '""');
}

function instrucoesDe(comando) {
  return semTextoCitado(semCorpoDeHeredoc(String(comando))).split(/&&|\|\||;|\||\n/);
}

function ehBuscaAtiva(comando) {
  return instrucoesDe(comando).some((i) => CHAMADA_BUSCA.test(i));
}

module.exports = { ehBuscaAtiva };
