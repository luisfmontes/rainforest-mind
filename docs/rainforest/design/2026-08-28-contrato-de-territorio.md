# Design — o contrato de território, extraído do primeiro território (Python)

Origem: conversa de 2026-08-28. Premissas fixadas nela: **domínio é skill,
papel é agente** (os papéis do harness ficam agnósticos; o território entra
por referência no briefing); e **território não mora no rainforest** — aqui
mora só o contrato. O repo de AdvPL já existente é o segundo implementador
natural, e o teste de que a interface não nasceu enviesada.

Data: 2026-08-28. Status: rascunho — **colher depois dos fluxos 1–3**. As Qs
dependem de fatos dos repositórios Python/Node/Flutter, que o Claude Code
responde melhor olhando do que você digitando.

## Objetivo

O fluxo é agnóstico de stack, mas a régua não é: "pronto quando" em Python é
`pytest -x` com fixture, em Flutter é `flutter test` com widget test, em
AdvPL é outra coisa. Hoje esse conhecimento entra por improviso a cada plano.

Pronto quando: existe `docs/rainforest/contrato-territorio.md` versionado
dizendo o que um pacote de território **fornece** e o que o rainforest
**consome**; existe um primeiro território (Python), em repositório próprio,
implementando o contrato; e um plano escrito com o território ativo referencia
templates de critério e padrão de mutação dele, provado num fluxo real.

## Decisões (fechadas na conversa)

- **D1 — o contrato nasce por extração, não por especificação.** O primeiro
  território (Python) se constrói direto; o contrato é o que ele precisou.
  Contrato desenhado antes do caso concreto erra a interface — e o segundo
  implementador (AdvPL, que já existe) é quem valida que ela generaliza.

- **D2 — o que o território fornece (mínimo, a confirmar na extração):**
  templates de critério falsificável para o `plano`; padrão de bateria e de
  alvo de mutação do stack; comandos canônicos (build, teste, lint) com exit
  code; e a regra de detecção que deixa `semear`/`setup` reconhecer que um
  repositório é daquele território.

- **D3 — papéis continuam no harness.** Executor, revisor, sabotador não se
  duplicam por stack; o briefing referencia a skill do território. M papéis ×
  N territórios sem explosão.

## Em aberto (responder no computador, com os repos na frente)

- **Q1 — qual repo Python é o piloto?** ➡️ Recomendo o de maior volume de
  fluxo previsto — o contrato extrai melhor de onde vai ser mais usado.
- **Q2 — como o território chega na sessão:** plugin separado no marketplace,
  ou skill instalada por caminho? ➡️ Recomendo plugin separado, espelhando o
  que o rainforest já faz consigo mesmo.
- **Q3 — o segundo território é AdvPL (validar contrato com o que já existe)
  ou Flutter (forçar o contrato a aguentar app além de API)?** ➡️ Recomendo
  AdvPL: valida com custo quase zero; Flutter vem como terceiro, quando o
  contrato já tiver dois pontos de apoio.
