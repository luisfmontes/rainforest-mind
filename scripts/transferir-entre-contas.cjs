#!/usr/bin/env node
/**
 * Transferência de sessão Claude Code entre contas (trabalho ↔ pessoal).
 *
 * Copia <id>.jsonl (transcript) e a pasta <id>/ inteira para a outra conta.
 * Imprime a linha pronta para retomada: `cd "<cwd>" && claude --resume <id>`
 * (com `CLAUDE_CONFIG_DIR` quando destino é pessoal).
 *
 * Exit codes:
 *   0: sucesso
 *   1: erro de entrada (sem CLAUDE_CODE_SESSION_ID, CLAUDE_CONFIG_DIR desconhecido, etc)
 *   4: colisão no destino (exit 4 citando --forcar)
 *
 * Uso: node transferir-entre-contas.cjs [--para trabalho|pessoal] [--forcar]
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { homeDoUsuario, contaAtual, outraConta, dirConta, dentroDeProjetos } = require('../hooks/lib/contas-claude.cjs');

/**
 * Processa argumentos CLI.
 * @returns {object} opções parseadas
 */
const FLAGS_COM_VALOR = new Set(['para']);
const FLAGS_BOOLEANAS = new Set(['forcar']);

function processarArgs() {
  const args = process.argv.slice(2);
  const opts = {};

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--help') {
      return { help: true };
    }

    if (arg.startsWith('--')) {
      const key = arg.substring(2);

      if (FLAGS_COM_VALOR.has(key)) {
        const valor = args[i + 1];
        if (valor === undefined || valor.startsWith('--')) {
          console.error(`erro: ${arg} exige um valor`);
          process.exit(1);
        }
        opts[key] = valor;
        i++;
      } else if (FLAGS_BOOLEANAS.has(key)) {
        opts[key] = true;
      } else {
        console.error(`erro: flag desconhecida: ${arg}`);
        process.exit(1);
      }
    } else {
      console.error(`erro: argumento posicional não aceito: ${arg}`);
      process.exit(1);
    }
  }

  return opts;
}

/**
 * Main.
 */
