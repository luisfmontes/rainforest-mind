#!/usr/bin/env node
/**
 * Estado do fluxo — máquina de estados persistida, uma por trabalho.
 *
 * Por que existe: o fluxo tem sete estágios e nenhuma memória entre sessões. Sem um
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
 *   - o plugin de cliente: `gates.json` com esquema fechado, e quatro skills o leem como PRÉ-CONDIÇÃO.
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
 *   node scripts/estado.cjs liberar  --slug <slug> --estagio <e>
 *   node scripts/estado.cjs listar
 */

const fs = require('fs');
const path = require('path');
const { spawnSync, execSync } = require('child_process');

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
// não polui o diff". O argumento estava errado, e o usuario derrubou com uma
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
  // `arqueologia` e o estagio ZERO, e e OPCIONAL de proposito. Ele mapeia codigo
  // que ninguem daqui escreveu, antes de o brainstorm fechar decisao sobre terreno
  // que ninguem viu. Em projeto novo nao ha o que mapear, e exigir mapa ali seria
  // burocracia — por isso ele NAO entra na varredura de retomada (`proximo`) e
  // nada o exige. `dispensada` e o registro explicito de "olhei e nao precisa",
  // que vale mais que o silencio: silencio nao distingue "nao precisa" de
  // "ninguem olhou".
  arqueologia: ['pendente', 'ok', 'dispensada'],
  design: ['pendente', 'aprovado'],
  plano: ['pendente', 'ok'],
};
const EXECUCAO = ['executar', 'revisar', 'verificar', 'fechar'];
const STATUS_EXECUCAO = ['pendente', 'parcial', 'ok', 'reprovado'];

// Quem exige quem. `exigir` recusa se qualquer pré-requisito não estiver fechado.
const PRE_REQUISITOS = {
  arqueologia: [], // estagio zero: nunca e barrado, e nunca barra ninguem
  design: [], // primeiro do fluxo: não depende de nada, mas precisa constar aqui —
              // esta tabela é também a lista de estágios que `marcar` aceita
  plano: ['design'],
  executar: ['design', 'plano'],
  revisar: ['executar'],
  verificar: ['revisar'],
  fechar: ['verificar'],
  limpar: [], // manutenção, não é estágio do fluxo: nunca bloqueia
};

const FECHADO = { design: 'aprovado', plano: 'ok' };
// `dispensada` fecha a arqueologia tanto quanto `ok`: as duas significam que
// alguem olhou e decidiu. Sao caminhos diferentes para o mesmo lugar.
const FECHA_TAMBEM = { arqueologia: ['ok', 'dispensada'] };

// Estágios de execução que exigem evidência (comando e saida) para fechar com ok
const ESTAGIOS_EXIGEM_EVIDENCIA = ['executar', 'verificar'];
function estaFechado(estagio, bloco) {
  if (!bloco || typeof bloco !== 'object') return false;
  // Issue #148: estágio reaberto por reprovação não está fechado, seja qual for
  // o status. Antes, só o `exigir` olhava `reaberto_por`; o `marcar` conferia
  // apenas o status do upstream, e um bloco "ok + reaberto_por" passava por ele.
  if (bloco.reaberto_por) return false;
  if (FECHA_TAMBEM[estagio]) return FECHA_TAMBEM[estagio].includes(bloco.status);
  return bloco.status === (FECHADO[estagio] || 'ok');
}

// `marcar` funde o bloco anterior do estágio com o `--json` novo (ver o comentário
// em cima do `estado[estagio] = ...` mais abaixo) porque a maioria dos campos deve
// sobreviver a uma transição — `catraca_mutacao`, `snapshot`, `arquivo`. Mas
// `pendentes` é o inverso: ele descreve a INCOMPLETUDE do fechamento anterior
// (`parcial`), e sobreviver a um fechamento terminal-positivo posterior (`ok` de
// `executar`, `aprovado` de `design`, etc.) produz um objeto que se diz completo e
// lista pendência ao mesmo tempo — achado real de um revisor independente, que não
// conseguiu decidir se o trabalho estava feito.
//
// A correção não é allowlist de campos persistentes: o plano
// `decisao-que-evapora-na-esteira` fixou como invariante que `--json` continua
// aceitando metadado arbitrário, sem lista fechada que rejeite (ou, por extensão,
// que apague em silêncio) chave que essa lista não previu. Campos como `pendentes`
// e `reaberto_por` descrevem incompletude — ver `skills/executar/SKILL.md`, seção
// "Condição de parada" — por isso entram nesta lista. Um campo novo com o mesmo
// papel entra aqui quando nascer. O rastro histórico da reprovação (criterio,
// comando, saida, faltou) fica no bloco do estágio que reprovou e não é efêmero.
const CAMPOS_EFEMEROS = ['pendentes', 'reaberto_por'];

// Teto de tentativas de reprovação consecutiva. Na terceira, `exigir` do upstream
// reaberto recusa com exit 2 mandando subir a decisão ao usuário. Constante
// nomeada, sem env (Q3 do design).
const TETO_TENTATIVAS = 3;

/**
 * Bloco anterior do estágio, pronto para ser fundido com o `--json` novo. Ao
 * fechar com status terminal-positivo, remove os `CAMPOS_EFEMEROS` que o bloco
 * anterior tinha e que o `--json` novo não repetiu — do contrário eles
 * atravessam a fusão feita no `marcar` (abaixo, em `estado[estagio] = ...`) e
 * sobrevivem à transição que deveriam ter fechado.
 */
function baseParaFundir(estagio, blocoAnterior, statusNovo, extra) {
  if (!blocoAnterior) return blocoAnterior;
  if (!estaFechado(estagio, { status: statusNovo })) return blocoAnterior;
  const base = { ...blocoAnterior };
  for (const campo of CAMPOS_EFEMEROS) {
    if (!(campo in extra)) delete base[campo];
  }
  return base;
}

function hoje() {
  // Relógio LOCAL. toISOString() é UTC e já gravou data no futuro neste repo.
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/**
 * Valida slug para impedir path traversal e escapes para fora de DIR_ESTADO.
 * RECUSA explicitamente (lança erro) quando o slug é vazio ou contém `/`, `\` ou `..`.
 * Recusa é erro de quem chamou, e corrigir por baixo esconde o defeito.
 */
function validarSlug(slug) {
  if (!slug || typeof slug !== 'string' || slug.trim() === '') {
    throw new Error('slug vazio ou inválido');
  }
  if (slug.includes('/') || slug.includes('\\') || slug.includes('..')) {
    throw new Error(`slug inválido: contém caracteres proibidos (/, \\, ou ..) — ${slug}`);
  }
}

function caminho(slug) {
  validarSlug(slug);
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
    arqueologia: { status: 'pendente' },
    design: { status: 'pendente' },
    plano: { status: 'pendente' },
    executar: { status: 'pendente' },
    revisar: { status: 'pendente' },
    verificar: { status: 'pendente' },
    fechar: { status: 'pendente' },
  };
}

