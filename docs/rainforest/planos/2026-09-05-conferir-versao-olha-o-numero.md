# Plano: Issue #189 — conferir-versao olha o numero declarado e nao sai 0 sem ter medido

Design: docs/rainforest/design/2026-09-05-conferir-versao-olha-o-numero.md

## O que não pode quebrar

- A contagem de commits desde o ultimo bump continua certa e continua usando a
  pickaxe `-G` (nao `-S`): o caso "conta do ULTIMO bump, nao do primeiro commit
  do manifesto" da bateria existente e o que separa o mecanismo certo do numero
  plausivel, e tem de continuar verde.
- O teto continua decidindo nas duas direcoes, e continua ajustavel por `--teto`.
- Rodar fora de um repositorio git, ou num repositorio que nao e plugin, continua
  saindo `0` — falha aberta, declarada no cabecalho do script.
- Repositorio sem `origin/main` (todos os de fixture da bateria nascem de `git
  init`, sem remoto) continua medivel: a comparacao de numero e pulada, nunca
  vira recusa nem `4`.
- `--json` continua imprimindo o objeto e continua sendo o que a bateria le para
  extrair `commits`.

## Tarefas

### 1. Separar "nao ha o que conferir" de "eu deveria conferir e nao consegui" [tipo: implementar]
atende: D1, D2
arquivos: `scripts/conferir-versao.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: o `process.exit(4)` do ramo em que o repositorio e plugin e o manifesto e ilegivel
  para: `process.exit(0)`
  bateria: `bash scripts/testa-conferir-versao.sh`
  fixture: `testa-conferir-versao.sh, caso "manifesto ilegivel sai 4"`
pronto quando: com `.claude-plugin/plugin.json` presente mas vazio num
repositorio que **e** plugin, `node scripts/conferir-versao.cjs` devolve exit
`4` e imprime a linha que comeca com `versao: nao deu para medir`; e com o cwd
numa pasta sem `.git`, o mesmo comando devolve exit `0` e imprime `nao e
repositorio git`. Hoje os dois devolvem `0`.

### 2. Comparar o numero declarado com o de `origin/main` [tipo: implementar]
atende: D3, D4, D5, D6
arquivos: `scripts/conferir-versao.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: o `process.exit(2)` do ramo de versao declarada nao-maior que a de `origin/main`
  para: `process.exit(0)`
  bateria: `bash scripts/testa-conferir-versao.sh`
  fixture: `testa-conferir-versao.sh, casos "versao igual a da main recusa" e "versao 0.9.0 menor que a main 1.3.0 recusa"`
pronto quando: num repositorio com `origin/main` declarando `1.3.0`, o comando
`node scripts/conferir-versao.cjs --teto 999` devolve exit `2` e imprime os
**dois** numeros quando o manifesto local diz `1.3.0`, devolve exit `2` e
imprime os dois numeros quando diz `0.9.0`, e devolve exit `0` quando diz
`1.4.0`. O `--teto 999` esta no comando de proposito: prova que a recusa veio da
comparacao de numero, nao do teto de commits. Num repositorio sem remoto o mesmo
comando devolve exit `0` e a saida diz que nao comparou com `origin/main`.

### 3. Casos de bateria para os tres ramos novos [tipo: teste]
atende: D7
arquivos: `scripts/testa-conferir-versao.sh`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: esta tarefa e o instrumento de falsificacao das tarefas 1 e 2 — as duas
  inversoes que importam estao declaradas la, e apontam para esta bateria. Nao ha
  comportamento de producao aqui para inverter.
pronto quando: `bash scripts/testa-conferir-versao.sh` devolve exit `0` e a saida
contem os quatro casos novos nomeados (`manifesto ilegivel sai 4`, `versao igual
a da main recusa`, `versao menor que a da main recusa`, `versao maior que a da
main passa`), alem de todos os casos que ja existiam. O caso antigo `manifesto
ilegivel sai 0 e diz o motivo` **muda de expectativa** para `4` — era ele que
fixava o defeito.
