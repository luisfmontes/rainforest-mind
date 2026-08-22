---
name: semear
description: Use quando o usuário quiser saber o que criar NESTE repositório — skill, agente, hook ou trava. Lê o histórico do que este trabalho já tropeçou (observações, relatórios, ideias abertas) e devolve propostas com a evidência de cada uma. Propõe e para; não executa.
---

# Semear

O vocabulário já tinha **plantar** (o que ele trouxe vai pro chão com contexto) e
**colher** (volta e vira trabalho). Falta o terceiro: **o que ainda não é ideia de
ninguém, mas o terreno pede**. É isso.

Plantar guarda o que veio dele. Semear propõe o que o repositório pede.

## O que NÃO fazer, primeiro

Não responda "o que costuma valer a pena num projeto assim". Isso é pergunta de
**stack** — framework, banco, testes, CI — e tem dono oficial e melhor: a skill
`claude-automation-recommender`, do plugin `claude-code-setup` da Anthropic.
Aponte para ela e siga.

O que esta skill tem e o oficial não é **o histórico do que este trabalho já
tropeçou**. O oficial olha o repo e diz "tem Prisma, instale o MCP de banco".
Aqui dá para olhar o mesmo repo **e** a observação de que uma entrega foi recusada
três vezes pela mesma família de defeito, e propor a trava que impede aquela
família. Um recomenda pelo que o projeto **é**; este, pelo que ele **sofreu**.

## Abrir

```
node scripts/semear.cjs
```

Devolve: **observações** (o que já deu errado aqui — cada uma é um defeito real,
com `ao_colher` dizendo o que fazer), **ideias abertas** (já propostas, não
reproponha), **relatórios** (incidentes com método e números; o título carrega a
lição) e **mapas de legado**, se a `arqueologia` já tiver levantado alguma fatia.

### E a arqueologia?

São fontes **complementares**, não encadeadas. `semear` lê o **histórico** — o que
este trabalho já tropeçou. `arqueologia` lê o **terreno** — o que já está lá e
ninguém daqui escreveu.

Esta skill **consome** o mapa quando ele existe, e **não dispara** a arqueologia:
mapear custa uma sessão e é escopado a uma demanda específica. Propor *"mapeie a
fatia X antes"* é uma proposta legítima; sair mapeando não é.

**Projeto sem histórico nenhum é o caso normal de quem acabou de instalar**, não
uma anomalia. Aí não há o que semear, e o script diz isso com os caminhos: esperar
o histórico nascer, levantar o terreno com a `arqueologia`, ou — para pergunta de
stack — o recomendador oficial.

## O método

1. **Agrupe por família, não por item.** Três observações sobre relato de agente
   aceito sem evidência são **uma** proposta, não três. A família é o que merece
   mecanismo; o item isolado quase sempre merece só uma linha de regra.
2. **Ordene por reincidência.** O que aconteceu duas vezes vai voltar. Família com
   uma ocorrência só é candidata fraca — proponha depois, ou nem proponha.
3. **Para cada proposta, escreva o que ela IMPEDE**, não o que ela faz. "Skill de
   review" não é proposta; "trava que recusa integrar entrega sem o comando e a
   saída colados, porque isso já passou três vezes" é.
4. **Prefira mecanismo a texto.** Regra escrita não alcança o modo de falha em que
   o agente leu a regra e errou mesmo assim — está registrado neste repo mais de
   uma vez. Hook com exit code, campo obrigatório em script, condição de parada
   verificável: nessa ordem. Texto por último, e assumido como o mais fraco.
5. **Diga como se saberia que funcionou**, de forma falsificável: qual comando,
   qual saída. Proposta sem isso vira debate de opinião na hora de avaliar.

## A regra que sustenta a skill

**Toda proposta cita o registro que a origina** — id da observação, arquivo do
relatório, data. Sem registro, não se propõe.

Isso não é formalidade: é o que separa esta skill do recomendador oficial. Sem a
citação ela vira uma segunda opinião genérica sobre boas práticas, e aí o usuário
tem duas ferramentas fazendo a mesma coisa, uma delas pior.

## Fechar

Apresente as propostas numeradas, cada uma com: **o que impede**, **a evidência**
(id ou arquivo), **o mecanismo** e **como se saberia**. Então **pare**.

Ele escolhe. O que ele aceitar vira trabalho — pelo fluxo, se for grande
(`Skill(brainstorm)`), ou direto, se for pequeno. O que ele não escolher agora
**é plantado** com gancho de retorno (regra 6), não descartado: proposta boa em
hora errada é semente, não lixo.

**Condição de parada**: esta skill não cria arquivo nenhum. Nem skill, nem hook,
nem agente. Ela propõe — e proposta que já veio implementada não é proposta, é
fato consumado com pergunta retórica em cima.
