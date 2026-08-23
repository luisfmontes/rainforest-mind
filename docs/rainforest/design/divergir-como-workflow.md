# Divergir como workflow — grafo em código, não em prosa

Design fechado em 2026-08-22. Estágio `brainstorm` do fluxo, slug
`divergir-como-workflow`.

## Objetivo

Converter a skill `divergir` num script de `Workflow` distribuído pelo plugin,
para que o isolamento entre os frames seja **garantido por código** em vez de
pedido por markdown.

O `divergir` já é um grafo: seis frames isolados em paralelo, depois um crítico
que nasce zerado. O que ele não é, é código. A própria skill diz o que sustenta
o valor dela — *"O isolamento **é** o mecanismo. Se os frames rodarem em
sequência na mesma janela, ou se um vir o resultado do outro, a skill não faz
nada que um prompt comum já não faça."* Esse mecanismo depende inteiramente de
eu ler o markdown e cumprir. Não há barreira de verdade, não há garantia de que
os seis não se veem, e não há retomada se a rodada quebrar depois de sete
despachos pagos.

O `executar` tem o mesmo defeito em forma mais crua: ele diz que *"despacho
paralelo é uma resposta com várias chamadas de `Agent`"* — paralelismo como
instrução para eu agrupar chamadas.

**Nenhuma skill do rainforest usa a ferramenta `Workflow` hoje.** Esta é a
primeira conversão, e o `divergir` foi escolhido por ser o mais barato de
errar: fan-out puro, não toca arquivo nenhum, e produz material para decidir em
vez de entrega.

### Fatos apurados antes de decidir

Levantados contra a instalação real (Claude Code 2.1.231), não contra a
documentação:

| fato | veredito |
|---|---|
| Plugin pode distribuir workflow nomeado | **Sim.** Pasta `workflows/` na raiz do repo, auto-descoberta como `skills/` e `agents/`. Os plugins oficiais `claude-security` e `code-modernization` já fazem, e o `plugin.json` deles não declara a pasta |
| Nome resolvido | `<plugin>:<meta.name>` — prefixado, igual a agente e skill |
| Formato em disco | Só `.js`. O loader recusa `.mjs`, `.cjs` e `.ts` sem tentar parsear. `export const meta` precisa ser a **primeira instrução** e literal pura — validado por AST |
| `agentType` de plugin dentro do script | **Válido.** `rainforest-mind:planejador` resolve por igualdade exata contra o registro. Em uso real no workflow oficial `code-modernization`, que chama `agentType: 'code-modernization:legacy-analyst'` |
| Teto de concorrência nesta máquina | **16** (i7-13650HX, 20 lógicos; fórmula real `min(16, max(2, cpus-2))`). Os 7 despachos rodam mesmo em paralelo |
| Script tem acesso a disco | **Não.** O workflow oficial da Anthropic documenta na própria saída: *"workflow scripts have no filesystem access"* — quem lê e escreve é a sessão que chamou |

O último fato é o que deu forma à decisão D7.

## Decisões fechadas

- **D1 — A `SKILL.md` fica, como porta de entrada; o script vira o mecanismo que ela invoca.**
  ~100 linhas da skill são julgamento, não mecânica: quando NÃO usar, o aviso
  dos N+1 despachos, o teste de falsificação. Isso não vira código, e precisa
  ser lido **antes** de gastar os sete despachos. Skill = quando e por quê;
  script = como.

- **D2 — Seis frames, fixos.**
  `restricao-dura`, `inversao`, `incentivo`, `ja-existe`, `modo-de-falha`,
  `premissa`. Foram escolhidos ortogonais e cada um tem justificativa escrita.
  Tornar variável é botão sem evidência de que faz falta.

- **D3 — Um crítico só, nascido zerado.**
  O mecanismo documentado é não herdar a narrativa de quem gerou — não é
  contagem de voto.