async function main() {
  const opts = processarArgs();

  if (opts.help) {
    console.log(`
Transfere sessão Claude Code entre contas (trabalho e pessoal).

Uso:
  node transferir-entre-contas.cjs \\
    [--para trabalho|pessoal] \\
    [--forcar] \\
    [--help]

Opcionais:
  --para <trabalho|pessoal>  Conta destino (default: a outra)
  --forcar                   Sobrescreve se a sessão já existe no destino
  --help                     Esta ajuda
    `);
    process.exit(0);
  }

  // Resolve home
  const home = homeDoUsuario(process.env);

  // 1. Determina conta atual
  const contaAtualValue = contaAtual(process.env, home);
  if (contaAtualValue === null) {
    const configDir = process.env.CLAUDE_CONFIG_DIR || '';
    console.error(`erro: CLAUDE_CONFIG_DIR desconhecido: ${configDir}`);
    process.exit(1);
  }

  // 2. Determina conta destino
  let contaDestinoValue;
  if (opts.para) {
    if (opts.para !== 'trabalho' && opts.para !== 'pessoal') {
      console.error(`erro: --para deve ser 'trabalho' ou 'pessoal', veio '${opts.para}'`);
      process.exit(1);
    }
    if (opts.para === contaAtualValue) {
      console.error(`erro: destino não pode ser igual à conta atual (${contaAtualValue})`);
      process.exit(1);
    }
    contaDestinoValue = opts.para;
  } else {
    contaDestinoValue = outraConta(contaAtualValue);
  }

  // 3. Busca CLAUDE_CODE_SESSION_ID
  const sessionId = process.env.CLAUDE_CODE_SESSION_ID;
  if (!sessionId) {
    console.error('erro: CLAUDE_CODE_SESSION_ID não está definido');
    process.exit(1);
  }

  // 4. Busca transcript
  const dirContaAtualValue = dirConta(contaAtualValue, home);
  const projectsDir = path.join(dirContaAtualValue, 'projects');
  let transcriptPath = null;

  // Procura em <projectsDir>/*/<sessionId>.jsonl
  if (fs.existsSync(projectsDir)) {
    const subdirs = fs.readdirSync(projectsDir);
    for (const subdir of subdirs) {
      const candidate = path.join(projectsDir, subdir, `${sessionId}.jsonl`);
      if (fs.existsSync(candidate)) {
        transcriptPath = candidate;
        break;
      }
    }
  }

  if (!transcriptPath) {
    console.error(`erro: transcript ${sessionId}.jsonl não encontrado em ${projectsDir}`);
    process.exit(1);
  }

  // 5. Lê transcript e busca primeiro cwd
  let linhasParsadas = [];
  let cwd = null;

  try {
    const conteudo = fs.readFileSync(transcriptPath, 'utf8');
    const linhas = conteudo.trim().split('\n');

    for (const linha of linhas) {
      if (!linha.trim()) continue;

      let evento;
      try {
        evento = JSON.parse(linha);
      } catch {
        continue;
      }

      if (evento.cwd && !cwd) {
        cwd = evento.cwd;
      }
    }
  } catch (e) {
    console.error(`erro: não consegui ler transcript: ${e.message}`);
    process.exit(1);
  }

  if (!cwd) {
    console.error('erro: nenhuma linha do transcript tem campo "cwd"');
    process.exit(1);
  }

  // 6. Determina destinos de arquivo e pasta
  const slugProjeto = path.basename(path.dirname(transcriptPath));
  const dirContaDestinoValue = dirConta(contaDestinoValue, home);
  const projectsDirDestino = path.join(dirContaDestinoValue, 'projects');
  const destJsonl = path.join(projectsDirDestino, slugProjeto, `${sessionId}.jsonl`);
  const destIdDir = path.join(projectsDirDestino, slugProjeto, sessionId);
  const srcIdDir = path.join(path.dirname(transcriptPath), sessionId);

  // Cria diretório destino de projetos se não existir
  if (!fs.existsSync(projectsDirDestino)) {
    fs.mkdirSync(projectsDirDestino, { recursive: true });
  }

  // Cria diretório slug se não existir
  const slugDir = path.dirname(destJsonl);
  if (!fs.existsSync(slugDir)) {
    fs.mkdirSync(slugDir, { recursive: true });
  }

  // 7. Verifica colisão
  const existe = fs.existsSync(destJsonl);
  if (existe && !opts.forcar) {
    console.error(`erro: a sessão ${sessionId} já existe em ${contaDestinoValue}. Use --forcar para sobrescrever.`);
    process.exit(4);
  }

  // 8. Copia transcript
  try {
    fs.copyFileSync(transcriptPath, destJsonl);
  } catch (e) {
    console.error(`erro: não consegui copiar transcript: ${e.message}`);
    process.exit(1);
  }

  // 9. Copia pasta <id>/ se existir
  if (fs.existsSync(srcIdDir)) {
    try {
      // Se destIdDir existe, remove para fazer o override correto
      if (fs.existsSync(destIdDir)) {
        fs.rmSync(destIdDir, { recursive: true, force: true });
      }
      fs.cpSync(srcIdDir, destIdDir, { recursive: true });
    } catch (e) {
      console.error(`erro: não consegui copiar pasta ${sessionId}/: ${e.message}`);
      process.exit(1);
    }
  }

  // 10. Imprime resultado
  console.log(`cd "${cwd}"`);

  if (contaDestinoValue === 'pessoal') {
    const dirContaPessoal = dirConta('pessoal', home);
    console.log(`CLAUDE_CONFIG_DIR="${dirContaPessoal}" claude --resume ${sessionId}`);
  } else {
    console.log(`claude --resume ${sessionId}`);
  }

  // Mensagem de fechamento em stderr (D4)
  console.error('Feche a janela desta conta (a sessão foi copiada para a outra).');

  process.exit(0);
}

main().catch(e => {
  console.error(`erro: ${e.message}`);
  process.exit(1);
});
