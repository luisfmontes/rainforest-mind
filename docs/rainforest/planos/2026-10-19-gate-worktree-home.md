# Plano: gate-worktree com HOME redefinido na linha (#561)

Design: docs/rainforest/design/2026-10-19-gate-worktree-home.md

## O que não pode quebrar
- Todo caso que já existe em `hooks/testa-gate-worktree.sh` mantém o exit esperado.
- Linha sem atalho de home não muda de veredito (`HOME=/tmp/h npm test` passa).
- Fora de worktree linkado a rede não age.

## Tarefas

### 1. Regra de casa redefinida no gate e casos na bateria [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
prova-na-base: verde — os casos novos nascem na própria bateria nesta tarefa; na base ela não os tem
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (casaRedefinida(comando, ehPowerShell)) return alvo;`
  para: `if (false) return alvo;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha =="`
pronto quando: com o cwd num worktree linkado da caixa de areia, as linhas `HOME=<W>; touch ~/../../../f`, `read HOME <<< <W>; touch ~/../../../f`, `printf -v HOME %s <W>; touch ~/../../../f`, `export {HOME,X}=<W>; touch ~/../../../f`, `unset HOME; touch ${HOME:-<W>}/../../../f`, `HOMEPATH=<W>; touch $HOMEDRIVE$HOMEPATH/../../../f` (Bash) e `$env:USERPROFILE="<W>"; Remove-Item ~/../../../f`, `$env:home="<W>"; Remove-Item ~/../../../f` (PowerShell) saem 2, e `home=/tmp/h; touch <W>/f`, `echo $HOME; touch <W>/f`, `touch <W>/HOME.md`, `HOME=/tmp/h npm test`, `git commit -m "ajusta HOME"` saem 0 — provado por `bash hooks/testa-gate-worktree.sh` com a seção `== #561: casa redefinida na linha ==` e o placar final sem falha. A regra é uma função `casaRedefinida(comando, ehPowerShell)` chamada uma vez no início da rede (depois de achar o worktree), sem caso de teste lendo o fonte.

### 2. CHANGELOG, versão e comentário [tipo: docs]
atende: D5
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `hooks/gate-worktree.cjs`, `docs/rainforest/estado/2026-10-19-estado-reabrir.json`
depende de: 10
mutacao: n/a
  motivo: texto e número de versão, sem comportamento a inverter
pronto quando: com o repositório da branch, `node scripts/conferir-versao.cjs` sai 0 com 1.70.1 maior que a da `origin/main`, o CHANGELOG abre com 1.70.1 citando #561 e a regra ampla de D1 (menção fora de leitura + uso da casa), `grep -n "fora de escopo (variavel" hooks/gate-worktree.cjs` não acha mais o comentário antigo, e `bash scripts/testa-versao.sh` sai `falhou: 0` com o badge do README em 1.70.1 — provado pelos quatro comandos. (O estado do fluxo estado-reabrir entra aqui por carona: é o `fechar ok` do #570, levado à `main` por esta branch.)

### 3. Braço do `cd` sem destino [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 1
prova-na-base: verde — emenda da revisão (rodada 1); os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `!cdSemArgumento.test(vivo.replace(/["'\\]/g, ""))) return false;`
  para: `true) return false;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", casos "HOME=$(dirname $PWD); cd -P; touch f" e "cd >/dev/null"`
