# Conta e vigia: ronda de teste sem escrita, aviso da pasta manual e estado que segue o login

## Objetivo

Fechar três Issues de conta e vigia:

- **#581:** a ronda `-Teste` do `run-vigia.ps1` deixa ligada toda tool do WhatsApp que não está na lista negra.
- **#584:** a pasta em troca manual nunca recebe aviso, mesmo com a conta em uso no limite.
- **#585:** um `/login` feito fora do `conta.cjs` deixa o `estado.json` divergente, e o `/conta trabalho` moveria o login novo para a reserva errada.

Para quem e quando: o próprio usuário, nas duas pastas de conta da máquina dele (trabalho e pessoal), com o vigia agendado a cada minuto. A troca e a volta automáticas continuam como estão. O `-Teste` passa a usar outro mecanismo de trava, e a reconciliação se soma ao `registrarCasas`.

## Decisões fechadas

- **D1 — O `-Teste` nega por lista de permitidas, com `dontAsk` (#581)**: em `vigias/run-vigia.ps1`, a ronda de teste troca `--dangerously-skip-permissions` mais `--disallowedTools` por `--permission-mode dontAsk --allowedTools <lista>`.
  - A lista leva as nativas que a ronda usa (`Bash, Read, Write, Edit, Glob, Grep`), o servidor `mcp__gmail-leitura` e as de leitura do WhatsApp: `list_chats`, `list_messages`, sete `get_*` de conversa e contato (`get_chat`, `get_contact_chats`, `get_direct_chat_by_contact`, `get_group_info`, `get_last_interaction`, `get_message_context`, `get_user_info`), `search_contacts`, `resolve_contact`, `check_whatsapp`.
  - Tool nova do bridge entra negada por padrão.
  - A ronda normal não muda: segue com bypass e com a lista negra do `mcp__gmail`.
  - O prefixo do prompt de teste continua: ele pede a mensagem entre `---INICIO---` e `---FIM---`, e diz que a falta das tools de envio não é bridge fora do ar.
  - porquê: medido em 2026-10-23 com `claude -p --model haiku --permission-mode dontAsk --allowedTools mcp__whatsapp__list_chats`, a chamada a `mcp__whatsapp__get_bridge_status`, que ficou fora da lista, voltou `Permission to use mcp__whatsapp__get_bridge_status has been denied because Claude Code is running in don't ask mode`. A Issue mediu que `--allowedTools` com bypass não restringe nada. A tool negada continua aparecendo na lista que o modelo vê, então o critério mede a chamada negada, não a lista.

- **D2 — Contra quem a trava do `-Teste` protege (modelo de ameaça)**: a trava protege contra o modelo da ronda de teste chamar tool MCP que muda estado: enviar, sair de grupo, arquivar, marcar como lida, parear.
  - Fica fora: o `Bash` falando direto com o bridge HTTP (por exemplo `curl` na porta 3005), porque a ronda de teste roda `node` como a real e fechar o `Bash` a quebraria.
  - Também fica fora a ronda normal, que precisa enviar.
  - O revisor recebe este parágrafo desde a rodada 1. Contorno por `Bash` é critério de parada, não achado.
  - porquê: escolha do usuário (Q2, 2026-10-23).

- **D3 — Pasta manual no limite gera aviso uma vez por estouro (#584)**: em `scripts/lib/conta-decidir.cjs`, a pasta com `manual: true` deixa de ser pulada em silêncio.
  - Quando a conta em uso dela tem `five_hour` ou `seven_day` em `>= trocarEm`, `decidir` devolve `{ tipo: 'avisar', pasta, conta, motivo }`. O `motivo` traz o limite, o percentual e o `resets_at`.
  - Ela continua sem nenhuma ação que mova credencial, como manda a D8 do design de troca de conta.
  - O `vigiar` (`scripts/conta.cjs`) registra o evento `manual_no_limite` **uma vez por estouro**: a chave é pasta, limite e `resets_at`, e a deduplicação olha o histórico inteiro, não a janela de 1 h do `registrarAviso`.
  - O mod (`hooks/conta-puro.mjs`, `frase`) diz: "a pasta <pasta> está na conta <conta>, que chegou a <n>% (<limite>); /conta <pasta> devolve".
  - porquê: em 18 a 22/10 a pasta de trabalho ficou 4 dias na conta pessoal a 100% da semana sem aviso nenhum. Uma vez por estouro informa sem virar ruído (Q3).

- **D4 — O estado segue o login, nos dois sentidos (#585)**: quem tem a trava (o `vigiar`, o `status` e o `trocar`) reconcilia o estado no mesmo passo do `registrarCasas`.
  - A reconciliação dispara quando o login da pasta, conferido no servidor por `API.dono`, é de uma conta **registrada** (`estado.contas[*].email`) diferente de `estado.pastas[P].conta`.
  - O que ela grava: `conta` passa a ser a conta do login, `manual` fica `conta !== casa`, `travouPor` vira `null`, e entra o evento `reconciliado` com o antes e o depois.
  - Vale para "fora" → "em casa" (o caso da Issue) e para "em casa" → "fora" (`/login` com a outra conta).
  - Login de conta não registrada mantém só o aviso `identidade_divergente` de hoje.
  - Nenhuma credencial se move.
  - Sem a trava, o `status` não grava nada e imprime uma linha de divergência na pasta.
  - No `trocar`, a reconciliação roda antes da comparação `de === para`. Com isso, `/conta trabalho` sobre uma pasta que já está na conta de trabalho sai "já está na conta" sem tocar no `.credentials.json`.
  - porquê: o estado é cópia e o login é a fonte. O vigia roda a cada minuto, então a divergência se cura sozinha (Q4).

- **D5 — Login guardado órfão é arquivado, não apagado (#585)**: quando a reconciliação põe a pasta em casa e existe `estacionado-<pasta>.json` com credencial, o arquivo é renomeado para `estacionado-<pasta>.orfao-<AAAAMMDD-HHMMSS>.json`, e o evento `reconciliado` cita o nome.
  - porquê: o `mover` (`scripts/lib/conta-mover.cjs:101`) recusa a troca com `saida_ocupada` quando o estacionado já tem credencial, e a próxima troca automática daquela pasta falharia para sempre. Apagar perde um login que ainda vale no servidor (Q5).

- **D6 — Baterias, docs e versão 1.74.0**:
  - **Baterias:** casos novos em `scripts/testa-conta-decidir.cjs` (D3), em `scripts/testa-conta.sh` (D3 a D5), em `hooks/testa-mod-conta.cjs` (frases novas) e uma bateria do `-Teste` que confere os argumentos montados pelo `run-vigia.ps1` (D1).
  - **Docs e versão:** o CHANGELOG ganha a seção 1.74.0, e o README fala do `-Teste` e da reconciliação. A versão sobe nos dois `plugin.json`.
  - porquê: são dois eventos novos e um comportamento novo, então MINOR (Q6). Sai um PR só para as três Issues.

## Avaliado e descartado

- **`--allowedTools` com `--dangerously-skip-permissions`:** não restringe nada. Com bypass, toda tool já está aprovada (medido na #581).
- **Negar o servidor `mcp__whatsapp` inteiro no `-Teste`:** derruba também a leitura, e o `--disallowedTools` vence o `--allowedTools`, então não dá para negar o servidor e liberar as tools de leitura.
- **Lista negra derivada da listagem de tools do bridge:** exigiria falar o protocolo MCP com o servidor dentro do `run-vigia.ps1`. O `dontAsk` resolve o mesmo com uma flag.
- **Só avisar no `status` e recusar no `trocar`, sem reconciliar:** deixa a pasta presa até o usuário rodar um comando, e o vigia segue pulando a pasta manual divergente.
- **Repetir o aviso da pasta manual de hora em hora:** ruído durante dias de semana travada (Q3).

## Fora de escopo

- O `Bash` da ronda de teste falando com o bridge HTTP (D2).
- A trava por lista de permitidas na ronda normal.
- Refazer a reserva pessoal ausente depois de um `/login` fora do `conta.cjs`. O `status` já mostra `reservas: ... pessoal ausente`, e o caminho é o `preparar`, que já existe.

## Varredura

`docs/rainforest/varredura/2026-10-23-conta-vigia.txt` — as Issues abertas são só a #581, a #584 e a #585. O histórico de `disallowedTools` (`1c9bf7bf`, "-Teste tira as tools de envio da sessao") confirma a origem da lista negra, depois do incidente de 2026-09-28. O `identidade_divergente` nasceu no PR #501 (troca automática) e é o aviso que a D4 mantém para conta não registrada. Nenhuma branch, PR ou ideia aberta trata destes defeitos, então nada foi reaproveitado.

## Em aberto
- nada: as seis decisões fecharam na rodada 1 (Q1 a Q6, recomendadas).
