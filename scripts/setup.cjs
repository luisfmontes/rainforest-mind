#!/usr/bin/env node
/**
 * Setup do rainforest — monta a pasta de dados e liga/desliga o que é opcional.
 *
 * Por que existe: até 2026-08-11 quem instalava o plugin e não configurava nada
 * recebia **o foco e as ideias de quem o publicou**, porque a cadeia de raiz caía
 * no diretório do plugin. Os dados saíram do repo no mesmo dia e o buraco virou o
 * inverso: sem pasta montada, a cadeia não resolve nada e o `/saude` alerta. Este
 * script é o que fecha os dois lados.
 *
 * E ele é IDEMPOTENTE de propósito. Rodar de novo não recomeça: mostra o estado,
 * e é por ele que se liga ou desliga peça. Setup que só serve na primeira vez é
 * setup que ninguém roda de novo — e aí o estado real e o configurado divergem
 * sem ninguém perceber.
 *
 * ESCOPO. Toda troca vale num de dois lugares, e a precedência é a mesma que o
 * harness já usa para settings e que a cadeia de raiz já usa para dados:
 *
 *   --escopo projeto   <projeto>/.rainforest/config.json   vence, vale só naquele repo
 *   --escopo usuario   <dados>/config.json                 o seu padrão, em qualquer pasta
 *
 * Uso:
 *   node scripts/setup.cjs                              # estado, não escreve nada
 *   node scripts/setup.cjs --criar                      # monta a pasta de dados
 *   node scripts/setup.cjs --ligar esteira
 *   node scripts/setup.cjs --desligar gate-staging --escopo projeto
 */

const fs = require('fs');
const path = require('path');

const CODIGO_ROOT = path.resolve(__dirname, '..');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');
const { CHAVES, resolverConfig } = require('../hooks/lib/config.cjs');

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i >= 0 ? (process.argv[i + 1] || true) : null;
}
const tem = (nome) => process.argv.includes(`--${nome}`);

const PROJETO = process.env.CLAUDE_PROJECT_DIR || process.cwd();

// ---------------------------------------------------------------- pasta de dados

/** Onde a pasta de dados NASCE quando ainda não existe: `~/.rainforest`. */
function destinoPadrao() {
  return path.join(process.env.USERPROFILE || process.env.HOME || '', '.rainforest');
}

const FOCO_MODELO = `# Foco

## Ativo

Todo foco declara a natureza — \`[trabalho]\` ou \`[pessoal]\`.

**(nenhum foco declarado)** — use \`/foco <texto>\` para declarar o primeiro.
O foco é a clareira onde você trabalha hoje, e é contra ele, e só contra ele,
que o desvio é medido.

## Compromissos com prazo

- (nenhum)

## Frentes

- (nenhuma)

## Concluídos

- (nenhum)
`;

