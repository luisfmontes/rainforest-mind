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
 * - Agregado (todas as fontes somadas): 15000 B
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
const { avaliarFolga } = require('../hooks/lib/folga.cjs');

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
  /**
   * Teto AGREGADO, em bytes. Subiu de 14.000 para 15.000 em 2026-08-25, e a conta
   * vai escrita porque subir teto neste repo e decisao consciente, nunca default.
   *
   * O 14.000 era o unico teto do projeto SEM justificativa escrita — os outros
   * carregam de onde sairam. Ele foi calibrado num mundo em que o bloco de foco
   * chegava vazio: a Issue #74 mostrou que `priorizarFoco` nunca rodava num
   * FOCO.md com CRLF, entao o hook media ~6,8 KB e o agregado fechava folgado.
   *
   * Com o foco funcionando o numero e OUTRO, e e estrutural: em `montarContexto`,
   * `tetoFoco = ORCAMENTO - fixo`, ou seja, o bloco de foco preenche por
   * construcao o que sobra. O hook passa a encostar em ~8.000 B em TODA sessao, e
   * o agregado vira ~8.000 + as descricoes (skills 3.601 + comandos 1.111 +
   * agentes 2.040 = 6.752) ≈ 14.750 B. Contra 14.000, o estouro seria permanente.
   *
   * Nao e numero novo escondido: a Issue #81 ja registrava +220 B na maquina do
   * dono com o CI verde, porque o CI roda com fixture de ~6,3 KB e nao com o
   * FOCO.md de quem usa. O conserto do CRLF so empurrou +220 para +720 ao fazer
   * o foco ocupar a cota que sempre foi dele.
   *
   * 15.000 da ~250 B de folga sobre o piso estrutural de ~14.750. Apertado de
   * proposito: continua doendo escrever descricao gorda, que e o trabalho que
   * este teto existe para fazer. Quem quiser passar daqui paga por SUBTRACAO.
   */
  const tetoAgregado = Number(valorDe('teto') || 15000);

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

  // Verifica tetos e acusa estouros/avisos
  let tetoExcedido = false;

  // Avaliar hook
  // O hook e limitado POR CONSTRUCAO: `tetoFoco = ORCAMENTO - fixo`, entao
  // `fixo + foco <= ORCAMENTO` sempre, e o `travarOrcamento` e so a rede. Medir
  // FOLGA aqui contra uma banda de 5% (400 B) so fazia sentido quando o bloco de
  // foco NAO usava a propria cota: hoje ele usa, o hook para a 32 B do teto, e o
  // aviso dispararia em toda sessao dizendo que esta tudo apertado quando na
  // verdade esta tudo funcionando. Aviso que nunca cala e aviso que ninguem le.
  //
  // O ESTOURO continua valendo, e e o invariante de verdade: se o hook passar de
  // ORCAMENTO_BYTES, quem cortou foi o `travarOrcamento`, e isso e defeito.
  // `banda: 0` mantem o estouro e aposenta o aviso de folga.
  const resultadoHook = avaliarFolga(bytesHook, tetoHook, {
    nome: 'teto do hook',
    banda: 0,
    alternativas: ['tirar do additionalContext']
  });
  if (resultadoHook.mensagem) {
    console.error(resultadoHook.mensagem);
  }
  if (resultadoHook.estado === 'estouro') {
    tetoExcedido = true;
  }

  // Avaliar agregado
  // Banda explicita, e nao os 5% do padrao. Com teto de 15.000 os 5% dariam 750 B
  // de limiar, contra um piso ESTRUTURAL de ~14.750 — ou seja, o aviso dispararia
  // em toda sessao, pelo mesmo motivo que o do hook acabou de ser aposentado logo
  // acima: aviso que nunca cala e aviso que ninguem le, e ele gasta a atencao que
  // o estouro de verdade vai precisar.
  //
  // 300 B e o quanto vale ser avisado: cabe uma descricao de agente inteira
  // (2.040 B / 9 = ~227 B em media), entao o aviso significa "a proxima descricao
  // que voce escrever nao cabe", que e acionavel. Acima disso, silencio.
  const resultadoAgregado = avaliarFolga(totalBytes, tetoAgregado, {
    nome: 'agregado',
    banda: 300 / tetoAgregado,
    alternativas: ['tirar do FOCO', 'subir o teto']
  });
  if (resultadoAgregado.mensagem) {
    console.error(resultadoAgregado.mensagem);
  }
  if (resultadoAgregado.estado === 'estouro') {
    tetoExcedido = true;
  }

  process.exit(tetoExcedido ? 1 : 0);
}

main();
