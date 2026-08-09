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
| `headroomlabs-ai/headroom` | 2026-08-09 | candidato forte, não medido | — (ataca os 40,2k tokens de MCP medidos) | 2026-08-09 |
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

## Fila da primeira rodada do batedor

Levantados pelo Luís em 2026-08-08 e deixados **sem avaliar de propósito** — são o
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
