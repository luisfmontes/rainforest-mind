---
description: Propõe o que criar NESTE repositório a partir do que ele já tropeçou — skill, agente, hook ou trava
argument-hint: [vazio olha o projeto atual; ou o slug de outro]
---

Carregue `Skill(semear)` e rode `node scripts/semear.cjs` sobre `$ARGUMENTS` — ou,
vazio, sobre o projeto atual.

A fonte é o **histórico**: observações da regra 13, relatórios de incidente e
ideias abertas. Agrupe por família e ordene por reincidência — o que aconteceu
duas vezes vai voltar.

**Toda proposta cita o registro que a origina.** Sem registro, não se propõe: é o
que separa esta skill do recomendador oficial da Anthropic, que olha o código e
não conhece o que este trabalho já sofreu.

Cada proposta traz **o que ela impede**, a **evidência**, o **mecanismo** (hook
com exit code > campo obrigatório > condição de parada > texto, nessa ordem) e
**como se saberia que funcionou**, com comando e saída.

Então **pare**. Ela não cria arquivo nenhum. O que ele aceitar vira trabalho
depois; o que ele não escolher agora é plantado com gancho, não descartado.

O que criar por **stack** — framework, banco, testes, CI — é outra pergunta e tem
dono oficial: a skill `claude-automation-recommender`, do plugin
`claude-code-setup`. Aponte para ela em vez de opinar.
