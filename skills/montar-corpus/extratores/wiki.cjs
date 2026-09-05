#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('../../../hooks/lib/raiz.cjs');
const { ler: lerProjetos, resolverSlug } = require('../../../hooks/lib/projetos.cjs');

function parseYAML(conteudo) {
  // Extrai frontmatter YAML entre --- no início do arquivo
  const match = conteudo.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};

  const yaml = match[1];
  const obj = {};

  // Parser simples de YAML para os campos que nos interessam
  const linhas = yaml.split('\n');
  for (const linha of linhas) {
    const match2 = linha.match(/^([a-z]+):\s*(.*)$/i);
    if (!match2) continue;
    const [, chave, valor] = match2;

    if (chave === 'titulo') {
      obj.titulo = valor.replace(/^["']|["']$/g, '').trim();
    } else if (chave === 'relacionados') {
      // Formato: relacionados: ["[[page1]]", "[[page2]]"]
      try {
        const arr = JSON.parse(valor);
        obj.relacionados = Array.isArray(arr) ? arr : [];
      } catch {
        obj.relacionados = [];
      }
    }
  }

  return obj;
}

function extrairTituloH1(conteudo) {
  // Extrai primeira linha de H1: # Titulo
  const match = conteudo.match(/^#\s+(.+?)(?:\r?\n|$)/);
  return match ? match[1].trim() : '';
}

function extrairLinks(conteudo) {
  // Extrai todos os [[...]] do corpo (fora do frontmatter)
  const semFrontmatter = conteudo.replace(/^---[\s\S]*?---/, '');
  const regex = /\[\[([^\[\]]+)\]\]/g;
  const links = [];
  let match;
  while ((match = regex.exec(semFrontmatter)) !== null) {
    links.push(match[1]);
  }
  return links;
}

function normalizarLink(link) {
  // Converte "page name" para "page-name.md"
  return link
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '');
}

function main() {
  // Parse argumentos
  let corpus = null;
  for (let i = 2; i < process.argv.length; i++) {
    if (process.argv[i] === '--corpus' && i + 1 < process.argv.length) {
      corpus = process.argv[i + 1];
      i++;
    }
  }

  if (!corpus) {
    console.error('erro: --corpus e obrigatorio');
    process.exit(1);
  }

  // Resolve raiz
  const { raiz } = resolverRaiz();
  if (!raiz) {
    console.error('erro: raiz de dados nao encontrada');
    process.exit(1);
  }

  // Lê projetos.json
  const mapa = lerProjetos(raiz);
  if (!mapa) {
    console.error('erro: projetos.json nao encontrado em', raiz);
    process.exit(1);
  }

  // Resolve slug para caminho
  const slug = resolverSlug(corpus, mapa);
  if (!slug) {
    console.error(`erro: corpus '${corpus}' nao encontrado em projetos.json`);
    process.exit(1);
  }

  const caminhoCorpus = mapa[slug].caminho;
  const caminhoWiki = path.join(caminhoCorpus, 'wiki');

  if (!fs.existsSync(caminhoWiki)) {
    console.error(`erro: ${caminhoWiki} nao existe`);
    process.exit(1);
  }

  // Lê todos os .md da wiki
  const arquivos = fs.readdirSync(caminhoWiki).filter(f => f.endsWith('.md'));

  // Coleta nós
  const nos = [];
  const mapa_ids = {}; // id -> arquivo

  for (const arquivo of arquivos) {
    const caminho_completo = path.join(caminhoWiki, arquivo);
    const conteudo = fs.readFileSync(caminho_completo, 'utf8');

    const frontmatter = parseYAML(conteudo);
    const titulo = frontmatter.titulo || extrairTituloH1(conteudo) || arquivo.replace('.md', '');

    const id = arquivo.replace('.md', '');
    mapa_ids[id] = arquivo;

    const no = {
      id,
      caminho: path.join('wiki', arquivo),
      titulo,
      resumo: titulo, // Por simplicidade, usar titulo como resumo
      file_type: 'concept',
      confidence: 'EXTRACTED'
    };

    nos.push(no);
  }

  // Coleta arestas
  const arestas = [];
  const arestas_set = new Set(); // Para evitar duplicatas

  for (const arquivo of arquivos) {
    const caminho_completo = path.join(caminhoWiki, arquivo);
    const conteudo = fs.readFileSync(caminho_completo, 'utf8');
    const id_de = arquivo.replace('.md', '');

    const frontmatter = parseYAML(conteudo);
    const links = extrairLinks(conteudo);

    // Processa relacionados do frontmatter
    if (frontmatter.relacionados) {
      for (const rel of frontmatter.relacionados) {
        const match = rel.match(/\[\[([^\[\]]+)\]\]/);
        if (match) {
          links.push(match[1]);
        }
      }
    }

    // Deduplica links
    const links_unicos = [...new Set(links)];

    for (const link of links_unicos) {
      const id_para = normalizarLink(link);

      // Checa se a página existe
      const page_existe = mapa_ids.hasOwnProperty(id_para);
      const confidence = page_existe ? 'EXTRACTED' : 'AMBIGUOUS';

      // Evita duplicatas
      const chave = `${id_de}|${id_para}`;
      if (arestas_set.has(chave)) continue;
      arestas_set.add(chave);

      const aresta = {
        de: id_de,
        para: id_para,
        tipo: 'relacionado',
        via: 'markdown-link',
        confidence // Campo não obrigatório mas útil
      };

      arestas.push(aresta);
    }
  }

  // Emite JSON
  const grafo = { nos, arestas };
  console.log(JSON.stringify(grafo, null, 2));
}

main();
