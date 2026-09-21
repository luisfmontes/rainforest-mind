#!/usr/bin/env node
// @categoria: sensor
/**
 * Conferidor de régua selada — valida que o manifesto não foi alterado
 * desde sua adição ao repo, e que tem o formato exigido.
 *
 * POR QUE EXISTE. Em karpathy/autoresearch, o juiz (`evaluate_bpb` em
 * `prepare.py`) é protegido só por uma linha de markdown — a régua deste repo
 * também era. Este script selada a régua por construção: git é o selo, não
 * hash próprio (D1). O crítico da régua é um agente novo a cada rodada e não
 * herda contexto da conversa — o que não estiver em disco não chega nele.
 *
 * NENHUMA PROTECAO CONTRA: orquestrador que não chama o script, rebase do
 * commit de adição (reescrever o histórico apaga a adição selada; o que sobra
 * parece uma adição única legítima), semântica vazia de seção "Freios" ou
 * cabeçalhos M<n> (validamos presença, não conteúdo).
 *   PROTEGE, e ja nao estava garantido antes: merge resolvido com um lado que
 *   tambem adicionou o manifesto (`--full-history` + recusa de mais de uma
 *   adicao) e `git replace` (`GIT_NO_REPLACE_OBJECTS`).
 *   Tambem NAO protege contra estado de git em que a leitura do historico
 *   falha por um motivo que a sonda em camadas de `ancoraDe` nao alcanca: ali
 *   o script pode sair 1 (veredito) onde 2 (ambiente) seria mais correto. A
 *   sonda cobre os casos conhecidos — sem commit, HEAD destacado, ref ausente,
 *   packed-refs ilegivel, fora de repositorio — e tres rodadas de revisao
 *   independente acharam um estado novo cada. O selo em si NAO depende dessa
 *   distincao: manifesto alterado continua sendo pego em qualquer um dos casos.
 *
 * Uso:
 *   node scripts/conferir-regua.cjs conferir --slug <slug>
 *     Valida que o manifesto <slug> não foi alterado e tem formato válido.
 *     Exit 0: tudo ok. Exit 1: veredito negativo (alterado, fora do formato,
 *     nunca commitado, ou selado e removido da arvore). Exit 2: uso errado, slug
 *             invalido (barra, contrabarra, dois-pontos ou ".."), arquivo
 *             inexistente, clone raso ou git falhou.
 *
 *   node scripts/conferir-regua.cjs mostrar --slug <slug>
 *     Valida que o manifesto <slug> não foi alterado e tem formato válido.
 *     Se válido, imprime o conteúdo do commit-âncora em stdout.
 *     Exit 0: tudo ok. Exit 1: manifesto alterado, formato inválido, nunca
 *             commitado, ou selado e removido da árvore.
 *             Exit 2: slug invalido ou inexistente, clone raso, ou git
 *             falhou.
 *
 *   node scripts/conferir-regua.cjs validar --slug <slug>
 *     ANTES de selar: confere so o formato do arquivo na arvore, sem ancora,
 *     e nao imprime o manifesto (o `mostrar` segue o unico que imprime).
 *     Exit 0: formato ok, pode commitar. Exit 1: formato invalido.
 *             Exit 2: slug invalido ou arquivo inexistente.
 *
 * Exit codes:
 *   0  Manifesto íntegro e formato válido (conferir: sucesso; mostrar: imprimiu conteúdo).
 *   1  Manifesto alterado, formato inválido, nunca commitado, selado e
 *      removido da árvore de trabalho, ou adicionado mais de uma vez no
 *      histórico (selo ambíguo).
 *   2  Slug invalido ou inexistente, uso errado, clone raso, ou git falhou.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { validarSlug } = require('./recibo.cjs');

const EXIT_RECUSA = 1;
const EXIT_GIT_FALHOU = 2;

// `git replace` troca o conteudo que `git log` e `git show` enxergam sem
// reescrever historico nenhum — o commit selado continua la, e o que se le
// dele e outra coisa. Toda leitura de historico e de conteudo passa por aqui.
const ENV_GIT = { ...process.env, GIT_NO_REPLACE_OBJECTS: '1', MSYS_NO_PATHCONV: '1' };

/**
 * O mesmo, sobre BYTES. O selo compara bytes, nunca texto decodificado.
 *
 * Decodificar como utf8 antes de comparar troca todo byte invalido por
 * U+FFFD, e dois manifestos com bytes diferentes passam a ser "iguais". Na
 * saida e pior: manifesto em CP-1252 — cenario vivo nesta maquina — sai do
 * `mostrar` com todo acento virado U+FFFD, quebrando a promessa de que a
 * leitura entregue ao critico cego e byte a byte a do `git show`.
 */
