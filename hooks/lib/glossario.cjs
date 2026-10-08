/**
 * Biblioteca do GLOSSARIO.md: lê os verbetes do arquivo do repo, casa os termos
 * no pedido e monta o bloco que os hooks injetam.
 *
 * Formato dos verbetes (D7 do design 2026-10-08-glossario-compartilhado):
 *   ## <termo>
 *   Definição: uma a duas frases.
 *   Onde mora: arquivo, rotina, tabela ou campo.
 *   Cenário: um caso real, concreto.
 *   Evite: sinônimo errado; outro sinônimo errado
 *
 * Sem banco e sem efeito colateral de escrita: o glossário é arquivo do repo.
 */

const fs = require('fs');
const path = require('path');

const CABECALHO = '## Glossário do repo';
const VERBETES_MAX = 3;
const TETO_BYTES_GLOSSARIO = 1800;
const BYTES_MAX_VERBETE = 900;

const ANTES = '(^|[^\\p{L}\\p{N}])';

const CAMPOS = new Map([
  ['definicao', 'definicao'],
  ['onde mora', 'ondeMora'],
  ['cenario', 'cenario'],
  ['evite', 'evite'],
]);

const PLACEHOLDERS = ['', 'tbd', 'a definir', 'n/a', '-', '...'];

function normalizar(s) {
  return String(s)
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function escaparRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function padraoTermo(termo) {
  const palavras = normalizar(termo).split(' ').map(escaparRegex).join(' ');
  return new RegExp(ANTES + palavras + 's?(?=[^\\p{L}\\p{N}]|$)', 'u');
}

function juntar(linhas) {
  return linhas
    .map(l => l.trim())
    .filter(l => l.length > 0)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Chave de deduplicação: sem acento, sem caixa, sem um `s` final. */
function chaveDe(termo) {
  const n = normalizar(termo);
  return n.length > 1 && n.endsWith('s') ? n.slice(0, -1) : n;
}

/**
 * Lê o texto de um GLOSSARIO.md e devolve todos os verbetes, válidos ou não.
 * Cabeçalho `## ` (fora de cerca de código) abre verbete; rótulo `Campo: texto`
 * no começo da linha abre campo; o resto é continuação do campo atual.
 */
function lerVerbetes(texto) {
  if (typeof texto !== 'string') {
    return [];
  }
  const linhas = texto.replace(/\r\n?/g, '\n').split('\n');
  const verbetes = [];
  let atual = null;
  let campo = null;
  let cerca = null;

  for (const linha of linhas) {
    if (cerca) {
      if (linha.startsWith(cerca)) {
        cerca = null;
      }
      continue;
    }
    const abre = /^(`{3}|~{3})/.exec(linha);
    if (abre) {
      cerca = abre[1];
      continue;
    }
    const cab = /^##(?!#)\s+(.+?)\s*$/.exec(linha);
    if (cab) {
      atual = {
        termo: cab[1].trim(),
        campos: { definicao: [], ondeMora: [], cenario: [], evite: [] },
      };
      campo = null;
      verbetes.push(atual);
      continue;
    }
    if (!atual) {
      continue;
    }
    const rot = /^([^\s:][^:]*):(.*)$/.exec(linha);
    const chave = rot ? CAMPOS.get(normalizar(rot[1])) : undefined;
    if (chave) {
      campo = chave;
      atual.campos[chave].push(rot[2]);
    } else if (campo) {
      atual.campos[campo].push(linha);
    }
  }

  return verbetes.map(v => ({
    termo: v.termo,
    definicao: juntar(v.campos.definicao),
    ondeMora: juntar(v.campos.ondeMora),
    cenario: juntar(v.campos.cenario),
    evite: juntar(v.campos.evite)
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0),
  }));
}

function placeholder(valor) {
  return PLACEHOLDERS.includes(normalizar(valor || ''));
}

/** Válido = termo, Definição, Onde mora e Cenário preenchidos e não-placeholder. */
function verbeteValido(v) {
  if (!v || typeof v !== 'object') {
    return false;
  }
  if (normalizar(v.termo || '') === '') {
    return false;
  }
  return [v.definicao, v.ondeMora, v.cenario].every(c => !placeholder(c));
}

/**
 * Sobe de `cwd` até o primeiro diretório com `.git` (pasta ou arquivo, para
 * valer em worktree) e devolve o caminho do GLOSSARIO.md dali, ou null.
 */
function acharGlossario(cwd) {
  let dir = path.resolve(String(cwd || ''));
  for (;;) {
    if (fs.existsSync(path.join(dir, '.git'))) {
      const arq = path.join(dir, 'GLOSSARIO.md');
      return fs.existsSync(arq) ? arq : null;
    }
    const pai = path.dirname(dir);
    if (pai === dir) {
      return null;
    }
    dir = pai;
  }
}

/**
 * Devolve os verbetes válidos cujo termo, ou um item do Evite, aparece no
 * pedido — sem acento, sem caixa, com fronteira de palavra e um `s` final —,
 * na ordem da primeira aparição.
 */
function casarVerbetes(verbetes, texto) {
  if (!Array.isArray(verbetes) || typeof texto !== 'string') {
    return [];
  }
  const alvo = normalizar(texto);
  const achados = [];
  for (const v of verbetes) {
    if (!verbeteValido(v)) {
      continue;
    }
    let primeira = Infinity;
    for (const termo of [v.termo, ...(v.evite || [])]) {
      if (normalizar(termo) === '') {
        continue;
      }
      const m = padraoTermo(termo).exec(alvo);
      if (m) {
        primeira = Math.min(primeira, m.index + (m[1] || '').length);
      }
    }
    if (primeira !== Infinity) {
      achados.push({ v, primeira });
    }
  }
  achados.sort((a, b) => a.primeira - b.primeira);
  return achados.map(a => a.v);
}

/**
 * Monta o bloco injetado: cabeçalho, no máximo VERBETES_MAX linhas, no máximo
 * TETO_BYTES_GLOSSARIO bytes. Verbete cuja linha passa de BYTES_MAX_VERBETE
 * nunca entra. Devolve '' quando nada entra.
 */
function montarBlocoGlossario(verbetes) {
  if (!Array.isArray(verbetes)) {
    return '';
  }
  const linhas = [];
  for (const v of verbetes) {
    if (linhas.length >= VERBETES_MAX) {
      break;
    }
    if (!verbeteValido(v)) {
      continue;
    }
    let linha = `- **${v.termo}**: ${v.definicao} | onde mora: ${v.ondeMora} | cenário: ${v.cenario}`;
    if (v.evite && v.evite.length > 0) {
      linha += ` | evite: ${v.evite.join('; ')}`;
    }
    if (Buffer.byteLength(linha, 'utf8') > BYTES_MAX_VERBETE) {
      continue;
    }
    linhas.push(linha);
  }
  while (linhas.length > 0 &&
         Buffer.byteLength([CABECALHO, ...linhas].join('\n'), 'utf8') > TETO_BYTES_GLOSSARIO) {
    linhas.pop();
  }
  return linhas.length > 0 ? [CABECALHO, ...linhas].join('\n') : '';
}

module.exports = {
  lerVerbetes,
  verbeteValido,
  acharGlossario,
  casarVerbetes,
  montarBlocoGlossario,
  chaveDe,
  CABECALHO,
  VERBETES_MAX,
  TETO_BYTES_GLOSSARIO,
  BYTES_MAX_VERBETE,
};
