# Design — a catraca de mutação não pode depender de relógio de parede

Issue #121. Achada rodando a varredura completa das 57 baterias na `main` logo
depois do merge do PR #116.

Data: 2026-08-26.

## Objetivo

Tirar o veredito de `scripts/testa-conferir-mutacao.sh` da dependência de quanto
a máquina está ocupada.

Duas varreduras completas, mesma árvore (`6668028`), mesmo comando serial do
`.github/workflows/baterias.yml`:

```
varredura 1:  === total=57 vermelhas:[ scripts/testa-conferir-mutacao.sh] ===
varredura 2:  === fim ===        # zero vermelhas
```

Isolada, cinco execuções seguidas, cinco verdes (`ok: 70  falhou: 0`).

Pronto quando: a lógica da heurística é provada sem cronômetro, e os casos que
ainda medem tempo **anunciam** quando a pré-condição de tempo não valeu, em vez
de reprovar.

## O mecanismo, nomeado

`scripts/conferir-mutacao.cjs` decide "suspeita de corte de shell" por relógio de
parede:

```js
const PISO_ABSOLUTO_MS = 1000;
if (baselineDuracao >= PISO_ABSOLUTO_MS && posDuracao < baselineDuracao * 0.1) { … exit 5 }
```

E dois casos da bateria montam fixtures cuja **duração** é o que define o
veredito esperado:

- **Caso 10** — `sleep 2` no baseline, pós-mutação sai na hora; espera `exit=5`.
  Sob carga, o caminho "instantâneo" (spawn de `bash` + `grep` + `exit`) pode
  passar de 200 ms, a razão sobe acima de 10%, a heurística não dispara e o caso
  recebe `exit=1`.
- **Caso 12** — `sleep 0.1` no baseline; espera `exit=0`, porque o baseline
  abaixo do piso impede a heurística. Sob carga, spawn de processo no Git Bash
  em Windows empurra o baseline acima de 1000 ms, o piso deixa de proteger, a
  heurística dispara e o caso recebe `exit=5`.

O caso 13 (verde e rápida) **não** é frágil: o `2` é decidido antes do bloco de
tempo, e por escolha explícita — está comentado no fonte.

Não consegui capturar a saída da execução vermelha: na varredura 1 mandei a
saída de cada bateria para `/dev/null`. Isso está registrado na issue como
limitação, e é o motivo de o desenho abaixo não depender de reproduzir.

## Decisões fechadas

- **D1 — a decisão da heurística vira função pura exportada, e a bateria testa a função com números fixos.**
  Porque: o que precisa ser provado é a **regra** (piso de 1 s, razão de 10%,
  fronteiras), e regra se prova com entrada, não com cronômetro. `suspeitaDeCorte
  (baselineDuracao, posDuracao)` recebe dois números e devolve um booleano; a
  bateria chama com 999/50, 1000/99, 1000/100, 5000/499 e afins. Zero relógio,
  zero carga, zero intermitência.

- **D2 — o comportamento em produção não muda.**
  Porque: o piso de 1 s e a razão de 10% foram calibrados contra um defeito real
  de 2026-08-24 e não há medição nova que justifique mexer. Esta entrega move
  **onde a regra é testada**, não qual é a regra. Extrair sem mudar é o que
  permite provar que não mudou.

- **D3 — os dois casos de ponta a ponta declaram a pré-condição de tempo e ANUNCIAM quando ela não vale, em vez de reprovar.**
  Porque: o caso 12 afirma "baseline abaixo do piso não dispara a heurística". Se
  o baseline medido ficou **acima** do piso, a pré-condição do caso não
  aconteceu — ele não falhou, ele não rodou. Reprovar aí é vermelho que não
  aponta defeito nenhum, e vermelho assim é como se aprende a ignorar vermelho.
  O anúncio nomeia a duração medida e o limite, para que ninguém confunda com
  cobertura.

- **D4 — as margens dos fixtures de ponta a ponta ficam folgadas, para que o anúncio seja raro.**
  Porque: anúncio frequente vira ruído e o ruído vira cegueira. O baseline do
  caso 10 sobe de 2 s para 5 s, o que dá 500 ms de folga para o caminho curto em
  vez de 200 ms.

- **D5 — a bateria nunca fica verde tendo pulado os dois casos de ponta a ponta.**
  Porque: o risco do anúncio é virar escape. Se **ambos** os casos e2e forem
  pulados na mesma execução, a bateria falha — a máquina estava ocupada demais
  para essa medição significar alguma coisa, e isso precisa parar o placar.

## Avaliado e descartado

- **Retentar o caso N vezes até passar.** É o caminho mais barato e o pior:
  retentativa em catraca ensina exatamente o hábito que a catraca existe para
  impedir. Descartado sem hesitação.

- **Aumentar o piso absoluto de 1 s para um valor maior.** Faria o caso 12 caber
  com folga. Descartado: muda o comportamento em produção para acomodar o teste,
  e o piso tem calibração medida atrás dele.

- **Variável de ambiente que ajuste piso e razão só nos testes.** Torna os dois
  casos e2e determinísticos. Descartado por agora: cria superfície de produção
  que só existe para o teste, e um `PISO_ABSOLUTO_MS` sobrescrevível por env é
  uma chave para desligar a heurística em produção sem querer. A função pura
  entrega o mesmo determinismo sem essa chave.

- **Apagar os dois casos e2e e ficar só com a função pura.** Simples e
  determinístico. Descartado: a função pura não prova que a duração medida chega
  até ela, nem que o `exit 5` sai de verdade. Fio inteiro tem de ser exercitado
  pelo menos uma vez.

## Fora de escopo

- **A calibração do piso e da razão.** Não há medição nova; mudar seria chute.
- **As outras 58 baterias do repositório.** Só a
  `scripts/testa-conferir-mutacao.sh` foi medida como intermitente.
- **O `hooks/testa-contexto-sessao.sh` (#120).** Mesma família — veredito que
  depende do ambiente —, mas o eixo lá é estado (quantas janelas abertas, que
  hora é), não carga, e a issue foi fechada por outra sessão.

## Em aberto

- **A execução vermelha nunca foi capturada.** O mecanismo acima é a explicação
  que os números sustentam, não uma reprodução. Se depois desta entrega a
  bateria voltar a piscar, a hipótese estava errada e o rastro para investigar é
  outro.
- **Se outras baterias do repositório têm o mesmo eixo** não foi medido. A
  varredura só acusa vermelho, e vermelho intermitente só aparece quando aparece.
- **Quanta folga é folga suficiente** é chute calibrado, não medição: 5 s de
  baseline dá 500 ms para o caminho curto, e ninguém mediu quanto o spawn no Git
  Bash realmente custa sob carga nesta máquina.
