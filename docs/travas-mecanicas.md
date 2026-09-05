# Travas mecânicas

Os hooks `PreToolUse` e os scripts com exit code que sustentam o método — e o
incidente que originou cada um. O README traz o resumo; aqui está o porquê.


Regra escrita não alcança o modo de falha em que o agente **leu a regra e errou
mesmo assim**. Um subagente rodou a verificação de isolamento, recebeu o
diretório principal — que era a condição de parada —, transcreveu a condição
corretamente e escreveu um OK do lado. No dia seguinte foi a vez da janela
principal: `git add -A` varreu trabalho de outra sessão duas vezes na mesma
noite, sabendo que não devia. O que sobrou das duas noites:

> Enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela
> deveria travar, ela não trava nada. **Exit code não se argumenta.**

| Hook (`PreToolUse`, exit 2) | Barra | Em quem |
|---|---|---|
| `gate-worktree.cjs` | escrita de subagente em repo git que não é worktree linkado; e `git checkout/switch/reset/…` neste checkout quando **outra** sessão do Claude Code está no MESMO diretório | subagente **e** a janela principal — esta no ramo de sessão co-locada (Issues #25 e #38) |
| `gate-staging-total.cjs` | `git add` com caminho total (`-A`, `--all`, `-u`, `--update`, `.`, `./`, `:/`, `*`), inclusive em flag combinada, e `git commit -a/-am/--all` | **também a janela principal**, que foi onde os dois incidentes ocorreram |
| `gate-publicacao-destino.cjs` | escrita de dados sensíveis (JID, telefone, email, credencial) em arquivo rastreado por git | **qualquer ferramenta que escreve** (`Write`, `Edit`, `MultiEdit`) — impede vazamento em repo público |
| `gate-repo-alheio.cjs` | escrita cujo destino está dentro de **outro repositório git** que não o da sessão | **também a janela principal**, que foi onde o incidente ocorreu — caminho fora de git e worktree do mesmo repo passam |
| `portaria.cjs` | despacho de subagente que não está declarado em `.rainforest/agentes.json`, ou cujo estágio ativo não consta na lista dele; agente com `escreve: true` despachado **sem `isolation: "worktree"`** ou **com `name`**; manifesto ausente ou inválido nega tudo (fail-closed) | **o despacho**, na janela que despacha — o humano não é perguntado em runtime, e exceção é diff no manifesto, que passa pelo `revisar`. Registrado só no `.claude/settings.json` **do projeto**, não na máquina |

Valem em **qualquer** repo git da máquina, porque o hábito é que é o problema,
não o repositório. A mensagem de bloqueio não só recusa: a de staging roda
`git status --porcelain -uall` e devolve o `git add` por caminho já montado —
trava que só diz "não" vira trava desligada. Saídas de emergência, nomeadas na
mensagem que a **janela principal** recebe — a do subagente as omite de
propósito, porque em 2026-08-11 uma delas foi usada para contornar a trava em
vez de resolver o problema: `node scripts/setup.cjs --desligar <gate> --escopo
projeto` (preferida), `RAINFOREST_GATE_OFF=1` no ambiente, ou um arquivo
`.rainforest-gate-off` na raiz do repo.

Cada uma tem bateria própria (`hooks/testa-gate-*.sh`, **427 casos**: 194 de
worktree + 104 de fechar Issue + 96 de staging + 27 de repo alheio + 16 de
publicação) que roda o hook
de verdade contra repos git montados na hora. A maioria dos casos testa o que
deve **passar**: falso positivo aqui atrapalha todo repo — a trava de repo alheio
é o exemplo, com 20 dos 27 casos provando que ela **não** barra.

E a trava de repo alheio traz uma lição que custou uma rodada de conserto: a
primeira versão dela copiou do `gate-worktree.cjs` a guarda `if (!ev.agent_id)
process.exit(0)`, que lá vale para o ramo de isolamento — e aquele ramo é sobre
isolamento de subagente, que é problema de subagente. (Lá a guarda hoje tem
corpo: antes de sair, chama o gate de sessão co-locada, que barra a janela
principal.) Aqui o incidente é de **janela
principal**: uma sessão cujo `cwd` era outro repositório foi consertar este
plugin dali mesmo, e deixou trabalho não commitado num worktree que se perdeu.
Molde se copia; recorte, não.

O mesmo princípio nos scripts, para o que hook nenhum alcança:

| Script / Lib | Para quê |
|---|---|
| `hooks/lib/cli-externo.cjs` | transporte de CLI externo — `rodarCli({ cmd, entrada, timeoutMs, env })` com stdin, timeout obrigatório e `windowsVerbatimArguments` no Windows; `extrairJson(stdout)` extrai JSON de ````json ... ```` ou `{...}`. Consumido por `scripts/segunda-opiniao.cjs` e `scripts/conselho.cjs` |
| `scripts/ideias.cjs` | única porta de escrita do `ideias.jsonl` — trava de arquivo, backup, escrita atômica, releitura do arquivo vivo e conferência byte a byte das linhas não-alvo; e o `projeto` é **slug de vocabulário fechado** (`projetos.json`), não texto livre |
| `scripts/ferramentas.cjs` | única porta de leitura e escrita do ledger `ferramentas.jsonl` — catálogo de ferramentas descobertas em uso. Ledger cresce por descoberta sem varredura de setup; ausência de entrada lê-se como **desconhecido**, não confirmado ausente. Receita de invocação é opcional — entra depois pelo comando explícito (D5, D11). A sonda do hook de consulta em `PreToolUse` anuncia descoberta ou bloqueio, deixa a execução passar sempre (D10) |
| `scripts/limpar-branches.cjs` | confere o local contra o remoto e classifica por dois eixos (upstream **e** merge); nunca remove branch viva, e exigir estar na base em dia é trava. A **remota** já sai sozinha no merge (`delete_branch_on_merge`, ligado em 2026-08-26); este script é para a **local** e para o resíduo de worktree de agente, que é o que sobrevive e ninguém vê |
| `scripts/conferir-publicacao.cjs` | **sai com código 2** quando o rascunho tem telefone, JID, e-mail, caminho de home ou credencial — antes de virar Issue público |
| `scripts/conferir-entrega.cjs` | roda na janela principal **depois** da entrega do agente: hash de base, isolamento e citação conferidos na fonte, não no relato. `--espera <caminho>` (repetível) confere o que a tarefa prometia **na árvore do commit** — `ls`/`cat` do agente provam o disco, e `git status` não lista ignorado |
| `scripts/conferir-fluxo.cjs` | fecha as três costuras entre artefatos vizinhos do fluxo, **com exit 2**: `design` (as seções obrigatórias e as decisões `D1..Dn` sem buraco nem repetição), `cobertura` (toda decisão virou tarefa **e** toda tarefa atende decisão que existe) e `creep` (arquivo no diff que não casa com o `arquivos:` de tarefa nenhuma). Chamado pelo `estado.cjs marcar` no fechamento de estágio — só age onde o design/plano existe, e nunca torna o fluxo obrigatório |
| `scripts/portoes.cjs` | troca **evidência colada por oráculo re-executável**: cada portão declara o `CHECK:` que o decide e o `ESPERA:` que a saída precisa conter, e cumprido é **exit 0 E match**, os dois, re-executáveis a qualquer momento. `status` e `lint` **nunca executam** `CHECK` nenhum — o `lint` audita a *autoria* do portão (`echo ok`/`ESPERA: ok` é erro), que é a única parte que nenhuma execução consegue conferir. `ABANDONA:` é terminal mas nunca é conclusão: força exit 1 com `DEVOLUCAO OBRIGATORIA` mesmo com o resto cumprido. A evidência gravada guarda **fingerprint**, nunca output bruto. Chamado pelo `estado.cjs` em dois pontos — `lint` no fechamento do `plano`, `rodar` no do `verificar` — e é **opt-in por fluxo**: só age quando existe `docs/rainforest/portoes/<slug>.md` |
| `scripts/conferir-versao.cjs` | conta os commits desde o último bump de versão e **sai com 2** acima do teto (5 por padrão, `--teto N`) — porque o que EXECUTA não é o clone, é o cache `plugins/cache/<mkt>/<plugin>/<versão>/`, indexado pela versão: sem bump, o trabalho fica na `main` e não chega em máquina nenhuma. Chamado pelo `fechar` |
| `scripts/setup.cjs` | monta a pasta de dados, liga/desliga o que é opcional **e configura o caminho de cada projeto** — e marca no estado o caminho que **não existe** nesta máquina, que era falha silenciosa |
| `scripts/ponte.cjs` | **gera** o `CLAUDE.md` (Claude Code sem o plugin), o `AGENTS.md` (Codex) e o `GEMINI.md` (Gemini CLI) a partir do mesmo SKILL.md que o hook injeta — e recusa gerar se não achar as regras, em vez de escrever meia ponte |
| `scripts/poda.cjs` | proxy **passthrough** local (`iniciar`/`parar`/`status`, só `127.0.0.1`) que mede o que passa — `metricas.jsonl` e `contexto.json` na raiz de dados, extraídos de uma CÓPIA do stream SSE, sem alterar nenhuma requisição nem resposta. A escrita respeita a chave `poda` do `config.json` (nasce ligada; desligar é o kill switch). **Não comprime nada** — compressão é fase 1, e só entra com o relatório da fase 0 em mãos |
| `scripts/relatorio-poda.cjs` | o gate de saída da fase 0: **sai com exit ≠ 0** enquanto `metricas.jsonl` não cobrir 7 dias-calendário distintos; aberto, imprime tokens por estágio, cache hit agregado e a média de `duracao_ms` do proxy — e diz explicitamente que não compara com "sem proxy", porque isso não é mensurável retroativamente |
| `scripts/segunda-opiniao.cjs` | segunda opinião de modelo de outra família sobre um diff: `node scripts/segunda-opiniao.cjs --base <sha> --head <sha> --criterio <arquivo>` monta prompt com `git diff <base>...<head>`, critério e commit-base, chama CLI externo por `rodarCli`, devolve veredito (1 linha) no stdout e parecer no stderr. Subcomando `registrar-divergencia` grava discordâncias ao log com motivo. D6: indisponibilidade reprova |
| `scripts/orcamento.cjs` | mede em **byte** as quatro fontes que o plugin põe na abertura (saída do hook, descriptions de skills, de commands e de agentes), compara com dois tetos (o `ORCAMENTO_BYTES` do hook, lido de `hooks/lib/contexto-sessao.cjs`, e um agregado de 15.000 B, que subiu de 14.000 em 2026-08-25), e sai com exit 1 quando estoura — entra no laço do `CONTRIBUTING.md:11` como o gate que acusa quando o plugin engordar além do orçamento |
| `scripts/medir-injecao.py` | custo real do prompt de abertura, lido do `usage` que a API devolve — token de verdade, sem estimativa. O modo `--repartir` reparte a abertura por fonte (skill_listing, deferred_tools_delta, agent_listing_delta, rainforest-mind) e marca o que é **medido** (total via API), o que é **estimado** (byte convertido por fator 3.11 do tokenizador OpenAI), e o que é **subconjunto** (rainforest-mind dentro das listagens) |

O que essas travas custaram e renderam fica em [`relatorios/`](../relatorios/) —
hoje o da trava de sessão co-locada
(`2026-08-21-branch-nova-e-o-que-derruba-a-outra-sessao.md`), com método e
números. Os incidentes de 2026-08-08 e 2026-08-11 estão citados no cabeçalho dos
próprios hooks, não em relatório à parte.

