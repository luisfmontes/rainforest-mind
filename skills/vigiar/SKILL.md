---
name: vigiar
description: Use para acompanhar uma conversa de WhatsApp e avisar quando a pessoa responder, sem gastar token esperando. Uma conversa, nesta sessão — não é vigia agendado de `vigias/`.
---

# Vigiar

Porta de entrada para o `/whatsapp:vigiar` do repositório `whatsapp-mcp`. O
fluxo inteiro (resolver o contato, armar o Monitor, rascunho ou `--auto`, parar)
mora **lá**, no `commands/vigiar.md` — esta skill só confere se dá para armar e
entrega os caminhos resolvidos. Não reescreva o fluxo aqui: duas cópias
divergem.

## 1. Conta

A vigia é de uma conta: `pessoal` ou `trabalho` (chaves do
`~/.whatsapp-mcp/accounts.json`). Se o pedido não disser e o contato puder
estar nas duas, o passo 1 do `vigiar.md` resolve — mas a checagem abaixo
precisa de uma conta. Na dúvida, pergunte antes de checar.

## 2. Checar antes de armar

```
node "<raiz do plugin>/scripts/vigiar-checar.cjs" --conta <conta>
```

`<raiz do plugin>` é `${CLAUDE_PLUGIN_ROOT}` quando definido; senão, dois
níveis acima do diretório base desta skill.

- **Exit ≠ 0**: repasse a linha do stderr ao usuário, como veio, e **pare**.
  Ela diz o que falta — a chave `integracao-whatsapp-mcp` desligada, a bridge
  da conta fora do ar (com a porta), a conta que não existe ou o
  `watch_chat.py` ausente. Não arme nada e não tente contornar.
- **Exit 0**: o stdout é um JSON com `conta`, `porta`, `status_url`,
  `script`, `vigiar_md` e `db`.

## 3. Seguir o fluxo do fork

Leia o arquivo `vigiar_md` do JSON e siga-o do passo 1 ao 7, com os
argumentos do usuário (contato e, se ele pediu, `--auto`). No passo 3, use o
`script`, o `db` e o `status_url` do JSON **como vieram** — o `status_url` é
o da bridge da conta checada, e é ele que faz a linha `BRIDGE:` avisar quando
a espera fica cega.

Se o contato resolvido no passo 1 do `vigiar.md` for de **outra** conta que
não a checada, volte ao passo 2 desta skill com essa conta antes de armar.
