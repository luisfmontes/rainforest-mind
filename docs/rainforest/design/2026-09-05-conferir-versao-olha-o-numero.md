# Issue #189 — conferir-versao olha o numero declarado e nao sai 0 sem ter medido

## Objetivo

Fazer o `scripts/conferir-versao.cjs` parar de dizer "ok" nos dois casos em que
ele nao mediu nada: manifesto ilegivel saindo `0`, e versao declarada que repete
ou anda para tras em relacao a `origin/main` saindo `0`. O que ele conta hoje —
commits desde o ultimo commit que tocou o arquivo — continua valendo; o que
falta e olhar o **numero**.

## Decisões fechadas

- **D1 — "nao deu para medir" ganha exit `4`, distinto de `0` (ok) e de `2`
  (recusa)** — porquê: e o precedente do proprio repositorio. O
  `conferir-mutacao.cjs` criou o `4` exatamente para "nao da para MEDIR" e o
  separou de aprovacao e de reprovacao. A mensagem de hoje ja e honesta ("nao
  consegui ler a versao"); e o exit code que mente, e quem chama num `&&`, num
  hook ou em CI le `0` e segue.

- **D2 — O `4` vale so quando o repositorio E um plugin e o manifesto nao pode
  ser lido. "Nao e repositorio git" e "nao e um plugin" continuam exit `0`** —
  porquê: a falha aberta desses dois ramos e proposital e esta documentada no
  cabecalho do script — a skill `fechar` roda este comando em **qualquer**
  projeto, e travar o fecho de quem trabalha fora do repositorio do plugin seria
  pior que o problema. A Issue tambem so pede exit diferente de `0` para
  "`plugin.json` vazio ou ilegivel". Sao ramos com enunciados diferentes:
  "nao ha o que conferir aqui" nao e "eu deveria conferir e nao consegui".

- **D3 — Recusar (exit `2`) quando a versao declarada for igual ou menor que a
  de `origin/main`, nomeando os dois numeros na mensagem** — porquê: e o
  enunciado real do defeito. O script nao olha o numero: conta commits desde o
  ultimo commit que tocou o arquivo e chama isso de conferir a versao. Com a
  versao revertida a mao para `1.3.0`, ou posta em `0.9.0`, ele sai `ok`. Sem
  numero maior, o `claude plugin update` nao tem versao nova para buscar — que e
  literalmente o que o script escreve na propria mensagem de recusa.

- **D4 — A comparacao e semver por componente numerico, nunca comparacao de
  string** — porquê: `"0.9.0" > "1.3.0"` e verdadeiro em ordem lexicografica, e
  o caso 3 da Issue (`0.9.0` contra uma `main` em `1.3.0`) e justamente o que
  precisa recusar. Comparar string faria o script passar verde no caso que ele
  existe para pegar.

- **D5 — Sem `origin/main` resolvivel, a comparacao de numero e pulada: o script
  segue so com a contagem de commits e diz na saida que nao comparou** — porquê:
  clone sem remoto, tarball e os repositorios de fixture da propria bateria (que
  nascem de `git init`, sem remoto) nao podem virar recusa nem virar `4`. E a
  mesma falha aberta de D2, pelo mesmo motivo, e e o que mantem os casos
  existentes da bateria verdes sem precisar mexer neles.

- **D6 — Ler o manifesto de `origin/main` com `MSYS_NO_PATHCONV=1` no ambiente e
  recusar-se a concluir com saida vazia** — porquê: no Git Bash o argumento
  `origin/main:.claude-plugin/plugin.json` e convertido em caminho Windows e o
  comando falha **em silencio**. Essa pegadinha derrubou a primeira contraprova
  do autor da Issue e fez o teste medir o nada. Saida vazia cai no ramo de D5
  (nao comparou), nunca em "as versoes sao iguais".

- **D7 — A bateria ganha caso para cada um dos tres ramos novos: manifesto
  ilegivel dando `4`, versao igual a da `main` recusando, versao menor que a da
  `main` recusando, versao maior passando** — porquê: e o criterio de pronto
  escrito na Issue. O caso existente "manifesto ilegivel sai 0 e diz o motivo"
  muda de expectativa para `4` — a bateria e que estava fixando o defeito.

## Avaliado e descartado

- **Comparar com a ultima tag em vez de `origin/main`** — a Issue oferece as
  duas. Descartado porque a tag e criada depois do merge e pode nao existir na
  hora do fecho, que e exatamente o momento em que a checagem tem de valer.
  `origin/main` esta sempre la e e a referencia que a mensagem de recusa ja cita.

- **Fazer todos os ramos "nao deu para medir" sairem `4`** — transformaria o
  `fechar` de qualquer projeto que nao seja este plugin numa parada. Contraria a
  falha aberta declarada no cabecalho do script, e vai alem do que a Issue pede.

- **Comparar versao com `localeCompare` ou `String >`** — coberto por D4; erra o
  caso `0.9.0` contra `1.3.0`, que e um dos tres reproduzidos na Issue.

## Fora de escopo

- **A #176 (`conferir-versao.cjs` media a pasta de instalacao em vez da do
  projeto)** — a Issue sugere resolver as duas na mesma passada, mas a #176 ja
  foi fechada pelo lote 4 (PR #188) e o `raizDoCwd()` que ela introduziu esta no
  arquivo. Nao ha o que fazer.

- **Bump da versao do plugin** — o script ja recusa hoje por teto (49 commits
  desde `61a9e7d`), e depois deste conserto vai recusar tambem por numero
  repetido. Subir a versao e decisao do usuario: a skill `fechar` manda parar e
  subir uma linha, nao bumpar por conta propria.

## Em aberto

- nada
