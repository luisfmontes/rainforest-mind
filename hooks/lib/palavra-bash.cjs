"use strict";
/**
 * Leitura da primeira palavra de um segmento de comando Bash, como o bash a lê.
 *
 * Enxertado de ruvnet/ruflo, plugins/ruflo-mods/hooks/guard/dangerous-command.ts (MIT).
 *
 * Funções puras: sem disco, sem processo. Um gate que decide por nome de comando
 * (`rm`, `git`, `cd`) precisa ver o nome que o bash VAI executar, não o texto cru:
 * `'cd' /x`, `c\d /x`, `$'\x63d' /x` e `{cd,/x}` executam `cd`, e um filtro
 * ingênuo deixa passar todos.
 *
 * - normalizarComando(seg): reescreve só a primeira palavra do segmento.
 * - expandirChaves(texto, marcas): expansão de chaves `{a,b}` do bash.
 * - corposDeSubstituicao(texto): corpo de cada crase e de cada `$(...)` fora de
 *   aspas simples, para o gate examinar o comando que roda dentro deles.
 *
 * `marcas` tem uma letra por caractere de `texto`: 'u' para caractere sem aspas
 * nem escape, 'q' para caractere entre aspas ou escapado. Só chave e vírgula
 * marcadas 'u' contam como sintaxe.
 */

const TERMINADORES = " \t\n;&|()<>";
const MAX_PALAVRAS = 4096;
const MAX_TRABALHO = 1000000;

// Um escape dentro de $'...'. `at` é o índice do caractere logo após a contrabarra.
// Devolve [texto que o escape representa, índice do último caractere consumido].
// Escape desconhecido mantém a contrabarra, como o bash.
function decodificarEscapeAnsi(s, at) {
  const c = s[at];
  const simples = {
    a: "\x07", b: "\b", e: "\x1b", E: "\x1b", f: "\f", n: "\n", r: "\r",
    t: "\t", v: "\v", "\\": "\\", "'": "'", '"': '"', "?": "?",
  };
  if (simples[c] !== undefined) return [simples[c], at];
  const digitos = (de, max, padrao) => (padrao.exec(s.slice(de, de + max)) || [])[0];
  const oct = digitos(at, 3, /^[0-7]+/);
  if (oct) return [String.fromCharCode(parseInt(oct, 8) & 255), at + oct.length - 1];
  const hex = c === "x" ? digitos(at + 1, 2, /^[0-9a-fA-F]+/) : undefined;
  if (hex) return [String.fromCharCode(parseInt(hex, 16)), at + hex.length];
  let wide;
  if (c === "u") wide = digitos(at + 1, 4, /^[0-9a-fA-F]+/);
  else if (c === "U") wide = digitos(at + 1, 8, /^[0-9a-fA-F]+/);
  if (wide && parseInt(wide, 16) <= 0x10ffff) {
    return [String.fromCodePoint(parseInt(wide, 16)), at + wide.length];
  }
  if (c === "c" && at + 1 < s.length) {
    return [String.fromCharCode(s.charCodeAt(at + 1) & 31), at + 1];
  }
  return ["\\" + c, at];
}

// O grupo `{...}` mais à esquerda com vírgula no próprio nível, fora de `${...}`.
// Uma passada com pilha. Devolve { abre, virgulas, fecha } ou undefined.
function acharGrupo(texto, marcas) {
  const pilha = [];
  let dolares = 0;
  let melhor;
  for (let k = 0; k < texto.length; k++) {
    if (marcas[k] !== "u") continue;
    const c = texto[k];
    if (c === "{") {
      const dolar = k > 0 && texto[k - 1] === "$" && marcas[k - 1] === "u";
      if (dolar) dolares++;
      pilha.push({ abre: k, virgulas: [], dolar: dolar || dolares > 0 });
    } else if (c === "," && pilha.length > 0) {
      pilha[pilha.length - 1].virgulas.push(k);
    } else if (c === "}" && pilha.length > 0) {
      const topo = pilha.pop();
      if (topo.dolar && texto[topo.abre - 1] === "$" && marcas[topo.abre - 1] === "u") dolares--;
      if (!topo.dolar && topo.virgulas.length > 0 && (melhor === undefined || topo.abre < melhor.abre)) {
        melhor = { abre: topo.abre, virgulas: topo.virgulas, fecha: k };
      }
    }
  }
  return melhor;
}

// Expansão de chaves do bash: ordem esquerda→direita, aninhada e colada ao texto.
// Iterativa (pilha). Passou de MAX_PALAVRAS palavras ou MAX_TRABALHO caracteres
// de trabalho → undefined.
function expandirChaves(texto, marcas) {
  const pilha = [[texto, marcas]];
  const saida = [];
  let trabalho = 0;
  while (pilha.length > 0) {
    const [t, m] = pilha.pop();
    trabalho += t.length;
    if (trabalho > MAX_TRABALHO) return undefined;
    const g = acharGrupo(t, m);
    if (g === undefined) {
      saida.push(t);
      if (saida.length > MAX_PALAVRAS) return undefined;
      continue;
    }
    const cortes = [g.abre, ...g.virgulas, g.fecha];
    // Empilhado ao contrário, para sair na ordem do bash.
    for (let c = cortes.length - 2; c >= 0; c--) {
      const de = cortes[c] + 1;
      const ate = cortes[c + 1];
      const novo = t.slice(0, g.abre) + t.slice(de, ate) + t.slice(g.fecha + 1);
      const novoM = m.slice(0, g.abre) + m.slice(de, ate) + m.slice(g.fecha + 1);
      trabalho += novo.length;
      if (trabalho > MAX_TRABALHO) return undefined;
      pilha.push([novo, novoM]);
    }
  }
  return saida;
}

