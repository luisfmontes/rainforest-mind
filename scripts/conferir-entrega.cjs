#!/usr/bin/env node
"use strict";
/* Port de scripts/conferir-entrega.py — confere a entrega de um subagente, sem
 * dependencia externa (so biblioteca padrao do Node). Mesma interface de linha de
 * comando, mesmas checagens, mesmos codigos de saida do original em Python.
 *
 * POR QUE O PORT: as regras 11 e 12 EXIGEM este script na integracao de toda
 * entrega de agente, e `skills/executar` e `agents/executor.md` o citam pelo nome.
 * Enquanto ele era Python, a promessa do README ("so Node no caminho de execucao,
 * e o Claude Code nao garante Python") era falsa — bastava um dev sem Python para
 * a regra 12 virar texto sem mecanismo, do lado errado da unica coisa que este
 * repo nao aceita: trava que nao trava. O .py fica como GEMEO, no mesmo desenho de
 * ideias.py e jornada.py: a mesma bateria roda contra os dois, e e isso que prova
 * que o port nao perdeu checagem nenhuma.
 *
 * O P1 do relatorio de metodo de 2026-08-08 (o acervo e do usuario, fora do repo):
 *
 *   "Enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela
 *    deveria travar, ela nao trava nada."
 *
 * Naquele dia o agente RODOU `git rev-parse --show-toplevel`, recebeu o diretorio
 * principal do repo — que era a condicao de parada —, transcreveu a condicao
 * corretamente e escreveu um OK do lado. Na mesma entrega colou o pai do commit,
 * viu que divergia da base e se absolveu com "diferenca nao afeta a
 * funcionalidade", quando era justamente o commit que fazia o criterio de aceite
 * passar.
 *
 * Nenhuma regra de texto alcanca esse modo de falha, porque o texto ja estava la e
 * foi lido. O que alcanca e o veredito sair das maos de quem executou: a janela
 * principal roda isto ao receber a entrega, e o exit code nao se argumenta.
 *
 * As seis falhas dos dois relatorios e onde cada uma morre aqui:
 *
 *   worktree ignorado, trabalho no dir principal ....... checagem 1
 *   commit sobre base errada, auto-absolvido ........... checagem 2
 *   sujeira deixada no worktree ........................ checagem 3
 *   arquivo rastreado apagado como dano colateral (N3) . checagem 3
 *   mexeu no diretorio principal do usuario (N1) ....... checagem 4
 *   stash/pop movendo o HEAD do usuario (N1) ........... checagem 5
 *   arquivo criado no disco que nunca virou commit ..... checagem 6
 *
 * A checagem 6 nasceu da Issue #4 (2026-08-13): uma tarefa criou
 * `scripts/gerado/.gitignore` com o conteudo `*`, que ignora A SI MESMO — o
 * `git add -A` nunca o adicionou e ele nunca chegou ao commit. O agente relatou
 * o arquivo como criado e colou evidencia REAL: `ls -la` mostrando o arquivo,
 * `cat` mostrando o conteudo. Evidencia do DISCO, nunca do COMMIT. E a checagem
 * 3 tambem nao pega: `git status --porcelain` por desenho nao lista ignorado,
 * que e exatamente a categoria do arquivo que faltava. As cinco checagens
 * passaram e a entrega estava incompleta.
 *
 * Cada checagem imprime o comando literal e a saida CRUA antes do veredito: quem
 * ler o relatorio confere a conclusao contra a evidencia, sem confiar na conclusao.
 *
 * Uso tipico, com o que a janela principal ja sabia antes de despachar:
 *
 *   node scripts/conferir-entrega.cjs \
 *       --worktree C:/repo/.worktrees/agent-abc \
 *       --base 61be664 \
 *       --head-antes $(git -C C:/repo rev-parse HEAD)
 *
 * Exit 0 so quando tudo passa.
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

class Conferencia {
  constructor() {
    this.falhas = [];
    this.avisos = [];
    this.n = 0;
  }

  // -- execucao --------------------------------------------------------
  git(dir, ...args) {
    let r;
    try {
      r = spawnSync("git", ["-C", String(dir), ...args], {
        encoding: "utf8",
        maxBuffer: 32 * 1024 * 1024,
      });
    } catch {
      return [127, "git nao encontrado no PATH"];
    }
    if (!r || (r.error && r.error.code === "ENOENT")) {
      return [127, "git nao encontrado no PATH"];
    }
    if (r.error) return [127, String(r.error.message || r.error)];
    const saida = `${r.stdout || ""}${r.stderr || ""}`.trim();
    return [r.status === null ? 127 : r.status, saida];
  }

  // -- relato ----------------------------------------------------------
  abre(titulo) {
    this.n += 1;
    console.log(`\n${this.n}. ${titulo}`);
  }

  mostra(dir, ...args) {
    const [rc, out] = this.git(dir, ...args);
    console.log(`   $ git -C ${dir} ${args.join(" ")}`);
    const linhas = (out || "(vazio)").split(/\r?\n/);
    for (const linha of linhas.length ? linhas : ["(vazio)"]) {
      console.log(`     ${linha}`);
    }
    return [rc, out];
  }

  ok(msg) {
    console.log(`   OK   ${msg}`);
  }

  falha(msg) {
    console.log(`   FALHA  ${msg}`);
    this.falhas.push(`${this.n}. ${msg}`);
  }

  aviso(msg) {
    console.log(`   aviso  ${msg}`);
    this.avisos.push(`${this.n}. ${msg}`);
  }
}

/** Compara caminho sem tropecar em barra invertida, maiuscula e link. */
// `realpathSync.native` primeiro, e nao por gosto: no Windows o `realpathSync`
// puro do Node NAO expande nome curto 8.3 — ele devolve `C:/Users/RUNNER~1/...`
// como recebeu. O git, do outro lado, sempre responde na forma longa
// (`C:/Users/runneradmin/...`). Comparar as duas por texto reprova uma entrega
// correta, e esta funcao e exatamente quem decide se o worktree do briefing e o
// worktree de verdade — ou seja, o falso "nao integre" da regra 12 nascia aqui.
//
// Medido em 2026-08-17 (Issue #16), mesmo diretorio pelas duas grafias:
//   realpathSync         curto -> .../tmp~1.pcq/uma-pa~1          <- nao bate
//   realpathSync         longo -> .../tmp.pcqqh0lbsn/uma-pasta-...
//   realpathSync.native  curto -> .../tmp.pcqqh0lbsn/uma-pasta-... <- bate
//   realpathSync.native  longo -> .../tmp.pcqqh0lbsn/uma-pasta-...
//
// A cadeia de fallback existe porque `.native` propaga erro do SO em caminho que
// nao existe (e em alguns caminhos de rede), e aqui caminho inexistente tem de
// virar comparacao textual, nao excecao.
function norm(p) {
  let alvo;
  try {
    alvo = fs.realpathSync.native(p);
  } catch {
    try {
      alvo = fs.realpathSync(p);
    } catch {
      alvo = path.resolve(p);
    }
  }
  return alvo.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

function erroArgs(msg) {
  process.stderr.write(`conferir-entrega.cjs: erro: ${msg}\n`);
  process.exit(2); // 2 = erro de uso, igual ao argparse do gemeo em Python
}

const OPCOES = {
  worktree: { dest: "worktree", exige: true },
  base: { dest: "base" },
  commit: { dest: "commit", padrao: "HEAD" },
  "repo-principal": { dest: "repo_principal" },
  "head-antes": { dest: "head_antes" },
  "permite-sujeira": { dest: "permite_sujeira", flag: true },
  paralelo: { dest: "paralelo", flag: true },
  // Repetivel: o briefing costuma prometer mais de um arquivo por tarefa.
  espera: { dest: "espera", lista: true },
};

function parseArgs(argv) {
  const a = { commit: "HEAD", permite_sujeira: false, paralelo: false, espera: [] };
  let i = 0;
  while (i < argv.length) {
    const tok = argv[i];
    if (!tok.startsWith("--")) erroArgs(`argumento inesperado: ${tok}`);
    const o = OPCOES[tok.slice(2)];
    if (!o) erroArgs(`opcao desconhecida: ${tok}`);
    if (o.flag) {
      a[o.dest] = true;
      i += 1;
      continue;
    }
    const val = argv[i + 1];
    if (val === undefined) erroArgs(`opcao ${tok} exige valor`);
    if (o.lista) a[o.dest].push(val);
    else a[o.dest] = val;
    i += 2;
  }
  for (const [chave, o] of Object.entries(OPCOES)) {
    if (o.exige && !a[o.dest]) erroArgs(`opcao obrigatoria faltando: --${chave}`);
  }
  return a;
}

function ehDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

/** Extrai conjunto de arquivos que o agente tocou. */
function arquivosAgente(c, wt, base, commit) {
  let rc, saida;
  if (base) {
    [rc, saida] = c.mostra(wt, "diff", "--name-only", `${base}..${commit}`);
  } else {
    [rc, saida] = c.mostra(wt, "show", "--name-only", "--format=", commit);
  }
  if (rc !== 0) return new Set();
  const linhas = saida ? saida.split(/\r?\n/).filter((l) => l.length > 0) : [];
  return new Set(linhas.map((l) => l.replace(/\\/g, "/").toLowerCase()));
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  const c = new Conferencia();
  const wt = a.worktree;

  if (!ehDir(wt)) {
    process.stderr.write(`erro: worktree '${wt}' nao existe\n`);
    return 2;
  }

  // ------------------------------------------------------------------
  c.abre("Onde ele mexeu — o worktree e mesmo um worktree?");
  let [rc, top] = c.mostra(wt, "rev-parse", "--show-toplevel");
  if (rc !== 0) {
    c.falha("nao e repositorio git");
    top = "";
  }
  const [, gitdir] = c.mostra(wt, "rev-parse", "--git-dir");
  const [, common] = c.git(wt, "rev-parse", "--git-common-dir");

  let principal = a.repo_principal;
  if (!principal && common) {
    const abs = path.isAbsolute(common) ? common : path.join(wt, common);
    principal = path.dirname(path.resolve(abs));
  }

  if (top && norm(top) !== norm(wt)) {
    c.falha(`o toplevel (${top}) nao e o worktree do briefing (${wt})`);
  } else if (top) {
    c.ok("o toplevel bate com o worktree do briefing");
  }

  if (!gitdir.replace(/\\/g, "/").includes("worktrees")) {
    c.falha(
      `o git-dir e '${gitdir}' — sem 'worktrees' no meio isto NAO e worktree linkado, ` +
        "e o agente trabalhou no repo principal. Foi esta a falha de 2026-08-08."
    );
  } else {
    c.ok("git-dir aponta para worktree linkado");
  }

  if (principal && top && norm(principal) === norm(top)) {
    c.falha(`worktree e repo principal sao o mesmo lugar (${principal})`);
  }

  // ------------------------------------------------------------------
  c.abre("De onde ele partiu — a base do commit entregue");
  const [rcLog, linha] = c.mostra(wt, "log", "--format=%H %P", "-1", a.commit);
  if (rcLog !== 0) {
    c.falha(`commit '${a.commit}' nao resolve no worktree`);
  } else if (a.base) {
    const partes = linha.split(/\s+/).filter(Boolean);
    const entregue = partes[0] || "";
    const pais = partes.slice(1);
    const [rcAnc] = c.git(wt, "merge-base", "--is-ancestor", a.base, entregue);
    const paiDireto = pais.some((p) => p.startsWith(a.base) || a.base.startsWith(p));
    if (paiDireto) {
      c.ok(`a base ${a.base} e pai direto do commit entregue`);
    } else if (rcAnc === 0) {
      c.aviso(`a base ${a.base} nao e pai direto, mas e ancestral — houve commit no meio`);
    } else {
      c.falha(
        `a base ${a.base} NAO esta na historia de ${entregue.slice(0, 12)} — o trabalho saiu de outro ` +
          "lugar. 'Nao afeta a funcionalidade' e conclusao da janela principal, nunca do agente."
      );
    }
  } else {
    c.aviso("sem --base para conferir; o briefing devia ter fixado uma");
  }

  // ------------------------------------------------------------------
  c.abre("O que ficou solto no worktree");
  const [, st] = c.mostra(wt, "status", "--porcelain");
  const linhasSt = st ? st.split(/\r?\n/).filter((l) => l.length > 0) : [];
  const apagados = linhasSt.filter((l) => l.slice(0, 2).trim() === "D");
  if (apagados.length) {
    c.falha(
      `${apagados.length} arquivo(s) RASTREADO(S) apagado(s) — dano colateral (falha N3): ` +
        apagados.slice(0, 5).map((l) => l.slice(3)).join(", ")
    );
  }
  if (linhasSt.length && !a.permite_sujeira) {
    c.falha(`${linhasSt.length} entrada(s) nao commitada(s) — a entrega nao esta no commit`);
  } else if (linhasSt.length) {
    c.aviso(`${linhasSt.length} entrada(s) nao commitada(s), dispensado por --permite-sujeira`);
  } else {
    c.ok("worktree limpo, tudo o que ele fez esta no commit");
  }

  // ------------------------------------------------------------------
  if (principal && ehDir(principal) && norm(principal) !== norm(wt)) {
    c.abre(`O repo principal foi tocado? (${principal})`);
    const [, stp] = c.mostra(principal, "status", "--porcelain");
    const linhasStp = stp ? stp.split(/\r?\n/).filter((l) => l.length > 0) : [];

    if (a.paralelo && linhasStp.length) {
      // Modo cruzamento: extrai arquivos que o agente tocou
      const arquivos = arquivosAgente(c, wt, a.base, a.commit);
      const caminhosSujos = linhasStp.map((l) => {
        // Descarta 3 primeiros caracteres do status, trata rename
        let p = l.slice(3);
        const partes = p.split(" -> ");
        p = partes.length > 1 ? partes[1] : partes[0];
        return p.replace(/\\/g, "/").toLowerCase();
      });
      const cruzamento = caminhosSujos.filter((p) => arquivos.has(p));

      if (cruzamento.length) {
        c.falha(
          `${cruzamento.length} arquivo(s) sujo(s) no principal e tocado(s) pelo agente: ` +
            cruzamento.slice(0, 5).join(", ")
        );
      } else {
        c.aviso(
          `${linhasStp.length} alteracao(oes) no principal, nenhuma nos arquivos do agente`
        );
      }
    } else if (linhasStp.length) {
      c.falha(
        `${linhasStp.length} alteracao(oes) no diretorio principal do usuario — o agente ` +
          "devia estar isolado no worktree. Foi a falha N1 de 2026-08-08."
      );
    } else {
      c.ok("diretorio principal intacto");
    }

    c.abre("O HEAD do repo principal se mexeu?");
    const [, headAgora] = c.mostra(principal, "rev-parse", "HEAD");
    if (!a.head_antes) {
      c.aviso("sem --head-antes; registre o HEAD antes de despachar para esta checagem valer");
    } else if (headAgora.startsWith(a.head_antes) || a.head_antes.startsWith(headAgora)) {
      c.ok("HEAD do repo principal inalterado");
    } else {
      // HEAD mexeu. Verifica se foi avanco (HEAD anterior é ancestral)
      const [rcAnc] = c.git(principal, "merge-base", "--is-ancestor", a.head_antes, "HEAD");
      if (rcAnc === 0) {
        // Avançou: contar commits
        const [, contagem] = c.mostra(principal, "rev-list", "--count", `${a.head_antes}..HEAD`);
        c.aviso(`o HEAD do principal avancou ${contagem} commit(s) desde o despacho`);
      } else {
        // Recuo ou movimento lateral: falha
        c.falha(
          `o HEAD do repo principal era ${a.head_antes} e virou ${headAgora.slice(0, 12)} — algo moveu ` +
            "o HEAD do usuario (stash/pop, checkout). Falha N1 de 2026-08-08."
        );
      }
    }
  } else {
    c.abre("Repo principal");
    c.aviso("nao identifiquei um repo principal distinto do worktree — checagens 4 e 5 puladas");
  }

  // ------------------------------------------------------------------
  // O que o briefing prometeu esta NO COMMIT? `git status --porcelain` da
  // checagem 3 nao lista arquivo ignorado, e `ls`/`cat` do agente provam o
  // disco. So a arvore do commit responde a pergunta que interessa.
  c.abre("O que a tarefa prometia criar esta MESMO no commit?");
  if (!a.espera.length) {
    c.aviso(
      "sem --espera; esta checagem so vale se o briefing disser que arquivo a tarefa devia criar"
    );
  } else {
    for (const alvo of a.espera) {
      const [rcT, dentro] = c.mostra(wt, "ls-tree", "-r", "--name-only", a.commit, "--", alvo);
      if (rcT === 0 && dentro) {
        c.ok(`'${alvo}' esta no commit entregue`);
        continue;
      }
      if (!fs.existsSync(path.join(wt, alvo))) {
        c.falha(`'${alvo}' nao esta no commit e nao existe no disco — a tarefa nao criou o arquivo`);
        continue;
      }
      const [rcIg, regra] = c.git(wt, "check-ignore", "-v", "--", alvo);
      const porque =
        rcIg === 0 && regra
          ? `um .gitignore o excluiu: ${regra.split(/\r?\n/)[0]}`
          : "existe no disco mas nunca foi adicionado ao indice";
      c.falha(
        `'${alvo}' EXISTE NO DISCO e NAO esta no commit — ${porque}. ` +
          "ls/cat do agente provam o disco, nunca o commit (Issue #4, 2026-08-13)."
      );
    }
  }

  // ------------------------------------------------------------------
  console.log("\n" + "=".repeat(66));
  if (c.falhas.length) {
    console.log(`REPROVADO — ${c.falhas.length} falha(s):`);
    for (const f of c.falhas) console.log(`  - ${f}`);
    console.log("\nNao integre. Se alguma falha for aceitavel, a dispensa e sua, por escrito,");
    console.log("nesta janela — nunca do agente que produziu a entrega.");
    return 1;
  }
  if (c.avisos.length) {
    console.log(`APROVADO com ${c.avisos.length} aviso(s):`);
    for (const w of c.avisos) console.log(`  - ${w}`);
    return 0;
  }
  console.log(`APROVADO — as ${c.n} checagens passaram.`);
  return 0;
}

process.exitCode = main();
