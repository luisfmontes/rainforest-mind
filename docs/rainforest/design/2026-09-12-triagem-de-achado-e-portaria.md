# Triagem de achado (defeito ≠ ideia) e portaria fora do fluxo

## Objetivo

Dois defeitos do plugin relatados pelo usuário em 2026-09-12, com a mesma raiz:
a regra que decide está escrita num lugar que a sessão não lê. (1) Achado de
defeito no meio do trabalho vira plantio, porque a triagem mora em
`commands/issue.md` e o núcleo injetado só oferece plantar. (2) Subagente pedido
fora de um fluxo é negado pela portaria mesmo com autorização explícita do
usuário, porque a regra 10 recusa exceção em runtime por princípio.

## Decisões fechadas

- **D1 — A triagem de achado entra no NÚCLEO da regra 6, não só na elaboração** —
  porquê: a tabela "defeito → Issue | melhoria → ideia | método → feedback" já
  existe em `commands/issue.md` e `commands/feedback.md`, mas são slash commands:
  só carregam quando digitados. O núcleo injetado tem três caminhos de plantio
  (regras 6 e 13) e nenhum de "conserta agora" ou "abre Issue", então todo achado
  cai na única porta visível. Prescrição já escrita em
  `obs-2026-08-24-defeito-do-plugin-oferecido-como-ideia`, plantada há 19 dias e
  nunca colhida — pelo mesmo motivo.

- **D2 — Os bytes saem de subir `NUCLEOS_MAX_BYTES` e o teto agregado de
  propósito, ~+300 B** — porquê: medido antes de decidir, o núcleo está em
  5598/5600 B (folga de 2 B) e o agregado em 14927/15000 B (folga de 73 B). O
  comentário do próprio `hooks/lib/contexto-sessao.cjs` prescreve esta escolha
  quando a margem zera: "encurtar `references/regra-NN.md` ou subir o teto de
  propósito — nunca deixar a folga sumir calada". Encurtar outro núcleo para
  pagar seria tirar regra de contexto para pôr regra em contexto. O motivo fica
  escrito ao lado do número novo, como está ao lado do antigo.

- **D3 — O ponteiro de elaboração no núcleo passa a citar o nome real do arquivo,
  com zero à esquerda** — porquê: o núcleo injetado manda ler
  `references/regra-<n>.md`, e os arquivos em disco são `regra-06.md`. Quem
  seguir o caminho literal para qualquer regra de um dígito não acha o arquivo,
  e a regra 14 manda anunciar regra bloqueada pelo ambiente — aqui ela falha em
  silêncio.

- **D4 — A portaria passa a admitir autorização do usuário, lida do
  `transcript_path`** — porquê: a regra 10 recusava exceção em runtime porque o
  hook só vê o payload, e o payload quem escreve é o modelo — autorização
  auto-relatada não é conferível. Mas o payload carrega `transcript_path`
  (confirmado em `.rainforest/portaria/amostra.json`), então o hook pode conferir
  a autorização nos turnos DO USUÁRIO. Deixa de ser auto-relato e passa a ser
  fato conferível, que é o padrão que a regra 12 exige de todo o resto.

- **D5 — O reconhecimento é por frase livre, não por comando dedicado** —
  porquê: o usuário já escreve "autorizo subagentes" naturalmente, sem saber que
  existe portaria — foi o que aconteceu na sessão que originou este fluxo.
  Comando dedicado obriga a aprender a sintaxe da trava para contornar a trava.
  O casamento é sobre turno de usuário apenas, com negação ("não autorizo")
  tratada, e lendo só a cauda do transcript para não estourar o orçamento de
  tempo do hook.

- **D6 — A autorização vale pela sessão inteira e libera qualquer agente; a
  regra 11 não afrouxa** — porquê: expirar por turno faria o usuário reautorizar
  a cada pedido, e já há registro de três reautorizações numa sessão só
  (`janela-parou-de-despachar-em-silencio`). O que a autorização dispensa é o
  portão de ESTÁGIO; agente que escreve continua exigindo `isolation: "worktree"`
  e despacho sem `name`, que é o que impede escrita na árvore do usuário.

