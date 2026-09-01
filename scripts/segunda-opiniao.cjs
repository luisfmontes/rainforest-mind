#!/usr/bin/env node
/**
 * Segunda opinião: parecer de modelo de OUTRA família sobre um diff
 *
 * Interface:
 *   node scripts/segunda-opiniao.cjs --base <sha> --head <sha> --criterio <arquivo> [--modelo codex|gemini]
 *
 * Comportamento:
 * - Monta prompt com git diff <base>...<head> (três pontos), critério falsificável, commit-base
 * - Chama CLI externo por rodarCli, mandando prompt por stdin
 * - Saída: veredito (1 linha) na stdout + parecer completo (N linhas) na stderr
 * - Recusa (exit ≠ 0) se: falta --base/--head, diff vazio, veredito inválido
 * - Arbitra sempre: script aconselha, não manda
 *
 * Vocabulário de veredito (exatamente):
 * - "concordo" — diff atende ao critério
 * - "discordo" — diff não atende ao critério
 * Qualquer outra última linha = erro, exit ≠ 0
 *
 * Timeout configurável por TIMEOUT_SEGUNDA_OPINIAO_MS (default 300000ms = 5min, alinhado ao conselho).
 * Parecer preservado permite que tarefas posteriores (ex.: registro de discordância) capturem motivo da rejeição.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { rodarCli } = require('../hooks/lib/cli-externo.cjs');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

// Parse argumentos
const args = {};
const subcomando = process.argv[2]; // Pode ser um subcomando
let offsetArgs = 2;

// Verificar se o primeiro argumento é um subcomando
if (subcomando === 'registrar-divergencia') {
  // Processar subcomando
  offsetArgs = 3; // Começar após o subcomando
}

for (let i = offsetArgs; i < process.argv.length; i++) {
  if (process.argv[i].startsWith('--')) {
    const key = process.argv[i].substring(2);
    args[key] = process.argv[++i];
  }
}

const BASE = args.base;
const HEAD = args.head;
const CRITERIO_ARQUIVO = args.criterio;
const MODELO = args.modelo || 'codex';
const CLI_CMD_CUSTOM = args['cli-cmd']; // Para testes com fixtures


/**
 * Subcomando: registrar divergência com motivo
 *
 * Uso: node scripts/segunda-opiniao.cjs registrar-divergencia --veredito discordo --motivo "<texto>" --base <sha>
 *
 * D5: Quando veredito for "discordo" e a janela rejeitar, registra com motivo escrito.
 * Motivo vazio ou só whitespace = recusa (exit ≠ 0, nada gravado).
 *
 * Arquivo de log: <raiz-de-dados>/.logs/divergencias-segunda-opiniao.jsonl
 * Onde <raiz-de-dados> é resolvida por resolverRaiz (cadeia: RFM_ROOT → <projeto>/.rainforest → ~/.rainforest → repo plugin)
 * Cada linha é JSON: { timestamp, veredito, motivo, base, modelo }
 *
 * Recusa (exit ≠ 0) se não houver raiz de dados disponível.
 * Motivo vazio ou só whitespace também reprova (exit ≠ 0, nada gravado).
 */
function registrarDivergencia() {
  if (!args.veredito || !args.motivo || !args.base) {
    console.error('Erro: registrar-divergencia requer --veredito, --motivo e --base');
    process.exit(1);
  }

  // D5: Validar que motivo não é vazio ou só whitespace
  if (!args.motivo.trim()) {
    console.error('Erro: motivo vazio é recusado');
    process.exit(1);
  }

  // Resolver raiz de dados (em ordem: RFM_ROOT, <projeto>/.rainforest, ~/.rainforest, plugin)
  const { raiz, nivel, escopo } = resolverRaiz();

  if (!raiz) {
    console.error('Erro: não foi possível resolver raiz de dados para gravar divergência');
    process.exit(1);
  }

  const logDir = path.join(raiz, '.logs');
  const logFile = path.join(logDir, 'divergencias-segunda-opiniao.jsonl');

  // Criar diretório se não existir
  if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
  }

  // Registrar como JSONL
  const registro = {
    timestamp: new Date().toISOString(),
    veredito: args.veredito,
    motivo: args.motivo,
    base: args.base,
    modelo: MODELO
  };

  try {
    fs.appendFileSync(logFile, JSON.stringify(registro) + '\n', 'utf8');
    console.error(`Divergência registrada em ${logFile}`);
    process.exit(0);
  } catch (e) {
    console.error(`Erro ao gravar divergência: ${e.message}`);
    process.exit(1);
  }
}

// Se é subcomando de registro, executar direto
if (subcomando === 'registrar-divergencia') {
  registrarDivergencia();
  // Não retorna, pois registrarDivergencia chama process.exit
}

// Validar argumentos obrigatórios
if (!BASE || !HEAD) {
  console.error('Erro: --base e --head são obrigatórios');
  process.exit(1);
}

if (!CRITERIO_ARQUIVO) {
  console.error('Erro: --criterio é obrigatório');
  process.exit(1);
}

