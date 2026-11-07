# Rodada salvos-instagram, 2026-11-06

Triagem dos 296 posts salvos no Instagram do Luís (export oficial, lido do Drive pelo `gws`).
234 posts são de programação, e 135 deles citam alguma ferramenta. São 144 ferramentas
distintas, cada uma classificada por relevância para o rainforest-mind no eixo de apoio ao
desenvolvimento.

**O que foi lido:** o README de cada repo identificado, nunca o código. A única exceção é o
`lboel/untangle`, que foi lido no clone e por isso tem linha na tabela "Avaliados" do livro.
Pelas regras do livro (pergunta 4 e a "Fila da primeira rodada"), avaliação só de README
não dá veredito. Por isso os repos abaixo estão registrados como **triados**, não como
avaliados, e quem os retomar começa pelo código.

## Placar da triagem

| Relevância | Quantas | Observação |
|---|---|---|
| alta | 2 | TokenEconomizer e agent-desktop |
| média | 9 | Tencent aparece duas vezes, então são 8 repos distintos |
| baixa | 133 | 45 fora do apoio ao dev, 44 já avaliados antes no livro ou nas ideias, 34 sem repo identificado (isso quer dizer "não lido", não "irrelevante") |

## Repos de relevância alta e média, e o que virou ideia

| Repo | Licença | Último push visto | Slot | O que o README diz | Ideia plantada |
|---|---|---|---|---|---|
| `microsoft/TokenEconomizer` | Apache-2.0 | 2026-11-06 | economia de contexto | poda de ferramenta por uso real, reversível; micro-fatos do repo tirados de falha repetida, sem chamar modelo; guarda contra laço de falha. Launcher POSIX, Windows não confirmado | `quebra-laco-de-falha-repetida` (ler o código do juiz antes) |
| `vercel-labs/agent-desktop` | Apache-2.0 | 2026-11-07 | verificação | dirige app de desktop pela árvore de acessibilidade (UI Automation no Windows 10 1809+), sem screenshot | `verificar-artefato-de-desktop` |
| `google/elephant-goldfish-model` | Apache-2.0 | 2026-11-07 | revisão | revisores de contexto zerado leem design e plano antes do código; skill `egm-drift-report` confronta design com código | `leitor-cego-do-plano-antes-do-codigo`, `deriva-design-codigo-pos-merge` |
| `Raj9914/elephant-goldfish` | MIT | 2026-10-28 | depuração | segundo diagnóstico recebe só o sintoma e o repro, nunca a hipótese | `depurador-com-diagnostico-cego` |
| `addyosmani/agent-skills` | MIT | 2026-11-01 | plano | `source-driven-development`: decisão de API de framework cita a doc oficial | `decisao-de-framework-cita-doc-oficial` |
| `zilliztech/memsearch` | MIT | 2026-11-06 | memória | markdown como fonte de verdade, índice vetorial reconstruível, busca híbrida vetor+BM25 | nenhuma. Seria a única peça que reabre a decisão de adiar o índice vetorial (FTS5 medido em 82% de recall) |
| `TencentCloud/TencentDB-Agent-Memory` | sem SPDX | 2026-11-04 | memória | memória em 4 camadas destilada de forma assíncrona, integrada por proxy | nenhuma. Já está no livro pela releitura de 2026-10-24 e se sobrepõe a OpenViking e agentmemory |
| `HeyCubit/effortless` | MIT | 2026-10-23 | economia de contexto | juiz Haiku escolhe o esforço do modelo a cada prompt | nenhuma. Custa uma chamada por prompt no `UserPromptSubmit`, que já está ocupado, e não documenta Windows |
| `sodiumsun/agenttrail` | MIT | 2026-11-06 | verificação | mapa ao vivo do que o agente fez, plano marcado contra o diff real | nenhuma. Encosta na ideia `creep-se-mede-no-diff-contra-o-plano`; o README diz "Windows has not been tested" |
| `tester-army/e2e` | Apache-2.0 | 2026-11-07 | testes | o agente descobre os passos, grava o caminho e repete sem modelo | nenhuma. Só serve para UI web e não menciona Windows |
| `pinchtab/pinchtab` | MIT | 2026-10-27 | verificação | servidor Go que controla o Chrome pela árvore de acessibilidade | nenhuma. O README diz que o Windows é "limited and best-effort"; é a mesma âncora do `vercel-labs/agent-browser`, que reprovou em Windows |
| `lboel/untangle` | AGPL-3.0 | 2026-11-06 | entendimento de código | (código lido) métricas de complexidade por função | enxertado como `complexas` no 2.5.0 (#649); a segunda metade virou `complexidade-no-diff-do-enxugar` |

O "You Should Know" (média, memória) ficou sem repo identificado. O vizinho mais próximo é o
`alexknowshtml/claude-auto-handoff`, e a ideia `retomada-pos-compact-com-ponteiro-e-teto` já
cobre o mecanismo.
