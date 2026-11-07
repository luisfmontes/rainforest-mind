# Design: deriva entre o design fechado e o código atual

## Objetivo
Dizer quais decisões de um design já mergeado perderam o código que as realizava. Hoje nada no
rainforest relê `docs/rainforest/design/*.md` depois do merge: um fluxo posterior pode refatorar
ou apagar o trecho que realizava a `D3` de um design antigo, e o design continua afirmando a
`D3`. Ideia `deriva-design-codigo-pos-merge`, da triagem dos salvos do Instagram
(`google/elephant-goldfish-model`, skill `egm-drift-report`, Apache-2.0; só a ideia, nada de
código). Modo autônomo ("pode fazer no modo automatico vai fazendo oq vc tiver", 2026-11-07): as
decisões marcadas **[sessão]** foram a recomendada, sem rodada, e ficam para veto no PR.

**Medida antes do design** (protótipo descartável sobre a `main` em `1d5782b9`): os 162 planos
têm 483 âncoras de mutação literais (`arquivo:` + `de:` entre crases). 433 ainda casam no código,
48 sumiram e 2 apontam para arquivo que não existe mais. Entre as que sumiram há evolução
legítima (o `"version"` de um `plugin.json`, trecho reescrito por um fluxo seguinte) e deriva de
verdade. Quem separa as duas é quem lê; o instrumento só precisa dizer onde olhar e o commit que
tirou o trecho.

## Decisões fechadas
- **D1 — Subcomando `deriva` no `conferir-fluxo.cjs`** — porquê: é o script que já lê design e plano (`extrairDecisoes`, `extrairTarefas`, `mutacao.campos`); um segundo leitor de plano divergiria dele. Forma: `node scripts/conferir-fluxo.cjs deriva [--slug <slug>] [--arquivo <caminho>]`. Sem filtro, varre todos os planos de `docs/rainforest/planos/`.
- **D2 — A âncora de uma decisão é o `de:` literal da mutação das tarefas que a atendem [sessão]** — porquê: o `de:` é o trecho que o conserto pôs no código e que a catraca provou que importa; é a única ligação entre `D<n>` e linha de código que o fluxo já grava e já verifica. `D<n>` herda as âncoras de toda tarefa com `atende: D<n>` cujo bloco `mutacao:` tem `arquivo:` e `de:` entre crases. `de:` em prosa, `mutacao: n/a` e tarefa sem bloco não são âncora: a decisão sem nenhuma âncora conta como **sem âncora medível**, lacuna declarada.
- **D3 — Três estados por âncora, e o commit que a tirou** — porquê: "sumiu" sem causa manda o leitor procurar sozinho. **Intacta**: o `de:` aparece no arquivo atual. **Sumiu**: o arquivo existe e o `de:` não aparece; a linha leva o último commit que mudou a contagem do trecho naquele arquivo, `git log -1 --format="%h %s" -S<de> -- <arquivo>`. **Arquivo sumiu**: o arquivo não existe; a linha leva o último commit que tocou o caminho, `git log -1 --format="%h %s" -- <arquivo>`. Sem commit achado (histórico raso, renome), a linha diz `commit não achado`.
- **D4 — Saída: só o que perdeu âncora, mais um placar** — porquê: 90% das âncoras estão intactas, e listá-las enterraria as 50 que importam. Uma linha por âncora perdida, agrupada por design, no formato `<slug> <D…>: <arquivo> — sumiu em <hash> <assunto>` (ou `— arquivo sumiu em …`); quando a mesma âncora atende várias decisões, elas saem juntas (`D1, D3`). Depois, o placar: `decisões: <n> com âncora (<i> intactas, <p> com âncora perdida), <s> sem âncora medível`. Com `--slug` ou `--arquivo`, o placar só conta o que o filtro selecionou. Exit 0 sempre que leu; exit 1 só por uso errado (slug sem plano, opção desconhecida). É relatório, não trava.
- **D5 — `--arquivo` responde "que decisões moram aqui"** — porquê: o uso que paga o custo é antes de mexer num arquivo, não auditoria geral. Com `--arquivo <caminho>`, só entram as âncoras daquele arquivo, e a saída lista também as intactas (`<slug> <D…>: intacta`), porque a pergunta é o que este arquivo ainda carrega. O `brainstorm` manda rodar `deriva --arquivo` para cada arquivo que a demanda vai tocar, antes da primeira rodada de perguntas, e ler o design de cada decisão listada.
- **D6 — Versão MINOR, com README e CHANGELOG** — porquê: subcomando novo é capacidade nova. Se o PR #657 (2.7.0) for mergeado antes, esta é a 2.8.0; o bump fica na última tarefa, depois de trazer a `main`.

## Avaliado e descartado
- Âncora por nome de arquivo do `arquivos:` da tarefa: arquivo que existe não diz que a decisão continua no código, e quase todo arquivo continua existindo.
- Ler o texto da `D<n>` e procurar no código com um agente: caro, não determinístico, e repete o que o leitor humano faz melhor com a lista na mão.
- Barrar o PR quando uma âncora some: âncora some legitimamente quando um fluxo seguinte reescreve o trecho. Barrar transformaria evolução em atrito.
- Gravar a âncora nova quando um fluxo reescreve o trecho: exigiria editar plano antigo, que é registro histórico.

## Fora de escopo
- Planos anteriores à regra do `de:` literal (#281), cujas âncoras são prosa: entram no placar como sem âncora medível, sem reescrita.
- Renome de arquivo seguido (`--follow`): o caminho do plano é o que vale; renome aparece como `arquivo sumiu`.

## Crédito
A ideia de confrontar design com código depois do merge vem da skill `egm-drift-report` do
`google/elephant-goldfish-model` (Apache-2.0). Nada do código dele é copiado; o mecanismo daqui
(âncora pelo `de:` da mutação e `git log -S`) é próprio.

## Varredura
docs/rainforest/varredura/2026-11-07-deriva-design.txt — nenhuma Issue casa "deriva" ou "drift"; as
que casam "âncora" falam de outras âncoras (catraca de mutação #254 e #215, régua do batedor #93). Os PRs que casam "deriva" falam de outra coisa
(home derivado #164, README #154, semear #67, memória #49, decisões pendentes #62, release #129).
Nenhuma branch. O `conferir-fluxo.cjs` já exporta `extrairTarefas` e lê `mutacao.campos`, que o
protótipo usou.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** (D2) ficam para veto no PR.