pronto quando: com o cwd num worktree linkado, `HOME=$(dirname $PWD); cd -P; touch f` e `HOME=$(dirname $PWD); cd >/dev/null; touch f` saem 2 (a rede antiga deixava passar: sem caminho literal na linha), e `git diff HEAD~1 | grep -n "export"` sai 0 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 4. Braço da execução indireta [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 3
prova-na-base: verde — emenda da revisão (rodada 1); os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (EXECUCAO_INDIRETA.test(junto)) return true;`
  para: `if (false) return true;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", caso python3 -c com os.environ['HO'+'ME']=os.path.dirname(os.getcwd())`
pronto quando: com o cwd num worktree linkado, `python3 -c "import os; os.environ['HO'+'ME']=os.path.dirname(os.getcwd()); os.system('touch ~/f')"` sai 2 (sem menção nem definidor: só a execução indireta barra), e `echo "$(git rev-parse HEAD~1)"` sai 0 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 5. Til e `cd` entre aspas ou em heredoc de dado não usam a casa [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 4
prova-na-base: verde — emenda da revisão (rodada 2); os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `: mascaraAspasBash(mascaraHeredocsBash(junto));`
  para: `: junto;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", casos "git commit -m \"reduz ~30 tokens\" && echo $(date)" e o commit por heredoc`
pronto quando: com o cwd num worktree linkado, `git commit -m "reduz ~30 tokens" && echo $(date)`, `echo "~" ; echo $(date)` e `git commit -m "$(cat <<'EOF'` + linha `fix: reduz ~30 tokens e o agente faz cd` + `EOF` + `)"` saem 0 (a rodada 2 media 2), enquanto `HOME=$(dirname $PWD); bash -c 'touch ~/f'` (interpretador na linha: as aspas contam) e `$env:USERPROFILE += "\..\.."; Remove-Item $env:USERPROFILE\f` saem 2 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 6. Só comando inerte deixa mascarar as aspas [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 5
prova-na-base: verde — emenda da revisão de segurança de `371a6b6b`; os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `const vivo = ehPowerShell || mexeNaCasa || !soComandosInertes(mascarado) ? junto : mascarado;`
  para: `const vivo = ehPowerShell || mexeNaCasa ? junto : mascarado;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", caso python3 -c com os.environ['HO'+'ME'] e til entre aspas`
pronto quando: com o cwd num worktree linkado, `HOME=$(dirname $PWD); awk 'BEGIN{system("touch ~/f")}'`, `HOME=$(dirname $PWD); find . -name x -exec sh -c 'touch ~/f' \;` e `HOME=$(dirname $PWD); git -c alias.x='!touch ~/f' x` saem 2 (a base deixava passar), e `gh issue create --title x --body "ver ~/x" && echo $(date)` sai 0 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 7. Linha que mexe na casa nunca mascara as aspas [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 6
prova-na-base: verde — emenda da revisão de segurança de `e12adb1c` e da rodada 3 do fluxo (impasse liberado); os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `ehPowerShell || mexeNaCasa || !soComandosInertes`
  para: `ehPowerShell || !soComandosInertes`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", casos printf -vHOME e >/dev/null HOME=... git push --receive-pack`
pronto quando: com o cwd num worktree linkado, `printf -vHOME %s $OLDPWD; git push --receive-pack='touch ~/f' origin`, `>/dev/null HOME=$OLDPWD git push --receive-pack='touch ~/f' origin`, `HOME=$OLDPWD; touch ${U:-~}/f` e ``HOME=$OLDPWD; `~/x.sh` `` saem 2 (o código de `90b97918` deixava passar), e o commit por heredoc com `~30 tokens` segue 0 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 8. Til por classe: fora de palavra é uso da casa [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 7
prova-na-base: verde — emenda da rodada 4 do fluxo (impasse liberado); os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `const tilDeCasa = /(^|[^\w\\])~/;`
  para: `const tilDeCasa = /(^|[\s'"=:,({;&|<>)\-+?])~/;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", casos ${X/y/~}, ${X//y/~}, ${Y#~} e ${Y%~}`
pronto quando: com o cwd num worktree linkado, `HOME=$OLDPWD; X=y; touch ${X/y/~}/f`, `${X//y/~}`, `${Y#~}` e `${Y%~}` saem 2 (o código de `a59bfe17` deixava passar), e `git diff @~1 --stat` e `git log --oneline HEAD~3..HEAD` seguem 0 — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 9. Continuação de linha se desfaz antes de qualquer checagem [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 8
prova-na-base: verde — emenda da rodada 4 do fluxo; o caso nasce na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `: /\\\r?\n/g, "");`
  para: `: /$^/g, "");`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", caso printf HO contrabarra quebra ME=$OLDPWD`
pronto quando: com o cwd num worktree linkado, `HO\<quebra de linha>ME=$OLDPWD; touch ~/f` sai 2 (o código de `a59bfe17` deixava passar), e `HOME=$OLDPWD; touch ${HO\<quebra>ME}/f`, `$HO\<quebra>ME/f` e `c\<quebra>d; touch f` saem 2 (o código de `65ebc32d` deixava passar) — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.

### 10. `source`/`.` em qualquer palavra conta como execução indireta [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 9
prova-na-base: verde — emenda da rodada 4 do fluxo; os casos nascem na bateria nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (FONTE_DE_SCRIPT.test(semAspas)) return true;`
  para: `if (false) return true;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `900000`
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha ==", casos builtin source, >/dev/null source, if source e source em linha propria`
pronto quando: com o cwd num worktree linkado, `builtin source ./define-casa.sh; touch ~/f`, `builtin . ./define-casa.sh; touch ~/f`, `>/dev/null source ./x.sh; touch ~/f`, `2>/dev/null . ./x.sh; touch ~/f`, `if source ./x.sh; then touch ~/f; fi`, `time source ./x.sh; touch ~/f` e `source` em linha própria antes de `touch ~/f` saem 2, `git add . && git status` e `ls ~/.config` seguem 0 (custo aceito: `git add . && cat ~/x.txt` cai) (o código de `a59bfe17` deixava passar) — provado por `bash hooks/testa-gate-worktree.sh` com placar sem falha.
