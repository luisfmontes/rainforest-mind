// Vocabulario de projeto — slug fechado, e o caminho de cada projeto FORA do dado.
//
// Por que existe como lib, e nao dentro do ideias.cjs: desde 2026-08-12 dois
// comandos mexem no mesmo arquivo — o `ideias.cjs projetos` (que nasceu com ele) e
// o `setup.cjs`, porque configuracao de caminho e assunto de setup. Duas
// implementacoes do mesmo esquema divergem em silencio; foi o que aconteceu com as
// duas CLAUDE.md sincronizadas a mao em 2026-08-10, e e o mesmo motivo de a ponte
// para Codex/Gemini ser gerada em vez de escrita.
//
// O DEFEITO QUE O SLUG MATA. O campo `projeto` do ideias.jsonl era texto livre e
// guardava caminho absoluto do Windows dentro de string JSON. Barra invertida
// seguida de `r` e escape de carriage return: `C:\Projetos\rainforest-mind` virou
// `C:\Projetos` + CR + `ainforest-mind` em QUATRO registros. Junto disso, 22
// valores distintos para 7 projetos reais tornavam o campo inagrupavel. Slug
// kebab-case nao tem barra para escape nenhum comer.

const fs = require('fs');
const path = require('path');

const NOME_ARQUIVO = 'projetos.json';
const RE_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

class ErroProjetos extends Error {}

function arquivoDe(raiz) {
  return path.join(raiz, NOME_ARQUIVO);
}

/**
 * Le o vocabulario. Devolve `null` quando o arquivo NAO EXISTE — e quem chama
 * decide o que fazer com a ausencia. Devolver `{}` faria "vocabulario vazio" e
 * "vocabulario inexistente" parecerem a mesma coisa, e o primeiro recusaria todo
 * `plantar` numa instalacao nova.
 */
function ler(raiz) {
  const alvo = arquivoDe(raiz);
  let bruto;
  try {
    bruto = fs.readFileSync(alvo, 'utf8');
  } catch {
    return null;
  }
  let mapa;
  try {
    mapa = JSON.parse(bruto);
  } catch (e) {
    throw new ErroProjetos(`${alvo} nao e JSON valido: ${e.message}`);
  }
  if (typeof mapa !== 'object' || mapa === null || Array.isArray(mapa)) {
    throw new ErroProjetos(`${alvo} precisa ser um objeto {slug: {...}}`);
  }
  for (const [slug, v] of Object.entries(mapa)) {
    if (!RE_SLUG.test(slug)) {
      throw new ErroProjetos(`slug '${slug}' em ${NOME_ARQUIVO} nao e kebab-case`);
    }
    if (typeof v !== 'object' || v === null || Array.isArray(v)) {
      throw new ErroProjetos(`projeto '${slug}' precisa ser um objeto {caminho, apelidos}`);
    }
  }
  return mapa;
}

