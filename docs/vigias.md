# Vigias — automação fora da sessão


A pasta [`vigias/`](../vigias/) tem prompts headless agendados no sistema
operacional (`claude -p`, haiku — o **sentinela-foco** em sonnet desde
2026-08-20, porque tool de MCP diferida não sai em haiku) que reportam por
WhatsApp: **sentinela-foco** (briefing matinal de prazo/avanço + triagem de
inbox em 3 baldes, somente leitura), **jardineiro-ideias** (semanal — ideias
plantadas + revisão do vault), **batedor-repos** (semanal — repositório e skill
de fora, com o veredito acumulado em `vigias/livro-de-repos.md`),
**vigia-tickets** e **revisao-bimestral**. O guarda-corpo funcionando fora da
sessão — onde o hiperfoco não deixa abrir uma.

**Os vigias nascem desligados** (chave `vigias`), e o **sentinela-foco** pede também
o foco, que é opcional desde a 2.0.0: a ronda só roda com `vigias` e `foco` ligados
(`node scripts/setup.cjs --ligar foco`, ou o grupo "foco" do `/setup`).

**A ronda de teste não escreve no WhatsApp.** `run-vigia.ps1 -Vigia <nome> -Teste` roda a
ronda fora do agendamento, e em vez de enviar o modelo escreve a mensagem entre
`---INICIO---` e `---FIM---`. Desde a 1.74.0 (#581), o `-Teste` usa
`--permission-mode dontAsk` com uma lista de **permitidas**: as nativas que a ronda usa
(`Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`), o `gmail-leitura` e as tools de
leitura do WhatsApp que os vigias usam: `list_chats`, `list_messages`, `get_chat`,
`get_contact_chats`, `get_direct_chat_by_contact`, `get_group_info`,
`get_last_interaction`, `get_message_context`, `get_user_info`, `search_contacts`,
`resolve_contact` e `check_whatsapp`. Qualquer outra é negada na hora da chamada,
inclusive tool nova do bridge e as de leitura que ficaram de fora da lista (por
exemplo `get_bridge_status`); a lista está em `vigias/run-vigia.ps1`. A lista negra de antes deixava liberada toda tool que ela não nomeava. Fica
fora da trava o `Bash` falando direto com o bridge HTTP, porque a ronda de teste roda
`node` como a real. A ronda agendada continua com `--dangerously-skip-permissions` e
nega só o servidor `mcp__gmail` inteiro.

**Quando um vigia falha, ele fala — e alguém tem de ouvir.** Todo erro de ronda
passa por uma porta única, [`vigias/erros.ps1`](../vigias/erros.ps1), que grava em
`vigias/ERROS.md` sempre em LF, sem BOM, e **troca caminho de máquina por
marcador antes de gravar** (o arquivo é versionado, e este repositório é
público). E o `/saude` passou a subir duas linhas sobre eles:

- **vigia agendado sem próxima execução.** Gatilho vencido deixa a tarefa com
  `State: Ready`, `Enabled: True` e `LastTaskResult: 0` — os três campos que
  uma pessoa checa — e só o `NextRunTime` **em branco** denuncia. Dois vigias
  ficaram vinte dias mortos assim. Bateria própria em
  `scripts/testa-vigias-agendados.sh`.
- **erros recentes no `ERROS.md`.** O arquivo registrou a mesma falha em toda
  ronda por cinco dias sem ninguém abrir. Instrumentação não faltou; leitura
  faltou.

