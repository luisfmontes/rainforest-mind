#!/usr/bin/env node
/**
 * Limpar branches — confere o local contra o remoto e diz o que sobrou de trabalho
 * que já acabou.
 *
 * NASCEU DE UM COMANDO QUE O LUÍS JÁ USA, e de um furo medido nele. O comando é:
 *
 *   git fetch --prune && git branch -vv | grep ' gone]' | awk '{print $1}' | xargs -r git branch -D
 *
 * Ele pega branch cujo UPSTREAM SUMIU — o caso clássico de PR mergeado e branch
 * apagada no GitHub. É o caso certo e o `-D` ali é necessário, não desleixo: quando
 * o merge do outro lado foi *squash*, o `-d` recusa, porque para o git aqueles
 * commits nunca entraram na main. Sem `-D`, o comando não limparia nada.
 *
 * O furo é que ` gone]` só enxerga quem TEVE upstream. Medido neste repo em
 * 2026-08-11:
 *
 *   branches locais ............... 10
 *   com upstream .................. 3
 *   sem upstream nenhum ........... 7   <- os `worktree-agent-*`, resíduo de subagente
 *   que o comando dele pegaria ..... 0
 *
 * As sete branches que de fato estavam sobrando eram exatamente as sete que o
 * comando não vê. Elas nascem da regra 11 (subagente edita em worktree isolado): o
 * `fechar` e o `limpar` removem o worktree, e a branch fica. Nunca foram
 * empurradas, então nunca terão upstream, então nunca ficarão ` gone]`.
 *
 * Por isso este script classifica por DOIS eixos — upstream e merge — em vez de um.
 *
 * O QUE ELE NÃO FAZ: não decide por conta própria. Sem `--remover` ele só lista.
 * E branch viva (não mergeada, upstream de pé) não entra na conta de remoção em
 * nenhuma hipótese, com ou sem `-D`.
 *
 * Uso:
 *   node scripts/limpar-branches.cjs                 # só lista, não toca em nada
 *   node scripts/limpar-branches.cjs --remover       # apaga as resolvidas (local)
 *   node scripts/limpar-branches.cjs --remover --forcar   # -D nesta rodada
 *   node scripts/limpar-branches.cjs --remover --remoto   # apaga também no origin
 *   node scripts/limpar-branches.cjs --sem-fetch --json
 *
 * Remover exige estar NA BASE e com ela em dia — a listagem, não. O porquê está
 * junto da checagem, lá embaixo; `--aqui-mesmo` desiste da exigência.
 */

const { spawnSync } = require('child_process');
const path = require('path');

const CODIGO_ROOT = path.resolve(__dirname, '..');
const REPO = process.env.CLAUDE_PROJECT_DIR || process.cwd();

const tem = (nome) => process.argv.includes(`--${nome}`);
const argValor = (nome) => {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? null : process.argv[i + 1] || null;
};

function git(args, { permitirErro = false } = {}) {
  const r = spawnSync('git', args, { cwd: REPO, encoding: 'utf8' });
  if (r.status !== 0 && !permitirErro) {
    console.error(`erro: git ${args.join(' ')}`);
    console.error((r.stderr || '').trim());
    process.exit(1);
  }
  return { ok: r.status === 0, saida: (r.stdout || '').trim(), erro: (r.stderr || '').trim() };
}

const linhas = (s) => s.split('\n').map((l) => l.trim()).filter(Boolean);

/**
 * `-D` só se ELE tiver pedido, e nunca por acidente.
 *
 * Toda outra chave do config falha para o lado de LIGAR, porque ligado é a trava.
 * Esta é o contrário: ligada, ela APAGA branch não mergeada. Então `ligado()` está
 * proibido aqui — ele devolve `true` quando a config está ilegível ou a chave não
 * existe, e isso viraria `-D` por causa de um JSON quebrado. Qualquer falha de
 * leitura vira `false`.
 */
function forcarConfigurado() {
  try {
    const { resolverConfig } = require('../hooks/lib/config.cjs');
    return resolverConfig({ projeto: REPO, plugin: CODIGO_ROOT }).valores['branch-forcar'] === true;
  } catch {
    return false;
  }
}

