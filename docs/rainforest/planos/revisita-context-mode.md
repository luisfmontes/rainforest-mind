# Plano: Revisita do `mksglu/context-mode` — #514, ranking bm25 no `buscar`, livro de repos

Design: docs/rainforest/design/revisita-context-mode.md

## O que não pode quebrar
- Tudo o que o `gate-worktree` barra hoje continua barrado. Escrita real no principal por subagente sai 2:
  - `echo x > f.txt`;
  - `cd <principal> && echo x > f` a partir do worktree;
  - `&{git checkout main}` (PowerShell);
  - o caso (j) do `testa-cwd-efetivo.sh`, ou seja, `(cd <principal> && codex exec --yolo)`.
- Os gates que consomem `segmentosComAspas` continuam verdes nas suas baterias: `testa-cwd-efetivo.sh`,
  `testa-gate-worktree.sh`, `testa-gate-fechar-issue.sh`, `testa-gate-mensagem-commit.sh` e
  `testa-gate-staging-total.sh`.
- `memoria.cjs buscar` sem `--texto` continua listando por recência. Com texto de pontuação crua, ainda
  repete a busca com os termos citados. Substituída continua fora.

## Tarefas

### 1. `/dev/null` e `$null` não são alvo de escrita (#514 P1) [tipo: implementar]
atende: D1
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
paralela: nao
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && node -e 'process.stdout.write(JSON.stringify({session_id:"p",agent_id:"a",agent_type:"Explore",cwd:process.argv[1],tool_name:"Bash",tool_input:{command:"(ls x) 2>/dev/null"}}))' "$P" | node hooks/gate-worktree.cjs`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `function ehDescarteDeSaida(alvo, ehPowerShell) {`
  para: `function ehDescarteDeSaida(alvo, ehPowerShell) { return false;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `600000`
  fixture: testa-gate-worktree.sh, secao "(#514) redirecionamento para descarte nao e escrita"
pronto quando: com payload PreToolUse real (`agent_type: Explore`, `cwd` = checkout principal deste repo):
- `(ls x) 2>/dev/null` (Bash) → **0**; na base `bae41ad3` era 2;
- `(ls x) > $null` (PowerShell) → **0**; na base era 2;
- `(ls x) > nul` → **2**, porque `NUL` continua sendo alvo;
- `echo x > f.txt` → **2**.

Provado por `bash hooks/testa-gate-worktree.sh` com 0 falhas, com os casos impressos. `alvosBashEscrita`
chama `ehDescarteDeSaida` antes de `empurra` no ramo de redirecionamento. *(Emenda de 2026-10-15, security review do commit `ebc926fd`: no bash `$null` é variável comum — `null=a.txt; echo x > $null` escreve —, então `$null` só é descarte com `tool_name: PowerShell`; no bash, `(ls x) > $null` e `null=a.txt; echo x > $null` → **2**. A âncora da mutação ganhou o parâmetro `ehPowerShell`.)*

### 2. Expansão de chaves em argumento não corta segmento (#514 P2) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 1
paralela: nao
prova: `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") && node -e 'process.stdout.write(JSON.stringify({session_id:"p",agent_id:"a",agent_type:"Explore",cwd:process.argv[1],tool_name:"Bash",tool_input:{command:"ls 2>/tmp/x.log; echo a/{b,c}/d"}}))' "$P" | node hooks/gate-worktree.cjs`
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `function fimDaExpansaoDeChaves(cmd, i, atual) {`
  para: `function fimDaExpansaoDeChaves(cmd, i, atual) { return -1;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `600000`
  fixture: testa-gate-worktree.sh, secao "(#514) expansao de chaves em argumento nao e grupo"
pronto quando: com payload PreToolUse real (Explore, `cwd` = checkout principal), saem **0**:
- `ls 2>/tmp/x.log; echo a/{b,c}/d` (na base era 2, e só P2 conserta);
- os quatro casos exit=2 da tabela da #514;
- `wc -l skills/{a,b}/SKILL.md`;
- `echo {1..3}`.

Continuam **2**:
- `&{git checkout main}` (PowerShell);
- `{ cd x; } > f`;
- o (j) do `testa-cwd-efetivo.sh`.

A partir do worktree, `A=1 {cd,<principal>}; echo x > f` e `if true; then {cd,<principal>}; fi; echo x > f`
têm o mesmo exit da base: a tarefa não piora os contornos do D5. Provado por
`bash hooks/testa-cwd-efetivo.sh && bash hooks/testa-gate-worktree.sh && bash hooks/testa-gate-fechar-issue.sh && bash hooks/testa-gate-mensagem-commit.sh && bash hooks/testa-gate-staging-total.sh`,
tudo com 0 falhas. *(Emenda de 2026-10-15, D5: do worktree, `echo {a,b}; A=1 cd <principal>; git commit`, `echo {a,b}; if true; then cd <principal>; fi; git commit`, `A=1 cd <principal>; echo x > f`, `if cd <principal>; then echo x > f; fi` e `! cd <principal>; git commit` → **2**, e `A=1 cd <worktree>; git commit` → **0**. Seção "(#514/#530) cd depois de atribuicao ou palavra reservada e movedor" do `testa-gate-worktree.sh`. Diferencial base × branch em 40 candidatos: nenhuma passagem de 2 para 0 além de `echo {a,b}; git commit` no worktree, que é o falso positivo pretendido.)*

### 3. `buscar --texto` ordena por relevância (bm25) [tipo: implementar]
atende: D3
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-memoria.sh 2>&1 | grep -qE '^ +ok +buscar --texto ordena por bm25'`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `const ORDEM_BUSCA_TEXTO = 'ORDER BY bm25(observacoes_fts), o.criada_em DESC';`
  para: `const ORDEM_BUSCA_TEXTO = 'ORDER BY o.criada_em DESC';`
  bateria: `bash scripts/testa-memoria.sh`
  timeout: `600000`
  fixture: testa-memoria.sh, secao "buscar --texto ordena por bm25"
pronto quando: num banco de sandbox (`RFM_ROOT` temporário) com duas observações do mesmo projeto:
- a mais antiga tem o termo `RELEVANCIA` três vezes, e a mais nova só uma;
- `node scripts/memoria.cjs buscar --texto RELEVANCIA --json` devolve a mais antiga primeiro;
- sem `--texto`, a mais nova vem primeiro.

As seções 23 e 24 do `testa-memoria.sh` continuam verdes. Provado por `bash scripts/testa-memoria.sh` com
0 falhas.

### 4. Revisita no livro e enxertos plantados [tipo: docs]
atende: D4
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: é texto de registro mais ideias plantadas por script, sem ramo de execução a inverter
pronto quando:
- a linha `mksglu/context-mode` do `vigias/livro-de-repos.md` mantém `2026-08-11` e contém
  `revisita 2026-10-15`, provado por `grep -c "revisita 2026-10-15" vigias/livro-de-repos.md` ≥ 1;
- o push registrado é 2026-10-14;
- `node scripts/ideias.cjs listar` mostra as 4 ideias novas de enxerto (trigram+RRF, Q→A do
  AskUserQuestion, snippet por `highlight()`, bloco de retomada com teto), cada uma com "ELv2" na
  descrição.

### 5. Issue dos contornos, versão, CHANGELOG e README [tipo: docs]
atende: D5, D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4
paralela: nao
mutacao: n/a
  motivo: são metadados de versão e uma Issue no GitHub; o comportamento é provado nas tarefas 1 a 3
pronto quando:
- existe uma Issue aberta com os três contornos do D5, cada um com payload e exit medido na base;
- a #514 tem comentário com a causa raiz em `cwd-efetivo.cjs`;
- `plugin.json` (dos dois) e o topo do `CHANGELOG.md` mostram a mesma versão nova, um patch acima de
  `origin/main`;
- o README cita a versão nova onde cita a atual.
