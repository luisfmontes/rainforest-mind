'use strict';
/**
 * Fonte única de verdade do corpus sintético da bateria de utilidade
 * (scripts/testa-utilidade.sh) — Tarefa 13 do plano
 * docs/rainforest/planos/2026-09-23-memoria-sinal-de-utilidade.md (Emenda 4).
 *
 * Por que existe como arquivo próprio, e não inline no .sh: o transcrito
 * versionado (scripts/fixtures/utilidade/transcrito-sessao.jsonl) tem, no bloco
 * `## Memória (corpus residentes)`, linhas servidas formatadas por
 * `formatarObservacao`. Se essas linhas fossem digitadas à mão no .jsonl e as
 * observações correspondentes fossem digitadas à mão de novo (em bash, dentro
 * de testa-utilidade.sh) para popular o banco de cada caixa de teste, as duas
 * cópias divergiriam em silêncio na primeira edição de uma das duas — foi
 * exatamente esse tipo de drift que a Tarefa 13 existe para eliminar (a
 * bateria antiga lia banco/transcrito REAIS desta máquina, nunca duplicava
 * nada). Este módulo é a ÚNICA lista de observações: `popularBanco()` grava as
 * mesmas linhas que `transcrito-sessao.jsonl` cita como servidas, porque as
 * duas nascem do mesmo array `OBSERVACOES` abaixo.
 *
 * `transcrito-sessao.jsonl` foi gerado UMA VEZ com
 * `node scripts/fixtures/utilidade/gerar-banco.cjs --emitir-transcrito
 * scripts/fixtures/utilidade/transcrito-sessao.jsonl`. Se `OBSERVACOES` mudar
 * (novo termo raro, nova observação servida), regenere o fixture com o mesmo
 * comando antes de commitar — testa-utilidade.sh NUNCA chama
 * `--emitir-transcrito`, só `popularBanco()` (via `--popular`).
 *
 * cwd sintético: um caminho que deliberadamente NÃO existe em disco
 * (`CWD_FIXTURE` / `CWD_FIXTURE_BOGUS`) — `lerProjetoDoTranscrito` sobe a
 * árvore procurando `.git`, não encontra (caminho inexistente), e cai no
 * fallback "usa o cwd cru": `curto = basename(cwd)`, `harnessKey =
 * chaveHarness(cwd)`. Isso torna o rótulo de projeto 100% determinístico,
 * sem depender de onde o repositório está checked out (worktree, clone do
 * CI, máquina do Luís) — ao contrário de usar um diretório REAL como cwd, que
 * faria `curto` variar por ambiente. A única exceção fica na seção da Tarefa 9
 * dentro de testa-utilidade.sh, que testa a subida até um `.git` de verdade
 * usando o próprio checkout do repositório (`$SRC`), gerado à parte — nunca
 * este fixture.
 */

const path = require('path');
const { formatarObservacao } = require('../../../hooks/lib/memoria-sessao.cjs');
const { chaveHarness } = require('../../memoria.cjs');

// cwd sintético do "projeto próprio" — inexistente em disco de propósito
// (ver comentário acima). path.win32 explícito: o fixture é consumido por
// código que roda no Windows (baterias.yml é windows-latest), e formatar com
// separador `\` reproduz o que um transcrito real grava em `cwd`.
const CWD_FIXTURE = 'C:\\Projetos\\fixture-utilidade-proj';
const CWD_FIXTURE_BOGUS = 'C:\\Projetos\\projeto-que-nao-existe-forcado-t9';

const HARNESS_KEY = chaveHarness(CWD_FIXTURE);
const CURTO = path.win32.basename(CWD_FIXTURE);
const APELIDOS = { [HARNESS_KEY]: CURTO };

// Todas as servidas caem no mesmo dia — acharAlvo() filtra por
// `criada_em LIKE '<data>%'`, e o "pronto quando" da Tarefa 1 exige contagem
// independente das linhas `[AAAA-MM-DD ...]` do bloco.
const DATA_SERVIDAS = '2026-01-05';

