# Plano: Rodada 17 — heredoc com continuação de linha e staging por script não-shell

Design: docs/rainforest/design/2026-11-24-zerar-issues-17.md

## O que não pode quebrar

- Todo caso existente de `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh` e `hooks/testa-gate-publicacao-destino.sh` mantém o exit esperado. Nenhum caso é apagado.
- A seção D6 de `gates-sem-ruido` no fim de `hooks/testa-gate-staging-total.sh` (regex de JS em corpo executado por `node` passa; `execSync('git add -A')` barra).
- A #258 (`cat > /tmp/x.md <<'EOF'` + `gh issue create --body-file /tmp/x.md` passa): o arquivo citado sem executor continua dado.
- A assinatura e o retorno de `alvoDoRedirecionamentoEhExecutadoDepois(cmd, i, fimDoHeredoc)` (booleano) e de `executoresDoAlvo(cmd, i, fimDoHeredoc)` (array de nomes normalizados, `"./"` para `./x`), exportadas por `hooks/lib/heredoc.cjs`.

## Tarefas

Todas tocam `hooks/lib/heredoc.cjs` e a mesma seção nova de `hooks/testa-gate-staging-total.sh`: seriais, na ordem. A seção nova, criada pela tarefa 1, fica logo antes de `echo "== resultado:` e abre com `echo "== rodada 17 (#724, #722): continuacao, stdin, copia, lista e operador colado =="`; as tarefas 2 a 5 acrescentam casos a ela. Todos os casos usam os ajudantes da bateria (`gate`, `b`, `hd`).

### 1. A máscara começa depois da linha lógica (#724) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- catalogo | fimDaLinhaLogica em hooks/lib/heredoc.cjs:31 | reuso; é a função que corpoDeHeredoc já usa para o início do corpo
desfecho: reusar
O que fazer:
- Em `hooks/lib/heredoc.cjs`, antes de `mascararCorposDeHeredoc`, `function inicioDoCorpo(fora, i)` com `const fl = fimDaLinhaLogica(fora, i);` e `return fl === -1 ? fora.length : fl + 1;`, e comentário citando a #724 (a máscara e `corpoDeHeredoc` tinham de concordar sobre onde o corpo começa).
- Nos dois ramos de `mascararCorposDeHeredoc` (dado e `scriptNaoShell`), as duas linhas `const quebra = fora.indexOf("\n", i);` + `const inicio = ...` viram `const inicio = inicioDoCorpo(fora, i);`.
- Bateria de `staging-total`, na seção nova:
  - `#724 continuacao esconde git add -A barra` → 2: `$(b "$(hd "cat <<'A' \\" "> /dev/null; git add -A" "x" "A")")`.
  - `#724 continuacao com corpo de dado passa` → 0: `$(b "$(hd "cat <<'A' \\" "> nota.md" "git add -A" "A")")`.
- `hooks/testa-gate-mensagem-commit.sh`, depois da seção `(m)`: `gate "#724 git commit pelado na continuacao da linha do heredoc -> exit 2" 2 "$(payload "$R1" Bash $'cat <<\x27A\x27 \\\n> /dev/null; git commit\nx\nA')"`.
- `hooks/testa-gate-worktree.sh`, depois do caso `git commit -F msg.txt depois de heredoc com rm -rf "$X" no corpo passa`: `g580e '#724 mv na continuacao da linha do heredoc barra' 2 "$(printf '%s\n' "cat <<'A' \\" '> msg.txt; mv a.txt "$X/f"' 'x' 'A')"`.
- `hooks/testa-gate-publicacao-destino.sh`, logo depois do caso `gh entre chaves em cwd privado barra (cwd incerto, falso positivo aceito)`, com `GH702="node $SANDBOX_BIN/gh-por-nome"` antes e o valor anterior restaurado depois: `confere702 "#724 GH_REPO na continuacao da linha do heredoc barra" 2 "" Bash "$R702P" $'cat <<\x27A\x27 \\\n> /dev/null; export GH_REPO=dono/publico; gh issue create --title termo702 --body x\nx\nA'`. Se a base já sair 2 por outro caminho (o caso não mediria a máscara), troca-se pela forma que a máscara afeta e o plano se emenda.
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
- Em `hooks/lib/heredoc.cjs`, `const RE_OPERADOR_COLADO = /([|;&(){}]+|\d*<|\d*>>?)/;` e `function tokensSeparados(texto)`: tokeniza com `tokensComAspas` (no `catch`, `split(/\s+/)` como hoje), aplica `.flatMap((t) => t.split(RE_OPERADOR_COLADO))` e descarta vazios. Comentário citando a D7.
- `executoresDoAlvo` usa `tokensSeparados(depois)` no lugar do `try { toks = tokensComAspas(...) } catch {...}`.
- Casos na seção nova:
  - `operador colado: bash t.sh; true barra` → 2: `$(b "$(hd "cat > t.sh <<'EOF'" "git add -A" "EOF" "bash t.sh; true")")`.
  - `operador colado: node t.cjs;bash t.cjs barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "node t.cjs;bash t.cjs")")`.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `.flatMap((t) => t.split(RE_OPERADOR_COLADO))`
  para: `.slice()`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "operador colado: bash t.sh; true barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `bash t.sh; true` sai 0 (sonda de 2026-11-24)
