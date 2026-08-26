# Plano: a catraca de mutação não pode depender de relógio (#121)

Design: docs/rainforest/design/2026-08-26-catraca-por-relogio.md

## O que não pode quebrar

- **O comportamento em produção fica idêntico.** Piso de 1 s e razão de 10% não
  mudam. Se mudarem, todas as catracas já rodadas neste acervo passam a
  significar outra coisa.
- **A catraca continua recusando bateria que não sabe falhar** — exit 2 — e
  continua recusando mutação que não casa (3) e baseline não-verde (4). Nenhum
  dos outros vereditos é tocado.
- **Nenhuma variável de ambiente nova** que permita ajustar piso ou razão: seria
  chave para desligar a heurística em produção sem querer.
- **Nada é escrito fora da caixa de teste.**

## Tarefas

### 1. A heurística vira função pura exportada [tipo: implementar]
atende: D1, D2
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `baselineDuracao >= PISO_ABSOLUTO_MS && posDuracao < baselineDuracao * 0.1`
  para: `baselineDuracao > PISO_ABSOLUTO_MS && posDuracao < baselineDuracao * 0.1`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: o caso "a fronteira do piso: 1000 dispara, 999 nao" de `scripts/testa-conferir-mutacao.sh`
pronto quando: `suspeitaDeCorte(baseline, pos)` está exportada e a bateria a chama com números fixos cobrindo as quatro fronteiras — piso exato (1000) e um abaixo (999), razão exata (10%) e um acima —, sem cronômetro nenhum; e a mutação que troca `>=` por `>` no piso deixa a bateria **vermelha**, provando que a fronteira está medida e não só a região

### 2. Os casos de ponta a ponta anunciam quando a pré-condição de tempo não valeu [tipo: implementar]
atende: D3, D4, D5
arquivos: `scripts/testa-conferir-mutacao.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/testa-conferir-mutacao.sh`
  de: `veredito_pulos() { [ "${1:-0}" -lt 2 ]; }`
  para: `veredito_pulos() { true; }`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: o caso "a trava do pulo duplo, provada com numero" de `scripts/testa-conferir-mutacao.sh`

> Alvo reescrito em 2026-08-26, durante a execução. A primeira redação mandava
> mutar o `if` solto no fim do arquivo, e o `conferir-mutacao.cjs` **recusou**:
> desligando a trava a bateria continuava verde, porque numa execução normal
> `pulados_e2e` é 0 e aquele ramo nunca é exercitado. O veredito virou função e
> passou a ser provado com número — 0 e 1 não reprovam, 2 e 3 reprovam.
pronto quando: os casos 10 e 12 leem a duração que o próprio `conferir-mutacao.cjs` imprime, comparam com a pré-condição que cada um afirma, e **anunciam** com a duração medida e o limite quando ela não valeu — em vez de contar falha; o baseline do caso 10 sobe para 5 s; e pular **os dois** na mesma execução faz o placar final reprovar, provado forçando o pulo duplo
