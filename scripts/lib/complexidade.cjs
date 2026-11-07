'use strict';
/**
 * Complexidade por função, por leitura de texto (D2-D6 do design complexidade-por-funcao).
 *
 * Aproximação sem parser, para JS/TS e Dart: um leitor de texto separa código de comentário,
 * string, template literal (com `${ }` aninhado), string tripla e crua do Dart e regex literal
 * do JS, e devolve fichas com a linha de cada uma. A medida anda nessas fichas.
 *
 * - cognitiva (estilo Sonar, regras próprias): `if`/`for`/`while`/`switch`/`catch` seguidos de
 *   `(` e o ternário somam 1 + profundidade; `else` e `else if` somam 1; cada troca de operador
 *   numa sequência de `&&`/`||` soma 1. Profundidade = blocos de controle e closures abertos
 *   dentro do corpo; `{` de objeto, mapa ou classe não aprofunda.
 * - ciclomática: 1 + cada `if`, `for`, `while`, `case`, `catch`, ternário, `&&` e `||`.
 *
 * `?` só é ternário com espaço dos dois lados (`String?`, `x?: T`, `?.` e `??` não contam).
 * String de aspas simples ou duplas termina no fim da linha se não fechar antes: o apóstrofo
 * de texto JSX só cega o resto daquela linha.
 *
 * Nada aqui foi copiado de outro projeto: as regras são reimplementadas da descrição pública das
 * duas métricas (crédito no design).
 */

// Só o que o D2 lista. `<` e `>` ficam de fora: em JSX a `/` de `</li>` vem depois de `<`, e
// regex depois de comparação é raro demais para pagar esse risco.
const ANTES_DE_REGEX = new Set([
  null, '(', ',', '=', ':', '[', '!', '&', '|', '?', '?:', '{', '}', ';', '&&', '||', '??', '=>',
  'return', 'typeof', 'case',
]);
// Ficha que, no fim de uma linha, deixa a expressão continuar na seguinte (corpo `=> expr` sem `;`).
// `<` e `>` ficam de fora: `</div>` termina em `>` e a seta de JSX de uma linha acabava engolindo a
// função seguinte. `+` e `-` só emendam quando não são `++`/`--` (ver `emendaNoFim`).
const CONTINUA_EXPRESSAO = new Set([
  '?', '?:', ':', '&&', '||', '??', '+', '-', '*', '/', '%', '.', '?.', ',', '(', '[', '=', '=>', '!', '&', '|',
]);

/** A ficha `k` termina a linha deixando a expressão aberta? `counter++` e `i--` não deixam. */
function emendaNoFim(fichas, k) {
  const t = fichas[k].t;
  if (!CONTINUA_EXPRESSAO.has(t)) return false;
  if ((t === '+' || t === '-') && k > 0 && fichas[k - 1].t === t) return false;
  return true;
}
// `)` que fecha a condição de um destes admite regex logo depois (D6). Marca interna do tokenizador.
const CONDICAO_ANTES_DE_REGEX = new Set(['if', 'while', 'for']);
const FECHA_CONDICAO = ')condicao';
const CONTROLE_COM_PARENTESES = new Set(['if', 'for', 'while', 'switch', 'catch']);
const ABRE_BLOCO_DE_CONTROLE = new Set(['if', 'else', 'for', 'while', 'do', 'switch', 'try', 'catch', 'finally']);
const ZERA_SEQUENCIA = new Set(['(', ')', ';', ',', '{', '}']);

