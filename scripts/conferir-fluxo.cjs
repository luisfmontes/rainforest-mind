#!/usr/bin/env node
// @categoria: sensor
/**
 * Conferir fluxo — validação de fechamento entre design, plano e código.
 *
 * Por que existe: o fluxo não tem checagem de fechamento entre artefatos
 * vizinhos. Decisão do design pode não virar tarefa, opção refutada não tem
 * onde morar, e código sem tarefa correspondente atravessa o revisar como se
 * fosse estilo. As três costuras fecham aqui com checagem que trava, não com
 * instrução que pede.
 *
 * Desenho: D1 (esta é a trava — não prosa), D2 (identificador D<n>), D3
 * (opção em "Avaliado e descartado"), D4 (creep reprova), D6 (arquivo → glob),
 * D7 (script único com subcomandos).
 *
 * Desenho de 2026-08-21 (gate de sessão co-locada e catraca de mutação): D7
 * (o alvo da mutação é DECLARADO pela tarefa, nunca inferido) e D9 (toda
 * tarefa declara, e `n/a` com motivo é resposta aceita) — cobrados no
 * subcomando `cobertura`.
 *
 * Uso:
 *   node scripts/conferir-fluxo.cjs design --slug <s>
 *   node scripts/conferir-fluxo.cjs cobertura --slug <s>
 *   node scripts/conferir-fluxo.cjs creep --slug <s> --base <ref> --head <ref>
 *
 * Exit: 0 passou, 2 recusa deliberada, 1 erro de uso, 69 nao-verificavel —
 * AMBIENTE, nao conteudo (D5, 2026-09-12): `creep` chama `git diff` e, se o
 * `git` nao estiver no PATH (`spawnSync`/`execFileSync` devolve ENOENT), a
 * ausencia de diff nao e' "sem creep" nem "creep encontrado" — e' "nao dei
 * para conferir". Primeira linha do stderr: "nao-verificavel: <motivo>".
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const { contarOcorrencias } = require(path.join(__dirname, '..', 'hooks', 'lib', 'contar-ocorrencias.cjs'));

// A raiz é a do PROJETO em que se trabalha, mesma cadeia do estado.cjs
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

// ================================================================ Utilitários

function arg(nome, obrigatorio = true) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) {
    if (obrigatorio) {
      console.error(`erro: falta --${nome}`);
      process.exit(1);
    }
    return null;
  }
  return process.argv[i + 1];
}

function lerMarkdown(arquivo) {
  if (!fs.existsSync(arquivo)) {
    return null;
  }
  let conteudo = fs.readFileSync(arquivo, 'utf8');
  // Remove BOM se houver (UTF-8 BOM é U+FEFF, três bytes: EF BB BF)
  if (conteudo.charCodeAt(0) === 0xFEFF) {
    conteudo = conteudo.slice(1);
  }
  // Normaliza CRLF para LF
  conteudo = conteudo.replace(/\r\n/g, '\n');
  return conteudo;
}

// ================================================================ design

/**
 * Valida a estrutura do design document.
 * Exige seções: Objetivo, Decisões fechadas, Avaliado e descartado, Fora de escopo, Em aberto.
 * Decisões são linhas `- **D<n> — <texto>**` com n sequencial, sem buraco, sem repetido.
 */
function cmdDesign() {
  const slug = arg('slug');
  const arquivo = arg('design', false) || path.join(RAIZ, 'docs', 'rainforest', 'design', `${slug}.md`);

  const conteudo = lerMarkdown(arquivo);
  if (!conteudo) {
    console.error(`RECUSADO: arquivo não existe: ${arquivo}`);
    process.exit(2);
  }

  // Verifica seções obrigatórias (como linhas exatas, não como substring)
  const secoes_obrigatorias = [
    '## Objetivo',
    '## Decisões fechadas',
    '## Avaliado e descartado',
    '## Fora de escopo',
    '## Em aberto',
    '## Varredura',
  ];

  const linhas_conteudo = conteudo.split('\n');
  const secoes_encontradas = new Set(linhas_conteudo);

  for (const secao of secoes_obrigatorias) {
    if (!secoes_encontradas.has(secao)) {
      console.error(`RECUSADO: seção obrigatória ausente: ${secao}`);
      process.exit(2);
    }
  }

  // A secao tem de citar literalmente o .txt do proprio slug (D4). So o
  // arquivo existir nao basta: secao escrita a mao, sem rodar varrer.cjs,
  // passava com um .txt qualquer ao lado.
  const iVarredura = linhas_conteudo.indexOf('## Varredura');
  const fimVarredura = linhas_conteudo.findIndex((l, i) => i > iVarredura && l.startsWith('## '));
  const corpoVarredura = linhas_conteudo.slice(iVarredura + 1, fimVarredura === -1 ? undefined : fimVarredura).join('\n');
  const citacaoVarredura = `docs/rainforest/varredura/${slug}.txt`;
  if (!corpoVarredura.includes(citacaoVarredura)) {
    console.error(`RECUSADO: seção ## Varredura não cita ${citacaoVarredura} (gere com node scripts/varrer.cjs --slug ${slug} <termos>)`);
    process.exit(2);
  }

  // Verifica se o arquivo de varredura existe e não está vazio
  const arquivoVarredura = path.join(RAIZ, 'docs', 'rainforest', 'varredura', `${slug}.txt`);
  if (!fs.existsSync(arquivoVarredura) || fs.statSync(arquivoVarredura).size === 0) {
    console.error(`RECUSADO: seção ## Varredura cita arquivo inexistente ou vazio: ${arquivoVarredura}`);
    process.exit(2);
  }

  // Extrai decisões de "Decisões fechadas"
  // Padrão: - **D<n> — <texto>** (travessão U+2014)
  const linhas = conteudo.split('\n');
  let em_decisoes = false;
  const decisoes = [];
  const decisoes_vistas = new Set();

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];

    // Marca inicio de "Decisões fechadas"
    if (linha === '## Decisões fechadas') {
      em_decisoes = true;
      continue;
    }

    // Marca fim de "Decisões fechadas" (outra seção começa)
    if (linha.startsWith('## ') && em_decisoes) {
      em_decisoes = false;
      continue;
    }

    // Se estamos em "Decisões fechadas", procura padrão D<n>
    if (em_decisoes && linha.startsWith('- **D')) {
      // Padrão: - **D<n> — <texto>**
      const match = linha.match(/^- \*\*D(\d+) — /);
      if (match) {
        const n = parseInt(match[1], 10);
        decisoes.push(n);
        decisoes_vistas.add(n);
      }
    }
  }

  // Valida seqüência: deve começar em 1, sem buraco, sem repetido
  if (decisoes.length === 0) {
    console.error('RECUSADO: nenhuma decisão encontrada no formato D<n>');
    process.exit(2);
  }

  // Ordena para checar
  const ordenadas = [...new Set(decisoes)].sort((a, b) => a - b);

  // Verifica se começa em 1
  if (ordenadas[0] !== 1) {
    console.error(`RECUSADO: decisões devem começar em D1, encontrado D${ordenadas[0]}`);
    process.exit(2);
  }

  // Verifica seqüência sem buraco
  for (let i = 0; i < ordenadas.length; i++) {
    if (ordenadas[i] !== i + 1) {
      console.error(`RECUSADO: buraco na seqüência de decisões: esperado D${i + 1}, pulou para D${ordenadas[i]}`);
      process.exit(2);
    }
  }

  // Verifica se há repetido
  if (decisoes.length !== ordenadas.length) {
    const duplicados = decisoes.filter((v, i) => decisoes.indexOf(v) !== i);
    console.error(`RECUSADO: decisão(ões) repetida(s): D${[...new Set(duplicados)].join(', D')}`);
    process.exit(2);
  }

  console.log(`ok: ${decisoes.length} decisão(ões) válida(s)`);
}

