---
description: Fixa uma régua externa nomeada e roda builder contra crítico cego, para a tarefa que não tem teste
argument-hint: [o que precisa ficar bom — ex.: "a statusline do plugin"]
---

Carregue `Skill(regua)` e aplique sobre `$ARGUMENTS`.

Antes de qualquer trabalho, **a régua**: que artefato externo, nomeado, obtível
agora e comparável responde à mesma pergunta que este trabalho? Sem os três, a
skill **para aqui** e a escolha da régua volta para ele — régua vaga faz o
crítico aprovar a primeira rodada.

Depois, **os três freios declarados antes da rodada 1**: teto de rodadas (que é
abort, não saída), commit por rodada, e a calibragem — se o crítico da rodada 1
não apontar uma lacuna específica e fechável, a régua está errada e o loop
aborta.

O crítico é `Agent` novo **toda rodada**, nunca `fork`, e recebe os dois
artefatos sem rótulo, sem saber qual é o nosso e sem saber que rodada é. Devolve
veredito **binário** e **uma** lacuna. Nota infla; binário não.

Saiu quando venceu a comparação cega. Se saiu no teto, a entrega nomeia em uma
linha a distância que ficou para a régua — nunca esconde.

Para o loop longo sozinho, o motor é o `/loop` nativo. Esta skill é o que dá a
ele uma condição de saída que não seja "o usuário mandou parar".
