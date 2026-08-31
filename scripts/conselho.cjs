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

// Raiz do projeto
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const DIR_CONSELHO = path.join(RAIZ, '.rainforest', 'conselho');
const ARQUIVO_MEMBROS = path.join(DIR_CONSELHO, 'membros.json');

const QUORUM_MINIMO = 3;

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
        cmd: 'node scripts/conselho.cjs adaptador-codex {prompt} {saida}',
        ligado: false,
      },
      {
        nome: 'gemini',
        cmd: 'node scripts/conselho.cjs adaptador-gemini {prompt} {saida}',
        ligado: false,
      },
    ]
  };
}

// Loads or creates membros.json
function resolverMembros() {
  fs.mkdirSync(DIR_CONSELHO, { recursive: true });

  if (!fs.existsSync(ARQUIVO_MEMBROS)) {
    const padrao = gerarMembrosDefault();
    fs.writeFileSync(ARQUIVO_MEMBROS, JSON.stringify(padrao, null, 2) + '\n', 'utf8');
    return padrao.membros;
  }

  const config = JSON.parse(fs.readFileSync(ARQUIVO_MEMBROS, 'utf8'));
  return config.membros || [];
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
    const conteudo = `${persona}\n\n## Questão\n\n${questao}`;
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
function executarPareceres() {
  const dirRodada = encontrarRodada();
  if (!dirRodada) {
    console.error('Erro: nenhuma rodada aberta encontrada');
    process.exit(1);
  }

  const estadoPath = path.join(dirRodada, 'estado.json');
  const estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
  const membrosLigados = estado.membros_ligados || [];

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

    // Replace placeholders in command
    const cmd = membro.cmd
      .replace('{prompt}', caminhoPrompt)
      .replace('{saida}', caminhoSaida);

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
      timeout: 30000  // 30 second timeout per member
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
      erros.push(`${nomeMembro}: parecer não encontrado`);
      continue;
    }

    // Check file is not empty
    const conteudo = fs.readFileSync(caminhoSaida, 'utf8');
    if (!conteudo || conteudo.trim().length === 0) {
      temErro = true;
      erros.push(`${nomeMembro}: parecer vazio`);
      continue;
    }

    // Try to parse JSON
    let parecer;
    try {
      parecer = JSON.parse(conteudo);
    } catch (e) {
      temErro = true;
      erros.push(`${nomeMembro}: JSON inválido (${e.message})`);
      continue;
    }

    // Validate schema
    const validacao = validarParecer(parecer);
    if (!validacao.valido) {
      temErro = true;
      erros.push(`${nomeMembro}: ${validacao.erro}`);
      continue;
    }
  }

  if (temErro) {
    erros.forEach(e => console.error(`Parecer inválido: ${e}`));
    process.exit(1);
  }

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

// Main command handler
function main() {
  const args = parseArgs();
  const comando = process.argv[2];

  if (!comando) {
    console.error('Uso: conselho.cjs <abrir|revisar|sintetizar|conferir> [opções]');
    process.exit(1);
  }

  try {
    if (comando === 'abrir') {
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
      executarPareceres();
    } else if (comando === 'revisar') {
      console.error('Comando revisar não implementado nesta tarefa');
      process.exit(1);
    } else if (comando === 'sintetizar') {
      console.error('Comando sintetizar não implementado nesta tarefa');
      process.exit(1);
    } else if (comando === 'conferir') {
      if (args.fase === 'pareceres') {
        conferirFasePareceres();
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
