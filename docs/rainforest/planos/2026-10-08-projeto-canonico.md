# Plano: Nome canônico de projeto no banco de memória (#435)

Design: docs/rainforest/design/2026-10-08-projeto-canonico.md
Base: 97758368. Versão alvo: 1.51.0 (os dois `plugin.json` estão em 1.50.2; `origin/main` está em 1.50.2 e é o merge-base).

## Achados que mudam o desenho

- **A1. O D4 apaga os resumos da abertura.** Conferido no banco real: `resumos` tem 180 linhas em 20 nomes de projeto, todos curtos (0 em forma de slug). `hooks/memoria-session-start.cjs:381` filtra resumos com o mesmo `IN (...)` das observações. Tirar o nome curto da lista sem migrar `resumos` zera todo resumo da abertura. O plano migra `resumos` junto, na mesma transação e pela regra do D6 (medido numa cópia: 8 nomes/154 linhas migram, 12 nomes/26 linhas ficam). Ver U1.
- **A2. `VERSAO_ESQUEMA` é armadilha.** `limparMarcaDagua` (`scripts/memoria.cjs:350-357`) faz `if (versao >= VERSAO_ESQUEMA) return;` e, abaixo, `DELETE FROM marca_dagua`. Subir a constante de 1 para 2 com o banco real em `user_version=1` apagaria as marcas d'água e reprocessaria tudo do offset 0 (viola D8 e a invariante "nenhuma linha some"). A migração nova usa constante e guarda próprias (`VERSAO_PROJETO_CANONICO = 2`). `VERSAO_ESQUEMA` continua 1 e é o alvo da mutação da tarefa 5.
- **A3. `cmdBackup` não roda dentro de `criarSchema`.** Ele chama `resolverCaminhos()` sem argumento, faz `process.exit(1)` em falha e abre conexão própria. `criarSchema` é chamado pelo hook `Stop` (`timeout: 5`). A tarefa 2 extrai a função, a CLI passa a chamá-la, e a migração a chama antes do primeiro `UPDATE`.
- **A4. `resolverCaminhos().projeto` muda de sentido em worktree.** Hoje é o basename do worktree (`scripts/memoria.cjs:123-125`); pelo D1 passa a ser o basename do repositório principal. Chamadores: `scripts/observar.cjs:44` (devolvido, não usado como chave), `scripts/importar-claude-mem.cjs:181` (fallback, vira o canônico na tarefa 9) e `cmdIniciar`/`cmdReindexar` (rótulo e tabelas derivadas, que seguem pelo nome curto).
- **A5. Rótulo de linha de outro projeto na abertura.** Linha de OUTRO projeto (as que completam o bloco) passa a ser rotulada pelo slug longo, porque o slug não é reversível para nome curto. Só o projeto atual mantém o rótulo curto (apelido). Ver U2.
- **A6. Primeira abertura depois da atualização.** O `SessionStart --recover` (`hooks/memoria-marca.cjs`, roda `criarSchema`) e `memoria-session-start.cjs` são hooks distintos do mesmo evento (inferido: rodam em paralelo). A primeira abertura pode ler antes da migração. A seguinte vê tudo. `node scripts/memoria.cjs iniciar` migra na hora. Vai no CHANGELOG (tarefa 11).
- **A7. Efeito transitório na colheita da #436.** Sessão aberta antes da migração e pontuada depois tem linhas de outros projetos rotuladas pelo nome curto antigo; `acharAlvo` não casa essas linhas. Medido numa cópia: 0 sessões de worktree pendentes de pontuação. Entra no CHANGELOG. Publicar cedo mantém a janela de 2026-10-23 limpa.
- **A8. Worktree fora de `.claude/worktrees/`.** A pasta de transcritos só carrega o marcador `--claude-worktrees-` nessa convenção. O leitor (por cwd) resolve qualquer worktree pelo `commondir`; o gravador, que só vê o nome da pasta (D2/D8), não. Linhas de worktree fora da convenção seguem sob o slug do próprio worktree (limite aceito).

## Decisões do usuário (fechadas em 2026-10-08: as três como recomendado)

- **U1. Migrar `resumos` junto (A1).** Decidido: sim, mesma regra do D6, mesma transação.
- **U2. Rótulo de linha de outro projeto na abertura (A5).** Decidido: slug cru nas linhas que completam o bloco; tabela manual de apelidos fica fora de escopo (como no design).
- **U3. Alcance do D7.** Decidido: reescrever a origem só das linhas de worktree que colidiriam (9 no banco real), como o D7 está escrito.

Decisões técnicas assumidas (sem impacto de produto): a biblioteca nova mora em `scripts/lib/projeto-canonico.cjs`, módulo folha que nunca requer `memoria.cjs` (evita o circular descrito em `scripts/lib/utilidade.cjs:283`). No par que difere só em caixa, vence a grafia com mais linhas (empate: ordem alfabética crescente). Slug armazenado pela regra antiga é renormalizado pela regra do harness no mesmo `UPDATE`. `COLLATE NOCASE` sem índice novo (medido: 5,5 ms por consulta em 13.765 linhas; o hook de abertura tem teto de 5 s). `scripts/semear.cjs:163` mantém a própria cópia da regra: só lista pastas de transcritos, não grava nem lê `projeto`, e a regra dele já é a correta.

