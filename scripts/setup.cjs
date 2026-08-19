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
const { execSync } = require('child_process');

const CODIGO_ROOT = path.resolve(__dirname, '..');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');
const { CHAVES, resolverConfig } = require('../hooks/lib/config.cjs');
const P = require('../hooks/lib/projetos.cjs');

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

Pastas:

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

/**
 * Os arquivos que este plugin possui na pasta de dados — UMA lista, lida por quem
 * SEMEIA (`criar`) e por quem MOSTRA (`estado`).
 *
 * Ela existe por causa de um defeito que aconteceu duas vezes no mesmo dia
 * (2026-08-12): nasceu o `projetos.json`, o `criar` aprendeu a semeá-lo, e o
 * `estado` nunca soube que ele existia — o usuário não tinha onde ver a
 * configuração nova. Horas depois, o mesmo com a ponte. A correção não é lembrar:
 * é arquivo novo entrar **aqui**, e as duas portas ganharem juntas. A bateria
 * `testa-setup.sh` cobra isso mecanicamente, com mutação.
 *
 * `semear: null` = não nasce no `--criar`; aparece quando alguém liga/desliga algo.
 */
const ARQUIVOS = [
  {
    nome: 'FOCO.md',
    descricao: 'o foco declarado, injetado em toda sessao',
    semear: () => FOCO_MODELO,
    aoCriar: () => 'FOCO.md (modelo vazio)',
  },
  {
    nome: 'ideias.jsonl',
    descricao: 'uma ideia (ou observacao) por linha',
    semear: () => '',
    aoCriar: () => 'ideias.jsonl (vazio)',
  },
  {
    nome: 'projetos.json',
    descricao: 'vocabulario de projeto: slug -> pasta',
    aoCriar: () => `projetos.json (solta + ${slugificar(path.basename(PROJETO)) || 'este-projeto'})`,
    semear: (destino) => {
      const slug = slugificar(path.basename(PROJETO)) || 'este-projeto';
      return `${JSON.stringify({
        solta: { caminho: null, apelidos: [] },
        [slug]: { caminho: PROJETO, apelidos: [] },
      }, null, 2)}\n`;
    },
  },
  {
    nome: 'config.json',
    descricao: 'o que esta ligado no seu escopo de usuario',
    semear: null,
  },
  {
    nome: 'AVANCOS.md',
    descricao: 'historico de avancos que saiu do FOCO.md pela rotacao',
    semear: null,
  },
];

function tamanhoDe(p) {
  try {
    const b = fs.statSync(p).size;
    if (b === 0) return 'vazio';
    return b < 1024 ? `${b} B` : `${(b / 1024).toFixed(1)} KB`;
  } catch {
    return null;
  }
}

