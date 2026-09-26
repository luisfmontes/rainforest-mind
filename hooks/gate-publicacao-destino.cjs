#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse — barra escrita de dados sensíveis em arquivo rastreado.
 * Protege contra: dados sensíveis (telefone/JID/CPF) em arquivo versionado
 * Não protege contra: dados sensíveis em arquivo gitignorado
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
const { resolverRaiz } = require("./lib/raiz.cjs");
const { temMarcadorNoConteudo } = require("./lib/marcador-dados.cjs");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Validade do cache de visibilidade de repositório, em ms.
 * Um repositório privado que muda para público é caso raro; uma semana é
 * conservador e cobre a maioria dos casos sem rede constante.
 */
const CACHE_VISIBILIDADE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 dias

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */

/**
 * Obtém o caminho do cache de visibilidade de repositório.
 */
function obterCachePath() {
  const { raiz } = resolverRaiz();
  if (!raiz) return null;
  return path.join(raiz, "cache-visibilidade-repo.json");
}

/**
 * Lê o cache de visibilidade de repositório.
 */
function lerCache() {
  const cachePath = obterCachePath();
  if (!cachePath) return {};
  try {
    const conteudo = fs.readFileSync(cachePath, "utf8");
    return JSON.parse(conteudo) || {};
  } catch {
    return {};
  }
}

/**
 * Grava o cache de visibilidade de repositório.
 */
