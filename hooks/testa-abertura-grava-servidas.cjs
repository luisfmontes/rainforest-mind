#!/usr/bin/env node
'use strict';
// @categoria: guia
// Bateria hermetica de D4 do design 2026-10-09-assunto-regua: a abertura (hooks/memoria-session-start.cjs)
// grava em <raiz>/memoria-assunto/<session_id>.json os ids das observacoes que de fato entraram no
// bloco impresso, para o canal do pedido (hooks/memoria-assunto-prompt.cjs) nao reinjetar a memoria
// que a escada de texto encurtou (o acharAlvo nao reconhece a linha encurtada).
//
// Caixa temporaria com RFM_ROOT proprio (nada toca ~/.rainforest); banco criado pelo criarSchema REAL;
// os dois hooks rodam como processo recebendo no stdin o payload que o harness envia.
// Nenhum caso le o texto de um fonte.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { slugDoCaminho } = require(path.join(__dirname, '..', 'scripts', 'lib', 'projeto-canonico.cjs'));
const ms = require('./lib/memoria-sessao.cjs');

const ABERTURA = path.join(__dirname, 'memoria-session-start.cjs');
const PEDIDO_HOOK = path.join(__dirname, 'memoria-assunto-prompt.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-abertura-grava-servidas-'));
const projeto = path.join(tmp, 'projeto-de-teste-da-bateria-de-abertura');
fs.mkdirSync(projeto);
const PROJ = slugDoCaminho(projeto);

// ---- caixa: 30 observacoes do projeto atual + 1 resumo + enchimento antigo (limiar do bm25) ----
const SUB = 'çãõ ação órfã '.repeat(20).trim();
const pristina = path.join(tmp, 'pristina');
fs.mkdirSync(pristina);
const db = new DatabaseSync(path.join(pristina, 'rainforest.db'));
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 400; i++) {
  ins.run(PROJ, 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-08-01T10:00:00.000Z', 'f' + i);
}
const idsObs = [];
for (let i = 1; i <= 30; i++) {
  const dia = String(i).padStart(2, '0');
  // A mais recente (i = 30) carrega os termos raros que o pedido do caso ponta a ponta cita.
  const raros = i === 30 ? 'zarquon flibbertigibbet ' : '';
  const corpo = i === 30 ? ' zarquon flibbertigibbet zarquon flibbertigibbet quasar' : '';
  const r = ins.run(PROJ, `## mk${i}k ${raros}ação órfã tração conexão decisão\n\n${SUB}${corpo}\n\n### Detalhe\n\ntexto`, `2026-09-${dia}T10:00:00.000Z`, 'm' + i);
  idsObs.push(Number(r.lastInsertRowid));
}
// Resumo mais novo que todas as observacoes: ocupa a primeira linha do bloco e nao tem id inteiro.
db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)')
  .run(PROJ, 'Resumo de teste', 'conteudo do resumo', '2026-10-02T10:00:00.000Z');
db.close();

