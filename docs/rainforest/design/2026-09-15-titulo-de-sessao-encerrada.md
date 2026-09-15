# Marcar no título da sessão, no SessionEnd de /exit, se o fluxo fechou ou onde parou

## Objetivo

Fazer o `/resume` distinguir sessão encerrada de sessão em aberto. Hoje toda
transcrição é igual na lista — pergunta de 30 segundos, fork de compactação e
fluxo interrompido no `verificar` aparecem com o mesmo peso. Um hook de
`SessionEnd` passa a escrever o estado do fluxo no título da própria sessão, e o
título é o que o picker exibe **e** o que a busca dele casa.

## Decisões fechadas

- **D1 — Duas fontes de verdade, um escritor** — porquê: o `fechar` sabe que
  fechou, mas só o `SessionEnd` roda nas sessões que **não** fecharam; as duas
  informações são complementares, não concorrentes.
- **D2 — Só daqui pra frente; nada de retro-marcar as ~1.120 sessões vivas** —
  porquê: o vínculo sessão ↔ fluxo não existe historicamente, então retro-marcar
  seria adivinhação, e título errado é pior que título ausente. Com
  `cleanupPeriodDays: 14` o passado envelhece sozinho.
- **D3 — Nome manual (`/rename`) tem precedência; o hook só prefixa** — porquê:
  `custom-title` é `last-wins`, então o hook sobrescreveria um nome escolhido a
  dedo. Prefixar dá as duas coisas: o nome continua achável e o estado vem de
  graça.
- **D4 — Quem escreve é o `SessionEnd`; o `fechar` não toca no transcript** —
  porquê: anexar no transcript de uma sessão **viva** disputa o arquivo com o
  writer do CC (no Windows a atomicidade do append é mais fraca que no POSIX), e
  um `[ok]` gravado às 14h mente se o fluxo reabrir às 16h. Lendo no fim, o
  título reflete o estado final. Custo aceito: o caso "fechou" passa a depender
  da mesma medição de flush que o caso "aberto".
- **D5 — O vínculo sessão ↔ fluxo mora no `sessoes.json` do plugin, não no
  repositório** — porquê: o estado comitado não está onde o hook consegue
  lê-lo. O `cwd` da sessão é o **checkout principal**; o arquivo de estado de um
  fluxo em andamento vive na branch de trabalho, dentro do worktree; e o
  `fechar` (passo 3) **remove o worktree** antes do `/exit`. Sob o desenho
  anterior o caso `[ok]` — o primeiro que o usuário pediu — nunca dispararia. O
  `sessoes.json` já existe na raiz do plugin, já é gitignorado, já é indexado
  por `session_id` com `cwd`, e já é escrito por `heartbeat.cjs` e
  `contexto-sessao.cjs`. No `/exit` o hook lê só esse arquivo e **não toca no
  repositório**: nem branch, nem worktree vivo, nem merge.
- **D6 — O marcador é palavra entre colchetes: `[ok]` e `[aberto: <estágio>]`** —
  porquê: a busca do `/resume` casa contra o `customTitle`, e ninguém digita `⋯`.
  Com palavra, `/resume` + digitar `aberto` devolve exatamente a lista de
  pendências, que é a pergunta que originou o trabalho.
- **D7 — O hook só age em `reason === "prompt_input_exit"`** — porquê: `clear` e
  `resume` são continuação, não fim (o `/clear` grava `continued-in` ligando a
  sessão velha à nova, e o picker usa isso pra não listar fragmento da mesma
  cadeia); `logout` é raro; e `other` inclui crash, onde um `[ok]` mentiria.
  Consequência aceita: fechar o terminal na mão não dispara hook nenhum, e a
  sessão fica sem título — que lê corretamente como "não encerrei direito".
- **D8 — `[ok]` só quando TODOS os fluxos tocados fecharam; qualquer um aberto
  joga o título para `[aberto: <estágio menos avançado>]`** — porquê: o título
  responde uma pergunta só ("posso esquecer esta sessão?") e um fluxo aberto já
  responde não. Listar dois estoura o espaço do picker sem mudar a ação.
- **D9 — Se o transcript ainda estiver sendo escrito: 3 tentativas / ~300 ms de
  teto, e desiste calado** — porquê: o CC **espera** os hooks de `SessionEnd`
  (`await`), então há orçamento real; e o modo de falha coincide com o sinal
  correto — sessão sem título já significa "não encerrei direito". O teto é
  número, para o `verificar` medir contra ele.
- **D10 — Sem `/rename`, o hook prefixa o `aiTitle` que já está no transcript;
  sem `aiTitle`, cai para o slug do fluxo** — porquê: `customTitle` ganha do
  `aiTitle`, então escrever só o marcador apagaria um rótulo que já está bom
  ("Limpar sessões finalizadas"). Nas 12 sessões mais recentes deste projeto, 10
  têm `aiTitle` útil; as 2 sem são sessões-fantasma de 267 bytes.
