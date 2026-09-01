#!/usr/bin/env node
/**
 * Conselho — debate estruturado de decisões de design
 *
 * Attribution: Ideas adapted from karpathy/llm-council (https://github.com/karpathy/llm-council).
 * The original repository has no license file. This is idea-mining only — no code is reused,
 * only the concepts of cross-review anonymization, ranked review, and mechanical synthesis.
 *
 * Fases:
 *   1. abrir --questao <arquivo.md>  -> gera prompts por membro, valida quórum
 *   2. revisar                        -> anonimiza, colhe revisões
 *   3. sintetizar [--unanime]         -> agrega, grava sintese.json
 *   4. conferir --fase <pareceres|revisao|sintese> -> valida portão
 *
 * Contrato de membro: executável em config, cmd com placeholders {prompt} e {saida},
 * exit 0 em sucesso, escreve JSON: {"posicao":"...", "argumentos":[...], "objecoes":[...], "riscos":[...]}
 */

const fs = require('fs');
const path = require('path');
const { spawnSync, execSync } = require('child_process');
const { resolverConfig } = require('../hooks/lib/config.cjs');

// Raiz do projeto
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const DIR_CONSELHO = path.join(RAIZ, '.rainforest', 'conselho');
const ARQUIVO_MEMBROS = path.join(DIR_CONSELHO, 'membros.json');

const QUORUM_MINIMO = 3;

// Cmd padrao dos adaptadores embutidos: caminho ABSOLUTO deste script.
// O spawn roda no projeto do usuario, e 'scripts/conselho.cjs' relativo so
// existe no repo do proprio plugin (achado da rodada real da T9).
const CMD_ADAPTADOR = (nome) => `node "${__filename}" adaptador-${nome} {prompt} {saida}`;

// Timeout por execução de membro. Membro real (claude/codex/gemini) leva
// 30-120s; fixture leva ms. Os 30s fixos matavam a rodada real (achado da T9).
const TIMEOUT_MEMBRO_MS = Number(process.env.CONSELHO_TIMEOUT_MS) || 300000;

// Lê JSON de saída de membro tolerando cerca de código (```json ... ```)
// que modelos reais põem mesmo instruídos a não pôr (achado da T9).
function parseJsonDeMembro(conteudo) {
  let texto = String(conteudo).trim();
  const cerca = texto.match(/^```(?:json)?\s*\n([\s\S]*?)\n```\s*$/);
  if (cerca) texto = cerca[1].trim();
  return JSON.parse(texto);
}

// Calculates a deterministic round ID based on date and question slug
function calcularIdRodada(nomeArquivo) {
  const hoje = new Date();
  const ano = String(hoje.getFullYear());
  const mes = String(hoje.getMonth() + 1).padStart(2, '0');
  const dia = String(hoje.getDate()).padStart(2, '0');

  // slug: nome do arquivo sem extensão, minúsculo, hífens em lugar de underscore/espaço
  let slug = path.basename(nomeArquivo, path.extname(nomeArquivo))
    .toLowerCase()
    .replace(/[_\s]+/g, '-')
    .replace(/[^a-z0-9-]/g, '');

  return `${ano}${mes}${dia}-${slug}`;
}

// Generates default membros.json with standard personas and disabled external members
function gerarMembrosDefault() {
  return {
    membros: [
      {
        nome: 'cetico',
        cmd: 'claude -p @{prompt} > {saida}',
        ligado: true,
      },
      {
        nome: 'arquiteto',
        cmd: 'claude -p @{prompt} > {saida}',
        ligado: true,
      },
      {
        nome: 'usuario-final',
        cmd: 'claude -p @{prompt} > {saida}',
        ligado: true,
      },
      {
        nome: 'codex',
        cmd: CMD_ADAPTADOR('codex'),
        ligado: false,
      },
      {
        nome: 'gemini',
        cmd: CMD_ADAPTADOR('gemini'),
        ligado: false,
      },
    ]
  };
}

// Loads or creates membros.json, composing with config-driven external members
// External members (codex, gemini) are added from config only if their chave is ligado.
// Precedence: config chave > membros.json ligado field.
function resolverMembros() {
  fs.mkdirSync(DIR_CONSELHO, { recursive: true });

  if (!fs.existsSync(ARQUIVO_MEMBROS)) {
    const padrao = gerarMembrosDefault();
    fs.writeFileSync(ARQUIVO_MEMBROS, JSON.stringify(padrao, null, 2) + '\n', 'utf8');
  }

  const config = JSON.parse(fs.readFileSync(ARQUIVO_MEMBROS, 'utf8'));
  let membros = config.membros || [];

  // Aplicar chaves de config: membros externos entram quando chave ligada
  try {
    const cfg = resolverConfig();

    // Codex: entra se chave ligada
    if (cfg.valores['conselho-codex']) {
      const indice = membros.findIndex(m => m.nome === 'codex');
      if (indice >= 0) {
        membros[indice].ligado = true;
      } else {
        membros.push({
          nome: 'codex',
          cmd: CMD_ADAPTADOR('codex'),
          ligado: true,
        });
      }
    }

    // Gemini: entra se chave ligada
    if (cfg.valores['conselho-gemini']) {
      const indice = membros.findIndex(m => m.nome === 'gemini');
      if (indice >= 0) {
        membros[indice].ligado = true;
      } else {
        membros.push({
          nome: 'gemini',
          cmd: CMD_ADAPTADOR('gemini'),
          ligado: true,
        });
      }
    }
  } catch (e) {
    // Se falhar na leitura de config, segue sem chaves ativadas
  }

  return membros;
}

