# Plano: faixa do PR, compactar a 60% e node por caminho absoluto

Design: docs/rainforest/design/2026-10-10-mods-faixa-compact.md

## O que não pode quebrar
- A barra e o pane do `/painel`, o relógio e o painel de PR seguem como na 1.57.0: `node hooks/testa-mod-painel.cjs`, `node hooks/testa-mod-relogio.cjs`, `node hooks/testa-mod-pr.cjs` e os casos existentes de `claude plugin test .` verdes.
- Falha aberta: falha de `$.session.compact`, de `$.ui.panes`, de leitura ou de localizar o `node` nunca quebra a sessão nem a barra.
- A nota do PR para o modelo continua sem texto de terceiro.

## Tarefas

### 1. Lógica pura da compactação [tipo: implementar]
atende: D2, D3, D4, D6
arquivos: `hooks/compactar-puro.mjs`, `hooks/testa-mod-compactar.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-compactar.cjs`
mutacao:
  arquivo: `hooks/compactar-puro.mjs`
  de: `if (agenteRodando)`
  para: `if (false)`
  bateria: `node hooks/testa-mod-compactar.cjs`
  fixture: `testa-mod-compactar.cjs, caso "agente rodando avisa uma vez e nao compacta"`
pronto quando: `decidir({ percent, limiar, armado, agenteRodando, ligado, avisado })` (ES module sem Node, sem relógio, uma função pura) devolve `{ acao, armado, avisado }` com `acao` em `'nada' | 'compactar' | 'avisar'`: desligado → `nada`; `percent` ausente → `nada`; abaixo do limiar → `nada` e rearma (`armado: true`, `avisado: false`); armado, no limiar ou acima, sem agente → `compactar` e desarma; armado com agente rodando → `avisar` só na primeira vez (`avisado` passa a `true`, `armado` segue `true`) e `nada` nas seguintes; desarmado acima do limiar → `nada`; e o agente terminar com o uso ainda acima → `compactar`. `LIMIAR_PADRAO` é 60. Texto do aviso por `textoAviso(percent, agenteRodando)`: com agente, "contexto em N%: agente rodando, compacto quando ele voltar (ou faça a passagem)"; sem, "compactado em N%". Provado por `node hooks/testa-mod-compactar.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`, com a sequência real de percentuais 30 → 61 → 61 → 20 → 65 (uma compactação por subida).

### 2. Linha do PR para a barra [tipo: implementar]
atende: D1, D6
arquivos: `hooks/pr-puro.mjs`, `hooks/testa-mod-pr.cjs`
depende de: nenhuma
paralela: sim
prova: `node -e "import('./hooks/pr-puro.mjs').then(m=>process.exit(typeof m.linhaPr==='function'?0:1))"`
mutacao:
  arquivo: `hooks/pr-puro.mjs`
  de: `if (r.estado === 'MERGED' || r.estado === 'CLOSED') return null;`
  para: `if (false) return null;`
  bateria: `node hooks/testa-mod-pr.cjs`
  fixture: `testa-mod-pr.cjs, caso "linha da barra: some com o PR mergeado ou fechado"`
pronto quando: com o resumo de `resumir()` sobre as fixtures reais do PR 455 já em `testa-mod-pr.cjs`, `linhaPr(r)` devolve `null` para `r` nulo, `MERGED` ou `CLOSED`, e para PR aberto `{ partes: [{ texto, tom }] }` com `#N`, os chips de `bloco(r)` (checks e merge, mesmo glifo e tom) e nenhum título, branch ou texto de terceiro (o caso usa título com isca e afirma que ela não aparece) — provado por `node hooks/testa-mod-pr.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`.

### 3. Fiação no mod: compactar, linha do PR, node absoluto e opções [tipo: implementar]
atende: D1, D2, D3, D4, D5
arquivos: `hooks/compactar.ts`, `hooks/mod.tsx`, `hooks/pr.tsx`, `types/index.d.ts`, `.claude-plugin/plugin.json`, `hooks/mod-compactar.test.tsx`, `hooks/mod-pr.test.tsx`, `hooks/mod-painel.test.tsx`, `hooks/mod-relogio.test.tsx` (emenda: o mock do relógio passa a responder o localizador do node)
depende de: 1, 2
paralela: nao
prova: `bash -c "test -f hooks/mod-compactar.test.tsx && claude plugin test ."`
mutacao:
  arquivo: `hooks/compactar.ts`
  de: `if (d.acao === 'compactar')`
  para: `if (d.acao !== 'nada')`
  bateria: `claude plugin test .`
  fixture: `mod-compactar.test.tsx, caso "agente rodando: avisa e nao compacta"`
pronto quando: com o `plugin.json`, os tipos e o `hooks.json` reais, `claude plugin validate .claude-plugin/plugin.json` passa e lista `session.measure` e as opções `compactarSozinho` (booleano, padrão `true`) e `compactarEm` (número, padrão 60); e `claude plugin test .` sai 0 com: (a) `session.measure` com `changed: ['context']` e `percent` 30 → 61 → 61 chama `$.session.compact` uma vez; (b) com subagente em andamento na sessão, a 61% dá um toast e não compacta, e compacta no primeiro measure depois que ele termina; (c) `compactarSozinho: false` nunca compacta; (d) compactação rejeitada rearma e compacta no measure seguinte; (e) a barra (`AbovePrompt`) mostra a linha do PR quando há PR acompanhado e `$.ui.panes()` não traz `rainforest-mind-pr` colocado e visível, e não mostra quando traz ou quando o PR está `MERGED`; (f) todo `process.run` que o mod faz sai com `argv[0]` absoluto — o filtro `a !== 'node'` de `hooks/mod-pr.test.tsx` sai, e o `node` é localizado por `localizadores('node', …)` + `escolherExecutavel` fora do cwd da sessão; (g) os casos existentes continuam verdes, e `node hooks/testa-mod-painel.cjs`, `node hooks/testa-mod-relogio.cjs` e `node hooks/testa-mod-abertura.cjs` também.

### 4. Documentação, versão e CHANGELOG [tipo: docs]
atende: D7
arquivos: `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação e versão, sem comportamento a inverter; a falsificação é a coerência com o código entregue.
pronto quando: a versão é o próximo MINOR livre sobre a `origin/main` (hoje 1.58.0) nos dois `plugin.json` e no badge do README; `## <versão>` no topo do `CHANGELOG.md` diz o que ele passa a ver (linha do PR na barra, compactar sozinho a 60% e o aviso com agente rodando, as duas opções, `node` por caminho absoluto), com crédito ao Rafael; o `CONTRIBUTING.md` descreve a compactação e a linha do PR com os números do código — provado por um `node -e` que importa `hooks/compactar-puro.mjs` e sai 1 se `LIMIAR_PADRAO` não aparecer no CHANGELOG e no CONTRIBUTING, mais `node scripts/conferir-versao.cjs` e `bash scripts/testa-versao.sh` saindo 0.

## Cobertura

D1: 2, 3 · D2: 1, 3 · D3: 1, 3 · D4: 1, 3 · D5: 3 · D6: 1, 2 · D7: 4
