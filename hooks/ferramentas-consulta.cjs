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

const { execFileSync } = require("node:child_process");
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

// Builtins e navegacao: nao sao ferramentas a conferir, e o argumento deles nao
// e executavel nenhum. Lista FECHADA de proposito — o que nao esta aqui e
// tratado como comando de verdade, que e o default seguro (no maximo se gasta
// uma sonda a mais; o contrario seria deixar de conferir uma ferramenta real).
const BUILTINS = new Set([
  "cd", "export", "set", "unset", "source", ".", "pushd", "popd",
  "umask", "alias", "unalias", "shift", "eval", "exec", "read", "echo",
]);

// Flags que CONSOMEM o proximo token. Sem isso, `sudo -u alguem foo` devolve
// "alguem" — foi um dos dois defeitos que a revisao de 2026-08-25 pegou.
const FLAGS_COM_VALOR = new Set(["-u", "-g", "-U", "-C", "--user", "--group", "--chdir"]);

/**
 * Extrai o executável que a linha de comando vai realmente rodar.
 *
 * RECORTE DECLARADO, e ele e estreito de proposito: separa a linha por `&&`,
 * `||`, `;` e `|`, e devolve o primeiro segmento cujo comando NAO e builtin.
 * Nao cobre `$(subshell)`, crase, variavel expandida nem alias — cobrir isso
 * exigiria executar a linha, que e exatamente o que este hook existe para
 * evitar fazer as cegas.
 *
 * POR QUE ASSIM, com data. A primeira versao pegava o primeiro token que "nao
 * parecia separador", pulando apenas o literal `cd`. Medido em 2026-08-25:
 *
 *   cd ..                                -> anunciava "'..' nao encontrado"
 *   cd /tmp && whisper-cli --model x.bin -> anunciava "'/tmp' nao encontrado"
 *   sudo -u alguem foo                   -> anunciava "'alguem' nao encontrado"
 *
 * Os dois primeiros sao o caso motivador da #76 saindo pior do que sem a
 * feature: o `whisper-cli` nunca era conferido, a sonda era gasta num
 * diretorio, e como diretorio nunca entra no ledger o alarme falso NUNCA
 * convergia — repetia em todo `cd` da vida.
 */
function extrairExecutavel(comando) {
  if (!comando || typeof comando !== "string") return null;

  for (const segmento of comando.split(/\s*(?:&&|\|\||;|\|)\s*/)) {
    const tokens = segmento.trim().split(/\s+/).filter(Boolean);
    let i = 0;

    // Prefixos que nao sao o comando: atribuicao de env, e wrappers com flags.
    while (i < tokens.length) {
      const t = tokens[i].replace(/^["']|["']$/g, "");
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { i++; continue; }      // VAR=valor
      if (t === "sudo" || t === "env" || t === "command" || t === "nohup" || t === "time") { i++; continue; }
      if (t.startsWith("-")) { i += FLAGS_COM_VALOR.has(t) ? 2 : 1; continue; }
      break;
    }

    if (i >= tokens.length) continue;
    const alvo = tokens[i].replace(/^["']|["']$/g, "");
    if (!alvo || alvo.startsWith("#") || /^[|;>&`$()]/.test(alvo)) continue;
    if (BUILTINS.has(alvo)) continue;   // builtin: segmento inteiro nao interessa

    return alvo;
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
 * O caminho achado NAO vira receita: a sonda prova existencia, nao invocacao.
 */
function sondarExecutavel(executavel) {
  try {
    // Argumentos em ARRAY, nunca string de shell interpolada. O nome do
    // executavel vem da linha de comando que a janela montou — valor de fora —
    // e monta-lo numa string de shell e a Issue #100 outra vez, fechada neste
    // repo em 2026-08-25.
    //
    // `command -v` e builtin, entao no Unix precisa de shell: o valor vai como
    // ARGUMENTO POSICIONAL (`"$1"`), nunca dentro do script.
    const saida = process.platform === "win32"
      ? execFileSync("where", [executavel], { encoding: "utf8", timeout: 2000, stdio: ["ignore", "pipe", "ignore"] })
      : execFileSync("sh", ["-c", 'command -v -- "$1"', "sh", executavel], { encoding: "utf8", timeout: 2000, stdio: ["ignore", "pipe", "ignore"] });

    // O `where` devolve UMA LINHA POR OCORRENCIA. Isso e resultado de busca, nao
    // receita — e nao vai para o ledger (D11). Fica so como sinal de que achou.
    return { achado: Boolean(saida.trim()) };
  } catch (e) {
    // NAO ACHAR e NAO CONSEGUIR CHECAR sao coisas diferentes, e colapsar as duas
    // era o cabecalho deste arquivo prometendo um terceiro caminho que o codigo
    // nao tinha (achado da revisao de 2026-08-25). O `where`/`command -v` sai
    // com codigo != 0 quando NAO ACHA — isso e resposta. Timeout, falta do
    // proprio `where`, ou erro de spawn nao sao resposta nenhuma: afirmar
    // ausencia a partir dali seria a mesma mentira que a D2 existe para impedir.
    const respondeu = typeof e.status === "number" && !e.signal;
    return respondeu ? { achado: false } : { achado: false, incerto: true };
  }
}


/**
 * Grava o fato positivo no ledger, pela porta unica.
 * Formato: {nome, descoberto, data} — SEM receita (D11).
 * Retorna {ok: true/false}.
 */
function gravarNoLedger(raiz, executavel, _caminhoDaSonda) {
  try {
    const script = path.join(__dirname, "..", "scripts", "ferramentas.cjs");

    // SEM `receita`, e o parametro da sonda entra aqui so para ficar explicito
    // que ele NAO e usado (D11). A sonda prova que o executavel existe; ela nao
    // sabe como invoca-lo. Em 2026-08-25 a primeira versao gravou a saida crua
    // do `where` como receita — dois caminhos concatenados, com um CR no meio —
    // e receita inventada custa mais que receita ausente. A receita entra
    // depois, pelo `registrar` explicito, quando alguem souber a invocacao.
    const entrada = {
      nome: executavel,
      descoberto: "sonda-consulta",
      data: new Date().toISOString().split("T")[0],
    };

    // `execFileSync` com argumentos em array, nunca `execSync` com o caminho
    // interpolado numa string de shell: e a regressao exata da Issue #100,
    // fechada neste repo em 2026-08-25.
    execFileSync(process.execPath, [script, "registrar", "--json"], {
      input: JSON.stringify(entrada),
      stdio: ["pipe", "ignore", "ignore"],
      timeout: 5000,
      cwd: raiz,
      encoding: "utf8",
    });

    return { ok: true };
  } catch {
    // Falha de escrita nao derruba nada (D10)
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
  const sonda = sondarExecutavel(executavel);

  if (sonda.achado) {
    // Acha a ferramenta — grava e anuncia
    gravarNoLedger(raiz, executavel, sonda.caminho);
    anunciar("disponivel", executavel);
  } else {
    // Não acha — anuncia bloqueio
    anunciar(sonda.incerto ? "incerto" : "bloqueio", executavel);
  }

  // D10 — sempre sai 0
  process.exit(0);
}

if (require.main === module) main();