// Validates quorum and returns list of linked members
function validarQuorum(membros) {
  const ligados = membros.filter(m => m.ligado);
  if (ligados.length < QUORUM_MINIMO) {
    const nomes = ligados.map(m => m.nome).join(', ') || '(nenhum)';
    console.error(`Quórum insuficiente: ${ligados.length} membros ligados (mínimo ${QUORUM_MINIMO}). Ligados: ${nomes}`);
    process.exit(1);
  }
  return ligados;
}

// Validates that the question file exists
function validarQuestao(caminhoQuestao) {
  if (!fs.existsSync(caminhoQuestao)) {
    console.error(`Erro: arquivo da questão não encontrado: ${caminhoQuestao}`);
    process.exit(1);
  }
}

// Creates rodada directory and generates prompt files for each member
function abrirRodada(caminhoQuestao, membrosLigados) {
  const questao = fs.readFileSync(caminhoQuestao, 'utf8');
  const nomeArquivo = path.basename(caminhoQuestao);
  const idRodada = calcularIdRodada(nomeArquivo);
  const dirRodada = path.join(DIR_CONSELHO, idRodada);

  fs.mkdirSync(dirRodada, { recursive: true });

  // Generate prompt file for each linked member
  for (const membro of membrosLigados) {
    const nomePrompt = path.join(dirRodada, `prompt-${membro.nome}.md`);
    const persona = gerarPersona(membro.nome);
    const contratoJson = [
      '## Formato da resposta (obrigatório)',
      '',
      'Responda SOMENTE com um objeto JSON válido, sem cerca de código e sem texto fora dele:',
      '',
      '{"posicao": "sua posição em uma frase", "argumentos": ["..."], "objecoes": ["ao menos uma objeção concreta"], "riscos": ["..."]}',
    ].join('\n');
    const conteudo = `${persona}\n\n## Questão\n\n${questao}\n\n${contratoJson}`;
    fs.writeFileSync(nomePrompt, conteudo, 'utf8');
  }

  // Create minimal estado.json for this rodada
  const estadoRodada = {
    id: idRodada,
    questao: nomeArquivo,
    aberto_em: new Date().toISOString(),
    membros_ligados: membrosLigados.map(m => m.nome),
    fases: {
      pareceres: { status: 'pendente' },
      revisao: { status: 'pendente' },
      sintese: { status: 'pendente' }
    },
    tentativas: {
      pareceres: 0,
      revisao: 0,
      sintese: 0
    }
  };

  const arquivoEstado = path.join(dirRodada, 'estado.json');
  fs.writeFileSync(arquivoEstado, JSON.stringify(estadoRodada, null, 2) + '\n', 'utf8');

  console.log(`Rodada ${idRodada} aberta`);
  console.log(`Diretório: ${dirRodada}`);
  console.log(`Membros: ${membrosLigados.map(m => m.nome).join(', ')}`);

  return { idRodada, dirRodada };
}

// Returns persona instruction for each member role
function gerarPersona(nome) {
  const personas = {
    cetico: `Você é um revisor cético e crítico. Sua função é questionar pressupostos,
identificar armadilhas lógicas e propor objeções sólidas baseadas em evidência.
Produza um parecer estruturado listando sua posição, argumentos que a sustentam,
objeções concretas (obrigatório: mínimo uma) e riscos identificados.`,

    arquiteto: `Você é um arquiteto de sistemas focado em design e escalabilidade.
Sua função é avaliar a decisão sob lentes de estrutura, coesão, acoplamento e manutenibilidade.
Produza um parecer estruturado listando sua posição, argumentos técnicos que a sustentam,
objeções concretas (obrigatório: mínimo uma) e riscos de implementação.`,

    'usuario-final': `Você é um usuário final representante. Sua função é avaliar
como a decisão afeta a experiência, usabilidade e valor entregue.
Produza um parecer estruturado listando sua posição, argumentos baseados em experiência do usuário,
objeções concretas (obrigatório: mínimo uma) e riscos à adoção.`,
  };

  return personas[nome] || '';
}

// Finds the most recent rodada directory or returns null
function encontrarRodada() {
  if (!fs.existsSync(DIR_CONSELHO)) {
    return null;
  }

  const rodadas = fs.readdirSync(DIR_CONSELHO)
    .filter(d => /^202\d{5}-/.test(d))
    .sort()
    .reverse();

  if (rodadas.length === 0) {
    return null;
  }

  return path.join(DIR_CONSELHO, rodadas[0]);
}

// Updates attempt counter for a phase and returns whether ABANDONA is reached
// Returns: { shouldAbandon: boolean, tentativa: number }
function incrementarTentativaFase(estado, dirRodada, fase) {
  if (!estado.tentativas) {
    estado.tentativas = { pareceres: 0, revisao: 0, sintese: 0 };
  }

  estado.tentativas[fase] = (estado.tentativas[fase] || 0) + 1;
  const tentativa = estado.tentativas[fase];

  let shouldAbandon = false;
  if (tentativa >= 3) {
    estado.resultado = 'ABANDONA';
    shouldAbandon = true;
  }

  // Write back estado
  const estadoPath = path.join(dirRodada, 'estado.json');
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + '\n', 'utf8');

  return { shouldAbandon, tentativa };
}

// Resets attempt counter for a phase on success
function zerarTentativaFase(estado, dirRodada, fase) {
  if (!estado.tentativas) {
    estado.tentativas = { pareceres: 0, revisao: 0, sintese: 0 };
  }

  estado.tentativas[fase] = 0;

  // Write back estado
  const estadoPath = path.join(dirRodada, 'estado.json');
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + '\n', 'utf8');
}

