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
 * - Saída deve terminar com LINHA DE VEREDITO de vocabulário fechado
 * - Recusa (exit ≠ 0) se: falta --base/--head, diff vazio, veredito inválido
 * - Arbitra sempre: script aconselha, não manda
 *
 * Vocabulário de veredito (exatamente):
 * - "concordo" — diff atende ao critério
 * - "discordo" — diff não atende ao critério
 * Qualquer outra última linha = erro, exit ≠ 0
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { rodarCli, extrairJson } = require('../hooks/lib/cli-externo.cjs');

// Parse argumentos
const args = {};
for (let i = 2; i < process.argv.length; i++) {
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

// Chamar CLI externo
const resultado = rodarCli({
  cmd,
  entrada: prompt,
  timeoutMs: 30000,
  env: process.env
});

if (resultado.status !== 0) {
  console.error(`Erro ao chamar ${MODELO}: status ${resultado.status}`);
  if (resultado.stderr) {
    console.error(resultado.stderr);
  }
  process.exit(1);
}

if (!resultado.stdout || resultado.stdout.trim().length === 0) {
  console.error(`Erro: ${MODELO} retornou saída vazia`);
  process.exit(1);
}

// Extrair última linha com conteúdo
const linhas = resultado.stdout.trim().split('\n');
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

// Sucesso: imprimir veredito
console.log(ultimaLinha);
process.exit(0);
