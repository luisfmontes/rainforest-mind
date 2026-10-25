# Plano: Apoio ao dev, lote 4

Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-4.md

## O que não pode quebrar
- `buscar` sem `--texto` mantém a ordem de hoje (mais recente primeiro); `buscar --texto` com um termo só mantém a ordem bm25 de hoje (`scripts/testa-memoria.sh`, caso "buscar --texto ordena por bm25").
- `buscar --json` continua devolvendo `conteudo` inteiro; `[]` no vazio (`scripts/testa-memoria-vazio-explicado.sh`).
- Banco já gravado abre sem rebuild: colunas novas entram por `adicionarColunaSeFaltar` (`scripts/memoria.cjs:353`) e linha antiga sem o valor novo segue servida como hoje (`scripts/testa-memoria-degradacao.sh`, `scripts/testa-memoria-somente-leitura.sh`).
- A abertura continua dentro do teto de 3.000 B e com a moldura do lote 1 (`hooks/testa-memoria-session-start.sh`, `scripts/testa-memoria-injecao-segura.sh`).
- O `utilidade --relatorio` mantém as linhas de hoje; a faixa de posição se soma (`scripts/testa-utilidade.sh`, `scripts/testa-utilidade-canais.sh`).

## Tarefas

### 1. Busca com trecho e proximidade [tipo: implementar]
atende: D2, D3
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria-proximidade.sh`
depende de: nenhuma
busca:
- repo | grep -n "ORDEM_BUSCA_TEXTO\|snippet(" scripts/memoria.cjs | memoria.cjs:961 ordena só por bm25 e não há snippet(); a saída humana corta 100 caracteres em :1127
- livro | context-mode store.ts:263-348 | rerank por proximidade sobre top-N do bm25
desfecho: estender
prova: `bash scripts/testa-memoria-proximidade.sh`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: const prox = janela === null ? 0 : 1 / (1 + janela / termos.length);
  para: const prox = 0;
  bateria: `bash scripts/testa-memoria-proximidade.sh`
  fixture: testa-memoria-proximidade.sh, caso "termos juntos vêm antes de termos espalhados com bm25 parecido"
pronto quando: num banco temporário (isolado como `scripts/testa-memoria.sh` faz: `export RFM_ROOT=<caixa mktemp>`, banco em `$RFM_ROOT/rainforest.db`) com a observação A contendo "deploy do servidor falhou" e a observação B, mais nova, contendo "deploy" no começo e "servidor" 40 palavras depois, `node scripts/memoria.cjs buscar --texto "deploy servidor"` lista A antes de B; com `--texto "deploy"` (um termo) a ordem é a do bm25 de hoje; a saída humana de cada linha mostra o trecho com o termo entre `[` e `]` (ex.: `[deploy]`) mesmo quando o termo está depois do caractere 100; `--json` traz o campo `trecho` e mantém `conteudo` inteiro; `--limite 1` devolve A (o corte vem depois do rerank); `--limite 0` continua saindo `(nenhum resultado — --limite 0)` (D7 do lote 2, `memoria.cjs:1106`) e `--json` com `--limite 0` continua `[]` — provado por `bash scripts/testa-memoria-proximidade.sh`, e `bash scripts/testa-memoria.sh` e `bash scripts/testa-memoria-vazio-explicado.sh` seguem verdes. A forma do cálculo é a linha do `de:` (`janela` = menor intervalo de tokens que contém todos os termos distintos, `null` quando falta algum ou há um termo só; `termos` = termos distintos da consulta).

### 2. Resumo invalidado em cascata [tipo: implementar]
atende: D2, D4
arquivos: `scripts/esquema-memoria.sql`, `scripts/memoria.cjs`, `hooks/memoria-session-start.cjs`, `scripts/testa-memoria-cascata.sh`
depende de: 1
busca:
- repo | grep -n "consolidada_em\|substituida_por" scripts/memoria.cjs hooks/memoria-session-start.cjs | consolidarAtomico grava o mesmo instante em resumos.criada_em e observacoes.consolidada_em (memoria.cjs:1589-1608); buscarResumosRecentes (memoria-session-start.cjs:371) não olha nada disso
- livro | agentmemory cascade.ts | superada marca stale o que foi derivado dela
desfecho: estender
prova: `bash scripts/testa-memoria-cascata.sh`
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: const filtroInvalidado = temInvalidado ? 'AND invalidado_em IS NULL' : '';
  para: const filtroInvalidado = '';
  bateria: `bash scripts/testa-memoria-cascata.sh`
  fixture: testa-memoria-cascata.sh, caso "resumo de observação superada não entra na abertura"
pronto quando: num banco temporário (isolado como `scripts/testa-memoria.sh` faz: `export RFM_ROOT=<caixa mktemp>`, banco em `$RFM_ROOT/rainforest.db`) com quatro observações do projeto P consolidadas no resumo R (mesmo `consolidada_em` = `R.criada_em`) e oito consolidadas no resumo R3, aplicar ao reconciliar uma decisão `update` que marca `substituida_por` numa observação de R (1/4 = limiar `LIMIAR_INVALIDA_RESUMO = 0.25`) grava `invalidado_em` em R; com oito observações em R3 e uma só superada (1/8), R3 fica sem `invalidado_em`; a abertura (`buscarResumosRecentes`, chamada como a bateria `hooks/testa-memoria-session-start.sh` chama) deixa de devolver R e continua devolvendo outro resumo R2 sem observação superada; um banco criado pelo esquema antigo (sem a coluna) abre, ganha `invalidado_em` pela migração e serve os resumos como hoje; a abertura num banco sem a coluna (somente leitura) não quebra — por isso o filtro só entra quando a coluna existe (`temInvalidado`) — provado por `bash scripts/testa-memoria-cascata.sh`, e `bash scripts/testa-memoria-reconciliar.sh` e `bash hooks/testa-memoria-session-start.sh` seguem verdes.

### 3. Posição servida no uso [tipo: implementar]
atende: D2, D5
arquivos: `scripts/esquema-memoria.sql`, `scripts/memoria.cjs`, `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade-posicao.sh`, `scripts/testa-utilidade.sh`
depende de: 2
busca:
- repo | grep -n "function gravarUso\|function pontuarSessao" scripts/lib/utilidade.cjs | uso_memoria não tem posição (esquema-memoria.sql:101-110); pontuarSessao reordena por canal (utilidade.cjs:643) e perde a ordem do bloco
- livro | ideia memoria-recall-log-com-rank-servido | registrar o rank servido para medir utilidade por posição
desfecho: estender
prova: `bash scripts/testa-utilidade-posicao.sh`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: posicao: indice + 1,
  para: posicao: null,
  bateria: `bash scripts/testa-utilidade-posicao.sh`
  fixture: testa-utilidade-posicao.sh, caso "a terceira linha do bloco grava posicao 3"
pronto quando: com um transcrito temporário cuja abertura serviu três memórias (ids X, Y, Z, nessa ordem no bloco), pontuar a sessão grava `uso_memoria.posicao` 1, 2 e 3 para X, Y e Z; memória do canal assunto ganha a posição dentro do bloco dela; linha antiga (gravada antes da migração) fica com `posicao` nula e o relatório não quebra; `node scripts/memoria.cjs utilidade --relatorio` ganha a nota média por faixa (1–3, 4–7, 8+) e mantém as linhas de hoje — provado por `bash scripts/testa-utilidade-posicao.sh`, e `bash scripts/testa-utilidade.sh` e `bash scripts/testa-utilidade-canais.sh` seguem verdes (a asserção D10 de `testa-utilidade.sh`, lista exata de colunas sem texto livre, passa a incluir `posicao`, que é INTEGER). A forma é a linha do `de:` (o índice é a ordem em que `extrairLinhasServidas` leu o bloco).

### 4. Versão 1.78.0, CHANGELOG e README [tipo: docs]
atende: D1, D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3
mutacao: n/a
  motivo: metadado de versão e documentação, sem comportamento a inverter
pronto quando: com o diff real das tarefas 1 a 3, os dois `plugin.json` dizem `1.78.0`, o badge do README diz 1.78.0, o CHANGELOG tem a entrada `1.78.0 — 2026-10-25` com uma linha por decisão entregue (D3 a D5) citando o `arquivo:linha` do furo, e o README documenta o trecho e a proximidade do `buscar`, a invalidação de resumo e a posição no relatório de utilidade onde documenta os vizinhos — provado por `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(require('./'+f).version)"` devolvendo `1.78.0` duas vezes e pela leitura do revisor casando cada linha do CHANGELOG com o diff.