pronto quando: com o comando real `bash t.sh; true` depois do heredoc, provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos dois casos `operador colado` e 0 falhas.

### 3. Executor por stdin e por pipe de `cat`, e uma régua só (#722, forma 3) [tipo: implementar]
atende: D2, D4
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 2
busca:
- catalogo | alvoDoRedirecionamentoEhExecutadoDepois e executoresDoAlvo em hooks/lib/heredoc.cjs:311,367 | unifico; as duas repetem a mesma varredura
desfecho: estender
O que fazer:
- `function alvosDaLinha(cmd, i)`: o trecho comum hoje repetido nas duas funções (linha lógica do heredoc, regex dos alvos de `>`/`>>`, nome-base) devolve o `Set`.
- `function ehRedirecionamentoDeEntrada(t)`: `/^\d*<$/.test(t)`.
- `function comandoDoTrecho(toks, k)`: do operador (`/^[|;&(){}]+$/`) anterior a `k` até `k`, pula atribuições (`/^\w+=/`) e redirecionamentos com o alvo; devolve `{ nome: normalizarExecutavel(primeiro), posicionais }`, onde `posicionais` conta os tokens entre o comando e `k` que não são flag (`-`) nem redirecionamento ou alvo dele.
- Em `executoresDoAlvo`, para cada token que casa um alvo, nesta ordem:
  1. `./x` como hoje;
  2. `if (k > 0 && ehRedirecionamentoDeEntrada(toks[k - 1]))`: `comandoDoTrecho(toks, k - 1)`; executor de `EXECUTAM_ARQUIVO` com `posicionais === 0` entra; `continue`;
  3. a varredura de hoje (anterior que não é flag);
  4. se o comando do trecho é `cat`: o próximo operador depois de `k` é `|` (ou `|&`) e o comando do trecho seguinte é executor sem posicional → entra.
- `alvoDoRedirecionamentoEhExecutadoDepois` vira `return executoresDoAlvo(cmd, i, fimDoHeredoc).length > 0;`, com o docblock dizendo que é a mesma régua (D4).
- Casos na seção nova:
  - `#722 sh < t.cjs barra` → 2: `$(b "$(hd "cat > t.cjs <<'EOF'" "git add -A" "EOF" "sh < t.cjs")")`.
  - `#722 sh <t.cjs colado barra` → 2 (mesmo corpo, `sh <t.cjs`).
  - `#722 cat t.cjs | sh barra` → 2 (mesmo corpo, `cat t.cjs | sh`).
  - `#722 node t.cjs; sh < t.cjs barra` → 2 (a forma da Issue).
  - `python script.py < dados.txt passa` → 0: `$(b "$(hd "cat > dados.txt <<'EOF'" "git add -A" "EOF" "python script.py < dados.txt")")`.
  - `cat dados.txt | node x.js passa` → 0 (corpo `git add -A` em `dados.txt`).
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `ehRedirecionamentoDeEntrada(toks[k - 1])`
  para: `false`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 sh < t.cjs barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `sh < t.cjs` e `cat t.cjs | sh` saem 0 (sonda de 2026-11-24)
pronto quando: com o comando real da #722 (`node t.cjs; sh < t.cjs`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos seis casos da tarefa e 0 falhas.

