---
description: Acompanha uma conversa de WhatsApp sem gastar token e avisa quando a pessoa escreve
argument-hint: <contato> [--conta pessoal|trabalho] [--auto]
---

Carregue `Skill(vigiar)` e siga-a para `$ARGUMENTS`.

A checagem de arme é
`node "${CLAUDE_PLUGIN_ROOT}/scripts/vigiar-checar.cjs" --conta <conta>` —
com exit ≠ 0, repasse a linha e pare.
