// Plugins em dia (/plugins-em-dia): atualiza dentro da sessao os plugins da lista da opcao
// `plugins` e, se algum subir de versao, recarrega (opcao `recarregarSozinho`) ou avisa.
// A logica pura (alvos, ordem dos comandos, versoes, janela de intervalo, acao) mora em
// ./plugins-em-dia-puro.mjs; aqui so se liga os eventos. O engine so aceita `$` passado a
// funcao declarada no topo deste arquivo; aos `.mjs` vao so valores.
import type { EngineInterface, Register } from 'claude-code'
import { LISTA_PADRAO, PERIODO_MS, acaoAposSubir, alvos, comandos, podeRodar, subiram, versoes } from './plugins-em-dia-puro.mjs'

type Registro = { plugins?: Record<string, { scope: string; version: string }[]> }

const listaDe = (valor: unknown): string[] => {
  const itens = Array.isArray(valor) ? valor : typeof valor === 'string' ? valor.split(',') : []
  const lista = itens.map(x => String(x).trim()).filter(x => x.includes('@'))
  return lista.length > 0 ? lista : [...LISTA_PADRAO]
}

function avisar($: EngineInterface, texto: string): void {
  void Promise.resolve($.ui.toast(texto)).catch(() => {})
}

async function atualizar($: EngineInterface, lista: string[], recarregaSeguro: boolean, forcado: boolean): Promise<string> {
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

  const falhas: string[] = []
  for (const argv of comandos(ids) as string[][]) {
    // claude e um shim .cmd do npm no Windows: sem shell, o sistema nao o executa direto.
    const r = await $.process.run(['cmd', '/d', '/c', 'claude', ...argv], { timeoutMs: 120_000 }).catch(() => ({ exitCode: -1 }))
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

  on('session.start', { isInteractive: true }, async ($, e, next) => {
    try {
      await $.command.register({
        name: 'plugins-em-dia',
        description: 'Atualiza agora os plugins da lista e avisa (ou recarrega) se subir versao',
      })
    } catch {
      // sem comando, a rodada automatica segue
    }
    const rodada = () => void atualizar($, lista, recarregaSeguro, false).catch(() => {})
    rodada()
    $.clock.every(PERIODO_MS, rodada)
    return next(e)
  })

  on('command.run', { command: 'plugins-em-dia' }, async $ => {
    try {
      return { text: await atualizar($, lista, recarregaSeguro, true) }
    } catch (err) {
      return { text: `plugins-em-dia falhou: ${String(err).slice(0, 160)}` }
    }
  })
}
