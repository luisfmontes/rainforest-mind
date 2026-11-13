# Plano: gate-publicacao confere o texto de `gh issue`/`gh pr` (#702)

Design: docs/rainforest/design/gate-publicacao-gh.md

## O que não pode quebrar
- `Write`/`Edit`/`MultiEdit` e `git commit` continuam como hoje: os casos existentes de `hooks/testa-gate-publicacao-destino.sh` seguem verdes.
- Comando `Bash`/`PowerShell` que não é `gh` de escrita de texto sai do novo trecho sem consultar `gh repo view` (sem custo de rede por comando).
- Repositório privado continua passando, e `desconhecida` continua barrando.

## Tarefas

### 1. Conferir título e corpo de `gh issue`/`gh pr` no Bash e no PowerShell [tipo: implementar]
atende: D1, D2, D3, D5, D6
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- repo | grep -n "function extrairCorpoDoPR\|FLAGS_CORPO" hooks/gate-fechar-issue.cjs | o parse de flags de corpo mora no gate-fechar-issue (:612-756), que está em mudança no fluxo gate-segmentador (#689); a lógica se reescreve aqui
- repo | grep -n "segmentosParaGate" hooks/*.cjs | exportado por gate-subagente-sem-gh.cjs e já usado por gate-matar-por-nome e gate-subagente-sem-instalar
- repo | grep -n "corpoDeHeredoc\|posicoesDeOperadorHeredoc" hooks/lib/heredoc.cjs | exportados
desfecho: compor
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (nome === "Bash" || nome === "PowerShell") conferirGh(ev, cwdDoEvento, agente);`
  para: `if (false) conferirGh(ev, cwdDoEvento, agente);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 issue create --body-file com termo em repo publico barra"`
prova: `grep -q "function conferirGh" hooks/gate-publicacao-destino.cjs`
pronto quando: payload real de PreToolUse, `HOME` de areia com o termo `termo702` na lista privada, repositório com remoto GitHub e o dublê `gh` da bateria:
- (a) `tool_name: "Bash"`, `gh issue create --title t --body-file corpo.md` com `corpo.md` (no cwd) contendo `termo702`, `GH_RESPONSE='{"isPrivate":false}'`: exit 2, e o stderr traz `[termo-privado]` e `Comando: gh issue create`.
- (b) com `GH_RESPONSE='{"isPrivate":true}'`: exit 0.
- (c) exit 2 no repositório público para cada forma:
  - `--body "x termo702"`;
  - `--title "termo702"`;
  - `-F corpo.md`;
  - `--body-file=corpo.md`;
  - caminho absoluto;
  - `cat > novo.md <<'EOF'` com o termo no heredoc, seguido de `&& gh pr create --body-file novo.md` (arquivo inexistente);
  - `gh issue comment 5 --body-file corpo.md`;
  - `gh pr comment 5 -b termo702`;
  - `gh pr merge 5 --squash --body termo702`;
  - `gh pr review 5 --comment -b termo702`;
  - `gh issue edit 5 --title termo702`;
  - o caso (a) com `tool_name: "PowerShell"`.
- (d) exit 0 no repositório público para:
  - `gh issue view 12`;
  - `gh pr list`;
  - `gh issue create --title t --body-file $f`;
  - `gh issue create --title t --body "$(cat x)"`;
  - `gh issue create --title ok --body limpo`;
  - `cd /pasta/termo702 && gh issue create --title ok --body limpo` (o termo só no caminho do `cd`).
- (e) o caso (d) `gh issue view 12` não grava invocação `repo view` no `GH_INVOCATIONS_FILE`.

Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `== resultado: N ok, 0 falha(s) ==` e exit 0, e cada caso acima nomeado `702 ...` na saída.

Forma prescrita:
- **Função nova de módulo `conferirGh(ev, cwdDoEvento, agente)`**, chamada em `main()` pela linha exata `if (nome === "Bash" || nome === "PowerShell") conferirGh(ev, cwdDoEvento, agente);`, colocada logo ANTES da linha que chama `conferirCommit`. Ela retorna (sem `process.exit`) quando não há achado, para o `conferirCommit` seguir. Barra com `process.exit(2)`.
- **Laço sobre os segmentos.** Para cada segmento de `segmentosParaGate(cmd)`:
  - tokeniza com `tokensComAspas(segmento)` (tokens `{ v }`);
  - acha o primeiro token cujo executável normalizado é `gh` (`normalizarExecutavel` de `hooks/lib/heredoc.cjs`);
  - lê família e verbo como os dois primeiros posicionais depois dele, pulando flags (a de valor pula também o token seguinte, pela lista `FLAGS_GH_VALOR` abaixo);
  - só segue se o par está em `{issue: create|comment|edit, pr: create|comment|edit|review|merge}`, com família e verbo em minúsculas.
- **Textos (D2).** Do resto dos tokens:
  - a chave da flag longa vai em minúsculas até o `=`; a curta é `tok.slice(0, 2)`, com caixa;
  - valor no token seguinte, depois de `=` ou colado à curta (`-bx`, `-b=x`);
  - `--title`/`-t`, `--body`/`-b` e `--subject` (o `-s` só no verbo `merge`) dão `{ origem: <flag>, texto: <valor> }`, e valor com `$(` ou crase é ignorado (D3);
  - `--body-file`/`-F` com valor que contém `$` ou crase, ou igual a `-`, é ignorado;
  - fora disso, o caminho passa por `normalizarMsys` (`hooks/lib/cwd-efetivo.cjs`) e, se relativo, resolve contra `cwdDoEvento`;
  - arquivo legível dá `{ origem: "--body-file <valor>", texto: <conteúdo> }`;
  - com `ENOENT`, cada corpo de heredoc do comando INTEIRO (`posicoesDeOperadorHeredoc(cmd)` + `corpoDeHeredoc(cmd, pos).corpo`) dá `{ origem: "heredoc", texto }`;
  - outros erros de leitura: ignorado.
- **`FLAGS_GH_VALOR`** é um `Set` local com `--repo`, `-R`, `--title`, `-t`, `--body`, `-b`, `--body-file`, `-F`, `--base`, `-B`, `--head`, `-H`, `--label`, `-l`, `--assignee`, `-a`, `--milestone`, `-m`, `--project`, `-p`, `--reviewer`, `-r`, `--template`, `-T`, `--subject`, `-s`, `--add-label`, `--remove-label`, `--add-assignee`, `--remove-assignee`.
- **Sem texto, nada a conferir.** Sem nenhum texto em nenhum segmento, `conferirGh` retorna sem consultar visibilidade.
- **Achados e visibilidade.** Com texto, os achados são `conferirConteudo(texto)` de cada texto, cada achado anotado com `origem`. Havendo achado, a visibilidade vem de `visibilidadeDoGh(...)` (tarefa 2; nesta tarefa, `visibilidadeDoRepo(gitTop)` com `gitTop` do `cwdDoEvento`, e sem `gitTop` retorna):
  - `privada`: retorna;
  - `desconhecida` com `declaradaPrivada(gitTop)`: filtra `termo-privado`;
  - sobrando achado: escreve no stderr `mensagemBloqueioGh(achados, familia, verbo, ehSubagente, visibilidade)` e sai 2.
- **`mensagemBloqueioGh`** é função nova:
  - abre com `BLOQUEADO pelo gate de publicação do rainforest-mind.` e `Comando: gh <familia> <verbo>`;
  - lista cada achado com `[<id>]`, a origem e o `o_que`/`faca`;
  - diz que o GitHub guarda o histórico de edição de Issue e PR, então corrigir depois não apaga;
  - reaproveita o texto de saídas (subagente / janela principal) da `mensagemBloqueio` atual, sem o parágrafo de `git add`.
- **Bateria:** seção nova `#702` no fim de `hooks/testa-gate-publicacao-destino.sh`, antes do placar.
  - Repositório `R702` com remoto `https://github.com/dono/publico.git`, `HOME` de areia `H702` com `termo702` em `.rainforest/termos-proibidos.txt` e `RFM_ROOT` de areia própria (cache de visibilidade limpo).
  - Payload por `node` com valores em `argv` (`{cwd, hook_event_name: "PreToolUse", tool_name, tool_input: {command}}`), nunca por printf.
  - O dublê `gh` existente com `GH_RESPONSE`.
  - Nenhum caso afirma sobre o texto do fonte.

### 2. Destino pelo `--repo` [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 1
busca:
- repo | grep -n "function visibilidadeDeUmRepo\|function calcularVisibilidade" hooks/gate-publicacao-destino.cjs | visibilidade por owner/repo já existe (:177), e o RAINFOREST_GATE_SEM_REDE só é lido em calcularVisibilidade (:161)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `const vis = repoAlvo ? visibilidadeDoAlvo(repoAlvo) : visibilidadeDoRepo(gitTop);`
  para: `const vis = visibilidadeDoRepo(gitTop);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 --repo dono/publico a partir de cwd privado barra"`
prova: `grep -q "function visibilidadeDoAlvo" hooks/gate-publicacao-destino.cjs`
pronto quando: payload real de PreToolUse `Bash` com o dublê `gh-por-nome` da bateria, que responde `isPrivate: true` só para repositório terminado em `/priv`:
- (a) cwd num repositório com remoto `dono/priv` e `gh issue create --repo dono/publico --title termo702 --body x`: exit 2.
- (b) cwd num repositório com remoto `dono/publico` e `gh issue create -R dono/priv --title termo702 --body x`: exit 0.
- (c) cwd fora de repositório git e `gh issue create --repo=dono/publico --title termo702 --body x`: exit 2.
- (d) cwd fora de repositório git, sem `--repo`, com o mesmo título: exit 0.
- (e) `--repo https://github.com/dono/publico` a partir de cwd privado: exit 2.
- (f) `--repo $R` a partir de cwd privado, com o termo no título: exit 2 (destino `desconhecida`).

Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0, e cada caso nomeado `702 ...` na saída.

Forma prescrita:
- `conferirGh` lê o `--repo`/`-R` do segmento (o token seguinte, `--repo=`, ou o colado ao `-R`) e normaliza para `owner/repo`:
  - URL `https://github.com/o/r(.git)` vira `o/r`;
  - valor com `$` ou crase vira o marcador `"?"`.
- A linha exata `const vis = repoAlvo ? visibilidadeDoAlvo(repoAlvo) : visibilidadeDoRepo(gitTop);` decide a visibilidade.
- `visibilidadeDoAlvo(ownerRepo)` é função nova:
  - devolve `desconhecida` se `ownerRepo === "?"` ou se `RAINFOREST_GATE_SEM_REDE === "1"`;
  - senão devolve `visibilidadeDeUmRepo(ownerRepo)`.
- Sem `repoAlvo` e sem `gitTop`, retorna sem achado.
- O filtro de `declaradaPrivada(gitTop)` só se aplica quando `repoAlvo` é nulo.

### 3. Versão 2.13.3, CHANGELOG e README [tipo: docs]
atende: D7
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 1, 2
mutacao: n/a
  motivo: tarefa só de texto e número de versão, sem comportamento a inverter
pronto quando: com o diff da branch, o número da versão e a descrição batem com o design:
- `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` devolve `2.13.3`;
- a seção `2.13.3` do `CHANGELOG.md` cita a #702 e os verbos do D1;
- a linha `gate-publicacao-destino.cjs` da tabela do README cita o título e o corpo de `gh issue`/`gh pr`.

Provado por `node scripts/conferir-versao.cjs` e `grep -n "2.13.3" CHANGELOG.md .claude-plugin/*.json`.
