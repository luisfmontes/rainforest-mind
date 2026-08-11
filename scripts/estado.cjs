#!/usr/bin/env node
/**
 * Estado da esteira — máquina de estados persistida, uma por trabalho.
 *
 * Por que existe: a esteira tem sete estágios e nenhuma memória entre sessões. Sem um
 * arquivo, "em que pé está isso?" se responde relendo a conversa — que é justamente o
 * que a compactação leva embora, e o que a sessão nova não tem.
 *
 * O desenho vem do `gates.json` do plugin interno de cliente, que é a única das três
 * fontes lidas em 2026-08-11 que resolve isso com arquivo em vez de prosa:
 *
 *   - superpowers: os estágios existem e gravam spec e plano em disco, mas a transição
 *     entre eles é texto que o modelo lê e obedece. `<HARD-GATE>` é tag XML dentro de
 *     markdown: não há parser, não há hook que a leia.
 *   - everything-claude-code: `/orchestrate` encadeia agentes em prosa e aceita o
 *     relato de cada um como verdade.
 *   - cliente: `gates.json` com esquema fechado, e quatro skills o leem como PRÉ-CONDIÇÃO.
 *
 * O que este arquivo acrescenta às três: `exigir` **sai com código ≠ 0**. Nele a
 * pré-condição é conferida por instrução dentro da skill — ou seja, pelo mesmo agente
 * que ela deveria barrar. Aqui é comando externo, e exit code não se argumenta (é a
 * mesma razão dos gates de worktree e de staging deste repo).
 *
 * Onde mora: `docs/rainforest/estado/<slug>.json` do PROJETO em que se trabalha,
 * **versionado**, ao lado do design e do plano — ver o comentário de `DIR_ESTADO`.
 *
 * Uso:
 *   node scripts/estado.cjs iniciar  --slug <slug> [--titulo "..."]
 *   node scripts/estado.cjs ler      --slug <slug>
 *   node scripts/estado.cjs marcar   --slug <slug> --estagio <e> --status <s> [--json '{...}']
 *   node scripts/estado.cjs proximo  --slug <slug>
 *   node scripts/estado.cjs exigir   --slug <slug> --estagio <e>
 *   node scripts/estado.cjs listar
 */

const fs = require('fs');
const path = require('path');

// A raiz aqui é a do PROJETO em que se trabalha, e **não** a cadeia de dados do
// rainforest (`hooks/lib/raiz.cjs`). São dois tipos de estado diferentes, e
// confundi-los foi um defeito real, pego em 2026-08-11 antes de rodar em campo:
//
//   FOCO.md, ideias.jsonl  -> do LUÍS, atravessam projeto: cadeia RFM_ROOT >
//                             projeto > global > plugin > legado
//   design, plano, estado  -> do PROJETO em que se trabalha: ficam onde o
//                             trabalho está, sempre
//
// Com a cadeia de dados, uma feature de ERP legado teria o estado gravado dentro
// do repositório do rainforest-mind — longe do código, invisível para quem
// clonasse o projeto, e misturado com o estado de outra feature de outro repo.
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

// VERSIONADO, junto do design e do plano. A primeira versão escondia isto num
// `.rainforest/estado/` fora do git, com o argumento de que "rastro de execução
// não polui o diff". O argumento estava errado, e o Luís derrubou com uma
// pergunta: o estado existe para o Claude saber como o fluxo ficou **e para
// outro dev pegar a atividade no meio**. Fora do git, quem clona o repositório
// não recebe nada — e a retomada, que é a razão de o arquivo existir, só
// funciona para quem já estava na máquina.
//
// A divisão certa não é decisão-vs-execução; é **veredito vs. tagarelice**:
//   veredito  (que estágio fechou, com que número)  -> versionado, é a fonte
//   tagarelice (briefs, diffs, log, worktree)       -> fora do git, é rastro
//
// É o que o plugin interno de cliente faz — `gates.json` mora em `docs/plans/`, e a
// skill manda ler dele em vez da conversa: "o arquivo é a fonte de verdade". O
// superpowers ignora o workspace de execução, que é a outra metade da divisão.
const DIR_ESTADO = path.join(RAIZ, 'docs', 'rainforest', 'estado');

// Os dois blocos de vocabulário, separados de propósito (lição do gates.json):
// DECISÃO é aprovada por gente e não entra na varredura de retomada; EXECUÇÃO é
// feita por máquina, tem ordem, e é por onde a retomada anda.
const DECISAO = {
  design: ['pendente', 'aprovado'],
  plano: ['pendente', 'ok'],
};
const EXECUCAO = ['executar', 'revisar', 'verificar', 'fechar'];
const STATUS_EXECUCAO = ['pendente', 'parcial', 'ok', 'reprovado'];

// Quem exige quem. `exigir` recusa se qualquer pré-requisito não estiver fechado.
const PRE_REQUISITOS = {
  design: [], // primeiro da esteira: não depende de nada, mas precisa constar aqui —
              // esta tabela é também a lista de estágios que `marcar` aceita
  plano: ['design'],
  executar: ['design', 'plano'],
  revisar: ['executar'],
  verificar: ['revisar'],
  fechar: ['verificar'],
  limpar: [], // manutenção, não é estágio da esteira: nunca bloqueia
};

const FECHADO = { design: 'aprovado', plano: 'ok' };
function estaFechado(estagio, bloco) {
  if (!bloco || typeof bloco !== 'object') return false;
  return bloco.status === (FECHADO[estagio] || 'ok');
}

