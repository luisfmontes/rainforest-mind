#!/usr/bin/env node
/**
 * PreToolUse — barra arquivo STAGED com conteúdo rejeitado pelo verificador.
 * Protege contra: dados sensíveis, credenciais, ou violações definidas pelo projeto no conteúdo staged
 * Não protege contra: dados sensíveis no worktree mas não staged
 *
 * Incidente de 2026-09-12 (Issue #83): conteúdo sensível passou pelo gate de publicação
 * porque a ferramenta Write não foi invocada — o script invocou `fs.writeFileSync` diretamente,
 * que salta o PreToolUse de ferramentas de escrita. O gate de commit (gate-publicacao-destino.cjs)
 * pegou, mas varre CONTEÚDO INTEIRO. Este gate varre SÓ o STAGED, no ponto em que o
 * desenvolvedor ainda está no fluxo de staging/commit — feedback mais cedo, antes do
 * próximo `git commit`.
 *
 * ESCOPO, deliberadamente estreito:
 *   - Tool: Bash / PowerShell
 *   - Comando contém `git commit` — sem git commit, passa
 *   - Descobre verificador nesta ordem:
 *     (i) chave `"verificador-staged"` em `.rainforest/config.json` (string de comando)
 *     (ii) primeiro de: `scripts/check-personal-data.py`, `.cjs`, `.sh`, `.js`
 *     (iii) `scripts/conferir-publicacao.cjs` — chamado com `-` e conteúdo staged no stdin
 *   - Materializa conteúdo STAGED em pasta temporária preservando caminhos relativos
 *   - Para (i) e (ii): chama verificador via shell com caminhos materializados como argumentos
 *   - Para (iii): chama com `-` (stdin) e conteúdo staged de cada arquivo
 *   - Exit ≠ 0 do verificador → gate sai 2 com mensagem + saída do verificador
 *
 * Saídas de emergência:
 *   - env RAINFOREST_GATE_OFF=1        → desliga na sessão inteira
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo
 *   - `.rainforest/config.json`, chave `"gate-verificador-staged": false` → desliga
 *
 * Com `agent_id` no payload: não nomeia escotilhas (subagente não vê as variáveis).
 * Sem `agent_id`: nomeia as três.
 */

const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

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
 * Descobre o verificador do repositório (raiz = toplevel do cwd do payload).
 * Retorna { tipo, caminho } ou null.
 */
function descobreVerificador(gitTop) {
  // (i) Chave em .rainforest/config.json
  const configPath = path.join(gitTop, ".rainforest", "config.json");
  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    if (config["verificador-staged"] && typeof config["verificador-staged"] === "string") {
      return { tipo: "config", caminho: config["verificador-staged"] };
    }
  } catch {}

  // (ii) scripts/check-personal-data.*
  for (const ext of [".py", ".cjs", ".sh", ".js"]) {
    const caminho = path.join(gitTop, "scripts", `check-personal-data${ext}`);
    if (fs.existsSync(caminho)) {
      return { tipo: "script", caminho };
    }
  }

  // (iii) scripts/conferir-publicacao.cjs
  const conferir = path.join(gitTop, "scripts", "conferir-publicacao.cjs");
  if (fs.existsSync(conferir)) {
    return { tipo: "conferir", caminho: conferir };
  }

  return null;
}

/**
 * Materializa conteúdo STAGED em pasta temporária preservando caminhos relativos.
 * Retorna { pasta, arquivos } onde arquivos = ["rel/path1", "rel/path2", ...]
 */
function materializaStaged(gitTop) {
  const pasta = fs.mkdtempSync(path.join(os.tmpdir(), "rfm-staged-"));
  const arquivos = [];

  try {
    // Lista arquivos staged
    const staged = git(gitTop, ["diff", "--cached", "--name-only", "--diff-filter=ACMR"]);
    if (!staged) return { pasta, arquivos };

    const nomes = staged.split("\n").filter(Boolean);
    for (const nome of nomes) {
      const relativo = nome;
      const caminhoLocal = path.join(gitTop, nome);
      const caminhoTemp = path.join(pasta, nome);

      // Cria diretório pai se necessário
      const dir = path.dirname(caminhoTemp);
      fs.mkdirSync(dir, { recursive: true });

      // Copia conteúdo STAGED (não o disco) para a pasta temporária
      const conteudo = git(gitTop, ["show", `:${nome}`]);
      if (conteudo !== null) {
        fs.writeFileSync(caminhoTemp, conteudo, "utf8");
        arquivos.push(relativo);
      }
    }
  } catch (e) {
    try { fs.rmSync(pasta, { recursive: true }); } catch {}
    throw e;
  }

  return { pasta, arquivos };
}

/**
 * Chama o verificador (tipo "config" ou "script") com caminhos materializados como argumentos.
 */
