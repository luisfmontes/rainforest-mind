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
  timeout: `900000`
  timeout: `1200000`
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
  de: `if (r.repoFlag) return [{ repo: r.repoFlag }];`
  para: `if (false) return [{ repo: r.repoFlag }];`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
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

### 4. Destino pelo cwd do segmento [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 2
busca:
- repo | grep -n "function cwdPorSegmento" hooks/lib/cwd-efetivo.cjs | cwd por segmento já existe (:660) e serve o gate-fechar-issue
desfecho: compor
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `const mapas = origens.map((o) => ({ o, mapa: cwdPorSegmento(texto, o.cwd, ps) }));`
  para: `const mapas = origens.map((o) => ({ o, mapa: [{ seg: texto, cwd: o.cwd, incerto: false }] }));`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 cd para repo publico antes do gh barra"`
prova-na-base: verde — emenda depois do executar: o código de base já é o da tarefa 1, e a prova é a mutação acima
pronto quando: payload real de PreToolUse `Bash` com o dublê `gh-por-nome`. A partir do repositório privado, `cd <repo público> && gh issue create --title termo702 --body x` sai 2. A partir do público, `cd <repo privado> && ...` sai 0. `cd $X && ...` com o termo sai 2: cwd incerto e sem `--repo`, falha fechada. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Emenda de 2026-11-13: a revisão de segurança automática do commit apontou que o destino era lido do cwd do evento, e um `cd` antes do `gh` publicava noutro repositório. É o D4 ("repositório git do `cwd`") lido pelo cwd em que o `gh` de fato roda.

### 5. Destino pelo `GH_REPO` [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 4
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (prefixo.length && r.prefixoLimpo) return prefixo;`
  para: `if (false) return prefixo;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 GH_REPO privado no prefixo libera cwd publico"`
prova-na-base: verde — emenda depois do executar: o código de base já é o da tarefa 1, e a prova é a mutação acima
pronto quando: payload real de PreToolUse com o dublê `gh-por-nome`, todos com o termo no título:
- `GH_REPO=dono/publico gh issue create ...` a partir do repositório privado sai 2.
- `export GH_REPO=dono/priv; gh issue create ...` a partir do privado sai 0. A partir do público sai 2, porque uma menção antes do segmento entra AO LADO do cwd e só aperta: quem lê o texto não sabe se a atribuição chega ao `gh`.
- `echo GH_REPO=dono/priv; gh issue create ...` a partir do público sai 2.
- `GH_REPO=dono/priv GH_REPO=dono/publico gh issue create ...` sai 2: com prefixo repetido, o pior destino decide.
- `GH_REPO=dono/priv gh issue create ...` a partir do público sai 0: prefixo de atribuição pura manda sozinho. Com `env -u X GH_REPO=dono/priv gh ...` sai 2, porque wrapper antes do `gh` faz o prefixo virar só mais um destino.
- Com `GH_REPO=dono/publico` no ambiente da sessão, `export GH_REPO=dono/priv; gh issue create ...` a partir do privado sai 2: o ambiente entra junto das menções.
- `cd <privado> && gh ... --body-file corpo.md; cd <público> && gh ... --body-file corpo.md`, com o termo só no `corpo.md` do público, sai 2: o arquivo se lê contra cada cwd do segmento repetido (terceira revisão de segurança).
- `gh issue create ...; export GH_REPO=dono/priv` a partir do público sai 2, porque a atribuição depois do `gh` não conta.
- No PowerShell, `$env:GH_REPO = "dono/publico"; gh issue create ...` a partir do privado sai 2.

Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Segunda revisão de segurança (2026-11-13). Menção que não chega ao `gh` liberava o cwd público, e segmento de texto repetido usava só a primeira ocorrência. Desde então todos os destinos possíveis são conferidos e o pior decide. A tarefa 4 confere todas as ocorrências do segmento (caso `segmento gh repetido em cwd privado e publico barra`).

Emenda de 2026-11-13, mesma origem da tarefa 4. O `gh` usa `GH_REPO` como `--repo` quando a flag falta, então ele entra na mesma precedência do D4: `--repo` primeiro, depois `GH_REPO`.

