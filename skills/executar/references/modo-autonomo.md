# Modo autônomo: do plano aprovado até o PR mergeado

Design: `docs/rainforest/design/2026-10-13-executar-autonomo.md`. É um enxerto do `execute` do
`wildz-data`, de Rafael Siqueira, que roda "until completion, ceiling hit, or unresolvable error".

## Quando vale

Vale só quando a chave `executar-autonomo` está ligada:

```
node -e "console.log(require('./hooks/lib/config.cjs').resolverConfig().valores['executar-autonomo'])"
```

O comando roda na raiz do repo do plugin. Se ele der erro, conte a chave como desligada. Ele lê o config do checkout principal, então num worktree vale o que está na `main`.

A chave vem desligada por padrão. Com ela desligada, nada aqui vale: as skills param onde sempre pararam.

Ligada, ela vale de `plano ok` até o PR mergeado (D1). O design e o plano continuam pedindo a palavra do usuário. Daí em diante, `executar`, `revisar` (o laço), `verificar` e `fechar` seguem um atrás do outro, sem perguntar entre estágios e sem esperar resposta.

## As seis paradas (D2)

O fluxo só para e chama o usuário nestes casos. Qualquer outro tropeço é resolvido no próprio fluxo.

| parada | como aparece |
|---|---|
| achado de design | `critica-do-revisor.cjs` sai 3 (achado `[design]`) |
| 3ª reprovação seguida | `exigir --estagio executar` recusa pelo teto de tentativas |
| `flaky` terminal | o estágio fecha `flaky` (`laco.md`, Flaky) |
| teto de despachos | o `gate-teto-despachos` nega o `Agent` |
| ambiente quebrado | exit 69 de qualquer `conferir-*`, `integrar-tarefa`, `publicar-branch` (gh ausente, sem auth, rede) ou `rodar-longo`; `estado` do `rodar-longo` com `morto` (exit 4) |
| conflito real com a `main` | `publicar-branch.cjs publicar` sai 3 listando um arquivo fora destes: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, ou o `README.md` com conflito fora da linha do selo |

Conflito que fica só nesses quatro arquivos não é parada. O tratamento:
1. `git merge origin/<padrão>` na branch do fluxo.
2. Nos dois `plugin.json` e no selo do README, fica a versão do fluxo.
3. No CHANGELOG ficam as duas entradas, a do fluxo por cima.
4. `publicar` de novo.

Se o `README.md` conflitar fora da linha do selo, é parada.

Em cada parada:
1. `PushNotification`, numa linha que comece pelo que o usuário precisa fazer. Exemplo: `executar-autonomo parou: achado [design] na tarefa 3 — decida antes de seguir`.
2. A explicação completa vai na resposta da sessão.
3. O estado fica com o estágio parado, como já fica hoje.

## Aviso (D3)

`PushNotification` só em dois momentos:
- em cada parada da tabela acima;
- no fim, com o PR mergeado. Exemplo: `executar-autonomo: PR #N mergeado, 1.66.0 — 2 decisões tomadas sem você no PR`.

Progresso de rotina não notifica: tarefa integrada, revisor reprovou e o laço seguiu, CI rodando.

## Decisão no meio do caminho (D4)

Quando surge uma decisão que, fora deste modo, viraria `Q` para o usuário:
1. Aplique a resposta recomendada.
2. Registre:

```
node scripts/estado.cjs decidir --slug <slug> --pergunta "<a pergunta>" --escolha "<o que foi aplicado>" --porque "<por quê>"
```

3. No `fechar`, cole a saída de `node scripts/estado.cjs decididos --slug <slug>` no corpo do PR, antes de `## Perigo de merge`. Com a lista vazia, o comando não imprime nada e a seção não entra.

A exceção à regra 16 tem um limite. Decisão que muda uma `D<n>` do design não entra aqui: é achado `[design]` e para o fluxo.

## Agentes e integração (D6, D7)

- **Agentes.** Rodam em segundo plano (`run_in_background`), com `isolation: "worktree"`. A volta de cada um acorda a sessão. Não use turno longo com `Agent` em primeiro plano. Registre cada agente em `em_voo` ao despachar.
- **Integração.** Cada tarefa entra por um comando só, rodado no worktree do fluxo. Como a mutação roda dentro dele, ele vai sempre pelo `rodar-longo` (abaixo):

```
node scripts/rodar-longo.cjs iniciar --saida <arq> -- node scripts/integrar-tarefa.cjs --slug <slug> --tarefa <n> --worktree <worktree do agente> --base <hash do briefing> --head-antes <HEAD do principal no despacho> --sujo-antes <arquivo com o porcelain do principal no despacho> --titulo "<assunto do commit>"
```

  `--base` é o HEAD do fluxo que foi no briefing. `--head-antes` e `--sujo-antes` são do checkout principal (a `main`), não do fluxo. É o principal que o script confere, a menos que venha `--repo-principal`. Escrita do agente no worktree do fluxo não é vigiada aqui: quem a pega é o índice com stage prévio, recusado, e o `creep` do revisor.

  - Exit 0: a tarefa está integrada, com todos os commits do agente num commit com trailer, mais o `marcar`. Se o JSON trouxer `"worktree_removido":false`, remova o worktree do agente por caminho.
  - Exit 2: recusado. O passo vem no JSON (`conferir-entrega`, `indice-sujo`, `base`, `apply`, `mutacao`, `commit`, `retomada`). A branch fica como estava, e o executor é redespachado com o motivo, como no laço. Se o passo for `apply`, a entrega não encaixa no fluxo atual: redespache a partir do HEAD novo do fluxo.
  - Exit 69: é parada. Se o commit já saiu e só o `marcar` falhou, rodar o mesmo comando de novo retoma sem commit novo.

- **Processo longo.** Bateria ou mutação que pode passar de 10 minutos não roda direto no Bash:

```
node scripts/rodar-longo.cjs iniciar --saida <arquivo> -- <comando>
node scripts/rodar-longo.cjs estado --saida <arquivo>
```

  O `estado` sai 3 enquanto o comando roda. Quando termina, sai 0 e imprime `exit <N>`. Se o vigia morreu sem registrar o fim, sai 4 com `morto`, e isso é ambiente quebrado. Para esperar, arme um Monitor com um laço enquanto o `estado` sair 3. Depois leia o `exit <N>` e a saída do comando no `<arq>`.
