# Orçamento: medida estável e folga declarada

## Objetivo

Fazer o veredito das baterias de orçamento depender do commit, e não da mesa de quem
roda — e dar aos três tetos um aviso antes da quebra, com uma mensagem que enuncie a
decisão a tomar em vez do conserto errado. Fecha as issues #81 e #79.

Duas medições feitas em 2026-08-24, na ponta da `main` (`c29377e`), delimitam o
trabalho.

A primeira separa o repositório da mesa. O mesmo comando, no mesmo commit, com e sem
a raiz de dados pessoal:

| fonte | raiz real | raiz neutra | delta |
|---|---|---|---|
| Hook (`additionalContext`) | 7.924 B | 6.558 B | **1.366 B** |
| Skills (descriptions) | 3.626 B | 3.626 B | 0 |
| Commands (descriptions) | 1.111 B | 1.111 B | 0 |
| Agentes (descriptions) | 1.801 B | 1.801 B | 0 |
| **Total** | **14.462 B** → exit 1 | **13.096 B** → exit 0 | **1.366 B** |

Os 1.366 B são inteiramente estado pessoal: 1.305 B de FOCO.md, 312 B do radar de
sessões — que muda entre duas execuções seguidas, sem ninguém commitar nada — e 220 B
de dependências da máquina. O CI, que não tem raiz de dados, mede 13.096 B e passa
verde no mesmo commit em que a máquina do dono sai 1. É a pior combinação possível,
porque cada lado acha que o outro está errado, e já custou trabalho concreto: em
2026-08-24 o `conferir-mutacao.cjs` recusou medir uma entrega com exit 4
(`RECUSADO: baseline NAO-VERDE`, `scripts/conferir-mutacao.cjs:235-240`) por um motivo
que não tinha nada a ver com a entrega.

A segunda mede as folgas. Nenhum dos três tetos tem margem declarada, e dois estão
abaixo de 1%:

```
núcleos  : 5.589 / 5.600   → folga     11 B  (0,20%)
hook     : 7.924 / 8.000   → folga     76 B  (0,90%)
agregado : 14.462 / 14.000 → ESTOURO  462 B
agregado (raiz neutra): 13.096 / 14.000 → folga 904 B (6,5%)
```

## Decisões fechadas

- **D1 — A asserção que reprova mede raiz neutra; a mesa vira seção que avisa sem
  reprovar.** — porquê: o veredito de um commit tem de ser reprodutível, e hoje a
  seção 1 de `scripts/testa-orcamento.sh:46` roda contra o repo real e exige exit 0,
  onde "real" inclui o FOCO.md e as sessões abertas naquele minuto. Mas jogar fora o
  sinal do ambiente real seria perder a única coisa que hoje avisa que a injeção vai
  cortar o FOCO. Duas seções: uma decide, a outra informa.

- **D2 — A neutralização é `RFM_ROOT` apontado para uma pasta vazia descartável, não
  uma flag nova no `orcamento.cjs`.** — porquê: `RFM_ROOT` é o nível 1 documentado da
  cadeia de resolução de raiz (`hooks/lib/raiz.cjs:67`, tabela em `README.md:567`,
  honrado por `scripts/setup.cjs:147`) — é superfície oficial, não acidente. Uma flag
  nova seria um segundo mecanismo para o que a cadeia já resolve, e só no
  `orcamento.cjs`; `RFM_ROOT` neutraliza qualquer script da bateria pelo mesmo caminho.

- **D3 — Neutralizam-se os cinco pontos medidos, não os dois que a #81 nomeia.** —
  porquê: o mesmo defeito está em mais lugares, e um deles quebra sozinho em 76 B —
  seria a mesma sessão consertando o mesmo defeito duas vezes. Os cinco:

  | local | o que mede | risco em 2026-08-24 |
  |---|---|---|
  | `scripts/testa-orcamento.sh:46` | agregado, repo real | já vermelho (+462 B) |
  | `scripts/testa-orcamento.sh:57` | idem, com `--teto 1000` | passa por acidente |
  | `hooks/testa-memoria-session-start.sh:137-140` | `Hook <= 8000 B` | 76 B de folga |
  | `scripts/testa-medir-injecao.sh:161` | roda o hook real cru | contaminado |
  | `hooks/testa-contexto-sessao.sh:326,1259,1268` | `RFM_ROOT="$SRC_WIN"` — a raiz é o próprio repo, que contém `sessoes.json` gitignored (`.gitignore:2`) | difere entre máquina e runner |

- **D4 — Banda de aviso proporcional de 5% da folga, mecanismo único para os três
  tetos.** — porquê: os três passam de verde a vermelho numa palavra, e um mecanismo
  por teto seria três lugares para manter em sincronia. Proporcional em vez de
  absoluto porque os tetos diferem em ordem de grandeza (5.600, 8.000, 14.000) e uma
  margem fixa seria folgada num e apertada noutro. Abaixo da banda a bateria imprime
  aviso e continua verde — margem que acabou é informação, não reprovação.

- **D5 — A mensagem enuncia a decisão a tomar, não o conserto.** — porquê: hoje
  `hooks/testa-contexto-sessao.sh:400-402` manda "reduzir os núcleos", que é conserto
  no lugar errado quando o que se quer é adicionar regra. A mensagem passa a nomear o
  trade-off real e de onde sai o byte: núcleo, FOCO ou agregado. Este é literalmente o
  segundo ramo do critério de pronto da #79.

