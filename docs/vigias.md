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

