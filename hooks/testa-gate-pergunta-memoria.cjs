#!/usr/bin/env node
/**
 * Bateria do gate-pergunta-memoria.cjs (Stop, D6 do plano 2026-10-28-colheita-observacoes).
 *
 * Processo real do hook, payload real de Stop (session_id, transcript_path, cwd,
 * hook_event_name, stop_hook_active). Cada caso monta um mkdtemp com o transcrito e a
 * pasta memory/ do fixture, e um RFM_ROOT com sessoes.json de duas sessões vivas: uma
 * do mesmo repositório do cwd e uma de outro.
 *
 *   P1 memoria-responde.jsonl: exit 2; stderr traz Q1, o arquivo, a description e a sessão do OUTRO repo
 *   P2 o mesmo texto com marcador **Q2 -**: exit 2 e Q2 no stderr
 *   P3 memoria-nao-responde.jsonl: exit 0
 *   P4 o texto do P1 sem nenhum Q<n>: exit 0
 *   P5 P1 com stop_hook_active: exit 0
 *   P6 P1 com agent_id: exit 0
 *   P7 P1 sem pasta memory/: exit 0
 *   P8 P1 com .rainforest/config.json do cwd com gate-pergunta-memoria false: exit 0
 *   P9 transcript_path inexistente: exit 0
 *   P14 recap em prosa ("Fechado: Q1 (b), ... como fica?"), Q1 no meio da linha: exit 0
 *   P15 pergunta cujo único vocabulário comum com a memória é o do projeto (regra, fluxo...): exit 0
 *   P16 banco: observação do projeto atual que abre com `---` e cabeçalho: exit 2 com o trecho útil;
 *       a mesma observação gravada em OUTRO projeto: exit 0
 *
 * Os exit 0 de P5 a P9 são contrastados com o P1 do mesmo jeito: a mesma montagem, só
 * a condição muda, então um exit 0 sem o mecanismo não passa por acidente.
 *
 * Uso: node hooks/testa-gate-pergunta-memoria.cjs   (exit 1 se alguma falhar)
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

const HOOK = path.join(__dirname, 'gate-pergunta-memoria.cjs');
const FIX = path.join(__dirname, 'fixtures', 'pergunta-memoria');
const DESCRICAO = 'desligar gate é RAINFOREST_GATE_OFF/config; arquivo .rainforest-gate-off não, por causa de repo de cliente';

const tmpdirs = [];
let ok = 0;
let falhou = 0;

function novoTmp(prefixo) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), prefixo));
  tmpdirs.push(d);
  return d;
}

function lerFixture(nome) {
  return fs.readFileSync(path.join(FIX, nome), 'utf8');
}

// Troca um trecho do transcrito com asserção de contagem: se o trecho não estiver
// exatamente uma vez no fixture, o caso não é o que diz ser, e o teste cai.
function trocar(texto, de, para) {
  const n = texto.split(de).length - 1;
  if (n !== 1) throw new Error(`trecho a trocar apareceu ${n} vezes (esperava 1): ${de}`);
  return texto.replace(de, () => para);
}

const TRECHO_Q1 = '**Q1 — Desligar o gate**:';

// Monta o cenário: transcrito (texto), memoria (copia pasta memory/?), projeto com config opcional.
function cenario({ transcrito, comMemoria = true, configProjeto = null, sessao = 'sess-atual', fixtureMemoria = 'gate-off-so-por-variavel.md' }) {
  const base = novoTmp('rfm-pergunta-base-');
  const proj = path.join(base, 'proj');
  const outro = path.join(base, 'outro-repo');
  fs.mkdirSync(proj, { recursive: true });
  fs.mkdirSync(outro, { recursive: true });

  const transcriptPath = path.join(proj, `${sessao}.jsonl`);
  fs.writeFileSync(transcriptPath, transcrito);

  if (comMemoria) {
    const memDst = path.join(proj, 'memory');
    fs.mkdirSync(memDst, { recursive: true });
    fs.copyFileSync(path.join(FIX, 'memory', fixtureMemoria), path.join(memDst, fixtureMemoria));
  }

  if (configProjeto) {
    fs.mkdirSync(path.join(proj, '.rainforest'), { recursive: true });
    fs.writeFileSync(path.join(proj, '.rainforest', 'config.json'), JSON.stringify(configProjeto));
  }

  // RFM_ROOT com sessoes vivas: pid = o desta bateria, que está de pé enquanto ela roda.
  const rfm = novoTmp('rfm-pergunta-raiz-');
  const agora = Date.now();
  const estado = {
    'sess-mesmo-repo': { cwd: proj, prompt_ts: agora - 60000, stop_ts: agora - 30000, pid: process.pid },
    'sess-outro-repo': { cwd: outro, prompt_ts: agora - 120000, stop_ts: agora - 60000, pid: process.pid },
  };
  fs.writeFileSync(path.join(rfm, 'sessoes.json'), JSON.stringify(estado));

  return { proj, outro, transcriptPath, rfm };
}

function payload(c, extra = {}) {
  return {
    session_id: 'sess-atual',
    transcript_path: c.transcriptPath,
    cwd: c.proj,
    hook_event_name: 'Stop',
    ...extra,
  };
}

function rodar(c, extra = {}, transcriptOverride = null) {
  const p = payload(c, extra);
  if (transcriptOverride !== null) p.transcript_path = transcriptOverride;
  const env = { ...process.env, RFM_ROOT: c.rfm, ...(c.env || {}) };
  delete env.RAINFOREST_GATE_OFF;
  delete env.CLAUDE_PROJECT_DIR;
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(p),
    encoding: 'utf8',
    env,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function teste(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}: ${e.message}`);
  }
}

// O fixture abre a pergunta com emoji (`❓ **Q1`), que é a forma real das perguntas: o marcador aceita
// emoji e negrito antes do Q<n>.
const TRANSCRITO_RESPONDE = lerFixture("memoria-responde.jsonl");
const TRANSCRITO_NAO_RESPONDE = lerFixture("memoria-nao-responde.jsonl");

teste('P1 memoria-responde: exit 2, Q1, o arquivo, a description e a sessão do outro repo (não a do mesmo)', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q1'), 'stderr sem Q1');
  assert(r.stderr.includes('gate-off-so-por-variavel.md'), 'stderr sem o nome do arquivo de memória');
  assert(r.stderr.includes(DESCRICAO), 'stderr sem a description');
  assert(r.stderr.includes(c.outro), 'stderr sem a sessão do outro repositório');
  assert(!r.stderr.includes(c.proj), 'stderr traz a sessão do MESMO repositório');
});

teste('P2 marcador **Q2 -** (hífen): exit 2 e Q2 no stderr', () => {
  const texto = trocar(TRANSCRITO_RESPONDE, TRECHO_Q1, '**Q2 -** Desligar o gate:');
  const c = cenario({ transcrito: texto });
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q2'), 'stderr sem Q2');
});

teste('P3 memoria-nao-responde: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_NAO_RESPONDE });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P4 o texto do P1 sem nenhum Q<n>: exit 0', () => {
  const texto = trocar(TRANSCRITO_RESPONDE, TRECHO_Q1, '**Desligar o gate**:');
  assert(!/\bQ\d+\b/.test(texto), 'o fixture sem Q ainda tem Q<n>');
  const c = cenario({ transcrito: texto });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P5 P1 com stop_hook_active: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, { stop_hook_active: true });
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P6 P1 com agent_id: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, { agent_id: 'agent-123' });
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P7 P1 sem pasta memory/: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, comMemoria: false });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P8 P1 com .rainforest/config.json do cwd: gate-pergunta-memoria false: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, configProjeto: { 'gate-pergunta-memoria': false } });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P9 transcript_path inexistente: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, {}, path.join(c.proj, 'nao-existe.jsonl'));
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

// Mesma função do hook (design D6): caminho absoluto com todo caractere fora de [A-Za-z0-9] trocado por "-".
const slugDoProjeto = (p) => p.replace(/[^A-Za-z0-9]/g, "-");

function git(cwd, args) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, GIT_AUTHOR_NAME: 'teste', GIT_AUTHOR_EMAIL: 'teste@example.invalid', GIT_COMMITTER_NAME: 'teste', GIT_COMMITTER_EMAIL: 'teste@example.invalid' },
  });
  assert(r.status === 0, `git ${args.join(' ')} falhou: ${r.stderr}`);
}

teste('P10 sessão em worktree: a memória do repositório principal barra (exit 2), Q1 e o arquivo no stderr', () => {
  // realpath: o git devolve o caminho longo; o slug tem de sair do mesmo texto nos dois lados.
  const base = fs.realpathSync.native(novoTmp('rfm-pergunta-wt-'));
  const repo = path.join(base, 'repo');
  const wt = path.join(base, 'wt');
  const projects = fs.realpathSync.native(novoTmp('rfm-pergunta-projects-'));
  fs.mkdirSync(repo);
  git(repo, ['init', '-q']);
  git(repo, ['commit', '--allow-empty', '-q', '-m', 'base']);
  git(repo, ['worktree', 'add', '-q', '--detach', wt]);

  // O transcrito da sessão aberta no worktree vai para a pasta do worktree; a memória fica só no principal.
  const dirSessao = path.join(projects, slugDoProjeto(wt));
  fs.mkdirSync(dirSessao, { recursive: true });
  const transcriptPath = path.join(dirSessao, 's.jsonl');
  fs.writeFileSync(transcriptPath, TRANSCRITO_RESPONDE);
  const memDst = path.join(projects, slugDoProjeto(repo), 'memory');
  fs.mkdirSync(memDst, { recursive: true });
  fs.copyFileSync(path.join(FIX, 'memory', 'gate-off-so-por-variavel.md'), path.join(memDst, 'gate-off-so-por-variavel.md'));
  const rfm = novoTmp('rfm-pergunta-raiz-');
  fs.writeFileSync(path.join(rfm, 'sessoes.json'), '{}');

  const r = rodar({ proj: wt, transcriptPath, rfm });
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q1'), 'stderr sem Q1');
  assert(r.stderr.includes('gate-off-so-por-variavel.md'), 'stderr sem o nome do arquivo de memória do principal');
});

teste('P11 memória com description de outro assunto e termos só no corpo: exit 0', () => {
  // O corpo repete os termos da Q1; só a description conta para o casamento.
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, fixtureMemoria: 'corpo-sem-relacao.md' });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

const { canonicoDoCaminho } = require(path.join(__dirname, '..', 'scripts', 'lib', 'projeto-canonico.cjs'));

// `projeto`: de quem é a observação alvo ('atual' = o projeto do cwd, no nome canônico que o hook compara).
function cenarioComBanco(orcamentoMs, { projeto = 'atual', conteudo = null } = {}) {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, comMemoria: false });
  const dono = projeto === 'atual' ? canonicoDoCaminho(c.proj).canonico : projeto;
  c.dono = dono;
  c.env = { RFM_PERGUNTA_MEMORIA_ORCAMENTO_MS: String(orcamentoMs) };
  const db = new DatabaseSync(path.join(c.rfm, 'rainforest.db'));
  criarSchema(db);
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  // Enchimento de 400 observações sem os termos da Q1: sem ele o termo raro passa do teto de df e nada casa.
  db.exec('BEGIN');
  for (let i = 0; i < 400; i++) {
    ins.run('projeto-enchimento', 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-10-01T10:00:00.000Z', 'f' + i);
  }
  db.exec('COMMIT');
  ins.run(
    dono,
    conteudo !== null ? conteudo : 'Decisao sobre desligar arquivo rainforest publicacao neste repositorio cliente\n\n' + 'desligar arquivo rainforest publicacao neste repositorio cliente '.repeat(3),
    '2026-10-02T10:00:00.000Z',
    'alvo-p12',
  );
  db.close();
  return c;
}

// Prazo folgado: o P12 mede o casamento no banco, não a velocidade da máquina.
teste('P12 banco por assunto, sem memory/: observação do projeto atual que casa com Q1 barra (exit 2) e o stderr cita o banco', () => {
  const c = cenarioComBanco(20000);
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q1'), 'stderr sem Q1');
  assert(r.stderr.includes('o banco tem observação de ' + c.dono), 'stderr sem a citação do banco');
});

// O mesmo banco com prazo zero: a perna do banco é pulada e o hook sai 0 (falha aberta, D6).
teste('P13 o P12 com prazo do banco zero: banco pulado, exit 0', () => {
  const r = rodar(cenarioComBanco(0));
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

// Transcrito de um turno só, com o texto dado como último texto do assistant.
function transcritoComTexto(texto) {
  const user = { parentUuid: null, isSidechain: false, uuid: 'fx-t12-1', type: 'user', message: { role: 'user', content: 'segue' } };
  const asst = { parentUuid: 'fx-t12-1', isSidechain: false, uuid: 'fx-t12-2', type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: texto }] } };
  return JSON.stringify(user) + '\n' + JSON.stringify(asst) + '\n';
}

// Memória de fixture escrita na hora (name e description à escolha) em vez de arquivo novo no repo.
function cenarioMemoria({ texto, name, description }) {
  const c = cenario({ transcrito: transcritoComTexto(texto), comMemoria: false });
  const memDst = path.join(c.proj, 'memory');
  fs.mkdirSync(memDst, { recursive: true });
  fs.writeFileSync(path.join(memDst, 'm-p14-p15.md'), `---\nname: ${name}\ndescription: ${description}\n---\n\ncorpo\n`);
  return c;
}

const MEM_DESLIGAR = { name: 'gate-off-so-por-variavel', description: DESCRICAO };

teste('P14 recap em prosa com Q1 no MEIO da linha e um ? depois: exit 0 (a memória casa 3 termos, mas não é pergunta)', () => {
  const texto = 'Fechado: Q1 (b), e sobre desligar rainforest cliente como fica?';
  const c = cenarioMemoria({ texto, ...MEM_DESLIGAR });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P14b contraste: os mesmos 3 termos numa pergunta com Q1 no começo da linha: exit 2', () => {
  const texto = 'Q1 — Desligar rainforest cliente: como fica?';
  const c = cenarioMemoria({ texto, ...MEM_DESLIGAR });
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P15 pergunta que só compartilha vocabulário do projeto com a memória (regra, fluxo, continua, agente): exit 0', () => {
  const texto = 'Q1 — Convivência com o hook atual: a regra do fluxo continua para o agente?';
  const c = cenarioMemoria({ texto, name: 'regra-do-fluxo-continua', description: 'a regra do fluxo continua para o agente' });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

const OBS_COM_CABECALHO = '---\n# Titulo\nTexto util da observacao sobre desligar arquivo rainforest publicacao neste repositorio cliente\n\n' +
  'desligar arquivo rainforest publicacao neste repositorio cliente '.repeat(3);

teste('P16 banco: observação do projeto atual abrindo com --- e cabeçalho: exit 2, o trecho é a primeira linha útil', () => {
  const r = rodar(cenarioComBanco(20000, { conteudo: OBS_COM_CABECALHO }));
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Texto util da observacao'), 'stderr sem o trecho útil');
  assert(!r.stderr.includes('— ---'), 'stderr traz o --- como trecho');
});

teste('P16b a mesma observação gravada em OUTRO projeto: exit 0', () => {
  const r = rodar(cenarioComBanco(20000, { projeto: 'outro-projeto', conteudo: OBS_COM_CABECALHO }));
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

for (const d of tmpdirs) {
  try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* melhor esforço */ }
}

console.log(`\nok: ${ok}   falhou: ${falhou}   skipped: 0`);
process.exit(falhou > 0 ? 1 : 0);