/** Imprime o bloco do último estágio reprovado quando ele é o motivo do próximo passo.
 *  Usado como ponto único de mutação: remover ou neutralizar esta chamada tira a feature. */
function imprimirReprovado(estado, estagio_reprovador) {
  const bloco = estado[estagio_reprovador];
  if (!bloco) return;
  // Imprime criterio, comando, saida e faltou do --json da reprovação
  if (bloco.criterio) console.log(`criterio: ${bloco.criterio}`);
  if (bloco.comando) console.log(`comando: ${bloco.comando}`);
  if (bloco.saida) console.log(`saida: ${bloco.saida}`);
  if (bloco.faltou) console.log(`faltou: ${bloco.faltou}`);
}

/** O primeiro estágio de execução ainda não fechado. É a definição de retomada. */
function proximo(estado) {
  // `arqueologia` fica FORA desta lista: se entrasse, todo projeto sem mapa
  // ficaria eternamente com "proximo: arqueologia", e o estagio opcional viraria
  // obrigatorio pela porta dos fundos.
  for (const e of ['design', 'plano', ...EXECUCAO]) {
    if (!estaFechado(e, estado[e])) return e;
  }
  return null;
}

/** Encontra o estágio de execução que foi reaberto por reprovação. */
function estagio_reprovado_pendente(estado) {
  for (const e of EXECUCAO) {
    const bloco = estado[e] || {};
    if (bloco.reaberto_por) return e;
  }
  return null;
}

function faltando(estado, estagio) {
  return (PRE_REQUISITOS[estagio] || []).filter((r) => !estaFechado(r, estado[r]));
}

/** O upstream imediato de um estágio — para reprovação, é o primeiro estágio de EXECUÇÃO.
 *  Quando um estágio de execução é reprovado, o trabalho volta ao início da fase de execução
 *  para ser refeit o. Para estágios de decisão (design, plano), não há upstream a reabrir. */
function upstreamImediato(estagio) {
  // Só há upstream para estágios de execução
  if (!EXECUCAO.includes(estagio)) return null;
  // O upstream é sempre executar (o primeiro de execução)
  return 'executar';
}

/** Rebaixa o upstream imediato para `parcial` quando um estágio é reprovado. */
function rebaixarUpstream(estado, estagio) {
  const upstream = upstreamImediato(estagio);
  if (!upstream) return null; // sem upstream, nada a rebaixar

  // Rebaixar o upstream para parcial com rastro de quem reprovou
  const bloco_upstream = estado[upstream] || {};
  estado[upstream] = {
    ...bloco_upstream,
    status: 'parcial',
    reaberto_por: {
      estagio: estagio,
      data: hoje(),
    },
    em: hoje(),
  };

  return upstream;
}

// ---------------------------------------- backstop de mutação no revisar (Issue #4)
//
// Problema: em 2026-08-13, um revisor mutou `gerar_updater_projeto.py` direto no
// diretório principal, o `gate-worktree.cjs` bloqueou o `git checkout --` do
// revert — corretamente, pela letra da trava — e ele desfez por fora do git,
// sem rastro auditável. A trava de worktree estava certa; o caminho de proteção
// no REVISAR é que não existia.
//
// Solução: capturar instantâneo (HEAD + caminhos sujos) quando `exigir revisar`
// roda, e comparar quando `marcar revisar ok` roda. Duas recusas distintas:
//   1. HEAD mexeu — qualquer movimento reprova, porque muda a base do diff
//   2. Caminho sujo NOVO — apareceu depois, não estava no instantâneo
//
// Sujeira pré-existente é legítima e não recusa — usuário pode ter outro
// trabalho em andamento no mesmo clone.
//
// DOIS defeitos que a primeira versão desta trava tinha, e que a bateria dela
// não pegava. Ficam registrados porque os dois são armadilha de fixture, não
// de código:
//
//   1. `statusOutput.trim()` antes do `split` comia o espaço inicial da
//      PRIMEIRA linha. Porcelain de arquivo rastreado e modificado vem como
//      ` M caminho` — com espaço na frente —, então `substring(3)` cortava um
//      caractere a mais e `docs/...` virava `ocs/...`. Só na primeira linha, e
//      só para arquivo rastreado: untracked vem `?? caminho`, sem espaço
//      inicial, e o fixture só tinha untracked. Pior que a mensagem errada: o
//      MESMO arquivo produzia chave diferente conforme a posição na saída, o
//      que gera falso positivo sozinho.
//
//   2. O `exigir` capturava o instantâneo e logo depois `gravar()` escrevia o
//      próprio instantâneo no arquivo de estado — que é VERSIONADO neste repo.
//      Resultado: o arquivo de estado ficava sujo DEPOIS do instantâneo, e o
//      `marcar ok` seguinte o via como caminho novo e recusava o caminho feliz,
//      sempre. O fixture não pegou porque nunca commitava o estado: lá o
//      arquivo já estava sujo (untracked) antes do instantâneo, e portanto
//      dentro dele. A bookkeeping da própria trava não pode ser evidência
//      contra o revisor, então ela sai dos dois conjuntos.

/** Caminhos que a própria trava suja, e que por isso não contam como mutação. */
function caminhosDaPropriaTrava(slug) {
  const rel = path.relative(RAIZ, path.join(DIR_ESTADO, `${slug}.json`));
  return new Set([rel.replace(/\\/g, '/')]);
}

/** Caminhos sujos do repo, normalizados. Sem `.trim()` no bloco: ver defeito 1. */
function caminhosSujos() {
  const saida = execSync('git status --porcelain', { cwd: RAIZ, encoding: 'utf8' });
  return saida
    .split(/\r?\n/)
    .filter((linha) => linha.length > 0)
    .map((linha) => {
      const partes = linha.substring(3).split(' -> ');
      const caminho = partes.length > 1 ? partes[1] : partes[0];
      return caminho.replace(/\\/g, '/');
    })
    .sort();
}

function capturarSnapshot() {
  try {
    return {
      head: execSync('git rev-parse HEAD', { cwd: RAIZ, encoding: 'utf8' }).trim(),
      caminhos_sujos: caminhosSujos(),
    };
  } catch (err) {
    console.error(`erro ao capturar snapshot: ${err.message}`);
    process.exit(1);
  }
}

