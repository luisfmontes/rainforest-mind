# Impasse — 2026-11-15-zerar-issues-14 (teto de 3 reprovações do revisar)

## O que aconteceu
- Revisão 1 reprovou com 12 achados: 10 consertados, 2 viraram resíduo pela D6.
- Revisão 2 reprovou com 9 achados, todos consertados no 4fb5da84.
- Revisão 3 (HEAD b591353c) reprovou por **um** achado dentro do modelo: falso positivo
  em `eval "grep 'x$' f"` e `iex "... 'x$'"`. A base sai 0 e o HEAD sai 2.
  - Ela não achou nenhuma regressão (base barra e HEAD deixa passar). Mediu cerca de 1.250
    comandos de fuzz contra bash real e mais de 150 comandos legítimos.
  - Achados de severidade baixa:
    - `$(( … )) # … gh` barrava.
    - O teto de 64 linhas de continuação barrava.
    - Linha `# … \` no corpo de heredoc barrava. A base já barra o mesmo corpo sem o `# … \`.
  - Os demais são preexistentes ou estão fora do modelo da D6.

## Por que não é critério errado nem decisão errada
O design e o plano se sustentaram. Cada reprovação trouxe falsos positivos cada vez
menores, criados pelos próprios consertos de segurança. Não houve divergência de D<n>.

## Consertos já feitos para a 4ª rodada (não integrados ao estado)
- `eval`/`iex`: o `$'` só conta fora de aspas, pela mesma função do `bash -c`.
- O comentário depois de `((` continua duvidoso, mesmo com o `((` já fechado. A tentativa de
  contar `((` contra `))` foi enganada duas vezes, então o falso positivo baixo virou custo
  aceito no design.
- Sai o teto de 64 linhas. O orçamento linear de varredura (D4d) cobre o comando gigante.
- Design: título da D3 corrigido. Os resíduos e o caso do heredoc foram registrados em
  "Fora de escopo".

## Decisão pedida ao usuário
Liberar uma 4ª rodada de revisão com esses consertos. É o recomendado.
