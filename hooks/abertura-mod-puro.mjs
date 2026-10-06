// Logica do mod da abertura, pura: ES module sem Node. Nao recebe o `$`: o engine nao
// aceita `$` passado como argumento (so `$.substantivo.evento(...)` no ponto de chamada,
// medido por `claude plugin validate`). Recebe `io`, tres funcoes que `register.ts` tira
// do `$`. `register.ts` so liga os tres hooks a ela; a bateria
// `hooks/testa-mod-abertura.cjs` carrega o proprio register.ts com um `$` falso.
//
// O que o mod faz: monta UMA vez por sessao a abertura (foco com as regras + memoria)
// rodando os dois geradores com `--destino mod`, acrescenta o texto como a secao
// `rainforest-mind:abertura` do system prompt (sem o teto de entrega do hook
// SessionStart) e tira do `classic.SessionStart` as entradas dos mesmos dois hooks, para
// o modelo nao receber a abertura duas vezes. Por que o canal e o prompt, e nao o hook,
// esta em hooks/abertura-mod.json e nos geradores.
//
// CONTA COM sec-default (login org): o built-in `cc-plugin-sec-default` faz bypass de
// `prompt.compose` e de `classic.SessionStart` de plugin tier user, entao a secao acima
// nao chega. Ai o mod entrega o MESMO texto da montagem memoizada (sem rodar os geradores
// de novo) como uma mensagem de usuario, via `$.session.append`: `engine.create` guarda a
// flag `barraCompose(e.plugins)`; com a flag, `session.start` anexa se o transcript nao
// tem a MARCA (`temMarca`, cobre o --resume), o primeiro `prompt.submit` depois de um
// `session.end` com reason clear anexa uma vez (nao ha session.start depois do /clear) e
// `session.compact` reanexa se as mensagens devolvidas perderam a MARCA. O nucleo do
// SessionStart fica como esta. Sem a flag nada disso roda: nenhum append, nenhuma leitura
// de messages(). Desenho: docs/rainforest/design/2026-10-06-regras-inteiras-conta-org.md.
//
// FALHA ABERTA: se a montagem falha (gerador com exit != 0, JSON invalido, timeout,
// additionalContext ausente), a secao nao e acrescentada E nenhuma entrada do
// SessionStart e removida. A sessao nunca fica sem as regras: no pior caso elas chegam
// pelo canal de sempre.

/**
 * @typedef {{
 *   rodar: (argv: string[], init: object) => Promise<any>,
 *   cwd: () => Promise<string>,
 *   raiz: string,
 * }} Io
 */

export const ID_SECAO = 'rainforest-mind:abertura';

// Primeira linha da mensagem anexada na conta com sec-default; `temMarca` a procura no
// transcript. Nao comeca por nenhum dos PREFIXOS: o filtro do SessionStart nao a toca.
export const MARCA = '[rainforest-mind:abertura]';

// 60 s: o hook do foco ja levou 6 a 8 s (issue #243); o teto padrao do `$.process.run`
// e 30 s.
export const TIMEOUT_MS = 60000;

export const GERADORES = [
  { nome: 'foco', script: 'foco-session-start.cjs', obrigatorio: true },
  { nome: 'memoria', script: 'memoria-session-start.cjs', obrigatorio: false },
];

// Como o additionalContext de cada hook COMECA. Sao os textos reais emitidos hoje
// (hooks/lib/contexto-sessao.cjs e hooks/lib/memoria-sessao.cjs); a bateria os confere
// contra a saida real dos geradores. Entrada que nao comeca por um destes fica: o
// filtro so remove o que reconhece, e o `codex-transfer-session-start.cjs` (que tambem
// escreve no SessionStart) nunca casa.
export const PREFIXOS_FOCO = [
  'RAINFOREST MIND ATIVO',
  '⚠️ **FALHA AO CARREGAR AS REGRAS',
  '⚠️ **INJEÇÃO ACIMA DO ORÇAMENTO',
];
export const PREFIXOS_MEMORIA = [
  '## Memória (corpus residentes)',
  '⚠️ Memória acima do orçamento',
  '⚠️ Captura da memória parada',
  '⚠️ Manutenção da memória falhou',
];
const PREFIXOS = [...PREFIXOS_FOCO, ...PREFIXOS_MEMORIA];

/**
 * Texto de uma mensagem: `text` de `$.session.messages()`, ou `content` (string ou
 * blocos `{ type: 'text', text }`) de `SessionCompacted.messages`.
 * @param {any} m
 * @returns {string}
 */
function textoDe(m) {
  if (!m) return '';
  if (typeof m.text === 'string' && m.text) return m.text.trimStart();
  const c = m.content;
  if (typeof c === 'string') return c.trimStart();
  if (!Array.isArray(c)) return '';
  const ts = c
    .filter((/** @type {any} */ b) => b && b.type === 'text' && typeof b.text === 'string')
    .map((/** @type {any} */ b) => b.text.trimStart());
  // No --resume (forma api) a linha anexada vem FUNDIDA como um bloco no meio do primeiro
  // item user, depois de blocos <system-reminder>: o join comecaria pelo reminder.
  return ts.find(t => t.startsWith(MARCA)) ?? ts.join('').trimStart();
}

/** @param {readonly any[] | null | undefined} mensagens */
export function temMarca(mensagens) {
  return (mensagens ?? []).some(m => textoDe(m).startsWith(MARCA));
}

/** @param {readonly string[]} nomes */
export function barraCompose(nomes) {
  return nomes.includes('cc-plugin-sec-default');
}

/** @param {unknown} texto */
export function ehEntradaDaAbertura(texto) {
  if (typeof texto !== 'string') return false;
  const t = texto.trimStart();
  return PREFIXOS.some(p => t.startsWith(p));
}

