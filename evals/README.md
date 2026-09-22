# Eval de gatilho — issue #302

Suíte de `claude plugin eval` com um caso por par de colisão da tabela da
issue #302. Mede se o pedido terso da tabela aciona a skill dona via
`Skill` tool, se a skill vizinha fica de fora, e se a resposta segue o
método da dona — nos dois braços (`with` = com o plugin, `without` =
baseline sem plugin, via `--ablation with-without`, ligado por default
porque o alvo `.` resolve o plugin `rainforest-mind`).

Rodar:

```
claude plugin eval . --trust-plugin --no-publish --runs 1 --max-cost-usd 10
```

## 1. Formato descoberto (não documentado em lugar nenhum além do `--help`)

`claude plugin eval init --bare <nome>` gera **dois arquivos**
(`prompt.md` + `graders/criteria.md`), não `case.yaml`:

```
$ claude plugin eval init --bare teste-formato --eval-dir scratch-eval-init
Created scratch-eval-init\teste-formato\prompt.md and scratch-eval-init\teste-formato\graders\criteria.md
```

`prompt.md`:
```yaml
---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

TODO: describe what the agent should do
```

`graders/criteria.md`:
```yaml
---
type: llm
weight: 1
---

TODO: describe what a successful response looks like
```

O `--help` do comando principal já avisa que o loader aceita **os dois
formatos** — `<eval dir>/**/case.yaml` OU `prompt.md + graders/*.md` — e o
briefing pediu especificamente `case.yaml`. Como `--bare` não cobre esse
formato, o schema de `case.yaml` foi reconstruído a partir das mensagens
de erro e do schema Zod embutidos no binário (`claude.exe`, strings
`invalid case.yaml:`, `missing required field schema_version`, e a
definição `Fc=f(()=>tt({schema_version:...}))` com a união de graders
`Mc()`), não documentação — está anotado aqui porque não tem onde mais
consultar:

```
schema_version: string obrigatório (ex. "1.0")
name: string (min 1)
description?: string
tags?: string[]
context?: { scaffold_script?, history_file?, add_dirs?: string[] }
execution:
  prompt?: string
  max_turns?: int (default 10, máx 200)
  timeout_seconds?: int (default 300, máx 3600)
  model?, allowed_tools?: string[], append_system_prompt?, env?
runs?: int (default 3, máx 50)
graders: array (mín 1), nomes únicos, união por `type`:
  - regex: {name, target, pattern, flags?, match?, weight?, arm?}
  - tool_order: {name, before, after, weight?, arm?}
  - tool_used: {name, tool, input_match?, min?, max?, weight?, arm?}
  - file_exists: {name, path, exists?, weight?, arm?}
  - llm: {name, criteria, focus?, weight?, arm?}
  - baseline: {name, baseline_file, criteria, weight?, arm?}
expected_outcome?: string
```

`arm` só aceita `with-only | both` (omitido = o runner decide; para
`tool_used` com `tool: Skill` isso vira indicador *display-only*, fora do
score — confirmado batendo o JSON de uma rodada de teste: com `arm`
omitido, `scored: false`/`withOnly: true`; com `arm: both`, `scored: true`
nos dois braços). `input_match` é regex JS testada contra o JSON
stringificado do input da chamada (`new RegExp(input_match).test(inputText)`),
não string exata.

**Nome real que o grader vê** (pedido explícito do briefing): o Skill tool
grava `input.skill` como `"rainforest-mind:<nome-da-skill>"` — confirmado
empiricamente numa rodada de validação durante a autoria (fora da rodada
oficial, arquivo já descartado, evidência colada aqui):
`aciona-limpar` com `input_match: "rainforest-mind:limpar"` deu
`Skill called 1x (expected 1..∞)`, ou seja, casou de verdade contra uma
chamada real do tool. `divergir` usa negative lookahead
(`rainforest-mind:divergir(?!-frames)`) porque o plugin também expõe
`rainforest-mind:divergir-frames` (subskill que `divergir` invoca por
dentro) e um match solto de substring pegaria os dois.

## 2. Desenho de cada caso

Por par: `execution.prompt` é o pedido **literal** da tabela da #302 (não
alterado para "ajudar" a acionar). `allowed_tools: [Skill, Read, Glob,
Grep]` — sem `Bash`/`Write`/`Edit` porque são *gated tools*: mesmo
listados em `execution.allowed_tools` do case, só são concedidos de
verdade com `--allow-tools` na linha de comando do operador, que o
comando exigido pelo critério T5 não passa (confirmado rodando com e sem
`Bash` na lista: com `Bash` listado mas sem `--allow-tools`, o próprio
agente relatou "esta sessão não tem Bash" na resposta). Por isso os
grader `llm` de outcome foram escritos para aceitar uma resposta que só
pede mais contexto ou relata falta de ferramenta, desde que o
*enquadramento* seja o da skill dona.

