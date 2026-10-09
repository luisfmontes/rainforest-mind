#!/usr/bin/env node
'use strict';
// Bateria hermetica do glossario no hook do pedido (hooks/memoria-assunto-prompt.cjs, UserPromptSubmit).
// Cada caso monta repos temporarios com .git e GLOSSARIO.md, uma RFM_ROOT propria e roda o hook
// como processo filho recebendo no stdin o payload que o harness envia (formato de
// docs/rainforest/referencia/2026-10-08-harness-prompt-e-agent.md). Banco so nos casos que o pedem,
// criado pelo criarSchema REAL.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

const HOOK = path.join(__dirname, 'memoria-assunto-prompt.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-glossario-prompt-'));
const raizSemBanco = path.join(tmp, 'raiz-sem-banco');
const raizComBanco = path.join(tmp, 'raiz-com-banco');
fs.mkdirSync(raizSemBanco);
fs.mkdirSync(raizComBanco);

const VERBETE_FLUXO = [
  '## fluxo',
  'Definição: sequência de estágios que um trabalho percorre do design ao fechamento.',
  'Onde mora: docs/rainforest/referencia e a skill rainforest-mind.',
  'Cenário: o estágio executar acontece depois do plano no fluxo.',
  'Evite: esteira; pipeline',
  '',
].join('\n');
const VERBETE_TERRITORIO = [
  '## TERRITORIO',
  'Definição: repositório de fontes AdvPL que o grafo de chamadas indexa.',
  'Onde mora: scripts/territorio.cjs.',
  'Cenário: a consulta de chamadores lê o grafo do TERRITORIO.',
  '',
].join('\n');
const VERBETE_INVALIDO = [
  '## lixo',
  'Definição: TBD',
  'Onde mora: nenhum.',
  'Cenário: nenhum.',
  '',
].join('\n');

// Repo de teste: pasta com .git e GLOSSARIO.md (texto dado ou nenhum), e um cwd dentro dele.
function repo(nome, glossario) {
  const raizRepo = path.join(tmp, nome);
  fs.mkdirSync(path.join(raizRepo, '.git'), { recursive: true });
  if (glossario !== null) fs.writeFileSync(path.join(raizRepo, 'GLOSSARIO.md'), '# Glossário\n\n' + glossario);
  const cwd = path.join(raizRepo, 'src');
  fs.mkdirSync(cwd, { recursive: true });
  return cwd;
}

// Corpus para os casos com banco: enchimento + alvos de termo raro (mesmo desenho da bateria de memoria).
const caminhoDb = path.join(raizComBanco, 'rainforest.db');
const db = new DatabaseSync(caminhoDb);
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 400; i++) {
  ins.run('projeto-teste', 'Registro generico ' + i + '\n\nrotina comum de trabalho numero ' + i + ' sem relevancia', '2026-10-01T10:00:00.000Z', 'f' + i);
}
for (const nome of ['Alfa', 'Bravo']) {
  ins.run('projeto-teste', 'Reconciliacao ' + nome + ' zarquon flibbertigibbet\n\n' +
    ('zarquon flibbertigibbet zarquon flibbertigibbet quasar ' + nome + ' ').repeat(3),
    '2026-10-0' + (nome === 'Alfa' ? 2 : 3) + 'T10:00:00.000Z', 'alvo-' + nome);
}
db.close();

const transcritoVazio = path.join(tmp, 'sem-abertura.jsonl');
fs.writeFileSync(transcritoVazio, JSON.stringify({ type: 'user', message: { role: 'user', content: 'oi' } }) + '\n');

// ---- infraestrutura ----
function rodar(stdin, { raizAmbiente = raizSemBanco } = {}) {
  const env = { ...process.env, RFM_ROOT: raizAmbiente };
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, env, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr };
}
// Sem raiz: RFM_ROOT ausente e HOME/USERPROFILE numa pasta vazia (resolverRaiz devolve raiz null).
const HOME_VAZIO = path.join(tmp, 'home-vazio');
fs.mkdirSync(HOME_VAZIO);
function rodarSemRaiz(stdin) {
  const env = { ...process.env, HOME: HOME_VAZIO, USERPROFILE: HOME_VAZIO };
  delete env.RFM_ROOT;
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, env, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr };
}
function payload(cwd, o) {
  return JSON.stringify(Object.assign({
    session_id: 'sessao-padrao', transcript_path: transcritoVazio, cwd,
    hook_event_name: 'UserPromptSubmit', prompt: 'o que significa esteira aqui?',
  }, o));
}
function contexto(saida) {
  const j = JSON.parse(saida);
  if (j.hookSpecificOutput.hookEventName !== 'UserPromptSubmit') throw new Error('evento errado');
  return j.hookSpecificOutput.additionalContext;
}
const vazioSaiu0 = (r) => r.codigo === 0 && r.saida === '';
function bateTudo(r) { return r.codigo === 0; }

