# Plano: gate-worktree — palavra do bash reconstruída, chaves, `bash -c` e substituição (#530, itens 1 a 3)

Design: docs/rainforest/design/gate-palavra-bash.md

## O que não pode quebrar
- Tudo o que o `gate-worktree` barra hoje continua barrado. A partir do worktree:
  - `cd <P> && echo x > f`;
  - `echo $(cd <P>; echo x > f)`;
  - `(cd <P>; echo x > f)`;
  - `bash -c 'cd $X; echo x > f'`;
  - `bash -c 'echo $HOME > f'`, que é ilegível;
  - `eval "$(ssh-agent -s)"`.
- O conserto da #514 (PR #535) continua valendo. Chave em argumento não vira fronteira: a partir do principal, com agente Explore, `ls 2>/tmp/x.log; echo a/{b,c}/d`, `wc -l skills/{a,b}/SKILL.md` e `echo {1..3}` saem 0.
- As baterias dos consumidores de `cwd-efetivo.cjs` seguem com 0 falhas: `testa-cwd-efetivo.sh`, `testa-gate-worktree.sh`, `testa-gate-fechar-issue.sh`, `testa-gate-mensagem-commit.sh` e `testa-gate-staging-total.sh`.

## Regra de parada (critério de trava)

Esta entrega reimplementa um pedaço da gramática do bash, onde o conjunto de contraexemplos não fecha. A parada é o D1. O revisor recebe o D1 desde a rodada 1. Contorno novo nas classes fora de escopo (`GIT_DIR`, função ou alias, `cd $VAR`, cmdlet do PowerShell, `cd` condicional) vira comentário na #530 ou na #533 e não reprova a entrega. Contorno novo **dentro** das classes do design (palavra reconstruída, chaves, `bash -c`/`eval`, substituição) é defeito desta entrega. Se a terceira rodada de revisão ainda achar contorno dentro do escopo, o fluxo volta ao `brainstorm` em vez de somar parser.

## Tarefas

### 1. Lib `hooks/lib/palavra-bash.cjs`: palavra, chaves e corpos de substituição [tipo: implementar]
atende: D4, D5, D6
arquivos: `hooks/lib/palavra-bash.cjs`, `hooks/testa-palavra-bash.sh`
depende de: nenhuma
prova: `bash hooks/testa-palavra-bash.sh`
mutacao:
  arquivo: `hooks/lib/palavra-bash.cjs`
  de: `if (marcas[k] !== "u") continue;`
  para: `if (false) continue;`
  bateria: `bash hooks/testa-palavra-bash.sh`
  fixture: testa-palavra-bash.sh, secao "chave entre aspas ou escapada nao expande"
pronto quando: a lib exporta três funções puras, sem disco nem processo.