// ---- infraestrutura ----
let ok = 0;
let falha = 0;
function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log('  ok   ' + nome); }
  else { falha++; console.log('  FALHA ' + nome + (detalhe ? ' — ' + String(detalhe).slice(0, 400) : '')); }
}
let contador = 0;
function novaCaixa() {
  const d = path.join(tmp, 'caixa-' + (++contador));
  fs.cpSync(pristina, d, { recursive: true });
  return d;
}
function envDe(raiz) {
  const env = { ...process.env, RFM_ROOT: raiz, CLAUDE_PROJECT_DIR: projeto };
  delete env.CLAUDE_PLUGIN_ROOT;
  return env;
}
function payloadSessao(sessao, extra) {
  const o = { hook_event_name: 'SessionStart', source: 'startup', cwd: projeto, transcript_path: path.join(tmp, 't.jsonl') };
  if (sessao !== undefined) o.session_id = sessao;
  return JSON.stringify(Object.assign(o, extra || {}));
}
function abrir(raiz, stdin) {
  const r = spawnSync(process.execPath, [ABERTURA], { input: stdin, env: envDe(raiz), encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr };
}
function contextoDe(saida) { return JSON.parse(saida).hookSpecificOutput.additionalContext; }
function marcadores(ctx) { return new Set((ctx.match(/mk(\d+)k/g) || []).map((m) => idsObs[Number(m.slice(2, -1)) - 1])); }
function lerArquivo(raiz, sessao) { return JSON.parse(fs.readFileSync(path.join(raiz, 'memoria-assunto', sessao + '.json'), 'utf8')); }
// O SQLite cria -wal/-shm so de abrir o banco: nao contam como arquivo novo da gravacao.
function lista(d) { return fs.readdirSync(d).filter((n) => !/^rainforest.db-(wal|shm)$/.test(n)).sort(); }
function mesmos(a, b) { return a.length === b.length && a.every((x) => b.includes(x)); }

async function main() {
  console.log('== a abertura grava os ids que serviu ==');

  // 1. Escada no degrau 120 e corte por observacao: so o que entrou no bloco vai ao arquivo.
  const raiz1 = novaCaixa();
  const SID = 'sessao-abertura-teste';
  const r1 = abrir(raiz1, payloadSessao(SID));
  const ctx1 = contextoDe(r1.saida);
  caso('a abertura sai com exit 0', r1.codigo === 0, r1.erro);
  caso('o bloco impresso desceu a escada ao degrau 120 e ainda cortou linhas',
    ctx1.includes('textos encurtados a 120 caracteres') && ctx1.includes('não couberam no teto'), ctx1.slice(0, 300));
  const noBloco = marcadores(ctx1);
  caso('o bloco imprime mais de uma e menos de 14 observacoes (corte real)', noBloco.size > 1 && noBloco.size < 13, noBloco.size);
  let arq1 = null;
  try { arq1 = lerArquivo(raiz1, SID); } catch (e) { arq1 = null; }
  caso('o arquivo <raiz>/memoria-assunto/<session_id>.json existe e e um array de inteiros',
    Array.isArray(arq1) && arq1.length > 0 && arq1.every(Number.isInteger), arq1);
  caso('so os ids das linhas que couberam no bloco entram no arquivo',
    arq1 !== null && mesmos(arq1, Array.from(noBloco)), JSON.stringify({ arq1, noBloco: Array.from(noBloco) }));
  caso('nenhum id de linha cortada pelo teto vai ao arquivo',
    arq1 !== null && idsObs.slice(0, 29).filter((id) => !noBloco.has(id)).every((id) => !arq1.includes(id)));
  caso('resumo nao entra no arquivo (so id inteiro de observacao)',
    arq1 !== null && arq1.length === noBloco.size && ctx1.split('\n').filter((l) => l.startsWith('[')).length === noBloco.size + 1);

  // 2. Ponta a ponta com o hook REAL do pedido: nao repete a memoria que a escada encurtou.
  const linhaEncurtada = ctx1.split('\n').find((l) => l.includes('mk30k'));
  caso('a memoria mais recente entrou no bloco da abertura, encurtada', Boolean(linhaEncurtada) && linhaEncurtada.endsWith('…'), linhaEncurtada);
  const transcrito = path.join(tmp, 'sessao-e2e.jsonl');
  fs.writeFileSync(transcrito, JSON.stringify({
    type: 'attachment',
    attachment: { type: 'hook_success', hookEvent: 'SessionStart', hookName: 'SessionStart:startup', stdout: r1.saida.trim() },
  }) + '\n');
  const PEDIDO = 'quero entender a reconciliacao zarquon flibbertigibbet quasar';
  function pedir(raiz, sessao) {
    const input = JSON.stringify({ session_id: sessao, transcript_path: transcrito, cwd: projeto, hook_event_name: 'UserPromptSubmit', prompt: PEDIDO });
    const r = spawnSync(process.execPath, [PEDIDO_HOOK], { input, env: envDe(raiz), encoding: 'utf8', timeout: 20000 });
    return { codigo: r.status, saida: r.stdout };
  }
  const controleRaiz = novaCaixa();
  const controle = pedir(controleRaiz, 'outra-sessao-sem-arquivo');
  caso('controle: sem o arquivo da abertura, a memoria encurtada e reinjetada (a semeadura pelo transcrito nao a acha)',
    controle.codigo === 0 && controle.saida.includes('mk30k'), controle.saida.slice(0, 300));
  const e2e = pedir(raiz1, SID);
  caso('ponta a ponta: com o arquivo da abertura, o hook do pedido nao repete a memoria encurtada',
    e2e.codigo === 0 && !e2e.saida.includes('mk30k'), e2e.saida.slice(0, 300));

  // 3. Retomada: soma aos ids que ja estavam no arquivo, sem duplicata.
  const raiz3 = novaCaixa();
  const SID3 = 'sessao-retomada-1';
  fs.mkdirSync(path.join(raiz3, 'memoria-assunto'));
  fs.writeFileSync(path.join(raiz3, 'memoria-assunto', SID3 + '.json'), JSON.stringify([999999]));
  const r3 = abrir(raiz3, payloadSessao(SID3, { source: 'resume' }));
  const arq3 = lerArquivo(raiz3, SID3);
  caso('retomada: o id extra continua no arquivo e os da abertura foram somados',
    r3.codigo === 0 && arq3.includes(999999) && mesmos(arq3.filter((n) => n !== 999999), Array.from(marcadores(contextoDe(r3.saida)))), JSON.stringify(arq3));
  abrir(raiz3, payloadSessao(SID3, { source: 'resume' }));
  const arq3b = lerArquivo(raiz3, SID3);
  caso('retomada repetida: sem duplicata', arq3b.length === new Set(arq3b).size && mesmos(arq3, arq3b), JSON.stringify(arq3b));

  // 4. Falhas e portas fechadas: stdout identico ao da execucao sem session_id, exit 0, sem arquivo novo.
  const raizBase = novaCaixa();
  const base = abrir(raizBase, payloadSessao(undefined));
  const antes = lista(raizBase);
  caso('sem session_id: a abertura sai normal e a pasta memoria-assunto nao nasce',
    base.codigo === 0 && base.saida.length > 0 && !fs.existsSync(path.join(raizBase, 'memoria-assunto')), base.erro);
  function portaFechada(nome, stdin, preparar) {
    const raiz = novaCaixa();
    if (preparar) preparar(raiz);
    const listaAntes = lista(raiz);
    const r = abrir(raiz, stdin);
    const listaDepois = lista(raiz);
    caso(nome + ': stdout identico, exit 0 e nenhum arquivo novo na caixa',
      r.codigo === 0 && r.saida === base.saida && mesmos(listaAntes, listaDepois), JSON.stringify({ c: r.codigo, igual: r.saida === base.saida, antes: listaAntes, depois: listaDepois }));
    return raiz;
  }
  const raizArquivo = portaFechada('memoria-assunto existe como arquivo (a gravacao falha)', payloadSessao('sessao-falha'),
    (raiz) => fs.writeFileSync(path.join(raiz, 'memoria-assunto'), 'nao sou pasta'));
  caso('o arquivo que ocupa o lugar da pasta segue intacto', fs.readFileSync(path.join(raizArquivo, 'memoria-assunto'), 'utf8') === 'nao sou pasta');
  portaFechada('stdin vazio', '');
  portaFechada('stdin {}', '{}');
  portaFechada('session_id "../fuga"', payloadSessao('../fuga'));
  portaFechada('stdin que nao e JSON', 'isto nao e json');
  caso('base de comparacao: a caixa pristina so tem o banco', mesmos(antes, lista(pristina)));

  // 5. stdin que nunca fecha: a abertura imprime na hora e o processo termina pelo teto de 1 s.
  const raiz5 = novaCaixa();
  const t0 = Date.now();
  const resultado5 = await new Promise((resolve) => {
    const filho = spawn(process.execPath, [ABERTURA], { env: envDe(raiz5), stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '';
    filho.stdout.on('data', (c) => { out += c; });
    filho.stdin.on('error', () => {});
    const guarda = setTimeout(() => { filho.kill(); resolve({ codigo: 'preso', saida: out }); }, 8000);
    filho.on('close', (codigo) => { clearTimeout(guarda); resolve({ codigo, saida: out }); });
  });
  caso('stdin que nunca fecha: stdout igual ao de sempre, exit 0 e termina sozinho (teto de 1 s)',
    resultado5.codigo === 0 && resultado5.saida === base.saida && Date.now() - t0 < 6000, JSON.stringify({ c: resultado5.codigo, ms: Date.now() - t0 }));
  caso('stdin que nunca fecha: nenhum arquivo de ids', !fs.existsSync(path.join(raiz5, 'memoria-assunto')));

  // 6. Os tres regimes de montarMemoriaComIds: .texto identico ao de montarMemoria e ids batendo com as linhas.
  const FRASE = 'Revisou a entrega do fluxo contra o design e o plano, rodou as baterias, conferiu a mutação na catraca e registrou os achados numerados com arquivo e linha';
  const SUBL = 'O subtítulo também é longo no banco real: conta o que mudou, onde, e o que ficou de fora para depois, com o arquivo e o motivo de cada decisão tomada na sessão.';
  const obs = (i, tamTitulo, sub = SUBL) => ({
    id: 100 + i, projeto: 'rainforest-mind', criada_em: `2026-09-${String(26 - Math.floor(i / 3)).padStart(2, '0')}T10:00:00Z`,
    conteudo: `## ${(`Obs ${i}: ` + FRASE + ' ' + FRASE).slice(0, tamTitulo)}\n\n${sub}\n\n### Detalhe\n\ntexto`,
  });
  const CAB = '## Memória (corpus residentes)\n';
  const ROD = '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"';
  const TETO = ms.TETOS.MEMORIA_MAX_BYTES;
  const nLinhas = (t) => t.split('\n').filter((l) => l.startsWith('[2026-')).length;

  const curtas = Array.from({ length: 5 }, (_, i) => obs(i, 60, 'Resumo curto.'));
  const inteiro = ms.montarMemoriaComIds({ observacoes: curtas });
  caso('regime inteiro: .texto igual ao de montarMemoria e igual ao bloco esperado, sem aviso',
    inteiro.texto === ms.montarMemoria({ observacoes: curtas }) && inteiro.texto === CAB + curtas.map((o) => ms.formatarObservacao(o)).join('\n') + ROD);
  caso('regime inteiro: ids = todos, na ordem', JSON.stringify(inteiro.ids) === JSON.stringify(curtas.map((o) => o.id)) && nLinhas(inteiro.texto) === inteiro.ids.length);

  const medias = Array.from({ length: 10 }, (_, i) => obs(i, 120));
  const escada = ms.montarMemoriaComIds({ observacoes: medias });
  const degrau = Number((escada.texto.match(/encurtados a (\d+)/) || [])[1]);
  const linhasDegrau = medias.map((o) => ms.formatarObservacao(o, null, degrau));
  caso('regime escada: .texto igual ao de montarMemoria e igual ao bloco reconstruido no degrau',
    escada.texto === ms.montarMemoria({ observacoes: medias }) &&
    escada.texto === ms.construirAvisoCorteMemoria(0, medias.length, TETO, degrau) + CAB + linhasDegrau.join('\n') + ROD, escada.texto.slice(0, 200));
  caso('regime escada: sem corte, ids = todos e batem com as linhas', escada.ids.length === 10 && nLinhas(escada.texto) === 10);

  const gordas = Array.from({ length: 30 }, (_, i) => obs(i, 435));
  const corte = ms.montarMemoriaComIds({ observacoes: gordas });
  const linhas120 = gordas.map((o) => ms.formatarObservacao(o, null, 120));
  caso('regime corte por observacao: .texto igual ao de montarMemoria e ao travarOrcamentoMemoria',
    corte.texto === ms.montarMemoria({ observacoes: gordas }) && corte.texto === ms.travarOrcamentoMemoria(linhas120, CAB, ROD, TETO, 120));
  caso('regime corte por observacao: ids = as primeiras N linhas que couberam',
    corte.ids.length === nLinhas(corte.texto) && corte.ids.length > 0 && corte.ids.length < 30 &&
    JSON.stringify(corte.ids) === JSON.stringify(gordas.slice(0, corte.ids.length).map((o) => o.id)));
  caso('banco sem observacao: texto vazio e ids vazios', JSON.stringify(ms.montarMemoriaComIds({ observacoes: [] })) === JSON.stringify({ texto: '', ids: [] }));
  const comResumo = ms.montarMemoriaComIds({ observacoes: [{ id: 'resumo_1', projeto: 'x', criada_em: '2026-09-30T10:00:00Z', conteudo: '## [resumo até 2026-09-30]\n\nT\n\nC' }, ...curtas] });
  caso('resumo ocupa a primeira linha e nao entra nos ids (so id inteiro)',
    comResumo.ids.length === 5 && comResumo.ids.every(Number.isInteger) && nLinhas(comResumo.texto) === 6);

  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('-----------------------------------------');
  console.log(`${ok} ok, ${falha} falha(s)`);
  process.exit(falha === 0 ? 0 : 1);
}

main().catch((e) => { console.log('FALHA inesperada: ' + (e && e.stack || e)); process.exit(1); });
