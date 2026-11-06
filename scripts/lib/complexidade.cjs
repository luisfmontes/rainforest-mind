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

const ANTES_DE_REGEX = new Set([
  null, '(', ',', '=', ':', '[', '!', '&', '|', '?', '?:', '{', '}', ';', '&&', '||', '??', '=>',
  'return', 'typeof', 'case', '+', '-', '*', '%', '<', '>', '~', '^',
]);
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
      if (c === '/' && !ehDart && ANTES_DE_REGEX.has(anterior)) {
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

/**
 * Acha o corpo da definição que começa na ficha `ini`: da primeira `{` fora de parênteses até a
 * `}` que a fecha; sem `{` antes de um `;`, até o `;`. Chave que fecha e é seguida de `>`, `{`,
 * `|`, `&` ou `[` era tipo literal (`): {a: T} {`) e a busca continua.
 * Devolve {de, ate} (índices exclusivos do corpo) ou null se não fechou.
 */
function acharCorpo(fichas, ini) {
  let parenteses = 0;
  for (let k = ini; k < fichas.length; k++) {
    const t = fichas[k].t;
    if (t === '(') parenteses++;
    else if (t === ')') parenteses--;
    else if (t === ';' && parenteses === 0) return { de: ini, ate: k };
    else if (t === '{' && parenteses === 0) {
      let prof = 0;
      let fim = -1;
      for (let m = k; m < fichas.length; m++) {
        if (fichas[m].t === '{') prof++;
        else if (fichas[m].t === '}') {
          prof--;
          if (prof === 0) {
            fim = m;
            break;
          }
        }
      }
      if (fim === -1) return null;
      const depois = fichas[fim + 1] && fichas[fim + 1].t;
      if (['>', '{', '|', '&', '['].includes(depois)) {
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
  let sequencia = null;
  for (let k = de; k < ate; k++) {
    const { t, l } = fichas[k];
    const ant = k > de ? fichas[k - 1].t : null;
    const prox = k + 1 < ate ? fichas[k + 1].t : null;
    if (ZERA_SEQUENCIA.has(t)) sequencia = null;
    if (t === '(') parenteses++;
    else if (t === ')') parenteses--;
    else if (t === ';') {
      if (pendente !== null && parenteses === pendente) pendente = null;
    } else if (t === '{') {
      let aprofunda = false;
      if (pendente !== null && parenteses === pendente) {
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
      if (prox !== 'if') soma(1, l, 'else');
    } else if (ABRE_BLOCO_DE_CONTROLE.has(t)) {
      pendente = parenteses;
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
  let fimDaMae = 0;
  for (const def of definicoes) {
    if (/(^|\s)class\s/.test(def.assinatura) || /^class\s/.test(def.assinatura)) continue;
    if (def.linha <= fimDaMae) continue;
    const ini = fichas.findIndex((f) => f.l >= def.linha);
    const corpo = ini === -1 ? null : acharCorpo(fichas, ini);
    if (!corpo) {
      naoMedidas.push({ linha: def.linha, nome: def.nome, motivo: 'corpo não fechou' });
      continue;
    }
    const fim = fichas[Math.min(corpo.ate, fichas.length - 1)].l;
    fimDaMae = fim;
    medidas.push({ linha: def.linha, nome: def.nome, fim, ...medirCorpo(fichas, corpo.de, corpo.ate) });
  }
  return { medidas, naoMedidas };
}

module.exports = { tokenizar, medirArquivo, incrementoAninhado };
