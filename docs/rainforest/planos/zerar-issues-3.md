# Plano — zerar as Issues abertas, rodada 3

**Slug:** `zerar-issues-3` · **Design:** `docs/rainforest/design/zerar-issues-3.md`
**Base:** `origin/main` @ `cf1ad768` · **Branch:** `fluxo/zerar-issues-3`

Cinco tarefas, cinco decisões. **Onda 1** (arquivos disjuntos entre si): T1, T2,
T3. **Onda 2**: T4 (README e travas, depois do que muda comportamento) e T5
(versão, por último).

**Restrição que vale para todas:** o repo é público — nenhum caminho desta
máquina em código, teste ou fixture; e-mail em `git config` de bateria é
`test@test`. Toda asserção de bateria tem os dois ramos (`if/else`): a forma
que só conta `ok` e nunca `FALHA` é a que não sabe falhar. Bateria com mais de
um `mktemp -d` usa o idioma `SANDBOXES` (guarda `testa-sandbox-com-trap.sh`);
nenhuma bateria chama `python`/`jq`/`rg` pelo nome (guarda
`testa-dependencias-de-bateria.sh`). Executor entrega em worktree isolado sobre
o hash de base do briefing e o commit de entrega tem esse hash como pai.

### 1. `gate-fechar-issue`: corpo de heredoc é dado, salvo quando alimenta um interpretador [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const heredoc = corpoDeHeredoc(cmd, i);`
  para: `const heredoc = null;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: heredoc com "(folga de 2 B). Ele sobe." passa a ser bloqueado de novo (exit 2 em vez de 0)
pronto quando: existe a função `corpoDeHeredoc(cmd, i)` em `hooks/gate-fechar-issue.cjs` que, com `cmd[i..]` começando por `<<` ou `<<-` seguido de delimitador nu ou entre aspas simples/duplas, devolve `{ fim, corpo, comando }` (índice logo após a linha do delimitador de fechamento, o texto do corpo, e o primeiro token do comando ao qual o heredoc pertence) e `null` quando não há heredoc ali; `segmentosParaGate` a chama por `const heredoc = corpoDeHeredoc(cmd, i);` (uma ocorrência), pula `corpo` quando `comando` não é interpretador e o entrega a `segmentosParaGate` recursivamente quando é (`bash`, `sh`, `zsh`, `ksh`, `dash`, `pwsh`, `powershell`, `cmd`, `eval`, `source`, `.`); casos novos em `hooks/testa-gate-fechar-issue.sh`, cada um mandando o payload ao hook por stdin: os cinco de prosa da Issue #239 saem 0 — `cat > d.md <<'EOF'` com `(x).`, com `(x). O que`, com `(x). o que`, com `(x) ; . O que` e com `Medido em 2026-09-12 (folga de 2 B). Ele sobe.`; heredoc com delimitador entre aspas duplas e nu idem (exit 0); `cat <<'EOF'` cujo corpo contém `gh issue close 12` sai 0 (o `cat` não executa); `bash <<'EOF'` cujo corpo contém `gh issue close 12` sai 2; `bash -c "gh issue close 12"` continua 2; **emenda da revisão (2026-09-13):** só o corpo é dado — o resto da linha do heredoc é comando e continua verificado: `cat <<EOF; gh issue close 12`, `cat <<EOF && gh issue close 12` e `cat <<'EOF' | gh pr create --body "closes #999"` (sem evidência) saem 2, e `gh issue close 12` na linha seguinte ao `EOF` idem; heredoc sem linha de fechamento (delimitador nunca aparece) não trava o gate e o texto restante é verificado como hoje — provado por `bash hooks/testa-gate-fechar-issue.sh` exit 0 com os casos novos `ok`, e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 2. `principal-atrasado` faz no máximo quatro chamadas a `git` [tipo: implementar]
atende: D2, D4
arquivos: `hooks/lib/principal-atrasado.cjs`, `hooks/testa-principal-atrasado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/principal-atrasado.cjs`
  de: `const mergeadas = branchesMergeadas(principal);`
  para: `const mergeadas = new Set();`
  bateria: `bash hooks/testa-principal-atrasado.sh`
  fixture: caso (a) — worktree cuja branch aponta para origin/main deixa de ser listada como "já em origin/main"
pronto quando: em `hooks/lib/principal-atrasado.cjs` a branch de cada worktree linkado sai das linhas `branch refs/heads/<x>` e `detached` do mesmo `git worktree list --porcelain` já executado (não há mais chamada a `symbolic-ref`), entradas com linha `prunable` são ignoradas, e a função `branchesMergeadas(principal)` roda uma única vez `git branch --merged origin/main --format=%(refname:short)` e devolve um `Set` de nomes, consultado por worktree — a linha `const mergeadas = branchesMergeadas(principal);` ocorre uma vez; `hooks/testa-principal-atrasado.sh` ganha (**emenda da revisão, 2026-09-13:** os rótulos (e) e (f) já existiam — hook de abertura e "outra grafia" — e ficam; os casos novos são (g) e (h)): (g) fixture com 33 worktrees linkados (15 em branch própria não mergeada, 15 em branch criada de `origin/main`, e 3 detached), que afirma primeiro que o fixture montou (34 registrados no `worktree list --porcelain`) e em que um driver com `node -r <preload>` que embrulha `execFileSync`/`spawnSync`/`execSync` de `child_process` e conta as chamadas afirma `1 ≤ n ≤ 4` chamadas externas (0 reprova: o embrulho não pegou) e as 15 worktrees mergeadas presentes em `linhas()`, as 15 não mergeadas e as 3 detached ausentes; (h) worktree registrado cujo diretório foi apagado (`prunable`, afirmado no porcelain antes) não aparece e não derruba a função; os casos (a)–(f) existentes continuam `ok` com a mesma saída textual de antes; a bateria nova sobre a lib de `cf1ad768` reprova em (g) (66 chamadas com 33 worktrees) — provado por `bash hooks/testa-principal-atrasado.sh` exit 0 e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 3. O exportador de hooks de sessão nomeia o timeout [tipo: implementar]
atende: D3
arquivos: `scripts/exporta-hooks-sessao-start.cjs`, `scripts/testa-memoria-somente-leitura.sh`, `scripts/testa-exporta-hooks-sessao-start.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/exporta-hooks-sessao-start.cjs`
  de: `exitCode = 124;`
  para: `exitCode = 1;`
  bateria: `bash scripts/testa-exporta-hooks-sessao-start.sh`
  fixture: hooks.json sintetico com hook que dorme 3 s e timeout 1 -> EXIT_1 deixa de ser 124
pronto quando: em `scripts/exporta-hooks-sessao-start.cjs`, quando `proc.status === null` (processo morto pelo `timeout` do `spawnSync`), `exitCode = 124;` (uma ocorrência literal) e `stderr` recebe `timeout: hook nao respondeu em <N> ms` com N igual ao timeout aplicado em milissegundos; a bateria nova `scripts/testa-exporta-hooks-sessao-start.sh` monta um `hooks.json` sintético (dois hooks `command`: um `node -e "setTimeout(()=>{},3000)"` com `timeout: 1` e um `node -e "console.log('oi')"` com `timeout: 5`) apontado por variável de ambiente ou argumento que o exportador já aceite (ou passe a aceitar, declarado no docblock), e afirma `EXIT_1=124`, `ERR_1` contendo `timeout` e `1000 ms`, `EXIT_2=0` e `OUT_2` contendo `oi`; `scripts/testa-memoria-somente-leitura.sh` imprime `$ERR_FOCO` na linha de `FALHA foco-session-start.cjs sai 0` (nos três casos) — provado por `bash scripts/testa-exporta-hooks-sessao-start.sh` exit 0, `bash scripts/testa-memoria-somente-leitura.sh` exit 0 nesta máquina depois da T2 (e continuando exit 0 no CI), e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 4. README e travas: heredoc no gate de Issue, quatro chamadas no radar [tipo: docs]
atende: D1, D2, D3
arquivos: `README.md`, `docs/travas-mecanicas.md`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: texto; a coerência com o código é o critério abaixo, e `testa-mapa-regras.sh` confere que todo arquivo citado existe
pronto quando: a linha de `gate-fechar-issue.cjs` na tabela de gates do README diz que corpo de heredoc é dado e só conta quando alimenta um interpretador (`bash <<EOF`); `docs/travas-mecanicas.md` diz o mesmo na linha do gate e, na linha de `hooks/lib/principal-atrasado.cjs` (ou onde o radar de principal atrasado é descrito), que o custo é fixo em até quatro chamadas a `git` por abertura, medido em 2026-09-13 contra 324; a soma de casos das baterias dos gates é re-medida se `hooks/testa-gate-fechar-issue.sh` mudou de placar; `bash scripts/testa-mapa-regras.sh` sai 0 — provado por esses comandos e por `grep -c heredoc README.md docs/travas-mecanicas.md` devolvendo ≥ 1 em cada.

### 5. Versão 1.12.1 [tipo: docs]
atende: D5
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4
paralela: nao
mutacao: n/a
  motivo: número de versão; a divergência entre os dois lugares é o que `testa-versao.sh` já pega
pronto quando: `.claude-plugin/plugin.json` declara `1.12.1` e o badge do README repete o número, num commit próprio — provado por `bash scripts/testa-versao.sh` exit 0 e `node scripts/conferir-versao.cjs` exit 0.
