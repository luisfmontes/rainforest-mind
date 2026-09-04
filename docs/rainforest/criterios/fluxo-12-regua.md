# Critério — fluxo 12: régua absorve `bar.md` e preflight

O diff altera a skill `skills/regua/SKILL.md` e o `README.md`. Julgue **só** se
as seis afirmações abaixo são verdadeiras sobre o texto que o diff deixa no
arquivo. Cada uma é falsificável: se o texto disser o contrário, ou não disser
nada, a afirmação é falsa.

1. **O builder NÃO vê o arquivo de mecanismos.** O texto prescreve
   explicitamente que o builder recebe a régua (o artefato) e a lacuna única,
   mas não a lista de mecanismos, e dá o motivo (otimizar para a lista vence a
   comparação sem melhorar o trabalho). O crítico, sim, recebe a lista.

2. **A lista de mecanismos é arquivo em disco, em
   `docs/rainforest/reguas/<slug>.md`, commitado na rodada 1 e imutável depois.**
   O motivo dado é que o crítico é um agente novo a cada rodada e não herda
   contexto da conversa.

3. **O preflight anuncia e nomeia qual crítico fica cego, e a parada é por
   lado.** Régua que não abre para o loop pelo teste "Obtível" da Fase 0 — o
   texto tem de dizer isso explicitamente, e não pode conter nenhuma frase que
   permita seguir o loop com a régua inacessível. Nosso lado que não renderiza de
   jeito nenhum também para. Render **parcial** de qualquer um dos dois não para,
   e segue com o crítico prejudicado nomeado.

4. **Existem DUAS redes de calibragem, não uma.** A nova, na Fase 0: não
   conseguir extrair 5 a 7 mecanismos reprova a régua antes da rodada 1, a custo
   zero de rodada. A antiga, da Fase 1 (crítico da rodada 1 sem lacuna fechável),
   continua existindo no texto.

5. **O veredito continua binário e a lacuna continua única.** O texto afirma
   explicitamente que os mecanismos não viram rubrica pontuada nem nota.

6. **A atribuição nomeia as duas fontes.** O rodapé credita o
   `robonuggets/gauntlet-loop` (como já fazia) E credita a skill `design-loop`
   pelas duas peças absorvidas, dizendo o que dela ficou de fora e por quê.

Responda `concordo` só se as seis forem verdadeiras. Qualquer uma falsa →
`discordo`, nomeando o número.
