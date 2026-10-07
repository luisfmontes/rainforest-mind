// Logica pura da faixa de foco: ES module sem Node, sem acesso a ambiente. Recebe so
// valores (os dados do script da faixa e o texto da resposta) e devolve valores; quem
// liga isso a tela e o mod.
//
// Contrato dos dados (so estes campos sao lidos, D10: prazo, jornada e versao nunca
// entram, mesmo que o objeto os traga):
//   dados = { foco: string|null, fluxos: [{ slug, etapa, tarefas_ok, tarefas, em_voo }] }
//   qs    = [{ n, titulo }]
//   relogio = linha pronta do relogio (string) ou null; a faixa tem ate 4 linhas:
//   foco, fluxo, relogio, Q.

export const MAX_LINHAS = 4;

// As duas formas com que o brainstorm numera uma pergunta aberta. Cada marcador captura
// o numero e o titulo; ambos aceitam o prefixo de blockquote `> ` e de item de lista
// (`- `, `* `, `1. `).
const PREFIXO = String.raw`^\s*(?:>\s*)*(?:(?:[-*+]|\d+[.)])\s+)?`;
export const MARCADORES_Q = [
  new RegExp(PREFIXO + String.raw`❓\s*\*\*Q(\d+)\s*[—–-]\s*(.*?)\*\*`, 'u'),
  new RegExp(PREFIXO + String.raw`\*\*Q(\d+)\.\*\*\s*(.*)$`, 'u'),
];

// Cerca de codigo: ``` ou ~~~ (3+), fechada pela mesma letra com o mesmo tamanho ou maior.
const CERCA = /^\s*(?:>\s*)*(`{3,}|~{3,})/;

function semMarkdown(s) {
  return String(s).replace(/[*_`]/g, '').trim();
}

// Na forma `**Qn.** texto` o resto da linha traz a pergunta e, muitas vezes, a
// recomendacao. O titulo e so a pergunta: corta no primeiro `?` (que fica), ou no
// primeiro `:`, ` — ` ou `. `, o que vier antes.
function tituloCurto(s) {
  const fim = [s.indexOf('?') + 1 || Infinity, s.indexOf(':'), s.indexOf(' — '), s.indexOf(' - '), s.indexOf('. ')]
    .filter(i => i > 0)
    .reduce((a, b) => Math.min(a, b), Infinity);
  return (fim === Infinity ? s : s.slice(0, fim)).trim();
}

/** @param {unknown} texto @returns {{n:number,titulo:string}[]} */
export function extrairQs(texto) {
  if (typeof texto !== 'string') return [];
  const achados = [];
  const vistos = new Set();
  let cerca = null;
  for (const linha of texto.split(/\r?\n/)) {
    const c = CERCA.exec(linha);
    if (c) {
      if (cerca === null) cerca = c[1];
      else if (c[1][0] === cerca[0] && c[1].length >= cerca.length) cerca = null;
      continue;
    }
    if (cerca !== null) continue;
    for (let i = 0; i < MARCADORES_Q.length; i++) {
      const m = MARCADORES_Q[i].exec(linha);
      if (!m) continue;
      const n = Number(m[1]);
      if (!vistos.has(n)) {
        vistos.add(n);
        achados.push({ n, titulo: tituloCurto(semMarkdown(m[2])) });
      }
      break;
    }
  }
  return achados;
}

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

const num = v => typeof v === 'number' && Number.isFinite(v);

function linhaFluxo(dados) {
  const fluxos = dados && Array.isArray(dados.fluxos) ? dados.fluxos : [];
  const f = fluxos[0];
  if (!f || !f.slug || !f.etapa) return null;
  let s = `fluxo ${String(f.slug).replace(/^\d{4}-\d{2}-\d{2}-/, '')}: ${f.etapa}`;
  if (num(f.tarefas_ok) && num(f.tarefas)) s += ` ${f.tarefas_ok}/${f.tarefas}`;
  const voo = Array.isArray(f.em_voo) ? f.em_voo.length : 0;
  if (voo > 0) s += ` | ${voo} em voo`;
  if (fluxos.length > 1) s += ` | +${fluxos.length - 1}`;
  return s;
}

// Cada Q recebe a sua fatia da largura, para todas aparecerem: titulo longo corta com
// `…` dentro da fatia em vez de empurrar as seguintes para fora da linha.
function linhaQ(qs, cols) {
  if (!Array.isArray(qs) || qs.length === 0) return null;
  const prefixo = `Q ${qs.length} aberta(s): `;
  const resto = Number.isFinite(cols) ? cols - largura(prefixo) - 3 * (qs.length - 1) : Infinity;
  const fatia = Math.max(8, Math.floor(resto / qs.length));
  const itens = qs.map(q => cortar(`Q${q.n} ${semControle(String(q.titulo))}`, fatia)).join(' | ');
  return prefixo + itens;
}

/** @returns {string[]} no maximo maxLinhas, cada uma com largura <= cols */
export function montarLinhas(dados, qs, cols, maxLinhas, relogio) {
  const q = linhaQ(qs, cols);
  const fluxo = linhaFluxo(dados);
  if (!q && !fluxo && !relogio) return [];
  const foco = dados && typeof dados.foco === 'string' && dados.foco.trim() ? `foco  ${dados.foco.trim()}` : null;
  // Prioridade quando falta espaco: Q, relogio, fluxo, foco. Exibicao: foco, fluxo, relogio, Q.
  const max = Math.max(0, Math.min(MAX_LINHAS, maxLinhas ?? MAX_LINHAS));
  const prioridade = [['q', q], ['relogio', relogio], ['fluxo', fluxo], ['foco', foco]].filter(p => p[1]).slice(0, max);
  const ficam = new Set(prioridade.map(p => p[0]));
  const ordem = [['foco', foco], ['fluxo', fluxo], ['relogio', relogio], ['q', q]];
  return ordem.filter(p => ficam.has(p[0])).map(p => cortar(semControle(p[1]), cols));
}

// Titulo de Q vem do texto do modelo e o foco do FOCO.md: ESC (sequencia ANSI), outros
// controles C0/C1 e override bidi nunca chegam crus ao terminal.
const CONTROLES = /[\u0000-\u001f\u007f-\u009f\u061c\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u2069\ufeff]/g;
export function semControle(s) {
  return s.replace(CONTROLES, ' ');
}

/** Estavel: muda com Q nova, etapa/slug novos e agente novo em voo; nao com tarefas_ok. */
export function assinatura(dados, qs, assinaturaRelogio) {
  const fluxos = dados && Array.isArray(dados.fluxos) ? dados.fluxos : [];
  const f = fluxos[0] || {};
  const voo = Array.isArray(f.em_voo) ? [...f.em_voo].map(String).sort() : [];
  const perguntas = (Array.isArray(qs) ? qs : []).map(q => [q.n, q.titulo]);
  const base = [perguntas, f.slug ?? null, f.etapa ?? null, voo];
  if (typeof assinaturaRelogio === 'string' && assinaturaRelogio) base.push(assinaturaRelogio);
  return JSON.stringify(base);
}

/** Esconder vale ate a assinatura mudar. */
export function escondida(oculto, assinatura) {
  return oculto !== null && oculto === assinatura;
}
