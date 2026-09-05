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
 * Alem do teto de commits, o script compara a versao declarada no manifesto
 * local com a de `origin/main`: se a local nao for MAIOR (empatou ou ficou
 * para tras), recusa citando os dois numeros — reverter a versao a mao para
 * uma ja publicada, ou esquecer de subi-la, tambem e' "nao ha versao nova
 * para o `claude plugin update` buscar", so que sem nenhum commit acumulado.
 * Comparacao e' semver por componente numerico (major.minor.patch), nunca
 * comparacao de string. Sem `origin/main` resolvivel — clone sem remoto,
 * tarball, fixture de bateria — a comparacao e' pulada e a saida diz isso;
 * nunca vira recusa nem exit `4`.
 *
 * Saida:
 *   exit 0  medido, versao local maior que a de origin/main (ou comparacao
 *           pulada) e contagem de commits abaixo do teto
 *   exit 2  RECUSADO — versao local nao-maior que a de origin/main, OU
 *           contagem de commits no teto ou acima
 *   exit 4  NAO MEDIU — o repositorio E um plugin (tem
 *           `.claude-plugin/plugin.json`) e o manifesto nao pode ser lido
 *           (ausente do JSON valido, ou sem campo `version` string)
 *   exit 0  "nao ha o que conferir aqui" — pasta sem git, repositorio que nao
 *           e um plugin, ou historico raso sem nenhum commit de bump. Falha
 *           ABERTA de proposito: isto nao e' guarda-corpo de seguranca, e
 *           travar o fecho de quem trabalha fora do repositorio do plugin
 *           seria pior que o problema que resolve. Distinto do exit `4`
 *           acima: aqui nao ha o que conferir; la, havia e a leitura falhou.
 */
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

/**
 * Descobre a raiz do repositório git do cwd (diretório de execução),
 * não da instalação do plugin. Se o cwd não estiver em um repositório git,
 * devolve null.
 */
function raizDoCwd() {
  try {
    return execFileSync("git", ["rev-parse", "--show-toplevel"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      cwd: process.cwd(),
    }).trim();
  } catch {
    return null;
  }
}

const RAIZ = raizDoCwd() || path.resolve(__dirname, "..");
const MANIFESTO = path.join(".claude-plugin", "plugin.json");
// Caminho de refspec do git (`git show ref:caminho`) usa SEMPRE barra normal,
// independente de SO — nao e' o mesmo valor que MANIFESTO acima no Windows.
const MANIFESTO_REF = ".claude-plugin/plugin.json";
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
 * Versao declarada no manifesto de `origin/main`, ou null se nao deu para ler
 * (origin/main nao resolve, o arquivo nao existe la, saida vazia, ou o JSON e'
 * invalido/sem campo `version` string).
 *
 * `MSYS_NO_PATHCONV=1` no env: sem isso o Git Bash converte
 * `origin/main:.claude-plugin/plugin.json` num caminho Windows e o comando
 * falha EM SILENCIO, devolvendo vazio — e vazio vira "nao consegui ler", nunca
 * "as versoes sao iguais" (D6 do design).
 */
function versaoDeOrigemMain() {
  try {
    const raw = execFileSync(
      "git",
      ["-C", RAIZ, "show", `origin/main:${MANIFESTO_REF}`],
      {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        env: { ...process.env, MSYS_NO_PATHCONV: "1" },
      }
    );
    if (!raw || !raw.trim()) return null;
    const m = JSON.parse(raw);
    return typeof m.version === "string" ? m.version : null;
  } catch {
    return null;
  }
}

/** "1.2.3" -> [1,2,3], ou null se nao parseavel como semver. */
function parseSemver(v) {
  if (typeof v !== "string") return null;
  const m = /^(\d+)\.(\d+)\.(\d+)/.exec(v.trim());
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

/**
 * Compara duas versoes por componente numerico (major, minor, patch) — NUNCA
 * comparacao de string: `"0.9.0" > "1.3.0"` e' verdadeiro em ordem lexicografica,
 * e e' justamente um dos casos que precisa recusar (D4 do design).
 * Devolve 1 se a>b, 0 se a=b, -1 se a<b, ou null se alguma nao parseia.
 */
function compararSemver(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa || !pb) return null;
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] > pb[i] ? 1 : -1;
  }
  return 0;
}

