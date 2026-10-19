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
 *   node scripts/setup.cjs --ligar fluxo
 *   node scripts/setup.cjs --desligar gate-staging --escopo projeto
 */

const fs = require('fs');
const path = require('path');
const { execSync, execFileSync } = require('child_process');
const readline = require('readline');
const { caminhoExecutavel, resolverExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const CODIGO_ROOT = path.resolve(__dirname, '..');
const { resolverRaiz, ehRaiz } = require('../hooks/lib/raiz.cjs');
const { CHAVES, resolverConfig, raizDoPrincipal, validarTipo, GRUPOS_ENTREVISTA } = require('../hooks/lib/config.cjs');
const P = require('../hooks/lib/projetos.cjs');

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i >= 0 ? (process.argv[i + 1] || true) : null;
}
const tem = (nome) => process.argv.includes(`--${nome}`);

// Worktree linkado e subdiretório gravam no PRINCIPAL: é lá que os gates leem.
const PROJETO = raizDoPrincipal(process.env.CLAUDE_PROJECT_DIR || process.cwd());

// ---------------------------------------------------------------- pasta de dados

/** Onde a pasta de dados NASCE quando ainda não existe: `~/.rainforest`. */
function destinoPadrao() {
  return path.join(process.env.USERPROFILE || process.env.HOME || '', '.rainforest');
}

