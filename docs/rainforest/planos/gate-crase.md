# Plano: gate-fechar-issue confere o comando dentro de crases

Design: docs/rainforest/design/gate-crase.md

## O que não pode quebrar
- `bash hooks/testa-gate-fechar-issue.sh` continua verde (420 ok hoje), inclusive (ar) e (as) do P4.
- `bash hooks/testa-gate-pr-flag-curta.sh` continua verde.
- Comando com crase que não escreve (`` echo "`git log -1`" ``, `` x=`date` ``) continua saindo 0.

## Tarefas

### 1. Crase vira segmento adicional no segmentosParaGate [tipo: implementar]
atende: D1, D2, D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
busca:
- repo | grep -n "P4 (rodada 8" hooks/gate-fechar-issue.cjs | o bloco do $(...) entre aspas duplas, dentro do ramo `if (aspa)` de segmentosParaGate, é o molde
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `for (const sub of segmentosParaGate(internoCrase)) {`
  para: `for (const sub of [].slice(0)) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, casos (crase-1) a (crase-3)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"echo x; echo `gh issue close 12`"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `` echo "`gh issue close 12`" ``, `` echo `gh issue close 12` `` e `` echo "`gh pr merge 5 --squash`" `` saem 2, e continuam saindo 0 `` echo "`git log -1`" ``, `` echo '`gh issue close 12`' `` (aspas simples não executam) e, no PowerShell, `` Write-Host "a`nb" ``; a bateria inteira continua verde — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `426 ok, 0 falha(s)` com exit 0, e pela mutação acima deixando (crase-1) a (crase-3) vermelhos

Forma prescrita (código a nascer): no laço de `segmentosParaGate`, como PRIMEIRA coisa do corpo do `for` (antes do `if (aspa)`), um bloco que só age quando `c === "`" && aspa !== "'" && cmd[i - 1] !== "\\"`: varre `j` de `i + 1` até a próxima crase cujo caractere anterior não seja `\`, acumulando em `internoCrase` (sem a crase final); se `internoCrase.trim()`, faz `for (const sub of segmentosParaGate(internoCrase)) { if (sub.trim()) segmentos.push(sub); }`. O bloco não altera `i`, `atual` nem `aspa`; o laço segue normalmente, e a crase de fechamento, ao ser visitada, abre de novo uma varredura cujo conteúdo é o texto entre ela e a próxima crase (o pedaço "de fora"); para não reprocessar, guarde o índice da crase de fechamento numa variável `fimCrase` declarada antes do laço (`let fimCrase = -1;`) e entre no bloco só se `i > fimCrase`, gravando `fimCrase = j` ao terminar. Comentário acima do bloco: o porquê (D1 de docs/rainforest/design/gate-crase.md) e a Issue #685.

Bateria: seis casos novos em `hooks/testa-gate-fechar-issue.sh`, logo depois do caso (as), no mesmo formato do (ar) (subshell com `PATH="$SBP/bin:$PATH"`, payload por `node -e`, stderr em `$SBP/err-crase-N`, `test_ok`/`test_fail` pelo exit): (crase-1) `` echo "`gh issue close 12`" `` → 2; (crase-2) `` echo `gh issue close 12` `` → 2; (crase-3) `` echo "`gh pr merge 5 --squash`" `` → 2; (crase-4) `` echo "`git log -1`" `` → 0; (crase-5) `` echo '`gh issue close 12`' `` → 0; (crase-6) via PowerShell (`tool_name:"PowerShell"`), `` Write-Host "a`nb" `` → 0. O comando vai numa variável montada com `String.fromCharCode(96)` ou com `$'...'` do bash, nunca com crase literal dentro de aspas duplas do shell da bateria (o bash da bateria executaria). Cada caso soma exatamente 1 ok: 420 + 6 = 426.