/** `Meu Repo` → `meu-repo`. O slug é fechado justamente para não caber barra. */
function slugificar(nome) {
  return String(nome || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function criar() {
  const destino = process.env.RFM_ROOT || destinoPadrao();
  const foco = path.join(destino, 'FOCO.md');
  const ideias = path.join(destino, 'ideias.jsonl');
  const projetos = path.join(destino, 'projetos.json');

  fs.mkdirSync(destino, { recursive: true });
  const feito = [];
  // Nunca sobrescreve: a pasta é a memória do usuário, e setup que roda de novo
  // não pode apagar o que já existe. É a mesma razão de o `iniciar` da esteira
  // recusar slug repetido.
  if (!fs.existsSync(foco)) {
    fs.writeFileSync(foco, FOCO_MODELO, 'utf8');
    feito.push('FOCO.md (modelo vazio)');
  }
  if (!fs.existsSync(ideias)) {
    fs.writeFileSync(ideias, '', 'utf8');
    feito.push('ideias.jsonl (vazio)');
  }
  // O `projeto` de cada ideia é slug de vocabulário fechado, e o vocabulário mora
  // aqui — é o que tira o caminho de dentro do dado (barra invertida dentro de
  // string JSON já corrompeu 4 registros). Nasce com DUAS entradas e não vazio:
  // vocabulário vazio recusaria todo `plantar`, e a `solta` é a que recebe ideia
  // que não é de repo nenhum.
  if (!fs.existsSync(projetos)) {
    const slug = slugificar(path.basename(PROJETO)) || 'este-projeto';
    const mapa = {
      solta: { caminho: null, apelidos: [] },
      [slug]: { caminho: PROJETO, apelidos: [] },
    };
    fs.writeFileSync(projetos, JSON.stringify(mapa, null, 2) + '\n', 'utf8');
    feito.push(`projetos.json (solta + ${slug})`);
  }

  console.log(`pasta de dados: ${destino}`);
  console.log(feito.length ? `  criado: ${feito.join(', ')}` : '  ja estava montada, nada foi sobrescrito');
  if (!process.env.RFM_ROOT && destino !== destinoPadrao()) {
    console.log('  aviso: RFM_ROOT aponta para outro lugar e venceu o padrao');
  }
  return destino;
}

// ---------------------------------------------------------------- toggles

function trocar(chave, valor, escopo) {
  if (!(chave in CHAVES)) {
    console.error(`erro: '${chave}' nao e uma chave conhecida. Sao: ${Object.keys(CHAVES).join(', ')}`);
    process.exit(1);
  }
  if (escopo !== 'projeto' && escopo !== 'usuario') {
    console.error(`erro: --escopo tem que ser 'projeto' ou 'usuario' (veio '${escopo}')`);
    process.exit(1);
  }

  let base;
  if (escopo === 'projeto') {
    base = path.join(PROJETO, '.rainforest');
  } else {
    const raiz = resolverRaiz({ plugin: CODIGO_ROOT }).raiz;
    if (!raiz) {
      console.error('erro: nao ha pasta de dados montada — rode primeiro: node scripts/setup.cjs --criar');
      process.exit(1);
    }
    base = raiz;
  }

  const arquivo = path.join(base, 'config.json');
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(arquivo, 'utf8')); } catch { /* arquivo novo */ }
  cfg[chave] = valor;

  fs.mkdirSync(base, { recursive: true });
  const tmp = `${arquivo}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, arquivo); // atomico: config truncada e pior que ausente

  console.log(`${chave}: ${valor ? 'ligado' : 'desligado'} no escopo ${escopo}`);
  console.log(`  ${arquivo}`);
  if (escopo === 'projeto') {
    console.log('  vale so neste repositorio, e vence o seu padrao de usuario');
    console.log('  (arquivo dentro do projeto: decida se ele entra no git ou no .gitignore)');
  }
}

// ---------------------------------------------------------------- estado

function estado() {
  const { raiz, nivel } = resolverRaiz({ plugin: CODIGO_ROOT });
  console.log('PASTA DE DADOS');
  if (!raiz) {
    console.log('  nenhuma — o foco e as ideias nao tem onde morar');
    console.log('  monte com: node scripts/setup.cjs --criar');
  } else {
    console.log(`  ${raiz}  (nivel: ${nivel})`);
    if (nivel === 'plugin') {
      console.log('  ATENCAO: esta e a pasta do PLUGIN. O foco e as ideias que voce ve');
      console.log('  sao de quem o publicou. Rode: node scripts/setup.cjs --criar');
    }
  }

  const { valores, origem, arquivos } = resolverConfig({ projeto: PROJETO });
  console.log('');
  console.log('O QUE ESTA LIGADO');
  for (const [chave, def] of Object.entries(CHAVES)) {
    const marca = valores[chave] ? 'ligado   ' : 'DESLIGADO';
    console.log(`  ${marca} ${chave.padEnd(14)} ${def.descricao}`);
    if (origem[chave] !== 'padrao') console.log(`            ^ definido em: ${origem[chave]}`);
  }
  console.log('');
  console.log('DE ONDE VEM');
  console.log(`  projeto: ${arquivos.projeto || '(nenhum)'}`);
  console.log(`  usuario: ${arquivos.usuario || '(nenhum)'}`);
  console.log('');
  console.log('Para trocar:');
  console.log('  node scripts/setup.cjs --desligar <chave> [--escopo projeto|usuario]');
  console.log('  node scripts/setup.cjs --ligar    <chave> [--escopo projeto|usuario]');
  console.log('');
  console.log('O que criar de automacao NESTE projeto e outra pergunta, e tem dono');
  console.log('oficial: a skill `claude-automation-recommender` (plugin claude-code-setup).');
}

// ---------------------------------------------------------------- CLI

function main() {
  if (tem('criar')) {
    criar();
    console.log('');
  }
  const ligar = arg('ligar');
  const desligar = arg('desligar');
  if (ligar || desligar) {
    const escopo = arg('escopo') || 'usuario';
    trocar(String(ligar || desligar), !!ligar, String(escopo));
    return;
  }
  estado();
}

if (require.main === module) main();
module.exports = { criar, trocar, FOCO_MODELO };
