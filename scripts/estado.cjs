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
// `dispensada` fecha a arqueologia tanto quanto `ok`: as duas significam que
// alguem olhou e decidiu. Sao caminhos diferentes para o mesmo lugar.
const FECHA_TAMBEM = { arqueologia: ['ok', 'dispensada'] };
function estaFechado(estagio, bloco) {
  if (!bloco || typeof bloco !== 'object') return false;
  if (FECHA_TAMBEM[estagio]) return FECHA_TAMBEM[estagio].includes(bloco.status);
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
    arqueologia: { status: 'pendente' },
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
  // `arqueologia` fica FORA desta lista: se entrasse, todo projeto sem mapa
  // ficaria eternamente com "proximo: arqueologia", e o estagio opcional viraria
  // obrigatorio pela porta dos fundos.
  for (const e of ['design', 'plano', ...EXECUCAO]) {
    if (!estaFechado(e, estado[e])) return e;
  }
  return null;
}

function faltando(estado, estagio) {
  return (PRE_REQUISITOS[estagio] || []).filter((r) => !estaFechado(r, estado[r]));
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
// --status ok`, que e o gargalo unico por onde a esteira inteira ja passa —
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
//      Mesmo desenho do backstop acima: travar retroativo quebra esteira em
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

const COMO_DECLARAR = "Ex.: --json '{\"tarefas_ok\":2,\"tarefas\":2,\"mutacao\":["
  + '{"tarefa":1,"resultado":"vermelho"},'
  + '{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]}\'';

/**
 * Números das tarefas do plano, ou `null` quando não há plano em disco.
 *
 * A leitura é EMPRESTADA do `conferir-esteira.cjs`, não reescrita aqui. A primeira
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
    ({ extrairTarefas, lerMarkdown } = require('./conferir-esteira.cjs'));
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
  }

  return null;
}

// ------------------------------------------------- trava de fechamento (D5)
//
// Fechar estágio roda a checagem correspondente do `conferir-esteira.cjs`, e
// recusa com exit 2 se ela falhar. O motivo de a trava morar AQUI, e não numa
// instrução dentro da skill: enquanto o veredito for redigido pelo mesmo agente
// que ele deveria travar, ele não trava nada — é o mesmo argumento que fez este
// arquivo existir, e em 2026-08-13 ele se provou três vezes numa tarde, com um
// agente aprovando a própria entrega em três rodadas seguidas.
//
// `marcar` é o gargalo único por onde a esteira inteira já passa, e já recusava
// com exit 2 por pré-requisito aberto. A trava nova é a mesma forma, não
// mecanismo novo.
//
// **Só age quando o arquivo alvo existe.** Projeto que não usa design/plano não
// pode passar a ser barrado por uma checagem sobre arquivos que ele nunca teve —
// isso é invariante, não detalhe: a trava foi desenhada para apertar quem já
// está na esteira, nunca para tornar a esteira obrigatória.
const CHECADOR = path.join(__dirname, 'conferir-esteira.cjs');

function docDe(tipo, slug) {
  return path.join(RAIZ, 'docs', 'rainforest', tipo, `${slug}.md`);
}

/** @returns {string|null} mensagem de recusa, ou null se passou/não se aplica */
function conferirFechamento(estagio, slug, extra) {
  if (!fs.existsSync(CHECADOR)) return null; // plugin antigo: não inventa trava

  let args = null;
  if (estagio === 'design' && fs.existsSync(docDe('design', slug))) {
    args = ['design', '--slug', slug];
  } else if (estagio === 'plano'
      && fs.existsSync(docDe('planos', slug))
      // `cobertura` cruza os DOIS arquivos, então exigir só o plano prendia o
      // estágio para sempre num projeto que escreveu plano e nunca escreveu
      // design: o `marcar design aprovado` passava (sem design em disco não há o
      // que conferir) e o `plano ok` seguinte recusava com "design não existe",
      // sem saída nenhuma. Achado 1 da revisão de 2026-08-13, reproduzido antes
      // de consertar. A regra é: a trava só age quando **tudo que a checagem lê**
      // existe — checar a presença do arquivo do estágio não basta.
      && fs.existsSync(docDe('design', slug))) {
    args = ['cobertura', '--slug', slug];
  } else if (estagio === 'revisar' && fs.existsSync(docDe('planos', slug))) {
    // Sem os dois pontos do diff não há como provar ausência de creep, e fechar
    // a revisão sem essa prova é exatamente o buraco que a decisão D4 fecha.
    const base = extra && extra.base;
    const head = extra && extra.head;
    if (!base || !head) {
      return `RECUSADO: fechar 'revisar' exige 'base' e 'head' no --json.\n`
        + `Sem os dois pontos do diff nao ha como provar que o trabalho nao tocou\n`
        + `arquivo fora do plano. Ex.: --json '{"achados":0,"base":"<ref>","head":"<ref>"}'`;
    }
    args = ['creep', '--slug', slug, '--base', String(base), '--head', String(head)];
  }
  if (!args) return null;

  // Processo filho de propósito: a mensagem útil (qual decisão ficou órfã, que
  // arquivo não casou com glob nenhum) já está no checador, e reimplementá-la
  // aqui criaria duas versões da mesma regra para divergirem.
  const r = spawnSync(process.execPath, [CHECADOR, ...args], { stdio: 'inherit' });
  if (r.status === 0) return null;
  return `RECUSADO: '${estagio}' nao fecha enquanto a checagem acima nao passar.`;
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
      // e nao podem passar — quem entregou meia esteira ou reprovou nao deve
      // ficar sem como registrar isso.
      if (estagio === 'executar') {
        const recusa_catraca = verificarCatracaMutacao(slug, estado.executar, estado, extra);
        if (recusa_catraca) {
          console.error(recusa_catraca);
          process.exit(2);
        }
      }
      const recusa = conferirFechamento(estagio, slug, extra);
      if (recusa) {
        console.error(recusa);
        process.exit(2);
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
