// Prova de engine da faixa acima do prompt: `claude plugin test <raiz do repo>`.
// O engine carrega hooks/mod.tsx de verdade e monta `AbovePrompt` em cada surface; o que
// responde por baixo dos plugins e `process.run` (a saida do script de dados), `session.cwd`
// e os fundos de `session.start` e `turn.complete`.
// Um `test` por surface: `$.state` dura a sessao de teste inteira, entao os casos correm em
// sequencia dentro dele e cada um herda o estado do anterior (a ordem e parte do contrato).
// Os dados nao sao inventados: FIXTURE_DADOS e a saida REAL de `scripts/faixa-dados.cjs`
// sobre um repo temporario (hooks/testa-mod-faixa.cjs confere que as chaves seguem as do
// script) e ANSWER e o texto real do exemplo de Q1 e Q2 do README.md.
import { test, expect } from 'claude-code/testing'
import { largura } from './faixa-puro.mjs'

// Saida real do script; so o campo `worktree` (caminho da caixa temporaria) foi trocado
// por um caminho neutro.
const FIXTURE_DADOS = {"foco":"🚀 Lancar faixa","fluxos":[{"slug":"2026-10-03-faixa-teste","titulo":"Faixa de teste","etapa":"executar","tarefas_ok":1,"tarefas":3,"em_voo":["agente-a"],"criado_em":"2026-10-03","worktree":"C:/tmp/faixa-repo-OdhnjD"}]}

const ANSWER = `Você pede uma feature. Em vez de sair codificando, vem uma rodada numerada,
cada pergunta **já com a resposta recomendada**:

> ❓ **Q1 — Onde o token vive**: sessão no servidor ou JWT no cliente?
> ➡️ **Recomendo:** sessão no servidor — você já tem Redis, e revogar JWT exige lista negra que é o mesmo trabalho com mais peças.
>
> ❓ **Q2 — Expiração**: 15 min com refresh, ou 8h fixas?
> ➡️ **Recomendo:** 8h fixas — refresh só se paga com múltiplos dispositivos, e não é o seu caso hoje.
`

const ANSWER_Q_NOVA = `${ANSWER}\n**Q3.** Quem revoga o token\n`
const ANSWER_INTRUSA = '**Q9.** Pergunta de subagente que nao pode entrar\n'

const VAZIO = { foco: null, fluxos: [] }
const AGENTE_NOVO = {
  ...FIXTURE_DADOS,
  fluxos: [{ ...FIXTURE_DADOS.fluxos[0], em_voo: ['agente-a', 'agente-b'] }],
}

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 20 },
  view: {},
}

