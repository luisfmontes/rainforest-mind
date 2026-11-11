# fechar-issue aceita "Pronto quando" e o gate deixa passar a ajuda do gh

## Objetivo
Duas travas do fechamento de Issue barram caso legítimo e empurram a sessão para o atalho. O `scripts/fechar-issue.cjs` recusa a Issue no formato que o repositório mais usa (Issue #681), e a sessão acaba comentando o marcador `<!-- rainforest-evidencia -->` à mão. O `hooks/gate-fechar-issue.cjs` barra `gh pr create --help` e `gh help pr create` como se criassem PR (Issue #682), e a gramática do `gh` só se confere pelo manual online.

Brainstorm conduzido em modo autônomo (autorização do Luís em 2026-11-11: "pode decidir e executar no automatico"). Toda decisão abaixo é **decidido pela sessão**, com a opção recomendada, aberta a veto no PR.

## Decisões fechadas
- **D1 — O `fechar-issue.cjs` aceita as três formas de "Pronto quando" em uso, além do cabeçalho canônico.** Passam: `## Critério de pronto (falsificável)` (como hoje), `##`/`###` seguido de `Pronto quando`, `**Pronto quando:**` no início da linha (com ou sem `- ` de lista) e `Pronto quando:` no início da linha. Continuam recusadas as variantes do cabeçalho canônico sem parênteses ou com outro delimitador (casos (j) e (k) da bateria), e a mensagem de recusa passa a citar as formas aceitas. — porquê: medido em 2026-11-11 nas 200 Issues mais recentes, há 19 com `## Pronto quando`, 14 com `**Pronto quando:**` e 3 com `Pronto quando:` no início da linha. O `commands/issue.md:96` documenta o cabeçalho canônico, mas a maior parte das Issues usa as outras formas, e recusá-las empurra a sessão a comentar o marcador à mão.
- **D2 — O comentário do `fechar-issue.cjs` que cita `commands/issue.md` fica como está.** — porquê: o arquivo tem o cabeçalho na linha 96. A Issue #681 dizia o contrário porque um `grep` com `[eé]` no Git Bash saiu vazio por codificação (corrigido em comentário na Issue, observação plantada).
- **D3 — O gate deixa passar `gh help ...` e `gh <grupo> <verbo>` com `--help` ou `-h` como único argumento depois do verbo.** Fica na entrada do `verificarComandoGh`, depois da recusa de subcomando por variável e antes de todo caso que lê corpo. — porquê: `gh help` nunca escreve. Com a ajuda sozinha depois do verbo, o `gh` só imprime a ajuda. Aceitar `--help` em qualquer posição abriria `gh pr create --nova-flag --help --body "Closes #12"`: se uma flag que o gate não conhece receber `--help` como valor, o `gh` cria o PR e o gate não confere o corpo.
- **D4 — Modelo de ameaça e parada.** Protege contra a sessão travar ao consultar a ajuda do `gh` e contra o atalho manual ao fechar Issue no formato comum. Fica fora, e continua barrado (falha fechada): ajuda misturada com outras flags, `-h` agrupado (`-dh`), `--help=...`. Achado de revisão nessas formas não reabre o fluxo, vira ideia.

## Avaliado e descartado
- **`--help` em qualquer posição de flag, pulando os valores conhecidos:** cobre `gh pr create --title t --help`, mas depende da lista de flags com valor estar completa. Flag nova do `gh` que receba `--help` como valor abre o furo descrito no D3. Nenhuma das formas pedidas na #682 precisa disso.
- **Exigir o cabeçalho canônico e reescrever as Issues antigas:** mexe em dezenas de Issues de outra época para manter uma regra que o próprio repositório não segue.

## Fora de escopo
- O `commands/issue.md` continua ensinando o cabeçalho canônico. Mudar o modelo de Issue é outra decisão.

## Varredura
docs/rainforest/varredura/fechar-issue-pronto-e-ajuda.txt — as Issues #681 e #682 são as únicas abertas sobre o tema; as fechadas que casaram (#664, #407 e outras do gate) tratam outra grafia de corpo, não ajuda nem "Pronto quando". O `AJUDA_PR_MERGE` (`hooks/gate-fechar-issue.cjs:761`) já trata a ajuda do `gh pr merge`, e o D3 segue a mesma ideia.

## Em aberto
