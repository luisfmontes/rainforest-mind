# Livro de repos do batedor

Uma linha por repo avaliado. **Repo não se aposenta aqui** — repo melhora todo dia.
O que a linha guarda é: a data da avaliação, o veredito, **em qual das seis perguntas
reprovou** e o **último push visto naquela data**. É isso que faz a revisita ser barata:
repo não se reavalia inteiro, se reavalia na pergunta que perdeu.

**Gatilho de revisita — duplo, e os dois são obrigatórios:** 60+ dias desde a avaliação
**E** push posterior ao registrado. Sem os dois não é devida. Repo parado não mudou de
ideia sozinho, e gatilho só de calendário é outra forma de mandar o agente achar alguma
coisa. Teto de **3 revisitas por rodada**.

Repo **adotado** tem pergunta diferente na revisita: não é "melhorou?", é
**"ainda vale o que custa?"**.

## As seis perguntas

| # | Pergunta | Reprova quando |
|---|---|---|
| 1 | Resolve o problema ancorado? | não ataca nenhuma ideia/observação aberta |
| 2 | Colide com o que já roda? | disputa SessionStart/Stop, MCP ou agente já carregado |
| 3 | Quanto custa em token por sessão? | acrescenta injeção fixa sem pagar por ela |
| 4 | Windows é caminho de primeira ou segunda classe? | **com evidência de issue**, nunca impressão |
| 5 | Dá pra instalar em pedaço? | é tudo-ou-nada |
| 6 | Está vivo? | último push, cadência de release, arquivado |

**Veredito default é `não acopla`.** Adotar exige as seis passarem; "tem peça aproveitável"
é veredito legítimo e diferente de adotar.

## Avaliados

