# Design: a captura passa a ser nossa, e por projeto

Continuação de `2026-08-17-memoria-e-dados-do-rainforest.md`, que entregou a
fase 1 (leitura) e o encanamento da fase 2 (marca d'água, gatilho de
`SessionEnd`, recuperação na abertura). Publicado em 0.68.0 no dia 2026-08-19.

O que este desenho resolve: a fase 2 foi declarada pronta com a coluna `projeto`
inerte de ponta a ponta e a chamada de LLM comentada. Os critérios do plano
anterior passavam mesmo assim — todos mediam a existência da peça, nenhum media
o que ela carrega.

## Objetivo

Fazer a memória do rainforest gravar e devolver observação **do projeto certo**,
e substituir a captura do claude-mem pela nossa — encerrando a dependência que
motivou o trabalho da fase 1.

## O quadro medido em 2026-08-19 (noite)

Três defeitos independentes, e qualquer um sozinho impede memória por projeto:

- `scripts/memoria.cjs:56` deriva o projeto do **nome da pasta da raiz de
  dados**. Com a raiz global (`C:\Users\Luis\.rainforest`), o valor medido é
  `projeto: "Luis"` — toda observação de toda sessão da máquina nasce com o
  mesmo rótulo.
- `scripts/importar-claude-mem.cjs:82` grava esse mesmo valor em todas as linhas
  importadas. A coluna `project` **existe na origem** e o `SELECT` da linha 53
  nem a lê. São **10.071 observações em 26 projetos distintos** (3.120
  `rainforest-mind`, 2.033 `claude-plugins`, 1.434 `inovacao`, 815
  `repositorio`, 749 `tbc-licensing`, 742
  `inovacao/gestao-projetos-template`).
- `hooks/memoria-session-start.cjs:30` injeta as 5 mais recentes **de todos os
  projetos**, sem `WHERE projeto`.

Nada foi corrompido: `observacoes` e `marca_dagua` estavam em 0 quando isto foi
escrito, porque a captura nunca gravou.

## Decisões fechadas

- **D1 — O projeto de uma observação é o basename do toplevel do git da sessão,
  com fallback para o basename do cwd** — porquê: a raiz de dados é global e
  compartilhada por todos os projetos, então qualquer coisa derivada dela é
  constante e não distingue nada. O que distingue uma sessão da outra é onde ela
  roda. O fallback existe para sessão fora de repositório git, que é caso
  normal, não erro.

- **D2 — A normalização é o último segmento do caminho, aplicada dos dois
  lados** — porquê: o claude-mem rotula worktree com o pai junto
  (`inovacao/gestao-projetos-template`), e o toplevel do git de uma worktree
  linkada é a própria pasta dela, cujo basename é `gestao-projetos-template`.
  Reduzir os dois lados ao último segmento faz as 742 observações daquele
  worktree casarem com as sessões novas **sem tabela de-para para manter**. O
  preço é conhecido e aceito: dois projetos com o mesmo basename em pais
  diferentes colidem. Nenhum dos 26 nomes medidos colide hoje.

- **D3 — A injeção filtra por projeto e completa o teto com as globais mais
  recentes** — porquê: memória de outro projeto na abertura é exatamente o ruído
  que o bloco existe para não ser. Mas projeto novo começa com zero observações,
  e bloco vazio é pior que bloco genérico: as vagas que sobram do teto (5, hoje)
  se preenchem com as mais recentes de qualquer projeto, marcadas como tal.

- **D4 — A importação preserva o projeto da origem, linha a linha** — porquê: o
  dado certo está lá e é a única chance de tê-lo; refazer depois significa
  reimportar 10.071 linhas e resolver duplicata.

- **D5 — A ordem da virada é importar, provar a captura, e só então desligar o
  claude-mem** — porquê: desligar antes abre buraco no histórico enquanto o
  substituto ainda não gravou observação nenhuma. O sinal de "provado" é
  observação real no banco vinda de transcrito real, não bateria verde.

## Avaliado e descartado

- **Manter a derivação do projeto pela raiz de dados.** É o estado de hoje, e
  produz `"Luis"` para a máquina inteira: a coluna existe e não distingue nada.
- **Tabela de-para entre os nomes do claude-mem e os das sessões novas.** Mais
  fiel, e some com a razão de existir na primeira vez que alguém renomeia pasta
  sem atualizar a tabela. O último segmento (D2) acerta os 26 casos medidos sem
  nada para manter.
- **Ler o projeto do `projetos.json`.** Fiel ao vocabulário do usuário, mas
  obriga a cadastrar projeto antes de ter memória nele — e memória que só
  funciona depois de configurar é memória que não funciona no dia em que
  importa.
- **`claude -p --bare` para a passada de LLM.** Sobe em 1,3 s e pula os hooks
  (resolveria a recursão de graça), mas a autenticação passa a ser estritamente
  `ANTHROPIC_API_KEY`, que não existe nesta máquina. Continua na mesa, junto da
  decisão em aberto.

