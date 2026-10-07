# Plano: Zerar issues: #409-#414, #417, #419

Design: docs/rainforest/design/2026-10-07-zerar-issues-17.md

Base: `0656db33` (origin/main).

Nota para quem executa: nas linhas que este plano dita como literais (alvo de mutação), nenhum caso de teste pode ler o texto do fonte — o teste exercita o comportamento; a forma literal existe só para a catraca achar a linha. Payload de hook em bateria nova sai de `node -e '…JSON.stringify(…)'` com valores por argv, nunca montado à mão. Os exemplos de cabeçalho e de telefone das tarefas 1 ficam só na bateria (que é sandbox de teste), não neste plano: o gate de publicação 1.44.0 os acusa aqui.

## O que não pode quebrar
- Toda bateria existente segue verde e sem perder caso (contagem de `ok` não cai em bateria alterada, exceto os casos do arquivo `.rainforest-gate-off`, que viram casos negativos — D11).
- `gate-fechar-issue` segue barrando `gh issue close 1`, `eval "$x"` com variável e `bash -c "gh issue close $N"`.
- `conferir-publicacao` segue acusando telefone com máscara e sem máscara, e o cabeçalho de autorização com esquema seguido de literal hex de 32 posições.
- Repo sem `docs/legado/` e sem `docs/plans/` segue com design, plano e mapa exatamente em `docs/rainforest/<tipo>/<slug>.md` (este repo é o caso).
- Config de projeto fora de git segue lido de `CLAUDE_PROJECT_DIR`/cwd como hoje.
- `marcar --estagio verificar` sem `--raiz` se comporta como hoje.
- O mod da abertura segue acrescentando a seção no `prompt.compose` e tirando as entradas duplicadas do SessionStart em conta sem `cc-plugin-sec-default`.
- `claude plugin validate .claude-plugin/plugin.json` sai 0.

## Tarefas

### 1. gate de publicação: pseudo-versão Go e esquema de Authorization [tipo: implementar]
atende: D17, D18, D19
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `if (dentroDePseudoVersaoGo(m, linha)) return false;`
  para: `if (false) return false;`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: `testa-conferir-publicacao.sh, caso "409 pseudo-versao Go em go.mod nao e telefone"`
pronto quando: com as linhas reais de `go.mod` e `go.sum` citadas na Issue #409 pelo stdin, `node scripts/conferir-publicacao.cjs - --json` sai 0 sem achado; um comentário com telefone mascarado no mesmo `go.mod` sai 2 com `telefone`; com as três formas de cabeçalho da Issue #410 (f-string Python, `.format` e `${VAR}` depois do esquema `Bearer`) sai 0; com o esquema seguido de literal hex de 32 posições, e com f-string cuja referência tem literal colado depois do fecha-chaves, sai 2 com `credencial`. A função `dentroDePseudoVersaoGo(m, linha)` casa `v\d+\.\d+\.\d+-(?:0\.)?\d{14}-[0-9a-f]{12}` e devolve true só se o match de telefone cai dentro dele; a linha literal do `de:` entra no `so_se` do telefone antes do teste de token hex. Para #410, o `so_se` da credencial, quando a chave é `authorization`, pula a palavra de esquema (`Bearer`/`Basic`/`Token`, com prefixo `f"` aceito) e julga o valor seguinte; `REFERENCIA_DE_VARIAVEL` ganha `{IDENT}` e `.format(IDENT)` — provado por `bash scripts/testa-conferir-publicacao.sh` imprimindo os casos novos como ok e `0 falha(s)`

### 2. mod da abertura: nada de append com cc-plugin-sec-default [tipo: implementar]
atende: D20
arquivos: `hooks/register.ts`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura-append.cjs`, `hooks/testa-mod-abertura.cjs`, `hooks/abertura-mod.json`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao: n/a
  motivo: a tarefa é remoção de um caminho de código; não sobra linha a inverter. A falsificação é a `prova:`: na base o caso novo fica vermelho porque o `register.ts` ainda anexa a mensagem
pronto quando: com o `register.ts` real carregado pelo `$` falso da bateria e `engine.create` disparado com `plugins: ['cc-plugin-sec-default']`, seguido de `session.start` e de `prompt.submit` depois de `session.end` com `reason: 'clear'`, nenhuma chamada a `session.append` acontece (caso novo "sec-default: nenhum append" em `hooks/testa-mod-abertura.cjs`, que conta as chamadas do `$` falso); `register.ts` não registra mais `engine.create`, `session.start`, `prompt.submit` nem `session.compact`; `hooks/testa-mod-abertura-append.cjs` deixa de existir; sem o plugin, `prompt.compose` segue recebendo a seção `rainforest-mind:abertura` — provado por `node hooks/testa-mod-abertura.cjs` com `0 falha(s)` e `git ls-files hooks/testa-mod-abertura-append.cjs` sem saída

### 3. config de projeto pela raiz do checkout principal [tipo: implementar]
atende: D7
arquivos: `hooks/lib/config.cjs`, `scripts/setup.cjs`, `hooks/testa-config.sh`, `scripts/testa-setup.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `hooks/lib/config.cjs`
  de: `const projetoDir = raizDoPrincipal(o.projeto || env.CLAUDE_PROJECT_DIR || process.cwd());`
  para: `const projetoDir = o.projeto || env.CLAUDE_PROJECT_DIR || process.cwd();`
  bateria: `bash hooks/testa-config.sh`
  fixture: `testa-config.sh, caso "411 config do projeto visto de dentro de worktree linkado"`