// Filters membros based on --membro flag
// If nomeMembro is specified, validates it exists in ligados and returns just that one
// If not specified, returns all ligados
// If specified but not found, prints error with available members and exits
function filtrarMembros(membrosLigados, nomeMembro) {
  if (!nomeMembro) {
    return membrosLigados;
  }

  const encontrado = membrosLigados.find(m => m === nomeMembro);
  if (!encontrado) {
    const disponiveis = membrosLigados.join(', ') || '(nenhum)';
    console.error(`Erro: membro desconhecido '${nomeMembro}'. Ligados: ${disponiveis}`);
    process.exit(1);
  }

  return [encontrado];
}

// Validates a parecer JSON against schema
function validarParecer(parecer) {
  if (typeof parecer !== 'object' || parecer === null) {
    return { valido: false, erro: 'parecer não é um objeto JSON' };
  }

  if (typeof parecer.posicao !== 'string') {
    return { valido: false, erro: 'campo posicao deve ser string' };
  }

  if (!Array.isArray(parecer.argumentos)) {
    return { valido: false, erro: 'campo argumentos deve ser array' };
  }

  if (!Array.isArray(parecer.objecoes)) {
    return { valido: false, erro: 'campo objecoes deve ser array' };
  }

  if (!Array.isArray(parecer.riscos)) {
    return { valido: false, erro: 'campo riscos deve ser array' };
  }

  if (parecer.objecoes.length < 1) {
    return { valido: false, erro: 'objecoes deve ter ao menos 1 elemento' };
  }

  return { valido: true };
}

// Executes parecer collection from all linked members
function executarPareceres(args) {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  let membrosLigados = estado.membros_ligados || [];

  // Filter by --membro if specified
  membrosLigados = filtrarMembros(membrosLigados, args && args.membro);

  const membros = resolverMembros();
  const membrosMap = {};
  membros.forEach(m => {
    membrosMap[m.nome] = m;
  });

  let temErro = false;
  const erros = [];

  // Execute each linked member's command
  for (const nomeMembro of membrosLigados) {
    const membro = membrosMap[nomeMembro];
    if (!membro) {
      console.error(`Erro: membro ${nomeMembro} não encontrado em config`);
      process.exit(1);
    }

    const caminhoPrompt = path.join(dirRodada, `prompt-${nomeMembro}.md`);
    const caminhoSaida = path.join(dirRodada, `parecer-${nomeMembro}.json`);

    // Replace placeholders in command — envolver caminhos em aspas para suportar espaços
    // Cuidado: se cmd JÁ tem "{prompt}" entre aspas (ex.: "{prompt}"), não duplicar
    let cmd = membro.cmd;
    if (cmd.includes('"{prompt}"')) {
      // Já tem aspas: substituir o padrão "{prompt}" literalmente
      cmd = cmd.replace('"{prompt}"', `"${caminhoPrompt}"`);
    } else {
      // Sem aspas: envolver o caminho
      cmd = cmd.replace('{prompt}', `"${caminhoPrompt}"`);
    }

    if (cmd.includes('"{saida}"')) {
      cmd = cmd.replace('"{saida}"', `"${caminhoSaida}"`);
    } else {
      cmd = cmd.replace('{saida}', `"${caminhoSaida}"`);
    }

    // Shell explicito por plataforma. No Windows, /d /s /c com o comando inteiro
    // entre aspas externas + windowsVerbatimArguments: sem isso o Node re-escapa
    // o argumento e o cmd.exe mutila qualquer cmd que contenha aspas (caminho
    // de fixture entre aspas falhava com exit 1 em todos os membros).
    const isWindows = process.platform === 'win32';
    const spawnArgs = isWindows
      ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
      : ['sh', ['-c', cmd]];

    // Execute command
    const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
      cwd: RAIZ,
      encoding: 'utf8',
      windowsVerbatimArguments: isWindows,
      timeout: TIMEOUT_MEMBRO_MS  // por membro; CONSELHO_TIMEOUT_MS sobrepõe
    });

    if (resultado.error) {
      temErro = true;
      erros.push(`${nomeMembro}: timeout ou erro de execução`);
      continue;
    }

    if (resultado.status !== 0) {
      temErro = true;
      erros.push(`${nomeMembro}: processo saiu com exit ${resultado.status}`);
      continue;
    }

    // Check that output file was created and is not empty
    if (!fs.existsSync(caminhoSaida)) {
      temErro = true;
      erros.push(`${nomeMembro}: arquivo de saída não foi criado`);
      continue;
    }

    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    if (!conteudo || conteudo.trim().length === 0) {
      temErro = true;
      erros.push(`${nomeMembro}: saída vazia`);
      continue;
    }
  }

  if (temErro) {
    erros.forEach(e => console.error(`  ${e}`));
    process.exit(1);
  }

  console.log(`Pareceres coletados de ${membrosLigados.length} membros`);
  process.exit(0);
}

