# Plano: Rodada 19 — `cd X #comentário` e o segmentador do gate de bateria (#736)

Design: docs/rainforest/design/2026-11-26-zerar-issues-19.md

## O que não pode quebrar

- Todo caso existente de `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-subagente-sem-gh.cjs` e `hooks/testa-gate-publicacao-destino.sh` mantém o exit esperado. Nenhum caso é apagado.
- A propriedade D4 da rodada 18 ("base barra ⇒ head barra", seção "D4: propriedade" de `hooks/testa-gate-staging-total.sh`) segue com `violacoes 0`: o gerador dela não tem `cd`, e a D1 só muda linha com movedor.
- O caso 6 de `hooks/testa-gate-bateria-sem-timeout.cjs` (`cat <<'EOF'` com bateria no corpo) segue 0.

## Tarefas

### 1. Comentário no fim dos seis movedores [tipo: implementar]
atende: D1
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`
busca:
- repo | grep -n "^const \(CD\|PUSHD\|POPD\|SET_LOCATION\|PUSH_LOCATION\|POP_LOCATION\) =" hooks/lib/cwd-efetivo.cjs | seis regex ancoradas em `\s*$` depois do destino; estendo as seis
- repo | grep -rn "\bCD\b\|SET_LOCATION\|PUSHD" hooks scripts --include=*.cjs | só `resolverMovedor` usa as regex; `gate-worktree.cjs:576` cita `CD` em comentário
- catalogo | pulado: a mudança é dentro das seis regex que já existem, sem função nova a procurar
desfecho: estender
O que fazer:
- `hooks/lib/cwd-efetivo.cjs`: `(?:(?<![\\`])[ \t]+#.*)?` antes do `\s*$` final em `CD`, `PUSHD`, `POPD`, `SET_LOCATION`, `PUSH_LOCATION` e `POP_LOCATION`, com o comentário de porquê sobre `CD`.
- `hooks/testa-cwd-efetivo.sh`: (736x) `cd`/`pushd`/`popd` com `#c` dão o mesmo mapa de sem ele, também na leitura antiga (`comLeituraAntiga`); (736y) `Set-Location`, `Push-Location`/`Pop-Location` no PowerShell; (736z) controles `cd a#b`, `cd 'a #b'` e `cd #c`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const POPD = /^\s*popd(?:\s+-n)?(?:(?<![\\`])[ \t]+#.*)?\s*$/;`
  para: `const POPD = /^\s*popd(?:\s+-n)?\s*$/;`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: testa-cwd-efetivo.sh, caso "(736x) cd/pushd/popd com # no fim movem como sem ele, nas duas leituras"
prova-na-base: verde — casos novos; no `main` `b76d80f8`, `cwdPorSegmento("cd sub #c\ngh ...", "/r")` dá ao `gh` o cwd `/r` com `incerto:false` (sonda de 2026-11-25)
pronto quando: `bash hooks/testa-cwd-efetivo.sh` com `ok` em (736x), (736y) e (736z) e 0 falhas.

### 2. Casos do gate de staging para o `cd` com comentário [tipo: implementar]
atende: D1
arquivos: `hooks/testa-gate-staging-total.sh`
depende de: 1
busca:
- repo | grep -n "WT=\|bml()\|pml()" hooks/testa-gate-staging-total.sh | fixture com worktree linkado e os helpers de payload multilinha; reuso
desfecho: estender
O que fazer:
- Seção "rodada 19 (#736, D1)": do worktree, `cd <principal> #c` + quebra + `git add -A` barra (736-cd1); a mesma linha sem `#c` barra (736-cd2, referência); do principal, `cd <worktree> #c` + quebra + `git add -A` passa (736-cd3); do worktree, `Set-Location <principal> #c` + quebra + `git add -A` pela ferramenta PowerShell barra (736-cd4).
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const CD = /^\s*cd\s+(?:--\s+)?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))(?:(?<![\\`])[ \t]+#.*)?\s*$/;`
  para: `const CD = /^\s*cd\s+(?:--\s+)?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))\s*$/;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, caso "736-cd1: do worktree, cd <principal> #c + quebra + git add -A barra"
  timeout: `1200000`
prova-na-base: verde — casos novos; no `main` `b76d80f8`, do worktree, `cd <principal> #c` + quebra + `git add -A` sai 0 no gate real (`sonda1.cjs`, 2026-11-26)
pronto quando: `bash hooks/testa-gate-staging-total.sh` com `ok` em 736-cd1 a 736-cd4, a linha `propriedade: ... violacoes 0` e 0 falhas.

### 3. Casos do gate de fechar Issue para o `cd` com comentário [tipo: implementar]
atende: D1
arquivos: `hooks/testa-gate-fechar-issue.sh`
depende de: 1
busca:
- repo | grep -n "caso_cwd_ps" hooks/testa-gate-fechar-issue.sh | helper da rodada 18 com A e B (B tem `Closes #999` no `corpo.txt`); copio para a ferramenta Bash
desfecho: estender
O que fazer:
- `caso_cwd_bash`, irmão de `caso_cwd_ps` com `tool_name` Bash. Casos: `cd <B> #c` + quebra + `gh pr create --body-file corpo.txt` pela ferramenta Bash (736-cd1) e `Set-Location <B> #c` + quebra + o mesmo `gh` pela ferramenta PowerShell (736-cd2), os dois barrando citando `#999`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const SET_LOCATION = /^\s*(?:Set-Location|sl|chdir)\s+(?:-(?:Path|LiteralPath)(?:\s+|:))?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))(?:(?<![\\`])[ \t]+#.*)?\s*$/i;`
  para: `const SET_LOCATION = /^\s*(?:Set-Location|sl|chdir)\s+(?:-(?:Path|LiteralPath)(?:\s+|:))?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))\s*$/i;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, caso "736-cd2"
  timeout: `1200000`
prova-na-base: verde — casos novos; no `main` `b76d80f8` o gate lê o `corpo.txt` de A, sem `Closes`, e sai 0 (mesmo mecanismo da sonda da tarefa 1)
pronto quando: `bash hooks/testa-gate-fechar-issue.sh` com `ok` em 736-cd1 e 736-cd2 e 0 falhas; `node hooks/testa-gate-subagente-sem-gh.cjs` e `bash hooks/testa-gate-publicacao-destino.sh` com 0 falhas.

### 4. Segunda leitura no gate de bateria [tipo: implementar]
atende: D2, D3
arquivos: `hooks/gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-bateria-sem-timeout.cjs`
busca:
- repo | grep -n "segmentosComAspasESubcomandos\|semCorpoDeHeredoc\|colapsaContinuacaoDeLinha" hooks/gate-bateria-sem-timeout.cjs | leitura própria em três passos; fica intacta
- catalogo | `segmentosComAspas` (hooks/lib/cwd-efetivo.cjs) e `mascararCorposDeHeredoc` (hooks/lib/heredoc.cjs) | reuso, sem `scriptNaoShell` (só o staging passa)
desfecho: estender
O que fazer:
- `hooks/gate-bateria-sem-timeout.cjs`: segmentos da leitura nova sobre o comando cru (`mascararCorposDeHeredoc` → `segmentosComAspas(cmd, false)` → cada um por `segmentosComAspasESubcomandos`), somados aos de hoje; exceção na leitura nova deixa só a de hoje.
- `hooks/testa-gate-bateria-sem-timeout.cjs`: 736-b1 a 736-b3 (as três linhas do Objetivo 2) saem 2; 736-b4 (`cat <<EOF` sem aspas, D3) sai 2; 736-b5 (controle `echo hi # don't` + quebra + `ls`) sai 0.
mutacao:
  arquivo: `hooks/gate-bateria-sem-timeout.cjs`
  de: `  for (const segmento of segmentos.concat(segmentosNovos)) {`
  para: `  for (const segmento of segmentos) {`
  bateria: `node hooks/testa-gate-bateria-sem-timeout.cjs`
  fixture: testa-gate-bateria-sem-timeout.cjs, caso "736-b2: aspa dentro de comentario nao esconde a bateria de baixo → 2"
prova-na-base: verde — casos novos; no `main` `b76d80f8` as três linhas saem 0 (comentário da #736, medido de novo em `sonda2.cjs` contra a base `e9d2b14e`, 2026-11-26)
pronto quando: `node hooks/testa-gate-bateria-sem-timeout.cjs` com `ok` em 736-b1 a 736-b5, no caso 6 (`cat <<'EOF'`) e 0 falhas.

### 6. Só espaço e tab, sem escape, abrem o comentário do movedor (primeira volta do revisor do fluxo) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-staging-total.sh`
depende de: 2
busca:
- repo | grep -n "function abreComentario" hooks/lib/cwd-efetivo.cjs | a leitura nova ja distingue branco de bash e de PowerShell (736t); a regex do movedor fica com o subconjunto seguro dos dois
- catalogo | pulado: troca dentro das seis regex da tarefa 1
desfecho: estender
O que fazer:
- `hooks/lib/cwd-efetivo.cjs`: nas seis regex, `(?:(?<![\\`])[ \t]+#.*)?` no lugar de `(?:\s+#.*)?`: só espaço e tab antes do `#`, e nunca depois de contrabarra ou crase.
- `hooks/testa-cwd-efetivo.sh`: (736w2) `cd A\ #c`, `cd A<NBSP>#c`, FF, VT, U+2003 e crase não movem; tab move.
- `hooks/testa-gate-staging-total.sh`: do principal, `cd <worktree>\ #c` (736-cd5) e `cd <worktree><NBSP>#c` (736-cd6) + quebra + `git add -A` barram.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const PUSHD = /^\s*pushd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))(?:(?<![\\`])[ \t]+#.*)?\s*$/;`
  para: `const PUSHD = /^\s*pushd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))(?:\s+#.*)?\s*$/;`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: testa-cwd-efetivo.sh, caso "(736w2) # depois de espaco escapado ou de branco que o bash nao conta nao e comentario"
prova-na-base: verde — casos novos; no head `47d10d60` da primeira volta, do principal, `cd <worktree>\ #c` e `cd <worktree><NBSP>#c` + quebra + `git add -A` saem 0 no `gate-staging-total` (base 2), medido pelo revisor do fluxo e por `sonda3.cjs` em 2026-11-26
pronto quando: `bash hooks/testa-cwd-efetivo.sh` com `ok` em (736w2) e 0 falhas; `bash hooks/testa-gate-staging-total.sh` com `ok` em 736-cd5 e 736-cd6 e 0 falhas.

### 7. O escape antes do `#` depende do dialeto (revisão de segurança automática do commit de313a38) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-fechar-issue.sh`
depende de: 6
busca:
- repo | grep -n "resolverMovedor(segCru, estado, ehPowerShell" hooks/lib/cwd-efetivo.cjs | o dialeto já chega a `resolverMovedor`; a escolha das regex mora lá
- catalogo | pulado: variante das seis regex da tarefa 6, derivada delas por `source`
desfecho: estender
O que fazer:
- `hooks/lib/cwd-efetivo.cjs`: `paraPowerShell(re)` troca o lookbehind `(?<![\\`])` por `(?<!`)`; `MOVEDORES_BASH` e `MOVEDORES_POWERSHELL`; `resolverMovedor` usa o conjunto do dialeto. No PowerShell a contrabarra é literal (`Set-Location C:\p\ #c` move) e só a crase escapa.
- `hooks/testa-cwd-efetivo.sh`: (736y2) `cd`, `Set-Location`, `Push-Location` e `pushd` com `A\ #c` movem no PowerShell e não no bash; com crase antes do espaço não movem no PowerShell.
- `hooks/testa-gate-staging-total.sh`: do worktree, `Set-Location <principal>\ #c` + quebra + `git add -A` pela ferramenta PowerShell barra (736-cd7).
- `hooks/testa-gate-fechar-issue.sh`: `Set-Location <B>\ #c` + quebra + `gh pr create --body-file corpo.txt` pela ferramenta PowerShell barra citando `#999` (736-cd3).
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const paraPowerShell = (re) => new RegExp(re.source.split("(?<![\\\\`])").join("(?<!`)"), re.flags);`
  para: `const paraPowerShell = (re) => re;`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: testa-cwd-efetivo.sh, caso "(736y2) PowerShell: a contrabarra e literal e o # depois dela abre comentario; a crase escapa"
prova-na-base: verde — casos novos; no head `de313a38`, do worktree, `Set-Location <principal>\ #c` + quebra + `git add -A` pela ferramenta PowerShell sai 0 no `gate-staging-total` (e 0 na base), `sonda4.cjs` em 2026-11-26
pronto quando: `bash hooks/testa-cwd-efetivo.sh` com `ok` em (736y2) e 0 falhas; `bash hooks/testa-gate-staging-total.sh` com `ok` em 736-cd7 e 0 falhas; `bash hooks/testa-gate-fechar-issue.sh` com `ok` em 736-cd3 e 0 falhas.

### 5. Versão 2.17.5 [tipo: docs]
atende: D1, D2, D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 3, 4, 7
O que fazer:
- Versão 2.17.5 nos dois `plugin.json` e no selo do `README.md`.
- Entrada 2.17.5 no `CHANGELOG.md`: `cd X #comentário` move o diretório nos gates (mão dupla), e o gate de bateria lê o comando duas vezes; `cat <<EOF` sem aspas com bateria no corpo passa a barrar.
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.5"' .claude-plugin/plugin.json`
pronto quando: com os manifestos que o cache lê para instalar, provado por `grep -c '"version": "2.17.5"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.5' CHANGELOG.md` imprimindo 1.
