// Plugins em dia (/plugins-em-dia): atualiza dentro da sessao os plugins da lista da opcao
// `plugins` e, se algum subir de versao, recarrega (opcao `recarregarSozinho`) ou avisa.
// A logica pura (alvos, ordem dos comandos, versoes, janela de intervalo, acao) mora em
// ./plugins-em-dia-puro.mjs; aqui so se liga os eventos. O engine so aceita `$` passado a
// funcao declarada no topo deste arquivo; aos `.mjs` vao so valores.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { escolherExecutavel, interpretadorDeLote, localizadores } from './pr-puro.mjs'
import { LISTA_PADRAO, PERIODO_MS, acaoAposSubir, alvos, comandos, podeRodar, subiram, versoes } from './plugins-em-dia-puro.mjs'
import { caminhoMarcador, deveRecarregar, textoMarcador } from './recarga-puro.mjs'

const claudeCaminho = atom({ plugin: 'rainforest-mind', key: 'pluginsEmDiaClaude' } as const, '')

// Recarga nas outras janelas (enxerto do marcador do wildz-data, de Rafael Lopes): a janela que
// atualiza grava o marcador; cada janela confere a cada 5 s e age uma vez por marcador mais novo
// que o carregamento deste modulo. Estado de modulo: o /reload-plugins recarrega o modulo e o
// carregadoEm passa do marcador.
// caminho e desligada sao lidos uma vez, na abertura: a conferencia de 5 s faz so o fs.read.
type Recarga = { carregadoEm: number; tratadoEm: number | null; ocupado: boolean; recarregaSeguro: boolean; caminho: string; desligada: boolean }
const CONFERIR_RECARGA_MS = 5000

type Registro = { plugins?: Record<string, { scope: string; version: string }[]> }

const listaDe = (valor: unknown): string[] => {
  const itens = Array.isArray(valor) ? valor : typeof valor === 'string' ? valor.split(',') : []
  const lista = itens.map(x => String(x).trim()).filter(x => x.includes('@'))
  return lista.length > 0 ? lista : [...LISTA_PADRAO]
}

function avisar($: EngineInterface, texto: string): void {
  void Promise.resolve($.ui.toast(texto)).catch(() => {})
}

// Caminho absoluto do executavel do CLI, achado UMA vez por sessao e fora do repositorio da
// sessao: o Windows procura o executavel primeiro na pasta atual. O localizador roda na pasta
// do plugin (confiavel), nunca no repo.
async function caminhoDoCli($: EngineInterface): Promise<string | null> {
  const guardado = await read($, claudeCaminho)
  if (guardado !== '') return guardado
  let cwd = ''
  try {
    cwd = await $.session.cwd()
  } catch {
    cwd = ''
  }
  for (const argv of localizadores('claude', await raizDoWindows($)) as string[][]) {
    try {
      const r = await $.process.run(argv, { cwd: $.plugin.root, timeoutMs: 10_000 })
      if (r.exitCode !== 0) continue
      const achado = escolherExecutavel(r.stdout, cwd) as string | null
      if (achado !== null) {
        await update($, claudeCaminho, () => achado)
        return achado
      }
    } catch {
      // este localizador nao existe nesta maquina; o outro tenta
    }
  }
  return null
}

async function caminhoDoMarcador($: EngineInterface): Promise<string> {
  const CLAUDE_CONFIG_DIR = await $.env.get('CLAUDE_CONFIG_DIR')
  const HOME = (await $.env.get('USERPROFILE')) || (await $.env.get('HOME'))
  return caminhoMarcador({ CLAUDE_CONFIG_DIR, HOME }) as string
}

// Grava o marcador para as outras janelas; esta ja trata a si mesma pelo caminho de sempre.
async function gravarMarcador($: EngineInterface, recarga: Recarga): Promise<void> {
  try {
    const at = await $.clock.now()
    recarga.tratadoEm = at
    await $.fs.write(await caminhoDoMarcador($), textoMarcador(at) as string)
  } catch {
    // sem marcador as outras janelas seguem sem saber; a rodada desta segue igual
  }
}

async function conferirRecarga($: EngineInterface, recarga: Recarga): Promise<void> {
  if (recarga.ocupado) return
  recarga.ocupado = true
  try {
    if (recarga.desligada || recarga.caminho === '') return
    let marcador: string
    try {
      marcador = await $.fs.read(recarga.caminho)
    } catch {
      return
    }
    const at = deveRecarregar({ marcador, carregadoEm: recarga.carregadoEm, tratadoEm: recarga.tratadoEm }) as number | null
    if (at === null) return
    recarga.tratadoEm = at
    if (recarga.recarregaSeguro) await $.command.run({ command: 'reload-plugins' })
    else avisar($, 'plugins atualizados em outra janela - rode /reload-plugins')
  } catch {
    // falha aberta: a proxima conferencia tenta de novo
  } finally {
    recarga.ocupado = false
  }
}