### 6. Segmentação crua e wrappers de string [tipo: implementar]
atende: D1, D2
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 5
busca:
- repo | grep -n "function desempacotarWrapperDeString" hooks/lib/tokens-comando.cjs | desempacota bash -c, sh -c, eval e powershell -Command (:841)
desfecho: compor
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `    empilhar(cmd, 0);`
  para: `    empilhar(mascarado, 0);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 GH_REPO privado no prefixo depois de heredoc passa em cwd publico"`
prova-na-base: verde — emenda da revisão 1: a base já é o código das tarefas 1 a 5, e a prova é a mutação acima
pronto quando: payload real de PreToolUse `Bash`, repositório público:
- `cat > n.md <<'EOF'` + `limpo` + `EOF` + `gh issue create --title termo702 --body x`, em linhas separadas, sai 2;
- `bash -c "gh issue create --title t --body termo702"`, `sh -c '...'` e `eval "..."` saem 2;
- `{ gh issue create --title termo702 --body x; }` num repositório privado sai 2. O `cwdPorSegmento` marca grupo como incerto, e esse é o preço aceito da falha fechada.
- emenda da revisão 2: num repositório público, `cat > n.md <<'EOF'` + `limpo` + `EOF` + `GH_REPO=dono/priv gh issue create --title termo702 --body x` sai 0 (o `gh` achado pela segmentação crua vai para o privado; sem ela, a rede da tarefa 9 barraria pelo cwd).

Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Forma prescrita:
- `conferirGh` segmenta o comando CRU, por uma função local `empilhar(texto, profundidade)`. Para cada segmento de `segmentosParaGate(texto)`, ela guarda o segmento e, até a profundidade 4, empilha o `interno` de `desempacotarWrapperDeString(seg.trim(), { ferramenta })`.
- `cwdPorSegmento` roda sobre o comando cru.
- `cwdsDoSegmentoGh` repassa o `incerto` do `cwdPorSegmento` sem reinterpretar.

### 7. Texto literal, corpos embutidos e close/reopen --comment [tipo: implementar]
atende: D1, D2, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 6
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  const textos = [{ origem: "comando", texto: cmdOriginal }];`
  para: `  const textos = [];`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 printf em pipe para -F - barra"`
prova-na-base: verde — emenda da revisão 1: a base já é o código das tarefas 1 a 5, e a prova é a mutação acima
pronto quando: payload real de PreToolUse, repositório público, saem 2:
- `--body "$(cat <<'EOF'` + `termo702 aqui` + `EOF` + `)"`;
- `--body 'veja \`termo702\` aqui'`;
- `--body-file -` com heredoc;
- heredoc que reescreve um `--body-file` existente e limpo;
- here-string do PowerShell com `--body-file`;
- `gh pr close 5 --comment termo702`;
- `gh issue reopen 5 -c termo702`.

Saem 0: `gh pr close 5 -c limpo` e `gh pr review 5 -c -b limpo` (`-c` é booleana no `review`). Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Emenda da revisão 2 (Q2 A do Luís, 2026-11-13): o texto conferido passa a ser o comando inteiro (tarefa 8), e a mutação desta tarefa troca de linha. Emenda da revisão 4: com o valor literal das flags de volta (tarefa 13), a fixture passa a ser o texto que só o comando inteiro carrega (`printf` em pipe).

### 8. O comando inteiro conta como texto [tipo: implementar]
atende: D2, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 7
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  const textos = [{ origem: "comando", texto: cmdOriginal }];`
  para: `  const textos = [{ origem: "comando", texto: segmento }];`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 variavel literal no mesmo comando barra"`
prova-na-base: verde — emenda da revisão 2: a base já é o código das tarefas 1 a 7, e a prova é a mutação acima
pronto quando: payload real de PreToolUse, repositório público, saem 2:
- `printf 'termo702' | gh issue comment 3 -F -`;
- `gh issue comment 3 -F - <<< "termo702"`;
- `B="termo702 aqui"; gh issue create --title t --body "$B"`;
- no PowerShell, `$b = @'` + `termo702` + `'@; gh issue create --title t --body $b`;
- `cd <repo público cujo caminho tem termo702> && gh issue create --title ok --body limpo` (falso positivo aceito).

