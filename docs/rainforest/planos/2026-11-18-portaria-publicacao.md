# Plano: Portaria e publicação — trilho protheus na pasta do cliente e nome da org no endpoint

Design: docs/rainforest/design/2026-11-18-portaria-publicacao.md

## O que não pode quebrar

- Todo caso que hoje sai exit 2 em `hooks/testa-portaria-fluxo-pulado.cjs`, `hooks/testa-aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs` e `hooks/testa-gate-publicacao-destino.sh` continua exit 2. Nenhum caso existente é apagado nem tem o exit esperado trocado.
- `protheusAberto` continua com a mesma assinatura (`{ gitTop, branch, agora }`) e devolvendo booleano: `hooks/lib/aviso-fluxo-comum.cjs:122` também o chama, e ganha as pastas de cliente e o diff junto, sem mudar de contrato.
- Trilho rainforest sem `.gates.json` aberto decide como hoje: o estágio aberto do estado do rainforest.
- `gh api` continua conferindo campo (`-f/-F/--raw-field/--field`), corpo de `--input`/`@arquivo`, corpo embutido e o resto do caminho do endpoint.

## Decisão do plano

- **O diff da branch (D1, parte 2) só vale para `.gates.json` sem campo `branch`.** O campo `branch` é o vínculo explícito do arquivo com uma branch (D10 do fluxo-pulado). Quando ele existe, só a igualdade decide, como hoje. É um refinamento de "além das duas formas de hoje" do design, registrado aqui e por `estado.cjs decidir`.

## Bateria da portaria: seção "O"

As tarefas 1 a 3 acrescentam casos a uma seção nova de `hooks/testa-portaria-fluxo-pulado.cjs`. Ela entra logo antes do `console.log("");` final do arquivo, com o cabeçalho `console.log("== O. multi-cliente (portaria-publicacao D1) ==");`. Cada caso é um bloco `{ ... }` próprio, com `const repo = novoRepo();` no começo e `descartar(repo);` no fim, e despacha com `despachar(repo, repo.main, "rainforest-mind:executor")` (o `cwd` é o checkout `repo.main`). O resultado se afirma com `caso("<id> <descrição>", r.status === <exit>, \`exit=${r.status} stderr=${r.stderr}\`)`. O conteúdo de `.gates.json` sem forma dita no caso é `{}\n`. "2 dias" é `fs.utimesSync(arq, t, t)` com `t = (Date.now() - 2 * 24 * 3600 * 1000) / 1000`.

## Tarefas

A tarefa 2 depende da 1 (mesma função). A 3 depende da 2 porque a bateria da 3 usa o `protheusAberto` final. A 4 é independente das três. A 5 fecha a versão.

### 1. `protheusAberto` lê `<raiz>/<pasta>/docs/plans` [tipo: implementar]
atende: D1
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | estendo protheusAberto de hooks/lib/caminho-leve.cjs:182 e reaproveito gateAbreFluxo de hooks/lib/caminho-leve.cjs:107; nenhuma lib lista pastas de primeiro nível
desfecho: estender
O que fazer:
- Função nova `function pastasDePlans(gitTop)` em `caminho-leve.cjs`: `fs.readdirSync(gitTop, { withFileTypes: true })` dentro de `try` (erro devolve `[]`), filtra `e.isDirectory() && !e.name.startsWith('.')` (symlink para pasta fica fora, porque `isDirectory()` é falso para ele) e devolve `path.join(gitTop, e.name, 'docs', 'plans')` de cada uma.
- Em `protheusAberto`, a primeira linha passa a ser, literal: `const dirs = [path.join(gitTop, 'docs', 'plans'), ...pastasDePlans(gitTop)];`. O laço de hoje vira um laço sobre `dirs`: `readdirSync` de cada `dirPlans` em `try`, e erro faz `continue` para o próximo (NÃO `return false`: a raiz pode não ter `docs/plans`). Dentro, a leitura por arquivo é a de hoje. O `return false` fica só depois do laço externo.
- Bateria, casos O1 a O5 (a raiz tem `docs/plans/velho.gates.json` com 2 dias em O1 a O4, para o trilho ser `protheus` e fechado):
  - O1: `Cliente/docs/plans/x.gates.json` recente → exit 0.
  - O2: o mesmo com 2 dias → exit 2.
  - O3: recente com conteúdo `{"branch":"outra-branch"}` → exit 2.
  - O4: `.oculta/docs/plans/x.gates.json` recente → exit 2.
  - O5: raiz com `docs/rainforest/estado/` (vazio) e SEM `docs/plans`, `Cliente/docs/plans/x.gates.json` recente → exit 0. Este caso só fica verde depois da tarefa 3; a tarefa 1 o escreve, e até a tarefa 3 ele é o único vermelho esperado.
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `const dirs = [path.join(gitTop, 'docs', 'plans'), ...pastasDePlans(gitTop)];`
  para: `const dirs = [path.join(gitTop, 'docs', 'plans')];`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", caso O1
