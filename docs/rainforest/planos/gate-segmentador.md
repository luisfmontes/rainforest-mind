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

### 6. Versão PATCH e CHANGELOG [tipo: docs]
atende: D4, D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 5
mutacao: n/a
  motivo: só versão e texto; comportamento medido pelas tarefas 1 a 5
pronto quando: `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-2.12.3-` e `alt="versão 2.12.3"`, topo do CHANGELOG `## 2.12.3 — 2026-11-11`) dizem 2.12.3; a entrada do CHANGELOG diz, pelo comportamento, que here-string, contrabarra antes de aspa (Bash) e `"$(...)"` com interior complexo deixam de esconder `gh issue close`/`gh pr merge` do gate (Issue 689), nomeia o falso positivo aceito do D4 (`"$(...)"` com interior complexo fora da forma canônica, seguido de `gh` de escrita, é barrado; contorno: `gh` em comando separado, corpo por `--body-file`/`-F`) e diz que o commit por heredoc canônico (`"$(cat <<'EOF' ... EOF
)"`) que cita `gh` de escrita entre crases volta a passar (D6) — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A4 '^## ' CHANGELOG.md`
