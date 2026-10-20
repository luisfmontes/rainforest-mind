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
  fixture: `testa-gate-worktree.sh, secao "== #561: casa redefinida na linha =="`
pronto quando: com o cwd num worktree linkado da caixa de areia, as linhas `HOME=<W>; touch ~/../../../f`, `read HOME <<< <W>; touch ~/../../../f`, `printf -v HOME %s <W>; touch ~/../../../f`, `export {HOME,X}=<W>; touch ~/../../../f`, `unset HOME; touch ${HOME:-<W>}/../../../f`, `HOMEPATH=<W>; touch $HOMEDRIVE$HOMEPATH/../../../f` (Bash) e `$env:USERPROFILE="<W>"; Remove-Item ~/../../../f`, `$env:home="<W>"; Remove-Item ~/../../../f` (PowerShell) saem 2, e `home=/tmp/h; touch <W>/f`, `echo $HOME; touch <W>/f`, `touch <W>/HOME.md`, `HOME=/tmp/h npm test`, `git commit -m "ajusta HOME"` saem 0 — provado por `bash hooks/testa-gate-worktree.sh` com a seção `== #561: casa redefinida na linha ==` e o placar final sem falha. A regra é uma função `casaRedefinida(comando, ehPowerShell)` chamada uma vez no início da rede (depois de achar o worktree), sem caso de teste lendo o fonte.

### 2. CHANGELOG, versão e comentário [tipo: docs]
atende: D5
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `hooks/gate-worktree.cjs`
depende de: 1
mutacao: n/a
  motivo: texto e número de versão, sem comportamento a inverter
pronto quando: com o repositório da branch, `node scripts/conferir-versao.cjs` sai 0 com 1.70.1 maior que a da `origin/main`, o CHANGELOG abre com 1.70.1 citando #561 e a regra ampla de D1 (menção fora de leitura + uso da casa), e `grep -n "fora de escopo (variavel" hooks/gate-worktree.cjs` não acha mais o comentário antigo — provado pelos três comandos.