- **D11 — Reentrada tira o marcador antigo antes de escrever o novo** — porquê:
  sessão retomada e encerrada de novo viraria `[ok] [aberto: revisar] nome`.
- **D12 — "Tocar um fluxo" é rodar QUALQUER verbo do `estado.cjs` com este
  `CLAUDE_SESSION_ID`: `iniciar`, `exigir` e `marcar` gravam o carimbo** —
  porquê: carimbar só no `marcar` deixa de fora a sessão que abre o fluxo e
  entrevista sem fechar estágio (esta aqui), e a que abre `executar`, despacha
  agente e morre antes de marcar. As duas são exatamente as sessões que o
  usuário precisa reconhecer como abertas. O que fica gravado por fluxo é o
  **último estágio conhecido**, que é o que o título quer dizer. O
  `estado.cjs` já lê `CLAUDE_SESSION_ID` (linha 1026), então a peça existe.
- **D13 — O hook mora em `hooks/hooks.json` do plugin, síncrono** — porquê: são
  duas config dirs de escopo usuário nesta máquina (`~/.claude` e
  `~/.claude-personal`), mantidas à mão e já divergidas uma vez (2026-08-10); o
  plugin está habilitado nas duas, então é o único lugar onde a regra vale para
  as duas. Síncrono porque os três hooks de `SessionEnd` de hoje são
  `async: true` (fire-and-forget) e este precisa ser esperado.

## Avaliado e descartado

- **Carimbar a sessão dentro do JSON de estado comitado, em
  `docs/rainforest/estado/`** (era o D12 da rodada 4). Morreu na rodada 5 por
  três fatos somados: o `cwd` da sessão é o checkout principal, o estado de um
  fluxo aberto vive na branch de trabalho dentro do worktree, e o `fechar`
  remove o worktree antes do `/exit`. Bônus da troca: some o inchaço de diff que
  essa decisão tinha aceitado nos 6 repos que usam o fluxo.
- **Ensinar o hook a varrer `git worktree list` a partir do `cwd`.** Resolveria o
  worktree, mas não o `fechar` que apaga o worktree antes de a sessão terminar —
  justamente no caso `[ok]`.
- **`ended-by-model`, a outra marca que o formato já tem.** Só o
  `EndConversation` a escreve, e sessão retomada com ela **trava**: recusa
  compactação, slash command e subagente. É cadeado, não marca.
- **`fechar` escrevendo o `[ok]` na hora, dentro da sessão viva** (era o D1 da
  rodada 1). Morreu por dois motivos levantados na rodada 2: disputa o arquivo
  com o writer do CC, e o título envelhece se o fluxo reabrir.
- **Marcar também em `reason: clear`.** Morreu ao achar o `continued-in`: no
  `/clear` a sessão não acabou, continuou em outra — o título iria para um
  fragmento que o picker já esconde, e o CC carrega o título adiante sozinho
  (`clearedSessionTitle`).
- **Símbolo (`✅` / `⋯`) como marcador.** Ilegível na busca do picker, que é
  metade do valor do trabalho.
- **`estado.cjs concluido` sem vínculo de sessão.** Medido neste repo: 3 fluxos
  abertos, sendo 2 que nenhuma sessão nova tocou — todo título nasceria dizendo
  `[aberto: executar]` por um fluxo de agosto.

## Fora de escopo

- **Apagar sessões.** Não existe comando, e o picker do `/resume` (CC 2.1.272)
  não tem tecla de apagar nem de arquivar. Resolvido por outro caminho fora
  deste fluxo: `cleanupPeriodDays: 14` nas duas config dirs.
- **Sessões em repo sem fluxo** — incluindo `inovacao`, onde a janela de
  trabalho roda. Saem sem título; o hook fica calado. É consequência de D5/D12,
  não uma feature a construir.
- **Aviso falado no fim da sessão.** O `fechar/SKILL.md` (linha 168) recusou
  pendurar o `concluido` no `SessionEnd` por barulho — "um vigia que fala
  sozinho toda sessão". Este trabalho não reabre essa decisão: título escrito
  numa sessão já encerrada não fala com ninguém.
- **Issue #180** (estágio que despacha agente em background e perde a aposta em
  sessão não interativa). O título vai **relatar** o fluxo pela metade; não
  impede que fique.

## Em aberto

- **Premissa não medida (D4/D9): o transcript está fechado quando o hook de
  `SessionEnd` roda.** Sabemos que o CC **espera** o hook (`await` nos dois
  pontos de disparo), mas não que já tenha liberado o arquivo. A primeira tarefa
  do plano é a medição — o hook loga `stat(transcript_path).size`, espera
  500 ms, loga de novo; tamanhos iguais = seguro anexar. **Se reprovar, D4 e D9
  voltam ao brainstorm**, porque o fallback restante é um caminho que esta
  rodada já descartou.
