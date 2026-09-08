# Agentes do rainforest em Codex ou Claude, por escolha do usuário

## Objetivo

Cada agente de função do plugin (`executor`, `revisor`, `tester`, `planejador`,
`depurador`, `documentador`, `resolvedor-de-build`, `arqueologo`,
`auditor-de-seguranca`) passa a poder rodar em **Claude** (Agent tool, como
hoje) ou em **Codex CLI**, e quem decide é o usuário: um default por agente no
manifesto e a palavra dele no despacho. Portaria, worktree isolado, briefing de
cinco blocos e conferência de entrega continuam os mesmos, seja qual for o
runtime. Absorve do `openai/codex-plugin-cc` o que não depende de worker em
background: `transfer` e o review gate no `Stop`, ambos opt-in.

Apuração que embasou (2026-09-08): leitura integral do `codex-plugin-cc`
(commit `db52e28`) e do que o rainforest já tem — `hooks/lib/cli-externo.cjs`,
`scripts/conselho.cjs`, `scripts/segunda-opiniao.cjs`, portaria, `executar`,
`modo-dev`, e a branch `codex/adaptacao-multihost-design` do agente Codex que
trabalha em paralelo neste repo.

## Decisões fechadas

- **D1 — A escolha mora no manifesto, com override por despacho** — porquê:
  `.rainforest/agentes.json` ganha o campo opcional `runtime` por agente
  (`"claude"` default, ou `"codex"`); a portaria já lê e o `revisar` já audita
  esse arquivo. A palavra do usuário no turno ("faz no codex") vence o default
  sem editar arquivo: o despacho grava `runtime: codex` no bloco 1 do briefing,
  e a portaria registra o campo `runtime` em cada linha de `despachos.jsonl`.
  Ausência do campo é `claude`, para todo manifesto existente continuar válido.
- **D2 — Transporte é `codex exec`, sobre o `cli-externo.cjs` existente** —
  porquê: o transporte já resolve stdin, timeout e matança de descendência no
  Windows, e tem bateria com mutação. O que o `app-server` JSON-RPC dá a mais
  (resume, interrupt, streaming) o fluxo não usa: agente que edita nunca é
  retomado (regra 10 / `executar`). `app-server` está marcado experimental na
  0.151.0. Flags: `-C <worktree>`, `-s read-only|workspace-write`,
  `--skip-git-repo-check`, `-o <arquivo>` para a última mensagem, `-m <modelo>`
  e `-c model_reasoning_effort=<nível>`; prompt por stdin.
- **D3 — O despacho continua pelo Agent tool; o `agents/<nome>.md` ganha um
  preâmbulo de ponte** — porquê: com `runtime: codex` no briefing, o subagente
  Claude faz **uma** chamada Bash a `scripts/despachar-codex.cjs` e devolve a
  saída literal (o desenho do `codex-rescue` da OpenAI). Assim
  `isolation: "worktree"` segue criando o worktree, a portaria segue vendo
  `subagent_type`, o briefing segue nos cinco blocos e `conferir-entrega.cjs`
  segue validando. O custo é um haiku de ponte por despacho. Chamar o script
  direto da janela principal deixaria a portaria cega e passaria o worktree
  para o script.
- **D4 — Uma fonte de método: o script lê o mesmo `agents/<nome>.md`** —
  porquê: o corpo (sem frontmatter e sem o preâmbulo de ponte) vira o prompt
  de sistema do Codex, seguido do briefing. `model:` do frontmatter mapeia
  para `-m` e `model_reasoning_effort` por tabela em `hooks/lib/config.cjs`
  (chaves `codex-modelo-haiku`, `codex-modelo-sonnet`, `codex-modelo-opus`),
  com default o modelo do `~/.codex/config.toml` do usuário (hoje
  `gpt-5.6-sol`, `medium`). Método não diverge entre famílias.
- **D5 — Sandbox segue `escreve` do manifesto** — porquê: `escreve: false` →
  `-s read-only` (permite rodar comando, o `revisor` precisa reproduzir
  achado); `escreve: true` → `-s workspace-write -C <worktree>`. Worktree do
  Claude Code tem o gitdir fora dele
  (`.git` é um arquivo `gitdir: <repo>/.git/worktrees/<nome>`), então o
  script passa `--add-dir <repo>/.git` para o commit ser possível; sem isso o
  Codex escreve mas não commita. Aprovação em `exec` é não-interativa; o
  script fixa `-c approval_policy="never"` e nunca usa
  `--dangerously-bypass-approvals-and-sandbox`.
- **D6 — Foreground, teto de 10 minutos, tarefa fatiada pelo plano** —
  porquê: o worker destacado com estado em disco e `status/result/cancel` é o
  grosso do código da OpenAI e só paga quando uma tarefa estoura o teto. O
  script recebe `--timeout-ms` (default 540000, abaixo do teto do Bash) e
  reporta timeout como falha fechada, com a última mensagem parcial se houver.
  Plantado: worker em background, gancho = primeira tarefa que morrer por
  timeout.