## Fatos apurados (lidos ou medidos no worktree 97758368 e numa cópia do banco real fora do repo)

- `.git` de worktree tem a forma `gitdir: <principal>/.git/worktrees/<nome>`, e esse diretório tem `commondir` com `../..`. O topo do repositório principal é o pai do diretório comum. Sem `spawn` de git (`hooks/testa-memoria-marca.sh`, teste 1, greppa `spawn`/`exec` no hook).
- `scripts/memoria.cjs`: `chaveHarness` `:86-90`; `resolverCaminhos` `:105-141`; `criarSchema` `:371`; `limparMarcaDagua(conexao)` em `:509`; `UNIQUE(projeto, origem)` em `scripts/esquema-memoria.sql:43`; `cmdBackup` `:1043-1120`; `cmdBuscar` `:938`, filtro `:987`; reconciliação copia `obs.projeto` (`:1975-1978`).
- Gatilho `observacoes_au` dispara em qualquer `UPDATE`. Na cópia: `UPDATE` de 13.765 linhas = 278 ms; `integrity-check` do FTS passa antes e depois.
- `scripts/observar.cjs:342-357` `INSERT` sem `ON CONFLICT`; `:534` origem. `scripts/lib/grupo-de-origem.cjs` pega o id da sessão até o primeiro `:`, então `sessao:<id>:wt:<nome>:offset:<n>` agrupa igual.
- Leitores: `hooks/memoria-session-start.cjs` `:61,:121,:140,:219,:239,:381` (`projeto [NOT] IN`), `:360-364` (apelido); `hooks/lib/memoria-sessao.cjs:197,:380` (`apelidos[projeto]` exato); `hooks/lib/memoria-assunto.cjs:62` (peso por `===`); `hooks/memoria-assunto-prompt.cjs:70,:83,:93`; `hooks/memoria-assunto-agente.cjs:27,:35`; `scripts/lib/utilidade.cjs:286-300` (cópia de `encontrarGit`), `:320-344` (cópia do regex em `:337`), `:614-615` (apelido).
- Banco real (cópia): `observacoes` 13.765 linhas, 83 nomes; `resumos` 180/20; `marca_dagua` 593 linhas; `user_version = 1`. Simulação da regra do D6: 9 nomes/8.777 linhas migram, 17 nomes/1.458 linhas sem correspondência, 0 ambíguos; 54 linhas em pasta de worktree, 9 colidem com a principal e deixam de colidir com `:wt:<nome>:`.
- Placares na base 97758368 (todos `0 falha(s)`): `hooks/testa-memoria-session-start.sh` 84; `scripts/testa-utilidade.sh` 19; `scripts/testa-utilidade-canais.sh` 22; `scripts/testa-memoria.sh` 41; `scripts/testa-observar.sh` 41; `scripts/testa-observar-offset.sh` 6; `scripts/testa-importar-claude-mem.sh` 18; `hooks/testa-memoria-marca.sh` 12; `scripts/testa-memoria-backup.sh` 11; `hooks/testa-memoria-recuperacao.sh` 14; `scripts/testa-memoria-somente-leitura.sh` 29; `scripts/testa-versao.sh` 17; `hooks/testa-memoria-assunto.cjs`, `-prompt.cjs`, `-agente.cjs` 14 cada; `hooks/testa-mod-abertura.cjs` 29 (0 skipped).

## O que não pode quebrar

- **Nenhuma linha some.** `count(*)` de `observacoes`, `resumos`, `marca_dagua` e `uso_memoria` antes = depois, e o conjunto de `id` de `observacoes` é o mesmo. A migração aborta com `ROLLBACK` se a contagem divergir.
- **Backup antes de qualquer alteração.** Com linha a mover e `user_version < 2`, o arquivo em `<raiz>/.rainforest-backups/` existe e abre com as mesmas contagens ANTES do primeiro `UPDATE`. Se o backup falhar, nada muda e `user_version` fica em 1.
- **Os testes nunca tocam `~/.rainforest`.** Toda bateria nova monta a própria caixa (`mkdtemp`) e passa `RFM_ROOT` explícito aos processos filhos. O ensaio com o banco real usa CÓPIA; `tamanho + mtime` do banco real e a listagem de `~/.rainforest` são iguais antes e depois.
- **`marca_dagua` fica como está (D8).** `projeto` continua sendo o nome da pasta de transcritos, e `VERSAO_ESQUEMA` continua 1.
- **Nenhum hook imprime em stdout por causa da migração.** Falha da migração nunca impede `criarSchema` nem o hook de sair 0. `hooks/memoria-marca.cjs` não ganha `spawn`/`exec`.
- **`UNIQUE(projeto, origem)` nunca estoura** na migração, na passada nem no gravador. Colisão que a regra do D7 não resolve deixa a linha onde está e entra no relatório.
- **FTS íntegro:** `integrity-check` passa depois da migração, e uma busca acha linha migrada.
- **Repositório público:** nenhum nome real de projeto, cliente ou empregador em código, fixtures, relatório ou critério (usar `alfa`, `beta`, `omega`, `comum`).
- **Passada idempotente:** a segunda abertura não altera nenhuma linha, e `user_version` fica em 2.

