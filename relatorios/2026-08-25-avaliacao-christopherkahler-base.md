# `ChristopherKahler/base` contra as seis perguntas — 2026-08-25

Não é rodada do batedor: o repo **chegou por indicação do usuário**, com a tese de que
"está nessas mudanças de harness que estamos fazendo". A tese foi tratada como hipótese
a testar, não como fato — pelo motivo escrito na seção "Fila da primeira rodada" do
`vigias/livro-de-repos.md`: veredito adiantado vira a hipótese que a avaliação tenta
confirmar. Entra no livro para **não ser reavaliado**, como o `666ghj/MiroFish`.

**Veredito: não acopla, tem peça forte.** Reprova em 2, 3 e 5. Passa em 1 (raspando),
4 (com folga, e por prova de código) e 6 (com bus factor 1).

## O que ele é, de código lido

Binário Rust (~26 mil linhas em `src/`, oxigraph/RocksDB) que mantém um grafo RDF de
projetos, tarefas, decisões, regras e um mapa AST, e se pluga no Claude Code por cinco
hooks que injetam pedaços desse grafo no contexto, com orçamento por abertura
(`[signal] max_chars`) e escala por **depleção real do transcript** (`[bracket] mode =
"percent"`).

Por cima, um **relay entre sessões**: registro global em `~/.base-gbl/.base/sessions.json`
amarrando apelido → `session_id` + `cwd` + `workspace` + heartbeat, caixa de tarefas por
título, e um contrato de acordar sessão ociosa armando a ferramenta `Monitor` com um loop
que carimba um sentinela `.watching` a cada 5 s.

Fecha com dashboard Svelte local na 3741, sistema próprio de extensões que executa
handlers de terceiro com segredos injetados por env, **auto-update silencioso do próprio
binário na abertura**, e 5.840 B enxertados na `~/.claude/CLAUDE.md` declarando
`base ast query` como ferramenta obrigatória antes de grep/find/Read.

## As seis perguntas

**1 — Resolve o problema ancorado? PASSA, raspando.** Ataca a P1 e a P3 do relatório de
2026-08-21 (`src/relay/session_registry.rs:24-59`: vivacidade lida de heartbeat contra
`DEAD_AFTER_SECS`, e `workspace_name()` separando "outra janela neste diretório" de
"outra janela noutro projeto") e a Issue #74 (`src/config.rs:213-253` +
`src/hook/user_prompt_submit.rs:38-45`). Não ataca nenhuma das 5 propostas do relatório
de bateria/medição, nem #88, #89, #82, #77, #76, #61.

**2 — Colide com o que já roda? REPROVA.** `src/install.rs:744-750` registra cinco
slots — SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop — e **quatro dos
cinco já estão ocupados aqui**. Fica atrás só do `volcengine/OpenViking` (5 de 5). O
`wire_hooks` faz merge, não sobrescrita; o problema é o conteúdo, de três naturezas:

1. **PreToolUse deny-capable** (`src/hook/pre_tool_use.rs:28-36` faz `exit(2)`), no mesmo
   slot do `gate-worktree`, que é a trava da regra 11 — dois hooks capazes de negar, sem
   ordem garantida.
2. **Intercepta grep/find** (`pre_tool_use.rs:39-43`) e planta na `~/.claude/CLAUDE.md`:
   *"ALWAYS use `base ast query` BEFORE grep, find, Read, or any MCP tool"*.
3. **Manda agir sem perguntar** — `src/relay/wake.rs:107-137`: *"Call the Monitor tool
   ONCE… **Do not ask permission**"*, documentado como *"a mandatory-first-action
   contract, not a suggestion"*. Mesma reprovação do `Egonex-AI/Understand-Anything`
   (11/08), e contra as regras 15 e 16.

Não colide em MCP nem em agente (não há `mcpServers` nem `agents/`; uma skill só).

**Ponto extra:** `install.rs:70-72` crava `home.join(".claude").join("CLAUDE.md")`. Nesta
máquina há **duas** config dirs; o `base install` escreveria só na de trabalho e a outra
divergiria em silêncio — o incidente exato de 2026-08-10.

**3 — Custo por sessão? REPROVA.** Piso de injeção fixa de **~9.060 B** (5.840 da seção
na CLAUDE.md + 2.000 de `[signal] max_chars` + 873 do bloco de flow + 347 da description
da skill), mais ~2.540 B do contrato de wake quando há título registrado. Contra a folga
medida aqui na mesma hora: `node scripts/orcamento.cjs` deu **13.648 de 14.000 B, folga
de 352 B**. É vinte vezes a folga — e a seção da CLAUDE.md nem entra na conta do
`orcamento.cjs`, porque custa em **todo** projeto.

**4 — Windows? PASSA com folga, por prova de código.** Segundo repo do livro a passar de
verdade aqui (o outro é `deepseek-harness`). Matriz `x86_64-pc-windows-msvc` no release,
`scripts/build-base-windows.ps1` nativo, e comentários que só existem porque alguém rodou
de verdade: `src/home.rs:20-25` (o `dirs` nunca consulta `$HOME` no Windows, então um fake
por `$HOME` **falha em silêncio** ao isolar) e `home.rs:112-121` (o `%TEMP%` do Windows
mora sob o perfil, então subir a árvore a partir de um tempdir atravessa
`C:\Users\<user>` — *"invisible until the suite ran on Windows"*). Mais códigos Win32
nomeados, `python` antes de `python3`, `windows_exe_fixup`, `WT_SESSION`.
Contraevidência honesta: `#!/bin/sh` cravado em `ast_repo.rs:53`, `Command::new("bash")`
em dois pontos do scaffold, e **nenhum job de CI roda `cargo test`** — nenhuma plataforma
tem suíte verde provada.

