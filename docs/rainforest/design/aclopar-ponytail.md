# Design — acoplar o ponytail de verdade

**Data:** 2026-09-08
**Slug:** `aclopar-ponytail`
**Origem:** o Luís pediu reanálise de <https://github.com/dietrichgebert/ponytail>
dizendo sentir que o rainforest não tinha acoplado o repo totalmente. A análise
confirmou a sensação e deu forma a ela.

## O diagnóstico

Do ponytail entrou **uma coisa**: a escada, comprimida em
`skills/modo-dev/SKILL.md:121-142`. E comprimida com perdas — 5 degraus em vez
de 7 (sumiu "cabe em uma linha?") e sumiu o formato de saída
`[código] → skipped: [X], add when [Y]`, que é o que torna a preguiça
auditável.

Nada mais entrou. E o `modo-dev` é carregado **sob demanda**, quando o modelo
lembra — que é exatamente o modo de falha que o ponytail existe para evitar:
`ACTIVE EVERY RESPONSE. No drift back to over-building.`

O padrão do erro é o mesmo em todos os sete itens: **entrou a prosa e ficou de
fora o mecanismo.** O ponytail força seu comportamento por hook em três
eventos, valida a própria consistência em CI, e mede o próprio efeito. O
rainforest copiou dele o único pedaço que depende do modelo lembrar.

## Decisões

### 1. `SubagentStart` injeta a escada nos nove agentes

**Problema.** `grep -ril "escada\|yagni\|stdlib" agents` → zero acertos. O
`executor` (haiku) escreve a maior parte do código deste repo e nunca viu a
escada. As 17 regras chegam pelo `SessionStart`, que é *parent-thread only* e
morre na porta do subagente. O `hooks/hooks.json` registra `SessionStart`,
`PreToolUse`, `UserPromptSubmit`, `Stop`, `SessionEnd` — `SubagentStart` não
existe aqui.

