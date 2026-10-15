# conta unificar: 5 achados baixos da pasta-unica (#503)

## Objetivo
Fechar os cinco achados baixos que a 6ª revisão do fluxo `2026-10-12-pasta-unica` deixou plantados. Nenhum afeta quem já migrou (esta máquina já tem a pasta `.claude-personal.aposentada`): o alvo é quem ainda vai rodar `conta.cjs unificar`.

## Decisões fechadas
- **D1 — Progresso resiste a linha rasgada** — porquê: hoje um processo morto no meio da gravação deixa `"projects/x/b` sem `\n`, e a próxima gravação cola nela (`"b"c"`), perdendo também a linha nova. `gravarProgresso` (`scripts/lib/conta-unificar.cjs`) passa a prefixar `\n`; a linha vazia já é ignorada por `lerProgresso`. Entra o teste que faltava: um arquivo com a última linha rasgada mais uma gravação nova devolve a nova, e a rasgada é ignorada sem erro.
- **D2 — O relatório sem `--aplicar` também recusa a conta pessoal sem registro** — porquê: hoje o relatório sai 0 e o `--aplicar` sai 2 pelo mesmo estado, então o relatório promete uma migração que não vai acontecer (Luís, Q1: recomendado). A checagem de `contas.pessoal` e do `oauthAccount` sobe para antes do retorno do relatório, com saída 2 e a mesma mensagem, como as outras recusas do plano.
- **D3 — A mensagem da recusa manda rodar `conta.cjs preparar pessoal`** — porquê: o `preparar` já registra a conta a partir do login quando não há registro (`scripts/conta.cjs`, trecho do `oauthDoLogin`); o `status` que a mensagem cita hoje também exige o `oauthAccount` e devolve à mesma recusa (Luís, Q2: recomendado).
- **D4 — O registro da pessoal recusa e-mail igual ao da conta `team` já registrada** — porquê: com o mesmo e-mail, `contaDoEmail` devolve sempre `team`, e um registro errado não tem conserto pelo CLI. A recusa sai com 2 antes de qualquer escrita, no relatório e no `--aplicar`. Sem chamada de API: a bateria não tem servidor falso, e a primeira troca já confere a identidade pela API (Luís, Q3: recomendado).
- **D5 — A mescla do `.claude.json` relata o que gravou** — porquê: um `mcpServers.x` que uma sessão gravou no destino entre o plano e o aplicar vence (correto), mas o relatório ainda conta "+1 mcp". A etapa `.claude.json` devolve os nomes gravados e os mantidos do destino, e o relatório do `--aplicar` usa essa lista, nomeando os mantidos. Entra o teste com o destino alterado entre plano e aplicar, que fica vermelho se a guarda `!Object.hasOwn(mcpServers, n)` sair.

## Avaliado e descartado
- Conferir a identidade da pessoal pela API no `unificar` (D4): pede rede e um stub novo; a conferência já acontece na primeira troca.
- Relatório avisando a recusa mas saindo 0 (D2): deixa o relatório e o `--aplicar` discordando sobre o mesmo estado.

## Fora de escopo
- O resto do `conta.cjs` e das outras etapas do `unificar`.

## Varredura
docs/rainforest/varredura/2026-10-15-conta-achados.txt — a única issue aberta com esses termos é a própria #503; nenhum PR aberto mexe nesses arquivos.

## Em aberto
nada