function chamaVerificadorComArgumentos(verificador, pastaTemp, arquivos, gitTop) {
  const { spawnSync } = require("node:child_process");
  const args = arquivos.slice();

  // Detecta o tipo de comando e executa apropriadamente
  let cmd = verificador.caminho;
  let cmdArgs = [];

  // Se o comando é uma string de shell (ex: "bash scripts/verifica.sh"), desdobra
  // e resolve caminhos relativos contra gitTop
  if (verificador.tipo === "config" && cmd.includes(" ")) {
    const partes = cmd.trim().split(/\s+/);
    const executor = partes[0];  // ex: "bash"
    const script = partes.slice(1).join(" ");  // ex: "scripts/verifica.sh"

    // Se script é caminho relativo, torna absoluto
    let scriptAbsoluto = script;
    if (!path.isAbsolute(script) && !script.startsWith("~")) {
      scriptAbsoluto = path.join(gitTop, script);
    }

    cmd = executor;
    cmdArgs = [scriptAbsoluto, ...args];
  } else if (verificador.tipo === "script") {
    // Para scripts descobertos (type: "script"), o caminho é absoluto
    // Detecta extensão para saber como executar
    if (cmd.endsWith(".py")) {
      // Python script - tentar com python3 diretamente
      cmd = "python3";
      cmdArgs = [verificador.caminho, ...args];
    } else if (cmd.endsWith(".cjs") || cmd.endsWith(".js")) {
      // JavaScript
      cmd = "node";
      cmdArgs = [verificador.caminho, ...args];
    } else {
      // Script bash/sh - chamar com bash
      cmd = "bash";
      cmdArgs = [verificador.caminho, ...args];
    }
  }

  try {
    const env = Object.assign({}, process.env);

    const resultado = spawnSync(cmd, cmdArgs, {
      cwd: pastaTemp,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
      env: env,
    });

    return { status: resultado.status || 0, stdout: resultado.stdout || "", stderr: resultado.stderr || "" };
  } catch (e) {
    return { status: 127, stdout: "", stderr: e.message };
  }
}

/**
 * Chama conferir-publicacao.cjs com stdin contendo cada arquivo staged.
 */
function chamaConferirPublicacao(verificador, gitTop, arquivos) {
  let statusGeral = 0;
  let stdoutGeral = "";
  let stderrGeral = "";

  for (const arquivo of arquivos) {
    const conteudo = git(gitTop, ["show", `:${arquivo}`]);
    if (!conteudo) continue;

    try {
      const resultado = spawnSync("node", [verificador.caminho, "-", "--json"], {
        input: conteudo,
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
      });

      if (resultado.status) {
        statusGeral = resultado.status;
        stdoutGeral += resultado.stdout;
        stderrGeral += resultado.stderr;
      }
    } catch (e) {
      statusGeral = 127;
      stderrGeral += e.message + "\n";
    }
  }

  return { status: statusGeral, stdout: stdoutGeral, stderr: stderrGeral };
}

/**
 * Extrai do payload o subcomando git se houver `git commit`.
 */
function contemGitCommit(cmd) {
  return /\bgit\s+(?:(?:-[A-Za-z]\s+\S+|--[a-z-]+(?:=\S+)?|-[A-Za-z]+)\s+)*commit(?=\s|$)/.test(cmd);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0);
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();

  // Toggle do setup
  try {
    if (!require("./lib/config.cjs").ligado("gate-verificador-staged", { projeto: cwdDoEvento })) {
      process.exit(0);
    }
  } catch {}

  // Só roda em Bash/PowerShell
  if (ev.tool_name !== "Bash" && ev.tool_name !== "PowerShell") process.exit(0);

  // Só roda se o comando contém `git commit`
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string" || !contemGitCommit(cmd)) process.exit(0);

  // Descobre a raiz do repositório
  let gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) process.exit(0);

  // Normaliza gitTop também, pois git pode retornar caminho MSYS

  // Confere escotilha de emergência
  if (fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) process.exit(0);

  // Descobre verificador
  const verificador = descobreVerificador(gitTop);
  if (!verificador) process.exit(0);

  // Materializa conteúdo STAGED
  let pastaTemp = null;
  let resultado = null;

  try {
    const { pasta, arquivos } = materializaStaged(gitTop);
    pastaTemp = pasta;

    if (arquivos.length === 0) process.exit(0);

    // Chama verificador
    if (verificador.tipo === "conferir") {
      resultado = chamaConferirPublicacao(verificador, gitTop, arquivos);
    } else {
      resultado = chamaVerificadorComArgumentos(verificador, pastaTemp, arquivos, gitTop);
    }
  } finally {
    // Limpa pasta temporária
    if (pastaTemp) {
      try { fs.rmSync(pastaTemp, { recursive: true }); } catch {}
    }
  }

  // Se verificador reprovou (linha para mutação)
  if (resultado.status !== 0) {
    const ehSubagente = Boolean(ev.agent_id);
    const escotilhas = [];
    if (!ehSubagente) {
      escotilhas.push(
        "\nSaídas de emergência:",
        "  - RAINFOREST_GATE_OFF=1 (env var da sessão);",
        "  - arquivo .rainforest-gate-off na raiz do repo;",
        "  - chave \"gate-verificador-staged\": false em .rainforest/config.json."
      );
    } else {
      escotilhas.push(
        "\nPARE e reporte isto para a janela principal — ela decide como seguir."
      );
    }

    const msg =
      `BLOQUEADO pelo gate de verificador staged do rainforest-mind.\n\n` +
      `Arquivo(s) staged contêm conteúdo rejeitado pelo verificador.\n\n` +
      `Verificador: ${verificador.caminho}\n` +
      `Exit code: ${resultado.status}\n\n` +
      `Saída do verificador:\n${resultado.stdout || resultado.stderr || "(sem saída)"}\n` +
      escotilhas.join("\n");

    process.stderr.write(msg);
    process.exit(2);
  }

  process.exit(0);
}

if (require.main === module) main();
