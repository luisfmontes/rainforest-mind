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
- Resposta, em 2026-11-16: "recomendado". A 4ª rodada foi liberada.

## Revisão 4 (HEAD 870cb69b)
- Ela reprovou por **uma regressão**, causada pelo conserto do `eval` no 6fed0986. Uma palavra
  mista de aspas (`eval '$'"'gh' issue comment 5"`) passava no gate de subagente, e a base barrava.
  O gate de fechamento barrava a mesma forma.
- Conserto no ab00f990: o `eval` confere o texto depois da remoção de aspas do bash.
  - O fuzz de 130 formas do revisor deu 0 regressões.
  - As sondas de falso positivo dele dão base igual ao HEAD no gate de subagente.
- Dois achados baixos viraram custo aceito no design:
  - `[[` e `$[` antes de um `#`;
  - a leitura dupla com mais de 350 linhas `#…\`.

- A revisão de segurança do ab00f990 achou outra regressão da mesma classe, que vinha do
  db99558c. A palavra mista sem `$` (`eval 'g'"h issue close 12"`) passava no gate de subagente.
  O conserto está no f3976b50: o texto desaspado é o script que o gate lê dentro do `eval`.

## Decisão pedida ao usuário (2)
Liberar uma 5ª rodada com os consertos do ab00f990 e do f3976b50. É o recomendado.
- Resposta, em 2026-11-16: "sim cara vai no automatico". Lida como a opção B: a 5ª rodada
  está liberada, e as seguintes da rodada 14 também, desde que cada reprovação seja uma
  regressão consertada com teste e mutação.

## Revisão 5 (HEAD 82ef09e2)
- Reprovou por duas regressões altas no gate de subagente, com a mesma causa: o `textoAPartir`
  remontava pela primeira aspa a palavra que mistura aspa dupla e contrabarra.
  - `eval "gh"\ issue\ close\ 12` e `bash -c "eval \"gh issue comment 5 --body hi\""` saíam 0, e a base barrava.
- Conserto: a palavra mista com contrabarra guarda o texto original (`raw`). A mutação deixa 6 casos
  vermelhos. O fuzz de 100 formas da classe dá 0 regressões com `gh` rodando.
- Rodada 6 liberada pela autorização de 2026-11-16 ("vai no automatico").
