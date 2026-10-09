#!/usr/bin/env node
/**
 * Bateria de hooks/lib/glossario.cjs — leitura do GLOSSARIO.md, casamento de
 * termos e bloco injetado. Cada caso prova um item do "pronto quando" da tarefa 1
 * do plano 2026-10-08-glossario-compartilhado.
 *
 * Nenhum caso lê o texto do fonte da biblioteca: a prova é pelo comportamento.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const lib = require('./lib/glossario.cjs');

const {
  lerVerbetes,
  verbeteValido,
  acharGlossario,
  casarVerbetes,
  montarBlocoGlossario,
  chaveDe,
  CABECALHO,
} = lib;

let ok = 0;
let falhou = 0;

function caso(nome, fn) {
  let resultado;
  try {
    resultado = fn();
  } catch (e) {
    resultado = { passou: false, detalhe: `lancou: ${e.message}` };
  }
  if (resultado === true) {
    resultado = { passou: true };
  } else if (resultado === false) {
    resultado = { passou: false, detalhe: '' };
  }
  if (resultado.passou) {
    ok++;
    console.log(`  ok    ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${resultado.detalhe ? ' — ' + resultado.detalhe : ''}`);
  }
}

const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const termos = vs => vs.map(v => v.termo);

// ============================================================================
// FIXTURE: GLOSSARIO.md no formato D7, como o Luís commitaria
// ============================================================================

const GLOSSARIO = [
  '# Glossário',
  '',
  'Termos de domínio do repo. Cada verbete tem definição, onde mora e um cenário real.',
  '',
  '## fluxo',
  'Definição: a sequência de sete estágios que vai de uma ideia até o PR.',
  'Onde mora: skills/ e hooks/ do plugin, estado em `.rainforest/estagio`.',
  'Cenário: o Luís pede "brainstorm" e o fluxo começa no estágio brainstorm.',
  'Evite: esteira; pipeline',
  '',
  '## território',
  'Definição: área de arquivos que um agente pode tocar numa entrega.',
  'Onde mora: o campo "território" de cada tarefa do plano.',
  'Cenário: a tarefa 3 declara o território em que pode editar.',
  '',
  '## worktree de agente',
  'Definição: diretório temporário de git criado para um subagente',
  'trabalhar isolado do checkout principal.',
  'Onde mora: .claude/worktrees/ na raiz do repo.',
  'Cenário: o despacho cria um worktree por tarefa paralela.',
  'Evite: clone; cópia do repo',
  '',
].join('\n');

const verbetesFixture = lerVerbetes(GLOSSARIO);
const fluxo = verbetesFixture.find(v => v.termo === 'fluxo');
const territorio = verbetesFixture.find(v => v.termo === 'território');
const worktree = verbetesFixture.find(v => v.termo === 'worktree de agente');

// Verbete válido mínimo para usar em testes de casamento e de bloco
const V = (termo, extra = {}) => ({
  termo,
  definicao: `definição de ${termo}`,
  ondeMora: 'arquivo.cjs',
  cenario: `cenário de ${termo}`,
  evite: [],
  ...extra,
});

// ============================================================================
// LEITURA
// ============================================================================

caso('o GLOSSARIO no formato D7 devolve 3 verbetes com termo, campos e itens do Evite', () => {
  if (verbetesFixture.length !== 3) {
    return { passou: false, detalhe: `esperado 3 verbetes, veio ${verbetesFixture.length}` };
  }
  if (!igual(termos(verbetesFixture), ['fluxo', 'território', 'worktree de agente'])) {
    return { passou: false, detalhe: `termos: ${JSON.stringify(termos(verbetesFixture))}` };
  }
  if (!igual(fluxo.evite, ['esteira', 'pipeline'])) {
    return { passou: false, detalhe: `evite do fluxo: ${JSON.stringify(fluxo.evite)}` };
  }
  if (fluxo.ondeMora !== 'skills/ e hooks/ do plugin, estado em `.rainforest/estagio`.') {
    return { passou: false, detalhe: `ondeMora do fluxo: ${fluxo.ondeMora}` };
  }
  if (!igual(worktree.evite, ['clone', 'cópia do repo'])) {
    return { passou: false, detalhe: `evite do worktree: ${JSON.stringify(worktree.evite)}` };
  }
  return true;
});

caso('o mesmo GLOSSARIO em CRLF devolve os mesmos verbetes', () => {
  const crlf = GLOSSARIO.replace(/\n/g, '\r\n');
  return igual(lerVerbetes(crlf), verbetesFixture);
});

caso('rotulo sem acento (Definicao:) e em outra caixa (ONDE MORA:) valem', () => {
  const texto = '## x\nDefinicao: a\nONDE MORA: b\nCenario: c';
  const [v] = lerVerbetes(texto);
  if (!v || v.definicao !== 'a' || v.ondeMora !== 'b' || v.cenario !== 'c') {
    return { passou: false, detalhe: JSON.stringify(v) };
  }
  return verbeteValido(v);
});

caso('### dentro de um verbete nao abre outro verbete', () => {
  const texto = '## x\nDefinição: d\n### sub\nOnde mora: o\nCenário: c';
  const vs = lerVerbetes(texto);
  if (vs.length !== 1) {
    return { passou: false, detalhe: `verbetes: ${vs.length}` };
  }
  return vs[0].ondeMora === 'o' ? true : { passou: false, detalhe: vs[0].ondeMora };
});

caso('cabecalho ## e rotulos dentro de cerca de codigo nao contam', () => {
  const texto = [
    '## real',
    'Definição: d',
    'Onde mora: o',
    'Cenário: c',
    '```',
    '## falso',
    'Definição: x',
    '```',
    '~~~',
    '## falso2',
    'Cenário: y',
    '~~~',
  ].join('\n');
  const vs = lerVerbetes(texto);
  if (vs.length !== 1 || vs[0].termo !== 'real') {
    return { passou: false, detalhe: `verbetes: ${JSON.stringify(termos(vs))}` };
  }
  return vs[0].definicao === 'd' ? true : { passou: false, detalhe: vs[0].definicao };
});

caso('texto antes do primeiro ## e ignorado', () => {
  const texto = 'Definição: solta\nOnde mora: x\n## a\nDefinição: d\nOnde mora: o\nCenário: c';
  const vs = lerVerbetes(texto);
  if (vs.length !== 1 || vs[0].termo !== 'a' || vs[0].definicao !== 'd') {
    return { passou: false, detalhe: JSON.stringify(vs) };
  }
  return true;
});

caso('campo de varias linhas junta as linhas', () => {
  return worktree.definicao === 'diretório temporário de git criado para um subagente trabalhar isolado do checkout principal.'
    ? true
    : { passou: false, detalhe: worktree.definicao };
});

caso('Evite vazio equivale a Evite ausente', () => {
  const [com] = lerVerbetes('## t\nDefinição: d\nOnde mora: o\nCenário: c\nEvite:');
  const [sem] = lerVerbetes('## t\nDefinição: d\nOnde mora: o\nCenário: c');
  return com.evite.length === 0 && sem.evite.length === 0 && verbeteValido(com) && verbeteValido(sem);
});

// ============================================================================
// VALIDADE
// ============================================================================

caso('verbeteValido falso sem Cenário', () => {
  const [v] = lerVerbetes('## t\nDefinição: d\nOnde mora: o');
  return verbeteValido(v) === false ? true : { passou: false, detalhe: 'aceitou sem cenário' };
});

caso('verbeteValido falso com Definição vazia', () => {
  const [v] = lerVerbetes('## t\nDefinição:\nOnde mora: o\nCenário: c');
  return verbeteValido(v) === false ? true : { passou: false, detalhe: 'aceitou definição vazia' };
});

for (const ph of ['TBD', 'a definir', 'n/a', '-', '...']) {
  caso(`verbeteValido falso com placeholder "${ph}" em Onde mora`, () => {
    const [v] = lerVerbetes(`## t\nDefinição: d\nOnde mora: ${ph}\nCenário: c`);
    return verbeteValido(v) === false ? true : { passou: false, detalhe: `aceitou ${ph}` };
  });
}

caso('verbeteValido verdadeiro sem Evite', () => {
  return verbeteValido(territorio) === true && territorio.evite.length === 0;
});

// ============================================================================
// CHAVE DE DEDUPLICAÇÃO
// ============================================================================

caso('chaveDe: Território, territorio e Territórios são iguais', () => {
  const a = chaveDe('Território');
  return a === chaveDe('territorio') && a === chaveDe('Territórios')
    ? true
    : { passou: false, detalhe: `${a} | ${chaveDe('territorio')} | ${chaveDe('Territórios')}` };
});

// ============================================================================
// CASAMENTO
// ============================================================================

const BIBLIOTECA = [fluxo, territorio, worktree];

caso('casa fluxos (plural com s) e devolve o verbete fluxo', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'preciso revisar os fluxos do plugin')), ['fluxo']);
});

caso('casa FLUXO em caixa alta', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'O FLUXO travou')), ['fluxo']);
});

caso('casa território escrito TERRITORIO (sem acento, em caixa alta)', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'o TERRITORIO da tarefa')), ['território']);
});

caso('casa worktree   de\\nagente com espaços e quebra de linha', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'criar worktree   de\nagente para isso')), ['worktree de agente']);
});

caso('casa o Evite esteira e devolve o verbete fluxo', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'essa esteira está lenta')), ['fluxo']);
});

caso('devolve os verbetes na ordem da primeira aparição no pedido', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'o território antes do fluxo')), ['território', 'fluxo']);
});

caso('ignora verbete invalido mesmo que o termo apareça no pedido', () => {
  const invalido = V('fluxo', { cenario: 'TBD' });
  return igual(casarVerbetes([invalido, territorio], 'fluxo e território'), [territorio]);
});

caso('termo no fim de palavra maior nao casa (contrafluxo)', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'isso é um contrafluxo raro')), []);
});

caso('nao casa fluxograma', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'veja o fluxograma abaixo')), []);
});

caso('nao casa superfluxos', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'vários superfluxos ativos')), []);
});

caso('nao casa termo que aparece so dentro de palavra maior (worktree de agentes em palavra)', () => {
  return igual(termos(casarVerbetes(BIBLIOTECA, 'o subworktree de agentes')), []);
});

// ============================================================================
// ARQUIVO (acharGlossario)
// ============================================================================

const RAIZ_TESTE = fs.mkdtempSync(path.join(os.tmpdir(), 'glossario-teste-'));

caso('acharGlossario sem .git acima devolve null mesmo com GLOSSARIO.md na pasta', () => {
  const semGit = path.join(RAIZ_TESTE, 'semgit');
  const sub = path.join(semGit, 'sub');
  fs.mkdirSync(sub, { recursive: true });
  fs.writeFileSync(path.join(semGit, 'GLOSSARIO.md'), GLOSSARIO, 'utf8');
  const r = acharGlossario(sub);
  return r === null ? true : { passou: false, detalhe: `devolveu ${r}` };
});

caso('acharGlossario em subdiretorio de repo com .git pasta devolve a raiz', () => {
  const repo = path.join(RAIZ_TESTE, 'repo-pasta');
  const fundo = path.join(repo, 'a', 'b');
  fs.mkdirSync(path.join(repo, '.git'), { recursive: true });
  fs.mkdirSync(fundo, { recursive: true });
  fs.writeFileSync(path.join(repo, 'GLOSSARIO.md'), GLOSSARIO, 'utf8');
  const r = acharGlossario(fundo);
  return r === path.join(repo, 'GLOSSARIO.md') ? true : { passou: false, detalhe: `devolveu ${r}` };
});

caso('acharGlossario em worktree com .git arquivo devolve a raiz do worktree', () => {
  const wt = path.join(RAIZ_TESTE, 'worktree-arquivo');
  const fundo = path.join(wt, 'x');
  fs.mkdirSync(fundo, { recursive: true });
  fs.writeFileSync(path.join(wt, '.git'), 'gitdir: /algum/lugar\n', 'utf8');
  fs.writeFileSync(path.join(wt, 'GLOSSARIO.md'), GLOSSARIO, 'utf8');
  const r = acharGlossario(fundo);
  return r === path.join(wt, 'GLOSSARIO.md') ? true : { passou: false, detalhe: `devolveu ${r}` };
});

caso('acharGlossario em repo com .git mas sem GLOSSARIO.md devolve null', () => {
  const repo = path.join(RAIZ_TESTE, 'repo-sem-glossario');
  fs.mkdirSync(path.join(repo, '.git'), { recursive: true });
  const r = acharGlossario(repo);
  return r === null ? true : { passou: false, detalhe: `devolveu ${r}` };
});

// Arquivo de tamanho exato gerado em tempo de execução (nada grande é commitado).
function glossarioDeTamanho(nome, bytes) {
  const repo = path.join(RAIZ_TESTE, nome);
  fs.mkdirSync(path.join(repo, '.git'), { recursive: true });
  const base = GLOSSARIO + '\n';
  const corpo = base + 'a'.repeat(bytes - Buffer.byteLength(base, 'utf8'));
  fs.writeFileSync(path.join(repo, 'GLOSSARIO.md'), corpo, 'utf8');
  return { repo, arq: path.join(repo, 'GLOSSARIO.md') };
}

caso('GLOSSARIO.md de 262144 B e lido pelo hook (no teto exato)', () => {
  const { repo, arq } = glossarioDeTamanho('glossario-no-teto', lib.GLOSSARIO_MAX_BYTES);
  const r = acharGlossario(repo);
  if (fs.statSync(arq).size !== 262144) {
    return { passou: false, detalhe: `tamanho gerado: ${fs.statSync(arq).size}` };
  }
  return r === arq ? true : { passou: false, detalhe: `devolveu ${r}` };
});

caso('GLOSSARIO.md acima do teto nao e lido pelo hook (262145 B)', () => {
  const { repo, arq } = glossarioDeTamanho('glossario-acima-teto', lib.GLOSSARIO_MAX_BYTES + 1);
  if (fs.statSync(arq).size !== 262145) {
    return { passou: false, detalhe: `tamanho gerado: ${fs.statSync(arq).size}` };
  }
  const r = acharGlossario(repo);
  return r === null ? true : { passou: false, detalhe: `devolveu ${r}` };
});

// ============================================================================
// BLOCO INJETADO (montarBlocoGlossario)
// ============================================================================

caso('montarBlocoGlossario comeca por ## Glossário do repo', () => {
  const bloco = montarBlocoGlossario(BIBLIOTECA);
  return CABECALHO === '## Glossário do repo' && bloco.startsWith('## Glossário do repo\n')
    ? true
    : { passou: false, detalhe: bloco.slice(0, 60) };
});

caso('montarBlocoGlossario devolve no maximo 3 linhas de verbete', () => {
  const quatro = [V('a1'), V('a2'), V('a3'), V('a4')];
  const linhas = montarBlocoGlossario(quatro).split('\n').filter(l => l.startsWith('- '));
  return linhas.length === 3 ? true : { passou: false, detalhe: `linhas: ${linhas.length}` };
});

caso('montarBlocoGlossario respeita o teto de 1800 B', () => {
  const grandes = [V('g1', { definicao: 'a'.repeat(700) }), V('g2', { definicao: 'b'.repeat(700) }), V('g3', { definicao: 'c'.repeat(700) })];
  const bloco = montarBlocoGlossario(grandes);
  const bytes = Buffer.byteLength(bloco, 'utf8');
  const linhas = bloco.split('\n').filter(l => l.startsWith('- ')).length;
  return bytes <= 1800 && linhas === 2
    ? true
    : { passou: false, detalhe: `bytes=${bytes} linhas=${linhas}` };
});

caso('montarBlocoGlossario devolve string vazia para lista vazia', () => {
  return montarBlocoGlossario([]) === '' ? true : { passou: false, detalhe: 'nao vazio' };
});

caso('montarBlocoGlossario devolve string vazia para verbete unico acima de 900 B', () => {
  return montarBlocoGlossario([V('enorme', { definicao: 'x'.repeat(950) })]) === ''
    ? true
    : { passou: false, detalhe: 'injetou verbete acima de 900 B' };
});

// ============================================================================
// LIMPEZA E RESULTADO
// ============================================================================

try {
  fs.rmSync(RAIZ_TESTE, { recursive: true, force: true });
} catch (e) {
  // sandbox de teste; falha de limpeza não muda o veredito
}

console.log('-----------------------------------------');
console.log(`ok: ${ok}   falhou: ${falhou}`);
console.log(`${falhou} falha(s)`);
process.exit(falhou === 0 ? 0 : 1);
