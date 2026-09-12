# Cobertura de arqueologia

Índice do que já foi mapeado, quando, e em que profundidade. Fatia com linha
aqui **não é extração nova** — a próxima rodada sobre ela é **conferência**, no
método que a skill `arqueologia` descreve.

| Fatia | Arquivo | Blocos | Profundidade | Data | Nota |
|---|---|---|---|---|---|
| multihost sobre 1.11 | 14 caminhos finais de `codex/piloto-rainforest` + `hooks/gate-staging-total.cjs` | 1 | superfície + mecanismo + regra implícita | 2026-09-12 | reconciliação contra `a338dd02`; core e contratos colidem semanticamente |

## Histórico do índice

Havia aqui um mapa real, de 2026-08-22, produzido durante a validação do agente
`arqueologo`. Ele foi **removido em 2026-09-08**: era arqueologia de um fonte de
um repositório de trabalho — nomes de função, portão de licenciamento, nome de
include interno —, e este repositório é público.

A remoção não é perda de método: o que o mapa provava (que o agente produz mapa
dentro do teto de bloco, com citação `arquivo:linha` reabrível) está provado por
`scripts/testa-arqueologo-ponta-a-ponta.sh`, que roda sobre fixture sintética e
não depende de fonte nenhum de cliente.

**Regra que fica**, e vale para quem for mapear daqui em diante: mapa de fonte
de trabalho mora no repositório daquele trabalho, nunca aqui. Este `COBERTURA.md`
indexa o que for mapeado **deste** repositório, ou fatia de código público.