// ================================================================ cobertura

/**
 * Valida cobertura entre design e plano.
 * Decisão sem tarefa → recusa.
 * Tarefa com atende: vazio/ausente → recusa.
 * Tarefa citando D<n> inexistente → recusa.
 * Tarefa sem bloco `mutacao:` → recusa, nomeando a tarefa.
 */
function cmdCobertura() {
  const slug = arg('slug');

  // Lê design
  const arquivo_design = arg('design', false) || path.join(RAIZ, 'docs', 'rainforest', 'design', `${slug}.md`);
  const conteudo_design = lerMarkdown(arquivo_design);
  if (!conteudo_design) {
    console.error(`RECUSADO: design não existe: ${arquivo_design}`);
    process.exit(2);
  }

  // Lê plano
  const arquivo_plano = arg('plano', false) || path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  const conteudo_plano = lerMarkdown(arquivo_plano);
  if (!conteudo_plano) {
    console.error(`RECUSADO: plano não existe: ${arquivo_plano}`);
    process.exit(2);
  }

  // Extrai decisões do design
  const decisoes_design = extrairDecisoes(conteudo_design);

  // Extrai tarefas e seus atende do plano
  const tarefas = extrairTarefas(conteudo_plano);

  // Extrai D<n> mencionados em tarefas
  const decisoes_citadas = new Set();
  const erros = [];
  const paralelasComArquivos = []; // Para checar overlaps

  for (const tarefa of tarefas) {
    const { numero, nome, atende, tipo, paralela, dependeDe, arquivos, mutacao } = tarefa;

    // Verifica se atende está vazio/ausente
    if (!atende || atende.trim() === '') {
      erros.push(`tarefa ${numero}. ${nome} tem atende: vazio`);
      continue;
    }

    // Extrai D<n> de atende (format: "D1, D2, D3")
    const matches = atende.match(/D(\d+)/g);
    if (matches) {
      for (const match of matches) {
        const d = parseInt(match.substring(1), 10);
        decisoes_citadas.add(d);

        // Verifica se D existe
        if (!decisoes_design.has(d)) {
          erros.push(`tarefa ${numero}. ${nome} cita D${d} que não existe no design`);
        }
      }
    }

    // A catraca de mutação. Em 2026-08-21 um agente cumpriu TODOS os critérios
    // falsificáveis do briefing, colou saída de validação por mutação e entregou
    // 49/49 verde — com a trava que ele acabara de escrever recusando o caminho
    // feliz sempre. Não foi caso isolado: 10 de 18 entregas do acervo têm o mesmo
    // formato de defeito (`obs-2026-08-17-dez-baterias-que-nao-sabiam-falhar`),
    // e uma bateria só vista PASSANDO não foi verificada.
    //
    // O que faltava não era rigor de quem executa, era o alvo: sem o plano dizer
    // qual linha inverter e qual bateria tem de ficar vermelha, a integração não
    // tem o que re-rodar, e o veredito volta a ser a prosa de quem implementou —
    // exatamente o arranjo que o cabeçalho do `conferir-entrega.cjs` já condena.
    // Inferir o alvo sozinho seria outro projeto; declarar é uma linha do plano.
    const falha_mutacao = conferirBlocoMutacao(mutacao);
    if (falha_mutacao) {
      erros.push(`tarefa ${numero}. ${nome} ${falha_mutacao}`);
    }

    // D14: paralela: sim com depende de ≠ nenhuma
    if (paralela === 'sim' && dependeDe !== 'nenhuma') {
      erros.push(`tarefa ${numero}. ${nome} paralela: sim mas depende de: ${dependeDe}`);
    }

    // D14: tipo fora da lista permitida
    const tipos_permitidos = ['implementar', 'configurar', 'pesquisar', 'pesquisa', 'teste', 'docs'];
    if (tipo && !tipos_permitidos.includes(tipo)) {
      erros.push(`tarefa ${numero}. ${nome} [tipo: ${tipo}] não está na lista permitida`);
    }

    // D14: arquivos com path absoluto ou saindo do repositório
    for (const arquivo of arquivos) {
      if (path.isAbsolute(arquivo)) {
        erros.push(`tarefa ${numero}. ${nome} arquivos: ${arquivo} é caminho absoluto`);
      }
      if (arquivo.split(/[\\/]/).includes('..')) {
        erros.push(`tarefa ${numero}. ${nome} arquivos: ${arquivo} sai do repositório`);
      }
    }

    // Guarda tarefas paralela: sim para checar overlaps depois
    if (paralela === 'sim') {
      paralelasComArquivos.push({ numero, nome, arquivos });
    }

    // D14: Campos desconhecidos na tarefa
    const { corpo, corpo_cerca } = extrairCorpoTarefa(conteudo_plano, numero);
    const campos_desconhecidos = extrairCamposDesconhecidos(corpo, corpo_cerca);
    for (const campo of campos_desconhecidos) {
      erros.push(`tarefa ${numero}. ${nome} campo desconhecido: ${campo}`);
    }

    // D15: Conta ocorrências de de: no arquivo da mutacao
    if (mutacao && mutacao.campos.de && !mutacao.campos.de.toLowerCase().includes('n/a')) {
      const arquivo_mutacao = mutacao.campos.arquivo ? mutacao.campos.arquivo.replace(/^`|`$/g, '') : null;
      const de = mutacao.campos.de.replace(/^`|`$/g, '');
      const raiz = mutacao.campos.raiz ? mutacao.campos.raiz.replace(/^`|`$/g, '') : '';

      if (arquivo_mutacao) {
        const caminho_arquivo = path.resolve(RAIZ, raiz || '', arquivo_mutacao);
        try {
          if (fs.existsSync(caminho_arquivo)) {
            const conteudo_arquivo = fs.readFileSync(caminho_arquivo, 'utf-8');
            const ocorrencias = contarOcorrencias(conteudo_arquivo, de);
            if (ocorrencias > 1) {
              erros.push(`tarefa ${numero}. ${nome} de: aparece ${ocorrencias} vezes em ${arquivo_mutacao}`);
            } else if (ocorrencias === 0) {
              console.log(`de: ainda nao casa em ${arquivo_mutacao} — codigo a nascer?`);
            }
          }
        } catch (_) {
          // Arquivo não existe - não é erro (D15 diz "arquivo ausente não é recusa")
        }
      }
    }
  }

  // D14: Duas tarefas paralela: sim com overlap em arquivos
  for (let i = 0; i < paralelasComArquivos.length; i++) {
    for (let j = i + 1; j < paralelasComArquivos.length; j++) {
      const t1 = paralelasComArquivos[i];
      const t2 = paralelasComArquivos[j];
      for (const arq1 of t1.arquivos) {
        for (const arq2 of t2.arquivos) {
          // Mesmo arquivo ou glob que casa
          if (arq1 === arq2 || globMatches(arq1, arq2) || globMatches(arq2, arq1)) {
            erros.push(`tarefa ${t1.numero}. ${t1.nome} e tarefa ${t2.numero}. ${t2.nome} compartilham arquivos: ${arq1}`);
          }
        }
      }
    }
  }

  // Verifica decisões sem tarefa (D que nenhuma tarefa atende)
  for (const d of decisoes_design) {
    if (!decisoes_citadas.has(d)) {
      erros.push(`decisão D${d} não tem tarefa correspondente no plano`);
    }
  }

  if (erros.length > 0) {
    console.error('RECUSADO:');
    for (const erro of erros) {
      console.error(`  ${erro}`);
    }
    process.exit(2);
  }

  console.log(`ok: cobertura válida — ${decisoes_design.size} decisão(ões), ${tarefas.length} tarefa(s)`);
}

