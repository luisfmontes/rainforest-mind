#!/usr/bin/env node
/**
 * Saúde do rainforest — só o que os checadores oficiais NÃO sabem.
 *
 * O Claude Code já entrega dois, e reimplementá-los é custo sem retorno:
 *
 *   claude doctor                      instalação: PATH, duplicata, atualização
 *   claude plugin details <nome>       inventário de componentes e custo de token
 *
 * Nenhum dos dois sabe de quem é a raiz de dados, se a injeção cabe no orçamento,
 * se o `ideias.jsonl` está íntegro, se há trabalho do fluxo parado no meio, se
 * sobrou worktree órfão, ou se o plugin instalado está atrás do repo. Essa faixa
 * é a única que sobra — e é pequena de propósito.
 *
 * O achado que motivou o arquivo (2026-08-11): o plugin instalado estava **18
 * commits atrás** do repo. Sete agentes, sete skills e o fluxo inteiro tinham
 * sido escritos e nada disso valia numa sessão nova. O inventário oficial dizia
 * — listava `grill`, renomeado horas antes — e ninguém tinha olhado.
 *
 * Barato de propósito: nada aqui roda bateria de teste. Comando que demora vira
 * comando que ninguém chama, e a graça deste é ser chamado sem pensar. Quando
 * algo cheira mal, ele APONTA qual bateria rodar.
 *
 * Uso: node scripts/saude.cjs [--json]
 * Saída: exit 0 se tudo ok, 1 se houver ALERTA.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const RAIZ_CODIGO = path.resolve(__dirname, '..');
const achados = [];

// ---- constantes de tempo
const QUARENTA_E_OITO_HORAS_MS = 48 * 60 * 60 * 1000;

function ok(item, detalhe) { achados.push({ nivel: 'ok', item, detalhe }); }
function aviso(item, detalhe, acao) { achados.push({ nivel: 'aviso', item, detalhe, acao }); }
function alerta(item, detalhe, acao) { achados.push({ nivel: 'alerta', item, detalhe, acao }); }

function rodar(cmd, args, opts = {}) {
  try {
    const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 20000, ...opts });
    return { status: r.status, out: `${r.stdout || ''}${r.stderr || ''}`.trim() };
  } catch {
    return { status: null, out: '' };
  }
}

// ---------------------------------------------------------------- 1. raiz de dados
// A pergunta que nenhum checador oficial faz: estes dados são SEUS?
function checarRaiz() {
  let r;
  try {
    ({ resolverRaiz: r } = require('../hooks/lib/raiz.cjs'));
  } catch {
    return alerta('raiz de dados', 'nao consegui carregar hooks/lib/raiz.cjs',
      'o plugin esta incompleto — reinstale');
  }
  const { raiz, nivel } = r();
  if (!raiz) {
    return alerta('raiz de dados', 'nenhuma raiz encontrada',
      'rode o setup, ou aponte RFM_ROOT para a sua pasta de dados');
  }
  if (nivel === 'plugin') {
    // O caso que motivou a checagem: quem instala e nao configura cai na raiz do
    // PLUGIN, e passa a receber o foco e as ideias de outra pessoa.
    return alerta('raiz de dados', `${raiz} (nivel: plugin)`,
      'esta e a pasta do PLUGIN — o foco e as ideias que voce esta vendo sao de quem o publicou. Rode o setup.');
  }
  ok('raiz de dados', `${raiz} (nivel: ${nivel})`);
}

// ---------------------------------------------------------------- 2. injecao
function checarInjecao() {
  const hook = path.join(RAIZ_CODIGO, 'hooks', 'foco-session-start.cjs');
  if (!fs.existsSync(hook)) return alerta('injecao', 'hook de abertura ausente', 'reinstale o plugin');
  const { status, out } = rodar(process.execPath, [hook]);
  if (status !== 0 || !out) return alerta('injecao', 'o hook de abertura nao rodou', `saida: ${out.slice(0, 120)}`);
  let ctx;
  try {
    ctx = JSON.parse(out).hookSpecificOutput.additionalContext;
  } catch {
    return alerta('injecao', 'o hook nao devolveu JSON com additionalContext', 'a sessao sobe sem as regras');
  }
  const bytes = Buffer.byteLength(ctx, 'utf8');
  let teto = 8000;
  try { teto = require('../hooks/lib/contexto-sessao.cjs').TETOS.ORCAMENTO_BYTES; } catch { /* usa o default */ }
  const margem = teto - bytes;
  if (ctx.includes('ACIMA DO ORÇAMENTO')) {
    return alerta('injecao', `${bytes} B para um teto de ${teto} — a trava disparou`,
      'conteudo esta sendo cortado; encolha regra ou foco');
  }
  if (ctx.includes('FALHA AO CARREGAR AS REGRAS')) {
    return alerta('injecao', 'as regras nao carregaram', 'a sessao sobe sem regra nenhuma');
  }
  if (margem < 100) {
    return aviso('injecao', `${bytes} B, margem de ${margem} B`,
      'no fio: uma janela nova ou um avanco a mais derruba conteudo da abertura');
  }
  ok('injecao', `${bytes} B, margem de ${margem} B`);
}

// ---------------------------------------------------------------- 3. ideias
function checarIdeias() {
  const script = path.join(RAIZ_CODIGO, 'scripts', 'ideias.cjs');
  if (!fs.existsSync(script)) return aviso('ideias', 'scripts/ideias.cjs ausente', 'reinstale o plugin');
  const { status, out } = rodar(process.execPath, [script, 'conferir']);
  const problemas = (out.match(/^\s+- linha /gm) || []).length;
  // A linha do RESUMO, nao a primeira do stdout: desde 0.53.0 o `conferir` abre
  // dizendo o caminho do arquivo, e pegar a primeira linha punha o caminho no
  // lugar da contagem.
  const linhas = out.split('\n');
  const primeira = linhas.find((l) => /^\d+ linhas,/.test(l)) || linhas[0] || '';
  // Quem decide se e ok e o EXIT CODE do conferir, nao a contagem de linhas: desde
  // 2026-08-12 ele separa divida HERDADA (nao bloqueia, sai 0) de problema novo. A
  // versao anterior lia so o numero e reportava aviso permanente com 35 pendencias
  // que nao bloqueavam nada — o mesmo defeito do gate sempre vermelho, um andar
  // acima (Issue #3).
  if (status === 0) {
    return ok('ideias', problemas
      ? `${primeira} — ${problemas} de divida herdada, nenhuma bloqueia`
      : primeira);
  }
  // `conferir` acusa e nao quebra: aqui isso vira aviso, nao alerta — arquivo com
  // pendencia continua utilizavel, e o numero e o que interessa.
  aviso('ideias', `${primeira} — ${problemas} pendencia(s)`,
    'rode: node scripts/ideias.cjs conferir');
}