prova-na-base: verde — o critério precisa do repositório de fixture (raiz com `.gates.json` velho e pasta de cliente) que só a bateria monta
pronto quando: com o payload `PreToolUse` de `Agent` que o harness manda (`subagent_type: rainforest-mind:executor`, `isolation: "worktree"`), provado por `node hooks/testa-portaria-fluxo-pulado.cjs` imprimindo `ok` em O1 a O4 (O5 depois da tarefa 3), e por `node hooks/testa-aviso-fluxo.cjs` e `node hooks/testa-bloqueio-fluxo.cjs` terminando com zero falhas no placar.

### 2. Diff da branch abre o `.gates.json` sem `branch` [tipo: implementar]
atende: D1
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 1
busca:
- catalogo | listar --raiz hooks/lib | estendo protheusAberto de hooks/lib/caminho-leve.cjs:182; o merge-base com a padrão já existe em baseDoDiff de hooks/lib/achados-revisor.cjs:160, mas devolve só a base e roda no cwd; aqui roda em gitTop e precisa da lista de arquivos
desfecho: estender
O que fazer:
- `function arquivosDaBranch(gitTop)`: roda git por `spawnSync(caminhoExecutavel('git'), ['-C', gitTop, ...args], { encoding: 'utf8', stdio: 'pipe' })`. Padrão: `symbolic-ref --short refs/remotes/origin/HEAD` (stdout aparado, ex.: `origin/main`); sem ela, a primeira de `origin/main` e `origin/master` em que `rev-parse --verify --quiet refs/remotes/<nome>` sai 0. Base: `merge-base HEAD <padrão>`. Lista: `-c core.quotepath=false diff --name-only -z <base> HEAD` (só o commitado na branch; emenda da revisão de segurança de 2026-11-18: mudança não commitada não prova a branch, caso O12). Devolve `new Set(<caminhos separados por \0, sem vazios, em minúsculas>)`. Qualquer passo com exit ≠ 0, ou padrão não achada, devolve `null`.
- `function tocadoPelaBranch(arq, dados, gitTop, baseDir, lerDiff)` → booleano. `baseDir` é a pasta que contém o `docs/plans` do arquivo (`path.dirname(path.dirname(dirPlans))`). Candidatos: o caminho do próprio `arq`; e, para cada valor texto não vazio entre `dados.plan.file`, `dados.design.doc`, `dados.plan` e `dados.design` (os dois últimos só quando são string; objeto sem o campo, número ou `null` é ignorado), `path.resolve(gitTop, v)` e `path.resolve(baseDir, v)`. Cada candidato vira `path.relative(gitTop, c).split(path.sep).join('/').toLowerCase()`; candidato que começa com `..` ou é absoluto depois disso é descartado. `const diff = lerDiff();` com `diff === null` devolve `false`; senão devolve se algum candidato está no `Set`.
- Em `protheusAberto`, antes do laço: `let diffCache; const lerDiff = () => (diffCache === undefined ? (diffCache = arquivosDaBranch(gitTop)) : diffCache);` (o diff roda no máximo uma vez por chamada, e só quando um arquivo não abriu pelas formas de hoje). Logo depois da linha do `gateAbreFluxo`, a linha literal: `if (typeof dados.branch !== 'string' && tocadoPelaBranch(arq, dados, gitTop, baseDir, lerDiff)) return true;`.
- Bateria, casos O6 a O9. Montagem, nesta ordem, em `repo.main` (os comandos git pelo helper `git(repo.main, [...])` da bateria):
  1. Gravar `docs/plans/velho.gates.json` (`{}`), `git add docs/plans/velho.gates.json`, `git commit -q -m velho`.
  2. Só O7 e O8: gravar `Cliente/docs/plans/x.gates.json` com `{"plan":{"file":"docs/plans/x-plan.md"},"design":{"doc":"docs/plans/x-design.md"}}` e `Cliente/docs/plans/x-plan.md` (`plano\n`), `git add Cliente`, `git commit -q -m base-cliente`.
  3. Exceto O9: `git update-ref refs/remotes/origin/main HEAD` e `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main`.
  4. `git checkout -q -b refactor/cliente-x`.
  5. O6 e O9: gravar `Cliente/docs/plans/x.gates.json` (`{}`), `git add Cliente`, `git commit -q -m gates`. O7: reescrever `Cliente/docs/plans/x-plan.md` (`plano 2\n`) e commitar. O8: gravar `Cliente/outro.txt` e commitar.
  6. Pôr 2 dias no `docs/plans/velho.gates.json` e no `Cliente/docs/plans/x.gates.json`, DEPOIS dos commits.
  - O6: `.gates.json` do cliente commitado na branch → exit 0.
  - O7: `.gates.json` na base, a branch só altera o `plan.file` (relativo à pasta do cliente) → exit 0.
  - O8: `.gates.json` na base, a branch altera outro arquivo → exit 2.
  - O9: como O6, sem `refs/remotes/origin/*` → exit 2.
  - O12: `.gates.json` na base, a branch commita outro arquivo e o `plan.file` muda só na árvore, sem commit → exit 2.
  - Emenda da revisão 1 (achado 3): cada candidata a padrão (`origin/HEAD`, `origin/main`, `origin/master`) se confere com `rev-parse --verify` antes de usar, e o diff leva `--no-renames`. O15: `origin/HEAD` aponta para `origin/master` inexistente, só `origin/main` existe → exit 0. O16: a branch faz `git mv` do `plan.file` declarado → exit 0.
  - Emenda da revisão 1 (achado 4): a linha `trilho protheus:` da recusa só sai quando existe alguma pasta `docs/plans` que `protheusAberto` leria (`temPastaDePlans(gitTop)`, exportada de `caminho-leve.cjs`). O17: repositório só com trilho rainforest → exit 2 sem a linha.
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `if (typeof dados.branch !== 'string' && tocadoPelaBranch(arq, dados, gitTop, baseDir, lerDiff)) return true;`
  para: `if (false) return true;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", casos O6 e O7
prova-na-base: verde — o critério precisa de branch com remoto e merge-base que só a fixture da bateria monta
pronto quando: com o mesmo payload da tarefa 1, provado por `node hooks/testa-portaria-fluxo-pulado.cjs` imprimindo `ok` em O6 a O9, e por `node hooks/testa-aviso-fluxo.cjs` e `node hooks/testa-bloqueio-fluxo.cjs` com zero falhas.

### 3. Portaria: trilho protheus aberto vale com o trilho rainforest presente, e a recusa diz onde procurou [tipo: implementar]
atende: D1
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 2
busca:
- catalogo | listar --raiz hooks | estendo o main de hooks/portaria.cjs:683 (estagioPermitido e a mensagem de negarFluxoPulado moram nele); detectarTrilhoFluxo de hooks/portaria.cjs:254 fica como está
desfecho: estender
O que fazer:
- O bloco de `const estagioPermitido = ...` (hoje `hooks/portaria.cjs:1018-1022`) fica exatamente assim:
  ```js
  const protheusLibera = (trilho === "protheus" || escreveDeclarado || escrevePorSinal)
    && protheusAberto({ gitTop: raiz, branch: obterBranch(raiz) });
  const estagioPermitido = trilho === "protheus"
    ? protheusLibera
    : protheusLibera || (escrevePorSinal
      ? Boolean(estResult)
      : Boolean(estResult) && Array.isArray(estagiosDeclarados) && estagiosDeclarados.includes(estResult.estagio));
  ```
  com um comentário de uma linha acima citando portaria-publicacao D1.3.
- Em `negarFluxoPulado`, no `const motivo = ...`, um termo novo entre `diagnostico +` e o termo que começa em `` `\n  saida 1 ``: `` `\n  trilho protheus: .gates.json procurado em '${raizBarras}/docs/plans' e '${raizBarras}/*/docs/plans'` + ``.
- Bateria: O5 (escrito na tarefa 1) fica verde, e os casos novos, com `docs/rainforest/estado/` (vazio) na raiz e sem fluxo rainforest:
  - O10: `Cliente/docs/plans/x.gates.json` com 2 dias → exit 2, e o stderr contém `/*/docs/plans`.
  - O11: sem `.gates.json` nenhum → exit 2.
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `: protheusLibera || (escrevePorSinal`
  para: `: (escrevePorSinal`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", casos O13 e O14 (O5 até a emenda da tarefa 6)