async function atualizar($: EngineInterface, lista: string[], recarregaSeguro: boolean, forcado: boolean, recarga: Recarga): Promise<string> {
  const agora = await $.clock.now()
  const ultima = Number((await $.store.get('ultima')) ?? 0)
  if (!podeRodar(ultima, agora, forcado)) return 'pulado: rodou ha menos de 30 min'
  await $.store.set('ultima', agora)

  let caminho: string
  let antes: Record<string, string>
  let ids: string[]
  try {
    const dir = (await $.env.get('CLAUDE_CONFIG_DIR')) || `${(await $.env.get('USERPROFILE')) || (await $.env.get('HOME'))}/.claude`
    caminho = `${dir}/plugins/installed_plugins.json`
    const registro = JSON.parse(await $.fs.read(caminho)) as Registro
    ids = alvos(registro, lista)
    antes = versoes(registro, ids)
  } catch {
    return 'sem installed_plugins.json legivel; nada feito'
  }
  if (ids.length === 0) return 'nenhum plugin da lista instalado no escopo user'

  const cli = await caminhoDoCli($)
  if (cli === null) {
    avisar($, 'plugins-em-dia: claude nao encontrado fora do repositorio')
    return 'claude nao encontrado fora do repositorio; nada feito'
  }
  // No Windows o executavel do npm e um shim .cmd/.bat: sem shell o sistema nao o executa direto.
  const prefixo = /\.(cmd|bat)$/i.test(cli) ? [interpretadorDeLote(await raizDoWindows($)), '/d', '/c', cli] : [cli]

  const falhas: string[] = []
  for (const argv of comandos(ids) as string[][]) {
    const r = await $.process.run([...prefixo, ...argv], { cwd: $.plugin.root, timeoutMs: 120_000 }).catch(() => ({ exitCode: -1 }))
    if (r.exitCode !== 0) falhas.push(`${argv.slice(1, 3).join(' ')} ${argv[3] ?? ''}`.trim() + ` (exit ${r.exitCode})`)
  }

  let depois = antes
  try {
    depois = versoes(JSON.parse(await $.fs.read(caminho)) as Registro, ids)
  } catch {
    // sem a segunda leitura, nada se pode dizer que subiu
  }
  const subidas = subiram(antes, depois) as string[]
  const resumo = subidas.join(', ')
  const falhou = falhas.length > 0 ? ` | falhou: ${falhas.join(', ')}` : ''

  const acao = acaoAposSubir(subidas, recarregaSeguro) as string
  if (subidas.length > 0) await gravarMarcador($, recarga)
  if (acao === 'nada') {
    if (falhas.length > 0) avisar($, `plugins-em-dia${falhou}`)
    return `tudo em dia (${ids.map(id => `${id.split('@')[0]} ${antes[id]}`).join(', ')})${falhou}`
  }
  if (acao === 'recarregar') {
    // O host recusa `$.command.run` de dentro de um hook de `command.run` (ele esperaria o turno
    // que o proprio hook segura): o recarregamento sai de um evento posterior, o timer de 1 s.
    void $.clock.after(1000, () => {
      void Promise.resolve($.command.run({ command: 'reload-plugins' }))
        .then(() => avisar($, `plugins atualizados e recarregados: ${resumo}${falhou}`))
        .catch(() => avisar($, `plugins atualizados: ${resumo} - rode /reload-plugins${falhou}`))
    })
    return `atualizados: ${resumo}; recarregando em 1 s${falhou}`
  }
  avisar($, `plugins atualizados: ${resumo} - rode /reload-plugins${falhou}`)
  return `atualizados: ${resumo}; rode /reload-plugins para valer na sessao${falhou}`
}

export const register: Register = (on, options) => {
  const lista = listaDe(options.plugins)
  const recarregaSeguro = options.recarregarSozinho === true
  const recarga: Recarga = { carregadoEm: Number.POSITIVE_INFINITY, tratadoEm: null, ocupado: false, recarregaSeguro, caminho: '', desligada: false }

  on('session.start', { isInteractive: true }, async ($, e, next) => {
    try {
      await $.command.register({
        name: 'plugins-em-dia',
        description: 'Atualiza agora os plugins da lista e avisa (ou recarrega) se subir versao',
      })
    } catch {
      // sem comando, a rodada automatica segue
    }
    const rodada = () => void atualizar($, lista, recarregaSeguro, false, recarga).catch(() => {})
    try {
      recarga.carregadoEm = await $.clock.now()
      // RAINFOREST_RECARGA=off desliga a recarga vinda de outra janela (o kill switch do Rafael).
      recarga.desligada = (await $.env.get('RAINFOREST_RECARGA')) === 'off'
      recarga.caminho = await caminhoDoMarcador($)
    } catch {
      // sem relogio ou sem caminho nao ha como conferir: a conferencia fica parada
    }
    rodada()
    $.clock.every(PERIODO_MS, rodada)
    // Desligada (ou sem caminho), nem o timer existe: zero disparos.
    if (!recarga.desligada && recarga.caminho !== '') $.clock.every(CONFERIR_RECARGA_MS, () => void conferirRecarga($, recarga))
    return next(e)
  })

  on('command.run', { command: 'plugins-em-dia' }, async $ => {
    try {
      return { text: await atualizar($, lista, recarregaSeguro, true, recarga) }
    } catch (err) {
      return { text: `plugins-em-dia falhou: ${String(err).slice(0, 160)}` }
    }
  })
}

// SystemRoot do ambiente; sem ele (ou se a leitura falhar) o localizador cai em C:\Windows.
async function raizDoWindows($: EngineInterface): Promise<string | undefined> {
  try {
    return await $.env.get('SystemRoot')
  } catch {
    return undefined
  }
}
