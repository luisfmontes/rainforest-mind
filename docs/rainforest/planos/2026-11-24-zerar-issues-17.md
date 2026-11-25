# Plano: Rodada 17 — heredoc com continuação de linha e staging por script não-shell

Design: docs/rainforest/design/2026-11-24-zerar-issues-17.md

## O que não pode quebrar

- Todo caso existente de `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh` e `hooks/testa-gate-publicacao-destino.sh` mantém o exit esperado. Nenhum caso é apagado.
- A seção D6 de `gates-sem-ruido` no fim de `hooks/testa-gate-staging-total.sh` (regex de JS em corpo executado por `node` passa; `execSync('git add -A')` barra).
- A #258 (`cat > /tmp/x.md <<'EOF'` + `gh issue create --body-file /tmp/x.md` passa): o arquivo citado sem executor continua dado.
- A assinatura e o retorno de `alvoDoRedirecionamentoEhExecutadoDepois(cmd, i, fimDoHeredoc)` (booleano) e de `executoresDoAlvo(cmd, i, fimDoHeredoc)` (array de nomes normalizados, `"./"` para `./x`), exportadas por `hooks/lib/heredoc.cjs`.

## Tarefas

Com a D4, o que as tarefas 2 a 4 reconhecem como executor muda a decisão de `dado` também em `gate-mensagem-commit`, `gate-worktree` e `gate-publicacao-destino`: as quatro baterias rodam inteiras depois da tarefa 5, não só a de staging.

A execução é na janela principal, não por executor haiku: é a lib de máscara que quatro gates compartilham, e o estágio revisar tem foco em segurança. Todas tocam `hooks/lib/heredoc.cjs` e a mesma seção nova de `hooks/testa-gate-staging-total.sh`: seriais, na ordem. A seção nova, criada pela tarefa 1, fica logo antes de `echo "== resultado:` e abre com `echo "== rodada 17 (#724, #722): continuacao, stdin, copia, lista e operador colado =="`; as tarefas 2 a 5 acrescentam casos a ela. Todos os casos usam os ajudantes da bateria (`gate`, `b`, `hd`).

### 1. A máscara começa depois da linha lógica (#724) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- catalogo | fimDaLinhaLogica em hooks/lib/heredoc.cjs:31 | reuso; é a função que corpoDeHeredoc já usa para o início do corpo
desfecho: estender
O que fazer:
- Em `hooks/lib/heredoc.cjs`, antes de `mascararCorposDeHeredoc`, `function inicioDoCorpo(fora, i)` com `const fl = fimDaLinhaLogica(fora, i);` e `return fl === -1 ? fora.length : fl + 1;`, e comentário citando a #724 (a máscara e `corpoDeHeredoc` tinham de concordar sobre onde o corpo começa).
- Nos dois ramos de `mascararCorposDeHeredoc` (dado e `scriptNaoShell`), as duas linhas `const quebra = fora.indexOf("\n", i);` + `const inicio = ...` viram `const inicio = inicioDoCorpo(fora, i);`.
- Bateria de `staging-total`, na seção nova:
  - `#724 continuacao esconde git add -A barra` → 2: `$(b "$(hd "cat <<'A' \\" "> /dev/null; git add -A" "x" "A")")`.
  - `#724 continuacao com corpo de dado passa` → 0: `$(b "$(hd "cat <<'A' \\" "> nota.md" "git add -A" "A")")`.
- `hooks/testa-gate-mensagem-commit.sh`, depois da seção `(m)`: `gate "#724 git commit pelado na continuacao da linha do heredoc -> exit 2" 2 "$(payload "$R1" Bash $'cat <<\x27A\x27 \\\n> /dev/null; git commit\nx\nA')"`.
- `hooks/testa-gate-worktree.sh`, depois do caso `git commit -F msg.txt depois de heredoc com rm -rf "$X" no corpo passa`: `g580e '#724 mv na continuacao da linha do heredoc barra' 2 "$(printf '%s\n' "cat <<'A' \\" '> msg.txt; mv a.txt "$X/f"' 'x' 'A')"`.
- `hooks/testa-gate-publicacao-destino.sh`, logo depois do caso `gh entre chaves em cwd privado barra (cwd incerto, falso positivo aceito)` e antes da linha que restaura `GH702="node $SANDBOX_BIN/gh"` (o `GH702` ali já é `gh-por-nome`): `confere702 "#724 GH_REPO na continuacao da linha do heredoc barra" 2 "" Bash "$R702P" $'cat <<\x27A\x27 \\\n> /dev/null; export GH_REPO=dono/publico; gh issue create --title termo702 --body x\nx\nA'`. Se contra a lib da base o caso já sair 2 (não mediria a máscara), a execução para e reporta antes de seguir.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `const fl = fimDaLinhaLogica(fora, i);`
  para: `const fl = fora.indexOf("\n", i);`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#724 continuacao esconde git add -A barra"
