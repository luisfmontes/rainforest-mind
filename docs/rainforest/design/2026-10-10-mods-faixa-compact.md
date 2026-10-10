# Design: faixa do PR, compactar a 60% e node por caminho absoluto

Fluxo `2026-10-10-mods-faixa-compact`. Três peças pequenas no mod, duas copiadas do
plugin `wildz-data` do Rafael Lopes (autorização dele, 2026-10-09) e uma Issue (#457).
Ideias de origem: `mod-pr-faixa-acima-do-prompt`, `mod-auto-compact-60`.

## Fatos medidos

- O mod já desenha uma barra acima do prompt (`hooks/mod.tsx`, `ui.render` de
  `AbovePrompt`), que `/painel esconder` oculta (`painelOculto`). Uma segunda barra do
  mesmo plugin competiria com ela.
- O engine empurra `session.measure` depois de cada turno; `e.context.percent` é o
  uso da janela (0 a 100) e `e.changed` diz o que mudou. `$.session.compact()` é o
  mesmo `/compact`, entre turnos; rejeita com turno em curso e devolve `{ skip }`
  quando um hook veta.
- O Luís tem `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 45` nas duas contas, e com Opus 5.5
  `[1m]` o CLI ignora o override (memória `autocompact-nao-respeita-override-com-1m`).
  O Rafael usa o mesmo modelo e janela, e compacta a 60%.
- O mod já conhece os subagentes da sessão (`painelStats.agentes`, `emAndamento`).
- `hooks/mod.tsx` chama `node` pelo nome em seis pontos (#457); o painel de PR já
  resolve `gh` por `localizadores` + `escolherExecutavel` (`hooks/pr-puro.mjs`).

## Decisões

**D1. A linha do PR entra na barra que já existe** (Q4). Uma linha a mais no
`AbovePrompt` do mod, com número, estado, checks e merge no mesmo tom dos chips do
pane. Só aparece quando há PR acompanhado e o pane `rainforest-mind-pr` não está
colocado e visível (`$.ui.panes()`); some quando o PR fica `MERGED` ou `CLOSED`.
`/painel esconder` esconde junto com o resto da barra. Sem botão próprio.

**D2. Compactar sozinho a 60% por padrão** (Q1). Opção `compactarEm` (número, padrão
60) no `userConfig`. Mede por `session.measure` (`e.context.percent`), só quando
`context` está em `e.changed`. Dispara uma vez por subida: desarma antes de chamar e
rearma quando o uso volta abaixo do limiar. Compactação rejeitada (turno em curso)
rearma e tenta no próximo `session.measure`, com aviso uma vez por sequência.

**D3. Com subagente rodando, não compacta: avisa** (Q2). Se a sessão tem subagente em
andamento (o mesmo critério da barra), o mod não compacta: dá um aviso (toast) uma vez
por subida, "contexto em N%: agente rodando, compacto quando ele voltar (ou faça a
passagem)", e compacta no primeiro `session.measure` sem agente rodando. Fora disso
compacta e avisa "compactado em N%".

**D4. Ligada por padrão, com opção para desligar** (Q3). `compactarSozinho` (booleano,
padrão `true`) no `userConfig`.

**D5. `node` por caminho absoluto no mod (#457).** O mod resolve o `node` uma vez por
sessão, como o painel de PR resolve o `gh`: `localizadores('node', SystemRoot)` com
`escolherExecutavel` fora do repositório da sessão, guardado em átomo. Os seis pontos
passam a usar esse caminho. Sem `node` achado, a peça que dependia dele se apaga (falha
aberta, como hoje com falha de processo).

**D6. Lógica pura separada e testada.** A decisão de compactar (limiar, armado, agente
rodando, opção desligada) e o texto da linha do PR moram em módulos `*-puro.mjs` com
bateria `.cjs`; a fiação tem prova de engine em `*.test.tsx` (`claude plugin test .`).

**D7. Versão e docs.** MINOR (próximo livre na hora do merge; hoje 1.58.0, depois do
#476 da outra janela). CHANGELOG, CONTRIBUTING (seções do mod) e README dizem o que
muda para quem usa, com os números do código. Crédito ao Rafael no código copiado.

## Fora do escopo

- Recarga em todas as janelas (`plugins-em-dia-recarga-multi-janela`): espera a medição
  na conta de trabalho.
- Issue #466 (achados menores do painel de PR).
