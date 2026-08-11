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
  if (nivel === 'legado') {
    return aviso('raiz de dados', `${raiz} (nivel: legado)`,
      'nivel de ponte; monte a raiz global ou defina RFM_ROOT');
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
  const aqui = rodar('git', ['rev-parse', 'HEAD'], { cwd: RAIZ_CODIGO });
  const la = rodar('git', ['rev-parse', 'HEAD'], { cwd: instalado });
  if (aqui.status !== 0 || la.status !== 0) return;
  if (aqui.out === la.out) return ok('plugin instalado', 'na mesma versao do repo');
  const atras = rodar('git', ['rev-list', '--count', `${la.out}..HEAD`], { cwd: RAIZ_CODIGO });
  const n = atras.status === 0 ? atras.out : '?';
  alerta('plugin instalado', `${n} commit(s) atras do repo (${la.out.slice(0, 7)} vs ${aqui.out.slice(0, 7)})`,
    'o que voce escreveu no repo NAO esta valendo em sessao nova — atualize o plugin');
}

// ---------------------------------------------------------------- saida

function main() {
  checarRaiz();
  checarInjecao();
  checarIdeias();
  checarEsteira();
  checarWorktrees();
  checarVersaoInstalada();

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
