# Design — acoplar o ponytail de verdade

**Data:** 2026-09-08
**Slug:** `aclopar-ponytail`

## Objetivo

Acoplar de verdade o que o rainforest pegou pela metade de
<https://github.com/dietrichgebert/ponytail>: hoje entrou **a prosa da escada**
e ficou de fora **todo o mecanismo**. Ao fim deste fluxo, a escada vale para os
nove agentes sem ninguém lembrar dela, as cláusulas que sustentam peso nas 17
regras não podem sumir em silêncio, os atalhos deliberados têm ledger, existe
uma faixa de revisão contra excesso, e o efeito disso é medido em vez de
afirmado.

## Diagnóstico

Do ponytail entrou **uma coisa**: a escada, comprimida em
`skills/modo-dev/SKILL.md:121-142`. E comprimida com perdas — 5 degraus em vez
de 7 (sumiu "cabe em uma linha?") e sumiu o formato de saída
`[código] → skipped: [X], add when [Y]`, que é o que torna a preguiça
auditável.

Nada mais entrou. E o `modo-dev` é carregado **sob demanda**, quando o modelo
lembra — que é exatamente o modo de falha que o ponytail existe para evitar:
`ACTIVE EVERY RESPONSE. No drift back to over-building.`

O padrão do erro é o mesmo nos sete pontos. O ponytail força seu comportamento
por hook em três eventos, valida a própria consistência em CI, e mede o próprio
efeito. O rainforest copiou dele o único pedaço que depende do modelo lembrar.

## Decisões fechadas