prova-na-base: verde — o critério precisa da raiz com os dois trilhos que só a fixture da bateria monta
pronto quando: com o payload de `Agent` da tarefa 1 e a raiz com `docs/rainforest/estado/` (o layout medido no repositório multi-cliente), provado por `node hooks/testa-portaria-fluxo-pulado.cjs` com `ok` em O10, O11, O13 e O14 e o placar final `falhou: 0`, e por `node hooks/testa-aviso-fluxo.cjs` e `node hooks/testa-bloqueio-fluxo.cjs` com zero falhas.

### 4. `gh api`: conta e repositório de destino no endpoint não são conferidos contra a lista privada [tipo: implementar]
atende: D2, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | estendo textosDoGhApi de hooks/gate-publicacao-destino.cjs:834; corposEmbutidos de hooks/gate-publicacao-destino.cjs:991 continua lendo o comando original
desfecho: estender
O que fazer:
- Função nova, logo acima de `textosDoGhApi`:
  ```js
  function neutralizarDestinoNoEndpoint(cmd) {
    return cmd
      .replace(/(\b(?:orgs|users)\/)[^/\s?#'"]+/gi, "$1<destino>")
      .replace(/(\brepos\/)[^/\s?#'"]+\/[^/\s?#'"]+/gi, "$1<destino>/<destino>");
  }
  ```
  com docblock citando a #726 e a D2. Os valores de campo, os corpos de `--input`/`@arquivo` e os corpos embutidos continuam entrando em `textos` pelos caminhos de hoje, lidos do original.
