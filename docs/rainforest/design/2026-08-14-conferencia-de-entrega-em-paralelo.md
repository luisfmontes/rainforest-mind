# Conferencia de entrega e teste de saude sobrevivem a despacho paralelo

## Objetivo

Tirar de `conferir-entrega.cjs` (e do gemeo `.py`) o falso positivo que reprova
toda segunda entrega de uma rodada paralela, e consertar o fixture do
`testa-saude.sh` que quebra assim que o historico ganha um merge commit — os
dois defeitos disparam pelo mesmo gatilho, a proxima esteira que despachar em
paralelo.

## Decisões fechadas

- **D1 — A checagem 5 passa de identidade para ancestralidade** — porquê: hoje
  `conferir-entrega.cjs:292` reprova se o HEAD do repo principal nao for
  literalmente igual a `--head-antes`. Em paralelo, a janela integra a entrega
  do agente A e o HEAD anda para frente por acao dela, nao do agente. Passa a
  valer: o HEAD atual tem de ser descendente-ou-igual do `--head-antes`. Recuo
  e movimento lateral (checkout de outra branch, reset) continuam reprovando, e
  e neles que mora a falha N1 de 2026-08-08 — o caso do
  `testa-conferir-entrega.sh:103` move o HEAD com `checkout HEAD~1`, para tras,
  e segue reprovando sem reescrita. Vale **sempre**, nao so em modo paralelo:
  em despacho serial a janela nao devia estar commitando, mas se commitou, o
  que se quer detectar continua sendo o movimento que nao e avanco.

- **D2 — A checagem 4 ganha modo cruzamento, ativado por `--paralelo`** —
  porquê: olhando so o estado do repo principal, a sujeira da janela e a do
  agente sao indistinguiveis. Sem flag, a checagem 4 fica como esta hoje
  (qualquer entrada em `status --porcelain` reprova), o que mantem verdes todos
  os casos existentes. Com `--paralelo`, so reprova a sujeira que **cruza** com
  os arquivos que o agente tocou; o resto vira aviso. O enfraquecimento fica
  opt-in e so vale quando o paralelismo foi escolhido — mesma logica da regra
  17, paralelo e escolha do usuario e o preco dela e dele.

- **D3 — "Arquivo que o agente tocou" e o diff `base..commit`** — porquê: com
  `--base` no briefing, o conjunto sai de `diff --name-only base..commit`;
  sem `--base`, cai para os arquivos do commit entregue sozinho. Agente que fez
  tres commits na tarefa tocou os tres conjuntos, e olhar so o ultimo cega o
  cruzamento para o que ele mexeu no meio do caminho.

- **D4 — O caso benigno vira aviso nomeado, nunca `OK` silencioso** — porquê: o
  script imprime comando e saida crua justamente para que a conclusao se confira
  contra a evidencia. HEAD que avancou sai como "o HEAD do principal avancou N
  commit(s) desde o despacho"; sujeira que nao cruza sai como "N alteracao(oes)
  no principal, nenhuma nos arquivos do agente". Aviso nao derruba o exit 0, e
  apagar o fato do relatorio esconderia que houve trabalho em paralelo.

- **D5 — A situacao A do `testa-saude.sh` passa a rodar contra uma FONTE
  sintetica, nao contra o repositorio real** — porquê: hoje `testa-saude.sh:62`
  monta o cenario com `reset --hard HEAD~3`, que anda pelo primeiro pai, e afere
  contra o `rev-list --count` do `saude.cjs`, que percorre o DAG inteiro. Em
  historico linear os dois numeros coincidem e o teste passa por acidente. O
  errado e o fixture, nao o `saude.cjs`: contar pelo DAG e a resposta certa para
  "quantos commits este clone esta atras".
  A bateria passa a montar um repositorio-fonte proprio, com historico linear
  criado por ela, clona-lo enquanto ele tem 1 commit, acrescentar 3 commits a
  fonte e so entao rodar o `saude.cjs` contra essa fonte. O clone fica 3 atras
  **por construcao**, em qualquer maquina e em qualquer dia.
  **Emendada em 2026-08-15**: a redacao anterior dizia "commits sinteticos numa
  linha reta criada pelo proprio teste" sem dizer contra qual fonte, e era
  incumprivel — enquanto o clone for do repositorio real, os commits que faltam
  a ele sao necessariamente commits reais, e commit sintetico deixaria o clone
  a FRENTE, que e a situacao C. Duas tentativas de agente falharam nesse ponto
  cego antes de a causa ser isolada.

