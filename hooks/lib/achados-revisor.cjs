'use strict';

/**
 * achados-revisor.cjs — conta os achados marcados de um relato do revisor.
 *
 * Um achado é o item que ABRE com a severidade entre colchetes: `[alta]`,
 * `[media]` (aceita `[média]`) ou `[baixa]`. `[design]` pode vir antes ou
 * depois dela, e sozinho conta só para `design` (contesta D<n>), não para o
 * total. "Abrir" é a posição em que `scripts/critica-do-revisor.cjs` já
 * reconhecia o `[design]`: marcador (`-`, `*`, `>`), título (`#`), número ou
 * rótulo (`A1.`, `Achado 1:`), negrito. Citado no meio da frase, não abre.
 *
 * Usado por `hooks/veredito-revisor.cjs` (coerência veredito x achados) e por
 * `scripts/critica-do-revisor.cjs` (exit 3 e exit 4).
 *
 * Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-2.md, D3 e D8.
 * D8: a régua é o formato, não o juízo — severidade errada dentro do formato
 * não é detectada aqui.
 */

const ABERTURA = /^\s*(?:[-*>]\s+|#{1,6}\s+)?(?:\*\*)?(?:(?:[A-Z]|Achado\s+)?\d+[.):]?\s*)?(?:\*\*)?\s*((?:(?:\*\*)?\[(?:alta|m[eé]dia|media|baixa|design)\](?:\*\*)?\s*)+)/i;
const SEVERIDADE = /\[(alta|m[eé]dia|media|baixa)\]/i;
const DESIGN = /\[design\]/i;

/**
 * @param {string} texto relato do revisor, sem a linha VEREDITO: (ou com ela; não importa)
 * @returns {{alta:number, media:number, baixa:number, design:number, total:number}}
 *   total = itens que abrem com severidade OU com [design] (um item só de
 *   [design] conta no total: D3 do lote 2, decisão de 2026-10-24).
 */
function contarAchados(texto) {
  const c = { alta: 0, media: 0, baixa: 0, design: 0, total: 0 };
  if (typeof texto !== 'string') return c;
  for (const linha of texto.split(/\r?\n/)) {
    const m = ABERTURA.exec(linha);
    if (!m) continue;
    const tags = m[1];
    const design = DESIGN.test(tags);
    const sev = SEVERIDADE.exec(tags);
    if (design) c.design += 1;
    if (!sev && !design) continue;
    if (sev) {
      const chave = /alta/i.test(sev[1]) ? 'alta' : /baixa/i.test(sev[1]) ? 'baixa' : 'media';
      c[chave] += 1;
    }
    c.total += 1;
  }
  return c;
}

/**
 * Regras de coerência veredito x achados (D3). Usada pelo hook
 * `hooks/veredito-revisor.cjs` e por `scripts/estado.cjs` (transcritoConfirmaVeredito),
 * para que as duas leituras da mesma mensagem concordem.
 * @returns {string|null} motivo legível da regra que disparou, ou null se coerente.
 */
function incoerencia(veredito, a) {
  const contagem = `contagem: alta ${a.alta}, media ${a.media}, baixa ${a.baixa}, design ${a.design}`;
  if (veredito === 'ok' && a.alta > 0) return `regra "ok com achado [alta]" (${contagem})`;
  if (veredito === 'reprovado' && a.total === 0) return `regra "reprovado sem achado marcado" (${contagem})`;
  return null;
}

module.exports = { contarAchados, incoerencia };