- **D6 — A passada de LLM sai por `claude -p --model claude-haiku-4-5-20251001
  --setting-sources ''`, com as ferramentas travadas e `cwd` neutro** — porquê: o
  custo de 125 s do `claude -p` não era do modelo nem do prompt, era do
  **carregamento das configurações de usuário** (plugins, marketplaces, hooks).
  Medido em 2026-08-20: 125,3 s na linha de base, 124,5 s com MCP inteiramente
  desligado — e **4,8 s** com `--setting-sources ''`, duas medições
  (4.806 ms e 4.804 ms), exit 0, mesma autenticação OAuth, sem chave nenhuma.
  Vinte e seis vezes mais rápido pelo caminho que já estava escolhido.

  Brinde que resolve o outro problema por construção: nessa forma **os hooks do
  plugin não rodam**, então não existe a recursão que ia exigir trava por
  variável de ambiente. Conferido pelo lado de fora — `sessoes.json` tinha 11
  sessões antes e 11 depois da chamada, ou seja, o `SessionStart` do rainforest
  não disparou.

  **E não é achado nosso: é o que o claude-mem já faz.** A leitura do código
  dele (clone em `plugins/marketplaces/thedotmack`) mostra o mesmo desenho, e as
  citações abaixo foram conferidas na fonte:
  `src/sdk/hardened-options.ts:124-139` monta as opções do SDK com
  `settingSources: []`, `mcpServers: {}`, `strictMcpConfig: true`,
  `additionalDirectories: []`, `tools: []`, `allowedTools: []`,
  `disallowedTools`, `permissionMode: 'dontAsk'`, `canUseTool` negando tudo,
  `thinkingConfig: {type:'disabled'}` e `cwd` preso a um diretório neutro —
  nunca o do projeto. O modelo default é `claude-haiku-4-5-20251001`
  (`src/shared/SettingsDefaultsManager.ts:118`), e a autenticação padrão é
  assinatura, não chave (`SettingsDefaultsManager.ts:125`,
  `CLAUDE_MEM_CLAUDE_AUTH_METHOD: 'subscription'`). O `~/.claude-mem/.env`, de
  onde ele leria uma chave, **não existe nesta máquina** — e o log de 2026-08-19
  tem 40 ocorrências de `authMethod=Claude Code OAuth token` contra **zero** de
  token injetado, com observações gravadas mesmo assim. Ele nunca precisou de
  chave porque spawna o **binário `claude` do próprio usuário** e deixa o CLI
  resolver a credencial.

  Copiamos o travamento de ferramenta junto, e por um motivo prático: o que a
  passada precisa é resumir texto, não navegar. Agente de resumo com Read e Bash
  na mão é superfície de ataque sobre o transcrito, que é conteúdo não
  confiável.

- **D7 — Nada de worker residente, nem de sessão reaproveitada entre chamadas** —
  porquê: o claude-mem sustenta um daemon Express em porta fixa e um subprocesso
  `claude` mantido vivo por um async generator, com timeout de ociosidade de 3
  minutos (`src/services/worker/SessionMessageBuffer.ts:5`, conferido). É isso
  que compra os 2 a 10 s por passada morna dele — e é exatamente a arquitetura
  que a fase 1 rejeitou, porque processo de pé é a causa medida da falha que
  originou este trabalho. Nossa passada roda uma vez por sessão, no `SessionEnd`:
  pagar 4,8 s de partida a cada sessão é mais barato que manter qualquer coisa
  viva, e o cold start medido no log dele para o caminho com worker é ~16 s,
  pior que o nosso sem worker.

## Em aberto

- (nada — a última fronteira fechou com a medição do `--setting-sources`)

## Histórico da decisão da LLM

- A escolha de 2026-08-19 foi
  `claude -p` com haiku, pela autenticação que já existe na máquina. As medições
  da mesma noite derrubaram a premissa de que isso sai barato:

  | caminho | tempo | autenticação |
  |---|---|---|
  | `claude -p --model haiku` (prompt trivial) | **125,3 s** | OAuth, já existe |
  | `claude -p --model haiku` (prompt de 4 kB) | **128,5 s** | OAuth, já existe |
  | `claude -p --bare` | **1,3 s** até falhar | exige `ANTHROPIC_API_KEY`, **ausente na máquina** |

  O custo é de **partida**, não de token: prompt trivial e prompt de 4 kB dão o
  mesmo tempo, e o `--bare` — que pula hooks, LSP, sync de plugin e descoberta
  de CLAUDE.md — sobe em 1,3 s. Ou seja, os ~125 s são o ambiente que o
  `--bare` não carrega, e é o mesmo peso de processo de que este trabalho está
  saindo.

  **Resolvido na D6**, e o que destravou foi a pergunta do Luís ("como o
  claude-mem faz? não podemos replicar?"): o `--setting-sources ''` corta esse
  ambiente sem trocar a autenticação, e a chave de API deixou de ser necessária.

  Dois limites do mesmo caminho, medidos junto: o trecho vai no **argumento**,
  porque `claude -p "instrução"` com stdin canalizado **trava** (morto em 120 s);
  e o argumento estoura `ENAMETOOLONG` entre 16.908 e 33.708 caracteres, então
  a passada precisa de teto por chamada de qualquer jeito.

## Fora de escopo

- Busca vetorial e semântica (segue valendo o desenho anterior: FTS5).
- Migração de ideias e foco para índice no banco.
