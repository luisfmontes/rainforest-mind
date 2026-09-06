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
    // Quebra de linha vem PRIMEIRO. Sem isso, um resumo com "\n# titulo"
    // abre um bloco markdown novo: no CommonMark uma ATX heading interrompe
    // paragrafo sem precisar de linha em branco. O acervo e lido por agente,
    // entao bloco injetado vira texto que passa por conteudo legitimo.
    .replace(/\r\n?|\n/g, ' ')
    // Controle tambem some: alguns quebram o arquivo, outros escondem texto.
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
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
  // Mesma razao do escaparTexto: span de codigo inline nao atravessa linha,
  // entao um \n aqui tambem abre bloco novo no documento.
  const s = String(texto)
    .replace(/\r\n?|\n/g, ' ')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
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
    // % primeiro, senao re-escapa o que os outros produziram.
    .replace(/%/g, '%25')
    // Quebra de linha e controle. O alvo do link NAO passa pelo escaparTexto,
    // e 'aresta.de'/'aresta.para' chegam crus: o schema permite 'para' ser
    // referencia externa, entao nao ha nó correspondente e nada os valida.
    // Sem isto, um \n parte o link no meio e corrompe o INDEX.md — medido.
    .replace(/\r/g, '%0D')
    .replace(/\n/g, '%0A')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .replace(/ /g, '%20')
    .replace(/\(/g, '%28')
    .replace(/\)/g, '%29')
    .replace(/</g, '%3C')
    .replace(/>/g, '%3E')
    // '#' e '?' cortam o alvo: './nota#1.md' aponta para o arquivo 'nota'
    // com fragmento '1.md', nao para o arquivo 'nota#1.md' que foi escrito.
    .replace(/#/g, '%23')
    .replace(/\?/g, '%3F');
}

// Caracteres que o Windows nao aceita em nome de arquivo. ':' e o pior deles:
// nao da erro, grava num Alternate Data Stream do NTFS. Medido — um id
// 'x:secret' criou um arquivo chamado 'x' e escondeu o conteudo no stream.
// So o que corrompe em SILENCIO. ':' vira Alternate Data Stream no NTFS
// (medido: id 'x:secret' criou um arquivo 'x' vazio e escondeu o no no
// stream, exit 0); caractere de controle nao aparece na listagem. O resto do
// conjunto proibido do Windows ('? * " < > |') o SO rejeita com erro, e erro
// o catch do writeFileSync nomeia — e em Linux esses caracteres sao validos,
// entao recusar aqui quebraria corpus que o schema aceita.
const RE_NOME_INVALIDO = /[:\x00-\x1F]/;

/**
 * Nome que o sistema de arquivos REALMENTE vai usar, para achar colisao antes
 * de ela apagar um no. O que colide de verdade aqui e a CAIXA: o NTFS nao
 * distingue 'Foo.md' de 'foo.md', entao dois ids que o schema aceita como
 * diferentes viram o mesmo arquivo e o segundo sobrescreve o primeiro sem
 * aviso — medido.
 *
 * Nao apara ponto nem espaco no fim: o nome sempre termina em '.md', entao a
 * poda do Win32 nunca chega a atuar. Uma versao anterior aparava, e era ramo
 * morto que a revisao pegou.
 *
 * Nao pega o 'İ' turco, e nao precisa: medido no NTFS, 'İ.md' e 'i.md'
 * coexistem como arquivos distintos, e o toLowerCase do V8 devolve 'i̇' (i
 * mais ponto combinante), que tambem nao colide com 'i'. As duas coisas
 * concordam, entao nao ha falso negativo.
 */
function nomeEfetivo(nomeArquivo) {
  return nomeArquivo.toLowerCase();
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

  // TODA recusa acontece ANTES da primeira escrita. Recusar no meio do laco
  // deixa alguns .md gravados, o INDEX.md ausente, e nada dizendo que o
  // acervo ficou pela metade — medido: um id ruim no segundo no deixava o
  // primeiro em disco e abortava sem indice.
  const nomesVistos = new Map(); // nome efetivo -> id que o reivindicou
  for (const no of grafo.nos) {
    const nomeArquivo = `${no.id}.md`;

    // Valida que o arquivo fica dentro da pasta do corpus (defesa contra path traversal)
    if (!validarCaminhoNo(nomeArquivo, pastaAcervo)) {
      console.error(`Erro: id contém path traversal: ${no.id}`);
      process.exit(1);
    }

    // ':' nao da erro: grava num Alternate Data Stream do NTFS, que some da
    // listagem e leva o no junto. E o unico caso de corrupcao SILENCIOSA, por
    // isso e o unico que a guarda recusa. Caractere que o SO rejeita de fato
    // ('?' e '*' no Windows, nenhum no Linux) cai no catch do writeFileSync,
    // que nomeia o no — recusar aqui derrubaria em Linux um id perfeitamente
    // valido, e o schema publica id como "qualquer string nao-vazia".
    if (RE_NOME_INVALIDO.test(no.id)) {
      console.error(`Erro: id contém caractere inválido para nome de arquivo: ${JSON.stringify(no.id)}`);
      process.exit(1);
    }

    // Colisao depois da normalizacao do sistema de arquivos: perda silenciosa
    // de no. Recusa em vez de deixar o segundo sobrescrever o primeiro.
    const efetivo = nomeEfetivo(nomeArquivo);
    if (nomesVistos.has(efetivo)) {
      console.error(
        `Erro: dois nós disputam o mesmo arquivo '${efetivo}': ` +
        `${JSON.stringify(nomesVistos.get(efetivo))} e ${JSON.stringify(no.id)}`
      );
      process.exit(1);
    }
    nomesVistos.set(efetivo, no.id);
  }

  // Se a escrita falhar no meio, desfaz o que ESTA execucao gravou. Nem toda
  // recusa da para prever antes: se o id e valido em Linux e o Windows
  // rejeita, so o writeFileSync descobre. O que nao pode acontecer e sobrar
  // um acervo pela metade, sem INDEX.md e sem dizer que ficou parcial.
  const escritos = [];
  function desfazer() {
    for (const c of escritos) {
      try { fs.rmSync(c, { force: true }); } catch (e) { /* nada a fazer */ }
    }
  }

  // Escreve um markdown por nó
  for (const no of grafo.nos) {
    const nomeArquivo = `${no.id}.md`;
    const caminhoArquivo = path.join(pastaAcervo, nomeArquivo);
    const conteudo = criarMarkdownNo(no);
    try {
      fs.writeFileSync(caminhoArquivo, conteudo, 'utf8');
      escritos.push(caminhoArquivo);
    } catch (erro) {
      // Sem isso, um id que o SO recusa sobe stack trace cru.
      console.error(`Erro ao escrever o nó ${JSON.stringify(no.id)}: ${erro.message}`);
      desfazer();
      console.error(`Nada gravado: desfeitos os ${escritos.length} arquivo(s) desta execução.`);
      process.exit(1);
    }
  }

  // Escreve o INDEX.md
  const caminhoIndex = path.join(pastaAcervo, 'INDEX.md');
  const conteudoIndex = criarIndex(grafo.nos, grafo.arestas || []);
  try {
    fs.writeFileSync(caminhoIndex, conteudoIndex, 'utf8');
  } catch (erro) {
    console.error(`Erro ao escrever o INDEX.md: ${erro.message}`);
    desfazer();
    console.error(`Nada gravado: desfeitos os ${escritos.length} arquivo(s) desta execução.`);
    process.exit(1);
  }

  process.exit(0);
}

main();