Saem 0: `B="limpo"; gh issue create --title t --body "$B"` e `cd <repo privado cujo caminho tem termo702> && gh issue create --title ok --body limpo`. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Forma prescrita: `textosDoSegmentoGh` abre `textos` com o comando inteiro e acrescenta só o conteúdo legível dos `--body-file`; `corposEmbutidos` e a leitura do valor de `--title`/`--body`/`--subject`/`--comment` saem.

### 9. Rede para o `gh` que a segmentação perde [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 8
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  if (ghTextoSegmentos !== nCru) conferirGhPerdido(cmd, cwdDoEvento, agente, conferirMemo);`
  para: `  if (false) conferirGhPerdido(cmd, cwdDoEvento, agente, conferirMemo);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 apostrofo escapado no bash antes do gh barra"`
prova-na-base: verde — emenda da revisão 2: a base já é o código das tarefas 1 a 7, e a prova é a mutação acima
pronto quando: payload real de PreToolUse, repositório público, saem 2: `echo it` + contrabarra + `'s; gh issue create --title termo702 --body x` no Bash, e o here-string do PowerShell com `it's termo702` seguido de `gh issue create --title t --body-file n.md` na linha de baixo. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Forma prescrita: quando nenhum segmento achou `gh issue|pr` de escrita e o texto cru casa `gh ... issue|pr <verbo>`, o comando inteiro é conferido; os destinos são todo `--repo`/`-R` e `GH_REPO=` do texto, o `GH_REPO` da sessão e o cwd do evento, incerto se o texto tem `cd`, `pushd`, `Set-Location` ou `-C`. O pior decide.

### 10. O `cd` dentro e antes de wrapper [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 9
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `        if (w && w.interno) empilhar(w.interno, profundidade + 1, locais, ehPs(s));`
  para: `        if (w && w.interno) empilhar(w.interno, profundidade + 1);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  timeout: `1200000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 cd antes de bash -c para repo publico barra"`
prova-na-base: verde — emenda da revisão 2: a base já é o código das tarefas 1 a 7, e a prova é a mutação acima
pronto quando: payload real de PreToolUse, a partir de um repositório privado, saem 2 `bash -c "cd <público> && gh issue create --title termo702 --body x"` e `cd <público> && bash -c "gh issue create --title termo702 --body x"`; a partir de um público, sai 0 `bash -c "cd <privado> && gh issue create --title termo702 --body x"`. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

Forma prescrita: cada segmento leva os cwds possíveis; o texto de dentro do wrapper roda o próprio `cwdPorSegmento` a partir de cada cwd do segmento do wrapper.

### 11. URL posicional de Issue ou PR é destino [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 10
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  return r.repoUrls.length ? [...base, ...r.repoUrls.map((repo) => ({ repo }))] : base;`
  para: `  return base;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 URL de Issue publica a partir de cwd privado barra"`
prova-na-base: verde — emenda da revisão 3: a base já é o código das tarefas 1 a 10, e a prova é a mutação acima
pronto quando: payload real de PreToolUse `Bash`, cwd num repositório privado: `gh issue comment https://github.com/dono/publico/issues/3 --body termo702` e `gh pr merge https://github.com/dono/publico/pull/5 --squash --body termo702` saem 2; a URL soma aos destinos e nunca os substitui (revisão de segurança do commit): de um cwd público, `gh issue comment https://github.com/dono/priv/issues/3 --body termo702` e `gh issue create --label https://github.com/dono/priv/issues/1 --title termo702 --body x` saem 2; de um cwd privado, `gh issue comment https://github.com/dono/priv/issues/3 --body termo702` sai 0. Todo posicional depois do verbo é lido por `new URL` (usuário e porta saem antes de olhar o host); com cara de URL do GitHub e ilegível, entra como destino de visibilidade desconhecida: `gh issue close 3 https://github.com/dono/publico/issues/3 --comment termo702` e `gh issue comment https://user@github.com:99999999/x --body termo702`, de um cwd privado, saem 2. A rede da tarefa 9 também soma a URL aos destinos. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 12. Só o termo privado olha o comando inteiro [tipo: implementar]
atende: D2
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 11
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (origem !== "comando" || a.id === "termo-privado") achados.push`
  para: `achados.push`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 --body-file com caminho de home passa"`
