#!/usr/bin/env node
/**
 * Transporte de agente do rainforest para Codex CLI via `codex exec`.
 *
 * Lê agents/<agente>.md (corpo sem frontmatter e sem ponte), extrai model:,
 * monta comando Codex, executa com sandbox por `--escreve`, e devolve a saída
 * literal. Sandbox: `--escreve false` → `-s read-only`; true → `-s workspace-write`.
 *
 * O Codex NÃO grava em `.git` sob `workspace-write`, nem com `--add-dir` no
 * `.git` do repo ou no gitdir exato do worktree (medido em 2026-09-08: ACL DENY
 * nos SIDs do sandbox, `index.lock: Permission denied`). Por isso este script
 * não passa `--add-dir`, e o commit do que o Codex deixou é da ponte (agente
 * Claude), conforme o preâmbulo `<!-- ponte-codex -->`. Timeout default
 * 540000ms. Modelo mapeado por tabela em hooks/lib/config.cjs (codex-modelo-<model>).
 *
 * Suporta RFM_TEST=1 + CODEX_CMD para dublê de teste (não roda codex real).
 * Saída: stdout = última mensagem de Codex (arquivo -o) ou stdout dele se vazio;
 * stderr = linha `comando: <cmd>` para auditoria. Exit 0 = sucesso; exit ≠ 0 =
 * falha do Codex ou timeout (124). RFM_TEST exporta env.DESPACHAR_CODEX_CMD_REAL
 * para auditoria do comando montado.
 *
 * Uso: node despachar-codex.cjs --agente <nome> --worktree <dir> --escreve <true|false> --briefing-file <arquivo> [--timeout-ms <n>] [--saida <arquivo>]
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { rodarCli, valorSeguroParaShell } = require('../hooks/lib/cli-externo.cjs');
const { detectarSemCota, EXIT_SEM_COTA } = require('../hooks/lib/codex-cota.cjs');
const { resolverConfig } = require('../hooks/lib/config.cjs');

/**
 * Parse frontmatter de agente.
 * @param {string} conteudo
 * @returns {{frontmatter: string|null, corpo: string}}
 */
// Porta ÚNICA para os valores interpolados no comando de shell (D2, Issue
// #223): --worktree, --saida, modelo e esforço de config passam todos por aqui.
// A negação da chamada abaixo é o trecho que o plano inverte na catraca de
// mutação, e ele existe uma vez só — cinco `if` copiados fariam o `--de` casar
// cinco vezes e a catraca recusar por ambiguidade (exit 4), e uma mutação num
// deles deixaria os outros quatro de pé, verde por motivo errado.
function recusaValorInseguro(nome, valor) {
  if (!valorSeguroParaShell(valor)) {
    console.error(`valor invalido: ${nome}`);
    return true;
  }
  return false;
}

function extrairFrontmatter(conteudo) {
  const match = conteudo.match(/^---\n([\s\S]*?)\n---/);
  if (!match) {
    return { frontmatter: null, corpo: conteudo };
  }
  const corpo = conteudo.substring(match[0].length);
  return { frontmatter: match[1], corpo };
}

/**
 * Extrai valor de chave do frontmatter.
 * @param {string} frontmatter
 * @param {string} chave (ex: "model")
 * @returns {string|null}
 */
function extrairChaveDoFrontmatter(frontmatter, chave) {
  if (!frontmatter) return null;
  const regex = new RegExp(`^${chave}:\\s*(.+)$`, 'm');
  const match = frontmatter.match(regex);
  return match ? match[1].trim() : null;
}

/**
 * Remove bloco entre <!-- ponte-codex --> e <!-- /ponte-codex --> (inclusive).
 * @param {string} corpo
 * @returns {string}
 */
function removerBlocoPonte(corpo) {
  return corpo.replace(/<!-- ponte-codex -->[\s\S]*?<!-- \/ponte-codex -->\n*/g, '');
}

/**
 * Resolve diretório raiz do plugin (parent do scripts/).
 * @returns {string}
 */
function resolverRaizPlugin() {
  return path.resolve(__dirname, '..');
}

/**
 * Processa argumentos CLI.
 * @returns {object|null}
 */
// Lista fechada: flag fora dela e recusada ANTES de qualquer efeito. E o oposto
// do `estado.cjs`, que le cada flag por `indexOf` e ignora o resto — foi assim
// que um `--dry-run` inventado aprovou um design em 2026-09-08 (Issue #218).
const FLAGS_ACEITAS = new Set(['agente', 'worktree', 'escreve', 'briefing-file', 'timeout-ms', 'saida']);

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
      if (!FLAGS_ACEITAS.has(key)) {
        console.error(`flag desconhecida: ${arg}`);
        process.exit(1);
      }
      const valor = args[i + 1];
      if (valor === undefined || valor.startsWith('--')) {
        console.error(`erro: ${arg} exige um valor`);
        process.exit(1);
      }
      opts[key] = valor;
      i++;
    } else {
      console.error(`flag desconhecida: ${arg}`);
      process.exit(1);
    }
  }

  return opts;
}

