# Erros de execução dos vigias

- 2026-08-06 14:52 [vigia-tickets]: WhatsApp bridge offline (HTTPConnectionPool localhost:8765 refused)
- 2026-08-07 07:54 [sentinela-foco]: bridge nao subiu apos acordar o WSL (porta 8765 fechada)
- 2026-08-07 09:48 [sentinela-foco]: send_message failed — localhost:8765 refused (connection refused)
- 2026-08-10 12:46 [sentinela-foco]: triagem de inbox falhou — a causa registrada aqui ("Gmail MCP nao autenticado") foi inventada pelo vigia; ver 13:11
- 2026-08-10 13:00 [sentinela-foco]: triagem de inbox falhou de novo, 3 tentativas — mesma causa inventada
- 2026-08-10 13:11 [sentinela-foco]: RESOLVIDO. Causa real: whatsapp e gmail estavam em disabledMcpServers do projeto rainforest-mind no .claude.json, entao nenhuma tool de MCP chegava a sessao do vigia (init da sessao: status disabled). A credencial do Gmail estava valida o tempo todo. Reabilitados; triagem conferida com dados reais