## Tarefas

### 1. Função canônica única de projeto [tipo: implementar]
atende: D1, D2, D6
arquivos: `scripts/lib/projeto-canonico.cjs`, `scripts/testa-projeto-canonico.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-projeto-canonico.cjs`
mutacao:
  arquivo: `scripts/lib/projeto-canonico.cjs`
  de: `String(caminho).replace(/[^a-zA-Z0-9]/g, '-')`
  para: `String(caminho).replace(/[\\/:]/g, '-')`
  bateria: `node scripts/testa-projeto-canonico.cjs`
  fixture: `testa-projeto-canonico.cjs, caso "caminho com ponto, sublinhado e espaco vira hifen (regra do harness)"`
pronto quando: com um repositório git real `<tmp>/alfa` (`git init` e `git -c user.name=t -c user.email=t@t.invalid commit --allow-empty`), um worktree real `<tmp>/alfa/.claude/worktrees/w1` (criado por `git worktree add`) e um segundo worktree real fora da convenção, `<tmp>/alfa-wt/w2`, o módulo `scripts/lib/projeto-canonico.cjs` exporta, e a bateria afirma contra essas pastas reais (nenhum caso lê o texto do fonte): `slugDoCaminho(caminho)` (regra do harness, `[^a-zA-Z0-9]` → `-`); `ehSlugDeCaminho(valor)` (começa por `<letra>--` ou `-`); `topoPrincipal(inicio)` (sobe até o `.git`; se for arquivo, lê `gitdir:`, lê `commondir` desse diretório e devolve o pai do diretório comum quando ele se chama `.git`; qualquer outro caso, inclusive `commondir` ausente ou `.git` de submódulo, devolve o próprio diretório); `canonicoDoCaminho(caminho)` devolvendo `{ canonico, curto, topo }`; `canonicoDaPasta(nome)` devolvendo `{ canonico, worktree }`; e `casarCurto(curto, canonicos)` devolvendo `{ tipo: 'unico'|'nenhum'|'ambiguo', canonico, candidatos }`. Asserções: `canonicoDoCaminho` de `<tmp>/alfa`, de `<tmp>/alfa/.claude/worktrees/w1`, de uma subpasta desse worktree e de `<tmp>/alfa-wt/w2` (resolvido pelo `commondir`, não pelo nome da pasta) devolvem o MESMO `canonico`, igual a `slugDoCaminho('<tmp>/alfa')`, e `curto === 'alfa'`; pasta sem `.git` devolve `canonico = slugDoCaminho(pasta)` e `curto = basename`; `slugDoCaminho('C:/Projetos/alfa/.claude/worktrees/w1')` é `C--Projetos-alfa--claude-worktrees-w1`, e caminho com `.`, `_`, espaço e acento vira só hífens; `canonicoDaPasta('C--Projetos-alfa--claude-worktrees-fluxo-x-y')` devolve `{ canonico: 'C--Projetos-alfa', worktree: 'fluxo-x-y' }`, pasta sem o marcador devolve `worktree: null` e o marcador em outra caixa também é reconhecido; `casarCurto('alfa', ['C--Projetos-alfa','C--Projetos-beta'])` é `unico`, com `['C--Projetos-alfa','C--Outros-alfa']` é `ambiguo` com os dois candidatos, `'gama'` é `nenhum`, `'ALFA'` casa (sem diferenciar caixa), `'lfa'` NÃO casa (fronteira de hífen) e `'meu_alfa'` é comparado como `meu-alfa`. A lib não usa `child_process`: `grep -c child_process scripts/lib/projeto-canonico.cjs` devolve `0`. Forma do alvo de mutação (código a nascer): `slugDoCaminho` é uma expressão só, sem ramo e sem log; nenhum caso afirma sobre o texto do fonte. Provado por `node scripts/testa-projeto-canonico.cjs` imprimindo uma linha `ok` por caso e `0 falha(s)`.

