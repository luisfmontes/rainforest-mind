# Eval de gatilho — issue #302

Suíte de `claude plugin eval` com 2-3 casos **positivos** e 1-2 casos
**negativos** por par de colisão da tabela da issue #302 (7 pares, 21 casos).
Redespacho da tarefa 5: a primeira tentativa (branch `worktree-agent-
a9d76e42881c581ed`, commit `b60825a7`) usava **um pedido de 2-3 palavras sem
contexto** por par ("tá quebrado", "revisa isso") e, em 7/7 casos, a skill
dona **nunca disparou** no braço `with` (n=1). Esta rodada substitui isso por
**cenários realistas de 1-3 frases**, do jeito que o Luís escreveria numa
sessão de trabalho de verdade — ver seção 2.

Rodar:

```
claude plugin eval . --trust-plugin --no-publish --runs 1 --max-cost-usd 6
```

## 1. Formato e correção sobre a tentativa anterior

O schema `case.yaml` é o mesmo já documentado na tentativa anterior (não
repetido aqui por extenso — reconstruído do Zod embutido no binário, não de
documentação pública). Duas coisas mudaram nesta rodada:

**`arm: with-only` no grader de disparo, não `arm: both`.** A tentativa
anterior usava `arm: both` no `aciona-<dona>` "para a mutação saber falhar"
(README anterior, seção 2). O briefing desta tarefa pediu explicitamente o
oposto — "Grader de disparo (`tool_used: Skill`) **só no braço with**" — e o
`--help` do comando confirma por que isso é o certo, não um detalhe estético:

> under with-without, graders marked with-only, incl. `tool_used: Skill`,
> **are a plugin-fired indicator rather than part of the score**

`arm: with-only` é o desenho correto: o indicador de disparo fica **fora do
score**, aparece só como nota ("Skill called Nx") na tabela, e o Δ mede
exclusivamente a diferença de qualidade de resposta entre braços — não
contaminado por uma assimetria estrutural entre eles (no braço `without` o
plugin nem existe, então um `aciona-<dona>` contando pro score ali seria
sempre reprovado por construção). A consequência para a mutação (critério 3)
está na seção 6.

`--case <glob>` filtra pelo campo `name` do caso (confirmado rodando
`--case "*depurar*"` e vendo só os 3 casos do par depurar aparecerem).

## 2. Desenho de cada caso

Por par: `evals/gatilho-<dona>-vs-<vizinha>-pos<n>/` (2-3, deve acionar a
dona) e `...-neg<n>/` (1-2, pedido da vizinha, deve acionar a vizinha e não a
dona). Todos os 7 casos antigos (um por par, pedido de 2-3 palavras) foram
apagados.

Cada `execution.prompt` é um cenário de 1-3 frases com contexto concreto
(sintoma, arquivo/módulo, o que a pessoa quer) — nunca um pedido solto. Isso
não é "maquiar para passar": é o pedido real que alguém escreve numa sessão
de trabalho, que é exatamente o que a issue #302 pede medir ("se a
`description` dispara nos pedidos certos"). Um pedido de duas palavras sem
contexto nenhum não testa a `description` — testa se o modelo adivinha
contexto que não foi dado, que é um teste diferente (e foi o que a tentativa
anterior mediu, sem perceber).

`allowed_tools: [Skill, Read, Glob, Grep]` — sem `Bash`/`Write`/`Edit`
(gated tools, mesma razão documentada na tentativa anterior).

Graders por caso positivo:
- `aciona-<dona>` (`tool_used`, `arm: with-only`) — indicador de disparo,
  fora do score.
- `nao-aciona-<vizinha>` (`tool_used`, `min:0 max:0`, `arm: both`) — um por
  vizinha; no par `revisar×enxugar/verificar` os positivos checam **as
  duas** vizinhas (grader extra não custa rodada nova, só mais uma asserção
  sobre o mesmo trace).
- `resposta-segue-metodo-<dona>` (`llm`) — grader de outcome opcional que
  usei em todo positivo, para medir Δ de qualidade de resposta.

