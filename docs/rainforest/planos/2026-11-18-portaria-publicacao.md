# Plano: Portaria e publicação — trilho protheus na pasta do cliente e nome da org no endpoint

Design: docs/rainforest/design/2026-11-18-portaria-publicacao.md

## O que não pode quebrar

- Todo caso que hoje sai exit 2 em `hooks/testa-portaria-fluxo-pulado.cjs`, `hooks/testa-aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs` e `hooks/testa-gate-publicacao-destino.sh` continua exit 2. Nenhum caso existente é apagado nem tem o exit esperado trocado.
- `protheusAberto` continua com a mesma assinatura (`{ gitTop, branch, agora }`) e devolvendo booleano: `hooks/lib/aviso-fluxo-comum.cjs:122` também o chama, e ganha as pastas de cliente e o diff junto, sem mudar de contrato.
- Trilho rainforest sem `.gates.json` aberto decide como hoje: o estágio aberto do estado do rainforest.
- `gh api` continua conferindo campo (`-f/-F/--raw-field/--field`), corpo de `--input`/`@arquivo`, corpo embutido e o resto do caminho do endpoint.

## Tarefas

A tarefa 2 depende da 1 (mesma função). A 3 depende da 2 porque a bateria da 3 usa o `protheusAberto` final. A 4 é independente das três. A 5 fecha a versão.

### 1. `protheusAberto` lê `<raiz>/<pasta>/docs/plans` [tipo: implementar]
atende: D1
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | estendo protheusAberto de hooks/lib/caminho-leve.cjs:114 e reaproveito gateAbreFluxo de hooks/lib/caminho-leve.cjs:107; nenhuma lib lista pastas de primeiro nível
desfecho: estender
O que fazer:
- Função nova `pastasDePlans(gitTop)` em `caminho-leve.cjs` que devolve a lista de diretórios `<gitTop>/<pasta>/docs/plans` para cada entrada de primeiro nível de `gitTop` que é diretório e não começa com `.`. Erro de leitura devolve lista vazia.
- `protheusAberto` percorre `[path.join(gitTop, 'docs', 'plans'), ...pastasDePlans(gitTop)]`, com a mesma leitura por arquivo de hoje (ilegível é pulado).
- Bateria: seção nova "O. multi-cliente (portaria-publicacao D1)" em `hooks/testa-portaria-fluxo-pulado.cjs`. A raiz tem `docs/plans/velho.gates.json` com mtime de 2 dias (trilho protheus detectado, fechado) e o caso varia a pasta do cliente.
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `const dirs = [path.join(gitTop, 'docs', 'plans'), ...pastasDePlans(gitTop)];`
  para: `const dirs = [path.join(gitTop, 'docs', 'plans')];`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", caso O1
prova-na-base: verde — o critério precisa do repositório de fixture (raiz com `.gates.json` velho e pasta de cliente) que só a bateria monta
pronto quando: com o payload `PreToolUse` de `Agent` que o harness manda (`subagent_type: rainforest-mind:executor`, `isolation: "worktree"`), provado por `node hooks/testa-portaria-fluxo-pulado.cjs` imprimindo `ok` em cada caso abaixo e a linha final `ok: N   falhou: 0   skipped: 0`:
  - O1: `Cliente/docs/plans/x.gates.json` recente, sem `branch` → exit 0.
  - O2: o mesmo arquivo com mtime de 2 dias → exit 2.
  - O3: recente com `"branch": "outra-branch"` → exit 2.
  - O4: `.oculta/docs/plans/x.gates.json` recente (pasta com ponto) → exit 2.

