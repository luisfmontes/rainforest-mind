# Plano: Zerar as Issues abertas, rodada 9 — gates (#337, #313, #322), CI das baterias .cjs (#335), veredito em worktree (#329), duplicação gitignorada (#323), carimbo de emenda (#312)

Design: docs/rainforest/design/zerar-issues-9.md

## O que não pode quebrar
- Tudo que os três gates de texto (`gate-fechar-issue`, `gate-mensagem-commit`, `gate-staging-total`) barram hoje continua barrado: `bash -c "gh issue close 12"`, `bash -c "$x"`, `eval "$x"`, `bash "$f" "gh issue close 12"`, `for t in x; do bash -c "gh issue close 12"; done` saem 2.
- `gate-publicacao-destino` continua recusando `Write` com e-mail de terceiro e `Edit` que **introduz** e-mail de terceiro.
- `bash scripts/varrer-baterias.sh` continua sem depender de rede nem credencial, e nenhuma bateria roda duas vezes.
- `veredito-revisor` nunca derruba a sessão: todo caminho novo sai 0.
- `estado.cjs` continua recusando carimbo de tarefa que não existe no plano (nem no arquivo, nem no número gravado).

## Tarefas

### 1. `bash $VAR` sem aspas é execução de arquivo (#337) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `function ehVariavelSemAspasComoArquivo(current) {`
  para: `function ehVariavelSemAspasComoArquivo(current) { return false;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `600000`
  fixture: testa-gate-fechar-issue.sh, secao "(#337) bash $VAR sem aspas"
pronto quando: com o payload PreToolUse real (`{"cwd":<worktree>,"tool_name":"Bash","tool_input":{"command":...}}`) e `gh` de sandbox no PATH, `for t in a b; do bash $t; done`, `f=x.sh; bash $f 2>&1 | tail -1`, `bash $t arg` e `sh ${t}` saem **0** no `gate-fechar-issue.cjs` (hoje os dois primeiros saem 2), enquanto `bash -c "$x"`, `bash -c $x`, `eval "$x"`, `bash $f "gh issue close 12"` e `for t in x; do bash -c "gh issue close 12"; done` saem **2** — nos três gates de texto, provado por `bash hooks/testa-gate-fechar-issue.sh && bash hooks/testa-gate-mensagem-commit.sh && bash hooks/testa-gate-staging-total.sh` com cada caso impresso com o exit. A função nova começa na linha exata `function ehVariavelSemAspasComoArquivo(current) {` e é chamada em `desempacotarWrapperDeString` ao lado de `ehVariavelCitadaFinal`. Antes de escrever, medir se `bash $f "gh issue close 12"` sai 2 hoje e colar no relato: aceitar esse caso é regressão (com `f=-c` vira `bash -c` escondido) — variável sem aspas só é arquivo quando nenhum argumento depois dela é string entre aspas com espaço; o executor documenta no comentário a regra exata que escolheu.

### 2. Aspas duplas do wrapper reduzem escape antes do colapso (#313) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-staging-total.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `function reduzEscapeAspasDuplas(str) {`
  para: `function reduzEscapeAspasDuplas(str) { return str;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `600000`
  fixture: testa-gate-fechar-issue.sh, secao "(#313) contrabarra dupla dentro do wrapper"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `bash -c "gh issue \\` + quebra + `close 12"` sai **2** nos três gates (hoje sai 0), e `bash -c 'gh issue \\` + quebra + `close 12'` (aspas simples) tem o comportamento de dois comandos separados — o executor mede o que o bash real executa nesse caso (`bash -c` com um `gh` falso que imprime os argumentos) e a bateria afirma o exit que corresponde a esse comportamento, com os dois casos lado a lado. Provado por `bash hooks/testa-gate-fechar-issue.sh && bash hooks/testa-gate-mensagem-commit.sh && bash hooks/testa-gate-staging-total.sh`; `desempacota` chama `reduzEscapeAspasDuplas` só no ramo de aspas duplas, antes de `colapsaContinuacaoDeLinha`; os casos fechados na rodada 8 (`bash -c "gh issue \<quebra>close 12"`, `echo hi \\<quebra>gh issue close 12`) continuam saindo 2.

### 3. Edit só é barrado pelo que introduz (#322) [tipo: implementar]
atende: D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `function soIntroduzidos(novos, antigos) {`
  para: `function soIntroduzidos(novos, antigos) { return novos;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: testa-gate-publicacao-destino.sh, secao "(#322) Edit que preserva achado de old_string"
pronto quando: com o payload PreToolUse real de `Edit` num arquivo versionado de um repo git de teste: `old_string` e `new_string` contendo o mesmo e-mail de terceiro (domínio real, não `.test`/`.example`, montado em tempo de execução na bateria para o próprio fonte não carregar um e-mail literal), mudando só outra palavra da linha → **0**; `new_string` que acrescenta um e-mail que não está em `old_string` → **2**; o mesmo par para `MultiEdit` (cada edit com seu `old_string`) → 0 e 2; `Write` com o e-mail de terceiro → **2**; `Edit` que troca só o nome do modelo na linha do trailer de co-autoria com o endereço noreply da Anthropic → **0**. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com os casos impressos. A comparação é por achado (`id` + `trecho` redigido, em multiconjunto: dois e-mails novos onde havia um → barra), feita pela função que começa na linha exata `function soIntroduzidos(novos, antigos) {`, aplicada no ramo `Edit` e no `MultiEdit`.

### 4. Varredor descobre baterias `.cjs` (#335) [tipo: configurar]
atende: D4
arquivos: `scripts/varrer-baterias.sh`, `scripts/testa-varrer-baterias.sh`, `hooks/testa-colapso-continuacao.sh`, `hooks/testa-gate-commit.sh`, `hooks/testa-gate-busca-raiz.sh`, `hooks/testa-memoria-escada.sh`, `CONTRIBUTING.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/varrer-baterias.sh`
  de: `de_hooks_cjs=(hooks/testa-*.cjs)`
  para: `de_hooks_cjs=()`
  bateria: `bash scripts/testa-varrer-baterias.sh`
  fixture: testa-varrer-baterias.sh, secao "(#335) bateria .cjs quebrada deixa o placar vermelho"
pronto quando: com a árvore real, `bash scripts/varrer-baterias.sh` roda com `node` cada `hooks/testa-*.cjs` e `scripts/testa-*.cjs` (as 18 de hoje, entre elas `hooks/testa-portaria-folha.cjs`) e nenhuma bateria aparece duas vezes — provado por `bash scripts/varrer-baterias.sh 2>&1 | grep -c -- '----- .*\.cjs -----'` igual a `ls hooks/testa-*.cjs scripts/testa-*.cjs | wc -l`, e `bash scripts/varrer-baterias.sh 2>&1 | grep -- '^----- ' | sort | uniq -d` vazio. Numa cópia da árvore com uma `hooks/testa-*.cjs` adulterada para `process.exit(1)`, o varredor sai **1** e a lista `vermelhas:` nomeia essa `.cjs` (caso novo em `testa-varrer-baterias.sh`). `--so` aceita `testa-*.cjs`. As cascas `.sh` que só fazem `exec node <mesma .cjs>` saem (`testa-colapso-continuacao.sh`, `testa-gate-commit.sh`, `testa-gate-busca-raiz.sh`, `testa-memoria-escada.sh` — conferir cada uma antes de apagar); `hooks/testa-cli-externo.sh` não é casca e fica — o executor confere se ele chama `scripts/testa-cli-externo.cjs` e, se chamar, garante que ela não rode em dobro. Pisos por pasta para `.cjs` como os de `.sh`. `CONTRIBUTING.md` coerente com D4 (o varredor roda `.sh` e `.cjs`; casca não é mais necessária).

### 5. `veredito-revisor` acha o estado no worktree (#329) [tipo: implementar]
atende: D5
arquivos: `hooks/veredito-revisor.cjs`, `hooks/testa-veredito-revisor.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: `function raizComEstadoDoSlug(repoRoot, slug) {`
  para: `function raizComEstadoDoSlug(repoRoot, slug) { return repoRoot;`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: testa-veredito-revisor.sh, secao "(#329) estado so no worktree"
pronto quando: com o payload SubagentStop real (`agent_type: rainforest-mind:revisor`, `cwd` = checkout principal de um repo de teste, transcrito com `Slug: <s>`, `last_assistant_message` terminando em `VEREDITO: ok`) e `docs/rainforest/estado/<s>.json` existindo **só** num worktree linkado desse repo: o veredito `ok` é gravado no JSON do worktree (`revisar.vereditos` com o `agent_id`) e `estado.cjs marcar --estagio revisar --status ok` rodado nesse worktree não recusa por falta de veredito; com o slug em **dois** worktrees e com o slug em **nenhum**: exit 0, nada gravado em lugar nenhum, e stderr com uma linha que nomeia o slug e o motivo (ambíguo, listando os caminhos / não encontrado). Provado por `bash hooks/testa-veredito-revisor.sh` com os três casos; o caso existente com o slug na raiz do `cwd` continua gravando lá.

### 6. Duplicação mede só o versionável (#323) [tipo: implementar]
atende: D6
arquivos: `scripts/conferir-duplicacao.cjs`, `scripts/testa-conferir-duplicacao.sh`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-duplicacao.cjs`
  de: `function candidatosPeloGit(raiz) {`
  para: `function candidatosPeloGit(raiz) { return null;`
  bateria: `bash scripts/testa-conferir-duplicacao.sh`
  fixture: testa-conferir-duplicacao.sh, secao "(#323) copia gitignorada nao conta"
pronto quando: com o checkout principal real (`C:/Projetos/rainforest-mind`, que tem `.claude/marketplaces/` com 3 cópias gitignoradas), `node scripts/conferir-duplicacao.cjs --raiz C:/Projetos/rainforest-mind --json` rodado **com o fonte do worktree** devolve `duplicados` vazio e exit 0 (hoje: 813 grupos); num repo de teste, a cópia de um arquivo versionado dentro de pasta gitignorada **não** conta e a mesma cópia fora do gitignore **conta** (caso novo). `candidatosPeloGit` usa `git ls-files --cached --others --exclude-standard` e devolve `null` fora de repo git, caso em que a varredura por `readdirSync` de hoje segue valendo. Na seção K de `scripts/testa-saude.sh`, a cópia da árvore passa a ser feita pela mesma lista do git em vez do `tar` do diretório. Provado por `bash scripts/testa-saude.sh` num worktree de teste com uma cópia gitignorada em `.claude/marketplaces/` terminando em `0 falha(s)` com `DUP2` e `K` em `ok`; o executor cola a linha `== resultado ==` de antes e de depois.

### 7. Teto do carimbo lê o arquivo do plano (#312) [tipo: implementar]
atende: D7
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `function tetoDeTarefasDoPlano(slug, blocoPlano) {`
  para: `function tetoDeTarefasDoPlano(slug, blocoPlano) { return blocoPlano && typeof blocoPlano.tarefas === 'number' ? blocoPlano.tarefas : null;`
  bateria: `bash scripts/testa-estado.sh`
  fixture: testa-estado.sh, secao "(#312) carimbo de tarefa acrescentada por emenda"
pronto quando: com um fluxo de teste cujo `plano.tarefas` gravado é 6 e cujo arquivo do plano tem `### 1.` a `### 8.`, `estado.cjs marcar --estagio executar` com carimbo da tarefa 8 **grava** (hoje: `RECUSADO: carimbo da tarefa 8 fora do plano (1..6).`), carimbo da tarefa 9 **recusa** nomeando `1..8`, e sem o arquivo do plano o teto volta a ser `plano.tarefas` (carimbo 7 recusado com `1..6`). A contagem reusa o leitor de `### <n>. ` que a validação de `mutacao` já usa (não um segundo parser). Provado por `bash scripts/testa-estado.sh` com os três casos impressos.

### 8. Versão, changelog e issues [tipo: docs]
atende: D8
arquivos: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: bump de versão e texto de changelog, sem comportamento a inverter
pronto quando: com `origin/main` no momento do `fechar`, a versão no `plugin.json` e no badge do README é o minor seguinte ao dela (hoje 1.23.15 → 1.24.0) — provado por `node scripts/conferir-versao.cjs` saindo 0; o CHANGELOG tem uma entrada por issue (#337, #313, #322, #335, #329, #323, #312) dizendo o comportamento novo de cada uma, coerente com D1-D7 (inclusive a emenda de D3: a isenção do `noreply@` não mudou nesta rodada), e não anuncia nada da #302; depois do merge, as sete fecham pelo `fechar-issue.cjs` e a #302 continua aberta — provado por `gh issue list --state open --json number` devolvendo só `302`.