/**
 * A base de comparação. Com `--base <ref>` é essa ref, sem mais pergunta — quem
 * pediu decide. Sem a flag: não chuta `main`, pergunta ao remoto, e só então tenta
 * os nomes usuais.
 */
function descobrirBase(override) {
  if (override) {
    const r = git(['rev-parse', '--verify', '--quiet', override], { permitirErro: true });
    return r.ok && r.saida ? override : null;
  }
  const h = git(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], { permitirErro: true });
  if (h.ok && h.saida) return h.saida.replace(/^origin\//, '');
  for (const nome of ['main', 'master']) {
    const r = git(['rev-parse', '--verify', '--quiet', nome], { permitirErro: true });
    if (r.ok && r.saida) return nome;
  }
  return null;
}

/**
 * Confirma se a remota de fato sumiu, usando `git ls-remote` de verdade.
 * O `fetch --prune` deixa ` gone]` no track, mas não prova nada: se a rede caiu,
 * ou a credencial expirou, o reflexo local fica desatualizado.
 *
 * Devolve mapa { nome -> true/false/null }, onde:
 *   `true` = ls-remote confirmou que a remota não existe
 *   `false` = ls-remote confirmou que a remota EXISTE (o ` gone]` é ilusão local)
 *   `null` = ls-remote falhou (sem rede, sem credencial, etc) — não conseguimos apurar
 *
 * `null` NUNCA vira remoção; quem chama trata como "continua viva" (até conseguir rede).
 */
function confirmarRemotaSumiu(refs) {
  const resultado = {};
  const candidatas = refs.filter((b) => b.sumiu);

  if (!candidatas.length) return resultado;

  for (const b of candidatas) {
    const r = spawnSync('git', ['ls-remote', '--heads', 'origin', b.nome],
      { cwd: REPO, encoding: 'utf8' });

    if (r.status !== 0) {
      // Falha de rede, credencial, ou qualquer outro erro em leitura da remota
      resultado[b.nome] = null;
    } else {
      // exit 0: temos resposta do remoto. Vazia = não existe, com conteúdo = existe
      resultado[b.nome] = !r.stdout.trim();
    }
  }

  return resultado;
}

/**
 * Squash sem upstream — a mesma situação do mergeada-por-squash, só que a branch
 * nunca teve upstream (típico de worktree-agent-* que foi apagado, deixando a
 * branch local órfã). Não há PR pra checkar, então testamos o conteúdo direto:
 * `git cherry-pick --no-commit` em um worktree isolado e `git diff --quiet`.
 *
 * Devolve mapa { nome -> true/false/null }, onde `true` = mergeada por conteúdo,
 * `false` = não mergeada (trabalho vivo de verdade), `null` = erro ao verificar
 * (ex.: cherry-pick falhou, worktree não se criou, etc.). `null` NUNCA vira remoção;
 * quem chama trata como "continua viva".
 */
function mergeadosPorConteudo(refs, base) {
  const resultado = {};
  const candidatas = refs.filter((b) => b.classe === 'viva' && !b.upstream);

  if (!candidatas.length) return resultado;

  for (const b of candidatas) {
    // Cria worktree isolado em temp — será removido no final, mesmo com erro
    const tempWT = `/tmp/worktree-${b.nome}-${Date.now()}`;

    // Tenta criar o worktree
    let wtOk = true;
    const addWT = spawnSync('git', ['worktree', 'add', '--detach', tempWT, 'HEAD'],
      { cwd: REPO, encoding: 'utf8' });

    if (addWT.status !== 0) {
      wtOk = false;
      resultado[b.nome] = null; // Não conseguiu verificar
    } else {
      // cherry-pick sem commit dos commits da branch que não estão na base
      const mergeBase = spawnSync('git', ['merge-base', base, b.nome],
        { cwd: REPO, encoding: 'utf8' });

      if (mergeBase.status === 0 && mergeBase.stdout) {
        const mb = mergeBase.stdout.trim();
        const pickRange = `${mb}..${b.nome}`;

        // tenta cherry-pick no worktree
        const pick = spawnSync('git', ['cherry-pick', '--no-commit', pickRange],
          { cwd: tempWT, encoding: 'utf8' });

        // se cherry-pick falhou, considere como não-mergeada (trabalho vivo)
        if (pick.status !== 0) {
          resultado[b.nome] = false;
        } else {
          // Se cherry-pick bem-sucedido, verifica se há diff
          const diff = spawnSync('git', ['diff', '--quiet', 'HEAD'],
            { cwd: tempWT, encoding: 'utf8' });

          // diff --quiet exit 0 = sem diff = mergeada por conteúdo
          resultado[b.nome] = diff.status === 0;
        }
      } else {
        resultado[b.nome] = null; // merge-base falhou
      }
    }

    // Remove o worktree em qualquer caso
    spawnSync('git', ['worktree', 'remove', '--force', tempWT],
      { cwd: REPO, encoding: 'utf8' });
  }

  return resultado;
}

