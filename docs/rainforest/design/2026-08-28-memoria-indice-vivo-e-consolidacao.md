# Design — a memória ganha índice vivo, leitura por relevância e ciclo de vida

Origem: revisão externa da camada de memória (2026-08-28), lida contra o fonte:
`esquema-memoria.sql`, `memoria.cjs` (superfície de comandos), `observar.cjs`,
`memoria-marca.cjs`, `memoria-session-start.cjs`, `lib/memoria-sessao.cjs`.

Data: 2026-08-28. Status: aprovado em 2026-08-28 — Q1–Q3 fechadas na recomendada.

## Objetivo

A fundação está certa — marca d'água idempotente, passada de LLM fora dos
hooks, degradação graciosa, teto de bytes medido. O que falta é o banco ser
**consultável de verdade e ao longo do tempo**, não só um cache de abertura:

1. O índice FTS5 só é populado por `iniciar`/`reindexar` (delete total +
   repovoamento). `observar.cjs` grava em `observacoes` e não toca o índice —
   toda observação nova é invisível para `buscar` até alguém reindexar.
2. A injeção de abertura é recência pura (`ORDER BY criada_em DESC LIMIT 14`,
   filtrada por projeto). FTS e foco existem e não participam da seleção: o que
   é velho mas pertinente à clareira de hoje nunca volta sozinho.
3. `memoria.cjs buscar` existe e nada ensina o modelo a usá-lo — a memória é
   escrita-pesada e leitura-rasa.
4. `resumos` é tabela sem produtor: nenhum comando grava nela. Observações
   acumulam sem consolidação nem subtração.
5. A degradação silenciosa é a escolha certa nos hooks, mas banco quebrado por
   semanas sem aviso contraria a regra 14 — e o `/saude` hoje não olha o banco.

Pronto quando: observação gravada por `observar.cjs` aparece em `buscar` sem
reindexar; a abertura injeta recentes E casadas com o foco, dentro do mesmo
teto de 3.000 B; o bloco injetado termina ensinando o comando de busca;
`memoria.cjs consolidar` existe, grava em `resumos` e nunca apaga observação;
e `/saude` acusa banco inacessível, índice defasado e pipeline parado.

## Decisões fechadas

- **D1 — o FTS5 vira tabela de conteúdo externo (`content='observacoes'`),
  sincronizada por triggers de INSERT/UPDATE/DELETE criados no schema.**
  Porque: sincronia garantida pelo SQLite não depende de nenhum caminho de
  código lembrar de inserir — `observar.cjs`, importadores futuros e qualquer
  script que grave observação ficam cobertos de graça. `reindexar` continua
  existindo como reconstrução (`INSERT INTO observacoes_fts(observacoes_fts)
  VALUES('rebuild')`), agora para recuperação, não para operação. Migração de
  banco existente: drop da tabela FTS antiga + recriação + rebuild, dentro do
  `criarSchema`, idempotente.

- **D2 — a abertura divide as 14 vagas: recentes primeiro, relevantes ao foco
  completando.** O hook já resolve o projeto; passa a extrair os termos do foco
  ativo (título do bloco do FOCO.md, que `foco-session-start` já parseia) e
  rodar uma consulta FTS com eles. Seleção: recentes por padrão; das vagas, até
  N vão para casadas por FTS que **não** estejam entre as recentes (Q1 decide o
  N). Sem foco ativo, sem termos ou FTS indisponível: 14 recentes, como hoje —
  a relevância é enriquecimento, nunca dependência.

- **D3 — o bloco injetado termina com uma linha de rodapé ensinando a busca:**
  `mais: node scripts/memoria.cjs buscar "<termo>"`. Porque: memória que só se
  lê na abertura é cache; a linha custa ~60 B do teto de 3.000 e transforma o
  banco em memória consultável no meio do loop. O rodapé conta dentro do teto
  e a bateria de `memoria-sessao` já mede bytes — só ganha um caso.

