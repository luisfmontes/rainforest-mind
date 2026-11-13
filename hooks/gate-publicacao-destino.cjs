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
 *   - chave do config do projeto (`.rainforest/config.json`, lida da raiz do
 *     checkout principal mesmo de dentro de um worktree)
 * O arquivo `.rainforest-gate-off` deixou de ser lido (#417).
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { caminhoExecutavel } = require("./lib/resolver-executavel.cjs");
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
    // `ssh://` aceita porta (`:22`, `:443`) e o host `ssh.github.com` (SSH pela 443).
    const m = url.match(/(?:https:\/\/(?:[^@/\s]+@)?(?:www\.)?github\.com[:/]|ssh:\/\/git@(?:ssh\.|www\.)?github\.com(?::\d+)?\/|git@(?:www\.)?github\.com:)([\w.-]+)\/([\w.-]+?)(?:\.git)?$/);
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
    const gh = process.env.RAINFOREST_GH ? process.env.RAINFOREST_GH.split(" ").filter(Boolean) : [caminhoExecutavel("gh")];
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
    return execFileSync(caminhoExecutavel("git"), ["-C", dir, ...args], {
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
    execFileSync(caminhoExecutavel("git"), ["-C", dir, "check-ignore", arquivo], {
      stdio: "ignore",
    });
    return true; // arquivo está ignorado (exit 0 de check-ignore)
  } catch {
    return false; // arquivo NÃO está ignorado (exit 1 de check-ignore)
  }
}

/**
 * Detecta se o arquivo **em disco** tem o marcador que dispensa a conferência.
 * Marcador: `rainforest-gate: dados-de-exemplo` nas 5 primeiras linhas do
 * arquivo (hooks/lib/marcador-dados.cjs, Issue #293) — fora dessa janela não conta.
 *
 * LEITURA DO DISCO, não do conteúdo que chega: isto fecha o furo de Edit no
 * arquivo com marcador (passa, mesmo se new_string não o tem). Write não passa
 * por esta função: o conteúdo dele é o arquivo inteiro (ver main).
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
 * Conteúdo atual do arquivo que um Write vai substituir, ou null quando ele não
 * existe ou não é legível. Caminho relativo resolve contra o cwd do evento.
 * O Write usa isso como `antigo`: a linha que já estava no disco não é novidade
 * da escrita, e soIntroduzidos a filtra como no Edit.
 */
function lerSeExiste(arquivo, cwd) {
  try {
    return fs.readFileSync(path.resolve(cwd, arquivo), "utf8");
  } catch {
    return null;
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
    const output = execFileSync(process.execPath, [scriptPath, "-", "--json"], {
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
 * Filtra achados que INTRODUZ a edição, comparando por valor cru dos padrões em multiconjunto.
 * Retorna apenas os achados de `achados` cujo padrão traz um valor novo em `textoNovo`
 * que não estava em `textoAntigo`.
 *
 * Issue #322 (emenda 2026-09-26): o gate barra só o que a edição INTRODUZ, medindo pelo
 * valor cru casado (não pelo `trecho` redigido, que é sempre igual para o mesmo padrão).
 * A primeira entrega comparava `id` + `trecho`, deixando passar:
 *   - Edit com e-mail A em old e e-mail B em new (mesma linha, trecho redigido igual)
 *   - Edit com e-mail A uma vez em old e A+B em new (novo na mesma linha)
 *
 * Padrão que casou um valor novo em qualquer linha barra — sem casar linha a linha.
 * Padrão com id fora de PADROES (termo privado) nunca cai — só traz valor novo quando
 * o PADROES dele para de existir.
 *
 * Falha fechada: exceção no require, `so_se` estourando ou PADROES inválido → return achados.
 */
function soIntroduzidos(achados, textoNovo, textoAntigo) {
  try {
    const { PADROES } = require("../scripts/conferir-publicacao.cjs");

    if (!Array.isArray(PADROES) || !Array.isArray(achados)) {
      return achados;
    }

    // Para cada padrão em PADROES, coleta todos os valores crus de textoAntigo
    // e textoNovo, computando diferença em multiconjunto.
    const mapPadrao = new Map(); // id → { pAntigo (Map), pNovo (Map) }
    for (const p of PADROES) {
      if (!p || typeof p.id !== 'string') continue;
      // Regex sem /g nunca avança o lastIndex e o while abaixo não termina:
      // num PreToolUse isso trava a sessão. Padrão assim não se compara — falha fechada.
      if (!(p.re instanceof RegExp) || !p.re.global) return achados;
      const pAntigo = new Map(); // valor → contagem
      const pNovo = new Map();

      // Coleta valores do texto antigo
      const linhasAntigo = textoAntigo.split('\n');
      for (const linha of linhasAntigo) {
        p.re.lastIndex = 0;
        let m;
        while ((m = p.re.exec(linha)) !== null) {
          try {
            // Respeita so_se: só conta se passou na verificação
            if (p.so_se && !p.so_se(m, linha)) {
              if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
              continue;
            }
          } catch {
            // so_se estourou: falha fechada
            return achados;
          }
          const valor = m[0];
          pAntigo.set(valor, (pAntigo.get(valor) || 0) + 1);
          if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
        }
      }

      // Coleta valores do texto novo
      const linhasNovo = textoNovo.split('\n');
      for (const linha of linhasNovo) {
        p.re.lastIndex = 0;
        let m;
        while ((m = p.re.exec(linha)) !== null) {
          try {
            if (p.so_se && !p.so_se(m, linha)) {
              if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
              continue;
            }
          } catch {
            return achados;
          }
          const valor = m[0];
          pNovo.set(valor, (pNovo.get(valor) || 0) + 1);
          if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
        }
      }

      mapPadrao.set(p.id, { pAntigo, pNovo });
    }

    // Calcula quais padrões introduzem valores novos
    const introduz = new Map(); // id → contagem total de valores novos
    for (const [id, { pAntigo, pNovo }] of mapPadrao) {
      let novos = 0;
      for (const [valor, cnt] of pNovo) {
        const cntAntigo = pAntigo.get(valor) || 0;
        if (cnt > cntAntigo) novos += (cnt - cntAntigo);
      }
      if (novos > 0) introduz.set(id, novos);
    }

    // Filtra: achado cai se seu id está em PADROES e não introduz valor.
    // Achado com id fora de PADROES (termo privado) nunca cai.
    const idsDePadroes = new Set(PADROES.map(p => p.id));
    return achados.filter(a => !idsDePadroes.has(a.id) || introduz.has(a.id));
  } catch {
    // Falha fechada: require, parse ou outro erro → retorna achados intactos
    return achados;
  }
}

/**
 * Formata a mensagem de bloqueio com os achados.
 */
function mensagemBloqueio(achados, arquivo, ehSubagente, visibilidade, temRemotoGitHub) {
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
    // Com remoto GitHub a declaracao nao vale (declaradaPrivada), entao nao se sugere.
    if (!ehSubagente && !temRemotoGitHub) {
      msgVisibilidade += `Repositório privado fora do GitHub? Declare \`"visibilidade-repo": "privada"\` em ` +
        `.rainforest/config.json do projeto (vale só para termos da lista privada; telefone, JID, CPF e credencial continuam barrando). `;
    }
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

  msg += textoDeSaidas(ehSubagente);
  return msg;
}

/** O bloco de saídas que as duas mensagens de bloqueio (arquivo e `gh`) compartilham. */
function textoDeSaidas(ehSubagente) {
  return ehSubagente
    ? `PARE e reporte isto para a janela principal — ela decide como seguir.\n` +
      `NÃO crie arquivo nem variável para desativar esta trava: a decisão não é sua,\n` +
      `e desativá-la para si mesmo é o contorno que esta trava existe para impedir.\n`
    : `A saída de emergência por ambiente NÃO vale no MESMO comando:\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente: precisa estar na sessão (export),\n` +
      `    não funciona como prefixo inline ('RAINFOREST_GATE_OFF=1 git commit').\n\n` +
      `Se isto é falso positivo legítimo (teste com dado fake, documentação de formato),\n` +
      `você tem duas saídas:\n` +
      `  - node scripts/setup.cjs --desligar gate-publicacao --escopo projeto (preferida,\n` +
      `    desliga só neste repositório, de forma declarada e legível);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessão (desliga na sessão inteira).\n`;
}

// `preambulo` sai ANTES da mensagem, e so quando ha bloqueio de verdade.
// Medido na revisao de 2026-09-15: o aviso da Issue #165 era escrito no stderr
// antes desta chamada, e em repositorio privado o gate segue para `exit(0)` --
// o usuario lia "este conteudo entraria no COMMIT" e nada tinha sido barrado.
// Declaração `visibilidade-repo: "privada"` (Issue #419). Modelo de ameaça: protege
// contra termo da lista privada bloquear trabalho legítimo em repo de trabalho
// privado fora do GitHub, que o `gh` não enxerga. Fica fora o repo declarado
// privado que depois vira público — a declaração é do usuário. Só vale quando o
// `gh` não soube responder; `publica` apurada prevalece.
function declaradaPrivada(gitTop) {
  try {
    // So o config DO PROJETO declara: no config de usuario a chave valeria para
    // todo repositorio sem resposta do `gh`, e a declaracao e por repositorio (D22).
    // E so para remoto FORA do GitHub: com remoto GitHub, `desconhecida` e o `gh`
    // fora do ar, e a declaracao liberaria termo privado num repo que pode ser publico.
    if (repositoriosDoGitHub(gitTop).length > 0) return false;
    const r = require("./lib/config.cjs").resolverConfig({ projeto: gitTop });
    return r.valores["visibilidade-repo"] === "privada" && String(r.origem["visibilidade-repo"]).startsWith("projeto");
  } catch { return false; }
}

function bloqueia(achados, arquivo, agente, gitTop, preambulo) {
  const ehSubagente = Boolean(agente);
  const visibilidade = visibilidadeDoRepo(gitTop);
  if (visibilidade === "privada") process.exit(0);
  if (visibilidade === "desconhecida" && declaradaPrivada(gitTop)) achados = achados.filter((a) => a.id !== "termo-privado");
  // Sem achado depois do filtro, este arquivo/edit esta liberado e o laco do
  // chamador CONTINUA: sair aqui deixaria os seguintes sem exame.
  if (achados.length === 0) return;
  if (preambulo) process.stderr.write(preambulo);
  process.stderr.write(mensagemBloqueio(achados, arquivo, ehSubagente, visibilidade, repositoriosDoGitHub(gitTop).length > 0));
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

/**
 * O texto de `gh issue`/`gh pr` — Issue #702.
 *
 * As duas travas acima veem o que vira ARQUIVO versionado. O título, o corpo e
 * o comentário que saem por `gh` não viram arquivo nenhum, e são tão públicos
 * quanto um, com o agravante de o GitHub guardar o histórico de edição: em
 * 2026-11-12 a #701 saiu com um termo da lista privada no corpo, e o mesmo texto
 * escrito num design no mesmo dia foi barrado aqui.
 *
 * Confere o valor de `--title`/`--body`/`--subject`/`--comment` e o arquivo
 * legível do `--body-file` com todos os detectores, e o comando inteiro só
 * contra a lista de termos privados (Q2 A do Luís e revisão 3, 2026-11-13):
 * stdin, variável escrita no comando, heredoc e here-string ficam cobertos para
 * o termo, e um caminho de home, um e-mail de `--author-email` ou um nome de
 * arquivo com data não barram o `gh` de rotina. Fora fica o que o comando não
 * carrega (arquivo lido por variável, saída de programa), design D3.
 */
const VERBOS_GH_TEXTO = {
  issue: new Set(["create", "comment", "edit", "close", "reopen"]),
  pr: new Set(["create", "comment", "edit", "review", "merge", "close", "reopen"]),
};
// `gh issue new` e `gh pr new` são apelidos de `create` (`gh issue create --help`).
const APELIDOS_GH = { new: "create" };

/**
 * `owner/repo` de uma URL de Issue ou PR do GitHub; `"?"` quando o token tem
 * cara de URL do GitHub e não se lê (falha fechada); null quando não é URL.
 * Lida por `new URL`, que tira usuário e porta antes de olhar o host.
 */
function repoDaUrlGh(valor) {
  const s = String(valor || "");
  if (!/github\.|\/(?:issues|pull)\//i.test(s)) return null;
  // Caminho que muda ao normalizar (`..`, `%2e`, contrabarra) pode apontar
  // para um repo no texto e outro no `new URL`: falha fechada (revisão de
  // segurança do commit, 2026-11-13).
  if (/\.\.|%|\\/.test(s)) return "?";
  try {
    const u = new URL(s);
    if (!/^(?:www\.)?github\.com$/i.test(u.hostname)) return "?";
    const m = u.pathname.match(/^\/([\w.-]+)\/([\w.-]+)\/(?:issues|pull)\/\d+/i);
    return m ? `${m[1]}/${m[2]}` : "?";
  } catch {
    return "?";
  }
}

const FLAGS_GH_VALOR = {
  longas: new Set([
    "--repo", "--title", "--body", "--body-file", "--subject", "--base", "--head", "--label",
    "--assignee", "--milestone", "--project", "--reviewer", "--template", "--add-label",
    "--remove-label", "--add-assignee", "--remove-assignee", "--add-project", "--remove-project",
    "--add-reviewer", "--remove-reviewer", "--author-email", "--match-head-commit",
  ]),
  curtasSempre: new Set(["-R", "-b", "-F"]),
  // No `merge`, `-s`/`-m`/`-r`/`-d` são booleanas (squash, merge, rebase,
  // delete-branch); no `review`, `-a`/`-c`/`-r` também. Tratá-las como flag de
  // valor engoliria o `--body` seguinte (leitor cego do plano, 2026-11-13).
  curtasPorVerbo: {
    create: new Set(["-t", "-a", "-l", "-m", "-p", "-T", "-B", "-H", "-r"]),
    edit: new Set(["-t", "-m", "-B"]),
    merge: new Set(["-t", "-A"]),
    comment: new Set(),
    review: new Set(),
    close: new Set(["-c", "--comment"]),
    reopen: new Set(["-c", "--comment"]),
  },
};

/**
 * Corpos que o próprio comando carrega: heredoc (bash) e here-string
 * (PowerShell, `@'...'@` e `@"...@"`). Contam com TODOS os detectores, porque
 * são texto que vira Issue ou PR; o resto do comando conta só contra a lista
 * de termos privados (revisão 4, 2026-11-13: JID em heredoc saía 0).
 */
function corposEmbutidos(cmd) {
  const { posicoesDeOperadorHeredoc, corpoDeHeredoc } = require("./lib/heredoc.cjs");
  const saida = [];
  try {
    for (const pos of posicoesDeOperadorHeredoc(cmd)) {
      const h = corpoDeHeredoc(cmd, pos);
      if (h && h.corpo) saida.push({ origem: "heredoc", texto: h.corpo });
    }
  } catch {}
  for (const m of String(cmd).matchAll(/@(["'])\r?\n([\s\S]*?)\r?\n\1@/g)) saida.push({ origem: "here-string", texto: m[2] });
  return saida;
}

/** `owner/repo` do valor de `--repo`, `"?"` quando ilegível, `null` sem valor. */
function normalizarRepoAlvo(valor) {
  if (valor == null || valor === "") return null;
  if (/[$\x60]/.test(valor)) return "?";
  const m = valor.match(/^(?:https?:\/\/)?(?:www\.)?github\.com\/([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/i);
  if (m) return `${m[1]}/${m[2]}`;
  const curto = valor.match(/^(?:[\w.-]+\/)?([\w.-]+)\/([\w.-]+)$/);
  if (curto) return `${curto[1]}/${curto[2]}`; // aceita HOST/OWNER/REPO, como o gh
  return "?";
}

function visibilidadeDoAlvo(ownerRepo) {
  if (ownerRepo === "?" || process.env.RAINFOREST_GATE_SEM_REDE === "1") return "desconhecida";
  return visibilidadeDeUmRepo(ownerRepo);
}

/**
 * Família, verbo, textos e `--repo` de um segmento, ou null se o segmento não é
 * `gh issue|pr <verbo de texto>`.
 */
function textosDoSegmentoGh(segmento, cmdOriginal, cwd) {
  const { tokensComAspas } = require("./lib/tokens-comando.cjs");
  const { normalizarExecutavel } = require("./lib/heredoc.cjs");
  let toks;
  try { toks = tokensComAspas(segmento).map((t) => t.v); } catch { return null; }
  const iGh = toks.findIndex((t) => normalizarExecutavel(t) === "gh");
  if (iGh === -1) return null;

  // `GH_REPO=x gh ...` (ou `env GH_REPO=x gh ...`): prefixo do próprio comando.
  const repoPrefixo = toks.slice(0, iGh).filter((t) => /^GH_REPO=/.test(t))
    .map((t) => normalizarRepoAlvo(t.slice("GH_REPO=".length)) || "?");
  let repoValor = null;
  const posicionais = [];
  let i = iGh + 1;
  for (; i < toks.length && posicionais.length < 2; i += 1) {
    const t = toks[i];
    if (t.startsWith("-")) {
      if (t === "-R" || t.toLowerCase() === "--repo") { repoValor = toks[i + 1] ?? null; i += 1; }
      else if (t.toLowerCase().startsWith("--repo=")) repoValor = t.slice("--repo=".length);
      else if (/^-R./.test(t)) repoValor = t.slice(2).replace(/^=/, "");
      continue;
    }
    posicionais.push(t.toLowerCase());
  }
  if (posicionais.length < 2) return null;
  const familia = posicionais[0];
  const verbo = APELIDOS_GH[posicionais[1]] || posicionais[1];
  if (!VERBOS_GH_TEXTO[familia] || !VERBOS_GH_TEXTO[familia].has(verbo)) return null;
  const repoUrls = [];

  const curtasDoVerbo = FLAGS_GH_VALOR.curtasPorVerbo[verbo] || new Set();
  // O comando inteiro conta como texto (Q2 A do Luís, 2026-11-13): valor de
  // flag, heredoc, here-string, `printf ... |`, `<<<` e `B="..."; ... "$B"`
  // estão todos escritos nele. Preço aceito: termo só num caminho do mesmo
  // comando barra. Fora fica só o que o comando não carrega (arquivo lido por
  // variável, saída de programa).
  // Só o termo privado conta na origem "comando" (revisão 3): ver conferirGh.
  const textos = [{ origem: "comando", texto: cmdOriginal }];
  textos.push(...corposEmbutidos(cmdOriginal));
  for (; i < toks.length; i += 1) {
    const tok = toks[i];
    // `gh issue comment <URL>` publica no repositório da URL, não no do cwd (revisão 3).
    if (!tok.startsWith("-")) { const u = repoDaUrlGh(tok); if (u) repoUrls.push(u); continue; }
    if (tok === "-") continue;
    const longa = tok.startsWith("--");
    const igual = tok.indexOf("=");
    const chave = longa ? (igual === -1 ? tok : tok.slice(0, igual)).toLowerCase() : tok.slice(0, 2);
    const colado = longa
      ? (igual === -1 ? null : tok.slice(igual + 1))
      : (tok.length > 2 ? tok.slice(2).replace(/^=/, "") : null);
    const temValor = longa ? (FLAGS_GH_VALOR.longas.has(chave) || curtasDoVerbo.has(chave))
      : (FLAGS_GH_VALOR.curtasSempre.has(chave) || curtasDoVerbo.has(chave));
    if (!temValor) continue; // booleana
    let valor = colado;
    if (valor === null) { valor = toks[i + 1] ?? null; i += 1; }
    if (valor === null) continue;

    if (chave === "--repo" || chave === "-R") { repoValor = valor; continue; }
    const ehTitulo = chave === "--title" || (chave === "-t" && verbo !== "merge");
    const ehSubject = verbo === "merge" && (chave === "--subject" || chave === "-t");
    const ehComentario = (verbo === "close" || verbo === "reopen") && (chave === "--comment" || chave === "-c");
    if (chave === "--body" || chave === "-b" || ehTitulo || ehSubject || ehComentario) {
      textos.push({ origem: chave, texto: valor });
      continue;
    }
    if (chave === "--body-file" || chave === "-F") {
      if (/[$\x60]/.test(valor) || valor === "-") continue;
      let caminho = valor;
      try { caminho = require("./lib/cwd-efetivo.cjs").normalizarMsys(valor); } catch {}
      const resolvido = path.isAbsolute(caminho) ? caminho : path.resolve(cwd, caminho);
      try {
        textos.push({ origem: `${chave} ${valor}`, texto: fs.readFileSync(resolvido, "utf8") });
      } catch {
        // Ilegível ou inexistente: o comando inteiro já entrou.
      }
    }
  }
  // O prefixo só manda sozinho quando tudo antes do `gh` é atribuição pura
  // (`A=b gh`, `env A=b gh`): `env -u`, `sudo` e afins podem mudar o ambiente
  // que chega ao `gh`, e aí o prefixo vira só mais um destino possível.
  const antesDoGh = toks.slice(0, iGh);
  const ehAtribuicao = (x) => /^[A-Za-z_][A-Za-z0-9_]*=/.test(x);
  const prefixoLimpo = antesDoGh.every(ehAtribuicao)
    || (antesDoGh[0] === "env" && antesDoGh.slice(1).every(ehAtribuicao));
  return { familia, verbo, textos, repoFlag: normalizarRepoAlvo(repoValor), repoUrls, repoPrefixo, prefixoLimpo };
}

function mensagemBloqueioGh(achados, familia, verbo, ehSubagente, visibilidade) {
  let msg = `BLOQUEADO pelo gate de publicação do rainforest-mind.\n\n` +
    `Comando: gh ${familia} ${verbo}\n` +
    `Razão: o texto deste comando vai para um repositório ` +
    (visibilidade === "publica" ? `público (apurado por 'gh repo view')` : `de visibilidade desconhecida (bloqueado por precaução)`) +
    ` e contém dados sensíveis.\n\nTrechos encontrados:\n`;
  for (const a of achados) {
    msg += `\n  ${a.origem}, linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}\n`;
    msg += `    ${a.o_que}\n`;
    msg += `    → ${a.faca}\n`;
  }
  msg += `\nO GitHub guarda o histórico de edição de Issue e PR: corrigir depois não apaga o texto publicado.\n` +
    `Corrija o texto e rode de novo.\n\n`;
  return msg + textoDeSaidas(ehSubagente);
}

/**
 * Todo `GH_REPO` mencionado ANTES do segmento (`export GH_REPO=...`,
 * `$env:GH_REPO = ...`, ou só citado num `echo`). Quem lê texto de shell não
 * sabe se a atribuição chega ao `gh` (subshell, `unset`, prefixo de outro
 * comando), então a menção só pode deixar o gate MAIS rígido: os valores
 * mencionados entram como destinos possíveis AO LADO do repositório do cwd,
 * nunca no lugar dele (revisão de segurança, 2026-11-13). Procura até a ÚLTIMA
 * ocorrência do segmento: com texto repetido, inclui mais menções, que só
 * apertam.
 */
function mencoesDeGhRepo(mascarado, segmento) {
  const pos = mascarado.lastIndexOf(segmento.trim());
  const antes = pos === -1 ? mascarado : mascarado.slice(0, pos);
  return [
    ...antes.matchAll(/GH_REPO\s*=\s*("[^"]*"|'[^']*'|[^\s;&|)]*)/gi),
  ].map((m) => normalizarRepoAlvo(m[1].replace(/^["']|["']$/g, "")) || "?");
}

/**
 * Os cwds em que ESTE segmento pode rodar: `cd outro-repo && gh issue create`
 * publica no repositório do `cd`, não no do evento. Segmento com texto repetido
 * no comando casa com TODAS as ocorrências, e todas são conferidas. Segmento de
 * dentro de `"$(...)"` (que `cwdPorSegmento` não separa) herda o cwd de quem o
 * contém. Sem correspondência, incerto.
 */

function cwdsDoSegmentoGh(mapa, segmento, cwdDoEvento) {
  const s = segmento.trim();
  let itens = mapa.filter((m) => m.seg.trim() === s);
  if (itens.length === 0) itens = mapa.filter((m) => m.seg.includes(s));
  // Sem correspondência, incerto. O `incerto` vem do `cwdPorSegmento`, que
  // resolve `"cd"`, `cd` e `builtin cd`; uma regex por cima dele deixava
  // passar o que ele marcou (revisão de segurança, 2026-11-13). Preço aceito:
  // `{ gh ...; }` com termo num repositório privado barra.
  if (itens.length === 0) return [{ cwd: cwdDoEvento, incerto: true }];
  return itens.map((m) => ({ cwd: m.cwd, incerto: Boolean(m.incerto) }));
}

/**
 * Para onde o `gh` deste segmento pode publicar, em ordem de precedência do
 * próprio `gh`: `--repo`; senão `GH_REPO` no prefixo do comando (todos, se
 * repetido); senão o cwd, somado a toda menção de `GH_REPO` antes do segmento;
 * senão o `GH_REPO` do ambiente da sessão; senão o cwd.
 */
function destinosDoSegmentoGh(r, locais, mencoes) {
  const base = destinosSemUrl(r, locais, mencoes);
  // A URL posicional SOMA aos destinos, nunca os substitui: um token que o
  // gate lê como URL sem que o `gh` o leia assim não pode liberar um destino
  // público (revisão de segurança do commit, 2026-11-13). O pior decide.
  return r.repoUrls.length ? [...base, ...r.repoUrls.map((repo) => ({ repo }))] : base;
}

function destinosSemUrl(r, locais, mencoes) {
  if (r.repoFlag) return [{ repo: r.repoFlag }];
  const prefixo = r.repoPrefixo.map((v) => ({ repo: v }));
  if (prefixo.length && r.prefixoLimpo) return prefixo;
  const ambiente = process.env.GH_REPO ? [{ repo: normalizarRepoAlvo(process.env.GH_REPO) || "?" }] : [];
  // Prefixo com wrapper, ou menção antes do segmento: tudo entra junto, e o pior decide.
  if (prefixo.length || mencoes.length) return [...prefixo, ...mencoes.map((v) => ({ repo: v })), ...locais, ...ambiente];
  if (ambiente.length) return ambiente;
  return locais;
}

const PESO_VISIBILIDADE = { privada: 0, "desconhecida-declarada": 1, desconhecida: 2, publica: 3 };

/** Visibilidade de um destino; `null` quando o cwd não é repositório (o `gh` não publicaria). */
function visibilidadeDoDestino(d) {
  if (d.repo) return visibilidadeDoAlvo(d.repo);
  if (d.incerto) return "desconhecida";
  const gitTop = git(d.cwd, ["rev-parse", "--show-toplevel"]);
  if (!gitTop) return null;
  const v = visibilidadeDoRepo(gitTop);
  return v === "desconhecida" && declaradaPrivada(gitTop) ? "desconhecida-declarada" : v;
}

/**
 * Junta a continuação de linha: crase + quebra no PowerShell, contrabarra +
 * quebra no bash. A leitura juntada é conferida ao lado da crua.
 */
function juntarContinuacao(ferramenta, cmd) {
  return ferramenta === "PowerShell" ? cmd.replace(/\x60\r?\n/g, " ") : juntarContrabarra(cmd);
}

function conferirGh(ev, cwdDoEvento, agente) {
  const cmdBruto = ev.tool_input && ev.tool_input.command;
  if (typeof cmdBruto !== "string") return;
  // Continuação de linha do PowerShell (crase + quebra de linha): o
  // `segmentosParaGate` quebrava ali, e o `--repo`/`--body-file` da linha de
  // baixo ficava num segmento que ninguém lia (revisão 4, 2026-11-13). Juntar
  // pode errar (crase dentro de aspas simples), então as DUAS leituras são
  // conferidas e qualquer uma barra (revisão de segurança do commit).
  const juntado = juntarContinuacao(ev.tool_name, cmdBruto);
  // A triagem olha as duas leituras: `g\<quebra>h` só vira `gh` juntado.
  if (!/\bgh\b/i.test(cmdBruto) && !/\bgh\b/i.test(juntado)) return;
  conferirGhLeitura(ev, cmdBruto, cwdDoEvento, agente);
  if (juntado !== cmdBruto) conferirGhLeitura(ev, juntado, cwdDoEvento, agente);
}

function conferirGhLeitura(ev, cmd, cwdDoEvento, agente) {
  let segmentos, mascarado;
  try {
    const { segmentosParaGate } = require("./gate-subagente-sem-gh.cjs");
    const { mascararCorposDeHeredoc } = require("./lib/heredoc.cjs");
    const { cwdPorSegmento } = require("./lib/cwd-efetivo.cjs");
    const { desempacotarWrapperDeString } = require("./lib/tokens-comando.cjs");
    // Segmenta o comando CRU. A máscara de heredoc apaga também a linha do
    // delimitador, e o `segmentosParaGate` perdia todo `gh` das linhas seguintes
    // (revisão, 2026-11-13). O resíduo do cru (#706: `novo.md` vira `novo.mdF`)
    // não abre nada: com `--body-file`, os corpos embutidos contam sempre.
    mascarado = mascararCorposDeHeredoc(cmd);
    // Cada segmento leva os cwds possíveis. O texto de dentro de um wrapper
    // (`bash -c "cd x && gh ..."`) tem o próprio `cwdPorSegmento`, que parte
    // de cada cwd possível do segmento do wrapper (revisão 2, 2026-11-13).
    const ehPs = (s) => /^(?:&\s*)?["']?(?:pwsh|powershell)(?:\.exe)?["']?(?:\s|$)|^(?:iex|invoke-expression)\b/i.test(s.trim());
    segmentos = [];
    const empilhar = (texto, profundidade, origens = [{ cwd: cwdDoEvento, incerto: false }], ps = ev.tool_name === "PowerShell") => {
      const mapas = origens.map((o) => ({ o, mapa: cwdPorSegmento(texto, o.cwd, ps) }));
      for (const s of segmentosParaGate(texto)) {
        const locais = [];
        for (const { o, mapa: m } of mapas) {
          for (const l of cwdsDoSegmentoGh(m, s, o.cwd)) locais.push({ cwd: l.cwd, incerto: l.incerto || o.incerto });
        }
        segmentos.push({ segmento: s, locais });
        if (profundidade >= 4) continue;
        let w = null;
        try { w = desempacotarWrapperDeString(s.trim(), { ferramenta: ev.tool_name }); } catch {}
        // `bash -c "gh ..."`, `sh -c`, `eval`, `powershell -Command`
        if (w && w.interno) empilhar(w.interno, profundidade + 1, locais, ehPs(s));
      }
    };
    empilhar(cmd, 0);
  } catch { return; }

  const memo = new Map();
  const conferirMemo = (texto) => {
    if (!memo.has(texto)) memo.set(texto, conferirConteudo(texto));
    return memo.get(texto);
  };
  let ghTextoSegmentos = 0;
  for (const { segmento, locais } of segmentos) {
    // O `--body-file` relativo se lê contra CADA cwd possível do segmento, e os
    // achados se somam: com o segmento repetido, cada ocorrência lê o seu.
    let r = null;
    let achados = [];
    for (const local of locais) {
      const ri = textosDoSegmentoGh(segmento, cmd, local.cwd);
      if (!ri) break; // não é `gh` de texto, em cwd nenhum
      if (!r) r = ri;
      for (const { origem, texto } of ri.textos) {
        const res = conferirMemo(texto);
        if (res && res.achados) for (const a of res.achados) if (origem !== "comando" || a.id === "termo-privado") achados.push({ ...a, origem });
      }
    }
    if (!r) continue;
    ghTextoSegmentos += 1;
    if (achados.length === 0) continue;

    // Falha fechada: o pior destino possível decide.
    let pior = null;
    for (const d of destinosDoSegmentoGh(r, locais, mencoesDeGhRepo(mascarado, segmento))) {
      const v = visibilidadeDoDestino(d);
      if (v !== null && (pior === null || PESO_VISIBILIDADE[v] > PESO_VISIBILIDADE[pior])) pior = v;
    }
    if (pior === null || pior === "privada") continue; // sem destino, ou só privado
    if (pior === "desconhecida-declarada") achados = achados.filter((a) => a.id !== "termo-privado");
    if (achados.length === 0) continue;
    const vis = pior === "publica" ? "publica" : "desconhecida";
    process.stderr.write(mensagemBloqueioGh(achados, r.familia, r.verbo, Boolean(agente), vis));
    process.exit(2);
  }
  // A rede roda quando a segmentação achou menos `gh` de texto do que o texto
  // cru tem: um `gh` perdido depois de outro achado escapava (revisão 4).
  // Contado sobre o texto com `\` + quebra de linha juntos, como o bash e o
  // segmentador leem; qualquer diferença, para mais ou para menos, roda a rede.
  const nCru = (juntarContrabarra(cmd).match(GH_TEXTO_CRU_G) || []).length;
  if (ghTextoSegmentos !== nCru) conferirGhPerdido(cmd, cwdDoEvento, agente, conferirMemo);
}

/**
 * Rede da segmentação (revisão 2, 2026-11-13): uma aspa ímpar (`echo it\'s`,
 * here-string com `it's`) fazia o `gh issue|pr` de escrita sumir dos
 * segmentos, e o gate não conferia nada. Se o texto cru tem um `gh` de escrita
 * que nenhum segmento achou, o comando inteiro é conferido e os destinos saem
 * do texto: todo `--repo`/`-R`, todo `GH_REPO=`, o `GH_REPO` da sessão e o
 * cwd do evento, incerto se o comando muda de diretório. O pior decide.
 */
const GH_TEXTO_CRU = /(?:^|[^\w.-])gh(?:\.exe)?\b[^\n]*?\b(issue|pr)\s+(create|new|comment|edit|close|reopen|review|merge)\b/i;
const GH_TEXTO_CRU_G = new RegExp(GH_TEXTO_CRU.source, "gi");
/**
 * Junta contrabarra + quebra de linha como o bash: as duas somem, sem espaço
 * (`termo\<quebra>702` é `termo702` para o bash; revisão de segurança).
 */
function juntarContrabarra(cmd) {
  return cmd.replace(/\\\r?\n/g, "");
}

function conferirGhPerdido(cmdOriginal, cwdDoEvento, agente, conferirMemo) {
  // O texto lido pela rede tem contrabarra + quebra juntas, o mesmo da
  // contagem: `gh \<quebra> issue ...` não escapa dela (revisão de segurança).
  const cmd = juntarContrabarra(cmdOriginal);
  const m = cmd.match(GH_TEXTO_CRU);
  if (!m) return;
  const res = conferirMemo(cmd);
  let achados = res && res.achados ? res.achados.filter((a) => a.id === "termo-privado").map((a) => ({ ...a, origem: "comando" })) : [];
  for (const c of corposEmbutidos(cmd)) {
    const rc = conferirMemo(c.texto);
    if (rc && rc.achados) for (const a of rc.achados) achados.push({ ...a, origem: c.origem });
  }
  // O arquivo de `--body-file`/`-F` legível também conta (revisão 3).
  for (const x of cmd.matchAll(/(?:--body-file[=\s]+|(?:^|\s)-F\s*=?\s*)(?:"([^"]+)"|'([^']+)'|([^\s"';|&()\x60]+))/gi)) {
    const arq = x[1] || x[2] || x[3];
    if (/[$\x60]/.test(arq) || arq === "-") continue;
    let caminho = arq;
    try { caminho = require("./lib/cwd-efetivo.cjs").normalizarMsys(caminho); } catch {}
    const resolvido = path.isAbsolute(caminho) ? caminho : path.resolve(cwdDoEvento, caminho);
    let texto = null;
    try { texto = fs.readFileSync(resolvido, "utf8"); } catch {}
    const r = texto === null ? null : conferirMemo(texto);
    if (r && r.achados) for (const a of r.achados) achados.push({ ...a, origem: `--body-file ${arq}` });
  }
  if (achados.length === 0) return;
  const destinos = [];
  // Por token, sem regex com `\S*` à frente (retrocesso quadrático num comando longo).
  for (const tok of cmd.split(/\s+/)) {
    const u = repoDaUrlGh(tok.replace(/^["']+|["']+$/g, ""));
    if (u) destinos.push({ repo: u });
  }
  for (const x of cmd.matchAll(/(?:--repo[=\s]+|(?:^|\s)-R\s*=?\s*)["']?([^\s"';|&]+)/gi)) destinos.push({ repo: normalizarRepoAlvo(x[1]) || "?" });
  for (const x of cmd.matchAll(/\bGH_REPO\s*=\s*["']?([^\s"';|&]*)/g)) destinos.push({ repo: normalizarRepoAlvo(x[1]) || "?" });
  if (process.env.GH_REPO) destinos.push({ repo: normalizarRepoAlvo(process.env.GH_REPO) || "?" });
  const mudaDir = /(?:^|[\s;&|({])(?:cd|pushd|popd|chdir|set-location|sl|push-location|pop-location)\b|(?:^|\s)-C\s/i.test(cmd);
  destinos.push({ cwd: cwdDoEvento, incerto: mudaDir });
  let pior = null;
  for (const d of destinos) {
    const v = visibilidadeDoDestino(d);
    if (v !== null && (pior === null || PESO_VISIBILIDADE[v] > PESO_VISIBILIDADE[pior])) pior = v;
  }
  if (pior === null || pior === "privada") return;
  if (pior === "desconhecida-declarada") achados = achados.filter((a) => a.id !== "termo-privado");
  if (achados.length === 0) return;
  const vis = pior === "publica" ? "publica" : "desconhecida";
  const v2 = m[2].toLowerCase();
  process.stderr.write(mensagemBloqueioGh(achados, m[1].toLowerCase(), APELIDOS_GH[v2] || v2, Boolean(agente), vis));
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

  const agente = ev.agent_id;
  const nome = ev.tool_name;

  // O commit é o ponto por onde tudo passa (Issue #165). Vem ANTES do filtro de
  // ferramentas de escrita porque `Bash` nunca esteve nele. O texto de `gh`
  // (Issue #702) vem antes do commit, que sai 0 em comando que não é commit.
  if (nome === "Bash" || nome === "PowerShell") conferirGh(ev, cwdDoEvento, agente);
  if (nome === "Bash" || nome === "PowerShell") conferirCommit(ev, cwdDoEvento, agente);

  if (!FERRAMENTAS_DE_ESCRITA.has(nome)) process.exit(0);

  const entrada = ev.tool_input || {};
  let arquivo = null;
  let conteudo = null;
  let antigo = null;

  if (nome === "Write" && typeof entrada.file_path === "string" && typeof entrada.content === "string") {
    arquivo = entrada.file_path;
    conteudo = entrada.content;
    antigo = lerSeExiste(arquivo, cwdDoEvento);
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

        let resultado = conferirConteudo(c);
        if (resultado && resultado.achados && resultado.achados.length) {
          // Filtra apenas achados introduzidos (não presentes em old_string)
          resultado.achados = soIntroduzidos(resultado.achados, c, o);

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
  // Write traz o arquivo INTEIRO, então as 5 primeiras linhas do conteúdo são as do arquivo
  // e o marcador ali vale. Edit/MultiEdit trazem só um fragmento (não é o topo do arquivo),
  // então para eles só o disco conta.
  if (temMarcadorDados(arquivo) || (nome === "Write" && temMarcadorNoConteudo(conteudo))) process.exit(0);

  // Roda a conferência de publicação
  let resultado = conferirConteudo(conteudo);
  if (resultado && resultado.achados && resultado.achados.length) {
    // Para Edit/MultiEdit, filtra apenas achados introduzidos (não presentes em old_string)
    if (antigo !== null) {
      resultado.achados = soIntroduzidos(resultado.achados, conteudo, antigo);
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