### 2. Diff da branch abre o `.gates.json` sem `branch` [tipo: implementar]
atende: D1
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 1
busca:
- catalogo | listar --raiz hooks/lib | estendo protheusAberto de hooks/lib/caminho-leve.cjs:114; o merge-base com a padrão já existe em baseDoDiff de hooks/lib/achados-revisor.cjs:160, mas devolve só a base e roda no cwd; aqui roda em gitTop e precisa da lista de arquivos
desfecho: estender
O que fazer:
- Função nova `arquivosDaBranch(gitTop)` em `caminho-leve.cjs`: resolve a padrão por `git symbolic-ref --short refs/remotes/origin/HEAD`, e sem ela tenta `origin/main` e `origin/master` por `git rev-parse --verify --quiet`; calcula `git merge-base HEAD <padrão>`; devolve o `Set` dos caminhos de `git -c core.quotepath=false diff --name-only -z <merge-base>` (barras `/`, minúsculas). Qualquer passo que falha devolve `null`. Calculada uma vez por chamada de `protheusAberto`, só quando algum `.gates.json` não abriu pelas formas de hoje.
- Um `.gates.json` SEM campo `branch` abre quando o `Set` contém: o caminho dele relativo a `gitTop`; ou o `plan.file`, o `design.doc` (ou `plan`/`design` quando são string), cada um lido de dois jeitos, relativo a `gitTop` e relativo à pasta que contém o `docs/plans` dele. Com campo `branch`, só a igualdade decide, como hoje.
- A linha da decisão é literal: `if (typeof dados.branch !== 'string' && tocadoPelaBranch(arq, dados, gitTop, baseDir, lerDiff)) return true;`.
- Bateria: casos O5 a O8 na seção "O". A fixture grava `refs/remotes/origin/main` e `refs/remotes/origin/HEAD` apontando para o commit da `main`, cria a branch `refactor/cliente-x`, e põe o `.gates.json` do cliente com mtime de 2 dias DEPOIS do commit.
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `if (typeof dados.branch !== 'string' && tocadoPelaBranch(arq, dados, gitTop, baseDir, lerDiff)) return true;`
  para: `if (false) return true;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", casos O5 e O6
prova-na-base: verde — o critério precisa de branch com remoto e merge-base que só a fixture da bateria monta
pronto quando: com o mesmo payload da tarefa 1, provado por `node hooks/testa-portaria-fluxo-pulado.cjs` imprimindo `ok` em cada caso e `falhou: 0`:
  - O5: `.gates.json` do cliente com 2 dias, sem `branch`, commitado na branch → exit 0.
  - O6: `.gates.json` commitado na `main` (base), com 2 dias, e a branch só altera o `plan.file` declarado (`docs/plans/x-plan.md`, relativo à pasta do cliente) → exit 0.
  - O7: como O6, mas a branch altera outro arquivo → exit 2.
  - O8: como O5, mas sem `refs/remotes/origin/*` → exit 2 (falha ao calcular o diff não libera).

### 3. Portaria: trilho protheus aberto vale com o trilho rainforest presente, e a recusa diz onde procurou [tipo: implementar]
atende: D1
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 2
busca:
- catalogo | listar --raiz hooks | estendo o main de hooks/portaria.cjs:683 (estagioPermitido e a mensagem de negarFluxoPulado moram nele); detectarTrilhoFluxo de hooks/portaria.cjs:254 fica como está
desfecho: estender
O que fazer:
- Antes de `estagioPermitido`: `const protheusLibera = (trilho === "protheus" || escreveDeclarado || escrevePorSinal) && protheusAberto({ gitTop: raiz, branch: obterBranch(raiz) });`. No ramo `trilho === "protheus"`, `estagioPermitido` é `protheusLibera`, como hoje. No outro ramo, a expressão de hoje vira `protheusLibera || (<expressão de hoje>)`, com a linha literal `: protheusLibera || (escrevePorSinal`.
- `negarFluxoPulado` acrescenta à mensagem, antes da `saida 1`, a linha `\n  trilho protheus: .gates.json procurado em '<raiz>/docs/plans' e '<raiz>/*/docs/plans'` (com `raizBarras`).
- Bateria: casos O9 a O11 na seção "O", com `docs/rainforest/estado/` na raiz.
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `: protheusLibera || (escrevePorSinal`
  para: `: (escrevePorSinal`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", caso O9