Graders por caso negativo: `aciona-<vizinha>` (`with-only`) e
`nao-aciona-<dona>` (`min:0 max:0`, `both`). Sem grader `llm` — opcional, e
cortado aqui por custo (ver seção 7).

**Limitação declarada**: o par `revisar×enxugar/verificar` tem duas
vizinhas na tabela da #302, mas só escrevi **1** negativo (`-neg1`, testando
`enxugar`) — não um para cada vizinha — para caber no teto de custo total da
tarefa (US$ 10). `verificar` como vizinha de `revisar` fica coberta pelo
outro par da tabela (`verificar×revisar`, onde `verificar` é a dona e
`revisar` a vizinha), então a cobertura não é zero, mas é assimétrica: nunca
testei um pedido que devesse disparar `verificar` como vizinha de `revisar`
especificamente dentro deste par.

## 3. Rodada de calibração (par depurar×executar, antes de escrever os outros 6)

Comando exigido pela ordem de trabalho do briefing:

```
claude plugin eval . --trust-plugin --no-publish --runs 1 --case "*depurar*" --max-cost-usd 2
```

Resultado (exit 0, `partial: false`; `costUsd` do `aggregate-result.json`,
resultado salvo pelo próprio `claude plugin eval` em
`evals/results/<timestamp>/aggregate-result.json`, arredondado a 6 casas:
US$ 1,517886):

| Caso | with | without | Δ | custo | disparou (indicador)? |
|---|---|---|---|---|---|
| gatilho-depurar-vs-executar-neg1 | 1.00 | 1.00 | 0.00 | $0.37 | `aciona-executar`: **não** (0x) |
| gatilho-depurar-vs-executar-pos1 | 1.00 | 1.00 | 0.00 | $0.73 | `aciona-depurar`: **sim** (1x) |
| gatilho-depurar-vs-executar-pos2 | 1.00 | 1.00 | 0.00 | $0.43 | `aciona-depurar`: **não** (0x) |

`pos1` disparou de primeira — confirmando que o cenário realista dispara a
skill, ao contrário dos 7/7 sem disparo da tentativa anterior — então segui
para escrever os outros 6 pares em vez de investigar trace com
`--keep-temp` (a contingência do briefing só valia se **nenhum** positivo
disparasse). `pos2` não disparou nesta amostra e `neg1` não disparou o lado
`executar` — ambos registrados como achado, não descartados.

## 4. Rodada oficial (critério 1, comando literal)

```
claude plugin eval . --trust-plugin --no-publish --runs 1 --max-cost-usd 6
```

Saída (colada, íntegra):

```
Ablation: 2 arms x 21 cases (42 runs)
...
[cost ceiling $6 hit; skipping remaining cases]

CASE                                  WITH  W/OUT Delta   RUNS COST    NOTES
gatilho-arqueologia-vs-analisar-neg1  1.00  1.00  0.00    2    $0.49
gatilho-arqueologia-vs-analisar-pos1  1.00  1.00  0.00    2    $0.37
gatilho-arqueologia-vs-analisar-pos2  1.00  1.00  0.00    2    $0.37   aciona-arqueologia: Skill called 0x (expected 1..infinito)
gatilho-depurar-vs-executar-neg1      1.00  1.00  0.00    2    $0.44   aciona-executar: Skill called 0x (expected 1..infinito)
gatilho-depurar-vs-executar-pos1      1.00  1.00  0.00    2    $0.53
gatilho-depurar-vs-executar-pos2      1.00  1.00  0.00    2    $0.45
gatilho-divergir-vs-brainstorm-neg1   1.00  1.00  0.00    2    $0.50
gatilho-divergir-vs-brainstorm-pos1   0.50  1.00  -0.50   2    $0.66   timed out after 300s
gatilho-divergir-vs-brainstorm-pos2   1.00  1.00  0.00    2    $2.14   exit 1: Reached maximum number of turns (6)
gatilho-enxugar-vs-revisar-neg1       1.00  --    --      1    $0.36

10 casos * mean Delta -0.06 * 1429s * $6.31 * partial (cost ceiling hit)
[exited with code 2]
```

