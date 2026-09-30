# Plano: Enxertos: poda idempotente (strands) e impressao digital de falha (reef)

Design: docs/rainforest/design/2026-09-29-enxertos-poda-e-impressao-digital.md

## O que não pode quebrar

- O `vigias/ERROS.md` só recebe linha no fim, e só pelo `vigias/erros.ps1`. Nenhuma tarefa
  escreve nele nem altera o `erros.ps1` (D3).
- O aviso de 7 dias do `/saude` (`vigias-erros`) e a seção `ERROS DE VIGIA NAS ULTIMAS 24H`
  do `dados-batedor-repos.js` continuam saindo como hoje. A saída nova aparece **ao lado**
  delas, não no lugar.
- Ler arquivo que não existe (sem `ERROS.md`, sem log) nunca derruba o `/saude` nem o
  batedor. Arquivo ausente vira "nada a mostrar" ou "sem log" (D6), nunca exceção.
- Os logs de vigia (`vigias/log-*.txt`) estão no `.gitignore` e continuam lá. As fixtures de
  teste moram em `scripts/fixtures/`, não em `vigias/`.

## Tarefas

### 1. Lib da impressão digital e dos dois rótulos [tipo: implementar]
atende: D3, D4, D5, D6
arquivos: `scripts/lib/impressao-falha.cjs`, `scripts/testa-impressao-falha.sh`, `scripts/fixtures/impressao-falha/ERROS.md`, `scripts/fixtures/impressao-falha/log-sentinela-foco.txt`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/lib/impressao-falha.cjs`
  de: const MINIMO_OCORRENCIAS = 2;
  para: const MINIMO_OCORRENCIAS = 3;
  bateria: `bash scripts/testa-impressao-falha.sh`
  fixture: `testa-impressao-falha.sh, caso "duas-seguidas-sem-log: persistente x2"`
pronto quando: com o `vigias/ERROS.md` e o `vigias/log-sentinela-foco.txt` **reais** do checkout principal e `agora = 2026-09-30T12:00`, a lib devolve **uma** recorrência: vigia `sentinela-foco`, rótulo `intermitente`, `n = 5` e `ultima = 2026-09-25`. A falha de 29/09 (`ZipArchiveHelper`) e as linhas de agosto ficam de fora. Provado por `RFM_VIGIAS_DIR=C:/Projetos/rainforest-mind/vigias node -e "const l=require('./scripts/lib/impressao-falha.cjs');console.log(JSON.stringify(l.falhasRecorrentes(new Date('2026-09-30T12:00:00')).map(r=>[r.vigia,r.rotulo,r.n,r.ultima])))"` devolvendo `[["sentinela-foco","intermitente",5,"2026-09-25"]]`.

Contrato da lib, para as tarefas 2 e 3 não adivinharem:
- `normalizarCausa(texto)` aplica, **nesta ordem**, a mesma do `normalize_cause` do reef
  (`manifest.py:41-54`):
  1. caminho absoluto (Windows `X:\…` ou `X:/…`, e POSIX `/…`) vira `<path>`;
  2. sequência opaca longa (hex/base36 com 12+ caracteres) vira `<id>`;
  3. dígitos viram `<n>`;
  4. espaço colapsa;
  5. o texto é truncado em 200 caracteres.
- `impressao(vigia, causa)`: sha256 de `vigia + "\x1f" + normalizarCausa(causa)`, em 16
  caracteres hex.
- `const JANELA_DIAS = 30;` e `const MINIMO_OCORRENCIAS = 2;`, no topo e com esses nomes. A
  mutação da tarefa depende do texto exato.
- `classificar({ erros, logs, agora })`:
  - entrada: `erros` é o texto do `ERROS.md`; `logs` é `{ <vigia>: texto | null }`;
  - saída: `[{ vigia, causa, impressao, rotulo: 'persistente' | 'intermitente', n, desde, ultima }]`,
    com as datas em `AAAA-MM-DD`;
  - lê linhas no formato `- AAAA-MM-DD HH:MM [vigia]: motivo`, o mesmo regex do
    `errosRecentes` do `saude.cjs`;
  - uma linha `[vigia]: RESOLVIDO…` zera as impressões daquela vigia anteriores a ela;
    `[conferido na janela principal]` não zera nada (D6).
- `falhasRecorrentes(agora = new Date())` lê o `ERROS.md` e os `log-<vigia>.txt` de
  `process.env.RFM_VIGIAS_DIR`. Sem essa variável, lê de `<raiz do plugin>/vigias`.
- `formatar(r)` devolve uma linha para leitura humana, em um destes dois formatos:
  - `sentinela-foco: <causa normalizada> - intermitente x5 em 30 dias, ultima 25/09`
  - `sentinela-foco: <causa normalizada> - persistente x3 desde 21/09`

Casos obrigatórios da bateria:
- `real-30-09`: as linhas **copiadas** do ERROS.md real, com os cabeçalhos de ronda de
  setembro copiados do log real do sentinela. Resultado: intermitente x5, última 25/09.
- `duas-seguidas-sem-log`: persistente x2.
- `resolvido-da-vigia-zera`.
- `conferido-na-janela-principal-nao-zera`.
- `normalizacao-colide`: o mesmo erro, com outro caminho e outros números, dá a mesma
  impressão.
- `uma-so-nao-aparece`.
- `sem-erros-md`: devolve `[]` sem lançar exceção.

### 2. `/saude` mostra as recorrências [tipo: implementar]
atende: D7
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/saude.cjs`
  de: for (const r of falhasRecorrentes()) aviso('vigias-recorrentes', formatar(r), 'mesma causa normalizada voltou - leia vigias/ERROS.md; escreva [vigia]: RESOLVIDO quando consertar');
  para: for (const r of []) aviso('vigias-recorrentes', formatar(r), 'mesma causa normalizada voltou - leia vigias/ERROS.md; escreva [vigia]: RESOLVIDO quando consertar');
  bateria: `bash scripts/testa-saude.sh`
  fixture: `testa-saude.sh, caso novo "vigias-recorrentes com RFM_VIGIAS_DIR apontando para scripts/fixtures/impressao-falha"`