/**
 * Squash apaga os commits originais da base — a única marca que sobra é o PR em
 * si, com estado `merged`. Por isso esta checagem só entra depois que os dois sinais
 * de git (`--merged` e `gone`) já disseram `viva`: nunca é o primeiro critério, é o
 * último, para quem tem upstream (sem upstream nao ha PR pra achar).
 *
 * Devolve `true` (achou PR mergeado), `false` (nao achou) ou `null` — `null` e o
 * caso "a checagem nao rodou": `gh` ausente, sem autenticacao, ou qualquer saida
 * != 0. `null` NUNCA vira remocao; quem chama trata como "continua viva".
 */
function prsMergeados() {
  // **Nenhum nome de branch entra na linha de comando.** Uma chamada só, com
  // argumentos constantes, e o cruzamento acontece aqui em JS. Não é elegância: a
  // primeira versão passava `--head <nomeBranch>` com `shell: true`, e nome de branch
  // é dado de quem empurrou — o git proíbe espaço, controle e `~^:?*[\`, mas ACEITA
  // `&`, `"`, `|`, `(`, `)` e `;`.
  //
  // Medido nesta máquina em 2026-08-17, com `shell: true`: uma branch chamada
  // `x&echo A>marca&y` fez o `echo` rodar e criar o arquivo, e a variante com `""`
  // também. Ou seja, quem consegue empurrar uma branch para um repo que você faz
  // fetch executa comando na sua máquina quando você roda esta limpeza. A alegação
  // de que "o Node escapa cada argumento" é falsa no cmd.exe, e a própria doc do
  // Node manda não passar entrada não-sanitizada com shell.
  //
  // Com argumentos constantes, o `shell: true` de fallback (que existe só para achar
  // um `gh` instalado como `.cmd`, que o spawn sem shell não alcança) não carrega
  // dado de ninguém.
  const args = ['pr', 'list', '--state', 'merged', '--limit', '200', '--json', 'headRefName'];
  const tentativas = process.platform === 'win32'
    ? [{ shell: false }, { shell: true }]
    : [{ shell: false }];
  for (const opts of tentativas) {
    const r = spawnSync('gh', args, { cwd: REPO, encoding: 'utf8', ...opts });
    // ENOENT é "não achei o executável assim" — tenta a próxima forma. Qualquer
    // outro erro, ou saída != 0 (sem auth, sem rede, repo sem GitHub por trás), é
    // `null`: a checagem não rodou, e `null` nunca vira remoção.
    if (r.error && r.error.code === 'ENOENT') continue;
    if (r.error || r.status !== 0) return null;
    try {
      const lista = JSON.parse(r.stdout || '[]');
      if (!Array.isArray(lista)) return null;
      // O `--limit 200` erra para o lado seguro: PR mergeado que ficou fora da
      // janela não aparece aqui, e a branch continua `viva` — nunca o contrário.
      return new Set(lista.map((p) => p && p.headRefName).filter(Boolean));
    } catch {
      return null;
    }
  }
  return null;
}

