# Memória e dados do rainforest saem de dependência frágil

## Objetivo

Tirar o rainforest-mind da dependência de um processo de terceiro para ler
memória, e acabar com o enxame de runtimes que o caminho de escrita atual
provoca. O corpus passa a ter store próprio; o claude-mem vira importador
opcional em vez de infraestrutura crítica.

Motivação medida em 2026-08-17: a assinatura de falha do worker
(`did not become ready before timeout`) aparece **zero vez até 09/08 e todo dia
útil desde 10/08** — ~3.890 ocorrências em oito dias, 1.589 delas só em 17/08.
Cada evento de hook sobe **três processos** — o comando é um script bash que
varre diretórios, chama `node`, que sobe `bun` (~120 MB) —, e o volume vai de
1.007 a 3.783 hooks por dia. Medido no log: **15.331 `PostToolUse` mais 833
`Stop`** em oito dias, com `matcher: "*"`, ou seja ~46 mil processos. O sintoma
que chega ao usuário é o prompt engolido no meio da frase; o custo já cobrado
foi um upgrade de RAM da máquina.

Distribuição por ferramenta (oito dias): Bash 8.296, Read 2.181, Edit 1.429,
Grep 792, PowerShell 704, Write 594 — as seis somam 91% do total.

## Decisões fechadas

- **D1 — Foco e ideias continuam com o texto como verdade; o banco é índice derivado e reconstruível** — porquê: o que quebrou esta semana foi depender de coisa com estado frágil, e arquivo texto não tem lock, não tem WAL, não corrompe e se lê com `cat`. O preço aceito é que as travas de integridade seguem no `ideias.cjs` (1.262 linhas) em vez de virarem `NOT NULL`; o ganho do banco passa a ser consulta e join, não integridade.
- **D2 — O store é próprio do rainforest; o claude-mem vira importador opcional, nunca dependência de execução** — porquê: um plugin cujo recurso central depende do esquema privado de outro autor não é distribuível. Funcionaria só na interseção de quem tem os dois e quebraria para todos a cada upgrade dele. Mesmo padrão do `whatsapp-bridge/store/messages.db`: store próprio dentro do projeto.
- **D3 — A raiz de dados (`~/.rainforest`) vira repositório git** — porquê: hoje não é versionada — 385 KB de ideias, o `FOCO.md` e o `AVANCOS.md`, meses de decisão, protegidos só pelo backup-por-escrita do `ideias.cjs`. É a proteção mais barata para o ativo mais caro, e independe de todo o resto deste desenho.
- **D4 — A captura (transcrito → observação) passa a ser do rainforest** — porquê: tirar só a leitura resolve o prompt bloqueado, mas não os ~3.800 spawns por dia, que vêm do caminho de **escrita** do claude-mem. Decidir agora muda o desenho do armazenamento (ele precisa aceitar escrita nossa); decidir depois obriga a migrar. A execução é fase 2.
- **D5 — Para o corpus de memória, o banco é a verdade — não o texto** — porquê: são 9.363 observações crescendo 55% em seis dias, geradas por máquina e nunca editadas à mão. A linha que separa D1 de D5 não é o tipo do dado, é **quem escreve**: o que o usuário edita fica texto, o que a máquina gera mora no banco.
- **D6 — As observações existentes entram por importação única mais reimportação incremental até a fase 2, e o importador é script isolado rodado sob demanda** — porquê: são meses de histórico real e jogar fora é perda de verdade. Mas mantendo o importador fora do caminho de execução, um upgrade que mude o esquema do claude-mem quebra um comando que o usuário roda, não a abertura da sessão dele.
- **D7 — O texto é versionado; o banco fica fora do git, com backup próprio** — porquê: o banco é verdade (D5) e portanto não é descartável, mas é binário que muda a cada minuto, e git não dá diff legível nele — versionar incharia o repo sem entregar o único motivo de versionar.
- **D8 — Driver `node:sqlite`, isolado no adaptador** — porquê: zero dependência é decisivo num plugin para distribuir; `better-sqlite3` exige toolchain de compilação no Windows, que é a classe de coisa que faz a instalação falhar na máquina dos outros. O status experimental no Node 22 é risco de API mudar, e o adaptador já existe para absorver isso.
- **D9 — O banco segue a raiz de dados resolvida, com coluna `projeto` dentro** — porquê: a cadeia de 4 níveis (`RFM_ROOT` > `<projeto>/.rainforest` > `~/.rainforest` > plugin) já é a política; quem aponta raiz por projeto está pedindo isolamento de propósito, e quem usa a global tem tudo consultável de uma vez. Não se inventa regra nova para memória.
- **D10 — A memória injetada é item de contexto separado, com teto próprio** — porquê: o hook atual usa 7.308 B de um teto de 8.000, e a disputa por esses bytes já deixou marcos e prazos fora da injeção mais de uma vez. O bloco do claude-mem hoje são ~9.018 B que não disputam esse orçamento; absorvê-los mataria o `FOCO.md`.
- **D11 — A injeção de memória é híbrida: poucas observações residentes mais ponteiro para busca sob demanda, com o número medido e não arbitrado** — porquê: só ponteiro é a tese teoricamente certa, mas regride comportamento que hoje entrega ~9 KB de contexto útil na abertura; injetar 50 observações é o custo sem revisão que já estourou orçamento antes.

  **Medição (D11):** com a decisão de injetar **título + subtítulo de múltiplas observações** em vez de conteúdo completo de uma:
  
  | Observações | Bytes | % do teto (3000 B) |
  |---|---|---|
  | 5 | 797 | 26,6% |
  | 10 | 1.468 | 48,9% |
  | 14 | 2.008 | **66,9%** |
  | 20 | 2.818 | 93,9% |
  
  **Escolha:** 14 observações residentes (2.008 B). Motivo: oferece ~13x mais ganchos na abertura do que uma observação inteira, mantendo 34% de margem (992 B) para oscilação no tamanho real. O ponteiro dá acesso ao corpus completo quando os ganchos não bastam. Número escolhido pela medição, não arbitrado — e **conferido ponta a ponta contra o hook real**: 30 observações no banco com limite 14 emitem 14 linhas, 1.075 B, com o ponteiro presente.
