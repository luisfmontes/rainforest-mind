# Design: variação de complexidade por função no `enxugar --diff`

## Objetivo
No modo 1 do `enxugar` (revisar um diff), dizer **quais funções a mudança deixou mais confusas**:
"`montarPainel` subiu de 8 para 19 de cognitiva". Hoje o `complexas` (2.5.0) só mede o repo
inteiro, num instante. É o segundo recorte da avaliação do `lboel/untangle` (fora de escopo do
design `complexidade-por-funcao`, que já previa este fluxo). Modo autônomo ("pode fazer no modo
automatico vai fazendo oq vc tiver", 2026-11-07): as decisões marcadas **[sessão]** foram a
recomendada, sem rodada, e ficam para veto no PR.

## Decisões fechadas
- **D1 — Subcomando `variacao` no `catalogo-funcoes.cjs`** — porquê: usa a mesma medida (`medirArquivo` de `scripts/lib/complexidade.cjs`), os mesmos filtros de teste e gerado e o mesmo formato de opções do `complexas`. Forma: `node scripts/catalogo-funcoes.cjs variacao [--raiz <dir>] [--base <ref>]`. Node puro, sem dependência nova.
- **D2 — Compara a base com a árvore de trabalho; a base padrão é a mesma do revisor [sessão]** — porquê: o `enxugar --diff` revisa "o que eu só adicionei", e isso inclui o que ainda não foi commitado. O lado novo é o arquivo no disco, e arquivo não rastreado (`git ls-files --others --exclude-standard`) entra como arquivo novo. O lado velho é `git show <base>:<arquivo>`. Sem `--base`, a base é `merge-base(HEAD, origin/<padrão>)`, a mesma que `baseDoDiff` (`hooks/lib/achados-revisor.cjs`) dá ao revisor, reaproveitada e não copiada. Base que não resolve é erro de uso (exit 1), com a mensagem pedindo `--base`.
- **D3 — Função tocada = a faixa dela cruza uma linha do diff** — porquê: o pedido é "só nas funções tocadas", e a medida já devolve `linha` e `fim` de cada função. As linhas vêm de `git diff -U0 --no-renames <base> -- <arquivo>`: linha adicionada ou alterada marca a função **atual** que a contém; linha removida marca a função **da base** que a contém. Remoção pura (`+N,0`) também marca a função atual que contém as linhas N e N+1, porque o corte aconteceu dentro dela. Arquivo novo marca todas as funções dele; arquivo apagado, todas as da base.
- **D4 — Pareamento por arquivo e nome; nome repetido pareia pela ordem [sessão]** — porquê: é o que a leitura de texto sabe identificar sem parser. A k-ésima `render` do arquivo na base pareia com a k-ésima no disco. Função renomeada, e função de arquivo renomeado (`--no-renames`), saem como **removida** mais **nova**: limite declarado, não erro.
- **D5 — Saída: uma linha por função tocada, com o porquê de quem subiu** — porquê: o número solto não diz o que mexer (D6 do `complexidade-por-funcao`). Forma: `<antes> → <depois> cognitiva (<±d>)  <antes> → <depois> ciclomática  <arquivo>:L<linha> <nome>`. Função nova usa `nova` no lugar do antes, e função removida usa `removida` no lugar do depois e a linha da base. Ordem: maior subida cognitiva primeiro (nova conta como subida a partir de 0, removida como descida até 0); empate pela ciclomática, depois caminho e linha. Debaixo de cada função que subiu ou é nova, as 3 maiores contribuições da versão atual, recuadas como no `complexas`. Função tocada sem variação sai com `(=)`, no fim. Depois, `não medido:` para arquivo do diff em linguagem sem chaves (contado por linguagem) e para função com corpo que não fechou, em qualquer dos dois lados (`(base)` ou `(atual)` no motivo). Sem função tocada: `nenhuma função medida tocada pelo diff`. A última linha é a mesma do `complexas`: `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`.
- **D6 — No `enxugar --diff`, é contexto, não achado** — porquê: o mesmo tratamento do D7 do `complexidade-por-funcao`. O modo 1 abre rodando `variacao`; a função que mais subiu é onde ler primeiro. Não vira tag, não entra no `líquido:`, e não há limite que reprove (exit 0 com qualquer variação; o `enxugar` lista, não barra).
- **D7 — Versão 2.7.0, com README, CHANGELOG e `skills/enxugar/SKILL.md` no mesmo PR** — porquê: subcomando novo é capacidade nova (MINOR), e o README acompanha toda entrega.

## Avaliado e descartado
- Opção `--base` no próprio `complexas`: misturaria duas saídas (ranking do repo e variação do diff) num subcomando, com regras de ordem diferentes.
- Comparar só commits (`<base>..HEAD`): perde o que ainda não foi commitado, que é justamente o caso do "o que eu só adicionei".
- Pareamento por similaridade de corpo para pegar renomeação: caro e chutado na leitura de texto; o limite fica declarado (D4).
- Detecção de renome de arquivo (`-M`): pareia caminho velho com novo, mas a soma de casos (renome com edição, cópia) não paga para uma lista de contexto.

## Fora de escopo
- Limite de subida que barra o PR (exit ≠ 0): o `enxugar` lista, não barra.
- Python e ADVPL: continuam como não medidos.
- Variação no modo 2 (repo inteiro, sem diff).

## Crédito
O mecanismo (medir antes e depois só nas funções tocadas) vem da descrição pública do
`lboel/untangle`, AGPL-3.0-only. Nada do código dele é copiado; o crédito fica aqui, conforme a
memória "crédito só quando copia código".

## Varredura
docs/rainforest/varredura/2026-11-07-complexidade-no-diff.txt — nenhuma Issue sobre o assunto; as
que casam "variacao" falam de timeout e de CI (#541, #509, #81, #153). Os PRs que casam são o
#649 (o `complexas`, 2.5.0, que pôs este recorte em "Fora de escopo") e o #651 (componentes React
no `complexas`). Nenhuma branch. O parser de `@@` existente (`linhasAdicionadas` em
`hooks/lib/achados-revisor.cjs`) só olha `<base>..HEAD` e ignora remoção pura; por isso o D3
lê o diff à parte.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** (D2, D4) ficam para veto no PR.
