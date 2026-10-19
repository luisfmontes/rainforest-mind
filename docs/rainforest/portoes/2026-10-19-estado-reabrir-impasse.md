# Impasse: 2026-10-19-estado-reabrir (revisar, 3 reprovações)

## Rodadas
1. `[design]`: `--raiz` gravava o HEAD da outra árvore (beco sem saída); trazer a `main` acusava; edição não commitada passava; estado de outro slug contava. Emenda Q1–Q4.
2. `[design]`: a trava não estava no caminho real do `fechar`; refazer só o `verificar` pulava a revisão; a interseção de nomes errava nos dois sentidos. Emenda Q1–Q3 (patch-id por arquivo).
3. Implementação da comparação por `patch-id` (`impressao` em `scripts/estado.cjs`): diff acima de 1 MiB passava; o contexto de 3 linhas acusava a `main` vizinha; `--stable` ignorava indentação; conflito de versão resolvido e HEAD com o squash acusavam; `git mv` para pasta isenta passava; docs omitiam `--raiz` no `verificar` e o silêncio do `marcar fechar ok` sem HEAD.

## Por que não é critério nem decisão errada
Nenhum achado da rodada 3 muda uma D<n>: são defeitos da forma da comparação que a D1(c) decidiu. O critério do plano continua certo; faltavam casos.

## O que o usuário decidiu (2026-10-19)
Liberar a 4ª rodada para consertar os achados 1–7 da rodada 3, cada um com caso na bateria e mutação: `maxBuffer` e erro como "mudou"; `git diff -U0`; `patch-id --verbatim`; arquivo só conta quando o conteúdo em HEAD difere do verificado; `--no-renames`; docs.
Se a 4ª rodada reprovar, a saída alternativa é voltar à fórmula por nomes com falso positivo documentado. Isso muda a D1 e é decisão dele.