- **D12 — O hook escreve direto no banco, e a passada de LLM nunca roda no caminho do prompt. A marca d'água só anda em evento que já dispara uma vez por turno — NUNCA em `PostToolUse`** — porquê: a premissa original desta decisão estava **errada**, e a medição a derrubou durante a execução da tarefa 10. Ela dizia "os hooks do rainforest já rodam como `.cjs` no node do harness, dá para gravar sem subir nada". Não existe hook em processo: **todo** hook do `hooks.json` é `type: "command"` e roda `node "${CLAUDE_PLUGIN_ROOT}/hooks/..."`, ou seja, um processo do SO por evento — exatamente como o do claude-mem. Registrar a marca d'água em `PostToolUse` reproduziria a patologia que este trabalho inteiro existe para escapar: 15.331 eventos em oito dias. O que salva o desenho é que o rainforest já paga um spawn por turno no `Stop` (`heartbeat.cjs`) e um no `SessionEnd` — a marca d'água pega carona nesses eventos, ao custo declarado de +1 processo por turno e +1 por sessão (~119 num dia de 119 prompts, contra ~1.900/dia do `PostToolUse` do claude-mem). O `node:sqlite` em processo continua valendo para o que importa: uma vez dentro do hook, a escrita custa microssegundos e não precisa de worker.
- **D13 — A matéria-prima é o transcrito que o harness já grava; o hook registra só a marca d'água (sessão, caminho, offset processado)** — porquê: o harness escreve o transcrito completo em `projects/<projeto>/<sessão>.jsonl` (1,3 MB numa sessão medida) e o `scripts/medir-injecao.py` já lê de lá. Gravar evento por evento seria duplicar o que já existe. A régua dá idempotência de graça: reprocessar é recuar o offset.
- **D14 — A passada de LLM dispara no `SessionEnd`, com recuperação pela marca d'água na abertura seguinte** — porquê: um spawn por sessão contra ~3.800 por dia é a diferença inteira, e no fim da sessão o transcrito está completo. A recuperação não é zelo: este repo já documenta que o `SessionEnd` não dispara quando a janela morre no X.
- **D15 — Os hooks do claude-mem não são desligados na fase 1, e não há alívio intermediário viável: convive-se com o spawn até a fase 2** — porquê: desligar antes abre um buraco no histórico exatamente enquanto o substituto está sendo construído. A primeira versão desta decisão mandava expandir `CLAUDE_MEM_SKIP_TOOLS`, e **a medição derrubou isso**: o `PostToolUse` do claude-mem tem `matcher: "*"`, o comando é um script bash que varre diretórios e chama `node`, que sobe `bun` — **três processos por evento de ferramenta** —, e o `SKIP_TOOLS` só é lido **dentro** do `worker-service.cjs`, depois dos três já terem subido (`bun-runner.js` não o menciona nenhuma vez). Por isso `Skill` e `AskUserQuestion`, já na lista, continuam aparecendo no log. A lista poupa trabalho do worker, não poupa spawn. O único lever que funciona é o `matcher` no `hooks.json` da cópia em cache, que todo `plugin update` sobrescreve — trocar isso por atraso de versão instalada é péssimo negócio, e este repo acabou de pagar por descobrir. O caminho durável é Issue no upstream pedindo filtro antes do spawn; o conserto real é a fase 2.
- **D16 — A fase 1 entrega esquema, adaptador de leitura, importador, bloco de injeção com teto e checagem de esquema no `/saude`; e é inteiramente reversível** — porquê: enquanto a fase 1 não escreve nada, desistir custa apagar um arquivo. Reversibilidade é o que permite entregar cedo sem apostar o histórico.