- **D4 — `memoria.cjs consolidar` nasce como o produtor de `resumos`:** para
  cada projeto com mais de um teto de observações antigas (Q2 decide teto e
  idade), a passada de LLM sintetiza N observações em 1 resumo, grava em
  `resumos` e marca as originais com `consolidada_em` (coluna nova). Nunca
  apaga: `observacoes` é verdade de máquina, e o invariante do schema —
  derivado se apaga, fonte não — continua valendo. A injeção passa a preferir
  resumo a observação já consolidada quando ambos disputam vaga.

- **D5 — `/saude` ganha a seção do banco de memória**, com três checagens e
  uma linha cada: o banco abre e o schema confere; `count(observacoes)` ==
  `count(observacoes_fts)` (índice vivo); e a marca d'água mais recente tem
  observação correspondente gravada (pipeline não parado). Porque: a regra 14
  manda o bloqueio se anunciar, e o lugar do anúncio é o comando de diagnóstico
  que o usuário já roda — não um hook que não pode falhar.

## Avaliado e descartado

- **Migrar FOCO.md e ideias.jsonl para dentro do SQLite.** A pergunta é boa e a
  resposta já estava no repo: o comentário do próprio `esquema-memoria.sql`
  fixa que `indice_foco`/`indice_ideias` são tabelas **derivadas** — "apagar
  nunca perde dados — tudo é rederivável do texto". Texto como fonte da
  verdade compra três coisas que o banco não devolve: o usuário lê e edita o
  FOCO.md direto (é interface, não só dado); a camada Obsidian desenhada em
  2026-08-24 lê arquivo `.md`, não SQLite; e recuperação/diff/backup de texto
  é trivial. O que parecia argumento pró-migração — "não vai pro git mesmo,
  fica local" — não muda o custo de token da injeção (o teto manda, não a
  origem) nem melhora a leitura humana. O defeito real não era a arquitetura,
  era o índice derivado ficar velho — e isso o D1 resolve por trigger.
  `ideias.jsonl` é o caso menos óbvio (só script grava nele), mas migrar
  ganharia pouco: o `indice_ideias` já dá a busca, e o jsonl dá grep, diff e
  o `trava-jsonl.cjs` já resolve a concorrência.

- **Inserir no FTS direto no código do `observar.cjs`, sem trigger.** Funciona
  até o segundo lugar que grava observação esquecer. Trigger é a versão "exit
  code" da sincronia: não se argumenta com ela.

- **Relevância por embedding/vetor.** Custo novo (modelo, storage, dependência)
  para um corpus que o FTS5 com os termos do foco já discrimina bem no tamanho
  atual. Revisitar se o banco crescer a ponto de o FTS errar de verdade —
  medição antes.

- **Consolidação que apaga as observações originais.** Economia de disco
  irrelevante contra a perda do invariante "verdade de máquina não se apaga".
  Marcar e preferir o resumo entrega a mesma limpeza de leitura.

## Fora de escopo

- **A arquitetura de raiz de dados** (RFM_ROOT > projeto > home > plugin) —
  intocada.
- **O prompt da passada de observação** — a qualidade do que se grava é outro
  eixo; aqui é acesso e ciclo de vida do que já se grava.
- **Mover a memória para o claude-mem ou outro store** — a decisão D2 do
  design de 2026-08-17 (store próprio) não é reaberta.

## Decisões das Qs (fechadas em 2026-08-28, na recomendada)

- **Q1 — 9 recentes + até 5 casadas por FTS com os termos do foco.** Recência
  continua maioria; sem casadas suficientes, as vagas voltam para recentes.
- **Q2 — consolidação nasce manual:** `memoria.cjs consolidar`, observações de
  60+ dias quando passarem de 50 não consolidadas por projeto, lotes de 10 → 1.
  Números são chute calibrado por leitura; automatizar em hook só depois de
  rodar algumas vezes à mão.
- **Q3 — "pipeline parado" só acusa pendência (offset visto > processado) com
  mais de 48 h** — o mesmo sinal do `--recover`, agora com relógio, para não
  dar vermelho em sessão sem conteúdo observável.

## Em aberto

- **Os números da consolidação (60 dias / 50 / 10) não têm medição atrás** —
  revisitar depois que o comando rodar à mão algumas vezes.
