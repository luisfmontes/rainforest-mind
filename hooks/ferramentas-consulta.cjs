#!/usr/bin/env node
/**
 * PreToolUse — consulta catálogo de ferramentas antes de tentar usar uma.
 *
 * Atende D8, D10, D12, D14 do design de #76 (docs/rainforest/design/2026-08-25-catalogo-de-ferramentas.md):
 *   D8 — Entrada presente: confia (zero subprocesso, lê em processo).
 *   D10 — Anuncia e deixa passar; nunca barra (exit 0 sempre).
 *   D12 — Entrada ausente: uma checagem barata, anunciando resultado real.
 *   D14 — Só escreve quando executável ainda não está no ledger.
 *
 * Fluxo:
 *   1. Lê payload JSON do stdin (PreToolUse do Bash).
 *   2. Extrai primeiro executável da linha de comando.
 *   3. Lê ledger em processo (sem subprocess).
 *   4. Se entrada existe no ledger:
 *      → Silêncio, sai 0 (D8).
 *   5. Se não existe no ledger:
 *      → Roda UMA sonda barata (which/command -v) do executável.
 *      → Se acha: anuncia que está disponível, grava no ledger (D14), sai 0.
 *      → Se não acha: anuncia bloqueio (regra 14), sai 0.
 *      → Se não consegue checar: anuncia incerteza, sai 0.
 *   6. Erro no ledger, leitura falha, raiz inacessível: silêncio, sai 0 (D10).
 *
 * Recorte de extração de executável (D9):
 *   Primeiro TOKEN "de verdade" que pareça ser comando — ignora cd, variáveis,
 *   sudo, redirecionadores, aspas, comentários.
 *
 * Incidente 2026-08-19: payload montado via `node argv`, nunca `printf`.
 */

const { execSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

/**
 * Resolve RAIZ do ledger ferramentas.jsonl.
 * Segue a mesma cadeia do ideias.cjs e scripts/ferramentas.cjs.
 */
function resolverRaiz(cwd) {
  try {
    const { resolverRaiz: fn } = require("./lib/raiz.cjs");
    const r = fn({ plugin: cwd });
    return r.raiz || cwd;
  } catch {
    return cwd;
  }
}

/**
 * Extrai o primeiro executável da linha de comando.
 */
function extrairExecutavel(comando) {
  if (!comando || typeof comando !== "string") return null;

  const partes = comando.split(/\s+/);

  for (const parte of partes) {
    if (!parte || parte.startsWith("#") || parte.match(/^[|;>&`$()]/)) continue;
    if (parte === "cd" || parte === "sudo" || parte === "sudo-u" || parte === "-u") continue;
    if (parte.includes("=")) continue;

    const sem_aspas = parte.replace(/^["']|["']$/g, "");
    if (!sem_aspas || sem_aspas.match(/^[|;&><]/)) continue;

    return sem_aspas;
  }

  return null;
}

/**
 * Lê o ledger ferramentas.jsonl em processo (sem subprocess).
 * Retorna array de objetos {nome, receita, descoberto, data}.
 * Se arquivo não existe ou erro: retorna [].
 */
function lerLedger(raiz) {
  const alvo = path.join(raiz, "ferramentas.jsonl");
  try {
    const conteudo = fs.readFileSync(alvo, "utf8");
    const linhas = conteudo.split("\n").filter((l) => l.trim().length > 0);
    const objs = [];
    for (const linha of linhas) {
      try {
        objs.push(JSON.parse(linha));
      } catch {
        // linha malformada: ignora
      }
    }
    return objs;
  } catch {
    // arquivo não existe ou erro de leitura
    return [];
  }
}

/**
 * Consulta o ledger e retorna a entrada se existe.
 */
function consultarLedger(raiz, executavel) {
  if (!executavel) return null;
  const ledger = lerLedger(raiz);
  return ledger.find((o) => o.nome === executavel) || null;
}

/**
 * Sonda barata do executável: which (ou command -v em bash).
 * Retorna {achado: true/false, caminho?: string}.
 * O caminho é usado como receita quando gravamos.
 */
function sodarExecutavel(executavel) {
  try {
    // Usa `where` no Windows, `which` em Unix
    const cmd =
      process.platform === "win32"
        ? `where ${JSON.stringify(executavel)}`
        : `command -v ${JSON.stringify(executavel)}`;

    const saida = execSync(cmd, {
      encoding: "utf8",
      timeout: 2000,
    }).trim();

    return { achado: true, caminho: saida };
  } catch {
    return { achado: false };
  }
}

/**
 * Grava entrada no ledger.
 * Formato: {nome, receita, descoberto, data}.
 * Receita = caminho retornado pela sonda (which/command -v).
 * Retorna {ok: true/false, motivo?: string}.
 */
function gravarNoLedger(raiz, executavel, caminho) {
  try {
    const script = path.join(__dirname, "..", "scripts", "ferramentas.cjs");
    const entrada = {
      nome: executavel,
      receita: caminho || executavel, // Caminho da sonda, ou nome como fallback
      descoberto: "sonda-consulta",
      data: new Date().toISOString().split("T")[0],
    };

    // Chama o script de escrita
    execSync(`node "${script}" registrar --json`, {
      input: JSON.stringify(entrada),
      stdio: ["pipe", "ignore", "ignore"],
      timeout: 5000,
      cwd: raiz,
      encoding: "utf8",
    });

    return { ok: true };
  } catch {
    // Falha de escrita não derruba nada (D10)
    return { ok: false };
  }
}

/**
 * Anuncia ferramenta conforme o resultado da sonda.
 * Regra 14: uma linha, com efeito prático nomeado.
 */
function anunciar(tipo, executavel) {
  if (tipo === "disponivel") {
    process.stderr.write(
      `[ferramentas-consulta] '${executavel}' descoberta e registrada.\n`
    );
  } else if (tipo === "bloqueio") {
    process.stderr.write(
      `[ferramentas-consulta] executável não encontrado: '${executavel}' — task vai falhar ao tentar usá-la.\n`
    );
  } else if (tipo === "incerto") {
    process.stderr.write(
      `[ferramentas-consulta] não consegui conferir '${executavel}' — prossigo sem garantia.\n`
    );
  }
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    // Payload ilegível — D10, nunca recusa
    process.exit(0);
  }

  // Só age em Bash
  if (ev.tool_name !== "Bash") {
    process.exit(0);
  }

  const comando = (ev.tool_input || {}).command;
  const cwd = ev.cwd || process.cwd();

  if (typeof comando !== "string") {
    process.exit(0);
  }

  // Extrai executável
  const executavel = extrairExecutavel(comando);
  if (!executavel) {
    process.exit(0);
  }

  // Resolve raiz
  const raiz = resolverRaiz(cwd);

  // Consulta ledger (sem subprocess)
  const entrada = consultarLedger(raiz, executavel);

  // D8 — Se está no ledger, confia e sai
  if (entrada) {
    process.exit(0);
  }

  // D12 — Não está no ledger: roda sonda de verdade
  const sonda = sodarExecutavel(executavel);

  if (sonda.achado) {
    // Acha a ferramenta — grava e anuncia
    gravarNoLedger(raiz, executavel, sonda.caminho);
    anunciar("disponivel", executavel);
  } else {
    // Não acha — anuncia bloqueio
    anunciar("bloqueio", executavel);
  }

  // D10 — sempre sai 0
  process.exit(0);
}

if (require.main === module) main();