### 2. Backup do banco como função reutilizável [tipo: implementar]
atende: D5
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria-backup-funcao.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-memoria-backup-funcao.cjs`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `fs.copyFileSync(caminhoDb, caminhoBackup);`
  para: `void 0;`
  bateria: `node scripts/testa-memoria-backup-funcao.cjs`
  fixture: `testa-memoria-backup-funcao.cjs, caso "backup tem as mesmas linhas do banco"`
pronto quando: com um banco de caixa criado por `criarSchema` real, com 3 observações e 2 marcas d'água, `fazerBackupDoBanco(caminhoDb)` (extraída do miolo de `cmdBackup`, exportada) devolve o caminho `<raiz>/.rainforest-backups/rainforest-<AAAA-MM-DDTHH-MM-SS>.db`. Esse arquivo abre por `abrirBancoSomenteLeitura` com `count(*)` igual ao do banco em cada tabela. Com uma conexão de escrita ainda aberta (WAL ativo) que acabou de inserir uma linha, o backup contém essa linha. Para caminho de banco inexistente a função LANÇA `Error` (sem `process.exit`). A rotação de 5 cópias nunca apaga a mais recente. `cmdBackup` passa a chamar a função e mantém o comportamento atual: `RFM_ROOT=<caixa> node scripts/memoria.cjs backup` imprime `backup: <caminho>` com exit 0, e com banco ausente sai 1 com `ERRO: banco não existe em ...` no stderr. Provado por `node scripts/testa-memoria-backup-funcao.cjs` com `0 falha(s)` e por `bash scripts/testa-memoria-backup.sh` continuando em `11 ok, 0 falha(s)`.

### 3. Peso do projeto atual sem diferenciar maiúscula [tipo: implementar]
atende: D3, D4
arquivos: `hooks/lib/memoria-assunto.cjs`, `hooks/testa-peso-projeto-atual.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-peso-projeto-atual.cjs`
mutacao:
  arquivo: `hooks/lib/memoria-assunto.cjs`
  de: `((String(b.projeto).toLowerCase() === atual) - (String(a.projeto).toLowerCase() === atual)) ||`
  para: `((b.projeto === atual) - (a.projeto === atual)) ||`
  bateria: `node hooks/testa-peso-projeto-atual.cjs`
  fixture: `testa-peso-projeto-atual.cjs, caso "desempate favorece o projeto atual mesmo com a caixa do slug diferente"`
pronto quando: com um banco de caixa criado pelo `criarSchema` real e duas observações de conteúdo idêntico (mesmo `bm25`), a de projeto `C--Projetos-beta` com `id` MENOR e a de `C--Projetos-Alfa` com `id` maior, `buscarPorAssunto(conexao, texto, { projetoAtual: 'c--projetos-alfa', jaServidos: new Set(), max: 3, limiar: 1e9 })` devolve a de alfa primeiro (com a comparação exata, a de beta viria primeiro pelo desempate de `id`). Com `projetoAtual` igual em caixa, o resultado não muda. `hooks/testa-memoria-assunto.cjs` continua em `14 ok, 0 falha(s)`. Forma do alvo de mutação (código a nascer): `const atual = String(projetoAtual).toLowerCase();` antes do `sort`, e o desempate por projeto numa expressão só, na forma do `de:`; nenhum caso lê o texto do fonte. Provado por `node hooks/testa-peso-projeto-atual.cjs` imprimindo `ok` por caso e `0 falha(s)`.

### 4. Gravador `observar`: projeto canônico e origem com o nome do worktree [tipo: implementar]
atende: D2, D7, D8
arquivos: `scripts/observar.cjs`, `scripts/testa-observar-canonico.cjs`
depende de: 1
paralela: nao
prova: `node scripts/testa-observar-canonico.cjs`
mutacao:
  arquivo: `scripts/observar.cjs`
  de: `${worktree ? ':wt:' + worktree : ''}`
  para: `${''}`
  bateria: `node scripts/testa-observar-canonico.cjs`
  fixture: `testa-observar-canonico.cjs, caso "mesma sessao na pasta principal e na de worktree com o mesmo offset grava duas linhas"`
pronto quando: com `RFM_ROOT=<tmp>` e a mesma sessão `S1` presente em `<tmp>/projects/C--Projetos-alfa/S1.jsonl` e em `<tmp>/projects/C--Projetos-alfa--claude-worktrees-w1/S1.jsonl` (mesmo conteúdo, logo mesmo `offsetFim`; eventos `user`/`assistant` no formato do transcrito real), cada pasta recebe sua marca pelo hook REAL `hooks/memoria-marca.cjs` com o payload de `Stop` (`{session_id:'S1', transcript_path, cwd}`) no stdin. Em seguida `node scripts/observar.cjs` (sem argumentos; `TESTADOR_CHAMAR_LLM=scripts/dubliador-llm-ok.cjs`) grava duas observações, ambas com `projeto = 'C--Projetos-alfa'`, de origens `sessao:S1:offset:<n>` e `sessao:S1:wt:w1:offset:<n>`. As duas marcas avançam (`offset_processado` = `offset`), e `marca_dagua.projeto` das duas continua sendo o nome da pasta (D8). Uma segunda execução de `observar.cjs` não grava linha nova. Na base, as duas observações saem com o nome da pasta como `projeto` e o caso falha. `bash scripts/testa-observar.sh` continua em `41 ok, 0 falha(s)`, `bash scripts/testa-observar-offset.sh` em `6 ok, 0 falha(s)` e `bash hooks/testa-memoria-marca.sh` em `12 ok, 0 falha(s)`. Forma do alvo de mutação (código a nascer): `destinoDaObservacao(marca, offsetFim)` devolve `{ projeto: canonico, origem }` por `canonicoDaPasta(marca.projeto)`, com a origem montada em template único `sessao:${marca.sessao}${worktree ? ':wt:' + worktree : ''}:offset:${offsetFim}`; nenhum caso afirma sobre o texto do fonte. Provado por `node scripts/testa-observar-canonico.cjs` com `0 falha(s)`.

### 5. Migração v2 e passada idempotente, com backup, resumos e colisões [tipo: implementar]
atende: D3, D5, D6, D7
arquivos: `scripts/lib/migrar-projeto-canonico.cjs`, `scripts/memoria.cjs`, `scripts/testa-migrar-projeto-canonico.cjs`
depende de: 1, 2
paralela: nao
prova: `node scripts/testa-migrar-projeto-canonico.cjs`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `const VERSAO_ESQUEMA = 1;`
  para: `const VERSAO_ESQUEMA = 2;`
  bateria: `node scripts/testa-migrar-projeto-canonico.cjs`
  fixture: `testa-migrar-projeto-canonico.cjs, caso "marca_dagua intacta na migracao 1 para 2"`
pronto quando: com um banco de caixa na forma do real, criado pelo `criarSchema` da base, com linhas inseridas à mão e `PRAGMA user_version = 1`, contendo: `C--Projetos-alfa` (várias linhas); `C--Projetos-alfa--claude-worktrees-w1` com uma linha de origem `sessao:S1:offset:10` que colide com a da principal, uma de origem `sessao:S2:offset:5` sem colisão e uma de origem `reconciliacao:1+2`; `c--projetos-alfa` (1 linha, menos linhas que a grafia maiúscula); o curto `alfa` (único; algumas origens `claude-mem:...`); o curto `omega` (sem correspondência); o curto `comum` (ambíguo: existem `C--A-comum` e `C--B-comum`); o curto `meu_alfa`; `resumos` curtos `alfa` e `omega`; 3 linhas de `marca_dagua` (uma de pasta de worktree) e linhas de `uso_memoria` que referenciam ids. Depois de `criarSchema(conexao)` e também de `RFM_ROOT=<caixa> node scripts/memoria.cjs iniciar`: (1) `count(*)` de `observacoes`, `resumos`, `marca_dagua` e `uso_memoria`, e o conjunto de ids de `observacoes`, são os mesmos de antes; `user_version` é 2; `marca_dagua` está byte a byte igual (a mutação de `VERSAO_ESQUEMA` apagaria as 3 marcas); (2) existe um arquivo em `<raiz>/.rainforest-backups/` que abre e tem as contagens de ANTES; (3) `c--projetos-alfa` e `C--Projetos-alfa--claude-worktrees-w1` viram `C--Projetos-alfa` (grafia com mais linhas); a linha que colidia fica com origem `sessao:S1:wt:w1:offset:10`, a sem colisão fica com a origem `sessao:S2:offset:5` e a `reconciliacao:1+2` não muda de origem; (4) o curto `alfa` e o `resumos` curto `alfa` vão para `C--Projetos-alfa`; `omega` e `comum` ficam como estão; `meu_alfa` é comparado como `meu-alfa`; (5) `integrity-check` do FTS passa e uma busca por termo de linha migrada a acha; (6) uma segunda abertura altera 0 linhas (instantâneo de todas as colunas igual); (7) uma linha inserida DEPOIS da migração, `(C--Projetos-alfa--claude-worktrees-w1, 'sessao:S1:offset:10')`, simulando a conta com plugin antigo, é recolhida pela abertura seguinte (projeto canônico e origem com `:wt:`) sem backup novo e sem nova versão; (8) com `fazerBackup` substituído por função que lança, nenhuma linha muda, `user_version` fica 1 e `criarSchema` não lança; (9) com outra conexão segurando `BEGIN IMMEDIATE`, `criarSchema` não lança nem altera nada, e liberada a conexão a abertura seguinte migra; (10) `criarSchema` executado como processo filho não escreve nada em stdout. Superfície humana: a primeira migração grava `<raiz>/migracao-projeto-canonico.txt`, e quem o abre vê o caminho do backup, as linhas movidas, as colisões reescritas e, por nome, os curtos que ficaram (`omega`, com a contagem de linhas) e os ambíguos (`comum`, com os dois candidatos); a passada seguinte não reescreve esse arquivo. Forma do alvo de mutação: `VERSAO_ESQUEMA` continua uma constante numérica no topo de `limparMarcaDagua`; a migração nova tem constante própria (`VERSAO_PROJETO_CANONICO = 2`, no módulo novo) e é chamada no fim de `criarSchema` como "Migração 7". Nenhum caso lê o texto do fonte. Provado por `node scripts/testa-migrar-projeto-canonico.cjs` com `0 falha(s)`, e por `bash scripts/testa-memoria-migracao-atomica.sh`, `bash hooks/testa-memoria-recuperacao.sh` (14), `bash scripts/testa-memoria-somente-leitura.sh` (29) e `bash scripts/testa-memoria.sh` (41) sem regressão de placar.

### 6. Leitores: `resolverCaminhos` devolve o canônico e abertura e hooks do assunto o usam [tipo: implementar]
atende: D2, D3, D4
arquivos: `scripts/memoria.cjs`, `hooks/memoria-session-start.cjs`, `hooks/lib/memoria-sessao.cjs`, `hooks/memoria-assunto-prompt.cjs`, `hooks/memoria-assunto-agente.cjs`, `hooks/testa-leitores-canonicos.cjs`, `hooks/testa-memoria-session-start.sh`, `hooks/testa-abertura-mod-memoria.sh`, `hooks/testa-mod-abertura.cjs`, `hooks/testa-memoria-assunto-prompt.cjs`, `hooks/testa-memoria-assunto-agente.cjs`, `scripts/fixtures/utilidade/gerar-banco.cjs`
depende de: 1, 5
paralela: nao
prova: `node hooks/testa-leitores-canonicos.cjs`
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: `const PROJETO_NOCASE = 'projeto COLLATE NOCASE';`
  para: `const PROJETO_NOCASE = 'projeto';`
  bateria: `node hooks/testa-leitores-canonicos.cjs`
  fixture: `testa-leitores-canonicos.cjs, caso "abertura acha linhas e resumos gravados com o slug em outra caixa"`
pronto quando: `resolverCaminhos(cwd)` devolve `{ raiz, caminhoDb, projeto, canonico }` sem o campo `projetos`: com `cwd` dentro de um worktree real do repositório `alfa` (e também na raiz e em subpasta), `canonico` é `slugDoCaminho(<topo de alfa>)` e `projeto` é `alfa`; sem `.git`, `canonico` é o slug do próprio `cwd` e `projeto` o basename. `chaveHarness` sai de `scripts/memoria.cjs` e do `module.exports`, e os chamadores de teste passam a importar `slugDoCaminho` da lib. A seção 11 de `hooks/testa-memoria-session-start.sh` passa a afirmar a regra do harness, a seção 12 passa a semear linhas em UM nome só e a seção 15 continua provando o rótulo curto. Com a entrada real da abertura (o hook `hooks/memoria-session-start.cjs` rodando como processo, `CLAUDE_PROJECT_DIR=<tmp>/alfa/.claude/worktrees/w1`, `RFM_ROOT=<caixa>`) e uma caixa com 3 observações de alfa gravadas com o canônico em outra caixa (`canonico.toUpperCase()`), 1 resumo de alfa na mesma grafia e 2 observações de `beta`, o `additionalContext` traz as 3 de alfa rotuladas `(alfa)` e nunca com a chave longa, traz o resumo, e as de beta só completam o bloco; com uma caixa de 14.000 observações de enchimento o hook sai 0 em menos de 3 s (teto do hook: 5 s). O hook do pedido (`memoria-assunto-prompt.cjs`), com o payload real de `UserPromptSubmit` e `cwd` no worktree, ainda semeia os ids servidos pela abertura, e o do `Agent` usa o mesmo `canonico` como `projetoAtual`. `apelidoDe(apelidos, projeto)` em `hooks/lib/memoria-sessao.cjs` compara sem diferenciar caixa nos dois pontos (`:197` e `:380`). Forma do alvo de mutação (código a nascer): uma constante `PROJETO_NOCASE` usada em TODA comparação de projeto de `hooks/memoria-session-start.cjs`; nenhum caso lê o texto do fonte. Os testes `hooks/testa-memoria-assunto-prompt.cjs` e `-agente.cjs` passam a semear o projeto atual com `slugDoCaminho(cwdSessao)`. Provado por `node hooks/testa-leitores-canonicos.cjs` com `0 falha(s)` e, sem regressão, `bash hooks/testa-memoria-session-start.sh`, `node hooks/testa-memoria-assunto-prompt.cjs`, `node hooks/testa-memoria-assunto-agente.cjs`, `bash hooks/testa-abertura-mod-memoria.sh`, `node hooks/testa-mod-abertura.cjs` (29, 0 skipped) e `bash scripts/testa-utilidade.sh` (19) com `0 falha(s)`.

### 7. Utilidade lê o canônico e para de duplicar a regra [tipo: implementar]
atende: D2, D3
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade-canonico.cjs`
depende de: 1, 6
paralela: nao
prova: `node scripts/testa-utilidade-canonico.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const { canonico, curto } = canonicoDoCaminho(cwd);`
  para: `const { canonico, curto } = { canonico: slugDoCaminho(cwd), curto: path.basename(cwd) };`
  bateria: `node scripts/testa-utilidade-canonico.cjs`
  fixture: `testa-utilidade-canonico.cjs, caso "sessao em worktree pontua as servidas do projeto principal"`
