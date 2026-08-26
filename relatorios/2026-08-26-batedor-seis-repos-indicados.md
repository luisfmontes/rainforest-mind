# Seis repos indicados pelo usuário — 2026-08-26

Chegaram por indicação, não por âncora. Entram no livro para **não serem
reavaliados** depois, pela mesma regra que trouxe o `666ghj/MiroFish` (24/08) e o
`ChristopherKahler/base` (25/08).

**O teto de 3 repos por ronda não se aplica.** Ele é do batedor autônomo, cuja
âncora sai do `dados-batedor-repos.js`. Aqui os seis vieram do usuário, e cada um
foi ancorado contra uma ideia aberta **antes** de qualquer agente abrir código —
seguindo a seção "Trilha: a âncora escolhe antes da busca" deste livro, escrita
depois da rodada de 12/08 em que dois dos três candidatos morreram na âncora e
não no repo.

Um avaliador por repo, seis em paralelo. Nenhum escreveu neste repositório:
todos leram clone raso em scratchpad e devolveram relatório. As afirmações que
mudam decisão foram reconferidas na janela principal, contra os mesmos arquivos.

## Âncoras declaradas antes da busca

| Repo | Problema ancorado | Trilha |
|---|---|---|
| `chaseai-yt/claudex-loop` | `segunda-opiniao-cross-model-no-revisor` + `council-hibrido-multi-modelo` | instalar |
| `AVIDS2/memorix` | `trazer-a-memoria-pra-dentro-do-rainforest` | instalar |
| `NuclearPhoenixx/fake-sandbox` | nenhuma ideia aberta cobre — hardening de máquina | instalar |
| `mukul975/Anthropic-Cybersecurity-Skills` | corpo de conhecimento do agente `auditor-de-seguranca` | enxertar |
| `bytedance/deer-flow` | `canal-fora-do-terminal-para-o-que-nao-cabe-na-sessao` | enxertar |
| `justrach/codegraff` | `n-implementacoes-da-mesma-tarefa-julgadas-por-criterio` + `autoavaliacao-do-metodo-contra-o-rastro` | enxertar |

## O que a rodada ensinou, e vale mais que os seis vereditos

**Cinco dos seis reprovaram em Instalar, e nenhum deles pela razão de sempre.**
Até 25/08 a reprovação padrão era colisão de slot de hook — quatro candidatos
seguidos morreram no SessionStart. Nesta rodada:

- o `claudex-loop` **não registra hook nenhum** (17 arquivos, todos markdown, zero
  código executável) e ainda assim reprova em 2, por framework de método e por um
  buraco de trava que o livro não conhecia (abaixo);
- o `cybersec-skills` também **não registra hook, MCP, agente nem comando** — e
  reprova por aritmética pura de injeção fixa;
- `deer-flow` e `codegraff` reprovam por serem **outro produto**, não por disputar
  slot.

**A pergunta 3 virou o freio real.** A folga agregada medida ao longo da rodada
oscilou entre **253 e 701 B** de 15.000 (o `Hook (additionalContext)` varia com o
tamanho do FOCO injetado). Contra isso: `claudex-loop` pede 4.054 B só de
description, `cybersec-skills` pede **355.602 B** (818 skills, ~89k tokens — 24×
o orçamento inteiro), `memorix` pede ~24 KB de `tools/list` com `alwaysLoad: true`.
Nenhum precisa colidir com nada para não caber.

**Um buraco de trava, e é nosso, não deles.** O `codex-build/SKILL.md:63` do
`claudex-loop` roda `codex exec --yolo`, e `:87` roda
`--dangerously-bypass-approvals-and-sandbox`. As duas listas do
`hooks/gate-worktree.cjs` são `FERRAMENTAS_DE_ESCRITA`
(`Write/Edit/MultiEdit/NotebookEdit`) e `VERBOS_QUE_MEXEM` (subcomandos de git).
**`codex` não está em nenhuma das duas.** A trava da regra 11 não é disputada —
ela fica **cega** para qualquer processo externo que escreva no repo. Isso vale
para `codex`, `gemini`, `aider` ou qualquer CLI de agente invocada por Bash.
É achado sobre este repositório, descoberto avaliando outro.

