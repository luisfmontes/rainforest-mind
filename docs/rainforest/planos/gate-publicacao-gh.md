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
  - heredoc que cria o arquivo: o comando é a string `"cat > novo.md <<'EOF' && gh pr create --title t --body-file novo.md\nx termo702\nEOF"` (com `\n` sendo quebra de linha real), e `novo.md` não existe no cwd;
  - `gh issue comment 5 --body-file corpo.md`;
  - `gh pr comment 5 -b termo702`;
  - `gh pr merge 5 --squash --body termo702`;
  - `gh pr merge 5 -s --body termo702` (`-s` é `--squash`, booleana: não pode engolir o `--body`);
  - `gh pr merge 5 -t termo702` (`-t` é `--subject` no `merge`);
  - `gh issue create --title t --body-file corpo2.md` com `corpo2.md` cuja 1ª linha é `rainforest-gate: dados-de-exemplo` e a 2ª tem `termo702` (D5: sem isenção de marcador);
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
- **Laço sobre os segmentos.** Para cada segmento de `segmentosParaGate(mascararCorposDeHeredoc(cmd))`:
  - A máscara (`hooks/lib/heredoc.cjs`) vem antes porque `segmentosParaGate` sobre comando com heredoc cola no último token o último caractere do delimitador. Medido: `--body-file novo.md` vira `novo.mdF`.
  - Tokeniza com `tokensComAspas(segmento)` (tokens `{ v }`).
  - Acha o primeiro token cujo executável normalizado é `gh` (`normalizarExecutavel` de `hooks/lib/heredoc.cjs`).
  - Lê família e verbo como os dois primeiros tokens depois dele que não começam com `-`. Uma flag antes deles só pula o token seguinte se for `--repo` ou `-R`.
  - Só segue se o par está em `{issue: create|comment|edit, pr: create|comment|edit|review|merge}`, com família e verbo em minúsculas.
- **Textos (D2).** Percorre os tokens depois do verbo, em ordem, por índice:
  - token que não começa com `-` é ignorado (posicional);
  - a chave da flag longa vai em minúsculas até o `=`; a curta é `tok.slice(0, 2)`, com caixa;
  - o valor fica na mesma palavra (`--x=v`, `-bx`, `-b=v`) ou no token seguinte, e nesse caso o índice avança 2, então o valor nunca é testado como flag;
  - `--body`/`-b`, `--title`, e `-t`, dão `{ origem: <flag como escrita>, texto: <valor> }`. O `-t` é `--title` fora do `merge` e `--subject` no `merge`, e o `--subject` só existe no `merge`;
  - valor com `$(` ou crase é ignorado (D3);
  - `--body-file`/`-F` com valor que contém `$` ou crase, ou igual a `-`, é ignorado;
  - fora disso, o caminho passa por `normalizarMsys` (`hooks/lib/cwd-efetivo.cjs`) e, se relativo, resolve contra `cwdDoEvento`;
  - arquivo legível dá `{ origem: "--body-file <valor>", texto: <conteúdo> }`;
  - com `ENOENT`, cada corpo de heredoc do comando ORIGINAL (`posicoesDeOperadorHeredoc(cmd)` + `corpoDeHeredoc(cmd, pos).corpo`) dá `{ origem: "heredoc", texto }`;
  - outros erros de leitura: ignorado;
  - `--repo`/`-R` guardam o valor em `repoAlvo` do segmento (a tarefa 2 o usa; nesta tarefa ele só é lido);
  - outra flag consome o token seguinte **só** se estiver no conjunto de flags de valor do verbo, e flag fora do conjunto é booleana.
- **Flags de valor, por verbo.** Constante de módulo `FLAGS_GH_VALOR` (objeto de `Set`).
  - **Longas**, sem caixa, em todos os verbos: `--repo`, `--title`, `--body`, `--body-file`, `--subject`, `--base`, `--head`, `--label`, `--assignee`, `--milestone`, `--project`, `--reviewer`, `--template`, `--add-label`, `--remove-label`, `--add-assignee`, `--remove-assignee`, `--add-project`, `--remove-project`, `--add-reviewer`, `--remove-reviewer`, `--author-email`, `--match-head-commit`.
  - **Curtas**, com caixa, sempre: `-R`, `-b`, `-F`.
  - **Curtas a mais por verbo:**
    - `create`: `-t`, `-a`, `-l`, `-m`, `-p`, `-T`, `-B`, `-H`, `-r`;
    - `edit`: `-t`, `-m`, `-B`;
    - `merge`: `-t`, `-A`;
    - `comment` e `review`: nenhuma.

    No `merge`, `-s`, `-m`, `-r` e `-d` são booleanas. No `review`, `-a`, `-c` e `-r` são booleanas.
