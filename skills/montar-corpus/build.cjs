#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('../../hooks/lib/raiz.cjs');

/**
 * Extrai --corpus <nome> dos argumentos
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
 * Valida se corpus foi fornecido e não contém path traversal
 */
function validarCorpus(corpus, raiz) {
  if (!corpus) {
    console.error('Erro: --corpus é obrigatório');
    process.exit(1);
  }

  // Cria a pasta acervo se não existir (necessário para realpath)
  const acervoReal = path.join(raiz, 'acervo');
  if (!fs.existsSync(acervoReal)) {
    fs.mkdirSync(acervoReal, { recursive: true });
  }

  const pastaCorpus = path.join(raiz, 'acervo', corpus);
  const pastaPai = path.dirname(pastaCorpus);

  let acervoResolved;
  let pastaCorpusResolved;

  try {
    // Resolve acervo (existe agora)
    acervoResolved = fs.realpathSync(acervoReal);
    // Resolve diretório pai do corpus (pode não existir ainda, então normaliza com resolve)
    pastaCorpusResolved = fs.realpathSync(pastaPai);
  } catch (e) {
    // Se realpath falhar, recusa (não conseguimos garantir confinamento)
    console.error('Erro: não é possível validar confinamento do corpus');
    process.exit(1);
  }

  // Usa path.relative para comparar caminhos corretamente
  const relativo = path.relative(acervoResolved, pastaCorpusResolved);

  const dentro = relativo === '' ||
                 (!relativo.startsWith('..' + path.sep) &&
                  relativo !== '..' &&
                  !path.isAbsolute(relativo));

  if (!dentro) {
    console.error('Erro: corpus contém path traversal');
    process.exit(1);
  }
}

/**
 * Lê e parseia o arquivo JSON do grafo
 */
function lerGrafo(caminhoGrafo) {
  try {
    const conteudo = fs.readFileSync(caminhoGrafo, 'utf8');
    return JSON.parse(conteudo);
  } catch (erro) {
    console.error(`Erro ao ler grafo: ${erro.message}`);
    process.exit(1);
  }
}

/**
 * Cria a pasta de destino se não existir
 */
function criarPasta(caminho) {
  if (!fs.existsSync(caminho)) {
    fs.mkdirSync(caminho, { recursive: true });
  }
}

/**
 * Valida que o caminho final do arquivo não sai de pastaBase usando realpath e path.relative
 */
function validarCaminhoNo(nomeArquivo, pastaBase) {
  const caminhoFinal = path.join(pastaBase, nomeArquivo);

  let caminhoRealizado;
  let pastaBaseRealizada;

  try {
    // Resolve ambos os caminhos usando realpath
    // Isso normaliza .., ., symlinks, etc.
    caminhoRealizado = fs.realpathSync(path.dirname(caminhoFinal));
    pastaBaseRealizada = fs.realpathSync(pastaBase);
  } catch (e) {
    // Se realpath falhar, recusa (não conseguimos garantir confinamento)
    return false;
  }

  // Usa path.relative para comparar caminhos corretamente
  // Se o arquivo está dentro da pasta base, relative retorna um caminho relativo
  // que não começa com '..' e não é absoluto
  const relativo = path.relative(pastaBaseRealizada, caminhoRealizado);

  // Dentro se: mesmo diretório (relativo === '')
  // ou dentro (relativo não contém '..', não é absoluto, não é vazio com separador)
  const dentro = relativo === '' ||
                 (!relativo.startsWith('..' + path.sep) &&
                  relativo !== '..' &&
                  !path.isAbsolute(relativo));

  return dentro;
}

/**
 * Escapa caracteres especiais para markdown seguro. Vale para TODO campo de
 * texto que sai no corpo — titulo, resumo, tipo de aresta. O grafo e entrada
 * nao confiavel: o schema deixa esses campos como "qualquer string".
 */
function escaparTexto(texto) {
  return String(texto)
    .replace(/\\/g, '\\\\')
    .replace(/\[/g, '\\[')
    .replace(/\]/g, '\\]')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)')
    .replace(/</g, '\\<')
    .replace(/>/g, '\\>');
}

// Nome antigo, mantido porque o SKILL.md cita.
const escaparTitulo = escaparTexto;

/**
 * Devolve o texto dentro de um span de codigo inline que ele nao consegue
 * fechar. Cerca com uma crase a mais que a maior sequencia de crases do
 * conteudo (CommonMark), e poe espaco de folga quando o conteudo comeca ou
 * termina em crase. Sem isso, um `id` com crase fecha o span e o resto do
 * documento sai deslocado.
 */
