# Sensor pedido pelo agente, na linha do briefing

Quando o manifesto do repo declara `sensores` para o agente despachado
(`.rainforest/agentes.json` ou o padrão embarcado), o briefing pede o sensor que
ele vai precisar rodar com uma linha isolada, no mesmo estilo de `Runtime:`:

```
Sensor: <nome>
```

`hooks/portaria.cjs`, função `sensoresPedidosDoPrompt`, lê essas linhas do prompt
de despacho: case-insensitive, pode haver **várias** linhas `Sensor:` e **todas**
contam — ao contrário de `Runtime:` (primeiro-encontro), uma linha `Sensor:`
dentro da lista do manifesto não mascara outra que caia fora dela.

## O que acontece com cada caso

| Caso | Efeito |
|---|---|
| manifesto sem `sensores` | nada muda; uma linha `Sensor:` num briefing desses não trava coisa alguma |
| sensor pedido está na lista | despacha, e o log registra o sensor pedido |
| sensor pedido **fora** da lista | **despacha (exit 0)**, com `sensor_fora_da_lista` no `despachos.jsonl` |
| valor que não é um nome (`[A-Za-z0-9_-]+`) — vazio, com espaço | **despacha (exit 0)**, com `sensor_ilegivel: true` no log |
| `sensores` malformado no manifesto | **nega (exit 2)** — é forma de arquivo, não admissão |

A assimetria entre as duas últimas linhas é a da issue #264, e vale reler quando
parecer arbitrária: forma de arquivo errada **dói no arquivo**, porque errar um
JSON à mão é o modo de falha mais provável e tem de ser dito ali; admissão virou
registro, porque o portão cobrava do usuário sem defender a árvore dele. Um
sensor pedido fora da lista é admissão. Ver a emenda de 2026-09-15 em
`docs/rainforest/design/2026-09-14-guias-e-sensores.md`.

## Não confundir os dois canais

Este é o sensor que o **agente pode rodar**, decidido no despacho, onde existe
briefing. É canal diferente do sensor citado na **evidência** ao fechar
`verificar` — aquele é o campo `sensor_externo` do `--json` de
`scripts/estado.cjs marcar`, decidido no fechamento, onde só existe `--json`, e
nunca passa por aqui. É a D18 do design: cada declaração usa o canal que o seu
leitor tem.