const CWD_FLUXO = repo('repo-fluxo', VERBETE_FLUXO + '\n' + VERBETE_TERRITORIO);

let ok = 0, falha = 0;
function caso(nome, fn) {
  let passou = false;
  try { passou = fn() === true; } catch (e) { passou = false; }
  if (passou) { ok++; console.log('ok ' + nome); } else { falha++; console.log('FALHA ' + nome); }
}

// ---- casos ----
caso('sem banco injeta **fluxo** para "esteira" e nenhum outro verbete', () => {
  const r = rodar(payload(CWD_FLUXO, { session_id: 's-sem-banco' }));
  const ctx = contexto(r.saida);
  return bateTudo(r) && ctx.startsWith('## Glossário do repo') && ctx.includes('**fluxo**') &&
    !ctx.includes('**TERRITORIO**') && ctx.split('\n').length === 2;
});
caso('prompt com termo do glossario injeta so o verbete casado', () => {
  const r = rodar(payload(CWD_FLUXO, { session_id: 's-casado', prompt: 'quero entender o termo fluxo do repo' }));
  const ctx = contexto(r.saida);
  return bateTudo(r) && ctx.includes('**fluxo**') && !ctx.includes('**TERRITORIO**');
});
caso('segunda chamada na mesma sessao sai vazio', () => {
  const r1 = rodar(payload(CWD_FLUXO, { session_id: 's-dedup' }));
  const r2 = rodar(payload(CWD_FLUXO, { session_id: 's-dedup' }));
  return contexto(r1.saida).includes('**fluxo**') && vazioSaiu0(r2);
});
caso('sessao diferente recebe de novo', () => {
  const r1 = rodar(payload(CWD_FLUXO, { session_id: 's-dedup-a' }));
  const r2 = rodar(payload(CWD_FLUXO, { session_id: 's-dedup-b' }));
  return contexto(r1.saida).includes('**fluxo**') && contexto(r2.saida).includes('**fluxo**');
});
caso('arquivo de dedup so tem chaves, nenhuma palavra do pedido', () => {
  const arq = path.join(raizSemBanco, 'memoria-assunto', 's-dedup.glossario.json');
  const dado = JSON.parse(fs.readFileSync(arq, 'utf8'));
  return Array.isArray(dado) && dado.length === 1 && dado[0] === 'fluxo' && !/esteira|significa|aqui/.test(fs.readFileSync(arq, 'utf8'));
});
caso('4 casados injeta 3, na ordem da aparicao, <= 1800 B', () => {
  const verbetes = ['alfa', 'bravo', 'charlie', 'delta'].map((t) => [
    '## ' + t,
    'Definição: termo de teste ' + t + ' com uma definição curta o bastante para caber na linha.',
    'Onde mora: scripts/' + t + '.cjs.',
    'Cenário: um caso concreto do termo ' + t + ' no repo de teste.',
    '',
  ].join('\n')).join('\n');
  const cwd = repo('repo-quatro', verbetes);
  const pedido = 'delta antes de tudo, depois charlie, bravo e alfa no mesmo pedido';
  const r = rodar(payload(cwd, { session_id: 's-quatro', prompt: pedido }));
  const ctx = contexto(r.saida);
  const linhas = ctx.split('\n').slice(1);
  return bateTudo(r) && linhas.length === 3 && Buffer.byteLength(ctx, 'utf8') <= 1800 &&
    linhas[0].startsWith('- **delta**') && linhas[1].startsWith('- **charlie**') && linhas[2].startsWith('- **bravo**');
});
caso('pedido curto injeta o glossario e nao a memoria', () => {
  const r = rodar(payload(CWD_FLUXO, { session_id: 's-curto', prompt: 'esteira?', transcript_path: transcritoVazio }), { raizAmbiente: raizComBanco });
  const ctx = contexto(r.saida);
  return bateTudo(r) && ctx.includes('**fluxo**') && !ctx.includes('## Memória do assunto');
});
caso('fluxograma nao injeta', () => vazioSaiu0(rodar(payload(CWD_FLUXO, { session_id: 's-fluxograma', prompt: 'o fluxograma do deploy ficou certo?' }))));
caso('Esteiras injeta fluxo e TERRITORIO injeta o proprio verbete', () => {
  const a = rodar(payload(CWD_FLUXO, { session_id: 's-plural', prompt: 'as Esteiras do projeto' }));
  const b = rodar(payload(CWD_FLUXO, { session_id: 's-territorio', prompt: 'o que o TERRITORIO indexa?' }));
  return contexto(a.saida).includes('**fluxo**') && contexto(b.saida).includes('**TERRITORIO**');
});
caso('pedido que comeca por barra nao injeta', () =>
  vazioSaiu0(rodar(payload(CWD_FLUXO, { session_id: 's-barra', prompt: '/brainstorm quero uma esteira nova' }))));
