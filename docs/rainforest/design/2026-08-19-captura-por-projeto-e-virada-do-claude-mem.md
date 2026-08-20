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

## Em aberto

- **Como a passada de LLM chama o modelo.** A escolha de 2026-08-19 foi
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

  Dois limites do mesmo caminho, medidos junto: o trecho vai no **argumento**,
  porque `claude -p "instrução"` com stdin canalizado **trava** (morto em 120 s);
  e o argumento estoura `ENAMETOOLONG` entre 16.908 e 33.708 caracteres, então
  a passada precisa de teto por chamada de qualquer jeito.

## Fora de escopo

- Busca vetorial e semântica (segue valendo o desenho anterior: FTS5).
- Migração de ideias e foco para índice no banco.
