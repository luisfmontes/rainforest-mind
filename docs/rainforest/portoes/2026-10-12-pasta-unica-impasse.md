# Impasse: 2026-10-12-pasta-unica

Três reprovações seguidas no `revisar`, com achados decrescendo em quantidade e gravidade:

| Rodada | Achados | O que sobrou |
|---|---|---|
| 1 | 8 (2 graves) | credencial em dois arquivos; retomada bloqueada por `.pessoal.*` |
| 2 | 6 | retomada: vigia desagendado, pasta fora de casa, flags do perfil, índice, `--profile`, rollback |
| 3 | 3 (2 médios, 1 baixo) | ver abaixo |

## Achados da rodada 3

1. **[médio] Índice de memória na retomada com conflito** — `scripts/lib/conta-unificar.cjs:69` e `:152`: o `<nome>.pessoal.md` já gravado volta como `igual` e conta como "copiado", e a retomada acrescenta ao `MEMORY.md` uma linha pessoal que aponta para o `a.md` da pasta de trabalho. Variante baixa: `a.md` idêntico nas duas pastas também acrescenta a linha numa rodada limpa.
2. **[médio, a confirmar] `<pasta>/.claude.json` da pasta padrão** — `scripts/conta.cjs:107` e `scripts/lib/conta-mover.cjs:79,82` leem `~/.claude/.claude.json`; o Claude Code usa `~/.claude.json` para a pasta padrão. Medido em 2026-10-12: os dois existem nesta máquina (o de dentro da pasta foi escrito pelo vigia em 2026-10-10), os dois com `oauthAccount`. Então o vigia não quebra aqui, mas grava o `oauthAccount` no arquivo que a pasta padrão não lê. É comportamento da 1.62.0, anterior a este fluxo.
3. **[baixo] `.bak-pasta-unica` de uma gravação de perfil que falhou bloqueia a retomada** — `scripts/conta.cjs` (`migrar`, `perfilSo`).

## Decisão pedida ao Luís

Liberar a 4ª rodada para consertar 1 e 3 (pequenos, no mesmo arquivo), e levar o 2 para uma Issue própria (anterior a este fluxo e não quebra a migração nesta máquina) — ou outra saída.

## Rodada 4 (liberada pelo Luís: "ajustar tudo") — reprovada com 5 achados

Os três achados da 3ª revisão foram conferidos como consertados. A tarefa 7 abriu um defeito novo:

1. **[grave]** `hooks/testa-mod-conta.cjs` não passa `RFM_CONTA_CLAUDE_JSON` e, com a tarefa 7, lê e grava o `~/.claude.json` real de quem roda a bateria (troca o `oauthAccount` por uma conta falsa). Medido em 2026-10-12 nesta máquina: o `~/.claude.json` real não tem dado falso (a bateria não rodou aqui). Conserto: a bateria passa a variável, e o `conta.cjs` recusa quando `RFM_TEST=1` define as pastas mas não o JSON.
2. **[médio]** Falta teste provando que a pasta pessoal (modo duas pastas) segue usando o `.claude.json` de dentro dela.
3. **[baixo]** CHANGELOG diz "com as duas pastas, nada muda" — falso desde a tarefa 7.
4. **[baixo]** O progresso da cópia só é gravado ao fim do laço; um travamento no meio perde o registro (sem perda de arquivo).
5. **[baixo]** Janela entre conferir e gravar o `~/.claude.json`, que sessões vivas também escrevem.

## Rodada 5 (liberada pelo Luís: "sim") — reprovada com 5 achados novos

Os 5 achados da 4ª revisão foram conferidos como consertados (inclusive o grave: nenhuma bateria alcança o `~/.claude.json` real; observado com canário). Achados novos:

1. **[médio]** `unificar` não registra a conta pessoal no `estado.json`; quem migra sem ela registrada fica sem troca e sem comando que conserte. Medido em 2026-10-12: nesta máquina `team` e `pessoal` já estão registradas, então não afeta a migração do Luís.
2. **[baixo]** `unificar` regrava o `~/.claude.json` a partir da leitura feita no planejamento (sessão aberta no meio perde a escrita dela).
3. **[baixo]** progresso reescrito inteiro a cada cópia: O(n²) (medido 22 s contra 7 s com 4000 arquivos).
4. **[baixo]** ramo do desfazer do `.claude.json` no `mover` sem teste que falhe.
5. **[baixo]** guarda de `RFM_CONTA_CLAUDE_JSON` só olha a pasta de trabalho; nome de caso `(z)` reaproveitado na bateria.

## Rodada 6 (liberada pelo Luís: "recomendado" = opção A)

Consertar os 5 achados da 5ª revisão; a 6ª revisão fica restrita a conferir esses consertos e o que eles mudaram.