function criar() {
  const destino = process.env.RFM_ROOT || destinoPadrao();

  fs.mkdirSync(destino, { recursive: true });
  const feito = [];
  // Nunca sobrescreve: a pasta é a memória do usuário, e setup que roda de novo
  // não pode apagar o que já existe. É a mesma razão de o `iniciar` da esteira
  // recusar slug repetido.
  //
  // O `projetos.json` nasce com DUAS entradas e não vazio: vocabulário vazio
  // recusaria todo `plantar`, e a `solta` é a que recebe ideia que não é de repo
  // nenhum.
  for (const a of ARQUIVOS) {
    if (!a.semear) continue;
    const alvo = path.join(destino, a.nome);
    if (fs.existsSync(alvo)) continue;
    fs.writeFileSync(alvo, a.semear(destino), 'utf8');
    feito.push(a.aoCriar ? a.aoCriar() : a.nome);
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
    // Cada arquivo que o plugin possui aparece NOMEADO. Ate 2026-08-12 este bloco
    // mostrava so o caminho da pasta, e arquivo novo (o `projetos.json`) podia
    // nascer sem que o usuario tivesse onde ve-lo. A lista e a mesma que o `criar`
    // semeia — uma fonte, duas portas.
    for (const a of ARQUIVOS) {
      const tam = tamanhoDe(path.join(raiz, a.nome));
      console.log(`  ${a.nome.padEnd(14)} ${(tam || '(ausente)').padEnd(9)} ${a.descricao}`);
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

  // PONTES: quais hosts de agente recebem as regras. E configuracao ("o que eu uso
  // nesta maquina"), por isso mora aqui; o repositorio de DESTINO nao e — ele e alvo
  // explicito do comando, com ensaio, porque o arquivo gerado vai ser commitado no
  // repo de outra pessoa. O que este bloco NAO guarda, de proposito: em quais repos
  // a ponte ja foi gerada. Isso e estado que envelhece sem ninguem conferir, e o
  // arquivo no repo (com o marcador `rainforest-mind:inicio`) e a fonte da verdade.
  const pontes = Object.entries(CHAVES).filter(([k]) => k.startsWith('ponte-'));
  const ligadas = pontes.filter(([k]) => valores[k]).map(([k]) => k.replace('ponte-', ''));
  console.log('');
  console.log('PONTES (as regras deste plugin em outro agente, geradas do mesmo SKILL.md)');
  if (!ligadas.length) {
    console.log('  nenhuma ligada — o plugin vale so no Claude Code desta maquina');
    console.log('  ligue o que voce usa: node scripts/setup.cjs --ligar ponte-codex');
  } else {
    for (const [chave, def] of pontes) {
      if (!valores[chave]) continue;
      console.log(`  ligado    ${chave.replace('ponte-', '').padEnd(8)} ${def.descricao}`);
    }
    console.log(`  gerar num repo: node scripts/ponte.cjs --alvo <dir>            (ensaio)`);
    console.log(`                  node scripts/ponte.cjs --alvo <dir> --aplicar`);
  }

  console.log('');
  console.log('PROJETOS (slug -> pasta; e o slug que vai no campo `projeto` das ideias)');
  if (raiz) listarProjetos(raiz);
  else console.log('  sem pasta de dados, sem vocabulario');

  console.log('');
  console.log('Para trocar:');
  console.log('  node scripts/setup.cjs --desligar <chave> [--escopo projeto|usuario]');
  console.log('  node scripts/setup.cjs --ligar    <chave> [--escopo projeto|usuario]');
  console.log('  node scripts/setup.cjs --projeto <slug> --caminho <dir> [--apelido a,b]');
  console.log('  node scripts/setup.cjs --remover-projeto <slug>');
  console.log('');
  console.log('O que criar de automacao NESTE projeto e outra pergunta, e tem dono');
  console.log('oficial: a skill `claude-automation-recommender` (plugin claude-code-setup).');
}

// ---------------------------------------------------------------- projetos

/**
 * Caminho de projeto é configuração, e configuração é assunto do setup — pedido do
 * usuario em 2026-08-12. A escrita continua sendo de UMA implementação só
 * (`hooks/lib/projetos.cjs`), que o `ideias.cjs` usa pelo `projetos --registrar`:
 * duas versões do mesmo esquema divergem em silêncio.
 */
function raizDeDadosOuMorre() {
  const raiz = resolverRaiz({ plugin: CODIGO_ROOT }).raiz;
  if (!raiz) {
    console.error('erro: nao ha pasta de dados montada — rode primeiro: node scripts/setup.cjs --criar');
    process.exit(1);
  }
  return raiz;
}

function listarProjetos(raiz) {
  let mapa;
  try {
    mapa = P.ler(raiz);
  } catch (e) {
    console.log(`  ERRO: ${e.message}`);
    return;
  }
  if (mapa === null) {
    console.log('  nenhum vocabulario ainda — o campo `projeto` das ideias entra SEM validacao');
    console.log('  registre o primeiro: node scripts/setup.cjs --projeto <slug> --caminho <dir>');
    return;
  }
  const slugs = Object.keys(mapa).sort();
  if (!slugs.length) console.log('  (vazio)');
  for (const s of slugs) {
    const caminho = mapa[s].caminho;
    // Caminho que nao existe nunca casa com a pasta de uma sessao, e o `semear`
    // devolveria vazio sem dizer por que. Falha silenciosa se anuncia AQUI.
    const marca = !caminho ? '(sem pasta propria)' : P.existe(caminho) ? caminho : `${caminho}  <- NAO EXISTE nesta maquina`;
    console.log(`  ${s.padEnd(22)} ${marca}`);
    const ap = P.apelidosDe(mapa, s);
    if (ap.length) console.log(`  ${''.padEnd(22)} apelidos: ${ap.join(', ')}`);
  }
}

function registrarProjeto(slug, caminho, apelido) {
  const raiz = raizDeDadosOuMorre();
  let r;
  try {
    r = P.registrar(raiz, String(slug), { caminho: caminho === null ? undefined : String(caminho), apelido });
  } catch (e) {
    console.error(`erro: ${e.message}`);
    process.exit(1);
  }
  console.log(`${r.novo ? 'registrado' : 'atualizado'} '${r.slug}'`);
  console.log(`  caminho: ${r.entrada.caminho || '(nenhum)'}`);
  console.log(`  apelidos: ${r.entrada.apelidos.join(', ') || '(nenhum)'}`);
  console.log(`  arquivo: ${P.arquivoDe(raiz)}`);
  for (const a of r.avisos) console.log(`  aviso: ${a}`);
}

function removerProjeto(slug) {
  const raiz = raizDeDadosOuMorre();
  // Quem sabe se o slug esta em uso e o jsonl, e ele e do ideias.cjs. Aqui a
  // pergunta e feita de leve (leitura direta): a trava de verdade vive na lib.
  let emUso = [];
  try {
    const linhas = fs.readFileSync(path.join(raiz, 'ideias.jsonl'), 'utf8').split('\n').filter((l) => l.trim());
    emUso = linhas.map((l) => JSON.parse(l)).filter((o) => o.projeto === slug).map((o) => o.id);
  } catch { /* sem jsonl legivel, a lib decide */ }
  try {
    const r = P.remover(raiz, String(slug), emUso);
    console.log(`removido '${slug}'`);
    console.log(`  restam: ${Object.keys(r.mapa).sort().join(', ') || '(nenhum)'}`);
  } catch (e) {
    console.error(`erro: ${e.message}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------- versionamento

/**
 * Transforma a raiz de dados num repositório git, com .gitignore que ignora
 * o banco SQLite (binário que muda a cada minuto).
 *
 * Atende D3 e D7 do design. É idempotente: rodar duas vezes não quebra nem
 * duplica commit.
 *
 * exit 0: repositorio foi criado ou ja existia
 * exit 1: raiz nao existe ou erro ao criar repo
 */
function versionar() {
  const { raiz, nivel } = resolverRaiz({ plugin: CODIGO_ROOT });

  if (!raiz) {
    console.error('erro: nao ha pasta de dados — rode primeiro: node scripts/setup.cjs --criar');
    process.exit(1);
  }

  const gitDir = path.join(raiz, '.git');
  const gitignorePath = path.join(raiz, '.gitignore');

  // Idempotencia: se ja eh repositorio, nada a fazer
  if (fs.existsSync(gitDir)) {
    console.log(`repositorio ja existe em: ${raiz}`);
    return;
  }

  // Cria .gitignore se nao existir. Nao sobrescreve se ja existe
  // (usuario pode ter escrito manualmente algo ali).
  if (!fs.existsSync(gitignorePath)) {
    const gitignoreConteudo = `# Dados do rainforest-mind (banco principal + backups)
# Binario que muda a cada minuto — git nao da diff legivel dele
# Cobre rainforest.db* (banco principal e seus journals)
# e .rainforest-*/ (backups e outros dados persistidos)
rainforest.db*
.rainforest-*/
`;
    fs.writeFileSync(gitignorePath, gitignoreConteudo, 'utf8');
  }

  // Inicializa repositorio e faz commit inicial
  try {
    execSync('git init', { cwd: raiz, stdio: 'pipe' });
    execSync('git add -A', { cwd: raiz, stdio: 'pipe' });
    execSync('git commit -m "Versionamento inicial: estrutura de dados do rainforest"', {
      cwd: raiz,
      stdio: 'pipe',
    });
    console.log(`repositorio criado em: ${raiz}`);
  } catch (e) {
    console.error(`erro ao criar repositorio: ${e.message}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------- CLI

function main() {
  // `versionar` como subcomando posicional (argv[2])
  if (process.argv[2] === 'versionar') {
    versionar();
    return;
  }

  if (tem('criar')) {
    criar();
    console.log('');
  }

  // `--ligado <chave>`: exit 0 se ligado, 1 se desligado. Existe para quem NAO e
  // Node poder perguntar — o run-vigia.ps1 pergunta por aqui em vez de
  // reimplementar a cadeia de 3 niveis em PowerShell. Falha de leitura conta como
  // DESLIGADO nas chaves cujo ligado dispara acao (vigias, branch-forcar).
  const perguntado = arg('ligado');
  if (perguntado) {
    const chave = String(perguntado);
    if (!(chave in CHAVES)) {
      console.error(`erro: '${chave}' nao e uma chave conhecida. Sao: ${Object.keys(CHAVES).join(', ')}`);
      process.exit(2);
    }
    let valor = false;
    try {
      valor = resolverConfig({ projeto: PROJETO }).valores[chave] === true;
    } catch {
      valor = false;
    }
    console.log(valor ? 'ligado' : 'desligado');
    process.exit(valor ? 0 : 1);
  }

  const projeto = arg('projeto');
  if (projeto) {
    registrarProjeto(projeto, arg('caminho'), arg('apelido'));
    return;
  }
  const removerProj = arg('remover-projeto');
  if (removerProj) {
    removerProjeto(removerProj);
    return;
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