- Em `textosDoGhApi`, a entrada do comando passa a ser `{ origem: "comando", texto: neutralizarDestinoNoEndpoint(cmdOriginal, endpoint) }`. Nada mais no arquivo muda (D3).
- **Emenda da revisão 1 (achado alta):** trocar no texto inteiro do comando apagava o termo de corpo por pipe, `<<<` ou `echo > arquivo`, que só se confere por esse texto. A troca passa a valer só no token do endpoint (`posicionais[0]`), na primeira ocorrência dele no comando, por `neutralizarEndpoint(ep)` (as duas regex acima). Endpoint que não aparece literal no comando deixa o comando como está. Casos novos, todos exit 2 com `"$PUB"`: `726 corpo por pipe com orgs/<termo> barra`, `726 corpo por <<< com users/<termo> barra`, `726 echo > arquivo com repos/<termo>/y barra`, `726 corpo anterior igual ao endpoint barra`.
- **Emenda da revisão de segurança do `8d599a1a`:** a troca só vale quando o token do endpoint é simples (forma crua igual ao valor: sem `mista`, sem `raw`) e o texto dele aparece uma única vez no comando. Com aspa no meio (`orgs/ter"mo702"/teams`), o `indexOf` caía num corpo igual por pipe e apagava o termo dele. `textosDoGhApi` recebe os tokens com aspas (`objs`) e guarda o índice do endpoint. Casos novos: `726 endpoint com aspa no meio e corpo igual barra` e `726 endpoint com contrabarra e corpo igual barra` (exit 2), `726 endpoint entre aspas inteiro passa` (exit 0).
- **Emenda da revisão 2 (achado 1, e as revisões de segurança do `db2f583e`):** com uma contrabarra solta (`orgs/termo702/teams`), o tokenizador tira a contrabarra sem marcar `mista` nem `raw`, e a guarda da emenda anterior passava. A troca passa a acontecer na posição do token: `tokensComAspas` (`hooks/lib/tokens-comando.cjs`) ganha `ini`/`fim` não enumeráveis; `neutralizarDestinoNoEndpoint(cmd, endpoint, tokEndpoint, segmento)` só troca quando a forma crua do token no segmento é o valor (ou ele entre um par de aspas), o valor não tem contrabarra, aspas, `$` nem crase, e o segmento aparece uma vez no comando; a posição é `indexOf(segmento) + ini`. Casos novos: `726 endpoint com uma contrabarra e corpo igual barra`, `726 endpoint com uma contrabarra e corpo por <<< barra` (exit 2) e `726 endpoint depois de corpo sem termo por pipe passa` (exit 0). O docblock de `textosDoGhApi` volta para cima da função (achado 3).
- **Emenda da revisão 1 (achado 2, D2 emendada com Q1 aceita):** as duas regex ganham âncora no início do endpoint, com prefixo opcional `/`, `https://api.github.com/` ou `https://<host>/api/v3/` (constantes `RE_CONTA_NO_ENDPOINT` e `RE_REPO_NO_ENDPOINT`, sem flag `g`). Casos novos: `726 contents/docs/users/<termo> barra`, `726 contents/orgs/<termo>/README barra` e `726 contents/a/repos/<termo>/b barra` (exit 2, `"$PUB"`); `726 URL completa de orgs/<termo> passa` e `726 /orgs/<termo> com barra inicial passa` (exit 0, `"$PUB"`).
- Bateria: seção nova logo antes do `echo` que precede `== resultado:`, com `echo "== (#726) gh api: destino no endpoint =="`, todos os casos com `confere702` direto, tipo `Bash`, `cwd` `"$R702P"`:
  - `726 orgs/<termo>/teams passa`: exit 0, `"$PUB"`, `gh api orgs/termo702/teams -X POST -f name=x -f privacy=closed`.
  - `726 users/<termo> passa`: exit 0, `"$PUB"`, `gh api users/termo702/x -X POST -f a=b`.
  - `726 repos/<termo>/x publico passa`: exit 0, `"$PUB"`, `gh api repos/termo702/x/issues -X POST -f title=ok`.
  - `726 campo de org com termo barra`: exit 2, `"$PRIV"`, `gh api orgs/termo702/teams -X POST -f description=termo702`.
  - `726 contents/<termo> no publico barra`: exit 2, `"$PUB"`, `gh api -X PUT repos/dono/x/contents/termo702.md -f message=ok -f content=eA==`.
  - `726 query string com termo barra`: exit 2, `"$PRIV"`, `gh api 'orgs/x/teams?q=termo702' -X POST -f name=y`.
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `{ origem: "comando", texto: neutralizarDestinoNoEndpoint(cmdOriginal, endpoint, objs && iEndpoint !== -1 ? objs[iEndpoint] : null, segmento) }`
  para: `{ origem: "comando", texto: cmdOriginal }`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: testa-gate-publicacao-destino.sh, seção "(#726) gh api: destino no endpoint", caso "726 orgs/<termo>/teams passa"
