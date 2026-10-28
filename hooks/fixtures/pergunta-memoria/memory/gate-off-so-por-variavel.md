---
name: gate-off-so-por-variavel
description: desligar gate é RAINFOREST_GATE_OFF/config; arquivo .rainforest-gate-off não, por causa de repo de cliente
metadata:
  type: feedback
---

Para desligar um gate, use a variável RAINFOREST_GATE_OFF ou a chave no config, nunca o arquivo .rainforest-gate-off na raiz.
Motivo: um arquivo na raiz vai junto no commit e chega a repo de cliente; a variável e a config não são versionadas.
