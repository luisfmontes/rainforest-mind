# Design: as recusas do corpo do PR dão uma receita só, a que passa

## Objetivo
O `hooks/gate-fechar-issue.cjs` tem cinco recusas sobre o corpo de `gh pr create`/`gh pr edit`
(`--body-file` com variável, `--body-file` relativo com cwd incerto, `--body-file` ilegível,
`--body` com `$(` ou crase, corpo por editor interativo). Cada uma sugere uma saída diferente, e
algumas sugerem a saída que outra recusa barra. O agente segue a sugestão, cai na recusa seguinte
e gasta várias tentativas no mesmo turno. Modo autônomo ("se tiver mais coisas pode continuar,
tem passe livre pra se auto melhorar", 2026-11-07): as decisões marcadas **[sessão]** foram a
recomendada, sem rodada, e ficam para veto no PR.

**Medida antes do design** (ideia `quebra-laco-de-falha-repetida`, script descartável sobre os
300 maiores transcritos dos últimos 30 dias): de 1279 turnos com falha de ferramenta, 48
repetiram a mesma falha 3 vezes ou mais. A maior fonte foi este gate, com 13 turnos e 42
negações. Nos quatro transcritos com 3 ou mais negações dele num turno, as tentativas não
repetem o comando: cada uma é a variante que a mensagem anterior sugeriu, e cada uma cai numa
recusa diferente.
- `95cb1278`, 6 negações: `--body` com crase ("Use --body \"texto-plano\""), `--body-file "$S/pr432.md"`
  ("variável"), `--body-file` literal apontando para o arquivo que o comando barrado ia criar
  ("não consegui ler"), de novo `--body`.
- `e117bdd8`, 3 negações: `cat > /tmp/pr.md <<EOF` e `gh` no mesmo comando (barrado), depois
  `--body-file /tmp/pr.md` duas vezes ("não consegui ler"), mas o arquivo nunca foi criado,
  porque o comando que o criaria foi barrado, e o node do gate não enxerga o `/tmp` do Git Bash.
- `40dfb6cb` e `db034fde`, a mesma escada: crase → variável → arquivo não lido.

A falha é da mensagem, não de quem tenta: não falta um contador de repetição neste gate. Quem
erra uma vez e lê a receita que passa acerta na segunda tentativa.

## Decisões fechadas
- **D1 — As cinco recusas do corpo terminam com a mesma receita [sessão]** — porquê: o agente segue a última sugestão lida, e só uma receita passa em todos os casos. Receita: gravar o corpo com a ferramenta de escrita (Write) num caminho absoluto literal (o scratchpad da sessão serve), e depois rodar, num comando que só tem o `gh`, `gh pr create ... --body-file "<caminho literal>"`. A receita diz também que comando barrado não roda nenhuma parte: o arquivo que ele criaria não existe. A recusa do `--body` com crase deixa de sugerir `--body "texto-plano"`, que não serve para corpo em markdown.
- **D2 — A recusa de arquivo ilegível diz o caminho que o gate tentou e por que falhou [sessão]** — porquê: "não consegui ler" sem caminho manda o agente adivinhar. A mensagem cita o caminho resolvido. Para `ENOENT`, diz que o arquivo não existe nesse caminho. Para caminho que começa com `/tmp/` (ou qualquer raiz POSIX que o `normalizarMsys` não converte, `/` seguido de algo que não é letra de unidade e barra), diz que o gate roda em node no Windows e não enxerga o `/tmp` do Git Bash, e que o caminho deve ser absoluto do Windows. Outro erro sai com o código (`EACCES`, `EISDIR`).
- **D3 — Versão PATCH, com CHANGELOG** — porquê: mensagem de recusa, sem contrato novo. É a 2.8.2 se o PR #662 (2.8.1) for mergeado antes; o bump fica na última tarefa, depois de trazer a `main`.

## Avaliado e descartado
- Contador de negações repetidas por sessão numa lib comum dos 20 gates: a medição mostra variantes, não o mesmo comando repetido. O defeito é o conteúdo da mensagem, e um contador só anunciaria o laço depois de ele acontecer. Fica na ideia `quebra-laco-de-falha-repetida`.
- Resolver `/tmp/...` com `cygpath` dentro do gate: um processo a mais num gate que roda em todo `gh pr`, para um caso que a receita evita.
- Deixar o gate aceitar `--body` com crase: crase dentro de aspas duplas é substituição de comando no shell, e o gate não lê o que ela produz.

## Fora de escopo
- As outras recusas do gate (Issue sem evidência, `gh pr merge` acompanhado, comando encapsulado): já dão a receita ou não apareceram em laço na medição.
- Os outros gates (portaria, fluxo sem estágio, repo alheio): apareceram em laço na medição, mas o caminho de cada um é outro. Ficam para quando a ideia for colhida.

## Varredura
docs/rainforest/varredura/2026-11-07-receita-corpo-pr.txt — as Issues que casam são consertos
anteriores do mesmo gate: `--saida` com caminho (#269), heredoc (#239, #247, #271), caminho MSYS
`/c/...` no `--body-file` (#344), variável no `--body-file` (#350). Nenhuma trata a mensagem como
escada. Memória `body-file-de-pr-em-caminho-windows`: os gates não leem `--body-file` em `/tmp` do
Git Bash nem caminho com `$`, que é o D2. O `deriva --arquivo hooks/gate-fechar-issue.cjs` lista
15 decisões, todas intactas. Nenhuma toca o texto das cinco recusas do corpo.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** (D1, D2) ficam para veto no PR.
