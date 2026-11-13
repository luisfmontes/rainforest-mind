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
- A linha `const ORCAMENTO_MS = Number(process.env.TESTADOR_ORCAMENTO_MS) || 25000;` sai de dentro de `processarMarca` e vai, com esse texto exato, para o escopo do módulo (logo antes de `async function processarMarca`). O caso 18 de `scripts/testa-observar.sh` lê essa linha pelo texto e tem de continuar achando-a.
- `processarSessao` cria, antes de qualquer marca, `const relogio = { inicio: Date.now(), orcamento: ORCAMENTO_MS };` e passa `relogio` como terceiro argumento de `processarMarca(conexao, marca, relogio)`, nos dois pontos de chamada (`--sessao` e varredura).
- Em `processarMarca`, a linha `const inicioDaPassada = Date.now();` vira exatamente `const inicioDaPassada = relogio.inicio;`. O corte entre fatias continua `if (i > 0 && decorrido > relogio.orcamento)`, com a mensagem de hoje (`orcamento de <N>ms atingido apos <i> fatia(s) de <total>; ...`) e o `break`. Depois do laço, a linha final `ok: observacao gravada em ...` continua saindo como hoje.
- `processarMarca` devolve `'orcamento'` quando parou por orçamento (o `break` acima, `tetoMs <= 0` ou chamada cortada), e o que devolve hoje nos outros casos. Para isso, uma variável `let parouPorOrcamento = false` vira `true` nesses três pontos, e o `return` do caminho de sucesso devolve `parouPorOrcamento ? 'orcamento' : <o valor de hoje>`.
- Antes de cada `chamarLLM`: `const tetoMs = relogio.orcamento - (Date.now() - relogio.inicio);`. Se `tetoMs <= 0` e `i > 0`, segue o mesmo caminho do corte entre fatias (mesma mensagem, `break`). Se `tetoMs <= 0` e `i === 0`, imprime `orcamento de <N>ms atingido antes da marca <sessao>` e devolve `'orcamento'` sem chamar.
- A chamada passa a ser `const observacao = await chamarComTeto(textoDaPassada, tetoMs);`. `chamarComTeto(texto, tetoMs)` é uma função nova de módulo. Ela faz um `Promise.race` entre `chamarLLM(texto, tetoMs + 1000)` e um timer de `tetoMs` ms que resolve o símbolo de módulo `const ESTOUROU = Symbol('estourou')`, e chama `clearTimeout` do timer num `finally`. Com `+ 1000` o timer do race sempre dispara antes do de `chamarLLM`.
- Ao receber `ESTOUROU`: imprime `orcamento de <N>ms atingido durante a fatia <i+1> (decorrido <d>ms); marca em <ultimoOffsetProcessado>`, com `<d> = Date.now() - relogio.inicio`, marca `parouPorOrcamento = true` e dá `break`, sem gravar e sem mexer na marca.
- No laço da varredura (`for (const marca of marcas)`, que passa a ser indexado), antes de abrir cada marca a partir da segunda: se `Date.now() - relogio.inicio > relogio.orcamento`, ou se a marca anterior devolveu `'orcamento'`, imprime `orcamento de <N>ms atingido; <k> marca(s) ficam para a proxima sessao`, com `k = marcas.length - idx` (as que não foram abertas), e sai do laço.
- `chamarLLM(textoDaPassada, tetoMs = 60000)`: `const timeout = Math.min(60000, tetoMs);`. O `spawn` passa a usar `timeout`, sem o `+ 5000`. `let child = null;` é declarado antes do timer, e o timer, ao estourar, faz `if (child) child.kill();` antes de resolver `null`. O caminho do dublê (`TESTADOR_CHAMAR_LLM`) não muda: quem o corta é o race.
- Bateria, no bloco do 8.c de `scripts/testa-observar.sh` (linhas ~629-675):
  - `TESTADOR_ORCAMENTO_MS=100` vira `400`, e o grep e a mensagem `orcamento de 100ms atingido` viram `400ms`. O dublê continua com 250 ms: a fatia 1 grava, a fatia 2 é cortada aos ~400 ms, e as asserções de hoje (1 ou mais observações, menos que `NUM_CHAMADAS`, marca intermediária) valem como estão.
- Bateria, caso novo 8.d logo depois do 8.c, montado como ele (`novo_sandbox`, mesmo `sgrande.jsonl`, `memoria.cjs iniciar`):
  - Copia o transcrito como `sgrande.jsonl` e `sgrande2.jsonl` e insere duas marcas em `marca_dagua` (sessões `sgrande` e `sgrande2`, `offset_processado` 0).
  - Roda com `TESTADOR_ORCAMENTO_MS=400` e o dublê de 250 ms.
  - Afirma: a saída tem `marca(s) ficam para a proxima sessao`, e exatamente uma das duas marcas termina com `offset_processado` 0. A ordem em que a varredura abre as marcas não importa, só que uma ficou intocada.
- Bateria, caso novo 8.e, montado igual com uma marca (`sgrande`):
  - Usa o dublê `duble-parado.cjs`, que espera 5000 ms e devolve um texto, com `TESTADOR_ORCAMENTO_MS=400`.
  - Afirma: a saída tem `atingido durante a fatia 1 (decorrido <d>ms)` com `<d>` menor que 1000 (extraído da saída por `sed`), há 0 observações e o `offset_processado` é 0.
  - O processo do teste fica vivo até o dublê terminar (~5 s): isso é esperado, e a medição vem do `decorrido` impresso.
- Nenhum caso novo lê o texto do fonte.

### 2. Notas e versão PATCH [tipo: docs]
atende: D1, D2
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e versão; o comportamento está na tarefa 1
pronto quando: com a versão 2.13.2 nos dois `plugin.json` e no selo do README (a `origin/main` está em 2.13.1; se outro PR subir a versão antes, vale a PATCH seguinte), o CHANGELOG ganha a entrada `## 2.13.2 — 2026-11-12` acima da atual. A entrada diz, pelo comportamento, que a captura de memória no fim da sessão passa a caber em 25 s no total, por execução e por chamada, e não cancela mais os hooks de outros plugins no fim da sessão, coerente com a D1 e a D2. Conferido por `node scripts/conferir-versao.cjs --sem-fetch` saindo 0.

Onde editar: `"version"` na linha 3 dos dois `plugin.json`; no `README.md` linha 7, a versão da URL do selo e do `alt`; no `CHANGELOG.md`, a entrada nova logo acima da primeira `## `, no estilo dela. Não edite entradas antigas.