// Validates that all parecer files in current rodada are valid
function conferirFasePareceres() {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  const membrosLigados = estado.membros_ligados || [];

  let temErro = false;
  const erros = [];

  // Check each linked member's parecer file
  for (const nomeMembro of membrosLigados) {
    const caminhoSaida = path.join(dirRodada, `parecer-${nomeMembro}.json`);

    // Check file exists
    if (!fs.existsSync(caminhoSaida)) {
      temErro = true;
      erros.push(`parecer do ${nomeMembro} não encontrado`);
      continue;
    }

    // Check file is not empty
    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    if (!conteudo || conteudo.trim().length === 0) {
      temErro = true;
      erros.push(`parecer do ${nomeMembro} vazio`);
      continue;
    }

    // Try to parse JSON
    let parecer;
    try {
      parecer = parseJsonDeMembro(conteudo);
    } catch (e) {
      temErro = true;
      erros.push(`parecer do ${nomeMembro}: JSON inválido (${e.message})`);
      continue;
    }

    // Validate schema
    const validacao = validarParecer(parecer);
    if (!validacao.valido) {
      // Explicitly cite member for objecoes: [] case
      if (validacao.erro === 'objecoes deve ter ao menos 1 elemento') {
        erros.push(`parecer do ${nomeMembro}: ${validacao.erro}`);
      } else {
        erros.push(`parecer do ${nomeMembro}: ${validacao.erro}`);
      }
      temErro = true;
      continue;
    }
  }

  if (temErro) {
    // Increment attempt counter
    const { shouldAbandon } = incrementarTentativaFase(estado, dirRodada, 'pareceres');

    // Print errors
    erros.forEach(e => console.error(`Parecer inválido: ${e}`));

    // If ABANDONA, print that too
    if (shouldAbandon) {
      console.error('Erro: terceira reprovação consecutiva na fase pareceres — rodada abandona');
    }

    process.exit(1);
  }

  // Success — reset counter and mark phase as ok
  zerarTentativaFase(estado, dirRodada, 'pareceres');

  // Mark phase as complete
  // estado.fases.pareceres.status = 'ok'; (desabilitado)
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + '\n', 'utf8');

  process.exit(0);
}

// Validates a revisao JSON against schema
// numeroPareceres: expected number of pareceres (N-1 where N is number of members)
function validarRevisao(revisao, numeroPareceres) {
  if (typeof revisao !== 'object' || revisao === null) {
    return { valido: false, erro: 'revisao não é um objeto JSON' };
  }

  if (!Array.isArray(revisao.ranking)) {
    return { valido: false, erro: 'campo ranking deve ser array' };
  }

  if (typeof revisao.criticas !== 'object' || revisao.criticas === null) {
    return { valido: false, erro: 'campo criticas deve ser objeto' };
  }

  // Check ranking has the expected number of items
  if (numeroPareceres !== undefined && revisao.ranking.length !== numeroPareceres) {
    return { valido: false, erro: `ranking incompleto: tem ${revisao.ranking.length} itens, esperava ${numeroPareceres}` };
  }

  // Check for duplicates in ranking (empates não são permitidos)
  const rankingUnique = new Set(revisao.ranking);
  if (rankingUnique.size !== revisao.ranking.length) {
    return { valido: false, erro: 'ranking contém duplicatas (empates não permitidos)' };
  }

  // Check that all apelidos in ranking have a corresponding critica
  for (const apelido of revisao.ranking) {
    if (!revisao.criticas.hasOwnProperty(apelido)) {
      return { valido: false, erro: `apelido "${apelido}" no ranking mas sem crítica` };
    }

    const critica = revisao.criticas[apelido];
    if (typeof critica !== 'string' || critica.trim().length === 0) {
      return { valido: false, erro: `crítica para "${apelido}" está vazia ou não é string` };
    }
  }

  // Check that all criticas have a corresponding ranking entry
  for (const apelido in revisao.criticas) {
    if (!revisao.ranking.includes(apelido)) {
      return { valido: false, erro: `crítica para "${apelido}" mas não está no ranking` };
    }
  }

  return { valido: true };
}

// Aggregates rankings from all reviewers by average position with tiebreaker
// Input: array of revisao objects
// Output: array of apelidos sorted by:
//   1. average position (lower is better)
//   2. count of first-place votes (higher is better, as tiebreaker)
//   3. alphabetical order of apelido (final tiebreaker)
// PURO E TESTÁVEL — sem chamada de modelo
function agregarRankings(revisoes) {
  // Collect all apelidos from all rankings
  const apelidos = new Set();
  for (const revisao of revisoes) {
    for (const apelido of revisao.ranking) {
      apelidos.add(apelido);
    }
  }

  // Calculate metrics for each apelido
  const metricas = {};
  for (const apelido of apelidos) {
    let somaPositoes = 0;
    let contagem = 0;
    let primeirosPor = 0;

    for (const revisao of revisoes) {
      const posicao = revisao.ranking.indexOf(apelido);
      if (posicao >= 0) {
        somaPositoes += posicao;
        contagem++;
        if (posicao === 0) {
          primeirosPor++;
        }
      }
    }

    const media = contagem > 0 ? somaPositoes / contagem : Infinity;
    metricas[apelido] = {
      media,
      primeirosPor,
      apelido
    };
  }

  // Sort by: média (asc), primeiros-por (desc), apelido (asc)
  const ranking = Array.from(apelidos).sort((a, b) => {
    const metA = metricas[a];
    const metB = metricas[b];

    if (metA.media !== metB.media) {
      return metA.media - metB.media;
    }

    if (metA.primeirosPor !== metB.primeirosPor) {
      return metB.primeirosPor - metA.primeirosPor;
    }

    return a.localeCompare(b);
  });

  return ranking;
}

// Validates a sintese JSON against schema
function validarSintese(sintese) {
  if (typeof sintese !== 'object' || sintese === null) {
    return { valido: false, erro: 'sintese não é um objeto JSON' };
  }

  if (typeof sintese.decisao_recomendada !== 'string') {
    return { valido: false, erro: 'campo decisao_recomendada deve ser string' };
  }

  if (!Array.isArray(sintese.fundamentos)) {
    return { valido: false, erro: 'campo fundamentos deve ser array' };
  }

  if (!Array.isArray(sintese.divergencias_nao_resolvidas)) {
    return { valido: false, erro: 'campo divergencias_nao_resolvidas deve ser array' };
  }

  if (!Array.isArray(sintese.ranking_agregado)) {
    return { valido: false, erro: 'campo ranking_agregado deve ser array' };
  }

  return { valido: true };
}

