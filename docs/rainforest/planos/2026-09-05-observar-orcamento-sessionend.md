# Plano: orçamento do `observar.cjs` dentro do teto real

Design: `docs/rainforest/design/2026-09-05-observar-orcamento-sessionend.md`
Issue: #198

Serial: as três tarefas tocam arquivos que se leem entre si (a tarefa 3 lê os
valores que as tarefas 1 e 2 escrevem), então não há fatia paralela.

### 1. Baixar `ORCAMENTO_MS` e trocar o comentário que documenta a premissa errada

atende: D1
arquivos: `scripts/observar.cjs`

O comentário de `:470` afirmava "o hook que chama este script tem teto de 120 s" —
premissa falsa, e é dela que o 90000 saiu. Passa a explicar o orçamento
compartilhado, com a fórmula do `i`, as constantes medidas no binário e o custo real
(19 sessões vazadas), para que a próxima edição não repita o cálculo errado.

critério: `grep` em `scripts/observar.cjs` mostra `|| 25000;` e nenhum `|| 90000;`.

mutacao:
  arquivo: `scripts/observar.cjs`
  de: `|| 25000;`
  para: `|| 90000;`
  bateria: `bash scripts/testa-observar.sh`

### 2. Baixar as DUAS declarações de `timeout` no `hooks.json`

atende: D2
arquivos: `hooks/hooks.json`

`observar.cjs` aparece em `SessionStart` e em `SessionEnd`, as duas com `timeout: 120`.
A troca é feita com asserção de contagem (esperado exatamente 2), e o JSON é
reparseado antes de gravar.

critério: parser do `hooks.json` lista as duas declarações de `observar.cjs` com
`timeout=30`, e o arquivo continua JSON válido.

mutacao:
  arquivo: `hooks/hooks.json`
  de: `"timeout": 30` na entrada de `SessionEnd`
  para: `"timeout": 120`
  bateria: `bash scripts/testa-observar.sh`

### 3. Casos 18-20: a bateria passa a ler o número declarado

atende: D3
arquivos: `scripts/testa-observar.sh`

Três casos que leem valor declarado em vez de exercitar comportamento, porque o
contrato aqui é o número e a mutação provou que nenhum caso de comportamento o
enxerga:

- **18** — `ORCAMENTO_MS` padrão < 60000 ms (teto duro do evento);
- **19** — toda declaração de `observar.cjs` no `hooks.json` tem `timeout` ≤ 60 s,
  e a mensagem de falha nomeia qual delas estourou (é o caso que pega o conserto
  pela metade);
- **20** — `ORCAMENTO_MS` < menor `timeout` declarado, que é a folga para os irmãos.

critério: `bash scripts/testa-observar.sh` sai 0 com 41 ok / 0 falha, e cada mutação
das tarefas 1 e 2 derruba **apenas** os casos que a leem.

mutacao:
  arquivo: `scripts/observar.cjs`
  de: `|| 25000;`
  para: `|| 90000;`
  bateria: `bash scripts/testa-observar.sh`