/**
 * Compara a versao local com a de `origin/main`. Sem `origin/main` resolvivel,
 * ou sem versao parseavel dos dois lados, a comparacao e' pulada — nunca vira
 * recusa nem falha de leitura (D5 do design).
 */
function compararComOrigemMain(versaoLocal) {
  const versaoRemota = versaoDeOrigemMain();
  if (versaoRemota === null) {
    return {
      comparouVersao: false,
      motivoNaoComparou: `origin/main nao resolve, ou ${MANIFESTO_REF} nao existe la`,
      versaoOrigemMain: null,
      versaoMaior: null,
    };
  }
  const cmp = compararSemver(versaoLocal, versaoRemota);
  if (cmp === null) {
    return {
      comparouVersao: false,
      motivoNaoComparou: `versao '${versaoLocal}' ou '${versaoRemota}' nao e' semver reconhecivel`,
      versaoOrigemMain: versaoRemota,
      versaoMaior: null,
    };
  }
  return {
    comparouVersao: true,
    motivoNaoComparou: null,
    versaoOrigemMain: versaoRemota,
    versaoMaior: cmp > 0,
  };
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
  // Primeiro, verifica se o RAIZ é um repositório git
  if (!git(["rev-parse", "--git-dir"])) {
    // Se raizDoCwd() devolveu null, o cwd está fora de um repo git
    if (!raizDoCwd()) {
      return { medivel: false, motivo: "esta pasta nao e repositorio git — nada a conferir" };
    }
    // Caso contrário, é um repo git sem .claude-plugin/plugin.json
    return { medivel: false, motivo: "este repositorio nao e um plugin — nada a conferir" };
  }

  // Verifica se o arquivo de manifesto existe
  const manifestoPath = path.join(RAIZ, MANIFESTO);
  if (!fs.existsSync(manifestoPath)) {
    // O repositório é um git mas não é um plugin
    return { medivel: false, motivo: "este repositorio nao e um plugin — nada a conferir" };
  }

  const versao = versaoDoManifesto();
  if (!versao) {
    // O repositorio E' um plugin (o manifesto existe) e a leitura falhou —
    // distinto dos ramos acima, em que nao ha o que conferir. Isto e' D1/D2
    // do design: "eu deveria conferir e nao consegui" vira exit 4 no main().
    return {
      medivel: false,
      motivo: `nao consegui ler a versao de ${MANIFESTO}`,
      falhaDeLeitura: true,
    };
  }

  const comparacao = compararComOrigemMain(versao);

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
    ...comparacao,
  };
}

/** Exit code correspondente ao resultado de medir() — usado nos dois modos. */
function codigoDeSaida(r) {
  if (!r.medivel) return r.falhaDeLeitura ? 4 : 0;
  if (r.comparouVersao && r.versaoMaior === false) return 2;
  if (r.estourou) return 2;
  return 0;
}

function main() {
  const teto = Number(valorDe("teto") || TETO_PADRAO);
  const base = valorDe("base") || "HEAD";
  const comoJson = process.argv.includes("--json");
  const r = medir(base, teto);

  if (comoJson) {
    console.log(JSON.stringify(r, null, 2));
    process.exit(codigoDeSaida(r));
  }

  if (!r.medivel) {
    console.log(`versao: nao deu para medir — ${r.motivo}`);
    process.exit(r.falhaDeLeitura ? 4 : 0);
  }

  if (r.comparouVersao && r.versaoMaior === false) {
    console.log(
      `RECUSADO: versao declarada ${r.versao} nao e' maior que a de origin/main ` +
        `(${r.versaoOrigemMain}).\n` +
        `  declarada: ${r.versao}   origin/main: ${r.versaoOrigemMain}\n\n` +
        `Sem numero maior nao existe versao nova para o 'claude plugin update'\n` +
        `buscar. Suba a versao no ${MANIFESTO} (e o badge do README, que repete\n` +
        `o numero), num commit proprio — PATCH se o lote so consertou, MINOR se\n` +
        `entrou coisa nova ou mudou contrato.`
    );
    process.exit(2);
  }

  const notaComparacao = r.comparouVersao
    ? ` (origin/main: ${r.versaoOrigemMain})`
    : ` (nao comparei com origin/main: ${r.motivoNaoComparou})`;

  if (!r.estourou) {
    console.log(
      `ok    versao ${r.versao}: ${r.commits} commit(s) desde o bump ${r.bump} (teto ${r.teto})${notaComparacao}`
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