// ---------------------------------------------------------------- 4. fluxo
function checarFluxo() {
  const script = path.join(RAIZ_CODIGO, 'scripts', 'estado.cjs');
  if (!fs.existsSync(script)) return; // fluxo e opcional
  const { out } = rodar(process.execPath, [script, 'listar'], { cwd: process.cwd() });
  if (/nenhum trabalho/.test(out)) return ok('fluxo', 'nenhum trabalho em andamento');
  const linhas = out.split('\n').filter((l) => l.trim() && !/\(completo\)/.test(l));
  if (!linhas.length) return ok('fluxo', 'todos os trabalhos completos');

  // O slug do trabalho e `<data>-<nome da branch>` — convencao que se sustenta no
  // acervo (`2026-08-17-memoria-e-dados-do-rainforest.json` <-> a branch
  // `memoria-e-dados-do-rainforest`). Tirar a data e comparar com o HEAD responde
  // uma pergunta que a listagem sozinha nao responde: **esta branch tem dono?**
  //
  // Em 2026-08-20 (Issue #25) esta checagem ja tinha as duas metades do fato e
  // imprimiu so uma. A sessao leu `1 trabalho(s) em aberto -> revisar` como estado
  // do fluxo, nao como "a branch em que voce esta e de outro", e commitou em cima
  // do trabalho alheio. Quando a correcao veio, a outra sessao ja tinha commitado
  // por cima, e desfazer custou `rebase --onto` + `push --force-with-lease`,
  // trocando o hash do commit dela. O fato existia 20 minutos antes do commit.
  //
  // O aviso NAO diz "nao commite": a sessao DONA do fluxo commita nessa branch o
  // tempo todo e com razao. Ele diz de quem e a branch, e quem sabe se e sua e voce.
  const r = rodar('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: process.cwd() });
  const branch = r.status === 0 ? r.out.trim() : '';
  const daBranch = branch && branch !== 'HEAD'
    ? linhas.find((l) => l.trim().split(/\s+/)[0].replace(/^\d{4}-\d{2}-\d{2}-/, '') === branch)
    : null;

  if (daBranch) {
    return aviso('fluxo', `${linhas.length} trabalho(s) em aberto — ESTA branch tem dono: ${daBranch.trim()}`,
      `se o trabalho nao e seu, comece o seu em branch nova (regra 11) — a partir da base, nao daqui:\n` +
      `        git checkout -b <sua-branch> $(git rev-parse --abbrev-ref origin/HEAD)\n` +
      linhas.map((l) => `  ${l.trim()}`).join('\n'));
  }

  aviso('fluxo', `${linhas.length} trabalho(s) em aberto`,
    linhas.map((l) => `  ${l.trim()}`).join('\n'));
}

// ---------------------------------------------------------------- 5. worktrees
function checarWorktrees() {
  const { status, out } = rodar('git', ['worktree', 'list'], { cwd: process.cwd() });
  if (status !== 0) return; // nao e repo git, nada a dizer
  const orfaos = out.split('\n').filter((l) => /[\\/]\.claude[\\/]worktrees[\\/]/.test(l));
  if (!orfaos.length) return ok('worktrees', 'nenhum worktree de agente pendurado');
  aviso('worktrees', `${orfaos.length} worktree(s) de agente ainda montado(s)`,
    'rode a skill `limpar` — worktree orfao nasce da sessao que nao chegou ao `fechar`');
}

// ---------------------------------------------------------------- 6. plugin vs repo
// O achado de 2026-08-11: 18 commits de atraso, e nada do que foi construido
// naquele dia valia numa sessao nova.
//
// O achado de 2026-08-17: a checagem voltou a mentir, e desta vez com a resposta
// MAIS SAUDAVEL do painel. Rodando a copia instalada, ela imprimia
// "rodando direto do repo (nenhuma copia instalada nesta config)" — enquanto o
// codigo que executava estava 6 commits atras, entre eles o proprio conserto do
// radar multi-janela. Medido no mesmo minuto, na mesma maquina, na mesma config:
//
//   $ (cd <cache>/0.65.0 && node scripts/saude.cjs)
//     OK     plugin instalado: rodando direto do repo (nenhuma copia instalada...)
//   $ (cd <repo> && CLAUDE_CONFIG_DIR=<mesma> node scripts/saude.cjs)
//     AVISO  plugin instalado: ... 6 commit(s) atras (a78132b vs 14dc7ad)
//
// Tres defeitos somados, e cada um sozinho ja bastava para o silencio:
//
//   1. O NOME do plugin saia de `path.basename(RAIZ_CODIGO)`. Rodando do cache
//      versionado (`plugins/cache/<mkt>/<plugin>/<versao>/`), o basename e a
//      VERSAO — "0.65.0" —, entao o clone procurado era
//      `plugins/marketplaces/0.65.0`, que nunca existe. A ausencia caia no ramo
//      de sucesso. Nome de plugin sai do MANIFESTO, que e onde ele e declarado;
//      basename e o nome da pasta, e pasta se renomeia.
//   2. So UMA config dir era olhada (`CLAUDE_CONFIG_DIR || ~/.claude`). Esta
//      maquina tem duas (`~/.claude` = trabalho, `~/.claude-personal` = pessoal)
//      com o plugin habilitado nas duas, e a divergencia silenciosa entre elas ja
//      tinha custado as regras da CLAUDE.md uma vez.
//   3. Rodando do cache, RAIZ_CODIGO nao e repo git — nao ha com o que comparar.
//      A resposta certa ali e dizer que a pergunta nao pode ser feita daqui, nao
//      responder "esta tudo bem". Medidor que nao sabe dizer "nao sei" e a mesma
//      familia do `? commit(s) atras` de 2026-08-11.
//
// E o que EXECUTA e o cache, nao o clone: sao dois artefatos independentes, e o
// `installed_plugins.json` e quem sabe qual versao/commit foi instalada. O clone
// pode ter sido atualizado hoje (foi, as 13:41) sem o install acompanhar.

/**
 * Nome e versao do plugin pelo MANIFESTO, com o basename so como ultimo recurso.
 *
 * O fallback existe para fonte sem manifesto (a bateria monta uma), e nao para o
 * caso do cache: la o manifesto existe e e ele que da a resposta certa.
 */
function manifestoDoPlugin(raiz) {
  try {
    const m = JSON.parse(fs.readFileSync(path.join(raiz, '.claude-plugin', 'plugin.json'), 'utf8'));
    if (m && typeof m.name === 'string' && m.name.trim()) {
      return { nome: m.name.trim(), versao: typeof m.version === 'string' ? m.version : null };
    }
  } catch { /* sem manifesto legivel: cai no basename */ }
  return { nome: path.basename(raiz), versao: null };
}

/**
 * Config dirs do harness a inspecionar.
 *
 * `CLAUDE_CONFIG_DIR` posto no ambiente e uma DECLARACAO — "a config e esta" —, e
 * quando ele existe a varredura para nele. Isso nao e detalhe: e o que mantem a
 * bateria HERMETICA. Varrer a home de qualquer jeito faria o teste ler as config
 * dirs reais de quem roda, e o resultado passaria a depender da maquina do dono —
 * exatamente o que a bateria deste repo deixou de aceitar em 2026-08-17.
 *
 * Sem a variavel, varre a home: `.claude` e `.claude-*` que tenham `plugins/`. O
 * discriminador e o `plugins/`, nao o nome — `.claude-mem` e `.claude-flow` casam
 * o prefixo e sao de outros programas (a mesma armadilha ja documentada na
 * checagem de autocompact).
 */
function configDirsDoHarness() {
  if (process.env.CLAUDE_CONFIG_DIR) return [path.resolve(process.env.CLAUDE_CONFIG_DIR)];
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (!home) return [];
  try {
    return fs.readdirSync(home)
      .filter((n) => n === '.claude' || n.startsWith('.claude-'))
      .map((n) => path.join(home, n))
      .filter((d) => fs.existsSync(path.join(d, 'plugins')))
      .map((d) => path.resolve(d));
  } catch {
    return [];
  }
}

/**
 * As instalacoes registradas de um plugin numa config dir.
 *
 * O `installed_plugins.json` e o unico lugar que diz QUAL versao esta instalada e
 * de que commit ela saiu — o cache em si nao e repo git e nao sabe se responder.
 * A chave e `<plugin>@<marketplace>`, e o mesmo plugin pode ter mais de uma
 * entrada (escopo `user` e escopo `local` por projeto).
 */
function instalacoesRegistradas(configDir, nome) {
  let registro;
  try {
    registro = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins', 'installed_plugins.json'), 'utf8'));
  } catch {
    return [];
  }
  const mapa = (registro && registro.plugins) || {};
  const saida = [];
  for (const [chave, lista] of Object.entries(mapa)) {
    if (chave.split('@')[0] !== nome) continue;
    for (const item of Array.isArray(lista) ? lista : []) {
      if (item && item.installPath) saida.push({ chave, ...item });
    }
  }
  return saida;
}

/**
 * As config dirs da maquina, SEM a declaracao do `CLAUDE_CONFIG_DIR`.
 *
 * Existe separada de `configDirsDoHarness()` de proposito, e a diferenca entre as
 * duas e a coisa mais importante deste bloco: la a declaracao PARA a varredura,
 * porque a pergunta e "o que executa NESTA sessao esta atras?" — pergunta sobre a
 * sessao, e a sessao carrega uma config so. Aqui a pergunta e outra, de
 * inventario: "as contas desta maquina estao na mesma versao?". Declaracao de
 * sessao nao responde pergunta de inventario, entao esta ignora a variavel.
 *
 * Nao e incoerencia, e nao "conserte" igualando as duas: alargar a
 * `configDirsDoHarness` faria a checagem 6 reclamar de uma copia que nao tem nada
 * a ver com a janela aberta, e quebraria a hermeticidade da bateria — que foi o
 * defeito que este repo extinguiu em 2026-08-17.
 */
function todasAsConfigDirsDaHome() {
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (!home) return [];
  try {
    return fs.readdirSync(home)
      .filter((n) => n === '.claude' || n.startsWith('.claude-'))
      .map((n) => path.join(home, n))
      .filter((d) => fs.existsSync(path.join(d, 'plugins')))
      .map((d) => path.resolve(d));
  } catch {
    return [];
  }
}

/**
 * Contas do harness em versoes diferentes do MESMO plugin.
 *
 * Esta maquina tem duas config dirs (`~/.claude` = trabalho, `~/.claude-personal`
 * = pessoal) e o plugin habilitado nas duas. Em 2026-08-20, depois de quatro PRs
 * e de um `claude plugin update`, o pessoal estava em 0.71.0 e o trabalho em
 * 0.70.0 — e o painel dizia `ok`, porque a checagem 6 obedece (corretamente) a
 * declaracao do `CLAUDE_CONFIG_DIR` e para na config ativa. Metade do setup certa
 * e a outra divergindo em silencio: e a mesma forma do incidente das duas
 * CLAUDE.md mantidas a mao, que ja custou um dia.
 *
 * **Silencio quando batem, de proposito.** Uma linha dizendo "as duas contas estao
 * iguais" e inventario 364 dias por ano; o evento e a divergencia. E `aviso`,
 * nunca alerta, porque divergir as vezes e ESCOLHA — travar o perfil de trabalho
 * numa versao estavel enquanto o pessoal anda na frente e legitimo, e instrumento
 * que trata escolha como defeito e desligado em duas semanas.
 *
 * So o plugin deste repo entra na comparacao. O inventario alheio e barulho de
 * outra pessoa.
 */
function checarConfigDirsDivergentes() {
  const { nome } = manifestoDoPlugin(RAIZ_CODIGO);
  const dirs = todasAsConfigDirsDaHome();
  if (dirs.length < 2) return; // uma config so nao diverge de ninguem

  const instalacoes = [];
  for (const d of dirs) {
    for (const i of instalacoesRegistradas(d, nome)) {
      instalacoes.push({
        dir: path.basename(d),
        versao: i.version || '?',
        sha: i.gitCommitSha ? i.gitCommitSha.slice(0, 7) : '?',
      });
    }
  }
  if (instalacoes.length < 2) return; // instalado numa conta so: nao ha par

  const assinaturas = new Set(instalacoes.map((i) => `${i.versao}|${i.sha}`));
  if (assinaturas.size === 1) return;

  aviso('config dirs',
    `${nome} em versoes diferentes: ${instalacoes.map((i) => `[${i.dir}] ${i.versao} (${i.sha})`).join(', ')}`,
    'se for escolha, ignore. Se nao for, atualize a atrasada com CLAUDE_CONFIG_DIR apontando para ela — ' +
    'e o efeito so alcanca janelas NOVAS daquela conta');
}

function checarVersaoInstalada() {
  const { nome, versao: versaoRepo } = manifestoDoPlugin(RAIZ_CODIGO);

  // Sem repo git sob os pes, a comparacao nao existe — e dizer isso e a resposta,
  // nao um detalhe de implementacao. Este e o ramo em que a versao anterior
  // imprimia "rodando direto do repo" e encerrava o assunto.
  const dentroDeGit = rodar('git', ['rev-parse', '--is-inside-work-tree'], { cwd: RAIZ_CODIGO });
  if (dentroDeGit.status !== 0 || dentroDeGit.out !== 'true') {
    return aviso('plugin instalado',
      `rodando a copia INSTALADA (${RAIZ_CODIGO}${versaoRepo ? `, versao ${versaoRepo}` : ''}), que nao e repo git`,
      'daqui nao da para saber se ha codigo novo. Rode o `/saude` de dentro do repo do plugin');
  }

  const dirs = configDirsDoHarness();
  const relatos = dirs
    .map((cfg) => avaliarConfigDir(cfg, nome, versaoRepo))
    .filter(Boolean);

  if (!relatos.length) {
    return ok('plugin instalado', 'rodando direto do repo (nenhuma copia instalada nesta config)');
  }

  // Prefixo so quando ha mais de uma config dir com o plugin: com uma so, ele
  // seria ruido em toda linha.
  const rotular = (r) => (relatos.length > 1 ? `[${path.basename(r.dir)}] ${r.detalhe}` : r.detalhe);
  const piores = ['alerta', 'aviso', 'ok'];
  const nivel = piores.find((n) => relatos.some((r) => r.nivel === n)) || 'ok';
  const relevantes = nivel === 'ok' ? relatos : relatos.filter((r) => r.nivel === nivel);
  const detalhe = relevantes.map(rotular).join(' | ');
  const acao = relevantes.map((r) => r.acao).filter(Boolean)[0];

  if (nivel === 'alerta') return alerta('plugin instalado', detalhe, acao);
  if (nivel === 'aviso') return aviso('plugin instalado', detalhe, acao);
  return ok('plugin instalado', detalhe);
}

/**
 * Avalia UMA config dir: o clone do marketplace e a instalacao que executa.
 *
 * Devolve `null` quando o plugin nao esta nessa config dir — ausencia nao e achado.
 */
function avaliarConfigDir(configDir, nome, versaoRepo) {
  const instalado = path.join(configDir, 'plugins', 'marketplaces', nome);
  const instalacoes = instalacoesRegistradas(configDir, nome);
  if (!fs.existsSync(instalado) && !instalacoes.length) return null;

  const doInstall = avaliarInstalacoes(instalacoes, versaoRepo, nome);
  if (!fs.existsSync(instalado)) {
    return doInstall || { dir: configDir, nivel: 'ok', detalhe: 'instalacao em dia com o repo' };
  }
  const doClone = avaliarClone(instalado, nome, instalacoes);
  // Aviso do install vem junto do clone: sao artefatos diferentes, e o clone em
  // dia com o install atrasado e justamente o caso que ninguem procura.
  if (doInstall && doClone.nivel === 'ok') return { ...doInstall, dir: configDir };
  if (doInstall && doClone.nivel !== 'ok') {
    return { ...doClone, dir: configDir, detalhe: `${doClone.detalhe}; ${doInstall.detalhe}` };
  }
  return { ...doClone, dir: configDir };
}

/**
 * Compara o que EXECUTA (cache versionado) com o repo.
 *
 * Devolve `null` quando nao ha divergencia — o silencio aqui e informativo, porque
 * o chamador so fala de install quando ha o que dizer.
 */
function avaliarInstalacoes(instalacoes, versaoRepo, nome) {
  if (!instalacoes.length) return null;
  const atras = [];
  const indeterminados = [];
  const chavesAtras = new Set();
  for (const i of instalacoes) {
    const partes = [];
    if (versaoRepo && i.version && i.version !== versaoRepo) {
      partes.push(`versao ${i.version} instalada contra ${versaoRepo} no repo`);
    }
    if (i.gitCommitSha) {
      const n = rodar('git', ['rev-list', '--count', `${i.gitCommitSha}..HEAD`], { cwd: RAIZ_CODIGO });
      // Comando que falha = commit desconhecido aqui. Nao vira contagem nem
      // interrogacao: vira a frase que descreve o que se sabe.
      if (n.status === 0 && Number(n.out) > 0) partes.push(`${n.out} commit(s) atras`);
      else if (n.status !== 0) partes.push(`instalada de um commit que este repo nao conhece (${i.gitCommitSha.slice(0, 7)})`);
    } else {
      // O campo simplesmente NAO EXISTE no registro (diferente de existir e nao
      // bater — esse e o `else if` acima). Sem ele nao ha o que comparar: nao e
      // "em dia" nem "atras", e um `ok` silencioso aqui e um `ok` que nao
      // conferiu nada. Fica de fora do `atras` porque a frase "esta atras" seria
      // uma afirmacao que este ramo nao tem base para fazer.
      indeterminados.push(i.version ? `versao ${i.version} sem 'gitCommitSha' no registro` : `sem 'gitCommitSha' no registro`);
    }
    if (partes.length) {
      atras.push(partes.join(', '));
      // A chave de QUEM esta atras, nao a primeira do registro: o mesmo plugin pode
      // ter entrada de mais de um marketplace, e mandar atualizar a errada nao
      // conserta nada. Havendo mais de uma atras, todas sao nomeadas.
      chavesAtras.add(i.chave || nome);
    }
  }
  if (atras.length) {
    return {
      nivel: 'aviso',
      detalhe: `o que EXECUTA esta atras: ${[...new Set(atras)].join('; ')}`,
      acao: `rode: claude plugin update ${[...chavesAtras].join(' e ') || nome} — e abra uma janela NOVA, o efeito nao alcanca as abertas`,
    };
  }
  if (indeterminados.length) {
    return {
      nivel: 'aviso',
      detalhe: `nao da para saber se o que EXECUTA esta em dia: ${[...new Set(indeterminados)].join('; ')}`,
      acao: 'o registro nao guarda o commit da instalacao para comparar com o repo — '
        + 'confira a mao (data de instalacao, `claude plugin details`) se e uma copia recente',
    };
  }
  return null;
}

function avaliarClone(instalado, nome, instalacoes) {
  // O CONTEÚDO do clone é o que carrega — e não bastava comparar commits.
  //
  // Em 2026-08-11 diagnostiquei isto errado duas vezes seguidas. Primeiro culpei o
  // clone estar atrás (estava, e o sync resolveu). Depois culpei o cache versionado
  // em `plugins/cache/<mkt>/<plugin>/<versao>/` — e cheguei a subir a versão do
  // plugin por causa disso. A medição derrubou as duas: o clone estava em `39d6510`
  // com as 10 skills, o cache tinha 3 skills congeladas de 10/08 às 12:41, e o usuario
  // via as 10. Quem carrega é o clone; o cache é outra coisa.
  //
  // CORREÇÃO de 2026-08-17 — a conclusão acima vale para a PALETA de skills, e só
  // para ela. O que EXECUTA sai do cache versionado: a injeção de abertura desta
  // máquina cita o próprio caminho de onde o hook rodou, e ele era
  // `plugins/cache/rainforest-mind/rainforest-mind/0.65.0/skills/...`. Hook, script
  // e agente vêm de lá. Por isso o cache agora é medido também, pelo
  // `installed_plugins.json` (ver `avaliarInstalacoes`), e não substituído por ele:
  // clone e install atrasam de forma independente.
  //
  // Comparar commit não basta porque um clone pode estar no commit certo e ainda
  // não ter sido re-escaneado. O sinal barato e visível é o CONTEÚDO: nome de skill
  // presente lá e aqui. É o que o usuario vê na lista de comandos, então é o que a
  // checagem tem que olhar.
  const listar = (base) => {
    try { return fs.readdirSync(path.join(base, 'skills')).sort(); } catch { return []; }
  };
  const skillsAqui = listar(RAIZ_CODIGO);
  const skillsLa = listar(instalado);
  const faltando = skillsAqui.filter((s) => !skillsLa.includes(s));

  // Commit é sinal SECUNDÁRIO, e por isso vem depois: clone no commit certo com
  // conteúdo faltando é o caso que dói, e a versão anterior desta checagem
  // devolvia cedo no commit e nunca chegava a olhar o conteúdo.
  const aqui = rodar('git', ['rev-parse', 'HEAD'], { cwd: RAIZ_CODIGO });
  const la = rodar('git', ['rev-parse', 'HEAD'], { cwd: instalado });

  // TRÊS situações, não uma — e a versão anterior desta checagem só sabia contar.
  //
  // Ela fazia `rev-list --count <la>..HEAD` e, quando o comando falhava, imprimia
  // `? commit(s) atras`. Isso aconteceu de verdade em 2026-08-11, depois de o
  // histórico ser reescrito para publicar: o commit do clone deixou de existir
  // aqui, a contagem virou impossível, e o `/saude` respondeu com uma
  // interrogação. Ficou mudo justamente no caso em que a resposta era mais útil —
  // e o conserto ali NÃO é o `marketplace update`, que não reconcilia histórias
  // sem parentesco.
  //
  // Medidor que não sabe dizer "esta pergunta não se aplica" é pior que medidor
  // ausente: a interrogação parece ruído de ferramenta, não achado.
  let atrasoCommit = '';
  let semParentesco = false;
  if (aqui.status === 0 && la.status === 0 && aqui.out !== la.out) {
    // O DISCRIMINADOR É O COMMIT RAIZ, e a primeira versão disto errou.
    //
    // Ela perguntava "o commit do clone existe aqui?" e, quando não existia,
    // concluía história sem parentesco. O teste derrubou na hora: um clone que fez
    // um commit próprio também tem um objeto que este repo não conhece — e ali o
    // parentesco existe, só não voltou. Ausência de objeto não é ausência de
    // parentesco.
    //
    // O commit raiz resolve sem depender de os dois lados compartilharem objeto
    // nenhum: histórias com a mesma origem têm a mesma raiz, e reescrever o
    // histórico troca a raiz. É a única pergunta que os dois repositórios sabem
    // responder sozinhos.
    const raizDe = (dir) => {
      const r = rodar('git', ['rev-list', '--max-parents=0', 'HEAD'], { cwd: dir });
      return r.status === 0 ? r.out.split('\n').pop().trim() : null;
    };
    const raizAqui = raizDe(RAIZ_CODIGO);
    const raizLa = raizDe(instalado);
    const par = `(${la.out.slice(0, 7)} vs ${aqui.out.slice(0, 7)})`;

    if (raizAqui && raizLa && raizAqui !== raizLa) {
      semParentesco = true;
    } else {
      const n = rodar('git', ['rev-list', '--count', `${la.out}..HEAD`], { cwd: RAIZ_CODIGO });
      if (n.status === 0) {
        atrasoCommit = `${n.out} commit(s) atras ${par}`;
      } else {
        // Mesma raiz, mas o commit do clone não chegou aqui: alguém commitou na
        // cópia instalada. Não é atraso — é trabalho que só existe lá, e o
        // `marketplace update` passaria por cima dele.
        atrasoCommit = `o clone tem commit proprio que este repo nao conhece ${par}`;
      }
    }
  }

  // O comando `marketplace update` recebe o nome do MARKETPLACE, nao a chave
  // `<plugin>@<marketplace>` — sao dois comandos diferentes. E a origem sai do
  // registro lido, nao da primeira entrada: o mesmo plugin pode vir de mais de
  // um marketplace, e nesse caso os dois sao nomeados em vez de um ser escolhido
  // em silencio.
  const marketplaces = [...new Set(
    (instalacoes || []).map((i) => i.chave && i.chave.split('@')[1]).filter(Boolean)
  )];
  const marketplace = marketplaces.join(' ou ') || nome;
  const atualiza = `rode: claude plugin marketplace update ${marketplace} — e abra uma janela NOVA, o efeito nao alcanca as abertas`;

  // Sem parentesco vem ANTES da checagem de skill: mesmo com todas as skills no
  // lugar, o clone está preso a uma história que não existe mais, e o comando de
  // atualizar não resolve isso.
  if (semParentesco) {
    return {
      nivel: 'alerta',
      detalhe: `o clone esta numa historia sem parentesco com este repo (${la.out.slice(0, 7)} nao existe aqui)`,
      acao: `o \`marketplace update\` NAO reconcilia isso. Reaponte o clone:\n        `
        + `git -C "${instalado}" fetch origin && git -C "${instalado}" reset --hard origin/main`,
    };
  }
  if (faltando.length) {
    return {
      nivel: 'alerta',
      detalhe: `carregado sem ${faltando.length} skill(s): ${faltando.join(', ')}`
        + (atrasoCommit ? `; ${atrasoCommit}` : ''),
      acao: atualiza,
    };
  }
  if (atrasoCommit) {
    // Todas as skills estão lá, mas há código novo (hook, script, regra) por vir.
    return { nivel: 'aviso', detalhe: `todas as skills presentes, mas ${atrasoCommit}`, acao: atualiza };
  }
  return { nivel: 'ok', detalhe: `as ${skillsLa.length} skills do repo estao no que carrega` };
}

// ---------------------------------------------------------------- 7. claude-mem
/**
 * O worker do claude-mem, medido pela PORTA e não pelo PID.
 *
 * Colhe a ideia `guarda-saude-worker-claude-mem`. O modo de falha, medido em
 * agosto de 2026 e sentido pelo usuario várias vezes: o guarda de spawn do
 * claude-mem só olha se o PID está vivo. Com **PID vivo e porta muda** ele
 * recusa subir um worker novo ("Worker already running, refusing to start
 * duplicate") — o sistema não tem como se curar, os hooks falham em sequência,
 * e aos 19 falhos o disjuntor bloqueia o `UserPromptSubmit` e **derruba o prompt
 * do usuario**. Ele descobre pela tela, no meio de uma frase.
 *
 * Por isso a checagem é aqui e é assim: PID vivo não é evidência de worker vivo;
 * só a porta responder é. E o contador de falhas consecutivas é o aviso que
 * chega ANTES do bloqueio — que é o ponto inteiro de checar.
 *
 * Reporta e oferece; não recicla sozinho. Matar processo é mexer no ambiente do
 * o usuario (regra 15), e isso se pergunta.
 */
function checarClaudeMem() {
  const home = process.env.USERPROFILE || process.env.HOME || '';
  const dir = process.env.CLAUDE_MEM_DIR || path.join(home, '.claude-mem');
  if (!fs.existsSync(dir)) return; // não instalado: não é problema deste plugin

  // Disjuntor primeiro: ele é o que derruba o prompt.
  const falhasPath = path.join(dir, 'state', 'hook-failures.json');
  let consecutivas = 0;
  try {
    consecutivas = JSON.parse(fs.readFileSync(falhasPath, 'utf8')).consecutiveFailures || 0;
  } catch { /* sem arquivo = sem falha registrada */ }

  const pidPath = path.join(dir, 'worker.pid');
  let info;
  try {
    info = JSON.parse(fs.readFileSync(pidPath, 'utf8'));
  } catch {
    if (consecutivas > 0) {
      return alerta('claude-mem', `sem worker.pid e ${consecutivas} falha(s) consecutiva(s) de hook`,
        'o worker nao esta de pe; o disjuntor vai bloquear o prompt');
    }
    return ok('claude-mem', 'sem worker registrado');
  }

  const vivo = (() => {
    try { process.kill(info.pid, 0); return true; } catch (e) { return !!(e && e.code === 'EPERM'); }
  })();

  const responde = (() => {
    const r = spawnSync(process.execPath, ['-e', `
      const net=require('net');
      const s=net.connect({host:'127.0.0.1',port:${Number(info.port)}},()=>{s.destroy();process.exit(0)});
      s.setTimeout(2000,()=>{s.destroy();process.exit(1)});
      s.on('error',()=>process.exit(1));
    `], { timeout: 6000 });
    return r.status === 0;
  })();

  if (!responde && vivo) {
    // O impasse exato: o guarda ve PID vivo e recusa reciclar; a porta esta muda.
    return alerta('claude-mem', `worker ${info.pid} vivo mas a porta ${info.port} nao responde`,
      `e o impasse que derruba o seu prompt — o guarda de spawn vai recusar subir outro. Encerre o ${info.pid} e deixe subir limpo.`);
  }
  if (!responde) {
    return aviso('claude-mem', `porta ${info.port} nao responde (worker ${info.pid} tambem morreu)`,
      'sobe sozinho no proximo hook; se repetir, e o worker saturando');
  }
  if (consecutivas > 0) {
    return aviso('claude-mem', `porta ${info.port} ok, mas ${consecutivas} falha(s) consecutiva(s) de hook`,
      'degradando — o disjuntor bloqueia o prompt ao acumular; vale reciclar antes');
  }
  const uptimeMin = info.startedAt
    ? Math.round((Date.now() - Date.parse(info.startedAt)) / 60000)
    : null;
  ok('claude-mem', `porta ${info.port} responde${uptimeMin !== null ? `, worker de pe ha ${uptimeMin} min` : ''}`);
}

// ---------------------------------------------------------------- 8. autocompact
/**
 * O ponto de autocompact, e — mais importante — se as config dirs concordam.
 *
 * Isto existe por um defeito que o próprio o usuario documentou na CLAUDE.md dele: há
 * **duas** config dirs nesta máquina (`~/.claude` = trabalho, `~/.claude-personal`
 * = pessoal), mantidas em sincronia à mão. "Editar uma acerta metade do setup e a
 * outra diverge em silêncio" — e foi o que aconteceu em 2026-08-10. Divergência
 * silenciosa é justamente o que um health check serve para quebrar.
 *
 * A manopla é `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, lida do bloco `env` do
 * settings.json. Do binário 2.1.220:
 *
 *   if (n !== undefined && !isNaN(n) && n > 0 && n <= 100)
 *     return Math.min(Math.floor(janelaUtil * (n / 100)), janelaUtil - 13000);
 *
 * Ela é **porcentagem da janela útil**, e compacta quando o uso chega lá. Repare no
 * `n > 0 && n <= 100`: valor fora da faixa é **ignorado em silêncio**, e o padrão
 * volta. Esse é o pior modo de falha possível — você configurou, leu que
 * configurou, e não está valendo. Por isso a faixa é checada aqui.
 *
 * O check NÃO recomenda um número: 45 é a preferência do usuario, não uma verdade.
 * Ele reporta o que está valendo, e grita quando as duas dirs discordam.
 */
function checarAutocompact() {
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (!home) return;

  // `~/.claude*` NÃO basta como filtro, e a primeira versão desta checagem provou
  // isso na primeira execução: ela acusou divergência entre `.claude`, `.claude-mem`
  // e `.claude-personal`. O `.claude-mem` tem um `settings.json` que é dele — um
  // mapa raso de `CLAUDE_MEM_*`, sem nada do harness. Comparar as duas coisas é
  // comparar config do Claude Code com config de outro programa, e o alerta que sai
  // dali é ruído com cara de achado.
  //
  // O que separa: as chaves de topo do harness. Config dir de verdade tem pelo menos
  // uma delas; config de terceiro não tem nenhuma.
  const CHAVES_DO_HARNESS = ['env', 'model', 'hooks', 'permissions', 'statusLine',
    'enabledPlugins', 'outputStyle', 'defaultView', 'effortLevel'];

  let candidatas;
  try {
    candidatas = fs.readdirSync(home)
      .filter((n) => n === '.claude' || n.startsWith('.claude-'))
      .map((n) => path.join(home, n))
      .filter((d) => fs.existsSync(path.join(d, 'settings.json')));
  } catch {
    return;
  }

  const lidas = [];
  for (const dir of candidatas) {
    let cfg;
    try {
      cfg = JSON.parse(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'));
    } catch {
      // JSON ilegível não deixa ver as chaves de topo, então a classificação cai
      // para o disco: config dir do harness tem `plugins/` ou uma CLAUDE.md ao lado.
      // Sem isso, é `settings.json` de outro programa e o problema não é nosso.
      const ehDoHarness = ['plugins', 'CLAUDE.md', 'commands', 'settings.local.json']
        .some((m) => fs.existsSync(path.join(dir, m)));
      if (ehDoHarness) lidas.push({ nome: path.basename(dir), bruto: null, quebrado: true });
      continue;
    }
    if (!cfg || typeof cfg !== 'object') continue;
    if (!CHAVES_DO_HARNESS.some((k) => k in cfg)) continue; // config de outro programa
    lidas.push({ nome: path.basename(dir), bruto: (cfg.env || {}).CLAUDE_AUTOCOMPACT_PCT_OVERRIDE ?? null, quebrado: false });
  }
  if (!lidas.length) return; // nenhuma config de usuário: nada a dizer

  const quebradas = lidas.filter((l) => l.quebrado);
  if (quebradas.length) {
    return alerta('autocompact', `settings.json ilegivel em: ${quebradas.map((l) => l.nome).join(', ')}`,
      'JSON quebrado — o Claude Code ignora o arquivo inteiro, nao so esta chave');
  }

  // Fora da faixa o binário descarta sem avisar, e o padrão volta valendo.
  const foraDaFaixa = lidas.filter((l) => {
    if (l.bruto === null) return false;
    const n = parseFloat(l.bruto);
    return !(Number.isFinite(n) && n > 0 && n <= 100);
  });
  if (foraDaFaixa.length) {
    return alerta('autocompact', `valor invalido em ${foraDaFaixa.map((l) => `${l.nome}=${l.bruto}`).join(', ')}`,
      'so vale 0 < n <= 100; fora disso o Claude Code IGNORA em silencio e o padrao volta');
  }

  const distintos = [...new Set(lidas.map((l) => String(l.bruto)))];
  if (distintos.length > 1) {
    return alerta('autocompact', lidas.map((l) => `${l.nome}=${l.bruto ?? '(nao definido)'}`).join(', '),
      'as config dirs DIVERGEM — mantidas a mao, uma edicao acerta metade do setup');
  }

  const valor = lidas[0].bruto;
  const onde = lidas.length > 1 ? ` (igual nas ${lidas.length} config dirs)` : '';
  if (valor === null) {
    return ok('autocompact', `no padrao do Claude Code${onde}`,
      undefined);
  }
  ok('autocompact', `compacta aos ${valor}% da janela util${onde}`);
}

// ---------------------------------------------------------------- 9. branches
// Irmã da checagem de worktree, e o buraco que ela deixava: remover o worktree não
// remove a branch. Medido em 2026-08-11 — zero worktree órfão, sete branches
// `worktree-agent-*` penduradas.
function checarBranches() {
  const script = path.join(RAIZ_CODIGO, 'scripts', 'limpar-branches.cjs');
  if (!fs.existsSync(script)) return;
  // `--sem-fetch` de propósito: health check não faz rede. A leitura pode estar
  // velha para o caso `gone`, e isso erra para menos — nunca inventa alvo.
  const { status, out } = rodar(process.execPath, [script, '--sem-fetch', '--json'], { cwd: process.cwd() });
  if (status !== 0) return; // não é repo git, ou não há base: nada a dizer
  let dados;
  try { dados = JSON.parse(out); } catch { return; }
  const n = (dados.alvos || []).length;
  if (!n) return ok('branches', 'nenhuma branch de trabalho ja resolvido sobrando');
  aviso('branches', `${n} branch(es) de trabalho ja resolvido ocupando o \`git branch\``,
    'rode: node scripts/limpar-branches.cjs (lista; so remove com --remover)');
}

// ---------------------------------------------------------------- 10. esquema
/**
 * Checagem de esquema do banco de dados.
 *
 * Achado 2 (2026-08-19): o schema mudou para UNIQUE(projeto, origem), mas
 * bancos existentes que tinham constraint diferente não migravam. A checagem
 * aqui detecta o descompasso ANTES que a aplicação encontre violações.
 *
 * Verificações:
 * - Tabela observacoes tem UNIQUE(projeto, origem)?
 * - Coluna offset_processado existe em marca_dagua?
 *
 * Tarefa 18 (D21): fala com banco via adaptador abrirBancoSomenteLeitura,
 * removendo duplicação de acesso ao sqlite3.
 */
function checarEsquema() {
  let raizDados;
  try {
    const { resolverRaiz } = require('../hooks/lib/raiz.cjs');
    const { raiz } = resolverRaiz({ plugin: RAIZ_CODIGO });
    raizDados = raiz;
  } catch {
    return; // sem raiz de dados: nada a checar
  }

  if (!raizDados) {
    return; // sem raiz: nada a checar
  }

  const caminhoDb = path.join(raizDados, 'rainforest.db');
  if (!fs.existsSync(caminhoDb)) {
    return; // sem banco: nada a checar
  }

  // Tarefa 18: Usar adaptador (memoria.cjs) em vez de carregar driver direto
  let abrirBancoSomenteLeitura, verificarConstraintUniqueProjetoOrigem;
  try {
    ({ abrirBancoSomenteLeitura, verificarConstraintUniqueProjetoOrigem } = require('../scripts/memoria.cjs'));
  } catch {
    return; // não consegui carregar adaptador: nada a checar
  }

  const db = abrirBancoSomenteLeitura(caminhoDb);
  if (!db) {
    return; // banco indisponível: degradação silenciosa
  }

  try {
    const problemas = [];

    // Verificação 1: observacoes tem UNIQUE(projeto, origem)?
    if (!verificarConstraintUniqueProjetoOrigem(db)) {
      problemas.push('observacoes sem UNIQUE(projeto, origem) — bancos legados precisam migrar');
    }

    // Verificação 2: marca_dagua tem offset_processado?
    try {
      const colunas = db.prepare('PRAGMA table_info(marca_dagua)').all();
      const temOffset = colunas.some(c => c.name === 'offset_processado');

      if (!temOffset) {
        problemas.push('marca_dagua sem coluna offset_processado — migração de tarefa 11 ausente');
      }
    } catch (e) {
      problemas.push(`erro ao verificar marca_dagua: ${e.message}`);
    }

    if (problemas.length > 0) {
      return alerta('esquema de banco', problemas.join('; '),
        'rode: node scripts/memoria.cjs iniciar — a migração é automática e idempotente');
    }
    ok('esquema de banco', 'observacoes com UNIQUE(projeto, origem), marca_dagua com offset_processado');
  } catch (e) {
    // Erro grave ao abrir banco: não é schema, é arquivo corrompido ou inacessível
    alerta('esquema de banco', `nao consegui ler banco: ${e.message}`,
      'o banco pode estar corrompido; procure um backup em .rainforest-*/');
  } finally {
    try {
      db.close();
    } catch {
      // Ignorar erro ao fechar
    }
  }
}

// ---------------------------------------------------------------- 10.5 conselho
/**
 * Checagem do conselho — rodadas abertas e ABANDONAs.
 * Procura em process.cwd() para ser independente de onde o plugin está instalado.
 * Só relata aviso se houver rodada ABANDONA ou parada aberta sem progresso.
 * Seção ausente se não houver nada a relatar.
 */
function checarConselho() {
  const dirConselho = path.join(process.cwd(), '.rainforest', 'conselho');
  if (!fs.existsSync(dirConselho)) {
    return; // sem conselho: seção ausente
  }

  try {
    const rodadas = fs.readdirSync(dirConselho)
      .filter(d => /^202\d{5}-/.test(d))
      .sort()
      .reverse();

    if (!rodadas.length) {
      return; // nenhuma rodada: seção ausente
    }

    const problemas = [];
    for (const rodada of rodadas) {
      const estadoPath = path.join(dirConselho, rodada, 'estado.json');
      if (!fs.existsSync(estadoPath)) continue;

      let estado;
      try {
        estado = JSON.parse(fs.readFileSync(estadoPath, 'utf8'));
      } catch {
        continue;
      }

      if (estado.resultado === 'ABANDONA') {
        problemas.push(`${rodada}: ABANDONA (3ª falha consecutiva na mesma fase)`);
      } else if (estado.fases) {
        // Rodada aberta parada (qualquer fase pendente)
        const pendentes = Object.keys(estado.fases).filter(f => estado.fases[f].status === 'pendente');
        if (pendentes.length > 0) {
          problemas.push(`${rodada}: parada na fase ${pendentes[0]}`);
        }
      }
    }

    if (!problemas.length) return; // tudo bem: seção ausente

    aviso('conselho', `${problemas.length} rodada(s) com aviso: ${problemas.join('; ')}`);
  } catch {
    // erro ao ler: silenciar
  }
}

// ---------------------------------------------------------------- 11. banco de memoria
/**
 * Checagem do banco de dados de memória do rainforest.
 *
 * Três verificações:
 * 1. Banco abre e schema confere → ALERTA se falhar
 * 2. count(observacoes) == count(observacoes_fts) → AVISO se divergir
 * 3. Pendência de marca d'água (offset > offset_processado) com >48h → AVISO
 *
 * Banco ausente é estado legítimo ("instalação sem memória é ok").
 */
function checarMemoria() {
  let raizDados;
  try {
    const { resolverRaiz } = require('../hooks/lib/raiz.cjs');
    const { raiz } = resolverRaiz({ plugin: RAIZ_CODIGO });
    raizDados = raiz;
  } catch {
    return; // sem raiz de dados: nada a checar
  }

  if (!raizDados) {
    return; // sem raiz: nada a checar
  }

  const caminhoDb = path.join(raizDados, 'rainforest.db');
  if (!fs.existsSync(caminhoDb)) {
    return ok('banco de memoria', 'ausente (instalacao sem memoria e estado legitimo)');
  }

  // Tentar abrir o banco somente-leitura
  let abrirBancoSomenteLeitura;
  try {
    ({ abrirBancoSomenteLeitura } = require('../scripts/memoria.cjs'));
  } catch {
    return; // não consegui carregar adaptador: nada a checar
  }

  const db = abrirBancoSomenteLeitura(caminhoDb);
  if (!db) {
    return alerta('banco de memoria', 'nao consegui abrir (arquivo corrompido ou inacessivel)',
      'o banco pode estar corrompido; procure um backup em .rainforest-*/');
  }

  try {
    const problemas = [];

    // Verificação 1: tabelas existem e schema é válido
    try {
      const tabelas = db.prepare(`
        SELECT name FROM sqlite_master
        WHERE type='table' AND name IN ('observacoes', 'marca_dagua', 'observacoes_fts')
      `).all();
      const tabelasPresentes = tabelas.map(t => t.name);
      if (!tabelasPresentes.includes('observacoes') || !tabelasPresentes.includes('marca_dagua')) {
        problemas.push('schema incompleto (observacoes ou marca_dagua faltam)');
      }
    } catch (e) {
      problemas.push(`erro ao verificar schema: ${e.message}`);
    }

    // Verificação 2: count(observacoes) == count(observacoes_fts)
    // Índice vivo: se os dois não batem, o FTS descala
    try {
      const countObservacoes = db.prepare('SELECT COUNT(*) as n FROM observacoes').all()[0]?.n || 0;
      const countFts = db.prepare('SELECT COUNT(*) as n FROM observacoes_fts').all()[0]?.n || 0;

      if (countObservacoes !== countFts) {
        problemas.push(`indice vivo diverge: observacoes=${countObservacoes} vs observacoes_fts=${countFts}`);
      }
    } catch (e) {
      problemas.push(`erro ao verificar indice vivo: ${e.message}`);
    }

    // Verificação 3: pendência de marca d'água com >48h
    // Offset visto > offset processado = há trabalho parado
    // Se parado há mais de 48h, avisa. Menos de 48h não acusa (Q3).
    try {
      const marcas = db.prepare(`
        SELECT processada_em, offset, offset_processado
        FROM marca_dagua
        WHERE offset > COALESCE(offset_processado, 0)
      `).all();

      for (const marca of marcas) {
        if (!marca.processada_em) continue;
        const tempoPassado = Date.now() - Date.parse(marca.processada_em);
        if (tempoPassado > QUARENTA_E_OITO_HORAS_MS) {
          problemas.push(`pipeline parado ha mais de 48h (marca: ${marca.processada_em})`);
          break; // relatar só a primeira, não saturar
        }
      }
    } catch (e) {
      problemas.push(`erro ao verificar marca dagua: ${e.message}`);
    }

    // Reportar resultado
    if (problemas.length > 0) {
      const eh_critico = problemas.some(p => p.includes('schema incompleto') || p.includes('corrupto'));
      const eh_aviso_indice = problemas.some(p => p.includes('indice vivo'));
      const eh_aviso_pipeline = problemas.some(p => p.includes('pipeline parado'));

      if (eh_critico) {
        return alerta('banco de memoria', problemas.join('; '),
          'rode: node scripts/memoria.cjs iniciar — a migração é automática e idempotente');
      }

      if (eh_aviso_indice) {
        return aviso('banco de memoria', `${problemas.join('; ')} (rode memoria.cjs reindexar para reparar)`,
          'rode: node scripts/memoria.cjs reindexar — reconstrói o FTS');
      }

      if (eh_aviso_pipeline) {
        return aviso('banco de memoria', `${problemas.join('; ')} (rode observar.cjs para processar)`,
          'rode: node scripts/observar.cjs — processa a fila de observações');
      }

      // C2: erro imprevisto não vira ok
      // Se chegou aqui e ainda tem problemas, é algo que nenhum pattern acima reconheceu.
      // Reportar como ALERTA genérico com as mensagens coladas.
      return alerta('banco de memoria', `erro imprevisto não classificado: ${problemas.join('; ')}`,
        'verifique o banco com: node scripts/memoria.cjs esquema');
    }

    return ok('banco de memoria', 'schema valido, indice vivo, pipeline em dia');
  } catch (e) {
    // Erro grave ao auditar banco
    return alerta('banco de memoria', `erro durante auditoria: ${e.message}`,
      'o banco pode estar corrompido; procure um backup em .rainforest-*/');
  } finally {
    try {
      db.close();
    } catch {
      // Ignorar erro ao fechar
    }
  }
}

// ---------------------------------------------------------------- saida

function main() {
  checarRaiz();
  checarInjecao();
  checarIdeias();
  checarFluxo();
  checarWorktrees();
  checarVersaoInstalada();
  checarConfigDirsDivergentes();
  checarClaudeMem();
  checarAutocompact();
  checarBranches();
  checarConselho();
  checarEsquema();
  checarMemoria();

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(achados, null, 2));
  } else {
    const marca = { ok: '  ok    ', aviso: '  aviso ', alerta: 'ALERTA  ' };
    for (const a of achados) {
      console.log(`${marca[a.nivel]}${a.item}: ${a.detalhe}`);
      if (a.acao) console.log(`        -> ${a.acao}`);
    }
    console.log('');
    const alertas = achados.filter((a) => a.nivel === 'alerta').length;
    const avisos = achados.filter((a) => a.nivel === 'aviso').length;
    console.log(`${alertas} alerta(s), ${avisos} aviso(s), ${achados.length - alertas - avisos} ok`);
    console.log('');
    console.log('Instalacao e custo de token sao dos checadores oficiais, nao deste:');
    console.log('  claude doctor                          saude da instalacao');
    console.log('  claude plugin details rainforest-mind  inventario e custo');
  }
  process.exit(achados.some((a) => a.nivel === 'alerta') ? 1 : 0);
}

if (require.main === module) main();
module.exports = { achados };