prova-na-base: verde — o critério precisa da raiz com os dois trilhos que só a fixture da bateria monta
pronto quando: com o payload de `Agent` da tarefa 1 e a raiz com `docs/rainforest/estado/` (o layout medido no repositório multi-cliente), provado por `node hooks/testa-portaria-fluxo-pulado.cjs` com `ok` em cada caso e `falhou: 0`:
  - O9: sem fluxo rainforest aberto e com `Cliente/docs/plans/x.gates.json` recente sem `branch` → exit 0.
  - O10: o mesmo com o `.gates.json` de 2 dias → exit 2, e o stderr contém `/*/docs/plans`.
  - O11: sem `.gates.json` nenhum → exit 2 (a decisão do trilho rainforest continua igual).

### 4. `gh api`: conta e repositório de destino no endpoint não são conferidos contra a lista privada [tipo: implementar]
atende: D2, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | estendo textosDoGhApi de hooks/gate-publicacao-destino.cjs:821; corposEmbutidos de hooks/gate-publicacao-destino.cjs:978 continua lendo o comando original
desfecho: estender
O que fazer:
- Função nova `neutralizarDestinoNoEndpoint(cmd)`: troca, no texto inteiro, o segmento depois de `orgs/` e de `users/` (regex `/(\b(?:orgs|users)\/)[^\/\s?#'"]+/gi`) e os dois segmentos depois de `repos/` (regex `/(\brepos\/)[^\/\s?#'"]+\/[^\/\s?#'"]+/gi`) por `<destino>`. Os valores de campo, os corpos de `--input`/`@arquivo` e os corpos embutidos continuam entrando em `textos` pelos caminhos de hoje, lidos do original.
- Em `textosDoGhApi`, a entrada do comando passa a ser `{ origem: "comando", texto: neutralizarDestinoNoEndpoint(cmdOriginal) }`.
- Só `textosDoGhApi` muda (D3).
- Bateria: seção nova "(#726) gh api: destino no endpoint" em `hooks/testa-gate-publicacao-destino.sh`, com o `termo702` da caixa de areia.
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `{ origem: "comando", texto: neutralizarDestinoNoEndpoint(cmdOriginal) }`
  para: `{ origem: "comando", texto: cmdOriginal }`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: testa-gate-publicacao-destino.sh, seção "(#726) gh api: destino no endpoint", caso "726 orgs/<termo>/teams passa"
prova-na-base: verde — o critério precisa da lista privada sintética e do `gh` falso que a caixa de areia da bateria monta
pronto quando: com o comando medido na #726 (`gh api orgs/<org>/teams -X POST -f name=x -f privacy=closed`) e o termo sintético `termo702` no lugar da org, provado por `bash hooks/testa-gate-publicacao-destino.sh` com `ok` em cada caso abaixo e `== resultado: N ok, 0 falha(s) ==`:
  - legítimos que passam: `gh api orgs/termo702/teams -X POST -f name=x -f privacy=closed` → exit 0; `gh api users/termo702/x -X POST -f a=b` → exit 0; `gh api repos/termo702/x/issues -X POST -f title=ok` com o repositório público → exit 0.
  - continuam barrando: `gh api orgs/termo702/teams -X POST -f description=termo702` → exit 2; `gh api -X PUT repos/dono/x/contents/termo702.md -f message=ok -f content=eA==` com o repositório público → exit 2; `gh api 'orgs/x/teams?q=termo702' -X POST -f name=y` → exit 2.
  - todos os casos `707` da bateria continuam com o exit de antes.

### 5. Versão 2.17.1, CHANGELOG e README [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 3, 4
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
pronto quando: com os dois manifestos do plugin, `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(f, require('./'+f).version)"` imprime `2.17.1` nas duas linhas, o selo de versão do README diz `2.17.1`, e a entrada `2.17.1` do `CHANGELOG.md` cita as Issues #726, #728 e #729 com o que mudou nos dois gates, coerente com D1 e D2 do design (pasta do cliente, diff da branch, trilho rainforest presente, segmento de conta e repositório no endpoint).
