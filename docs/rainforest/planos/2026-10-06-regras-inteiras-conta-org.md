# Plano: regras inteiras na conta de trabalho via session.append

Design: docs/rainforest/design/2026-10-06-regras-inteiras-conta-org.md

Base: worktree `worktree-regras-inteiras-conta-org`, ancestral de `origin/main` `a85f9315`. Versao publicada: 1.41.0.
Types do engine: `plugin-authoring/types/claude-code.d.ts` da skill embutida no CLI 2.1.292.

## O que não pode quebrar

- **Conta sem sec-default fica como hoje:** nenhum `$.session.append`, nenhuma leitura de `$.session.messages()`, secao do compose e filtro do SessionStart identicos. Prova: `node hooks/testa-mod-abertura.cjs` e `claude plugin test .` verdes, sem editar os casos existentes, exceto o caso da lista de eventos ligados por `register.ts`, que passa a ter os novos.
- **Falha aberta:** gerador que falha, ou `$.session.messages()`/`$.session.append` que lancam, fazem o hook devolver `next(e)` intacto; a sessao segue com o nucleo do SessionStart.
- **Um gerador so (D1):** o texto anexado e `MARCA + "\n" + <texto da mesma montagem memoizada do compose>`; nenhuma segunda chamada aos geradores na mesma abertura.
- **A secao `hooks` do `hooks/hooks.json` fica intacta.**
- **`skills/rainforest-mind/references/regra-*.md` nao sao editados.**
- **Ambiente do usuario nao muda:** nada de settings ou plugin instalado; a medicao real usa `--plugin-dir`, e os transcripts das sondas sao movidos para o scratchpad ao fim.
- **`claude plugin validate .` sai 0** depois de cada tarefa que toca `hooks/*.ts|mjs`.
- **`varrer-baterias` nao passa a depender do binario `claude`:** a bateria nova e Node puro.

## Tarefas

### 1. Append condicionado ao sec-default, com marca, resume, clear e compact [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6, D7
arquivos: `hooks/abertura-mod-puro.mjs`, `hooks/register.ts`, `hooks/testa-mod-abertura.cjs`, `hooks/testa-mod-abertura-append.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-abertura-append.cjs`
mutacao:
  arquivo: `hooks/abertura-mod-puro.mjs`
  de: `return (mensagens ?? []).some(m => textoDe(m).startsWith(MARCA));`
  para: `return false;`
  bateria: `node hooks/testa-mod-abertura-append.cjs`
  fixture: `testa-mod-abertura-append.cjs, caso "resume com a marca no transcript nao anexa de novo"`
pronto quando: com o `e.plugins` que o `engine.create` da conta de trabalho manda (nomes medidos: `cc-plugin-sec-default,rainforest-mind,cc-plugin-agents-md,cc-plugin-telemetry,cc-plugin-you-should-know`, na forma dos types), o `session.start` chama `$.session.append` exatamente 1 vez com `{ message: { type: 'user', content: [{ type: 'text', text }] } }` e `text` comecando por `MARCA` seguido do texto que o compose usaria; um `session.start` de resume com a marca ja em `$.session.messages()` faz 0 appends; `session.end` com `reason: 'clear'` seguido de 2 `prompt.submit` faz 1 append so, no primeiro; `session.compact` cujo `next(e)` devolve mensagens sem a marca faz 1 append, e com a marca 0; com `e.plugins` sem `cc-plugin-sec-default`, 0 appends e 0 leituras de `messages()` em todos os eventos — provado por `node hooks/testa-mod-abertura-append.cjs` (carrega o `register.ts` real com `$` falso e geradores reais sobre fixture) imprimindo o placar final com 0 falhas e exit 0, e por `node hooks/testa-mod-abertura.cjs` com exit 0.

Forma prescrita do codigo novo (alvo de mutacao em codigo a nascer):
- `export const MARCA` e uma string de uma linha, sem aspas nem barra invertida, que nao comeca por nenhum dos `PREFIXOS` existentes (ex.: `[rainforest-mind:abertura]`).
- `temMarca(mensagens)` e uma expressao so: `return (mensagens ?? []).some(m => textoDe(m).startsWith(MARCA));` — `textoDe` junta os blocos de texto da mensagem no formato de `$.session.messages()` e de `SessionCompacted.messages`, lido nos types antes de escrever.
- `barraCompose(nomes)` e uma expressao so sobre a lista de nomes que `register.ts` tira de `e.plugins` (forma do item lida em `EngineCreateInput` nos types): `return nomes.includes('cc-plugin-sec-default');`.
- Nenhum caso de teste afirma sobre o texto do fonte; so sobre as chamadas ao `$` falso.
- `register.ts` liga `engine.create` (devolve `next(e)` intacto, so guarda a flag), `session.start`, `prompt.submit` e `session.compact`, alem dos tres atuais; todo append passa por `temMarca` sobre as mensagens atuais e fica em `try/catch`; `prompt.submit` so age com a pendencia de `/clear` armada, e a desarma.
- O cabecalho de `abertura-mod-puro.mjs` descreve o caminho do append e cita o design.