/**
 * Marca quais linhas caem dentro de cerca de código — triplo backtick ou triplo
 * til, sempre na coluna 0. A cerca de abertura e a de fechamento contam como
 * dentro: nenhuma das duas é conteúdo do documento.
 *
 * Mora aqui, e não dentro de cada parser, porque a divergência entre parsers foi
 * o defeito: o bloco `mutacao:` já ignorava cerca, e `### 3.` dentro de cerca
 * continuava virando tarefa fantasma. Um documento tem uma leitura só.
 */
function mascaraDeCerca(linhas) {
  const dentro = new Array(linhas.length).fill(false);
  let tipo = null; // 'backtick' | 'til' | null

  for (let i = 0; i < linhas.length; i++) {
    const abre = /^`{3,}/.test(linhas[i]) ? 'backtick'
      : /^~{3,}/.test(linhas[i]) ? 'til'
        : null;

    if (tipo) {
      dentro[i] = true;
      // Cerca só fecha com o MESMO caractere que a abriu: um bloco ```
      // pode conter ~~~ como texto, e vice-versa.
      if (abre === tipo) tipo = null;
      continue;
    }
    if (abre) {
      tipo = abre;
      dentro[i] = true;
    }
  }

  return dentro;
}

function extrairDecisoes(conteudo) {
  const decisoes = new Set();
  const linhas = conteudo.split('\n');
  const cerca = mascaraDeCerca(linhas);
  let em_decisoes = false;

  for (let i = 0; i < linhas.length; i++) {
    if (cerca[i]) continue;
    const linha = linhas[i];
    if (linha === '## Decisões fechadas') {
      em_decisoes = true;
      continue;
    }
    if (linha.startsWith('## ') && em_decisoes) {
      em_decisoes = false;
      continue;
    }
    if (em_decisoes && linha.startsWith('- **D')) {
      const match = linha.match(/^- \*\*D(\d+) — /);
      if (match) {
        decisoes.add(parseInt(match[1], 10));
      }
    }
  }

  return decisoes;
}