// Executes revisao collection from all linked members with anonymization
function executarRevisao(args) {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  // First, check that pareceres phase is complete
  const resultConferir = spawnSync('node', [process.argv[1], 'conferir', '--fase', 'pareceres'], {
    cwd: RAIZ,
    encoding: 'utf8'
  });

  if (resultConferir.status !== 0) {
    console.error('Erro: fase pareceres não foi completada com sucesso');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  let membrosLigados = estado.membros_ligados || [];

  // Filter by --membro if specified
  membrosLigados = filtrarMembros(membrosLigados, args && args.membro);

  const membros = resolverMembros();
  const membrosMap = {};
  membros.forEach(m => {
    membrosMap[m.nome] = m;
  });

  // Create fase2 directory
  const dirFase2 = path.join(dirRodada, 'fase2');
  fs.mkdirSync(dirFase2, { recursive: true });

  // Read all pareceres and create anonymization map
  const pareceres = {};
  const parecerArquivos = [];

  for (const nomeMembro of membrosLigados) {
    const caminhoSaida = path.join(dirRodada, `parecer-${nomeMembro}.json`);
    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    const parecer = parseJsonDeMembro(conteudo);
    pareceres[nomeMembro] = parecer;
    parecerArquivos.push(nomeMembro);
  }

  // Shuffle pareceres and create anonymization map
  // Fisher-Yates shuffle
  for (let i = parecerArquivos.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [parecerArquivos[i], parecerArquivos[j]] = [parecerArquivos[j], parecerArquivos[i]];
  }

  // Create mapa-anonimato.json (internal, not distributed — store in dirRodada, NOT in dirFase2)
  const mapaAnonimato = {};
  const apelidos = [];
  for (let i = 0; i < parecerArquivos.length; i++) {
    const nomeMembro = parecerArquivos[i];
    const apelido = `membro-${String.fromCharCode(65 + i)}`; // membro-A, membro-B, membro-C, ...
    mapaAnonimato[nomeMembro] = apelido;
    apelidos.push(apelido);
  }

  const arquivoMapaAnonimato = path.join(dirRodada, 'mapa-anonimato.json');
  fs.writeFileSync(arquivoMapaAnonimato, JSON.stringify(mapaAnonimato, null, 2) + '\n', 'utf8');

  let temErro = false;
  const erros = [];

  // Execute each linked member's revisor command
  for (const nomeMembro of membrosLigados) {
    const membro = membrosMap[nomeMembro];
    if (!membro) {
      console.error(`Erro: membro ${nomeMembro} não encontrado em config`);
      process.exit(1);
    }

    // Create prompt with pareceres from OTHERS, anonymized
    const pareceresDosOutros = [];
    for (const outroMembro of membrosLigados) {
      if (outroMembro !== nomeMembro) {
        const apelido = mapaAnonimato[outroMembro];
        const parecer = pareceres[outroMembro];
        pareceresDosOutros.push({
          apelido,
          posicao: parecer.posicao,
          argumentos: parecer.argumentos,
          objecoes: parecer.objecoes,
          riscos: parecer.riscos
        });
      }
    }

    // Create pacote-prompt for this member
    const pacotePrompt = {
      instrucao: 'Você está revisando pareceres de colegas sobre uma decisão. Cada parecer é identificado por um apelido (membro-A, membro-B, etc.). Sua tarefa: ranquear os pareceres do melhor para o pior (sem empates) e oferecer uma crítica concisa para cada um. Responda SOMENTE com um objeto JSON valido, sem cerca de codigo: {"ranking": ["membro-A", "membro-B"], "criticas": {"membro-A": "...", "membro-B": "..."}} — o ranking cobre TODOS os apelidos recebidos.',
      pareceres: pareceresDosOutros
    };

    const caminhoPromptFase2 = path.join(dirFase2, `pacote-prompt-${nomeMembro}.json`);
    fs.writeFileSync(caminhoPromptFase2, JSON.stringify(pacotePrompt, null, 2) + '\n', 'utf8');

    const caminhoSaidaFase2 = path.join(dirFase2, `revisao-${nomeMembro}.json`);

    // Replace placeholders in command — envolver caminhos em aspas para suportar espaços
    // Cuidado: se cmd JÁ tem "{prompt}" entre aspas (ex.: "{prompt}"), não duplicar
    let cmd = membro.cmd;
    if (cmd.includes('"{prompt}"')) {
      // Já tem aspas: substituir o padrão "{prompt}" literalmente
      cmd = cmd.replace('"{prompt}"', `"${caminhoPromptFase2}"`);
    } else {
      // Sem aspas: envolver o caminho
      cmd = cmd.replace('{prompt}', `"${caminhoPromptFase2}"`);
    }

    if (cmd.includes('"{saida}"')) {
      cmd = cmd.replace('"{saida}"', `"${caminhoSaidaFase2}"`);
    } else {
      cmd = cmd.replace('{saida}', `"${caminhoSaidaFase2}"`);
    }

    const isWindows = process.platform === 'win32';
    const spawnArgs = isWindows
      ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
      : ['sh', ['-c', cmd]];

    // Execute command
    const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
      cwd: RAIZ,
      encoding: 'utf8',
      windowsVerbatimArguments: isWindows,
      timeout: TIMEOUT_MEMBRO_MS
    });

    if (resultado.error) {
      temErro = true;
      erros.push(`${nomeMembro}: timeout ou erro de execução`);
      continue;
    }

    if (resultado.status !== 0) {
      temErro = true;
      erros.push(`${nomeMembro}: processo saiu com exit ${resultado.status}`);
      continue;
    }

    // Check that output file was created and is not empty
    if (!fs.existsSync(caminhoSaidaFase2)) {
      temErro = true;
      erros.push(`${nomeMembro}: arquivo de saída não foi criado`);
      continue;
    }

    const conteudo = fs.readFileSync(caminhoSaidaFase2, 'utf8');
    if (!conteudo || conteudo.trim().length === 0) {
      temErro = true;
      erros.push(`${nomeMembro}: saída vazia`);
      continue;
    }
  }

  if (temErro) {
    erros.forEach(e => console.error(`  ${e}`));
    process.exit(1);
  }

  console.log(`Revisões coletadas de ${membrosLigados.length} membros`);
  process.exit(0);
}