function codigoInline(texto) {
  const s = String(texto);
  let maior = 0;
  for (const seq of s.match(/`+/g) || []) {
    if (seq.length > maior) maior = seq.length;
  }
  const cerca = '`'.repeat(maior + 1);
  const folga = (s.startsWith('`') || s.endsWith('`')) ? ' ' : '';
  return `${cerca}${folga}${s}${folga}${cerca}`;
}

/**
 * Escapa o ALVO de um link markdown. O `id` vira nome de arquivo e alvo de
 * link, e o schema permite parenteses e espaco — os dois quebram a forma
 * `[texto](alvo)`. Percent-encoding resolve sem mudar o arquivo apontado.
 */
function alvoLink(id) {
  return String(id)
    .replace(/%/g, '%25')
    .replace(/ /g, '%20')
    .replace(/\(/g, '%28')
    .replace(/\)/g, '%29')
    .replace(/</g, '%3C')
    .replace(/>/g, '%3E');
}

/**
 * Cria um markdown por nó
 */
function criarMarkdownNo(no) {
  let conteudo = `# ${escaparTexto(no.titulo)}\n\n`;
  conteudo += `**ID:** ${codigoInline(no.id)}\n\n`;
  conteudo += `**Tipo:** ${escaparTexto(no.file_type)}\n\n`;
  conteudo += `**Confiança:** ${escaparTexto(no.confidence)}\n\n`;
  conteudo += `**Caminho:** ${codigoInline(no.caminho)}\n\n`;
  conteudo += `## Resumo\n\n${escaparTexto(no.resumo)}\n`;

  return conteudo;
}

/**
 * Cria o INDEX.md com rota de entrada
 */
function criarIndex(nos, arestas) {
  let conteudo = '# Acervo\n\n';
  conteudo += '## Nós\n\n';

  // Lista todos os nós
  for (const no of nos) {
    const tituloEscapado = escaparTexto(no.titulo);
    conteudo += `- [${tituloEscapado}](./${alvoLink(no.id)}.md) (${escaparTexto(no.file_type)})\n`;
  }

  conteudo += '\n## Arestas\n\n';

  // Lista todas as arestas
  if (arestas && arestas.length > 0) {
    for (const aresta of arestas) {
      const noDeId = nos.find(n => n.id === aresta.de);
      const noParaId = nos.find(n => n.id === aresta.para);
      // O fallback tambem e texto do grafo: escapa nos dois ramos.
      const noDeTitle = escaparTexto(noDeId ? noDeId.titulo : aresta.de);
      const noParaTitle = escaparTexto(noParaId ? noParaId.titulo : aresta.para);

      conteudo += `- [${noDeTitle}](./${alvoLink(aresta.de)}.md) --${escaparTexto(aresta.tipo)}--> [${noParaTitle}](./${alvoLink(aresta.para)}.md)\n`;
    }
  }

  return conteudo;
}

/**
 * Main - orquestra o build
 */
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error('Uso: build.cjs <grafo.json> --corpus <nome>');
    process.exit(1);
  }

  const caminhoGrafo = args[0];
  const corpus = extrairCorpus(args);

  // Resolve a raiz de dados primeiro
  const resultado = resolverRaiz();
  if (!resultado || !resultado.raiz) {
    console.error('Erro: não foi possível resolver a raiz de dados');
    process.exit(1);
  }

  const raiz = resultado.raiz;

  // Valida que corpus foi fornecido
  validarCorpus(corpus, raiz);

  // Verifica que o arquivo de grafo existe
  if (!fs.existsSync(caminhoGrafo)) {
    console.error(`Erro: arquivo de grafo não encontrado: ${caminhoGrafo}`);
    process.exit(1);
  }

  // Lê o grafo
  const grafo = lerGrafo(caminhoGrafo);

  // Valida estrutura básica
  if (!Array.isArray(grafo.nos)) {
    console.error('Erro: grafo.nos não é um array');
    process.exit(1);
  }
  const pastaAcervo = path.join(raiz, 'acervo', corpus);

  // Cria a pasta de destino
  criarPasta(pastaAcervo);

  // Escreve um markdown por nó
  for (const no of grafo.nos) {
    const nomeArquivo = `${no.id}.md`;

    // Valida que o arquivo fica dentro da pasta do corpus (defesa contra path traversal)
    if (!validarCaminhoNo(nomeArquivo, pastaAcervo)) {
      console.error(`Erro: id contém path traversal: ${no.id}`);
      process.exit(1);
    }

    const caminhoArquivo = path.join(pastaAcervo, nomeArquivo);
    const conteudo = criarMarkdownNo(no);
    fs.writeFileSync(caminhoArquivo, conteudo, 'utf8');
  }

  // Escreve o INDEX.md
  const caminhoIndex = path.join(pastaAcervo, 'INDEX.md');
  const conteudoIndex = criarIndex(grafo.nos, grafo.arestas || []);
  fs.writeFileSync(caminhoIndex, conteudoIndex, 'utf8');

  process.exit(0);
}

main();
