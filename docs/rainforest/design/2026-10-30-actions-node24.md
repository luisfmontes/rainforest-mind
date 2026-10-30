# Actions dos workflows em Node 24

## Objetivo
O primeiro run do `release.yml`, em 2026-10-30, terminou com o aviso `Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/checkout@v4, actions/setup-node@v4`. O `baterias.yml` usa as mesmas duas actions, mais `actions/setup-python@v5`, que também é Node 20. Hoje o runner força Node 24 e tudo passa. O aviso aparece em todo run, e o dia em que o GitHub deixar de forçar vira run vermelho sem mudança nossa. Este trabalho sobe as três actions para majors que já declaram Node 24.

Conduzido pela sessão em 2026-10-30, sob a autorização permanente de seguir o fluxo com a recomendada.

## Decisões fechadas
- **D1 — `actions/checkout@v7`, `actions/setup-node@v7`, `actions/setup-python@v7` nos dois workflows, mantendo a convenção de tag de major (`@vN`).** Porquê: são os majors atuais (checkout v7.0.1, setup-node v7.1.0, conferidos com `gh api repos/actions/<nome>/releases/latest` em 2026-10-30). Ficar no primeiro major Node 24 (v5/v6) deixaria outro aviso de major velho pela frente. As quebras de cada major entre o atual e o v7, conferidas nas notas de release, não tocam este repositório:
  - **checkout v6:** a credencial persistida sai do `.git/config` para um arquivo à parte. Nenhum script ou hook lê credencial do checkout: `grep -rn "extraheader\|persist-credentials\|includeIf" scripts hooks` sai vazio.
  - **checkout v7:** bloqueia checkout de PR de fork sob `pull_request_target` e `workflow_run`. Os gatilhos aqui são `pull_request`, `push` e `workflow_dispatch`.
  - **setup-node v5 e v6:** cache automático quando o `package.json` declara `packageManager`. O repositório não tem `package.json`, então nada liga.
  - **setup-python v7:** removeu a entrada `pip-install`. O `baterias.yml` passa só `python-version`.
- **D2 — Versão 2.3.1 (PATCH), com entrada no CHANGELOG.** Porquê: o lote só conserta um aviso de depreciação, e a tabela do `CONTRIBUTING.md` chama isso de PATCH. O bump também é o que faz o `release.yml` rodar no merge (ele só dispara em push que toca `.claude-plugin/plugin.json`). Sem bump, as actions novas do `release.yml` ficariam sem nenhum run real neste fluxo.
- **D3 — A prova é o run real, não o arquivo.** YAML de workflow não roda localmente. O `baterias.yml` do próprio PR prova as três actions no Windows, e o `release.yml` do merge prova checkout e setup-node no Ubuntu. Nos dois, o log não tem a linha `Node.js 20 is deprecated` e o run sai verde. O id do run se re-deriva de `gh run list`, nunca de um relato.

## Avaliado e descartado
- **Fixar as actions por SHA de commit.** É endurecimento de cadeia de suprimento, uma decisão à parte, e mudaria a convenção dos dois workflows. Fica fora deste conserto.
- **Só subir até o primeiro major Node 24 (checkout v5, setup-node v5, setup-python v6).** Evita as quebras do v6 e do v7, mas nenhuma delas toca este repositório (D1), e deixaria o repositório dois majors atrás.

## Fora de escopo
- O comentário do topo do `baterias.yml` ainda chama o repositório de privado. É texto, não comportamento, e não muda aqui.

## Varredura
docs/rainforest/varredura/2026-10-30-actions-node24.txt — nenhuma Issue, PR, branch ou ideia sobre a versão das actions. O PR #317 fixou as baterias no Node 24, mas isso é o Node que roda os scripts (`node-version` da matriz), não o runtime das actions. O commit `e678c417` explica o `fetch-depth: 0` do checkout, que fica.

## Em aberto
nada
