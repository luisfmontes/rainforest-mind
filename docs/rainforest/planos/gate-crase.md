# Plano: gate-fechar-issue confere o comando dentro de crases

Design: docs/rainforest/design/gate-crase.md

## O que não pode quebrar
- `bash hooks/testa-gate-fechar-issue.sh` continua verde (420 ok hoje), inclusive (ar) e (as) do P4.
- As outras baterias que chamam o gate continuam verdes: `hooks/testa-gate-pr-flag-curta.sh`, `hooks/testa-gate-merge-auto.sh`, `hooks/testa-gate-receita-corpo.sh`, `hooks/testa-gate-staging-total.sh`.
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
  fixture: `testa-gate-fechar-issue.sh, casos (crase-1), (crase-2), (crase-3) e (crase-7)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"echo x; echo \u0060gh issue close 12\u0060"}}))' | node hooks/gate-fechar-issue.cjs; test $? -eq 2`
pronto quando: com o payload real de PreToolUse (Bash), `` echo "`gh issue close 12`" ``, `` echo `gh issue close 12` ``, `` echo "`gh pr merge 5 --squash`" `` e `` echo `gh issue close 12 `` (crase sem par) saem 2, e continuam saindo 0 `` echo "`git log -1`" ``, `` echo '`gh issue close 12`' `` (aspas simples não executam) e, no PowerShell, `` Write-Host "a`nb" `` — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 427 ok, 0 falha(s) ==` com exit 0; por `bash hooks/testa-gate-pr-flag-curta.sh`, `bash hooks/testa-gate-merge-auto.sh`, `bash hooks/testa-gate-receita-corpo.sh` e `bash hooks/testa-gate-staging-total.sh` saindo 0 cada uma; e pela mutação acima deixando (crase-1), (crase-2), (crase-3) e (crase-7) vermelhos. A `prova` confere só a segmentação: o bloqueio sai antes de qualquer chamada ao `gh`, então ela não depende de stub.

Forma prescrita (código a nascer), em ordem:
1. Em `segmentosParaGate`, junto de `let aspa = null;`, declarar `let fimCrase = -1;`.
2. Como PRIMEIRA coisa do corpo do `for (let i = 0; ...)`, antes do `if (aspa)`, um bloco com a condição `if (c === "`" && aspa !== "'" && cmd[i - 1] !== "\\" && i > fimCrase) {`.
3. Dentro dele: `let j = i + 1; let internoCrase = "";` e um `while (j < cmd.length && !(cmd[j] === "`" && cmd[j - 1] !== "\\")) { internoCrase += cmd[j]; j += 1; }`. Sem crase de fechamento, `j` termina em `cmd.length` e o conteúdo vai até o fim.
4. Depois do `while`: `fimCrase = j;` e `if (internoCrase.trim()) { for (const sub of segmentosParaGate(internoCrase)) { if (sub.trim()) segmentos.push(sub); } }`.
5. O bloco NÃO altera `i`, `atual` nem `aspa` e não tem `continue`: o laço segue normalmente para o mesmo caractere.
6. Comentário acima do bloco: crase executa o comando de dentro (com ou sem aspas duplas, não em aspas simples), segmento adicional como o P4, D1 de docs/rainforest/design/gate-crase.md, Issue #685.

Bateria: sete casos novos em `hooks/testa-gate-fechar-issue.sh`, logo depois do caso (as) (linhas 761-771). Cada caso copia o bloco (ar) (linhas 745-759), trocando só o nome da variável (`COMANDO_CRASE_N`), o título `echo "== (crase-N) <comando> → exit X =="`, o arquivo de stderr (`$SBP/err-crase-N`) e o exit esperado. O comando vai SEMPRE numa variável com `$'...'` do bash, com a crase literal dentro (nunca crase dentro de aspas duplas do shell da bateria, que o bash executaria):
- (crase-1) `COMANDO_CRASE_1=$'echo "`gh issue close 12`"'` → 2
- (crase-2) `COMANDO_CRASE_2=$'echo `gh issue close 12`'` → 2
- (crase-3) `COMANDO_CRASE_3=$'echo "`gh pr merge 5 --squash`"'` → 2
- (crase-4) `COMANDO_CRASE_4=$'echo "`git log -1`"'` → 0
- (crase-5) `COMANDO_CRASE_5=$'echo \'`gh issue close 12`\''` → 0
- (crase-6) PowerShell: payload com `tool_name:"PowerShell"` e `COMANDO_CRASE_6=$'Write-Host "a`nb"'` → 0
- (crase-7) `COMANDO_CRASE_7=$'echo `gh issue close 12'` (sem par) → 2

Os comandos acima levam a crase literal, como vão no arquivo da bateria. Cada caso soma exatamente 1 ok: 420 + 7 = 427.

### 2. Versão PATCH e CHANGELOG [tipo: docs]
atende: D1
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1
mutacao: n/a
  motivo: só versão e texto; comportamento medido pela tarefa 1
pronto quando: com a `main` trazida para a branch (`git fetch origin && git merge origin/main`; conflito fora de versão e CHANGELOG: pare e relate), `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-X-` e `alt="versão X"`, topo do CHANGELOG `## X — 2026-11-11`) dizem a versão seguinte à da `main` na casa PATCH; a entrada do CHANGELOG diz, pelo comportamento, que `gh issue close` ou `gh pr merge` dentro de crases passa a ser conferido pelo gate como já era dentro de `$(...)` — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`
