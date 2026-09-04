# Handover — lote 3 (guardas), da rodada 3 à rodada 18

**Data:** 2026-09-04 09:41. **Branch:** `fluxo/guardas` (worktree `.claude/worktrees/fluxo-guardas`; o checkout principal fica na `main`). **HEAD:** `4ebd8a4` (já na `origin/fluxo/guardas` até aqui; o commit deste handover vem em seguida). **Base do diff:** `53c2a42` = `origin/main` em **1.2.0** (PRs #177 régua e #178 versão, mesclados pela outra janela e já absorvidos na branch por merge limpo). **Estado do fluxo:** `2026-09-03-guardas`, `executar` reaberto pela 16ª revisão (`revisar` reprovado: 1 achado do auditor; o revisor foi interrompido pelo handover, sem veredito). Trabalhe sempre no worktree; a portaria resolve o estágio pelo cwd.

> Se você só for ler um parágrafo: faltam **uma rodada de conserto** (rodada 18, um agente, ~30 min), `executar ok`, **a 17ª revisão** (revisor zerado + auditor), `verificar`, bump **1.3.0** (não 1.2.0: já saiu) e o PR com `closes #142, #143, #127, #131, #125, #145`. Tudo o que o lote entrega está integrado, com 13 baterias verdes e mutação re-rodada na integração para cada conserto.

## O que falta, na ordem

1. **Rodada 18 — um agente `rainforest-mind:executor` (sonnet), `isolation: "worktree"`, base = `git rev-parse HEAD` na hora.** Achado do auditor (16ª): `hooks/lib/tokens-comando.cjs` (`desempacotarWrapperDeString`, ~336-405) devolve `{interno:null, ilegivel:false}` para `source x.sh`, `. x.sh` (bash) e `. x.ps1`, `& x.ps1` (PowerShell) — o arquivo é opaco ao parser, e `bash x.sh` sem `-c` já vira `ilegivel:true` (postura conservadora). Conserto: `source`/`.`/`&` (este só em `tool_name: "PowerShell"`) viram ilegível → os três gates bloqueiam como já fazem para `bash x.sh`. Bateria: `hooks/testa-gate-staging-total.sh` (no principal, `source x.sh` → 2; `. x.sh` → 2; via `PowerShell`, `& .\x.ps1` → 2), `hooks/testa-gate-worktree.sh` (fora de worktree, `source rodar.sh` → 2), `hooks/testa-gate-fechar-issue.sh` (`source fechar.sh` → 2). Catraca com `--de`/`--para` literais; exit 0.
2. **Integração** como nas rodadas anteriores (receita abaixo).
3. `node scripts/estado.cjs marcar --slug 2026-09-03-guardas --estagio executar --status ok --json "$(cat /c/Users/Luis/AppData/Local/Temp/claude/C--Projetos-rainforest-mind/a3d9c153-38c3-4462-9356-dd17f50f1db5/scratchpad/marcar-ok-r17.json (ajustado))"` — o JSON é o `marcar-ok-r17.json` do scratchpad desta sessão com `rodada: 18`, a `saida` atualizada com o placar e `rodada18: {...}`; o campo `mutacao` (14 itens, um por tarefa) já está lá e não muda.
4. `exigir revisar` (tira o instantâneo; **não commite o estado antes de `marcar revisar`**, o HEAD tem de ficar parado) → **17ª revisão**: revisor + auditor, briefings `brief-revisor-g3r16.md`/`brief-auditor-g3r16.md` do scratchpad com `__HEAD__` = HEAD novo e mais uma linha "16ª revisão (fechado na rodada 18): `source`/`.`/`&` viram ilegível". Os dois são **folha** (não despacham `Agent`) e classificam bypass por modelo de ameaça (emenda no plano).
5. `verificar`: `bash /c/Users/Luis/AppData/Local/Temp/claude/C--Projetos-rainforest-mind/a3d9c153-38c3-4462-9356-dd17f50f1db5/scratchpad/verificar-g3.sh <worktree>` — uma linha por tarefa (T1…T14 + dep + enc + saúde); marcar com comando e saída.
6. **Bump 1.3.0**: `.claude-plugin/plugin.json` e a badge do `README.md` (linha 7), commit próprio `1.3.0 — ...` (MINOR), marcado para veto no PR.
7. `fechar`: PR com o corpo do apêndice A (troque `VERIFICAR_PLACAR`, `SUITE_PLACAR`, `REVISAR_RESUMO`), `closes #142, closes #143, closes #127, closes #131, closes #125, closes #145`; `node scripts/conferir-versao.cjs`; `marcar fechar ok --json '{"acao":"pr"}'`.

## Receita de integração (o que funcionou 17 vezes)

```
node scripts/conferir-entrega.cjs --repo-principal "$(pwd)" --worktree ../agent-<id> --base <hash> --head-antes <hash> --sujo-antes <porcelain-antes.txt> --paralelo --espera <cada arquivo prometido>
git merge --no-ff -m "Merge lote 3 rodada N (...) into fluxo/guardas" worktree-agent-<id>
node scripts/conferir-mutacao.cjs --raiz . --arquivo <fonte> --de '<literal do diff>' --para '<inversão>' --bateria 'bash <bateria>'   # exit 0 = vermelha; 2 = não mede; 3 = --de não casa; 4 = ambíguo
git worktree remove --force ../agent-<id>; git branch -D worktree-agent-<id>
```
Depois: as 12 baterias rápidas em sequência e `scripts/testa-saude.sh` **em segundo plano** (em paralelo com as outras ela passa de 10 min). `ls "$(printenv OneDrive)/rainforest-backup"` tem de dar "No such file or directory".

## Cuidados que custaram caro

- **Agente não cola `--de`/`--para` literais** (haiku sempre, sonnet às vezes): re-derive do diff (`git -C <wt> diff <base>..HEAD -- <arquivo>`), nunca aceite `<literal>`. Whitespace do `--de` tem de ser exato (uma mutação saiu `3` por indentação; extraia com node do arquivo).
- **Mutação neutra sai `2`**: antes de reprovar a bateria, confira que o `--de` está no mecanismo vivo (o regex `SEPARADORES` não era mais o consumidor; o laço em `segmentosComAspas` era).
- **Revisor da 6ª revisão despachou 4 sub-revisores nomeados** que nunca responderam e ficaram no roster; matei com `TaskStop`. Briefings dizem "você é folha".
- **Baterias gravaram zips reais em `%OneDrive%\rainforest-backup` três vezes** (14 bytes de `FOCO.md` de caixa cada); removidos; trava `verificar_destino_seguro` desde a rodada 7. Confira o `ls` depois de toda bateria.
- **Limite de sessão da conta** derrubou revisor/auditor duas vezes (reset às 19:20 e às 04:50); o transcript do agente morto fica em `tasks/<id>.output` — grep bounded (`grep -o 'exit=[0-9]\+[^"]\{0,80\}'`), nunca `Read` inteiro.
- **Diretórios de worktree de agente ficam presos** (Permission denied) por minutos; `rm -rf` depois resolve. Os que estão em `.claude/worktrees` agora: `versao-1-2-0` (sobra da outra janela, não registrado) e `handover-rodada-cega` (worktree da outra janela, branch `relatorio/rodada-cega-20260904`) — **não são meus**.
- **Portaria barra `executor` com estágio `revisar` ativo**: marque `reprovado` antes de despachar conserto.

## O que este run ensinou (plantado em `ideias.jsonl`, tipo observacao)

- `gate-por-parser-de-shell-e-poco-sem-fundo`: 16 revisões, um vetor novo por rodada. A emenda do plano (6ª revisão) fixou o modelo de ameaça: **agente cooperativo que erra**; só-adversário vira residual. Ainda assim cada rodada achou um cooperativo plausível (`env -u`, `-o pipefail`, `timeout -s`, `source`…). Decisão a tomar no PR: aceitar a lista residual e parar, ou trocar o mecanismo (PATH do subagente sem `gh`; wrapper do `gh` que exige o marcador).
- `bateria-com-fallback-de-destino-real-precisa-de-trava`: o incidente do OneDrive.
- `revisor-que-despacha-sub-revisores-nomeados`: revisor/auditor são folha.

## Emendas registradas no plano (`docs/rainforest/planos/2026-09-03-guardas.md`, seção "Emendas")

Handover é rastro; D14 flags separadas; rodada 5 dentro das tarefas; `tokens-comando.cjs` na Tarefa 1; **modelo de ameaça**; gates cobrem a ferramenta `PowerShell`; D15 ganha `gh pr edit` e lê a descrição real no `gh pr merge`.

## Apêndice A — corpo do PR (rascunho)

## Lote 3 — guardas medem o repositório da operação; backup fora da máquina; fechar Issue exige critério rodado

Três dívidas com Issue aberta, uma entrega: (A) os guardas passam a medir o repositório **onde a operação roda**, com uma resolução só (#142, #143, #127, #131); (B) os dados do rainforest ganham cópia fora da máquina, sem credencial em processo não supervisionado (#125); (C) fechar Issue passa a exigir o critério de pronto rodado e colado, por mecanismo (#145).

**Como este PR nasceu — e o que você deve vetar.** Brainstorm conduzido pela sessão sozinha, em run autônomo autorizado em 2026-09-02 como teste. As 17 decisões do design (`docs/rainforest/design/2026-09-03-guardas.md`) são da sessão, não suas; as que mais merecem seu olhar:

- **D3** — a portaria continua decidindo pelo cwd da sessão; só a mensagem ganha raiz, branch, estágio e os outros worktrees com fluxo aberto (nada de adivinhar worktree).
- **D9** — destino do backup: `%OneDrive%\rainforest-backup`, porque a pasta já está autenticada nesta máquina e sincroniza sozinha; `Z:` estava desconectada e repo privado a #118 já rejeitou.
- **D12** — o sentinela agendado passa a chamar `node scripts/backup.cjs gravar` (só escreve em pasta local).
- **D15** — hook novo barra `gh issue close` direto e `closes #N` em PR sem comentário de evidência marcado; saídas de emergência iguais aos outros gates.
- **D17** — o template do `/issue` exige `## Critério de pronto (falsificável)` e `fechar-issue.cjs` recusa Issue sem a seção.

Plano: `docs/rainforest/planos/2026-09-03-guardas.md` (14 tarefas, todas com catraca de mutação re-rodada pela janela principal na integração).

## O que entrou

| Ramo | Entrega |
|---|---|
| A | `hooks/lib/cwd-efetivo.cjs` (extraído do `gate-worktree`), `gate-staging-total` decide pelo cwd efetivo, portaria nomeia o que leu, `scripts/limpar-worktrees.cjs` (órfão nunca é "sujo"), `conferir-entrega --escopo` (deleção fora do escopo reprova), BOM e `trim()` do porcelain consertados nos dois lados, `hooks/lib/clis-que-escrevem.cjs` no `gate-worktree` |
| B | `scripts/backup.cjs gravar/conferir` (zip diário, atômico, teto 30, hash na restauração, "sincronizacao e do OneDrive, nao conferida aqui"), sentinela chama o backup, `/saude` alerta backup velho |
| C | `scripts/fechar-issue.cjs` (posta evidência marcada, fecha; `--saida` e `--saida-arquivo` separados), `hooks/lib/resolver-executavel.cjs`, `hooks/gate-fechar-issue.cjs` (quinto gate), `commands/issue.md` com a seção obrigatória |

## O que o run ensinou (e está nos relatórios)

- **Testes bateram no GitHub real.** O `spawnSync('gh')` do Node não honra a ordem do PATH para `.cmd`, e o stub da bateria nunca rodava: 16 comentários de teste foram postados no PR #123 (apagados). Nasceram o `resolver-executavel.cjs` e a trava anti-gh-real nas baterias.
- **O Node recusa `.cmd` sem shell** (EINVAL, CVE-2024-27980): o resolvedor usa `shell: true` só para `.cmd`/`.bat`, e só com argumentos que o script controla.
- **O medidor comia a primeira letra** também no lado "agora" (`trim()` do stdout do git): a própria integração deste lote reprovou uma entrega por `ocs/rainforest/...` antes de a T6 consertar os dois lados.
- **Duas entregas vieram com o fonte mutado ou com bateria que não morde**, e as duas foram pegas na re-rodada da mutação pela janela.

## Evidência

```
VERIFICAR_PLACAR
```

Suíte completa na branch: SUITE_PLACAR

`revisar`: revisor zerado + auditor de segurança, REVISAR_RESUMO

## Versão

`1.2.0` → `1.3.0` (MINOR: cinco comandos/hooks novos e um gate a mais; a 1.2.0 saiu pela outra janela, PR #178, durante este run). Depois do merge: `/plugin marketplace update rainforest-mind` + janela nova; o sentinela agendado passa a gravar em `%OneDrive%\rainforest-backup` na próxima ronda.

Closes #142, closes #143, closes #127, closes #131, closes #125, closes #145.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01JsVDaSaZ3hCgumGVytmKgS


## Rodadas de revisão (o que o revisor zerado e o auditor acharam, e o que entrou por causa disso)

| Rodada | Achados que bloquearam | Conserto |
|---|---|---|
| 1ª | 7 do revisor (R1–R12) + 7 do auditor (F1–F7) | rodadas 2 e 3 do `executar`: `incerto` bloqueia CLI, token citado em posição de comando, portaria lê o estado do outro worktree, zip atômico, `conferir` bidirecional, `require` da raiz, `saude` importa `resolverDestino`, regex do critério exige parênteses, `git -C` repetido, separador em aspas, `gh.exe`/`"gh"`, `--body "$(...)"`, `--saida-arquivo` confinado. **F6 era falso positivo**: `Get-MotivoSaneado` (pré-existente) já saneava o caminho; entrou só um teto de 200 chars. |
| 2ª | `alvosBash` pegava o primeiro `-C`; `gate-fechar-issue` só olhava o primeiro token (`true && gh issue close 12`); `(cd X && codex)` com `incerto=false`; `$'codex'`; raiz crua no `limpar` | rodada 4 |
| 3ª | `procuraCLI` casava palavra solta (`grep -rn claude .` bloqueado); cwd **final** da linha em vez do cwd no ponto da CLI (`codex exec && cd <wt>`); `pushd`, `env -C`; `(gh ...)`, `$(gh ...)`, `{ gh; }`, `env/eval/nohup/timeout/xargs gh`, `pwsh -c`, `-EncodedCommand`; rename no `--escopo` | rodada 5: `cwdPorSegmento`/`resolverMovedor`, `procuraCLI` só em posição de comando ou após wrapper, `gate-fechar-issue` segmenta por `( ) { } $(` e pula prefixos |
| 4ª | `&` simples não separava (`echo hi & cd <principal>; git commit`, `sudo & gh issue close 42`); `seg.includes("git")` + `-C` do `grep` corrompia o cwd; zip nomeado por UTC (bateria flakey das 21h à meia-noite) | rodada 6: `&` nos três gates, `comandoEhGit` por posição de comando (`hooks/lib/tokens-comando.cjs`), `dataLocal` |
| 5ª | revisor `ok`; auditor: `env -C . git add -A` escapava do staging-total (tokenizador próprio); `Closes <url>/issues/N` não era extraído; **a bateria do vigia gravou zips reais em `%OneDrive%ainforest-backup`** (três vezes ao longo do run, 14 bytes de `FOCO.md` de caixa cada; removidos) | rodada 7: staging-total acha o git por `posicaoDeComando`; `closes` por URL; bateria com trava `verificar_destino_seguro`, destino de caixa em toda chamada e checagem do OneDrive real antes/depois |
| 6ª | revisor: `env -u X` não pulado em `posicaoDeComando` (staging-total e gate-worktree liberam), parser próprio do gate-fechar-issue com o mesmo furo, **`--body "don't forget: closes #42"` capturava `don`** (prosa comum); auditor: `\cd`/`command cd`/`builtin cd`, `"$(gh issue close 42)"` em aspas duplas, truncar antes de sanear no vigia | rodada 8: tabela de flags por wrapper em `tokens-comando.cjs`, gate-fechar-issue sobre o mesmo tokenizador, `--body` por token, `$( )` em aspas duplas, `cd` via wrapper, vigia saneia antes de truncar |
| 7ª | revisor: `env -u X --chdir=<principal> git add -A` (o `-C` do `env` era regex, só logo após `env`); auditor: `Invoke-Expression`/`iex` não era wrapper; **`gate-worktree` e `gate-staging-total` só agiam na ferramenta `Bash`** — pela ferramenta `PowerShell` (a primária nesta máquina) tudo passava, linha anterior ao lote | rodada 9: `env -C` por tokens, `iex` como wrapper, os dois gates agem em `PowerShell` com `Set-Location`/`sl`/`Push-Location`/`Pop-Location` como movedores (emenda no plano) |
| 8ª | auditor: `Set-Location -Path:X` (dois-pontos) fabricava um cwd inexistente que os gates liam como "fora de repo, passa"; revisor: **`limpar-worktrees` ignorava `logs/`, `index`, `HEAD`… do porcelain** e `--remover --force` destruía um worktree com `logs/app.log` não rastreado | rodada 10: destino inexistente ou começando com `-` vira incerto; lista de exclusão removida (qualquer linha do porcelain é sujeira) |
| 9ª | revisor `ok`; auditor: `timeout -s TERM 30 <cmd>` (flag com valor não modelada); da leitura do transcript do revisor interrompido por limite: `Invoke-Expression "git add -A"` passava no staging-total e no gate-worktree (só o gate-fechar-issue sabia `iex`) | rodada 11: `timeout` na tabela de flags; desempacotamento de wrapper de string (`eval`, `-c`, `iex`) movido para `tokens-comando.cjs` e usado pelos três gates |
| 10ª | revisor `ok`; auditor: `bash -xc "git add -A"` (flags curtas coladas ao `-c` não eram wrapper) | rodada 12: `-c` colado a outras flags curtas reconhecido |
| 11ª | revisor `ok`; auditor: `timeout 5 bash -c "git add -A"` (pulo de prefixo e desempacotamento de wrapper não se compunham no staging-total e no gate-fechar-issue; o gate-worktree já fazia) | rodada 13: composição nos dois gates, `textoAPartir` no módulo compartilhado |
| 12ª | revisor `ok` (nota: `# gh issue close` em comentário shell super-bloqueava); auditor: `bash -o pipefail -c "..."` (flag com valor antes do `-c` derrubava o desempacotador em silêncio) | rodada 14: flags com valor dos shells; token desconhecido antes do `-c` vira ilegível; comentário shell fora da rede de segurança |
| 13ª | revisor `ok`; auditor: `--body-file` relativo era lido do cwd do processo do hook, não do cwd efetivo do segmento (`cd <wt> && gh pr create --body-file corpo.txt` com homônimo no principal) | rodada 15: caminho resolvido por `cwdPorSegmento`; segmento incerto → ilegível |
| 14ª | revisor `ok`; auditor: `cwdDoSegmento` (introduzido na rodada 15) casava o segmento por texto e devolvia a primeira ocorrência — dois `cd X && gh pr create --body-file corpo.txt` idênticos na mesma linha liam o corpo errado | rodada 16: casamento pela k-ésima ocorrência; ambiguidade → ilegível |
| 15ª | revisor `ok`; auditor: `gh pr edit --body "Closes #12"` não era gatilho, e o `--body` do `gh pr merge` é a mensagem do merge commit, não a descrição do PR | rodada 17: `pr edit` vira gatilho; no `merge` o gate lê a descrição real com `gh pr view --json body` (só leitura) e bloqueia se não conseguir ler (emenda D15) |
| 16ª | auditor: `source x.sh`, `. x.sh` e `& .\x.ps1` saíam como "não é wrapper" (arquivo opaco; `bash x.sh` já era ilegível); revisor interrompido pelo handover | **rodada 18 (pendente)**: `source`/`.`/`&` viram ilegível |

**Decisão da sessão para seu veto (emenda no plano, 6ª revisão):** o modelo de ameaça dos gates por texto é o **agente cooperativo que erra**; vetor que só um adversário escreveria entra na lista residual e não bloqueia — foi o critério de parada que faltava. **O que isto ensina, e está plantado como observação:** gate que decide lendo o texto do comando não converge por rodada de auditoria — cada rodada acha o próximo wrapper. Ficou a pergunta para a Issue seguinte: modelo de ameaça (agente cooperativo que erra vs. adversário) e, para o adversário, guarda que não seja por texto (PATH do subagente sem `gh`, ou wrapper do `gh` que exige o marcador). **Lacuna declarada** (baixa): flag de diretório da própria CLI (`codex --cwd X`) não é modelada.

## Apêndice B — `verificar-g3.sh`

```
#!/usr/bin/env bash
# Estagio verificar do lote 3: o "pronto quando" de cada tarefa do plano contra o artefato real.
cd "$1" || exit 9
r() { local n="$1"; shift; OUT=$("$@" 2>&1); rc=$?; printf 'T%s | exit=%s | %s\n' "$n" "$rc" "$(printf '%s' "$OUT" | tail -1 | cut -c1-110)"; }
r 1 bash hooks/testa-cwd-efetivo.sh
r 2 bash hooks/testa-gate-staging-total.sh
r 3 bash hooks/testa-portaria.sh
r 3b node hooks/portaria.cjs --lint
r 4 bash scripts/testa-limpar-worktrees.sh
r 5 bash scripts/testa-conferir-entrega.sh
r 7 bash hooks/testa-gate-worktree.sh
r 8 bash scripts/testa-backup-gravar.sh
r 9 bash scripts/testa-backup-conferir.sh
r 11 bash scripts/testa-backup-estado.sh
r 12 bash scripts/testa-fechar-issue.sh
r 13 bash hooks/testa-gate-fechar-issue.sh
r 13b bash hooks/testa-config.sh
r 14 grep -nF '## Critério de pronto (falsificável)' commands/issue.md
r dep bash scripts/testa-dependencias-de-bateria.sh
r enc node scripts/conferir-encoding.cjs
r 10 bash scripts/testa-saude.sh
```
