# Plano: Memória — reconciliação na escrita e consolidação automática

Design: docs/rainforest/design/2026-09-16-memoria-reconciliacao-e-consolidacao.md

## Medição do acervo — 2026-09-18, `~/.rainforest/rainforest.db`

Os números do design são de 2026-09-16 e mudaram; e um deles **muda o D7**. Medido
com `node --experimental-sqlite` contra o banco real, em modo somente-leitura:

| o que | valor |
|---|---|
| observações | 11.467 (eram 10.855) |
| consolidadas / resumos | 0 / 0 |
| com 60+ dias (regra atual) | **0** — a mais antiga é de 2026-08-04, 45 dias |
| com 30+ dias (regra do D7) | 9.827 |
| `origem` na forma `sessao:<id>:offset:<n>` | 1.375 (12%), de 2026-08-20 em diante |
| `origem` na forma `claude-mem:<seq>:<hash>` | **10.092 (88%)**, de 2026-08-04 a 2026-08-20 |
| sessões distintas (nas 1.375) | 260 grupos, média 5,29, maior 33 |
| ritmo atual de captura | 1.377 observações nos últimos 30 dias (~46/dia) |

**O furo do D7:** o `<seq>` do `claude-mem:` é um contador crescente da importação —
10.092 valores distintos em 10.092 linhas. As importadas **não têm sessão de origem
nenhuma**. Agrupar por sessão cobriria 12% do acervo e deixaria 88% fora da
consolidação para sempre, que é o oposto do que o D7 quer. A tarefa 4 declara um
agrupamento de recurso para elas — ver `Q1` no fim deste arquivo, que é decisão do
usuário e pode mudar só a tarefa 4.

## Números calibrados (D4 e D6, que o design deixou para cá)

- **K = 5 candidatas** por observação, do FTS5, mesmo `projeto`, ordenadas por
  `bm25(observacoes_fts)`. **Não há limiar numérico de similaridade** — o `bm25` do
  SQLite não tem escala comparável entre consultas, e um corte arbitrário sobre ele
  seria número inventado passando por critério. Quem decide parecença é o passo de
  LLM, que tem `skip` como ação válida; o K é o parâmetro que a medição da tarefa 7
  revisa.
- **N = 200 observações reconciliadas por execução** (teto do D6). Com ~46 novas por
  dia e uma execução por dia, sobram ~154/dia para o acervo: 10.092 pendentes ÷ 154
  ≈ **66 dias** para o acervo inteiro passar uma vez. Teto menor deixaria a fila
  crescer; maior estoura o custo de uma passada só.
- **Consolidação: grupo mínimo de 2, teto de 30 observações por grupo** (o maior
  grupo de sessão medido tem 33; o maior grupo do recurso tem 521, então o teto
  fatia), **idade ≥ 30 dias**, e **M = 10 grupos por execução** — sem esse teto a
  primeira execução dispararia ~340 chamadas de LLM de uma vez.

## O que não pode quebrar

- **Nada é apagado.** `substituida_por` tira a linha da injeção e da busca; `DELETE`
  em `observacoes` continua não existindo em nenhum caminho novo. A fusão **insere
  uma terceira** observação e marca as duas antigas — não reescreve nenhuma.
