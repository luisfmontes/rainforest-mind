# Troca automática de conta Claude pelo uso

## Objetivo

Quando a conta de uma pasta de configuração (`~/.claude`, team, ou `~/.claude-personal`, max) chega ao limite, as
sessões daquela pasta seguem trabalhando na outra conta sem reiniciar, e voltam sozinhas quando o limite zerar. O
Luís também troca na mão quando quiser.

## Decisões fechadas

- **D1 — A troca vale nos dois sentidos, trabalho → pessoal e pessoal → trabalho, e misturar a conta da organização
  com a pessoal é permitido** — porquê: o Luís é o administrador da organização; e medido em 2026-10-10, cada conta
  trava por um limite diferente (team em `weekly_all` 53%, pessoal em `session` 15%), então os dois sentidos ocorrem.
- **D2 — Cada conta tem um segundo login, de reserva, guardado fora das duas pastas; trocar é MOVER, nunca copiar** —
  a reserva da conta com folga entra no `.credentials.json` da pasta no limite, e o login próprio dessa pasta vai
  para a reserva. Só a chave `claudeAiOauth` se move; `mcpOAuth` e `trustedDeviceToken` ficam onde estão. O
  `oauthAccount` do `.claude.json` da pasta acompanha o login que entrou — porquê: o refresh token é de uso único e a
  trava de renovação é por pasta; credencial copiada para duas pastas derruba as duas (claude-cockpit, gotcha #1,
  sete sessões caídas em 2026-08-04). Dois logins separados da mesma conta convivem (o "seal test" deles).
- **D3 — A pasta volta sozinha para a conta dela quando o limite que travou zerar**, pelo `resets_at` que o servidor
  devolve — porquê: sem volta, a conta errada segue sendo gasta até alguém lembrar.
- **D4 — Gatilho: a conta da pasta passa de 97% na janela de 5 h ou na semana; destino só se estiver abaixo de 60%
  (5 h) e 85% (semana)**. Os quatro números ficam num arquivo de configuração — porquê: são os valores do
  claude-cockpit, e ajustar não pode exigir release.
- **D5 — Um vigia único, tarefa agendada do Windows a cada 1 minuto, com trava, consulta o uso e faz a troca** —
  porquê: troca disparada de dentro de cada sessão corre contra as outras. Medido: o node que consulta o endpoint
  ocupa ~70 MB por ~0,7 s e nada entre execuções; um processo residente ocuparia 50–70 MB o tempo todo.
- **D6 — Toda troca e toda volta viram aviso nativo nas sessões abertas e uma linha de log** — porquê: troca
  silenciosa faz ler o consumo da conta errada.
- **D7 — Troca manual a qualquer momento: `/conta pessoal` ou `/conta trabalho` dentro de qualquer sessão, e `/conta`
  sem argumento mostra o uso das duas contas e qual login está em cada pasta** — porquê: pedido do Luís; o status
  substitui o painel do cockpit no lugar onde ele já trabalha.
- **D8 — Troca manual desliga a volta automática daquela pasta até a próxima troca manual** — porquê: a escolha dele
  não pode ser desfeita pelo vigia.
- **D9 — O primeiro `/conta` prepara as reservas: um login no navegador por conta, conferido no servidor
  (`/api/oauth/profile`) antes de gravar; a troca automática só liga com as duas reservas prontas** — porquê: sem
  reserva não há troca sem copiar credencial.
- **D10 — Identidade sempre perguntada ao servidor (`/api/oauth/profile`), nunca ao `.claude.json`; uso sempre de
  `/api/oauth/usage`, com cache único e espera após HTTP 429** — porquê: o cache do `.claude.json` divergiu do token e
  fez o claude-cockpit gravar o login de uma conta por cima de outra (2026-08-05); o endpoint de uso tem limite de
  taxa por conta.
- **D11 — Antes de mover, os dois logins precisam de 30 min de vida no access token; mover relê os dois arquivos
  logo antes de gravar e desiste se algum mudou; cada gravação é relida e, se não bater, desfeita** — porquê: sessão
  renovando no meio do movimento gasta o refresh token que acabou de sair (claude-cockpit, desenho da troca).
- **D12 — O `/transferir claude` sai neste fluxo, depois que a troca estiver provada em uso real; o
  `/transferir codex` fica** — porquê: com a conta trocando por baixo da pasta, mudar a sessão de pasta perde o
  motivo; tirar só depois evita ficar sem nenhum dos dois.

## Avaliado e descartado

- **Copiar o `.credentials.json` de uma pasta para a outra** (era a forma registrada em
  `2026-10-09-mods-pr-e-plugins.md`): derruba as duas contas pelo refresh token de uso único — D2.
- **Trocar os dois arquivos entre si, sem reserva**: dispensa o login extra, mas joga as sessões da outra pasta na
  conta esgotada.
- **Instalar o claude-cockpit**: só macOS por código (chaveiro, `launchd`) — `relatorios/2026-10-10-claude-cockpit-troca-de-conta.md`.
- **Proxy de contas (CLIProxyAPI)**: descartado em 2026-10-09, mantido.
- **Vigia como processo residente**: 50–70 MB o tempo todo contra ~0,7 s por minuto da tarefa agendada — D5.

## Fora de escopo

- Mais de duas contas.
- Previsão de quando a cota acaba (o "forecast" do claude-cockpit).
- Abrir a janela de 5 h das contas ociosas (o `claude-ping` do claude-cockpit).

## Varredura

docs/rainforest/varredura/2026-10-10-troca-de-conta.txt — achou o `/transferir claude` (PR #415), que levou à D12;
o design de 2026-10-09 com a troca como fluxo próprio; e o PR #490 com a avaliação do claude-cockpit, de onde vêm
D2, D10 e D11. Nenhuma Issue, branch ou ideia já fazia a troca.

## Em aberto

- **Medir no plano, antes de ligar a troca automática:** com a pasta `~/.claude` rodando no login pessoal, as regras
  da organização (o `cc-plugin-sec-default` e o que mais vier por conta da org) continuam valendo naquelas sessões?
  O resultado vira critério do plano, não decisão nova.