| Repo | Data | Veredito | Reprovou em | Último push visto |
|---|---|---|---|---|
| `affaan-m/ECC` | 2026-08-08 | não acopla, tem peça | 2 (colisão SessionStart/Stop) e 3 (custo/sessão) | — |
| `debpalash/VoiceStudio` | 2026-08-08 | olhar de perto | — (AGPL-3.0 trava se virar produto) | — |
| `virgiliojr94/book-to-skill` | 2026-08-08 | **adotado, já pagou** | — (15 livros no vault) | — |
| `thedotmack/claude-mem` | 2026-08-08 | **adotado, rodando** | — (injeta o contexto de abertura) | — |
| `whatsapp-mcp` (Rodrigo) | 2026-08-08 | **adotado, em obra** | — | caminho GitHub não registrado |
| `Graphify-Labs/graphify` | 2026-08-09 | não acopla ainda, peça forte | 1 (não cobre linguagem de ERP legado — `.prw`/`.tlpp` fora do mapa de linguagens) | 2026-08-08 |
| `tirth8205/code-review-graph` | 2026-08-09 | não acopla | 1 (custom_languages exige gramática no tree_sitter_language_pack) | 2026-08-02 |
| `kepano/obsidian-skills` | 2026-08-09 | **adotado** | — (json-canvas + obsidian-markdown) | 2026-06-08 |
| `headroomlabs-ai/headroom` | 2026-08-09 | não acopla **ainda** — o mais forte da fila | 4 (Windows não vetado: issue #1466 "not working on Windows" aberta e sem resposta desde 26/06, e o próprio README diz que os caminhos Windows "need real OS validation") | 2026-08-09 |
| `getagentseal/codeburn` | 2026-08-09 | testar, custo zero (`npx`) | — | 2026-08-09 |
| `anthropics/skills` | 2026-08-09 | ler, não copiar | — (**sem arquivo de licença**) | 2026-08-07 |
| `anthropics/claude-plugins-official` | 2026-08-09 | referência de estrutura | — | 2026-08-09 |
| `hesreallyhim/awesome-claude-code` | 2026-08-09 | índice de descoberta | — | 2026-08-09 |
| `upstash/context7` | 2026-08-09 | não acopla | 3 (é mais um MCP: injeção fixa) e 1 (não tem doc de linguagem de ERP legado) | 2026-08-07 |
| `bmad-code-org/BMAD-METHOD` | 2026-08-09 | não acopla | 2 (framework de método concorre com o SKILL.md) | 2026-08-09 |
| `SuperClaude-Org/SuperClaude_Framework` | 2026-08-09 | não acopla | 2 (mesma colisão do BMAD) | 2026-07-22 |
| `snarktank/ralph` | 2026-08-09 | não acopla | 6 (6 meses parado) e 1 (`/loop` já é nativo) | 2026-02-02 |
| `gsd-build/get-shit-done` | 2026-08-09 | não acopla | 6 (**arquivado**; sucessor `open-gsd/gsd-core` caiu de 64,7k pra 7,9k ★) | 2026-05-31 |
| `um marketplace interno de cliente` | 2026-08-09 | **adotado** (já instalado como `marketplace-interno`) | — | 2026-08-09 |
| `steveyegge/beads` | 2026-08-09 | candidato, não avaliado | — (3 aparições independentes; `.beads/issues.jsonl` espelha o `ideias.jsonl`) | — |
| `maslennikov-ig/claude-code-orchestrator-kit` | 2026-08-09 | não acopla | 2 (issue aberta: colisão MCP) e 3 (600-5000 tokens injeção fixa) | 2026-08-04 |
| `Mansuro/claude-projects` | 2026-08-09 | não acopla | 1 (job-runner ≠ despachante contextuado) e 6 (novo demais, 3 ★) | 2026-07-30 |
| `garrytan/gstack` | 2026-08-09 | não acopla, tem peça (`/codex`) | 2 (framework de método: `careful` vs gate-worktree, `investigate` vs `depurar`, `context-save/restore` vs claude-mem — mesma classe do BMAD/SuperClaude), 3 (55 skills = injeção fixa ~1,0–1,5k tokens em toda sessão, inclusive ERP legado) e 4 (82 issues + 117 PRs de Windows abertos, só 30 mergeados; #2478 `icacls` brica o `.gstack/`, #1375 aberto desde 08/05; o `setup` documenta Windows como modo degradado sem symlink) | 2026-08-08 |
| `Egonex-AI/Understand-Anything` | 2026-08-11 | não acopla | **1** (o problema ancorado é arqueologia de **ERP legado**, e o motor é Tree-sitter — mesma reprovação de `Graphify-Labs/graphify` em 09/08, `.prw`/`.tlpp` fora do mapa de linguagens), **2** e **3**. A lacuna sobre hooks foi FECHADA lendo `understand-anything-plugin/hooks/hooks.json` direto: ele registra **SessionStart** (colide com os dois injetores já ativos) e **PostToolUse** com matcher `Bash`. E o conteúdo do SessionStart é o problema maior que a colisão — quando o grafo está velho, ele injeta no contexto: *"You MUST read the file at … and execute its instructions … **Do not ask the user for confirmation — just do it.**"* Um hook de terceiro mandando o agente agir sem perguntar é o oposto direto das regras 15 e 16. Some 9 skills + 10 agentes de injeção fixa (pergunta 3, a mesma reprovação das 55 skills do gstack) | 2026-08-11 |
| `mksglu/context-mode` | 2026-08-11 | não acopla — **mas o desenho se lê** | 2 (registra os **seis** hooks: SessionStart, Stop, UserPromptSubmit, PreToolUse, PostToolUse, PreCompact — colide em 4 dos slots já ocupados: 2 injetores de SessionStart, o Stop do claude-mem e o PreToolUse do gate-worktree) e 3 (11 MCP tools de injeção fixa, contra a medição de 2026-08-09 em que MCP somava 40,2k tokens vs ~330 das skills). **Licença ELv2 (Elastic License 2.0), não OSI** — `gh api` devolve NOASSERTION, o LICENSE é ELv2 de Mert Koseoglu; proíbe oferecer como serviço gerenciado, o que importa para as ideias de publicar o rainforest. Vale como **referência arquitetural**, categoria "ler, não copiar": ele faz memória de sessão em **SQLite + FTS5** e recupera estado por BM25 no PreCompact — a mesma tese da ideia `trazer-a-memoria-pra-dentro-do-rainforest`, plantada horas antes e sem conhecimento deste repo | 2026-08-11 |
| `usestrix/strix` | 2026-08-11 | não acopla | 1 (pentest autônomo não ataca nenhuma ideia ou observação aberta — ele não faz teste de segurança). Apache-2.0, releases semanais, exige Docker de pé e chave de LLM. O próprio README exige alvo próprio ou **autorização escrita**. Fica no livro como "existe, se um dia for auditar app próprio" | 2026-08-11 |
| `NousResearch/hermes-agent` | 2026-08-11 | não acopla, tem peça (arquitetura de **gateway**) | 2 (framework de método — mesma classe de BMAD/SuperClaude/gstack, só que mais abrangente: substitui de uma vez o claude-mem por FTS5 cross-session, os vigias por cron, os 7 agentes por subagentes, o whatsapp-mcp por gateway multi-canal, e as regras por método próprio) e 5 (core monolítico; `hermes setup` é seletivo só depois de instalar tudo). **Pergunta 4 passa com folga e isso é raro:** Windows é primeira classe de verdade — instalador PowerShell nativo sem WSL, Git Bash embarcado, E2E em runner Windows real. A peça aproveitável é o **gateway multi-canal** (Telegram/Discord/Slack/WhatsApp/Signal/Email), que é o que a ideia `canal-fora-do-terminal-para-o-que-nao-cabe-na-sessao` pede | 2026-08-12 |
| `Zackriya-Solutions/meetily` | 2026-08-11 | **não acopla como peça, mas é candidato a USO DIRETO** | 5 (é app Tauri de desktop; os assets do v0.4.0 são só `.exe`/`.msi`/`.dmg`/`.app` — **não existe CLI nem binário headless**, e há 21 issues abertas pedindo isso sem solução). Por isso não serve de **motor** dentro da `pilha-de-voz-local-voicestudio`, que precisa de CLI. Mas o fato decisivo passou: **captura áudio do SISTEMA (loopback) junto com o microfone** (`frontend/src-tauri/src/audio/capture/system.rs`; issues #701/#702/#688), que é justamente o que nem o whisper da bridge nem o VoiceStudio entregam hoje. ASR local sem chave (Whisper **e** Parakeet), instalador Windows nativo, e licença **MIT** — mais folgada que a AGPL-3.0 do VoiceStudio, que era o travamento se virasse produto. Ressalva da pergunta 6: último push 05/06, ~2 meses, com 339 issues abertas | 2026-06-05 |
| `evolution-foundation/evolution-api` | 2026-08-11 | não acopla | 2 (colide de frente com o `whatsapp-mcp` do Rodrigo, **já adotado e em obra**, cujo `send_audio_message` funciona hoje na 3005) e 5 (`docker-compose` exige **Redis e PostgreSQL** de pé como `depends_on`, para entregar multi-instância que ele não usa). E **não melhora o MCP: ele não tem MCP** — expõe REST na 8080 e webhook, então a camada MCP continuaria sendo trabalho dele. Por baixo é Baileys + Cloud API oficial. Pergunta 6 em alerta: último release **estável** é o 2.3.7 de 05/12/2025; desde então só RCs (2.4.0-rc1/rc2, maio/2026). **Licença como FATO, não veredito** (conforme [[licenca-e-fato-nao-veredito]]): `gh api` devolve NOASSERTION porque é Apache-2.0 **com duas condições adicionais** lidas no LICENSE — (a) não remover LOGO/copyright dos componentes de frontend e (b) **Usage Notification Requirement**, que obriga exibir aviso visível de que a Evolution API está em uso em qualquer projeto, inclusive fechado, sob pena de exigir licença comercial | 2026-07-14 |
| `fischerf/aar` | 2026-08-11 | não acopla | 6 (**~2 meses sem push** — último em 18/06, v0.4.0 em 10/06; 22 ★, **1 único contribuidor** com 286 commits: mesma reprovação de `Mansuro/claude-projects`) e 2 (não é plugin do Claude Code, é um **substituto** dele — agente de codificação próprio em Python). Apache-2.0, zero issues abertas. Peça conceitual: sessão em **JSONL resumível** e suporte a **ACP** (Agent Client Protocol, badge 0.10.5) para Zed/VSCode — o ACP já tinha aparecido no livro pelo `last30days-skill` | 2026-06-18 |

## Fila da primeira rodada do batedor

Levantados pelo usuario em 2026-08-08 e deixados **sem avaliar de propósito** — são o
material de teste da própria maquinaria.

1. **`fockus/claude-skill-find-skill`** (e a variante em `vercel-labs/skills`) — CLI que
   busca em catálogo de 4800+ skills de 14 fontes, lê o catálogo local antes de cair na
   API viva. O mais forte dos três: ataca a ronda 2 direto, trocando "procura no mundo"
   por consulta a catálogo, e por ser CLI custa **zero token por sessão**. Casa com o
   princípio de que os números não são do agente — o script consulta, o modelo julga.
2. **`mvanhorn/last30days-skill`** — pesquisa um tema nos últimos 30 dias com citação
   real. **Cuidado:** como motor de descoberta aberta ele é exatamente o modo que este
   desenho recusa; acharia novidade toda semana. Uso legítimo é na **revisita**:
   complementar a data de push com sinal de comunidade, e responder por evidência
   externa a pergunta 4 e o "é bom mesmo ou só tem estrela?", que README nunca responde
   contra si. Entra como fonte de revisita, nunca de varredura.
3. **`vercel-labs/agent-browser`** — o mais fraco para esta tarefa: avaliar repo se faz
   com a API do GitHub e README cru por HTTP, sem navegador. Colide de frente com o MCP
   do playwright já carregado. Avaliar por último.