/** Onde o `criar()` SEMEIA. Uma fonte só: o ensaio do `--aplicar` mostra este mesmo caminho. */
function destinoDoCriar() {
  return process.env.RFM_ROOT || destinoPadrao();
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

/** ESTRATEGIA.md (D13): contexto estável, lido na abertura; o tático é do /foco. */
const ESTRATEGIA_MODELO = (texto) => `# Estratégia

Contexto estável, lido na abertura de cada sessão. O tático (o que é agora) é do \`/foco\`.

${texto.trim()}
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
  const destino = destinoDoCriar();

  fs.mkdirSync(destino, { recursive: true });
  const feito = [];
  // Nunca sobrescreve: a pasta é a memória do usuário, e setup que roda de novo
  // não pode apagar o que já existe. É a mesma razão de o `iniciar` do fluxo
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

/** Um config.json só pode ser objeto: array ou escalar não recebe chave (#559). */
function ehObjetoSimples(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

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
  try {
    const lido = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
    if (!ehObjetoSimples(lido)) {
      console.error(`erro: ${arquivo} nao e um objeto JSON; corrija ou apague o arquivo antes de gravar`);
      process.exit(2); // sem gravar: sobrescrever aqui seria perder o conteudo
    }
    cfg = lido;
  } catch { /* arquivo novo, ou JSON invalido: como hoje, recomeca de {} */ }
  cfg[chave] = valor;

  fs.mkdirSync(base, { recursive: true });
  const tmp = `${arquivo}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, arquivo); // atomico: config truncada e pior que ausente

  // Booleano segue dizendo ligado/desligado; texto, lista e modelo mostram o valor (o --aplicar grava esses).
  const dito = typeof valor === 'boolean' ? (valor ? 'ligado' : 'desligado') : JSON.stringify(valor);
  console.log(`${chave}: ${dito} no escopo ${escopo}`);
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

  console.log('');
  console.log('DIAL DE INTENSIDADE (escada YAGNI)');
  // Lê a configuração de nível de intensidade
  let nivelIntensidade = 'padrão'; // padrão fallback
  let origem_nivel = 'padrão';
  try {
    let cfg_projeto = null;
    let cfg_usuario = null;
    const doProjeto = path.join(PROJETO, '.rainforest', 'config.json');
    const doUsuario = arquivos.usuario;

    // Só lê config do projeto se a pasta .rainforest for uma raiz válida (tem FOCO.md ou ideias.jsonl)
    // Isso garante consistência com hooks/lib/raiz.cjs e com o comportamento do hook escada-subagente
    const pastaProjetoRaiz = path.join(PROJETO, '.rainforest');
    if (ehRaiz(pastaProjetoRaiz)) {
      try {
        cfg_projeto = JSON.parse(fs.readFileSync(doProjeto, 'utf8'));
      } catch { /* sem config do projeto */ }
    }

    try {
      if (doUsuario) cfg_usuario = JSON.parse(fs.readFileSync(doUsuario, 'utf8'));
    } catch { /* sem config do usuario */ }

    if (cfg_projeto && typeof cfg_projeto['escada-intensidade'] === 'string') {
      nivelIntensidade = cfg_projeto['escada-intensidade'];
      origem_nivel = 'projeto';
    } else if (cfg_usuario && typeof cfg_usuario['escada-intensidade'] === 'string') {
      nivelIntensidade = cfg_usuario['escada-intensidade'];
      origem_nivel = 'usuario';
    }
  } catch { /* sem arquivo, use padrão */ }

  const descNivel = {
    'enxuto': 'só proteções (carve-outs), sem degraus',
    'padrão': 'escada completa (7 degraus + proteções)'
  };
  console.log(`  ${nivelIntensidade.padEnd(10)} ${descNivel[nivelIntensidade] || '(desconhecido)'}`);
  if (origem_nivel !== 'padrão') console.log(`            ^ definido em: ${origem_nivel}`);
  console.log(`  trocar:   node scripts/setup.cjs --ligar escada-intensidade enxuto [--escopo usuario|projeto]`);

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

  // INTEGRACOES: repositórios opcionais com ciclo de release próprio. Declaráveis
  // e desligadas por padrão. O `/saude` confere só o que foi declarado.
  const integracoes = Object.entries(CHAVES).filter(([k]) => k.startsWith('integracao-'));
  const integracoesLigadas = integracoes.filter(([k]) => valores[k]);
  console.log('');
  console.log('INTEGRACOES (repositorios opcionais, declaraveis e desligadas por padrao)');
  if (!integracoesLigadas.length) {
    console.log('  nenhuma ligada');
  }
  for (const [chave, def] of integracoes) {
    const marca = valores[chave] ? 'ligado   ' : 'DESLIGADO';
    console.log(`  ${marca} ${chave.replace('integracao-', '').padEnd(14)} ${def.descricao}`);
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
 * duplica commit. Se o repositório já existe:
 * - Garante que .gitignore tem os padrões corretos
 * - Desrastreia arquivos que deveriam estar ignorados (ex: .db versionado antes)
 * - Nunca perde dados — apenas remove do rastreamento
 *
 * exit 0: repositorio foi criado, atualizado, ou ja estava correto
 * exit 1: raiz nao existe ou erro ao criar/atualizar repo
 */
function versionar() {
  const { raiz, nivel } = resolverRaiz({ plugin: CODIGO_ROOT });

  if (!raiz) {
    console.error('erro: nao ha pasta de dados — rode primeiro: node scripts/setup.cjs --criar');
    process.exit(1);
  }

  const gitDir = path.join(raiz, '.git');
  const gitignorePath = path.join(raiz, '.gitignore');

  // Conteúdo esperado do .gitignore — fonte única
  const gitignoreConteudo = `# Dados do rainforest-mind (banco principal + backups)
# Binario que muda a cada minuto — git nao da diff legivel dele
# Cobre rainforest.db* (banco principal e seus journals)
# e .rainforest-*/ (backups e outros dados persistidos)
rainforest.db*
.rainforest-*/
`;

  try {
    // Se repositório não existe, criar
    if (!fs.existsSync(gitDir)) {
      // Cria .gitignore antes de init, mas não sobrescreve se já existe
      // (permite que o usuário tenha escrito conteúdo customizado antes de chamar versionar)
      if (!fs.existsSync(gitignorePath)) {
        fs.writeFileSync(gitignorePath, gitignoreConteudo, 'utf8');
      } else {
        // Arquivo já existe: garantir que tem os padrões
        const conteudoAtual = fs.readFileSync(gitignorePath, 'utf8');
        if (!conteudoAtual.includes('rainforest.db*')) {
          fs.appendFileSync(gitignorePath, '\n' + gitignoreConteudo, 'utf8');
        }
      }

      // Inicializa repositorio e faz commit inicial
      execFileSync(caminhoExecutavel('git'), ['init'], { cwd: raiz, stdio: 'pipe' });
      execFileSync(caminhoExecutavel('git'), ['add', '-A'], { cwd: raiz, stdio: 'pipe' });
      execFileSync(caminhoExecutavel('git'), ['commit', '-m', 'Versionamento inicial: estrutura de dados do rainforest'], {
        cwd: raiz,
        stdio: 'pipe',
      });
      console.log(`repositorio criado em: ${raiz}`);
      return;
    }

    // Repositório já existe — tornar idempotente
    console.log(`repositorio ja existe em: ${raiz}`);

    // 1. Garantir que .gitignore tem os padrões corretos (Achado 3)
    let gitignoreAtualizado = false;
    if (!fs.existsSync(gitignorePath)) {
      fs.writeFileSync(gitignorePath, gitignoreConteudo, 'utf8');
      gitignoreAtualizado = true;
      console.log('  .gitignore criado com padrões atualizados');
    } else {
      // Verificar se tem os padrões esperados
      const conteudoAtual = fs.readFileSync(gitignorePath, 'utf8');
      if (!conteudoAtual.includes('rainforest.db*')) {
        // Anexar padrões faltando ao final
        fs.appendFileSync(gitignorePath, '\n' + gitignoreConteudo, 'utf8');
        gitignoreAtualizado = true;
        console.log('  .gitignore atualizado com padrões faltando');
      }
    }

    // 2. Desrastrear arquivos que deveriam estar ignorados (Achado 3)
    // Isto acontece quando alguém rodou versionar antes do .gitignore estar correto
    // e commitou rainforest.db ou backups.
    try {
      const arquivosRastreados = execFileSync(caminhoExecutavel('git'), ['ls-files'], { cwd: raiz, encoding: 'utf8' })
        .split('\n')
        .filter(f => f.trim());

      const arquivosIgnorados = ['rainforest.db', 'rainforest.db-shm', 'rainforest.db-wal'];
      const arquivosDesrastrear = arquivosRastreados.filter(f => {
        return arquivosIgnorados.some(padrão => {
          // Verificar se arquivo casa com padrão (direto ou como wildcard)
          return f === padrão || f.startsWith(padrão);
        });
      });

      if (arquivosDesrastrear.length > 0) {
        console.log(`  desrastreando ${arquivosDesrastrear.length} arquivo(s) que deveriam estar ignorados:`);
        for (const arquivo of arquivosDesrastrear) {
          execFileSync(caminhoExecutavel('git'), ['rm', '--cached', arquivo], { cwd: raiz, stdio: 'pipe' });
          console.log(`    ${arquivo}`);
        }
        // Fazer commit para formalizar a remoção do histórico
        execFileSync(caminhoExecutavel('git'), ['add', '.gitignore'], { cwd: raiz, stdio: 'pipe' });
        execFileSync(caminhoExecutavel('git'), ['commit', '-m', 'Desrastrear arquivos que deveriam estar ignorados (banco + journals)'], {
          cwd: raiz,
          stdio: 'pipe',
        });
        console.log('  commit: arquivos desrastreados formalizado');
      }
    } catch (e) {
      // Se falhar ao listar ou desrastrear, log mas nao trava
      if (process.env.DEBUG_SETUP) {
        console.error(`  AVISO: erro ao verificar rastreamento: ${e.message}`);
      }
    }

    if (gitignoreAtualizado) {
      try {
        execFileSync(caminhoExecutavel('git'), ['add', '.gitignore'], { cwd: raiz, stdio: 'pipe' });
        execFileSync(caminhoExecutavel('git'), ['commit', '-m', 'Atualizar .gitignore com padrões atuais'], {
          cwd: raiz,
          stdio: 'pipe',
        });
        console.log('  commit: .gitignore atualizado');
      } catch (e) {
        // Falha ao commitar .gitignore (pode nao ter mudanças se ja estava atualizado)
        if (process.env.DEBUG_SETUP) {
          console.error(`  AVISO: erro ao commitar .gitignore: ${e.message}`);
        }
      }
    }
  } catch (e) {
    console.error(`erro ao processar repositorio: ${e.message}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------- plano da entrevista

/**
 * Detecta se a chave aparece nesta maquina. `detectar: {}` = nada a detectar (null:
 * a pergunta e de preferencia). Senao TODAS as formas declaradas precisam passar.
 *
 * `resolverExecutavel`, e nao `caminhoExecutavel`: este procura so `.com`/`.exe` e,
 * quando nao acha, devolve um caminho INEXISTENTE (dentro de hooks/lib/ausente-do-PATH).
 * Nesta maquina o `codex` e `codex.cmd` (npm), entao checar por `caminhoExecutavel`
 * daria "ausente" sempre. Conferido em 2026-10-17.
 */
async function detectarChave(detectar) {
  if (!detectar || Object.keys(detectar).length === 0) return null;
  const provas = [];
  for (const nome of detectar.executaveis || []) provas.push(Boolean(resolverExecutavel(nome)));
  for (const nome of detectar.env || []) provas.push(Boolean(process.env[nome]));
  if (detectar.integracao) {
    // Carregado so aqui: o estado e a mutacao da bateria antiga (testa-setup.sh, bloco 7)
    // montam uma arvore com poucas libs, e um require de topo quebraria todos eles.
    const { INTEGRACOES } = require('../hooks/lib/integracoes.cjs');
    const checador = INTEGRACOES[detectar.integracao];
    let ok = false;
    if (checador) {
      try { ok = (await checador.checar()).ok === true; } catch { ok = false; }
    }
    provas.push(ok);
  }
  if (provas.length === 0) return null;
  return provas.every(Boolean);
}

/** Pasta de configuracao do Claude Code desta conta: CLAUDE_CONFIG_DIR, senao ~/.claude. */
function pastaDeConfigClaude() {
  if (process.env.CLAUDE_CONFIG_DIR) return process.env.CLAUDE_CONFIG_DIR;
  return path.join(process.env.USERPROFILE || process.env.HOME || '', '.claude');
}

/** `cwd` da PRIMEIRA linha do transcrito que o tem. Para ali: o resto nao e lido. */
function cwdDoTranscrito(arquivo) {
  return new Promise((resolve) => {
    const entrada = fs.createReadStream(arquivo, { encoding: 'utf8' });
    const rl = readline.createInterface({ input: entrada, crlfDelay: Infinity });
    let feito = false;
    const fim = (valor) => {
      if (feito) return;
      feito = true;
      rl.close();
      entrada.destroy();
      resolve(valor);
    };
    rl.on('line', (linha) => {
      if (feito) return;
      let obj;
      try { obj = JSON.parse(linha); } catch { return; }
      if (obj && typeof obj.cwd === 'string' && obj.cwd) fim(obj.cwd);
    });
    rl.on('close', () => fim(null));
    entrada.on('error', () => fim(null));
  });
}

function ehRepoGit(dir) {
  try {
    if (!fs.statSync(dir).isDirectory()) return false;
    return fs.existsSync(path.join(dir, '.git')); // pasta, ou arquivo (worktree)
  } catch {
    return false;
  }
}

function chaveDeCaminho(p) {
  const r = path.resolve(p);
  return process.platform === 'win32' ? r.toLowerCase() : r;
}

/**
 * Sugestoes de projeto: uma por pasta de `<config>/projects/`, a partir do transcrito
 * MAIS NOVO dela. Vira sugestao so a pasta que existe, e repo git, e que ainda nao
 * esta em projetos.json (nem pelo slug, nem pelo caminho). Erro de leitura numa pasta
 * pula essa pasta; nunca derruba o modo.
 */
async function sugestoesDeProjeto(raiz) {
  let registrados = {};
  if (raiz) {
    try { registrados = P.ler(raiz) || {}; } catch { registrados = {}; }
  }
  const slugsUsados = new Set(Object.keys(registrados));
  const caminhosUsados = new Set(
    Object.values(registrados).map((v) => v && v.caminho).filter(Boolean).map(chaveDeCaminho)
  );

  const raizProjetos = path.join(pastaDeConfigClaude(), 'projects');
  let pastas = [];
  try {
    pastas = fs.readdirSync(raizProjetos, { withFileTypes: true }).filter((d) => d.isDirectory());
  } catch {
    return [];
  }

  const achados = [];
  for (const d of pastas) {
    try {
      const dir = path.join(raizProjetos, d.name);
      const jsonls = fs.readdirSync(dir)
        .filter((n) => n.endsWith('.jsonl'))
        .map((n) => ({ arquivo: path.join(dir, n), mtime: fs.statSync(path.join(dir, n)).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime);
      if (!jsonls.length) continue;
      const cwd = await cwdDoTranscrito(jsonls[0].arquivo);
      if (!cwd || !ehRepoGit(cwd)) continue;
      // Worktree de agente (.claude/worktrees/) e repo git, mas não é projeto do usuário (B do plano).
      if (cwd.replace(/\\/g, '/').toLowerCase().includes('/.claude/worktrees/')) continue;
      const slug = slugificar(path.basename(cwd));
      if (!slug) continue;
      achados.push({ slug, caminho: cwd, mtime: jsonls[0].mtime });
    } catch {
      continue;
    }
  }

  achados.sort((a, b) => b.mtime - a.mtime);
  const slugsVistos = new Set();
  const caminhosVistos = new Set();
  const saida = [];
  for (const a of achados) {
    const cam = chaveDeCaminho(a.caminho);
    if (slugsUsados.has(a.slug) || caminhosUsados.has(cam)) continue;
    if (slugsVistos.has(a.slug) || caminhosVistos.has(cam)) continue;
    slugsVistos.add(a.slug);
    caminhosVistos.add(cam);
    saida.push({ slug: a.slug, caminho: a.caminho });
  }
  return saida;
}

/**
 * `--plano-entrevista`: o que a skill /setup precisa para entrevistar, em UM JSON no
 * stdout. Nao grava nada: nem config, nem projetos, nem FOCO.md (D11).
 */
async function planoEntrevista() {
  const { raiz, nivel } = resolverRaiz({ plugin: CODIGO_ROOT });

  // Se a leitura da configuracao falhar, cada chave cai no padrao do codigo.
  let cfg = null;
  try { cfg = resolverConfig({ projeto: PROJETO }); } catch { cfg = null; }

  const porGrupo = {};
  for (const g of GRUPOS_ENTREVISTA) porGrupo[g] = [];
  const fixas = [];

  for (const [chave, meta] of Object.entries(CHAVES)) {
    const temValor = cfg !== null && Object.prototype.hasOwnProperty.call(cfg.valores, chave);
    const valor = temValor ? cfg.valores[chave] : meta.padrao;
    const origem = temValor && cfg.origem[chave] !== undefined ? cfg.origem[chave] : 'padrao';

    if (meta.entrevista === null) {
      fixas.push({ chave, valor });
      continue;
    }
    if (!Object.prototype.hasOwnProperty.call(porGrupo, meta.entrevista.grupo)) {
      throw new Error(`chave '${chave}' declara grupo '${meta.entrevista.grupo}' fora de GRUPOS_ENTREVISTA`);
    }
    const detectado = await detectarChave(meta.entrevista.detectar);
    const perguntar = meta.entrevista !== null && detectado !== false;
    porGrupo[meta.entrevista.grupo].push({ chave, valor, origem, detectado, perguntar });
  }

  return {
    primeira_vez: primeiraVez(raiz, nivel),
    nivel: raiz ? nivel : null,
    passos: GRUPOS_ENTREVISTA.map((grupo) => ({ grupo, chaves: porGrupo[grupo] })),
    fixas,
    sugestoes: { projetos: await sugestoesDeProjeto(raiz) },
  };
}

// ---------------------------------------------------------------- aplicar (D5, D9, D11, D13)

/** Primeira vez (D1): sem pasta de dados, ou a do plugin, ou pasta sem FOCO.md (pasta vazia = setup nunca rodou nela). */
function primeiraVez(raiz, nivel) {
  return !raiz || nivel === 'plugin' || !fs.existsSync(path.join(raiz, 'FOCO.md'));
}

/**
 * Onde o `--aplicar` GRAVA o escopo usuario, e de onde o `--ensaio` lê o estado. Uma fonte
 * só para as duas portas: um ensaio que lê outra raiz mostra um diff que não é o que se
 * grava (revisor de 2026-10-17: com `nivel: plugin` o ensaio dizia `ja existe`).
 *
 * Primeira vez, o `criar()` semeia em `RFM_ROOT || destinoPadrao()`, e é ali que o aplicar
 * cai. Exceção: raiz de projeto sem FOCO.md (só ideias.jsonl) continua vencendo depois do
 * `criar()`, porque o resolverRaiz põe o projeto antes do home.
 */
function raizDeGravacao(raizAntes, nivelAntes) {
  if (!primeiraVez(raizAntes, nivelAntes)) return raizAntes;
  if (nivelAntes === 'projeto') return raizAntes;
  return process.env.RFM_ROOT || destinoPadrao();
}

const CAMPOS_PAYLOAD = ['chaves', 'projetos', 'estrategia'];
const CAMPOS_PROJETO = ['slug', 'caminho', 'apelido'];

function ehDiretorio(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

/** Acumula em `erros` tudo o que impede gravar. Esta função não escreve nada. */
function validarPayload(p, erros) {
  if (typeof p !== 'object' || p === null || Array.isArray(p)) {
    erros.push('o payload precisa ser um objeto JSON');
    return;
  }
  for (const k of Object.keys(p)) {
    if (!CAMPOS_PAYLOAD.includes(k)) erros.push(`campo desconhecido no payload: '${k}'`);
  }
  if (p.chaves !== undefined) {
    if (typeof p.chaves !== 'object' || p.chaves === null || Array.isArray(p.chaves)) {
      erros.push('"chaves" precisa ser um objeto {"<chave>": <valor>}');
    } else {
      for (const [chave, valor] of Object.entries(p.chaves)) {
        if (!Object.prototype.hasOwnProperty.call(CHAVES, chave)) {
          erros.push(`chave '${chave}' nao e conhecida`);
          continue;
        }
        const tipo = CHAVES[chave].tipo || 'boolean';
        if (!validarTipo(valor, tipo)) {
          erros.push(`'${chave}' espera um valor do tipo ${tipo}, veio ${JSON.stringify(valor)}`);
        }
      }
    }
  }
  if (p.projetos !== undefined) {
    if (!Array.isArray(p.projetos)) {
      erros.push('"projetos" precisa ser uma lista');
    } else {
      p.projetos.forEach((pr, i) => {
        const rot = `projetos[${i}]`;
        if (typeof pr !== 'object' || pr === null || Array.isArray(pr)) {
          erros.push(`${rot} precisa ser um objeto`);
          return;
        }
        for (const k of Object.keys(pr)) {
          if (!CAMPOS_PROJETO.includes(k)) erros.push(`${rot}: campo desconhecido '${k}'`);
        }
        if (typeof pr.slug !== 'string' || !P.RE_SLUG.test(pr.slug)) {
          erros.push(`${rot}: slug '${pr.slug}' nao e kebab-case`);
        }
        if (typeof pr.caminho !== 'string' || !path.isAbsolute(pr.caminho)) {
          erros.push(`${rot}: caminho precisa ser absoluto`);
        } else if (!ehDiretorio(pr.caminho)) {
          erros.push(`${rot}: caminho '${pr.caminho}' nao existe ou nao e pasta`);
        }
        const apelidos = pr.apelido === undefined ? [] : [].concat(pr.apelido);
        if (!apelidos.every((a) => typeof a === 'string' && a.trim() && !a.includes(','))) {
          erros.push(`${rot}: apelido precisa ser texto (ou lista de textos) sem virgula`);
        }
      });
    }
  }
  if (p.estrategia !== undefined && (typeof p.estrategia !== 'string' || !p.estrategia.trim())) {
    erros.push('"estrategia" precisa ser um texto nao vazio');
  }
}

const apelidoDe = (pr) => (pr.apelido === undefined ? undefined : [].concat(pr.apelido).join(','));

function valoresAtuais() {
  try {
    return resolverConfig({ projeto: PROJETO });
  } catch {
    return null;
  }
}

/** O que o --aplicar faria, linha a linha. Só lê. */
function linhasEnsaio({ chaves, projetos, estrategia, raiz, escopo }) {
  const linhas = [];
  const atual = valoresAtuais();
  const valores = atual ? atual.valores : null;
  for (const [chave, depois] of Object.entries(chaves)) {
    const antes = valores ? valores[chave] : CHAVES[chave].padrao;
    const jDepois = JSON.stringify(depois);
    // O .rainforest do projeto vence o escopo usuario: gravar la e nao mudar nada. O aviso
    // sai na linha, antes da confirmacao, e so quando o valor atual vem do projeto.
    const origem = atual ? atual.origem[chave] : 'padrao';
    const aviso = escopo === 'usuario' && origem.startsWith('projeto')
      ? ` (AVISO: o .rainforest/config.json do projeto fixa ${JSON.stringify(antes)} e vence o escopo usuario; grave com --escopo projeto para mudar aqui)`
      : '';
    if (JSON.stringify(antes) === jDepois) linhas.push(`${chave}: ${jDepois} (sem mudanca)${aviso}`);
    else linhas.push(`${chave}: ${JSON.stringify(antes)} -> ${jDepois}${aviso}`);
  }
  const mapa = raiz ? P.ler(raiz) || {} : {};
  for (const pr of projetos) {
    const ja = Object.prototype.hasOwnProperty.call(mapa, pr.slug);
    linhas.push(`projeto ${pr.slug}: ${pr.caminho} (${ja ? 'ja registrado' : 'novo'})`);
  }
  if (estrategia !== undefined) {
    const ja = raiz && fs.existsSync(path.join(raiz, 'ESTRATEGIA.md'));
    linhas.push(`ESTRATEGIA.md: ${ja ? 'ja existe, nao toca' : 'cria'}`);
  }
  const destino = escopo === 'projeto' ? path.join(PROJETO, '.rainforest') : (raiz || destinoPadrao());
  linhas.push(`escopo: ${escopo} (${destino})`);
  return linhas;
}

/**
 * `--aplicar <arquivo.json> [--ensaio] [--escopo projeto]`: grava o que a entrevista
 * decidiu. Valida TUDO antes da primeira escrita (um erro = nada gravado, exit 2).
 */
function aplicar() {
  const errosAplicar = [];
  const ensaio = tem('ensaio');
  const escopoArg = arg('escopo');
  const escopo = escopoArg === null ? 'usuario' : String(escopoArg);
  if (escopo !== 'usuario' && escopo !== 'projeto') {
    errosAplicar.push(`--escopo tem que ser 'projeto' ou 'usuario' (veio '${escopo}')`);
  }

  const arquivo = arg('aplicar');
  let payload = null;
  let lido = false;
  if (typeof arquivo !== 'string') {
    errosAplicar.push('--aplicar precisa do caminho de um arquivo .json');
  } else {
    try {
      payload = JSON.parse(fs.readFileSync(arquivo, 'utf8').replace(/^﻿/, ''));
      lido = true;
    } catch (e) {
      errosAplicar.push(`'${arquivo}' nao e legivel ou nao e JSON valido: ${e.message}`);
    }
  }
  if (lido) validarPayload(payload, errosAplicar);

  const { raiz: raizAntes, nivel: nivelAntes } = resolverRaiz({ plugin: CODIGO_ROOT });
  const destinoUsuario = raizDeGravacao(raizAntes, nivelAntes);
  // trocar() com escopo usuario grava na raiz que o resolverRaiz acha, e uma .rainforest
  // do projeto vence a global. Sem esta trava, config de usuario iria para o repositorio.
  if (escopo === 'usuario' && nivelAntes === 'projeto') {
    errosAplicar.push(`a pasta de dados desta sessao e a do projeto (${raizAntes}); 'usuario' gravaria la. Use --escopo projeto, ou aponte RFM_ROOT para a pasta de dados do usuario`);
  }
  if (lido && payload && payload.projetos !== undefined) {
    try {
      P.ler(destinoUsuario);
    } catch (e) {
      errosAplicar.push(`vocabulario de projetos ilegivel: ${e.message}`);
    }
  }
  // Um config.json que existe e nao le como JSON seria regravado do zero por trocar() (perda
  // de dados). Recusa aqui, antes da primeira escrita.
  const arquivoConfig = path.join(escopo === 'projeto' ? path.join(PROJETO, '.rainforest') : destinoUsuario, 'config.json');
  if (fs.existsSync(arquivoConfig)) {
    let bruto = null;
    try {
      bruto = fs.readFileSync(arquivoConfig, 'utf8');
    } catch (e) {
      errosAplicar.push(`${arquivoConfig} nao e legivel: ${e.message}`);
    }
    if (bruto !== null) {
      try {
        const lido = JSON.parse(bruto);
        if (!ehObjetoSimples(lido)) errosAplicar.push(`${arquivoConfig} nao e um objeto JSON; corrija ou apague antes de aplicar`);
      } catch {
        errosAplicar.push(`${arquivoConfig} nao e JSON valido; corrija ou apague antes de aplicar`);
      }
    }
  }

  for (const e of errosAplicar) console.error(`erro: ${e}`);
  if (errosAplicar.length > 0) process.exit(2);

  const chaves = payload.chaves || {};
  const projetos = payload.projetos || [];
  const { estrategia } = payload;

  if (ensaio) {
    for (const linha of linhasEnsaio({ chaves, projetos, estrategia, raiz: destinoUsuario, escopo })) console.log(linha);
    // O --aplicar real chama criar() quando for primeira vez: o ensaio diz onde e o que semeia (#559).
    // Só os que faltam: o criar() nunca sobrescreve, e listar um que já existe é prometer o que ele pula.
    if (primeiraVez(raizAntes, nivelAntes)) {
      const destino = destinoDoCriar();
      const nomes = ARQUIVOS.filter((a) => a.semear && !fs.existsSync(path.join(destino, a.nome))).map((a) => a.nome);
      if (nomes.length) console.log(`criar: semearia em ${destino} (${nomes.join(', ')})`);
    }
    return;
  }

  if (primeiraVez(raizAntes, nivelAntes)) criar();
  const raiz = resolverRaiz({ plugin: CODIGO_ROOT }).raiz;
  if (!raiz) {
    console.error('erro: nao ha pasta de dados montada, mesmo depois de --criar');
    process.exit(1);
  }

  if (escopo === 'projeto' && Object.keys(chaves).length > 0) {
    console.log(`aviso: o .rainforest/config.json do repositorio (${path.join(PROJETO, '.rainforest')}) pode ir para o commit; decida no .gitignore antes de commitar`);
  }
  for (const [chave, valor] of Object.entries(chaves)) trocar(chave, valor, escopo);
  for (const pr of projetos) registrarProjeto(pr.slug, pr.caminho, apelidoDe(pr));

  if (estrategia !== undefined) {
    const alvo = path.join(raiz, 'ESTRATEGIA.md');
    if (fs.existsSync(alvo)) {
      console.log('ESTRATEGIA.md: ja existe, nao foi tocado');
    } else {
      // 'wx': nunca sobrescreve, mesmo se algo criar o arquivo no meio do caminho.
      fs.writeFileSync(alvo, ESTRATEGIA_MODELO(estrategia), { encoding: 'utf8', flag: 'wx' });
      console.log(`ESTRATEGIA.md: criado em ${alvo}`);
    }
  }
  console.log(`gravado: ${Object.keys(chaves).length} chave(s), ${projetos.length} projeto(s), escopo ${escopo}`);
}

// ---------------------------------------------------------------- CLI

function main() {
  // `versionar` como subcomando posicional (argv[2])
  if (process.argv[2] === 'versionar') {
    versionar();
    return;
  }

  // `--plano-entrevista`: JSON da entrevista do /setup. So le. Vem antes de --criar
  // para que a saida seja UM JSON, sem texto de outro modo misturado.
  if (tem('plano-entrevista')) {
    planoEntrevista().then((plano) => {
      console.log(JSON.stringify(plano, null, 2));
    });
    return;
  }

  // `--aplicar`: grava a decisão da entrevista (ou só mostra, com --ensaio). Não sai do fluxo.
  if (tem('aplicar')) {
    aplicar();
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