`costUsd` exato do `aggregate-result.json` (arredondado a 6 casas): US$
6,310947 (`"partial": true`, `"partialReason": "cost_ceiling"`).

**Critério 1 NÃO passa como está escrito.** O comando literal do critério
(`--max-cost-usd 6`, sem `--case`) só cobriu **10 dos 21 casos** antes de
bater o teto — os outros **11 ficaram `skipped`**:
`gatilho-enxugar-vs-revisar-pos1`, `-pos2`, os 3 de `limpar-vs-fechar`, os 3
de `revisar-vs-enxugar-verificar` e os 3 de `verificar-vs-revisar`. O
critério exige explicitamente "Nenhum `skipped`" — isso não foi alcançado,
registrado como está.

**Achado de custo**: o custo médio real por caso nesta rodada (cerca de
US$ 0,63, ou seja $6,31 dividido por 10) é maior que o teto assumido pelo
critério (US$ 6 para 21 casos, ou seja, cerca de US$ 0,29 por caso).
Extrapolando o custo médio observado para os 21 casos, a rodada precisaria
de cerca de **US$ 13** para não pular nenhum — quase o dobro do teto do
critério. Isso não é uma falha minha de execução: é o próprio orçamento do
critério 1, escrito antes de qualquer medição real, não fechando contra o
custo real de cenários de 1-3 frases (mais caros que o pedido de 2-3
palavras da tentativa anterior, que cabia em US$ 2,42 para os mesmos 7
pares porque quase nunca disparava a skill — disparo custa mais, como o
próprio `pos1` vs `pos2` do par depurar mostra: $0.57 quando dispara contra
$0.28 quando não, na rodada de calibração).

### Achados específicos, casos que rodaram

- **`gatilho-depurar-vs-executar-neg1`**: `aciona-executar` não disparou
  (0x) nas duas rodadas em que rodou (calibração e oficial) — o pedido de
  despachar um plano já fechado não aciona `executar` via `Skill` tool.
  Metade do trabalho do caso (não acionar `depurar`) passou; a outra
  metade (acionar `executar`) falhou nas duas vezes. Registrado como
  achado, pedido não reescrito.
- **`gatilho-arqueologia-vs-analisar-pos2`** e **`gatilho-depurar-vs-
  executar-pos2`**: dispararam de forma **inconsistente** entre a
  calibração e a rodada oficial (depurar-pos2 não disparou na calibração,
  disparou na oficial — mesma instabilidade de n=1 que a tentativa
  anterior já tinha registrado como "achado 1", agora com um positivo que
  às vezes dispara em vez de nunca disparar).
- **`gatilho-divergir-vs-brainstorm-pos1`**: a skill `divergir` **disparou**
  (`aciona-divergir`: 1x) mas o braço `with` **deu timeout em 300 segundos**
  e score caiu para 0.50 (Δ **-0.50**, pior que o baseline) — o grader
  `llm` votou reprovado nas três vezes. Ao contrário dos outros pares,
  aqui a skill disparar não foi neutro: piorou o resultado medido. Não
  investiguei a causa raiz do timeout (fora do escopo desta tarefa, que é
  escrever a suíte, não corrigir a skill) — fica registrado como achado
  para uma issue futura sobre `divergir`, não corrigido aqui.
- **`gatilho-divergir-vs-brainstorm-pos2`**: braço `with` bateu no teto de
  `max_turns: 6` (esgotou o número máximo de turnos) mas ainda assim
  pontuou 1.00 — o grader `llm` julgou a resposta parcial como aceitável.
  Braço `without` custou US$ 1,73, muito acima da média (o baseline
  raciocinou bastante sem skill nenhuma).

## 5. Por skill — acrescenta / peso morto / indeterminado / não avaliado

