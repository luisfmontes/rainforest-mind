// Prova de engine da recarga nas outras janelas (marcador do /plugins-em-dia, enxerto do
// wildz-data de Rafael Lopes): `claude plugin test <raiz>`. O engine carrega hooks/mod.tsx de
// verdade; por baixo respondem `fs.read`/`fs.write` (o installed_plugins.json e o marcador,
// escolhidos pelo caminho), `process.run` (localizador e CLI) e o relogio simulado.
import { test, expect, mock } from 'claude-code/testing'
import { textoMarcador } from './recarga-puro.mjs'

const CLAUDE_CMD = 'C:\\Users\\teste\\AppData\\Roaming\\npm\\claude.cmd'
const INICIO = 1760000000000
const SEG = 1000

const saida = (stdout: string, exitCode = 0) => ({
  value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'recusado', isStdoutTruncated: false, isStderrTruncated: false },
})

const registro = (versao: string) =>
  JSON.stringify({
    version: 2,
    plugins: {
      'rainforest-mind@rainforest-mind': [
        { scope: 'user', installPath: `<home>/plugins/cache/rainforest-mind/rainforest-mind/${versao}`, version: versao, installedAt: '2026-08-08T15:56:01.994Z', lastUpdated: '2026-10-09T13:47:15.749Z' },
      ],
    },
  })

// `versao` e a versao instalada; `sobe` diz se o `claude plugin update` a troca por 1.54.0.
async function montar($: any, on: any, env: Record<string, string> = {}) {
  const relogio = mock.clock(on, { now: INICIO })
  mock.store(on)
  mock.env(on, { CLAUDE_CONFIG_DIR: 'C:/ContaTeste', ...env })
  const s = { versao: '1.54.0', marcador: '', escritas: [] as { path: string; text: string }[], reloads: 0, toasts: [] as string[] }
  const ehMarcador = (p: unknown) => String(p).replace(/\\/g, '/').endsWith('/recarga-pedida.json')
  on('fs.read', async (_$: any, e: any) => ({ value: ehMarcador(e.path) ? s.marcador : registro(s.versao) }) as never)
  on('fs.write', async (_$: any, e: any) => {
    s.escritas.push({ path: String(e.path).replace(/\\/g, '/'), text: String(e.text) })
    if (ehMarcador(e.path)) s.marcador = String(e.text)
    return { value: undefined } as never
  })
  on('process.run', async (_$: any, e: any) => {
    if (/[\\/]system32[\\/]where\.exe$/i.test(String(e.argv[0]))) return e.argv.includes('claude.cmd') ? saida(`${CLAUDE_CMD}\r\n`) : saida('', 1)
    if (!/[\\/]system32[\\/]cmd\.exe$/i.test(String(e.argv[0]))) return saida('', 1)
    if (e.argv.includes('update') && e.argv.includes('rainforest-mind@rainforest-mind')) s.versao = '1.54.0'
    return saida('ok')
  })
  on('command.run', { command: 'reload-plugins' }, async () => {
    s.reloads += 1
    return { text: '' }
  })
  on('ui.toast', async (_$: any, e: any) => {
    s.toasts.push(String(e.text))
    return { value: undefined } as never
  })
  on('command.register', async (_$: any, e: any) => ({ value: { command: e.name } }) as never)
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('session.start', async (_$: any, e: any) => ({ cwd: e.cwd }))
  const comecar = async () => {
    await $.session.start({ cwd: '/projeto', surface: 'terminal', isInteractive: true })
    await relogio.settle()
  }
  const avisosDeOutra = () => s.toasts.filter(t => t.includes('outra janela')).length
  return { relogio, s, comecar, avisosDeOutra }
}

test('recarga: a rodada que sobe versao grava o marcador no caminho da conta', async ($, on) => {
  const { s } = await montar($, on)
  s.versao = '1.53.2'
  await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  const m = s.escritas.filter(w => w.path.endsWith('/recarga-pedida.json'))
  expect(m.length).toBe(1)
  expect(m[0].path).toBe('C:/ContaTeste/plugins/data/rainforest-mind-rainforest-mind/recarga-pedida.json')
  expect(JSON.parse(m[0].text).v).toBe(1)
  expect(typeof JSON.parse(m[0].text).at).toBe('number')
})

test('recarga: rodada sem versao nova nao grava marcador', async ($, on) => {
  const { s } = await montar($, on)
  await $.command.run({ command: 'plugins-em-dia', args: '' } as never)
  expect(s.escritas.length).toBe(0)
})

test('recarga: marcador de outra janela recarrega uma vez', { options: { recarregarSozinho: true } }, async ($, on) => {
  const { s, relogio, comecar } = await montar($, on)
  await comecar()
  expect(s.reloads).toBe(0)
  s.marcador = textoMarcador(INICIO + 2 * SEG) as string
  await relogio.advance(6 * SEG)
  expect(s.reloads).toBe(1)
  await relogio.advance(30 * SEG)
  expect(s.reloads).toBe(1)
  // um marcador mais novo age de novo
  s.marcador = textoMarcador(INICIO + 60 * SEG) as string
  await relogio.advance(10 * SEG)
  expect(s.reloads).toBe(2)
})

test('recarga: sem recarregarSozinho so avisa, uma vez por marcador', async ($, on) => {
  const { s, relogio, comecar, avisosDeOutra } = await montar($, on)
  await comecar()
  s.marcador = textoMarcador(INICIO + 2 * SEG) as string
  await relogio.advance(30 * SEG)
  expect(s.reloads).toBe(0)
  expect(avisosDeOutra()).toBe(1)
  expect(s.toasts.find(t => t.includes('outra janela'))).toContain('/reload-plugins')
})

test('recarga: marcador anterior a abertura nao faz nada', { options: { recarregarSozinho: true } }, async ($, on) => {
  const { s, relogio, comecar } = await montar($, on)
  s.marcador = textoMarcador(INICIO - 60 * SEG) as string
  await comecar()
  await relogio.advance(30 * SEG)
  expect(s.reloads).toBe(0)
})

test('recarga: RAINFOREST_RECARGA=off desliga', { options: { recarregarSozinho: true } }, async ($, on) => {
  const { s, relogio, comecar, avisosDeOutra } = await montar($, on, { RAINFOREST_RECARGA: 'off' })
  await comecar()
  s.marcador = textoMarcador(INICIO + 2 * SEG) as string
  await relogio.advance(30 * SEG)
  expect(s.reloads).toBe(0)
  expect(avisosDeOutra()).toBe(0)
})

test('recarga: a janela que gravou o marcador nao recarrega de novo por ele', { options: { recarregarSozinho: true } }, async ($, on) => {
  const { s, relogio, comecar } = await montar($, on)
  s.versao = '1.53.2'
  // a abertura roda a rodada: sobe, grava o marcador e recarrega pelo caminho de sempre (1 s)
  await comecar()
  expect(s.escritas.filter(w => w.path.endsWith('/recarga-pedida.json')).length).toBe(1)
  await relogio.advance(SEG)
  expect(s.reloads).toBe(1)
  await relogio.advance(30 * SEG)
  expect(s.reloads).toBe(1)
})