**Uma premissa do briefing estava errada e o avaliador a corrigiu com evidência.**
O briefing do `memorix` dizia "o usuário roda hoje o `thedotmack/claude-mem`".
Não roda: foi desinstalado em **25/08**, o backup está em
`~/.claude-personal/plugins/installed_plugins.json.bak-antes-desinstalar-claude-mem-20260825`
e as duas contas têm zero referências. Conferido. Consequência: SessionStart e
Stop já não são disputados por ele, e o buraco de "contexto de abertura" está
aberto agora — o que o `memorix` **não fecha**, porque
`src/hooks/handler.ts:409-411` registra que *"Claude Code ignores SessionStart
systemMessage as model context"*.

## Vereditos

### `chaseai-yt/claudex-loop` — `Instalar -> Enxertar: enxerta`

Reprovou em **2** (framework de método sobre o fluxo de sete estágios, quinta
reincidência da classe BMAD/SuperClaude/gstack; `PLAN.md` na raiz contra
`docs/rainforest/planos/`; e o buraco do `--yolo` acima) e em **3** (4.054 B de
description contra 253-701 B de folga — três skills de terceiro custam mais que
as dezesseis daqui).

Passa em 1 pela `segunda-opiniao-cross-model-no-revisor`, não pela
`council-hibrido-multi-modelo` (são dois modelos e um revisor, sem peer review
anonimizado e sem chairman). Ressalva para a colheita: o corpo do repo revisa o
**plano**; a ideia ancorada pede o **diff**, que é a fase 3, menor e opcional.

Fatos de contexto: `codex` não está instalado nesta máquina (`which codex` vazio,
`~/.codex` ausente) e o repo só o invoca por CLI com conta ChatGPT. Zero releases,
20 commits na história, bus factor 1, `author.url` aponta para canal de YouTube.
O "whoever built it never grades it" **não é mecanismo** — não há máquina de
estado nem trava, porque não há código. MIT canônica (o `NOASSERTION` do `gh api`
vem de um parágrafo de atribuição, não de cláusula).

**Cinco peças, e o alvo é o `revisar`, não um fluxo novo:**

1. Três fatos operacionais do `codex exec` headless: `resume` recusa `-s` (vai por
   `-c sandbox_mode="read-only"`, senão herda o `config.toml` e pode escrever no
   meio do loop); `< /dev/null` obrigatório ou trava para sempre a 0% CPU sob
   driver não-interativo; teto de 10 min porque o default de 2 min mata a revisão.
2. Contrato de veredito de uma linha — `VERDICT: APPROVED|REVISE` como última
   linha exata, com grep nela. Vira parecer em prosa num sinal que o `estado.cjs`
   registra. ~10 linhas.
3. Thread persistente com árbitro nomeado: rounds 2..N por `resume` no mesmo
   thread para o crítico não relitigar; inspeção pós-build em thread **novo**,
   para o revisor ver o código frio. *"Claude is final arbiter — Codex advises,
   doesn't command"*, com rejeição logada com motivo.
4. `MAX_ROUNDS` com deadlock honesto: *"Do NOT pretend it converged"* — estourou
   sem aprovação, lista cada ponto não resolvido e entrega ao humano.
5. Banner obrigatório de fim de run em background: *"The user is not watching tool
   calls; never let a completed build slide silently into the verify phase."*

### `AVIDS2/memorix` — `Instalar -> Enxertar: enxerta`

Reprovou em **2** (colide em 3 dos 5 slots ocupados — SessionStart,
UserPromptSubmit, Stop; **não** toca o PreToolUse, o que é raro e o distingue de
`context-mode`, `OpenViking` e `base`) e em **3** (MCP com `alwaysLoad: true`, modo
`lite` = 20 tools, ~24 KB estimados; e `memorix hook` roda em **PostToolUse**, a
cada chamada de ferramenta, respawnando node a cada invocação).

Passa em **4 com a melhor evidência desde o `hermes-agent`**: CI em matriz com
`windows-latest`, 47 `windowsHide: true`, 48 ocorrências de `win32`, e a issue #163
(Windows 11 + PowerShell 7) aberta e fechada em 1h33 — o conserto é o
`windowsHide` de hoje. Passa em **5 com folga**, que é o que a âncora pedia: sem
daemon, sem embedding obrigatório (`MEMORIX_EMBEDDING=off` é o default), sem chave
paga, sem Chroma/Postgres/Redis, dados em `~/.memorix/data`, e caminho de leitura
por CLI puro. Nada da classe do chroma-mcp órfão. Apache-2.0 com três edições
lexicais no corpo, sem cláusula acrescentada. Bus factor 1 (732 de ~764 commits).

**Duas peças:**