/**
 * Roda um gerador e devolve o `additionalContext` dele. Lanca em qualquer falha.
 * @param {Io} io
 * @param {string} cwd
 * @param {{ nome: string, script: string, obrigatorio: boolean }} g
 * @returns {Promise<string>}
 */
async function gerar(io, cwd, g) {
  const script = `${io.raiz}/hooks/${g.script}`;
  const r = await io.rodar(['node', script, '--destino', 'mod'], {
    cwd: io.raiz,
    env: { CLAUDE_PROJECT_DIR: cwd },
    timeoutMs: TIMEOUT_MS,
  });
  if (r.exitCode !== 0) throw new Error(`${g.nome}: exit ${r.exitCode}`);
  if (r.isStdoutTruncated) throw new Error(`${g.nome}: saida truncada`);
  const ctx = JSON.parse(r.stdout)?.hookSpecificOutput?.additionalContext;
  if (typeof ctx !== 'string') throw new Error(`${g.nome}: sem additionalContext`);
  if (g.obrigatorio && !ctx.trim()) throw new Error(`${g.nome}: additionalContext vazio`);
  return ctx.trim();
}

/**
 * Monta o texto da secao: additionalContext do foco, depois o da memoria, sem os
 * systemMessage. `null` quando qualquer gerador falha.
 * @param {Io} io
 * @returns {Promise<string | null>}
 */
async function montar(io) {
  try {
    const cwd = await io.cwd();
    const partes = await Promise.all(GERADORES.map(g => gerar(io, cwd, g)));
    const texto = partes.filter(Boolean).join('\n\n');
    return texto || null;
  } catch {
    return null;
  }
}

/**
 * Um estado por mod carregado: a promessa da montagem. Memoizar a PROMESSA (e nao o
 * texto) resolve a ordem dos eventos: o `classic.SessionStart` pode chegar antes do
 * primeiro `prompt.compose`, e os dois esperam a mesma montagem em vez de rodar os
 * geradores duas vezes, e o filtro do SessionStart so age sabendo que ela deu certo.
 */
export function criarAbertura() {
  /** @type {Promise<string | null> | null} */
  let memo = null;
  // Conta com sec-default (engine.create) e `/clear` ainda sem a abertura reanexada.
  let barra = false;
  let pendente = false;

  /**
   * Anexa a abertura como mensagem de usuario. Nunca lanca; texto null, nao anexa.
   * @param {Io} io
   * @param {() => Promise<readonly any[] | null | undefined>} ler  transcript a conferir
   * @param {(args: any) => Promise<any>} escrever
   */
  async function anexar(io, ler, escrever) {
    try {
      const texto = await (memo ?? (memo = montar(io)));
      if (!texto) return;
      if (temMarca(await ler())) return;
      await escrever({ message: { type: 'user', content: [{ type: 'text', text: `${MARCA}\n${texto}` }] } });
    } catch {
      // falha aberta: sem append, a sessao segue
    }
  }

  return {
    /**
     * A montagem (uma por abertura).
     * @param {Io} io
     */
    obter(io) {
      if (memo) return memo;
      memo = montar(io);
      return memo;
    },

    /** `/clear` e `/resume` encerram a conversa sem `session.start`: a proxima abertura e remontada. */
    aoEncerrar(/** @type {string} */ reason) {
      if (reason === 'clear' || reason === 'resume') memo = null;
      if (reason === 'clear') pendente = true;
    },

    /** `engine.create`: liga o caminho do append so na conta em que o compose e barrado. */
    engineCriado(/** @type {unknown} */ plugins) {
      barra = barraCompose(Array.isArray(plugins) ? plugins : []);
    },

    /** `session.start`: anexa se o transcript nao tem a MARCA. */
    async aoIniciar(/** @type {Io} */ io, /** @type {() => Promise<any>} */ ler, /** @type {(args: any) => Promise<any>} */ escrever) {
      if (barra) await anexar(io, ler, escrever);
    },

    /** `prompt.submit`: depois de um /clear, anexa uma vez e desarma a pendencia. */
    async aoSubmeter(/** @type {Io} */ io, /** @type {() => Promise<any>} */ ler, /** @type {(args: any) => Promise<any>} */ escrever) {
      if (!barra || !pendente) return;
      pendente = false;
      await anexar(io, ler, escrever);
    },

    /** `session.compact`: `r` e o resultado de next(e); reanexa se as mensagens devolvidas perderam a MARCA. */
    async aposCompactar(/** @type {Io} */ io, /** @type {any} */ r, /** @type {(args: any) => Promise<any>} */ escrever) {
      if (!barra || !Array.isArray(r?.messages)) return;
      await anexar(io, async () => r.messages, escrever);
    },

    /** Resultado do `prompt.compose` com a secao no fim; `r` intacto sem texto. */
    comSecao(/** @type {any} */ r, /** @type {string | null} */ texto) {
      if (!texto || !r || !Array.isArray(r.sections)) return r;
      if (r.sections.some((/** @type {any} */ s) => s.id === ID_SECAO)) return r;
      return { ...r, sections: [...r.sections, { id: ID_SECAO, text: texto, scope: 'session' }] };
    },

    /** Resultado do `classic.SessionStart` sem as entradas da abertura; `r` intacto sem texto. */
    semAbertura(/** @type {any} */ r, /** @type {string | null} */ texto) {
      if (!texto || !r || !Array.isArray(r.additionalContext)) return r;
      const ficam = r.additionalContext.filter((/** @type {any} */ x) => !ehEntradaDaAbertura(x));
      if (ficam.length === r.additionalContext.length) return r;
      return { ...r, additionalContext: ficam };
    },
  };
}
