# Plano: gate-fechar-issue — here-string, contrabarra e `"$(...)"` não escondem mais o `gh`

Design: docs/rainforest/design/gate-segmentador.md

## O que não pode quebrar
- `bash hooks/testa-gate-fechar-issue.sh` continua verde (436 ok na base `e3d7896`), inclusive (ar), (as) e (crase-1) a (crase-16); a única expectativa existente que muda é a do (crase-12), de 2 para 0, na tarefa 5 (D6).
- As outras baterias que chamam o gate continuam verdes: `hooks/testa-gate-pr-flag-curta.sh`, `hooks/testa-gate-merge-auto.sh`, `hooks/testa-gate-receita-corpo.sh`, `hooks/testa-gate-staging-total.sh`, `node hooks/testa-gate-subagente-sem-gh.cjs`.
- PowerShell não ganha escape por contrabarra (D2).

## Molde dos casos de bateria (vale para as tarefas 1 a 4)
Todo caso novo entra em `hooks/testa-gate-fechar-issue.sh` logo depois do caso (crase-16) e antes do comentário `# R2 (rodada 9, lote 3, 2026-09-04)`, na ordem das tarefas. Cada caso copia o bloco (crase-16) inteiro, trocando só: o comentário `# Caso (X): ... → exit N (Dn de gate-segmentador)`, o título `echo "== (X) <descrição> → exit N =="`, o nome da variável (`COMANDO_X` com o `-` virando `_`, ex.: `COMANDO_HS_1`), o arquivo de stderr (`$SBP/err-X`), a variável de exit (`EXIT_X`) e o exit esperado no teste. Caso marcado PowerShell troca `tool_name:"Bash"` por `tool_name:"PowerShell"` no `node -e` do payload. A atribuição da variável é copiada LITERALMENTE da tabela da tarefa (uma string `$'...'` do bash; `\\` vira uma contrabarra e `\'` vira um apóstrofo). Cada caso soma exatamente 1 ok.

## Tarefas