- **`normalizarComando(seg)` devolve `{ seg, estouro }`.** Lê a **primeira palavra** do segmento como o bash a lê: espaços à esquerda, pedaços entre aspas simples e duplas juntados, `\` escapando o caractere seguinte e `$'...'` com os escapes ANSI-C (`\xHH`, `\NNN` octal, `\uHHHH`, `\n`, `\t` e afins). A palavra termina em espaço ou em `;&|()<>` sem aspas. A máscara é paralela, `u` para caractere sem aspas e `q` para caractere com aspas ou escapado. A palavra é expandida por chaves, e as palavras expandidas, juntadas por um espaço, substituem a primeira palavra. **O resto do segmento fica cru, byte a byte.** Palavra sem aspa, `\`, `$'` nem chave devolve `seg` idêntico ao de entrada.
- **`expandirChaves(texto, marcas)` devolve `string[]` ou `undefined`.** Expande `{a,b}` aninhado ou colado no texto, nesta ordem da esquerda para a direita. Só conta chave e vírgula marcadas `u`, e a função tem uma linha `if (marcas[k] !== "u") continue;` no laço que procura o grupo. Não expande `{1..3}` nem nada dentro de `${...}`. É iterativa, com teto de 4.096 palavras e 1.000.000 de caracteres de trabalho, e passar do teto devolve `undefined`. Com `undefined`, `normalizarComando` devolve `{ seg, estouro: true }`.
- **`corposDeSubstituicao(texto)` devolve `string[]`.** Devolve o corpo de cada crase e de cada `$(...)` fora de aspas simples, inclusive dentro de aspas duplas. Os parênteses são balanceados e ignoram parêntese entre aspas dentro do corpo. Crase escapada (`` \` ``) não abre corpo.
- O cabeçalho credita `ruvnet/ruflo`, `plugins/ruflo-mods/hooks/guard/dangerous-command.ts`, licença MIT. Nenhum caso de teste lê o fonte.

Casos, cada um como `assert` na bateria:

| entrada | saída |
|---|---|
| `normalizarComando("'cd' /x")` | `.seg === "cd /x"` |
| `normalizarComando("c\\d /x")` | `"cd /x"` |
| `normalizarComando("$'\\x63d' /x")` | `"cd /x"` |
| `normalizarComando("{cd,/x} && y")` | `"cd /x && y"` |
| `normalizarComando("{c,}d /x")` | `"cd d /x"` |
| `normalizarComando("'{cd,/x}'")` | `"{cd,/x}"` (chave entre aspas não expande) |
| `normalizarComando("\\{cd,/x}")` | `"{cd,/x}"` (escapada) |
| `normalizarComando("cd /x")` | idêntico |
| `normalizarComando("echo {1..3}")` | idêntico |
| `normalizarComando("${a,b}")` | idêntico |
| `expandirChaves` com `{a,b}{c,d}{e,f}…` em 13 grupos (8.192 palavras) | `undefined` |
| `corposDeSubstituicao('echo "$(cd /x; y)"')` | `["cd /x; y"]` |
| ``corposDeSubstituicao("echo `cd /x`")`` | `["cd /x"]` |
| ``corposDeSubstituicao("echo 'a`b`'")`` | `[]` |

Provado por `bash hooks/testa-palavra-bash.sh`, que imprime cada caso com 0 falhas. Na base o arquivo não existe, e a prova falha.

### 2. `cwd-efetivo`: a palavra de chaves não é fronteira e o movedor lê a palavra normalizada [tipo: implementar]
atende: D4, D5
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-worktree.sh`, `hooks/lib/palavra-bash.cjs`, `hooks/testa-palavra-bash.sh`
depende de: 1
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"'"'"'cd'"'"' "+process.argv[2]+"; echo x > f"}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const segMovedor = normalizado.seg;`
  para: `const segMovedor = semPrefixoSintaticoDeBuiltin(seg);`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: testa-cwd-efetivo.sh, secao "(#530) palavra de comando reconstruida: aspas, escape, ANSI-C e chaves"
pronto quando: a mudança tem duas partes.

- **Segmentação.** Em `segmentosComAspas`, uma `{` sem aspas que abre expansão de chaves (sem espaço logo depois, fechando na mesma palavra, com vírgula no nível dela e sem aspa, `$`, crase ou parêntese dentro) **não é fronteira em posição nenhuma**: a palavra inteira fica no segmento. Com aspa, `$` ou crase dentro, continua fronteira, e portanto `incerto`, como hoje. `{ cd x; }`, com espaço depois da chave, continua grupo.
- **Movedor.** `resolverMovedor` passa a ter, nesta ordem:
  ```
  const normalizado = normalizarComando(semPrefixoSintaticoDeBuiltin(seg));
  if (normalizado.estouro) estado.estouro = true;
  const segMovedor = normalizado.seg;
  ```
  `estado.estouro` nasce `false` onde o `estado` nasce, e `cwdPorSegmento` o propaga no item devolvido.

Com `cwdPorSegmento`, em `testa-cwd-efetivo.sh`, a partir de um worktree temporário W, com o principal P:

- `'cd' P`, `c\d P`, `$'\x63d' P`, `{cd,P}`, `A=1 {cd,P}` e `then {cd,P}` têm o cwd do segmento seguinte igual a P. O último é `incerto`, como o `then cd` de hoje.
- `{c,}d P` mantém W, como o bash, que falha com `too many arguments`.
- `{cd,"P"}`, com aspa dentro da chave, fica `incerto`, como hoje.
- Uma linha com 13 grupos de chaves em posição de comando sai com `estouro: true`.

Pelo gate real, com payload PreToolUse (`agent_id`, `agent_type: executor`, `cwd` = W), `'cd' P; echo x > f` → 2, que era 0 na base. Provado por `bash hooks/testa-cwd-efetivo.sh && bash hooks/testa-gate-fechar-issue.sh && bash hooks/testa-gate-mensagem-commit.sh && bash hooks/testa-gate-staging-total.sh`, todas com 0 falhas.

### 3. `gate-worktree`: escrita dentro de `bash -c`/`eval` e de substituição, e estouro barrado [tipo: implementar]
atende: D1, D2, D3, D5, D6
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`, `hooks/lib/palavra-bash.cjs`, `hooks/testa-palavra-bash.sh`
depende de: 2
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"bash -c '"'"'echo x > "+process.argv[2]+"/f'"'"'"}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (interno !== null && !ilegivel) alvos.push(`
  para: `if (false) alvos.push(`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `600000`
  fixture: testa-gate-worktree.sh, secao "(#530) escrita dentro de bash -c, eval e substituicao de comando"
pronto quando: `alvosBashEscrita(comando, cwdInicial, ehPowerShell, profundidade = 0)` recebe três acréscimos, em cada segmento e depois de resolver o `base`.

- **Wrapper.** `const { interno, ilegivel } = desempacotarWrapperDeString(seg, { ferramenta: ehPowerShell ? "PowerShell" : "Bash" });`, seguido de `if (interno !== null && !ilegivel) alvos.push(...alvosBashEscrita(interno, base, ehPowerShell, profundidade + 1));`. O ilegível não recursa: segue para o caminho de hoje (`procuraCLI`), que já barra.
- **Substituição.** Para cada corpo de `corposDeSubstituicao(seg)`, aplica a mesma recursão, partindo de `base`.
- **Barrar.** Com `profundidade > 4`, ou com `estado.estouro` (tarefa 2), devolve um alvo `{ tipo: "barrar", motivo }`. O motivo é `"wrapper aninhado demais para conferir (mais de 4 niveis)"` ou `"expansao de chaves grande demais para conferir"`. Em `main`, alvo `barrar` chama `bloqueia(motivo, <toplevel do cwd>, <agente>)`, como o ramo `incerto` de `procuraCLI`. A pessoa lê a mensagem no stderr e o motivo aparece nela.

Pelo gate real, com payload PreToolUse (`agent_id`, `agent_type: executor`, `cwd` = worktree W, principal P).

**Os nove contornos → 2** (todos 0 na base):
- `{cd,P} && echo x > f`
- `'cd' P; echo x > f`
- `c\d P; echo x > f`
- `$'\x63d' P; echo x > f`
- `bash -c 'cd P; echo x > f'`
- `bash -c 'echo x > P/f'`
- ``echo `cd P; echo x > f` ``
- `echo "$(cd P; echo x > f)"`
- ``echo "`cd P; echo x > f`"``

**Barrados por motivo, com o motivo no stderr → 2:**
- `bash -c` aninhado em cinco níveis, com `echo x > f` no centro. A bateria monta a string por código, aplicando aspas nível a nível, e não por literal digitado. Com quatro níveis, a mesma construção sai **0**;
- uma linha com 13 grupos de chaves em posição de comando.

**Vizinhos legítimos → 0** (cada um conferido antes como 0 na base):
- `bash -c 'echo x > f'`
- `eval 'echo x > f'`
- `echo "$(git rev-parse HEAD)" > f`
- ``echo 'a`b`' > f``
- `echo '{cd,x}' > f`
- `echo a{b,c} > f`
- `{c,}d P; echo x > f`, porque o bash não muda de cwd
- `'cd' hooks && echo x > f`, dentro do próprio W

**Também → 2** (emenda de 2026-10-15, sondagem depois da tarefa 2; 0 na base e na branch da tarefa 2, e o bash muda o cwd ou roda o git em P em todos):
- `cd P > /dev/null; echo x > f`
- `cd P 2>/dev/null && echo x > f`
- `>/dev/null cd P; echo x > f`
- `2>&1 cd P; echo x > f`
- `A=a b cd P; echo x > f`
- `{"cd",P}; echo x > f`
- `{git,-C,P,commit,-m,x}`
- `{env,-C,P,git,commit}`

O vizinho legítimo correspondente, `cd hooks > /dev/null; echo x > f` dentro de W, → **0**.

**Continuam como hoje:** os seis "não pode quebrar" do topo. Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas e os casos impressos.

### 4. Diferencial base × branch nos consumidores [tipo: teste]
atende: D7
arquivos: `docs/rainforest/estado/gate-palavra-bash-diferencial.txt`
depende de: 3
prova-na-base: verde — compara a base com a branch pronta, e na base não há branch para comparar
mutacao: n/a
  motivo: a tarefa mede o efeito das tarefas 1 a 3, e não tem ramo próprio a inverter. As mutações estão nas tarefas 1 a 3
pronto quando: um script no scratchpad (fora do repo) roda o mesmo corpus de comandos contra o gate da base `9f6b9ca3` e contra o da branch, nos cinco hooks que carregam `cwd-efetivo.cjs` (`grep -l cwd-efetivo hooks/*.cjs`): `gate-worktree`, `gate-fechar-issue`, `gate-mensagem-commit`, `gate-staging-total` e `gate-subagente-sem-gh`.

- O corpus é a união dos comandos das baterias desses gates com as formas desta entrega, rodado com `cwd` no worktree e no principal.
- O arquivo `docs/rainforest/estado/gate-palavra-bash-diferencial.txt` registra a contagem total, cada mudança `base→branch` com hook, comando e `cwd`, e o comando que gerou o arquivo.
- **Pronto quando:**
  - nenhuma linha `2→0`;
  - toda linha `0→2` é um dos nove contornos, uma das duas formas de barrar por motivo, ou um gêmeo deles (mesma forma com outro alvo ou outro `cwd`), cada gêmeo explicado na linha.

Provado por `grep -c "2→0" docs/rainforest/estado/gate-palavra-bash-diferencial.txt` devolvendo `0`.

### 5. Versão, CHANGELOG e README [tipo: docs]
atende: D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 3
mutacao: n/a
  motivo: metadados de versão e texto, sem comportamento. O comportamento está provado nas tarefas 1 a 3
pronto quando: a entrada nova do `CHANGELOG.md` cumpre três coisas.

- Nomeia as nove formas fechadas e os dois motivos de barrar.
- Diz o que fica fora (D1) com os números da #530 e da #533.
- Credita o enxerto do ruflo (MIT).

`plugin.json`, nos dois arquivos, e o topo do `CHANGELOG.md` mostram a mesma versão, um patch acima da `origin/main` no momento do commit. O README cita a versão nova onde cita a atual. Provado por `node -e 'const a=require("./.claude-plugin/plugin.json").version,b=require("./.codex-plugin/plugin.json").version;process.exit(a===b?0:1)'` e por `git diff origin/main -- CHANGELOG.md | grep -c "#530"` ≥ 1, com a leitura do texto contra os D1 a D6.

### 6. Regressão do PowerShell, falso positivo de substituição e CHANGELOG honesto (rodada 2, decisão (a) do usuário) [tipo: implementar]
atende: D4, D6, D8
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/lib/cwd-efetivo.cjs`, `CHANGELOG.md`
depende de: 5
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const B=String.fromCharCode(92);process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"PowerShell",tool_input:{command:"C:"+B+"PROGRA~1"+B+"Git"+B+"cmd"+B+"git.exe -C "+process.argv[2]+" commit --allow-empty -m x"}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao: n/a
  motivo: subsumida pela união da tarefa 9 (decisão do usuário em 2026-10-16). Medido no corpus de 4012 execuções: a mutação da tarefa 6 só muda saídas de 0 para 2 (276 casos, todos escrita ou commit real no checkout principal dentro de wrapper PowerShell) e nenhuma de 2 para 0, então a bateria não tem como ficar vermelha sem barrar o que deveria ser barrado. A remoção do código fica na #530
pronto quando: três consertos.

- **PowerShell fora da leitura do bash.** `normalizarComando`, `corposDeSubstituicao` e a recursão de wrapper do bash só se aplicam com `tool_name` diferente de `PowerShell`, decidido por uma linha `const ehBash = ferramenta !== "PowerShell";` (ou nome equivalente com esse texto exato, alvo da mutação).
  - Pelo gate real, a partir de W, com `tool_name: PowerShell`, `C:\PROGRA~1\Git\cmd\git.exe -C P commit --allow-empty -m x` → **2**. Era 2 na base e 0 na branch da rodada 1.
  - O mesmo para `\Git\cmd\git.exe -C P commit …` e `cd P; C:\Git\cmd\git.exe commit …`.
- **Substituição no cwd do segmento.** O corpo de substituição resolve contra o cwd do segmento onde ele está, nunca contra o `cwdInicial`. `cd hooks; echo "$(echo x > ../f)"` a partir de W → **0**; na rodada 1 saía 2. A passada extra sobre o comando inteiro (crase que atravessa `;`) só entra para corpo que **não** cabe inteiro num segmento.
  - `cd P; echo "$(echo x > f)"` → **2**, com caso na bateria.
  - Os 17 contornos da tarefa 3 continuam → 2.
- **CHANGELOG 1.67.6 honesto.** A entrada afirma só o que a bateria prova, que são as 17 formas listadas, e ganha um item "Limite conhecido". Esse item diz que a leitura do bash é parcial e cita exemplos que ainda passam: `bash -c '…' _`, `env bash -c`, `t\ee`, `{cp,a,P/f}`, `tee {P/f,}`. Diz também que a família inteira está na #530 e que a abordagem por caminho do principal vem num fluxo próprio.
- **Docblocks.** Os comentários de `fimDaExpansaoDeChaves` e `semRedirecionamentos` em `cwd-efetivo.cjs` são corrigidos para o código atual.

Provado por `bash hooks/testa-gate-worktree.sh` e `bash hooks/testa-cwd-efetivo.sh`, com 0 falhas.

### 7. Texto de `powershell -Command`/`cmd /c` lido como PowerShell, não como bash (rodada 3, achado 1 da revisão 2) [tipo: implementar]
atende: D4, D6, D8
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `CHANGELOG.md`
depende de: 6
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const B=String.fromCharCode(92);process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"powershell -Command \"C:"+B+"Git"+B+"cmd"+B+"git.exe -C "+process.argv[2]+" commit -m x\""}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao: n/a
  motivo: subsumida pela união da tarefa 9 (decisão do usuário em 2026-10-16). Medido no corpus de 4012 execuções: a mutação da tarefa 7 só muda saídas de 0 para 2 (54 casos, todos escrita ou commit real no checkout principal dentro de wrapper PowerShell) e nenhuma de 2 para 0, então a bateria não tem como ficar vermelha sem barrar o que deveria ser barrado. A remoção do código fica na #530
pronto quando: o texto interno de um wrapper de shell Windows (`pwsh`, `powershell`, `cmd`, com ou sem `.exe`) é analisado com `ferramenta` = `"PowerShell"` (texto cru, sem `normalizarComando`) nos três pontos que recursam sobre `desempacotarWrapperDeString` em `hooks/gate-worktree.cjs` (hoje linhas ~157, ~556 e ~645). A decisão mora numa função pequena, `ferramentaDoInterno(segmento, ferramenta)`, cuja última linha é exatamente `return ehShellWindows ? "PowerShell" : ferramenta;` (alvo da mutação). Nenhum caso de teste lê o texto do fonte.
- Pelo gate real, tool Bash, cwd W: `powershell -Command "C:\Git\cmd\git.exe -C P commit -m x"` → **2** (era 2 na base 9f6b9ca3 e 0 na rodada 2); `powershell.exe -c "C:\PROGRA~1\Git\cmd\git.exe -C P commit --allow-empty -m x"` → **2**. Casos na bateria, com a contrabarra montada por `String.fromCharCode(92)` ou equivalente que o teste confira (o teste falha se a contrabarra sumir).
- Vizinhos legítimos continuam: `powershell -Command "git -C W status"` → 0; `bash -c 'echo x > f'` a partir de W → 0; os casos das tarefas 3 e 6 seguem verdes.
- CHANGELOG 1.67.6: o item "Limite conhecido" ganha o falso positivo residual `cd hooks; x=$(echo a; echo b > ../c)` (substituição sem aspas que cruza `;` é resolvida a partir do cwd inicial, e barra) e o primo `bash -c '…'` dentro da ferramenta PowerShell, os dois remetidos à #530.

Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas.

### 8. `git` de caminho Windows sem aspas mantém o `-C` no `cwdPorSegmento` (rodada 3, achado 3 da revisão 2) [tipo: implementar]
atende: D4
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`
depende de: 7
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const path=require("path");const {cwdPorSegmento}=require("./hooks/lib/cwd-efetivo.cjs");const B=String.fromCharCode(92);const r=cwdPorSegmento("C:"+B+"Git"+B+"cmd"+B+"git.exe -C "+process.argv[2]+" status",process.argv[1]);const n=(x)=>path.resolve(x).toLowerCase();process.exit(n(r[0].cwd)===n(process.argv[2])?0:1)' "$W" "$P"`
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const segGit = comandoEhGit(seg) ? seg : normalizarComando(seg).seg;`
  para: `const segGit = normalizarComando(seg).seg;`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: testa-cwd-efetivo.sh, secao "(#530) rodada 3: git de caminho Windows sem aspas mantem o -C"
pronto quando: no `cwdPorSegmento`, o segmento cujo texto cru já é `git` em posição de comando é lido cru; só o que não é git cru passa pela palavra normalizada (linha exata acima, alvo da mutação).
- `cwdPorSegmento("C:\Git\cmd\git.exe -C P status", W)[0].cwd` → P (na rodada 2 dava W; na base dava P). Mesmo para o segmento antes de `; codex exec x`.
- `{git,-C,P,status}` e `'git' -C P status` continuam dando P (casos da tarefa 2 verdes).

Provado por `bash hooks/testa-cwd-efetivo.sh` com 0 falhas.

### 9. União no reconhecimento do git: o cru ou o normalizado (rodada extra, decisão (a) do impasse) [tipo: implementar]
atende: D4, D6
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `CHANGELOG.md`
depende de: 8
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const B=String.fromCharCode(92);process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"powershell -c \"echo a; C:"+B+"PROGRA~1"+B+"Git"+B+"cmd"+B+"git.exe -C "+process.argv[2]+" commit --allow-empty -m x\""}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `return [palavras(String(texto)), palavras(textoLido(texto, ferramenta).seg)];`
  para: `return [palavras(textoLido(texto, ferramenta).seg)];`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: testa-gate-worktree.sh, secao "(#530) rodada extra: git reconhecido no texto cru ou no normalizado"
pronto quando: a leitura do bash só acrescenta bloqueio, nunca tira. Uma função `leiturasDoComando(texto, ferramenta)` devolve as duas listas de palavras: a do texto cru, exatamente como a base 9f6b9ca3 lia, e a da palavra normalizada. A última linha dela é exatamente `return [palavras(String(texto)), palavras(textoLido(texto, ferramenta).seg)];`, alvo da mutação; com a ferramenta PowerShell as duas listas coincidem. Nenhum caso de teste lê o texto do fonte.
- `subcomandoGit` procura o git nas duas leituras. Quem decide por verbo (`verboNaLinha`, `linhaDeRestauro` e quem mais chamar `subcomandoGit`) barra se **qualquer** leitura der verbo no conjunto. Ou seja, `subcomandoGit` devolve o subcomando de cada leitura que achou git (lista) e o chamador testa todos, ou um equivalente com o mesmo efeito.
- Pelo gate real, tool Bash, cwd W, sai **2**:
  - `powershell -c "echo a; C:\PROGRA~1\Git\cmd\git.exe -C P commit --allow-empty -m x"`;
  - `powershell -c "& C:\PROGRA~1\Git\cmd\git.exe -C P commit --allow-empty -m x"`;
  - `pwsh -c "echo a; C:\Git\cmd\git.exe -C P commit -m x"`;
  - `cmd /c "echo a & C:\Git\cmd\git.exe -C P commit -m x"`;
  - `x=$(powershell -c "cd P; C:\Git\cmd\git.exe commit -m x")`.

  Todos eram 2 na base e 0 na rodada 3. A contrabarra é montada no teste por `String.fromCharCode(92)` ou equivalente, e o teste falha se ela sumir.
- Vizinhos legítimos continuam **0**: `git status` e `git -C W log` a partir de W, e `powershell -Command "git -C W status"`. Os casos das tarefas 3, 6, 7 e 8 seguem verdes.
- **Diferencial:** o corpus do revisor (`r3diff.cjs`, 995 comandos × Bash e PowerShell × cwd W e W/hooks), rodado contra a base 9f6b9ca3 e o HEAD, dá **zero** linhas `2->nao2`. A integração roda e cola esse resultado.
- CHANGELOG 1.67.6: uma linha dizendo que o reconhecimento do git é a união da leitura crua com a do bash, e que por isso `C:\Git\cmd\git.exe -C P …` sem aspas no Bash continua barrado, como na base (conservador).

Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas e pelo diferencial com zero `2->nao2`.

### 10. Recursão do `subcomandoGit` uma vez por interno distinto, com teto (rodada extra 2) [tipo: implementar]
atende: D4, D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `CHANGELOG.md`
depende de: 9
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const c="'"'"'eval'"'"' ".repeat(22)+"\"git -C "+process.argv[2]+" commit --allow-empty -m x\"";process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:c}}))' "$W" "$P" | timeout 5 node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (profundidade < 4) achados.push(...subcomandoGit(interno, ferr, profundidade + 1));`
  para: `achados.push(...subcomandoGit(interno, ferr, profundidade + 1));`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: testa-gate-worktree.sh, secao "(#530) rodada extra 2: wrapper aninhado fundo nao explode nem passa"
pronto quando: `subcomandoGit` coleta os internos das duas leituras e recursa uma vez só por par distinto (texto interno, ferramenta do interno). A chave do par fica num `Set` chamado `internosVistos`. Recebe também `profundidade` e não recursa além de 4 níveis; a linha do teto é o alvo da mutação. (Emenda de 2026-10-16: o alvo era a linha do `Set`, mas com o teto o `Set` fica redundante — 2^4 chamadas — e a mutação dele saiu verde; medido: tirar o teto deixa `eval ` × 3000 em exit 1 por `RangeError`.) Daí em diante quem decide é o barramento por profundidade que já existe em `alvosBashEscrita` ("wrapper aninhado demais para conferir (mais de 4 niveis)"). Nenhum caso de teste lê o texto do fonte.
- Pelo gate real, tool Bash, cwd W, saem **2**, e cada um em menos de 2 s (o teste mede o tempo e falha acima disso, ou usa `timeout 5` e falha se estourar):
  - `'eval' ` × 22 seguido de `"git -C P commit --allow-empty -m x"`;
  - `\eval ` × 22 com a mesma cauda;
  - `'bash' -c '…'` aninhado 6 níveis com `git -C P commit` no fundo;
  - `eval ` × 3000 com a cauda citada. Na base sai 2; na rodada extra 1 saía 1 por `RangeError`.
- Vizinhos legítimos continuam **0**: `eval "git status"` e `bash -c 'git -C W log'` a partir de W. Os casos das tarefas 3, 6, 7, 8 e 9 seguem verdes.
- Diferencial do corpus do revisor (`r9diff.cjs`) contra a base 9f6b9ca3 continua com **zero** linhas `2->nao2`. A integração roda e cola o resultado.
- CHANGELOG 1.67.6: os itens de escrita dentro de `bash -c`/`eval` e de substituição dizem que valem para **escrita** (redirecionamento, `tee`, `cp`). Verbo de git com `cd` dentro do wrapper, como `bash -c 'cd P && git commit'`, fica no "Limite conhecido", remetido ao item 4 da #530.

Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas e pelo diferencial com zero `2->nao2`.

### 11. Teto do `subcomandoGit` falha fechado (rodada extra 2, achado do security review sobre a tarefa 10) [tipo: implementar]
atende: D4, D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 10
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && W=$(git rev-parse --show-toplevel) && node -e 'const c="iex ".repeat(5)+"'"'"'git -C "+process.argv[2]+" commit -m x'"'"'";process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:process.argv[1],hook_event_name:"PreToolUse",tool_name:"PowerShell",tool_input:{command:c}}))' "$W" "$P" | node hooks/gate-worktree.cjs >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (profundidade >= 4) achados.push(SUB_ANINHADO);`
  para: `if (false) achados.push(SUB_ANINHADO);`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: testa-gate-worktree.sh, secao "(#530) rodada extra 2: teto do subcomandoGit falha fechado"
pronto quando: no teto, com um wrapper legível ainda a desembrulhar, `subcomandoGit` devolve uma sentinela em vez de nada.
- A sentinela é a constante `SUB_ANINHADO`, um subcomando marcado `incerto: true`. A linha que a acrescenta vem logo depois da linha do teto da tarefa 10, que fica intacta, e é exatamente `if (profundidade >= 4) achados.push(SUB_ANINHADO);`. É o alvo da mutação.
- Todo chamador de `subcomandoGit` trata a sentinela como casamento e barra (exit 2): `verboNaLinha`, `linhaDeRestauro`, `moveOHead`, o `casa` de `alvosBash`, `alvosBash` e quem mais a usar. O motivo no stderr é "wrapper aninhado demais para conferir (mais de 4 niveis)". Nenhum caso de teste lê o texto do fonte.
- Pelo gate real, cwd W, saem **2**. Todos eram 2 na base 9f6b9ca3 e 0 no HEAD 61eef4a6:
  - `iex ` × 5 + `'git -C P commit -m x'`, na ferramenta PowerShell;
  - o mesmo × 8;
  - `Invoke-Expression ` × 5 com a mesma cauda.
- Vizinhos continuam: `iex 'git status'` → 0, e `iex ` × 3 + `'git -C W log'` → 0. Os casos das tarefas 3 e 6 a 10 seguem verdes.
- O diferencial do corpus do revisor (`r9diff.cjs`) contra a base continua com **zero** `2->nao2`, e a matriz `sec10.cjs` do scratchpad (`iex`, `cmd`, `powershell` e `eval` em 3 a 8 níveis, nas duas ferramentas) dá zero `base=2 head=0`. A integração roda os dois e cola o resultado.

Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas, mais o diferencial e a matriz.
