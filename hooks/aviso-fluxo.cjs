#!/usr/bin/env node
// @categoria: guia
/**
 * Bloqueio de edição de código sem fluxo e sem caminho leve (#430).
 *
 * Bloqueia (exit 2, mensagem em stderr) o Edit/Write/MultiEdit de arquivo de código
 * fora de docs/ quando o repositório tem fluxo (rainforest ou protheus), nenhum está
 * aberto e a branch não tem o registro `leve` (`estado.cjs leve --motivo`). Repete a
 * cada edição: não há memória por sessão (D8 do design 2026-10-08-fluxo-pulado-bloqueio).
 *
 * A mensagem nomeia as duas saídas com comando pronto (D9): abrir o fluxo, ou o caminho
 * leve declarado. Chave `aviso-fluxo` do config desliga tudo (D4). Subagente (agent_id)
 * não é barrado aqui: quem barra o despacho de agente que edita é a portaria.
 *
 * O repositório é o do ARQUIVO editado, não o do cwd da sessão (emenda 1 do plano, D1/D9):
 * sessão no checkout principal editando um worktree de fluxo aberto passa.
 *
 * Extensões de código (comparadas em minúsculas): .js .cjs .mjs .ts .tsx .jsx .py .sh .ps1 .psm1 .prw .prx .tlpp .ch .go .rs .java .cs .rb .php .sql .c .h .cpp .bat .cmd
 */

const fs = require('node:fs');
const path = require('node:path');
const { leveDaBranch } = require('./lib/caminho-leve.cjs');

const {
  EXTENSOES_CODIGO, diretorioExistente, toplevel, branchAtual, ehBranchPadraoDoRepo,
  detectarTrilho, fluXoAberto, mensagemHeadDestacado, mensagemBloqueio,
} = require('./lib/aviso-fluxo-comum.cjs');

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível — não impacta a sessão
  }
  if (!ev || typeof ev !== 'object') process.exit(0);

  // Critério 1: sem agent_id (subagentes são barrados pela portaria, não aqui)
  if (typeof ev.agent_id === 'string' && ev.agent_id) {
    process.exit(0);
  }

  // Critério 2: arquivo com extensão de código
  if (!ev.tool_input || typeof ev.tool_input !== 'object' || !ev.tool_input.file_path) {
    process.exit(0);
  }
  const filePath = ev.tool_input.file_path;
  const ext = path.extname(filePath).toLowerCase();
  if (!EXTENSOES_CODIGO.has(ext)) {
    process.exit(0);
  }

  // Critério 4: repositório git do ARQUIVO (não do cwd): emenda 1 do plano, D1
  if (!ev.cwd) process.exit(0);
  const gitTop = toplevel(diretorioExistente(path.resolve(ev.cwd, filePath)));
  if (!gitTop) process.exit(0);

  // Critério 3: arquivo não sob docs/
  // Caminho real dos dois lados: no Windows o temp pode vir em nome curto 8.3
  // (`RUNNER~1`) e o git devolve o longo, e o `relative` subia com `..`.
  const real = (p) => {
    try { return fs.realpathSync.native(p); } catch { /* arquivo novo: sobe ao pai */ }
    try { return path.join(fs.realpathSync.native(path.dirname(p)), path.basename(p)); } catch { return p; }
  };
  const normalize = (p) => p.split(/[\\/]/).join('/');
  const relPath = normalize(path.relative(real(gitTop), real(path.resolve(ev.cwd, filePath))));
  const partes = relPath.split('/');
  if (partes[0] === 'docs') {
    process.exit(0);
  }

  // Critério 5: repositório com fluxo (rainforest ou protheus)
  const trilho = detectarTrilho(gitTop);
  if (!trilho) {
    process.exit(0);
  }

  // Critério 6: config permite a trava (chave `aviso-fluxo`, padrão ligada)
  try {
    if (!require('./lib/config.cjs').ligado('aviso-fluxo', { projeto: gitTop })) {
      process.exit(0);
    }
  } catch {}

  // Critério 7: há fluxo aberto na branch
  if (fluXoAberto(gitTop, trilho)) {
    process.exit(0);
  }

  // HEAD destacado: sem branch não há fluxo nem `leve` possível (o estado.cjs recusa).
  const branch = branchAtual(gitTop);
  const headDestacado = branch === 'HEAD';

  // Critério 8: a branch tem o caminho leve declarado (D6, D7)
  if (!headDestacado && branch && leveDaBranch({ gitTop, branch })) {
    process.exit(0);
  }

  // Bloqueio (D7, D9): o leve só é oferecido onde o estado.cjs o aceita.
  const ehBranchPadrao = ehBranchPadraoDoRepo(gitTop, branch);
  const ofereceLeve = !headDestacado && !(trilho === 'rainforest' && ehBranchPadrao);
  const texto = headDestacado
    ? mensagemHeadDestacado(trilho)
    : mensagemBloqueio(trilho, branch || 'desconhecida', ofereceLeve, gitTop);

  // fs.writeSync garante que a mensagem sai antes do exit.
  fs.writeSync(2, texto + '\n');
  process.exit(2); // bloqueio-fluxo
}

main();