function verificarMutacao(slug, snapshot_anterior) {
  if (!snapshot_anterior || typeof snapshot_anterior !== 'object') {
    // Instantâneo não existe: slug que fechou revisar sem ter passado pelo
    // exigir novo. Avise, mas não trave — retroativamente travar quebra trabalho
    // em andamento.
    console.warn(`aviso: instantâneo de revisar nao encontrado para ${slug}. Nao ha como provar ausencia de mutacao. Rode 'exigir --estagio revisar' antes de revisar.`);
    return null;
  }

  try {
    const head_agora = execSync('git rev-parse HEAD', { cwd: RAIZ, encoding: 'utf8' }).trim();

    // Verificar se HEAD mudou
    if (head_agora !== snapshot_anterior.head) {
      return `RECUSADO: HEAD mudou durante a revisao: ${snapshot_anterior.head} -> ${head_agora}.\n`
        + `A base do diff foi alterada. A revisao foi feita contra outra arvore e nao e mais valida.\n`
        + `Outra janela commitou, ou voce commitou sem querer no diretorio principal.\n`
        + `Rode 'exigir --estagio revisar' novamente para capturar o novo snapshot e revise novamente.`;
    }

    // Verificar se novos caminhos sujos apareceram
    const propria = caminhosDaPropriaTrava(slug);
    const sujos_antes = new Set(snapshot_anterior.caminhos_sujos || []);

    const novos_sujos = caminhosSujos()
      .filter((c) => !sujos_antes.has(c) && !propria.has(c));
    if (novos_sujos.length > 0) {
      return `RECUSADO: novos arquivos sujaram durante a revisao: ${novos_sujos.join(', ')}.\n`
        + `O repositorio foi mutado enquanto voce revisava. O revisor nao edita em lugar nenhum\n`
        + `muito menos no diretorio principal. Desfaca as mudancas e rode a revisao novamente.`;
    }

    return null;
  } catch (err) {
    console.error(`erro ao verificar mutacao: ${err.message}`);
    process.exit(1);
  }
}

// ------------------------------ catraca de mutacao no executar (D6, D9, D10)
//
// Em 2026-08-21 um agente cumpriu todos os criterios falsificaveis do briefing,
// colou saida de mutacao no relato e entregou 49/49 verde — e a trava que ele
// dizia ter invertido recusava o caminho feliz SEMPRE. A bateria nao sabia
// falhar, e o fechamento nao cobrava prova nenhuma disso: a catraca era prosa
// no briefing, e prosa e conferida pelo mesmo agente que ela deveria barrar. E
// a oitava vez que a familia "bateria que nao sabe falhar" volta ao acervo.
//
// Por isso o campo `mutacao` e cobrado AQUI, no `marcar --estagio executar
// --status ok`, que e o gargalo unico por onde o fluxo inteiro ja passa —
// mesma forma da trava de `base`/`head` do `revisar`, logo abaixo, e mesmo
// exit 2. O que o agente declara no campo nao vira verdade por ser declarado:
// quem re-roda a mutacao e a integracao (D8). O campo existe para que exista
// alvo declarado a re-rodar, e para que "esqueci" pare de sair 0.
//
// Duas frouxidoes deliberadas, cada uma fechando um jeito conhecido de a trava
// morrer no primeiro dia de pressa:
//
//   1. `n/a` com `motivo` e resposta aceita (D9). Tarefa de doc nao tem
//      comportamento a inverter, e exigir o impossivel cria o habito do
//      `--forcar`, que mata a trava inteira em vez de uma tarefa. Sem `motivo`,
//      porem, `n/a` seria so a palavra mais curta ate o exit 0 — por isso ele e
//      obrigatorio, e vazio nao conta.
//
//   2. Slug cujo `executar` foi aberto antes desta mudanca avisa e passa (D10).
//      Mesmo desenho do backstop acima: travar retroativo quebra fluxo em
//      andamento. O sinal de "aberto depois" e o marcador que o `exigir
//      --estagio executar` passa a gravar no proprio arquivo de estado, no
//      lugar onde o `revisar` ja grava o instantaneo dele — e o unico registro
//      que existe do momento em que o estagio abriu.
//
//   3. A lista `mutacao` deve cobrir TODAS as tarefas do plano, sem duplicatas,
//      e sem citar tarefas inexistentes. Plano que nao existe em disco avisa
//      e passa (fail-open).

/** Resultados aceitos. `verde` fica de fora de proposito: bateria que continua
 *  verde com o conserto invertido e exatamente o defeito que a catraca mede. */
const RESULTADOS_MUTACAO = ['vermelho', 'n/a'];

/** A `fixture` passou a ser exigida em 2026-08-23 (Issue #53, P2). Fluxo cuja
 *  catraca foi armada ANTES disso tem plano escrito sem o campo: exigir dele
 *  seria travar retroativo, que e o que a D10 evita para a catraca em si. Divida
 *  herdada AVISA e passa; armada depois, derruba. Mesmo idioma do
 *  `GANCHO_EXIGIDO_DESDE` do `ideias.cjs`, e pelo mesmo motivo: anistia que
 *  esconde vira esquecimento, entao o aviso sai em toda execucao. */
const FIXTURE_EXIGIDA_DESDE = '2026-08-23';

const COMO_DECLARAR = "Ex.: --json '{\"tarefas_ok\":2,\"tarefas\":2,\"mutacao\":["
  + '{"tarefa":1,"resultado":"vermelho","fixture":"nome-do-caso-de-teste"},'
  + '{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]}\'';

/**
 * Números das tarefas do plano, ou `null` quando não há plano em disco.
 *
 * A leitura é EMPRESTADA do `conferir-fluxo.cjs`, não reescrita aqui. A primeira
 * versão desta checagem tinha parser próprio, e ele divergia em duas coisas: não
 * pulava cerca de código (`### 3.` dentro de um bloco ``` virava tarefa fantasma) e
 * não normalizava CRLF. O efeito era o pior possível para uma trava — recusar
 * entrega correta, com uma mensagem apontando uma tarefa que não existe.
 */
