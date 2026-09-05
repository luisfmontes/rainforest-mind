# Handover — lote 3 (guardas, backup fora da máquina, fechar Issue com critério)

**Data:** 2026-09-03. **Branch:** `fluxo/guardas` (worktree `.claude/worktrees/fluxo-guardas`), base `origin/main` em `408af94` (1.1.0). **Estado do fluxo:** `2026-09-03-guardas`, `executar` reaberto pela reprovação do `revisar` (7 achados do auditor de segurança + 7 do revisor). **Checkout principal fica na `main`.**

> Se você só for ler um parágrafo: as 14 tarefas do plano estão integradas na branch com mutação vermelha re-rodada pela janela; a rodada 2 fechou os quatro bypasses de parser do auditor (`git -C` repetido, `;` em aspas, `gh.exe`/`"gh"`, `--body "$(...)"`) e o `--saida-arquivo`; falta a **rodada 3** (achados do revisor), depois `executar ok` → `revisar` (revisor + auditor de novo) → `verificar` → versão `1.2.0` → PR. O run parou por limite de sessão (reset 12:40) com o contexto da janela em 96%.

## O que falta (rodada 3), com o achado que motiva

| # | Onde | Achado (reproduzido pela janela ou pelo revisor) | Arquivos |
|---|---|---|---|
| R1 | `hooks/gate-worktree.cjs` ~667 | checagem de CLI ignora `incerto`: `cd $(pwd)/../principal && codex exec --yolo` de subagente passa | `gate-worktree.cjs`, `testa-gate-worktree.sh` |
| R2 | `gate-worktree.cjs` `procuraCLI` ~425 | `"codex" exec --yolo` passa (token entre aspas é pulado) — reproduzido: exit 0 | idem |
| R8 | `skills/limpar/SKILL.md:25` | texto diz que "sem `.git` próprio" é `limpo`; o código classifica como `órfão` | SKILL |
| R3 | `hooks/portaria.cjs` ~143-165 | `obterEstagioDesseLado` lê o estado a partir do worktree ATUAL; o estágio do outro worktree sai sempre `?`; o teste (c) só grepa a palavra "estágio" | `portaria.cjs`, `testa-portaria-diagnostico.cjs` |
| R4 | `scripts/backup.cjs` ~494 | `tmp` declarado, mas `compactarSimples` grava direto no nome final: não é atômico; `gravarAtomico` e `compactarComPowerShell` são código morto | `backup.cjs`, `testa-backup-gravar.sh` |
| R5 | `backup.cjs` `cmdConferir` | comparação unidirecional: item da lista D10 presente na origem e ausente do zip → "intacto" | `backup.cjs`, `testa-backup-conferir.sh` |
| R9/R10 | `backup.cjs:53`, `saude.cjs` ~1394 | `require('./hooks/lib/raiz.cjs')` errado (cai no fallback); `saude` duplica `resolverDestino` em vez de importar | `backup.cjs`, `saude.cjs` |
| R12 | `scripts/fechar-issue.cjs:103` | regex do critério aceita `(` ou `^` e zero parênteses | `fechar-issue.cjs`, `testa-fechar-issue.sh` |
| F6 | `vigias/backup-estado.ps1` ~132 | linha de erro com caminho absoluto (usuário) vai para `ERROS.md` versionado — sanitizar antes de `Registrar-Erro` | `backup-estado.ps1`, `testa-backup-estado.sh` |

O agente da F6 morreu no limite com 2 arquivos sujos em `.claude/worktrees/agent-a7685f1782d2465d0` (base `66d5fae`): olhe o diff antes de decidir reaproveitar; o da R1/R2 (`agent-aed5b44355b71dee2`) não chegou a editar. Os dois worktrees podem ser removidos.

Depois da rodada 3: `node scripts/estado.cjs marcar --slug 2026-09-03-guardas --estagio executar --status ok --json` com o ledger de mutação (14 itens, um por tarefa — o rascunho está no scratchpad desta sessão, refaça a partir dos relatórios se não existir), `exigir revisar`, revisor zerado + auditor, `verificar` (script `verificar-g3.sh` no scratchpad: uma linha por tarefa), bump `1.2.0`, PR com `closes #142, #143, #127, #131, #125, #145`. Corpo do PR rascunhado no scratchpad (`pr-body-g3.md`), com as decisões D3, D9, D12, D15, D17 marcadas para veto.

## O que este run ensinou (para o método)

- **Os testes bateram no GitHub real.** `spawnSync('gh')` não honra a ordem do PATH para `.cmd`; 16 comentários foram postados no PR #123 (apagados). Nasceram `hooks/lib/resolver-executavel.cjs` e a trava anti-gh-real nas baterias. **Node recusa `.cmd` sem `shell`** (EINVAL): o resolvedor usa `shell: true` só para `.cmd`/`.bat`, e só com argumentos do próprio script.
- **Stub batch com `enabledelayedexpansion` some com o `!` do marcador e, sob a suíte, escreve num arquivo chamado `!GH_LOG!`.** Stubs de `gh` agora são wrappers em Node.
- **O medidor comia a primeira letra também no lado "agora"** (`trim()` do stdout do git): a integração reprovou uma entrega por `ocs/rainforest/...` antes de a T6 consertar os dois lados.
- **Entregas com fonte mutado, bateria que não morde, ou bateria "mínima" no lugar da completa** apareceram em 4 de 14 tarefas; todas foram pegas na re-rodada da mutação pela janela.
- **A janela principal gastou o contexto (96%)** conferindo tudo e lendo relatórios inteiros. Observação plantada: teto de linhas no relatório de agente, conferência por script de uma linha por critério, handover ao passar de 70%.
- O gate de publicação confere o **arquivo inteiro** no commit: editar arquivo antigo com fixture pré-existente exige reescrever a fixture (aconteceu em 6 arquivos neste lote).
