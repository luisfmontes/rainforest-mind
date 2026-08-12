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
 * se o `ideias.jsonl` está íntegro, se há trabalho da esteira parado no meio, se
 * sobrou worktree órfão, ou se o plugin instalado está atrás do repo. Essa faixa
 * é a única que sobra — e é pequena de propósito.
 *
 * O achado que motivou o arquivo (2026-08-11): o plugin instalado estava **18
 * commits atrás** do repo. Sete agentes, sete skills e a esteira inteira tinham
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
  const { out } = rodar(process.execPath, [script, 'conferir']);
  const problemas = (out.match(/^\s+- linha /gm) || []).length;
  const primeira = out.split('\n')[0] || '';
  if (/sem problemas/.test(out)) return ok('ideias', primeira);
  // `conferir` acusa e nao quebra: aqui isso vira aviso, nao alerta — arquivo com
  // pendencia continua utilizavel, e o numero e o que interessa.
  aviso('ideias', `${primeira} — ${problemas} pendencia(s)`,
    'rode: node scripts/ideias.cjs conferir');
}

// ---------------------------------------------------------------- 4. esteira
function checarEsteira() {
  const script = path.join(RAIZ_CODIGO, 'scripts', 'estado.cjs');
  if (!fs.existsSync(script)) return; // esteira e opcional
  const { out } = rodar(process.execPath, [script, 'listar'], { cwd: process.cwd() });
  if (/nenhum trabalho/.test(out)) return ok('esteira', 'nenhum trabalho em andamento');
  const linhas = out.split('\n').filter((l) => l.trim() && !/\(completo\)/.test(l));
  if (!linhas.length) return ok('esteira', 'todos os trabalhos completos');
  aviso('esteira', `${linhas.length} trabalho(s) em aberto`,
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
function checarVersaoInstalada() {
  const configDir = process.env.CLAUDE_CONFIG_DIR
    || path.join(process.env.USERPROFILE || process.env.HOME || '', '.claude');
  const nome = path.basename(RAIZ_CODIGO);
  const instalado = path.join(configDir, 'plugins', 'marketplaces', nome);
  if (!fs.existsSync(instalado)) {
    return ok('plugin instalado', 'rodando direto do repo (nenhuma copia instalada nesta config)');
  }
  // O CONTEÚDO do clone é o que carrega — e não bastava comparar commits.
  //
  // Em 2026-08-11 diagnostiquei isto errado duas vezes seguidas. Primeiro culpei o
  // clone estar atrás (estava, e o sync resolveu). Depois culpei o cache versionado
  // em `plugins/cache/<mkt>/<plugin>/<versao>/` — e cheguei a subir a versão do
  // plugin por causa disso. A medição derrubou as duas: o clone estava em `39d6510`
  // com as 10 skills, o cache tinha 3 skills congeladas de 10/08 às 12:41, e o usuario
  // via as 10. Quem carrega é o clone; o cache é outra coisa.
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
  let atrasoCommit = '';
  if (aqui.status === 0 && la.status === 0 && aqui.out !== la.out) {
    const n = rodar('git', ['rev-list', '--count', `${la.out}..HEAD`], { cwd: RAIZ_CODIGO });
    atrasoCommit = `${n.status === 0 ? n.out : '?'} commit(s) atras (${la.out.slice(0, 7)} vs ${aqui.out.slice(0, 7)})`;
  }

  const atualiza = `rode: claude plugin marketplace update ${nome} — e abra uma janela NOVA, o efeito nao alcanca as abertas`;
  if (faltando.length) {
    return alerta('plugin instalado', `carregado sem ${faltando.length} skill(s): ${faltando.join(', ')}`
      + (atrasoCommit ? `; ${atrasoCommit}` : ''), atualiza);
  }
  if (atrasoCommit) {
    // Todas as skills estão lá, mas há código novo (hook, script, regra) por vir.
    return aviso('plugin instalado', `todas as skills presentes, mas ${atrasoCommit}`, atualiza);
  }
  ok('plugin instalado', `as ${skillsLa.length} skills do repo estao no que carrega`);
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

// ---------------------------------------------------------------- saida

function main() {
  checarRaiz();
  checarInjecao();
  checarIdeias();
  checarEsteira();
  checarWorktrees();
  checarVersaoInstalada();
  checarClaudeMem();
  checarAutocompact();
  checarBranches();

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
