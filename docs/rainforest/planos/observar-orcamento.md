# Plano: observar.cjs respeita o orçamento do SessionEnd (#701)

Design: docs/rainforest/design/observar-orcamento.md

## O que não pode quebrar
- A marca d'água avança por fatia e nunca passa da última fatia gravada (D6 da #198).
- `--sessao <id>` continua processando só aquela sessão; `--seco` e `--help` não mudam.
- O padrão de 25 s e o `timeout: 30` do `hooks/hooks.json` (casos 18 a 20 de `scripts/testa-observar.sh`).

## Tarefas

### 1. Um orçamento por execução e teto por chamada [tipo: implementar]
atende: D1, D2, D3
arquivos: `scripts/observar.cjs`, `scripts/testa-observar.sh`
depende de: nenhuma
busca:
- repo | grep -n "inicioDaPassada\|ORCAMENTO_MS" scripts/observar.cjs | o relógio nasce em processarMarca (:559) e o orçamento só é lido ali (:558, :567)
desfecho: estender
mutacao:
  arquivo: `scripts/observar.cjs`
  de: `const inicioDaPassada = relogio.inicio;`
  para: `const inicioDaPassada = Date.now();`
  bateria: `bash scripts/testa-observar.sh`
  fixture: `testa-observar.sh, caso 8.d (duas marcas dividem um orçamento)`
prova: `bash scripts/testa-observar.sh`
pronto quando: com `TESTADOR_ORCAMENTO_MS=400` e `node scripts/observar.cjs` sem `--sessao`: (8.d) duas marcas pendentes de várias fatias cada e um dublê de 250 ms: a saída traz `marca(s) ficam para a proxima sessao` e a segunda marca processada fica com `offset_processado` igual ao de antes; (8.e) uma marca e um dublê que espera 5000 ms: a saída traz `atingido durante a fatia 1 (decorrido <d>ms)` com `<d>` menor que 1000, nenhuma observação gravada e `offset_processado` 0; (8.c, ajustado) dublê de 250 ms e orçamento de 400 ms numa marca: uma observação gravada, marca intermediária e `orcamento de 400ms atingido` na saída — provado por `bash scripts/testa-observar.sh` com `falhou: 0` e exit 0.

Forma prescrita:
- `processarSessao` cria, antes de qualquer marca, `const relogio = { inicio: Date.now(), orcamento: Number(process.env.TESTADOR_ORCAMENTO_MS) || 25000 }` e passa `relogio` como terceiro argumento de `processarMarca(conexao, marca, relogio)`, nos dois pontos de chamada (`--sessao` e varredura). `ORCAMENTO_MS` sai de dentro de `processarMarca` e passa a ser `relogio.orcamento`.
- Em `processarMarca`, a linha `const inicioDaPassada = Date.now();` vira exatamente `const inicioDaPassada = relogio.inicio;`. O corte entre fatias continua `if (i > 0 && decorrido > relogio.orcamento)`, com a mensagem de hoje.
- `processarMarca` devolve `'orcamento'` quando parou por orçamento (entre fatias ou durante a chamada). No laço da varredura, ao receber `'orcamento'` ou ao achar `Date.now() - relogio.inicio > relogio.orcamento` antes da próxima marca, imprime `orcamento de <N>ms atingido; <k> marca(s) ficam para a proxima sessao` (k = marcas que não foram abertas) e sai do laço.
- Antes de cada `chamarLLM`, `const tetoMs = relogio.orcamento - (Date.now() - relogio.inicio);`. Se `tetoMs <= 0`, trata como parada por orçamento sem chamar. Senão chama `chamarComTeto(textoDaPassada, tetoMs)`: um `Promise.race` entre `chamarLLM(textoDaPassada, tetoMs)` e um timer de `tetoMs` que resolve o símbolo `ESTOUROU`. Ao receber `ESTOUROU`: imprime `orcamento de <N>ms atingido durante a fatia <i> (decorrido <d>ms); marca em <offset>` e devolve `'orcamento'`, sem gravar e sem mexer na marca.
- `chamarLLM(textoDaPassada, tetoMs = 60000)`: `const timeout = Math.min(60000, tetoMs)`. O `spawn` passa a usar `timeout` (sem `+ 5000`). O timer, ao estourar, chama `child.kill()` antes de resolver `null`; para isso, `child` é declarado com `let` fora do `try`. O caminho do dublê (`TESTADOR_CHAMAR_LLM`) não muda: o corte dele é o `Promise.race`.
- Nenhum caso de teste lê o texto do fonte.

### 2. Notas e versão PATCH [tipo: docs]
atende: D1, D2
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e versão; o comportamento está na tarefa 1
pronto quando: com a versão PATCH seguinte à da `origin/main` nos dois `plugin.json` e no selo do README, o CHANGELOG ganha a entrada dela acima da atual. A entrada diz, pelo comportamento, que a captura de memória no fim da sessão passa a caber em 25 s no total, por execução e por chamada, e não cancela mais os hooks de outros plugins no fim da sessão, coerente com a D1 e a D2. Conferido por `node scripts/conferir-versao.cjs --sem-fetch` saindo 0.

Onde editar: `"version"` na linha 3 dos dois `plugin.json`; no `README.md` linha 7, a versão da URL do selo e do `alt`; no `CHANGELOG.md`, a entrada nova logo acima da primeira `## `, no estilo dela. Não edite entradas antigas.