// Lê a primeira palavra do segmento como o bash e expande as chaves dela.
// Devolve { seg, estouro }. Sem aspa, contrabarra, $' nem chave na primeira
// palavra, devolve o mesmo `seg` de entrada. O resto do segmento fica cru.
function normalizarComando(seg) {
  const s = String(seg);
  let inicio = 0;
  while (inicio < s.length && " \t\n".includes(s[inicio])) inicio++;
  let valor = "";
  let marcas = "";
  let precisa = false;
  let j = inicio;
  while (j < s.length && !TERMINADORES.includes(s[j])) {
    const c = s[j];
    if (c === "'") {
      precisa = true;
      let k = s.indexOf("'", j + 1);
      if (k < 0) k = s.length;
      valor += s.slice(j + 1, k);
      marcas += "q".repeat(k - j - 1);
      j = k + 1;
    } else if (c === '"') {
      precisa = true;
      j++;
      while (j < s.length && s[j] !== '"') {
        if (s[j] === "\\" && s[j + 1] === "\n") {
          // Continuação de linha dentro de aspas duplas: o par some (confirmado no bash).
          j += 2;
        } else if (s[j] === "\\" && j + 1 < s.length && '"\\$`'.includes(s[j + 1])) {
          valor += s[j + 1];
          marcas += "q";
          j += 2;
        } else {
          valor += s[j];
          marcas += "q";
          j++;
        }
      }
      j++;
    } else if (c === "\\") {
      precisa = true;
      if (s[j + 1] === "\n") {
        // Continuação de linha fora de aspas: o par some (confirmado no bash).
        j += 2;
      } else {
        if (j + 1 < s.length) {
          valor += s[j + 1];
          marcas += "q";
        }
        j += 2;
      }
    } else if (c === "$" && s[j + 1] === '"') {
      // $"..." é aspa dupla de locale: o $ some, e o laço seguinte lê a aspa.
      precisa = true;
      j++;
    } else if (c === "$" && s[j + 1] === "'") {
      precisa = true;
      j += 2;
      // NUL corta a string no bash: o resto do $'...' some, mas o laço segue até a aspa de fechamento.
      let cortado = false;
      while (j < s.length && s[j] !== "'") {
        if (s[j] === "\\" && j + 1 < s.length) {
          const [txt, ultimo] = decodificarEscapeAnsi(s, j + 1);
          if (txt === "\0") cortado = true;
          if (!cortado) {
            valor += txt;
            marcas += "q".repeat(txt.length);
          }
          j = ultimo + 1;
        } else {
          if (!cortado) {
            valor += s[j];
            marcas += "q";
          }
          j++;
        }
      }
      j++;
    } else {
      if (c === "{") precisa = true;
      valor += c;
      marcas += "u";
      j++;
    }
  }
  if (!precisa) return { seg: s, estouro: false };
  const fim = Math.min(j, s.length);
  const palavras = expandirChaves(valor, marcas);
  if (palavras === undefined) return { seg: s, estouro: true };
  return { seg: s.slice(0, inicio) + palavras.join(" ") + s.slice(fim), estouro: false };
}

// Índice do `)` que fecha um `$(` cujo conteúdo começa em `i`, ou -1.
// Parênteses dentro de aspas e escapes não contam.
function fechaParenteses(t, i) {
  let prof = 1;
  for (let j = i; j < t.length; j++) {
    const c = t[j];
    if (c === "\\") { j++; continue; }
    if (c === "'") {
      const k = t.indexOf("'", j + 1);
      if (k < 0) return -1;
      j = k;
      continue;
    }
    if (c === '"') {
      let k = j + 1;
      while (k < t.length && t[k] !== '"') k += t[k] === "\\" ? 2 : 1;
      if (k >= t.length) return -1;
      j = k;
      continue;
    }
    if (c === "(") prof++;
    else if (c === ")") {
      prof--;
      if (prof === 0) return j;
    }
  }
  return -1;
}

// Corpo de cada crase e de cada `$(...)` fora de aspas simples (dentro de aspas
// duplas conta). Crase escapada não abre corpo.
// Lê um nível só: crase dentro de `$(...)` e `$(...)` dentro de crase saem como
// texto do corpo, e quem chama recursa sobre cada corpo até não sobrar nenhum.
// `$((1+2))` sai como corpo `(1+2)`: é espúrio, mas não come o resto da linha.
function corposDeSubstituicao(texto) {
  const corpos = [];
  let sq = false;
  let dq = false;
  let i = 0;
  while (i < texto.length) {
    const c = texto[i];
    if (sq) {
      if (c === "'") sq = false;
      i++;
      continue;
    }
    if (c === "\\") { i += 2; continue; }
    if (c === "'" && !dq) { sq = true; i++; continue; }
    if (c === '"') { dq = !dq; i++; continue; }
    if (c === "`") {
      let k = i + 1;
      while (k < texto.length && texto[k] !== "`") k += texto[k] === "\\" ? 2 : 1;
      if (k >= texto.length) break;
      corpos.push(texto.slice(i + 1, k));
      i = k + 1;
      continue;
    }
    if (c === "$" && texto[i + 1] === "(") {
      const f = fechaParenteses(texto, i + 2);
      if (f < 0) break;
      corpos.push(texto.slice(i + 2, f));
      i = f + 1;
      continue;
    }
    i++;
  }
  return corpos;
}

module.exports = { normalizarComando, expandirChaves, corposDeSubstituicao };
