# Recall do FTS5 como buscador de candidatas — reconciliação de memória

Medição da tarefa 7 (D4) do plano
`docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md`, rodada em
2026-09-18 contra cópia somente-leitura de `C:\Users\Luis\AppData\Local\Temp\rfm-recall-sandbox\rainforest.db`.

## Desenho

A pergunta do D4: o FTS5 sozinho acha a observação certa para reconciliar, ou falta
índice vetorial? O risco nomeado é o corpus bilíngue: observações nativas em
português e observações importadas do claude-mem em inglês.

Para cada observação sondada, o conjunto de candidatas apresentado à LLM é **maior**
que o do FTS5 — senão o recall sairia 100% por construção, porque a LLM só veria o
que o FTS5 trouxe:

- as **K = 5** candidatas que o FTS5 traria (`K_CANDIDATAS` de `scripts/memoria.cjs`,
  `bm25(observacoes_fts)`, mesmo `projeto`);
- mais as **independente: 20** observações mais recentes do mesmo `projeto`,
  anteriores à sondada (função `buscarIndependentes` em
  `scripts/medir-recall-reconciliacao.cjs` — não vem do FTS5).

A união (sem duplicar id) é embaralhada e apresentada à LLM numerada de 1 a N, sem id
de banco visível. Exemplo de conjunto apresentado (observação 18297): FTS5 trouxe 5, independentes trouxe 20, união sem duplicata = 25 candidatas (maior que K = 5).

Pergunta-se à LLM exatamente o que `cmdReconciliar` pergunta na produção (mesma
ação válida: store/update/merge/skip). Das decisões `update`/`merge`, o **recall**
é a fração cujo alvo escolhido estava entre as 5 do FTS5.

## Amostra

- amostra: 200 (requisitada via `--amostra`; obtida: 200)
- estratificada meio a meio entre as duas metades do corpus bilíngue
- falhas na chamada à LLM (item "sem decisão", não contam no recall): 8

## Resultado

| corpus | origem | n na amostra | store | skip | decisões update/merge | hits (no FTS5) | recall | falhas |
|---|---|---|---|---|---|---|---|---|
| portugues | `sessao:%` | 100 | 24 | 5 | 63 | 47 | 74.6% | 8 |
| ingles | `claude-mem:%` | 100 | 10 | 25 | 65 | 58 | 89.2% | 0 |

recall global: 82.0% (105/128)

## Veredito

veredito: recall de 70% ou mais nas duas metades (portugues 74.6%, ingles 89.2%) — mantém FTS5 com K=5, sem vetor.

Limiar deste plano: recall abaixo de 70% em qualquer das duas metades vira decisão de
vetor no próximo design; 70% ou mais mantém o FTS5 com K = 5.
