'use strict';
/**
 * Regras de definição por linguagem, numa fonte só (D7 do design lgpd-e-duplicata).
 *
 * Quem usa: hooks/aviso-duplicata.cjs (conjunto `topo`, mesmo nome na edição) e
 * scripts/catalogo-funcoes.cjs (os dois conjuntos: `topo` e `metodo`, para a passada
 * de duplicata semântica do enxugar).
 *
 * - `topo`: definição na coluna zero (JS, Python, Dart). ADVPL aceita recuo, porque o
 *   fonte costuma vir indentado dentro de bloco.
 * - `metodo`: método de classe recuado. JS/TS só casa com visibilidade, async, static,
 *   get ou set, e sem `if`/`for`/`while`/`switch`/`return`/`catch`. Dart só casa com
 *   tipo de retorno antes do nome, para não confundir chamada solta com definição.
 *
 * Cada regex tem o nome em `m[1]`. `casar` devolve o primeiro nome que casa, ou null.
 */

const EXTENSOES = {
  '.js': 'js', '.cjs': 'js', '.mjs': 'js', '.ts': 'js', '.tsx': 'js', '.jsx': 'js',
  '.py': 'py',
  '.prw': 'advpl', '.prx': 'advpl', '.tlpp': 'advpl', '.ch': 'advpl',
  '.dart': 'dart',
};

// Palavra que nunca é nome de função de topo em Dart (começo de instrução ou modificador).
const NAO_RESERVADA_DART = '(?!(?:return|if|for|while|switch|catch|await|throw|new|else|final|const|var|late|case|do|try|class)\\b)';

const REGRAS = {
  topo: {
    js: [
      /^(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+([\w$]+)/,
      /^(?:export\s+)?(?:const|let|var)\s+([\w$]+)\s*=\s*(?:async\b|\()/,
      /^(?:export\s+)?class\s+([\w$]+)/,
      /^exports\.([\w$]+)\s*=/,
    ],
    py: [/^(?:async\s+)?def\s+(\w+)/, /^class\s+(\w+)/],
    advpl: [/^\s*(?:user\s+function|static\s+function|function|class)\s+(\w+)/i],
    dart: [
      // função de topo com tipo de retorno opcional: `void main(`, `Future<void> foo(`, `bar(`
      new RegExp('^' + NAO_RESERVADA_DART + '(?:[A-Za-z_]\\w*(?:<.+?>)?\\??\\s+)?([A-Za-z_]\\w*)\\s*\\('),
      // classe, com modificadores opcionais de Dart 3
      /^(?:(?:abstract|base|final|sealed|interface)\s+)*class\s+([A-Za-z_]\w*)/,
    ],
  },
  metodo: {
    js: [
      /^\s+(?:(?:public|private|protected|static|async|get|set|readonly)\s+)*(?!(?:if|for|while|switch|return|catch)\b)([\w$]+)\s*\([^)]*\)\s*(?::[^{]*)?\{/,
    ],
    // tipo de retorno obrigatório antes do nome (void, bool, int, ... ou tipo que começa com maiúscula)
    dart: [
      /^\s+(?:(?:static|final|late)\s+)*(?:void|bool|int|double|num|dynamic|[A-Z_]\w*(?:<[^(]*>)?\??)\s+(\w+)\s*\(/,
    ],
  },
};

/** Nome definido pela linha, no conjunto `topo` (padrão) ou `metodo`; null se a linha não define nada. */
function casar(linha, linguagem, conjunto = 'topo') {
  const lista = (REGRAS[conjunto] && REGRAS[conjunto][linguagem]) || [];
  for (const re of lista) {
    const m = re.exec(linha);
    if (m) return m[1];
  }
  return null;
}

module.exports = { EXTENSOES, REGRAS, casar };
