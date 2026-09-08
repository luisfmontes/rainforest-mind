---
description: Transfere a sessão de Claude Code para Codex CLI
---

Transfere o histórico desta sessão do Claude Code para um novo `codex exec`, permitindo continuar como um agente independente no Codex.

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/transferir-para-codex.cjs" $ARGUMENTS
```

**Requer `/setup --ligar transfer-codex`.** Sem a chave ligada, o script recusa com mensagem de erro.

Ao terminar, use `codex resume <thread-id>` (impresso na última linha) para retomar a sessão no Codex com o histórico completo.
