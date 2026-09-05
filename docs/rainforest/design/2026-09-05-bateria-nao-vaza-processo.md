# Issue #187 — a bateria de segunda-opiniao nao vaza processo nem diretorio temporario

## Objetivo

Fazer com que rodar `scripts/testa-segunda-opiniao.sh` ate o fim nao deixe
processo filho vivo nem diretorio temporario para tras — e que o criterio que
prova isso meça de verdade, em vez de sair verde por nao enxergar nada.

## Decisões fechadas

- **D1 — O conserto entra em `hooks/lib/cli-externo.cjs`, nao no trap do
  `testa-segunda-opiniao.sh`** — porquê: a Issue atribui o vazamento ao trap do
  script de teste, e isso foi medido e nao se sustenta. O script nao tem um
  unico `&` de fundo (os hits sao `&&` e `2>&1`), entao nao ha PID de background
  para acumular. Quem vaza e o `rodarCli`: em `cli-externo.cjs:40` ele faz
  `spawnSync('cmd.exe', ['/d','/s','/c', cmd])`, e o `timeout` do `spawnSync`
  mata o **filho direto** (o `cmd.exe`), nunca o neto que executa de verdade.
  Reproduzido em 2026-09-05 com `timeoutMs: 800`: `status` volta `null`, o
  `cmd.exe` some, e o `node` da fixture continua vivo. Isto e defeito de
  biblioteca, nao de bateria: `conselho.cjs` chama `rodarCli` em `:402`, `:792`,
  `:1199` e `:1280`, e vaza pelos quatro.

- **D2 — No timeout, `rodarCli` mata a descendencia do PID que o `spawnSync`
  devolveu, recursivamente, e so processos nascidos depois do inicio da
  chamada** — porquê: o `cmd.exe` ja esta morto quando o `spawnSync` retorna
  (medido: consulta por `ProcessId` do pai devolve `0`), entao `taskkill /T`
  sobre ele nao alcanca ninguem. O que sobrevive e o PPID **gravado** no neto:
  medido em 2026-09-05, com o pai `54356` ja morto, a consulta por
  `ParentProcessId=54356` ainda devolveu o orfao `25432`. A guarda de janela de
  criacao existe porque o Windows reusa PID — sem ela, um processo alheio que
  nascesse com o mesmo numero de pai seria morto junto, que e exatamente o que a
  regra 15 proibe. O encerramento sai como funcao **exportada** e portatil
  (`matarDescendencia`), nao inline no ramo de timeout: o design
  `docs/rainforest/design/fluxo-8-design-handover-regente.md:88` ja registrava
  "nada de sinais unix pra matar sessao — usar mecanismo portatil" como risco
  conhecido, e o regente do fluxo-8 vai subir sessao headless pela mesma maquina
  de spawn. Funcao exportada a outra frente herda pronta; ramo inline ela
  reescreve.

- **D3 — Os dois `trap ... EXIT` de `testa-segunda-opiniao.sh` viram um so, com
  a limpeza saindo de dentro do que vai apagar — e a sobra de diretorio so
  desaparece de fato depois de D2** — porquê: sao **tres** causas empilhadas, e
  as duas primeiras sozinhas nao resolvem. Medido nesta ordem, rodando a bateria
  de verdade:

  1. `bash` **substitui** o handler de `EXIT`, nao acumula. O trap da linha 607
     apagava o da linha 17, e o `rm -rf` da caixa de areia nunca rodava. 80
     diretorios `test-segunda-opiniao-*` orfaos no temporario desta maquina,
     confirmados de forma independente por outra sessao.
  2. Com o trap unificado, a bateria saiu `0`, o `FORA_REPO` foi removido — e a
     caixa de areia **sobreviveu assim mesmo**: 81 diretorios em vez de 80. A
     bateria faz `cd` para dentro de `$RAIZ` o tempo todo e termina la dentro, e
     no Windows nao se remove diretorio que e cwd de processo vivo. Por isso a
     funcao de limpeza faz `cd "$SRC"` antes de apagar.
  3. Com o `cd` tambem no lugar, sobrou **um unico** subdiretorio:
     `test-indisponivel-timeout-repo`, o do CASO 12 — exatamente onde o processo
     orfao do `externo-indisponivel-timeout.cjs` tem o cwd. Confirmado por
     `Get-CimInstance`: dois `node.exe` vivos, um por execucao da bateria.

  Ou seja, a sobra de diretorio e em boa parte **sintoma** do vazamento de
  processo: enquanto o orfao vive, o diretorio dele nao sai. D3 conserta o que e
  do arquivo de teste; o resto so fecha com D2.