caso('sem GLOSSARIO.md nao injeta', () => {
  const cwd = repo('repo-sem-glossario', null);
  return vazioSaiu0(rodar(payload(cwd, { session_id: 's-sem-glossario' })));
});
caso('diretorio sem .git nao injeta, mesmo com GLOSSARIO.md', () => {
  const solto = path.join(tmp, 'solto');
  fs.mkdirSync(solto, { recursive: true });
  fs.writeFileSync(path.join(solto, 'GLOSSARIO.md'), VERBETE_FLUXO);
  return vazioSaiu0(rodar(payload(solto, { session_id: 's-sem-git' })));
});
caso('verbete invalido e ignorado e os validos injetam', () => {
  const cwd = repo('repo-invalido', VERBETE_FLUXO + '\n' + VERBETE_INVALIDO);
  const r = rodar(payload(cwd, { session_id: 's-invalido', prompt: 'esteira e lixo ao mesmo tempo' }));
  const ctx = contexto(r.saida);
  return bateTudo(r) && ctx.includes('**fluxo**') && !ctx.includes('**lixo**');
});
caso('stdin invalido sai 0 e calado', () => vazioSaiu0(rodar('isto nao e json {')) && vazioSaiu0(rodar('')));
caso('session_id invalido sai 0 calado e nao escreve fora da raiz', () => {
  const r = rodar(payload(CWD_FLUXO, { session_id: '../fuga' }));
  return vazioSaiu0(r) && !fs.existsSync(path.join(raizSemBanco, 'fuga.glossario.json')) &&
    !fs.existsSync(path.join(tmp, 'fuga.glossario.json'));
});
caso('com banco: glossario vem antes, linha em branco, depois a memoria', () => {
  const pedido = 'o que significa esteira aqui na reconciliacao zarquon flibbertigibbet quasar?';
  const r = rodar(payload(CWD_FLUXO, { session_id: 's-com-banco', prompt: pedido, transcript_path: transcritoVazio }), { raizAmbiente: raizComBanco });
  const ctx = contexto(r.saida);
  const iG = ctx.indexOf('## Glossário do repo');
  const iM = ctx.indexOf('\n\n## Memória do assunto');
  return bateTudo(r) && iG === 0 && iM > 0 && iM > ctx.indexOf('**fluxo**') && ctx.includes('Reconciliacao');
});
caso('com banco travado: sobra so o glossario', () => {
  const trava = new DatabaseSync(caminhoDb);
  try {
    trava.exec('BEGIN EXCLUSIVE');
    let travou = false;
    const leitor = new DatabaseSync(caminhoDb, { readOnly: true });
    try { leitor.prepare('SELECT COUNT(*) FROM observacoes').get(); } catch (e) { travou = /locked|busy/i.test(e.message); }
    try { leitor.close(); } catch (e) { /* ja fechado */ }
    if (!travou) return false; // sem trava efetiva o caso nao prova nada
    const pedido = 'o que significa esteira aqui na reconciliacao zarquon flibbertigibbet quasar?';
    const r = rodar(payload(CWD_FLUXO, { session_id: 's-travado', prompt: pedido }), { raizAmbiente: raizComBanco });
    const ctx = contexto(r.saida);
    return bateTudo(r) && ctx.startsWith('## Glossário do repo') && ctx.includes('**fluxo**') && !ctx.includes('## Memória do assunto');
  } finally {
    try { trava.exec('ROLLBACK'); } catch (e) { /* melhor esforco */ }
    trava.close();
  }
});

caso('sem raiz de dados injeta o glossario sem dedup', () => {
  const cwd = CWD_FLUXO;
  const r1 = rodarSemRaiz(payload(cwd, { session_id: 's-sem-raiz' }));
  const r2 = rodarSemRaiz(payload(cwd, { session_id: 's-sem-raiz' }));
  const c1 = contexto(r1.saida);
  const c2 = contexto(r2.saida);
  const semArquivo = fs.readdirSync(HOME_VAZIO).length === 0 &&
    !fs.existsSync(path.join(cwd, '.rainforest')) &&
    !fs.existsSync(path.join(cwd, 'memoria-assunto')) &&
    !fs.existsSync(path.join(path.dirname(cwd), 'memoria-assunto'));
  return bateTudo(r1) && bateTudo(r2) &&
    c1.startsWith('## Glossário do repo') && c1.includes('**fluxo**') && !c1.includes('## Memória do assunto') &&
    c2.startsWith('## Glossário do repo') && c2.includes('**fluxo**') && !c2.includes('## Memória do assunto') &&
    semArquivo;
});

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforco */ }
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha > 0 ? 1 : 0);
