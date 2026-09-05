# Plano: Issue #187 — a bateria de segunda-opiniao nao vaza processo nem diretorio temporario

Design: docs/rainforest/design/2026-09-05-bateria-nao-vaza-processo.md

## O que não pode quebrar

- `rodarCli` continua **sincrono** e continua devolvendo `{ status, stdout, stderr }`
  — cinco chamadores em producao dependem disso (`segunda-opiniao.cjs:217`,
  `conselho.cjs:402`, `:792`, `:1199`, `:1280`).
- O caminho feliz (CLI que responde antes do timeout) nao paga nenhuma consulta
  de processo: o encerramento so roda no ramo de timeout.
- Nenhum processo e morto por **nome**. So por PID descendente do PID que esta
  chamada criou, e so se nascido depois do inicio da chamada (regra 15).
- `scripts/testa-segunda-opiniao.sh` continua saindo 0, com os mesmos casos.
- `bash scripts/testa-cli-externo.sh` continua saindo 0.

## Tarefas

### 1. `matarDescendencia` portatil, e o ramo de timeout do `rodarCli` passa a chamar [tipo: implementar]
atende: D1, D2
arquivos: `hooks/lib/cli-externo.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/cli-externo.cjs`
  de: a chamada a `matarDescendencia` dentro do ramo de timeout do `rodarCli`
  para: a chamada removida (o ramo volta a so devolver o resultado)
  bateria: `node scripts/testa-cli-externo.cjs`
  fixture: `testa-cli-externo.cjs, caso "timeout nao deixa descendente vivo"`
pronto quando: com o transporte real — `rodarCli` chamando `cmd.exe` com a
fixture `scripts/fixtures/segunda-opiniao/externo-indisponivel-timeout.cjs` e
`timeoutMs` de 800ms — nenhum descendente do PID que o `spawnSync` devolveu
continua vivo 2s depois, provado por `node scripts/testa-cli-externo.cjs`
devolvendo exit `0` e imprimindo a linha `ok   timeout nao deixa descendente
vivo`. Hoje esse mesmo caso reprova nomeando o PID sobrevivente.

### 2. Caso de bateria que prova o encerramento, medindo por PID e nao por nome [tipo: teste]
atende: D4, D5
arquivos: `scripts/testa-cli-externo.cjs`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: esta tarefa **e** o instrumento de falsificacao da tarefa 1 — a
  inversao que importa esta declarada la, e inverter o proprio teste so provaria
  que ele roda. Nao ha comportamento de producao nesta tarefa para inverter.
pronto quando: o caso registra o PID que ele proprio criou (o devolvido pelo
`spawnSync`), consulta a descendencia por `ParentProcessId` desse PID e falha
nomeando o PID sobrevivente — nunca filtra por nome de executavel nem por
string do comando. Provado por `grep -c "ps -W" scripts/testa-cli-externo.cjs`
devolvendo `0` e por `node scripts/testa-cli-externo.cjs` devolvendo exit `0`.

### 4. Guarda de reuso do PID RAIZ, e o caso que a prova [tipo: implementar]
atende: D6
arquivos: `hooks/lib/cli-externo.cjs`, `scripts/testa-cli-externo.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/cli-externo.cjs`
  de: `if (!raizConfiavel(porPid.get(pidRaiz), 'cmd.exe')) {`
  para: `if (false) {`
  bateria: `node scripts/testa-cli-externo.cjs`
  fixture: `testa-cli-externo.cjs, Teste 11 "PID raiz reusado nao mata descendencia alheia"`
pronto quando: com o PID deste proprio processo `node` passado como raiz (que
nao e `cmd.exe`, e portanto encena o PID reciclado por outro dono), um filho
legitimo dele criado depois do marco **sobrevive** a chamada de
`matarDescendencia` — provado por `node scripts/testa-cli-externo.cjs`
devolvendo exit `0` com 11 casos e a linha `ok   raiz que nao e a minha aborta
em vez de matar`. Com a guarda invertida, o mesmo comando devolve exit `1`
nomeando o processo alheio morto.

Esta tarefa nasceu do estagio `revisar`, nao do plano original: dois agentes
independentes (revisor e auditor de seguranca) acharam a mesma lacuna, e a
mutacao acima confirmou que era defeito, nao teoria.

### 3. Os dois `trap ... EXIT` de `testa-segunda-opiniao.sh` viram um so [tipo: implementar]
atende: D3
arquivos: `scripts/testa-segunda-opiniao.sh`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: o defeito e do proprio arquivo de teste, e nao existe bateria-da-bateria
  para ficar vermelha quando ele for invertido. A inversao ja foi medida no
  estado anterior — 80 diretorios orfaos acumulados — e a falsificacao desta
  tarefa e o criterio de pronto abaixo, que roda a bateria de verdade e confere o
  diretorio no disco.
pronto quando: rodando `bash scripts/testa-segunda-opiniao.sh` ate o fim **com a
tarefa 1 ja integrada**, o diretorio de caixa de areia que ela imprime na
primeira linha (`(caixa de areia: <caminho>)`) **nao existe mais** ao final —
provado por `test -d <caminho>` devolvendo exit `1`, com a bateria ainda saindo
`0`. Hoje o diretorio sobrevive.

**A dependencia da tarefa 1 foi medida, nao suposta.** Com o trap unificado e o
`cd` de saida, mas sem o encerramento de descendencia, a bateria saiu `0` e
sobrou exatamente um subdiretorio: `test-indisponivel-timeout-repo`, o do CASO
12 — o cwd do processo orfao. Windows nao apaga diretorio que e cwd de processo
vivo, entao esta tarefa nao pode ser validada antes da 1 estar no lugar. O plano
saiu com `depende de: nenhuma` e foi corrigido aqui.