/** Fichas `{t, l}` do código; strings viram 'str', regex vira 'regex', número vira 'num'. */
function tokenizar(texto, ehDart) {
  const fichas = [];
  const n = texto.length;
  let i = 0;
  let linha = 1;
  let anterior = null;
  // Um item por `(` aberto: true quando ele abre a condição de `if`/`while`/`for`.
  const parentesesDeCondicao = [];
  const emite = (t) => {
    fichas.push({ t, l: linha });
    anterior = t;
  };

  function lerString(delim, tripla, cru, template) {
    while (i < n) {
      const c = texto[i];
      if (!cru && c === '\\') {
        if (texto[i + 1] === '\n') linha++;
        i += 2;
        continue;
      }
      if (tripla) {
        if (texto.startsWith(delim + delim + delim, i)) {
          i += 3;
          return;
        }
      } else if (c === delim) {
        i++;
        return;
      }
      if (c === '\n') {
        if (!tripla && !template) return; // string simples não atravessa a linha
        linha++;
        i++;
        continue;
      }
      if (!cru && (template || ehDart) && c === '$' && texto[i + 1] === '{') {
        i += 2;
        lerCodigo(true);
        continue;
      }
      i++;
    }
  }

  function lerRegex() {
    i++;
    let classe = false;
    while (i < n) {
      const c = texto[i];
      if (c === '\n') return;
      if (c === '\\') {
        i += 2;
        continue;
      }
      if (c === '[') classe = true;
      else if (c === ']') classe = false;
      else if (c === '/' && !classe) {
        i++;
        while (i < n && /[a-z]/i.test(texto[i])) i++;
        return;
      }
      i++;
    }
  }

  function lerCodigo(interpolacao) {
    let chaves = 0;
    while (i < n) {
      const c = texto[i];
      const d = texto[i + 1];
      if (c === '\n') {
        linha++;
        i++;
        continue;
      }
      if (c === ' ' || c === '\t' || c === '\r') {
        i++;
        continue;
      }
      if (c === '/' && d === '/') {
        while (i < n && texto[i] !== '\n') i++;
        continue;
      }
      if (c === '/' && d === '*') {
        i += 2;
        while (i < n && !(texto[i] === '*' && texto[i + 1] === '/')) {
          if (texto[i] === '\n') linha++;
          i++;
        }
        i += 2;
        continue;
      }
      if (ehDart && c === 'r' && (d === "'" || d === '"')) {
        const tripla = texto.startsWith(d + d + d, i + 1);
        i += tripla ? 4 : 2;
        lerString(d, tripla, true, false);
        emite('str');
        continue;
      }
      if (c === "'" || c === '"') {
        const tripla = ehDart && texto.startsWith(c + c + c, i);
        i += tripla ? 3 : 1;
        lerString(c, tripla, false, false);
        emite('str');
        continue;
      }
      if (c === '`' && !ehDart) {
        i++;
        lerString('`', false, false, true);
        emite('str');
        continue;
      }
      // `/>` é fechamento de tag JSX, nunca regex. Depois do `)` da condição de `if`/`while`/`for`
      // a `/` abre regex (`if (s) /[}]/.test(s)`, D6). Depois de `}`, só abre regex como primeira
      // ficha da linha: na mesma linha é texto JSX (`{page}/{pages}`), D7.
      const primeiraDaLinha = !fichas.length || fichas[fichas.length - 1].l !== linha;
      const regexPossivel = anterior === FECHA_CONDICAO
        || (ANTES_DE_REGEX.has(anterior) && (anterior !== '}' || primeiraDaLinha));
      if (c === '/' && d !== '>' && !ehDart && regexPossivel) {
        lerRegex();
        emite('regex');
        continue;
      }
      if (/[A-Za-z_$]/.test(c)) {
        let j = i;
        while (j < n && /[\w$]/.test(texto[j])) j++;
        emite(texto.slice(i, j));
        i = j;
        continue;
      }
      if (/[0-9]/.test(c)) {
        let j = i;
        while (j < n && /[\w.]/.test(texto[j])) j++;
        emite('num');
        i = j;
        continue;
      }
      if (interpolacao && c === '}' && chaves === 0) {
        i++;
        return;
      }
      if (c === '{') chaves++;
      else if (c === '}') chaves--;
      const dois = c + (d || '');
      if (dois === '&&' || dois === '||' || dois === '??' || dois === '?.' || dois === '=>') {
        emite(dois);
        i += 2;
        continue;
      }
      if (c === '?') {
        const antes = i > 0 ? texto[i - 1] : '';
        emite(/\s/.test(antes) && /\s/.test(d || '') ? '?:' : '?');
        i++;
        continue;
      }
      emite(c);
      if (c === '(') parentesesDeCondicao.push(CONDICAO_ANTES_DE_REGEX.has(fichas.length > 1 ? fichas[fichas.length - 2].t : null));
      else if (c === ')' && parentesesDeCondicao.pop()) anterior = FECHA_CONDICAO;
      i++;
    }
  }

  lerCodigo(false);
  return fichas;
}