function hoje() {
  // Relógio LOCAL. toISOString() é UTC e já gravou data no futuro neste repo.
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function caminho(slug) {
  return path.join(DIR_ESTADO, `${slug}.json`);
}


function ler(slug) {
  const p = caminho(slug);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function gravar(slug, estado) {
  fs.mkdirSync(DIR_ESTADO, { recursive: true });
  const tmp = `${caminho(slug)}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(estado, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, caminho(slug)); // atômico: estado truncado é pior que ausente
}

function novo(slug, titulo) {
  return {
    slug,
    titulo: titulo || slug,
    criado_em: hoje(),
    design: { status: 'pendente' },
    plano: { status: 'pendente' },
    executar: { status: 'pendente' },
    revisar: { status: 'pendente' },
    verificar: { status: 'pendente' },
    fechar: { status: 'pendente' },
  };
}

/** O primeiro estágio de execução ainda não fechado. É a definição de retomada. */
function proximo(estado) {
  for (const e of ['design', 'plano', ...EXECUCAO]) {
    if (!estaFechado(e, estado[e])) return e;
  }
  return null;
}

function faltando(estado, estagio) {
  return (PRE_REQUISITOS[estagio] || []).filter((r) => !estaFechado(r, estado[r]));
}

// ---------------------------------------------------------------- CLI

function arg(nome, obrigatorio = true) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) {
    if (obrigatorio) {
      console.error(`erro: falta --${nome}`);
      process.exit(1);
    }
    return null;
  }
  return process.argv[i + 1];
}

function main() {
  const cmd = process.argv[2];

  if (cmd === 'listar') {
    if (!fs.existsSync(DIR_ESTADO)) return console.log('(nenhum trabalho em andamento)');
    const arquivos = fs.readdirSync(DIR_ESTADO).filter((f) => f.endsWith('.json'));
    if (!arquivos.length) return console.log('(nenhum trabalho em andamento)');
    for (const f of arquivos) {
      const e = JSON.parse(fs.readFileSync(path.join(DIR_ESTADO, f), 'utf8'));
      const p = proximo(e);
      console.log(`${e.slug}  ${p ? `-> ${p}` : '(completo)'}  ${e.titulo}`);
    }
    return;
  }

  const slug = arg('slug');

  if (cmd === 'iniciar') {
    if (ler(slug)) {
      console.error(`erro: ${slug} ja existe — use 'ler' ou 'marcar'`);
      process.exit(1);
    }
    const e = novo(slug, arg('titulo', false));
    gravar(slug, e);
    console.log(`iniciado: ${caminho(slug)}`);
    console.log('commite este arquivo junto com o trabalho — e por ele que outra');
    console.log('sessao, ou outro dev, retoma de onde parou.');
    console.log(`proximo: ${proximo(e)}`);
    return;
  }

  const estado = ler(slug);
  if (!estado) {
    console.error(`erro: ${slug} nao existe — rode 'iniciar' primeiro`);
    process.exit(1);
  }

  if (cmd === 'ler') return console.log(JSON.stringify(estado, null, 2));

  if (cmd === 'proximo') {
    const p = proximo(estado);
    if (!p) return console.log('completo');
    console.log(p);
    return;
  }

  if (cmd === 'exigir') {
    const estagio = arg('estagio');
    if (!(estagio in PRE_REQUISITOS)) {
      console.error(`erro: estagio desconhecido '${estagio}'`);
      process.exit(1);
    }
    const falta = faltando(estado, estagio);
    if (!falta.length) {
      console.log(`ok: pre-requisitos de '${estagio}' fechados`);
      return;
    }
    // Exit 2, não 1: é a mesma convenção dos gates deste repo, e o que separa
    // "recusa deliberada" de "o comando quebrou".
    console.error(`RECUSADO: '${estagio}' exige ${falta.join(', ')} fechado(s).`);
    for (const r of falta) {
      console.error(`  ${r}: status=${(estado[r] || {}).status || '(ausente)'}`);
    }
    console.error(`Rode o estagio '${falta[0]}' antes. Retomada: node scripts/estado.cjs proximo --slug ${slug}`);
    process.exit(2);
  }

  if (cmd === 'marcar') {
    const estagio = arg('estagio');
    const status = arg('status');
    if (!(estagio in PRE_REQUISITOS)) {
      console.error(`erro: estagio desconhecido '${estagio}'`);
      process.exit(1);
    }
    const permitidos = DECISAO[estagio] || STATUS_EXECUCAO;
    if (!permitidos.includes(status)) {
      console.error(`erro: status '${status}' invalido para '${estagio}' — use ${permitidos.join('|')}`);
      process.exit(1);
    }
    // Fechar um estágio com pré-requisito aberto é o furo que o arquivo existe para
    // impedir: sem isto, `marcar verificar ok` pularia a revisão inteira em silêncio.
    if (status === (FECHADO[estagio] || 'ok')) {
      const falta = faltando(estado, estagio);
      if (falta.length) {
        console.error(`RECUSADO: nao da para fechar '${estagio}' com ${falta.join(', ')} em aberto.`);
        process.exit(2);
      }
    }
    let extra = {};
    const j = arg('json', false);
    if (j) {
      try {
        extra = JSON.parse(j);
      } catch (err) {
        console.error(`erro: --json nao e JSON valido: ${err.message}`);
        process.exit(1);
      }
    }
    estado[estagio] = { ...estado[estagio], ...extra, status, em: hoje() };
    gravar(slug, estado);
    console.log(`${estagio}: ${status}`);
    const p = proximo(estado);
    console.log(p ? `proximo: ${p}` : 'completo');
    return;
  }

  console.error('uso: iniciar | ler | marcar | proximo | exigir | listar');
  process.exit(1);
}

if (require.main === module) main();
module.exports = { novo, proximo, faltando, estaFechado, EXECUCAO, PRE_REQUISITOS, DIR_ESTADO };