pronto quando: num repo git de `mktemp -d` com `.rainforest/config.json` `{"gate-publicacao": false}` na raiz e um `git worktree add` dentro de `.claude/worktrees/x`, `node -e 'console.log(require("./hooks/lib/config.cjs").ligado("gate-publicacao",{projeto:process.argv[1]}))' <worktree>` imprime `false`, e o mesmo a partir de um subdiretório do principal imprime `false`; numa pasta fora de git com o config, imprime `false` como hoje; `node scripts/setup.cjs --desligar gate-publicacao --escopo projeto` rodado com cwd no worktree grava em `<principal>/.rainforest/config.json` e não cria `<worktree>/.rainforest/`. `raizDoPrincipal(dir)` usa `git rev-parse --path-format=absolute --git-common-dir` com `cwd: dir`; basename `.git` → `dirname`; qualquer falha → `dir` — provado por `bash hooks/testa-config.sh` e `bash scripts/testa-setup.sh` com os casos novos ok e `0 falha(s)`

### 4. gate-fechar-issue lê o arquivo do `. arquivo` [tipo: implementar]
atende: D14, D15, D16
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (ehSourceDeArquivo(toksComAspas, pos)) {`
  para: `if (false) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, casos "414-1 set -a ponto env com variavel passa", "414-2 ponto env literal passa", "414-3 laco com ponto ./$f passa"`
pronto quando: com o payload PreToolUse real (`node -e JSON.stringify` com o comando por argv) dos três repros da Issue #414 (`set -a; . "/c/x/transcription.env"; set +a` + `uv run`; `set -a; . /c/x/transcription.env; set +a` + `uv run`; o laço `for f in env-api env-off; do ( …; . ./$f; … ); done`), `node hooks/gate-fechar-issue.cjs` sai 0; `bash -c "gh issue close $N"` sai 2; `source fechar.sh` com `fechar.sh` contendo `gh issue close 12` sai 2 (caso `(by)` mantido); `. ./fechar.sh` com o mesmo conteúdo sai 2; e o stderr do bloqueio de `. ./x.sh` ilegível não contém `contém variável` quando o comando não tem `$`. O ramo novo vem antes do `desempacotarWrapperDeString`, com a linha literal do `de:` acima, e usa `caminhoDeArquivoExecutado` + `arquivoDeScriptExecutado` como `gate-subagente-sem-gh.cjs:717-727` — provado por `bash hooks/testa-gate-fechar-issue.sh` com os casos novos ok e `0 falha(s)`

### 5. verificar: `--raiz` separa onde a mutação roda [tipo: implementar]
atende: D12, D13
arquivos: `scripts/estado.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/testa-estado.sh`, `skills/verificar/SKILL.md`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `const raizCodigo = flagRaizCodigo || RAIZ;`
  para: `const raizCodigo = RAIZ;`
  bateria: `bash scripts/testa-estado.sh`
  timeout: `900000`
  fixture: `testa-estado.sh, caso "413 verificar --raiz roda a mutacao na arvore do codigo"`
pronto quando: com um estado e um plano em `RFM_ESTADO_ROOT=<A>` (de `mktemp -d`) cuja tarefa muta `src/x.sh`, que só existe numa segunda árvore `<B>` com a bateria, `node scripts/estado.cjs marcar --slug <s> --estagio verificar --status ok --raiz <B> --json '{…}'` roda a catraca contra `<B>` e passa; o mesmo sem `--raiz` sai 2 como hoje; `--raiz <inexistente>` sai 2 com mensagem nomeando a flag; o JSON do estado depois do `marcar` não contém o caminho `<B>`. `estado.cjs` repassa `--raiz-codigo <B>` ao `conferir-fluxo.cjs mutacoes`, e `raizTarefa` passa a ser `path.resolve(raizCodigo, raiz:)` ou `raizCodigo`; `skills/verificar/SKILL.md` diz quando passar a flag — provado por `bash scripts/testa-estado.sh` com o caso novo ok e `0 falha(s)`

### 6. desligar gate só por variável e config [tipo: implementar]
atende: D8, D9, D10, D11
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/gate-git-verificacao.cjs`, `hooks/gate-staging-total.cjs`, `hooks/gate-verificador-staged.cjs`, `hooks/gate-agente-em-voo.cjs`, `hooks/gate-repo-alheio.cjs`, `hooks/gate-worktree.cjs`, `hooks/gate-publicacao-destino.cjs`, `hooks/gate-mensagem-commit.cjs`, `hooks/gate-subagente-sem-instalar.cjs`, `hooks/lib/config.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-git-verificacao.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-repo-alheio.sh`, `hooks/testa-gate-agente-em-voo.sh`, `hooks/testa-gate-commit.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `hooks/testa-gate-verificador-staged.sh`, `hooks/testa-fuga-de-escotilha.sh`, `hooks/testa-config.sh`, `hooks/testa-gate-subagente-sem-instalar.cjs`, `docs/travas-mecanicas.md`, `README.md`, `.gitignore`, `hooks/hooks.json`
depende de: 3, 4
paralela: nao
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `hooks/gate-git-verificacao.cjs`
  de: `if (ehSubagente) return mensagemSemEscotilha(motivo, dir);`
  para: `if (false) return mensagemSemEscotilha(motivo, dir);`
  bateria: `bash hooks/testa-fuga-de-escotilha.sh`
  fixture: `testa-fuga-de-escotilha.sh, caso "gate-git-verificacao: subagente nao ve RAINFOREST_GATE_OFF"`
pronto quando: com o arquivo `.rainforest-gate-off` presente na raiz de um repo de `mktemp -d`, o payload PreToolUse real que cada um dos nove gates barra continua saindo 2 (um caso negativo por gate nas baterias listadas); com `RAINFOREST_GATE_OFF=1` no ambiente, os mesmos saem 0; `grep -rn "rainforest-gate-off" hooks/*.cjs hooks/lib/*.cjs` não devolve leitura de arquivo (só, se houver, comentário histórico); nenhuma mensagem de bloqueio contém `.rainforest-gate-off`; com `agent_id` no payload, o stderr do `gate-git-verificacao` não contém `RAINFOREST_GATE_OFF`; o `gate-subagente-sem-instalar` deixa passar Write de `.rainforest-gate-off` e segue barrando `export RAINFOREST_GATE_OFF=1` de subagente; emenda da revisão: sem a trava do arquivo, o matcher do `gate-subagente-sem-instalar` em `hooks/hooks.json` fica só em `Bash|PowerShell` — provado pelas baterias listadas em `arquivos:` com `0 falha(s)` cada, e por `grep -rn "rainforest-gate-off" hooks/*.cjs README.md docs/travas-mecanicas.md`

### 7. resolvedor de pastas de docs e estado lendo o caminho real [tipo: implementar]
atende: D1, D2, D3, D6
arquivos: `hooks/lib/pastas-docs.cjs`, `scripts/pastas-docs.cjs`, `scripts/testa-pastas-docs.sh`, `hooks/lib/config.cjs`, `scripts/estado.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/conferir-prova.cjs`, `scripts/semear.cjs`, `scripts/testa-semear.sh`, `scripts/baterias-obrigatorias.txt`, `scripts/testa-estado.sh`, `scripts/testa-estado-territorio.sh`, `scripts/testa-conferir-fluxo.sh`, `scripts/desvio-do-plano.cjs` (emenda da revisão 5: o desvio vindo da main lia o plano em caminho fixo)
depende de: 3, 5
paralela: nao
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `hooks/lib/pastas-docs.cjs`
  de: `if (tipo === 'mapas' && existe(raiz, 'docs/legado/COBERTURA.md')) return 'docs/legado';`
  para: `if (false) return 'docs/legado';`
  bateria: `bash scripts/testa-pastas-docs.sh`
  fixture: `testa-pastas-docs.sh, caso "mapas adota docs/legado com COBERTURA"`
pronto quando: num repo de `mktemp -d` com `docs/legado/COBERTURA.md` (cabeçalho `| Fatia | Fontes cobertos | Demanda | Data |`) e `docs/plans/2026-01-01-x-design.md`, `node scripts/pastas-docs.cjs caminho --tipo mapas --raiz <repo>` imprime `docs/legado`, `--tipo design --slug s` imprime `docs/plans/s-design.md` e `--tipo planos --slug s` imprime `docs/plans/s-plano.md`; num repo vazio imprimem `docs/rainforest/mapas`, `docs/rainforest/design/s.md` e `docs/rainforest/planos/s.md`; com `.rainforest/config.json` `{"pastas":{"design":"doc/arq"}}`, `--tipo design --slug s` imprime `doc/arq/s-design.md`; `{"pastas":{"design":"../fora"}}` é rejeitado pelo `validarTipo` e cai no padrão; `docs/plans/` só com `README.md` não é adotado; `estado.cjs marcar --estagio plano` com design gravado como `{"doc":"docs/plans/s-design.md"}` acha o design lá (D3); `semear.cjs` num repo com `docs/legado/COBERTURA.md` traz as linhas dela em `mapas` (emenda da integração: as baterias que copiam `estado.cjs`/`conferir-fluxo.cjs` para sandbox passam a copiar também `hooks/lib/pastas-docs.cjs` e o que ele exige, senão saem com MODULE_NOT_FOUND) — provado por `bash scripts/testa-pastas-docs.sh`, `bash scripts/testa-estado.sh`, `bash scripts/testa-estado-territorio.sh`, `bash scripts/testa-conferir-fluxo.sh` e `bash scripts/testa-semear.sh` com `0 falha(s)` cada

### 8. skills, agente e comandos usam a pasta resolvida [tipo: docs]
atende: D4, D5
arquivos: `skills/arqueologia/SKILL.md`, `agents/arqueologo.md`, `commands/arqueologia.md`, `skills/brainstorm/SKILL.md`, `commands/brainstorm.md`, `skills/plano/SKILL.md`, `skills/executar/SKILL.md`, `skills/revisar/SKILL.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: texto de skill e agente, sem comportamento executável a inverter; a falsificação é o texto mandar rodar o comando que a tarefa 7 criou e a regra de COBERTURA casar com D4
pronto quando: com o repo como fica depois da tarefa 7, cada um dos oito arquivos manda obter o caminho por `node scripts/pastas-docs.cjs caminho --tipo <t> [--slug <s>]` em vez de fixar `docs/rainforest/{mapas,design,planos}`; o `agents/arqueologo.md` tem a condição de parada "escreve só na pasta de mapas que `pastas-docs.cjs` devolve"; `skills/arqueologia/SKILL.md` diz que em `docs/legado/` a linha do `COBERTURA.md` é uma por fatia nas quatro colunas de lá e o detalhe por bloco fica no mapa, e que fora disso vale a tabela de 6 colunas atual (D4); o comando rodado literalmente em cada skill imprime caminho neste repo — provado por `grep -rnE "docs/rainforest/(mapas|design|planos)" skills/arqueologia skills/brainstorm skills/plano skills/executar skills/revisar agents/arqueologo.md commands/arqueologia.md commands/brainstorm.md` sem linha que prescreva o caminho fixo (exemplos históricos marcados como tal ficam) e por `node scripts/pastas-docs.cjs caminho --tipo design --slug x` imprimindo `docs/rainforest/design/x.md` neste repo

### 10. visibilidade-repo declarada para remoto fora do GitHub [tipo: implementar]
atende: D22, D23
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/lib/config.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `hooks/testa-config.sh`
depende de: 6
paralela: nao
prova-na-base: verde — a bateria existe na base e passa; os casos que medem a tarefa ainda nao existem nela, e entram com a entrega
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (visibilidade === "desconhecida" && declaradaPrivada(gitTop)) achados = achados.filter((a) => a.id !== "termo-privado");`
  para: `if (false) achados = achados.filter((a) => a.id !== "termo-privado");`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: `testa-gate-publicacao-destino.sh, caso "419 visibilidade-repo privada libera termo privado com remoto sem gh"`
pronto quando: num repo de `mktemp -d` com `origin` apontando para um host que o `gh` não resolve (ou com `RAINFOREST_GATE_SEM_REDE=1`), termo da lista privada de teste no conteúdo e `.rainforest/config.json` com `{"visibilidade-repo":"privada"}` na raiz do principal, o payload PreToolUse real de Write de um `.md` versionado sai 0 — também a partir de um worktree linkado; sem a chave, sai 2; com a chave e um telefone mascarado no mesmo conteúdo, sai 2 com `telefone`; com `{"visibilidade-repo":"publica"}` a chave é inválida e sai 2; a mensagem de bloqueio de `desconhecida` cita `visibilidade-repo` — provado por `bash hooks/testa-gate-publicacao-destino.sh` e `bash hooks/testa-config.sh` com os casos novos ok e `0 falha(s)`

### 9. versão 1.46.0 [tipo: configurar]

(Emenda da integração: a origin/main publicou 1.45.0 durante o fluxo; esta entrega sobe para 1.46.0.)
atende: D21
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 7, 8, 10
paralela: nao
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
pronto quando: com o repo integrado, `node scripts/conferir-versao.cjs` sai 0 com 1.46.0 em todos os manifestos, o `CHANGELOG.md` tem a entrada 1.46.0 citando #409, #410, #411, #412, #413, #414, #417, #419 e a retirada do append do sec-default, e `claude plugin validate .claude-plugin/plugin.json` sai 0 — provado pelos dois comandos