function gravarCache(cache) {
  const cachePath = obterCachePath();
  if (!cachePath) return;
  try {
    const dir = path.dirname(cachePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(cachePath, JSON.stringify(cache, null, 2), "utf8");
  } catch {
    // erro ao gravar cache
  }
}

// Memoria do PROCESSO. `bloqueia` precisa da visibilidade duas vezes -- para
// decidir e para escrever a mensagem -- e sem isto o `gh` seria invocado duas
// vezes na mesma gravacao.
const visibilidadeMemorizada = new Map();

/**
 * Visibilidade do remoto de destino: "privada", "publica" ou "desconhecida".
 *
 * D6 (zerar-issues-4, #253). A lista de termos proibidos existe para proteger
 * repositorio PUBLICO -- a propria mensagem de bloqueio dizia "Arquivos
 * versionados em repo publico nao tem como desaparecer" --, mas o hook nunca
 * conferiu visibilidade. Aplicada a um repositorio privado de trabalho, ela
 * torna impossivel documentar o trabalho no lugar onde o trabalho mora: medido
 * em 2026-09-14, 18 ocorrencias num design doc, todas do prefixo dos fontes e
 * do nome da organizacao, que sao o proprio assunto daquele repositorio.
 *
 * FALHA FECHADA. So "privada" libera, e so quando o `gh` respondeu JSON com
 * `isPrivate: true`. Sem remoto, sem `gh`, `gh` com exit != 0, saida ilegivel,
 * ou `RAINFOREST_GATE_SEM_REDE=1`: "desconhecida", que bloqueia como antes. Um
 * repositorio publico novo nunca passa por omissao.
 *
 * O cache em disco guarda SO "publica". Cachear "desconhecida"
 * transformaria uma indisponibilidade de rede de dez segundos em uma semana de
 * decisao errada -- e no sentido que importa, porque e a resposta que decide se
 * o termo vaza ou nao. E `privada` e essa mesma resposta pelo lado que
 * LIBERA, num arquivo que nenhum gate protege -- por isso tambem nao se
 * cacheia, e se re-pergunta ao `gh` a cada achado.
 */
function visibilidadeDoRepo(gitTop) {
  if (visibilidadeMemorizada.has(gitTop)) return visibilidadeMemorizada.get(gitTop);
  const v = calcularVisibilidade(gitTop);
  visibilidadeMemorizada.set(gitTop, v);
  return v;
}

/**
 * `owner/repo` de TODOS os remotos do GitHub cadastrados, sem repetir.
 *
 * Nao usa `remotoDeDestino`, e a diferenca e de proposito. Aquela funcao
 * responde "para onde ESTA branch publica", e `paiJaPublicado` depende disso
 * (D19: aceitar qualquer remoto reabria a porta do espelho descartavel). Aqui
 * a pergunta e outra: "existe algum destino publico ao alcance de um push?".
 *
 * Medido em 2026-09-15: com `origin` privado e um fork publico cadastrado,
 * numa branch SEM upstream, `remotoDeDestino` caia em `origin`, o gate
 * consultava o repositorio errado, o segredo entrava no commit, e
 * `git push fork main` publicava. Branch nova sem upstream e o caso comum, nao
 * o raro. Falha fechada: basta um remoto publico para bloquear.
 */
function repositoriosDoGitHub(gitTop) {
  const nomes = (git(gitTop, ["remote"]) || "").split(/\r?\n/).map((n) => n.trim()).filter(Boolean);
  const achados = [];
  for (const nome of nomes) {
    const url = git(gitTop, ["remote", "get-url", nome]);
    if (!url) continue;
    const m = url.match(/(?:https:\/\/|git@)(?:www\.)?github\.com[:/]([\w.-]+)\/([\w.-]+?)(?:\.git)?$/);
    if (!m) continue;
    const ownerRepo = `${m[1]}/${m[2]}`;
    if (!achados.includes(ownerRepo)) achados.push(ownerRepo);
  }
  return achados;
}

function calcularVisibilidade(gitTop) {
  if (process.env.RAINFOREST_GATE_SEM_REDE === "1") return "desconhecida";

  const repos = repositoriosDoGitHub(gitTop);
  if (repos.length === 0) return "desconhecida";

  // So libera quando TODOS sao privados. Um publico basta para bloquear, e um
  // desconhecido tambem -- a mesma falha fechada que o resto deste gate usa.
  let veredito = "privada";
  for (const ownerRepo of repos) {
    const v = visibilidadeDeUmRepo(ownerRepo);
    if (v === "publica") return "publica";
    if (v === "desconhecida") veredito = "desconhecida";
  }
  return veredito;
}

function visibilidadeDeUmRepo(ownerRepo) {
  // O cache guarda SO `publica` -- a resposta que MANTEM o bloqueio.
  //
  // A primeira versao guardava as duas e aceitava `privada` do disco. O
  // arquivo e `<raiz de dados>/cache-visibilidade-repo.json`, fora de repo
  // git: nenhum gate confere escrita ali, e um `Write` basta. Medido em
  // 2026-09-15, com o `gh` respondendo PUBLICO o tempo todo:
  //
  //   sem cache                                exit 2
  //   plantado privada, em = agora             exit 0
  //   plantado privada, em = +100 anos         exit 0   (para sempre)
  //   plantado privada, em = 8 dias atras      exit 2
  //
  // A mensagem deste mesmo hook diz ao subagente para NAO criar arquivo nem
  // variavel que desligue a trava; este era esse arquivo. O docblock de
  // `visibilidadeDoRepo` ja dizia por que `desconhecida` nao se cacheia --
  // e a resposta que decide se o termo vaza. `privada` e a MESMA resposta,
  // do lado que libera, e o argumento vale com mais forca ainda.
  //
  // O custo e baixo porque `bloqueia()` so pergunta a visibilidade quando JA
  // houve achado: em repo privado o `gh` roda uma vez por achado, nao por
  // escrita. O cache continua existindo para o caso publico, que e o que se
  // repete numa sessao de muitos achados.
  //
  // `em` no futuro nao vale: `Date.now() - em < TTL` e verdade para qualquer
  // instante futuro, entao uma entrada com data adiantada nunca expirava.
  const agora = Date.now();
  const cache = lerCache();
  const guardado = cache[ownerRepo];
  // `em` tem de ser NUMERO. A auditoria mediu a forma com `em` como string
  // (2026-09-15): `"123" <= agora` coage e passa, e a entrada plantada valia.
  // Hoje isso so deixaria o gate mais rigido (o cache guarda apenas
  // `publica`), mas ler tipo errado de um arquivo que qualquer um escreve e
  // exatamente o que a A08 chama de integridade de dado nao verificada.
  if (guardado && typeof guardado.em === "number" && Number.isFinite(guardado.em)
      && guardado.em <= agora
      && agora - guardado.em < CACHE_VISIBILIDADE_TTL_MS
      && guardado.visibilidade === "publica") {
    return "publica";
  }

  let visibilidade = "desconhecida";
  try {
    // `RAINFOREST_GH` e costura de teste, e existe por uma razao de plataforma:
    // no Windows o `execFileSync` resolve pelo PATHEXT, entao um duble de `gh`
    // escrito como script sem extensao nunca roda, por mais que esteja no PATH
    // com bit de execucao -- a chamada cai no catch e o caso de teste passa a
    // medir a ausencia do duble, nao a visibilidade. Aceita linha de comando
    // ("node /caminho/stub"), e os argumentos sao passados como VETOR: nada de
    // shell, nada de interpolacao.
    const gh = (process.env.RAINFOREST_GH || "gh").split(" ").filter(Boolean);
    const saida = execFileSync(gh[0], [...gh.slice(1), "repo", "view", ownerRepo, "--json", "isPrivate"], {
      encoding: "utf8", timeout: 10000, stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const j = JSON.parse(saida);
    if (j && j.isPrivate === true) visibilidade = "privada";
    else if (j && j.isPrivate === false) visibilidade = "publica";
  } catch {
    return "desconhecida"; // nao cacheia: ver docblock
  }
  if (visibilidade === "desconhecida") return "desconhecida";

  if (visibilidade === "publica") {
    cache[ownerRepo] = { visibilidade, em: Date.now() };
    gravarCache(cache);
  }
  return visibilidade;
}

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
 * O gate está desligado por arquivo `.rainforest-gate-off`?
 *
 * Issue #265: o arquivo é untracked, então `git worktree add` não o leva para
 * a raiz do worktree novo — quem cria o toggle no checkout PRINCIPAL via um
 * worktree linkado do mesmo repo (`gitTop` ali é a raiz do worktree, não a do
 * principal) tinha o gate voltando a bloquear lá, mesmo com o arquivo presente
 * no repo.
 *
 * `gitTop` continua sendo a raiz de onde o comando roda — é dali que o resto
 * do hook lê conteúdo, visibilidade e `.gitignore`, e isso não muda. Este
 * arquivo é o ÚNICO lido também na raiz do checkout principal, deduzida via
 * `--git-common-dir` (mesmo padrão de `scripts/limpar-worktrees.cjs:365-379`):
 * aponta para o `.git` do principal mesmo a partir de um worktree, e
 * `path.dirname()` do resultado (quando termina em `.git`) dá a raiz dele.
 *
 * Falha ao medir o common-dir não apaga o comportamento de hoje: a checagem
 * do próprio `gitTop` roda sempre, a do principal é só um OR a mais.
 */
function desligadoPorArquivo(gitTop) {
  try {
    if (fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) return true;
  } catch {}
  try {
    const commonDir = git(gitTop, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
    if (commonDir && path.basename(commonDir) === ".git") {
      const raizPrincipal = path.dirname(commonDir);
      if (raizPrincipal !== gitTop && fs.existsSync(path.join(raizPrincipal, ".rainforest-gate-off"))) return true;
    }
  } catch {}
  return false;
}

/**
 * Detecta se o arquivo **em disco** tem o marcador que dispensa a conferência.
 * Marcador: `rainforest-gate: dados-de-exemplo` nas 5 primeiras linhas do
 * arquivo (hooks/lib/marcador-dados.cjs, Issue #293) — fora dessa janela não conta.
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
    return temMarcadorNoConteudo(conteudo);
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
 * Filtra achados comparando por multiconjunto (id + trecho).
 * Retorna apenas os achados de `novos` que não aparecem em `antigos`.
 *
 * Issue #322: o gate barra só o que a edição INTRODUZ, não o que já estava.
 * Compara por `id` + `trecho` (redigido, que identifica sem expor o dado).
 * Dois achados novos onde havia um → sobra um → barra.
 *
 * Falha fechada: se `antigos` é null/inválido, retorna `novos` (barra tudo).
 */
function soIntroduzidos(novos, antigos) {
  // Constrói mapa de contagem de achados antigos por chave (id + trecho)
  const contadorAntigos = new Map();
  if (antigos && Array.isArray(antigos)) {
    for (const a of antigos) {
      if (a && typeof a.id === "string" && typeof a.trecho === "string") {
        const chave = a.id + "\u0000" + a.trecho;
        contadorAntigos.set(chave, (contadorAntigos.get(chave) || 0) + 1);
      }
    }
  }

  // Filtra: mantém novos achados que não estão em antigos (multiconjunto)
  const sobra = [];
  if (novos && Array.isArray(novos)) {
    for (const n of novos) {
      if (n && typeof n.id === "string" && typeof n.trecho === "string") {
        const chave = n.id + "\u0000" + n.trecho;
        const saldo = contadorAntigos.get(chave) || 0;
        if (saldo > 0) {
          contadorAntigos.set(chave, saldo - 1);
        } else {
          sobra.push(n);
        }
      } else {
        // Achado malformado: falha fechada, mantém para bloquear
        sobra.push(n);
      }
    }
  }
  return sobra;
}

/**
 * Formata a mensagem de bloqueio com os achados.
 */
function mensagemBloqueio(achados, arquivo, ehSubagente, visibilidade) {
  let msg = `BLOQUEADO pelo gate de publicação do rainforest-mind.\n\n` +
    `Arquivo: ${arquivo}\n` +
    `Razão: este arquivo é versionado (rastreado por git) e contém dados sensíveis.\n\n` +
    `Trechos encontrados:\n`;

  for (const a of achados) {
    msg += `\n  linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}\n`;
    msg += `    ${a.o_que}\n`;
    msg += `    → ${a.faca}\n`;
  }

  let msgVisibilidade = "";
  if (visibilidade === "publica") {
    msgVisibilidade = `\n\nRepositório: visibilidade pública, apurada por 'gh repo view'. `;
  } else if (visibilidade === "desconhecida") {
    msgVisibilidade = `\n\nRepositório: visibilidade desconhecida — bloqueado por precaução. `;
  }
  msg += msgVisibilidade;

  msg += `\n\nArquivos versionados em repo público não têm como "desaparecer". `;
  msg += `Filter-branch\nremove de uma branch, mas em rede de fork o objeto continua `;
  msg += `servido por SHA\ne só o Support do GitHub consegue remover do storage da rede.\n`;
  msg += `Corrija o conteúdo e rode de novo.\n\n` +
    `ATENÇÃO — PreToolUse aborta a CHAMADA INTEIRA, não só a ferramenta:\n` +
    `  Um 'git add X && git commit' bloqueado não rodou o 'git add'; o índice fica\n` +
    `  com a versão velha e o gate repete o achado depois da correção, parecendo\n` +
    `  que a edição não gravou. Separe: 'git add', verifique com 'git show :<arquivo>',\n` +
    `  depois 'git commit'.\n\n`;

  const saidas = ehSubagente
    ? `PARE e reporte isto para a janela principal — ela decide como seguir.\n` +
      `NÃO crie arquivo nem variável para desativar esta trava: a decisão não é sua,\n` +
      `e desativá-la para si mesmo é o contorno que esta trava existe para impedir.\n`
    : `As duas saídas de emergência NÃO valem no MESMO comando:\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente: precisa estar na sessão (export),\n` +
      `    não funciona como prefixo inline ('RAINFOREST_GATE_OFF=1 git commit');\n` +
      `  - arquivo .rainforest-gate-off: é conferido ANTES do hook rodar, então\n` +
      `    'touch .rainforest-gate-off && git commit' é bloqueado (usa outro 'git add' depois).\n\n` +
      `Se isto é falso positivo legítimo (teste com dado fake, documentação de formato),\n` +
      `você tem três saídas:\n` +
      `  - node scripts/setup.cjs --desligar gate-publicacao --escopo projeto (preferida,\n` +
      `    desliga só neste repositório, de forma declarada e legível);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessão (desliga na sessão inteira);\n` +
      `  - arquivo .rainforest-gate-off na raiz do repo (desliga naquele repo).\n`;

  msg += saidas;
  return msg;
}

// `preambulo` sai ANTES da mensagem, e so quando ha bloqueio de verdade.
// Medido na revisao de 2026-09-15: o aviso da Issue #165 era escrito no stderr
// antes desta chamada, e em repositorio privado o gate segue para `exit(0)` --
// o usuario lia "este conteudo entraria no COMMIT" e nada tinha sido barrado.
function bloqueia(achados, arquivo, agente, gitTop, preambulo) {
  const ehSubagente = Boolean(agente);
  const visibilidade = visibilidadeDoRepo(gitTop);
  if (visibilidade === "privada") process.exit(0);
  if (preambulo) process.stderr.write(preambulo);
  process.stderr.write(mensagemBloqueio(achados, arquivo, ehSubagente, visibilidade));
  process.exit(2);
}

/**
 * O comando é um `git commit`?
 *
 * Casa `git commit`, `git -C <dir> commit`, `git commit -am "x"`. NÃO casa
 * `git commit-tree` nem a palavra "commit" em prosa, porque o \b depois de
 * `commit` exige fim de TOKEN e o `git` tem de vir antes.
 * O `\b` que estava aqui casava DENTRO de `commit-tree`, porque `-` e fronteira
 * de palavra — a bateria pegou, e por isso o lookahead e por espaco ou fim.
 */
const RE_GIT_COMMIT = /\bgit\s+(?:(?:-[A-Za-z]\s+\S+|--[a-z-]+(?:=\S+)?|-[A-Za-z]+)\s+)*commit(?=\s|$)/;

/** `-a`, `-am`, `--all`: o commit leva o que está no WORKTREE, não no índice. */
const RE_COMMIT_TUDO = /(?:^|\s)(?:--all\b|-[A-Za-z]*a[A-Za-z]*\b)/;

/**
 * Um commit é publicado quando já existe em algum ramo remoto: o conteúdo dele
 * não é novidade que este comando esteja introduzindo.
 *
 * É o que separa `git merge origin/main` (o caso de campo da Issue #173: o
 * arquivo vem do outro pai, que é a própria `main` já publicada) de `git merge
 * uma-branch-qualquer` cujos commits nunca passaram por gate nenhum. No
 * segundo caso o segredo é novo para o destino, e a isenção do outro pai seria
 * exatamente a porta que este arquivo existe para fechar.
 */
function remotoDeDestino(dir) {
  // O remoto para onde ESTA branch publica, e não "qualquer um cadastrado". A
  // pergunta é feita ao upstream da branch atual; sem upstream, `origin`, que é
  // a convenção que o resto do plugin já assume.
  const up = git(dir, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]);
  if (up && up.includes("/")) return up.split("/")[0];
  return "origin";
}

function paiJaPublicado(dir, sha) {
  // Só contam os ramos do remoto de destino. Aceitar qualquer remoto reabria a
  // porta que D19 fecha por outro caminho, e foi reproduzido na revisão de
  // 2026-09-05: `git remote add espelho <bare descartável>`, um push para lá, e
  // o merge seguinte tratava o segredo como "já publicado". Nenhum gate deste
  // lote olha `remote add` ou `push`, então essa era uma porta de uma linha.
  const remoto = remotoDeDestino(dir);
  const r = git(dir, ["branch", "-r", "--contains", sha, "--list", `${remoto}/*`]);
  return !!(r && r.trim());
}

/**
 * Confere se um achado já existe num arquivo de um dos pais deste commit.
 *
 * Pais são HEAD (se existir) e MERGE_HEAD já publicado (se um merge estiver em
 * progresso). Se a linha do achado já estava lá, não é conteúdo novo — isenta.
 *
 * `conteudo` é o que VAI para o commit, e chega pronto de
 * `arquivosQueVaoParaOCommit`, que é quem sabe se este commit leva o índice ou
 * o worktree. Reler por conta própria aqui refazia essa decisão pela fonte
 * errada: num `git commit -a` o achado era procurado no ÍNDICE, que ainda tem
 * a versão velha, e uma linha nova inserida só no disco casava com a linha de
 * mesma posição do pai — segredo novo isento. A bateria
 * `testa-gate-commit.cjs` ficou vermelha nesse caso exato.
 */
function achadoJaEstaNoPai(dir, nome, a, conteudo) {
  const linhaDoAchado = a.linha;
  const pais = [];

  // HEAD é o commit atual
  try {
    const head = git(dir, ["rev-parse", "HEAD"]);
    if (head) pais.push(head);
  } catch {}

  // MERGE_HEAD é o commit sendo mergeado (pode haver mais de um em merge octopus)
  // `--git-path` funciona em worktree linkado, onde `.git` é ARQUIVO e o
  // `path.join(dir, ".git", "MERGE_HEAD")` nunca existe. Mas ele devolve
  // caminho RELATIVO ao repositório (`.git/MERGE_HEAD`), e um `existsSync`
  // sobre ele resolveria contra o cwd do processo do hook, que não é o
  // repositório do commit — daí o `path.resolve(dir, ...)`. Sem essa segunda
  // metade, o caso de campo da Issue #173 (`git merge origin/main`, arquivo
  // vindo do outro pai) continuava barrado, com o mecanismo escrito e mudo.
  try {
    const gitPath = git(dir, ["rev-parse", "--git-path", "MERGE_HEAD"]);
    const mergeHeadPath = gitPath ? path.resolve(dir, gitPath) : null;
    if (mergeHeadPath && fs.existsSync(mergeHeadPath)) {
      const mergeHeads = fs.readFileSync(mergeHeadPath, "utf8").trim().split("\n");
      for (const h of mergeHeads) {
        const sha = h.trim();
        if (sha && paiJaPublicado(dir, sha)) pais.push(sha);
      }
    }
  } catch {}

  // Normaliza separadores para forward slash (git show espera isto)
  const nomeNormalizado = nome.replace(/\\/g, "/");
  if (typeof conteudo !== "string") return false;

  const linhasAtual = conteudo.split("\n");
  const linhaAtualContent = linhasAtual[linhaDoAchado - 1];
  if (!linhaAtualContent) return false; // linha não existe

  const linhaAtualTrimmed = linhaAtualContent.trim();

  // Confere cada pai
  for (const pai of pais) {
    const conteudoPai = git(dir, ["show", `${pai}:${nomeNormalizado}`]);
    if (conteudoPai === null) continue; // arquivo não existia neste pai

    const linhasPai = conteudoPai.split("\n");

    // Procura a mesma linha (trimmed) em qualquer posição do arquivo pai
    if (linhasPai.some(l => l.trim() === linhaAtualTrimmed)) {
      return true; // encontrou a mesma linha no pai
    }
  }

  return false;
}

/**
 * O que ESTE commit levaria, e o conteúdo exato que iria para o objeto.
 *
 * A distinção índice-vs-worktree não é preciosismo: `git commit` leva o que
 * está no ÍNDICE, e `git commit -a` leva o que está no worktree. Conferir o
 * arquivo em disco num commit normal aprovaria (ou reprovaria) conteúdo que não
 * é o que vai ser gravado — que é exatamente a classe de erro que este arquivo
 * inteiro existe para não cometer.
 */
function arquivosQueVaoParaOCommit(dir, cmd) {
  const levaWorktree = RE_COMMIT_TUDO.test(cmd);
  const lista = git(dir, ["diff", "--cached", "--name-only", "--diff-filter=ACMR"]);
  const nomes = new Set((lista || "").split("\n").map((s) => s.trim()).filter(Boolean));

  if (levaWorktree) {
    const modificados = git(dir, ["diff", "--name-only", "--diff-filter=ACMR"]);
    for (const n of (modificados || "").split("\n").map((s) => s.trim()).filter(Boolean)) nomes.add(n);
  }

  const saida = [];
  for (const nome of nomes) {
    let conteudo = null;
    if (levaWorktree) {
      try { conteudo = fs.readFileSync(path.join(dir, nome), "utf8"); } catch { conteudo = null; }
    } else {
      // `git show :<caminho>` devolve o conteúdo do ÍNDICE, que é o que o commit
      // vai gravar. Não é o mesmo que ler o arquivo do disco.
      conteudo = git(dir, ["show", `:${nome}`]);
    }
    if (conteudo === null) continue;
    // Binário não passa por regex de telefone sem gerar ruído; o \0 é o teste
    // que o próprio git usa para decidir "Binary files differ".
    if (conteudo.includes("\u0000")) continue;
    saida.push({ nome, conteudo });
  }
  return saida;
}

/**
 * A trava no COMMIT — Issue #165.
 *
 * O gate acima cobre `Write`, `Edit` e `MultiEdit`, e é o que dá o aviso cedo.
 * Mas ele cobre a FERRAMENTA, não o EFEITO: em 2026-09-02 o mesmo conteúdo
 * sensível entrou no repositório sem ele ver, escrito por um `fs.writeFileSync`
 * dentro de um script node invocado pelo Bash. Nenhum evento de `Write` foi
 * emitido, nenhum `PreToolUse` disparou. `sed -i`, heredoc e `python - <<PY`
 * têm o mesmo caminho livre — e escrita por script é justamente a que se usa em
 * mudança de lote, que é onde o volume passa sem ninguém ler linha a linha.
 *
 * Por que no commit e não numa checagem de `Bash`: ler a linha de comando não
 * diz o que o script vai escrever. `node edita.mjs` é opaco. O commit é o único
 * ponto por onde tudo passa, independentemente de como o arquivo foi escrito —
 * e é o ponto em que o dado deixa de ser local e vira histórico.
 *
 * As três isenções são as mesmas do gate de escrita, de propósito: um arquivo
 * que passa por `Write` e reprova no `commit` seria uma trava contradizendo a
 * outra, e o usuário aprenderia a desligar as duas.
 */
function conferirCommit(ev, cwdDoEvento, agente) {
  const cmd = ev.tool_input && ev.tool_input.command;
  if (typeof cmd !== "string" || !RE_GIT_COMMIT.test(cmd)) process.exit(0);

  const gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) process.exit(0);

  if (desligadoPorArquivo(gitTop)) process.exit(0);

  for (const { nome, conteudo } of arquivosQueVaoParaOCommit(gitTop, cmd)) {
    const absoluto = path.join(gitTop, nome);
    if (estaGitignorado(gitTop, absoluto)) continue;
    // O marcador é procurado no conteúdo QUE VAI SER COMMITADO, não no disco:
    // arquivo que ganhou o marcador só no worktree não pode dispensar a
    // conferência do que já está no índice.
    if (temMarcadorNoConteudo(conteudo)) continue;

    const resultado = conferirConteudo(conteudo);
    if (resultado && resultado.achados && resultado.achados.length) {
      const achadosAbloquear = [];
      const dir = gitTop; // para a mutação: a linha tem que ser exata
      for (const a of resultado.achados) {
        if (achadoJaEstaNoPai(dir, nome, a, conteudo)) continue;
        achadosAbloquear.push(a);
      }

      if (achadosAbloquear.length > 0) {
        bloqueia(achadosAbloquear, absoluto, agente, gitTop,
          `\nEste conteudo entraria no COMMIT, e o gate de escrita nao o viu —\n` +
          `ele cobre Write/Edit, e este arquivo pode ter sido escrito por script\n` +
          `(node, sed, heredoc). Issue #165.\n`
        );
      }
    }
  }
  process.exit(0);
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

  const agente = ev.agent_id;
  const nome = ev.tool_name;

  // O commit é o ponto por onde tudo passa (Issue #165). Vem ANTES do filtro de
  // ferramentas de escrita porque `Bash` nunca esteve nele.
  if (nome === "Bash" || nome === "PowerShell") conferirCommit(ev, cwdDoEvento, agente);

  if (!FERRAMENTAS_DE_ESCRITA.has(nome)) process.exit(0);

  const entrada = ev.tool_input || {};
  let arquivo = null;
  let conteudo = null;
  let antigo = null;

  if (nome === "Write" && typeof entrada.file_path === "string" && typeof entrada.content === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.content;
  } else if (nome === "Edit" && typeof entrada.file_path === "string" && typeof entrada.new_string === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.new_string;
    antigo = typeof entrada.old_string === "string" ? entrada.old_string : "";
  } else if (nome === "MultiEdit") {
    // MultiEdit passa um array de edits. Conferir cada um.
    const edits = Array.isArray(entrada.edits) ? entrada.edits : [];
    for (const edit of edits) {
      if (typeof edit.file_path === "string" && typeof edit.new_string === "string") {
        // Confere este arquivo/conteúdo
        const a = edit.file_path;
        const c = edit.new_string;
        const o = typeof edit.old_string === "string" ? edit.old_string : "";
        const dir = dirDe(a);
        const gitTop = git(dir, ["rev-parse", "--show-toplevel"]);
        if (!gitTop) continue; // fora de repo git

        if (estaGitignorado(dir, a)) continue; // gitignorado passa

        if (temMarcadorDados(a)) continue; // marcador de dados-de-exemplo passa

        if (desligadoPorArquivo(gitTop)) continue; // Issue #265: faltava aqui

        let resultado = conferirConteudo(c);
        if (resultado && resultado.achados && resultado.achados.length) {
          // Filtra apenas achados introduzidos (não presentes em old_string)
          const ra = conferirConteudo(o);
          const achadosAntigos = (ra && ra.achados) || [];
          resultado.achados = soIntroduzidos(resultado.achados, achadosAntigos);

          if (resultado.achados.length > 0) {
            bloqueia(resultado.achados, a, agente, gitTop);
          }
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

  // Toggle de emergência, herdado do checkout principal quando gitTop é worktree
  if (desligadoPorArquivo(gitTop)) process.exit(0);

  // Roda a conferência de publicação
  let resultado = conferirConteudo(conteudo);
  if (resultado && resultado.achados && resultado.achados.length) {
    // Para Edit/MultiEdit, filtra apenas achados introduzidos (não presentes em old_string)
    if (antigo !== null) {
      const ra = conferirConteudo(antigo);
      const achadosAntigos = (ra && ra.achados) || [];
      resultado.achados = soIntroduzidos(resultado.achados, achadosAntigos);
    }

    if (resultado.achados.length > 0) {
      bloqueia(resultado.achados, arquivo, agente, gitTop);
    }
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