// Validar que o arquivo de critério existe
if (!fs.existsSync(CRITERIO_ARQUIVO)) {
  console.error(`Erro: arquivo de critério não encontrado: ${CRITERIO_ARQUIVO}`);
  process.exit(1);
}

// Gerar diff
const diffCmd = `git diff ${BASE}...${HEAD}`;
const diffResult = spawnSync('git', ['diff', `${BASE}...${HEAD}`], {
  encoding: 'utf8',
  cwd: process.cwd()
});

if (diffResult.status !== 0) {
  console.error(`Erro ao gerar diff: ${diffResult.stderr}`);
  process.exit(1);
}

const diff = diffResult.stdout;

// Validar que diff não está vazio
if (!diff || diff.trim().length === 0) {
  console.error('Erro: sem diff, sem revisão');
  process.exit(1);
}

// Ler arquivo de critério
const criterio = fs.readFileSync(CRITERIO_ARQUIVO, 'utf8');

// Montar prompt
const prompt = `## Diff da entrega

\`\`\`
${diff}
\`\`\`

## Critério de sucesso (falsificável)

${criterio}

## Commit-base esperado

${BASE}

Sua tarefa: revise o diff acima contra o critério. Responda com UMA LINHA no final, exatamente:
- "concordo" (se o diff atende ao critério)
- "discordo" (se o diff não atende ao critério)
`;

// Selecionar comando conforme modelo
let cmd = CLI_CMD_CUSTOM; // Se fornecido, usa direto (para testes com fixture)

if (!cmd) {
  const cmdMap = {
    codex: 'codex exec -s read-only --skip-git-repo-check',
    gemini: 'gemini -m gemini-3.7-flash --skip-trust --approval-mode plan'
  };

  cmd = cmdMap[MODELO];
  if (!cmd) {
    console.error(`Erro: modelo desconhecido: ${MODELO}. Use codex ou gemini.`);
    process.exit(1);
  }
}

// Chamar CLI externo com timeout configurável
// Default 300000ms (5min) alinhado ao timeout do conselho (scripts/conselho.cjs:41 TIMEOUT_MEMBRO_MS).
// Um diff de ~900 linhas não responde em 30s, e nenhuma fixture detectava isso.
const timeoutMs = parseInt(process.env.TIMEOUT_SEGUNDA_OPINIAO_MS || '300000', 10);
// Log do timeout para validação em testes (stderr, não polui stdout)
if (process.env.TIMEOUT_SEGUNDA_OPINIAO_DEBUG) {
  console.error(`[DEBUG] TIMEOUT_SEGUNDA_OPINIAO_MS=${timeoutMs}ms`);
}
const resultado = rodarCli({
  cmd,
  entrada: prompt,
  timeoutMs,
  env: process.env
});

// D6: Falha fechada — modelo ligado e indisponível reprova, nunca segue sem ele
// Detectar 3 modos de indisponibilidade com mensagens distintas

// Modo 1: CLI sai com exit ≠ 0
if (resultado.status !== 0 && resultado.status !== null) {
  console.error(`Erro: modelo ligado mas indisponível (exit ≠ 0): ${resultado.status}`);
  if (resultado.stderr) {
    console.error(resultado.stderr);
  }
  process.exit(1);
}

// Modo 3: Timeout (resultado.status === null quando spawnSync tira timeout)
if (resultado.status === null) {
  console.error(`Erro: modelo ligado mas indisponível (timeout após ${timeoutMs}ms)`);
  if (resultado.stderr) {
    console.error(resultado.stderr);
  }
  process.exit(1);
}

// Modo 2: Stdout vazio (deve vir depois de status null check, pois null !== 0)
if (!resultado.stdout || resultado.stdout.trim().length === 0) {
  console.error(`Erro: modelo ligado mas indisponível (stdout vazio)`);
  process.exit(1);
}

// Extrair última linha com conteúdo
const parecer = resultado.stdout.trim(); // Parecer completo preservado
const linhas = parecer.split('\n');
const ultimaLinha = linhas[linhas.length - 1].trim().toLowerCase();

// Validar veredito contra vocabulário fechado
const vocabularioValido = ['concordo', 'discordo'];
if (!vocabularioValido.includes(ultimaLinha)) {
  console.error(
    `Erro: veredito fora do vocabulário. Recebido: "${ultimaLinha}"\n` +
    `Válido: ${vocabularioValido.join(', ')}`
  );
  process.exit(1);
}

// Sucesso: imprimir veredito (stdout) + parecer completo (stderr)
// Quem chama pode capturar ambos do mesmo rodar:
//   stdout: veredito (1 linha, vocabulário fechado)
//   stderr: parecer (N linhas, justificativa completa)
// D5 do design: discordância rejeitada vai ao log com motivo — parecer fornece a matéria-prima.
console.error(parecer); // parecer (stdout é reservado pro veredito)
console.log(ultimaLinha); // veredito
process.exit(0);