function extrairNumerosTarefa(slug) {
  const arquivo_plano = path.join(RAIZ, 'docs', 'rainforest', 'planos', `${slug}.md`);
  if (!fs.existsSync(arquivo_plano)) {
    return null; // plano nao existe
  }

  // Emprestar leitura cria uma dependência, e dependência que falta não pode
  // derrubar o `marcar`: o resto deste arquivo avisa e libera quando não consegue
  // medir, e uma exceção aqui recusaria por motivo que não é do usuário.
  let extrairTarefas, lerMarkdown;
  try {
    ({ extrairTarefas, lerMarkdown } = require('./conferir-fluxo.cjs'));
  } catch (e) {
    console.warn(`aviso: nao consegui carregar o leitor de plano (${e.message}) — a lista de mutacao nao sera cruzada com o plano.`);
    return new Set();
  }

  const conteudo = lerMarkdown(arquivo_plano);
  if (conteudo === null) return null;

  return new Set(extrairTarefas(conteudo).map((t) => t.numero));
}

/** @returns {string|null} mensagem de recusa, ou null se passou/nao se aplica */
function verificarCatracaMutacao(slug, bloco, estado, extra) {
  // Recusar para slug novo se a catraca nao foi armada
  if (!bloco || !bloco.catraca_mutacao) {
    const criado_em = estado && estado.criado_em;
    // Comparacao de strings date: YYYY-MM-DD
    // '2026-08-20' < '2026-08-21' < '2026-08-22', etc.
    const eh_novo = criado_em && criado_em >= '2026-08-21';

    if (eh_novo) {
      // Slug criado EM ou DEPOIS de 2026-08-21 (quando a catraca nasceu),
      // mas sem ter passado por exigir para armar a catraca.
      // Se nao passou por exigir, nao tem como armar.
      return "RECUSADO: catraca de mutacao nao armada para " + slug + ". "
        + "Este 'executar' precisa ter passado por 'exigir --estagio executar' "
        + "para armar a catraca. Rode novamente: node scripts/estado.cjs exigir "
        + "--slug " + slug + " --estagio executar";
    } else {
      // Slug criado ANTES de 2026-08-21, ou sem data gravada (muito antigo).
      // D10: nao ha como saber se foi aberto antes ou depois, entao avisa.
      console.warn(`aviso: catraca de mutacao nao armada para ${slug} — este 'executar' foi aberto antes dela existir. Fechando sem prova de que as baterias sabem falhar. Rode 'exigir --estagio executar' antes de executar.`);
      return null;
    }
  }

  const exigeFixture = String(bloco.catraca_mutacao || "") >= FIXTURE_EXIGIDA_DESDE;
  const lista = extra && extra.mutacao;
  if (!Array.isArray(lista) || lista.length === 0) {
    return "RECUSADO: fechar 'executar' exige 'mutacao' no --json: uma lista, um item por tarefa do plano.\n"
      + 'Sem ela, "a bateria passou" nao distingue bateria que testa de bateria que nao\n'
      + 'sabe falhar, e foi assim que uma entrega quebrada saiu daqui 49/49 verde.\n'
      + COMO_DECLARAR;
  }

  // Extrair numeros de tarefas do plano
  const nums_plano = extrairNumerosTarefa(slug);

  // Se nao ha plano em disco, avisa e passa
  if (nums_plano === null) {
    console.warn(`aviso: plano nao encontrado para ${slug} — nao ha como validar lista de mutacao contra plano. Prosseguindo sem validacao.`);
  } else if (nums_plano.size > 0) {
    // Validar lista contra plano
    const nums_lista = new Set();
    const tarefas_vistas = new Set();

    // Cooletar todos os numeros declarados na lista
    for (const item of lista) {
      const tarefa_num = item.tarefa;
      if (tarefas_vistas.has(tarefa_num)) {
        return `RECUSADO: tarefa ${tarefa_num} aparece mais de uma vez na lista 'mutacao'.\n`
          + `Cada tarefa deve aparecer exatamente uma vez.\n${COMO_DECLARAR}`;
      }
      tarefas_vistas.add(tarefa_num);
      nums_lista.add(tarefa_num);
    }

    // Validar que todas as tarefas da lista existem no plano
    for (const num of nums_lista) {
      if (!nums_plano.has(num)) {
        return `RECUSADO: lista 'mutacao' cita tarefa ${num} que nao existe no plano.\n`
          + `Tarefas do plano: ${Array.from(nums_plano).sort((a, b) => a - b).join(', ')}.\n${COMO_DECLARAR}`;
      }
    }

    // Validar que todas as tarefas do plano estao na lista
    for (const num of nums_plano) {
      if (!nums_lista.has(num)) {
        return `RECUSADO: lista 'mutacao' nao cobre tarefa ${num} do plano.\n`
          + `Tarefas do plano: ${Array.from(nums_plano).sort((a, b) => a - b).join(', ')}.\n`
          + `Tarefas na lista: ${Array.from(nums_lista).sort((a, b) => a - b).join(', ')}.\n${COMO_DECLARAR}`;
      }
    }
  }

  // Validar estrutura de cada item
  for (let i = 0; i < lista.length; i += 1) {
    const item = lista[i];
    const onde = `mutacao[${i}]`;
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      return `RECUSADO: ${onde} nao e um objeto.\n${COMO_DECLARAR}`;
    }
    if (item.tarefa === undefined || item.tarefa === null || String(item.tarefa).trim() === '') {
      return `RECUSADO: ${onde} nao diz de que 'tarefa' e. E um item por tarefa do plano, e sem\n`
        + `o numero nao da para cruzar a lista com o plano nem re-rodar a mutacao certa.\n${COMO_DECLARAR}`;
    }
    const resultado = item.resultado === undefined ? '(ausente)' : String(item.resultado);
    if (!RESULTADOS_MUTACAO.includes(item.resultado)) {
      return `RECUSADO: ${onde} (tarefa ${item.tarefa}) tem resultado '${resultado}' — use ${RESULTADOS_MUTACAO.join(' ou ')}.\n`
        + `Bateria que fica VERDE com o conserto invertido nao prova nada: ela nao sabe\n`
        + `falhar, e por isso 'verde' nao e resposta aceita aqui.\n${COMO_DECLARAR}`;
    }
    if (item.resultado === 'n/a' && (typeof item.motivo !== 'string' || item.motivo.trim() === '')) {
      return `RECUSADO: ${onde} (tarefa ${item.tarefa}) e 'n/a' sem 'motivo'.\n`
        + `'n/a' aceito sem justificativa e so a palavra mais curta ate o exit 0, e a\n`
        + `catraca inteira morre na primeira pressa. Diga por que nao ha o que inverter.\n${COMO_DECLARAR}`;
    }
    if (item.resultado === 'vermelho' && (typeof item.fixture !== 'string' || item.fixture.trim() === '')) {
      if (!exigeFixture) {
        console.warn(
          `aviso: ${onde} (tarefa ${item.tarefa}) e 'vermelho' sem 'fixture' — divida herdada, ` +
          `a catraca deste fluxo foi armada em ${bloco.catraca_mutacao} e o campo passou a ser ` +
          `exigido em ${FIXTURE_EXIGIDA_DESDE}. Passa, mas a mutacao fica sem o caso que a exercita.`
        );
        continue;
      }
      return `RECUSADO: ${onde} (tarefa ${item.tarefa}) e 'vermelho' sem 'fixture'.\n`
        + `Bateria vermelha prova que ela sabe falhar, mas nao prova que ficou vermelha PELO\n`
        + `motivo certo: sem o caso nomeado, vermelho vindo de outro lugar passa por prova, e\n`
        + `veredito certo pelo motivo errado e pior que veredito errado.\n${COMO_DECLARAR}`;
    }
  }

  return null;
}