/** Contribuição de uma estrutura aninhada: 1 mais a profundidade em que ela está. */
function incrementoAninhado(profundidade) {
  return 1 + profundidade;
}

/** Índice da chave que fecha a `{` em `k`, ou -1. */
function fechaChave(fichas, k) {
  let prof = 0;
  for (let m = k; m < fichas.length; m++) {
    if (fichas[m].t === '{') prof++;
    else if (fichas[m].t === '}' && --prof === 0) return m;
  }
  return -1;
}

/**
 * Corpo `=> expr` (a ficha `de` é a primeira depois da seta): termina no `;` fora de parênteses,
 * colchetes e chaves, ou na quebra de linha em que nada fica aberto, a linha anterior não termina
 * em operador e a seguinte não começa com um (estilo sem ponto e vírgula).
 */
function fimDaExpressao(fichas, de) {
  let aberto = 0;
  for (let k = de; k < fichas.length; k++) {
    const t = fichas[k].t;
    if (k > de && aberto === 0 && fichas[k].l > fichas[k - 1].l
        && !emendaNoFim(fichas, k - 1) && !CONTINUA_EXPRESSAO.has(t)) return k;
    if (t === '(' || t === '[' || t === '{') aberto++;
    else if (t === ')' || t === ']' || t === '}') {
      if (aberto === 0) return k; // a expressão era argumento de algo que fecha aqui
      aberto--;
    } else if (t === ';' && aberto === 0) return k;
  }
  return fichas.length;
}

/**
 * Acha o corpo da definição que começa na ficha `ini`. Depois de `=>` fora de parênteses: bloco
 * `{ }` se a seta é seguida de `{`, senão a expressão (`fimDaExpressao`). Sem seta: da primeira
 * `{` fora de parênteses até a `}` que a fecha; `;` antes dela é corpo vazio (`void f();`). Chave
 * que fecha e é seguida de `>`, `{`, `|`, `&`, `[` ou `=>` era tipo literal (`): {a: T} {`) e a
 * busca continua. Devolve {de, ate} (índices exclusivos do corpo) ou null se não fechou.
 */
function acharCorpo(fichas, ini) {
  let parenteses = 0;
  let angulos = 0; // `<...>` de genérico na assinatura: `Promise<() => void>` não é a seta do corpo
  // `const f: (a: T) => void = ...`: a anotação de tipo vai até o `=`, e a seta dela não é a do corpo.
  let tipo = fichas[ini + 1] && fichas[ini + 1].t === ':';
  let envolve = false; // `memo(` / `forwardRef<T>(`: o `(` da chamada é transparente (D4)
  let fechouParametros = false;
  for (let k = ini; k < fichas.length; k++) {
    const t = fichas[k].t;
    if (t === '(' && envolve) {
      envolve = false;
      continue;
    }
    if (tipo) {
      if (t === '(') parenteses++;
      else if (t === ')') parenteses--;
      else if (t === '<') angulos++;
      else if (t === '>' && angulos > 0) angulos--;
      else if (t === '=' && parenteses === 0 && angulos === 0) tipo = false;
      if (tipo || t !== '=') continue;
    }
    const iife = fichas[k + 2] && ['(', 'function', 'async'].includes(fichas[k + 2].t);
    if (t === '=' && parenteses === 0 && angulos === 0 && fichas[k + 1] && fichas[k + 1].t === '(' && !iife) {
      // `const total = (a + b) * c`: depois do `)` que fecha não vem `=>` nem tipo de retorno,
      // então não é função (D9). Sai sem medida e sem aviso. IIFE (`const RAIZ = (() => {`) fica:
      // é lógica de verdade, medida desde a 2.5.0.
      let p = 0;
      let m = k + 1;
      for (; m < fichas.length; m++) {
        if (fichas[m].t === '(') p++;
        else if (fichas[m].t === ')' && --p === 0) break;
      }
      const depois = fichas[m + 1] && fichas[m + 1].t;
      if (depois !== '=>' && depois !== ':') return { naoFuncao: true };
    }
    if ((t === 'memo' || t === 'forwardRef') && parenteses === 0 && angulos === 0
        && fichas[k + 1] && (fichas[k + 1].t === '(' || fichas[k + 1].t === '<')) {
      envolve = true;
      continue;
    }
    // Sobrecarga TS sem `;` (D9): parâmetros fechados, nada aberto, e a linha seguinte começa outra
    // instrução sem a assinatura ter emendado. Termina aqui, como a sobrecarga com `;`.
    if (fechouParametros && parenteses === 0 && angulos === 0 && k > ini && fichas[k].l > fichas[k - 1].l
        && t !== '{' && !emendaNoFim(fichas, k - 1) && !CONTINUA_EXPRESSAO.has(t)) {
      return { de: ini, ate: k };
    }
    if (t === ')' && parenteses === 1) fechouParametros = true;
    if (t === '(') parenteses++;
    else if (t === ')') parenteses--;
    else if (t === '<' && parenteses === 0) angulos++;
    else if (t === '>' && parenteses === 0 && angulos > 0) angulos--;
    else if (angulos > 0) continue;
    else if (t === '=>' && parenteses === 0) {
      if (fichas[k + 1] && fichas[k + 1].t === '{') {
        const fim = fechaChave(fichas, k + 1);
        return fim === -1 ? null : { de: k + 2, ate: fim };
      }
      return { de: k + 1, ate: fimDaExpressao(fichas, k + 1) };
    } else if (t === ';' && parenteses === 0) return { de: ini, ate: k };
    else if (t === '{' && parenteses === 0) {
      const fim = fechaChave(fichas, k);
      if (fim === -1) return null;
      // Só emenda na mesma linha da `}`: `[1, 2].forEach(g)` na linha de baixo é outra instrução.
      const prox = fichas[fim + 1];
      const depois = prox && prox.l === fichas[fim].l && prox.t;
      if (['>', '{', '|', '&', '[', '=>'].includes(depois)) {
        k = fim;
        continue;
      }
      return { de: k + 1, ate: fim };
    }
  }
  return null;
}