Só é possível avaliar os pares que rodaram nesta rodada (10 de 21 casos);
os 11 `skipped` ficam **não avaliado**.

| Skill dona | Disparou (indicador)? | Δ outcome | Veredito |
|---|---|---|---|
| arqueologia | pos1 sim, pos2 não (inconsistente) | 0.00 nos dois | peso morto — quando dispara, não muda a qualidade da resposta (baseline já entrega igual) |
| depurar | pos1 sim, pos2 sim | 0.00 nos dois | peso morto — mesma leitura |
| divergir | pos1 e pos2 sim (2/2) | pos1 **-0.50**, pos2 0.00 | indeterminado/negativo — disparo consistente, mas um dos dois casos piorou o resultado (timeout); não dá para chamar de "acrescenta" com um Δ negativo na amostra |
| enxugar | não avaliado (o único caso que rodou foi o negativo, `revisar`) | — | não avaliado — nenhum positivo de `enxugar` rodou antes do teto |
| limpar | não avaliado | — | não avaliado — todos os 3 casos ficaram `skipped` |
| revisar | não avaliado como dona (só o negativo do par `enxugar×revisar` rodou, testando `revisar` como vizinha, não como dona) | — | não avaliado |
| verificar | não avaliado | — | não avaliado — todos os 3 casos ficaram `skipped` |

Leitura de vizinha (negativos que rodaram): `analisar` disparou 1x
(`arqueologia-vs-analisar-neg1`), `brainstorm` disparou 1x
(`divergir-vs-brainstorm-neg1`), `revisar` disparou 1x
(`enxugar-vs-revisar-neg1`) — os três corretamente, contra `executar` que
não disparou (`depurar-vs-executar-neg1`).

## 6. Mutação (critério 3) — NÃO RODADA, dois bloqueios registrados

Comando do critério 3:

```
node scripts/conferir-mutacao.cjs --raiz . --arquivo skills/depurar/SKILL.md \
  --de 'description: Use quando algo está quebrado, falhando, com erro, lento ou intermitente' \
  --para 'description: Use para formatar tabelas em markdown' \
  --bateria 'claude plugin eval . --trust-plugin --no-publish --runs 3 --threshold 0.6 --max-cost-usd 5 --case "*depurar*"' \
  --timeout 1800000
```

**Não rodei este comando.** Dois motivos, os dois suficientes sozinhos:

**Bloqueio de custo.** `--runs 3 --case "*depurar*"` roda os 3 casos do par
depurar vezes 2 braços vezes 3 runs = 18 execuções por bateria, e
`conferir-mutacao.cjs` roda a bateria **duas vezes** (baseline + mutada) —
até 36 execuções. À taxa medida nesta sessão (braço `with` entre $0.25 e
$0.73, braço `without` entre $0.11 e $0.16, média perto de $0.30 por
execução), isso projeta algo entre US$ 9 e US$ 11. O orçamento restante
desta tarefa no momento em que cheguei aqui era de aproximadamente
US$ 2,17 (dez menos o gasto acumulado das duas rodadas acima) — muito
abaixo do necessário, e a própria bateria interna já tem `--max-cost-usd 5`
(metade do que projetei só para o baseline).

**Bloqueio estrutural — o próprio desenho pedido pelo briefing impede o
critério 3 de passar.** A seção 1 documentou que `arm: with-only` (pedido
explícito do briefing, "só no braço with") faz o grader `aciona-depurar`
sair do score: aparece como indicador `with-only`, fora do score, em todo
run desta sessão (confirmado no JSON e em todo trecho `aciona-depurar
[with-only, not scored]` da saída colada acima). O score de cada caso
positivo fica só com `nao-aciona-executar` (passa sempre, trivialmente —
não depende de qual skill disparou) e `resposta-segue-metodo-depurar`
(grader `llm`, que nesta sessão passou mesmo quando a skill **não
disparou** — `gatilho-depurar-vs-executar-pos2` na calibração: 0x disparo,
três votos de aprovação, score 1.00). Ou seja: mutar a `description` de
`depurar` para não falar mais de bug **não tem como derrubar o score** do
jeito que os casos estão desenhados — o único jeito de o score cair seria
o grader `llm` mudar de voto, e ele já demonstrou, nesta própria rodada,
que aprova mesmo sem a skill disparar.

