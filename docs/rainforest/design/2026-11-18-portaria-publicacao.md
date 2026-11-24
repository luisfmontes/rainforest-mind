# Portaria e publicação: trilho protheus na pasta do cliente e nome da org no endpoint

## Objetivo

Tirar dois bloqueios falsos que apareceram no trabalho do dia a dia (Issues #728, #729 e #726) sem abrir o que cada gate protege.

1. **Portaria (#728, #729).** Ela barra o `protheus-implementer` em repositório multi-cliente com o trilho do protheus aberto. O `.gates.json` do trabalho fica em `<cliente>/docs/plans/`, e `protheusAberto` só lê `<raiz>/docs/plans/`. Antes disso, `detectarTrilhoFluxo` vê `<raiz>/docs/rainforest/estado/` e classifica o trilho como `rainforest`, de modo que `protheusAberto` nem chega a ser chamado (#729, aberta por outra sessão no mesmo dia).
2. **Gate de publicação (#726).** Ele barra `gh api orgs/<org>/teams -X POST ...` quando o nome da org está na lista privada. O nome aparece só no caminho do endpoint e identifica a conta de destino, sem publicar nada.

Pedido do Luís em 2026-11-18 ("olha uma issue que abriu ontem... bloqueou chamar um agente do plugin protheus... e tbm teve um bloqueio de escrita do nome [da org]"), com a recomendada aceita ("sim pode seguir no automatico"). A rodada roda sob `executar-autonomo`; as decisões abaixo foram tomadas pela sessão dentro dessa delegação.

## Decisões fechadas

- **D1 — A portaria reconhece o trilho protheus aberto na pasta do cliente, também com o trilho rainforest presente** — quatro partes:
  1. `protheusAberto` lê `<raiz>/docs/plans/*.gates.json`, como hoje, e `<raiz>/<pasta>/docs/plans/*.gates.json` para cada pasta de primeiro nível da raiz que não começa com `.`.
  2. Um `.gates.json` abre o trilho, além das duas formas de hoje (`branch` igual à branch atual; sem `branch`, modificado há menos de um dia), quando o diff da branch contra a base toca o próprio `.gates.json` ou o caminho do `plan` ou do `design` que ele declara. A base é o merge-base com a branch padrão do remoto.
  3. Para agente que escreve, um trilho protheus aberto para a branch libera o despacho mesmo quando `detectarTrilhoFluxo` devolve `rainforest`. Nesse caso, o `.gates.json` só conta aberto com vínculo com a branch: o campo `branch` igual à branch atual ou o diff commitado da branch (parte 2). A regra de "modificado há menos de um dia" não vale aqui. Sem trilho protheus aberto, a decisão do trilho rainforest continua igual.
     - **Emenda de 2026-11-18 (revisão de segurança, Q1 aceita pelo Luís: "recomednado"):** `git worktree add` grava todo arquivo com mtime de agora, então num worktree novo do repositório multi-cliente todo `.gates.json` de cliente parecia recente por 24 h e liberaria qualquer escritor por cima do trilho rainforest. O caso medido segue coberto: o `.gates.json` dele está commitado na branch. Pela mesma revisão, o diff da parte 2 conta só o commitado (`base..HEAD`).
  4. A mensagem de recusa diz onde procurou o `.gates.json` (`<raiz>/docs/plans` e `<raiz>/*/docs/plans`).
  - **Porquê:** medido em 2026-11-18 no worktree do repositório multi-cliente. O `.gates.json` do trabalho em curso estava na pasta do cliente, modificado 13 h antes. A raiz tem `docs/rainforest/estado/` e uma pasta `docs/plans` por cliente. A parte 2 existe porque um trabalho que passa mais de um dia sem tocar o `.gates.json` voltaria a ser barrado no meio; e o diff da branch é a evidência de que o plano é dela. O contorno usado na #729 (`estado.cjs leve` numa branch `fluxo/...`) liberou uma feature de 14 tarefas pelo caminho feito para hotfix.
  - **Modelo de ameaça:** protege contra agente que escreve despachado fora de trilho aberto. Fica fora: um `.gates.json` de outro cliente, no mesmo repositório, recente e sem `branch`, também libera; a janela de um dia sem `branch` já tinha esse alcance dentro de `<raiz>/docs/plans`. Pastas que começam com `.` (`.claude/worktrees`, `.git`) ficam fora, para um worktree aninhado não abrir o trilho do principal. Falha ao calcular o diff (sem remoto, sem merge-base) não libera pela parte 2: valem só as duas formas de hoje.

- **D2 — No `gh api`, o identificador da conta ou do repositório de destino no endpoint não é conferido contra a lista privada** — no texto do comando que o gate confere, o segmento depois de `orgs/` e de `users/`, e os dois segmentos depois de `repos/`, viram um marcador neutro antes da conferência, só no início do caminho do endpoint (depois de `/`, `https://api.github.com/` ou `https://<host>/api/v3/` opcionais) e só no token do endpoint, não no comando inteiro. O resto do caminho continua conferido, como hoje, e também a query string, os valores de campo (`-f/-F/--raw-field/--field`), os corpos de `--input`/`@arquivo` e os corpos embutidos.
  - **Emenda de 2026-11-18 (revisão 1; Q1 aceita pelo Luís: "recomendado"):** a primeira versão trocava em qualquer ponto do comando. Isso apagava o termo de corpo por pipe e `<<<`, e também de `contents/docs/users/<x>.md`, que é nome de arquivo publicado. A âncora no início do token do endpoint fecha os dois.
  - **Porquê:** o caso medido (`gh api orgs/<org>/teams -X POST -f name=x -f privacy=closed`) barrou só pelo nome da org no caminho. Esse nome identifica uma conta que já existe e não é texto publicado.
  - **Por que não tirar o caminho inteiro, como a Issue propunha:** parte do caminho vira conteúdo público. `PUT repos/<dono>/<repo>/contents/<arquivo>` cria um arquivo com aquele nome, e um termo privado no nome do arquivo vaza num repositório público.
  - **Modelo de ameaça:** protege contra texto da lista privada publicado por `gh api` de escrita em destino público ou desconhecido. Fica fora: um termo que só aparece como nome de org, usuário ou repositório já existente. Esse nome está na URL, mas não é publicado pela chamada. Criar repositório (`POST orgs/<org>/repos -f name=...`) leva o nome num campo, e o campo continua conferido.

- **D3 — Só a família `gh api` muda no gate de publicação** — `gh issue`, `gh pr`, `gh release`, `gh gist` e o `git push` continuam conferidos como hoje.
  - **Porquê:** a Issue #726 mediu só o `gh api`. Nas outras famílias o destino vem de `--repo` e da URL, e o texto conferido é o corpo e o título, não o comando inteiro, o que foi conferido na leitura de `textosDoGhApi` e dos vizinhos em `hooks/gate-publicacao-destino.cjs`.

- **D4 — Versão 2.17.1 (PATCH)** — são dois consertos de bloqueio falso, sem contrato novo (`CONTRIBUTING.md`).

## Avaliado e descartado

- **Ler o `.gates.json` em qualquer profundidade (`**/docs/plans`)** — custo de varredura a cada despacho, e um worktree aninhado ou uma cópia de outro trabalho abriria o trilho. Um nível cobre o layout medido.
- **Casar o `slug` do `.gates.json` com o nome da branch (proposta da #729)** — no caso medido, o slug (`<data>-<area>-<demanda>`) e a branch (`refactor/<cliente>-<demanda>`) não casam por texto. O diff da branch (D1, parte 2) prova o vínculo sem depender de convenção de nome.
- **Tratar `orgs/<org>/...` como destino privado (proposta 2 da #726)** — um time `closed` e um convite não são públicos, mas um `secret` ou um campo `description` num endpoint de org teria de ser classificado por endpoint. Com a D2, o caso medido passa e o campo continua conferido como destino desconhecido, que é a falha fechada.
- **Desligar o gate de publicação no projeto, como no contorno de 2026-11-17** — é a saída de emergência, não o conserto.

## Fora de escopo

- Os bloqueios de 2026-11-16 no repositório de inovação: lá o `docs/plans` está na raiz. Pela observação `obs-2026-11-17-repo-protheus-usa-trilho-protheus-nao-estado-rainforest`, a sessão tinha usado o estado do rainforest em vez do trilho do protheus. A causa é outra.
- O despacho de 2026-11-17 em que o classificador do modo automático não deu veredito porque um hook mudou a entrada do `Agent`. É um mecanismo diferente e não está medido.

## Varredura

`docs/rainforest/varredura/2026-11-18-portaria-publicacao.txt` (termos `protheusAberto`, `gates.json`, `textosDoGhApi`, `termos-proibidos`). `hooks/lib/caminho-leve.cjs` (`protheusAberto`, `gateAbreFluxo`), `hooks/portaria.cjs:254-265` (`detectarTrilhoFluxo`, que devolve `rainforest` quando existe `<raiz>/docs/rainforest/estado`) e `hooks/portaria.cjs:1018-1023`, onde o trilho `protheus` decide `estagioPermitido`. `hooks/gate-publicacao-destino.cjs`: `textosDoGhApi` (linhas 821-918) monta `textos` com o comando inteiro (`{ origem: "comando", texto: cmdOriginal }`) mais os campos e corpos, e só resolve destino para `repos/<dono>/<repo>` e `gists`.

## Em aberto

(nada)
