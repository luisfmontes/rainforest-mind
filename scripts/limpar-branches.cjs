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

/** A base de comparação. Não chuta `main`: pergunta ao remoto, e só então tenta os nomes usuais. */
function descobrirBase() {
  const h = git(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], { permitirErro: true });
  if (h.ok && h.saida) return h.saida.replace(/^origin\//, '');
  for (const nome of ['main', 'master']) {
    const r = git(['rev-parse', '--verify', '--quiet', nome], { permitirErro: true });
    if (r.ok && r.saida) return nome;
  }
  return null;
}

function coletar() {
  const base = descobrirBase();
  if (!base) {
    console.error('erro: nao achei a branch base (nem origin/HEAD, nem main, nem master)');
    process.exit(1);
  }

  const atual = git(['rev-parse', '--abbrev-ref', 'HEAD']).saida;

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
    else if (emUso.has(b.nome)) b.classe = 'em-uso';
    else if (b.sumiu) b.classe = b.mergeada ? 'sumiu-mergeada' : 'sumiu-divergente';
    else if (b.mergeada) b.classe = b.upstream ? 'resolvida-remota' : 'resolvida-local';
    else b.classe = 'viva';
  }

  return { base, atual, refs };
}

/**
 * O que entra na remoção — e o que NUNCA entra.
 *
 * `viva` fica de fora sempre: é trabalho que não está na base e cujo remoto está de
 * pé. Nem `--forcar` a alcança, porque a única coisa que `-D` faz por ela é apagar
 * commit que só existe ali.
 */
const REMOVIVEIS = new Set(['resolvida-local', 'resolvida-remota', 'sumiu-mergeada', 'sumiu-divergente']);

const EXPLICA = {
  base: 'a base — nunca',
  atual: 'e onde voce esta agora',
  'em-uso': 'tem worktree aberto (o git recusaria)',
  'resolvida-local': 'ja esta na base e nunca foi empurrada — residuo de worktree de agente',
  'resolvida-remota': 'ja esta na base, e o remoto ainda existe',
  'sumiu-mergeada': 'o remoto foi apagado e o trabalho esta na base',
  'sumiu-divergente': 'o remoto foi apagado mas a base NAO contem estes commits (tipico de squash merge) — so o -D apaga',
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

  const { base, atual, refs } = coletar();
  const forcar = tem('forcar') || forcarConfigurado();
  let remover = tem('remover');

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
  const precisamForca = alvos.filter((b) => b.classe === 'sumiu-divergente');
  const vaoSair = forcar ? alvos : alvos.filter((b) => b.classe !== 'sumiu-divergente');

  if (tem('json')) {
    console.log(JSON.stringify({ base, atual, forcar, refs, alvos: vaoSair.map((b) => b.nome) }, null, 2));
    return;
  }

  console.log(`BRANCHES — base: ${base}, aqui: ${atual}`);
  console.log(`Modo de remocao: ${forcar ? 'git branch -D (FORCA)' : 'git branch -d (recusa nao mergeada)'}`);
  console.log('');

  for (const classe of ['viva', 'sumiu-divergente', 'sumiu-mergeada', 'resolvida-remota', 'resolvida-local', 'em-uso', 'atual', 'base']) {
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
    const comRemoto = removidas.filter((b) => b.classe === 'resolvida-remota');
    for (const b of comRemoto) {
      const r = git(['push', 'origin', '--delete', b.nome], { permitirErro: true });
      console.log(`  ${r.ok ? 'ok      origin/' : 'FALHOU  origin/'}${b.nome}`);
    }
    if (!comRemoto.length) console.log('  (nenhuma tinha remoto vivo para apagar)');
  } else if (removidas.some((b) => b.classe === 'resolvida-remota')) {
    console.log('');
    console.log('As `resolvida-remota` ainda existem no origin. Para apagar la tambem:');
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
