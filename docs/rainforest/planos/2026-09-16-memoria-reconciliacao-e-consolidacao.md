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

## Emendas ao plano

Registradas antes do `revisar`, porque creep se destrava emendando o plano —
justificar em prosa não destrava.

- **2026-09-18, tarefa 3 — a leitura de `resumos` sai do escopo do filtro.** O
  plano mandava aplicar `substituida_por IS NULL` também à leitura de `resumos`
  no hook. A tabela `resumos` **não tem essa coluna** (`PRAGMA table_info(resumos)`
  → `id, projeto, titulo, conteudo, criada_em`), e nenhuma tarefa a adiciona — a
  reconciliação só toca `observacoes`. Aplicar o filtro ali geraria SQL inválido,
  que o `try/catch` de degradação engoliria em silêncio, **esvaziando os resumos da
  injeção sem ninguém ver** — o modo de falha que o filtro existe para evitar. O
  executor recusou aplicar e devolveu o achado; a emenda é do plano, não da
  entrega. O critério da tarefa 3 vale sem essa metade.

## Nomes fixados (o plano prescreve, para o critério ter o que ler)

As tarefas 2, 4 e 5 criam constantes com **estes nomes**, em `scripts/memoria.cjs`:
`K_CANDIDATAS = 5`, `TETO_RECONCILIAR = 200`, `TETO_POR_GRUPO = 30`,
`TETO_GRUPOS = 10`, `DIAS_CONSOLIDACAO = 30`. A tarefa 3 cria
`function filtroVivas(alias)` no mesmo arquivo e o reusa nos hooks; a tarefa 4 cria
`scripts/lib/grupo-de-origem.cjs`, que exporta `sqlGrupoDeOrigem()` — a expressão SQL
que devolve a chave de grupo de uma linha de `observacoes`. Não é preciosismo de
estilo: os critérios das tarefas 1, 4 e 8 leem esses nomes do fonte para comparar com
o texto e com o comportamento, e nome escolhido pelo executor deixa o critério sem o
que casar — e um ponto único de inversão é o que dá à tarefa 3 uma mutação que casa
uma vez só (o `conferir-mutacao.cjs` recusa `--de` que casa 2+ vezes).

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
pronto quando: com uma cópia do banco real (`~/.rainforest/rainforest.db`) numa raiz de sandbox apontada por `RFM_ROOT`, `node scripts/memoria.cjs iniciar` deixa as duas colunas novas em `observacoes` e **não perde nem uma linha** — os três números saem iguais entre si e iguais ao `COUNT(*)` tirado **antes** do `iniciar` (o acervo cresce ~46/dia, então o número não pode estar escrito aqui) — provado por `ANTES=$(node --experimental-sqlite -e 'const{DatabaseSync}=require("node:sqlite");console.log(new DatabaseSync(process.argv[1],{readOnly:true}).prepare("SELECT COUNT(*) n FROM observacoes").get().n)' <sandbox>/rainforest.db) && RFM_ROOT=<sandbox> node scripts/memoria.cjs iniciar && node --experimental-sqlite -e 'const{DatabaseSync}=require("node:sqlite");const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare("SELECT COUNT(*) n, SUM(substituida_por IS NULL) s, SUM(reconciliada_em IS NULL) c FROM observacoes").get();console.log(r.n,r.s,r.c)' <sandbox>/rainforest.db && echo "antes=$ANTES"` imprimindo três números iguais ao valor de `antes=`, e por um segundo `iniciar` repetindo a mesma saída (idempotência, como a migração 4)

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
pronto quando: num sandbox com o par real medido no acervo — a antiga ("Captura parada desde 2026-09-03 por spawn EINVAL no claude.cmd") e a nova que a corrige ("Captura religada: #282 corrigido, PR #283 mergeado") — e o mock de `TESTADOR_CHAMAR_LLM` devolvendo `{"acao":"update","alvo_id":<id da antiga>}`, a antiga fica com `substituida_por` igual ao id da nova, **as duas continuam na tabela**, e as duas ganham `reconciliada_em` — provado por `RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs reconciliar && node --experimental-sqlite -e 'const{DatabaseSync}=require("node:sqlite");const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare("SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes").get();console.log(r.t,r.s,r.c)' <sandbox>/rainforest.db` imprimindo `2 1 2`; e, com o mock devolvendo texto que **não** é JSON, o mesmo par de comandos imprimindo `2 0 2` com exit 0 — resposta ilegível cai em `store`, que é o lado seguro do D3. A fusão insere uma **terceira** linha com `origem` determinística `reconciliacao:<id_menor>+<id_maior>` e marca as duas antigas; o teto por execução é `TETO_RECONCILIAR` e as candidatas são as `K_CANDIDATAS` do FTS5 no mesmo `projeto`, por `bm25`

