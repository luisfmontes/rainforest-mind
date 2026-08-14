#!/usr/bin/env node
/**
 * Orcamento — mede o custo do rainforest-mind em BYTES e acusa quando estoura
 * os tetos.
 *
 * Fontes medidas:
 * 1. Saída do hook foco-session-start.cjs — campo additionalContext do JSON
 * 2. Descriptions dos skills (skills dir)
 * 3. Descriptions dos commands (commands dir)
 * 4. Descriptions dos agentes (agents dir)
 *
 * Tetos:
 * - Hook sozinho: ORCAMENTO_BYTES de hooks/lib/contexto-sessao.cjs
 * - Agregado (todas as fontes somadas): 14000 B
 * - --teto <n> sobrescreve o teto agregado
 *
 * Saída: uma linha por fonte medida, uma linha de total, e — quando estoura —
 * uma linha por teto excedido.
 *
 * Exit: 0 dentro dos tetos, 1 quando estoura qualquer um.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const LOCAL = path.resolve(__dirname, '..');

const bytes = (s) => Buffer.byteLength(s, 'utf8');

function morrer(msg) {
  console.error(`erro: ${msg}`);
  process.exit(1);
}

function valorDe(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? null : process.argv[i + 1] || null;
}

/**
 * Extrai ORCAMENTO_BYTES de hooks/lib/contexto-sessao.cjs.
 * Nunca digita o literal — sempre lê de lá, para evitar divergência.
 */
function lerOrcamentoDaLib() {
  const caminhoLib = path.join(LOCAL, 'hooks', 'lib', 'contexto-sessao.cjs');
  const conteudo = fs.readFileSync(caminhoLib, 'utf8');
  const match = conteudo.match(/ORCAMENTO_BYTES:\s*(\d+)/);
  if (!match) {
    morrer('não consegui ler ORCAMENTO_BYTES de hooks/lib/contexto-sessao.cjs');
  }
  return Number(match[1]);
}

/**
 * Executa o hook e extrai additionalContext do JSON de saída.
 */
function medirHook() {
  try {
    const hookPath = path.join(LOCAL, 'hooks', 'foco-session-start.cjs');
    const saida = execSync(`node "${hookPath}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const json = JSON.parse(saida);
    const additionalContext = json.hookSpecificOutput?.additionalContext || '';
    return bytes(additionalContext);
  } catch (err) {
    morrer(`erro ao executar hook: ${err.message}`);
  }
}

/**
 * Extrai o campo `description` do frontmatter YAML de um arquivo.
 * O frontmatter fica entre --- e --- na primeira linha.
 * A description é sempre uma string, não array.
 */
function extrairDescription(caminhoArquivo) {
  try {
    const conteudo = fs.readFileSync(caminhoArquivo, 'utf8');
    // Procura pelo bloco frontmatter.
    // O `\r?` nao e zelo: o repo tem .gitattributes exigindo LF, e ainda assim
    // `agents/executor.md` e `commands/foco.md` estao em CRLF no disco. Sem
    // tolerar o \r, o bloco nao casa, esta funcao devolve '' e a fonte inteira
    // e medida como 0 B — o instrumento subestima o orcamento e o gate nunca
    // dispara. Foi o que aconteceu em 2026-08-13: `Agentes: 0 B` no checkout
    // principal, contra 1.618 B no worktree do agente, que veio com LF.
    const match = conteudo.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if (!match) return '';
    const frontmatter = match[1];
    // Procura pela linha description:
    // O regex pega tudo após description: até o fim da linha
    const descMatch = frontmatter.match(/^description:\s*(.*)$/m);
    if (!descMatch) return '';
    return descMatch[1].trim();
  } catch {
    return '';
  }
}

/**
 * Mede descriptions dos skills (cada subdir em skills/ contém SKILL.md).
 */
function medirSkills() {
  const skillsDir = path.join(LOCAL, 'skills');
  let totalBytes = 0;
  if (!fs.existsSync(skillsDir)) return totalBytes;

  const dirs = fs.readdirSync(skillsDir, { withFileTypes: true });
  for (const dir of dirs) {
    if (!dir.isDirectory()) continue;
    const skillMd = path.join(skillsDir, dir.name, 'SKILL.md');
    if (fs.existsSync(skillMd)) {
      const desc = extrairDescription(skillMd);
      if (desc) {
        totalBytes += bytes(desc);
      }
    }
  }
  return totalBytes;
}

/**
 * Mede descriptions dos commands (markdown files em commands dir).
 */
function medirCommands() {
  const commandsDir = path.join(LOCAL, 'commands');
  let totalBytes = 0;
  if (!fs.existsSync(commandsDir)) return totalBytes;

  const files = fs.readdirSync(commandsDir, { withFileTypes: true });
  for (const file of files) {
    if (!file.isFile() || !file.name.endsWith('.md')) continue;
    const desc = extrairDescription(path.join(commandsDir, file.name));
    if (desc) {
      totalBytes += bytes(desc);
    }
  }
  return totalBytes;
}

/**
 * Mede descriptions dos agentes (markdown files em agents dir).
 */
function medirAgentes() {
  const agentsDir = path.join(LOCAL, 'agents');
  let totalBytes = 0;
  if (!fs.existsSync(agentsDir)) return totalBytes;

  const files = fs.readdirSync(agentsDir, { withFileTypes: true });
  for (const file of files) {
    if (!file.isFile() || !file.name.endsWith('.md')) continue;
    const desc = extrairDescription(path.join(agentsDir, file.name));
    if (desc) {
      totalBytes += bytes(desc);
    }
  }
  return totalBytes;
}

function main() {
  const orcamentoDaLib = lerOrcamentoDaLib();
  const tetoHook = orcamentoDaLib;
  const tetoAgregado = Number(valorDe('teto') || 14000);

  const bytesHook = medirHook();
  const bytesSkills = medirSkills();
  const bytesCommands = medirCommands();
  const bytesAgentes = medirAgentes();

  const totalBytes = bytesHook + bytesSkills + bytesCommands + bytesAgentes;

  // Imprime resultados
  console.log(`Hook (additionalContext): ${bytesHook} B`);
  console.log(`Skills (descriptions): ${bytesSkills} B`);
  console.log(`Commands (descriptions): ${bytesCommands} B`);
  console.log(`Agentes (descriptions): ${bytesAgentes} B`);
  console.log(`Total: ${totalBytes} B`);

  // Verifica tetos e acusa estouros
  let tetoExcedido = false;
  if (bytesHook > tetoHook) {
    console.error(`Estouro do teto do hook: ${bytesHook} B > ${tetoHook} B (+${bytesHook - tetoHook} B)`);
    tetoExcedido = true;
  }
  if (totalBytes > tetoAgregado) {
    console.error(`Estouro do teto agregado: ${totalBytes} B > ${tetoAgregado} B (+${totalBytes - tetoAgregado} B)`);
    tetoExcedido = true;
  }

  process.exit(tetoExcedido ? 1 : 0);
}

main();