prova-na-base: verde — os casos #724 só existem nas baterias que esta tarefa escreve; contra a lib da base o `git add -A` na continuação sai 0 (sonda de 2026-11-24)
pronto quando: com o payload real de `PreToolUse` da #724 (`cat <<'A' \` + quebra + `> /dev/null; git add -A`), provado por `bash hooks/testa-gate-staging-total.sh`, `bash hooks/testa-gate-mensagem-commit.sh`, `bash hooks/testa-gate-worktree.sh` e `bash hooks/testa-gate-publicacao-destino.sh` com `ok` nos casos `#724` e 0 falhas no placar de cada uma.

### 2. Operador colado ao nome se separa (forma 5) [tipo: implementar]
atende: D7
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 1
busca:
- catalogo | tokensComAspas em hooks/lib/tokens-comando.cjs | estendo; o tokenizador é de uso geral e não separa operador colado de propósito, então a separação fica local em heredoc.cjs
desfecho: estender
O que fazer:
- Emenda do executar (D7 emendada): `const RE_OPERADOR_COLADO = /(^\d+[<>]&\d*-?|[<>]&\d*-?|&>>?|^\d+>>?|^\d+<|>>?|<|[|;&(){}]+)/;` (dígito de descritor só no começo do token; `2>&1`, `>&2` e `&>` inteiros), `RE_REDIR_COM_ALVO = /^(?:\d*(?:<|>>?)|&>>?)$/`, `RE_REDIR_FECHADO = /^\d*[<>]&\d*-?$/` e `ehOperador`. `function tokensSeparados(texto)`: tira `\`+quebra, tokeniza com `tokensComAspas` e põe `;` entre dois tokens que têm quebra de linha entre eles (pelos offsets `ini`/`fim`); no `catch`, quebra vira ` ; ` e `split(/\s+/)`; e `return toks.flatMap((t) => t.split(RE_OPERADOR_COLADO)).filter(Boolean);` (essa linha, literal, é o `de:` da mutação). Revisão 1: `<<`, `<<-`, `<<<` e `>|` também se separam inteiros. Comentário citando a D7.
- `executoresDoAlvo` usa `tokensSeparados(depois)` no lugar do `try { toks = tokensComAspas(...) } catch {...}`.
- Casos na seção nova:
  - `operador colado: bash t.sh; true barra` → 2: `$(b "$(hd "cat > t.sh <<'EOF'" "git add -A" "EOF" "bash t.sh; true")")`.
  - `operador colado: bash t.sh;true barra` → 2: `$(b "$(hd "cat > t.sh <<'EOF'" "git add -A" "EOF" "bash t.sh;true")")`.
  - `digito so e descritor no comeco: bash t2>log barra` → 2: arquivo `t2`, cauda `bash t2>log`.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `return toks.flatMap((t) => t.split(RE_OPERADOR_COLADO)).filter(Boolean);`
  para: `return toks;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "operador colado: bash t.sh; true barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `bash t.sh; true` sai 0 (sonda de 2026-11-24)
pronto quando: com o comando real `bash t.sh; true` depois do heredoc, provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos dois casos `operador colado` e 0 falhas.

