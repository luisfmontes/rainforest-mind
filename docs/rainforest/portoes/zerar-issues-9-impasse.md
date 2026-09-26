# Impasse — zerar-issues-9, revisar reprovado 3 vezes (2026-09-26)

## O que reprovou
As três reprovações vieram do mesmo ponto: `valoresDaVariavelNoComando`
(`hooks/lib/tokens-comando.cjs`), que decide quando `bash $VAR` sem aspas deixa de
ser ilegível no `gate-fechar-issue` (#337, D1 com a emenda Q1 (a)).

1. Revisão 1: bateria rodando em dobro (casca `.sh`), caso de aspas simples da
   #313 ausente (que escondia um falso positivo do `textoAPartir`), `indexOf`,
   design corrompido. Consertados.
2. Revisão 2: crase colada à variável e array `f=(-c x.sh)` escapavam; a mesma
   causa abria segundo `for`, `read`, `printf -v`, `+=`, `declare`. Consertados
   com a regra "toda ocorrência do nome é ligação reconhecida ou uso".
3. Revisão 3: glob no valor (`f=?c`, `f=[-]c`) expande para `-c` quando existe um
   arquivo `-c` no diretório, e `bash $f "gh issue close 12"` vira `bash -c`.
   A lista branca barrava só `-` textual.

As outras seis issues (#313, #322, #335, #329, #323, #312) não tiveram achado
nas três revisões.

## Decisão do usuário (Q1, 2026-09-26): (a) quarta rodada
Conserto: o primeiro caractere de cada valor tem de ser literal — nem `-`, nem
metacaractere de glob (`?`, `*`, `[`), nem `~`. Expansão de glob preserva o
prefixo literal, então nenhum valor aceito vira `-c`. Casos novos na bateria:
`f=?c` e `f=[-]c`, com um arquivo `-c` real no sandbox, → 2.

Alternativa rejeitada nesta rodada, e recomendada se a quarta revisão achar
outro buraco na mesma função: (b) tirar a #337 desta entrega, reverter o código
da tarefa 1 e deixar a issue aberta.
