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
| 4 | Windows é caminho de primeira ou segunda classe? | **com evidência de issue ou de código-fonte**, nunca impressão de README — e ausência de issue não é evidência de suporte |
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
| `fockus/claude-skill-find-skill` | 2026-08-12 | não acopla | **1** (a âncora foi corrigida pelo usuário: ele **já tem** a skill `find-skills` instalada, e ela é a do `vercel-labs/skills` — o CLI oficial `npx skills`, do projeto que mantém o `skills.sh`. O candidato tira **3999 das suas 4835 entradas (83%) raspando o sitemap do skills.sh**: mesma fonte, por caminho pior e congelado em cache local), **3** e **6**. A tese que estava escrita na fila caiu nos dois termos: **não é CLI** — `src/find_skill_cli/cli.py` só tem `version`/`update`/`uninstall`/install, nenhum subcomando de busca; quem busca é o modelo rodando script inline dentro do SKILL.md. E o custo medido é **274 B de injeção fixa contra 264 B do já instalado, e 11.247 B de corpo contra 5.446** — mais que o dobro para entregar o que já está entregue. Pergunta 6: a vida inteira do projeto cabe em 21/04/2026 (os dois releases no PyPI e o último push), 1 contribuidor com 7 commits, zero releases no GitHub, 1 issue na história. **Sem arquivo de licença** — 404 nos seis nomes e `gh api .../license` devolve Not Found; "MIT" existe só como palavra no `pyproject.toml` e no README, mesma situação do `anthropics/skills`. Pergunta 4 tem prova de código sem nenhuma issue: `cli.py:38` crava `os.execv("/bin/bash", ...)` sem detecção de plataforma. **Foi este caso que fez a pergunta 4 passar a aceitar prova de código-fonte** — ver a seção logo abaixo da tabela das seis perguntas; a mudança foi feita depois desta rodada fechar, e este veredito não foi revisado por ela (reprova em 1, 3 e 6 de qualquer modo) | 2026-04-21 |
| `mvanhorn/last30days-skill` | 2026-08-12 | não acopla | **2** (`hooks/hooks.json` registra **SessionStart** rodando 12,5 KB de bash a cada abertura — terceira vez que o mesmo slot reprova um candidato, depois de `Understand-Anything` e `context-mode` em 11/08) e **1**, por um motivo que só apareceu no código. O que justificava a âncora (fonte de revisita) era o recorte de 30 dias ser **filtro real no provedor**, e é: `freshness=` no Brave, `startPublishedDate` no Exa, `tbs=cdr:1,cd_min` no Serper, mais um segundo filtro em Python que descarta item sem data. **Só que isso não vale no host dele:** `grounding.py:226-275` só escolhe backend pago **se houver chave**, e o piso keyless **só dispara em host sem busca nativa** — a docstring de `web_search_keyless.py` diz "It must never run on a host that has native search". Claude Code tem WebSearch nativo. E o piso keyless, quando roda, **recebe o intervalo de datas e ignora** (DuckDuckGo/Startpage/SearXNG não passam data; `_to_item` fixa `"date": None`). Sem chave paga de Brave/Exa/Serper ele não é fonte de revisita, é o mesmo WebSearch com ~61,6k tokens de instrução em volta. Tamanho, para registro: **SKILL.md de 222 KB (~61,6k tokens), 3,7× o rainforest-mind inteiro**, monolítico — a issue #759 (jul/2026, aberta) pede o split porque 192 KB estourava o limite do Hermes, e desde então o arquivo **cresceu 30 KB**. Pela letra da pergunta 3 ele não reprova (injeção fixa é só a description de 261 chars), mas o custo por disparo inviabiliza o uso ocasional que era a âncora. Pergunta 6 passa com folga — é o repo **mais vivo do livro**: 171 commits em 30 dias, 100+ contribuidores, 37 releases, 57,9k ★. MIT canônica, arquivo lido, sem cláusula adicional. **LACUNA deixada de propósito** (o veredito já era não acopla): issue #565 "Security is flagging as high risk" e o fragmento `changelog.d/+sessionstart-env-rce.security.md` **não foram lidos** — num repo que registra hook de SessionStart executando bash, é por aí que qualquer revisita começa | 2026-08-09 |
| `vercel-labs/agent-browser` | 2026-08-12 | não acopla **ainda** — passa em 5 das 6, mesma forma do `headroomlabs-ai/headroom` | **4**, e a evidência acerta em cheio a âncora corrigida pelo usuário ("acessar site quando o fetch não dá conta, **sem abrir navegador como o playwright**"). O headless está certo no código — default `true` em três camadas (`flags.rs:482` nasce `false` para `--headed`; `actions.rs:4060` cai em headless quando o campo falta; `chrome.rs:344` default do struct) e `--headless=new` é a flag real entregue ao Chrome. **Mas no Windows a janela aparece assim mesmo:** issue **#1498 aberta** — "headless Chrome can leave a visible black rectangle on the desktop" (Win 11, sai até em screenshot do sistema) — e **#1644 aberta**, em que o daemon roda com `DETACHED_PROCESS` e todo filho console-subsystem ganha janela de terminal visível. São **54 issues com "windows" no título**, e as que matam são do ambiente exato dele: **#171 "Not working in Claude Code windows git bash"**, **#1270** (`open <url>` trava indefinidamente no Git Bash), **#1308** (trava pré-handshake no Win 11, 16+ min), **#43** ("does not work in Windows native shells"), além de **#382/#1281** (binário em quarentena pelo Defender como `Trojan:Win32/Posilod.EB!cl`). O que **passa**, e é o que o mantém na fila: pergunta 2 passa — `.claude-plugin/marketplace.json` declara **só `skills`, sem `mcpServers`**, então não colide com o MCP do playwright a menos que o usuário opte; e o driver é **CDP próprio em Rust** (`cli/Cargo.toml` tem 27 deps e **nenhuma de automação de navegador**; protocolo vendorizado em `cli/cdp-protocol/`), reusando o Chromium do Playwright só como 3º fallback. Pergunta 3 passa como CLI (**zero injeção fixa**; como MCP seria ~15,4k tokens no perfil `core` e ~78k no `all`, mas é opt-in). Pergunta 5 passa. Pergunta 6 passa com folga: 102 releases em ~7 meses, push de ontem, 112 contribuidores, 40,5k ★. Apache-2.0 **canônica** — o LICENSE foi diferenciado contra o texto da Apache Foundation, divergência só de formatação do Prettier, nenhuma cláusula acrescentada. Ressalvas de ambiente, não de veredito: o `npm install` baixa **13 MB** de binário no postinstall, o `agent-browser install` baixa **~192 MB** de Chrome for Testing em `~/.agent-browser/browsers`, e o daemon segura o Chrome vivo por **1h de ociosidade por padrão**. Detalhe que o nome esconde: **`read <url>` NÃO executa JavaScript** (é fetch HTTP puro, não sobe Chrome) — o caminho com DOM renderizado é `open` + `read` sem URL, e é esse que sobe navegador. **Gatilho de revisita mais barato que o calendário: quando #43, #171, #1270 e #1498 fecharem** | 2026-08-11 |
| `fischerf/aar` | 2026-08-11 | não acopla | 6 (**~2 meses sem push** — último em 18/06, v0.4.0 em 10/06; 22 ★, **1 único contribuidor** com 286 commits: mesma reprovação de `Mansuro/claude-projects`) e 2 (não é plugin do Claude Code, é um **substituto** dele — agente de codificação próprio em Python). Apache-2.0, zero issues abertas. Peça conceitual: sessão em **JSONL resumível** e suporte a **ACP** (Agent Client Protocol, badge 0.10.5) para Zed/VSCode — o ACP já tinha aparecido no livro pelo `last30days-skill` | 2026-06-18 |
| `ctrf-io/github-test-reporter` | 2026-08-21 | não acopla | 1 (não resolve nenhuma das 5 propostas do batedor: briefing de conserto com medição, stdin/timeout, limpeza segura, validação em estágio, padrão honesto) | 2026-08-21 |
| `WithSecureOpenSource/flaky-tests-detection` | 2026-08-21 | não acopla | 6 (**parado desde 2022-12-15**, 3+ anos sem push) | 2022-12-15 |
| `runetsk/ttgo` | 2026-08-21 | não acopla | 1 (plataforma genérica de testes, não ataca nenhuma proposta aberta) | 2026-07-30 |