### 3. Executor por stdin e por pipe de `cat`, e uma régua só (#722, forma 3) [tipo: implementar]
atende: D2, D4, D8
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 2
busca:
- catalogo | alvoDoRedirecionamentoEhExecutadoDepois e executoresDoAlvo em hooks/lib/heredoc.cjs:311,367 | unifico; as duas repetem a mesma varredura
desfecho: estender
O que fazer:
- `function alvosDaLinha(cmd, i)`: o trecho comum hoje repetido nas duas funções (linha lógica do heredoc, regex dos alvos de `>`/`>>`, nome-base) devolve o `Set`.
- `function ehRedirecionamentoDeEntrada(t)`: `/^\d*<$/.test(t)`.
- `function trechoEm(toks, k)`: devolve `[ini, fim]`, com `ini` = um depois do último operador antes de `k` (ou 0) e `fim` = o próximo operador a partir de `k` (ou `toks.length`). É o único cortador de trechos, usado também pela tarefa 4.
- Emenda do executar: `function lerTrecho(toks, ini, fim)` no lugar de `comandoDoTrecho`: percorre `toks[ini..fim)`, pula `RE_REDIR_COM_ALVO` com o token seguinte, `RE_REDIR_FECHADO`, e, antes do comando, atribuição (`/^\w+=/`), flag, número (`timeout 5`) e prefixo de `PREFIXOS_DE_COMANDO` (`sudo`, `env`, `command`, `exec`, `nohup`, `nice`, `time`, `timeout`, `builtin`). Devolve `{ nome, posicionais }`, com os índices dos posicionais (não começam com `-`). `executorDeStdin(trecho)`: o nome, se é de `EXECUTAM_ARQUIVO` e não há posicional. `executorAntes(toks, k, ini)`: a varredura de hoje para trás, pulando também redirecionamento e o alvo dele; alvo que é ele mesmo destino de redirecionamento não é argumento.
- D8: `executoresDoAlvo` tokeniza `cmd.slice(i, fimDaLinhaLogica)` + quebra + o texto depois do fechamento, para ler o executor na própria linha do heredoc.
- Em `executoresDoAlvo`, para cada token que casa um alvo, nesta ordem:
  1. `./x` como hoje;
  2. `if (k > ini && ehRedirecionamentoDeEntrada(toks[k - 1]))`: `executorDeStdin(trecho, toks)` entra e encerra o token; senão
  3. `executorAntes(toks, k, ini)` entra e encerra o token;
  4. se o trecho é `cat` (alvo como argumento ou como stdin) e `toks[fim]` é `|` ou `|&`: `executorDeStdin` do trecho seguinte (`trechoEm(toks, fim + 1)`).
- Revisão 1: `FLAGS_COM_VALOR` (`-o`, `+o`, `-O`, `+O`, `-W`, `-X`, `-r`, `--require`, `--import`, `--loader`, `-I` e afins) pula o valor em `lerTrecho` e em `executorAntes`; `executorAntes` aceita também o alvo como primeiro posicional de executor; `executoresDaPipeline(toks, fim)` segue `|`/`|&` e `( )`/`{ }` até um executor de stdin, a partir de qualquer trecho que lê o alvo (`trechoLeAlvo`: argumento ou `<`); `-` só é script antes de qualquer posicional (`stdinComoScript`); `deno run`/`bun run` pulam o subcomando. Casos `R1` de flag com valor, pipe encadeado e `-` de dado.
- Emenda da revisão de segurança automática: `lerTrecho` devolve também `flags`; `executorDeStdin(trecho, toks)` aceita, além de sem posicional, `-` entre as flags, `-s` em shell (`SHELLS_COM_S`) e `/dev/stdin` como primeiro posicional.
- `alvoDoRedirecionamentoEhExecutadoDepois` vira `return executoresDoAlvo(cmd, i, fimDoHeredoc).length > 0;`, com o docblock dizendo que é a mesma régua (D4).
- Casos na seção nova:
  - `#722 sh < t.cjs barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "sh < t.cjs")")`.
  - `#722 sh <t.cjs colado barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "sh <t.cjs")")`.
  - `#722 cat t.cjs | sh barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "cat t.cjs | sh")")`.
  - `#722 node t.cjs; sh < t.cjs barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "node t.cjs; sh < t.cjs")")`.
  - `python script.py < dados.txt passa` → 0: `$(b "$(hd "cat > dados.txt <<'EOF'" "git add -A" "EOF" "python script.py < dados.txt")")`.
  - `cat dados.txt | node x.js passa` → 0: `$(b "$(hd "cat > dados.txt <<'EOF'" "git add -A" "EOF" "cat dados.txt | node x.js")")`.
  - Emenda do executar, mesmo molde (arquivo, cauda): `#722 < t.cjs sh barra` (`< t.cjs sh`), `#722 sh 2>&1 < t.cjs barra`, `#722 sudo sh < t.cjs barra`, `bash 2>&1 t.sh barra` e `bash 2>/dev/null t.sh barra` (arquivo `t.sh`) → 2; `sh x.sh < dados.txt passa` → 0. Da revisão de segurança automática: `cat < t.cjs | sh`, `sh -s arg < t.cjs`, `bash /dev/stdin < t.sh` (arquivo `t.sh`) e `node - arg < t.cjs` (corpo `execSync('git add -A')`) → 2; `python -s script.py < dados.txt` → 0.
  - D8: `D8 node na linha do heredoc barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF' && node t.cjs" "execSync('git add -A')" "EOF")")`; `D8 gh --body-file na linha do heredoc passa` → 0: `$(b "$(hd "cat > n.md <<'EOF' && gh issue create --title t --body-file n.md" "git add -A" "EOF")")`.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `ehRedirecionamentoDeEntrada(toks[k - 1])`
  para: `false`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 sh < t.cjs barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `sh < t.cjs` e `cat t.cjs | sh` saem 0 (sonda de 2026-11-24)