function coletar(baseOverride) {
  const base = descobrirBase(baseOverride);
  if (!base) {
    console.error('erro: nao achei a branch base (nem origin/HEAD, nem main, nem master)');
    process.exit(1);
  }

  const atual = git(['rev-parse', '--abbrev-ref', 'HEAD']).saida;

  // A branch PADRAO do repositorio, seja qual for a `--base`. Ela nunca e residuo de
  // worktree de agente, que e o alvo declarado deste script — e sem esta linha ela
  // vira alvo com facilidade, porque a classificacao esta CERTA e ainda assim leva
  // ao lugar errado: com `--base <branch-de-trabalho>`, a branch de trabalho saiu da
  // `main`, logo a `main` esta contida nela, logo a `main` satisfaz "ja esta na base"
  // e cai em `resolvida-remota`, que e removivel por desenho.
  //
  // Aconteceu em 2026-08-19 (Issue #23), no `fechar` de um fluxo cujo trabalho
  // ainda nao tinha chegado a `main`: sairam as 11 branches de agente (certo) e a
  // `main` local junto, e o passo seguinte morreu com `fatal: ambiguous argument
  // 'main..HEAD'`. Ali nao houve perda porque `origin/main` estava intacta; num repo
  // em que a padrao so exista localmente, ou com commit nao empurrado, e perda.
  //
  // Estar na `main` NAO protege: no incidente a pessoa estava na branch de trabalho,
  // e e por isso que a classe `atual` nao pegou o caso.
  const padrao = descobrirBase(null);

  // Branch com worktree aberto o git RECUSA apagar — e recusa certo. Marcar aqui
  // evita propor uma remoção que vai falhar, que é pior que não propor.
  const emUso = new Set();
  for (const l of linhas(git(['worktree', 'list', '--porcelain']).saida)) {
    if (l.startsWith('branch ')) emUso.add(l.slice(7).replace('refs/heads/', ''));
  }

  const mergeadas = new Set(
    linhas(git(['branch', '--merged', base, '--format=%(refname:short)']).saida),
  );

  const refs = linhas(
    git(['for-each-ref', '--format=%(refname:short)\t%(upstream:short)\t%(upstream:track)\t%(objectname:short)', 'refs/heads']).saida,
  ).map((l) => {
    const [nome, upstream, track, sha] = l.split('\t');
    return { nome, upstream: upstream || null, track: track || '', sha };
  });

  for (const b of refs) {
    b.mergeada = mergeadas.has(b.nome);
    b.sumiu = /\bgone\b/.test(b.track);
    b.adiante = /ahead \d+/.test(b.track);

    if (b.nome === base) b.classe = 'base';
    else if (b.nome === atual) b.classe = 'atual';
    else if (padrao && b.nome === padrao) b.classe = 'padrao';
    else if (emUso.has(b.nome)) b.classe = 'em-uso';
    else if (b.sumiu) b.classe = b.mergeada ? 'sumiu-mergeada' : 'sumiu-divergente';
    else if (b.mergeada) b.classe = b.upstream ? 'resolvida-remota' : 'resolvida-local';
    else b.classe = 'viva';
  }

  // Confirmação por ls-remote: o ` gone]` é só opinião local. Pergunte ao remoto.
  // Se a remota EXISTE, a branch volta a ser 'viva' (o reflexo local está desatualizado).
  // Se ls-remote FALHA, não conseguimos apurar — a branch fica como estava.
  let lsRemoteFalhou = false;
  const remotoConfirmado = confirmarRemotaSumiu(refs);
  for (const b of refs) {
    if ((b.classe === 'sumiu-mergeada' || b.classe === 'sumiu-divergente') &&
        remotoConfirmado[b.nome] === false) {
      // A remota ainda EXISTE — o ` gone]` é ilusão. Reclassifica como viva.
      b.classe = 'viva';
    } else if ((b.classe === 'sumiu-mergeada' || b.classe === 'sumiu-divergente') &&
               remotoConfirmado[b.nome] === null) {
      // Não conseguimos apurar — marca que falhamos.
      lsRemoteFalhou = true;
      // Não reclassifica — deixa em sumiu, mas sabe-se que é incerto.
    }
  }

  // Segunda passada, so em cima de quem ainda e 'viva' e tem upstream: e a
  // interseccao "squash + remoto sobrevivente" que nenhum dos dois sinais acima
  // enxerga. A consulta e UMA, feita antes do laco — nao uma por branch — e o
  // cruzamento e por nome, aqui dentro. `ghFalhou` liga quando ela nao rodou.
  let ghFalhou = false;
  const candidatas = refs.filter((b) => b.classe === 'viva' && b.upstream);
  if (candidatas.length) {
    const mergeadosNoGitHub = prsMergeados();
    if (mergeadosNoGitHub === null) ghFalhou = true;
    else {
      for (const b of candidatas) {
        if (mergeadosNoGitHub.has(b.nome)) b.classe = 'mergeada-por-squash';
      }
    }
  }

  // Terceira passada, so em cima de quem ainda e 'viva' e NAO tem upstream:
  // mesma interseccao "squash", so que sem PR pra achar. Testa por conteudo
  // em worktree isolado: cherry-pick + diff.
  const mergeadosConteudo = mergeadosPorConteudo(refs, base);
  for (const b of refs) {
    if (b.classe === 'viva' && !b.upstream && mergeadosConteudo[b.nome] === true) {
      b.classe = 'mergeada-por-conteudo';
    }
  }

  return { base, atual, refs, ghFalhou, lsRemoteFalhou };
}