function gravar(raiz, mapa) {
  const alvo = arquivoDe(raiz);
  const ordenado = {};
  for (const k of Object.keys(mapa).sort()) ordenado[k] = mapa[k];
  fs.mkdirSync(raiz, { recursive: true });
  const tmp = `${alvo}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(ordenado, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, alvo); // atomico, como o jsonl
}

function apelidosDe(mapa, slug) {
  const v = mapa[slug] || {};
  return Array.isArray(v.apelidos) ? v.apelidos.filter((a) => typeof a === 'string' && a) : [];
}

function normalizarProsa(s) {
  return String(s === null || s === undefined ? '' : s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-');
}

function posicaoDoTermo(prosaNorm, termo) {
  // Posicao do termo respeitando fronteira de hifen: `solta` nao casa dentro de
  // `consoltado`. Devolve -1 quando nao ha ocorrencia com fronteira.
  const t = normalizarProsa(termo).replace(/^-|-$/g, '');
  if (!t) return -1;
  let de = 0;
  for (;;) {
    const i = prosaNorm.indexOf(t, de);
    if (i < 0) return -1;
    const antesOk = i === 0 || prosaNorm[i - 1] === '-';
    const fim = i + t.length;
    const depoisOk = fim === prosaNorm.length || prosaNorm[fim] === '-';
    if (antesOk && depoisOk) return i;
    de = i + 1;
  }
}

/**
 * Slug para uma prosa livre. Quem aparece PRIMEIRO na string ganha: o projeto e
 * nomeado no comeco e o resto do texto e detalhe ("rainforest-mind (...); observado
 * em whatsapp-mcp" e uma ideia do rainforest). Empate de posicao entre slugs
 * diferentes e ambiguidade declarada, nao desempate por chute.
 */
function resolverSlug(prosa, mapa) {
  const norm = normalizarProsa(prosa);
  let melhor = null;
  let ambiguo = false;
  for (const slug of Object.keys(mapa)) {
    let pos = -1;
    for (const termo of [slug, ...apelidosDe(mapa, slug)]) {
      const p = posicaoDoTermo(norm, termo);
      if (p >= 0 && (pos < 0 || p < pos)) pos = p;
    }
    if (pos < 0) continue;
    if (melhor === null || pos < melhor.pos) {
      melhor = { slug, pos };
      ambiguo = false;
    } else if (pos === melhor.pos && melhor.slug !== slug) {
      ambiguo = true;
    }
  }
  if (!melhor || ambiguo) return null;
  return melhor.slug;
}

/** CR, LF e TAB dentro do valor sao o rastro do bug: morrem aqui. */
function semControle(s) {
  return String(s === null || s === undefined ? '' : s).replace(/[\r\n\t]+/g, ' ');
}

/**
 * Remove SO o parenteses que e caminho inteiro (`(C:\Projetos\x)`, `(~/y)`,
 * `(/tmp/z)`) — regra estreita de proposito. Prosa raramente comeca com letra +
 * dois-pontos, e apagar por heuristica larga perderia informacao real (branch,
 * porta, fork).
 */
function tirarCaminhos(prosa) {
  return semControle(prosa)
    .replace(/\(\s*(?:[A-Za-z]:|~[\\/]|\/)[^;()]*\)/g, '')
    .replace(/\s{2,}/g, ' ')
    .replace(/\s+([;,])/g, '$1')
    .trim()
    .replace(/^[\s;,\u2014-]+|[\s;,\u2014-]+$/g, '')
    .trim();
}

/** Valor que e SO caminho, sem nome de projeto em volta. */
function soCaminho(s) {
  return /^\s*(?:[A-Za-z]:|~[\\/]|\/)[^;]*$/.test(semControle(s));
}

/**
 * Nota do projeto: existe apenas quando a prosa carrega algo que o slug e o
 * caminho NAO dizem (branch, porta, fork, "observado em outro repo").
 */
function notaDeProjeto(prosa, slug, mapa) {
  if (soCaminho(prosa)) return null;
  const limpa = tirarCaminhos(prosa);
  let resto = normalizarProsa(limpa);
  for (const termo of [slug, ...apelidosDe(mapa, slug)]) {
    const t = normalizarProsa(termo).replace(/^-|-$/g, '');
    if (t) resto = resto.split(t).join('-');
  }
  const sobrou = resto.replace(/-+/g, '');
  if (sobrou.length < 3) return null;
  return limpa || null;
}

/**
 * Registra ou atualiza um slug. Devolve o que foi gravado e os AVISOS — hoje um
 * so, e ele nasceu de um erro meu: em 2026-08-12 registrei `protheus-aiba` com
 * caminho `...\protheus-totvs-agro\AIBA` deduzido do NOME que aparecia na prosa,
 * e a pasta nao existia. Caminho que nao existe nunca casa com a pasta de uma
 * sessao, entao o `semear` simplesmente nao traria nada — falha silenciosa. Aviso e
 * nao recusa: registrar projeto de outra maquina e caso legitimo.
 */
function registrar(raiz, slug, { caminho, apelido } = {}) {
  if (!RE_SLUG.test(slug)) {
    throw new ErroProjetos(
      `slug '${slug}' nao e kebab-case ([a-z0-9] separado por hifen). O slug e fechado ` +
        'justamente para nao caber barra nem espaco — foi barra dentro de string JSON ' +
        'que corrompeu 4 registros.'
    );
  }
  const mapa = ler(raiz) || {};
  const novo = !Object.prototype.hasOwnProperty.call(mapa, slug);
  const atual = mapa[slug] || {};
  const apelidos = new Set(apelidosDe(mapa, slug));
  if (apelido) {
    for (const a of String(apelido).split(',').map((x) => x.trim()).filter(Boolean)) apelidos.add(a);
  }
  const caminhoFinal = caminho !== undefined && caminho !== null ? caminho : (atual.caminho || null);
  mapa[slug] = { caminho: caminhoFinal, apelidos: [...apelidos].sort() };
  gravar(raiz, mapa);

  const avisos = [];
  if (caminhoFinal && !existe(caminhoFinal)) {
    avisos.push(
      `o caminho '${caminhoFinal}' nao existe nesta maquina — se for engano, o semear ` +
        'nunca vai casar a pasta com este slug, e o erro e silencioso'
    );
  }
  return { slug, novo, entrada: mapa[slug], avisos, mapa };
}

function existe(p) {
  try {
    fs.statSync(p);
    return true;
  } catch {
    return false;
  }
}

/**
 * Remove um slug. `emUso` e a lista de ids que ainda apontam para ele: a remocao
 * so acontece com a lista vazia, porque vocabulario que perde slug em uso deixa o
 * dado orfao sem ninguem notar.
 */
function remover(raiz, slug, emUso = []) {
  const mapa = ler(raiz);
  if (mapa === null) throw new ErroProjetos(`${arquivoDe(raiz)} nao existe — nada a remover`);
  if (!Object.prototype.hasOwnProperty.call(mapa, slug)) {
    throw new ErroProjetos(
      `'${slug}' nao esta no vocabulario — registrados: ` +
        `${Object.keys(mapa).sort().join(', ') || '(nenhum)'}`
    );
  }
  if (emUso.length) {
    throw new ErroProjetos(
      `'${slug}' ainda e o projeto de ${emUso.length} linha(s): ` +
        `${emUso.slice(0, 5).join(', ')}${emUso.length > 5 ? ', ...' : ''}\n` +
        '  mova primeiro: node scripts/ideias.cjs editar --id <id> (campo projeto)'
    );
  }
  delete mapa[slug];
  gravar(raiz, mapa);
  return { slug, mapa };
}

/** Semente de instalacao nova: `solta` mais o slug da pasta atual. */
function slugificar(nome) {
  return String(nome || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

module.exports = {
  NOME_ARQUIVO,
  RE_SLUG,
  ErroProjetos,
  arquivoDe,
  ler,
  gravar,
  apelidosDe,
  normalizarProsa,
  posicaoDoTermo,
  resolverSlug,
  semControle,
  tirarCaminhos,
  soCaminho,
  notaDeProjeto,
  registrar,
  remover,
  existe,
  slugificar,
};