pronto quando: com a saída REAL do hook de abertura (`hooks/memoria-session-start.cjs` rodando com `CLAUDE_PROJECT_DIR=<tmp>/alfa/.claude/worktrees/w1` sobre uma caixa com 3 observações de alfa gravadas no slug do repositório principal) colada num transcrito como o attachment `SessionStart`, cuja entrada `user` e cujas demais linhas levam `cwd` do worktree, `pontuarSessao` grava em `uso_memoria` uma linha servida (`servida = 1`) para cada uma das 3 linhas do bloco e `servidasSemId` é 0. Na base o `harnessKey` sai com o slug do worktree e as servidas não casam. `lerProjetoDoTranscrito` devolve `{ harnessKey, curto }` (o nome do campo fica, o valor passa a ser o canônico, sem a cópia do regex de `:337` e sem `encontrarGitLocal`), com `cwd` em subpasta do repositório e em worktree resolvendo o mesmo projeto. `bash scripts/testa-utilidade.sh` continua em `19 ok, 0 falha(s)` e `bash scripts/testa-utilidade-canais.sh` em `22 ok, 0 falha(s)`. Forma do alvo de mutação (código a nascer): a derivação de `{ canonico, curto }` a partir do `cwd` é uma única desestruturação de `canonicoDoCaminho(cwd)`; nenhum caso lê o texto do fonte. Provado por `node scripts/testa-utilidade-canonico.cjs` com `0 falha(s)`.