// --------------------------------- validação de evidência (comando e saida)
//
// Estágios de execução (`executar` e `verificar`) exigem que `comando` e `saida`
// estejam preenchidos (string não vazia e não só espaço) para fechar com ok.
// `revisar` e `fechar` não exigem esses campos. A validação vale para TODO
// fechamento com ok, sem exceção por idade. Estado antigo (JSONs sem os campos)
// continua legível — isso significa `exigir`/`proximo` não explodem, não que
// fechamento antigo passa sem evidência.

/** @returns {string|null} mensagem de recusa, ou null se passou/não se aplica */
function validarEvidenciaNoFechamento(estagio, extra) {
  // Só valida para os estágios que exigem
  if (!ESTAGIOS_EXIGEM_EVIDENCIA.includes(estagio)) return null;

  // Sem --json ou --json não é objeto, falta tudo
  if (!extra || typeof extra !== 'object') {
    return `RECUSADO: fechar '${estagio}' exige comando e saida no --json.\n`
      + `Presença é tudo — strings vazias ou só espaço não contam.\n`
      + `Exemplos:\n`
      + `  node scripts/estado.cjs marcar --slug <slug> --estagio ${estagio} --status ok --json '{"comando":"node x.cjs","saida":"ok: 3 casos"}'\n`
      + `  node scripts/estado.cjs marcar --slug <slug> --estagio ${estagio} --status ok --json '{"comando":"bash script.sh","saida":"resultado esperado"}'`;
  }

  const comando = extra.comando;
  const saida = extra.saida;

  // Ambos devem estar presentes e não vazios (permitindo espaço é furo)
  const comandoVazio = comando === undefined || comando === null || String(comando).trim() === '';
  const saidaVazio = saida === undefined || saida === null || String(saida).trim() === '';

  if (comandoVazio || saidaVazio) {
    const faltam = [];
    if (comandoVazio) faltam.push('comando');
    if (saidaVazio) faltam.push('saida');
    return `RECUSADO: fechar '${estagio}' exige ${faltam.join(' e ')} no --json.\n`
      + `Presença é tudo — strings vazias ou só espaço não contam.\n`
      + `Exemplos:\n`
      + `  node scripts/estado.cjs marcar --slug <slug> --estagio ${estagio} --status ok --json '{"comando":"node x.cjs","saida":"ok: 3 casos"}'\n`
      + `  node scripts/estado.cjs marcar --slug <slug> --estagio ${estagio} --status ok --json '{"comando":"bash script.sh","saida":"resultado esperado"}'`;
  }

  return null;
}

// ------------------------------------------------- trava de fechamento (D5)
//
// Fechar estágio roda a checagem correspondente do `conferir-fluxo.cjs`, e
// recusa com exit 2 se ela falhar. O motivo de a trava morar AQUI, e não numa
// instrução dentro da skill: enquanto o veredito for redigido pelo mesmo agente
// que ele deveria travar, ele não trava nada — é o mesmo argumento que fez este
// arquivo existir, e em 2026-08-13 ele se provou três vezes numa tarde, com um
// agente aprovando a própria entrega em três rodadas seguidas.
//
// `marcar` é o gargalo único por onde o fluxo inteiro já passa, e já recusava
// com exit 2 por pré-requisito aberto. A trava nova é a mesma forma, não
// mecanismo novo.
//
// **Só age quando o arquivo alvo existe.** Projeto que não usa design/plano não
// pode passar a ser barrado por uma checagem sobre arquivos que ele nunca teve —
// isso é invariante, não detalhe: a trava foi desenhada para apertar quem já
// está no fluxo, nunca para tornar o fluxo obrigatório.
const CHECADOR = path.join(__dirname, 'conferir-fluxo.cjs');

function docDe(tipo, slug) {
  return path.join(RAIZ, 'docs', 'rainforest', tipo, `${slug}.md`);
}

/**
 * Caminho REAL do doc de um estágio.
 *
 * O estado grava `arquivo` no bloco do estágio (`design.arquivo`,
 * `plano.arquivo`) quando o doc não se chama `<slug>.md` — e é o caso normal:
 * nenhum design deste repositório se chama assim (`fluxo-9-design-portaria.md`,
 * `fluxo-6-design-portoes.md`). Até 2026-09-02 `conferirFechamento` ignorava
 * esse campo e só olhava `docDe(tipo, slug)`.
 *
 * A consequência foi medida, não suposta: a checagem `cobertura` — a que prova
 * que toda decisão do design virou tarefa e que toda tarefa cita decisão real —
 * **nunca disparou**, porque exige que os DOIS caminhos derivados do slug
 * existam, e o do design nunca existia. Ela passou o fluxo 9 inteiro sem rodar
 * uma vez. Trava registrada, testada e inerte: o estado sabia onde o arquivo
 * estava, e o gate procurava noutro lugar.
 *
 * A ordem aqui é a mesma do `conferir-entrega.cjs`: perguntar onde a coisa está
 * antes de perguntar se ela passa.
 */
