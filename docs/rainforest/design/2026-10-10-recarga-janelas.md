# Design: recarga do plugin em todas as janelas por marcador

## Objetivo

Fluxo `2026-10-10-recarga-janelas`. Hoje o `/plugins-em-dia` só recarrega (ou avisa) a janela
que atualizou; as outras seguem com a versão velha carregada até alguém rodar
`/reload-plugins` nelas. Enxerto do protocolo de marcador do `wildz-data` do Rafael Lopes
(autorização dele, 2026-10-09; `plugin/scripts/reload_marker.mjs`). Ideia de origem:
`plugins-em-dia-recarga-multi-janela`; a sonda da conta de trabalho de que ela dependia foi
dispensada pelo Luís em 2026-10-10 ("o rafael já testou isso e tá funcionando").

## Fatos medidos

- `hooks/plugins-em-dia.ts` roda na abertura de cada sessão interativa e a cada `PERIODO_MS`, com
  trava de 30 min em `$.store` (`ultima`): numa rodada só uma janela atualiza; as outras pulam e
  nunca ficam sabendo que o disco mudou.
- O engine tem `$.fs.read` e `$.fs.write(path, text)` (eventos `fs.read`/`fs.write`, medido no
  binário do CLI) e nenhum evento para criar pasta. A pasta de dados do plugin
  (`<config>/plugins/data/rainforest-mind-*`) não existe na conta de trabalho (revisão); a pasta
  `<config>/plugins/`, onde está o `installed_plugins.json`, existe em toda conta com plugin.
- `/reload-plugins` recarrega o módulo do mod: o estado de módulo zera e o "carregado em" anda.
- O harness de `claude plugin test` comprime o tempo: cada disparo de timer custa ~50 ms lá, e o
  timer de 5 s vira centenas de disparos no teste do relógio (~77 min simulados e um salto de 24 h),
  estourando o teto de 5 s dele mesmo com a conferência retornando antes de qualquer chamada. Com
  `RAINFOREST_RECARGA=off` o timer nem é criado, e o teste do relógio liga essa chave (medido em
  2026-10-10). Em produção o timer corre em tempo real.
- O Rafael usa dois marcadores (um por sessão, escrito pelo hook de SessionStart dele, e um
  compartilhado) e uma chave por sessão no `$.store`. Aqui a atualização roda dentro do mod,
  não num hook com trava própria.

## Decisões fechadas

- **D1 — Um marcador compartilhado, gravado por quem atualizou**: depois de uma rodada em que algum
plugin subiu de versão, o `plugins-em-dia` grava `{"v":1,"at":<ms>}` em
`<CLAUDE_CONFIG_DIR ou HOME/.claude>/plugins/rainforest-mind-recarga.json` (ao lado do
`installed_plugins.json`) com `$.fs.write`; sem nenhum dos dois não há caminho e nada se grava. A janela que gravou marca o próprio `at` como tratado antes de gravar (ela já
recarrega ou avisa pelo caminho de hoje). Falha de escrita não quebra a rodada.

- **D2 — Cada janela confere a cada 5 s e age uma vez por marcador**: em sessão interativa, um
`$.clock.every(5000)` lê o marcador; age quando `at` é mais novo que o carregamento deste módulo e
que o último `at` tratado. Com `recarregarSozinho` ligado, roda `/reload-plugins`; desligado (ou com o
`/reload-plugins` recusado), um toast "plugins atualizados em outra janela - rode /reload-plugins", uma
vez por marcador. Marcador com `at` mais de 1 min no futuro é ignorado (sem laço de recarga).
`RAINFOREST_RECARGA=off` no ambiente desliga (o kill switch do Rafael).

- **D3 — Estado de módulo, sem chave no `$.store`**: "carregado em" e "último tratado" vivem no
módulo. O `/reload-plugins` recarrega o módulo e o "carregado em" passa do marcador; sem `$.store`
não há chave por sessão para podar.

- **D4 — Lógica pura separada e testada**: caminho, texto, leitura e a decisão (`deveRecarregar`)
em `hooks/recarga-puro.mjs` com bateria `.cjs`; a fiação com prova de engine em `*.test.tsx`.

- **D5 — Versão e docs**: MINOR (comportamento novo). CHANGELOG, CONTRIBUTING e README, com
crédito ao Rafael.

## Avaliado e descartado

- **Marcador por sessão (o `own` do Rafael)**: existe lá porque o update roda num hook de
  SessionStart com trava que pode perder a vez; aqui o update roda no mod, e a janela que
  atualizou já trata a si mesma.
- **Chave por sessão no `$.store`**: o estado de módulo basta (D3) e não acumula chave.
- **Recarregar sempre, ignorando `recarregarSozinho`**: a opção existe para quem não quer
  recarga sozinha; desligada, as outras janelas recebem só o aviso, como a que atualizou.

## Fora de escopo

- Issue #466 (achados menores do painel de PR e do plugins-em-dia, inclusive a corrida da trava
  de 30 min): está livre para outra sessão; com o marcador, duas janelas que atualizem juntas
  gravam o mesmo tipo de marcador e cada uma age uma vez.

## Varredura

docs/rainforest/varredura/2026-10-10-recarga-janelas.txt — só a #466 aberta no tema, e ela trata de outros achados do plugins-em-dia; nada sobre recarga em várias janelas.

## Em aberto

- Nada.