**5 — Instala em pedaço? REPROVA.** Há granularidade parcial real (`--skip-hooks`, e cada
seção do `base.toml` com `enabled = false`), mas o `base install` é um bloco: binário em
`~/.local/bin`, `~/.base-gbl`, hooks no `settings.json`, migração CARL, scripts AST,
**`pip install -r requirements.txt` no Python do usuário sem venv**, download de skill do
GitHub, e os 5.840 B na CLAUDE.md. E `[update] auto` nasce `true`
(`src/config.rs:349-351`): **toda abertura de sessão pode trocar o binário em disco**,
*"silent by contract: stdout and stderr are discarded"*. O pedaço que interessa — o
registro de sessões — não existe fora disso.

**6 — Está vivo? PASSA, com bus factor 1.** `pushed_at 2026-08-24T20:17:35Z`, não
arquivado, 66 ★, 3 issues abertas, 63 commits em 4 semanas, 30 releases desde 02/06.
Mas **233 dos 235 commits são de um autor** (mesma classe do `fischerf/aar` e do
`Mansuro/claude-projects`, que reprovaram aqui), e há um vazio de ~4 semanas entre 13/07
e 11/08. A issue #3 aberta se chama *"Six bugs from a single fresh install"*.

## Licença — fato, não veredito

`gh api .../license` devolve `NOASSERTION`. O `LICENSE.md` é **PolyForm Noncommercial
1.0.0**, diferenciado contra o texto canônico do `polyformproject/polyform-licenses`:
o diff é inteiramente rewrap de linha e reordenação de dois parágrafos — **nenhuma
cláusula acrescentada**. O `Required Notice: Copyright Chris Kahler, Chris AI Systems` é
previsto pela própria licença.

O que ela impede, na prática:

1. **Não é OSI.** *"Any noncommercial purpose is a permitted purpose"*, e *Your company*
   abrange "any legal entity … that you work for" — instalar na máquina de trabalho
   Protheus/TBC Agro **não é propósito permitido**.
2. *"These terms do not allow you to sublicense or transfer any of your licenses"* —
   nenhuma linha entra neste repo, que é MIT. Peça se **reimplementa a partir da ideia**,
   como se decidiu para o AGPL do OpenViking em 24/08.
3. Há camada comercial explícita: `base activate <key>` — *"enter your Skool classroom key
   to remove attribution"*.

## Peças (reimplementar, nunca copiar)

1. **Vivacidade lida do heartbeat, separada da poda por idade** —
   `session_registry.rs:53-59` + `relay/mod.rs:44-45`. O `hooks/heartbeat.cjs` daqui
   **admite no próprio comentário** (l. 32-38) o custo de podar só por idade de 24 h:
   janela fechada por crash "pode ser lida como janela do foco ociosa". São duas
   perguntas; aqui são uma. Ataca a P1 de 2026-08-21.
2. **Nome de workspace, não `cwd` cru, para distinguir janelas** —
   `session_registry.rs:297-302`. É o que a P3 pede; o `sessoes.json` daqui só guarda
   `cwd`.
3. **Orçamento com escala por depleção medida** — o `orcamento.cjs` daqui mede bytes em
   repouso contra teto fixo; o `base` lê o **% do contexto realmente consumido** do
   `transcript_path` que o evento de hook já carrega. É a metade que falta para a #74, e
   irmã da peça `orcamento-por-categoria-com-teto-de-aprofundamento` (OpenViking, 24/08).
4. **Prova de cumprimento por rastro datado** — `wake.rs:1-19`: o loop carimba um
   sentinela a cada poll, e o **frescor do sentinela é** o estado de vigilância. É a
   resposta estrutural para #61/#83: critério que só o próprio agente relata não vale;
   critério que deixa rastro datado, vale. **Só a ideia** — o texto injetado é justamente
   o que reprova na pergunta 2.
5. **Seam de home + tripwire de escrita isolada** — `src/home.rs` inteiro: `BASE_HOME`
   como única porta, `clippy.toml` proibindo `dirs::home_dir()`, teste que grepa por ela,
   e `assert_isolated_write()` que **entra em pânico** se escrita de teste cair sob o
   perfil real. Este repo tem hooks que gravam em `sessoes.json` e no banco durante
   bateria — mesma classe de risco.

## Lacunas — por onde uma revisita começa

1. `src/hook/memory.rs` (399 linhas) e `post_tool_use.rs` (621): o `handle_memory` pode
   devolver `blocked=true` e matar a chamada com `exit(2)`; **por qual critério, não foi
   lido**. É onde moraria a colisão com os dois gates de PreToolUse daqui.
2. `src/plugin/mod.rs` + `src/secret.rs`: o contrato de extensão injeta **todo
   `KEY=VALUE` de `~/.base-gbl/.env`** como env em processo de terceiro. Caminho de
   execução não lido.
3. `scripts/ast/extractor.py` (7.400+ linhas): **o mapa de linguagens não foi lido**. Se
   `.prw`/`.tlpp` estiverem fora (como em `graphify` e `Understand-Anything`), a camada
   que o próprio instalador chama de "MANDATORY FIRST TOOL" é inerte no trabalho Protheus.
   Um `grep -n 'prw\|tlpp\|advpl'` resolve.
4. `src/dashboard/server.rs`: servidor HTTP local na 3741, superfície de rede não
   inspecionada.
5. Issue #3, *"Six bugs from a single fresh install"*: título lido, corpo não.
6. **O README não foi lido, de propósito.** Toda afirmação acima sai de código, template
   de instalador, workflow de CI, LICENSE ou `gh api`.