/**
 * Valida argumentos obrigatórios.
 * @returns {boolean}
 */
function validarArgs(opts) {
  if (!opts.agente) {
    console.error('erro: --agente obrigatória');
    return false;
  }
  if (!opts.worktree) {
    console.error('erro: --worktree obrigatória');
    return false;
  }
  if (opts.escreve === undefined) {
    console.error('erro: --escreve obrigatória (true ou false)');
    return false;
  }
  if (!opts['briefing-file']) {
    console.error('erro: --briefing-file obrigatória');
    return false;
  }

  // Normaliza --worktree com path.resolve antes de validar (remove separador final)
  opts.worktree = path.resolve(opts.worktree);

  // Valida segurança dos valores interpolados ANTES de qualquer outro teste
  if (recusaValorInseguro('--worktree', opts.worktree)) return false;
  if (opts.saida && recusaValorInseguro('--saida', opts.saida)) return false;

  if (!fs.existsSync(opts.worktree)) {
    console.error(`erro: worktree não existe: ${opts.worktree}`);
    return false;
  }
  if (!fs.existsSync(opts['briefing-file'])) {
    console.error(`erro: briefing-file não existe: ${opts['briefing-file']}`);
    return false;
  }
  return true;
}

/**
 * Parse --escreve string para boolean.
 */
function parseEscreve(valor) {
  if (valor === 'true') return true;
  if (valor === 'false') return false;
  return null;
}

// Caminho do `-o` temporário ainda não apagado, para o catch de main() limpar
// quando uma exceção escapa depois de ele ter sido criado.
let temporarioPendente = null;

/**
 * Main.
 */
