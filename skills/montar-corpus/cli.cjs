#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { resolverRaiz } = require('../../hooks/lib/raiz.cjs');
const { ler: lerProjetos, resolverSlug } = require('../../hooks/lib/projetos.cjs');

/**
 * Conferência de dependência externa.
 * Padrão do doutor() do sabia (sabia.py:1282):
 * confere e nomeia o comando que falta, nunca instala.
 */
function conferirDependencias() {
  // Lista vazia por enquanto: o extrator de wiki não usa graphifyy.
  // Quando um preenchedor precisar de dependência externa, entra aqui.

  // Nenhuma dependência obrigatória por enquanto.
  return true;
}

/**
 * Extrai --repo da linha de comando
 */
function extrairRepo(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--repo' && i + 1 < args.length) {
      return args[i + 1];
    }
  }
  return null;
}

/**
 * Extrai --corpus da linha de comando
 */
function extrairCorpus(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--corpus' && i + 1 < args.length) {
      return args[i + 1];
    }
  }
  return null;
}

/**
 * Main - orquestra o pipeline
 */
function main() {
  const args = process.argv.slice(2);
  const repo = extrairRepo(args);
  const corpus = extrairCorpus(args);

  // Sem nenhum dos dois, recusa
  if (!repo && !corpus) {
    console.error('Erro: --repo e/ou --corpus são obrigatórios');
    console.error('Uso: cli.cjs --repo <caminho> --corpus <slug>');
    console.error('     cli.cjs --corpus <slug>  (usa CLAUDE_PROJECT_DIR ou cwd)');
    process.exit(1);
  }

  // Confere dependências externas
  try {
    conferirDependencias();
  } catch (e) {
    console.error(`Erro ao conferir dependências: ${e.message}`);
    process.exit(1);
  }

  // Resolve a raiz de dados
  const resultado = resolverRaiz();
  if (!resultado || !resultado.raiz) {
    console.error('Erro: não foi possível resolver a raiz de dados');
    console.error('Configure RFM_ROOT, <projeto>/.rainforest ou ~/.rainforest');
    process.exit(1);
  }

  const raiz = resultado.raiz;

  // Lê projetos.json
  const mapa = lerProjetos(raiz);
  if (!mapa) {
    console.error(`Erro: projetos.json não encontrado em ${raiz}`);
    process.exit(1);
  }

  // Se corpus não foi passado, recusa
  if (!corpus) {
    console.error('Erro: --corpus é obrigatório');
    process.exit(1);
  }

  // Resolve slug para caminho
  const slug = resolverSlug(corpus, mapa);
  if (!slug) {
    console.error(`Erro: corpus '${corpus}' não encontrado em projetos.json`);
    process.exit(1);
  }

  // Agora que temos o slug, verificamos se o corpus existe
  const caminhoCorpus = mapa[slug].caminho;
  const caminhoWiki = path.join(caminhoCorpus, 'wiki');

  if (!fs.existsSync(caminhoWiki)) {
    console.error(`Erro: ${caminhoWiki} não existe`);
    process.exit(1);
  }

  // Diretório temporário para o grafo intermediário
  const tempDir = path.join(raiz, '.temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const caminhoGrafoTemp = path.join(tempDir, `grafo-${slug}.json`);
  const SRC = path.resolve(__dirname, '..', '..');
  let SRC_WIN = SRC;
  try {
    SRC_WIN = require('child_process').execSync('cygpath -m "' + SRC + '"', { encoding: 'utf8' }).trim();
  } catch {
    SRC_WIN = SRC;
  }

  try {
    // 1. Extrator: wiki → grafo.json
    console.log(`[1/3] Extraindo ${slug}...`);
    const extrator = path.join(SRC_WIN, 'skills', 'montar-corpus', 'extratores', 'wiki.cjs');
    const cmdExtrator = `node "${extrator}" --corpus ${slug}`;
    const grafoJson = execSync(cmdExtrator, {
      cwd: raiz,
      env: { ...process.env, RFM_ROOT: raiz },
      encoding: 'utf8'
    });

    fs.writeFileSync(caminhoGrafoTemp, grafoJson, 'utf8');

    // 2. Validador: confere grafo.json
    console.log(`[2/3] Validando ${slug}...`);
    const validador = path.join(SRC_WIN, 'scripts', 'validar-grafo.cjs');
    const cmdValidador = `node "${validador}" "${caminhoGrafoTemp}"`;
    const validacao = execSync(cmdValidador, {
      cwd: raiz,
      encoding: 'utf8'
    });

    if (!validacao.includes('valido')) {
      console.error(`Erro: grafo de ${slug} não é válido`);
      console.error(validacao);
      process.exit(1);
    }

    // 3. Build: grafo.json → acervo
    console.log(`[3/3] Construindo acervo de ${slug}...`);
    const build = path.join(SRC_WIN, 'skills', 'montar-corpus', 'build.cjs');
    const cmdBuild = `node "${build}" "${caminhoGrafoTemp}" --corpus ${slug}`;
    execSync(cmdBuild, {
      cwd: raiz,
      env: { ...process.env, RFM_ROOT: raiz },
      encoding: 'utf8'
    });

    // Limpa temporário
    if (fs.existsSync(caminhoGrafoTemp)) {
      fs.unlinkSync(caminhoGrafoTemp);
    }

    console.log(`Pronto: acervo de ${slug} em ${raiz}/acervo/${slug}/`);
    process.exit(0);
  } catch (erro) {
    console.error(`Erro durante a execução: ${erro.message}`);
    process.exit(1);
  }
}

main();