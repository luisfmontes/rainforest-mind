---
description: Transfere a sessão entre Claude Code (local) ou Codex CLI
---

Transfere o histórico desta sessão para outro destino. O destino determina como.

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/transferir.cjs" $ARGUMENTS
```

## Destinos

**Sem argumento (padrão: Codex):** copia o transcript para `codex exec --json`, criando um agente independente.
- Requer `/setup --ligar transfer-codex`
- Retorna `codex resume <thread-id>` para retomar no Codex
- Usa cota do Codex (CLI externa)

**`claude` ou `claude --para pessoal|trabalho`:** copia a sessão para a outra conta do Claude Code nesta máquina.
- Sem chave ou setup necessário (copia arquivo, sem API)
- Só funciona entre contas nesta máquina (`~/.claude` ↔ `~/.claude-personal`)
- `--para trabalho|pessoal` força destino explícito (padrão: a outra conta)
- `--forcar` sobrescreve se a sessão já existe no destino
- Retorna `cd "..." && CLAUDE_CONFIG_DIR="..." claude --resume <id>` pronto para colar na outra conta

Sem argumentos e sem `transfer-codex` ligada: recusa com mensagem.
