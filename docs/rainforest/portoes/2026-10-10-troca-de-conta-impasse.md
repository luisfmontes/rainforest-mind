# Impasse — troca-de-conta, 3ª reprovação (2026-10-11)

## O que ficou em aberto
1. `scripts/conta.cjs` (`trocar` e `aplicarTroca`): a troca manual move os logins sem a guarda de 30 min
   da D11. Com o login da pasta a 2 min de vencer, `trocar pessoal --pasta trabalho` saiu 0 e moveu.
   O README promete a guarda sem ressalva.
2. `hooks/conta-puro.mjs` (`frase`): o evento `falhou` com `desfeito=false` vira "a troca ... foi
   desfeita", quando o desfazer não aconteceu.

Fora do veredito: a renovação da D13 nunca rodou contra o servidor real; a prova vai para o `verificar`.

## Ponto (revisor)
A D11 diz "antes de mover, os dois logins precisam de 30 min" sem restringir ao automático; a única
exceção é o login que sai vencido há mais de 10 min. O aviso falso esconde a troca pela metade que a
tarefa 17 queria tornar visível.

## Contraponto
O CLI relê o arquivo antes de renovar, então o risco real da troca manual é pequeno; e o caso do
aviso falso é raro (conferência no servidor que não bate e desfazer que devolve `mudou` ou `gravacao`).

## Opções
1. Troca manual com a mesma regra do vigia: guarda de 30 min nos dois logins e a exceção dos 10 min;
   a recusa diz quando tentar de novo. Aviso de `desfeito=false` diz que a troca não foi desfeita.
2. Troca manual isenta: emendar a D11 e o README; o Luís assume o risco na troca na mão.

## Decisão do usuário
2026-10-11: o Luís respondeu "recomendado" às duas perguntas: libera a 4ª rodada e escolhe a opção 1
(mesma regra na troca manual), com o conserto do aviso.