// Validates that all revisao files in current rodada fase2 are valid
function conferirFaseRevisao() {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  const dirFase2 = path.join(dirRodada, 'fase2');
  if (!fs.existsSync(dirFase2)) {
    console.error('Erro: diretório fase2 não encontrado');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  const membrosLigados = estado.membros_ligados || [];

  // Expected number of pareceres for each member: N-1 (all except their own)
  const numeroPareceres = membrosLigados.length - 1;

  let temErro = false;
  const erros = [];

  // Check each linked member's revisao file
  for (const nomeMembro of membrosLigados) {
    const caminhoSaida = path.join(dirFase2, `revisao-${nomeMembro}.json`);

    // Check file exists
    if (!fs.existsSync(caminhoSaida)) {
      temErro = true;
      erros.push(`${nomeMembro}: revisao não encontrada`);
      continue;
    }

    // Check file is not empty
    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    if (!conteudo || conteudo.trim().length === 0) {
      temErro = true;
      erros.push(`${nomeMembro}: revisao vazia`);
      continue;
    }

    // Try to parse JSON
    let revisao;
    try {
      revisao = parseJsonDeMembro(conteudo);
    } catch (e) {
      temErro = true;
      erros.push(`${nomeMembro}: JSON inválido (${e.message})`);
      continue;
    }

    // Validate schema with expected number of pareceres
    const validacao = validarRevisao(revisao, numeroPareceres);
    if (!validacao.valido) {
      temErro = true;
      erros.push(`${nomeMembro}: ${validacao.erro}`);
      continue;
    }
  }

  if (temErro) {
    // Increment attempt counter
    const { shouldAbandon } = incrementarTentativaFase(estado, dirRodada, 'revisao');

    // Print errors
    erros.forEach(e => console.error(`Revisão inválida: ${e}`));

    // If ABANDONA, print that too
    if (shouldAbandon) {
      console.error('Erro: terceira reprovação consecutiva na fase revisao — rodada abandona');
    }

    process.exit(1);
  }

  // Success — reset counter and mark phase as ok
  zerarTentativaFase(estado, dirRodada, 'revisao');

  // Mark phase as complete
  estado.fases.revisao.status = 'ok';
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + '\n', 'utf8');

  process.exit(0);
}

// Identifies divergencies from pareceres and reviewer disagreement
// Input: mapaAnonimato (apelido -> name), pareceres (name -> parecer), revisoes (array of revisao objects)
// Output: array of divergency descriptions
function identificarDivergencias(mapaAnonimato, pareceres, revisoes) {
  const divergencias = [];

  // Collect all objeções from pareceres
  const todasObjecoes = [];
  for (const nomeMembro in pareceres) {
    const parecer = pareceres[nomeMembro];
    if (Array.isArray(parecer.objecoes)) {
      for (const objecao of parecer.objecoes) {
        todasObjecoes.push(objecao);
      }
    }
  }

  if (todasObjecoes.length > 0) {
    divergencias.push(`Objeções levantadas: ${todasObjecoes.length} total`);
  }

  // Add divergencies if reviewers disagree on ranking (not all identical)
  // Check if any two reviewers have different rankings
  if (revisoes.length > 1) {
    const primeiroRanking = JSON.stringify(revisoes[0].ranking);
    let temDissenso = false;
    for (let i = 1; i < revisoes.length; i++) {
      if (JSON.stringify(revisoes[i].ranking) !== primeiroRanking) {
        temDissenso = true;
        break;
      }
    }
    if (temDissenso) {
      divergencias.push(`Ranking com divergência: revisores não concordam na ordem`);
    }
  }

  return divergencias;
}

// Validates that sintese.json exists and is valid
function conferirFaseSintese() {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));

  const caminhoSintese = path.join(dirRodada, 'sintese.json');

  // Check file exists
  if (!fs.existsSync(caminhoSintese)) {
    // Increment attempt counter
    incrementarTentativaFase(estado, dirRodada, 'sintese');
    console.error('Parecer inválido: sintese.json não encontrado');
    process.exit(1);
  }

  // Check file is not empty
  const conteudo = fs.readFileSync(caminhoSintese, 'utf8');
  if (!conteudo || conteudo.trim().length === 0) {
    // Increment attempt counter
    incrementarTentativaFase(estado, dirRodada, 'sintese');
    console.error('Parecer inválido: sintese.json vazio');
    process.exit(1);
  }

  // Try to parse JSON
  let sintese;
  try {
    sintese = parseJsonDeMembro(conteudo);
  } catch (e) {
    // Increment attempt counter
    incrementarTentativaFase(estado, dirRodada, 'sintese');
    console.error(`Parecer inválido: sintese.json JSON inválido (${e.message})`);
    process.exit(1);
  }

  // Validate schema
  const validacao = validarSintese(sintese);
  if (!validacao.valido) {
    // Increment attempt counter
    incrementarTentativaFase(estado, dirRodada, 'sintese');
    console.error(`Parecer inválido: ${validacao.erro}`);
    process.exit(1);
  }

  // Check for divergencias_nao_resolvidas or unanime flag
  const temDivergencias = Array.isArray(sintese.divergencias_nao_resolvidas)
    && sintese.divergencias_nao_resolvidas.length > 0;
  const temUnanime = sintese.unanime === true;

  if (!temDivergencias && !temUnanime) {
    // Increment attempt counter
    incrementarTentativaFase(estado, dirRodada, 'sintese');
    console.error('Parecer inválido: síntese sem divergências não resolvidas exige unanime: true registrado');
    process.exit(1);
  }

  // Success — reset counter and mark phase as ok
  zerarTentativaFase(estado, dirRodada, 'sintese');

  // Mark phase as complete
  estado.fases.sintese.status = 'ok';
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + '\n', 'utf8');

  process.exit(0);
}