- **D7 — Os agentes nativos do Claude Code entram no `.rainforest/agentes.json`
  DESTE repositório, como read-only** — porquê: `Explore`, `general-purpose` e
  `claude-code-guide` são negados hoje até DENTRO de um fluxo, por não constarem
  de um manifesto que só conhece agentes do rainforest. O log tem 11 negações só
  deles.

  **Correção de 2026-09-12, no estágio `plano`:** a primeira redação desta
  decisão mandava o manifesto para o "padrão do plugin, via `/setup`",
  justificado por "vale para qualquer repo que instale o plugin". As duas
  afirmações eram falsas e foram aprovadas pelo usuário na palavra da sessão,
  sem que ele tivesse como conferir. Medido depois:

  ```
  grep -n  "agentes"      skills/setup/SKILL.md   -> nada
  grep -rln "agentes.json" scripts/*.cjs          -> nada
  grep -n  "portaria"     hooks/hooks.json        -> exit 1
  grep -n  "portaria"     .claude/settings.json   -> node "$CLAUDE_PROJECT_DIR/hooks/portaria.cjs"
  ```

  Não existe manifesto padrão — o daqui foi escrito à mão — e a portaria está
  registrada só no `.claude/settings.json` deste repositório, num caminho que só
  existe aqui. Logo ela não roda em nenhum outro repo, e o alcance que
  justificava a decisão não existia. Registrado em
  `obs-2026-09-12-afirmei-alcance-do-plugin-sem-medir`.

- **D8 — O log registra sob que autorização o agente entrou** — porquê: é a mesma
  cegueira que o campo `escreve_conferido` fechou em 2026-09-01. Allow por
  autorização do usuário sai com `via: "autorizacao-do-usuario"` e o turno que a
  originou; allow por estágio continua como está. Registrar que um agente rodou
  sem registrar a única coisa que tornou aquilo admissível repete o defeito já
  consertado uma vez.

- **D9 — O defeito de roteamento vira Issue neste repo, e a observação de
  2026-08-24 é colhida com este fluxo como resultado** — porquê: é a própria
  triagem da D1 aplicada a si mesma. A observação tem `ao_colher` escrito e
  gancho que já disparou dezenas de vezes; deixá-la plantada depois de consertar
  o defeito que ela descreve seria provar que o mecanismo continua quebrado.

- **D10 — Levar a portaria para o nível do plugin fica FORA deste fluxo, e vira
  Issue de decisão** — porquê: é o que a correção da D7 destrampou, e é escolha
  do usuário, não consequência técnica: exigiria criar o manifesto padrão,
  ensinar o `/setup` a instalá-lo e aceitar portão de subagente em todo repo
  dele. Decidir isso de dentro de um fluxo sobre outro assunto seria a mesma
  pressa que produziu a D7 errada.

## Avaliado e descartado

- **Estágio avulso (`fora-de-fluxo`) aberto por comando** — é estado que o modelo
  pode marcar sozinho, então a autorização voltaria a ser auto-relato: exatamente
  o buraco que a portaria existe para tapar. A leitura do transcript não tem essa
  propriedade.
- **Só ampliar o manifesto (declarar nativos, alargar `estagios`)** — resolve as
  negações por "não consta no manifesto", mas não as por "sem estágio ativo".
  Medido no log: `tester` negado 2× em 2026-09-11 já estando declarado.
- **Encurtar outro núcleo para pagar os bytes da D1** — tirar regra de contexto
  para pôr regra em contexto, com a escolha de qual sacrificar feita sem critério.
- **Pôr a triagem só no `references/regra-06.md`** — é o estado atual do defeito:
  elaboração não é injetada, e ler a elaboração pressupõe já saber que a regra se
  aplica.

## Fora de escopo

- Reavaliar `tester`, `documentador` e `resolvedor-de-build` no manifesto dentro
  do fluxo — ficaram de fora por decisão de 2026-09-02, e a D6 os alcança fora do
  fluxo sem reabrir aquela decisão.
- Medir quantos bytes do SessionStart de fato chegam à sessão — ideia plantada
  (`medir-quantos-bytes-do-session-start-chegam`), pré-requisito de nada aqui: a
  D2 mexe no teto que o hook aplica, não no que o harness entrega.
- Colher as outras 5 ideias que são defeito disfarçado (listadas na sessão) —
  a D1 conserta o mecanismo; reclassificar o acervo é trabalho separado.

## Em aberto

(vazio)