- **D4 — A rodada fica gravada.**
  A skill define o próprio teste de falsificação ("rode em 3 decisões reais e
  guarde a escolha") e hoje nada guarda. Sem registro, esse teste nunca rodou e
  nunca vai rodar.

- **D5 — Nome distinto: `divergir-frames`.**
  Invocável como `rainforest-mind:divergir-frames`. Skill e Workflow não
  colidem no runtime, mas nome idêntico vira ambiguidade na invocação e no
  painel. É o que a Anthropic faz: comando `/modernize-assess`, workflow
  `modernize-portfolio-assess`.

- **D6 — O crítico é `rainforest-mind:revisor`.**
  A skill exige do crítico o que o `revisar` cobra — refutação com cenário
  concreto de falha (entrada, estado, sequência) — e escreve literalmente
  *"igual a achado de `revisar`"*. O contrato pedia o revisor pelo nome sem ter
  percebido.

- **D7 — A gravação é de um script novo (`divergencias.cjs`), chamado pela janela principal, nunca pelo grafo.**
  O script não tem acesso a disco, então não é opção. E mesmo se fosse: a
  escrita precisa de trava entre sessões paralelas, gravação atômica, backup e
  conferência byte a byte das linhas não-alvo — o que o `ideias.cjs` faz desde
  os dois appends quebrados de 2026-08-08.

- **D8 — Cada frame devolve schema estruturado: lista de `{ideia, porque}`, mínimo de duas.**
  O crítico precisa receber as ideias sem saber de que frame veio cada uma. Com
  schema isso é mecânico — descarta o campo. Com texto livre, o anonimato
  dependeria de o crítico não deduzir a origem pelo estilo.

- **D9 — A rodada é gravada em dois momentos: `aberta` quando o grafo termina, `fechada` quando o usuário decide.**
  O campo que o teste de falsificação precisa é *"a escolha dele bateu com a
  primeira ideia da conversa?"*, e ele só existe depois da decisão. Mesmo
  padrão plantada→colhida do `ideias.cjs`.

- **D10 — O crítico devolve híbrido: schema para shortlist, escolha não-óbvia e o booleano de ancoragem; prosa para a refutação.**
  A refutação é argumento com cenário concreto; amputada em campo curto ela
  piora, e a skill exige que seja concreta.

Decidido sem subir ao usuário (consistência, vetável): o `divergencias.jsonl`
mora na **pasta de dados** (`~/.rainforest/`), ao lado do `ideias.jsonl` e do
`FOCO.md`, não no repo — é onde dado de sessão já vive, e é o que faz o arquivo
sobreviver a reinstalação do plugin.

### Contrato do script

`workflows/divergir-frames.js`, no repo do plugin.

**Entrada** (`args`): o enunciado do problema, em texto. Nada mais — o script
não lê disco, então tudo que ele precisa chega por `args`.

**Fase 1 — divergir.** `parallel()` com seis `agent()`, um por frame, todos com
o mesmo enunciado e contexto zero entre si. `agentType:
"rainforest-mind:planejador"`, `schema` exigindo `{ideias: [{ideia, porque}]}`
com mínimo de duas. A barreira aqui é correta e não é preguiça: o crítico
precisa das seis saídas juntas para agrupar.

**Fase 2 — focar.** Um `agent()` com `agentType: "rainforest-mind:revisor"`,
recebendo as ideias **embaralhadas e sem o campo de origem**. Devolve schema
com `shortlist`, `escolha_nao_obvia`, `bate_com_a_primeira_ideia`, e um campo
de texto livre com a refutação do sedutor-mas-quebrado.

**Saída:** o objeto do crítico mais as ideias cruas. Quem monta a decisão
numerada para o usuário é a janela principal, não o grafo — a skill não decide
(regra 16).

## Avaliado e descartado

| alternativa | por que perdeu |
|---|---|
| **O script substitui a `SKILL.md`** | O critério de "quando não usar" só funciona se for lido **antes** dos sete despachos. Virando comentário de código, ele deixa de ser lido na hora que importa |
| **Skill e workflow soltos, sem uma chamar a outra** | Duas portas para a mesma coisa — exatamente o defeito encontrado hoje no repo Protheus do usuário, onde `advpl-tlpp-compile` e a skill `compile` do plugin coexistem sem nenhuma marcada como preferida |
| **N de frames variável por argumento** | Cria a pergunta "quantos?" em toda invocação, e quem responde errado perde a ortogonalidade que faz a skill valer |
| **Subconjunto de frames por tipo de problema** | Quem escolhe o subconjunto já está ancorando — que é precisamente o que a skill existe para evitar |
| **Painel de 3 críticos com lentes distintas** | É o padrão que a ferramenta sugere, mas é mudança de desenho contrabandeada dentro de uma conversão: com ela, não dá para saber se o ganho veio do código ou do painel. Fica como candidato **depois** de a conversão provar a forma |
| **Crítico com o mesmo `planejador` dos frames** | Quem gera e quem critica com o mesmo perfil tende a validar — versão fraca do viés que a skill combate |
| **Um agente dentro do grafo grava a rodada** | Agentes de workflow têm Bash, então seria possível. Mas a escrita fugiria da trava entre sessões e do backup — o que os dois appends quebrados de 2026-08-08 fizeram virar código |
| **Gravar a rodada no design doc do fluxo** | O teste de falsificação compara três rodadas, e prosa espalhada em três documentos não é comparável |
| **Gravar num momento só** | No fim do grafo, o registro nunca sabe o que o usuário escolheu — some o campo que o teste precisa. Só na decisão dele, perde-se a rodada inteira (e os sete despachos) se ele decidir noutra sessão |
| **Schema no crítico inteiro, inclusive na refutação** | O cenário de falha viraria campo curto, e a skill exige que ele seja concreto (entrada, estado, sequência) |

## Fora de escopo

- **Motor de grafo próprio ou LangGraph.** O motor existe e é a ferramenta
  `Workflow`. O "nível 3" descrito no material de referência não se aplica a
  quem já tem o nível 2 disponível.
- **Converter o fluxo inteiro.** `brainstorm` é entrevista sequencial e
  `fechar` é um comando; forçar grafo neles é o overengineering que o próprio
  material de referência nomeia.
- **Converter `regua`, `executar` e `revisar` agora.** São as próximas, nesta
  ordem, e só depois que esta provar a forma.

  A ordem mudou depois de fechado o design, por observação do usuário de que
  `regua` e `divergir` se pareciam. Não são a mesma skill — `divergir` abre o
  espaço e devolve opções sem decidir; `regua` fecha o acabamento de um
  artefato sem teste e devolve um vencedor — e a própria `regua` já escreve a
  fronteira ("você quer opções e não um vencedor — isso é `divergir`"). Mas as
  duas são **a mesma primitiva**: fan-out para agentes isolados, mais um crítico
  proibido de herdar a narrativa de quem gerou.

  A `regua` passa na frente do `revisar` porque é um **loop com condição de
  saída**, que é onde prosa garante menos e código garante mais: os três freios
  dela — teto como abort e não como saída, commit por rodada, calibragem na
  rodada 1 — hoje são promessas em markdown, e viram `while`, passo obrigatório
  e `if` num script. A skill delega o loop ao `/loop` nativo, que não tem
  nenhum dos três; o motor que ela precisa é o `Workflow`.

  O `executar` fica antes do `revisar` por risco, não por ganho: ele edita
  arquivo, então cada nó vai exigir `isolation: "worktree"` e a conferência de
  hash de base da regra 11 — classe de risco que esta conversão não tem.
- **Mudar o desenho do `divergir`.** Seis frames continuam seis, um crítico
  continua um. Mudar desenho dentro de uma conversão impede saber a origem do
  ganho.
- **Reativar o `ultracode`.** Ele é o grafo automático em toda tarefa
  substantiva; este trabalho é o grafo nomeado, invocado de propósito. São
  coisas distintas e a decisão de mantê-lo desligado não depende desta.

## Em aberto

- **O `divergencias.cjs` ganha um subcomando `conferir`**, como o `ideias.cjs`?
  Provavelmente sim, mas só faz sentido depois de existir arquivo com linha
  suficiente para conferir. Decidir no `plano`.
- **Qual é o enunciado-isca do teste de isolamento.** O critério está definido
  abaixo, mas o problema concreto que provoca convergência ainda precisa ser
  escrito. Tarefa do `plano`.
- **Se o `verificar` desta entrega consegue ler o journal da execução** para
  provar o isolamento, ou se a prova tem que ser montada de outro jeito. Fato a
  apurar no `plano`, não decisão do usuário.

### O que falsificaria esta conversão

Duas provas distintas, e nenhuma é "a suíte passou".

1. **O isolamento é real?** Rodar o grafo com um enunciado desenhado para
   provocar convergência e conferir, no journal da execução, que os seis frames
   receberam prompts idênticos e nenhum recebeu a saída de outro. Se um frame
   citar a ideia de outro, o isolamento não existe e a conversão não entregou o
   mecanismo.
2. **O grafo em código entrega o que a prosa entregava?** Rodar as duas versões
   no mesmo problema e comparar a shortlist. Se a versão em código produzir
   material mais pobre, o ganho de garantia não paga a perda.

E o teste que a skill já definia continua de pé, agora possível: em três
rodadas gravadas, se `bate_com_a_primeira_ideia` for verdadeiro nas três, a
skill não paga o custo e sai. Este design não muda esse veredito — só torna
mensurável o que antes era opinião.

### Enunciado-isca

Dois scripts deste plugin fazem append num `.jsonl` compartilhado em
`~/.rainforest/`: `scripts/ideias.cjs`, hoje, e o `divergencias.cjs` que este
próprio design manda criar (D7). Ambos podem ser chamados por sessões
paralelas do Claude Code, escrevendo ao mesmo tempo. Depois dos dois appends
quebrados de 2026-08-08 — linha cortada no meio do arquivo —, alguém precisa
decidir como impedir isso de novo. A resposta que qualquer um aceita de
primeira: colocar um lock de arquivo em volta do `fs.appendFileSync` e pronto.

- `restricao-dura` — se só houvesse UMA escrita física por rodada permitida, a
  resposta vira "não escreva N vezes direto no disco compartilhado": acumule
  em memória e grave uma vez só, no fim.
- `inversao` — a garantia não é da aplicação, é do sistema de arquivos: escreva
  num arquivo temporário e troque com `rename` atômico (como
  `scripts/ideias.cjs:349` já faz), o lock vira proteção só da troca, não da
  escrita inteira.
- `incentivo` — um lock bloqueante incentiva quem está com pressa a matar a
  sessão para não esperar liberar, e o `.lock` órfão trava todo mundo depois —
  o próprio lock premia o atalho que deveria impedir.
- `ja-existe` — um arquivo-banco de verdade (SQLite em modo WAL, por exemplo)
  já resolve escrita concorrente segura; não precisa reinventar trava nem
  `.jsonl` — "não construa" é a resposta.
- `modo-de-falha` — comece do arquivo já corrompido no meio da rodada (o
  desastre de 2026-08-08) e desenhe para ele ser irrelevante: backup antes de
  escrever, como `scripts/ideias.cjs:341-349` faz antes do rename atômico, para
  que a sessão morrer no meio nunca destrua o arquivo original.
- `premissa` — por que N sessões escrevem direto no mesmo arquivo
  compartilhado? A resposta certa pode ser nenhuma escrever direto — só a
  janela principal grava, que é literalmente a D7 deste design.

A isca é "basta um lock de arquivo em volta do append": ela seduz porque
resolve o caso feliz de dois processos coordenados e é a resposta de manual
para concorrência, mas esconde que travar não impede escrita parcial se o
processo morre com o lock preso, não repara o que já corrompeu, e não
questiona se deveria haver N escritores no mesmo arquivo para começo de
conversa.