- **D6 — Nenhum valor de teto muda nesta entrega.** — porquê: três medições refutam a
  hipótese de que falta teto. (i) `tetoFoco` no melhor caso possível já é 1.841 B
  contra `FOCO_MAX_BYTES` de 2.600 (`hooks/lib/contexto-sessao.cjs:1033-1035`) — os
  núcleos já comeram 759 B do FOCO, e os 76 B de folga do payload são do FOCO, não das
  regras. (ii) Subir `ORCAMENTO_BYTES` de 8.000 para 8.800 levaria o agregado máximo a
  15.338 B, contra um teto de 14.000 que já está estourado. (iii) Nenhuma regra nova
  entrou em 16 dias: as 17 se formaram entre 2026-08-05 e 2026-08-08 e a contagem não
  mexeu desde. Subir teto sem regra para colocar gasta folga inexistente comprando
  espaço que ninguém usa. Quando a regra 18 existir, a mensagem da D5 já dirá de onde
  tirar o byte.

- **D7 — O teto agregado fica em 14.000.** — porquê: 14.000 nunca mudou desde que
  nasceu em `41d73b7` (2026-08-14), e recalibrar o teto no mesmo commit que conserta o
  instrumento perde a referência de comparação — não se saberia depois se a medida
  melhorou ou se a régua encolheu. E, diferente dos outros dois, o agregado tem folga
  real: com raiz neutra são 13.096 B, folga de 904 B contra uma banda de 700 B. Este é
  o teto que **não** avisa hoje, e é assim que se sabe que a banda discrimina em vez de
  reclamar de tudo:

  | teto | folga hoje | banda (5%) | avisa? |
  |---|---|---|---|
  | núcleos 5.600 | 11 B | 280 B | **sim** |
  | hook 8.000 | 76 B | 400 B | **sim** |
  | agregado 14.000 (raiz neutra) | 904 B | 700 B | não |

- **D8 — O corpo da issue #81 é ampliado com a tabela da D3 antes de fechar.** —
  porquê: a issue descreve dois pontos e a entrega conserta cinco. Registro menor que
  a entrega faz o próximo leitor achar que três dos consertos foram escopo esticado
  sem motivo.

## Avaliado e descartado

- **Subir `NUCLEOS_MAX_BYTES` e `ORCAMENTO_BYTES` juntos** — era a recomendação
  aprovada na rodada 1 do brainstorm, refutada pela medição da rodada 2: o `tetoFoco`
  real já é 1.841 B contra os 2.600 nominais, e subir `ORCAMENTO_BYTES` empurra o
  agregado máximo para 15.338 B contra um teto já estourado em 462 B. Compraria espaço
  para regras que não estão sendo escritas, com folga que não existe.

- **Subir só `NUCLEOS_MAX_BYTES` até o teto físico de ~6.730 B** — cabe (acima disso o
  FOCO cai abaixo de `FOCO_MIN_BYTES: 700` e vira aviso de uma linha), mas cada byte
  sai do FOCO, que já está estrangulado. Na taxa histórica de 15,8 regras/mês, 6.730 B
  compra 3 regras típicas de 348 B — 5,7 dias de folga. Não vale o byte que custa.

- **Plantar `~/.rainforest` ou FOCO.md sintéticos no CI** — o próprio workflow já
  recusou este caminho por escrito, e a razão continua válida:
  `.github/workflows/baterias.yml:102-104` — *"isso deixaria o CI verde alimentando as
  baterias com o acoplamento que elas não deviam ter"*. A correção é tirar o
  acoplamento da bateria, não replicá-lo no runner.

- **Recalibrar o teto agregado para o que a medida neutra pede** — ver D7: perde a
  referência de comparação no exato commit em que o instrumento muda.

- **Neutralizar só os dois pontos que a #81 nomeia** — `hooks/testa-memoria-session-start.sh:137`
  quebraria sozinho dentro de 76 B, pelo mesmo defeito, exigindo uma segunda sessão
  idêntica a esta.

## Fora de escopo

- **#74 — o FOCO.md monolítico não cabe na injeção.** É a única das três issues do
  orçamento que *devolve* folga em vez de gastar, e é a causa raiz do estrangulamento
  medido na D6. Fica de fora porque transformaria um conserto de instrumento numa
  refatoração do FOCO, e porque o instrumento precisa estar confiável antes de medir o
  efeito dela. Decidido explicitamente em 2026-08-24.

- **Decidir se 17 é o número final de regras.** É decisão de produto, não de
  instrumento. A D5 faz a bateria enunciar o trade-off quando a regra 18 aparecer;
  quem decide continua sendo o dono.

- **Remover `NUCLEOS_MAX_BYTES` por não ser usado em runtime.** Verificado que ele só
  existe na definição (`hooks/lib/contexto-sessao.cjs:82`) e num comentário (`:126`) —
  quem trava a injeção de verdade é `travarOrcamento` (`:963`), e `a78132b` rodou com
  5.657 B contra teto de 5.600 sem quebrar nada. A catraca é do CI, e ter catraca de
  CI que dói na hora de escrever é o ponto dela. Mudar isso é outro assunto.

- **#82 — `limpar-branches` classifica branch de PR squashed como trabalho vivo.**
  Defeito real, sem relação com orçamento, e com escolha técnica própria a fazer.

## Em aberto

- (vazio)