function docDoEstagio(tipo, slug, estado) {
  const bloco = estado && estado[tipo === 'planos' ? 'plano' : 'design'];
  if (bloco && typeof bloco.arquivo === 'string' && bloco.arquivo) {
    const declarado = path.resolve(
      path.isAbsolute(bloco.arquivo) ? bloco.arquivo : path.join(RAIZ, bloco.arquivo)
    );
    // CONFINADO à árvore do projeto. O `arquivo` vem de um campo de texto livre
    // do estado, e sem esta cerca um caminho absoluto (ou com `../`) aceitava
    // como design "aprovado" do fluxo um arquivo que nunca foi versionado — um
    // rascunho no temp, por exemplo. Não vira bypass de validação (a checagem
    // estrutural ainda roda contra ele), mas quebra a garantia que dá sentido ao
    // versionamento: o design que autorizou o trabalho tem de estar no repo, ou
    // ninguém depois consegue ler o que foi aprovado. Achado A3 da revisão de
    // 2026-09-02.
    // Por `realpath`, NÃO por comparação de string. `path.resolve` +
    // `startsWith` é teste LÉXICO: um symlink (ou junction, que no Windows
    // qualquer usuário cria sem privilégio) dentro da raiz apontando para fora
    // passa nele — o caminho declarado "parece" interno e o checador acaba
    // lendo o arquivo externo. Achado da auditoria cross-model (codex) em
    // 2026-09-02, sobre a primeira versão desta mesma cerca, que eu tinha
    // escrito no mesmo dia para fechar outro buraco.
    //
    // Os dois lados passam por `realpathSync`: comparar caminho resolvido com
    // raiz não-resolvida daria falso negativo em máquina cuja raiz já está sob
    // um link (o `/tmp` do macOS é o caso clássico).
    let real;
    let raizReal;
    try {
      real = fs.realpathSync(declarado);
      raizReal = fs.realpathSync(RAIZ);
    } catch (_) {
      // Caminho inexistente ou ilegível: não adota, cai no fallback. Recusar
      // aqui prenderia o estágio por um campo opcional.
      return docDe(tipo, slug);
    }
    const dentro = real === raizReal || real.startsWith(raizReal + path.sep);
    if (dentro) return real;
  }
  return docDe(tipo, slug);
}

/**
 * Caminho do arquivo de portões deste fluxo, ou null.
 *
 * Derivado do slug, sem campo novo no estado — decisão P1 do design do fluxo 6.
 * Portões são opt-in: fluxo sem este arquivo fecha exatamente como antes.
 */
function portoesDe(slug) {
  const p = path.join(RAIZ, 'docs', 'rainforest', 'portoes', `${slug}.md`);
  return fs.existsSync(p) ? p : null;
}

const PORTOES = path.join(__dirname, 'portoes.cjs');
const RECIBO = path.join(__dirname, 'recibo.cjs');

/**
 * Roda um dos checadores e devolve a recusa, ou null.
 *
 * Processo filho de propósito: a mensagem útil (qual decisão ficou órfã, que
 * arquivo não casou com glob nenhum, qual portão não cumpriu) já está no
 * checador, e reimplementá-la aqui criaria duas versões da mesma regra para
 * divergirem.
 */
function rodarChecador(exe, args, estagio) {
  const r = spawnSync(process.execPath, [exe, ...args], { stdio: 'inherit' });
  if (r.status === 0) return null;
  return `RECUSADO: '${estagio}' nao fecha enquanto a checagem acima nao passar.`;
}