### 3. `substituida_por IS NULL` em todo caminho de leitura [tipo: implementar]
atende: D3
arquivos: `hooks/memoria-session-start.cjs`, `scripts/memoria.cjs`, `hooks/testa-memoria-session-start.sh`, `scripts/testa-memoria.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `  return 'AND ' + (alias || '') + 'substituida_por IS NULL';`
  para: `  return '';`
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: `testa-memoria-session-start.sh, caso "observacao substituida nao entra na disputa de vagas"`
pronto quando: num sandbox com 20 observações das quais 6 têm `substituida_por` preenchido, o payload real de `SessionStart` (`{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"<sandbox>","transcript_path":"<sandbox>/t.jsonl"}`) no stdin de `node hooks/memoria-session-start.cjs` produz um `additionalContext` em que **nenhuma** das 6 substituídas aparece e as 14 vivas aparecem — provado por `RFM_ROOT=<sandbox> printf '%s' "<payload>" | node hooks/memoria-session-start.cjs > <sandbox>/saida.json && node -e 'const fs=require("fs");const t=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).hookSpecificOutput.additionalContext;const m=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));console.log(m.substituidas.filter(c=>t.includes(c)).length, m.vivas.filter(c=>t.includes(c)).length)' <sandbox>/saida.json <sandbox>/conteudos.json` imprimindo `0 14`, e por `RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto <termo que só as substituídas contêm> --json` imprimindo `[]`. Os caminhos cobertos, um a um: as 7 consultas de `lerObservacoesComFTS`/`lerObservacoes` (recentes, casadas por FTS, os 3 ramos de recurso, `lerObservacoes` com e sem `projetosList`), a leitura de `resumos`, os dois ramos de `cmdBuscar` e a seleção de `cmdConsolidar` — todos por `filtroVivas()`, para haver um ponto único a inverter

### 4. Consolidação por grupo de origem, a partir de 30 dias [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `scripts/lib/grupo-de-origem.cjs`, `scripts/testa-memoria.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `      const TETO_POR_GRUPO = 30;`
  para: `      const TETO_POR_GRUPO = 100000;`
  bateria: `bash scripts/testa-memoria.sh`
  fixture: `testa-memoria.sh, caso "grupo de 45 observacoes vira dois resumos, nao um"`
pronto quando: numa cópia do banco real em sandbox (9.827 observações com 30+ dias, 260 grupos de sessão e 98 grupos de recurso), com o mock devolvendo resumo fixo, `node scripts/memoria.cjs consolidar` grava **exatamente `TETO_GRUPOS`** resumos, **nenhum resumo mistura dois grupos**, e **nenhum grupo passa de `TETO_POR_GRUPO`** — provado por `RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs consolidar && node --experimental-sqlite -e 'const{DatabaseSync}=require("node:sqlite");const{sqlGrupoDeOrigem}=require("./scripts/lib/grupo-de-origem.cjs");const G=sqlGrupoDeOrigem();const d=new DatabaseSync(process.argv[1],{readOnly:true});const q=s=>d.prepare(s).get().n;console.log(q("SELECT COUNT(*) n FROM resumos"), q("SELECT COUNT(*) n FROM (SELECT consolidada_em FROM observacoes WHERE consolidada_em IS NOT NULL GROUP BY consolidada_em HAVING COUNT(DISTINCT ("+G+"))>1)"), q("SELECT COUNT(*) n FROM (SELECT consolidada_em FROM observacoes WHERE consolidada_em IS NOT NULL GROUP BY consolidada_em HAVING COUNT(*)>30)"))' <sandbox>/rainforest.db` imprimindo `10 0 0`; e pelo mesmo banco, **antes** desta tarefa, fazendo `consolidar` imprimir `nenhum projeto com 50+ observações de 60+ dias, nada a fazer` — a regra velha não dispara em 2026-09-18 e a nova dispara, que é o ponto do D7. `sqlGrupoDeOrigem()` devolve a sessão para `origem LIKE 'sessao:%'` e `projeto || ':' || substr(criada_em,1,10)` para o resto (ver `Q1`)