- **D4 — O criterio de pronto mede pelo PID que o proprio teste criou, nunca
  por nome de processo** — porquê: duas razoes independentes. A primeira e que
  o criterio escrito na Issue (`ps -W` filtrado pelo nome da fixture) nao pode
  falhar: o `ps -W` do Git Bash imprime `PID PPID PGID WINPID TTY UID STIME
  COMMAND` e a coluna `COMMAND` traz o caminho do executavel, nunca a linha de
  comando — contei `0` antes e `0` depois com o processo comprovadamente vivo. A
  segunda e a regra 15: ha quatro sessoes do Claude e varios subagentes rodando
  `node.exe` nesta maquina, e varrer por nome mata o alheio.

- **D5 — O caso novo mora em `scripts/testa-cli-externo.cjs`, junto do codigo
  que conserta** — porquê: o defeito e do transporte, e teste de transporte na
  bateria de um chamador so cobre aquele chamador. `testa-segunda-opiniao.sh`
  ganha apenas a correcao do trap (D3), sem caso novo.

## Avaliado e descartado

- **`trap 'kill 0' EXIT`** — proposta original da Issue, medida e refutada pelo
  proprio autor em 2026-09-05: o `kill 0` sobe e mata o shell chamador junto. O
  marcador `CHAMADOR: SOBREVIVI` nunca foi gravado e a chamada de teste inteira
  voltou sem saida. Nao reproponho.

- **Acumular o PID de background numa lista e matar PID a PID no trap do bash** —
  a forma que a Issue passou a recomendar depois de refutar o `kill 0`. Nao se
  aplica a este script: nao existe um unico `&` de fundo nele, entao nao existe
  PID a acumular. E ainda que existisse, seria o PID do `node
  segunda-opiniao.cjs`, que ja morre sozinho — o que sobrevive e o neto, dois
  niveis abaixo.

- **`taskkill /F /T` sobre o PID do `cmd.exe` depois do `spawnSync` retornar** —
  o `/T` so alcanca arvore de processo vivo, e o `cmd.exe` ja esta morto nesse
  ponto (medido: contagem `0`). Mataria nada e sairia verde.

- **Trocar `spawnSync` por `spawn` assincrono para segurar o handle vivo** —
  resolveria na raiz, mas `rodarCli` e sincrono por contrato e tem cinco
  chamadores em producao que dependem disso. Refatorar os cinco e uma entrega
  maior que o defeito, e a Issue nao pede.

- **Fazer as fixtures acordarem quando o stdin fecha** — apagaria o sintoma na
  bateria sem tocar no vazamento com CLI real (`codex`, `gemini`) travado, que e
  o caso de producao. Alem disso o sono longo e proposital: e o que detecta a
  mutacao do timeout de 300s para 30s.

## Fora de escopo

- **Apagar os 80 diretorios temporarios que ja existem** — sao residuo de
  execucoes passadas, de varias sessoes. O conserto impede os proximos; varrer os
  atuais e decisao do usuario, e sai como recomendacao no PR.

- **Bump da versao do plugin** — o `conferir-versao.cjs` ja recusa hoje (49
  commits desde `61a9e7d`), e a skill `fechar` e explicita: release e decisao do
  usuario, nao se sobe versao por conta propria.

- **Os outros chamadores de `rodarCli` (`conselho.cjs`)** — o conserto em D1/D2
  os beneficia sem que nenhuma linha deles mude. Nao ha trabalho a fazer ali.

## Em aberto

- nada
