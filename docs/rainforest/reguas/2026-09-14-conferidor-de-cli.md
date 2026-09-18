# Régua: um conferidor de CLI do rainforest-mind

**Artefato da régua:** `scripts/conferir-duplicacao.cjs` (237 linhas, na ponta de
`fluxo/guias-e-sensores`).

**Fase 0 — os três testes:**

| Teste | Veredito |
|---|---|
| **Nomeada** | passa — é um arquivo exato, não "as boas práticas" |
| **Obtível** | passa — está em disco, lado a lado com o que se compara |
| **Comparável** | passa — os dois respondem "como é um conferidor de linha de comando deste plugin", mesma linguagem, mesmo formato de saída, mesmo público |

**Para que serve este arquivo:** medir a diferença entre `haiku` e `sonnet` no
papel de *builder*, com o crítico cego fixo nos dois braços (D12 do design
`2026-09-14-guias-e-sensores.md`). O que varia é um parâmetro só.

**Imutável a partir da rodada 1.** O crítico é agente novo a cada rodada e não
tem memória da conversa: o que não estiver escrito aqui não chega nele.

---

## Os mecanismos

Sete coisas que se conferem **olhando** o arquivo. Não são rubrica, não têm
peso, não somam nota — são o que distingue um conferidor maduro deste plugin de
um script que faz a mesma coisa.

### M1 — O cabeçalho diz POR QUE existe, com um incidente datado

Não "o que faz" — isso o código diz. O bloco de topo nomeia o defeito concreto
que motivou o script, com data e medição. Na régua: a análise de 2026-09-12 de um
plugin de terceiro, em que `ch_mcp.py` era byte a byte idêntico entre duas skills
e 20 funções homônimas se repetiam.

Reprova: cabeçalho que parafraseia o nome do arquivo.

### M2 — Existe uma seção "não protege contra", e ela é específica

O arquivo declara os próprios limites em prosa que alguém consegue conferir. Na
régua: "função com nome diferente e lógica idêntica, duplicação PARCIAL (um
trecho copiado dentro de um arquivo maior), ou qualquer arquivo fora da árvore de
`--raiz`".

Reprova: ausência da seção, ou limites genéricos ("pode haver falsos positivos").

### M3 — O exit code carrega significado, e significados diferentes têm códigos diferentes

Na régua: `2` para duplicata byte a byte (certeza, vira falha) e `0` para o
inventário de homônimos (só levantamento, quem julga é quem lê) — e o cabeçalho
**explica a diferença**. Um conferidor que sai 1 para tudo obriga quem chama a
adivinhar.

Reprova: exit code único, ou códigos sem explicação de por que são distintos.

### M4 — O bloco `Uso:` mostra as invocações reais, incluindo os modos

Na régua, três linhas de uso cobrindo `--raiz`, `--json` e `--funcoes`. Quem lê
o topo do arquivo sabe rodá-lo sem ler o `main()`.

Reprova: uso ausente, ou uso que não cobre algum modo que o código aceita.

### M5 — As exclusões são explícitas e justificadas

Na régua: `.git`, `node_modules`, `fixtures`, `.claude/worktrees` e **arquivos
vazios** — este último com o motivo colado ("hash de conteúdo vazio não significa
cópia de nada"). Exclusão sem motivo é exclusão que ninguém ousa mexer.

Reprova: exclusão hardcoded sem comentário, ou nenhuma exclusão onde o domínio
claramente pede uma.

### M6 — Modo `--json` ao lado do modo humano, com o mesmo veredito

A régua tem os dois, e o exit code é o mesmo nos dois caminhos. É o que permite
outro script consumir o resultado sem parsear prosa.

Reprova: só saída humana; ou `--json` cujo exit diverge do modo humano.

### M7 — A saída humana nomeia os arquivos envolvidos, não só a contagem

Na régua: `for (const g of grupos) console.log(g.join(' == '))` — quem lê sabe
**quais** arquivos, não "2 duplicatas encontradas". Contagem sem nome obriga uma
segunda investigação para agir.

Reprova: saída que só conta, ou que exige `--json` para saber quem foi.

---

## O que NÃO entra na comparação

- Tamanho do arquivo. A régua tem 237 linhas; isso não é alvo.
- Estilo de formatação, aspas, ponto e vírgula.
- Se o artefato "funciona" — isso é a bateria que mede, não o crítico cego.
- Performance.
