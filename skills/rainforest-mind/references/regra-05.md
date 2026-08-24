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