async function main() {
  const opts = processarArgs();

  if (opts.help) {
    console.log(`
Despacha agente do rainforest para Codex CLI.

Uso:
  node despachar-codex.cjs \\
    --agente <nome> \\
    --worktree <dir> \\
    --escreve <true|false> \\
    --briefing-file <arquivo> \\
    [--timeout-ms <ms>] \\
    [--saida <arquivo>] \\
    [--help]

Obrigatórias:
  --agente <nome>           Nome do agente (ex: revisor, executor)
  --worktree <dir>          Diretório do worktree
  --escreve <true|false>    Sandbox: true → workspace-write, false → read-only
  --briefing-file <arquivo> Caminho do briefing (stdin do Codex)

Opcionais:
  --timeout-ms <ms>         Timeout em ms (default: 540000)
  --saida <arquivo>         Arquivo de saída Codex (default: tmp)
  --help                    Esta ajuda
    `);
    process.exit(0);
  }

  if (!validarArgs(opts)) {
    process.exit(1);
  }

  // Nome simples: `--agente ../x` ou `sub/x` sairia de agents/ e injetaria
  // qualquer arquivo no prompt (achado do revisor em Codex, 2026-09-08).
  if (!/^[a-z0-9][a-z0-9-]*$/i.test(opts.agente)) {
    console.error(`erro: --agente deve ser um nome simples (letras, dígitos, hífen): ${opts.agente}`);
    process.exit(1);
  }

  const raizPlugin = resolverRaizPlugin();
  const agentePath = path.join(raizPlugin, 'agents', `${opts.agente}.md`);
  const escreve = parseEscreve(opts.escreve);

  if (escreve === null) {
    console.error('erro: --escreve deve ser "true" ou "false"');
    process.exit(1);
  }

  // Lê agente
  if (!fs.existsSync(agentePath)) {
    console.error(`erro: agente não encontrado: ${agentePath}`);
    process.exit(1);
  }

  let conteudoAgente;
  try {
    conteudoAgente = fs.readFileSync(agentePath, 'utf8');
  } catch (e) {
    console.error(`erro: não consegui ler agente: ${e.message}`);
    process.exit(1);
  }

  // Extrai frontmatter e corpo
  const { frontmatter, corpo: corpoComPonte } = extrairFrontmatter(conteudoAgente);

  // Extrai model:
  const model = extrairChaveDoFrontmatter(frontmatter, 'model');

  // Remove bloco de ponte
  const corpo = removerBlocoPonte(corpoComPonte);

  // Lê briefing
  let briefing;
  try {
    briefing = fs.readFileSync(opts['briefing-file'], 'utf8');
  } catch (e) {
    console.error(`erro: não consegui ler briefing: ${e.message}`);
    process.exit(1);
  }

  // Entrada = corpo + separador + briefing
  const entrada = corpo + '\n\n---\n\n' + briefing;

  // Resolve sandbox
  const sandbox = escreve ? 'workspace-write' : 'read-only';

  // Resolve arquivo de saída. O temporario e nosso e some no fim; o que veio
  // por --saida e do chamador e fica.
  let saidaArquivo = opts.saida;
  const saidaTemporaria = !saidaArquivo;
  if (saidaTemporaria) {
    saidaArquivo = path.join(os.tmpdir(), `despachar-codex-${process.pid}-${Date.now()}.txt`);
    temporarioPendente = saidaArquivo;

    // Valida o arquivo temporário gerado
    if (recusaValorInseguro('--saida', saidaArquivo)) process.exit(1);
  }
  // Ler e apagar são falhas independentes: um `unlink` que falha (arquivo
  // preso por antivírus/indexador) não pode jogar fora o texto já lido — foi o
  // aviso 4 do revisar de 2026-09-08.
  const lerSaida = () => {
    if (!fs.existsSync(saidaArquivo)) return null;
    let texto = null;
    try {
      texto = fs.readFileSync(saidaArquivo, 'utf8');
    } catch {
      texto = null;
    }
    if (saidaTemporaria) {
      try { fs.unlinkSync(saidaArquivo); temporarioPendente = null; } catch { /* fica para o catch de main */ }
    }
    return texto;
  };

  // Resolve modelo e valida valores
  let modeloResolvido = null;
  let esforcoResolvido = null;
  if (model) {
    const config = resolverConfig({ projeto: opts.worktree });
    const chaveModelo = `codex-modelo-${model}`;
    const modeloConfig = config.valores[chaveModelo];

    if (modeloConfig && typeof modeloConfig === 'object' && modeloConfig.modelo) {
      modeloResolvido = modeloConfig.modelo;
      esforcoResolvido = modeloConfig.esforco || null;

      // Valida modelo e esforço da config
      if (recusaValorInseguro('modelo de config', modeloResolvido)) process.exit(1);
      if (esforcoResolvido && recusaValorInseguro('esforço de config', esforcoResolvido)) process.exit(1);
    }
  }

  // Monta comando base
  let cmd = `codex exec -s ${sandbox} --skip-git-repo-check -C "${opts.worktree}" -c approval_policy="never" -o "${saidaArquivo}"`;

  // Sem `--add-dir` de propósito: o sandbox do Codex nega escrita em `.git`
  // mesmo com o diretório declarado (ver cabeçalho). Quem commita é a ponte.

  // Adiciona modelo se resolvido
  if (modeloResolvido) {
    cmd += ` -m "${modeloResolvido}"`;
    if (esforcoResolvido) {
      cmd += ` -c model_reasoning_effort="${esforcoResolvido}"`;
    }
  }

  // Suporte para RFM_TEST
  let env = process.env;
  let cmdReal = cmd;
  if (process.env.RFM_TEST === '1' && process.env.CODEX_CMD) {
    cmd = process.env.CODEX_CMD;
    env = { ...process.env, DESPACHAR_CODEX_CMD_REAL: cmdReal };
  }

  // Resolve timeout
  const timeoutMs = opts['timeout-ms'] ? parseInt(opts['timeout-ms'], 10) : 540000;
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    console.error('erro: --timeout-ms deve ser um número positivo');
    process.exit(1);
  }

  // Executa
  const resultado = rodarCli({ cmd, entrada, timeoutMs, env });

  // Escreve comando no stderr para auditoria
  console.error(`comando: ${cmdReal}`);

  // Trata resultado
  if (resultado.status === null) {
    // Timeout
    console.error(`timeout apos ${timeoutMs} ms`);
    // Conteúdo parcial de -o, se o Codex chegou a gravar algo
    const parcial = lerSaida();
    if (parcial) console.log(parcial);
    process.exit(124);
  }

  // Sem cota (D5): passageiro, legível, exit 75. A linha própria vem antes do
  // stderr bruto do Codex, que enterra a causa atrás do banner. SÓ com exit ≠ 0:
  // com exit 0 o texto é resposta do agente, e um revisor que cite "usage
  // limit" num parecer legítimo não pode virar falso "sem cota" (revisar de
  // 2026-09-08). Este script não usa `--json`; o caso do evento fica no transferir.
  const semCota = resultado.status !== 0
    ? detectarSemCota(`${resultado.stderr || ''}\n${resultado.stdout || ''}`)
    : null;
  if (semCota) {
    console.error(`codex sem cota: ${semCota}`);
    if (resultado.stderr) console.error(resultado.stderr);
    lerSaida();
    process.exit(EXIT_SEM_COTA);
  }

  if (resultado.status !== 0) {
    // Erro do Codex
    if (resultado.stderr) {
      console.error(resultado.stderr);
    }
    lerSaida();
    process.exit(resultado.status || 1);
  }

  // Sucesso: conteúdo de -o se existir e não estiver vazio, senão stdout do Codex
  const saida = lerSaida();
  console.log(saida ? saida : resultado.stdout);
  process.exit(0);
}

main().catch(e => {
  console.error(`erro: ${e.message}`);
  if (temporarioPendente) {
    try { fs.unlinkSync(temporarioPendente); } catch { /* já sumiu ou está preso */ }
  }
  process.exit(1);
});