- **Deadline duro de hook com force-exit** (`src/hooks/lifecycle.ts:127-174`): dois
  orçamentos independentes — relógio de parede (20 s) e ociosidade de stdin (3 s) —
  e, ao estourar, escreve `{"continue":true}` no stdout e chama `process.exit(0)`,
  porque *"withTimeout cannot abort in-flight fetches; process.exit is the
  backstop"*. Os hooks daqui têm `timeout` no `hooks.json`, mas isso mata o
  processo **pai**; falta o backstop de dentro. ~60 linhas.
- **Tabela de capacidade do host por evento de hook** (`src/hooks/handler.ts:738-757`):
  o Claude Code só honra `additionalContext` em PreToolUse, UserPromptSubmit e
  PostToolUse — SessionStart, Stop e PreCompact devolvem `systemMessage` que o
  modelo não lê. Custo zero de código: é conhecimento, e conversa direto com o teto
  de entrega do SessionStart medido em 2026-08-10.

### `NuclearPhoenixx/fake-sandbox` — `fora da ancora`

Reprovou em **1**, sem cascata. Duas varreduras do `ideias.jsonl` (185 abertas) não
acharam nenhuma ideia sobre malware, antivírus ou endurecimento de máquina; os três
itens de segurança abertos são todos de **aplicação própria**. Mesmo desfecho do
`usestrix/strix` (11/08).

O veredito é o menos interessante. O que o registro guarda é **por que não instalar**:

- **O README mente sobre a desinstalação.** `README.md:69` diz *"No files will remain
  on your system"*; o `:uninstally` (`installer/fsp-installer.bat:51-54`) apaga só o
  `fsp.bat` da pasta Startup e `%appdata%\FakeSandboxProcesses\`. **Nenhuma pasta
  `%TEMP%\<GUID>` é removida** — e cada execução copia `ping.exe` 11 vezes com nome
  de ferramenta de análise (~484 KB por boot, acumulando, e em uso enquanto os
  processos vivem).
- **O interruptor de desligar não vem na instalação.** O `fsp.ps1` gerado em
  `fsp-installer.bat:70-84` é o original **sem a ramificação `stop`**; o próprio
  cabeçalho admite que não há como parar os processos senão baixando o `.ps1` de novo.
- **Baixa e executa `.bat` de `raw.githubusercontent.com/master/` a cada login**,
  sem hash nem assinatura (cinco ocorrências; `updater.bat:54` e `:67` trocam o
  próprio updater e o próprio instalador). Bus factor 1: conta que muda de mãos
  executa código novo em toda máquina instalada, no próximo boot.
- **A premissa quebrou em 2018.** `fsp.ps1:29` chama `1.1.1.1` de *"invalid ip"* —
  a Cloudflare assumiu o IP em abril/2018, e o `-w 3600000` é timeout de resposta,
  não intervalo. São 11 processos chamados `wireshark.exe`, `ollydbg.exe`,
  `ImmunityDebugger.exe` executando **cópias renomeadas de binário do sistema a
  partir de `%TEMP%`**, ocultos, com ICMP contínuo para IP externo fixo. Numa
  máquina com Protheus corporativo, é a assinatura que EDR e SIEM caçam.
- `fsp.ps1:43` mata **por nome**, sem filtro de caminho ou PID: derruba VirtualBox,
  VMware Tools, Wireshark ou Procmon **reais** se estiverem instalados.

Morto: zero mudança de lógica desde 18/12/2017; o release de 2023 diz no corpo que
duvida que alguém ainda use aquilo. GPL-3.0 canônica (26 linhas de diff, todas
cosméticas) — copyleft forte, incompatível com colar aqui.

### `mukul975/Anthropic-Cybersecurity-Skills` — `Enxertar -> Ler: vale voltar`

Reprovou na pergunta **4 de Enxertar** (*"o custo de reimplementar cabe, contra o
que entrega?"*), por três razões:

- **O mapeamento é etiqueta aplicada em lote, não conhecimento.**
  `exploiting-idor-vulnerabilities` e `exploiting-mass-assignment-in-rest-apis` —
  vulnerabilidades diferentes — carregam o **mesmo quarteto NIST**, e 41 skills
  carregam esse quarteto idêntico. `T1190` aparece em 234 das 818. Os PRs #13 e #18
  dizem como: mapeamento aplicado depois, por subdomínio.
- **A fonte primária é grátis e canônica** (attack.mitre.org, atlas.mitre.org), e o
  próprio `agents/auditor-de-seguranca.md` já manda citar a fonte por URL e nunca
  colar o texto dela aqui.
- **O formato está errado para o trabalho do auditor.** Ele lê código estático e
  emite `arquivo:linha`; isto é biblioteca de **operação** (SOC/pentest/DFIR contra
  infraestrutura viva). Skills sobre análise de código-fonte: **3 de 818**. Skills
  citando CWE: **5**, campo `cwe:` no frontmatter em **zero** — e CWE é a taxonomia
  do auditor. `application-security` tem 4 skills, contra 66 de `cloud-security`.
  E onde encosta na régua, está uma geração atrás: **49 ocorrências de `A0x:2021`
  contra zero de `A0x:2025`**, enquanto o auditor roda a 2025 desde 25/08.

**D3FEND é reivindicação vazia.** O `marketplace.json` e o README vendem
"6-framework mapping" incluindo D3FEND; **zero das 818 skills tem o campo
`d3fend:`** (conferido). Contra 806 com `mitre_attack` e 805 com `nist_csf`.

**Qualidade: bimodal, não uniforme — e não é o perfil do `MiroFish`.** Há
engenharia real no `tools/` (parser único de frontmatter com censo de bug
documentado; detector de colisão de roteamento por cosseno TF-IDF em stdlib; linter
de description com canário de truncamento) e ~42% da amostra com autoria genuína,
segundo a auditoria automática da issue #49 (score 79/100). O enchimento é o resto:
**133 skills repetem o mesmo bullet de `## When to Use`**, 90 repetem outro, e no
conjunto 43% têm a seção inteiramente genérica — o nome do arquivo injetado numa
frase molde. É conteúdo real com enchimento em volta, não template gerado com o
nome trocado.