/**
 * O que entra na remoção — e o que NUNCA entra.
 *
 * `viva` fica de fora sempre: é trabalho que não está na base e cujo remoto está de
 * pé. Nem `--forcar` a alcança, porque a única coisa que `-D` faz por ela é apagar
 * commit que só existe ali.
 */
// A ordem importa para a bateria de teste: a secao de MUTACAO casa, no fonte deste
// arquivo, o ultimo item deste Set seguido do fechamento do array, para sabotar a
// lista sem tocar no teste. Por isso o item sumiu-x fica por ultimo aqui, e o item
// novo entra antes dele, nao depois.
const REMOVIVEIS = new Set(['resolvida-local', 'resolvida-remota', 'sumiu-mergeada', 'mergeada-por-squash', 'mergeada-por-conteudo', 'sumiu-divergente']);

// Classes que tem remoto vivo e podem ser apagadas remotamente
const COM_REMOTO_VIVO = new Set(['resolvida-remota', 'mergeada-por-squash']);

const EXPLICA = {
  base: 'a base — nunca',
  atual: 'e onde voce esta agora',
  padrao: 'e a branch padrao do repositorio — nunca e residuo, seja qual for a --base',
  'em-uso': 'tem worktree aberto (o git recusaria)',
  'resolvida-local': 'ja esta na base e nunca foi empurrada — residuo de worktree de agente',
  'resolvida-remota': 'ja esta na base, e o remoto ainda existe',
  'sumiu-mergeada': 'o remoto foi apagado e o trabalho esta na base',
  'sumiu-divergente': 'o remoto foi apagado mas a base NAO contem estes commits (tipico de squash merge) — so o -D apaga',
  'mergeada-por-squash': 'o PR foi mergeado por squash e o remoto ainda existe — a base NAO contem estes commits (gh confirmou o merge) — so o -D apaga',
  'mergeada-por-conteudo': 'o conteudo entrou na base por squash, mas a branch nao tem upstream (worktree de agente) — so o -D apaga',
  viva: 'nao esta na base e o remoto esta de pe — trabalho vivo',
};