/** Mede as fichas [de, ate) de um corpo. */
function medirCorpo(fichas, de, ate) {
  let cognitiva = 0;
  let ciclomatica = 1;
  const contribuicoes = [];
  const soma = (valor, linha, rotulo) => {
    cognitiva += valor;
    contribuicoes.push({ valor, linha, rotulo });
  };
  let profundidade = 0;
  const blocos = [];
  let parenteses = 0;
  let pendente = null;
  let esperaCondicao = false; // entre `if` e o `)` da condição dele
  let corpoSemChave = false; // o corpo da estrutura pendente já começou, e não foi com `{`
  let sequencia = null;
  for (let k = de; k < ate; k++) {
    const { t, l } = fichas[k];
    const ant = k > de ? fichas[k - 1].t : null;
    const prox = k + 1 < ate ? fichas[k + 1].t : null;
    // `if (x) return` sem `;`: a quebra de linha que encerra a instrução do corpo encerra a
    // estrutura, e a `{` de objeto da instrução seguinte não aprofunda (D8). "Encerra" é o
    // critério do corpo `=> expr`: nada aberto, linha sem operador no fim nem no começo da seguinte.
    if (corpoSemChave && parenteses === pendente && k > de && l > fichas[k - 1].l
        && !emendaNoFim(fichas, k - 1) && !CONTINUA_EXPRESSAO.has(t)) {
      pendente = null;
      corpoSemChave = false;
    }
    if (pendente !== null && !esperaCondicao && parenteses === pendente && t !== '{' && t !== ';') {
      corpoSemChave = true;
    }
    if (ZERA_SEQUENCIA.has(t)) sequencia = null;
    if (t === '(') parenteses++;
    else if (t === ')') {
      parenteses--;
      if (esperaCondicao && parenteses === pendente) esperaCondicao = false;
    } else if (t === ';') {
      if (pendente !== null && parenteses === pendente) {
        pendente = null;
        corpoSemChave = false;
      }
    } else if (t === '{') {
      let aprofunda = false;
      if (pendente !== null && parenteses === pendente && !corpoSemChave) {
        aprofunda = true;
        pendente = null;
      } else if (ant === '=>' || ant === ')' || ant === 'async') {
        aprofunda = true;
      }
      blocos.push(aprofunda);
      if (aprofunda) profundidade++;
    } else if (t === '}') {
      if (blocos.pop()) profundidade--;
    } else if (t === 'else') {
      pendente = parenteses;
      esperaCondicao = false;
      corpoSemChave = false;
      if (prox !== 'if') soma(1, l, 'else');
    } else if (ABRE_BLOCO_DE_CONTROLE.has(t) && ant !== '.' && ant !== '?.') {
      // `.catch(` de promessa é chamada de método, não estrutura de controle.
      pendente = parenteses;
      esperaCondicao = CONTROLE_COM_PARENTESES.has(t) && prox === '(';
      corpoSemChave = false;
      if (CONTROLE_COM_PARENTESES.has(t) && prox === '(') {
        if (t === 'if' && ant === 'else') {
          soma(1, l, 'else if');
        } else {
          soma(incrementoAninhado(profundidade), l, `${t} (profundidade ${profundidade})`);
        }
        if (t !== 'switch') ciclomatica++;
      }
    } else if (t === 'case') {
      ciclomatica++;
    } else if (t === '?:') {
      soma(incrementoAninhado(profundidade), l, `ternário (profundidade ${profundidade})`);
      ciclomatica++;
    } else if (t === '&&' || t === '||') {
      ciclomatica++;
      if (sequencia !== t) {
        soma(1, l, `sequência ${t}`);
        sequencia = t;
      }
    }
  }
  contribuicoes.sort((a, b) => b.valor - a.valor || a.linha - b.linha);
  return { cognitiva, ciclomatica, contribuicoes };
}