- **`observar.cjs` não ganha chamada de LLM nenhuma** (D1). Foi ali que a captura
  parou calada por 13 dias (#282); o caminho da escrita continua com o custo de hoje.
- **O `UNIQUE(projeto, origem)` continua valendo.** A observação nascida de fusão tem
  `origem` própria e determinística (`reconciliacao:<id_menor>+<id_maior>`), então
  reprocessar o mesmo par não duplica.
- **Degradação continua sendo exit 0.** Banco ausente, corrompido, `claude` fora do
  PATH ou LLM que falha: aviso no stderr e segue — nenhum caminho novo derruba a
  abertura da sessão nem o hook.
- **O teto de 3.000 B do bloco de memória** (`hooks/lib/memoria-sessao.cjs`,
  `TETOS.MEMORIA_MAX_BYTES`) não sobe. A linha do D8 cabe dentro do que já existe ou
  não entra.
- **A contagem do `/saude`** (`observacoes` vs `observacoes_fts`) continua batendo:
  linha substituída permanece nas duas tabelas, e os triggers do FTS já cuidam do
  `UPDATE`.
- **Regra 15 — nada fora da raiz de dados.** A manutenção em segundo plano escreve só
  em `~/.rainforest/` (banco, trava, log) e é morta pelo PID que ela mesma registra.

## Tarefas

### 1. Colunas `substituida_por` e `reconciliada_em` em `observacoes` [tipo: implementar]
atende: D3, D6
arquivos: `scripts/esquema-memoria.sql`, `scripts/memoria.cjs`, `scripts/testa-memoria.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `      ALTER TABLE observacoes ADD COLUMN substituida_por INTEGER;`
  para: `      SELECT 1;`
  bateria: `bash scripts/testa-memoria.sh`
  fixture: `testa-memoria.sh, caso "migracao 6: banco legado ganha substituida_por e reconciliada_em"`
pronto quando: com uma cópia do banco real (`~/.rainforest/rainforest.db`, 11.467 linhas) colocada numa raiz de sandbox via `RFM_ROOT`, `node scripts/memoria.cjs iniciar` seguido de `node scripts/memoria.cjs esquema` lista as colunas `substituida_por` e `reconciliada_em` em `observacoes`, e as 11.467 linhas continuam lá com as duas colunas em `NULL` — provado por `RFM_ROOT=<sandbox> node --experimental-sqlite -e "const {DatabaseSync}=require('node:sqlite');const d=new DatabaseSync(process.argv[1]);console.log(d.prepare('SELECT COUNT(*) n, SUM(substituida_por IS NULL) s, SUM(reconciliada_em IS NULL) r FROM observacoes').get().n + ' ' + d.prepare('SELECT SUM(substituida_por IS NULL) s FROM observacoes').get().s)" <sandbox>/rainforest.db` imprimindo `11467 11467`, e rodar `iniciar` uma segunda vez repetindo a mesma saída (idempotência, como a migração 4)

### 2. Comando `memoria.cjs reconciliar` — store/update/merge/skip [tipo: implementar]
atende: D2, D3, D4, D6
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria-reconciliar.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `    if (decisao.acao === 'merge' || decisao.acao === 'update') {`
  para: `    if (false) {`
  bateria: `bash scripts/testa-memoria-reconciliar.sh`
  fixture: `testa-memoria-reconciliar.sh, caso "update marca a antiga com substituida_por e nao apaga nada"`
pronto quando: com um banco de sandbox contendo o par real medido no acervo — uma observação antiga ("Captura parada desde 2026-09-03 por spawn EINVAL no claude.cmd") e a nova que a corrige ("Captura religada: #282 corrigido, PR #283 mergeado") — e o mock de LLM em `TESTADOR_CHAMAR_LLM` devolvendo `{"acao":"update","alvo_id":<id da antiga>}`, `node scripts/memoria.cjs reconciliar --limite 200` deixa a antiga com `substituida_por` = id da nova e ambas ainda presentes, e marca as duas com `reconciliada_em` — provado por `RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs reconciliar --limite 200 && node --experimental-sqlite -e "…SELECT COUNT(*) total, SUM(substituida_por IS NOT NULL) substituidas FROM observacoes…"` imprimindo `2 1`; e, com o mock devolvendo texto que não é JSON, a mesma chamada imprime `2 0` (ação de recurso é `store`, nada é substituído) com exit 0

### 3. `substituida_por IS NULL` em todo caminho de leitura [tipo: implementar]
atende: D3
arquivos: `hooks/memoria-session-start.cjs`, `scripts/memoria.cjs`, `hooks/testa-memoria-session-start.sh`, `scripts/testa-memoria.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: `          AND substituida_por IS NULL`
  para: ``
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: `testa-memoria-session-start.sh, caso "observacao substituida nao entra na disputa de vagas"`
pronto quando: num banco de sandbox com 20 observações das quais 6 têm `substituida_por` preenchido, o payload real de `SessionStart` (`{"hook_event_name":"SessionStart","source":"startup","session_id":"…","cwd":"…","transcript_path":"…"}`) no stdin de `node hooks/memoria-session-start.cjs` produz um `additionalContext` em que **nenhuma** das 6 substituídas aparece e o bloco continua com 14 observações — provado por `RFM_ROOT=<sandbox> echo '<payload>' | node hooks/memoria-session-start.cjs | node -e "…conta ocorrências dos 6 conteúdos…"` imprimindo `0 14`; e `node scripts/memoria.cjs buscar --texto <termo que só as substituídas contêm> --json` imprimindo `[]`. Os caminhos de leitura cobertos são, um a um: as 7 consultas de `lerObservacoesComFTS`/`lerObservacoes` (recentes, casadas por FTS, os 3 ramos de recurso, `lerObservacoes` com e sem `projetosList`), a leitura de `resumos`, os dois ramos de `cmdBuscar` (com e sem `--texto`) e a seleção de `cmdConsolidar`

### 4. Consolidação por grupo de origem, a partir de 30 dias [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `      const TETO_POR_GRUPO = 30;`
  para: `      const TETO_POR_GRUPO = 100000;`
  bateria: `bash scripts/testa-memoria.sh`
  fixture: `testa-memoria.sh, caso "grupo de 45 observacoes vira dois resumos, nao um"`
pronto quando: numa cópia do banco real em sandbox (9.827 observações com 30+ dias; 260 grupos de sessão e 98 grupos de recurso `(projeto, dia)`), com o mock de LLM devolvendo um resumo fixo, `node scripts/memoria.cjs consolidar --limite-grupos 10` grava **exatamente 10** resumos, marca `consolidada_em` só nas observações desses 10 grupos, e **nenhum resumo mistura dois grupos** — provado por `RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs consolidar --limite-grupos 10 && node --experimental-sqlite -e "…SELECT (SELECT COUNT(*) FROM resumos), (SELECT COUNT(DISTINCT consolidada_em) FROM observacoes WHERE consolidada_em IS NOT NULL)…"` imprimindo `10` resumos; e, contra o mesmo banco **antes** da mudança, `consolidar` imprimindo `nenhum projeto com 50+ observações de 60+ dias, nada a fazer` — a regra velha não dispara em 2026-09-18 e a nova dispara, que é o ponto do D7

### 5. Passada de manutenção em segundo plano, uma vez por dia [tipo: implementar]
atende: D1, D5
arquivos: `scripts/memoria.cjs`, `hooks/memoria-manutencao-session-start.cjs`, `hooks/hooks.json`, `hooks/testa-memoria-manutencao.sh`
depende de: 2, 4
paralela: nao
mutacao:
  arquivo: `hooks/memoria-manutencao-session-start.cjs`
  de: `  if (fs.existsSync(travaDeHoje)) process.exit(0);`
  para: `  if (false) process.exit(0);`
  bateria: `bash hooks/testa-memoria-manutencao.sh`
  fixture: `testa-memoria-manutencao.sh, caso "segunda sessao no mesmo dia nao dispara a manutencao"`
pronto quando: com o payload real de `SessionStart` no stdin, a primeira execução de `node hooks/memoria-manutencao-session-start.cjs` cria a trava do dia em `<raiz>/manutencao-<AAAA-MM-DD>.lock` com o PID do filho dentro e sai em menos de 1 s (o filho segue destacado), e a segunda execução no mesmo dia **não cria processo nenhum** — provado por `RFM_ROOT=<sandbox> echo '<payload>' | node hooks/memoria-manutencao-session-start.cjs; echo "exit=$?"; cat <sandbox>/manutencao-$(date +%F).lock` saindo `exit=0` com um PID no arquivo, e pela segunda chamada imprimindo o **mesmo** PID (a trava é `mkdir`/`wx` atômico, não `existsSync` seguido de escrita, porque duas sessões abrem juntas); e `node scripts/memoria.cjs manutencao` sozinho chamando `reconciliar --limite 200` e depois `consolidar --limite-grupos 10`, nessa ordem, com o executável resolvido por `scripts/lib/achar-executavel-claude.cjs` (o conserto do #282)

### 6. Falha da manutenção ou da captura vira linha na abertura [tipo: implementar]
atende: D8
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/memoria-session-start.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: 5
paralela: nao
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: `  if (horasParada > 48) linhas.push(avisoDePipeline(horasParada, ultimaManutencao));`
  para: `  if (false) linhas.push(avisoDePipeline(horasParada, ultimaManutencao));`
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: `testa-memoria-session-start.sh, caso "marca d'agua parada ha 60h imprime a linha de pipeline na abertura"`
pronto quando: num sandbox cuja `marca_dagua` tenha `offset > offset_processado` e `processada_em` de 60 h atrás, o payload real de `SessionStart` no stdin de `node hooks/memoria-session-start.cjs` produz um `additionalContext` contendo **uma** linha que nomeia as três coisas que o usuário precisa para agir — que a captura está parada, **há quanto tempo**, e o comando que religa (`node scripts/observar.cjs`) —, e o bloco inteiro continua **≤ 3.000 B** (`TETOS.MEMORIA_MAX_BYTES`, sem subir o teto); com a marca em dia, a linha **não** aparece — provado por `RFM_ROOT=<sandbox> echo '<payload>' | node hooks/memoria-session-start.cjs | node -e "…imprime (contém a linha? sim/nao) e Buffer.byteLength do bloco…"` imprimindo `sim <=3000` no primeiro caso e `nao` no segundo, e por `bash scripts/testa-orcamento.sh` continuando verde

### 7. Medir o recall do FTS5 como buscador de candidatas [tipo: pesquisar]
atende: D4
arquivos: `scripts/medir-recall-reconciliacao.cjs`, `relatorios/2026-09-18-recall-fts5-reconciliacao.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: tarefa de medição — o artefato é um relatório com números, não comportamento
  do sistema. A falsificação dela é outra: o relatório tem de trazer os campos e o
  número, e um relatório sem eles reprova na leitura, não numa bateria invertida.
pronto quando: contra o banco real em cópia somente-leitura, `node scripts/medir-recall-reconciliacao.cjs --amostra 200` escreve `relatorios/2026-09-18-recall-fts5-reconciliacao.md` contendo, nomeados: o tamanho da amostra (200 observações mais recentes), o K medido (5), **o recall em % — quantas das decisões `update`/`merge` da LLM tinham a observação-alvo dentro das 5 candidatas do FTS5** — e o recall recortado pelas duas metades do corpus bilíngue (as 1.375 nativas em português e as 10.092 importadas em inglês), que é o risco que o D4 nomeia. O relatório fecha declarando o veredito contra o limiar deste plano: **recall abaixo de 70% em qualquer das duas metades vira decisão de vetor no próximo design; 70% ou mais mantém o FTS5 e o K=5** — provado por `node scripts/medir-recall-reconciliacao.cjs --amostra 200 && grep -cE "recall|amostra: 200|K = 5|portugues|ingles|veredito" relatorios/2026-09-18-recall-fts5-reconciliacao.md` devolvendo 6 ou mais e o arquivo trazendo números, não `n/d`

### 8. Documentar o que passou a existir [tipo: docs]
atende: D3, D5, D7
arquivos: `README.md`, `scripts/esquema-memoria.sql`, `skills/rainforest-mind/references/regra-13.md`
depende de: 6, 7
paralela: nao
mutacao: n/a
  motivo: texto não tem comportamento a inverter; a falsificação é a coerência com o
  que o código faz, conferida pelos comandos abaixo
pronto quando: os três números do texto casam com os do código, lidos do fonte e não
  do plano — o teto por execução do README é o mesmo literal de `--limite` em
  `scripts/memoria.cjs`, o teto de grupos é o mesmo de `--limite-grupos`, e a idade de
  consolidação é a mesma constante de dias — provado por
  `node -e "const s=require('fs').readFileSync('scripts/memoria.cjs','utf8');const r=require('fs').readFileSync('README.md','utf8');const n=[/limite[^0-9]{0,20}(\d+)/,/limite-grupos[^0-9]{0,20}(\d+)/,/(\d+)\s*\*\s*24\s*\*\s*60\s*\*\s*60/].map(x=>(s.match(x)||[])[1]);console.log(n.join(' '), n.every(v=>v&&r.includes(v)))"`
  imprimindo `200 10 30 true`; e o cabeçalho do `esquema-memoria.sql` descrevendo
  `substituida_por` como "tira da injeção e da busca, nunca apaga" — a prescrição do
  D3 —, conferido por `bash scripts/testa-memoria.sh` continuar verde com o esquema
  lido do arquivo

## Em aberto para o usuário

**Q1 — as 10.092 observações importadas do claude-mem não têm sessão. Como agrupá-las
na consolidação?** O D7 decidiu "agrupa por sessão de origem", e isso só existe para
12% do acervo. ➡️ **Recomendo agrupar por `(projeto, dia de criada_em)`** — medido:
98 grupos, média 103 observações, maior 521, só 3 grupos de 1. A importação é
cronológica por projeto, então um dia dentro de um projeto é o mais perto de "um
assunto" que o dado permite, e o teto de 30 por grupo já fatia os grandes. As duas
alternativas e por que não: deixar as importadas fora da consolidação para sempre
(mantém 88% do acervo sem síntese, que é o problema que o D7 ataca) ou agrupar por
janela fixa de N observações (é o lote cronológico que o D7 acabou de rejeitar).
A tarefa 4 está escrita com a recomendação; mudar a resposta muda só ela.
