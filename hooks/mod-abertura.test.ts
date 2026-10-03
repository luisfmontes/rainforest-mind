// Prova de engine do mod da abertura: `claude plugin test <raiz do repo>`.
// A prova de comportamento completa (geradores reais, falha aberta, tres cenarios de
// filtro) e hooks/testa-mod-abertura.cjs; aqui o engine carrega register.ts de verdade
// e os hooks respondem por baixo dos plugins (process.run, session.cwd, prompt.compose).
// Evento de chamada em `$` (process.run, session.cwd) responde `{ value }`.
import { test, expect } from 'claude-code/testing'

const FOCO = 'RAINFOREST MIND ATIVO — corpo do foco de teste'
const MEMORIA = '## Memória (corpus residentes)\n[2026-09-01 (p)] obs\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"'
const CODEX = 'RAINFOREST_TRANSCRIPT_PATH=/tmp/t.jsonl'
const ID = 'rainforest-mind:abertura'
const FATOS = { model: 'claude-test', promptModel: 'claude-test', surfaces: [] as never[], tools: [] as string[], outputStyle: null, traits: [] as never[] }

const saida = (ctx: string) => JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: ctx }, systemMessage: 'legenda visivel' })
const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })

test('abertura: uma secao no fim, montada uma vez, SessionStart sem as entradas dos dois hooks', async ($, on) => {
  let rodadas = 0
  on('process.run', async (_$, e) => {
    rodadas++
    return ok(e.argv.some(a => a.endsWith('foco-session-start.cjs')) ? saida(FOCO) : saida(MEMORIA))
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('prompt.compose', async () => ({ sections: [{ id: 'intro', text: 'intro', scope: 'shared' as const }] }))
  on('classic.SessionStart', async () => ({ additionalContext: [FOCO, CODEX, MEMORIA] }))

  for (let i = 0; i < 3; i++) {
    const r = await $.prompt.compose(FATOS)
    expect(r.sections.map(s => s.id)).toEqual(['intro', ID])
    expect(r.sections[1].scope).toBe('session')
    expect(r.sections[1].text).toBe(`${FOCO}\n\n${MEMORIA}`)
  }
  expect(rodadas).toBe(2)

  const ss = await $.classic.SessionStart({ source: 'startup' })
  expect(ss.additionalContext).toEqual([CODEX])
})

test('abertura: gerador que falha deixa o prompt e o SessionStart intactos', async ($, on) => {
  let tentativas = 0
  on('process.run', async () => {
    tentativas++
    return { value: { exitCode: 1, stdout: '', stderr: 'recusado', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.cwd', async () => ({ value: '/projeto' }))
  on('prompt.compose', async () => ({ sections: [{ id: 'intro', text: 'intro', scope: 'shared' as const }] }))
  on('classic.SessionStart', async () => ({ additionalContext: [FOCO, CODEX, MEMORIA] }))

  const r = await $.prompt.compose(FATOS)
  expect(r.sections.map(s => s.id)).toEqual(['intro'])
  expect(tentativas).toBe(2) // o mod chegou a rodar os geradores; foi a falha que o deixou calado
  const ss = await $.classic.SessionStart({ source: 'startup' })
  expect(ss.additionalContext).toEqual([FOCO, CODEX, MEMORIA])
})