Segunda mutacao, tambem rodada na integracao: `de:` `return nomes.includes('cc-plugin-sec-default');` `para:` `return false;` — a `bateria:` `node hooks/testa-mod-abertura-append.cjs` tem de ficar vermelha no caso "conta com sec-default anexa uma vez no session.start".

### 2. Prova de engine do append [tipo: teste]
atende: D3, D4
arquivos: `hooks/mod-abertura.test.ts`
depende de: 1
paralela: nao
prova-na-base: verde — `claude plugin test .` ja passa na base com os dois casos atuais; o caso novo nasce com esta tarefa, e o comando roda pelo binario `claude`, fora do CI
mutacao:
  arquivo: `hooks/abertura-mod-puro.mjs`
  de: `return nomes.includes('cc-plugin-sec-default');`
  para: `return false;`
  bateria: `claude plugin test .`
  fixture: `mod-abertura.test.ts, test "append: sec-default no engine.create anexa uma vez e o resume nao duplica"`
pronto quando: com o engine real do `claude-code/testing` carregando o modulo do `hooks.json` e `engine.create` recebendo `cc-plugin-sec-default` entre os plugins, um `session.start` gera 1 chamada a `session.append` com texto iniciado pela `MARCA`, e um segundo `session.start` com essa linha em `session.messages` gera 0 — provado por `claude plugin test .` com exit 0 e o nome do teste novo no relatorio. Se o `claude-code/testing` nao conseguir simular `engine.create` ou `session.append`, a tarefa para e reporta o trecho dos types que impede; nao troca por teste que afirme menos.

### 3. Medicao real nas duas contas [tipo: pesquisar]
atende: D1, D2, D3, D4, D6
arquivos: `docs/rainforest/medicoes/2026-10-06-regras-inteiras-conta-org.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: medicao do artefato real em sessoes `claude -p`; nao ha linha de codigo desta tarefa a inverter — as inversoes moram nas tarefas 1 e 2
pronto quando: com sessoes reais `claude -p --debug --plugin-dir <worktree> --model haiku` na conta de trabalho (`CLAUDE_CONFIG_DIR=<home>/.claude`) e na pessoal (`CLAUDE_CONFIG_DIR=<home>/.claude-personal`), a pergunta "Responda so com o texto que vem logo depois de `**O terceiro caso:` no seu contexto, ou NONE" volta com `fato que só ele sabe não se deduz do ambiente.` nas duas; na de trabalho, o transcript jsonl tem exatamente 1 linha `isMeta` cujo texto comeca pela `MARCA` na sessao nova e continua com 1 apos `--resume <id>`, e o debug tem `rainforest-mind: prompt.compose bypassed`; na pessoal, 0 linhas com a `MARCA` e o debug tem `prompt.compose` sem bypass; apos `claude -p --resume <id> "/compact"` na de trabalho, a mesma pergunta no `--resume` seguinte volta com a mesma frase e o que sobrou do transcript tem 1 linha com a `MARCA`. Cada medicao colada no arquivo como comando literal + saida literal + veredito; item que nao puder rodar em `-p` fica "nao medido" com a mensagem de erro colada e volta ao usuario — provado pelo proprio arquivo, conferido pela janela principal re-rodando uma das contagens.

A frase-sonda separa os caminhos: `node hooks/foco-session-start.cjs` (nucleo classico) tem 0 ocorrencias de `O terceiro caso`, e `--destino mod` tem 1 (medido na base em 2026-10-06). Por isso a resposta so volta se o texto inteiro chegou.

### 4. Medicao do /clear no REPL, feita pelo usuario [tipo: pesquisar]
atende: D5
arquivos: `docs/rainforest/medicoes/2026-10-06-regras-inteiras-conta-org.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: `/clear` so existe no REPL interativo, que o agente nao dirige; o comportamento esta invertido pela mutacao da tarefa 1 no caso de `/clear` da bateria
pronto quando: com o usuario numa sessao interativa da conta de trabalho aberta com `claude --plugin-dir <worktree>`, depois de `/clear`, a mesma pergunta da tarefa 3 volta com `fato que só ele sabe não se deduz do ambiente.` e o transcript da sessao pos-clear tem exatamente 1 linha `isMeta` iniciada pela `MARCA` — provado pelo comando de contagem que a janela principal roda sobre o jsonl do novo session id, colado no arquivo de medicoes.

### 5. Handoff da sessao de origem [tipo: docs]
atende: D3, D7
arquivos: `docs/rainforest/handoff/2026-10-06-regras-inteiras-conta-org.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: documento de passagem escrito pela sessao de origem (commit 0bd2e907) antes do brainstorm; nao tem comportamento a inverter. Emenda feita no revisar, porque o creep o acusou
pronto quando: com o handoff versionado na branch, as medicoes que ele declara (debug `prompt.compose bypassed by cc-plugin-sec-default`, sonda de append admitida, rota de admin descartada) batem com as decisoes D3 e D7 do design e com `docs/rainforest/medicoes/2026-10-06-regras-inteiras-conta-org.md` — provado por `git log --format=%h -1 -- docs/rainforest/handoff/2026-10-06-regras-inteiras-conta-org.md` devolvendo `0bd2e907`, e por leitura cruzada na revisao.