function extrairTarefas(conteudo) {
  const tarefas = [];
  const linhas = conteudo.split('\n');
  const cerca = mascaraDeCerca(linhas);

  for (let i = 0; i < linhas.length; i++) {
    if (cerca[i]) continue;
    const linha = linhas[i];

    // Tarefa começa com ### <n>. <nome> [tipo: <tipo>]
    const match = linha.match(/^### (\d+)\. (.+?)(?:\s+\[tipo:\s*([^\]]*)\])?\s*$/);
    if (match) {
      const numero = parseInt(match[1], 10);
      const nome = match[2].trim();
      const tipo = (match[3] || '').trim().toLowerCase();

      // Corpo da tarefa: até a próxima tarefa ou seção — cabeçalho dentro de
      // cerca não fecha a tarefa, pelo mesmo motivo que não abre uma.
      const corpo = [];
      const corpo_cerca = [];
      for (let j = i + 1; j < linhas.length; j++) {
        if (!cerca[j] && (linhas[j].startsWith('###') || linhas[j].startsWith('##'))) {
          break;
        }
        corpo.push(linhas[j]);
        corpo_cerca.push(cerca[j]);
      }

      // Procura campo atende: no corpo (o primeiro vale)
      let atende = '';
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('atende:')) {
          atende = corpo[k].substring('atende:'.length).trim();
          break;
        }
      }

      // Procura campo prova: linha que começa com `prova:` e tem um par de crases
      let prova = null;
      let provaMalformada = false;
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('prova:')) {
          const m = corpo[k].match(/^prova:\s*`([^`]+)`\s*$/);
          if (m) {
            prova = m[1];
          } else {
            provaMalformada = true;
          }
          break;
        }
      }

      // Procura campo prova-na-base: texto após `prova-na-base:`
      let provaNaBase = null;
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('prova-na-base:')) {
          provaNaBase = corpo[k].substring('prova-na-base:'.length).trim();
          break;
        }
      }

      // Procura campo arquivos: e extrai os caminhos
      let arquivos = [];
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('arquivos:')) {
          const match = corpo[k].match(/arquivos:\s*(.+)/);
          if (match) {
            const items = match[1];
            const matches = items.match(/`([^`]+)`/g);
            if (matches) {
              for (const m of matches) {
                arquivos.push(m.replace(/`/g, ''));
              }
            }
          }
          break;
        }
      }

      // Procura campo depende de:
      let dependeDe = 'nenhuma';
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('depende de:')) {
          dependeDe = corpo[k].substring('depende de:'.length).trim();
          break;
        }
      }

      // Procura campo paralela:
      let paralela = 'nao';
      for (let k = 0; k < corpo.length; k++) {
        if (!corpo_cerca[k] && corpo[k].startsWith('paralela:')) {
          paralela = corpo[k].substring('paralela:'.length).trim().toLowerCase();
          break;
        }
      }

      tarefas.push({ numero, nome, atende, tipo, prova, provaMalformada, provaNaBase, arquivos, dependeDe, paralela, mutacao: extrairMutacao(corpo, corpo_cerca) });
    }
  }

  return tarefas;
}

/**
 * Lê o bloco `mutacao:` de uma tarefa. Devolve `null` quando a tarefa não o
 * declara — que é o caso que o `cobertura` recusa.
 *
 * Forma:
 *   mutacao:
 *     arquivo: `<caminho>`
 *     de: <padrão a inverter>
 *     para: <substituto>
 *     bateria: `<comando>`
 *
 * O casamento é por INÍCIO de linha, nunca por substring: `pronto quando:` cita
 * `mutacao:` entre crases em plano que fale da própria trava, e reconhecer isso
 * como declaração daria por cumprida uma tarefa que só menciona a palavra.
 * Ignora linhas que aparecem dentro de cerca de código (triplos backticks ou tils).
 */
function extrairMutacao(corpo, cerca) {
  // A máscara vem de quem leu o documento inteiro. Recalcular aqui sobre o corpo
  // recortado daria resposta diferente quando a cerca abre antes da tarefa.
  const dentro_cerca = cerca || mascaraDeCerca(corpo);

  // Procura `mutacao:` fora de cerca de código
  const i = corpo.findIndex((l, idx) => l.startsWith('mutacao:') && !dentro_cerca[idx]);
  if (i === -1) {
    return null;
  }

  const bloco = {
    inline: corpo[i].substring('mutacao:'.length).trim(),
    campos: {},
  };

  // Subcampos são as linhas INDENTADAS logo abaixo; a primeira linha em branco
  // ou de campo de topo (`pronto quando:`) fecha o bloco.
  for (let j = i + 1; j < corpo.length; j++) {
    const sub = corpo[j];
    if (!/^\s+\S/.test(sub)) {
      break;
    }
    const campo = sub.match(/^\s+([\wÀ-ÿ-]+):\s*(.*)$/);
    if (!campo) {
      break;
    }
    bloco.campos[campo[1].toLowerCase()] = campo[2].trim();
  }

  // `motivo:` sem indentação, logo abaixo de `mutacao: n/a`, também conta. É a
  // forma que sai naturalmente da mão de quem escreve o plano, e recusá-la seria
  // falso positivo — e trava que recusa declaração legítima é trava desligada
  // pelo hábito do `--forcar`, que é o que D9 do design manda evitar.
  if (bloco.campos.motivo === undefined) {
    const solto = corpo.find((l, idx) => l.startsWith('motivo:') && !dentro_cerca[idx]);
    if (solto) {
      bloco.campos.motivo = solto.substring('motivo:'.length).trim();
    }
  }

  return bloco;
}

/**
 * Confere um bloco `mutacao:` já extraído. Devolve `null` quando está conforme,
 * ou a frase que completa "tarefa <n>. <nome> ..." na lista de erros.
 */
function conferirBlocoMutacao(bloco) {
  if (!bloco) {
    return 'não declara `mutacao:` (arquivo, de, para, bateria — ou `n/a` com `motivo:`)';
  }

  const campos = bloco.campos;
  const vazio = v => v === undefined || v.trim() === '';
  const na = v => v !== undefined && v.trim().toLowerCase() === 'n/a';

  // `n/a` nas duas formas que o plano usa: no valor de `mutacao:` ou marcando
  // `de:`/`para:`. Tarefa de doc não tem comportamento a inverter (D9), e o
  // preço do escape é o motivo escrito.
  if (na(bloco.inline) || (na(campos.de) && na(campos.para))) {
    if (vazio(campos.motivo)) {
      return 'declara `mutacao: n/a` sem `motivo:`';
    }
    return null;
  }

  for (const campo of ['arquivo', 'de', 'para', 'bateria']) {
    if (vazio(campos[campo])) {
      return `declara \`mutacao:\` sem \`${campo}:\``;
    }
  }

  // `raiz:` opcional (#379): pasta, relativa ao repositório, onde a bateria roda.
  // Apontar para pasta que não existe faria a tarefa inteira sair `pulada`.
  if (!vazio(campos.raiz)) {
    const pasta = campos.raiz.replace(/^`|`$/g, '').trim();
    let ehPasta = false;
    try { ehPasta = fs.statSync(path.resolve(RAIZ, pasta)).isDirectory(); } catch (_) { ehPasta = false; }
    if (!ehPasta) {
      return `declara \`mutacao:\` com \`raiz:\` que não é uma pasta existente: ${pasta}`;
    }
  }

  return null;
}

/**
 * Extrai o corpo de uma tarefa específica do plano por seu número.
 */
function extrairCorpoTarefa(conteudo_plano, numero_tarefa) {
  const linhas = conteudo_plano.split('\n');
  const cerca = mascaraDeCerca(linhas);

  for (let i = 0; i < linhas.length; i++) {
    if (!cerca[i] && linhas[i].match(new RegExp(`^### ${numero_tarefa}\\.`))) {
      const corpo = [];
      const corpo_cerca = [];
      for (let j = i + 1; j < linhas.length; j++) {
        if (!cerca[j] && (linhas[j].startsWith('###') || linhas[j].startsWith('##'))) {
          break;
        }
        corpo.push(linhas[j]);
        corpo_cerca.push(cerca[j]);
      }
      return { corpo, corpo_cerca };
    }
  }
  return { corpo: [], corpo_cerca: [] };
}

/**
 * Confere campos desconhecidos no corpo de uma tarefa (D14).
 * Retorna uma lista de nomes de campos desconhecidos encontrados.
 */
function extrairCamposDesconhecidos(corpo, cerca) {
  const conhecidos_top = new Set([
    'atende', 'arquivos', 'depende de', 'paralela', 'prova',
    'prova-na-base', 'mutacao', 'motivo', 'pronto quando'
  ]);
  const conhecidos_subcampos = new Set([
    'arquivo', 'de', 'para', 'bateria', 'fixture', 'raiz', 'timeout', 'motivo'
  ]);

  const desconhecidos = [];
  let em_mutacao = false;

  for (let k = 0; k < corpo.length; k++) {
    if (cerca && cerca[k]) continue; // Pula linhas em cerca de código

    const linha = corpo[k];

    // `pronto quando:` e o ultimo campo do template; o que vem depois e prosa,
    // e prosa tem dois-pontos ("nasceu:", "emenda 2026-09-08:") sem ser campo.
    if (/^pronto quando:/.test(linha)) break;

    // Detecta bloco mutacao:
    if (linha.startsWith('mutacao:')) {
      em_mutacao = true;
      continue;
    }

    // Sai do bloco mutacao: quando encontra uma linha não-indentada que não é um subcampo
    if (em_mutacao && linha && !/^\s/.test(linha)) {
      em_mutacao = false;
    }

    // Campo = linha `chave:` na coluna 0 (ou subcampo indentado de `mutacao:`),
    // chave minuscula de ate tres palavras — frase de prosa nao vira campo.
    const match = linha.match(/^(\s*)([a-z][a-z0-9-]*(?: [a-z0-9-]+){0,2}):(.*)$/);
    if (!match) continue;

    const indentacao = match[1];
    const campo = match[2].toLowerCase();

    // Se está indentado, é subcampo de mutacao:
    if (indentacao) {
      if (em_mutacao && !conhecidos_subcampos.has(campo)) {
        desconhecidos.push(`${campo}:`);
      }
    } else {
      // Campo no topo
      if (!conhecidos_top.has(campo)) {
        desconhecidos.push(`${campo}:`);
      }
    }
  }

  return desconhecidos;
}

// ================================================================ creep

/**
 * Detecta arquivos no diff que não casam com glob de tarefa nenhuma.
 * Globs: *, **, ?
 * Isenção: docs/rainforest/design/**, docs/rainforest/planos/**, docs/rainforest/estado/**
 */
function cmdCreep() {
  const slug = arg('slug');
  const base = arg('base');
  const head = arg('head');

  // Lê plano
  const arquivo_plano = arg('plano', false) || path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  const conteudo_plano = lerMarkdown(arquivo_plano);
  if (!conteudo_plano) {
    console.error(`RECUSADO: plano não existe: ${arquivo_plano}`);
    process.exit(2);
  }

  // Extrai globs de todas as tarefas
  const tarefas = extrairTarefas(conteudo_plano);
  const globs = [];
  for (const tarefa of tarefas) {
    const gs = extrairArquivos(conteudo_plano, tarefa.numero);
    globs.push(...gs);
  }

  // Isentos: os artefatos que o PRÓPRIO fluxo escreve para ESTE trabalho.
  // Eles nunca aparecem no `arquivos:` de tarefa nenhuma — quem os escreve é o
  // brainstorm, o plano e o `estado.cjs` —, então sem isenção a checagem acusaria
  // o próprio rastro dela e nunca passaria.
  //
  // **Escopado por slug de propósito.** A primeira versão isentava
  // `docs/rainforest/design/**` inteiro, e com isso um diff que também tocasse o
  // design de OUTRA feature passava despercebido — creep de verdade, escondido
  // dentro da pasta isenta. É a mesma forma do glob largo que a decisão D6 proíbe
  // numa tarefa, só que embutida no checador, onde nenhum `revisar` a veria.
  // Achado 4 da revisão de 2026-08-13.
  // Os dois primeiros saem do caminho REAL quando ele veio por `--design`/`--plano`.
  // Quase nenhum design deste repositório se chama `<slug>.md`
  // (`fluxo-9-design-portaria.md`, `fluxo-6-design-portoes.md`), e derivar do slug
  // fazia o design DO PRÓPRIO FLUXO aparecer como creep do fluxo — o arquivo que
  // autoriza o trabalho acusado de estar fora dele.
  const rel = (abs, padrao) => (abs
    ? path.relative(RAIZ, abs).split(path.sep).join('/')
    : padrao);
  const globs_isentos = [
    rel(arg('design', false), `docs/rainforest/design/${slug}.md`),
    rel(arg('plano', false), `docs/rainforest/planos/${slug}.md`),
    `docs/rainforest/estado/${slug}.json`,
    // Portão é datado no nome (`2026-09-08-aclopar-ponytail.md`) — os dois que
    // existem neste repo são, e o `recibo`/`portoes` cria assim. `${slug}.md`
    // seco não casava com nenhum, então o arquivo que REGISTRA a verificação do
    // fluxo era acusado de creep desse mesmo fluxo. É a irmã exata do defeito
    // que o comentário acima descreve para o design, e sobreviveu a ele.
    `docs/rainforest/portoes/*${slug}.md`,
    // Achado 2 do plano contrato-de-veredito: o arquivo de impasse que a
    // Tarefa 7 exige em 'liberar --estagio revisar' (D4, D7) se chama
    // `<slug>-impasse.md` — o glob acima exige o slug IMEDIATAMENTE antes de
    // `.md`, e `-impasse` depois do slug não casa nele. Sem esta entrada
    // literal, o arquivo que autoriza a 4ª rodada seria creep da própria
    // revisão que o autoriza.
    `docs/rainforest/portoes/${slug}-impasse.md`,
    'relatorios/',
    // A skill `regua` exige commitar a régua antes da 1ª rodada, e ela nunca
    // aparece em `arquivos:` de tarefa nenhuma — incondicional, igual a
    // `relatorios/` acima (Issue #279).
    'docs/rainforest/reguas/',
    // Brainstorm obriga a criar varredura; o `marcar --estagio design` a exige (Issue #368).
    'docs/rainforest/varredura/' + slug + '.txt',
  ];

  // Isenção condicional: quando uma tarefa declara `skills/<s>/SKILL.md` em
  // `arquivos:`, os `references/` dessa mesma skill ficam isentos também —
  // documentação auxiliar da skill que a tarefa já está autorizada a tocar.
  // Só entra quando o `SKILL.md` está declarado; skill nenhuma ganha glob
  // largo escondendo creep de verdade (Issue #279).
  for (const g of globs) {
    const m = g.match(/^skills\/([^/]+)\/SKILL\.md$/);
    if (m) globs_isentos.push(`skills/${m[1]}/references/`);
  }

  // Pega diff.
  //
  // `execFileSync` com LISTA de argumentos, e nunca `execSync` com string montada:
  // string invoca um shell de verdade, e `base`/`head` chegam aqui vindos do
  // `--json` de quem fecha o estágio `revisar`. Nome de branch aceita `;`, `` ` ``,
  // `$()`, `&` e `|` — o git só proíbe espaço e alguns símbolos no `refname` —,
  // então uma branch chamada `feature;calc` passada como `--head` fazia o shell
  // executar `calc` com os privilégios do processo do fluxo (Issue #89, achado da
  // primeira execução do `auditor-de-seguranca` contra este próprio repo).
  //
  // O mais amargo é que o caminho seguro já existia e era abandonado no último
  // passo: o valor viaja como array por `spawnSync` em `estado.cjs:552-563`, e só
  // aqui era remontado como string. `hooks/gate-worktree.cjs` já usava
  // `execFileSync` — era assimetria dentro da mesma base de código.
  let diff_arquivos = [];
  try {
    const output = execFileSync(caminhoExecutavel('git'), ['diff', '--name-only', `${base}...${head}`], { cwd: RAIZ, encoding: 'utf8' });
    diff_arquivos = output.trim().split('\n').filter(f => f.length > 0);
  } catch (err) {
    if (err.code === 'ENOENT') {
      // Ambiente, nao conteudo (D5, 2026-09-12): sem `git` no PATH nao ha diff
      // nenhum para ler — nao e' "sem creep" (aprovacao por falta de dado).
      process.stderr.write('nao-verificavel: git nao encontrado no PATH\n');
      process.exit(69);
    }
    console.error(`erro ao rodar git diff: ${err.message}`);
    process.exit(1);
  }

  // Normaliza \ para / (Windows)
  diff_arquivos = diff_arquivos.map(f => f.replace(/\\/g, '/'));

  // Verifica cada arquivo do diff
  const creep = [];
  for (const arquivo of diff_arquivos) {
    // Verifica se está nos globs isentos
    let isento = false;
    for (const g of globs_isentos) {
      if (globMatches(arquivo, g)) {
        isento = true;
        break;
      }
    }
    if (isento) continue;

    // Verifica se casa com algum glob de tarefa
    let casou = false;
    for (const g of globs) {
      if (globMatches(arquivo, g)) {
        casou = true;
        break;
      }
    }

    if (!casou) {
      creep.push(arquivo);
    }
  }

  if (creep.length > 0) {
    console.error('RECUSADO: arquivo(s) no diff sem tarefa correspondente:');
    for (const arq of creep) {
      console.error(`  ${arq}`);
    }
    console.error('Emendar o plano: adicione uma tarefa com campos arquivos: que cubra este(s) arquivo(s)');
    process.exit(2);
  }

  console.log(`ok: sem creep — ${diff_arquivos.length} arquivo(s) coberto(s)`);
}

function extrairArquivos(conteudo_plano, numero_tarefa) {
  const linhas = conteudo_plano.split('\n');
  let em_tarefa = false;
  const globs = [];

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];

    // Identifica a tarefa pelo número
    if (linha.match(new RegExp(`^### ${numero_tarefa}\\.`))) {
      em_tarefa = true;
      continue;
    }

    // Sai do modo "dentro da tarefa" sem encerrar a varredura do documento
    // inteiro: uma emenda que repete `### N.` mais adiante, separada por
    // outra tarefa, ainda precisa ser alcançada (Issue #279). Numa linha só
    // de propósito — o campo `de:`/`para:` do plano só aceita uma linha.
    if (em_tarefa && (linha.startsWith('###') || linha.startsWith('##'))) { em_tarefa = false; continue; }

    // Procura "arquivos: ..."
    if (em_tarefa && linha.startsWith('arquivos:')) {
      // Formato: arquivos: `<glob>`, `<glob>`
      // ou: arquivos: `<glob>`
      const match = linha.match(/arquivos:\s*(.+)/);
      if (match) {
        const items = match[1];
        // Extrai globs entre backticks
        const matches = items.match(/`([^`]+)`/g);
        if (matches) {
          for (const m of matches) {
            globs.push(m.replace(/`/g, ''));
          }
        }
      }
    }
  }

  return globs;
}