// Executes sintese creation and persistence
function executarSintetizar(args) {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  // First, validate that revisao phase is complete
  const resultConferir = spawnSync('node', [process.argv[1], 'conferir', '--fase', 'revisao'], {
    cwd: RAIZ,
    encoding: 'utf8'
  });

  if (resultConferir.status !== 0) {
    console.error('Erro: fase revisao não foi completada com sucesso');
    process.exit(1);
  }

  // Load estado
  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  const membrosLigados = estado.membros_ligados || [];

  // Load mapa-anonimato
  const arquivoMapaAnonimato = path.join(dirRodada, 'mapa-anonimato.json');
  const mapaAnonimato = JSON.parse(fs.readFileSync(arquivoMapaAnonimato, 'utf8'));

  // Load all pareceres
  const pareceres = {};
  for (const nomeMembro of membrosLigados) {
    const caminhoSaida = path.join(dirRodada, `parecer-${nomeMembro}.json`);
    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    pareceres[nomeMembro] = parseJsonDeMembro(conteudo);
  }

  // Load all revisoes
  const dirFase2 = path.join(dirRodada, 'fase2');
  const revisoes = [];
  for (const nomeMembro of membrosLigados) {
    const caminhoRevisao = path.join(dirFase2, `revisao-${nomeMembro}.json`);
    const conteudo = fs.readFileSync(caminhoRevisao, 'utf8');
    revisoes.push(parseJsonDeMembro(conteudo));
  }

  // Aggregate rankings
  const rankingAgregado = agregarRankings(revisoes);

  // Desanonymize ranking — mapa é apelido -> nomeMembro, precisamos do reverso
  const mapaReverso = {};
  for (const nomeMembro in mapaAnonimato) {
    const apelido = mapaAnonimato[nomeMembro];
    mapaReverso[apelido] = nomeMembro;
  }

  const rankingAgregadoDesanon = rankingAgregado.map(apelido => mapaReverso[apelido]);

  // Identify divergencies
  const divergencias = identificarDivergencias(mapaAnonimato, pareceres, revisoes);

  // Get top-ranked parecer for decision recommendation
  const topApelido = rankingAgregado[0];
  const topNomeMembro = mapaReverso[topApelido];
  const topParecer = pareceres[topNomeMembro];

  // Validate divergencies — consenso sem divergências só com --unanime explícito
  const temUnanimeFlag = args.unanime === true;
  if (divergencias.length === 0 && !temUnanimeFlag) {
    console.error('Erro: síntese sem divergências não resolvidas exige --unanime explícito');
    process.exit(1);
  }

  // Create sintese.json
  const sintese = {
    decisao_recomendada: topParecer.posicao,
    fundamentos: topParecer.argumentos || [],
    divergencias_nao_resolvidas: divergencias,
    ranking_agregado: rankingAgregadoDesanon
  };

  // Add unanime flag if used
  if (temUnanimeFlag) {
    sintese.unanime = true;
  }

  // Validate sintese
  const validacao = validarSintese(sintese);
  if (!validacao.valido) {
    console.error(`Erro: síntese inválida: ${validacao.erro}`);
    process.exit(1);
  }

  // Write sintese.json
  const arquivoSintese = path.join(dirRodada, 'sintese.json');
  fs.writeFileSync(arquivoSintese, JSON.stringify(sintese, null, 2) + '\n', 'utf8');

  console.log(`Síntese gravada em ${arquivoSintese}`);
  process.exit(0);
}

// Parses command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].slice(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        parsed[key] = args[i + 1];
        i++;
      } else {
        parsed[key] = true;
      }
    }
  }

  return parsed;
}

/**
 * Adaptador para Codex.
 * Executa: codex exec -s read-only --skip-git-repo-check "<prompt>"
 * stdin: fechado (spawn com stdio: ['ignore', ...])
 * Lê stdout, extrai JSON do parecer, valida, escreve em <saida>.
 * Falha: exit !== 0 SEM escrever <saida>
 */
function adaptadorCodex() {
  const args = process.argv.slice(2);
  const idx = args.indexOf('adaptador-codex');
  if (idx < 0) return;

  const prompt = args[idx + 1];
  const saida = args[idx + 2];

  if (!prompt || !saida) {
    console.error('adaptador-codex: prompt e saida obrigatórios');
    process.exit(1);
  }

  // {prompt} é o CAMINHO do arquivo; o CLI recebe o CONTEÚDO via stdin —
  // passar por argumento quebrava com aspas/quebras de linha no cmd.exe e
  // mandava o path como pergunta (achado da T9). stdin fechado após a escrita
  // também evita o travamento conhecido do codex exec com stdin aberto.
  let conteudoPrompt;
  try {
    conteudoPrompt = fs.readFileSync(prompt, 'utf8');
  } catch (e) {
    console.error(`adaptador-codex: não leu o prompt: ${e.message}`);
    process.exit(1);
  }

  const cmd = 'codex exec -s read-only --skip-git-repo-check';
  const isWindows = process.platform === 'win32';
  const spawnArgs = isWindows
    ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
    : ['sh', ['-c', cmd]];

  const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
    encoding: 'utf8',
    input: conteudoPrompt,
    windowsVerbatimArguments: isWindows,
    timeout: TIMEOUT_MEMBRO_MS,
  });

  if (resultado.status !== 0) {
    console.error(`adaptador-codex: exit ${resultado.status}`);
    process.exit(1);
  }

  const stdout = resultado.stdout || '';
  if (!stdout) {
    console.error('adaptador-codex: saída vazia do CLI');
    process.exit(1);
  }

  // Extrai JSON (tolerando ```json...```)
  let parecer;
  try {
    const match = stdout.match(/```json\s*([\s\S]*?)\s*```/) || stdout.match(/({[\s\S]*})/);
    const json = match ? match[1] : stdout;
    parecer = JSON.parse(json);
  } catch (e) {
    console.error(`adaptador-codex: JSON inválido: ${e.message}`);
    process.exit(1);
  }

  // A forma NÃO se valida aqui: na fase 1 a saída é parecer, na fase 2 é
  // revisão — quem valida o schema é o portão da fase (conferir --fase).
  fs.writeFileSync(saida, JSON.stringify(parecer, null, 2) + '\n', 'utf8');
  process.exit(0);
}

