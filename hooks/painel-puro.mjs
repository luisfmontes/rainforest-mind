// Adaptado do terminal-desk 0.2.1 (licenca MIT, titular ClariSortAi); texto da licenca e
// origem em NOTICE, na raiz do plugin.
// Logica pura do painel do mod (barra de sessao e pane): preco e cache de prompt, fatias
// do contexto, ritmo, formatacao e as figuras da barra. ES module sem Node, sem `$` e sem
// relogio: o instante entra por argumento (`agora`, em ms), nunca por leitura.
// Largura em celulas vem de faixa-puro.mjs (nunca copiada aqui).

import { largura, cortar, semControle } from './faixa-puro.mjs';

const MINUTO = 60_000;

// Precos de lista da API em dolares por milhao de tokens de entrada e a parcela que uma
// leitura de cache custa dela. A primeira linha que casa vence (cotacoes de 2026-09-25,
// nao reconferidas).
export const PRECOS = [
  { casa: 'fable-5-1', entrada: 10, leitura: 0.025 },
  { casa: 'mythos-5-1', entrada: 10, leitura: 0.025 },
  { casa: 'fable', entrada: 10, leitura: 0.1 },
  { casa: 'mythos', entrada: 10, leitura: 0.1 },
  { casa: 'opus-5-5', entrada: 4, leitura: 0.05 },
  { casa: 'opus', entrada: 5, leitura: 0.1 },
  { casa: 'sonnet-5', entrada: 2, leitura: 0.1 },
  { casa: 'sonnet', entrada: 3, leitura: 0.1 },
  { casa: 'haiku', entrada: 1, leitura: 0.1 },
];

export function precoDe(modelo) {
  const nome = String(modelo ?? '');
  return PRECOS.find((p) => nome.includes(p.casa)) ?? null;
}

export function compacto(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(2) + 'M';
  return n >= 1000 ? (n / 1000).toFixed(1) + 'K' : String(n);
}

export function dinheiro(usd) {
  if (typeof usd !== 'number' || !Number.isFinite(usd)) return '--';
  return usd > 0 && usd < 0.005 ? '<$0.01' : '$' + usd.toFixed(2);
}

// Minutos e segundos que faltam, para a contagem se ver andar.
export function restante(ms) {
  const s = Math.ceil(Math.max(0, ms) / 1000);
  return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
}

// Chamadas de ferramenta no ultimo minuto antes de `agora`.
export function ritmoPorMinuto(carimbos, agora) {
  return (Array.isArray(carimbos) ? carimbos : []).filter((t) => agora - t <= MINUTO).length;
}

// Cache de prompt: quente enquanto a ultima requisicao da sessao principal comecou dentro
// da vida do cache (reenviar e leitura barata); frio depois (a janela inteira e escrita de
// novo, a 1,25x no cache de 5 min e a 2x no de 1 h).
export function cacheDe({ modelo, ctxTokens, ultimaRequisicaoMs, agora, ttlMs }) {
  const restanteMs = ultimaRequisicaoMs === 0 ? 0 : Math.max(0, ultimaRequisicaoMs + ttlMs - agora);
  const quente = restanteMs > 0;
  const preco = precoDe(modelo);
  const semDado = preco === null || typeof ctxTokens !== 'number';
  const milhoes = (ctxTokens ?? 0) / 1_000_000;
  const escrita = ttlMs > 5 * MINUTO ? 2 : 1.25;
  return {
    quente,
    restanteMs,
    custoQuente: semDado ? null : milhoes * preco.entrada * preco.leitura,
    custoFrio: semDado ? null : milhoes * preco.entrada * escrita,
  };
}

// Celulas por fatia pelo maior resto: a barra tem exatamente `larguraTotal` celulas.
export function fatias(lista, larguraTotal) {
  const total = lista.reduce((s, f) => s + f.tokens, 0);
  if (total === 0) return lista.map(() => 0);
  const exato = lista.map((f) => (f.tokens / total) * larguraTotal);
  const celulas = exato.map(Math.floor);
  let sobra = larguraTotal - celulas.reduce((s, n) => s + n, 0);
  const ordem = exato.map((x, i) => ({ i, resto: x - Math.floor(x) })).sort((a, b) => b.resto - a.resto);
  for (const { i } of ordem) {
    if (sobra <= 0) break;
    celulas[i] += 1;
    sobra -= 1;
  }
  return celulas;
}