/**
 * Glob simples: *, **, ?
 * * não cruza /
 * ** cruza /
 * ? é qualquer caractere (não /)
 */
function globMatches(arquivo, glob) {
  // Barra no fim é PASTA: cobre tudo abaixo dela. Sem isto, `arquivos:
  // scripts/fixtures/escada/` no plano lia como cobertura da pasta e não
  // cobria arquivo nenhum — comparação literal contra um caminho de pasta
  // nunca casa com um caminho de arquivo. O `revisar` recusava por creep os
  // dez arquivos que o plano declarava, sem dizer por quê. Achado em
  // 2026-09-08, fechando o fluxo aclopar-ponytail.
  if (glob.endsWith('/')) {
    return arquivo.startsWith(glob);
  }

  // Simples: se não tem *, **, ou ?, é match literal
  if (!glob.includes('*') && !glob.includes('?')) {
    return arquivo === glob;
  }

  // Converte glob para regex
  let pattern = glob
    .replace(/\./g, '\\.')
    .replace(/\//g, '/');

  // ** em qualquer lugar cruza /
  pattern = pattern.replace(/\*\*/g, '<<<DOUBLESTAR>>>');
  // * em qualquer lugar não cruza /
  pattern = pattern.replace(/\*/g, '[^/]*');
  // ? é qualquer caractere (não /)
  pattern = pattern.replace(/\?/g, '[^/]');
  // Restaura **
  pattern = pattern.replace(/<<<DOUBLESTAR>>>/g, '.*');

  // Âncora: se não começar com *, é desde o início
  if (!glob.startsWith('*')) {
    pattern = '^' + pattern;
  }
  // Se não terminar com *, é até o final
  if (!glob.endsWith('*')) {
    pattern = pattern + '$';
  }

  const regex = new RegExp(pattern);
  return regex.test(arquivo);
}

// ================================================================ mutacoes

/**
 * Valida mutações: para cada tarefa do plano que declare `mutacao:`, executa
 * o script `conferir-mutacao.cjs` com os campos do bloco.
 *
 * Saída: uma linha por tarefa — `tarefa N: vermelho` (exit 0), `tarefa N: mutante sobreviveu`
 * (exit 2), `tarefa N: pulada (<motivo>)` para n/a, exit 3/4/5, etc.
 *
 * Exit: 0 se nenhum mutante sobreviveu (ou tudo foi pulado); ≠ 0 se algum sobreviveu.
 */
function cmdMutacoes() {
  const slug = arg('slug');

  // Lê plano
  const arquivo_plano = arg('plano', false) || path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  const conteudo_plano = lerMarkdown(arquivo_plano);
  if (!conteudo_plano) {
    console.error(`RECUSADO: plano não existe: ${arquivo_plano}`);
    process.exit(2);
  }

  // Extrai tarefas
  const tarefas = extrairTarefas(conteudo_plano);

  // Processa cada tarefa
  let algumSobreviveu = false;
  // Issue #281: exit 1/3/4/5/outros (mutação não aplicada, baseline
  // não-verde, corte de shell, etc.) são "não medi", não "medi e passou".
  // Antes só exit === 2 (mutante sobreviveu de fato) recusava o subcomando;
  // qualquer outra falha de medição saía como `pulada` e não pesava no exit
  // final, então um plano com `de:` todo em prosa fechava `mutacoes` com
  // exit 0 sem ter aplicado mutação nenhuma.
  let algumaFalhaDeMedicao = false;
  const CONFERIR_MUTACAO = path.join(__dirname, 'conferir-mutacao.cjs');

  for (const tarefa of tarefas) {
    const { numero, nome, mutacao } = tarefa;

    // Tarefa sem `mutacao:` é erro estrutural já capturado por `cobertura`
    if (!mutacao) {
      console.log(`tarefa ${numero}: pulada (sem bloco mutacao)`);
      continue;
    }

    const campos = mutacao.campos;
    const vazio = v => v === undefined || v.trim() === '';
    const na = v => v !== undefined && v.trim().toLowerCase() === 'n/a';

    // `n/a` nas duas formas
    if (na(mutacao.inline) || (na(campos.de) && na(campos.para))) {
      const motivo = campos.motivo || mutacao.campos.motivo || 'sem motivo declarado';
      console.log(`tarefa ${numero}: pulada (n/a — ${motivo})`);
      continue;
    }

    // Checar se campos obrigatórios estão presentes
    const campos_obrigatorios = ['arquivo', 'de', 'para', 'bateria'];
    const ausentes = campos_obrigatorios.filter(c => vazio(campos[c]));
    if (ausentes.length > 0) {
      console.log(`tarefa ${numero}: pulada (falta ${ausentes.join(', ')})`);
      continue;
    }

    // Remover crases se houver (formato do plano)
    const arquivo = campos.arquivo.replace(/^`|`$/g, '');
    const de = campos.de.replace(/^`|`$/g, '');
    const para = campos.para.replace(/^`|`$/g, '');
    // Issue #254(b): `campos.bateria` é a linha inteira depois de `bateria:`,
    // e quem escreve o plano às vezes cola uma nota humana depois da crase de
    // fechamento (`` `node x.cjs` (tarefa 6) ``). Tirar só a crase do
    // início/fim da string inteira deixava a nota colada ao comando. Extrai
    // só o PRIMEIRO trecho entre crases — mesmo padrão de `extrairArquivos`
    // (linha 625) — caindo para o valor bruto trimado se não houver crase.
    const bateriaEntreCrases = campos.bateria.match(/`([^`]+)`/);
    const bateria = bateriaEntreCrases ? bateriaEntreCrases[1] : campos.bateria.trim();
    // `timeout:` e opcional. Sem ele o conferir-mutacao usa o proprio padrao.
    // Existe porque bateria legitimamente lenta (testa-saude.sh passa dos 300 s,
    // e a catraca a roda DUAS vezes) virava `pulada (nao mensuravel)` — cobertura
    // perdida em silencio, que e o modo de falha que D9 veio fechar.
    // `raiz:` opcional (#379): em monorepo a bateria só existe relativa à pasta do
    // app. Sem o campo, a raiz do repositório, como sempre foi.
    const raizTarefa = campos.raiz ? path.resolve(RAIZ, campos.raiz.replace(/^`|`$/g, '').trim()) : RAIZ;
    const timeout = campos.timeout ? campos.timeout.replace(/^`|`$/g, '').trim() : '';

    // Executar conferir-mutacao.cjs via spawnSync (array de argumentos, nunca string)
    const { spawnSync } = require('child_process');
    const argumentos = [
      CONFERIR_MUTACAO,
      '--arquivo', arquivo,
      '--de', de,
      '--para', para,
      '--bateria', bateria,
      '--raiz', raizTarefa,
    ];
    if (timeout) argumentos.push('--timeout', timeout);
    const resultado = spawnSync(process.execPath, argumentos, {
      stdio: 'pipe',
      encoding: 'utf8',
    });

    // A razao do conferir-mutacao vem no stderr, e `stdio: pipe` a engolia: tres
    // causas diferentes (baseline nao-verde, `--de` ambiguo, baseline estourou o
    // teto) viravam a mesma palavra `nao mensuravel`. Trava que nao diz por que
    // desistiu obriga quem le a reproduzir a mao para descobrir.
    const razao = () => {
      const LF = String.fromCharCode(10);
      const CR = String.fromCharCode(13);
      const linhas = String(resultado.stderr || '')
        .split(LF)
        .map(linha => linha.split(CR).join('').trimEnd());
      const ehRotulo = linha => {
        const t = linha.trim();
        return t.startsWith('RECUSADO') || t.startsWith('MUTACAO NAO APLICADA')
          || t.startsWith('BATERIA SEM VEREDITO');
      };
      let i = -1;
      for (let n = 0; n < linhas.length; n++) if (ehRotulo(linhas[n])) i = n;
      if (i < 0) {
        // Sem rótulo conhecido (stack trace, `erro: --arquivo não existe`): a primeira
        // linha que carrega uma marca de erro, para o motivo não sair vazio (#379).
        const MARCAS_ERRO = ['Error', 'erro', 'EPERM'];
        const achada = linhas.find(l => MARCAS_ERRO.some(m => l.includes(m)));
        return achada ? ' — ' + achada.trim() : '';
      }
      const rotulo = linhas[i].trim();
      // `RECUSADO:` já traz o motivo na mesma linha. `MUTACAO NAO APLICADA` e
      // `BATERIA SEM VEREDITO` são só o título — o que interessa está na linha
      // indentada logo abaixo, e sem ela a razão volta a não dizer nada.
      let detalhe = '';
      if (!rotulo.startsWith('RECUSADO:')) {
        for (let n = i + 1; n < linhas.length; n++) {
          const t = linhas[n].trim();
          if (!t) continue;
          if (ehRotulo(linhas[n])) break;
          // `arquivo:` repete o que o bloco `mutacao:` do plano ja diz — nao e a
          // razao de ter pulado, e ocupava a linha inteira do motivo.
          if (t.startsWith('arquivo:')) continue;
          detalhe = t;
          break;
        }
      }
      const texto = rotulo.startsWith('RECUSADO:')
        ? rotulo.slice('RECUSADO:'.length).trim()
        : (detalhe ? rotulo + ': ' + detalhe : rotulo);
      return ' — ' + texto;
    };

    // Interpretar exit code
    const exit = resultado.status;
    if (exit === 0) {
      // Mutação casou e bateria VERMELHA
      console.log(`tarefa ${numero}: vermelho`);
    } else if (exit === 2) {
      // Bateria VERDE com mutação — mutante sobreviveu
      console.log(`tarefa ${numero}: mutante sobreviveu`);
      algumSobreviveu = true;
    } else if (exit === 3) {
      // MUTACAO NAO APLICADA — trecho não existe. Falha de medição (#281):
      // ninguém provou que a bateria morde, então não pode fechar como se
      // tivesse medido.
      console.log(`tarefa ${numero}: pulada (de não encontrado)${razao()}`);
      algumaFalhaDeMedicao = true;
    } else if (exit === 4) {
      // Não dá para medir — baseline já falha ou --de ambíguo
      console.log(`tarefa ${numero}: pulada (não mensurável)${razao()}`);
      algumaFalhaDeMedicao = true;
    } else if (exit === 5) {
      // Suspeita de corte de shell
      console.log(`tarefa ${numero}: pulada (suspeita de corte de shell)${razao()}`);
      algumaFalhaDeMedicao = true;
    } else if (exit === 1) {
      // Erro de uso ou bateria sem veredito
      console.log(`tarefa ${numero}: pulada (erro de execução)${razao()}`);
      algumaFalhaDeMedicao = true;
    } else {
      // Qualquer outro exit (inclusive o 6 de "bateria colapsou") é a mesma
      // coisa: a catraca não conseguiu medir esta tarefa.
      console.log(`tarefa ${numero}: pulada (exit ${exit})${razao()}`);
      algumaFalhaDeMedicao = true;
    }
  }

  // Exit code do subcomando. `algumaFalhaDeMedicao` cobre o caso que a Issue
  // #281 registrou: nove tarefas, sete com mutação declarada, nenhuma
  // aplicada, e o exit saía 0 porque só `algumSobreviveu` (mutante realmente
  // sobrevivendo) derrubava o subcomando.
  process.exit((algumSobreviveu || algumaFalhaDeMedicao) ? 1 : 0);
}

// ================================================================ main

function main() {
  const cmd = process.argv[2];

  if (cmd === 'design') {
    return cmdDesign();
  }

  if (cmd === 'cobertura') {
    return cmdCobertura();
  }

  if (cmd === 'creep') {
    return cmdCreep();
  }

  if (cmd === 'mutacoes') {
    return cmdMutacoes();
  }

  console.error('uso: design | cobertura | creep | mutacoes');
  process.exit(1);
}

if (require.main === module) main();
// `extrairTarefas` e `lerMarkdown` saem daqui porque o `estado.cjs` precisa da MESMA
// leitura do plano para cruzar a catraca de mutação com a lista de tarefas. Um
// segundo parser divergiria — e divergiu: a primeira versão daquela checagem contava
// `### 3.` dentro de cerca como tarefa e recusava entrega correta.
module.exports = { globMatches, extrairTarefas, lerMarkdown, mascaraDeCerca };
