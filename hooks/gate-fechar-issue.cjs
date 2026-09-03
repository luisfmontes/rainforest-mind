#!/usr/bin/env node
/**
 * PreToolUse — barra `gh issue close` direto e `gh pr create/merge` sem evidência.
 *
 * Decisões D15, D16: fechar Issue sem o marcador de evidência é bloqueado.
 * - `gh issue close <n>` direto → exit 2, stderr aponta para scripts/fechar-issue.cjs
 * - `gh pr create`/`gh pr merge` com corpo citando `closes #N` para Issue sem marcador → exit 2
 * - Corpo ilegível (editor interativo) → exit 2 dizendo isso
 * - Saídas de emergência: `RAINFOREST_GATE_OFF=1`, `.rainforest-gate-off`
 *
 * O gate só LÊ comentários via `gh issue view --json comments`; nunca escreve.
 */

const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const { MARCADOR } = require("./lib/marcador-evidencia.cjs");
const { executar } = require("./lib/resolver-executavel.cjs");

/**
 * Normaliza o nome de um executável: remove caminho, extensão e aspas.
 * Exemplos: `gh`, `gh.exe`, `gh.cmd`, `"gh"`, `C:\x\gh.exe` → `gh`
 */
function normalizarExecutavel(nome) {
  let sem_aspas = nome.replace(/^["']|["']$/g, "");
  sem_aspas = path.basename(sem_aspas);
  sem_aspas = sem_aspas.replace(/\.(exe|cmd|bat)$/i, "");
  return sem_aspas.toLowerCase();
}

/**
 * Tokeniza um comando bash, respeitando aspas simples e duplas.
 * Retorna array de tokens (sem aspas).
 */
function tokenizar(comando) {
  const tokens = [];
  let tok = "";
  let emAspaDupla = false;
  let emAspaSimples = false;

  for (let i = 0; i < comando.length; i++) {
    const char = comando[i];
    if (char === '"' && !emAspaSimples) {
      emAspaDupla = !emAspaDupla;
      continue;
    }
    if (char === "'" && !emAspaDupla) {
      emAspaSimples = !emAspaSimples;
      continue;
    }
    if ((char === " " || char === "\t") && !emAspaDupla && !emAspaSimples) {
      if (tok) {
        tokens.push(tok);
        tok = "";
      }
      continue;
    }
    tok += char;
  }
  if (tok) tokens.push(tok);
  return tokens;
}

/**
 * Verifica se o comando começa com um executável de nome 'gh' (normalizado).
 */
function comandoComecaCom(comando, exe_name) {
  const tokens = tokenizar(comando);
  if (tokens.length === 0) return false;
  return normalizarExecutavel(tokens[0]) === exe_name;
}

/**
 * Extrai subcomandos do comando (tokens a partir do segundo).
 */
function extrairSubcomandos(comando) {
  const tokens = tokenizar(comando);
  return tokens.slice(1);
}

/**
 * Verifica se os subcomandos contêm uma sequência específica (case-insensitive).
 */
function temSubcomando(subcomandos, padrao) {
  for (let i = 0; i <= subcomandos.length - padrao.length; i++) {
    if (
      subcomandos
        .slice(i, i + padrao.length)
        .every((s, idx) => s.toLowerCase() === padrao[idx].toLowerCase())
    ) {
      return true;
    }
  }
  return false;
}

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */
function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * Extrai a lista de Issues citadas num corpo de PR usando padrões de fechamento.
 * Padrão: close(s|d)|fix(es|ed)|resolve(s|d) #<n>
 * Retorna array de números únicos encontrados.
 */
function extrairIssuesCitadas(corpo) {
  const regex = /\b(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\s+#(\d+)/gi;
  const issues = new Set();
  let match;
  while ((match = regex.exec(corpo)) !== null) {
    issues.add(parseInt(match[1], 10));
  }
  return Array.from(issues);
}

/**
 * Verifica se uma Issue tem comentário com o marcador de evidência.
 * Retorna true se encontrado, false caso contrário ou em erro.
 */
function temMarcadorEvidencia(issueNum) {
  try {
    const resultado = executar("gh", [
      "issue",
      "view",
      String(issueNum),
      "--json",
      "comments",
    ]);

    // Erro ao chamar o comando
    if (resultado.status === null || resultado.status === undefined) {
      return false;
    }

    if (resultado.status !== 0) {
      return false;
    }

    const saida = (resultado.stdout || "").trim();
    return saida.includes(MARCADOR);
  } catch (e) {
    return false;
  }
}

/**
 * Extrai o corpo do comando `gh pr create` ou `gh pr merge`.
 * Procura por `--body "..."` ou `--body-file <arquivo>`.
 * Retorna { tipo: "direto"|"arquivo"|"nenhum", conteudo: string|null, legivel: bool }
 */
function extrairCorpoDoPR(comando) {
  // Procurar por --body "..."
  const matchBodyDireto = /--body\s+["']([^"']+)["']/i.exec(comando);
  if (matchBodyDireto) {
    const corpo = matchBodyDireto[1];
    // Validar se o corpo é legível: não contém $(...), crases, ou aspas não fechadas
    if (corpo.includes("$(") || corpo.includes("`")) {
      return { tipo: "direto", conteudo: corpo, legivel: false };
    }
    return { tipo: "direto", conteudo: corpo, legivel: true };
  }

  // Procurar por --body-file <arquivo>
  const matchBodyFile = /--body-file\s+(\S+)/i.exec(comando);
  if (matchBodyFile) {
    const arquivo = matchBodyFile[1];
    try {
      const conteudo = fs.readFileSync(arquivo, "utf8");
      return { tipo: "arquivo", conteudo, legivel: true };
    } catch {
      return { tipo: "arquivo", conteudo: null, legivel: false };
    }
  }

  return { tipo: "nenhum", conteudo: null, legivel: false };
}

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0);
  }

  // Verificar saídas de emergência
  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  const gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"]);
  if (gitTop && fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) {
    process.exit(0);
  }

  // Toggle do setup
  try {
    if (!require("./lib/config.cjs").ligado("gate-fechar-issue", { projeto: cwdDoEvento })) {
      process.exit(0);
    }
  } catch {}

  // Só age em Bash/PowerShell
  const nome = ev.tool_name;
  if (nome !== "Bash" && nome !== "PowerShell") process.exit(0);

  const comando = (ev.tool_input && ev.tool_input.command) || "";
  if (!comando) process.exit(0);

  // Caso (a): `gh issue close <n>` → exit 2
  if (comandoComecaCom(comando, "gh")) {
    const subcomandos = extrairSubcomandos(comando);
    if (temSubcomando(subcomandos, ["issue", "close"])) {
      bloqueia(
        `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
        `Razão: 'gh issue close' direto não registra a evidência de pronto.\n\n` +
        `Use:\n` +
        `  node scripts/fechar-issue.cjs <número> --comando "<seu-comando>" --saida "<saída-ou-arquivo>"\n\n` +
        `O script registra o comentário com a evidência antes de fechar.\n`
      );
    }
  }

  // Caso (b) e (c): `gh pr create` ou `gh pr merge` → verificar corpo
  if (comandoComecaCom(comando, "gh")) {
    const subcomandos = extrairSubcomandos(comando);
    if (temSubcomando(subcomandos, ["pr", "create"]) || temSubcomando(subcomandos, ["pr", "merge"])) {
      const corpoDoPR = extrairCorpoDoPR(comando);

      // Corpo ilegível (não consegue ler com segurança)
      if (!corpoDoPR.legivel) {
        if (corpoDoPR.tipo === "arquivo") {
          bloqueia(
            `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
            `Razão: não consegui ler o arquivo de corpo do PR.\n\n` +
            `Use --body "texto" ou --body-file <arquivo-legível>.\n`
          );
        } else if (corpoDoPR.tipo === "direto" && (corpoDoPR.conteudo.includes("$(") || corpoDoPR.conteudo.includes("`"))) {
          bloqueia(
            `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
            `Razão: o corpo do PR contém substituição de comando (\\$(...) ou backticks), não consegui ler com segurança.\n\n` +
            `Use --body "texto-plano" ou --body-file <arquivo> com o corpo já expandido.\n`
          );
        } else {
          bloqueia(
            `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
            `Razão: o corpo do PR vem de editor interativo (sem --body ou --body-file).\n\n` +
            `Se o corpo cita 'closes #N', a checagem não consegue ler.\n` +
            `Use --body "texto" ou --body-file <arquivo> para incluir a informação de fechamento.\n`
          );
        }
      }

      // Corpo legível: verificar Issues citadas
      const issues = extrairIssuesCitadas(corpoDoPR.conteudo || "");
      for (const issue of issues) {
        if (!temMarcadorEvidencia(issue)) {
          bloqueia(
            `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
            `Razão: Issue #${issue} não tem comentário com a evidência de pronto.\n\n` +
            `O critério de pronto deve ter sido rodado e colado em comentário.\n` +
            `Use:\n` +
            `  node scripts/fechar-issue.cjs ${issue} --comando "<seu-comando>" --saida "<saída-ou-arquivo>"\n\n` +
            `Depois crie o PR com o corpo citando closes #${issue}.\n`
          );
        }
      }
    }
  }

  process.exit(0);
}

if (require.main === module) main();