### 8. `buscar --projeto` aceita curto, slug ou caminho [tipo: implementar]
atende: D3, D6, D9
arquivos: `scripts/memoria.cjs`, `scripts/testa-buscar-projeto.cjs`
depende de: 1, 6
paralela: nao
prova: `node scripts/testa-buscar-projeto.cjs`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `if (r.tipo !== 'unico') return { erro: formatarErroProjeto(valor, r, conhecidos) };`
  para: `if (false) return { erro: formatarErroProjeto(valor, r, conhecidos) };`
  bateria: `node scripts/testa-buscar-projeto.cjs`
  fixture: `testa-buscar-projeto.cjs, caso "curto ambiguo sai com exit 2 listando os candidatos"`
pronto quando: com uma caixa de `RFM_ROOT` com `C--Projetos-alfa` (3 observações), `C--Projetos-beta`, o órfão `omega`, `C--A-comum` e `C--B-comum`, o comando `node scripts/memoria.cjs buscar --projeto <valor> --json` resolve nesta ordem: (1) igualdade, sem diferenciar caixa, com um valor JÁ gravado (cobre o slug, o órfão e os nomes de baterias antigas como `proj-subst`); (2) valor com `/`, `\` ou `:` vira slug de caminho; (3) nome curto por sufixo único via `casarCurto`; (4) senão erro. `alfa`, `C--Projetos-alfa`, `C--projetos-ALFA` e `C:/Projetos/alfa` devolvem as mesmas 3 observações; `omega` devolve as do órfão; `comum` sai com exit 2 e `desconhecido` sai com exit 2. Em ambos o stderr traz o valor digitado, o motivo (`ambíguo` ou `não encontrado`), um candidato por linha (para `comum`, `C--A-comum` e `C--B-comum`; para o desconhecido, os projetos conhecidos) e a instrução de repetir com o nome completo ou o caminho. O mesmo vale com `--texto`. Sem `--projeto`, a saída é a de antes. Superfície humana: a pessoa que digitou `comum` vê, no stderr, os dois nomes completos e o que digitar, e o critério falha se a lista de candidatos some. `bash scripts/testa-memoria.sh` continua em `41 ok, 0 falha(s)`. Forma do alvo de mutação (código a nascer): `resolverProjetoDaBusca(conexao, valor)` tem uma única guarda de erro na forma do `de:`, depois de `const r = casarCurto(valor, conhecidos);`; nenhum caso lê o texto do fonte. Provado por `node scripts/testa-buscar-projeto.cjs` com `0 falha(s)`.

### 9. Importador grava o projeto canônico [tipo: implementar]
atende: D2, D6, D10
arquivos: `scripts/importar-claude-mem.cjs`, `scripts/testa-importar-canonico.cjs`
depende de: 1
paralela: nao
prova: `node scripts/testa-importar-canonico.cjs`
mutacao:
  arquivo: `scripts/importar-claude-mem.cjs`
  de: `if (alvo.tipo === 'unico') projetoFinal = alvo.canonico;`
  para: `if (false) projetoFinal = alvo.canonico;`
  bateria: `node scripts/testa-importar-canonico.cjs`
  fixture: `testa-importar-canonico.cjs, caso "projeto relativo com barra casa o slug canonico unico"`
pronto quando: com um `claude-mem.db` de caixa na forma real (tabela `observations`; `project` com valor relativo com barra, `grupo/alfa`, valor simples `alfa`, órfão `omega` e ambíguo `comum`; uma observação sem `project`) e um banco destino de caixa que já tem linhas de `C--Projetos-alfa`, `C--A-comum` e `C--B-comum`, a importação grava `grupo/alfa` e `alfa` como `C--Projetos-alfa`, deixa `omega` e `comum` como estão (último segmento) e grava a observação sem `project` no `canonico` do `cwd` (um repositório git real da caixa), não no nome curto. Uma segunda importação grava 0 linhas e conta todas como duplicadas. `bash scripts/testa-importar-claude-mem.sh` continua em `18 ok, 0 falha(s)`. Forma do alvo de mutação (código a nascer): depois de `const normalizado = normalizarProjeto(obs.project);`, `const alvo = casarCurto(normalizado, canonicosDoDestino);` seguido da linha do `de:`; nenhum caso lê o texto do fonte. Provado por `node scripts/testa-importar-canonico.cjs` com `0 falha(s)`.

### 10. Ensaio da migração numa cópia do banco real [tipo: pesquisar]
atende: D5, D6, D7
arquivos: nenhum arquivo do repo (ensaio em cópia no scratchpad; só números entram no registro)
depende de: 5, 6, 8
paralela: nao
mutacao: n/a
  motivo: ensaio de medição em dados reais; não há comportamento do repo a inverter, a falsificação é a comparação de contagens colada.
pronto quando: com uma CÓPIA do `~/.rainforest/rainforest.db` real (feita com `cp` para o scratchpad; confirmar antes que não há `rainforest.db-wal`), rodando `RFM_ROOT=<pasta da cópia> node scripts/memoria.cjs iniciar`: as contagens de `observacoes`, `resumos`, `marca_dagua` e `uso_memoria` antes e depois são idênticas; `user_version` vai de 1 a 2; o backup existe e abre; o `integrity-check` do FTS passa; o relatório `migracao-projeto-canonico.txt` diz 9 nomes migrados (8.777 linhas), 17 sem correspondência (1.458 linhas), 0 ambíguos e 9 colisões reescritas com `:wt:`, e para `resumos` 8 nomes (154 linhas) migrados e 12 (26 linhas) mantidos (se o banco cresceu desde 2026-10-08, a diferença tem de ser explicada por linhas com `criada_em` posterior); uma segunda abertura altera 0 linhas; `buscar --projeto <curto de um dos 9>` devolve linhas; o hook de abertura com `CLAUDE_PROJECT_DIR` num repositório com histórico migrado devolve linhas desse projeto e seus resumos; a migração leva menos de 3 s. O banco real não foi tocado: `tamanho + mtime` de `~/.rainforest/rainforest.db` e a listagem de `~/.rainforest` são iguais antes e depois, com as duas leituras coladas. O registro cola só contagens, nunca nomes de projeto — provado pela colagem dessas saídas na entrega.

### 11. Documentação, CHANGELOG e versão 1.51.0 [tipo: docs]
atende: D1, D4, D5, D6, D9
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 3, 4, 5, 6, 7, 8, 9, 10
paralela: nao
mutacao: n/a
  motivo: documentação e número de versão; a falsificação é a coerência do texto com o design e dos três lugares da versão entre si, não um comportamento.
pronto quando: com o design e o código entregues, o README ganha, na seção "Memória", um parágrafo que diz o mesmo que as decisões: o nome do projeto no banco é o slug do repositório principal, os worktrees são juntados a ele, a exibição continua pelo nome curto (D1); `resumos` migra junto; nomes curtos de correspondência única migram e os demais ficam (9 nomes/8.777 linhas migram e 17 nomes/1.458 linhas ficam, os números do design — D6); a migração faz backup em `.rainforest-backups/` e grava `migracao-projeto-canonico.txt` (D5); `buscar --projeto` aceita nome curto, slug ou caminho (D9). O CHANGELOG ganha `## 1.51.0 — <data>` com o que muda para quem usa, incluindo: vale a partir da sessão seguinte à atualização, `node scripts/memoria.cjs iniciar` migra na hora, a primeira abertura pode ainda não ver os nomes curtos (A6) e as sessões abertas antes da migração e pontuadas depois podem ter linhas de outros projetos sem id (A7). `plugin.json` e `.codex-plugin/plugin.json` vão a `1.51.0`, e o badge do README (URL e `alt`) lê `1.51.0`, os três juntos no mesmo commit. Provado por `bash scripts/testa-versao.sh` com `0 falha(s)`, `node scripts/conferir-versao.cjs` com exit 0, `node -p "require('./.claude-plugin/plugin.json').version+' '+require('./.codex-plugin/plugin.json').version"` imprimindo `1.51.0 1.51.0`, e `node -e "const f=require('fs');const t=f.readFileSync('README.md','utf8')+f.readFileSync('CHANGELOG.md','utf8');const d=f.readFileSync('docs/rainforest/design/2026-10-08-projeto-canonico.md','utf8');for(const n of ['8.777','1.458'])console.log(n,t.includes(n)&&d.includes(n))"` imprimindo `true` nos dois, conferido à mão que a frase de cada número diz o mesmo que o D6 (não só contém o número).

## Notas de integração

- Ondas: a 1ª leva as tarefas 1, 2 e 3 em paralelo (arquivos disjuntos). Depois seguem em série 4, 5, 6, 7, 8 e 9 (as tarefas 5, 6 e 8 editam `scripts/memoria.cjs`), depois a 10 e a 11.
- A integração roda `bash scripts/varrer-baterias.sh` completo e `node scripts/conferir-categoria.cjs`, e confere os placares da base listados em "Fatos".
- Cada bateria nova usa `mkdtemp` e `RFM_ROOT` explícito. As que precisam de worktree real criam com `git worktree add` e identidade de commit por `-c user.name/-c user.email` (a CI é windows-latest).
