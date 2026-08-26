#!/usr/bin/env node
/**
 * PreToolUse — barra escrita de dados sensíveis em arquivo rastreado.
 *
 * Incidente da Issue #83 (2026-08-08): um `progress.jsonl` versionado em repo
 * público recebeu um JID de WhatsApp colado como evidência de smoke. Ficou
 * 16 dias exposto. Conserto exigiu filter-branch em 211 commits e **mesmo assim
 * não bastou**, porque em rede de fork o objeto continua servido por SHA.
 *
 * O script `scripts/conferir-publicacao.cjs` já detecta o que tem forma
 * (telefone, JID, email, caminho de home, credencial). Exit 2 = recusado.
 * O buraco **não é alcance, é chamada**: nenhum artefato de fluxo passa por ali,
 * só markdown de instrução.
 *
 * **P2 vira hook, não vira parágrafo**: um parágrafo a mais seria exatamente a
 * coisa que já falhou. Regra escrita não alcança o modo de falha em que quem a
 * leu erra mesmo assim. O que alcança é código com exit code.
 *
 * ESCOPO, deliberadamente estreito:
 *   - Write/Edit/MultiEdit (ferramentas de escrita)
 *   - arquivo dentro de repo git — fora de repo, passa
 *   - arquivo NÃO gitignorado — se está ignorado, passa (nunca vira histórico)
 *   - conteúdo sendo escrito (tool_input.content para Write, tool_input.new_string
 *     para Edit)
 *   - roda `conferir-publicacao.cjs` sobre o conteúdo novo
 *   - se achar dados sensíveis, bloqueia com mensagem útil que nomeia o padrão
 *
 * Saídas de emergência, as mesmas dos outros gates:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessão inteira
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */
function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * Tenta rodar git check-ignore no arquivo. Se não está ignorado, retorna false.
 */
function estaGitignorado(dir, arquivo) {
  try {
    execFileSync("git", ["-C", dir, "check-ignore", arquivo], {
      stdio: "ignore",
    });
    return true; // arquivo está ignorado (exit 0 de check-ignore)
  } catch {
    return false; // arquivo NÃO está ignorado (exit 1 de check-ignore)
  }
}

/**
 * Detecta se o arquivo **em disco** tem o marcador que dispensa a conferência.
 * Marcador: qualquer linha contendo `rainforest-gate: dados-de-exemplo`.
 *
 * LEITURA DO DISCO, não do conteúdo que chega: isto fecha dois furos:
 *   - Edit no arquivo com marcador passa, mesmo se new_string não o tem;
 *   - Write de arquivo novo com marcador embutido é barrado, porque não tem arquivo em disco.
 *
 * Arquivo inexistente, sem permissão ou erro de leitura → sem marcador → segue para
 * conferência. Errar para o lado de conferir, nunca de liberar.
 */
function temMarcadorDados(caminhoDoArquivo) {
  try {
    const conteudo = fs.readFileSync(caminhoDoArquivo, "utf8");
    return /rainforest-gate:\s*dados-de-exemplo/i.test(conteudo);
  } catch {
    // Arquivo inexistente, sem permissão, ou erro de leitura: sem marcador
    return false;
  }
}

/**
 * Roda conferir-publicacao.cjs em modo JSON e retorna o resultado parseado.
 * Retorna { achados: [...], cego: [...] } ou null se não conseguir rodar.
 *
 * O conferir-publicacao.cjs sai com exit 2 quando acha dados sensíveis,
 * então precisamos capturar a saída mesmo quando há erro.
 */