## Avaliado e descartado

- **Ler o `claude-mem.db` como fonte de execução.** Medido e funcionando: abertura `mode=ro` concorrente com o worker de pé, sem cópia e sem encostar no WAL, sobre 9.363 observações com FTS5 pronto. Descartado mesmo assim por D2 — acopla um recurso central ao esquema privado de outro autor num plugin destinado a publicar.
- **Copiar o corpus para banco nosso mantendo o claude-mem como fonte contínua.** Duplica ~49 MB e cria problema de sincronia, que é a mesma classe de problema de que este trabalho está saindo.
- **Fila em arquivo drenada por worker residente.** Reintroduz o processo de pé que é a causa medida da falha (~3.890 timeouts de prontidão em oito dias, worker saturando com 48 h de uptime).
- **Injetar memória dentro do orçamento de 8.000 B do hook atual.** Ele está a 692 B da borda; a disputa por esses bytes tem histórico de vítima documentado no `contexto-sessao.cjs`.
- **Só ponteiro na abertura, sem observação residente.** Teoricamente certo e rejeitado por regressão de comportamento sentida na primeira sessão.
- **Gravar evento por evento no banco como matéria-prima.** O harness já grava o transcrito completo; seria duplicar o que existe.

## Fora de escopo

- Toda a captura — marca d'água, gatilho de `SessionEnd` e passada de LLM. É a fase 2, decidida em D4 e deliberadamente não entregue aqui.
- Migração de ideias e foco para índice no banco. D1 decide que acontece; a fase 1 não faz.
- Desligar o claude-mem (D15).
- Busca vetorial e semântica. O chroma foi desligado em 2026-08-17 e não volta neste desenho; o FTS5 cobre a busca por texto.
- O detalhe do que entra no `.gitignore` da raiz de dados. D7 fixa o critério; o resto é do plano.

## Em aberto

- (nada — a fronteira esvaziou na rodada 4)
