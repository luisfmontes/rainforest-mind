'use strict';
/**
 * Nome canônico de projeto (#435; design docs/rainforest/design/2026-10-08-projeto-canonico.md,
 * D1 e D2). Uma função só para quem grava e para quem lê o `projeto` da memória.
 *
 * Módulo folha: usa só stdlib de arquivo (fs, path) e não requer scripts/memoria.cjs.
 * Não executa processo externo: o topo do repositório principal sai lendo o `.git`
 * (arquivo `gitdir:` e `commondir`), como o próprio git faz.
 */
const fs = require('fs');
const path = require('path');

// Regra do harness (scripts/semear.cjs): qualquer caractere fora de [a-zA-Z0-9] vira hífen.
function slugDoCaminho(caminho) {
  return String(caminho).replace(/[^a-zA-Z0-9]/g, '-');
}

// Forma de slug: `<letra>--...` (drive do Windows) ou começa por `-` (caminho Unix).
function ehSlugDeCaminho(valor) {
  return /^(?:[a-zA-Z]--|-)/.test(String(valor));
}

function lerTexto(arquivo) {
  try {
    return fs.readFileSync(arquivo, 'utf8');
  } catch {
    return null;
  }
}

// `.git` de worktree é um arquivo `gitdir: <caminho>`; o `commondir` dentro desse
// diretório aponta para o `.git` do repositório principal.
function topoDoArquivoGit(arquivoGit, pastaDoArquivo) {
  const texto = lerTexto(arquivoGit);
  const m = texto && /^gitdir:\s*(.+?)\s*$/m.exec(texto);
  if (!m) return pastaDoArquivo;
  const gitdir = path.resolve(pastaDoArquivo, m[1]);
  const comum = lerTexto(path.join(gitdir, 'commondir'));
  if (comum === null) return pastaDoArquivo;
  const dirComum = path.resolve(gitdir, comum.trim());
  return path.basename(dirComum) === '.git' ? path.dirname(dirComum) : pastaDoArquivo;
}

// Sobe a partir de `inicio` até achar `.git`. Devolve o topo do repositório principal
// (para worktree, o pai do diretório comum) ou null se nenhum `.git` existir acima.
function topoPrincipal(inicio) {
  let atual = path.resolve(String(inicio));
  for (;;) {
    const marca = path.join(atual, '.git');
    let st = null;
    try {
      st = fs.statSync(marca);
    } catch {
      st = null;
    }
    if (st) return st.isDirectory() ? atual : topoDoArquivoGit(marca, atual);
    const pai = path.dirname(atual);
    if (pai === atual) return null;
    atual = pai;
  }
}

// Canônico = slug do topo principal. Pasta sem `.git` cai no próprio caminho.
function canonicoDoCaminho(caminho) {
  const topo = topoPrincipal(caminho) || path.resolve(String(caminho));
  return { canonico: slugDoCaminho(topo), curto: path.basename(topo), topo };
}

// Nome de pasta de transcritos: `<slug>--claude-worktrees-<nome>` (marca sem diferenciar caixa).
const MARCA_WORKTREE = /^(.*?)--claude-worktrees-(.+)$/i;

function canonicoDaPasta(nome) {
  const m = MARCA_WORKTREE.exec(String(nome));
  if (!m) return { canonico: String(nome), worktree: null };
  return { canonico: m[1], worktree: m[2] };
}

// Casa um nome curto com o sufixo de um canônico, na fronteira de hífen e sem diferenciar caixa.
function casarCurto(curto, canonicos) {
  const alvo = slugDoCaminho(curto).toLowerCase();
  const candidatos = [...new Set(canonicos)].filter((c) => {
    const minusculo = String(c).toLowerCase();
    return minusculo === alvo || minusculo.endsWith(`-${alvo}`);
  });
  if (candidatos.length === 1) return { tipo: 'unico', canonico: candidatos[0], candidatos };
  if (candidatos.length === 0) return { tipo: 'nenhum', canonico: null, candidatos };
  return { tipo: 'ambiguo', canonico: null, candidatos };
}

module.exports = {
  slugDoCaminho,
  ehSlugDeCaminho,
  topoPrincipal,
  canonicoDoCaminho,
  canonicoDaPasta,
  casarCurto,
};