/**
 * Adaptador para Gemini.
 * Executa: gemini -m gemini-3.7-flash -p "<prompt>" --skip-trust --approval-mode plan
 * stdin: fechado
 * GEMINI_API_KEY deve estar no ambiente (ausente = exit !== 0 com mensagem)
 * Lê stdout, extrai JSON, valida, escreve em <saida>.
 * Falha: exit !== 0 SEM escrever <saida>
 */
function adaptadorGemini() {
  const args = process.argv.slice(2);
  const idx = args.indexOf('adaptador-gemini');
  if (idx < 0) return;

  const prompt = args[idx + 1];
  const saida = args[idx + 2];

  if (!prompt || !saida) {
    console.error('adaptador-gemini: prompt e saida obrigatórios');
    process.exit(1);
  }

  if (!process.env.GEMINI_API_KEY) {
    console.error('adaptador-gemini: GEMINI_API_KEY não definida no ambiente — gemini CLI exige credencial');
    process.exit(1);
  }

  // {prompt} é o CAMINHO do arquivo; o conteúdo vai via stdin (o -p com o
  // path mandava o caminho como pergunta — achado da T9). Piped stdin roda
  // o gemini em modo headless; o -m fixa o melhor modelo da chave.
  let conteudoPrompt;
  try {
    conteudoPrompt = fs.readFileSync(prompt, 'utf8');
  } catch (e) {
    console.error(`adaptador-gemini: não leu o prompt: ${e.message}`);
    process.exit(1);
  }

  const cmd = 'gemini -m gemini-3.7-flash --skip-trust --approval-mode plan';
  const isWindows = process.platform === 'win32';
  const spawnArgs = isWindows
    ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
    : ['sh', ['-c', cmd]];

  const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
    encoding: 'utf8',
    input: conteudoPrompt,
    env: { ...process.env },
    windowsVerbatimArguments: isWindows,
    timeout: TIMEOUT_MEMBRO_MS,
  });

  if (resultado.status !== 0) {
    console.error(`adaptador-gemini: exit ${resultado.status}`);
    process.exit(1);
  }

  const stdout = resultado.stdout || '';
  if (!stdout) {
    console.error('adaptador-gemini: saída vazia do CLI');
    process.exit(1);
  }

  // Extrai JSON (tolerando ```json...```)
  let parecer;
  try {
    const match = stdout.match(/```json\s*([\s\S]*?)\s*```/) || stdout.match(/({[\s\S]*})/);
    const json = match ? match[1] : stdout;
    parecer = JSON.parse(json);
  } catch (e) {
    console.error(`adaptador-gemini: JSON inválido: ${e.message}`);
    process.exit(1);
  }

  // A forma NÃO se valida aqui: na fase 1 a saída é parecer, na fase 2 é
  // revisão — quem valida o schema é o portão da fase (conferir --fase).
  fs.writeFileSync(saida, JSON.stringify(parecer, null, 2) + '\n', 'utf8');
  process.exit(0);
}

// Main command handler
function main() {
  const args = parseArgs();
  const comando = process.argv[2];

  if (!comando) {
    console.error('Uso: conselho.cjs <abrir|revisar|sintetizar|conferir|adaptador-codex|adaptador-gemini> [opções]');
    process.exit(1);
  }

  try {
    if (comando === 'adaptador-codex') {
      adaptadorCodex();
      return;
    } else if (comando === 'adaptador-gemini') {
      adaptadorGemini();
      return;
    } else if (comando === 'abrir') {
      if (!args.questao) {
        console.error('Erro: --questao é obrigatório');
        process.exit(1);
      }

      // Resolve question path (absolute or relative to current directory)
      const caminhoQuestao = path.isAbsolute(args.questao)
        ? args.questao
        : path.join(process.cwd(), args.questao);

      validarQuestao(caminhoQuestao);
      const membros = resolverMembros();
      const membrosLigados = validarQuorum(membros);
      abrirRodada(caminhoQuestao, membrosLigados);
      process.exit(0);
    } else if (comando === 'pareceres') {
      executarPareceres(args);
    } else if (comando === 'revisar') {
      executarRevisao(args);
    } else if (comando === 'sintetizar') {
      executarSintetizar(args);
    } else if (comando === 'conferir') {
      if (args.fase === 'pareceres') {
        conferirFasePareceres();
      } else if (args.fase === 'revisao') {
        conferirFaseRevisao();
      } else if (args.fase === 'sintese') {
        conferirFaseSintese();
      } else {
        console.error('Comando conferir não implementado para esta fase');
        process.exit(1);
      }
    } else {
      console.error(`Comando desconhecido: ${comando}`);
      process.exit(1);
    }
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
