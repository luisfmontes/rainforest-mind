// Biblioteca de largura em celulas de terminal: ES module sem Node, sem acesso a ambiente.
// Guardou o nome da faixa de foco que o mod desenhava antes da barra de sessao (o foco, as
// linhas de fluxo e as Q sairam, D2); hoje so serve a hooks/painel-puro.mjs: `largura`,
// `cortar` e `semControle`. Renomear o arquivo e escopo a parte.

// Largura em celulas de terminal: emoji e CJK valem 2; combinantes e seletores de
// variacao valem 0. Um caractere seguido de U+FE0F (apresentacao de emoji) vale 2.
const LARGOS = [
  [0x1100, 0x115f], [0x2e80, 0xa4cf], [0xac00, 0xd7a3], [0xf900, 0xfaff],
  [0xfe30, 0xfe6f], [0xff00, 0xff60], [0xffe0, 0xffe6],
  [0x231a, 0x231b], [0x23e9, 0x23ec], [0x23f0, 0x23f0], [0x23f3, 0x23f3],
  [0x25fd, 0x25fe], [0x2614, 0x2615], [0x2648, 0x2653], [0x267f, 0x267f],
  [0x2693, 0x2693], [0x26a1, 0x26a1], [0x26aa, 0x26ab], [0x26bd, 0x26be],
  [0x26c4, 0x26c5], [0x26ce, 0x26ce], [0x26d4, 0x26d4], [0x26ea, 0x26ea],
  [0x26f2, 0x26f3], [0x26f5, 0x26f5], [0x26fa, 0x26fa], [0x26fd, 0x26fd],
  [0x2705, 0x2705], [0x270a, 0x270b], [0x2728, 0x2728], [0x274c, 0x274c],
  [0x274e, 0x274e], [0x2753, 0x2755], [0x2757, 0x2757], [0x2795, 0x2797],
  [0x27b0, 0x27b0], [0x27bf, 0x27bf], [0x2b1b, 0x2b1c], [0x2b50, 0x2b50],
  [0x2b55, 0x2b55], [0x1f004, 0x1f004], [0x1f0cf, 0x1f0cf], [0x1f18e, 0x1f18e],
  [0x1f191, 0x1f19a], [0x1f200, 0x1f64f], [0x1f680, 0x1f6ff], [0x1f7e0, 0x1f7eb],
  [0x1f900, 0x1faff], [0x20000, 0x3fffd],
];
const ZERO = [
  [0x0300, 0x036f], [0x1ab0, 0x1aff], [0x1dc0, 0x1dff], [0x200b, 0x200f],
  [0x20d0, 0x20ff], [0xfe00, 0xfe0f], [0xfe20, 0xfe2f], [0xe0100, 0xe01ef],
];
const dentro = (tabela, c) => tabela.some(([a, b]) => c >= a && c <= b);

function larguraDe(c, seguinte) {
  if (dentro(ZERO, c)) return 0;
  if (dentro(LARGOS, c) || seguinte === 0xfe0f) return 2;
  return 1;
}

/** @param {unknown} str */
export function largura(str) {
  const cps = Array.from(String(str ?? ''), ch => ch.codePointAt(0));
  let total = 0;
  for (let i = 0; i < cps.length; i++) total += larguraDe(cps[i], cps[i + 1]);
  return total;
}

export function cortar(str, cols) {
  if (largura(str) <= cols) return str;
  if (cols < 1) return '';
  const cps = Array.from(str);
  let saida = '';
  let w = 0;
  for (let i = 0; i < cps.length; i++) {
    const c = larguraDe(cps[i].codePointAt(0), cps[i + 1] ? cps[i + 1].codePointAt(0) : 0);
    if (w + c > cols - 1) break;
    saida += cps[i];
    w += c;
  }
  return saida + '…';
}

// Texto que vem do modelo (nome de subagente, titulo): ESC (sequencia ANSI), outros controles
// C0/C1 e override bidi nunca chegam crus ao terminal.
const CONTROLES = /[\u0000-\u001f\u007f-\u009f\u061c\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u2069\ufeff]/g;
export function semControle(s) {
  return s.replace(CONTROLES, ' ');
}