- **D6 — As mudancas entram no `.cjs` e no gemeo `.py`** — porquê: a bateria
  roda contra os dois por `CONFERIR="python scripts/conferir-entrega.py"`
  (`testa-conferir-entrega.sh:17`), e e isso que prova que o port nao perdeu
  checagem. Mexer so no `.cjs` faz a suite verde mentir sobre paridade a partir
  do primeiro caso novo.

- **D7 — O contrato de chamada muda em um lugar so** — porquê: o unico bloco de
  invocacao documentado e `skills/executar/SKILL.md:74`, que passa a mandar
  `--paralelo` no caminho de despacho paralelo. `agents/executor.md` cita o
  script pelo nome (linha 133) mas nao monta a linha de comando, entao nao muda.

## Avaliado e descartado

- **Cruzamento sempre, sem flag** — matava o caso de `testa-conferir-entrega.sh:97-99`.
  Medido no fixture: o commit do agente toca so `feito.txt` (linha 58) e o
  intruso e `$R/intruso.txt` (linha 97), entao nao ha cruzamento e o caso, que
  hoje espera exit 1, passaria a exit 0. O que ele protege e falha N1 real —
  agente sujando o diretorio do usuario num arquivo que ele nao tocou no
  worktree.
- **Foto `--sujeira-antes` no despacho, comparando a diferenca** — integrar a
  entrega do agente A produz exatamente sujeira nova que nao estava na foto, e
  a checagem reprova pelo mesmo motivo de hoje.
- **A janela reenviar `--head-antes` com o valor do momento da conferencia** — a
  checagem passa a se comparar consigo mesma e aprova sempre.
- **Abandonar a leitura do repo principal e medir so o diff do agente** — era a
  saida que a propria ideia recomendava, e cega a checagem para a falha N1
  inteira, que e agente editando o diretorio do usuario.
- **Modo `--paralelo` rebaixando as checagens 4 e 5 a mero aviso** — desliga a
  trava exatamente onde o risco e maior.
- **Derivar o alvo do fixture da mesma metrica (recuar ate `rev-list --count`
  dar 3)** — descartado primeiro por manter o teste refem do DAG do dia, e
  depois **refutado por medicao**: em 2026-08-15, na propria branch de trabalho,
  as contagens dos dez ancestrais do HEAD eram `0, 1, 2, 4, 4, 5, 7, 8, 8, 9`.
  O 3 foi pulado. Nao existe alvo a derivar — o cenario "exatamente 3 atras"
  pode nao existir no historico, e um fixture que o procura falha por ausencia,
  nao por defeito.
- **Afrouxar a assercao da situacao A (exigir so o nivel `aviso`, sem o numero)**
  — apaga justamente o que dava valor ao caso: o defeito original era uma
  contagem errada passando despercebida.
- **Derivar alvo e numero esperado juntos, com `rev-list --count` antes de
  asserir** — sempre existe e e barato, mas afere com a mesma regua que testa:
  pegaria nivel errado e formato errado, nunca contagem errada.

## Fora de escopo

- **`.gitattributes` / CRLF em `agents/` e `commands/`** — tem gancho proprio:
  pega carona na proxima entrega que ja for tocar essas pastas, para nao gastar
  um commit de ruido sozinho.
- **`reprovado` sem diff no `estado.cjs`** — outra trava, outro estagio; nao
  encosta em `conferir-entrega`.
- **`agents/executor.md`** — nao monta linha de comando, entao nao muda (D7).
- **Trocar o `saude.cjs`** — a contagem por DAG esta certa; o defeito e do
  fixture (D5).

## Em aberto

- (vazio)
