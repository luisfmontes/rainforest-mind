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
 * `[preexistente]` (lote 6, D3) acompanha a severidade na abertura e marca
 * defeito que já estava na base do diff. Quem tem a marca NÃO bloqueia (não
 * entra em alta/media/baixa/total), salvo quando `preexistentesNoDiff` acha a
 * linha citada num trecho adicionado ou alterado pelo diff: aí a marca é
 * recusada e `tirarMarcaPreexistente` a tira antes de contar.
 *
 * Usado por `hooks/veredito-revisor.cjs` (coerência veredito x achados) e por
 * `scripts/critica-do-revisor.cjs` (exit 3 e exit 4).
 *
 * Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-2.md, D3 e D8;
 * docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md, D3 e D9.
 * D8 (lote 2): a régua é o formato, não o juízo — severidade errada dentro do
 * formato não é detectada aqui.
 */

const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'resolver-executavel.cjs'));

const ABERTURA = /^\s*(?:[-*>]\s+|#{1,6}\s+)?(?:\*\*)?(?:(?:[A-Z]|Achado\s+)?\d+[.):]?\s*)?(?:\*\*)?\s*((?:(?:\*\*)?\[(?:alta|m[eé]dia|media|baixa|design|preexistente)\](?:\*\*)?\s*)+)/i;
const SEVERIDADE = /\[(alta|m[eé]dia|media|baixa)\]/i;
const DESIGN = /\[design\]/i;
const PREEXISTENTE = /\[preexistente\]/i;
const CAMINHO_LINHA = /([\w.\/-]+\.\w+):(\d+)/;

/**
 * @param {string} texto relato do revisor, sem a linha VEREDITO: (ou com ela; não importa)
 * @returns {{alta:number, media:number, baixa:number, design:number, total:number, preexistente:number}}
 *   total = itens que abrem com severidade OU com [design] e NÃO têm a marca
 *   [preexistente] (D3 do lote 6). preexistente = linhas de abertura com a marca.
 */
function contarAchados(texto) {
  const c = { alta: 0, media: 0, baixa: 0, design: 0, total: 0, preexistente: 0 };
  if (typeof texto !== 'string') return c;
  for (const linha of texto.split(/\r?\n/)) {
    const m = ABERTURA.exec(linha);
    if (!m) continue;
    const tags = m[1];
    const design = DESIGN.test(tags);
    const sev = SEVERIDADE.exec(tags);
    const bloqueia = !PREEXISTENTE.test(tags);
    if (!bloqueia) c.preexistente += 1;
    if (design) c.design += 1;
    if (!sev && !design) continue;
    if (!bloqueia) continue;
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

/**
 * Itens do relato (mesma régua de `contarAchados`), com o índice da linha no
 * texto. `arquivo`/`linha` vêm do primeiro `caminho:linha` da linha de abertura.
 * @returns {Array<{indice:number, sev:'alta'|'media'|'baixa'|'design', arquivo:string|null, linha:number|null, preexistente:boolean}>}
 */
function itensAchados(texto) {
  const itens = [];
  if (typeof texto !== 'string') return itens;
  texto.split(/\r?\n/).forEach((linha, indice) => {
    const m = ABERTURA.exec(linha);
    if (!m) return;
    const tags = m[1];
    const sev = SEVERIDADE.exec(tags);
    if (!sev && !DESIGN.test(tags)) return;
    const chave = !sev ? 'design' : /alta/i.test(sev[1]) ? 'alta' : /baixa/i.test(sev[1]) ? 'baixa' : 'media';
    const cam = CAMINHO_LINHA.exec(linha);
    itens.push({
      indice,
      sev: chave,
      arquivo: cam ? cam[1] : null,
      linha: cam ? Number(cam[2]) : null,
      preexistente: PREEXISTENTE.test(tags),
    });
  });
  return itens;
}

/**
 * D4 (lote 5): lista os achados (mesma régua de `contarAchados`) com a
 * severidade, o primeiro `caminho:linha` do item e a marca `preexistente`.
 * `sev` é 'design' só quando o item não tem severidade; `arquivo` é null quando o
 * item não cita `caminho:linha` na própria linha de abertura.
 * @returns {Array<{sev:'alta'|'media'|'baixa'|'design', arquivo:string|null, preexistente:boolean}>}
 */
function listarAchados(texto) {
  return itensAchados(texto).map(({ sev, arquivo, preexistente }) => ({ sev, arquivo, preexistente }));
}

/**
 * Linhas novas de cada arquivo em `<base>..HEAD` (`git diff -U0`). Mapa
 * caminho -> Set de números de linha adicionados ou alterados; null se o git falhar.
 */
function linhasAdicionadas(cwd, base) {
  const r = spawnSync(caminhoExecutavel('git'), ['-c', 'core.quotepath=off', 'diff', '-U0', `${base}..HEAD`], {
    cwd, encoding: 'utf8', stdio: 'pipe', maxBuffer: 64 * 1024 * 1024,
  });
  if (r.status !== 0 || typeof r.stdout !== 'string') return null;
  const mapa = new Map();
  let arquivo = null;
  let cabecalho = false;
  for (const linha of r.stdout.split('\n')) {
    if (linha.startsWith('diff --git ')) { cabecalho = true; arquivo = null; continue; }
    if (cabecalho && linha.startsWith('+++ ')) {
      arquivo = linha === '+++ /dev/null' ? null : caminhoDoCabecalho(linha);
      if (arquivo && !mapa.has(arquivo)) mapa.set(arquivo, new Set());
      continue;
    }
    const h = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/.exec(linha);
    if (!h) continue;
    cabecalho = false;
    if (!arquivo) continue;
    const ini = Number(h[1]);
    const n = h[2] === undefined ? 1 : Number(h[2]);
    for (let i = 0; i < n; i += 1) mapa.get(arquivo).add(ini + i);
  }
  return mapa;
}

/**
 * Caminho do cabeçalho `+++ b/<caminho>`. Com espaço no nome o git acrescenta
 * uma tabulação no fim; com aspas ou caractere de controle, cita o caminho entre
 * aspas com escape em C (acento passa cru pelo `core.quotepath=off`).
 */
function caminhoDoCabecalho(linha) {
  let c = linha.replace(/\r$/, '').slice(4).replace(/\t$/, '');
  if (c.startsWith('"') && c.endsWith('"')) c = c.slice(1, -1).replace(/\\(["\\])/g, '$1');
  return c.replace(/^b\//, '');
}

/** Base da entrega: merge-base(HEAD, origin/<padrão>). null se não resolver. */
function baseDoDiff(cwd) {
  const git = caminhoExecutavel('git');
  const opts = { cwd, encoding: 'utf8', stdio: 'pipe' };
  const sym = spawnSync(git, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], opts);
  const padrao = sym.status === 0 && sym.stdout.trim() ? sym.stdout.trim().replace(/^origin\//, '') : 'main';
  const mb = spawnSync(git, ['merge-base', 'HEAD', `origin/${padrao}`], opts);
  if (mb.status !== 0) return null;
  return mb.stdout.trim() || null;
}

/**
 * D3/D9 (lote 6): os achados `[preexistente]` cujo `arquivo:linha` cai numa linha
 * adicionada ou alterada por `git diff -U0 <base>..HEAD` — marca recusada.
 * Sem marca no texto, devolve [] sem tocar no git. Com marca e sem base
 * resolvível (sem remoto, erro de git, `cwd` ausente), devolve null: a marca
 * vale como escrita e quem chama avisa "não conferida". A citação se procura
 * pelos caminhos do próprio diff (`<caminho>:<n>` na linha de abertura, com `\`
 * ou `/`), o que pega caminho com espaço e acento; sem casar nenhum, vale o
 * primeiro `caminho:linha` da abertura. Item com marca sem `arquivo:linha` não
 * se confere por máquina e é recusado (revisão do lote 6). `motivo` é o que
 * quem chama imprime depois de "marca [preexistente] recusada: ".
 * @returns {Array<{indice:number, sev:string, arquivo:string|null, linha:number|null, preexistente:boolean, motivo:string}>|null}
 */
function preexistentesNoDiff(texto, cwd) {
  const marcados = itensAchados(texto).filter((x) => x.preexistente);
  if (marcados.length === 0) return [];
  if (typeof cwd !== 'string' || !cwd) return null;
  const base = baseDoDiff(cwd);
  if (!base) return null;
  const adicionadas = linhasAdicionadas(cwd, base);
  if (!adicionadas) return null;
  const linhas = texto.split(/\r?\n/);
  const recusadas = [];
  for (const x of marcados) {
    const abertura = linhas[x.indice].replace(/\\/g, '/');
    let arquivo = null;
    let linha = null;
    for (const caminho of adicionadas.keys()) {
      if (arquivo && caminho.length <= arquivo.length) continue;
      // o caminho começa num limite: `xa.cjs:3` não é citação de `a.cjs`
      for (let i = abertura.indexOf(`${caminho}:`); i >= 0; i = abertura.indexOf(`${caminho}:`, i + 1)) {
        const n = /^\d+/.exec(abertura.slice(i + caminho.length + 1));
        if (n && (i === 0 || !/[\w.-]/.test(abertura[i - 1]))) { arquivo = caminho; linha = Number(n[0]); break; }
      }
    }
    if (!arquivo && x.arquivo && x.linha !== null) {
      arquivo = x.arquivo.replace(/\\/g, '/').replace(/^\.\//, '');
      linha = x.linha;
    }
    if (!arquivo) {
      recusadas.push({ ...x, motivo: 'sem arquivo:linha para conferir' });
    } else if (adicionadas.has(arquivo) && adicionadas.get(arquivo).has(linha)) {
      recusadas.push({ ...x, arquivo, linha, motivo: `${arquivo}:${linha} está no diff` });
    }
  }
  return recusadas;
}

/** Tira a marca `[preexistente]` das linhas indicadas (itens com `indice`). */
function tirarMarcaPreexistente(texto, itens) {
  if (typeof texto !== 'string' || !itens || itens.length === 0) return texto;
  const alvo = new Set(itens.map((x) => x.indice));
  return texto.split(/\r?\n/).map((l, i) => (alvo.has(i) ? l.replace(PREEXISTENTE, '') : l)).join('\n');
}

/**
 * Fim (exclusivo) do item que abre em `linhas[indice]`: a abertura e as linhas
 * seguintes não vazias, até linha em branco, título (`#`) ou nova abertura.
 */
function fimDoItem(linhas, indice) {
  let fim = indice + 1;
  while (fim < linhas.length && linhas[fim].trim() !== '' && !/^\s*#{1,6}\s/.test(linhas[fim]) && !ABERTURA.test(linhas[fim])) {
    fim += 1;
  }
  return fim;
}

module.exports = {
  contarAchados, incoerencia, listarAchados, itensAchados,
  preexistentesNoDiff, tirarMarcaPreexistente, fimDoItem,
};