O ponytail bateu no mesmo bug (issue #252, citado no código deles) e resolveu
com um hook de `SubagentStart`.

**Decisão.** Hook novo `hooks/escada-subagente.cjs`, registrado sob
`SubagentStart`, injetando a escada em **todos** os agentes.

**Detalhe que economiza uma rodada inteira,** vindo de `ponytail-runtime.js`:

> Native Claude: SessionStart accepts raw stdout, but **SubagentStart needs the
> `hookSpecificOutput` JSON form or the context is dropped.**

Ou seja, a forma da saída é obrigatoriamente
`{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: "..."}}`.
Texto cru no stdout é descartado em silêncio. É o mesmo modo de falha do
`foco-session-start.cjs` (documentado lá: 32 KB de texto cru viraram 2,2 KB),
numa porta diferente.

**Por que todos os agentes, e não só os que escrevem.** O matcher por
`agent_type` existe (o ponytail o expõe em `PONYTAIL_SUBAGENT_MATCHER`), mas
seis dos nove agentes escrevem, e os três que não escrevem — `revisor`,
`auditor-de-seguranca`, `planejador` — revisam ou desenham código, onde a
escada vale igual. Um matcher que separa dois grupos quando os dois querem a
mesma coisa é ponto de variação sem segundo caso: degrau 1 da escada.

**A fonte do texto é o `modo-dev/SKILL.md`, extraída — nunca duplicada.**
Duplicar aqui criaria exatamente o defeito que a decisão 2 existe para pegar.

### 2. Invariantes de conteúdo das 17 regras

**Correção de rota registrada.** A primeira versão desta análise disse que a
skill `ponte` e as duas CLAUDE.md de escopo usuário precisavam de trava de
deriva. **Errado, conferido:** `scripts/ponte.cjs` gera o arquivo, embute hash
de 16 caracteres do SKILL.md no bloco, e `scripts/conferir-ponte.cjs` detecta
edição manual. E `diff` entre as duas CLAUDE.md (64 linhas cada) sai **vazio** —
a deriva de 2026-08-10 foi resolvida por *remoção* (a regra saiu das duas e foi
para o plugin), não por trava. Não há trabalho ali.

O `check-rule-copies.js` do ponytail tem duas metades e a primeira análise
apontou a errada. A que importa é a outra: os `INVARIANTS`.

**Problema real.** Não é "a cópia divergiu da fonte". É **"a fonte perdeu uma
cláusula que sustentava peso e nada acusou"**. Três fatos deste repo:

- O SKILL.md das 17 regras **não chega inteiro em lugar nenhum**.
  `montarContexto` chama `extrairNucleo(filtrarRegras(skillText))`, e
  `extrairNucleo` corta cada regra na marca `↳`: **o que está depois da marca
  nunca é injetado.** Uma reescrita que empurre uma cláusula para depois da
  marca a apaga da sessão em silêncio.
- Já caiu uma vez, em escala: em 2026-08-10, 50 de 50 sessões receberam 2,2 KB
  de 32 KB e **as regras 4 a 17 não chegaram a sessão nenhuma**. Ninguém
  percebeu por conta própria.
- Cada regra tem **dois** textos — o núcleo no SKILL.md e a elaboração em
  `references/regra-<n>.md`. Esse par é o análogo exato de SKILL.md/AGENTS.md
  no ponytail, e nada garante que continuem dizendo a mesma coisa.

**Decisão.** `skills/rainforest-mind/invariantes.json` (declarativo) +
`scripts/conferir-invariantes.cjs`, ao lado de `scripts/medir-skill.cjs` e
**usando o mesmo motor real** (`filtrarRegras`, `extrairNucleo`) que ele já
importa — reuso, degrau 2.

Cada invariante é `{regra, frase, onde: ["nucleo"|"skill"|"referencia"]}`. Três
checagens, e a terceira é a que não existe em lugar nenhum hoje:

1. a frase existe no `SKILL.md`;
2. a frase existe na `references/regra-<n>.md` correspondente;
3. **a frase sobrevive ao `extrairNucleo`** — isto é, chega na sessão.

Candidatos iniciais, todos load-bearing: `3.000` (regra 10 — sem o número a
regra vira "despache quando parecer grande"), `exit ≠ 0 nunca é sucesso` (12),
`nunca a `main`` (11), `printenv NOME` (15),
``pelo `ideias.cjs plantar`, nunca à mão`` (13).

**Por que não byte-comparação.** O ponytail já explica por que não, e a razão
vale igual aqui: o SKILL.md é mais longo que o núcleo por construção, então não
há igualdade a comparar. A lista de frases é canário, não equivalência.

`blocoRegras` já degrada barulhento por **tamanho**
(`TETOS.REGRAS_MIN_CHARS`). Isto acrescenta a degradação por **conteúdo**, que
falta.

### 3. Convenção de atalho deliberado + coletor de ledger

**Problema.** Existe **exatamente 1** marcador `ponytail:` no repo
(`hooks/heartbeat.cjs:75`), o `modo-dev` não documenta a convenção, e nada
coleta. Convenção adotada por imitação, sem a regra e sem o coletor — que é o
estado em que "depois" vira "nunca".

**Decisão.** Marcador em português: `atalho: <teto>, <caminho de upgrade>`. O
repo é em português e amarrar o vocabulário ao nome de um plugin de terceiro
não se paga. A única ocorrência existente migra; o coletor aceita os dois
prefixos porque é uma alternância no regex — custo zero, e não quebra o que
já está escrito.

Entregáveis: seção no `modo-dev/SKILL.md` documentando a convenção, e
`scripts/atalhos.cjs` que varre, agrupa por arquivo e marca `sem-gatilho` os
que não nomeiam condição de retorno — a tag é o ponto todo: é ela que separa
adiamento de descarte.

É o mesmo desenho do `/ideia` (gancho de retorno concreto), aplicado a código
em vez de ideia.

### 4. Skill `enxugar` — revisão contra excesso

**Problema.** O `revisar` do rainforest é correção e QA. Não existe faixa que
revise **só** over-engineering. A regra 9 barra polimento novo; nada corta o
que já está lá.

**Nome.** `poda` está ocupado — `scripts/poda.cjs` é um proxy HTTP de medição
de contexto, sem relação. `enxugar` está livre e combina com o vocabulário do
repo (`enxertar`).

**Decisão.** Uma skill, dois modos (diff e repo inteiro), tags fechadas em
português: `apagar:`, `stdlib:`, `nativo:`, `yagni:`, `encolher:`. Uma linha por
achado, ranqueado pelo maior corte, e placar `líquido: -N linhas`.

Fronteira herdada do ponytail, que é o que impede a skill de virar um segundo
`revisar`: **correção, segurança e performance estão explicitamente fora de
escopo** — vão para o `revisar` e o `auditor-de-seguranca`. E o mínimo de um
check executável (regra do próprio `modo-dev`) nunca é marcado para deleção.

Duas skills separadas (diff e repo) seriam ponto de variação sem segundo caso:
o método é o mesmo, muda a entrada.

### 5. Régua medida, com fronteira de honestidade

**Problema.** O ponytail mede o efeito da própria skill: LOC + um gate de
correção (*"proves 'less code' is not 'broken code'"*), tarefas fixas × três
modelos, resultados datados em `benchmarks/results/`. O rainforest tem a skill
`regua` (builder × crítico cego), mas **nenhuma medição de que suas regras
mudem comportamento de modelo**.

**Decisão, dimensionada para não virar teatro.** Duas entregas, e a segunda é
a barata que vale mais:

**(a) A medição.** `scripts/medir-escada.sh` roda um conjunto fixo de tarefas
pequenas contra o mesmo agente **com e sem** a injeção da decisão 1, e mede
duas coisas: linhas de código produzidas, e um **gate de correção** — um
`assert` por tarefa que falha se o código estiver errado. Sem o gate, "menos
linhas" não significa nada. Usa `hooks/lib/cli-externo.cjs` (`rodarCli`), que
já chama Codex/Gemini para o `conselho` e a `segunda-opiniao` — sem infra nova,
sem promptfoo, sem chave nova.

**(b) A fronteira de honestidade,** copiada quase literal do `ponytail-gain`
porque é uma regra que este repo precisa e não tem:

> NEVER print a per-repo savings number: the unbuilt version was never written,
> so there is no real baseline to subtract from.

Número de economia só sai de dois lugares: da bateria (a), que tem baseline
medido, ou do ledger da decisão 3, que é contagem. Nunca de estimativa sobre um
repo vivo.

### 6. Dial de intensidade + mostrador

**Problema.** O ponytail resolve o teto de injeção com um **dial**
(`lite`/`full`/`ultra` filtram o ruleset) e mostra o nível ativo na statusline.
O rainforest resolveu o mesmo teto com núcleo+índice fixo. São desenhos
diferentes para o mesmo problema, e o dial nunca foi considerado.

**Decisão.** O dial governa **a escada da decisão 1**, não as 17 regras. Três
níveis em `config.json` da pasta de dados, lidos pelo hook e filtrando o texto
injetado no subagente; o nível ativo aparece na statusline, que já existe
(`statusline/`, `scripts/instalar-statusline.sh`).

**Por que não estender o dial às 17 regras.** Elas já têm um mecanismo de
dimensionamento medido e testado (`montarContexto`, `TETOS`,
`testa-medir-injecao.sh`). Trocá-lo por outro desenho é refactor de raio grande
sem defeito que o motive — a escada é o caso novo, e é onde o dial nasce.

### 7. Crédito do ponytail no README

`modo-dev/SKILL.md:9-10` diz "procedência item a item no README". O README
lista mattpocock, karpathy, unlazy, task-observer, UditAkhourii — **ponytail
não está lá**, nem superpowers. A escada é compressão quase direta de um
projeto MIT, e o repo é público. Ponta solta de atribuição, não arrumação.

## O que fica de fora, e por quê

A abertura em leque multi-harness do ponytail (`.cursor/`, `.windsurf/`,
`.clinerules/`, `.kiro/`, MCP, extensão pi). A `ponte` já faz isso sob demanda,
que é a decisão certa para este repo.

## Nota de processo

Duas correções do Luís nesta sessão, na mesma direção, gravadas em
`plantar-virou-o-lugar-onde-ideia-morre`: os itens 3, 4 e 5 foram oferecidos
primeiro como plantio e depois como Issue, e as duas foram recusadas — *"as
ideias estão se perdendo no tempo e não fazemos nada"*. O estoque dá razão a
ele: **226 plantadas contra 126 colhidas**, a mais antiga de 2026-08-05.

Plantar serve para o que **desvia do foco ativo** (regra 6). Item de um
trabalho que o próprio usuário trouxe e quer resolve-se agora. Por isso os sete
itens estão neste design, e não em sete linhas do `ideias.jsonl`.
