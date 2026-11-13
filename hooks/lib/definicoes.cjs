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
 *   get ou set, sem `if`/`for`/`while`/`switch`/`return`/`catch`/`with`, e sem `function`
 *   dentro dos parênteses. Dart (topo e método) só casa com tipo de retorno antes do nome,
 *   para não confundir chamada solta com definição; `main` de topo fica de fora.
 *   ADVPL/TLPP (`metodo`): só a implementação, `Method x(...) [as <tipo>] Class Y`, que
 *   casa com a classe. A declaração recuada dentro do corpo da classe (`Method x()` sem
 *   `Class` depois) não casa, para não contar a mesma função duas vezes.
 *
 * Cada regex tem o nome em `m[1]`; quando tem um segundo grupo (`m[2]`, a classe de um
 * método ADVPL), `casar` devolve `Classe:metodo`. `casar` devolve o primeiro nome que casa, ou null.
 */

const EXTENSOES = {
  '.js': 'js', '.cjs': 'js', '.mjs': 'js', '.ts': 'js', '.tsx': 'js', '.jsx': 'js',
  '.py': 'py',
  '.prw': 'advpl', '.prx': 'advpl', '.tlpp': 'advpl', '.ch': 'advpl',
  '.dart': 'dart',
};

// Palavra que nunca é nome de função de topo em Dart (começo de instrução ou modificador).
const NAO_RESERVADA_DART = '(?!(?:return|if|for|while|switch|catch|await|yield|throw|new|else|final|const|var|late|case|do|try|class)\\b)';

const REGRAS = {
  topo: {
    js: [
      /^(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+([\w$]+)/,
      // Seta, `function` ou componente envolvido (`memo(`, `forwardRef<T>(`, com ou sem `React.`),
      // com anotação de tipo opcional antes do `=` (#648): `const Foo: React.FC<P> = ({ a }) => {`.
      // A anotação aceita `=>` dentro dela (`const f: (a: T) => void = (a) => {`).
      /^(?:export\s+)?(?:const|let|var)\s+([\w$]+)\s*(?::(?:[^=]|=>)+?)?=\s*(?:async\b|\(|function\b|(?:React\.)?(?:memo|forwardRef)\s*[(<])/,
      /^(?:export\s+)?class\s+([\w$]+)/,
      /^exports\.([\w$]+)\s*=/,
    ],
    py: [/^(?:async\s+)?def\s+(\w+)/, /^class\s+(\w+)/],
    advpl: [/^\s*(?:user\s+function|static\s+function|function|class)\s+(\w+)/i],
    dart: [
      // função de topo COM tipo de retorno: `void salvar(`, `Future<void> foo(`, `String? bar(`.
      // Sem tipo, `print('x');` ou `setState(` na coluna zero de um trecho editado viravam
      // definição. `main` fica de fora: é o ponto de entrada de todo app e de todo teste Dart,
      // e o mesmo nome em cada arquivo não é duplicata (revisão do lgpd-e-duplicata, achado 1).
      new RegExp('^' + NAO_RESERVADA_DART + '[A-Za-z_]\\w*(?:<.+?>)?\\??\\s+(?!main\\b)([A-Za-z_]\\w*)\\s*\\('),
      // classe, com modificadores opcionais de Dart 3
      /^(?:(?:abstract|base|final|sealed|interface)\s+)*class\s+([A-Za-z_]\w*)/,
    ],
  },
  metodo: {
    js: [
      // `with (obj) {` e chamada que recebe função anônima (`setTimeout(function () {`) não são
      // método: o nome não pode ser palavra de instrução e os parênteses não podem conter `function`.
      /^\s+(?:(?:public|private|protected|static|async|get|set|readonly)\s+)*(?!(?:if|for|while|switch|return|catch|with|function)\b)([\w$]+)\s*\((?![^)]*\bfunction\b)[^)]*\)\s*(?::[^{]*)?\{/,
    ],
    // tipo de retorno obrigatório antes do nome (void, bool, int, ... ou tipo que começa com maiúscula)
    dart: [
      /^\s+(?:(?:static|final|late)\s+)*(?:void|bool|int|double|num|dynamic|[A-Z_]\w*(?:<[^(]*>)?\??)\s+(\w+)\s*\(/,
    ],
    // implementação ADVPL/TLPP: `Method x(...) [as <tipo>] Class Y`; grupo 1 = método, grupo 2 = classe
    advpl: [/^\s*method\s+(\w+)\s*\([^)]*\)(?:\s+as\s+\w+)?\s+class\s+(\w+)/i],
  },
};

/** Nome definido pela linha, no conjunto `topo` (padrão) ou `metodo`; null se a linha não define nada. */
function casar(linha, linguagem, conjunto = 'topo') {
  const lista = (REGRAS[conjunto] && REGRAS[conjunto][linguagem]) || [];
  for (const re of lista) {
    const m = re.exec(linha);
    if (m) return m[2] ? `${m[2]}:${m[1]}` : m[1];
  }
  return null;
}

module.exports = { EXTENSOES, REGRAS, casar };