- **D1 — `SubagentStart` injeta a escada nos nove agentes.** Hook novo
  `hooks/escada-subagente.cjs`, registrado em `hooks/hooks.json` sob
  `SubagentStart`, injetando em **todos** os agentes.

  *Problema.* `grep -ril "escada\|yagni\|stdlib" agents` → zero acertos. O
  `executor` (haiku) escreve a maior parte do código deste repo e nunca viu a
  escada. As 17 regras chegam pelo `SessionStart`, que é *parent-thread only* e
  morre na porta do subagente. O `hooks/hooks.json` registra `SessionStart`,
  `PreToolUse`, `UserPromptSubmit`, `Stop`, `SessionEnd` — `SubagentStart` não
  existe aqui. O ponytail bateu no mesmo bug (issue #252 deles) e resolveu
  assim.

  *Detalhe que economiza uma rodada inteira,* vindo de `ponytail-runtime.js`:
  no Claude nativo, `SessionStart` aceita stdout cru, mas **`SubagentStart`
  exige a forma `hookSpecificOutput` ou o contexto é descartado** — a saída tem
  de ser `{hookSpecificOutput: {hookEventName: "SubagentStart",
  additionalContext: "..."}}`. Texto cru some em silêncio. É o mesmo modo de
  falha já documentado no `foco-session-start.cjs` (32 KB de texto cru viraram
  2,2 KB), numa porta diferente.

  *Por que todos os agentes.* O matcher por `agent_type` existe, mas seis dos
  nove escrevem e os três que não escrevem — `revisor`,
  `auditor-de-seguranca`, `planejador` — revisam ou desenham código, onde a
  escada vale igual. Separar dois grupos que querem a mesma coisa é ponto de
  variação sem segundo caso.

  *A fonte do texto é o `modo-dev/SKILL.md`, extraída — nunca duplicada.*
  Duplicar aqui criaria exatamente o defeito que D2 existe para pegar.

- **D2 — Invariantes de conteúdo das 17 regras.**
  `skills/rainforest-mind/invariantes.json` (declarativo) +
  `scripts/conferir-invariantes.cjs`, ao lado de `scripts/medir-skill.cjs` e
  usando o **mesmo motor real** (`filtrarRegras`, `extrairNucleo`) que ele já
  importa.

  *Problema.* Não é "a cópia divergiu da fonte" — é **"a fonte perdeu uma
  cláusula que sustentava peso e nada acusou"**. Três fatos: (a)
  `montarContexto` chama `extrairNucleo(filtrarRegras(skillText))`, e
  `extrairNucleo` corta cada regra na marca `↳` — **o que está depois da marca
  nunca é injetado**, então uma reescrita que empurre uma cláusula para depois
  da marca a apaga da sessão em silêncio; (b) já caiu em escala: em 2026-08-10,
  50 de 50 sessões receberam 2,2 KB de 32 KB e as regras 4 a 17 não chegaram a
  sessão nenhuma, sem ninguém perceber; (c) cada regra tem **dois** textos — o
  núcleo no SKILL.md e a elaboração em `references/regra-<n>.md` — e nada
  garante que continuem dizendo a mesma coisa.

  *Forma.* Cada invariante é `{regra, frase, onde}`. Três checagens, e a
  terceira não existe em lugar nenhum hoje: a frase está no `SKILL.md`; a frase
  está na `references/regra-<n>.md`; **a frase sobrevive ao `extrairNucleo`**,
  isto é, chega na sessão. Candidatos iniciais, todos load-bearing: `3.000`
  (regra 10 — sem o número a regra vira "despache quando parecer grande"),
  `exit ≠ 0 nunca é sucesso` (12), ``nunca a `main``` (11), `printenv NOME`
  (15), ``pelo `ideias.cjs plantar`, nunca à mão`` (13).

  *Por que canário e não byte-comparação.* O SKILL.md é mais longo que o núcleo
  por construção; não há igualdade a comparar. É a mesma razão que o ponytail
  dá no comentário do `check-rule-copies.js`.

  `blocoRegras` já degrada barulhento por **tamanho**
  (`TETOS.REGRAS_MIN_CHARS`). Isto acrescenta a degradação por **conteúdo**.

- **D3 — Convenção `atalho:` + coletor de ledger.** Seção nova no
  `modo-dev/SKILL.md` documentando `atalho: <teto>, <caminho de upgrade>`, e
  `scripts/atalhos.cjs` que varre, agrupa por arquivo e marca **`sem-gatilho`**
  os que não nomeiam condição de retorno.

  *Problema.* Existe **exatamente 1** marcador `ponytail:` no repo
  (`hooks/heartbeat.cjs:75`), o `modo-dev` não documenta a convenção, e nada
  coleta. Convenção adotada por imitação, sem a regra e sem o coletor — que é o
  estado em que "depois" vira "nunca".

  *Marcador em português* porque o repo é em português e amarrar o vocabulário
  ao nome de um plugin de terceiro não se paga. A única ocorrência existente
  migra; o coletor aceita os dois prefixos por alternância no regex — custo
  zero. A tag `sem-gatilho` é o ponto todo: é ela que separa adiamento de
  descarte. Mesmo desenho do `/ideia` (gancho de retorno concreto), aplicado a
  código.

- **D4 — Skill `enxugar`: revisão contra excesso.** Uma skill, dois modos (diff
  e repo inteiro), tags fechadas em português — `apagar:`, `stdlib:`,
  `nativo:`, `yagni:`, `encolher:` — uma linha por achado, ranqueado pelo maior
  corte, placar `líquido: -N linhas`.

  *Problema.* O `revisar` é correção e QA. Não existe faixa que revise **só**
  over-engineering. A regra 9 barra polimento novo; nada corta o que já está
  lá.

  *Nome.* `poda` está ocupado — `scripts/poda.cjs` é um proxy HTTP de medição
  de contexto, sem relação. `enxugar` está livre e combina com `enxertar`.

  *Fronteira herdada do ponytail,* e é ela que impede a skill de virar um
  segundo `revisar`: correção, segurança e performance ficam **explicitamente
  fora de escopo**, e o mínimo de um check executável (regra do próprio
  `modo-dev`) nunca é marcado para deleção.

  Duas skills separadas seriam ponto de variação sem segundo caso: o método é o
  mesmo, muda a entrada.

- **D5 — Régua medida, com fronteira de honestidade.** Duas entregas.

  *(a) A medição.* `scripts/medir-escada.sh` roda um conjunto fixo de tarefas
  pequenas contra o mesmo agente **com e sem** a injeção de D1, e mede duas
  coisas: tamanho do código produzido, e um **gate de correção** — um `assert`
  por tarefa que falha se o código estiver errado. Sem o gate, "menos código"
  não significa nada; é o ponto do `benchmarks/correctness.js` do ponytail
  (*"proves 'less code' is not 'broken code'"*). Usa
  `hooks/lib/cli-externo.cjs` (`rodarCli`), que já chama Codex/Gemini para o
  `conselho` e a `segunda-opiniao` — sem infra nova, sem promptfoo, sem chave
  nova.

  *Tamanho é em caractere, não em linha* — este parágrafo dizia "linhas" e o
  script sempre contou caractere. Fica caractere: as respostas curtas das
  tarefas cabem em uma linha, e uma régua em linhas devolveria ganho zero para
  uma redução real. Caractere é o mesmo eixo, mais fino.

  *O gate roda código de modelo, que é código arbitrário.* Ele entra em
  `vm.runInNewContext` num contexto vazio (sem `require`, sem `process`) e com
  relógio — e as **provas de cada tarefa entram no mesmo script**, não em volta
  dele: o relógio do `vm` só vale para o que roda dentro da chamada, e uma
  função que nunca retorna, chamada do host, pendura a bateria para sempre. A
  bateria carrega três payloads hostis (`cli-hostil.cjs`) só para que remover
  essa fronteira deixe a medição vermelha; sem eles a catraca de mutação
  devolvia `RECUSADO: bateria VERDE`.

  *(b) A fronteira de honestidade,* que este repo precisa e não tem: nunca
  imprimir número de economia estimado sobre um repo vivo — a versão não
  construída nunca foi escrita, então não há baseline de onde subtrair. Número
  só sai da bateria (a), que tem baseline medido, ou do ledger de D3, que é
  contagem.

  *Problema.* O rainforest tem a skill `regua` (builder × crítico cego), mas
  nenhuma medição de que suas regras mudem comportamento de modelo.

- **D6 — Dial de intensidade + mostrador.** Três níveis em `config.json` da
  pasta de dados, lidos pelo hook de D1 e filtrando o texto injetado no
  subagente; nível ativo na statusline, que já existe (`statusline/`,
  `scripts/instalar-statusline.sh`).

  *Escopo do dial: a escada de D1, não as 17 regras.* Elas já têm um mecanismo
  de dimensionamento medido e testado (`montarContexto`, `TETOS`,
  `testa-medir-injecao.sh`); trocá-lo por outro desenho é refactor de raio
  grande sem defeito que o motive. A escada é o caso novo, e é onde o dial
  nasce.

- **D7 — Crédito do ponytail no README.** `modo-dev/SKILL.md:9-10` diz
  "procedência item a item no README". O README lista mattpocock, karpathy,
  unlazy, task-observer, UditAkhourii — **ponytail não está lá**, nem
  superpowers. A escada é compressão quase direta de um projeto MIT, e o repo é
  público: ponta solta de atribuição, não arrumação.

- **D8 — O checador de creep enxerga pasta e portão datado.** Achado ao fechar
  este próprio fluxo, e não é ponytail: é o `revisar` recusando por creep os
  dez arquivos que o plano declarava.

  *Dois defeitos, mesma família.* (a) `globMatches` compara literalmente
  qualquer padrão sem `*`, então `arquivos: scripts/fixtures/escada/` no plano
  lê como cobertura da pasta e não cobre arquivo nenhum — caminho de pasta
  nunca é igual a caminho de arquivo. (b) A isenção do portão é
  `docs/rainforest/portoes/<slug>.md`, mas portão nasce datado
  (`2026-09-08-aclopar-ponytail.md`); os dois que existem no repo são. O
  arquivo que **registra a verificação do fluxo** era acusado de creep desse
  mesmo fluxo.

  *Por que aqui e não plantado.* Os dois apareceram na frente, bloqueando o
  `marcar revisar`, e o custo de contorná-los (listar dez arquivos à mão no
  plano) é maior que o de consertá-los — e o contorno deixa a armadilha
  armada para o próximo plano que escrever `pasta/`.

  *(b) é a irmã exata do defeito já documentado* no comentário de
  `globs_isentos` para o design (`fluxo-9-design-portaria.md` não se chama
  `<slug>.md`). O conserto de lá não olhou a linha de baixo.

- **D9 — O teto de tempo do CI para de ser cara ou coroa.** `timeout-minutes:
  20` contra uma suíte que leva 18-21 min. Medido em 2026-09-08 nos doze runs
  anteriores a este fluxo: os que passam chegam em 18-19 min, e **cinco
  morreram em 20-21 min com o placar `as N baterias passaram` já impresso** —
  verde, cancelado no último segundo. Três branches diferentes, mais este.

  *Não é o meu fluxo que estourou o orçamento.* As 3 baterias que entram aqui
  põem o run em 19m08s no node 24 (verde) e 20m13s no node 22 (cancelado); o
  `fluxo/agentes-em-codex` bateu 20 min sem nada meu dentro. O teto está
  mal-posto para a suíte que existe.

  *Vai para 35, e o teto continua servindo.* O modo de falha que ele deve pegar
  é bateria **pendurada** — stdin aberto, espera de rede —, e para isso 35 pega
  igual. O que 20 pegava era o tempo normal, e um alarme que dispara no normal
  ensina a reapertar botão até dar sorte: o dia em que a suíte quebrar de
  verdade, ninguém acredita no vermelho.

  *E a metade que é minha eu corto.* O caso do laço infinito da bateria da
  escada é 5 s de espera parada por run. `TIMEOUT_MS` passa a ler
  `RFM_GATE_TIMEOUT_MS`, e só esse caso baixa para 500 ms — prova a mesma
  coisa, que existe relógio. O default de 5 s continua valendo para código de
  modelo de verdade, e a catraca `{ timeout: TIMEOUT_MS }` → `{}` continua
  vermelha.

  *Se o tempo real encostar em 30,* o conserto é a suíte ficar mais barata, não
  este número subir de novo. Está escrito no arquivo.

## Avaliado e descartado

- **Trava de deriva para a `ponte` e para as duas CLAUDE.md.** Foi a primeira
  leitura desta análise, e está **errada — conferido**. `scripts/ponte.cjs`
  gera o arquivo, embute hash de 16 caracteres do SKILL.md no bloco, e
  `scripts/conferir-ponte.cjs` detecta edição manual; a skill já manda nunca
  escrever à mão. E `diff` entre as duas CLAUDE.md (64 linhas cada) sai
  **vazio** — a deriva de 2026-08-10 foi resolvida por *remoção* (a regra saiu
  das duas e foi para o plugin), não por trava. Não há trabalho ali. O
  `check-rule-copies.js` tem duas metades e a primeira leitura apontou a
  errada; a que importa virou D2.

- **Matcher por `agent_type` no hook de D1** (o `PONYTAIL_SUBAGENT_MATCHER` do
  original). Ponto de variação sem segundo caso: os nove agentes querem a mesma
  injeção. Entra quando existir um agente que comprovadamente não deva
  recebê-la.

- **Estender o dial de D6 às 17 regras.** Ver D6: refactor de raio grande sobre
  um mecanismo medido e testado, sem defeito que o motive.

- **Promptfoo e chave de API nova para D5.** `rodarCli` já resolve, e é o que o
  `conselho` e a `segunda-opiniao` usam.

- **Duas skills separadas para diff e repo em D4.** Mesmo método, entrada
  diferente.

## Fora de escopo

- A abertura em leque multi-harness do ponytail (`.cursor/`, `.windsurf/`,
  `.clinerules/`, `.kiro/`, `.opencode/`, MCP, extensão pi). A `ponte` já faz
  isso sob demanda, que é a decisão certa para este repo.
- Os dois arquivos não-rastreados `cross-cutting-principles.md` (3 linhas, só
  cabeçalho) e `skill-observations/` (`last-review-date.txt` = `never`): são
  enxerto de outro repo, largado no meio. Mesmo sintoma, origem diferente —
  não entra neste fluxo.
- Recuperar os dois degraus perdidos na compressão da escada ("cabe em uma
  linha?" e o formato `skipped:`): entram junto com D1, que reescreve o texto
  injetado, mas não são decisão própria.

## Em aberto

- **Quantos modelos na bateria de D5.** O ponytail usa três (Haiku, Sonnet,
  Opus). Aqui depende de quais CLIs o `/setup` desta máquina declara. Resolve-se
  na execução lendo a config, não agora.
- **Se o `revisar` deve chamar o `enxugar` automaticamente** ou se a skill fica
  só invocável. Fica invocável nesta rodada; encadear é decisão que quer um caso
  real de uso antes.

## Nota de processo

Duas correções do Luís nesta sessão, na mesma direção, gravadas em
`plantar-virou-o-lugar-onde-ideia-morre`: os itens D3, D4 e D5 foram oferecidos
primeiro como plantio e depois como Issue, e as duas foram recusadas — *"as
ideias estão se perdendo no tempo e não fazemos nada"*. O estoque dá razão a
ele: **226 plantadas contra 126 colhidas**, a mais antiga de 2026-08-05.

Plantar serve para o que **desvia do foco ativo** (regra 6). Item de um
trabalho que o próprio usuário trouxe e quer resolve-se agora. Por isso os sete
itens estão neste design, e não em sete linhas do `ideias.jsonl`.