Graders por caso:
- `aciona-<dona>` (`tool_used`, `tool: Skill`, `input_match` no nome da
  dona, **`arm: both`**) — indicador de disparo, e **contando para o
  score** (ver "achado 1" abaixo — sem isso a mutação não sabe falhar).
- `nao-aciona-<vizinha>` (`tool_used`, `min: 0, max: 0, arm: both`) — um
  por vizinha (2 no par revisar×enxugar/verificar).
- `resposta-segue-metodo-<dona>` (`llm`) — grader de outcome (exigido: um
  caso não pode ter só `tool_used`).

## 3. Rodada de medição (comando literal do critério T5)

```
claude plugin eval . --trust-plugin --no-publish --runs 1 --max-cost-usd 10
```

Saída: `Ablation: 2 arms × 7 cases (14 runs)`. Os 7 casos apareceram, o
braço baseline rodou para todos, **nenhum `skipped`**. Exit 1 (score abaixo
do threshold 1.0 no braço `with`, esperado — ver achado 1).
`aggregate-result.json` em
`evals/results/2026-09-22T13-07-36-435Z/aggregate-result.json`
(`evals/results/` não é commitado — entrou no `.gitignore`).

| Caso | with | without | Δ | custo | `aciona-<dona>` disparou? |
|---|---|---|---|---|---|
| gatilho-arqueologia-vs-analisar | 0.67 | 0.33 | +0.33 | $0.31 | não (0x) |
| gatilho-depurar-vs-executar | 0.67 | 0.67 | 0.00 | $0.30 | não (0x) |
| gatilho-divergir-vs-brainstorm | 0.33 | 0.33 | 0.00 | $0.25 | não (0x) |
| gatilho-enxugar-vs-revisar | 0.33 | 0.33 | 0.00 | $0.45 | não (0x) |
| gatilho-limpar-vs-fechar | 0.33 | 0.33 | 0.00 | $0.38 | não (0x) |
| gatilho-revisar-vs-enxugar-verificar | 0.50 | 0.50 | 0.00 | $0.38 | não (0x) |
| gatilho-verificar-vs-revisar | 0.33 | 0.33 | 0.00 | $0.34 | não (0x) |

Custo total da rodada: **US$ 2,4196105** (`costUsd` do
`aggregate-result.json`), `partial: false`. `casesPassed: 0/7`,
`overallScore: 0.452`, `meanDelta: +0.048`.

Em todos os 7 casos, `nao-aciona-<vizinha>` passou (0x, como esperado —
nenhuma skill disparou, então a vizinha também não). `resposta-segue-
metodo-<dona>` passou só em arqueologia (with) e depurar (with+without).

### Achado 1 — nenhuma skill disparou nesta rodada (n=1)

Com `--runs 1`, **nenhum dos 7 pedidos literais da tabela acionou a skill
dona via `Skill` tool**, no braço `with`. Isso é o achado central desta
rodada, registrado como está — não maquiado:

- Numa rodada de validação isolada durante a autoria (fora do agregado
  oficial), o mesmíssimo par `limpar`/`"limpa o rastro"` **disparou 1x**
  com o mesmo prompt e o mesmo `allowed_tools`. Ou seja, o mecanismo
  dispara — só não com confiabilidade em `n=1`.
- O texto da resposta, quando não dispara, costuma nomear a skill
  certa em prosa ("o caminho é `depurar`") sem chamar o tool — o modelo
  reconhece a skill mas trata sandbox vazia (sem repositório, sem
  arquivo) como "nada para agir agora" e pergunta contexto em vez de
  invocar.
- O próprio texto de ajuda do `claude plugin eval` embute uma regra dura
  para quem autora eval: `runs: 3` como **mínimo não-negociável**,
  justamente porque disparo de skill é estocástico. O critério T5 manda
  `--runs 1` por custo; esta rodada mede exatamente o que isso custa em
  confiabilidade — o resultado não dá para generalizar como "a skill não
  dispara", só como "não disparou nesta amostra de 1".

**Consequência para a leitura da tabela abaixo**: como `aciona-<dona>`
nunca passou no braço `with`, o **Δ não mede se a skill acrescenta valor**
— mede variância de julgamento do LLM-judge entre duas respostas onde a
skill nunca foi de fato usada em nenhum dos dois braços. Rotular isso de
"peso morto" seria factualmente errado (a skill não chegou a ser testada);
rotular de "acrescenta" também. Por isso a coluna "veredito" abaixo é
**indeterminado** para os 7, e não "peso morto".

## 4. Por skill: acrescenta / peso morto / indeterminado

