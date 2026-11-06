# Plano: complexidade por função no enxugar

Design: docs/rainforest/design/complexidade-por-funcao.md

## O que não pode quebrar
- Os subcomandos `listar`, `maiores`, `separar` e `conferir` do `catalogo-funcoes.cjs` saem como hoje: os casos 1 a 9 de `bash scripts/testa-catalogo-funcoes.sh` seguem verdes.
- `skills/enxugar/SKILL.md` fica abaixo de 500 linhas e 16 384 bytes (`bash scripts/testa-teto-skills.sh`), e as checagens atuais de `bash scripts/testa-enxugar-estrutura.sh` seguem verdes.
- Node puro: `scripts/lib/complexidade.cjs` só usa JavaScript sem `require` de pacote externo.
- Nenhuma linha do `lboel/untangle` (AGPL-3.0) entra no repositório (D8).

## Tarefas

### 1. Medida de complexidade por função e subcomando `complexas` [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6, D8
arquivos: `scripts/lib/complexidade.cjs`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: nenhuma
busca:
- repo | rg -i "complexidade|cognitiv|ciclom|cyclomatic" skills agents scripts hooks | nada; só linhas por arquivo em scripts/catalogo-funcoes.cjs (maiores)
- livro | vigias/livro-de-repos.md "untangle" | sem linha: repo avaliado nesta sessão, AGPL, trilha enxertar só do mecanismo
- web | lboel/untangle packages/complexity/src/cognitive.ts | lido em 2026-11-06 no clone 87bc00d4; usa tree-sitter, sem Dart
desfecho: estender
mutacao:
  arquivo: `scripts/lib/complexidade.cjs`
  de: `return 1 + profundidade;`
  para: `return 1;`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso "10. complexas: aninhamento pesa mais que ramos em fila"`
prova: `node scripts/catalogo-funcoes.cjs complexas --raiz scripts --top 1`
pronto quando: com o próprio repositório do plugin como entrada real, `node scripts/catalogo-funcoes.cjs complexas --raiz . --top 5` sai 0 e imprime 5 blocos `<c> cognitiva  <y> ciclomática  <arquivo>:L<linha> <nome>` em ordem decrescente de cognitiva, cada `arquivo:L<linha>` apontando para a linha em que `node scripts/catalogo-funcoes.cjs listar --raiz .` diz que aquela função começa, cada bloco com até 3 linhas `    +<n> L<linha> <rótulo>` cujas linhas caem entre o começo da função e o fim dela, e termina com a linha `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`; numa fixture com JS, TSX e Dart, a bateria confere os valores exatos: dois `if` em fila dão cognitiva 2 e o mesmo par aninhado dá 3; `a && b && c` dá 1 e `a && b || c` dá 2; `String? x`, `x?: T`, `a?.b` e `a ?? b` não contam e `c ? 1 : 2` conta; `if` dentro de string `'if (x)'`, de comentário, de template literal com `${ {a: 1} }`, de string tripla e crua do Dart e de texto JSX com apóstrofo (`<p>Don't</p>`) não conta; `{` de objeto literal não aprofunda; closure dentro da função soma na mãe e não sai à parte; arquivo `.py` sai na linha `não medido: <n> função(ões) py — linguagem sem chaves` — provado por `bash scripts/testa-catalogo-funcoes.sh`, que monta esses casos e roda o repo real, nenhum deles afirmando sobre o texto do fonte

Forma prescrita: `scripts/lib/complexidade.cjs` exporta `tokenizar`, `medirArquivo` e `incrementoAninhado`; `incrementoAninhado(profundidade)` é uma expressão só, `return 1 + profundidade;`, e é o único lugar em que a profundidade entra na cognitiva. `catalogo-funcoes.cjs complexas [--raiz <dir>] [--top N]` usa `candidatos` e `definicoesDoArquivo` do próprio script.

### 2. Modo 2 do enxugar roda `complexas` depois do `maiores` [tipo: docs]
atende: D7
arquivos: `skills/enxugar/SKILL.md`, `scripts/testa-enxugar-estrutura.sh`
depende de: 1
mutacao:
  arquivo: `skills/enxugar/SKILL.md`
  de: `catalogo-funcoes.cjs complexas --raiz <repo> --top 10`
  para: `catalogo-funcoes.cjs --raiz <repo> --top 10`
  bateria: `bash scripts/testa-enxugar-estrutura.sh`
  fixture: `testa-enxugar-estrutura.sh, caso "D7: modo 2 roda complexas depois do maiores, fora do líquido"`
pronto quando: com o `skills/enxugar/SKILL.md` real, o trecho do modo 2 (entre `### Modo 2` e `### Passada de duplicata semântica`) manda rodar `catalogo-funcoes.cjs complexas --raiz <repo> --top 10` **depois** da linha do `maiores`, diz que a nota é aproximada e que é contexto que não vira tag nem entra no `líquido:` (D7), e diz que o "não medido" se lê e não se esconde (D6) — provado por `bash scripts/testa-enxugar-estrutura.sh`, cujo caso novo confere a ordem (linha do `complexas` maior que a do `maiores`) e as duas frases, e por `bash scripts/testa-teto-skills.sh`

### 3. README, CHANGELOG e versão 2.5.0 [tipo: docs]
atende: D9
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
mutacao: n/a
  motivo: tarefa só de texto e número de versão; a falsificação é a coerência com o que as tarefas 1 e 2 entregaram, conferida no critério
pronto quando: com o repositório real, o README descreve a complexidade por função do `enxugar` no mesmo lugar em que cita `scripts/catalogo-funcoes.cjs`, dizendo que é aproximação, sem crédito ao untangle (D8); `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.5.0`; o selo do README diz 2.5.0 e o `CHANGELOG.md` abre com 2.5.0 — provado por `grep -c "complexas" README.md` ≥ 1, `grep -ci "untangle" README.md` = 0, `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` = `2.5.0`, e `bash scripts/testa-plugin-codex.sh` e `bash hooks/testa-abertura-mod-config.sh` verdes
