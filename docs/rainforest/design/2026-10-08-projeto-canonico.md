# Nome canônico de projeto no banco de memória (#435)

## Objetivo
Um projeto, um nome em `observacoes.projeto`: o slug do repositório principal pela regra do harness, com os worktrees
juntados a ele. Gravação já normalizada, dados existentes migrados, e todo leitor (abertura, `buscar`, canal do
assunto, utilidade) enxergando o projeto inteiro. Pronto antes da colheita da #436 em 2026-10-23.

## Decisões fechadas
- **D1 — Nome canônico = slug do repositório principal** — `caminho.replace(/[^a-zA-Z0-9]/g, '-')` sobre o topo do
  repositório principal (para worktree, o pai do `git-common-dir`, não o `.git` do worktree). Pasta
  `<slug>--claude-worktrees-<nome>` vira `<slug>`. A exibição continua pelo nome curto (basename do repositório
  principal). Porquê: é único por caminho; o nome curto pode colidir entre repositórios. Decisão do usuário,
  2026-10-08.
- **D2 — Uma função só para o canônico, usada por quem grava e por quem lê** — substitui `chaveHarness`
  (`scripts/memoria.cjs:86-90`), que troca só `[\\/:]` e diverge do harness (`scripts/semear.cjs:163` aplica a regra
  certa), e a cópia em `scripts/lib/utilidade.cjs:337`. Duas formas de entrada: caminho (cwd/topo) e nome de pasta de
  transcritos (o que `hooks/memoria-marca.cjs` extrai). Porquê: as divergências medidas nasceram de derivações
  diferentes do mesmo nome.
- **D3 — Comparação sem diferenciar maiúscula** — leitores comparam `projeto` com `COLLATE NOCASE`, e a migração
  agrupa sem diferenciar maiúscula. Porquê: caminho no Windows não diferencia, e `CLAUDE_PROJECT_DIR` pode chegar com
  a letra do drive em outra caixa do que a pasta do harness.
- **D4 — Substitui, não convive** — leitores consultam só o canônico (some o `IN (slug, basename)` de
  `resolverCaminhos` e de `hooks/memoria-session-start.cjs`); o peso do projeto atual (`hooks/lib/memoria-assunto.cjs:62`)
  passa a reconhecer o projeto inteiro. Porquê: com o dado migrado, a lista de duas chaves só preserva a divisão.
- **D5 — Migração única + passada idempotente em toda abertura** — `user_version` 1→2 marca a migração única (com
  backup do banco antes, pelo `memoria.cjs backup` existente); além dela, toda abertura roda um `UPDATE` só sobre
  linhas fora do canônico. Porquê: as duas contas do usuário (dois config dirs) gravam no mesmo
  `~/.rainforest/rainforest.db`, e a conta com versão antiga do plugin voltaria a dividir os dados depois da
  migração única.
- **D6 — Nomes curtos: migram só os de correspondência única** — nome curto cujo slug normalizado casa com o sufixo
  de exatamente um slug canônico existente no banco migra para ele (medido no banco real em 2026-10-08: 9 nomes,
  8.777 linhas). Sem correspondência, fica como está (17 nomes, 1.458 linhas, todos nomes de worktree da época do
  importador, cujas pastas de transcritos já não existem), visível na busca sem filtro de projeto. Mais de uma
  correspondência: fica como está e entra no relatório da migração. Porquê: adivinhar o repositório de um nome de
  worktree apagado é chutar. Decisão do usuário, 2026-10-08.
- **D7 — Origem de sessão em worktree leva o nome do worktree** — quando a pasta de transcritos é
  `<slug>--claude-worktrees-<nome>`, a origem gravada passa a `sessao:<id>:wt:<nome>:offset:<n>`; a da pasta
  principal fica `sessao:<id>:offset:<n>`. A migração aplica o mesmo formato às linhas de pasta de worktree que
  colidiriam (9 em 2026-10-08, sessões que começaram na principal e entraram num worktree). Porquê: o offset é posição
  no arquivo de transcrito, e a mesma sessão em duas pastas repete offsets; sem isso, `UNIQUE(projeto, origem)`
  (`scripts/memoria.cjs:281`) faria o `INSERT` de `scripts/observar.cjs:347` falhar e a marca d'água nunca andar.
  Decisão do usuário, 2026-10-08.
- **D8 — A marca d'água continua pela pasta de transcritos** — `marca_dagua.projeto` não muda (ele localiza o arquivo
  `.jsonl`); o canônico se aplica na passagem para `observacoes`. Porquê: a marca é ponteiro de leitura de arquivo, não
  dado de memória.
- **D9 — `buscar --projeto` aceita curto, slug ou caminho** — tudo resolve para o canônico; curto ambíguo ou
  desconhecido sai com erro listando os candidatos. Porquê: hoje é match exato, e só acha quem digita a grafia
  gravada. Decisão do usuário, 2026-10-08.
- **D10 — O importador grava canônico** — `scripts/importar-claude-mem.cjs:133` passa pela função do D2 (com a regra
  do D6 para nome curto). Porquê: é o único outro gravador; a reconciliação (`memoria.cjs:1976`) copia o `projeto` da
  linha de origem e herda o canônico.

## Avaliado e descartado
- **Nome curto como canônico** — junta repositórios diferentes de mesmo basename, e a pasta de transcritos do harness
  não carrega o nome curto de forma reversível (`-` vale por `\`, `:`, `.`, `_`, espaço e hífen).
- **Migração só por `user_version`** — a conta com plugin antigo continuaria gravando slug de worktree depois dela (D5).
- **Mapear os 17 nomes órfãos pelas pastas de transcritos** — medido: nenhum dos 17 tem pasta correspondente nos dois
  config dirs (257 pastas).

## Fora de escopo
- Os itens 1 a 3 da #436 (contagem de busca, tautologia do canal do assunto, dedupe da abertura cortada) — Issue
  própria; só o peso do projeto atual (D4) depende desta.
- Tabela manual de apelidos para os 17 nomes órfãos — fica para quando houver demanda.
- Pastas temporárias gravadas como projeto (scratchpad) — continuam como estão.

## Varredura
docs/rainforest/varredura/2026-10-08-projeto-canonico.txt — achou o PR #49 ("A memória volta a ler o que ela mesma
escreve"), que criou a leitura pelas duas chaves em vez de migrar, para não perder o corpus importado. Isso mudou o
desenho: a migração do D6 é o passo que o #49 adiou, e o D4 só remove a lista de duas chaves porque o dado passa a
estar num nome só. Nenhuma ideia no `ideias.jsonl` casou.

## Em aberto