// Nome de subagente vem do modelo: controles e override bidi nunca chegam crus ao terminal.
export function rotuloSubagente(nome, cols = 24) {
  return cortar(semControle(String(nome ?? '')), cols);
}

const SEPARADOR = '  ';

function barraContexto(pct) {
  const n = 7;
  const pos = Math.min(n - 1, Math.max(0, Math.round((pct / 100) * (n - 1))));
  let b = '';
  for (let i = 0; i < n; i++) b += i === pos ? '●' : i < pos ? '━' : '─';
  return b;
}

// stats: { trabalhando, tokens, custoUsd, ctxPct, ctxTokens, modelo, ttlMs,
//          ultimaRequisicaoMs, agora, deixado, carimbos, subagentes, turnos, erros }
// relogio: linha pronta de `linhaRelogio` (string) ou null.
// Devolve as figuras que cabem em `cols`, na ordem de exibicao: [{ id, texto, largura }].
// Quando aperta, caem da direita; o estado e o relogio ficam por ultimo, o relogio por ultimo.
export function figurasDaBarra(stats, relogio, cols) {
  const s = stats ?? {};
  const agora = s.agora ?? 0;
  const c = cacheDe({
    modelo: s.modelo,
    ctxTokens: s.ctxTokens,
    ultimaRequisicaoMs: s.ultimaRequisicaoMs ?? 0,
    agora,
    ttlMs: s.ttlMs ?? 5 * MINUTO,
  });
  const todas = [
    ['estado', s.trabalhando ? '● trabalhando' : '○ pronto'],
    ['tokens', 'Tokens ' + compacto(s.tokens ?? 0)],
    ['custo', 'Custo ' + dinheiro(s.custoUsd ?? null)],
  ];
  if (typeof s.ctxPct === 'number') todas.push(['contexto', 'Contexto 0 ' + barraContexto(s.ctxPct) + ' 100 ' + Math.round(s.ctxPct) + '%']);
  todas.push([
    'cache',
    c.quente
      ? 'Cache ● quente ' + restante(c.restanteMs) + ' · reenvio ' + dinheiro(c.custoQuente) + ' (' + dinheiro(c.custoFrio) + ' se esfriar)'
      : 'Cache ○ frio · reenvio ' + dinheiro(c.custoFrio),
  ]);
  if ((s.deixado ?? 0) > 0) todas.push(['deixado', 'Deixado ' + s.deixado]);
  todas.push(['ritmo', 'Ferram./min ' + ritmoPorMinuto(s.carimbos, agora)]);
  todas.push(['subagentes', 'Subagentes ' + (s.subagentes ?? 0)]);
  todas.push(['turnos', 'Turnos ' + (s.turnos ?? 0)]);
  todas.push(['erros', 'Erros ' + (s.erros ?? 0)]);
  if (relogio) todas.push(['relogio', relogio]);

  const figuras = todas.map(([id, texto]) => {
    const t = semControle(String(texto));
    return { id, texto: t, largura: largura(t) };
  });
  // Ordem em que as figuras tentam entrar: o relogio primeiro (e o ultimo a cair), o estado
  // depois, o resto na ordem de exibicao. Cada uma entra se couber; a que nao cabe nao
  // impede as seguintes. As demais so entram com o estado ja dentro: estreito demais para os
  // dois prioritarios juntos, sobra o relogio sozinho, nunca uma figura menor no lugar do estado.
  const prioridade = ['relogio', 'estado'];
  const ordemDeEntrada = [...prioridade, ...figuras.map((f) => f.id).filter((id) => !prioridade.includes(id))];
  const mantidas = new Set();
  let usado = 0;
  for (const id of ordemDeEntrada) {
    const f = figuras.find((x) => x.id === id);
    if (!f) continue;
    if (!prioridade.includes(id) && !mantidas.has('estado')) continue;
    const custo = f.largura + (mantidas.size > 0 ? largura(SEPARADOR) : 0);
    if (usado + custo > cols) continue;
    mantidas.add(id);
    usado += custo;
  }
  if (mantidas.size === 0 && figuras.length > 0) {
    const t = cortar(figuras[0].texto, cols);
    return [{ id: figuras[0].id, texto: t, largura: largura(t) }];
  }
  return figuras.filter((f) => mantidas.has(f.id));
}