**Procedência, como fato.** O dono é `mukul975` (Mahipal, Berlim), sem vínculo com
a Anthropic — e **o próprio README declara isso duas vezes**, nas linhas 35 e 463:
*"Not affiliated with Anthropic PBC."* O `LICENSE` é `Copyright 2026 mukul975` e a
palavra "Anthropic" não aparece nele. O que fica registrado: a marca está no **nome
do repositório, no slug da URL e no comando de instalação**, que é o que aparece na
busca e no marketplace; o desmentido está no corpo do README. Contraste com o
`anthropics/skills` (09/08), que é da organização de verdade e **não tem arquivo de
licença**.

**Não instala, por aritmética, e nem chegou a ser avaliado nessa trilha:** a soma de
`name + description` das 818 skills é **355.602 B ≈ 89k tokens** — 24× o orçamento
agregado inteiro (15.000 B), em toda sessão. Passaria na pergunta 2, aliás: não há
`hooks/hooks.json`, `.mcp.json`, `agents/` nem `commands/` (conferido).

Registrado de passagem, porque decide uma eventual revisita: a issue **#100**
(aberta desde 03/07, sem resposta) mostra o **Windows Defender pondo um SKILL.md em
quarentena** como `Trojan:script/Wacatac.H!ml`, e a **#114** tem o Huorong
classificando o projeto inteiro como cavalo de troia. Mesma classe do
`agent-browser`, só que aqui o arquivo quarentenado é **markdown**. E a **#103**
(05/07, aberta) executou todos os 809 `agent.py` e achou 5 defeitos reproduzíveis,
dois fatais no import.

**O que vale a volta, e é por isso que a cascata desceu para Ler em vez de parar:**

- **As 14 skills de `ai-security`** — o cluster limpo do repo, **zero delas com o
  boilerplate**. `detecting-indirect-prompt-injection` enumera vetores concretos
  (HTML comments, `display:none`, texto branco em PDF, alt-text e EXIF, texto
  rasterizado, Unicode tag/zero-width, Base64/ROT13). E
  `auditing-mcp-servers-for-tool-poisoning` é diretamente sobre o que se faz nesta
  máquina: descrição de ferramenta é superfície de ataque, e como ela entra no
  contexto do agente, envenená-la é injeção indireta entregue pela cadeia de
  suprimentos. O **batedor-repos é o consumidor natural disso**.
- **`tools/detect-collisions.py`, `tools/lint-descriptions.py`,
  `tools/skill_frontmatter.py`** — colisão de roteamento entre descriptions e
  truncamento de frontmatter são problemas de qualquer repo com muitas skills, e
  aqui estão resolvidos em stdlib com o porquê escrito no docstring.

### `bytedance/deer-flow` — `Instalar -> Enxertar: enxerta`

