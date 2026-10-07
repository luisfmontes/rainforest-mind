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
// CONTA COM sec-default (login org): o built-in `cc-plugin-sec-default` barra, por politica
// da organizacao, `prompt.compose` e `classic.SessionStart` de plugin tier user. O mod nao
// tenta entregar a abertura por outro canal: a abertura chega so pelo nucleo do SessionStart
// que o harness deixar passar. Regras inteiras ali pedem liberacao do admin da organizacao.
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
