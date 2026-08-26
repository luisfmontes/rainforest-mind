#!/usr/bin/env node
/**
 * PreToolUse — consulta ledger de ferramentas antes de tentar usar uma.
 *
 * Atende D8, D10, D12 do design de #76 (docs/rainforest/design/2026-08-25-catalogo-de-ferramentas.md):
 *   D8 — Entrada positiva que envelheceu: confia e deixa tropeçar (nenhum subprocesso se presente).
 *   D10 — O PreToolUse anuncia e deixa passar; nunca barra (exit 0 em todos os casos).
 *   D12 — A sonda deixa de ser peça separada e vira a própria consulta (exatamente uma checagem se ausente).
 *
 * O problema (Issue #76): janela descobre ferramenta faltando por tropeço — cinco comandos
 * de reconhecimento. A assimetria que decide tudo:
 *   - Catálogo que diz "existe" e não existe: devolve tropeço (tolerável, é o estado atual).
 *   - Catálogo que diz "não existe": faz janela RECUSAR trabalho que funcionaria (pior caso).
 *
 * Fluxo:
 *   1. Lê payload JSON do stdin (preToolUse do Bash).
 *   2. Extrai primeiro executável da linha de comando (recorte: vide comentário abaixo).
 *   3. Consulta ledger via `scripts/ferramentas.cjs consultar <nome>`.
 *      - Se encontrar (exit 0 e imprime receita): anuncia NADA, sai 0.
 *      - Se não encontrar (exit 0 e imprime "desconhecido"): anuncia achado + efeito, sai 0.
 *   4. Erro no ledger, leitura falha, raiz inacessível, comando malformado: anuncia NADA, sai 0.
 *      (D10 — nunca recusa por erro interno.)
 *
 * Recorte de extração do executável (D9 — só superfície Bash):
 *   Tira o PRIMEIRO TOKEN que pareça ser um comando de verdade:
 *   - Ignora `cd`, variáveis (contêm `=`), sudo/sudo -u.
 *   - Ignora redirecionamentos (>, >>, |, ||, &&, ;), aspas e comentários.
 *   - Pega `/path/exe`, `exe`, `./ exe` — qualquer coisa que não é um modificador.
 *
 *   Não cobre: $variável expandida, subshell $(cmd), backtick `cmd`, aliases.
 *   Razão: esses exigem execução. O recorte é deliberadamente estreito.
 *
 * Incidente 2026-08-19: em 2026-08-19 dez baterias verdes certificaram um subsistema morto
 * porque o hook lia `evento.project`, campo que o harness nunca envia, e os testes injetavam
 * o campo à mão. Neste arquivo: payload montado via `node argv`, nunca `printf`.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 * Cópia do gate-publicacao-destino.cjs — já está provada.
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
 *
 * Recorte deliberadamente estreito (comentário acima):
 *   - Pula `cd`, variáveis, sudo, redirecionadores.
 *   - Retorna o primeiro token "real" que parece ser comando.
 *
 * Se nada conseguir extrair: retorna null.
 */
function extrairExecutavel(comando) {
  if (!comando || typeof comando !== "string") return null;

  // Quebra por separadores, mantendo ordem
  const partes = comando.split(/\s+/);

  for (const parte of partes) {
    // Ignora aspas, comentários, redirecionadores
    if (!parte || parte.startsWith("#") || parte.match(/^[|;>&`$()]/)) continue;
    if (parte === "cd" || parte === "sudo" || parte === "sudo-u" || parte === "-u") continue;

    // Ignora variáveis
    if (parte.includes("=")) continue;

    // Tira aspas se houver
    const sem_aspas = parte.replace(/^["']|["']$/g, "");
    if (!sem_aspas) continue;

    // Ignora operadores de pipe/redirecionamento
    if (sem_aspas.match(/^[|;&><]/)) continue;

    // Achou algo: pode ser caminho ou nome
    return sem_aspas;
  }

  return null;
}

/**
 * Consulta o ledger de ferramentas.
 *
 * Retorna { encontrado: true/false, receita?: string, raiz: string, nomeFerramen: string? }
 * Nunca lança erro — sempre retorna um resultado.
 */
function consultarLedger(cwd, executavel) {
  const raiz = resolverRaiz(cwd);

  if (!executavel) {
    return { encontrado: false, raiz, nomeFerramental: null };
  }

  try {
    // Path absoluto do script ferramentas.cjs — está na raiz do projeto
    const script = path.join(__dirname, "..", "scripts", "ferramentas.cjs");
    const saida = execFileSync("node", [script, "consultar", executavel], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 5000, // max 5 segundos
      env: { ...process.env },  // Propaga variáveis de ambiente (RFM_ROOT)
    }).trim();

    // Se a saída é "desconhecido", ferramenta não está no ledger
    if (saida === "desconhecido") {
      return { encontrado: false, raiz, nomeFerramental: executavel };
    }

    // Se chegou aqui, é a receita
    return { encontrado: true, receita: saida, raiz, nomeFerramental: executavel };
  } catch {
    // Erro ao consultar — ledger inacessível, script não existe, timeout
    // D10 — nunca recusa
    return { encontrado: false, raiz, nomeFerramental: executavel };
  }
}

/**
 * Anuncia ferramenta ausente + efeito prático.
 * Forma: regra 14 (references/regra-14.md) — anúncio que nomeia a ferramenta
 * e o efeito prático, sem prescrever a solução (fica pra janela decidir).
 */
function anunciarAusente(ferramenta) {
  process.stderr.write(
    `[ferramentas-consulta] ferramenta ausente: '${ferramenta}' — ` +
    `task pode falhar ao tentar usá-la.\n`
  );
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

  // Consulta ledger
  const resultado = consultarLedger(cwd, executavel);

  // Se não encontrou e tem nome de ferramenta, anuncia
  if (!resultado.encontrado && resultado.nomeFerramental) {
    anunciarAusente(resultado.nomeFerramental);
  }

  // D10 — sempre sai 0
  process.exit(0);
}

if (require.main === module) main();
