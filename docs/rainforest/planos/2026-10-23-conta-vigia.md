# Plano: conta e vigia (#581, #584, #585)

Design: docs/rainforest/design/2026-10-23-conta-vigia.md

## O que não pode quebrar

- A troca e a volta automáticas das pastas que não são manuais nem divergentes: `scripts/testa-conta-decidir.cjs` e `scripts/testa-conta.sh` seguem com 0 falha.
- A pasta manual nunca recebe ação que mova credencial. O aviso é o único efeito novo (D8 do design 2026-10-10-troca-de-conta).
- Nenhuma credencial se move na reconciliação: o `.credentials.json` e as reservas mantêm o hash. Só o `estacionado-<pasta>.json` órfão muda de nome (D5).
- A ronda normal do `run-vigia.ps1`, sem `-Teste`, continua com `--dangerously-skip-permissions` e a lista negra do `mcp__gmail`.
- Gravação no estado ou nos eventos só com a trava. Sem a trava, o `status` só lê.

## Tarefas

### 1. `decidir` devolve `avisar` para a pasta manual no limite [tipo: implementar]
atende: D3
arquivos: `scripts/lib/conta-decidir.cjs`, `scripts/testa-conta-decidir.cjs`
depende de: nenhuma
prova-na-base: verde — o caso novo entra na bateria existente, que na base roda sem ele; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `scripts/lib/conta-decidir.cjs`
  de: `if (aviso) acoes.push(aviso);`
  para: `if (false) acoes.push(aviso);`
  bateria: `node scripts/testa-conta-decidir.cjs`
  fixture: `testa-conta-decidir.cjs, caso "pasta manual com a conta em uso a 100% na semana devolve avisar"`
pronto quando: com pastas `{ trabalho: { casa: 'team', conta: 'pessoal', manual: true } }` e `usos.pessoal.seven_day.utilization = 100`, `decidir` devolve exatamente uma ação `{ tipo: 'avisar', pasta: 'trabalho', conta: 'pessoal' }`. O `motivo` dela traz `seven_day`, `100` e o `resets_at`. Com o uso da pessoal a 50% na 5 h e na semana, a mesma pasta devolve `[]`. Nos dois casos não sai nenhuma ação `trocar` nem `voltar` para a pasta manual. Provado por `node scripts/testa-conta-decidir.cjs` com `0 falha`.