### 1. Palavra do here-string volta ao laço principal [tipo: implementar]
atende: D1, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
busca:
- repo | grep -n "here-string" hooks/gate-fechar-issue.cjs | o ramo do <<< em segmentosParaGate engole a palavra com atual += cmd.slice(i, k)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `      i += 2; // D1 (gate-segmentador): a palavra do here-string volta ao laco`
  para: `      i = k - 1;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (hs-1), (hs-2) e (hs-3)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"cat <<< \u0060gh issue close 12\u0060"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), ``cat <<< `gh issue close 12` ``, ``cat <<< "`gh issue close 12`"`` e `cat <<< $(gh issue close 12)` saem 2, e `cat <<< "texto comum"` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 440 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (hs-1), (hs-2) e (hs-3) vermelhos.

Forma prescrita: no ramo `if (c === "<" && cmd[i + 1] === "<" && cmd[i + 2] === "<") {` de `segmentosParaGate`, trocar as duas linhas finais

```
      atual += cmd.slice(i, k);
      i = k - 1;
```

por

```
      atual += "<<<";
      i += 2; // D1 (gate-segmentador): a palavra do here-string volta ao laco
```

e acrescentar acima delas, com a mesma indentação, exatamente estas duas linhas de comentário:

```
      // D1 (gate-segmentador, Issue #689): o ramo consome so os tres `<`; a
      // palavra segue pelo laco, onde crase, aspas e $( tem ramo proprio.
```
 O cálculo de `k`/`conteudo`, a recursão de interpretador e o `TEXTOS_DE_HEREDOC.push(conteudo)` ficam como estão.

Casos (molde acima):
| caso | atribuição | exit |
|---|---|---|
| hs-1 | ``COMANDO_HS_1=$'cat <<< `gh issue close 12`'`` | 2 |
| hs-2 | ``COMANDO_HS_2=$'cat <<< "`gh issue close 12`"'`` | 2 |
| hs-3 | `COMANDO_HS_3=$'cat <<< $(gh issue close 12)'` | 2 |
| hs-4 | `COMANDO_HS_4=$'cat <<< "texto comum"'` | 0 |

### 2. Contrabarra fora de aspas escapa o caractere seguinte (Bash) [tipo: implementar]
atende: D2, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 1
busca:
- repo | grep -n "escapadaPorContrabarra" hooks/gate-fechar-issue.cjs | a paridade de contrabarra já existe para a crase; o rastreio de aspas não a usa
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `FERRAMENTA !== "PowerShell" && aspa === null &&`
  para: `false && aspa === null &&`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (cb-1) e (cb-2)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"echo \u005c\u0022; gh issue close 12"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse, `echo \"; gh issue close 12` e ``echo \'`gh issue close 12` `` (Bash) saem 2; `echo \"oi\"` (Bash) sai 0; `echo 'a\'; gh issue close 12` (Bash) continua 2; `cd C:\x\; gh issue close 12` e `Write-Host "C:\"; gh issue close 12` (PowerShell) continuam 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 446 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (cb-1) e (cb-2) vermelhos.

Forma prescrita: em `segmentosParaGate`, logo DEPOIS do bloco da crase (que termina em `continue;\n    }`) e ANTES de `if (aspa) {` (a primeira ocorrência do arquivo, dentro de `segmentosParaGate`; a de `comandoUnicoSemShell`, perto da linha 855, não muda), inserir:

```
    // D2 (gate-segmentador, Issue #689): no Bash, contrabarra fora de aspas
    // escapa o caractere seguinte (`echo \"; gh issue close 12` executa o gh).
    // No PowerShell a contrabarra e literal.
    if (FERRAMENTA !== "PowerShell" && aspa === null && c === "\\" && i + 1 < cmd.length) {
      atual += c + cmd[i + 1];
      i += 1;
      continue;
    }
```

Casos (molde acima):
| caso | atribuição | ferramenta | exit |
|---|---|---|---|
| cb-1 | `COMANDO_CB_1=$'echo \\"; gh issue close 12'` | Bash | 2 |
| cb-2 | ``COMANDO_CB_2=$'echo \\\'`gh issue close 12`'`` | Bash | 2 |
| cb-3 | `COMANDO_CB_3=$'echo \\"oi\\"'` | Bash | 0 |
| cb-4 | `COMANDO_CB_4=$'echo \'a\\\'; gh issue close 12'` | Bash | 2 |
| cb-5 | `COMANDO_CB_5=$'cd C:\\x\\; gh issue close 12'` | PowerShell | 2 |
| cb-6 | `COMANDO_CB_6=$'Write-Host "C:\\"; gh issue close 12'` | PowerShell | 2 |

### 3. Contrabarra dentro de aspas duplas e aspas ANSI-C (Bash) [tipo: implementar]
atende: D2, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 2
busca:
- repo | grep -n "if (c === aspa) aspa = null" hooks/gate-fechar-issue.cjs | o fecho de aspa ignora a contrabarra
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `return aspa === "$'" ||`
  para: `return false &&`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (ad-1) e (ad-2)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"echo \u0022\u005c\u0022\u0022; gh issue close 12"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `echo "\""; gh issue close 12`, `echo $'\''; gh issue close 12` e `echo \$'a\'; gh issue close 12` saem 2, e `echo "say \"oi\""` e ``echo $'`gh issue close 12`'`` saem 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 451 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (ad-1) e (ad-2) vermelhos.

Forma prescrita, quatro mudanças em `hooks/gate-fechar-issue.cjs`:
1. Logo depois de `let chamadasSegmentacao = 0;`, acrescentar:

```
// D2 (gate-segmentador, Issue #689): dentro de aspas duplas a contrabarra so
// escapa `"`, `\`, `$` e crase; em aspas ANSI-C ($'...') escapa qualquer um.
const ESCAPAVEIS_EM_ASPAS_DUPLAS = new Set(['"', "\\", "$", "`"]);
function escapaDentroDaAspa(aspa, proximo) {
  return aspa === "$'" || (aspa === '"' && ESCAPAVEIS_EM_ASPAS_DUPLAS.has(proximo));
}
```

2. No bloco da crase, a condição `if (c === "`" && aspa !== "'" && !escapadaPorContrabarra(cmd, i)) {` passa a `if (c === "`" && aspa !== "'" && aspa !== "$'" && !escapadaPorContrabarra(cmd, i)) {` (em `$'...'` a crase é literal).
3. Como PRIMEIRA coisa dentro de `if (aspa) {` de `segmentosParaGate` (antes do comentário do P4; não a de `comandoUnicoSemShell`), inserir:

```
      if (FERRAMENTA !== "PowerShell" && c === "\\" && i + 1 < cmd.length && escapaDentroDaAspa(aspa, cmd[i + 1])) {
        atual += c + cmd[i + 1];
        i += 1;
        continue;
      }
```

e trocar `if (c === aspa) aspa = null;` por `if (c === aspa || (aspa === "$'" && c === "'")) aspa = null;`.
4. Na abertura de aspa de `segmentosParaGate`, trocar a linha `      aspa = c;` que vem logo antes de `      atual += c;` (a de `comandoUnicoSemShell` vem antes de `continue;` e não muda) por:

```
      aspa = c === "'" && FERRAMENTA !== "PowerShell" && cmd[i - 1] === "$" && !escapadaPorContrabarra(cmd, i - 1) ? "$'" : c;
```

Casos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| ad-1 | `COMANDO_AD_1=$'echo "\\""; gh issue close 12'` | 2 |
| ad-2 | `COMANDO_AD_2=$'echo $\'\\\'\'; gh issue close 12'` | 2 |
| ad-3 | `COMANDO_AD_3=$'echo "say \\"oi\\""'` | 0 |
| ad-4 | ``COMANDO_AD_4=$'echo $\'`gh issue close 12`\''`` | 0 |
| ad-5 | `COMANDO_AD_5=$'echo \\$\'a\\\'; gh issue close 12'` | 2 |

### 4. `"$(...)"` com interior complexo e `gh` de escrita depois barra [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 3
busca:
- repo | grep -n "function temGhLiteralQueEscreve" hooks/gate-fechar-issue.cjs | busca textual de gh de escrita que ignora aspas; reaproveitada como gatilho
desfecho: compor
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (INTERIOR_COMPLEXO.test(interno) &&`
  para: `if (false &&`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (ps-1), (ps-3) e (ps-4)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"echo \u0022$(echo \u0027)\u0027 ; gh issue close 12)\u0022"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `echo "$(echo ')' ; gh issue close 12)"`, `echo "$(echo ')' && gh issue close 12)"`, `echo "$(echo ')' ; gh pr merge 5)"` e `echo "$(echo "'")"; gh issue close 12` saem 2, e `echo "$(echo ')' ; echo oi)"` e o commit por heredoc com apóstrofo e `)` solto sem `gh` saem 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 457 ok, 0 falha(s) ==` com exit 0, pelas baterias `hooks/testa-gate-pr-flag-curta.sh`, `hooks/testa-gate-merge-auto.sh`, `hooks/testa-gate-receita-corpo.sh`, `hooks/testa-gate-staging-total.sh` e `node hooks/testa-gate-subagente-sem-gh.cjs` saindo 0 cada uma, e pela mutação acima deixando (ps-1), (ps-3) e (ps-4) vermelhos.

Forma prescrita:
1. Logo depois de `let chamadasSegmentacao = 0;` (e do bloco da tarefa 3), acrescentar:

```
// D3 (gate-segmentador, Issue #689): interior de "$(...)" cujo fim a contagem
// de parenteses nao acha com seguranca (aspa, crase, comentario, heredoc,
// contrabarra, case).
const INTERIOR_COMPLEXO = /['"`#<\\]|\bcase\b/;
```

2. No ramo do P4 (`if (aspa === '"' && c === "$" && cmd[i + 1] === "(") {`), logo depois do `while` que monta `interno` e ANTES de `// A recursao (e nao o push cru) desce em crase e heredoc la dentro (D6).`, inserir:

```
        // D3 (gate-segmentador): o fim do $(...) sai da contagem de parenteses,
        // que nao entende aspas; com interior complexo o laco de fora pode
        // reler o resto com o estado de aspas errado. Com gh de escrita do $(
        // em diante, barra (falha fechada). Gatilho booleano: nao conta gh.
        if (INTERIOR_COMPLEXO.test(interno) && temGhLiteralQueEscreve(cmd.slice(i))) {
          bloqueia(
            "BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n" +
            "Razão: o comando tem \"$(...)\" com aspa, crase, comentário, heredoc ou case dentro, e um 'gh' que escreve depois dele;\n" +
            "o gate não acha o fim da substituição com segurança.\n\n" +
            "Rode o 'gh' em comando separado. Texto de corpo vai por --body-file ou git commit -F <arquivo>.\n"
          );
        }
```

Casos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| ps-1 | `COMANDO_PS_1=$'echo "$(echo \')\' ; gh issue close 12)"'` | 2 |
| ps-2 | `COMANDO_PS_2=$'echo "$(echo \')\' && gh issue close 12)"'` | 2 |
| ps-3 | `COMANDO_PS_3=$'echo "$(echo \')\' ; gh pr merge 5)"'` | 2 |
| ps-4 | `COMANDO_PS_4=$'echo "$(echo "\'")"; gh issue close 12'` | 2 |
| ps-5 | `COMANDO_PS_5=$'echo "$(echo \')\' ; echo oi)"'` | 0 |
| ps-6 | `COMANDO_PS_6=$'git commit -m "$(cat <<\'EOF\'\ndon\'t ) solto\nEOF\n)"'` | 0 |

Em ps-6, `\n` é uma contrabarra e um `n`, que o `$'...'` vira quebra de linha, no mesmo formato do (crase-16).

### 5. Forma canônica `"$(cat <<'DELIM' ... )"` é opaca e isenta do D3 [tipo: implementar]
atende: D4, D6
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 4
busca:
- repo | grep -n "function corpoDeHeredoc" hooks/gate-fechar-issue.cjs | o leitor geral de heredoc devolve corpo e fim, mas aqui só a forma canônica tem fim exato dentro de $(...); regex ancorada basta
desfecho: construir
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const canonico = HEREDOC_CANONICO.exec(cmd.slice(i));`
  para: `const canonico = null;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (hc-1) e (crase-12)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"git commit -m "$(cat <<'EOF'\nfoo " bar\nEOF\n)"; gh issue close 12"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), o commit canônico seguido de `&& gh issue comment 5 --body ok` sai 0; `git commit -m "$(cat <<'EOF'` + `foo " bar` + `EOF` + `)"; gh issue close 12` sai 2; e o (crase-12), commit canônico que cita `` `gh issue close` `` entre crases, passa de 2 para 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 459 ok, 0 falha(s) ==` com exit 0, pelas baterias `hooks/testa-gate-pr-flag-curta.sh`, `hooks/testa-gate-merge-auto.sh`, `hooks/testa-gate-receita-corpo.sh`, `hooks/testa-gate-staging-total.sh` e `node hooks/testa-gate-subagente-sem-gh.cjs` saindo 0 cada uma, e pela mutação acima deixando (hc-1) e (crase-12) vermelhos.

Forma prescrita:
1. Logo ANTES da linha `const INTERIOR_COMPLEXO = ...` (tarefa 4), acrescentar:

```
// D6 (gate-segmentador, Issue #689): "$(cat <<'DELIM'\n...\nDELIM\n)" tem fim
// exato (o bash fecha o heredoc na primeira linha igual ao delimitador) e o
// corpo de heredoc citado e literal. Essa forma e opaca para o laco de fora e
// fica fora do D3.
const HEREDOC_CANONICO = /^\$\(cat <<'([A-Za-z_][A-Za-z0-9_]*)'\n[\s\S]*?\n\1\n\)/;
```

2. Como PRIMEIRA coisa dentro do ramo do P4 (`if (aspa === '"' && c === "$" && cmd[i + 1] === "(") {`), antes de `let profundidade = 1;`, inserir:

```
        const canonico = HEREDOC_CANONICO.exec(cmd.slice(i));
        if (canonico) {
          for (const sub of segmentosParaGate(canonico[0].slice(2, -1))) {
            if (sub.trim()) segmentos.push(sub);
          }
          atual += canonico[0];
          i += canonico[0].length - 1;
          continue;
        }
```

3. Caso (crase-12) existente: trocar o exit esperado de 2 para 0 (`[ $EXIT_CRASE_12 -eq 0 ] && test_ok "exit 0"`), o título para `commit por heredoc canonico que cita gh de escrita em crase → exit 0`, e as duas linhas de comentário acima dele para `# Caso (crase-12): commit por heredoc canonico que cita gh de escrita em crase → exit 0 (D6 de gate-segmentador:` / `# o corpo de heredoc citado e literal; desfaz o falso positivo do D7 de gate-crase)`. A atribuição `COMANDO_CRASE_12` não muda. O número de casos não muda.

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| hc-1 | `COMANDO_HC_1=$'git commit -m "$(cat <<\'EOF\'\nfix: ajusta o texto\nEOF\n)" && gh issue comment 5 --body ok'` | 0 |
| hc-2 | `COMANDO_HC_2=$'git commit -m "$(cat <<\'EOF\'\nfoo " bar\nEOF\n)"; gh issue close 12'` | 2 |

### 7. Dialeto do texto de dentro do wrapper (revisão de segurança) [tipo: implementar]
atende: D7
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 5
busca:
- repo | grep -n "for (const sub of segmentosParaGate(interno)) {" hooks/gate-fechar-issue.cjs | a recursão do wrapper em processarSegmento roda com o FERRAMENTA global
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `FERRAMENTA = dialetoDoWrapper(toksComAspas[pos].v, anterior);`
  para: `FERRAMENTA = anterior;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (wd-1)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"PowerShell",tool_input:{command:"bash -c \u0027echo \u005c\u0022; gh issue close 12\u0027"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse, `bash -c 'echo \"; gh issue close 12'` pela ferramenta PowerShell sai 2 e `bash -c 'echo \"oi\"'` pela PowerShell sai 0; `pwsh -Command 'Write-Host "C:\"; gh issue close 12'` pelo Bash continua 2 e `pwsh -Command 'Write-Host "oi"'` pelo Bash continua 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 463 ok, 0 falha(s) ==` com exit 0, pelas baterias `hooks/testa-gate-pr-flag-curta.sh`, `hooks/testa-gate-merge-auto.sh`, `hooks/testa-gate-receita-corpo.sh`, `hooks/testa-gate-staging-total.sh` e `node hooks/testa-gate-subagente-sem-gh.cjs` saindo 0 cada uma, e pela mutação acima deixando (wd-1) vermelho.

Forma prescrita:
1. Logo depois da linha `let FERRAMENTA = "";`, acrescentar:

```
// D7 (gate-segmentador, Issue #689): o texto de dentro de um wrapper segue as
// regras de aspas e escape do wrapper, nao as da ferramenta que o chamou.
const WRAPPERS_BASH = new Set(["bash", "sh", "zsh", "ksh", "dash", "eval"]);
const WRAPPERS_POWERSHELL = new Set(["pwsh", "powershell", "cmd", "invoke-expression", "iex"]);
function dialetoDoWrapper(token, atual) {
  const exe = normalizarExecutavel(token);
  if (WRAPPERS_BASH.has(exe)) return "Bash";
  if (WRAPPERS_POWERSHELL.has(exe)) return "PowerShell";
  return atual;
}
```

2. Em `processarSegmento`, trocar o bloco

```
  if (interno !== null) {
    for (const sub of segmentosParaGate(interno)) {
      processarSegmento(sub, mapaCwd, contadores, ferramenta);
    }
    return;
  }
```

por

```
  if (interno !== null) {
    const anterior = FERRAMENTA;
    FERRAMENTA = dialetoDoWrapper(toksComAspas[pos].v, anterior);
    try {
      for (const sub of segmentosParaGate(interno)) {
        processarSegmento(sub, mapaCwd, contadores, ferramenta);
      }
    } finally {
      FERRAMENTA = anterior;
    }
    return;
  }
```

Casos novos (molde acima):
| caso | atribuição | ferramenta | exit |
|---|---|---|---|
| wd-1 | `COMANDO_WD_1=$'bash -c \'echo \\"; gh issue close 12\''` | PowerShell | 2 |
| wd-2 | `COMANDO_WD_2=$'bash -c \'echo \\"oi\\"\''` | PowerShell | 0 |
| wd-3 | `COMANDO_WD_3=$'pwsh -Command \'Write-Host "C:\\"; gh issue close 12\''` | Bash | 2 |
| wd-4 | `COMANDO_WD_4=$'pwsh -Command \'Write-Host "oi"\''` | Bash | 0 |

### 8. Heredoc canônico só com fim exato (revisão 1) [tipo: implementar]
atende: D6
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 7
busca:
- repo | grep -n "HEREDOC_CANONICO.exec" hooks/gate-fechar-issue.cjs | o atalho da tarefa 5 aceita o primeiro \nDELIM\n) mesmo com um DELIM anterior
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const fimExato = canonico !== null && canonico[0].indexOf(`
  para: `const fimExato = canonico !== null; const ignorado = canonico !== null && canonico[0].indexOf(`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (hc-3)`
prova: `bash -c 'test "$(grep -c "const fimExato = " hooks/gate-fechar-issue.cjs)" -eq 1'`
pronto quando: com o payload real de PreToolUse (Bash), o comando de várias linhas `echo "$(cat <<'EOF'` / `x` / `EOF` / `echo '` / `EOF` / `)'` / `gh issue close 12` / `echo ')')"` sai 2 (o bash executa o `gh`), e (hc-1), (hc-2), (crase-12) e (ps-6) continuam com o exit de antes — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 464 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (hc-3) vermelho.

Forma prescrita: no ramo do P4, trocar

```
        if (canonico) {
```

por

```
        // A primeira linha igual ao delimitador tem de ser a que vem antes do
        // `)`: um DELIM anterior fecha o heredoc no bash, e o resto executa
        // (revisao 1 do gate-segmentador).
        const fimExato = canonico !== null && canonico[0].indexOf("\n" + canonico[1] + "\n") === canonico[0].length - canonico[1].length - 3;
        if (fimExato) {
```

Caso novo (molde acima, Bash):
| caso | atribuição | exit |
|---|---|---|
| hc-3 | `COMANDO_HC_3=$'echo "$(cat <<\'EOF\'\nx\nEOF\necho \'\nEOF\n)\'\ngh issue close 12\necho \')\')"'` | 2 |

### 9. `tokensComAspas` com a contrabarra do Bash na remontagem do wrapper (revisão 1) [tipo: implementar]
atende: D8
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 8
busca:
- repo | grep -n "function tokensComAspas" hooks/lib/tokens-comando.cjs | ignora a contrabarra; textoAPartir remonta o wrapper a partir desses tokens
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `tokensComAspas(segmento, { contrabarra: FERRAMENTA !== "PowerShell" })`
  para: `tokensComAspas(segmento, { contrabarra: false })`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (cw-1), (cw-2) e (cw-3)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"bash -c "echo \\\"; gh issue close 12""}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `bash -c "echo \\\"; gh issue close 12"`, `eval "echo \\\"; gh issue close 12"` e `sh -c "echo \\\"; gh pr merge 5"` saem 2, e `bash -c "echo \"oi\""` sai 0; (#313d) e (#339) continuam verdes — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 468 ok, 0 falha(s) ==` com exit 0; por `bash hooks/testa-gate-staging-total.sh`, `bash hooks/testa-cwd-efetivo.sh`, `bash hooks/testa-gate-mensagem-commit.sh`, `node hooks/testa-colapso-continuacao.cjs`, `bash hooks/testa-gate-pr-flag-curta.sh`, `bash hooks/testa-gate-merge-auto.sh`, `bash hooks/testa-gate-receita-corpo.sh` e `node hooks/testa-gate-subagente-sem-gh.cjs` saindo 0 cada uma; e pela mutação acima deixando (cw-1), (cw-2) e (cw-3) vermelhos.

Forma prescrita:
1. Em `hooks/lib/tokens-comando.cjs`, a assinatura `function tokensComAspas(cmd) {` passa a `function tokensComAspas(cmd, opcoes = {}) {`, e como PRIMEIRA coisa dentro do `for`, logo depois de `const c = cmd[i];`, entra:

```
    // D8 (gate-segmentador, Issue #689): com `opcoes.contrabarra` (Bash), fora
    // de aspas simples a contrabarra e o caractere seguinte entram crus no
    // token e nao abrem, fecham nem separam. Sem a opcao, nada muda.
    if (opcoes.contrabarra && c === "\\" && aspa !== "'" && i + 1 < cmd.length) {
      atual += c + cmd[i + 1];
      i += 1;
      temAlgo = true;
      continue;
    }
```

   Acrescentar ao docblock de `tokensComAspas` uma linha dizendo que a opção `contrabarra` existe e quem a usa (o `processarSegmento` do `gate-fechar-issue`).
2. Em `hooks/gate-fechar-issue.cjs`, em `processarSegmento`, a linha `  const toksComAspas = tokensComAspas(segmento);` passa a `  const toksComAspas = tokensComAspas(segmento, { contrabarra: FERRAMENTA !== "PowerShell" });`. Nenhuma outra chamada de `tokensComAspas` muda.

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| cw-1 | `COMANDO_CW_1=$'bash -c "echo \\\\\\"; gh issue close 12"'` | 2 |
| cw-2 | `COMANDO_CW_2=$'eval "echo \\\\\\"; gh issue close 12"'` | 2 |
| cw-3 | `COMANDO_CW_3=$'sh -c "echo \\\\\\"; gh pr merge 5"'` | 2 |
| cw-4 | `COMANDO_CW_4=$'bash -c "echo \\"oi\\""'` | 0 |

### 10. Comentário de shell vai até o fim da linha (revisão 1) [tipo: implementar]
atende: D9
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 9
busca:
- repo | grep -n "idxComentario" hooks/gate-fechar-issue.cjs | o comentario ja e tratado na W2 e no heredoc, mas nao no laco de segmentosParaGate
desfecho: estender
mutacao: n/a
  motivo: D9 revogado na 4ª rodada (decisão do Luís, 2026-11-12); o código desta tarefa foi removido pela tarefa 16
prova-na-base: verde — D9 revogado; o comportamento volta ao da base
pronto quando: com o payload real de PreToolUse (Bash), `# it's done` + quebra + `gh issue close 12` e `git status` + quebra + `# don't forget` + quebra + `gh pr merge 5 --squash` saem 2, e `echo a#b; echo 'x'` e `echo hi # comentario` saem 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 472 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (cm-1) e (cm-2) vermelhos.

Forma prescrita: em `segmentosParaGate`, logo DEPOIS do bloco do D2 que termina em `      i += 1;\n      continue;\n    }` (o `if (FERRAMENTA !== "PowerShell" && aspa === null && c === "\\" ...`) e ANTES da primeira ocorrência de `    if (aspa) {`, inserir:

```
    // D9 (gate-segmentador, Issue #689): comentario de shell fora de aspas vai
    // ate o fim da linha; o apostrofo dele nao abre aspa.
    if (aspa === null && c === "#" && (i === 0 || /[\s;&|()]/.test(cmd[i - 1]))) {
      while (i < cmd.length && cmd[i] !== "\n") {
        atual += cmd[i];
        i += 1;
      }
      i -= 1;
      continue;
    }
```

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| cm-1 | `COMANDO_CM_1=$'# it\'s done\ngh issue close 12'` | 2 |
| cm-2 | `COMANDO_CM_2=$'git status\n# don\'t forget\ngh pr merge 5 --squash'` | 2 |
| cm-3 | `COMANDO_CM_3=$'echo a#b; echo \'x\''` | 0 |
| cm-4 | `COMANDO_CM_4=$'echo hi # comentario'` | 0 |

### 11. Contrabarra fora de aspas some na remontagem do wrapper (revisão de segurança) [tipo: implementar]
atende: D8
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 10
busca:
- repo | grep -n "function textoAPartir" hooks/lib/tokens-comando.cjs | remonta token sem aspas cru; com espaço dentro ele se parte em várias palavras
desfecho: estender
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `atual += aspa === null ? cmd[i + 1] : c + cmd[i + 1];`
  para: `atual += c + cmd[i + 1];`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (cw-5) e (cw-6)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"eval gh\ issue\ close\ 12"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `eval gh\ issue\ close\ 12` e `bash -c gh\ pr\ merge\ 5` saem 2 e `eval gh\ issue\ view\ 12` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 475 ok, 0 falha(s) ==` com exit 0; por `bash hooks/testa-gate-staging-total.sh`, `bash hooks/testa-cwd-efetivo.sh`, `bash hooks/testa-gate-mensagem-commit.sh` e `node hooks/testa-colapso-continuacao.cjs` saindo 0; e pela mutação acima deixando (cw-5) e (cw-6) vermelhos.

Forma prescrita, em `hooks/lib/tokens-comando.cjs`:
1. No ramo `if (opcoes.contrabarra && c === "\\" ...)` de `tokensComAspas`, a linha `      atual += c + cmd[i + 1];` passa a `      atual += aspa === null ? cmd[i + 1] : c + cmd[i + 1];`, e o comentário do ramo ganha: fora de aspas a contrabarra some (remoção do bash); dentro de aspas duplas o par fica cru para o `desempacota` reduzir (#313).
2. Em `textoAPartir`, o token sem aspas que tenha espaço passa a ser citado entre aspas simples (aspa simples de dentro vira `'\''`): o `.map` passa a `(t) => (t.q ? (t.aspa === "'" ? `'${t.v}'` : `"${t.v}"`) : (/\s/.test(t.v) ? `'${t.v.replace(/'/g, "'\\''")}'` : t.v))`. Sem a opção `contrabarra`, token sem aspas nunca tem espaço, então os outros gates não mudam.

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| cw-5 | `COMANDO_CW_5=$'eval gh\\ issue\\ close\\ 12'` | 2 |
| cw-6 | `COMANDO_CW_6=$'bash -c gh\\ pr\\ merge\\ 5'` | 2 |
| cw-7 | `COMANDO_CW_7=$'eval gh\\ issue\\ view\\ 12'` | 0 |

### 12. Comentário só começa em fronteira não escapada (revisão de segurança) [tipo: implementar]
atende: D9
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 11
prova-na-base: verde — D9 revogado; o comportamento volta ao da base
mutacao: n/a
  motivo: D9 revogado na 4ª rodada (decisão do Luís, 2026-11-12); o código desta tarefa foi removido pela tarefa 16
pronto quando: com o payload real de PreToolUse (Bash), `echo \ #; gh issue close 12` e `echo \;#x; gh pr merge 5` saem 2 e (cm-1) a (cm-4) mantêm o exit — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 477 ok, 0 falha(s) ==` com exit 0.

Forma prescrita: em `segmentosParaGate`, a condição do D9 `if (aspa === null && c === "#" && (i === 0 || /[\s;&|()]/.test(cmd[i - 1]))) {` passa a `if (aspa === null && c === "#" && (i === 0 || (/[\s;&|()]/.test(cmd[i - 1]) && !escapadaPorContrabarra(cmd, i - 1)))) {`.

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| cm-5 | `COMANDO_CM_5=$'echo \\ #; gh issue close 12'` | 2 |
| cm-6 | `COMANDO_CM_6=$'echo \\;#x; gh pr merge 5'` | 2 |

### 13. Comentário falha fechado nos separadores (revisão 2) [tipo: implementar]
atende: D9
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 12
busca:
- repo | grep -n "D9 (gate-segmentador" hooks/gate-fechar-issue.cjs | o ramo do comentario engole ; e && ate a quebra de linha
desfecho: estender
mutacao: n/a
  motivo: D9 revogado na 4ª rodada (decisão do Luís, 2026-11-12); o código desta tarefa foi removido pela tarefa 16
prova-na-base: verde — D9 revogado; o comportamento volta ao da base
pronto quando: com o payload real de PreToolUse (Bash), `echo $(true)#; gh issue close 12`, `echo ${x:-a #b}; gh issue close 12` e `a=(x)#; gh issue close 12` saem 2, e (cm-1) a (cm-6) mantêm o exit — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 480 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (cm-7), (cm-8) e (cm-9) vermelhos.

Forma prescrita: no ramo do D9, o laço que consome o comentário passa a juntar o texto numa variável `comentario`, que entra em `atual`; depois, cada pedaço do comentário após um `;`, `&` ou `|` vira segmento:

```
      let comentario = "";
      while (i < cmd.length && cmd[i] !== "\n") {
        comentario += cmd[i];
        i += 1;
      }
      atual += comentario;
      // Falha fechada (revisao 2): o gate nao sabe sempre se o # abre
      // comentario (`$(true)#`, `${x:-a #b}`); o resto depois de ; & | e
      // conferido como comando.
      for (const pedaco of comentario.split(/[;&|]+/).slice(1)) {
        if (pedaco.trim()) segmentos.push(pedaco);
      }
      i -= 1;
      continue;
```

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| cm-7 | `COMANDO_CM_7=$'echo $(true)#; gh issue close 12'` | 2 |
| cm-8 | `COMANDO_CM_8=$'echo ${x:-a #b}; gh issue close 12'` | 2 |
| cm-9 | `COMANDO_CM_9=$'a=(x)#; gh issue close 12'` | 2 |

### 14. Here-string entre aspas duplas reduz a contrabarra (revisão 2) [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 13
busca:
- repo | grep -n "fecha a aspa" hooks/gate-fechar-issue.cjs | a extracao do conteudo do here-string citado para na primeira aspa, escapada ou nao
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `ESCAPAVEIS_EM_ASPAS_DUPLAS.has(cmd[k + 1])) { conteudo += cmd[k + 1]; k += 2; continue; }`
  para: `false) { conteudo += cmd[k + 1]; k += 2; continue; }`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (hs-5) e (hs-6)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"bash <<< "echo \"hi\"; gh issue close 12""}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `bash <<< "echo \\\"; gh issue close 12"` e `bash <<< "echo \"hi\"; gh issue close 12"` saem 2, e `cat <<< "texto \"citado\""` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 483 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (hs-5) e (hs-6) vermelhos.

Forma prescrita: no ramo do `<<<`, o laço de aspa `while (k < cmd.length && cmd[k] !== aspa) { conteudo += cmd[k]; k++; }` passa a:

```
        while (k < cmd.length && cmd[k] !== aspa) {
          // Entre aspas duplas a contrabarra escapa ", \, $ e crase, como no
          // bash (revisao 2 do gate-segmentador).
          if (aspa === '"' && cmd[k] === '\\' && k + 1 < cmd.length && ESCAPAVEIS_EM_ASPAS_DUPLAS.has(cmd[k + 1])) { conteudo += cmd[k + 1]; k += 2; continue; }
          conteudo += cmd[k]; k++;
        }
```

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| hs-5 | `COMANDO_HS_5=$'bash <<< "echo \\\\\\"; gh issue close 12"'` | 2 |
| hs-6 | `COMANDO_HS_6=$'bash <<< "echo \\"hi\\"; gh issue close 12"'` | 2 |
| hs-8 | `COMANDO_HS_8=$'cat <<< "texto \\"citado\\""'` | 0 |

### 15. Linhas de `TEXTOS_DE_HEREDOC` com a contrabarra do Bash (revisão 2) [tipo: implementar]
atende: D1, D8
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 14
busca:
- repo | grep -n "function verificarTextosDeHeredoc" hooks/gate-fechar-issue.cjs | tokeniza cada linha sem a opcao contrabarra
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `try { toks = tokensComAspas(linha, { contrabarra: FERRAMENTA !== "PowerShell" }); }`
  para: `try { toks = tokensComAspas(linha); }`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (hs-7)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"cat <<< "echo \\\"; gh issue close 12" | bash"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `cat <<< "echo \\\"; gh issue close 12" | bash` sai 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 484 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (hs-7) vermelho.

Forma prescrita: em `verificarTextosDeHeredoc`, `try { toks = tokensComAspas(linha); }` passa a `try { toks = tokensComAspas(linha, { contrabarra: FERRAMENTA !== "PowerShell" }); }`.

Caso novo (molde acima, Bash):
| caso | atribuição | exit |
|---|---|---|
| hs-7 | `COMANDO_HS_7=$'cat <<< "echo \\\\\\"; gh issue close 12" \| bash'` | 2 |

### 16. Revoga o D9: o `#` volta ao comportamento da base (4ª rodada) [tipo: implementar]
atende: D9
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 15
prova-na-base: verde — remoção de código; na base o `#` já não era tratado
mutacao: n/a
  motivo: remoção; não há comportamento novo a inverter, e os vizinhos (cm-3) a (cm-9) medem que o `#` voltou ao da base
pronto quando: com o payload real de PreToolUse (Bash), `echo $(true)#$(gh issue close 12)` e `echo ${x:-a #b}$(gh issue close 12)` saem 2 (como na base), e (cm-3) a (cm-9) mantêm o exit — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 484 ok, 0 falha(s) ==` com exit 0 (os casos (cm-1) e (cm-2), que exigiam o D9, saem da bateria).

Forma prescrita: em `segmentosParaGate`, remover o bloco inteiro do D9 (do comentário `// D9 (gate-segmentador, Issue #689): comentario de shell fora de aspas vai` até o `continue;` que fecha o `if`, antes de `if (aspa) {`); em `hooks/testa-gate-fechar-issue.sh`, remover os casos (cm-1) e (cm-2).

### 17. Here-string lê a palavra inteira, com trechos citados colados (revisão 3) [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 16
busca:
- repo | grep -n "let conteudo = ''" hooks/gate-fechar-issue.cjs | a extracao separava palavra citada de palavra nua e parava na primeira ; da palavra nua
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const aspaDaPalavra = cmd[k] === "'" || cmd[k] === '"' ? cmd[k] : null;`
  para: `const aspaDaPalavra = null;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (hs-9) e (hs-10)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"bash <<< 'echo x'"; gh issue close 12""}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `bash <<< echo\ x";gh issue close 12"` e `bash <<< 'echo x'"; gh issue close 12"` saem 2, e (hs-4), (hs-8) e os here-strings de interpretador existentes mantêm o exit — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 484 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (hs-9) e (hs-10) vermelhos.

Forma prescrita: no ramo do `<<<`, os dois ramos da extração (palavra citada / palavra nua) viram um laço só que lê a palavra até espaço, `;`, `&` ou `|` fora de aspas; dentro dele, uma aspa abre um trecho citado (com a redução de contrabarra das aspas duplas) e, fora de aspas, a contrabarra escapa o caractere seguinte.

Casos novos (molde acima, todos Bash):
| caso | atribuição | exit |
|---|---|---|
| hs-9 | `COMANDO_HS_9=$'bash <<< echo\\ x";gh issue close 12"'` | 2 |
| hs-10 | `COMANDO_HS_10=$'bash <<< \'echo x\'"; gh issue close 12"'` | 2 |

### 18. `$'` só abre ANSI-C com `$` ímpar colado na aspa (revisão 4) [tipo: implementar]
atende: D2
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 17
busca:
- repo | grep -n 'cmd\[i - 1\] === "\$"' hooks/gate-fechar-issue.cjs | a abertura do `$'` olhava um `$` só e tomava `$$'` (PID + aspa simples) por ANSI-C
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `return n % 2 !== 0;`
  para: `return n > 0;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (ad-6)`
prova-na-base: verde — regressão aberta pelo próprio diff (tarefa 2); a base já barrava o caso com exit 2
pronto quando: com o payload real de PreToolUse (Bash), `echo $$'\'; bash -c 'gh issue close 12'; echo '\'` sai 2 (saía 0 no HEAD da revisão 4, 2 na base) e `echo $$$'\''; gh issue close 12` sai 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 486 ok, 0 falha(s) ==` com exit 0, e pela mutação acima deixando (ad-6) vermelho.

Forma prescrita: função `abreAnsiC(s, i)` conta os `$` colados antes da aspa, desconta o primeiro se escapado por contrabarra, e devolve se a contagem é ímpar; o ramo de abertura de aspa usa `abreAnsiC(cmd, i)` no lugar de `cmd[i - 1] === "$"`.

Casos novos: (ad-6) `echo $$'\'; bash -c 'gh issue close 12'; echo '\'` → 2; (ad-7) `echo $$$'\''; gh issue close 12` → 2.

### 19. `eval` do bash junta os valores das palavras (revisão 5) [tipo: implementar]
atende: D8
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 18
busca:
- repo | grep -n "desempacotarWrapperDeString(textoAPartir" hooks/gate-fechar-issue.cjs | o eval passava pelo desempacotador de string, que remonta as palavras com aspas e não junta os valores
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const ehEvalDoBash = pos !== null && FERRAMENTA !== "PowerShell" && toksComAspas[pos].v === "eval" && pos + 1 < toksComAspas.length;`
  para: `const ehEvalDoBash = false;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (cw-8) e (cw-9)`
prova-na-base: verde — regressão aberta pelo próprio diff (tarefa 9, D8); a base já barrava os casos com exit 2
pronto quando: com o payload real de PreToolUse (Bash), `eval echo\ x\;gh pr merge 5`, `eval x \;\ gh\ issue\ close\ 12` e `eval echo\ \'x\'\;\ gh\ issue\ close\ 12` saem 2 (saíam 0 no HEAD da revisão 5, 2 na base), e `eval echo\ \'oi\'\;\ gh\ issue\ view\ 12` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 492 ok, 0 falha(s) ==` com exit 0, pela mutação acima deixando (cw-8) e (cw-9) vermelhos ((cw-10) também é coberto pela tarefa 20), e pelo fuzz do revisor (`node fuzz.cjs 800 <seed> ran g3`, sementes 1 a 3) sem nenhum caso "HEAD 0 / base 2".

Forma prescrita: em `processarSegmento`, quando o token na posição de comando é `eval` e o dialeto corrente (`FERRAMENTA`) não é PowerShell, o `interno` é a junção com espaço dos valores das palavras seguintes (valor de token entre aspas duplas com o escape reduzido por `reduzEscapeAspasDuplas`), e `ilegivel` sai de `contemConstrucaoIlegivel` sobre ele; os outros wrappers seguem por `desempacotarWrapperDeString`.

### 20. Palavra com espaço volta entre aspas duplas escapadas (revisão 5) [tipo: implementar]
atende: D8
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 19
busca:
- repo | grep -n "function textoAPartir" hooks/lib/tokens-comando.cjs | a remontagem com aspas simples e '\\'' não era revertida pelo desempacota
desfecho: estender
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `'"' + t.v.replace(/[\\"$\x60]/g, "\\$&") + '"'`
  para: `"'" + t.v.replace(/'/g, "'\\''") + "'"`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (cw-11)`
prova-na-base: verde — regressão aberta pelo próprio diff (tarefa 9, D8); a base já barrava o caso com exit 2
pronto quando: com o payload real de PreToolUse (Bash), `bash -c echo\ \'x\'\;\ gh\ issue\ close\ 12` sai 2 e `bash -c echo\ \'oi\'` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 492 ok, 0 falha(s) ==` com exit 0 e pela mutação acima deixando (cw-11) vermelho.

Forma prescrita: em `textoAPartir`, token sem aspas com espaço (só nasce da opção `contrabarra`) sai entre aspas duplas com contrabarra antes de contrabarra, aspa dupla, cifrão e crase (crase escrita como `\x60` na classe), que o `desempacota` reduz ao valor exato.

Emenda da 7ª rodada (revisão 6; Q1 A do Luís em 2026-11-12): as tarefas 21 a 23 fecham os achados 1 a 3 da revisão 6. A bateria passa a 512 ok (492 + os 20 casos (mx) e (ac); (mx-14) e (mx-15) vieram da revisão de segurança do commit 5513b4d3 (ANSI-C montando o `gh`); (mx-11) a (mx-13) vieram da revisão de segurança do commit f06775e7 (flag entre o substantivo e o verbo, expansão de chaves); (mx-9), (mx-10) e (ac-5) vieram da revisão de segurança do commit 60835732: o `gh` fora da palavra mista e o `\U` de 8 dígitos).

### 21. Palavra de aspas mistas com contrabarra e `gh` de escrita dentro de wrapper é ilegível (revisão 6) [tipo: implementar]
atende: D8
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 6, 20
busca:
- repo | grep -n "primeiraAspa" hooks/lib/tokens-comando.cjs | o token guarda só a primeira aspa; o internoDoEval e o textoAPartir reduzem a palavra inteira por ela
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (ilegivel || mistaComGh) {`
  para: `if (ilegivel) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (mx-1) a (mx-5)`
prova-na-base: verde — a base também deixa passar (mx-1) e (mx-3) a (mx-5) e barra (mx-2) só por acidente; a prova é a mutação acima, que reabre os cinco
pronto quando: com o payload real de PreToolUse (Bash), `eval "echo"' \"; gh issue close 12'`, `bash -c "echo"' \"; gh issue close 12'`, `eval ""'echo \"; gh pr merge 5'`, `time eval "echo"' \"; gh issue close 12'` e `eval "e"'cho \"'"; gh pr merge 5"` saem 2 (o bash executa o `gh` nos cinco, conferido com o stub de `gh`), o vizinho `echo "a"' \"; gh issue close 12'` (sem wrapper) sai 0, e `eval "echo"' \"oi'` e `bash -c "gh issue view 12"' --json \"title\"'` saem 2 (falso positivo aceito: a palavra mista com contrabarra dentro de wrapper barra sempre) — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 512 ok, 0 falha(s) ==` com exit 0 e pela mutação acima deixando (mx-1) vermelho.

Forma prescrita: `tokensComAspas` guarda, por palavra, os modos de citação vistos (aspas duplas, simples, fora de aspas; abrir a aspa conta, mesmo vazia) e o token com mais de um modo sai com `mista: true` (sem mistura, o campo não existe). Em `processarSegmento`, depois de achar o `interno` do wrapper, `mistaComGh` é verdadeiro quando algum token depois da posição de comando é misto e tem contrabarra, sem procurar `gh` (falha fechada, como `bash -c "$x"`): três revisões de segurança seguidas acharam um jeito de esconder o `gh` de qualquer procura (flag entre o substantivo e o verbo, chaves, ANSI-C); `ilegivel || mistaComGh` barra.

### 22. A rede do D3 decodifica o ANSI-C antes de procurar o `gh` (revisão 6) [tipo: implementar]
atende: D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 21
busca:
- repo | grep -n "function semContrabarra" hooks/lib/tokens-comando.cjs | a decodificação de `\xHH`, `\u` e octal já existe para o nome de comando; a rede do D3 não a aplicava
desfecho: estender
mutacao: n/a
  motivo: decodificação revogada na 8ª rodada (Q1 B do Luís, 2026-11-12); o código foi removido pela tarefa 24
prova-na-base: verde — tarefa revogada; o código saiu na tarefa 24
pronto quando: com o payload real de PreToolUse (Bash), `echo "$(echo ')' ; gh issue $'clo\x73e' 12)"`, `echo "$(echo ')' ; gh issue $'cl\157se' 12)"` e `echo "$(echo ')' ; $'\x67h' issue close 12)"` saem 2 (o bash executa `gh issue close 12` nos três, conferido com o stub), e `echo "$(echo ')' ; echo $'clo\x73e')"` sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 512 ok, 0 falha(s) ==` com exit 0 e pela mutação acima deixando (ac-1) vermelho.

Forma prescrita: em `temGhLiteralQueEscreve`, antes de tirar aspas, cada `$'...'` do texto tem `\xHH`, `\uHHHH` e `\UHHHHHHHH` (até 0x10FFFF) e octal de até três dígitos trocados pelo caractere; fora de `$'...'` nada muda.

### 23. CHANGELOG restaurado e os falsos positivos da revisão 6 [tipo: docs]
atende: D4
arquivos: `CHANGELOG.md`
depende de: 22
mutacao: n/a
  motivo: só texto; o comportamento está medido pelas tarefas 21 e 22, e a falsificação é a coerência do CHANGELOG com o da base mais a entrada 2.12.3
pronto quando: o `CHANGELOG.md` tem o mesmo número de linhas da base mais as linhas da entrada `## 2.13.3` (antes 2.12.3) (uma ocorrência de `## 2.12.2`, nenhuma linha truncada), e a entrada 2.12.3 diz, pelo comportamento, que a palavra de aspas mistas dentro de `eval`/`bash -c` com `gh` de escrita passa a barrar e que o ANSI-C dentro de `"$(...)"` continua escapando (Issue #694, emenda da 8ª rodada), e nomeia os dois falsos positivos aceitos da emenda do D4 com o contorno — conferido por `grep -c '^## 2.12.2' CHANGELOG.md` devolvendo `1`, `git diff --stat e3d7896d -- CHANGELOG.md` mostrando só inserções, e a leitura da entrada contra a D3, a D4 e a D8.

### 24. A rede do D3 volta a não decodificar ANSI-C (revisão 7) [tipo: implementar]
atende: D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 23
busca:
- repo | git show b4864bbc:hooks/gate-fechar-issue.cjs | a linha `const v = String(texto).replace(` da 6ª rodada, que barrava o caso (r8-1)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const v = String(texto).replace(/\$(?=["'])/g, "")`
  para: `const v = String(texto).replace(/\$'((?:[^'\\]|\\[\s\S])*)'/g, (_, c) => "'" + c.replace(/\\u([0-9a-fA-F]{1,4})/g, (__, h) => String.fromCharCode(parseInt(h, 16))) + "'").replace(/\$(?=["'])/g, "")`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, caso (r8-1)`
prova-na-base: verde — a base (e3d7896) não decodifica e já barra (r8-1); a regressão só existia no HEAD da 7ª rodada, e a prova é a mutação acima, que a reabre
pronto quando: com o payload real de PreToolUse (Bash), `echo "$(echo ')' ; echo '$' ; gh iss\ue close 12 ; echo 'x')"` sai 2 (o bash executa `gh issue close 12`, conferido pelo revisor 7 com o stub) e `echo "$(echo ')' ; echo $'clo\x73e')"` (ac-4) segue 0; os casos (ac-1), (ac-2), (ac-3) e (ac-5) saem da bateria, porque a base também os deixa passar e a classe fica na Issue #694 — provado por `bash hooks/testa-gate-fechar-issue.sh` com exit 0 e 0 falha(s) e pela mutação acima deixando (r8-1) vermelho.

Forma prescrita: `temGhLiteralQueEscreve` volta à linha da 6ª rodada: `const v = String(texto).replace(/\$(?=["'])/g, "")...`, sem a variável `ansiC`.

### 25. Palavra mista com contrabarra só barra no dialeto do bash (revisão 7) [tipo: implementar]
atende: D8
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 24
busca:
- repo | grep -n "exe === \"cmd\"\|exe === \"pwsh\"\|exe === \"&\"" hooks/lib/tokens-comando.cjs | os wrappers de dialeto PowerShell que o desempacotador conhece (D7)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const mistaComGh = !wrapperSemContrabarra && `
  para: `const mistaComGh = `
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, casos (r8-2) a (r8-4)`
prova-na-base: verde — a base não tem a regra da palavra mista e já deixa passar (r8-2) a (r8-4); a prova é a mutação acima, que volta a barrá-los
pronto quando: com o payload real de PreToolUse (PowerShell), `& "C:\Microsiga\advpls.exe" appre x.prw -I"C:\Microsiga\includes"`, `cmd /c dir "C:\Program Files"\foo` e `& "C:\Program Files\nodejs\node.exe" --out="C:\x y\z"` saem 0, `bash -c "echo"' \"; gh issue close 12'` pela ferramenta PowerShell (r8-5) sai 2, e os casos (mx-1) a (mx-15) do Bash seguem saindo 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` com exit 0 e 0 falha(s) e pela mutação acima deixando (r8-2) vermelho.

Forma prescrita: em `processarSegmento`, `exeDoWrapper` é `normalizarExecutavel` do token na posição de comando; `mistaComGh` só vale com `exeDoWrapper` fora de `cmd`, `pwsh`, `powershell`, `iex`, `invoke-expression` e `&`. Decide o dialeto do wrapper, não a ferramenta de fora: `bash -c` pela ferramenta PowerShell segue barrando (revisão de segurança automática do commit b2db757a).

### 26. CHANGELOG da 8ª rodada [tipo: docs]
atende: D3, D8
arquivos: `CHANGELOG.md`
depende de: 25
mutacao: n/a
  motivo: só texto; o comportamento está medido pelas tarefas 24 e 25
pronto quando: a entrada 2.13.3 (antes 2.12.3) do `CHANGELOG.md` não diz mais que o ANSI-C dentro de `"$(...)"` barra, cita a Issue #694 para essa classe, e diz que a regra da palavra mista vale só no bash (no PowerShell e em `cmd`/`pwsh` a contrabarra é literal), coerente com as emendas da D3 e da D8 — conferido por `grep -c '^## 2.12.2' CHANGELOG.md` devolvendo `1` e pela leitura da entrada contra a D3 e a D8.

### 27. Texto da revisão 8: falso positivo aceito, D8 e cabeçalho do (cm-8) [tipo: docs]
atende: D4, D8
arquivos: `CHANGELOG.md`, `hooks/testa-gate-fechar-issue.sh`
depende de: 26
mutacao: n/a
  motivo: só texto (Q1 A do Luís, 2026-11-13); nenhum comportamento muda, e o cabeçalho do (cm-8) só troca aspas duplas por simples num echo
pronto quando: o falso positivo do D3 com aspa qualquer dentro de `"$(...)"` está nomeado com o exemplo `cd "$(dirname "$0")"` no D4 e na entrada do CHANGELOG, a Issue #708 é citada nos dois, a D8 diz aspas duplas onde o código (`textoAPartir` em `hooks/lib/tokens-comando.cjs`) usa duplas, e `bash hooks/testa-gate-fechar-issue.sh 2>&1 | grep -c 'bad substitution'` devolve `0`.

### 6. Versão PATCH e CHANGELOG [tipo: docs]
atende: D4, D6, D7, D8, D9
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 5, 7, 17
mutacao: n/a
  motivo: só versão e texto; comportamento medido pelas tarefas 1 a 5 e 7 a 10
pronto quando: `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-2.13.3-` e `alt="versão 2.13.3"`, topo do CHANGELOG `## 2.13.3 — 2026-11-13`) dizem 2.13.3 (renumerada de 2.12.3 no merge com a `origin/main` da rodada 9); a entrada do CHANGELOG diz, pelo comportamento, que here-string, contrabarra antes de aspa (Bash) e `"$(...)"` com interior complexo deixam de esconder `gh issue close`/`gh pr merge` do gate (Issue 689), nomeia o falso positivo aceito do D4 (`"$(...)"` com interior complexo fora da forma canônica, seguido de `gh` de escrita, é barrado; contorno: `gh` em comando separado, corpo por `--body-file`/`-F`) diz que `bash -c` rodado pelo PowerShell (e `pwsh -Command` pelo Bash) segue as regras de aspas do wrapper (D7), diz que o comentário de shell com apóstrofo seguido de `gh` na linha de baixo continua escapando (Issue #692; o D9 foi revogado na 4ª rodada), e diz que o commit por heredoc canônico (`"$(cat <<'EOF' ... EOF
)"`) que cita `gh` de escrita entre crases volta a passar (D6) — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A4 '^## ' CHANGELOG.md`