| Skill dona | Disparou (n=1, with)? | Δ outcome | Veredito |
|---|---|---|---|
| arqueologia | não | +0.33 | indeterminado — skill nunca invocada em nenhum braço; Δ é ruído de julgamento |
| depurar | não | 0.00 | indeterminado — idem |
| divergir | não | 0.00 | indeterminado — idem |
| enxugar | não | 0.00 | indeterminado — idem |
| limpar | não (nesta rodada; 1x numa rodada de validação anterior) | 0.00 | indeterminado — idem |
| revisar | não | 0.00 | indeterminado — idem |
| verificar | não | 0.00 | indeterminado — idem |

Nenhuma das 7 skills pôde ser classificada como "acrescenta" ou "peso
morto" nesta rodada porque nenhuma disparou no braço `with`. O `Δ` de
`arqueologia` (+0.33) vem do `llm` grader variando entre os dois braços
sem a skill ter sido chamada em nenhum dos dois — é sinal de variância de
amostra única, não de efeito do plugin.

## 5. Mutação (critério 4 da #302)

Comando literal do briefing:

```
node scripts/conferir-mutacao.cjs --raiz . --arquivo skills/depurar/SKILL.md \
  --de 'description: Use quando algo está quebrado, falhando, com erro, lento ou intermitente' \
  --para 'description: Use para formatar tabelas em markdown' \
  --bateria 'claude plugin eval . --trust-plugin --no-publish --runs 1 --max-cost-usd 3 --case "*depurar*"' \
  --timeout 900000
```

Saída (íntegra, colada):

```
--- bateria baseline (fonte íntegro) em 69644 ms ---

CASE                         WITH  W/OUT Δ      RUNS COST    NOTES
gatilho-depurar-vs-executar  0.33  0.67  -0.33  2    $0.35   aciona-depurar: Skill called 0x (expected 1..∞)

1 case(s) · mean Δ -0.33 · 68s · $0.35
...
RECUSADO: baseline NAO-VERDE (exit 1).
  A bateria não sai 0 no fonte íntegro. Qualquer mutação pode deixá-la
  vermelha por motivo diverso do comportamento que você quer medir.
```

**Exit 4** (`não dá para medir — baseline não-verde`). Consistente com a
contingência já prevista no briefing ("se o caso depurar já falhar no
fonte íntegro, a catraca dá exit 4 — relate, não force"): nesta rodada,
`aciona-depurar` não disparou (mesmo padrão do achado 1) e o outcome
`llm` votou `FAIL FAIL PASS` no braço `with` — o caso não fecha 1.0 nem
antes de mutar a description, então a catraca corretamente recusa medir
o efeito da mutação (não dá pra saber se uma bateria vermelha
pós-mutação seria por causa da mutação ou pela mesma instabilidade que já
reprovava o fonte íntegro). Não forcei nova tentativa — o comando não foi
repetido, por instrução explícita de custo ("não rode de novo sem
necessidade").

Nota de leitura do `--de`/`--para`: a mutação troca só a primeira frase
da description (`Use quando algo está quebrado...` → `Use para formatar
tabelas em markdown`); o resto da linha continua falando de bug
("regressão de performance, comportamento que não reproduz..."). Isso é
premissa do briefing, não corrigida aqui — mas o exit 4 chegou antes de
essa mutação ter qualquer chance de ser aplicada (o script mutation nunca
roda a segunda bateria quando a baseline já reprova).

## 6. Limitações conhecidas (não confirmadas / fora do escopo desta rodada)

- **`n=1` por caso**: `--runs 1` foi mandato do briefing por custo. O
  achado 1 mostra que isso deixa o sinal de disparo abaixo do ruído — uma
  rodada com `--runs 3` (o mínimo que a própria ferramenta recomenda)
  custaria ~3x mais e teria mais chance de separar "não dispara nunca" de
  "dispara, mas não sempre".
- **Sandbox vazia**: `execution.context.add_dirs` só pode apontar para
  dentro da pasta do caso ou do plugin sob teste (não para o repo real,
  nem para `.git`) — não criei fixtures dentro de cada `evals/gatilho-*/`
  porque isso mudaria o pedido testado de "pedido terso cru" (o que a
  tabela da #302 pede) para "pedido terso com uma prova de contexto
  desenhada pra facilitar o disparo", o que o briefing veta
  explicitamente ("não maquie o pedido para passar"). Fica registrado
  como fator ambiental que pesa contra o disparo, não como algo corrigido
  aqui.
- **CI (critério 3 da #302)**: esta task não conectou a suíte ao CI —
  fora do escopo do que foi pedido na tarefa 5 (que pede a suíte e a
  mutação, não a integração em pipeline).