pronto quando: com `RFM_VIGIAS_DIR=C:/Projetos/rainforest-mind/vigias` (os arquivos reais), `node scripts/saude.cjs` imprime um aviso `vigias-recorrentes` cujo texto contém `intermitente x5 em 30 dias, ultima 25/09`, e o aviso `vigias-erros` continua saindo — provado por `RFM_VIGIAS_DIR=C:/Projetos/rainforest-mind/vigias node scripts/saude.cjs 2>&1 | grep -E "vigias-(recorrentes|erros)"` devolvendo as duas linhas. Superfície humana: quem lê o `/saude` precisa ver **qual vigia**, **qual falha**, **desde quando** e a ação `RESOLVIDO`. O caso da bateria confere os quatro no texto.

A linha nova entra dentro de `checarVigias()`, depois do bloco `vigias-erros`. O `require`
da lib fica no topo do arquivo.

### 3. O batedor vê as recorrências [tipo: implementar]
atende: D7
arquivos: `vigias/dados-batedor-repos.js`, `scripts/testa-dados-batedor-repos.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `vigias/dados-batedor-repos.js`
  de: falhas_recorrentes: falhasRecorrentes(),
  para: falhas_recorrentes: [],
  bateria: `bash scripts/testa-dados-batedor-repos.sh`
  fixture: `testa-dados-batedor-repos.sh, caso novo "secao FALHAS RECORRENTES com RFM_VIGIAS_DIR"`
pronto quando: com `RFM_VIGIAS_DIR=C:/Projetos/rainforest-mind/vigias`, `node vigias/dados-batedor-repos.js` imprime, logo depois da seção `ERROS DE VIGIA NAS ULTIMAS 24H`, uma seção `FALHAS RECORRENTES (30 DIAS) (1)` com a linha `intermitente x5 em 30 dias, ultima 25/09` — provado por `RFM_VIGIAS_DIR=C:/Projetos/rainforest-mind/vigias node vigias/dados-batedor-repos.js | grep -A1 "FALHAS RECORRENTES"`.

### 4. Descartar a ideia da poda, com a medição [tipo: configurar]
atende: D1, D2
arquivos: `<raiz de dados>/ideias.jsonl`
depende de: nenhuma
paralela: nao
mutacao: n/a
  motivo: é mudança de dado pelo CLI dono do arquivo (`ideias.cjs descartar`), sem código a inverter. A trava que falsifica é o próprio CLI, que recusa descarte sem `--motivo`.
pronto quando: a ideia `poda-de-resultado-com-invariante-de-convergencia`, hoje `plantada`, passa a `descartada` com um motivo que cita os números do design: 13,6% na faixa 8k-30k; 3,1% sem o Read; limiar de 10%; `updatedToolOutput` medido; `buildPreview` não idempotente — provado por `node scripts/ideias.cjs listar | grep -c "Podar saida grande"` devolvendo `0` e `node scripts/ideias.cjs listar --status descartada | grep -c "Podar saida grande"` devolvendo `1`.

Esta tarefa é feita pela janela principal, não por agente: a regra 15 proíbe agente de
escrever dado fora do worktree.
