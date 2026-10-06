// Mod da abertura (fluxo 2026-10-02-mod-regras-inteiras): as regras e a memoria entram
// como secao do system prompt, sem o teto de entrega do hook SessionStart. Toda a logica
// mora em ./abertura-mod-puro.mjs (testavel sem engine); aqui so se liga os hooks.
// Um modulo de mod com `import()` dinamico nao carrega: o import abaixo e estatico.
// O engine tambem recusa `$` passado como argumento: a logica recebe so tres funcoes
// tiradas dele, escritas no ponto de chamada.
import type { Register } from 'claude-code'
import { criarAbertura } from './abertura-mod-puro.mjs'

export const register: Register = on => {
  const abertura = criarAbertura()

  on('session.end', ($, e, next) => {
    abertura.aoEncerrar(e.reason)
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    const texto = await abertura.obter({
      rodar: (argv, init) => $.process.run(argv, init),
      cwd: () => $.session.cwd(),
      raiz: $.plugin.root,
    })
    return abertura.comSecao(r, texto)
  })

  on('classic.SessionStart', async ($, e, next) => {
    const r = await next(e)
    const texto = await abertura.obter({
      rodar: (argv, init) => $.process.run(argv, init),
      cwd: () => $.session.cwd(),
      raiz: $.plugin.root,
    })
    return abertura.semAbertura(r, texto)
  })

  // Conta com sec-default: o compose e o SessionStart sao barrados, entao a abertura
  // entra por `$.session.append` (ver o cabecalho de abertura-mod-puro.mjs). Sem
  // sec-default em `e.plugins`, nenhum dos hooks abaixo anexa nem le messages().
  on('engine.create', (_$, e, next) => {
    abertura.engineCriado(e.plugins)
    return next(e)
  })

  // Matcher em session.start e prompt.submit: mod.tsx registra os seus sem matcher, e o engine
  // recusa dois hooks do mesmo evento sem matcher. Aqui o matcher casa qualquer valor (/.*/).
  on('session.start', { cwd: /.*/ }, async ($, e, next) => {
    await abertura.aoIniciar(
      { rodar: (argv, init) => $.process.run(argv, init), cwd: () => $.session.cwd(), raiz: $.plugin.root },
      () => $.session.messages(),
      args => $.session.append(args),
    )
    return next(e)
  })

  on('prompt.submit', { text: /.*/ }, async ($, e, next) => {
    await abertura.aoSubmeter(
      { rodar: (argv, init) => $.process.run(argv, init), cwd: () => $.session.cwd(), raiz: $.plugin.root },
      () => $.session.messages(),
      args => $.session.append(args),
    )
    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    const r = await next(e)
    await abertura.aposCompactar(
      { rodar: (argv, init) => $.process.run(argv, init), cwd: () => $.session.cwd(), raiz: $.plugin.root },
      r,
      args => $.session.append(args),
    )
    return r
  })
}
