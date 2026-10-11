# Cabeçalho `teto-despachos:`

O hook `hooks/gate-teto-despachos.cjs` conta os despachos de agente de cada
fluxo e nega o que passa do teto. O plano declara o teto do próprio fluxo
numa linha do cabeçalho; sem a linha, vale o teto padrão de 40 despachos
(D9 do design `docs/rainforest/design/2026-10-10-flaky-teto.md`).

## Onde fica

Entre as linhas do plano **antes do primeiro `## `** (o título, o `Design:`,
a linha em branco). Linha dentro de uma seção `##` é ignorada.

```
# Plano: <título>

Design: docs/rainforest/design/<slug>.md
teto-despachos: 60
```

O rótulo não diferencia maiúscula de minúscula e aceita espaço antes dele e
antes do `:`. Só uma linha `teto-despachos:` é aceita.

## Valor aceito

Inteiro de 1 a 9999, sem sinal, sem zero à esquerda e sem unidade. O padrão
de 40 ficou acima do maior fluxo medido no design (D9, 36 despachos).

## Valor ilegível

Duas linhas `teto-despachos:`, ou um valor fora do que está acima (`0`, `-5`,
`40 despachos`, vazio), é ilegível. O hook **nega o despacho** (exit 2) e diz
qual linha leu: ilegível nunca vira o teto padrão (D12). Conserte o
cabeçalho do plano; o hook lê o plano a cada despacho.

O erro aparece antes, no próprio plano: `node scripts/conferir-fluxo.cjs
cobertura` (e o `marcar --estagio plano` que a roda) recusa com exit 2 o
mesmo cabeçalho ilegível, pelo mesmo leitor do hook
(`hooks/lib/teto-despachos.cjs`, D14).

Plano ainda inexistente (fluxo em `design`) vale o padrão de 40.

## Teto efetivo

Teto efetivo é o declarado (ou 40) mais 10 por liberação gravada no estado
do fluxo: `node scripts/estado.cjs liberar-teto --slug <slug> --motivo "..."`,
com a palavra do usuário. Veja `skills/revisar/references/laco.md`.
