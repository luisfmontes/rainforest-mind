---
description: Transfere a sessão para o Codex CLI (troca de conta do Claude Code é com /conta)
---

Transfere o histórico desta sessão para o Codex CLI.

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/transferir.cjs" $ARGUMENTS
```

## Destinos

**Sem argumento (padrão: Codex):** copia o transcript para `codex exec --json`, criando um agente independente.
- Requer `/setup --ligar transfer-codex`
- Retorna `codex resume <thread-id>` para retomar no Codex
- Usa cota do Codex (CLI externa)

**`claude` (qualquer variação, inclusive `claude --para ...`):** recusado com exit 2 e a mensagem `o /transferir claude saiu: use /conta para trocar a conta da pasta`. Para trocar a conta de uma pasta do Claude Code, use o `/conta` (`/conta pessoal` ou `/conta trabalho`).

Sem argumentos e sem `transfer-codex` ligada: recusa com mensagem.