- **Sem texto, nada a conferir.** Sem nenhum texto em nenhum segmento, `conferirGh` retorna sem consultar visibilidade.
- **Achados e visibilidade, por segmento.** Com texto no segmento, os achados são `conferirConteudo(texto)` de cada texto, cada achado anotado com `origem`. Havendo achado, decide a visibilidade daquele segmento, e o primeiro segmento com achado que sobrar barra. Nesta tarefa a visibilidade é `visibilidadeDoRepo(gitTop)`, com `gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"])`, e sem `gitTop` o segmento passa. A tarefa 2 troca essa linha pela do `repoAlvo`. Com a visibilidade:
  - `privada`: retorna;
  - `desconhecida` com `declaradaPrivada(gitTop)`: filtra `termo-privado`;
  - sobrando achado: escreve no stderr `mensagemBloqueioGh(achados, familia, verbo, ehSubagente, visibilidade)` e sai 2.
- **`mensagemBloqueioGh`** é função nova:
  - abre com `BLOQUEADO pelo gate de publicação do rainforest-mind.` e `Comando: gh <familia> <verbo>`;
  - lista cada achado com `[<id>]`, a origem e o `o_que`/`faca`;
  - traz a frase literal `O GitHub guarda o histórico de edição de Issue e PR: corrigir depois não apaga o texto publicado.`;
  - termina com o mesmo bloco `saidas` (subagente / janela principal) de `mensagemBloqueio`, extraído para uma função `textoDeSaidas(ehSubagente)` que as duas mensagens chamam. O bloco fica em `hooks/gate-publicacao-destino.cjs`, `const saidas = ehSubagente ? ...` dentro de `mensagemBloqueio`. O parágrafo `ATENÇÃO — PreToolUse aborta...` não entra na mensagem nova.
- **Bateria:** seção nova `#702` no fim de `hooks/testa-gate-publicacao-destino.sh`, imediatamente antes das linhas finais `echo`, `echo "== resultado: ..."` e `[ "$falhou" = 0 ]`.
  - Reusa `$SANDBOX_BIN/gh`, `$SANDBOX_BIN/gh-por-nome` e `$GH_INVOCATIONS`, já definidos antes no arquivo.
  - Monta `R702="$RAIZ/r702"` com `git init` e remoto `https://github.com/dono/publico.git`, e `H702="$RAIZ/home702"` com `termo702` em `$H702/.rainforest/termos-proibidos.txt`.
  - `D702="$RAIZ/dados702"` é o `RFM_ROOT`. Antes de cada caso roda `rm -f "$D702/cache-visibilidade-repo.json"`, para a resposta pública cacheada de um caso não valer no seguinte.
  - O payload sai de um helper `pay702 <tool_name> <cwd> <command>` em `node -e` com os valores em `argv`: `{cwd, hook_event_name: "PreToolUse", tool_name, tool_input: {command}}`. Nunca por printf.
  - A medição é um helper `confere702 "<nome>" <exit esperado> <GH_RESPONSE> <tool_name> <cwd> <command>`. Ele roda o gate com `env HOME="$H702" RFM_ROOT="$D702" GH_RESPONSE=... RAINFOREST_GH="node $SANDBOX_BIN/gh" GH_INVOCATIONS_FILE="$GH_INVOCATIONS"` e soma em `ok`/`falhou`. Imprime `  ok   702 <nome>` ou `  FALHA 702 <nome>: esperava X, veio Y` mais as 10 primeiras linhas do stderr.
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
- (c) cwd fora de repositório git (`$RAIZ/sem-git`, a variável `FORA` do topo da bateria) e `gh issue create --repo=dono/publico --title termo702 --body x`: exit 2.
- (d) cwd fora de repositório git, sem `--repo`, com o mesmo título: exit 0.
- (e) `--repo https://github.com/dono/publico` a partir de cwd privado: exit 2.
- (f) `--repo $R` a partir de cwd privado, com o termo no título: exit 2 (destino `desconhecida`).

Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0, e cada caso nomeado `702 ...` na saída.

Forma prescrita:
- Os casos usam `confere702` com `RAINFOREST_GH="node $SANDBOX_BIN/gh-por-nome"` no lugar do dublê de `GH_RESPONSE`. Um segundo repositório `R702P` tem remoto `https://github.com/dono/priv.git`.
- O `repoAlvo` que a tarefa 1 já lê na mesma passada de tokens é normalizado para `owner/repo`:
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
- a versão sobe de `2.13.2` para `2.13.3` em `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json`; se a `origin/main` já estiver em `2.13.3` ou mais na hora, a versão é o próximo PATCH livre acima dela, e o resto deste critério lê esse número no lugar de `2.13.3`;
- o badge da linha 7 do `README.md` troca `2.13.2` por `2.13.3` nas duas ocorrências (`vers%C3%A3o-2.13.2` e `alt="versão 2.13.2"`);
- o `CHANGELOG.md` ganha, no topo, a seção `## 2.13.3 — 2026-11-13`, que cita a #702 e os verbos do D1;
- a linha `gate-publicacao-destino.cjs` da tabela de hooks do README passa a citar o título e o corpo de `gh issue`/`gh pr`.

Provado por `node scripts/conferir-versao.cjs` com exit 0 (ele só confere que a versão declarada é maior que a da `origin/main`; exit 2 quer dizer bump faltando), `grep -c "2.13.3" README.md` devolvendo 2 ou mais, e `grep -n "2.13.3" CHANGELOG.md .claude-plugin/plugin.json .codex-plugin/plugin.json` com uma linha por arquivo.