- **D7 — Nenhum comando novo espelhando `review`, `adversarial-review` ou
  `rescue`** — porquê: `review` é o `revisor` em Codex; `adversarial-review`
  já existe como segunda opinião cross-model no `revisar` (PR #140);
  `rescue` é o `depurador` em Codex. Duplicar viraria dois caminhos para a
  mesma função.
- **D8 — `transfer` entra, opt-in, como script** — porquê: leva uma sessão
  Claude Code (o `.jsonl` de `~/.claude/projects`, capturado no
  `SessionStart` que o plugin já tem) para uma thread Codex retomável por
  `codex resume <id>`. `scripts/transferir-para-codex.cjs`, sem comando novo
  além de um `commands/transferir.md` fino. Desligado por padrão, chave
  `transfer-codex` na config.
- **D9 — Review gate no `Stop` entra, opt-in, e reaproveita o `revisor` em
  Codex** — porquê: é a mesma peça de D3 chamada por hook: antes de o Claude
  parar, o `revisor` em Codex lê a última resposta e devolve `ALLOW` ou
  `BLOCK: motivo`; `BLOCK` sai como decisão JSON do hook, nunca como exit
  code. Chave `gate-review-codex`, default `false`, teto de 10 minutos, e
  indisponibilidade do Codex **bloqueia com motivo** (falha fechada, D6 da
  segunda opinião). Fica ao lado de `gate-agente-em-voo.cjs` no `Stop`.
- **D10 — v1 valida em dois agentes reais, o resto herda** — porquê:
  `executor` (escreve, worktree, `workspace-write`, commit via `--add-dir`) e
  `revisor` (read-only) são as duas classes de `escreve`. Os outros sete
  ganham o preâmbulo de D3 mas não têm rodada real na v1.
- **D11 — Bateria com fixture; Codex real só na validação manual** — porquê:
  padrão já fixado em D7 da segunda opinião e D11 do conselho. O script aceita
  `RFM_TEST=1` + `CODEX_CMD` para injetar um dublê, e a bateria prova por
  mutação que o dublê não passa onde o real falharia.
- **D12 — Erro deste trabalho se corrige aqui, sem Issue; defeito alheio
  vira Issue, não conserto** — porquê: decisão do usuário (2026-09-08). O que
  estiver errado no diff, no design ou nas tarefas deste fluxo é consertado na
  própria branch; o fluxo não termina abrindo Issues sobre o que ele mesmo
  fez. Mau funcionamento do repo sem relação com esta mudança recebe Issue com
  evidência e fica fora do escopo daqui.
- **D13 — Não toca a frente do agente Codex paralelo** — porquê: as branches
  `codex/*` e worktrees `.claude/worktrees/codex-*` são de outro dono; a
  frente dele é rainforest **dentro** do Codex como host, esta é Codex como
  **runtime de subagente dentro do Claude**. Os scripts nascem neutros de host
  (Node, zero dependência, sem `CLAUDE_*` obrigatório) para ele reaproveitar.

## Avaliado e descartado

- **`app-server` JSON-RPC como transporte** — dá resume, interrupt e
  streaming, mas o fluxo proíbe retomar agente que edita e o transporte
  `exec` já está pronto e testado; `app-server` é experimental na 0.151.0.
- **Chamar o script direto da janela principal, sem subagente Claude** —
  economiza um haiku, mas a portaria (matcher `Task|Agent`) não vê o despacho
  e o worktree isolado passa a ser obrigação do script; dois mecanismos de
  admissão em vez de um.
- **Prompt separado por agente para Codex** — método divergiria entre
  famílias e o `agents/*.md` deixaria de ser a fonte.
- **Worker em background com `status/result/cancel` na v1** — sem tarefa que
  estoure 10 minutos, é casca vazia; plantado com gancho concreto.
- **Comandos `review`/`adversarial-review`/`rescue`** — já existem como
  função (`revisor`, segunda opinião, `depurador`); só o runtime muda.

## Fora de escopo

- Gemini como runtime de agente: reservado, mesma trilha de D7 do design
  multihost do agente Codex; entra quando o Codex estiver rodando.
- Rainforest instalado **dentro** do Codex (manifesto `.codex-plugin/`,
  hooks no host Codex): é a frente do agente paralelo.
- Benchmark Claude × Codex por agente.
- Coautoria dos commits gerados em Codex: continua a regra do repo.

## Em aberto

- (vazio)

## Emenda de 2026-09-08 — o que a T8 com Codex real derrubou

- **D5, parte do commit, estava errada.** O sandbox `workspace-write` do Codex
  marca `.git` como somente-leitura, e `--add-dir` não reabre: reproduzido com
  `--add-dir <repo>/.git` e com `--add-dir <repo>/.git/worktrees/<nome>` (o
  gitdir exato), os dois com `fatal: Unable to create '.../index.lock':
  Permission denied`; a ACL do gitdir mostra `DENY (W,D,Rc,DC)` para os SIDs
  do sandbox. O Codex escreve os arquivos; **o commit é da ponte** (passo 3 do
  preâmbulo nos agentes com `escreve: true`). O script deixou de passar
  `--add-dir`. D10 lê-se com esta emenda: "commit via `--add-dir`" virou
  "commit pela ponte".
- **Shell do Codex no Windows é PowerShell 5.1** (`powershell.exe -Command`):
  `&&` é erro de parser. Briefing que vai para o Codex separa comandos com `;`
  ou uma chamada por linha.
- **A portaria viva de uma sessão em worktree é a do checkout principal**
  (`$CLAUDE_PROJECT_DIR`). A linha `"runtime"` no `despachos.jsonl` só aparece
  ao vivo depois do merge; a prova antes disso é rodar o hook da branch contra
  o payload real, que foi o que a T8 fez.