prova-na-base: verde — emenda da revisão 3: a base já é o código das tarefas 1 a 10, e a prova é a mutação acima
pronto quando: payload real, repositório público: `gh pr create --title Fix --body-file C:/Users/Fulano/AppData/Local/Temp/x/body.md` e `gh pr merge 5 --squash --author-email fulano@empresa.com.br` saem 0 (a base saía 0); `gh issue create --title termo702 --body x` segue saindo 2. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 13. Valor literal de flag com todos os detectores [tipo: implementar]
atende: D2
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 12
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `      textos.push({ origem: chave, texto: valor });`
  para: `      void valor;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 e-mail no valor de --body ainda barra"`
prova-na-base: verde — emenda da revisão 3: a base já é o código das tarefas 1 a 10, e a prova é a mutação acima
pronto quando: payload real, repositório público: `gh issue create --title t --body 'fale com fulano@empresa.com.br'` sai 2 pelo detector de e-mail, que a origem `comando` não aplica mais. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 14. A rede do gh perdido lê o --body-file [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 13
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `    try { texto = fs.readFileSync(resolvido, "utf8"); } catch {}`
  para: `    try { texto = null; } catch {}`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 gh perdido na segmentacao le o --body-file"`
prova-na-base: verde — emenda da revisão 3: a base já é o código das tarefas 1 a 10, e a prova é a mutação acima
pronto quando: payload real, repositório público, `corpo.md` com `termo702`: `echo it` + contrabarra + `'s; gh issue create --title t -F corpo.md` sai 2. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 15. Apelido new de create [tipo: implementar]
atende: D1
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 14
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `const APELIDOS_GH = { new: "create" };`
  para: `const APELIDOS_GH = {};`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 issue new com e-mail no corpo barra"`
prova-na-base: verde — emenda da revisão 3: a base já é o código das tarefas 1 a 10, e a prova é a mutação acima
pronto quando: payload real, repositório público: `gh issue new --title termo702 --body x` e `gh pr new --title t --body termo702` saem 2 (`gh issue create --help` lista `ALIASES: gh issue new`), e `gh issue new --title t --body 'fale com fulano@empresa.com.br'` sai 2 pelo detector de e-mail, que a rede do `gh` perdido não aplica: sem o apelido, só o termo privado seria pego. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 16. Continuação de linha do PowerShell [tipo: implementar]
atende: D1, D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 15
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  const juntado = juntarContinuacao(ev.tool_name, cmdBruto);`
  para: `  const juntado = cmdBruto;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 continuacao do PowerShell com --repo publico na linha de baixo barra"`
prova-na-base: verde — emenda da revisão 4: a base já é o código das tarefas 1 a 15, e a prova é a mutação acima
pronto quando: payload real de PreToolUse `PowerShell`: de um cwd privado, `gh issue create --title "Fix"` + crase + quebra + `--repo dono/publico --body "termo702"` sai 2 e o mesmo com `--repo dono/priv` sai 0; de um cwd público, `gh issue create --title "Fix"` + crase + CRLF + `--body-file corpo.md` (com `termo702`) sai 2. As duas leituras, com e sem a junção, são conferidas e qualquer uma barra: crase e quebra dentro de aspas simples com `--repo dono/priv` não libera um cwd público (revisão de segurança do commit). Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 17. A rede roda quando a segmentação acha menos gh que o texto [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 16
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  if (ghTextoSegmentos !== nCru) conferirGhPerdido(cmd, cwdDoEvento, agente, conferirMemo);`
  para: `  if (ghTextoSegmentos === 0) conferirGhPerdido(cmd, cwdDoEvento, agente, conferirMemo);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 gh perdido depois de outro gh achado barra"`
prova-na-base: verde — emenda da revisão 4: a base já é o código das tarefas 1 a 15, e a prova é a mutação acima
pronto quando: payload real `Bash`, repositório público, `corpo.md` com `termo702`: `gh issue close 1 --comment ok; echo it` + contrabarra + `'s; gh issue comment 3 -F corpo.md` sai 2. A rede roda em qualquer diferença de contagem, contada com contrabarra + quebra juntas sem espaço, como o bash (a leitura juntada do bash também é conferida: `--title termo` + contrabarra + quebra + `702` sai 2); `gh` + contrabarra + quebra + `issue create --repo dono/priv --title termo702 --body x` de um cwd público sai 0, e `echo it` + contrabarra + `'s; gh` + contrabarra + quebra + `issue comment 3 -F corpo.md` sai 2: a rede lê o texto com contrabarra + quebra juntas. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 18. Corpo de heredoc e here-string com todos os detectores [tipo: implementar]
atende: D2
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 17
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `  textos.push(...corposEmbutidos(cmdOriginal));`
  para: `  void corposEmbutidos;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 JID em heredoc do --body-file barra"`
prova-na-base: verde — emenda da revisão 4: a base já é o código das tarefas 1 a 15, e a prova é a mutação acima
pronto quando: payload real `Bash`, repositório público: `cat > n.md <<'EOF'` + `veja 5511999998888@s.whatsapp.net` + `EOF` + `gh issue create --title t --body-file n.md` sai 2 pelo detector de JID, que a origem `comando` não aplica. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 19. A rede lê --body-file entre aspas [tipo: implementar]
atende: D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 18
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `    const arq = x[1] || x[2] || x[3];`
  para: `    const arq = x[3] || x[2] || "-";`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 rede le --body-file entre aspas com espaco"`
prova-na-base: verde — emenda da revisão 4: a base já é o código das tarefas 1 a 15, e a prova é a mutação acima
pronto quando: payload real `Bash`, repositório público, `sp/a b.md` com `termo702`: `echo it` + contrabarra + `'s; gh issue create --title t --body-file "sp/a b.md"` sai 2. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 20. A rede reconhece flag e aspas entre família e verbo [tipo: implementar]
atende: D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 19
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `["']?\b(issue|pr)\b["']?(?:\s+-{1,2}\w[\w-]*(?:=[^\s;|&]*|\s+(?!-)[^\s;|&]+)?)*\s+["']?(create|`
  para: `\b(issue|pr)\s+(create|`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  timeout: `900000`
  fixture: `testa-gate-publicacao-destino.sh, seção "#702", caso "702 rede pega gh perdido com flag entre familia e verbo"`
prova-na-base: verde — emenda da revisão 5: a base já é o código das tarefas 1 a 19, e a prova é a mutação acima
pronto quando: payload real `Bash`, cwd no repositório privado: `echo it` + contrabarra + `'s; gh issue --repo dono/publico comment 3 --body termo702` sai 2, `echo it` + contrabarra + `'s; gh "issue" create --repo dono/publico --title t --body termo702` sai 2, e `gh issue --repo dono/priv comment 3 --body termo702` sai 0. Provado por `bash hooks/testa-gate-publicacao-destino.sh` com `0 falha(s)` e exit 0.

### 3. Versão 2.14.1, CHANGELOG e README [tipo: docs]
atende: D7
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
mutacao: n/a
  motivo: tarefa só de texto e número de versão, sem comportamento a inverter
pronto quando: com o diff da branch, o número da versão e a descrição batem com o design:
- a versão sobe de `2.14.0` para `2.14.1` em `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json`; se a `origin/main` já estiver em `2.14.1` ou mais na hora, a versão é o próximo PATCH livre acima dela, e o resto deste critério lê esse número no lugar de `2.14.1`;
- o badge da linha 7 do `README.md` troca `2.14.0` por `2.14.1` nas duas ocorrências (`vers%C3%A3o-2.14.0` e `alt="versão 2.14.0"`);
- o `CHANGELOG.md` ganha, no topo, a seção `## 2.14.1 — 2026-11-13`, que cita a #702 e os verbos do D1;
- a linha `gate-publicacao-destino.cjs` da tabela de hooks do README passa a citar o título e o corpo de `gh issue`/`gh pr`, com os verbos do D1 (inclusive `close` e `reopen`).

Provado por `node scripts/conferir-versao.cjs` com exit 0 (ele só confere que a versão declarada é maior que a da `origin/main`; exit 2 quer dizer bump faltando), `grep -o "2.14.1" README.md | wc -l` devolvendo 2 ou mais (o `grep -c` conta linhas, e as duas ocorrências estão na mesma linha), e `grep -n "2.14.1" CHANGELOG.md .claude-plugin/plugin.json .codex-plugin/plugin.json` com uma linha por arquivo.
