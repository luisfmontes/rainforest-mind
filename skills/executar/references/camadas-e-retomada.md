# Camadas, retomada e painel do `executar`

## Despachar por camada

As camadas saem do `depende de:` do plano. O `paralela:` não é mais exigido; se um
plano antigo ainda o trouxer, ele passa com aviso. Antes do primeiro despacho:

```
node scripts/conferir-fluxo.cjs camadas --slug <slug>
```

O comando imprime as camadas em JSON. Com exit 0, as tarefas de uma mesma camada vão
**juntas**, numa resposta só com várias chamadas de `Agent`, e a camada seguinte só
sai depois de a anterior estar integrada. Exit 2 é recusa: ciclo, `depende de:`
citando tarefa que não existe, ou duas tarefas da mesma camada com `arquivos:` em
comum. A mensagem nomeia as tarefas. Quem conserta é o plano, não o despacho.

A recusa confere só o que está declarado. Uma tarefa que mexe em arquivo fora do
`arquivos:` é pega pelo `creep` do `revisar`. Uma dependência real que ninguém
escreveu no plano não é pega.

## Integrar na ordem fixa

Cada tarefa entra na branch do fluxo nesta ordem, e só nela:

1. conferência: `conferir-entrega.cjs` e a re-execução de `conferir-mutacao.cjs`;
2. commit com o trailer: `git commit -m "<titulo>" --trailer "Rainforest-Tarefa: <slug>#<n>"`;
3. `marcar`, levando o número em `integradas`:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status parcial --json '{"tarefas_ok":N,"tarefas":M,"integradas":[<n>]}'
```

`integradas` se funde com o que já estava lá e persiste até o `ok`, como `carimbos`.
É o trailer que prova a integração, não o JSON: tarefa sem commit com trailer nunca
conta como `integrada`, mesmo que apareça no estado.

Ao despachar, registre o agente em `em_voo`, com `tarefa` começando pelo número
(`"3 painel"`). É por esse registro que uma sessão nova encontra o que ficou no ar.

## Retomar um `executar` pela metade

Depois de queda, compactação ou troca de conta, a sessão que pega o fluxo roda, antes
de despachar qualquer coisa:

```
node scripts/estado.cjs retomar --slug <slug>
```

A saída é JSON: `tarefas` (`numero`, `estado`, `camada`), `re_marcar`, `redespachar`
e `proxima_camada`. O `estado` de cada tarefa é `integrada`, `em_voo` ou `pendente`.

- `re_marcar`: o trailer já está na branch, mas o estado não contou. Rode o `marcar`
  com esses números em `integradas` e não despache de novo.
- `redespachar`: a tarefa está em `em_voo`, mas não tem trailer. Despache do zero,
  com base nova. O worktree do agente anterior é sobra: confira-o pelo caminho antes
  de removê-lo.
- `proxima_camada`: o que falta despachar agora. `null` quer dizer que tudo está
  integrado e o `executar` pode fechar `ok`.

## Painel

Cada `marcar` de `executar`, `revisar` e `verificar` regenera
`<dados>/fluxos/<slug>/painel.html`. `<dados>` é a raiz de dados que
`hooks/lib/raiz.cjs` resolve, a mesma do gate de teto. Para gerar fora do `marcar`:

```
node scripts/painel-fluxo.cjs gerar --slug <slug>
```

O comando imprime o caminho. O painel mostra um cartão por tarefa (estado, camada e o
agente em voo) e um resumo: o que está em voo, o que falta, o estágio atual, o último
`marcar`, o veredito do `revisar` e se o fluxo parou. Se a geração falhar, sai um
`aviso: painel` no stderr, e o exit do `marcar` não muda.

O painel não avisa ninguém. Quem notifica é a sessão, com `PushNotification`, em três
momentos: o laço bateu no teto, um estágio fechou `flaky`, ou o `executar` fechou `ok`.