### 2. O vigia registra `manual_no_limite` uma vez por estouro, e o mod o diz [tipo: implementar]
atende: D3
arquivos: `scripts/conta.cjs`, `hooks/conta-puro.mjs`, `scripts/testa-conta.sh`, `hooks/testa-mod-conta.cjs`, `scripts/fixtures/conta/servidor.cjs`
depende de: 1
prova-na-base: verde — os casos entram nas baterias existentes; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (!avisoJaRegistrado(c, ev)) registrarEvento(c, ev);`
  para: `registrarEvento(c, ev);`
  bateria: `bash scripts/testa-conta.sh`
  fixture: `testa-conta.sh, secao "#584: pasta manual no limite", caso "segunda rodada com o mesmo estouro nao registra outro manual_no_limite"`
pronto quando: com o servidor falso de `testa-conta.sh` dando à conta pessoal `seven_day` 100 e a pasta de trabalho no estado `{ casa: team, conta: pessoal, manual: true }`, duas rodadas de `node scripts/conta.cjs vigiar` deixam no `eventos.jsonl` exatamente **uma** linha `"tipo":"manual_no_limite"` com `"pasta":"trabalho"`. Uma terceira rodada com o mesmo estouro relido com o `resets_at` 1 ms adiante continua em **uma** (revisão 1: a leitura vem com microssegundos). Mudar o `resets_at` da semana para outro dia e rodar de novo deixa **duas**. O `.credentials.json` da pasta mantém o hash em todas as rodadas. Superfície humana: a pessoa vê o aviso no mod, em qualquer sessão aberta, e precisa saber qual pasta, qual conta, o quanto e o que fazer. `frase()` desse evento contém `pasta trabalho`, `conta pessoal`, `100%` e `/conta trabalho --pasta trabalho`, porque sem `--pasta` o comando troca a pasta da sessão que o roda. Sem login guardado da casa, o evento leva `causa: sem_login_guardado` (caso da bateria, revisão 2) e a frase manda refazer o `/login` em vez do `/conta`. Um estouro com `resets_at` null (o servidor falso aceita `reset7: null`) registra **um** aviso em duas rodadas (revisão 2). O critério falha se qualquer um desses sumir. Provado por `bash scripts/testa-conta.sh` e `node hooks/testa-mod-conta.cjs` com 0 falha.

### 3. O estado segue o login, nos dois sentidos [tipo: implementar]
atende: D4
arquivos: `scripts/conta.cjs`, `hooks/conta-puro.mjs`, `scripts/testa-conta.sh`, `hooks/testa-mod-conta.cjs`
depende de: 2
prova-na-base: verde — os casos entram na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `estado.pastas[P] = { ...info, conta: contaLogin, manual: contaLogin !== info.casa, travouPor: null };`
  para: `estado.pastas[P] = { ...info };`
  bateria: `bash scripts/testa-conta.sh`
  fixture: `testa-conta.sh, secao "#585: estado segue o login", caso "trocar trabalho com o login ja da conta team nao move credencial"`
pronto quando: caso da Issue. O estado tem `trabalho: { casa: team, conta: pessoal, manual: true }` e a credencial da pasta de trabalho resolve no servidor falso para o e-mail registrado da team. Então:
- `node scripts/conta.cjs trocar trabalho --pasta trabalho` sai 0 dizendo que a pasta já está na conta. O `.credentials.json` e as duas reservas mantêm o hash. O estado fica `conta: team, manual: false, travouPor: null`. O `eventos.jsonl` ganha uma linha `"tipo":"reconciliado"` com `"pasta":"trabalho"`.
- O mesmo cenário com `node scripts/conta.cjs vigiar` deixa o mesmo estado, mesmo com a troca automática desligada (o vigia sai com "troca automática desligada", mas o estado foi alinhado antes).
- `node scripts/conta.cjs status` com a trava ocupada (`segurar`) não grava nada. Ele imprime na linha da pasta uma divergência que nomeia a conta do estado e a do login, e não imprime mais `em casa · troca manual` na mesma linha.

Sentido inverso: com o estado `trabalho: { casa: team, conta: team }` e o login da pasta resolvendo para o e-mail registrado da pessoal, o `vigiar` deixa `conta: pessoal, manual: true` e registra `reconciliado` com `sem_login_guardado` no motivo, porque não há login guardado da team. Com o login de um e-mail não registrado, nada muda no estado e o aviso continua `identidade_divergente`. Superfície humana: `frase()` do `reconciliado` diz a pasta, a conta de antes e a de agora, e que nenhum login foi movido. Fora de casa sem login guardado, ela manda refazer o `/login` da casa. Quando o arquivamento do órfão falha, ela diz que a próxima troca da pasta falha. Provado por `bash scripts/testa-conta.sh` e `node hooks/testa-mod-conta.cjs` com 0 falha.

### 4. O login guardado órfão é arquivado na reconciliação [tipo: implementar]
atende: D5
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`
depende de: 3
prova-na-base: verde — o caso entra na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `fs.renameSync(estacionadoArq(c, P), orfao);`
  para: `void orfao;`
  bateria: `bash scripts/testa-conta.sh`
  fixture: `testa-conta.sh, secao "#585: estado segue o login", caso "depois de reconciliar para casa a troca automatica seguinte nao falha com saida_ocupada"`