## Por que a pergunta 4 aceita código, e não só issue (2026-08-12)

A redação anterior era "reprova **com evidência de issue**, nunca impressão". Ela nasceu
para barrar impressão de README — e barra. Mas **não admitia prova de código-fonte**, que
é mais dura que issue: issue é relato de terceiro, código é o comportamento.

O caso que forçou a mudança foi o `fockus/claude-skill-find-skill`: **zero issue de
Windows** — o repo tem 1 issue em toda a história, e não é sobre isso — e ainda assim
`src/find_skill_cli/cli.py:38` crava `os.execv("/bin/bash", ...)` com caminho absoluto e
sem detecção de plataforma, o que torna o pacote inutilizável fora de WSL/Git-Bash. Pelo
critério anterior isso não reprovava, e o repo passaria na pergunta 4 por silêncio.

O erro de leitura que a redação antiga induzia: **repo novo, pequeno ou sem usuário de
Windows não tem issue de Windows porque ninguém tentou**, não porque funciona. Ausência
de issue não é evidência de suporte — é ausência de teste.

O que **não** mudou, e é o que a regra sempre quis dizer: impressão de README continua
não valendo. "O README não menciona Windows" não reprova ninguém; `os.execv("/bin/bash")`
reprova. A régua ficou mais dura de satisfazer por acidente, não mais frouxa.

Alterado **depois** da rodada de 2026-08-12 fechar, de propósito — mudar critério de
veredito com a peça em cima da régua é reescrever a medida para caber no que se mediu.
Os vereditos daquela rodada foram dados sob o critério antigo e não foram revisados: o
`find-skill` reprovou em 1, 3 e 6 de qualquer modo.

## Fila da primeira rodada do batedor — encerrada em 2026-08-12

Os três foram levantados pelo usuario em 2026-08-08 e deixados sem avaliar de propósito,
como material de teste da própria maquinaria. **Foram avaliados em 2026-08-12 e estão na
tabela acima** — nenhum acopla; o `vercel-labs/agent-browser` fica como "não acopla
**ainda**", barrado só na pergunta 4.

O que a rodada ensinou, e vale mais que os três vereditos: **dois dos três morreram na
âncora, não no repo.** A tese escrita aqui sobre o `find-skill` ("é CLI, custa zero token")
estava errada nos dois termos, e a do `agent-browser` ("colide de frente com o MCP do
playwright") também — ele não registra MCP nenhum. As duas foram escritas a partir de
README, sem código. Fila é lugar de guardar **candidato e âncora**, nunca de guardar
veredito antecipado: o veredito adiantado vira a hipótese que a avaliação tenta confirmar.

Ver a ideia plantada `fila-do-livro-de-repos-e-prosa-que-ninguem-le` — esta seção é prosa
que o apurador não lê, e a correção proposta (um `vigias/fila-de-repos.jsonl` com **âncora
declarada** por candidato) continua aberta.