function conferirConteudo(conteudo) {
  try {
    const scriptPath = path.join(__dirname, "..", "scripts", "conferir-publicacao.cjs");
    const output = execFileSync("node", [scriptPath, "-", "--json"], {
      input: conteudo,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return JSON.parse(output);
  } catch (e) {
    // execFileSync lança erro quando exit != 0. Tentamos pegar o stdout do erro.
    if (e.stdout) {
      try {
        return JSON.parse(e.stdout);
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * Formata a mensagem de bloqueio com os achados.
 */
function mensagemBloqueio(achados, arquivo) {
  let msg = `BLOQUEADO pelo gate de publicação do rainforest-mind.\n\n` +
    `Arquivo: ${arquivo}\n` +
    `Razão: este arquivo é versionado (rastreado por git) e contém dados sensíveis.\n\n` +
    `Trechos encontrados:\n`;

  for (const a of achados) {
    msg += `\n  linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}\n`;
    msg += `    ${a.o_que}\n`;
    msg += `    → ${a.faca}\n`;
  }

  msg += `\n\nArquivos versionados em repo público não têm como "desaparecer". `;
  msg += `Filter-branch\nremove de uma branch, mas em rede de fork o objeto continua `;
  msg += `servido por SHA\ne só o Support do GitHub consegue remover do storage da rede.\n`;
  msg += `Corrija o conteúdo e rode de novo.\n\n` +
    `Se isto é falso positivo legítimo (teste com dado fake, documentação de formato),\n` +
    `você tem duas saídas:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessão (desliga na sessão inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga naquele repo).\n`;

  return msg;
}

function bloqueia(achados, arquivo) {
  process.stderr.write(mensagemBloqueio(achados, arquivo));
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegível nunca trava o trabalho do usuário
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  // Toggle do setup: quem não quer este gate num repositório pode desligá-lo por
  // `.rainforest/config.json` do projeto.
  try { if (!require("./lib/config.cjs").ligado("gate-publicacao", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  const nome = ev.tool_name;
  if (!FERRAMENTAS_DE_ESCRITA.has(nome)) process.exit(0);

  const entrada = ev.tool_input || {};
  let arquivo = null;
  let conteudo = null;

  if (nome === "Write" && typeof entrada.file_path === "string" && typeof entrada.content === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.content;
  } else if (nome === "Edit" && typeof entrada.file_path === "string" && typeof entrada.new_string === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.new_string;
  } else if (nome === "MultiEdit") {
    // MultiEdit passa um array de edits. Conferir cada um.
    const edits = Array.isArray(entrada.edits) ? entrada.edits : [];
    for (const edit of edits) {
      if (typeof edit.file_path === "string" && typeof edit.new_string === "string") {
        // Confere este arquivo/conteúdo
        const a = edit.file_path;
        const c = edit.new_string;
        const dir = dirDe(a);
        const gitTop = git(dir, ["rev-parse", "--show-toplevel"]);
        if (!gitTop) continue; // fora de repo git

        if (estaGitignorado(dir, a)) continue; // gitignorado passa

        if (temMarcadorDados(a)) continue; // marcador de dados-de-exemplo passa

        const resultado = conferirConteudo(c);
        if (resultado && resultado.achados && resultado.achados.length) {
          bloqueia(resultado.achados, a);
        }
      }
    }
    process.exit(0);
  } else {
    process.exit(0);
  }

  if (!arquivo || !conteudo) process.exit(0);

  // Determina o diretório onde o arquivo vai ficar
  const dir = dirDe(arquivo);

  // Confere se está dentro de um repo git
  const gitTop = git(dir, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) process.exit(0); // fora de repo git: passa

  // Confere se é arquivo gitignorado
  if (estaGitignorado(dir, arquivo)) process.exit(0); // ignorado passa

  // Confere se tem marcador de dados-de-exemplo (para testes de bateria)
  if (temMarcadorDados(arquivo)) process.exit(0); // marcador dispensa conferência

  // Confere se o arquivo está na raiz do repo ou em subdiretório
  try {
    if (fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) process.exit(0);
  } catch {}

  // Roda a conferência de publicação
  const resultado = conferirConteudo(conteudo);
  if (resultado && resultado.achados && resultado.achados.length) {
    bloqueia(resultado.achados, arquivo);
  }

  process.exit(0);
}

function dirDe(alvo) {
  try {
    return fs.existsSync(alvo) && fs.statSync(alvo).isDirectory() ? alvo : path.dirname(alvo);
  } catch {
    return path.dirname(alvo);
  }
}

if (require.main === module) main();