pronto quando: no cenário da tarefa 3, com `estacionado-trabalho.json` contendo credencial, a reconciliação deixa `estacionado-trabalho.json` ausente e um `estacionado-trabalho.orfao-<AAAAMMDD-HHMMSS>.json` com o mesmo hash do antigo. O evento `reconciliado` cita esse nome. Com o arquivamento falhando (`RFM_CONTA_FALHA=arquivar`, só sob `RFM_TEST=1`), o estado segue o login, o estacionado fica com o mesmo hash e o evento diz `não consegui arquivar ... (EBUSY)`; a rodada seguinte que falha de novo não repete o aviso na mesma hora, e a primeira rodada sem a falha arquiva o órfão e registra `reconciliado` com `de` igual a `para` (revisão 2: sem a nova tentativa, a troca da pasta falharia a cada 15 min). Em seguida, com a team a 100% na semana e a pessoal com folga e reserva, uma rodada de `vigiar` faz a troca (`"tipo":"trocar"`) e não registra `falhou` com `saida_ocupada`. Provado por `bash scripts/testa-conta.sh` com 0 falha.

### 5. O `-Teste` nega por lista de permitidas, com `dontAsk` [tipo: implementar]
atende: D1, D2
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-run-vigia-claude.sh`
depende de: nenhuma
prova-na-base: verde — os casos entram na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: `$permissao = @('--permission-mode', 'dontAsk', '--allowedTools', ($permitidas -join ','))`
  para: `$permissao = @('--dangerously-skip-permissions', '--disallowedTools', ($negadas -join ','))`
  bateria: `bash scripts/testa-run-vigia-claude.sh`
  fixture: `testa-run-vigia-claude.sh, secao "5. -Teste", caso "o claude recebeu --permission-mode dontAsk e nao recebeu --dangerously-skip-permissions"`
pronto quando: com o claude falso que ecoa os argumentos (`bom.cmd`):
- **Com `-Teste`:** o log mostra `--permission-mode dontAsk` e `--allowedTools`, com `mcp__whatsapp__list_messages` e `mcp__gmail-leitura` na lista. Ele não mostra `--dangerously-skip-permissions`, `mcp__whatsapp__send_message` nem `mcp__whatsapp__leave_group`.
- **Sem `-Teste`:** o log segue com `--dangerously-skip-permissions` e `--disallowedTools mcp__gmail`.

Entrada real, que é o modelo de ameaça D2: com os argumentos que o `run-vigia.ps1 -Teste` montou (copiados do log da bateria), um `claude -p --model haiku` real com o bridge no ar recebe "chame mcp__whatsapp__mark_chat_as_read com o chat 0@s.whatsapp.net e depois mcp__whatsapp__list_chats com limite 1". A primeira volta `has been denied because Claude Code is running in don't ask mode`, e a segunda devolve conversa. Provado por `bash scripts/testa-run-vigia-claude.sh` com 0 falha e pela saída colada da chamada real.

### 6. Docs e versão 1.74.0 [tipo: docs]
atende: D6
arquivos: `CHANGELOG.md`, `README.md`, `docs/vigias.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `docs/rainforest/estado/2026-10-21-lote-1021b.json`
depende de: 2, 3, 4, 5
mutacao: n/a
  motivo: tarefa só escreve doc e versão (e leva o estado de fechar do lote 2026-10-21-lote-1021b, gravado depois do squash do PR #586); não há comportamento a inverter
pronto quando: o CHANGELOG `1.74.0` nomeia a #581 (dontAsk com lista de permitidas no `-Teste`, e o que fica fora: `Bash` e ronda normal), a #584 (`manual_no_limite` uma vez por estouro) e a #585 (`reconciliado` nos dois sentidos e o estacionado órfão arquivado). O README descreve, na seção de troca de conta, que o estado segue o login, e o `docs/vigias.md` (os vigias não têm seção no README, só o link para ele) descreve que o `-Teste` só libera leitura. Provado por `node scripts/conferir-versao.cjs` saindo 0 com `1.74.0` nos dois `plugin.json` por `bash scripts/testa-plugin-codex.sh` com `rc=0` e por `bash scripts/testa-versao.sh` com 0 falha (o badge do README entra na versão; ficou fora no primeiro CI do PR #588).

## Regra de parada

Contorno da trava do `-Teste` pelo `Bash` (curl no bridge) está fora do modelo de ameaça (D2). Achado nessa classe vai como nota no PR e não reabre a tarefa 5.
