# Memória: reconciliação na escrita e consolidação automática

## Objetivo
A memória deixa de só acumular: observação nova que corrige, repete ou complementa
uma antiga passa a atualizá-la ou fundir-se a ela (enxerto da reconciliação
store/update/merge/skip do `TencentDB-Agent-Memory`, `MemoryCore/src/core/record/l1-dedup.ts`),
e a consolidação em `resumos` passa a rodar sozinha — hoje é manual e nunca rodou.

Ponto de partida medido em 2026-09-16 (`~/.rainforest/rainforest.db`): 10.855
observações, 0 consolidadas, 0 resumos; a mais antiga é de 2026-08-04, então a regra
atual de 60 dias só teria o que consolidar em 2026-10-03. Captura estava parada desde
2026-09-03 por `spawn EINVAL` no `claude.cmd` (#282, PR #283) — pré-requisito deste
trabalho, já corrigido.

## Decisões fechadas
- **D1 — Reconciliação roda numa passada de manutenção separada, junto com a consolidação, nunca dentro do `observar.cjs`** — porquê: o hook tem 30 s de orçamento e foi exatamente ali que a captura parou calada por 13 dias; mais uma chamada de LLM no caminho da escrita aumenta esse risco.
- **D2 — Reconcilia-se a observação como ela é hoje (resumo de 1–2 frases), sem mudar a extração para fatos atômicos tipados** — porquê: trocar a unidade da memória é outro projeto; o prompt de reconciliação é que se adapta a resumo.
- **D3 — Update/merge marca a antiga com `substituida_por` e a tira da injeção e da busca por padrão; nada é apagado** — porquê: preserva o invariante "verdade de máquina não se apaga" e deixa fusão ruim reversível.
- **D4 — Candidatas parecidas vêm do FTS5 existente, sem vetor; mede-se a perda numa amostra** — porquê: custo zero de dependência; o risco conhecido é o corpus bilíngue (importadas do claude-mem em inglês, nativas em português), e a medição decide se vetor vira decisão futura.
- **D5 — A manutenção dispara no SessionStart, em background, com trava de no máximo uma execução por dia** — porquê: não altera o ambiente do usuário (tarefa agendada exigiria instalar) e não cai no orçamento curto do SessionEnd.
- **D6 — O acervo existente também é reconciliado, gradualmente, com teto de lotes por execução** — porquê: as observações de estado envelhecido ("endpoint agora funciona") estão justamente no acervo.
- **D7 — Consolidação agrupa por sessão de origem, a partir de 30 dias, em vez de lotes cronológicos de 10 com 60 dias** — porquê: sessão já é unidade de assunto; lote cronológico mistura temas sem relação num resumo só.
- **D8 — Falha da manutenção ou da captura (pendência com mais de 48 h) vira uma linha na abertura da sessão, além do `/saude`** — porquê: o `/saude` já acusava "pipeline parado há mais de 48h" e ninguém viu por 13 dias; aviso que só aparece quando alguém pergunta não é aviso.

## Avaliado e descartado
- **Reconciliar dentro do hook de captura** — o hook de 30 s já falhou em silêncio (#282); ver D1.
- **Apagar as memórias substituídas, como o Tencent faz (`l1-writer.ts`)** — perde o invariante do schema e a reversão; ver D3.
- **Instalar `ruflo` ou `TencentDB-Agent-Memory`** — avaliados no código em 2026-09-16 (`vigias/livro-de-repos.md`): nenhum fecha laço de resultado sobre a memória; ruflo fora da âncora, Tencent só enxerta.
- **Manter a regra 60 dias / 50 / lotes de 10** — nunca dispararia antes de 2026-10-03 e agrupa por data, não por assunto; ver D7.

## Fora de escopo
- **Sinal de utilidade da memória injetada (feedback de resultado → ranking)** — é o que faria o agente "ficar mais inteligente a cada rodada", mas hoje não há como observar se a memória injetada foi usada; plantado como ideia, retomar duas semanas depois de a reconciliação rodar.
- **Mudar o prompt de captura do `observar.cjs`** — ver D2.
- **Relevância por embedding** — só se a medição de D4 mostrar perda relevante.

## Em aberto
- Números de D6 (teto de lotes por execução) e o limiar de similaridade das candidatas de D4 nascem de chute calibrado no plano e se revisam com a primeira medição.