### 4. O alvo segue cópia e renomeação (#722, forma 4) [tipo: implementar]
atende: D3
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 3
busca:
- catalogo | listar --raiz hooks/lib | nada equivalente: nenhuma lib segue cópia de arquivo em comando
desfecho: criar
O que fazer:
- `function expandirAlvosPorCopia(toks, alvos)`: até 10 voltas, enquanto o `Set` cresce, para cada trecho (entre operadores): comando `cp`, `mv`, `ln` ou `install` com dois ou mais posicionais, algum de origem (todos menos o último) com nome-base em `alvos` → acrescenta o nome-base do último (vazio, como em `d/`, não entra); comando `cat` com posicional em `alvos` e redirecionamento `>`/`>>` no trecho → acrescenta o nome-base do alvo do redirecionamento.
- Em `executoresDoAlvo`, `expandirAlvosPorCopia(toks, alvos);` logo depois de `tokensSeparados`.
- Casos na seção nova (corpo `git add -A` gravado em `t.cjs`):
  - `#722 cp t.cjs x.sh && bash x.sh barra` → 2.
  - `#722 cat t.cjs > x.sh && bash x.sh barra` → 2.
  - `#722 cp t.cjs a; mv a b.sh; bash b.sh barra` → 2.
  - `#722 node t.cjs; cp t.cjs x.sh; bash x.sh barra` → 2 (a forma da Issue).
  - `cp nota.md copia.md passa` → 0 (corpo `git add -A` em `nota.md`, sem executor).
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `expandirAlvosPorCopia(toks, alvos);`
  para: `void alvos;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 cp t.cjs x.sh && bash x.sh barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base `cp t.cjs x.sh && bash x.sh` sai 0 (sonda de 2026-11-24)
pronto quando: com o comando real da #722 (`cp t.cjs x.sh; bash x.sh`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos cinco casos da tarefa e 0 falhas.

### 5. `git` em lista de strings fica visível (#722, forma 1) [tipo: implementar]
atende: D5
arquivos: `hooks/lib/heredoc.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 4
busca:
- catalogo | mascaraSoGit em hooks/lib/heredoc.cjs:413 | estendo; é a única máscara de corpo não-shell
desfecho: estender
O que fazer:
- `function trechosDeListaGit(linha)`: acha cada literal `'git'`, `"git"` ou `` `git` `` seguido de literais separados por espaço, vírgula ou colchete, com a mesma aspa abrindo e fechando cada um; devolve os intervalos `[ini, fim)`.
- Em `mascaraSoGit`, depois do laço de hoje: `for (const [a, z] of trechosDeListaGit(linha))`, cada posição do intervalo recebe o caractere original, trocado por espaço quando é aspa, vírgula ou colchete. Comprimento preservado.
- Casos na seção nova:
  - `#722 spawnSync('git',['add','-A']) executado por node barra` → 2.
  - `#722 subprocess.run(["git", "add", "-A"]) executado por python barra` → 2.
  - `spawnSync('git',['status']) executado por node passa` → 0.
mutacao:
  arquivo: `hooks/lib/heredoc.cjs`
  de: `of trechosDeListaGit(linha)`
  para: `of []`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 17", caso "#722 spawnSync('git',['add','-A']) executado por node barra"
prova-na-base: verde — casos novos desta tarefa; contra a lib da base o spawn em array sai 0 (sonda de 2026-11-24)
pronto quando: com o corpo real da #722 (`require('child_process').spawnSync('git',['add','-A'])` + `node t.cjs`), provado por `bash hooks/testa-gate-staging-total.sh` com `ok` nos três casos da tarefa e 0 falhas.

### 6. Versão 2.17.3 [tipo: docs]
atende: D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 5
O que fazer:
- `version` `2.17.3` nas duas `plugin.json` e no selo do `README.md`.
- `## 2.17.3 — 2026-11-24` no topo do `CHANGELOG.md`, um item por Issue (#724, #722) e um para o operador colado, do ponto de vista de quem usa.
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.3"' .claude-plugin/plugin.json`
pronto quando: com o plugin instalado pela versão nova, provado por `grep -c '"version": "2.17.3"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.3' CHANGELOG.md` imprimindo 1.