Lendo `scripts/conferir-mutacao.cjs` (linhas 712 a 717): se a bateria
pós-mutação sair **verde** (código de saída 0), o script imprime
"RECUSADO: bateria VERDE com o comportamento invertido" e sai com o
**código 2** — não 0 (mutação pega o defeito) nem 4 (baseline não-verde).
Pela leitura estrutural acima, o resultado esperado se eu rodasse o
comando é o código 2, não o código 0. Não rodei para confirmar com
dinheiro porque a leitura do código mais a evidência empírica já colhida
nesta sessão (grader `llm` passando sem disparo) apontam para o mesmo
lugar, e o custo de confirmar (entre US$ 9 e US$ 11) excede o que sobrava
do orçamento.

**Critério 3: NÃO FEITO.** Não é um "quase passou" nem um código de saída
4 — é uma tensão entre dois pedidos do próprio briefing (marcar o grader
de disparo como `with-only`, e exigir que a mutação prove que a suíte sabe
falhar) que não fecha com o desenho atual. Corrigir isso — por exemplo,
adicionar um grader que dependa do disparo real de alguma forma que ainda
respeite "não contar para o score do braço `without`" — é decisão de
desenho que não me cabe tomar sozinho aqui; fica registrado para quem
revisar.

## 7. Custo total de todas as rodadas

| Rodada | Propósito | Custo |
|---|---|---|
| calibração (`depurar`, 3 casos) | ordem de trabalho do briefing, critério "confira que o positivo dispara" | US$ 1,517886 |
| oficial (critério 1, todos os 21 casos, parcial) | critério 1 | US$ 6,310947 |
| mutação (critério 3) | não rodada — ver seção 6 | US$ 0 |

**Total desta sessão (redespacho): aproximadamente US$ 7,83.** Somado à
tentativa anterior (aproximadamente US$ 3,85, README dela, seção 7): cerca
de **US$ 11,68** gastos nas duas tentativas da issue #302 até aqui. Esta
sessão sozinha ficou abaixo do teto de US$ 10 do briefing, mas acima do
checkpoint de US$ 8 — parei de rodar qualquer coisa paga assim que a
rodada oficial terminou (perto de US$ 7,83) e não tentei o critério 3 por
isso, além do bloqueio estrutural da seção 6.

## 8. Limitações conhecidas

- **11 de 21 casos nunca rodaram** nesta sessão (teto de custo do critério
  1) — `enxugar` (2 positivos), `limpar` (3), `revisar-vs-enxugar-verificar`
  (3) e `verificar` (3) ficam sem dado de disparo ou de Δ. Uma rodada
  futura com `--max-cost-usd` maior (ou sem teto) fecharia essa lacuna, mas
  isso está fora do orçamento desta tarefa.
- **`revisar×enxugar/verificar`** só testa 1 das 2 vizinhas no negativo
  (seção 2) — por orçamento, não por decisão de desenho.
- **`n=1` por caso**: mesma limitação da tentativa anterior. Os casos que
  dispararam numa rodada e não na outra (`arqueologia-pos2`,
  `depurar-pos2`) mostram que 1 amostra não separa "não dispara nunca" de
  "dispara, mas não sempre" — precisaria de `--runs 3` ou mais para isso,
  que o orçamento desta tarefa não cobre para os 21 casos.
- **`divergir` piorando com timeout** (seção 4) é um achado sobre o
  comportamento da skill em si, não sobre a eval — não investigado a
  fundo aqui, fora do escopo desta tarefa (escrever a suíte, não corrigir
  skill).
- **CI (critério 3 da issue #302 original, não o "critério 3" desta
  tarefa)**: não conectado — mesma nota da tentativa anterior, fora do
  escopo da tarefa 5.