pronto quando: com o comando real da #722 (`node t.cjs; sh < t.cjs`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos casos da tarefa e 0 falhas.

### 4. O alvo segue cópia e renomeação (#722, forma 4) [tipo: implementar]
atende: D3
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 3
busca:
- catalogo | listar --raiz hooks/lib | nada equivalente: nenhuma lib segue cópia de arquivo em comando
desfecho: construir
O que fazer:
- `function nomeBase(t)`: tira aspas das pontas (`replace(/^["']+|["']+$/g, "")`) e devolve `split(/[\\/]/).pop()`, a mesma conta de hoje; `executoresDoAlvo` e `alvosDaLinha` passam a usá-la.
- Revisão 1: `cat` que lê o alvo pelo stdin (`cat < t.sh > x.sh`) também copia (`trechoLeAlvo`). Caso `R1 cat < t.sh > x.sh; bash x.sh`.
- `function expandirAlvosPorCopia(toks, alvos)`: até 10 voltas, enquanto o `Set` cresce, para cada trecho cortado por `trechoEm` (da tarefa 3), com os posicionais de `lerTrecho` (flag = começa com `-`, pulada sem valor; redirecionamento e alvo fora): comando `cp`, `mv`, `ln` ou `install` com dois ou mais posicionais, algum de origem (todos menos o último) com nome-base em `alvos` → acrescenta o nome-base do último (vazio, como em `d/`, não entra); comando `cat` com posicional em `alvos` e redirecionamento `>`/`>>` no trecho → acrescenta o nome-base do alvo do redirecionamento.
- Em `executoresDoAlvo`, `expandirAlvosPorCopia(toks, alvos);` logo depois de `tokensSeparados`.
- Casos na seção nova, todos `$(b "$(hd "cat > <arq> <<'EOF'" "git add -A" "EOF" "<cauda>")")` com `<arq>` e `<cauda>`:
  - `#722 cp t.cjs x.sh && bash x.sh barra` → 2: `t.cjs`, `cp t.cjs x.sh && bash x.sh`.
  - `#722 cat t.cjs > x.sh && bash x.sh barra` → 2: `t.cjs`, `cat t.cjs > x.sh && bash x.sh`.
  - `#722 cp t.cjs a; mv a b.sh; bash b.sh barra` → 2: `t.cjs`, `cp t.cjs a; mv a b.sh; bash b.sh`.
  - `#722 node t.cjs; cp t.cjs x.sh; bash x.sh barra` → 2: `t.cjs`, `node t.cjs; cp t.cjs x.sh; bash x.sh`.
  - `D8 cp na linha do heredoc e bash depois barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF' && cp t.cjs x.sh" "git add -A" "EOF" "bash x.sh")")`.
  - `cp nota.md copia.md passa` → 0: `nota.md`, `cp nota.md copia.md`.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `expandirAlvosPorCopia(toks, alvos);`
  para: `void alvos;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 cp t.cjs x.sh && bash x.sh barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `cp t.cjs x.sh && bash x.sh` sai 0 (sonda de 2026-11-24)
pronto quando: com o comando real da #722 (`cp t.cjs x.sh; bash x.sh`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos seis casos da tarefa e 0 falhas.

### 5. `git` em lista de strings fica visível (#722, forma 1) [tipo: implementar]
atende: D5
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 4
busca:
- catalogo | mascaraSoGit em hooks/lib/heredoc.cjs:413 | estendo; é a única máscara de corpo não-shell
desfecho: estender
O que fazer:
- `function trechosDeListaGit(texto)` (emenda do executar: sobre o corpo inteiro, não por linha): acha cada literal `'git'`, `"git"` ou `` `git` `` (sem exigir `(` ou `[` antes) e o estende enquanto vier, depois de espaços (quebra de linha inclusive), vírgulas e colchetes, outro literal completo de mesma aspa na abertura e no fechamento (sem quebra de linha nem aspa dentro); a sequência termina no primeiro caractere que não é isso. Devolve os intervalos `[ini, fim)`, `fim` logo depois da aspa que fecha o último literal.
- Revisão 1: o literal inicial aceita caminho e `.exe` (`/(['"`])((?:[^'"`\n]*[\\/])?git(?:\.exe)?)\1/gi`), os separadores aceitam chave, parêntese, comentário de bloco e chave de objeto, e `trechosDeListaGit` devolve `{ ini, fim, conteudos }`: só o miolo dos literais fica visível. Casos `R1 git.exe`, `R1 comentario`, `R1 Deno.Command`.
- `mascaraSoGit` passa a trabalhar sobre o corpo inteiro (a regex de hoje já para em quebra de linha). Depois do laço de hoje: `for (const [a, z] of trechosDeListaGit(trecho))`, cada posição do intervalo recebe o caractere original, trocado por espaço quando é aspa, vírgula, colchete ou quebra de linha. Comprimento preservado.
- Casos na seção nova:
  - `#722 spawnSync('git',['add','-A']) executado por node barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "require('child_process').spawnSync('git',['add','-A'])" "EOF" "node t.cjs")")`.
  - `#722 subprocess.run(["git", "add", "-A"]) executado por python barra` → 2: `$(b "$(hd "cat > t.py <<'EOF'" 'subprocess.run(["git", "add", "-A"])' "EOF" "python t.py")")`.
  - `lista em varias linhas executada por node barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "spawnSync('git', [" "  'add', '-A'])" "EOF" "node t.cjs")")`.
  - `spawnSync('git',['status']) executado por node passa` → 0: o primeiro com `['status']`.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `of trechosDeListaGit(trecho)`
  para: `of []`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 spawnSync('git',['add','-A']) executado por node barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base o spawn em array sai 0 (sonda de 2026-11-24)
pronto quando: com o corpo real da #722 (`require('child_process').spawnSync('git',['add','-A'])` + `node t.cjs`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos quatro casos da tarefa e 0 falhas.

### 7. Execução por caminho e por texto de `-c`/`eval`; alvos de `tee` e `>` colado (revisão 1) [tipo: implementar]
atende: D9
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 5
busca:
- catalogo | lerTrecho e alvosDaLinha em hooks/lib/heredoc.cjs | estendo; lerTrecho passa a devolver nomeIdx
desfecho: estender
O que fazer:
- `lerTrecho` devolve `nomeIdx` (índice do token do comando). Em `executoresDoAlvo`, `if (trecho.nomeIdx === k && /[\\/]/.test(t))` empurra `"./"`.
- `abrirTextoDeComando(toks)`: token com espaço depois de `-c` (`/^-\w*c\w*$/`) ou de `eval` vira `;` + `tokensSeparados(token)` + `;`. `executoresDoAlvo` aplica antes de `expandirAlvosPorCopia`.
- `alvosDaLinha`: regex `/\d?>[>|]?\s*([^\s;|&<>()]+)/g` (sem exigir espaço antes) e os posicionais de `tee` da linha.
- Casos `R1 $PWD/t.sh`, `R1 ../t.sh`, `R1 bash -c 'bash t.sh'`, `R1 tee t.sh <<EOF > /dev/null`, `R1 cat>t.sh<<EOF` e `R1 cat >| t.sh` → 2 na seção nova.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `trecho.nomeIdx === k`
  para: `false`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "R1 ../t.sh barra"
prova-na-base: verde — casos novos da revisão 1; contra a lib do commit 6cea5864 saem 0 (25 falhas medidas com a lib anterior)
pronto quando: com os comandos que o revisor mediu no bash real (`../t.sh`, `bash -c 'bash t.sh'`, `tee t.sh <<'A'`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos casos `R1` desta tarefa e 0 falhas.

### 8. Linha lógica de verdade (revisão 1) [tipo: implementar]
atende: D10
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 7
busca:
- catalogo | fimDaLinhaLogica em hooks/lib/heredoc.cjs:31 | estendo; é a função que corpoDeHeredoc, a máscara e os leitores de alvo usam
desfecho: estender
O que fazer:
- `fimDaLinhaLogica(cmd, i)` vira varredura de `i` em diante: aspa simples (sem escape), contrabarra fora dela pula o caractere seguinte (quebra inclusive), aspa dupla, `$'...'` com `\` escapando, profundidade de `$(`, e `#` em início de palavra (`/[\s;|&()]/` antes) que encerra a linha na próxima quebra se não estiver dentro de `$(`. Devolve a primeira quebra fora de tudo isso, ou `-1`.
- Casos `R1 contrabarra escapada fecha a linha`, `R1 contrabarra em comentario nao continua` e `R1 aspa multilinha na abertura` → 2. O caso `#724` e o `continuacao normal | bash` de antes seguem barrando.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `if (sub === 0) return q;`
  para: `if (sub === 0) {}`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "R1 contrabarra em comentario nao continua barra"
prova-na-base: verde — casos novos da revisão 1; contra a lib do commit 6cea5864 saem 0
pronto quando: com as três aberturas que o revisor rodou no bash real, provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos três casos e 0 falhas.

### 9. `<<` que não é operador (revisão 1) [tipo: implementar]
atende: D11
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 8
busca:
- catalogo | posicoesDeOperadorHeredoc em hooks/lib/heredoc.cjs | estendo
desfecho: estender
O que fazer:
- Em `posicoesDeOperadorHeredoc`, fora de aspas: `$'` pula até a `'` não escapada; `${` pula até a `}` que fecha (contando chaves); e `)` entra na lista de caracteres que abrem comentário antes de `#`.
- Casos `R1 ${x:-<<'A'} nao abre heredoc` e `R1 (true)#<<'A' e comentario` → 2.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `" \t\n;|&()".includes(antes)`
  para: `" \t\n;|&(".includes(antes)`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "R1 (true)#<<'A' e comentario barra"
prova-na-base: verde — casos novos da revisão 1; contra a lib do commit 6cea5864 saem 0
pronto quando: com as duas linhas que o revisor rodou no bash real, provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos dois casos e 0 falhas.

### 10. Heredoc no stdin de interpretador não-shell (revisão 1) [tipo: implementar]
atende: D12
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 9
busca:
- catalogo | executorDeStdin e mascararCorposDeHeredoc em hooks/lib/heredoc.cjs | componho; o reconhecimento é o executorDeStdin da tarefa 3 aplicado ao trecho do próprio <<
desfecho: compor
O que fazer:
- `RE_OPERADOR_COLADO` e `RE_REDIR_COM_ALVO` passam a tratar `<<`, `<<-` e `<<<` como redirecionamento com alvo.
- `interpretadorNaoShellDoHeredoc(cmd, i)`: tokeniza a linha lógica, acha o token `<<` de `i` (o último da linha até `i`), e devolve `executorDeStdin` do trecho dele se for de `INTERPRETADORES_NAO_SHELL`, senão null.
- Em `mascararCorposDeHeredoc`, `dado` ganha `&& !(opcoes.scriptNaoShell === true && interpretadorNaoShellDoHeredoc(fora, i))`, e o ramo `scriptNaoShell` soma esse interpretador aos executores.
- Casos `R1 node - <<'A' com execSync` e `R1 python - <<'A' com os.system` → 2; `R1 node - <<'A' com regex sem git` e `R1 python script.py <<'A' com dado` → 0.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `!(opcoes.scriptNaoShell === true && interpretadorNaoShellDoHeredoc(fora, i))`
  para: `true`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "R1 node - <<'A' com execSync barra"
prova-na-base: verde — casos novos da revisão 1; contra a lib do commit 6cea5864 saem 0
pronto quando: com o `node - <<'A'` que o revisor rodou no bash real, provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos quatro casos e 0 falhas.

### 6. Versão 2.17.3 [tipo: docs]
atende: D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 10
O que fazer:
- `version` `2.17.3` nas duas `plugin.json` e nas duas ocorrências da linha do selo do `README.md` (URL e `alt`).
- `## 2.17.3 — 2026-11-24` no topo do `CHANGELOG.md`, um item por Issue (#724, #722) e um para o operador colado, do ponto de vista de quem usa.
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.3"' .claude-plugin/plugin.json`
pronto quando: com os manifestos que o cache lê para instalar, provado por `grep -c '"version": "2.17.3"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.3' CHANGELOG.md` imprimindo 1.
