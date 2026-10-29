# Plano: Colheita — coordenação entre sessões, carimbo com hash real e exemplos prescritos contra os gates

Design: docs/rainforest/design/2026-10-29-colheita-coordenacao-e-gates.md

## O que não pode quebrar
- Carimbo com `hash_base` real (saído de `git rev-parse`) continua aceito; fora de repositório git o `marcar` não muda de comportamento.
- Os casos já existentes de `scripts/testa-estado.sh`, `scripts/testa-painel-fluxo.sh` e `hooks/testa-gate-fechar-issue.sh` continuam verdes.
- O núcleo injetado continua dentro dos tetos: `bash scripts/testa-orcamento.sh`, `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-contexto-sessao.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` verdes.

## Tarefas

### 1. estado.cjs recusa carimbo cujo hash_base não é commit do repositório [tipo: implementar]
atende: D4, D8
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`, `scripts/testa-painel-fluxo.sh`
depende de: nenhuma
busca:
- repo | rg "cat-file -e" scripts hooks | conferir-ancoras.cjs resolve sha com cat-file -e <sha>^{commit}, função local e não exportada; estado.cjs já tem ehAncestralDoHead com spawnSync e o mesmo contrato true/false/null
- livro | pulado: trava pequena sobre função existente do próprio estado.cjs
desfecho: compor
prova-na-base: verde — o caso novo nasce na própria tarefa dentro de testa-estado.sh; na base a bateria não o tem e sai 0
mutacao:
  arquivo: `scripts/estado.cjs`
  de: if (hashEhCommit(hash) === false) {
  para: if (false) {
  bateria: `bash scripts/testa-estado.sh`
  timeout: 900000
  fixture: testa-estado.sh, caso "carimbo com hash_base que nao e commit deste repositorio recusa (D4)"
pronto quando: com o `marcar --estagio executar --status parcial --json '{"carimbos":[{"tarefa":1,"hash_base":"d0000000"}]}'` que a janela principal roda num repositório git com o fluxo em `executar`, o `estado.cjs` sai 2 com "nao e commit deste repositorio" e não grava o carimbo; o mesmo comando com `hash_base` igual a `git rev-parse HEAD` sai 0 e grava; fora de repositório git o hash inexistente continua aceito — provado por `bash scripts/testa-estado.sh` devolvendo as linhas `ok` dos três casos e `== resultado: N ok, 0 falhas ==`, e por `bash scripts/testa-painel-fluxo.sh` saindo 0

Forma prescrita para o código novo: uma função `hashEhCommit(hash)` ao lado de `ehAncestralDoHead`, com o mesmo contrato (`true`/`false`/`null`; `null` quando a raiz do estado não é repositório ou o git falha por outro motivo — distinguir com `git rev-parse --is-inside-work-tree` antes do `git cat-file -e <hash>^{commit}`), chamada em `processarCarimbos` logo depois da checagem de formato, numa linha que case com o `de:` acima. Fixtures existentes que usam hash fictício (`abc1234`, `abc1234567890`) dentro de repositório git passam a usar hash real do sandbox; nenhum caso pode afirmar sobre o texto do fonte.

### 2. Bateria de exemplos prescritos contra o gate-fechar-issue [tipo: teste]
atende: D6, D7, D8
arquivos: `scripts/testa-exemplos-prescritos.cjs`, `scripts/tempos-baterias.json`, `skills/fechar/SKILL.md`, `scripts/contrato-plugin-codex.cjs`
depende de: nenhuma
prova: `node scripts/testa-exemplos-prescritos.cjs`
mutacao:
  arquivo: `skills/fechar/SKILL.md`
  de: `gh pr edit <de-cima> --base main`; só então
  para: `gh issue close <de-cima>`; só então
  bateria: `node scripts/testa-exemplos-prescritos.cjs`
  fixture: testa-exemplos-prescritos.cjs, forma extraída de skills/fechar/SKILL.md (a linha de `--base main`)
pronto quando: com os `.md` reais de `skills/`, `skills/*/references/`, `commands/` e `agents/` no HEAD da tarefa, cada forma `gh issue|pr <create|close|merge|edit|comment|reopen> ...` entre crases ou em bloco de código vira um payload `PreToolUse` de `Bash` (stdin JSON com `tool_input.command`) passado ao processo `node hooks/gate-fechar-issue.cjs`, com `gh` stub à frente do PATH e corpo em `os.tmpdir()`; a bateria imprime uma linha por forma (arquivo:linha, comando, exit) e sai 0 quando nenhuma forma fora da lista de exceções sai 2 — provado por `node scripts/testa-exemplos-prescritos.cjs` devolvendo ao menos as formas `gh pr create`, `gh pr merge <n> --squash`, `gh pr edit <de-cima> --base main` e `gh issue create --repo` com exit 0, e saindo 1 com a mutação acima aplicada (a linha da forma mutada mostrando exit 2)

Emenda de 2026-10-29, no executar: a primeira execução achou `skills/fechar/SKILL.md:116` prescrevendo `gh pr create` sem `--body-file`, que o gate barra. O texto passou a `gh pr create --title "<título>" --body-file <arquivo>` (regra 6: mesma classe, cabe no PR), e a âncora binária do corpo do `fechar` em `scripts/contrato-plugin-codex.cjs` foi re-medida, provado por `bash scripts/testa-plugin-codex.sh` saindo 0. Emenda da tarefa 1, no mesmo dia: o git da checagem roda na raiz do estado (`RAIZ`), não no cwd.

Contrato da lista de exceções, dentro do próprio arquivo: cada item tem `forma`, `arquivo` e `motivo` não vazio; item sem motivo faz a bateria sair 1, e item cuja forma não aparece mais no arquivo citado também. O peso em `tempos-baterias.json` é o tempo medido de uma execução local, arredondado para cima.

### 3. Regra 6: sessão dona viva, uma mensagem ao dono certo, design lido antes de "aguardo" [tipo: docs]
atende: D1, D2, D3
arquivos: `skills/rainforest-mind/references/regra-06.md`, `skills/rainforest-mind/SKILL.md`
depende de: nenhuma
mutacao: n/a
  motivo: só texto de regra; não há comportamento executável a inverter, e D8 declara que nenhum hook confere SendMessage
pronto quando: com o `regra-06.md` e o núcleo do `SKILL.md` no HEAD da tarefa, a subseção nova "Repo alheio com sessão dona viva" prescreve as três condutas do design na ordem D1 (olhar `sessoes.json` e `ListAgents`, ausência no `ListAgents` não prova sessão morta, pedido por `SendMessage` só à dona, Issue quando não há dona viva ou ela pede), D2 (dúvida sobe ao coordenador ou ao Luís, sem mensagem a várias nem de cortesia) e D3 (aviso que cita design: abrir o design e ler a seção de responsabilidades antes de responder, citando a regra 16); a frase "não há hook que avise commit fora do repo da sessão" deixa de contradizer o `hooks/gate-repo-alheio.cjs` (que barra Write/Edit em outro repo, não commit pelo shell); e o núcleo da regra 6 diz "pedido à sessão dona viva, senão Issue + `Q`" se couber nos tetos — provado por `grep -n "sessão dona viva" skills/rainforest-mind/references/regra-06.md skills/rainforest-mind/SKILL.md` devolvendo a subseção e (se coube) o núcleo, `grep -c "não há hook que avise commit fora do repo da sessão" skills/rainforest-mind/references/regra-06.md` devolvendo `0`, e `bash scripts/testa-orcamento.sh`, `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-contexto-sessao.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saindo 0. Se o núcleo não couber, o relato cola a saída vermelha do teto com a mudança e o núcleo fica como está (D1).

### 4. Skill plano: critério sobre arquivo que outras sessões escrevem [tipo: docs]
atende: D5
arquivos: `skills/plano/SKILL.md`
depende de: nenhuma
mutacao: n/a
  motivo: só texto de skill; o efeito é sobre quem escreve o próximo plano
pronto quando: com o `skills/plano/SKILL.md` no HEAD da tarefa, a lista "Três cuidados ao escrever o critério" da seção "`pronto quando:` nomeia a ENTRADA REAL" ganha o cuidado de arquivo compartilhado entre sessões (`ideias.jsonl`, `sessoes.json`, banco de memória) entrar no critério pelos ids que a tarefa toca, nunca por contagem global, com o incidente do colheita-pos-2-1-0 (tarefa 5, verificar reprovou entrega correta) — provado por `grep -n "contagem global" skills/plano/SKILL.md` devolvendo a linha dentro da seção, e `bash scripts/testa-teto-skills.sh` e `bash scripts/testa-plugin-codex.sh` saindo 0

### 5. README, CHANGELOG e versão 2.2.0 [tipo: docs]
atende: D9
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2, 3, 4
mutacao: n/a
  motivo: só texto e número de versão; o comportamento novo é medido pelas mutações das tarefas 1 e 2
pronto quando: com o repositório no HEAD da tarefa, a versão é `2.2.0` nos dois `plugin.json` e no badge do README, o CHANGELOG tem a entrada 2.2.0 citando a recusa de carimbo com hash inexistente, a bateria de exemplos prescritos e a regra 6 com sessão dona viva — provado por `bash scripts/testa-versao.sh` saindo 0 e `grep -c "2.2.0" CHANGELOG.md` devolvendo ao menos `1`
