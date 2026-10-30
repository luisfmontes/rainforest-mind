# Catraca de mutação: o que cada saída significa

Movido de `skills/executar/SKILL.md`, seção "A catraca de mutação: quem roda não é quem julga", em 2026-10-30, para abrir folga no teto de 16 KB da skill.

| exit | significa | o que fazer |
|---|---|---|
| `0` | mutação casou e bateria **VERMELHA** | única aprovação: a bateria sabe falhar |
| `2` | mutação casou e bateria **VERDE** | reprovado — a bateria não mede o conserto |
| `3` | `MUTACAO NAO APLICADA` — o `--de` não existe no fonte | a declaração está errada; nada foi medido |
| `4` | não dá para MEDIR — a bateria já falha no fonte íntegro, ou o `--de` casa mais de uma vez | conserte o baseline (ou desambigue o `--de`) e rode de novo; nada foi mutado |
| `5` | suspeita de CORTE DE SHELL — pós-mutação < 10% baseline (ou < 1 s) | confirme rodando a bateria pós-mutação à mão; se sair 0, ignorar; se durar >= 1 s, aumentar piso |
| `1` | erro de uso, ou bateria sem veredito (estouro de tempo / sinal) | não é aprovação nem reprovação |
| `69` | bateria não **EXECUTA** — ambiente (D5) | bloqueio de ambiente (regra 14): anuncie e não redespache |

O `4` recusa **antes** de tocar no fonte, e cobre os dois jeitos de a medição
não existir: bateria vermelha no íntegro (o vermelho depois da mutação não
provaria nada, porque já era vermelho) e `--de` ambíguo (a inversão cairia num
trecho que não é o que a tarefa declarou, e D11 manda recusar quando a mutação
não casa com o fonte).

`2` e `3` são códigos **diferentes de propósito**: "a bateria é fraca" e "a
declaração de mutação está errada" pedem conserto em lugares distintos, e o
`3` nunca pode ser lido como reprovação da bateria. Veredito certo pelo
motivo errado é pior que veredito errado, porque ninguém volta a olhar.

No Git Bash, argumento que **começa** com `//` chega ao script com uma barra
só (`'// coment'` vira `'/ coment'`) e não casa, dando `3` sem culpa do fonte.
Ponha um caractere antes das barras, ou exporte `MSYS_NO_PATHCONV=1`.

