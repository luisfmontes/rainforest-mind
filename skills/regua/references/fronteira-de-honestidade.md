# A fronteira de honestidade

Regra de medição desta skill. Vale sempre que o loop for reportar número.

Esta skill não faz medição. Não aceita estimativa, não converte histórico em
previsão, não responde perguntas em forma de "se pudéssemos sair da baseline".

**Nunca imprima número de economia estimado sobre um repo vivo.** A versão não
construída nunca foi escrita, então não há baseline de onde subtrair. Não existe
frase "quanto as regras economizam?" que responda sem dados medidos.

Número só sai de dois lugares:

1. **Bateria medida, com gate.** Um conjunto fixo de tarefas, rodado **com e sem**
   a coisa sendo medida, que conta linhas e valida que o resultado está correto.
   Sem gate, "menos linhas" não significa nada — é "errado por menos linhas", que é
   pior. O exemplo é `scripts/medir-escada.sh`: roda um conjunto fixo com e sem o
   `additionalContext` da escada, colhe dois números (linhas e gate), e reporta.
   Sem CLI declarado na config, o script **pula e diz que pulou** — nunca inventa
   número.

2. **Contagem real.** Um ledger que registra cada adiamento ou corte — a
   `scripts/atalhos.cjs`, que varre o repo e colhe os marcadores `atalho:` e
   `ponytail:`. Isto é contagem, não estimativa: o número está ali, em código.

Se o que você quer medir não cabe em nenhuma das duas formas acima, não está pronto
para número. Fica escrito "menos boilerplate" até que vire um dos dois. E "menos
boilerplate" é prognóstico, não fato, e tem que ser dito assim.

Esta regra é comprada com a vida do repositório. Estimativa que fica lá não envelhece
bem — daqui a um ano ela é história, e a próxima pessoa lê como fato. Três linhas
de honestidade ("número saiu de bateria medida com gate, CLI: codex") custam bem
menos que quatro meses de alguém acreditando em número que não existe.

## O topo continua procedural

A sessão que orquestra precisa chamar o comando certo, porque quem orquestra é
um LLM. Não é promessa de impossibilidade de burla; é limite honesto de onde
termina a garantia.

## E o selo precisa de histórico

O selo é o git, e em clone raso não há no que ancorar: o único commit visível é
a fronteira do clone, e o conteúdo dela é, por construção, o que está no
checkout — a comparação de integridade compararia o arquivo consigo mesmo e
sairia 0 sobre régua adulterada.

Por isso `conferir-regua.cjs` detecta clone raso e **se recusa a julgar**
(exit 2, ambiente), em vez de julgar errado. Quem roda o loop em CI precisa de
`fetch-depth: 0` — `--depth 1` é o default do `actions/checkout`.
