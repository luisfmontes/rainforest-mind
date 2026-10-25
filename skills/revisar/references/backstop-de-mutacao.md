# Backstop de mutação (Issue #4)

`exigir --estagio revisar` **captura um instantâneo**:
o `HEAD` do repositório e a lista de caminhos sujos (`git status --porcelain`).
Depois, `marcar --estagio revisar --status ok` **compara** esse instantâneo e
recusa (exit 2) se:

1. **HEAD mexeu** — qualquer movimento reprova. Se o HEAD andou, a base do diff
   que você revisou mudou, e a revisão foi feita contra outra árvore. A mensagem
   distingue "você commitou" de "outra janela commitou" e diz o que fazer: re-rode
   `exigir revisar` e revise novamente.

2. **Caminho sujo NOVO** — arquivo que não estava no instantâneo mas aparece agora.
   A comparação usa **conjuntos, não contagem**: sujeira pré-existente é legítima
   (outro trabalho em andamento no mesmo clone) e não reprova. Só caminho novo
   recusa.

   Uma exceção, e ela é o próprio mecanismo: `docs/rainforest/estado/<slug>.json`
   sai da comparação. É o `exigir` que o suja, ao gravar ali o instantâneo que
   acabou de tirar — e o arquivo é versionado neste repo. Sem a exceção a trava
   recusa o caminho feliz **sempre**, porque acusa de mutação a escrita que ela
   mesma fez. A bookkeeping da trava não pode ser evidência contra o revisor.

Se o instantâneo não existir (slug que fechou `revisar` sem passar pelo novo
`exigir`), **avise e não trave** — travar retroativo quebra trabalho em andamento.
O instantâneo fica gravado no arquivo de estado (`docs/rainforest/estado/<slug>.json`)
e sobrevive entre sessões.
