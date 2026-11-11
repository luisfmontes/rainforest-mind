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
  de: `if (c === "`" && aspa !== "'"`
  para: `if (false && aspa !== "'"`
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

### 3. Conteúdo da crase opaco para as aspas de fora (revisão de segurança) [tipo: implementar]
atende: D4
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 1
busca:
- repo | grep -n "internoCrase" hooks/gate-fechar-issue.cjs | o bloco da tarefa 1 lia a crase e deixava o laço de fora reler o conteúdo
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `      i = j;`
  para: `      i = cmd.length;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, caso (crase-8)`
prova-na-base: verde — o caso (crase-8) nasce com esta tarefa; a versão entregue na tarefa 1 deixava o mesmo comando sair 0 (medido no payload real)
pronto quando: com o payload real de PreToolUse, `` echo `echo "`; gh issue close 12 `` sai 2 (caso crase-8) e a bateria inteira fica verde — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 428 ok, 0 falha(s) ==`

Na tarefa 1, o bloco passa a terminar com `atual += cmd.slice(i, Math.min(j + 1, cmd.length)); i = j; continue;`, e a variável `fimCrase` sai (o salto do índice substitui a guarda). A mutação `i = i + 0` não serve de medida: a crase de fechamento abre outra varredura até o fim e barra o caso por outro caminho.

*Emenda da revisão 1:* o alvo de mutação da tarefa 1 passou a ser a condição de entrada do bloco, porque a linha da recursão mudou na tarefa 4.

### 4. Escape de crase como o bash (revisão 1 e revisão de segurança) [tipo: implementar]
atende: D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 3
busca:
- repo | grep -n "cmd`[i - 1] !== `" hooks/gate-fechar-issue.cjs | o bloco da crase olhava só um caractere antes
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `g, "$1"))) {`
  para: `g, "$&"))) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, caso (crase-9)`
prova-na-base: verde — os casos (crase-9) a (crase-11) nascem com esta tarefa; na versão da tarefa 3, (crase-9) e (crase-10) saíam 0 (medido no payload real)
pronto quando: com o payload real de PreToolUse, a crase aninhada com `\`` (crase-9) e `\\` antes da crase (crase-10) saem 2, e `\`` sozinho (crase-11) sai 0 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 433 ok, 0 falha(s) ==`

### 5. Crase dentro de $(...) entre aspas fica com o P4 recursivo [tipo: implementar]
atende: D6
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 4
busca:
- repo | grep -n "if (interno.trim()) segmentos.push(interno);" hooks/gate-fechar-issue.cjs | o P4 empurrava o conteúdo de $(...) cru, sem recursão
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `          for (const sub of segmentosParaGate(interno)) {`
  para: `          for (const sub of [interno]) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, caso (crase-13)`
prova-na-base: verde — (crase-12) saía 0 na base e 2 na versão da tarefa 3; (crase-13) saía 0 nas duas (medido no payload real)
pronto quando: com o payload real, o commit por heredoc citado com crase de texto (crase-12) sai 0 e a crase dentro de `$(...)` entre aspas (crase-13) sai 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 433 ok, 0 falha(s) ==`; trocar a recursão do P4 por `[interno]` também deixa (crase-13) vermelho (medido)

*Emenda da revisão de segurança do commit 6bbfa81:* a tarefa 5 perdeu o `fimDolarAspas` (D7), então o alvo de mutação dela passou a ser a recursão do P4, medido por (crase-13); o (crase-12) passou a esperar 2.

### 6. Crase conferida dentro de $(...) e teto de segmentação [tipo: implementar]
atende: D7
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 5
busca:
- repo | grep -n "fimDolarAspas" hooks/gate-fechar-issue.cjs | o pulo da tarefa 5, que contava parênteses sem entender aspas
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `  if (chamadasSegmentacao > TETO_SEGMENTACAO) {`
  para: `  if (false) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, caso (crase-15)`
prova-na-base: verde — (crase-14) e (crase-15) saíam 0 na versão da tarefa 5 (medido no payload real); a base não tinha a recursão
pronto quando: com o payload real, o parêntese entre aspas simples dentro de `$(...)` não esconde a crase (crase-14 sai 2), `"$(...)"` aninhado 20 vezes barra em menos de 1 s (crase-15 sai 2), o commit por heredoc citado com crase que cita `gh` de escrita sai 2 (crase-12) e com crase de texto comum sai 0 (crase-16) — provado por `bash hooks/testa-gate-fechar-issue.sh` terminando em `== resultado: 436 ok, 0 falha(s) ==`