Reprovou em **2** (é outro produto: FastAPI + Next.js + nginx, `make docker-start`,
UI e TUI próprias) e **5** (o `channels/` só roda dentro do runtime dele).

A armadilha que o briefing mandou checar primeiro **não se confirmou** — e é o
inverso do que se supunha. Existem dois "gateways" e o que interessa é real:
`backend/app/gateway/` é o servidor HTTP; `backend/app/channels/` é o canal humano
bidirecional, com nove adaptadores registrados em `service.py`, e transporte sem IP
público (`telegram.py:1` long-polling, `slack.py:1` Socket Mode). **Não é barramento
interno entre subagentes.**

**Não existe WhatsApp** — `grep -ril whatsapp` no repo devolve zero, e Signal e
email também não estão. O canal que o usuário já tem não está lá.

O núcleo é pequeno e não arrasta nada: `message_bus.py` 359 + `base.py` 393 +
`store.py` 153 + `run_policy.py` 118 = **1.023 linhas**, contra 2.629 só do
`manager.py`, onde mora o acoplamento ao LangGraph. `grep -rn redis` em `channels/`
= **zero**: sem broker, sem fila, sem banco no caminho padrão. MIT canônica, só uma
segunda linha de copyright. Push de hoje, 182 commits em 4 semanas, cinco
mantenedores acima de 100 commits — o melhor bus factor da rodada.

**Quatro peças, todas de código lido** (o avaliador declarou explicitamente que não
usou o `channels/AGENTS.md` de 32 KB como evidência — foi a lacuna que sujou a linha
do `deepseek-harness` em 24/08):

1. **`ChannelRunPolicy`** (`run_policy.py:23-118`): política por canal num dataclass.
   `is_interactive=False` faz o middleware de clarificação responder *"proceed with
   best judgment"* em vez de travar esperando resposta, **porque não há humano
   sincronamente presente**. É o problema central da ideia ancorada, resolvido por
   política declarada em vez de `if` espalhado. Ressalva: hoje existe para canal por
   webhook (GitHub), não para IM.
2. **Chave de conversa com `topic_id`** (`store.py:74-78`): `canal:chat` ou
   `canal:chat:topico` — a diferença entre "cada mensagem é um assunto novo" e "esta
   conversa continua", em 153 linhas com escrita atômica.
3. **Handshake de vinculação por código**: `token_urlsafe(16)`, TTL 600 s, 429 no
   acúmulo, e a inversão obrigatória de ordem contra a allowlist — senão identidade
   que o bot nunca viu não consegue se registrar.
4. **Contrapressão por reserva em duas fases** (`message_bus.py:219-247`):
   `reserve_inbound` levanta `InboundQueueFullError` em vez de esperar, porque o SDK
   do provedor roda em thread estrangeira. É o que impede o canal de virar
   amplificador quando chegam 40 mensagens de uma vez.

**O que não se enxerta:** o caminho de retorno completo supõe runtime com API de
thread resumível (`runs.stream`/`runs.create`). Claude Code não tem sessão
endereçável de fora — esse pedaço se substitui, não se enxerta.

Contra o `hermes-agent`, mesma âncora desde 11/08: **os dois se somam.** O hermes
cobre WhatsApp e este não; este entrega o mecanismo em código legível com
`arquivo:linha` e o hermes ficou no nível de arquitetura. O desenho vem daqui, a
lista de canais vem de lá.

### `justrach/codegraff` — `Instalar -> Enxertar: enxerta`

Reprovou em **2** (é outro harness — `build.zig:43-44` produz o executável `graff`,
e não existe `.claude-plugin/` nem `.claude/` no repo).

**O DGM existe em código, roda, e quem julga é critério medido — nenhum LLM entra na
decisão.** `learn_tournament.zig:34-56` é uma ordem total determinística (falhas
críticas → regressões críticas → pass rate → passes → economia → custo → bytes do
genoma → id), com o comentário *"Parent-relative deltas and one-shot latency are
deliberately excluded: a stochastic parent or noisy wall clock must not choose a
winner"*. O portão de promoção é **cauda binomial pareada exata com correção de
Bonferroni pelo número de braços planejados** (`learn_comparison.zig:117-120`:
`correctness_p * planned_candidates <= alpha`). O único LLM-juiz do repo está no
exemplo Python e está rebaixado por construção — só reordena variantes que já
passaram a suíte inteira, e o desempate ali é economia de chamadas de ferramenta.

