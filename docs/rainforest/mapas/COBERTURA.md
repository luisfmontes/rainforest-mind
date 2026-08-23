# Cobertura de arqueologia

Índice do que já foi mapeado, quando, e em que profundidade. Fatia com linha
aqui **não é extração nova** — a próxima rodada sobre ela é **conferência**, no
método que a skill `arqueologia` descreve.

| Fatia | Arquivo | Blocos | Profundidade | Data | Nota |
|---|---|---|---|---|---|
| `IAG67M12` | `IAG67M12.prw` | 1 de ~14 | superfície + mecanismo + regra | 2026-08-22 | classe `logica` (repetição 32,3%); bloco 1 = linhas 1–569, âncora `IAG67M12`; hash do fonte `e34c3e2b8ab02d9779465f19a3638e88609282ff` |

## Blocos por fatia

### `IAG67M12` — Painel de Fechamento Financeiro (Inovação Agro / TBC Agro)

Fonte de 13.692 linhas e 219 funções. Triagem: densidade 62,52 lin/func,
repetição 32,3%, classe `logica`. Ao teto de 40.000 caracteres por bloco, o
arquivo rende ~14 blocos.

| Bloco | Âncora | Faixa (em 2026-08-22) | Bytes do fonte | Estado |
|---|---|---|---|---|
| `IAG67M12.prw#IAG67M12` | `IAG67M12` | 1–569 | 27.712 | mapeado |
| — | `INC67M12` | 570–1067 | 26.326 | pendente |
| — | `fCalTot` em diante | 1068–13.692 | ~485.000 | pendente |

O bloco 1 fecha antes de `INC67M12` porque essa função sozinha tem ~26 KB:
juntá-la levaria o bloco a 54.038 bytes e estouraria o teto.