function normalizarEolBytes(buf) {
  const CR = 0x0d, LF = 0x0a;
  const saida = Buffer.allocUnsafe(buf.length);
  let n = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === CR) {
      saida[n++] = LF;
      if (buf[i + 1] === LF) i++;
    } else {
      saida[n++] = buf[i];
    }
  }
  return saida.subarray(0, n);
}

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return (i === -1 || i + 1 >= process.argv.length) ? null : process.argv[i + 1];
}

function uso() {
  console.error(`uso: node scripts/conferir-regua.cjs conferir --slug <slug>`);
  console.error(`      node scripts/conferir-regua.cjs mostrar --slug <slug>`);
  console.error(`      node scripts/conferir-regua.cjs validar --slug <slug>`);
}

/**
 * Resolve a âncora do manifesto: commit em que foi adicionado.
 * Devolve a string do hash SHA1, ou null se não encontrado.
 */
function ancoraDe(slug) {
  // CLONE RASO NAO TEM ONDE ANCORAR (achado bloqueante da rodada 5).
  //
  // `git log --diff-filter=A` devolve o commit de adicao VISIVEL. Num clone
  // raso o unico commit visivel e a fronteira do clone, e o conteudo dela e,
  // por construcao, o que esta no checkout: a comparacao de integridade passa
  // a comparar o arquivo consigo mesmo e sai 0 sobre manifesto adulterado. O
  // selo degradava em silencio de "nao mudou desde que entrou no repo" para
  // "nao esta sujo desde o clone" — e `--depth 1` e o default do
  // `actions/checkout`. Reproduzido: repo completo sai 1, clone raso do mesmo
  // repo sai 0 e o `mostrar` entrega a regua afrouxada ao critico cego.
  //
  // Aqui o script se RECUSA A JULGAR (exit 2, ambiente), em vez de julgar
  // errado — e a D5 aplicada: ancora que nao resolve aborta.
  const raso = spawnSync("git", ["rev-parse", "--is-shallow-repository"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  if (!raso.error && raso.status === 0 && raso.stdout.trim() === "true") {
    console.error(`clone raso: o selo nao ancora sem historico (${slug})`);
    console.error("  Refaca o checkout com historico completo (em CI, fetch-depth: 0).");
    process.exit(EXIT_GIT_FALHOU);
  }

  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  // `--full-history` e obrigatorio. Sem ele o git SIMPLIFICA o historico: num
  // merge TREESAME a um dos pais, segue so aquele pai. Reproduzido: regua
  // estrita selada na main, branch que tambem adiciona o arquivo (frouxo),
  // merge resolvido com o lado da branch — o `log` simplificado nunca visita a
  // adicao selada, devolve so a da branch, e `conferir` saia 0 com `mostrar`
  // entregando a regua frouxa ao critico cego.
  const res = spawnSync('git', [
    'log',
    '--full-history',
    '--diff-filter=A',
    '--format=%H',
    '--',
    caminhoManifesto,
  ], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: ENV_GIT,
  });

  // AMBIENTE (2) vs. VEREDITO (1). `git log` sai != 0 em casos muito
  // diferentes, e so UM deles e veredito sobre o trabalho: o repositorio nunca
  // recebeu commit. Os outros — git ausente, fora de repositorio, historico
  // ilegivel — sao ambiente.
  //
  // A sonda e em CAMADAS, e nenhuma delas e "existe alguma ref". Essa foi a
  // tentativa anterior e errava nos dois sentidos: HEAD destacado sem branch
  // nao aparece em `for-each-ref` (e virava veredito com o objeto podre), e um
  // `fetch` sem checkout enche `refs/remotes/` num repositorio que nunca
  // commitou nada (e virava ambiente). "Tem ref em algum lugar" nao responde
  // "o HEAD tem historico legivel".
  if (res.error || res.status !== 0) {
    const gitDir = spawnSync('git', ['rev-parse', '--git-dir'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (gitDir.error || gitDir.status !== 0) {
      console.error(`git indisponivel ou fora de repositorio ao resolver a ancora de ${slug}`);
      process.exit(EXIT_GIT_FALHOU);
    }

    // 1. O HEAD resolve? Se sim, ha historico legivel e o `log` falhou por
    //    outro motivo — ambiente.
    const head = spawnSync('git', ['rev-parse', '--quiet', '--verify', 'HEAD'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (head.status === 0) {
      console.error(`git falhou ao ler o historico ao resolver a ancora de ${slug} (o HEAD resolve)`);
      process.exit(EXIT_GIT_FALHOU);
    }

    // 2. HEAD nao resolve. Destacado (nao simbolico) significa que HEAD guarda
    //    um SHA: ja houve commit, e nao resolver e historico podre — ambiente.
    const sym = spawnSync('git', ['symbolic-ref', '-q', 'HEAD'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (sym.error || sym.status !== 0) {
      console.error(`git falhou ao ler o HEAD destacado ao resolver a ancora de ${slug}`);
      process.exit(EXIT_GIT_FALHOU);
    }

    // 3. HEAD simbolico: o ref para o qual ele aponta existe? `show-ref` usa
    //    status 1 para "nao achei" e 128 para erro de verdade (packed-refs
    //    ilegivel, por exemplo) — e a distincao e por CODIGO, nunca por texto.
    const ref = sym.stdout.trim();
    const mostraRef = spawnSync('git', ['show-ref', '--verify', '--quiet', ref], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (mostraRef.status === 1) {
      return null; // ref ausente: o repositorio nunca commitou. Veredito, exit 1.
    }
    console.error(`git falhou ao resolver ${ref} ao resolver a ancora de ${slug}`);
    process.exit(EXIT_GIT_FALHOU);
  }

  const linhas = res.stdout.trim().split(/\r?\n/).filter(Boolean);
  if (linhas.length === 0) {
    return null;
  }

  // MAIS DE UMA ADICAO e veredito (1): o selo ficou ambiguo. Escolher uma
  // delas nao resolve — pela data, a data de commit e de quem commita; pela
  // topologia, e a mesma porta do merge com outro nome. Regua apagada e
  // recriada no mesmo slug cai aqui tambem, e e coerente que caia: regua
  // recriada e regua trocada. Slug novo e o caminho legitimo.
  if (linhas.length > 1) {
    console.error(`manifesto adicionado ${linhas.length} vezes no historico: selo ambiguo (docs/rainforest/reguas/${slug}.md)`);
    console.error(`  commits de adicao: ${linhas.join(' ')}`);
    console.error('  Regua trocada nao se re-sela no mesmo slug: crie outro.');
    process.exit(EXIT_RECUSA);
  }

  return linhas[0];
}

/**
 * Os quatro contratos de formato do manifesto — `## Freios`, `### M<n>`
 * bem formado, 5 a 7, sequencial desde 1. Recebe BYTES e sai 1 no primeiro
 * que falhar. E a MESMA funcao que o selo aplica ao conteudo do commit e que
 * o `validar` aplica ao arquivo antes de selar: se fossem duas, divergiriam,
 * e o autor passaria no `validar` para reprovar no `conferir`.
 */
function validarFormato(bytes, caminhoManifesto) {
  // Aqui decodificar e legitimo: o que se procura sao
  // cabecalhos ASCII, e a integridade ja foi comparada sobre bytes.
  const linhas = normalizarEolBytes(bytes).toString('utf8').split('\n');

  // Procura pela secao "## Freios"
  const temFreios = linhas.some(linha => linha === '## Freios');
  if (!temFreios) {
    console.error(`secao obrigatoria ausente: ## Freios (${caminhoManifesto})`);
    process.exit(EXIT_RECUSA);
  }

  // Procura por cabecalhos ### M<n>
  const regexM = /^### M(\d+) +\S/;
  const regexMQualquer = /^### M/;
  const numerosM = [];
  let primeiraLinhaOffensora = null;

  for (const linha of linhas) {
    const match = linha.match(regexM);
    if (match) {
      numerosM.push(parseInt(match[1], 10));
    } else if (regexMQualquer.test(linha)) {
      // Tem "### M" mas não casa o padrão
      if (!primeiraLinhaOffensora) {
        primeiraLinhaOffensora = linha;
      }
    }
  }

  // Cabecalho `### M` malformado REPROVA, sempre — nunca e ignorado.
  //
  // Antes ele so era relatado quando NENHUM casava, e isso deixava o teto de
  // 5-7 burlavel: cinco bem formados mais `### M6:` e `### M7:` contavam
  // cinco, passavam a faixa e saiam 0, com dois mecanismos que o validador
  // nunca viu. `references/formato-manifesto.md` diz que essas formas sao
  // REJEITADAS, e divergencia entre o doc e a regex e defeito pela propria
  // letra daquele arquivo.
  if (primeiraLinhaOffensora) {
    console.error(`cabecalho de mecanismo fora do formato '### M<n> ': ${primeiraLinhaOffensora} (${caminhoManifesto})`);
    process.exit(EXIT_RECUSA);
  }

  // Valida: 5 a 7 mecanismos
  if (numerosM.length < 5 || numerosM.length > 7) {
    console.error(`quantidade invalida de mecanismos: ${numerosM.length} (esperado 5-7) (${caminhoManifesto})`);
    process.exit(EXIT_RECUSA);
  }

  // Valida: sequencial a partir de 1, sem buraco e sem repetido
  for (let i = 0; i < numerosM.length; i++) {
    if (numerosM[i] !== i + 1) {
      console.error(`mecanismos nao sequenciais ou com buraco: ${numerosM.join(', ')} (${caminhoManifesto})`);
      process.exit(EXIT_RECUSA);
    }
  }
}

/**
 * Resolve a âncora, valida que existe, valida o formato do manifesto.
 * Retorna a string do hash (âncora) se tudo ok.
 * Faz process.exit(1 ou 2) se há erro. Nunca retorna em caso de falha.
 */
function exigirAncoraEFormato(slug) {
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  const existeNaArvore = fs.existsSync(caminhoManifesto);
  const ancora = ancoraDe(slug);

  // AUSENCIA SEM ANCORA e uso errado (2): nao ha regua com esse slug.
  if (!ancora && !existeNaArvore) {
    console.error(`arquivo não encontrado: ${caminhoManifesto}`);
    process.exit(2);
  }

  // Existe na arvore mas nunca entrou no git: veredito (1). Nao ha selo.
  if (!ancora) {
    console.error(`manifesto nunca foi commitado: ${caminhoManifesto}`);
    process.exit(EXIT_RECUSA);
  }

  // SELADO E APAGADO tambem e veredito (1), nunca ambiente. Sumir com o
  // manifesto e da mesma familia de edita-lo, e classificar isso como uso
  // errado manda o operador para o remedio de ambiente — refazer o checkout
  // com historico — quando o que houve foi o manifesto deixar a arvore.
  if (!existeNaArvore) {
    console.error(`manifesto selado e removido da arvore de trabalho: ${caminhoManifesto}`);
    process.exit(EXIT_RECUSA);
  }

  // Lê o conteúdo do commit
  const resShow = spawnSync('git', [
    'show',
    `${ancora}:${caminhoManifesto}`,
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: ENV_GIT,
  });

  if (resShow.error || resShow.status !== 0) {
    console.error(`erro ao ler conteudo do commit ${ancora}: ${caminhoManifesto}`);
    process.exit(EXIT_GIT_FALHOU);
  }

  // Sem `encoding` no spawn acima: `resShow.stdout` vem Buffer.
  const bytesCommit = resShow.stdout;
  const bytesArquivo = fs.readFileSync(caminhoManifesto);

  // Compara BYTES, so com EOL normalizado. Decodificar antes de comparar
  // apagaria diferenca real: byte invalido vira U+FFFD dos dois lados.
  if (!normalizarEolBytes(bytesCommit).equals(normalizarEolBytes(bytesArquivo))) {
    console.error(`manifesto editado na arvore de trabalho: ${caminhoManifesto}`);
    process.exit(EXIT_RECUSA);
  }

  validarFormato(bytesCommit, caminhoManifesto);

  return ancora;
}

// ============== Main

const subcomando = process.argv[2];
const slug = arg('slug');

// Slug monta caminho (`docs/rainforest/reguas/<slug>.md`) em tres pontos. Sem
// validar, `--slug '../../../skills/regua/SKILL'` le fora da pasta de reguas e
// o selo passa a ter dois pontos por onde burlar, nao um (design D3). A recusa
// vem de `validarSlug` (scripts/recibo.cjs), que ja sai 2 com motivo nomeado.
// Falta de `--slug` continua caindo no `uso()` de cada subcomando, que e a
// mensagem certa para quem chamou errado.
if (slug) validarSlug(slug);

if (subcomando === 'validar') {
  // ANTES de selar. Confere so o formato do arquivo na arvore — sem ancora,
  // porque ainda nao ha commit — e nao imprime o manifesto: o `mostrar`
  // continua sendo o unico caminho que imprime (D3). Sem este subcomando,
  // manifesto selado com erro de formato ficava sem conserto: a ancora e a
  // primeira adicao, a quebrada, e o orquestrador travado ali tinha o
  // incentivo exato para ler o arquivo direto.
  if (!slug) {
    uso();
    process.exit(2);
  }

  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;
  if (!fs.existsSync(caminhoManifesto)) {
    console.error(`arquivo não encontrado: ${caminhoManifesto}`);
    process.exit(2);
  }

  validarFormato(fs.readFileSync(caminhoManifesto), caminhoManifesto);
  console.error(`formato ok: ${caminhoManifesto} — pode selar (commitar).`);
  process.exit(0);
} else if (subcomando === 'conferir') {
  if (!slug) {
    uso();
    process.exit(2);
  }

  exigirAncoraEFormato(slug);
  process.exit(0);
} else if (subcomando === 'mostrar') {
  if (!slug) {
    uso();
    process.exit(2);
  }

  const ancora = exigirAncoraEFormato(slug);
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  const resShow = spawnSync('git', [
    'show',
    `${ancora}:${caminhoManifesto}`,
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: ENV_GIT,
  });

  if (resShow.error || resShow.status !== 0) {
    // Mesmo `git show` que acabou de funcionar dentro de exigirAncoraEFormato:
    // chegar aqui e o git mudar entre as duas chamadas. Raro — e por isso
    // mesmo nao pode sair mudo, que e o formato de erro que ninguem investiga.
    console.error(`erro ao reler o commit ${ancora}: ${caminhoManifesto}`);
    process.exit(EXIT_GIT_FALHOU);
  }

  // Buffer direto para stdout: o que o critico cego le e byte a byte o que
  // o `git show` devolve. Decodificar e reescrever trocaria byte invalido
  // por U+FFFD e a leitura deixaria de ser a do commit.
  process.stdout.write(resShow.stdout);
  process.exit(0);
} else {
  uso();
  process.exit(2);
}
