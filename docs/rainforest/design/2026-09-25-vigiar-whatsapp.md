# Skill vigiar: acompanhar conversa de WhatsApp sem gastar token

## Objetivo
Issue #331. Hoje, para acompanhar uma conversa de WhatsApp, o usuário precisa avisar
a sessão quando a pessoa responde. O `watch_chat.py` do repositório
`whatsapp-mcp` (PR luisfmontes/whatsapp-mcp#32) já espera sem gastar token, e o
`commands/vigiar.md` de lá tem o fluxo completo. Só que o comando mora num repo
que não está instalado como plugin. O rainforest, habilitado nas duas contas,
ganha uma skill `vigiar` que é a porta de entrada para esse fluxo, e o script
passa a avisar quando a bridge cai, em vez de esperar calado.

## Decisões fechadas
- **D1 — A queda da bridge chega pelo mesmo processo que espera: o `watch_chat.py` consulta o `/api/status` da bridge da conta a cada ~60s e emite `BRIDGE: desconectada` quando ela cai e `BRIDGE: conectada` quando volta** — porquê: conferido no código em 2026-09-25, o script só acusa erro de leitura do `messages.db`, e com a bridge caída o banco continua legível; a vigia fica muda até o `END:` de 2h, e "ninguém respondeu" fica igual a "a bridge morreu". O `/api/status` já existe (`whatsapp-bridge/main.go`, responde 200 com o estado da conexão e do login), então nada de stream novo. A mudança vai por PR no repo `whatsapp-mcp`. Decidido pelo usuário em 2026-09-25.
- **D2 — A skill do rainforest é só a porta: detecta, resolve `WHATSAPP_MCP_DIR` (padrão `C:/Projetos/whatsapp-mcp`) e manda seguir o `commands/vigiar.md` de lá, passando o caminho do `watch_chat.py` já resolvido** — porquê: uma fonte só para o fluxo, sem duas cópias divergindo; o design `2026-08-28-ponte-bloco-do-projeto-e-integracoes` já rejeitou empacotar o WhatsApp-MCP no plugin. O fork ganha um ajuste: o passo 3 do `vigiar.md` hoje prefere `${CLAUDE_PLUGIN_ROOT}/scripts/watch_chat.py`, e chamado do rainforest essa variável aponta para o plugin errado; passa a usar esse caminho só quando o arquivo existir. Decidido pelo usuário em 2026-09-25.
- **D3 — O nome é `vigiar`, e a descrição diz em uma linha que isto acompanha uma conversa dentro da sessão e não é um dos vigias agendados de `vigias/`** — porquê: é o nome da issue e do comando do fork, e é como o usuário chama. Decidido pelo usuário em 2026-09-25.
- **D4 — A skill só arma com as duas condições: a chave `integracao-whatsapp-mcp` ligada e a bridge da conta escolhida respondendo no `/api/status`. Faltando qualquer uma, diz em uma linha o que falta e para** — porquê: quem não declarou a integração não usa a skill por acaso. Em 2026-09-25 a chave está desligada na config do usuário, então o primeiro uso pede `--ligar integracao-whatsapp-mcp`. Decidido pelo usuário em 2026-09-25 ("A, B", lido como as duas condições juntas).
- **D5 — A conta define a porta: a bridge `pessoal` responde em 3005 e a `trabalho` em 3006 (`~/.whatsapp-mcp/accounts.json`). A checagem do D4 e a consulta de status do D1 usam a porta da conta vigiada, nunca a 3005 fixa** — porquê: com duas bridges, checar a 3005 para uma vigia da conta de trabalho aprovaria a bridge errada. Consequência do D1 com os fatos de 2026-09-25, registrada para não ficar suposta.

## Avaliado e descartado
- Um segundo Monitor só para o status (D1): dois processos por conversa vigiada.
- Stream em que a bridge avisa cada mensagem (plano de 2026-08-22 na ideia `vigia-de-resposta-whatsapp-sem-token`): mexe no Go da bridge; o `/api/status` resolve a liveness sem isso.
- Reescrever o fluxo em português dentro da skill (D2).
- Nome `acompanhar` (D3).
- Liberar só pela bridge, sem a chave (D4).

## Fora de escopo
- Mudar o que o fluxo do fork faz com a mensagem (rascunho, `--auto`, limites): segue como está no `commands/vigiar.md`.
- Vigiar várias conversas numa só vigia.
- Os vigias agendados de `vigias/`.

## Em aberto
