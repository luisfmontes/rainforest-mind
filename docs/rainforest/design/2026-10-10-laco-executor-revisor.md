# Laço executor → revisor com teto no fluxo

## Objetivo
Revisor que reprova devolve o trabalho ao executor **sem a mão da janela
principal na crítica**: os achados do último revisor, literais do transcrito
gravado, entram no redespacho, e o laço gira até o teto de reprovações que o
`estado.cjs` já tem, parando antes se o achado contesta o design. Enxerto D da
comparação com o orquestrador do plugin `wildz-data` (Rafael Siqueira),
`skills/execute/SKILL.md` §7–13.

## Decisões fechadas
- **D1 — O laço roda na janela principal, durante `executar` → `revisar`, sem devolver a vez entre rodadas** — porquê: é o run autônomo já autorizado; hoje cada reprovação para e espera o Luís.
- **D2 — O laço substitui o redespacho manual e reaproveita o teto existente (`TETO_TENTATIVAS = 3`, a 4ª rodada só com `liberar` e a palavra do usuário)** — porquê: dois tetos para a mesma coisa divergem; o do `estado.cjs` já tem trava e rastro (contrato de veredito de 2026-09-23, D4/D7).
- **D3 — O redespacho leva o briefing original + só os achados do último revisor, literais do transcrito gravado no veredito; nunca paráfrase da janela, nunca histórico acumulado** — porquê: "só a última crítica" é a disciplina de contexto do Rafael; o literal impede a janela de abrandar a crítica.
- **D4 — Modelo de ameaça: protege contra a janela principal reescrever ou abrandar a crítica e contra o laço sem fim; não protege contra o revisor errar** — porquê: achado falso gasta rodada até o teto, e o teto de 3 já limita esse custo; julgar o revisor é outro contrato.
- **D5 — Achado que contesta uma `D<n>` do design ou o plano interrompe o laço e sobe ao usuário** — porquê: o executor não pode mudar decisão de design; redespachar isso queima rodada sem chance de resolver.
- **D6 — `scripts/critica-do-revisor.cjs --slug <slug>` extrai a crítica**: lê o último veredito `reprovado` do `revisar` no estado, abre o `transcrito` gravado e imprime a última mensagem do revisor sem a linha `VEREDITO:`. Saídas: `0` crítica impressa; `3` crítica com achado `[design]`; `4` nenhum veredito `reprovado` gravado; `69` transcrito ausente ou ilegível (ambiente, regra 14); `1` uso — porquê: o caminho do transcrito já é gravado (D14 do contrato de veredito); o script torna o "literal" mecânico.
- **D7 — O `agents/revisor.md` marca com `[design]` o achado que contesta uma `D<n>` ou o plano** — porquê: quem julga escreve o marcador; a parada de D5 fica mecânica, não juízo da janela.
- **D8 — O laço mora numa seção nova de `skills/revisar/SKILL.md` ("Reprovado: o laço"), com ponteiro de uma linha no `executar`; o redespacho segue a regra 11 (despacho novo, nunca `SendMessage`; base = HEAD do worktree do fluxo)** — porquê: o reprovado nasce no `revisar`, e o `executar` está a 1 B do teto de 16 KiB.
- **D9 — Prova: `scripts/testa-critica-do-revisor.sh` com transcrito de fixture cobre os quatro caminhos de D6 (0, 3, 4, 69); a mutação que tira o filtro da linha `VEREDITO:` deixa a bateria vermelha** — porquê: são exatamente os caminhos que o laço lê para decidir.

## Avaliado e descartado
- Contador de iterações novo, como o `max_iterations_per_task` (8) do Rafael: descartado por D2 — o teto de 3 do contrato de veredito já mede a mesma coisa, com trava.
- Janela principal resumir os achados para o executor: descartado por D3/D4 — é o vetor que o laço existe para fechar.
- Entrega estruturada do executor gravada por hook (o "C" da comparação): ficou fora; a `conferir-entrega` e o critério reexecutado pela janela já cobrem o mecânico (decidido pelo Luís em 2026-10-10).

## Fora de escopo
- Estado `flaky` e teto de despachos por hook (ideia `executar-flaky-e-teto-de-despachos`).
- DAG com `touches` e retomada por sentinela (ideia `executar-dag-touches-e-retomada`).
- Julgar a qualidade do revisor (D4).

## Varredura
docs/rainforest/varredura/2026-10-10-laco-executor-revisor.txt — termos `laco`, `reprovado`, `TETO_TENTATIVAS`, `redespach`, `ultima critica`. Achou o contrato de veredito (#327) e o PR #443 (verificar reprovado reabre o fechar), que já dão o teto e a reabertura usados em D2; as ideias `contrato-de-veredito-de-uma-linha-no-revisar` (já implementada) e `executar-laco-executor-revisor` (esta). Nenhuma Issue aberta sobre laço.

## Em aberto
- Nada.
