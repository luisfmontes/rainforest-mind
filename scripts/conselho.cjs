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
    } else if (comando === 'revisar') {
      console.error('Comando revisar não implementado nesta tarefa');
      process.exit(1);
    } else if (comando === 'sintetizar') {
      console.error('Comando sintetizar não implementado nesta tarefa');
      process.exit(1);
    } else if (comando === 'conferir') {
      console.error('Comando conferir não implementado nesta tarefa');
      process.exit(1);
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