**O segundo problema ancorado é atacado de frente, e é o achado mais forte:** o juiz
roda **fora da árvore que o avaliado pode editar**, copiado para fora e pinado por
sha256 — *"the running judge is not the in-tree copy a variant could rewrite"*. Eval
set pinado por hash com `exit(3)` no mismatch; falha do juiz retorna 0,0 e imprime
*"fail closed"*; linhas de score assinadas com HMAC para que a seleção não coma linha
forjada. No motor Zig o avaliador é reverificado **depois do uso**, antes de gravar o
registro, e o holdout só é exposto ao vencedor único.

**Licença — é o fato mais pesado da rodada.** `gh api` devolve NOASSERTION porque é
**AGPL-3.0 modificada**: os dois autores reservam para si, e só para si, o direito de
explorar comercialmente sem ficar presos à AGPL. Para todos os outros,
`LICENSE:33-39`: *"EVERY OTHER PERSON OR ENTITY receives… strictly and only under the
AGPL-3.0… including its Section 13 obligation to offer the Corresponding Source to
all users who interact with a modified version remotely over a network."* O corpo a
partir da linha 65 é a AGPL canônica; a modificação inteira está no preâmbulo. Não é
OSI. **Nenhuma linha pode ser colada aqui**, e a Seção 13 morde direto as ideias de
publicar o rainforest. É a mais capturante do livro — pior que a PolyForm do `base`,
por motivo diferente: a PolyForm exclui a máquina de trabalho, esta captura o
derivado.

**Custo de reimplementar: ~180 linhas de JS, zero dependências.** O volume do repo
(`learn_store`, `learn_receipt`, `learn_submit`) serve para evoluir genoma persistente
através de gerações — a ideia ancorada não pede isso, pede escolher entre N
implementações uma vez. A parte cara é a que não se aproveita. E o isolamento por
braço custa **zero linha nova**: a regra 11 já isola subagente em `git worktree`; o que
falta importar é a higiene de env (allowlist + `HOME`/`TMP` redirecionados), ~20 linhas.

**Os três detalhes que ninguém inventa sozinho:**

1. **Repetição não é amostra** — repetições e clones do mesmo caso colapsam numa
   unidade estatística antes de contar vitórias; senão rodar 5× o mesmo caso finge n=5.
2. **N braços exigem Bonferroni** — fan-out de 16 variantes sem correção acha vencedor
   no ruído.
3. **Instrumentação faltando é desconhecido, não zero** — braço que não reportou
   chamadas de ferramenta **perde** para quem reportou, em vez de ganhar por "0
   chamadas".

Saúde: 947 commits em 4 semanas, 30 releases (três nos últimos três dias), mas **bus
factor 1**. As "71 issues abertas" enganam: 25 são PRs, e das 46 restantes a maioria é
roadmap do mantenedor — bug de usuário fecha em dias. Windows passa por prova de
código (96 branches `.windows`, e o CI roda o e2e do próprio `learn` em
`windows-latest`).

## Lacunas desta rodada, declaradas

- Nenhum dos seis repos foi **executado**. Regra 15: nada instalado, nenhum `pip`,
  `npm`, `docker`, `zig build` ou script rodado. Toda afirmação de comportamento é
  leitura de código.
- O `memorix` teve o custo de `tools/list` **estimado** (~24 KB), não medido — subir o
  servidor exigiria instalar. A prosa das definições foi medida; o andaime JSON foi
  estimado. Não muda o veredito: a folga é de centenas de bytes.
- No `cybersec-skills`, 810 das 818 skills não foram lidas. As afirmações
  quantitativas são `grep` sobre o corpo inteiro e valem; o julgamento de qualidade
  técnica vale para as 8 lidas e para os 100 arquivos da amostra da issue #49. Os
  1.457 arquivos de `references/` não foram abertos.
- No `deer-flow`, `manager.py` (2.629 linhas) foi lido em trechos, não inteiro; a
  persistência das vinculações não foi lida.
- No `codegraff`, `src/fitness_strata.zig` (segundo mecanismo de seleção, MAP-Elites
  por nicho) teve só o cabeçalho lido, e `learn_credentials.zig` não foi aberto —
  **não se sabe se `graff learn` exige credencial de provedor para rodar**.
- No `claudex-loop`, a issue #8 ("YAML parse error", aberta hoje) tem corpo só de
  imagem, sem texto. Num plugin cuja única superfície é front matter, é por aí que
  uma revisita começa.
