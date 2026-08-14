# Decisão e opção que evaporam entre design, plano e revisão

## Objetivo

A esteira não tem **checagem de fechamento entre artefatos vizinhos**: decisão do
design pode não virar tarefa, opção refutada não tem onde morar, e código sem tarefa
correspondente atravessa o `revisar` como se fosse estilo. Fechar as três costuras com
checagem que trava, não com instrução que pede.

Vem de três ideias plantadas em 2026-08-13 — `cobertura-do-design-no-plano`,
`opcao-avaliada-e-morta-some-do-design-doc` e `creep-se-mede-no-diff-contra-o-plano` —
tratadas juntas porque são o mesmo defeito em três pontos.

## Decisões fechadas

- **D1 — As três checagens moram em script com exit ≠ 0, não em prosa dentro das
  skills.** Porquê: o cabeçalho do `estado.cjs` já cravou o princípio — "enquanto o
  veredito de uma checagem for redigido pelo mesmo agente que ela deveria travar, ela
  não trava nada". Provado no mesmo dia: um agente redigiu o próprio veredito três
  vezes seguidas, e as três precisaram ser reprovadas rodando o artefato real.

- **D2 — Decisão do design ganha identificador estável `D1..Dn`, e a tarefa do plano
  cita `atende: D2, D5`.** Porquê: sem identificador a cobertura só se confere por
  leitura humana, que é exatamente o que falha hoje. Custo de migração é zero —
  medido: não há design escrito no repo, só o `README.md` da pasta.

- **D3 — Opção avaliada e refutada mora em seção nova do próprio design doc,
  `## Avaliado e descartado`, com a medição que a matou.** Porquê: separar em outro
  arquivo é o que faz perder. E `## Fora de escopo` não serve, porque caminho refutado
  não é escopo: em 2026-08-13 duas abordagens morreram por medição (subir a árvore de
  processos; casar o `claude.exe` pela linha de comando) e nenhuma das duas era "fora
  de escopo" — eram caminhos tentados e derrubados por evidência.

- **D4 — Creep encontrado reprova o `revisar`, e a única saída é emendar o plano.** A
  tarefa que faltava entra no plano com critério falsificável; justificar em prosa não
  destrava. Porquê: achado informativo vira ruído que ninguém lê, e a emenda deixa
  rastro de que o escopo cresceu conscientemente.

- **D5 — A trava fica no `estado.cjs marcar`, que recusa fechar o estágio quando a
  checagem falha.** Porquê: é o gargalo único por onde a esteira inteira já passa, e
  ele **já** recusa com exit 2 quando pré-requisito está aberto — é a mesma forma, não
  mecanismo novo.

- **D6 — A tarefa do plano declara `arquivos:` (caminhos ou globs), e arquivo do diff
  que não casa com glob de tarefa nenhuma é creep.** Glob largo (`hooks/**`) é achado
  do `revisar`, não atalho. Porquê: sem ligação tarefa→caminho o creep não é
  computável — hoje a tarefa declara tipo, dependência e critério de pronto, e nada
  que a ligue a um caminho.

- **D7 — Um script com subcomandos: `conferir-esteira.cjs design|cobertura|creep`.**
  Porquê: uma bateria só, um lugar só para resolução de caminho, e é o padrão que o
  repo já tem no `estado.cjs`.

- **D8 — A cobertura vale nos dois sentidos: decisão sem tarefa barra, e tarefa com
  `atende:` vazio barra.** Porquê: pega creep **no plano**, antes de existir código,
  em vez de esperar o diff. Simétrica, mesma leitura, mesmo arquivo, custo quase zero.

## Avaliado e descartado

- **As três checagens como prosa dentro das skills** — é o modo de falha que D1
  nomeia. Rejeitado antes de virar tarefa.
- **Hook `PreToolUse` como trava (estilo `gate-worktree`/`gate-staging`)** — dispara em
  Bash arbitrário e vira ruído fora da esteira; a trava certa é no gargalo da esteira.
- **A skill chamar o script e ler a saída** — é a prosa de D1 outra vez, com um passo
  extra: quem decide se obedece continua sendo o agente.
- **Três scripts separados** — três baterias, três resoluções de caminho, três lugares
  para divergir.
- **Creep como achado informativo** — ruído que ninguém lê; e sem reprovar, "escopo
  cresceu" nunca fica registrado.
- **Arquivo separado para a opção morta** — separar é o que faz perder, que é o defeito
  original da ideia `opcao-avaliada-e-morta-some-do-design-doc`.

## Fora de escopo

- **Migrar design existente** — não existe nenhum, medido.
- **Dar worktree ao `revisar` ou deixá-lo mutar** — segue leitura; mutação continua
  ofício do `tester`.
- **`arqueologia`, `executar`, `verificar`, `fechar`** — nenhum dos três defeitos mora
  neles.
- **Cobrir o creep de arquivo *apagado*** — a checagem olha o que o diff tocou; apagar
  arquivo fora de tarefa é caso mais raro e pede desenho próprio.

## Em aberto

- (vazio)

## Pendência de coerência encontrada no caminho

Não é decisão deste trabalho, mas afeta a resolução de caminho do script: a skill
`brainstorm` diz que o slug é `<AAAA-MM-DD-tema-em-kebab>` e grava o doc em
`<slug>.md`, enquanto `docs/rainforest/design/README.md` diz que o arquivo é
`AAAA-MM-DD-<tema>.md`. As duas convenções coincidem **só** se o slug já começar com a
data — e o slug deste trabalho não começa. O script resolve por `<slug>.md`, que é o
que o estado grava; a divergência entre os dois documentos fica registrada aqui.