// `origem` aqui é a coluna livre de `observacoes` (UNIQUE(projeto, origem)) —
// nada a ver com o `origem` de `uso_memoria` ('observacao'|'resumo').
//
// Termo comum ao corpus inteiro (df alto, > LIMIAR_DF=3): "corpusfiller",
// presente em TODAS as linhas abaixo — prova que um termo comum não pontua
// sozinho (D5) sem precisar do corpus isolado da seção 2c.
// Termos raros: um por observação servida/contrafactual, exclusivo dela (df=1)
// — dá para calcularNota() ter razão certa de raros presentes/total.
const OBSERVACOES = [
  // ---- servidas do projeto "próprio" (projeto = HARNESS_KEY) ----
  {
    origem: 'fx-servida-alfa',
    projeto: HARNESS_KEY,
    criadaEm: `${DATA_SERVIDAS}T09:00:00.000Z`,
    conteudo: 'titulo alfa corpusfiller\nsubtitulo alfa raroalfaunico',
    servida: true,
  },
  {
    origem: 'fx-servida-beta',
    projeto: HARNESS_KEY,
    criadaEm: `${DATA_SERVIDAS}T09:05:00.000Z`,
    conteudo: 'titulo beta corpusfiller\nsubtitulo beta rarobetaunico',
    servida: true,
  },
  {
    origem: 'fx-servida-gama',
    projeto: HARNESS_KEY,
    criadaEm: `${DATA_SERVIDAS}T09:10:00.000Z`,
    conteudo: 'titulo gama corpusfiller\nsubtitulo gama rarogamaunico',
    servida: true,
  },
  {
    origem: 'fx-servida-delta',
    projeto: HARNESS_KEY,
    criadaEm: `${DATA_SERVIDAS}T09:15:00.000Z`,
    conteudo: 'titulo delta corpusfiller\nsubtitulo delta rarodeltaunico',
    servida: true,
  },
  // ---- servida de OUTRO projeto, rótulo curto gravado direto (sem alias) —
  // reproduz o caso real descrito na Tarefa 11: uma linha servida de outro
  // projeto casa por id com QUALQUER rótulo (acharAlvo não filtra por
  // projeto, só compara o texto formatado; e como este `projeto` já é o nome
  // curto, nenhum apelido o traduz) — Tarefa 9/seção "servida sem id não
  // reaparece como não-servida" usa esta linha para provar
  // servidasComIdBogus < servidasComIdOriginal sem depender de sorte.
  {
    origem: 'fx-servida-outro-projeto',
    projeto: 'outro-proj',
    criadaEm: `${DATA_SERVIDAS}T09:20:00.000Z`,
    conteudo: 'titulo outro projeto corpusfiller\nsubtitulo outro rarooutrounico',
    servida: true,
  },

  // ---- contrafactual visado: termos que o texto da sessão usa (prompt e
  // tool_use) para que buscarContrafactual() ache candidato de verdade ----
  {
    origem: 'fx-contra-ferramenta',
    projeto: HARNESS_KEY,
    criadaEm: '2026-01-02T09:00:00.000Z',
    conteudo: 'titulo ferramenta corpusfiller\nsubtitulo comando raroferramentaunico',
    servida: false,
  },
  {
    origem: 'fx-contra-prompt',
    projeto: HARNESS_KEY,
    criadaEm: '2026-01-02T09:05:00.000Z',
    conteudo: 'titulo prompt corpusfiller\nsubtitulo extra raroprompttextounico',
    servida: false,
  },

  // ---- filler: só engordam o df de "corpusfiller" acima de LIMIAR_DF e dão
  // volume ao FTS; termos raros delas não aparecem no texto da sessão, então
  // não pontuam (nota=0) — presença ou ausência no contrafactual não afeta
  // nenhuma asserção da bateria. ----
  { origem: 'fx-filler-1', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:00:00.000Z', conteudo: 'titulo filler um corpusfiller\nsubtitulo fillerraroum', servida: false },
  { origem: 'fx-filler-2', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:05:00.000Z', conteudo: 'titulo filler dois corpusfiller\nsubtitulo fillerarodois', servida: false },
  { origem: 'fx-filler-3', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:10:00.000Z', conteudo: 'titulo filler tres corpusfiller\nsubtitulo fillerarotres', servida: false },
  { origem: 'fx-filler-4', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:15:00.000Z', conteudo: 'titulo filler quatro corpusfiller\nsubtitulo fillararoquatro', servida: false },
  { origem: 'fx-filler-5', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:20:00.000Z', conteudo: 'titulo filler cinco corpusfiller\nsubtitulo fillararocinco', servida: false },
  { origem: 'fx-filler-6', projeto: HARNESS_KEY, criadaEm: '2026-01-01T09:25:00.000Z', conteudo: 'titulo filler seis corpusfiller\nsubtitulo fillararoseis', servida: false },
];

// Linhas servidas, na formatação EXATA que a abertura grava (e que
// extrairSessao()/acharAlvo() têm que casar de volta) — computadas com a
// função de produção, nunca digitadas à mão.
const SERVIDAS = OBSERVACOES.filter((o) => o.servida);
const LINHAS_SERVIDAS = SERVIDAS.map((o) =>
  formatarObservacao({ conteudo: o.conteudo, projeto: o.projeto, criada_em: o.criadaEm }, APELIDOS)
);

/**
 * Grava as observações do corpus sintético na conexão já aberta (schema já
 * criado por quem chama — `criarSchema`/`garantirEsquema`, nunca duplicado
 * aqui). Idempotente por `origem` (UNIQUE(projeto, origem)) — pode rodar mais
 * de uma vez na mesma caixa sem duplicar linha.
 *
 * @param {object} conexao conexão DatabaseSync já aberta para escrita
 */
function popularBanco(conexao) {
  const insert = conexao.prepare(
    'INSERT OR IGNORE INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)'
  );
  for (const obs of OBSERVACOES) {
    insert.run(obs.projeto, obs.conteudo, obs.criadaEm, obs.origem);
  }
}

/**
 * Monta as linhas do transcrito sintético (uma por entrada do harness),
 * cobrindo exatamente o que a Tarefa 1 precisa provar: o attachment de
 * SessionStart com as servidas; um attachment de OUTRO hook (ignorado); um
 * prompt do usuário com os termos raros que dão nota à alfa/beta e ao
 * contrafactual do prompt; um tool_use cujo `input` carrega o termo raro do
 * contrafactual de ferramenta; uma prosa do assistente que ecoa a injeção
 * (tem que ficar de FORA do texto); e um tool_result (também de fora).
 *
 * Função pura — usada só para (re)gerar o fixture versionado, nunca pela
 * bateria em produção.
 *
 * @returns {object[]} entradas no formato do transcrito (.jsonl do harness)
 */
function construirEntradasTranscrito() {
  const additionalContext = [
    '## Memória (corpus residentes)',
    ...LINHAS_SERVIDAS,
    '',
    'mais: node scripts/memoria.cjs buscar --texto "<termo>"',
  ].join('\n');

  // Envelope comum a toda linha de um transcrito real (estrutura copiada por
  // leitura do transcrito mais recente desta máquina com "corpus residentes"
  // — nunca o conteúdo). `parentUuid`/`uuid` usam sufixo letra-dígito
  // misturado (nunca uma corrida de 4+ dígitos puros): o gate de publicação
  // (`scripts/conferir-publicacao.cjs`) reconhece forma de telefone em
  // sequências `\d{2}...9?\d{4}...\d{4}`, e um uuid "de verdade" (blocos hex
  // de 4/8/12 dígitos) casaria.
  const base = {
    parentUuid: null,
    isSidechain: false,
    uuid: 'fx-uuid-a1b2-linha',
    timestamp: '2026-01-05T09:00:00.000Z',
    userType: 'fixture',
    entrypoint: 'cli',
    cwd: CWD_FIXTURE,
    sessionId: 'fixture-sessao-utilidade',
    version: '0.0.0-fixture',
    gitBranch: 'fixture-branch',
  };

  return [
    // Attachment de outro hook (nunca SessionStart) — extrairSessao() tem que
    // ignorá-lo (não é servida, não é texto).
    {
      ...base,
      type: 'attachment',
      attachment: {
        type: 'hook',
        hookName: 'fixture-hook-irrelevante',
        hookEvent: 'PostToolUse',
        toolUseID: 'fixture-tool-1',
        content: null,
        stdout: JSON.stringify({ ok: true }),
        stderr: '',
        exitCode: 0,
        command: 'node hooks/fixture-hook-irrelevante.cjs',
        durationMs: 8,
      },
    },
    // Attachment de SessionStart — é daqui que vêm as servidas (D3, D8).
    {
      ...base,
      type: 'attachment',
      attachment: {
        type: 'hook',
        hookName: 'memoria-session-start',
        hookEvent: 'SessionStart',
        toolUseID: null,
        content: null,
        stdout: JSON.stringify({
          hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext },
          systemMessage: '',
        }),
        stderr: '',
        exitCode: 0,
        command: 'node hooks/memoria-session-start.cjs',
        durationMs: 12,
      },
    },
    // Linha de tipo desconhecido do extrator — cobre o `continue` genérico.
    { ...base, type: 'system', message: { content: 'fixture: linha de sistema, fora do texto' } },
    // Prompt do usuário: MARCADORPROMPTUNICO prova a seção "prosa não entra"
    // (o prompt ENTRA); raroalfaunico/rarobetaunico dão nota às servidas
    // alfa/beta; raroprompttextounico alimenta o contrafactual do prompt.
    {
      ...base,
      type: 'user',
      promptId: 'fx-prompt-um',
      message: {
        role: 'user',
        content:
          'MARCADORPROMPTUNICO investigar raroalfaunico e rarobetaunico, ligado a raroprompttextounico',
      },
    },
    // tool_use do assistente: o `input` ENTRA no texto (raroferramentaunico
    // alimenta o contrafactual de ferramenta; MARCADORFERRAMENTAUNICO prova
    // que tool_use entra).
    {
      ...base,
      type: 'assistant',
      message: {
        model: 'fixture-model',
        id: 'fx-msg-tool-use',
        type: 'message',
        role: 'assistant',
        content: [
          {
            type: 'tool_use',
            id: 'fixture-tool-1',
            name: 'Bash',
            input: { command: 'echo MARCADORFERRAMENTAUNICO raroferramentaunico' },
          },
        ],
        stop_reason: 'tool_use',
      },
    },
    // tool_result: NUNCA é prompt do usuário — fica de fora do texto mesmo
    // vindo dentro de uma mensagem `user`.
    {
      ...base,
      type: 'user',
      message: {
        role: 'user',
        content: [
          {
            type: 'tool_result',
            tool_use_id: 'fixture-tool-1',
            content: 'MARCADORRESULTADOUNICO',
            is_error: false,
          },
        ],
      },
    },
    // Prosa do assistente que ECOA a injeção (repete "alfa corpusfiller" e o
    // termo raroalfaunico) — tem que ficar de FORA do texto (D4): é
    // exatamente o que a mutação da Tarefa 1 teria que fazer passar.
    {
      ...base,
      type: 'assistant',
      message: {
        model: 'fixture-model',
        id: 'fx-msg-prosa',
        type: 'message',
        role: 'assistant',
        content: [
          {
            type: 'text',
            text:
              'MARCADORPROSAUNICO resumindo: a observação titulo alfa corpusfiller com raroalfaunico ' +
              'foi a que usei, e rarogamaunico também parece relevante.',
          },
        ],
        stop_reason: 'end_turn',
      },
    },
  ];
}

function emitirTranscrito(destino) {
  const fs = require('fs');
  const linhas = construirEntradasTranscrito().map((l) => JSON.stringify(l));
  fs.writeFileSync(destino, linhas.join('\n') + '\n');
  return linhas.length;
}

module.exports = {
  CWD_FIXTURE,
  CWD_FIXTURE_BOGUS,
  HARNESS_KEY,
  CURTO,
  APELIDOS,
  DATA_SERVIDAS,
  OBSERVACOES,
  LINHAS_SERVIDAS,
  popularBanco,
  construirEntradasTranscrito,
  emitirTranscrito,
};

if (require.main === module) {
  const args = process.argv.slice(2);
  const iEmitir = args.indexOf('--emitir-transcrito');
  if (iEmitir !== -1) {
    const destino = args[iEmitir + 1];
    if (!destino) {
      console.error('Uso: node gerar-banco.cjs --emitir-transcrito <destino.jsonl>');
      process.exit(1);
    }
    const n = emitirTranscrito(destino);
    console.log(`ok: ${n} linhas escritas em ${destino}`);
  } else if (args.includes('--popular')) {
    // Chamador real: scripts/testa-utilidade.sh, função preparar_caixa_utilidade
    // (`RFM_ROOT=<caixa> node scripts/fixtures/utilidade/gerar-banco.cjs
    // --popular`, depois de `$MEMORIA iniciar` já ter criado o schema).
    const { abrirBanco, criarSchema, resolverCaminhos } = require('../../memoria.cjs');
    const { caminhoDb } = resolverCaminhos();
    const conexao = abrirBanco(caminhoDb);
    criarSchema(conexao); // idempotente — cobre também o uso direto, sem `iniciar` antes
    popularBanco(conexao);
    conexao.close();
    console.log(`ok: banco populado em ${caminhoDb}`);
  } else {
    console.error('Uso: node gerar-banco.cjs --emitir-transcrito <destino.jsonl> | --popular (com RFM_ROOT)');
    process.exit(1);
  }
}
