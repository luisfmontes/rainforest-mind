#!/usr/bin/env node
/**
 * Quantos commits a base acumulou desde o ultimo bump de versao — e a partir de
 * quantos isso vira problema.
 *
 * O INCIDENTE, 2026-08-26. O `plugin.json` estava em 0.77.0 desde 25/08. A `main`
 * tinha 18 commits alem disso: quatro PRs de regra, tres defeitos de producao, uma
 * trava de borda nova. Nada disso estava rodando na maquina — porque o plugin que
 * EXECUTA nao e o clone, e o cache
 * `~/.claude/plugins/cache/<mkt>/<plugin>/<versao>/`, indexado pela VERSAO. Sem
 * bump, o `claude plugin update` nao tem versao nova para buscar e o snapshot de
 * ontem continua sendo o que roda.
 *
 * O `/saude` ja media essa distancia e dizia "o que EXECUTA esta atras: 18
 * commit(s) atras". O que faltava era alguem OLHAR no momento em que ainda da para
 * agir: o fecho. Era habito, e habito nao dispara — o bump nunca esteve escrito no
 * CONTRIBUTING.md, nem na skill `fechar`, nem nas 17 regras.
 *
 * Por que um teto em vez de "qualquer commit": logo depois de todo merge existe
 * pelo menos um commit sem release, e isso e' normal. Reclamar sempre seria ruido
 * que se aprende a ignorar — o defeito e o ACUMULO. O teto e' onde acumulo demais
 * comeca, e e' ajustavel por `--teto`.
 *
 * Uso:
 *   node scripts/conferir-versao.cjs                 # teto padrao
 *   node scripts/conferir-versao.cjs --teto 10
 *   node scripts/conferir-versao.cjs --json
 *   node scripts/conferir-versao.cjs --base origin/main
 *
 * Saida: exit 0 abaixo do teto (com a contagem impressa), exit 2 no teto ou acima.
 * Nao dando para medir — pasta sem git, historico raso, manifesto ilegivel —, sai
 * 0 com o motivo escrito. Falha ABERTA de proposito: isto nao e' guarda-corpo de
 * seguranca, e travar o fecho de quem trabalha num tarball seria pior que o
 * problema que resolve.
 */
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const RAIZ = path.resolve(__dirname, "..");
const MANIFESTO = path.join(".claude-plugin", "plugin.json");
const TETO_PADRAO = 5;

function git(args) {
  try {
    return execFileSync("git", ["-C", RAIZ, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

function valorDe(flag) {
  const i = process.argv.indexOf(`--${flag}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : null;
}

/** Versao declarada no manifesto, ou null se ilegivel. */
function versaoDoManifesto() {
  try {
    const m = JSON.parse(fs.readFileSync(path.join(RAIZ, MANIFESTO), "utf8"));
    return typeof m.version === "string" ? m.version : null;
  } catch {
    return null;
  }
}

/**
 * O commit do ultimo bump.
 *
 * `-G`, nao `-S`. A pickaxe `-S` acha commit onde o NUMERO DE OCORRENCIAS da
 * string muda — e trocar "0.77.0" por "0.78.0" nao muda a contagem de
 * `"version"`, que continua uma. A primeira versao deste script usava `-S` e
 * respondeu 271 commits em vez de 18, apontando para um commit de agosto que nao
 * tinha nada a ver. `-G` casa o PADRAO nas linhas adicionadas ou removidas do
 * diff, que e o que se quer aqui. Achado rodando o script contra a verdade
 * conhecida (0bb922c, 18 commits) em vez de aceitar o primeiro numero.
 *
 * Se o manifesto nunca mudou de versao, devolve null.
 */
function commitDoUltimoBump() {
  const sha = git(["log", "-1", "--format=%H", "-G\"version\":", "--", MANIFESTO]);
  return sha || null;
}

function medir(base, teto) {
  if (!git(["rev-parse", "--git-dir"])) {
    return { medivel: false, motivo: "esta pasta nao e repositorio git — nada a conferir" };
  }
  const versao = versaoDoManifesto();
  if (!versao) {
    return { medivel: false, motivo: `nao consegui ler a versao de ${MANIFESTO}` };
  }
  const bump = commitDoUltimoBump();
  if (!bump) {
    return { medivel: false, motivo: `nenhum commit de bump encontrado em ${MANIFESTO} — historico raso?` };
  }
  const cabeca = git(["rev-parse", base]);
  if (!cabeca) {
    return { medivel: false, motivo: `'${base}' nao resolve para um commit` };
  }
  const bruto = git(["rev-list", "--count", `${bump}..${cabeca}`]);
  if (bruto === null) {
    return { medivel: false, motivo: `nao consegui contar ${bump.slice(0, 7)}..${base}` };
  }
  const commits = Number(bruto);
  return {
    medivel: true,
    versao,
    base,
    bump: bump.slice(0, 7),
    cabeca: cabeca.slice(0, 7),
    commits,
    teto,
    estourou: commits >= teto,
  };
}

function main() {
  const teto = Number(valorDe("teto") || TETO_PADRAO);
  const base = valorDe("base") || "HEAD";
  const comoJson = process.argv.includes("--json");
  const r = medir(base, teto);

  if (comoJson) {
    console.log(JSON.stringify(r, null, 2));
    process.exit(r.medivel && r.estourou ? 2 : 0);
  }

  if (!r.medivel) {
    console.log(`versao: nao deu para medir — ${r.motivo}`);
    process.exit(0);
  }

  if (!r.estourou) {
    console.log(
      `ok    versao ${r.versao}: ${r.commits} commit(s) desde o bump ${r.bump} (teto ${r.teto})`
    );
    process.exit(0);
  }

  console.log(
    `RECUSADO: ${r.commits} commit(s) em '${r.base}' desde o ultimo bump de versao ` +
      `(${r.bump}), e o teto e ${r.teto}.\n` +
      `  versao declarada: ${r.versao}   base: ${r.cabeca}\n\n` +
      `O que EXECUTA nao e este clone: e o cache\n` +
      `  ~/.claude/plugins/cache/<marketplace>/<plugin>/${r.versao}/\n` +
      `indexado pela VERSAO. Sem bump nao existe versao nova para o\n` +
      `'claude plugin update' buscar, entao o trabalho fica na main e nao chega\n` +
      `na maquina de ninguem — inclusive na sua.\n\n` +
      `Suba a versao no ${MANIFESTO} (e o badge do README, que repete o numero),\n` +
      `num commit proprio. PATCH se o lote so consertou, MINOR se entrou coisa\n` +
      `nova ou mudou contrato — a tabela esta no CONTRIBUTING.md. Depois:
` +
      `  claude plugin marketplace update <marketplace>\n` +
      `Abra uma janela NOVA — o efeito nao alcanca as abertas.\n\n` +
      `Se o acumulo for proposital, o teto e ajustavel: --teto N.`
  );
  process.exit(2);
}

if (require.main === module) main();
module.exports = { medir, versaoDoManifesto, commitDoUltimoBump, TETO_PADRAO };