prova-na-base: verde — o critério precisa da lista privada sintética e do `gh` falso que a caixa de areia da bateria monta
pronto quando: com o comando medido na #726 (`gh api orgs/<org>/teams -X POST -f name=x -f privacy=closed`) e o termo sintético `termo702` no lugar da org, provado por `bash hooks/testa-gate-publicacao-destino.sh` com `ok` nos casos `726` (os seis originais e os quatro da emenda) e `== resultado: N ok, 0 falha(s) ==` (os casos `707` continuam com o exit de antes).

### 6. Com o trilho rainforest na raiz, só vínculo abre o trilho protheus [tipo: implementar]
Emenda de 2026-11-18: a revisão de segurança do commit mostrou que `git worktree add` renova o mtime de todo arquivo. Num worktree novo, todo `.gates.json` de cliente parecia recente e liberaria qualquer escritor por cima do trilho rainforest. A D1.3 foi emendada no design (Q1 aceita pelo Luís).
atende: D1
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 3
busca:
- catalogo | listar --raiz hooks/lib | estendo protheusAberto de hooks/lib/caminho-leve.cjs:182 com a opção exigeVinculo; a portaria a passa no main de hooks/portaria.cjs:683
desfecho: estender
O que fazer:
- `protheusAberto({ gitTop, branch, agora, exigeVinculo = false })`: com `exigeVinculo`, um arquivo abre pelo próprio conteúdo só com `typeof dados.branch === 'string' && dados.branch === branch` (o mtime não conta). A via do diff (tarefa 2) vale igual.
- Na portaria, a chamada de `protheusLibera` passa `exigeVinculo: trilho !== "protheus"`.
- Bateria: O5 passa a esperar exit 2 (recente sem vínculo), O14 (`{"branch":"main"}` recente, trilho rainforest) → exit 0, O13 (`.gates.json` do cliente commitado na branch, trilho rainforest, remoto gravado como em O6) → exit 0.
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `exigeVinculo: trilho !== "protheus"`
  para: `exigeVinculo: false`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: testa-portaria-fluxo-pulado.cjs, seção "O. multi-cliente", caso O5
prova-na-base: verde — o critério precisa da raiz com os dois trilhos que só a fixture da bateria monta
pronto quando: com o payload de `Agent` da tarefa 1 e a raiz com `docs/rainforest/estado/`, provado por `node hooks/testa-portaria-fluxo-pulado.cjs` com `ok` em O5 (exit 2), O13 e O14 (exit 0) e `falhou: 0`.

### 5. Versão 2.17.1, CHANGELOG e README [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 4, 6
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
O que fazer: `"version": "2.17.1"` nos dois manifestos; no README, só o selo da linha 7 (URL e `alt`); no CHANGELOG, a seção `## 2.17.1 — 2026-11-18` acima da `## 2.17.0`.
pronto quando: com os dois manifestos do plugin, `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(f, require('./'+f).version)"` imprime `2.17.1` nas duas linhas, o selo de versão do README diz `2.17.1`, e a entrada `2.17.1` do `CHANGELOG.md` cita as Issues #726, #728 e #729 com o que mudou nos dois gates, coerente com D1 e D2 do design (pasta do cliente, diff da branch, trilho rainforest presente, segmento de conta e repositório no endpoint).