/** @returns {string|null} mensagem de recusa, ou null se passou/não se aplica */
function conferirFechamento(estagio, slug, extra, estado) {
  if (!fs.existsSync(CHECADOR)) return null; // plugin antigo: não inventa trava

  // Os PORTÕES rodam em sequência com as checagens abaixo, não em vez delas.
  // Enquanto `conferirFechamento` foi uma cadeia `if/else if`, um estágio só
  // podia ter UMA checagem, e `plano` agora tem duas: `cobertura` e o lint dos
  // portões.
  //
  // As recusas se ACUMULAM em vez de retornarem na primeira. A versão anterior
  // retornava direto no lint, e com isso um plano que tivesse portão mal
  // autorado E decisão órfã só mostrava o segundo problema depois de a pessoa
  // consertar o primeiro e rodar de novo — duas idas para um fechamento. Nada
  // fechava indevidamente, mas "checagens independentes em sequência" era
  // promessa não cumprida: continuava uma cadeia, só que mais longa. Achado da
  // auditoria cross-model (codex) em 2026-09-02.
  const recusas = [];

  if (fs.existsSync(PORTOES)) {
    const arquivoPortoes = portoesDe(slug);
    if (arquivoPortoes) {
      if (estagio === 'plano') {
        const r = rodarChecador(PORTOES, ['lint', arquivoPortoes], estagio);
        if (r) recusas.push(r);
      } else if (estagio === 'verificar') {
        // O gate que o fluxo 6 existe para instalar: com portões declarados, a
        // evidência colada deixa de bastar. O `ok` só grava se os oráculos
        // re-executarem e passarem agora — não se alguém afirmar que passaram.
        //
        // `--reverificar` é OBRIGATÓRIO aqui, e isto foi achado usando o gate no
        // fechamento deste próprio fluxo. Sem a flag, `rodar` pula todo portão
        // que já tenha evidência gravada, e os seis saíram "cumprido (pulado)" —
        // o gate aprovou lendo o arquivo em vez de executar. Aceitar evidência
        // gravada é exatamente a evidência colada que os portões existem para
        // substituir, só em JSON em vez de prosa. É também a decisão D2 do
        // design ao contrário: "o arquivo não é a verdade; a execução é".
        const r = rodarChecador(PORTOES, ['rodar', arquivoPortoes, '--reverificar'], estagio);
        if (r) recusas.push(r);
      }
    }
  }

  // O gate do recibo roda SEMPRE quando recibo.cjs existe, mesmo sem portoes.md.
  // A decisão de opt-in (gravar apenas se há plano.entregaveis) mora dentro de
  // recibo.cjs, e este branch se limita a invocar — ver Tarefa 5 do fluxo 7.
  if (fs.existsSync(RECIBO) && estagio === 'fechar') {
    const r = rodarChecador(RECIBO, ['gravar', '--slug', slug, '--nao-provado', JSON.stringify((extra && extra.nao_provado) || [])], estagio);
    if (r) recusas.push(r);
  }

  let args = null;
  if (estagio === 'design' && fs.existsSync(docDoEstagio('design', slug, estado))) {
    args = ['design', '--slug', slug, '--design', docDoEstagio('design', slug, estado)];
  } else if (estagio === 'plano'
      && fs.existsSync(docDoEstagio('planos', slug, estado))
      // `cobertura` cruza os DOIS arquivos, então exigir só o plano prendia o
      // estágio para sempre num projeto que escreveu plano e nunca escreveu
      // design: o `marcar design aprovado` passava (sem design em disco não há o
      // que conferir) e o `plano ok` seguinte recusava com "design não existe",
      // sem saída nenhuma. Achado 1 da revisão de 2026-08-13, reproduzido antes
      // de consertar. A regra é: a trava só age quando **tudo que a checagem lê**
      // existe — checar a presença do arquivo do estágio não basta.
      && fs.existsSync(docDoEstagio('design', slug, estado))) {
    args = ['cobertura', '--slug', slug,
      '--design', docDoEstagio('design', slug, estado),
      '--plano', docDoEstagio('planos', slug, estado)];
  } else if (estagio === 'revisar' && fs.existsSync(docDoEstagio('planos', slug, estado))) {
    // Sem os dois pontos do diff não há como provar ausência de creep, e fechar
    // a revisão sem essa prova é exatamente o buraco que a decisão D4 fecha.
    const base = extra && extra.base;
    const head = extra && extra.head;
    if (!base || !head) {
      recusas.push(`RECUSADO: fechar 'revisar' exige 'base' e 'head' no --json.\n`
        + `Sem os dois pontos do diff nao ha como provar que o trabalho nao tocou\n`
        + `arquivo fora do plano. Ex.: --json '{"achados":0,"base":"<ref>","head":"<ref>"}'`);
      args = null;
    } else {
      args = ['creep', '--slug', slug, '--base', String(base), '--head', String(head),
        '--plano', docDoEstagio('planos', slug, estado)];
    }
  }

  if (args) {
    const r = rodarChecador(CHECADOR, args, estagio);
    if (r) recusas.push(r);
  }

  return recusas.length > 0 ? recusas.join('\n') : null;
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
  try {
    validarSlug(slug);
  } catch (err) {
    console.error(`erro: ${err.message}`);
    process.exit(1);
  }

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
    // Imprimir o bloco do reprovado pendente, se houver
    const e_reprovado = estagio_reprovado_pendente(estado);
    if (e_reprovado) {
      imprimirReprovado(estado, estado[e_reprovado].reaberto_por.estagio);
    }
    console.log(p);
    return;
  }

  if (cmd === 'exigir') {
    const estagio = arg('estagio');
    if (!(estagio in PRE_REQUISITOS)) {
      console.error(`erro: estagio desconhecido '${estagio}'`);
      process.exit(1);
    }

    // Teto de tentativas: se ESTE estágio foi reaberto e quem o reprovou já
    // acumulou TETO_TENTATIVAS, insistir precisa de decisão humana (liberar).
    const blocoExigido = estado[estagio] || {};
    if (blocoExigido.reaberto_por) {
      const estagio_reprovador = blocoExigido.reaberto_por.estagio;
      const bloco_reprovador = estado[estagio_reprovador] || {};
      const tentativas = bloco_reprovador.tentativas || 0;
      if (tentativas >= TETO_TENTATIVAS && !bloco_reprovador.liberado_em) {
        console.error(
          `RECUSADO: '${estagio_reprovador}' já reprovou ${tentativas} vez(es) — teto de ${TETO_TENTATIVAS} atingido. ` +
          `Suba a decisão ao usuário: ou o critério está errado (plano) ou a decisão está errada (design). ` +
          `Destrave explícito: node scripts/estado.cjs liberar --slug ${slug} --estagio ${estagio_reprovador}`
        );
        process.exit(2);
      }
    }

    // Verificar se há algum estágio de execução com reaberto_por preenchido
    // DIFERENTE do estágio sendo exigido. O próprio estágio reaberto PASSA aqui —
    // é o caminho de volta. A recusa vale só quando tentar exigir outro estágio
    // DE EXECUÇÃO enquanto há upstream reaberto pendente: `arqueologia`, `limpar`,
    // `design` e `plano` nunca são bloqueados por reprovação alheia (invariante do
    // plano do ciclo-por-máquina, pego por revisão em 2026-08-31 — a primeira
    // versão vazava a recusa para todo estágio de PRE_REQUISITOS).
    if (EXECUCAO.includes(estagio)) {
      const upstreamReaberto = EXECUCAO.find((e) => {
        if (e === estagio) return false; // permite exigir do próprio reaberto
        const bloco = estado[e] || {};
        return bloco.reaberto_por;
      });
      if (upstreamReaberto) {
        const bloco_upstream = estado[upstreamReaberto];
        console.error(
          `RECUSADO: '${upstreamReaberto}' foi reaberto por reprovação em '${bloco_upstream.reaberto_por.estagio}' ` +
          `(${bloco_upstream.reaberto_por.data}). Rode '${upstreamReaberto}' antes.`
        );
        process.exit(2);
      }
    }

    const falta = faltando(estado, estagio);
    if (!falta.length) {
      console.log(`ok: pre-requisitos de '${estagio}' fechados`);
      // Capturar snapshot ao exigir revisar, para detectar mutacao depois
      if (estagio === 'revisar') {
        const snapshot = capturarSnapshot();
        estado.revisar = { ...estado.revisar, snapshot };
        gravar(slug, estado);
        console.log(`snapshot capturado: HEAD=${snapshot.head.substring(0, 7)}, ${snapshot.caminhos_sujos.length} arquivo(s) sujo(s)`);
      }
      // Armar a catraca ao exigir executar. Este marcador e o unico jeito de
      // distinguir estagio aberto DEPOIS da catraca de estagio que ja estava em
      // andamento quando ela nasceu — o segundo so avisa (D10).
      if (estagio === 'executar') {
        estado.executar = { ...estado.executar, catraca_mutacao: hoje() };
        gravar(slug, estado);
        console.log("catraca armada: fechar este 'executar' com 'ok' vai exigir o campo 'mutacao' no --json.");
      }
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

  if (cmd === 'liberar') {
    const estagio = arg('estagio');
    if (!(estagio in PRE_REQUISITOS)) {
      console.error(`erro: estagio desconhecido '${estagio}'`);
      process.exit(1);
    }
    // Gravar liberado_em no bloco do estágio para destrava-lo uma vez
    estado[estagio] = { ...estado[estagio], liberado_em: hoje() };
    gravar(slug, estado);
    console.log(`${estagio}: liberado em ${hoje()}`);
    console.log(JSON.stringify(estado[estagio], null, 2));
    return;
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
    // Parsear JSON primeiro, antes de qualquer outra verificação
    let extra = {};
    const j = arg('json', false);
    if (j) {
      try {
        extra = JSON.parse(j);
      } catch (err) {
        console.error(`erro: --json nao e JSON valido: ${err.message}`);
        process.exit(1);
      }
      // Issue #148: `reaberto_por` é escrito pelo próprio estado.cjs ao reprovar
      // (objeto {estagio, data}). Vindo do --json chegava como texto livre, o
      // `exigir` lia `.estagio` de uma string e imprimia 'undefined'. Campo da
      // máquina não entra pela mão — e --json continua aceitando o resto.
      if (Object.prototype.hasOwnProperty.call(extra, 'reaberto_por')) {
        console.error("erro: 'reaberto_por' e preenchido pelo proprio estado.cjs ao reprovar — nao entra pelo --json (Issue #148)");
        process.exit(1);
      }
    }
    // Fechar um estágio com pré-requisito aberto é o furo que o arquivo existe para
    // impedir: sem isto, `marcar verificar ok` pularia a revisão inteira em silêncio.
    if (status === (FECHADO[estagio] || 'ok')) {
      const falta = faltando(estado, estagio);
      if (falta.length) {
        console.error(`RECUSADO: nao da para fechar '${estagio}' com ${falta.join(', ')} em aberto.`);
        process.exit(2);
      }
      // Issue #148: estágio a montante reaberto por reprovação barra o fechamento
      // deste — é a varredura que o `exigir` já fazia, e que só ele fazia. O
      // próprio estágio reaberto pode fechar (é assim que a reabertura se resolve).
      const reaberto = estagio_reprovado_pendente(estado);
      if (reaberto && reaberto !== estagio && EXECUCAO.indexOf(reaberto) < EXECUCAO.indexOf(estagio)) {
        const r = estado[reaberto].reaberto_por;
        console.error(`RECUSADO: '${reaberto}' foi reaberto por reprovação em '${r.estagio}' (${r.data}). Rode '${reaberto}' antes.`);
        process.exit(2);
      }
    }
    // Depois do `--json`, porque o `revisar` tira `base` e `head` de lá; e antes
    // do `gravar`, porque estado que já foi para o disco não desfecha.
    if (status === (FECHADO[estagio] || 'ok')) {
      // Verificar mutacao ANTES de conferirFechamento, porque é independente
      if (estagio === 'revisar') {
        const recusa_mutacao = verificarMutacao(slug, estado.revisar && estado.revisar.snapshot);
        if (recusa_mutacao) {
          console.error(recusa_mutacao);
          process.exit(2);
        }
      }
      // Só o fechamento `ok` cobra: `parcial` e `reprovado` nao passam por aqui,
      // e nao podem passar — quem entregou meio fluxo ou reprovou nao deve
      // ficar sem como registrar isso.
      if (estagio === 'executar') {
        const recusa_catraca = verificarCatracaMutacao(slug, estado.executar, estado, extra);
        if (recusa_catraca) {
          console.error(recusa_catraca);
          process.exit(2);
        }
      }
      // Validar evidência (comando e saida) para executar e verificar DEPOIS da catraca
      const recusa_evidencia = validarEvidenciaNoFechamento(estagio, extra);
      if (recusa_evidencia) {
        console.error(recusa_evidencia);
        process.exit(2);
      }
      // O gate tem de enxergar o `--json` DESTA chamada, não só o que já estava
      // gravado. Sem esta fusão, declarar `arquivo` no mesmo `marcar` que fecha
      // o estágio — que é a única forma de fazê-lo, porque `design` não tem
      // estado intermediário entre `pendente` e `aprovado` — deixava o gate
      // cego para o caminho declarado: ele caía no `docDe(tipo, slug)`, que não
      // existe, e a checagem estrutural nunca rodava. Exit 0, sem erro nem
      // aviso. Achado por revisão independente em 2026-09-02, reproduzido antes
      // de consertar: um design com uma linha de texto solto fechava como
      // `aprovado`, enquanto a MESMA checagem rodada à mão contra o MESMO
      // arquivo saía 2 com "seção obrigatória ausente".
      //
      // O `docDoEstagio` da tarefa 6 existia justamente para o caso do arquivo
      // fora do padrão `<slug>.md` — e sem esta linha ele não alcançava o único
      // momento em que esse caminho é declarado. A trava consertada continuava
      // inerte pelo uso real que a motivou.
      const estadoComExtra = {
        ...estado,
        [estagio]: { ...(estado[estagio] || {}), ...extra },
      };
      const recusa = conferirFechamento(estagio, slug, extra, estadoComExtra);
      if (recusa) {
        console.error(recusa);
        process.exit(2);
      }
    }
    // `campos efemeros` (pendentes) somem do bloco anterior quando o fechamento e
    // terminal-positivo e o --json novo nao os repete — ver `baseParaFundir` e o
    // comentario de `CAMPOS_EFEMEROS`. O resto do bloco anterior sobrevive normal.
    // `tentativas` e `liberado_em` também somem no `ok`, mas a lógica é manual aqui.
    const baseAnterior = baseParaFundir(estagio, estado[estagio], status, extra);
    const blocoNovo = { ...baseAnterior, ...extra, status, em: hoje() };

    // Quando um estágio é reprovado, incrementa o contador (DEPOIS de fundir com base)
    if (status === 'reprovado') {
      // Incrementar tentativas no bloco do estágio sendo reprovado, preservando valor anterior
      blocoNovo.tentativas = (blocoNovo.tentativas || 0) + 1;
      // `liberar` destrava UMA rodada: a reprovação seguinte re-arma o teto.
      // Sem isto, um liberar desarmava o teto para sempre (achado de revisão,
      // 2026-08-31) e o loop podia reprovar indefinidamente sem subir decisão.
      delete blocoNovo.liberado_em;
      // Auto-reprovação (reprovar o próprio `executar`) não rebaixa ninguém: o
      // rebaixamento seria sobrescrito por `estado[estagio] = blocoNovo` logo
      // abaixo, gravando mensagem de sucesso sem efeito (achado de revisão).
      if (upstreamImediato(estagio) !== estagio) {
        const upstream_reaberto = rebaixarUpstream(estado, estagio);
        if (upstream_reaberto) {
          console.log(`upstream '${upstream_reaberto}' reaberto por reprovação`);
        }
      }
    }
    // Limpar tentativas e liberado_em quando fecha com ok
    if (status === (FECHADO[estagio] || 'ok')) {
      delete blocoNovo.tentativas;
      delete blocoNovo.liberado_em;
    }
    estado[estagio] = blocoNovo;
    gravar(slug, estado);
    console.log(`${estagio}: ${status}`);
    const p = proximo(estado);
    console.log(p ? `proximo: ${p}` : 'completo');
    return;
  }

  console.error('uso: iniciar | ler | marcar | proximo | exigir | liberar | listar');
  process.exit(1);
}

if (require.main === module) main();
module.exports = { novo, proximo, faltando, estaFechado, EXECUCAO, PRE_REQUISITOS, DIR_ESTADO };
