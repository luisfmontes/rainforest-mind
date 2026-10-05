#!/usr/bin/env node
// @categoria: guia
// Dados da faixa de foco: o foco declarado e os fluxos em curso de TODOS os worktrees.
// Somente leitura. Saida: JSON em uma linha. Contrato em
// docs/rainforest/planos/2026-10-03-mod-faixa-foco.md ("Contrato dos dados").
//
// Uso: node scripts/faixa-dados.cjs --cwd <dir>
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const { proximo } = require('./estado.cjs');
const { tituloDoFocoAtivo } = require('../hooks/lib/contexto-sessao.cjs');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

const PLUGIN = path.resolve(__dirname, '..');
const ORDEM = ['design', 'plano', 'executar', 'revisar', 'verificar', 'fechar', 'completo'];
// Caminho de worktree criado pelo harness para subagente (isolation: worktree).
const WORKTREE_DE_AGENTE = /[\\/]\.claude[\\/]worktrees[\\/]agent-[^\\/]*[\\/]?$/;

function valorDe(nome) {
  const i = process.argv.indexOf(nome);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

// `git -C` num diretorio que nao e repo sobe para o pai em silencio; por isso
// spawnSync com cwd e conferencia de status. Falhou: so o proprio cwd.
function worktrees(cwd) {
  const r = spawnSync(caminhoExecutavel('git'), ['worktree', 'list', '--porcelain'], { cwd, encoding: 'utf8' });
  if (r.error || r.status !== 0) return [cwd];
  const dirs = String(r.stdout)
    .split(/\r?\n/)
    .filter((l) => l.startsWith('worktree '))
    .map((l) => l.slice('worktree '.length));
  return dirs.length ? dirs : [cwd];
}

function numero(v) {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function emVooDe(estado, etapa) {
  const bloco = estado[etapa];
  return bloco && typeof bloco === 'object' && Array.isArray(bloco.em_voo)
    ? bloco.em_voo.filter((a) => a && typeof a === 'object' && a.agente).map((a) => a.agente)
    : [];
}

function lerFluxos(cwd) {
  const melhores = new Map();
  for (const wt of worktrees(cwd)) {
    const dir = path.join(wt, 'docs', 'rainforest', 'estado');
    let nomes;
    try {
      nomes = fs.readdirSync(dir).filter((n) => n.endsWith('.json'));
    } catch {
      continue;
    }
    for (const nome of nomes) {
      const arquivo = path.join(dir, nome);
      let estado;
      let mtime;
      try {
        estado = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
        mtime = fs.statSync(arquivo).mtimeMs;
        if (!estado || typeof estado !== 'object' || Array.isArray(estado)) throw new Error('nao e um objeto');
      } catch (e) {
        process.stderr.write(`faixa-dados: estado ilegivel ignorado: ${arquivo} (${e.message})\n`);
        continue;
      }
      const slug = typeof estado.slug === 'string' && estado.slug ? estado.slug : nome.replace(/\.json$/, '');
      const etapa = proximo(estado);
      const indice = ORDEM.indexOf(etapa === null ? 'completo' : etapa);
      // Worktree de subagente (.claude/worktrees/agent-*) carrega copia do estado do
      // despacho: so vence quando nao ha outra copia. Entre as demais, a mais avancada.
      const agente = WORKTREE_DE_AGENTE.test(wt);
      const atual = melhores.get(slug);
      const vence = !atual
        || (atual.agente && !agente)
        || (atual.agente === agente && (indice > atual.indice || (indice === atual.indice && mtime > atual.mtime)));
      if (vence) {
        melhores.set(slug, { slug, estado, etapa, indice, mtime, worktree: wt, agente });
      }
    }
  }
  const fluxos = [];
  for (const { slug, estado, etapa, worktree } of melhores.values()) {
    if (etapa === null) continue;
    const exec = estado.executar && typeof estado.executar === 'object' ? estado.executar : {};
    fluxos.push({
      slug,
      titulo: typeof estado.titulo === 'string' && estado.titulo ? estado.titulo : slug,
      etapa,
      tarefas_ok: numero(exec.tarefas_ok),
      tarefas: numero(exec.tarefas),
      em_voo: emVooDe(estado, etapa),
      criado_em: typeof estado.criado_em === 'string' ? estado.criado_em : '',
      worktree,
    });
  }
  fluxos.sort((a, b) => (a.criado_em !== b.criado_em ? (a.criado_em < b.criado_em ? 1 : -1) : a.slug < b.slug ? 1 : a.slug > b.slug ? -1 : 0));
  return fluxos;
}

function lerFoco(cwd) {
  const { raiz } = resolverRaiz({ cwd, plugin: PLUGIN });
  if (!raiz) return null;
  let texto;
  try {
    texto = fs.readFileSync(path.join(raiz, 'FOCO.md'), 'utf8');
  } catch {
    return null;
  }
  return tituloDoFocoAtivo(texto) || null;
}

function main() {
  const cwd = path.resolve(valorDe('--cwd') || process.cwd());
  process.stdout.write(`${JSON.stringify({ foco: lerFoco(cwd), fluxos: lerFluxos(cwd) })}\n`);
}

main();