function main() {
  if (!git(['rev-parse', '--is-inside-work-tree'], { permitirErro: true }).ok) {
    console.error(`erro: ${REPO} nao e um repositorio git`);
    process.exit(1);
  }

  // O `--prune` é o que faz o ` gone]` aparecer. Sem ele a classificação nasce
  // velha, e branch cujo PR foi mergeado hoje continua parecendo viva.
  if (!tem('sem-fetch')) {
    const f = git(['fetch', '--prune'], { permitirErro: true });
    if (!f.ok) console.log('aviso: `git fetch --prune` falhou — a leitura pode estar velha\n');
  }

  const { base, atual, refs, ghFalhou, lsRemoteFalhou } = coletar(argValor('base'));
  const forcar = tem('forcar') || forcarConfigurado();
  let remover = tem('remover');

  // `null` de prMergeado nunca vira remocao — so avisa. Fora do modo --json: em
  // --json a saida inteira tem que ser o objeto (e' o que `alvos()`/`classe()` da
  // bateria fazem com `JSON.parse`), entao um aviso solto quebraria o parse.
  if (ghFalhou && !tem('json')) {
    console.log(
      "aviso: `gh pr list` nao respondeu (gh ausente, sem autenticacao, ou saida != 0) — " +
      "branch(es) candidata(s) a mergeada-por-squash continuam 'viva', sem checagem de PR\n",
    );
  }

  // ls-remote falhou: não conseguimos confirmar se a remota sumiu. Branches em
  // `sumiu-*` podem ainda existir no remoto. Avisar para que o usuário tente de novo
  // quando tiver rede/credencial.
  if (lsRemoteFalhou && !tem('json')) {
    console.log(
      "aviso: `git ls-remote` nao respondeu (sem rede, sem autenticacao, ou saida != 0) — " +
      "branch(es) em 'sumiu-*' podem ainda existir no remoto\n",
    );
  }

  // ESTAR NA BASE — regra do usuario, 2026-08-11, e ela protege mais do que anuncia.
  //
  // A parte óbvia: fora da base, a branch em que você está sai da conta (vira
  // `atual`), então uma rodada de limpeza feita de um lugar errado limpa quase tudo
  // e deixa justamente a que você estava usando.
  //
  // A parte que morde de verdade: TUDO aqui é medido contra a base LOCAL. Se ela
  // estiver atrás do `origin`, branch já mergeada lá em cima ainda não está na base
  // daqui — o script a chama de `viva` e não a remove. Isso erra para o lado seguro,
  // mas erra: a limpeza não limpa e parece que não havia o que limpar.
  //
  // Por isso a exigência vale para a REMOÇÃO, não para a listagem. Listar de
  // qualquer lugar é útil e não quebra nada; apagar a partir de uma leitura velha é
  // o que não dá para desfazer sem procurar SHA no reflog.
  if (remover && !tem('aqui-mesmo')) {
    const problemas = [];
    if (atual !== base) problemas.push(`voce esta em '${atual}', nao em '${base}'`);

    const atras = git(['rev-list', '--count', `${base}..origin/${base}`], { permitirErro: true });
    if (atras.ok && Number(atras.saida) > 0) {
      problemas.push(`'${base}' esta ${atras.saida} commit(s) atras de origin/${base}`);
    }

    if (problemas.length) {
      console.log('REMOCAO CANCELADA');
      for (const p of problemas) console.log(`  - ${p}`);
      console.log('');
      console.log(`Tudo aqui e medido contra a '${base}' LOCAL. Base velha faz branch ja`);
      console.log('mergeada parecer viva, e ai a limpeza nao limpa e voce acha que nao havia');
      console.log('o que limpar.');
      console.log('');
      console.log(`  git checkout ${base} && git pull`);
      console.log('');
      console.log('A listagem abaixo vale mesmo assim — so nao apaga nada.');
      console.log('');
      remover = false;
    }
  }

  const porClasse = {};
  for (const b of refs) (porClasse[b.classe] ||= []).push(b);

  // O `-d` recusa o que a base não contém. Só `sumiu-divergente` cai nesse caso, e
  // é exatamente ele que o comando original do usuario resolvia com `-D`.
  const alvos = refs.filter((b) => REMOVIVEIS.has(b.classe));
  const precisamForca = alvos.filter((b) => b.classe === 'sumiu-divergente' || b.classe === 'mergeada-por-squash' || b.classe === 'mergeada-por-conteudo');
  const vaoSair = forcar
    ? alvos
    : alvos.filter((b) => b.classe !== 'sumiu-divergente' && b.classe !== 'mergeada-por-squash' && b.classe !== 'mergeada-por-conteudo');

  if (tem('json')) {
    console.log(JSON.stringify({ base, atual, forcar, refs, alvos: vaoSair.map((b) => b.nome) }, null, 2));
    return;
  }

  console.log(`BRANCHES — base: ${base}, aqui: ${atual}`);
  console.log(`Modo de remocao: ${forcar ? 'git branch -D (FORCA)' : 'git branch -d (recusa nao mergeada)'}`);
  console.log('');

  for (const classe of ['viva', 'mergeada-por-squash', 'mergeada-por-conteudo', 'sumiu-divergente', 'sumiu-mergeada', 'resolvida-remota', 'resolvida-local', 'em-uso', 'atual', 'padrao', 'base']) {
    const lista = porClasse[classe];
    if (!lista || !lista.length) continue;
    console.log(`${classe} (${lista.length}) — ${EXPLICA[classe]}`);
    for (const b of lista) {
      const up = b.upstream ? ` -> ${b.upstream}${b.track ? ` ${b.track}` : ''}` : ' (sem upstream)';
      console.log(`  ${b.sha}  ${b.nome}${up}`);
    }
    console.log('');
  }

  if (!alvos.length) {
    console.log('Nada a remover.');
    return;
  }

  if (!remover) {
    console.log(`${vaoSair.length} branch(es) sairiam com --remover.`);
    if (precisamForca.length && !forcar) {
      console.log(`${precisamForca.length} ficariam de fora: o -d as recusa. Se o merge foi squash,`);
      console.log('o trabalho ESTA no remoto e elas sao lixo; se nao foi, sao a unica copia.');
      console.log('  nesta rodada:  node scripts/limpar-branches.cjs --remover --forcar');
      console.log('  como padrao:   node scripts/setup.cjs --ligar branch-forcar');
    }
    console.log('');
    console.log('Remover: node scripts/limpar-branches.cjs --remover');
    return;
  }

  console.log('REMOVENDO');
  const removidas = [];
  for (const b of vaoSair) {
    const r = git(['branch', forcar ? '-D' : '-d', b.nome], { permitirErro: true });
    if (r.ok) {
      removidas.push(b);
      console.log(`  ok      ${b.nome}  (${b.sha})`);
    } else {
      console.log(`  RECUSOU ${b.nome} — ${r.erro.split('\n')[0]}`);
    }
  }

  // Remoto é decisão de outra ordem: local se recria com o SHA, remoto some para
  // todo mundo. Por isso exige a flag, e por isso `sumiu-*` nem aparece aqui (o
  // remoto delas já não existe).
  if (tem('remoto')) {
    const comRemoto = removidas.filter((b) => COM_REMOTO_VIVO.has(b.classe));
    for (const b of comRemoto) {
      const r = git(['push', 'origin', '--delete', b.nome], { permitirErro: true });
      console.log(`  ${r.ok ? 'ok      origin/' : 'FALHOU  origin/'}${b.nome}`);
    }
    if (!comRemoto.length) console.log('  (nenhuma das removidas tinha remoto para apagar)');

    // Confirma com ls-remote se alguma continuou de pé
    if (comRemoto.length) {
      const remotos = git(['ls-remote', '--heads', 'origin'], { permitirErro: true });
      if (remotos.ok) {
        for (const b of comRemoto) {
          const existe = remotos.saida.includes(`refs/heads/${b.nome}`);
          if (existe) console.log(`  AVISO: origin/${b.nome} continuou de pé`);
        }
      }
    }
  } else if (removidas.some((b) => COM_REMOTO_VIVO.has(b.classe))) {
    console.log('');
    console.log('Branches removidas localmente ainda existem no origin. Para apagar la tambem:');
    console.log('  node scripts/limpar-branches.cjs --remover --remoto');
  }

  // Sem isto, `-D` seria irreversível na prática: o reflog guarda, mas ninguém
  // procura. Com o SHA na tela, desfazer é uma linha.
  if (removidas.length) {
    console.log('');
    console.log('Para trazer qualquer uma de volta:');
    for (const b of removidas) console.log(`  git branch ${b.nome} ${b.sha}`);
  }
}

if (require.main === module) main();
module.exports = { descobrirBase, forcarConfigurado, REMOVIVEIS };
