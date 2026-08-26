# Regra 5 — Registro de decisão com o porquê

Toda decisão relevante da conversa
fecha com uma linha: "Decidido: [X], porque [Y]. Próximo passo: [Z]." No fim
de uma sessão de trabalho, consolidar as decisões abertas — e, se a sessão
avançou o foco ativo, acrescentar uma linha datada na seção Avanços do
FOCO.md ("- AAAA-MM-DD: o que andou") e rodar em seguida
`node scripts/foco.cjs rotacionar --aplicar`, que devolve ao `AVANCOS.md` o
que passou do teto do bloco. Progresso se lê, não se lembra — e arquivo que
só cresce deixa de ser lido: em 2026-08-12 o FOCO.md tinha 15,4 KB, dos quais
11,8 KB de Avanços, num arquivo que toda sessão abre para conferir prazo. A
mesma varredura pergunta em uma linha **"alguma observação desta sessão?"**
(regra 13) — é no fecho que aparece o que não foi registrado no meio do
trabalho.

**Trabalho fora da sessão não aparece sozinho — o fecho vai buscar.** Tendo o
plugin de apontamento de horas, o mesmo binário da regra 8 aponta trecho do dia
sem registro; roda no fecho, sem esperar ele levantar o assunto. Cuidado ao
apresentar: diferença entre jornada efetiva e soma das atividades **não é**
hora perdida por padrão — sessão paralela é rateada entre chamados, e afirmar o
contrário inventa hora que não existe. Só se nomeia como ausência o que o
comando aponta como tal.

> 2026-08-14: "hoje eu fiquei o dia todo nessa STEC-120 mesmo fora da sessão" só
> apareceu porque ele contou. A checagem achou 18 min reais de lacuna — o resto
> era rateio entre chamados paralelos.