### 5. Passada de manutenção em segundo plano, uma vez por dia [tipo: implementar]
atende: D1, D5
arquivos: `scripts/memoria.cjs`, `hooks/memoria-manutencao-session-start.cjs`, `hooks/hooks.json`, `hooks/testa-memoria-manutencao.sh`
depende de: 2, 4
paralela: nao
mutacao:
  arquivo: `hooks/memoria-manutencao-session-start.cjs`
  de: `    if (e.code === 'EEXIST') process.exit(0);`
  para: `    if (false) process.exit(0);`
  bateria: `bash hooks/testa-memoria-manutencao.sh`
  fixture: `testa-memoria-manutencao.sh, caso "segunda sessao no mesmo dia nao dispara a manutencao"`
pronto quando: a trava do dia nasce **atomicamente** de `fs.openSync(trava, 'wx')` — nunca `existsSync` seguido de escrita, porque duas sessões abrem juntas —, a primeira execução grava nela o PID do filho destacado e retorna em menos de 1 s, e a segunda execução do mesmo dia não cria processo nenhum — provado por `RFM_ROOT=<sandbox> printf '%s' "<payload>" | node hooks/memoria-manutencao-session-start.cjs; echo "exit1=$?"; A=$(cat <sandbox>/manutencao-$(date +%F).lock); RFM_ROOT=<sandbox> printf '%s' "<payload>" | node hooks/memoria-manutencao-session-start.cjs; echo "exit2=$?"; B=$(cat <sandbox>/manutencao-$(date +%F).lock); echo "pid1=$A pid2=$B"` saindo `exit1=0`, `exit2=0` e `pid1` igual a `pid2` (a segunda não disparou nada); e por `RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs manutencao && cat <sandbox>/manutencao.log` trazendo a linha de `reconciliar` **antes** da de `consolidar`, com o executável resolvido por `scripts/lib/achar-executavel-claude.cjs` (o conserto do #282). Nenhum dos dois caminhos escreve fora de `<sandbox>` (regra 15)

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
  fixture: `testa-memoria-session-start.sh, caso "marca d agua parada ha 60h imprime a linha de pipeline na abertura"`
pronto quando: num sandbox cuja `marca_dagua` tenha `offset > offset_processado` e `processada_em` de 60 h atrás, o payload real de `SessionStart` no stdin produz um `additionalContext` com **uma** linha que nomeia as três coisas de que o usuário precisa para agir — que a captura está parada, **há quantas horas**, e o comando que religa (`node scripts/observar.cjs`) — e o bloco inteiro continua dentro de `TETOS.MEMORIA_MAX_BYTES` (3.000 B, que **não sobe**); com a marca em dia, a linha não aparece — provado por `RFM_ROOT=<sandbox> printf '%s' "<payload>" | node hooks/memoria-session-start.cjs | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&/60/.test(x)&&x.includes("observar.cjs"));console.log(l.length, Buffer.byteLength(t,"utf8")<=3000)})'` imprimindo `1 true` no sandbox parado e `0 true` no sandbox em dia, e por `bash scripts/testa-orcamento.sh` continuando verde

### 7. Medir o recall do FTS5 como buscador de candidatas [tipo: pesquisar]
atende: D4
arquivos: `scripts/medir-recall-reconciliacao.cjs`, `relatorios/2026-09-18-recall-fts5-reconciliacao.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: tarefa de medição — o artefato é um relatório com números, não comportamento
  do sistema. A falsificação dela é a do relatório: sem os campos e sem o número ele
  reprova na leitura, e não há linha a inverter numa bateria.
pronto quando: a medição usa um conjunto de candidatas **independente do FTS5** — senão o recall sai 100% por construção, porque a LLM só veria o que o FTS5 trouxe. A LLM recebe, embaralhadas e sem id visível, as `K_CANDIDATAS` do FTS5 **mais** as 20 observações mais recentes do mesmo `projeto` anteriores à sondada; o recall é a fração das decisões `update`/`merge` cujo alvo escolhido **estava** entre as do FTS5. Contra cópia somente-leitura do banco real, `node scripts/medir-recall-reconciliacao.cjs --amostra 200` escreve `relatorios/2026-09-18-recall-fts5-reconciliacao.md` nomeando: `amostra: 200`, `K = 5`, `independente: 20`, `recall global` com o número em %, e o recall recortado pelas duas metades do corpus bilíngue (`portugues` nas 1.375 nativas, `ingles` nas 10.092 importadas) — que é o risco que o D4 nomeia —, fechando com o `veredito` contra o limiar deste plano: **abaixo de 70% em qualquer das duas metades vira decisão de vetor no próximo design; 70% ou mais mantém FTS5 com K=5** — provado por `node scripts/medir-recall-reconciliacao.cjs --amostra 200 && node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");const campos=["amostra: 200","K = 5","independente: 20","recall global","portugues","ingles","veredito"];const faltam=campos.filter(c=>!t.includes(c));const semNumero=!/recall global[^0-9]{0,40}[0-9]+(\.[0-9]+)?\s*%/.test(t);console.log(faltam.join(",")||"nenhum", semNumero?"SEM-NUMERO":"com-numero")' relatorios/2026-09-18-recall-fts5-reconciliacao.md` imprimindo `nenhum com-numero`

### 8. Documentar o que passou a existir [tipo: docs]
atende: D3, D5, D7
arquivos: `README.md`, `scripts/esquema-memoria.sql`, `skills/rainforest-mind/references/regra-13.md`
depende de: 6, 7
paralela: nao
mutacao: n/a
  motivo: texto não tem comportamento a inverter; a falsificação é a coerência com o
  que o código faz, e é isso que o comando abaixo mede
pronto quando: os três números do README são **lidos do fonte**, não do plano — o teto por execução, o teto de grupos e a idade de consolidação do texto são os mesmos literais de `TETO_RECONCILIAR`, `TETO_GRUPOS` e `DIAS_CONSOLIDACAO` em `scripts/memoria.cjs` — provado por `node -e 'const fs=require("fs");const s=fs.readFileSync("scripts/memoria.cjs","utf8");const r=fs.readFileSync("README.md","utf8");const v=["TETO_RECONCILIAR","TETO_GRUPOS","DIAS_CONSOLIDACAO"].map(n=>(s.match(new RegExp(n+"\\s*=\\s*([0-9]+)"))||[])[1]);console.log(v.join(" "), v.every(x=>x&&r.includes(x)))'` imprimindo `200 10 30 true`; e o cabeçalho de `scripts/esquema-memoria.sql` descrevendo `substituida_por` com a prescrição do D3 — "tira da injeção e da busca, nunca apaga" — conferido por `grep -c "nunca apaga" scripts/esquema-memoria.sql` devolvendo `1` e por `bash scripts/testa-memoria.sh` continuando verde

## Em aberto para o usuário

**Q1 — as 10.092 observações importadas do claude-mem não têm sessão. Como agrupá-las
na consolidação?** O D7 decidiu "agrupa por sessão de origem", e isso só existe para
12% do acervo. ➡️ **Recomendo agrupar por `(projeto, dia de criada_em)`** — medido:
98 grupos, média 103 observações, maior 521, só 3 grupos de 1. A importação é
cronológica por projeto, então um dia dentro de um projeto é o mais perto de "um
assunto" que o dado permite, e o teto de 30 por grupo já fatia os grandes. As duas
alternativas e por que não: deixar as importadas fora da consolidação para sempre
(mantém 88% do acervo sem síntese, que é o problema que o D7 ataca), ou agrupar por
janela fixa de N observações (é o lote cronológico que o D7 acabou de rejeitar).
A tarefa 4 está escrita com a recomendação e **só ela muda** se a resposta for outra;
as tarefas 1, 2, 3 e 7 não dependem da Q1. Respondida, o D7 do design ganha a linha
do agrupamento de recurso nesta mesma branch, para o `revisar` ver design e plano
dizendo a mesma coisa.
