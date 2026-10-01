# Impasse: enxertos-poda-impressao, revisar reprovado 3 vezes

## O que reprovou, rodada a rodada

As três reprovações caíram na mesma decisão: separar **persistente** de **intermitente**
exige provar que houve uma **ronda limpa** entre as ocorrências, e o log de vigia não
prova isso.

1. **Rodada 1.** O log era procurado ao lado do `ERROS.md`, mas o `run-vigia.ps1` o
   grava em `RFM_ROOT` (`:5,152`). Havia também duas baterias quebradas pelo `require`
   novo.
2. **Rodada 2.** O `run-vigia.ps1` grava erro e sai **antes** do cabeçalho da ronda
   (`:56,70,97`). Uma vigia que falhava todo dia saía intermitente.
3. **Rodada 3.** Há ronda que ganha cabeçalho e nunca chega ao passo que falha: bridge
   fora do ar (`run-vigia.ps1:171,179`), `-Teste` (`backup-estado.ps1:126-128`), ou
   outro passo falhando antes (`backup-estado.ps1:145-151`). Essa ronda contava como
   limpa, e a falha saía intermitente sem nunca ter parado.

Cada conserto abria um caso novo, porque saber se uma ronda foi limpa depende de qual
passo cada vigia executa. Nenhum sinal genérico do log prova isso.

## Decisão do usuário (2026-09-30)

Opção (a), a recomendada: **um rótulo só**, `recorrente xN em 30 dias, desde DD/MM,
ultima DD/MM`. A lib deixa de ler o log, e só `RESOLVIDO` tira a falha da lista. Assim
ela nunca infere melhora, e continua entregando o objetivo do design: a falha que volta
para de chegar como novidade.

A separação por prova de passo (a opção b: ronda limpa só com a linha do log que prova
que o passo chegou ao fim, como `backup do estado:`) vira ideia plantada, e não entra
nesta entrega.