const saida = (stdout: string, exitCode = 0) => ({
  value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'recusado', isStdoutTruncated: false, isStderrTruncated: false },
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`faixa (${surface}): quieta, desenha, cede a vaga, esconde, falha aberta, largura`, async ($, on) => {
    let modo: 'fixture' | 'vazio' | 'falha' | 'agente-novo' = 'vazio'
    const chamadas: { argv: readonly string[]; cwd: unknown }[] = []
    on('process.run', async (_$, e) => {
      chamadas.push({ argv: e.argv, cwd: e.init?.cwd })
      if (modo === 'falha') return saida('', 1)
      if (modo === 'vazio') return saida(JSON.stringify(VAZIO))
      return saida(JSON.stringify(modo === 'agente-novo' ? AGENTE_NOVO : FIXTURE_DADOS))
    })
    on('session.cwd', async () => ({ value: '/projeto' }))
    on('session.start', async (_$, e) => ({ cwd: e.cwd }))
    on('turn.complete', async () => ({ text: '' }))
    on('prompt.submit', async (_$, e) => e as never)
    // Fundo da cadeia: o que o engine desenharia quando o mod cede (aqui, uma caixa vazia).
    on('ui.render', async (t$, e) => {
      const { Box } = t$.ui.resolve(e)
      return <Box />
    })

    const comecar = () => $.session.start({ cwd: '/projeto', surface, isInteractive: true })
    let n = 0
    const terminar = (answer: string, extra: Record<string, unknown> = {}) =>
      $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: `t${++n}`, reason: 'answer', ...extra } as never)

    // Todo caso falha com o nome dele na mensagem (o caso de hasSurvey e a mutacao do plano).
    const caso = async (nome: string, fn: () => Promise<void>) => {
      try {
        await fn()
      } catch (err) {
        throw new Error(`[${surface}] ${nome}: ${err instanceof Error ? err.message : String(err)}`)
      }
    }

    const ui = await $.ui.mount({ plugin: 'rainforest-mind', surface, component: 'AbovePrompt', props: PROPS })
    const textos = async () => (await ui.findAll({ type: 'Text' })).map(t => t.text)
    const botao = () => ui.find({ type: 'Button', key: 'esconder' })
    const quieta = async () => {
      expect(await textos()).toEqual([])
      expect(await botao()).toBeUndefined()
    }
    const desenha = async () => {
      const t = (await textos()).join('\n')
      expect(t).toContain('Lancar faixa')
      expect(t).toContain('fluxo faixa-teste: executar')
      expect(t).toContain('Q1 Onde o token vive')
      expect(await botao()).toBeDefined()
    }

    await caso('quieta sem fluxo e sem Q (antes de qualquer evento)', quieta)

    await caso('quieta com dados vazios depois de session.start', async () => {
      modo = 'vazio'
      await comecar()
      await quieta()
    })

    await caso('desenha foco, slug sem data com etapa e Q1 depois de session.start + turn.complete', async () => {
      modo = 'fixture'
      await comecar()
      await terminar(ANSWER)
      await desenha()
      const t = (await textos()).join('\n')
      expect(t).toContain('1/3')
      expect(t).toContain('1 em voo')
      expect(t).toContain('Q2 Expiração')
      expect(t).not.toContain('2026-10-03')
    })

    await caso('o process.run da faixa roda com cwd na raiz do plugin, e a sessao vai por --cwd', async () => {
      const dados = chamadas.filter(c => String(c.argv[1]).endsWith('faixa-dados.cjs'))
      expect(dados.length).toBeGreaterThan(0)
      for (const c of dados) {
        const raiz = String(c.argv[1]).replace(/[\\/]scripts[\\/]faixa-dados\.cjs$/, '')
        expect(raiz).not.toBe(String(c.argv[1]))
        expect(c.cwd).toBe(raiz)
        expect(c.argv[c.argv.indexOf('--cwd') + 1]).toBe('/projeto')
      }
    })

    await caso('cede a vaga quando hasSurvey', async () => {
      await ui.redraw({ ...PROPS, hasSurvey: true })
      await quieta()
      await ui.redraw({ ...PROPS, hasSurvey: false })
      await desenha()
    })

    await caso('isWorking true ainda desenha', async () => {
      await ui.redraw({ ...PROPS, isWorking: true })
      await desenha()
      await ui.redraw(PROPS)
    })

    await caso('largura: com bodyColumns 30 cada Text cabe em 30 celulas', async () => {
      await ui.redraw({ ...PROPS, bodyColumns: 30 })
      const t = await textos()
      expect(t.length).toBeGreaterThan(0)
      for (const linha of t) expect(largura(linha)).toBeLessThanOrEqual(30)
      expect(t.some(linha => linha.endsWith('…'))).toBe(true) // houve corte de verdade
      await ui.redraw(PROPS)
    })

    await caso('esconder deixa quieta e a mesma Q no turno seguinte mantem escondida', async () => {
      await ui.press({ key: 'esconder' })
      await quieta()
      await terminar(ANSWER)
      await quieta()
    })

    await caso('Q nova traz a faixa de volta', async () => {
      await terminar(ANSWER_Q_NOVA)
      await desenha()
      expect((await textos()).join('\n')).toContain('Q3 Quem revoga o token')
    })

    await caso('agente novo em voo traz a faixa de volta depois de esconder', async () => {
      await ui.press({ key: 'esconder' })
      await quieta()
      modo = 'agente-novo'
      await terminar(ANSWER_Q_NOVA)
      await desenha()
      expect((await textos()).join('\n')).toContain('2 em voo')
      // modo fica em 'agente-novo' de proposito: os casos seguintes refazem os dados a cada
      // turno, e voltar ao fixture devolveria a assinatura escondida e calaria a faixa.
    })

    await caso('turn.complete de subagente (agentId) nao mexe na Q', async () => {
      await terminar(ANSWER_INTRUSA, { agentId: 'sub-1' })
      const t = (await textos()).join('\n')
      expect(t).not.toContain('Q9')
      expect(t).toContain('Q3 Quem revoga o token')
    })

    await caso('turn.complete aborted nao mexe na Q', async () => {
      await terminar(ANSWER_INTRUSA, { reason: 'aborted', isAborted: true })
      const t = (await textos()).join('\n')
      expect(t).not.toContain('Q9')
      expect(t).toContain('Q3 Quem revoga o token')
    })

    await caso('answer vazio e ausente nao quebram; o fluxo continua na tela', async () => {
      await terminar('')
      expect((await textos()).join('\n')).toContain('fluxo faixa-teste: executar')
      await terminar(undefined as never)
      expect((await textos()).join('\n')).toContain('fluxo faixa-teste: executar')
      await terminar(ANSWER) // restaura as Q para o caso seguinte
      await desenha()
    })

    await caso('process.run com exitCode 1 apaga foco e fluxo e a Q fica, sem excecao', async () => {
      modo = 'falha'
      await terminar(ANSWER)
      const t = (await textos()).join('\n')
      expect(t).not.toContain('Lancar faixa')
      expect(t).not.toContain('fluxo faixa-teste')
      expect(t).toContain('Q1 Onde o token vive')
      modo = 'fixture'
    })

    await caso('mensagem do usuario tira as Q da tela ate o proximo fim de turno', async () => {
      modo = 'agente-novo' // fixture devolveria a assinatura escondida (ver acima)
      await terminar(ANSWER)
      expect((await textos()).join('\n')).toContain('Q1 Onde o token vive')
      await $.prompt.submit({ text: 'respondi' } as never)
      const t = (await textos()).join('\n')
      expect(t).not.toContain('Q1 Onde o token vive')
      expect(t).toContain('fluxo faixa-teste: executar')
      await terminar(ANSWER)
      expect((await textos()).join('\n')).toContain('Q1 Onde o token vive')
    })

    await ui.unmount()
  })
}