/**
 * Mede as definições de um arquivo. `definicoes` = [{linha, nome, assinatura}] em ordem de linha.
 * Classe não é unidade; definição que começa dentro do corpo de outra já medida soma na mãe.
 * Devolve {medidas: [{linha, nome, fim, cognitiva, ciclomatica, contribuicoes}], naoMedidas: [{linha, nome, motivo}]}.
 */
function medirArquivo(texto, linguagem, definicoes) {
  const fichas = tokenizar(texto, linguagem === 'dart');
  const medidas = [];
  const naoMedidas = [];
  const linhas = texto.split(/\r?\n/);
  const recuo = (d) => /^\s*/.exec(linhas[d.linha - 1] || '')[0].length;
  let mae = null;
  for (const def of definicoes) {
    if (/(^|\s)class\s/.test(def.assinatura)) continue;
    // O nome tem de ser código naquela linha: definição dentro de comentário ou string não é unidade.
    const ini = fichas.findIndex((f) => f.l === def.linha && f.t === def.nome);
    if (ini === -1) continue;
    if (mae && def.linha <= mae.fim) {
      // Definição com recuo menor ou igual ao da mãe nunca mora dentro dela: função de topo dentro
      // de função de topo, método dentro do método vizinho (D5). Se o corpo da mãe a atravessou, a
      // leitura de texto errou: a mãe sai como lacuna declarada e esta é medida normalmente. Recuo
      // maior é função aninhada de verdade, e soma na mãe.
      if (!(recuo(def) <= mae.recuo)) continue;
      medidas.splice(medidas.indexOf(mae.medida), 1);
      naoMedidas.push({ linha: mae.medida.linha, nome: mae.medida.nome, motivo: `corpo passou por ${def.nome} (L${def.linha}): leitura errada` });
      mae = null;
    }
    const corpo = acharCorpo(fichas, ini);
    if (corpo && corpo.naoFuncao) continue;
    if (!corpo) {
      naoMedidas.push({ linha: def.linha, nome: def.nome, motivo: 'corpo não fechou' });
      continue;
    }
    // Fim do corpo: a `}` ou o `;` que o fecha; corpo de expressão sem `;` acaba na última ficha
    // dele, e não na primeira da linha seguinte (que pode ser a próxima definição).
    const fecho = fichas[corpo.ate];
    const fim = fecho && (fecho.t === '}' || fecho.t === ';') ? fecho.l : fichas[Math.max(corpo.ate - 1, 0)].l;
    const medida = { linha: def.linha, nome: def.nome, fim, ...medirCorpo(fichas, corpo.de, corpo.ate) };
    medidas.push(medida);
    mae = { medida, fim, recuo: recuo(def) };
  }
  return { medidas, naoMedidas };
}

module.exports = { tokenizar, medirArquivo, incrementoAninhado };
