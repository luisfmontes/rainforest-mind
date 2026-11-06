# Design: complexidade por função no enxugar

## Objetivo
Dizer, no modo 2 do `enxugar`, **quais funções** do app (Flutter) e do site (Next.js) são as mais
confusas, não só quais arquivos são os maiores. O `enxugar` hoje só conta linhas por arquivo
(`catalogo-funcoes.cjs maiores`). A ideia vem da avaliação do `lboel/untangle` (commit `87bc00d4`,
2026-11-06): ele não acha duplicação nem lê Dart, mas mede complexidade por função, e é isso que
falta aqui. Modo autônomo ("vai fazendo no automatico", 2026-11-06): as decisões marcadas
**[sessão]** foram a recomendada, sem rodada, e ficam para veto no PR.

## Decisões fechadas
- **D1 — Subcomando `complexas` no `catalogo-funcoes.cjs`, com a medida em `scripts/lib/complexidade.cjs`** — porquê: usa os mesmos arquivos e definições do `listar` (testes e gerados fora) e o mesmo formato de opções do `maiores`; a medida é função pura sobre o texto, testável sem repo. `node scripts/catalogo-funcoes.cjs complexas --raiz <dir> --top N` (padrão 10). Node puro, sem dependência nova.
- **D2 — É aproximação por leitura de texto, e a saída diz isso [sessão]** — porquê: não há parser de Dart em Node puro e o plugin não traz dependência npm. Um leitor de texto acha o corpo pelo balanço de chaves e pula o que não é código: comentário `//` e `/* */`; string `'` e `"`, que termina no fim da linha se não fechar antes (JS e Dart não aceitam quebra de linha nela, então o apóstrofo de texto JSX, `<p>Don't</p>`, só cega o resto daquela linha); template literal com `${ }` aninhado; interpolação `${ }` em string Dart; string tripla `'''`/`"""` e crua `r'...'` do Dart; regex literal JS, reconhecida quando a `/` vem depois de `(`, `,`, `=`, `:`, `[`, `!`, `&`, `|`, `?`, `{`, `}`, `;`, `return` ou no começo da linha, e nunca quando a `/` é seguida de `>` (fechamento `/>` de JSX). *Emenda da revisão 1:* `<` e `>` ficam fora da lista, porque a `/` de `</li>` vem depois de `<` e lida como regex engolia o resto da linha e a chave que fechava o corpo; `if`/`for`/`while`/`switch`/`catch` depois de `.` ou `?.` é chamada de método (`.catch(` de promessa), não controle; definição cujo nome não é código naquela linha (função dentro de comentário) não é unidade. A última linha da saída é `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`.
- **D3 — A unidade é a definição mais externa** — porquê: é onde mora o inchaço (o `build()` do Flutter e o callback do React). O corpo vai da primeira `{` depois da assinatura até a `}` que a fecha; sem `{` antes de um `;` (corpo de uma expressão, `=> x;`), vai até o `;`. *Emenda da revisão 1:* depois de `=>` fora de parênteses e de genérico (`Promise<() => void>` não conta), o corpo é o bloco se a seta é seguida de `{`, senão a expressão, que termina no `;` fora de parênteses, colchetes e chaves, ou na quebra de linha em que nada fica aberto e nenhuma das duas linhas emenda por operador (estilo sem ponto e vírgula). `{` de tipo literal seguida de `=>` também continua a busca (`(a): { x: T } => {`). Definição que começa dentro do corpo de outra já medida soma na mãe e não sai à parte. Classe não é unidade: os métodos dela são.
- **D4 — Cognitiva no estilo Sonar, com regras próprias** — porquê: pune aninhamento, que é o que torna a leitura difícil, e não só a contagem de ramos. `if`, `for`, `while`, `switch`, `catch` e o ternário somam `1 + profundidade`; `else` e `else if` somam 1, sem profundidade; cada troca de operador numa sequência de `&&`/`||` soma 1 (`a && b && c` = 1; `a && b || c` = 2), e a sequência zera em `(`, `)`, `;`, `,`, `{` e `}`. Profundidade = blocos abertos dentro do corpo por estrutura de controle (`if`, `else`, `for`, `while`, `do`, `switch`, `try`, `catch`, `finally`) ou por closure (`{` depois de `=>`, ou depois de `)` sem controle pendente). `{` de objeto literal, mapa ou classe não aprofunda. `?` só é ternário com espaço antes e depois: `String?`, `x?: T`, `?.` e `??` não contam.
- **D5 — Ciclomática clássica ao lado** — porquê: sai da mesma contagem quase de graça. `1 +` cada `if`, `for`, `while`, `case`, `catch`, ternário, `&&` e `||`.
- **D6 — Saída com o porquê da nota e com o que não foi medido** — porquê: um número solto não diz o que mexer, e lacuna escondida passa por "limpo". Uma linha por função, da maior cognitiva para a menor (empate: ciclomática, depois caminho e linha): `<c> cognitiva  <y> ciclomática  <arquivo>:L<linha> <nome>`, seguida das 3 maiores contribuições recuadas, `    +3 L23 if (profundidade 2)`. Depois, uma linha por linguagem sem chaves (`não medido: 12 função(ões) py — linguagem sem chaves`) e uma por função cujo corpo não fechou (`não medido: <arquivo>:L<linha> <nome> — corpo não fechou`).
- **D7 — No `enxugar`, é contexto, não achado** — porquê: é o mesmo tratamento que o D10 do `lgpd-e-duplicata` deu ao `maiores`. O modo 2 roda `complexas` logo depois do `maiores`; as funções do topo dizem onde ler primeiro, sem tag e fora do `líquido:`.
- **D8 — Nada do untangle é copiado; o crédito fica neste design** — porquê: o untangle é AGPL-3.0-only (`LICENSE:1-2` do clone), copyleft forte. O mecanismo é reimplementado a partir da descrição pública das métricas, e a memória "crédito só quando copia código" manda o crédito para o design, não para o README.
- **D9 — Versão 2.5.0, com README e CHANGELOG no mesmo commit** — porquê: subcomando novo é capacidade nova (MINOR), e o README acompanha toda entrega.

## Avaliado e descartado
- Instalar o untangle: não lê Dart (Dart só aparece como plano, `docs/BUILD_PLAN.md:577` do clone), exige build local com tree-sitter nativo, e é AGPL.
- Carregar o `typescript` do `node_modules` do repo-alvo para ter árvore exata no TS: cobre só metade (o site), cria dependência do estado do repo-alvo e dois caminhos de medida que divergem.
- Halstead, índice de manutenibilidade e manifesto feature↔código: pouco vira ação para um dev só.

## Fora de escopo
- A variação de complexidade no `enxugar --diff` ("subiu de 8 para 19"): depende desta medida e vira fluxo próprio.
- Corte por limite (exit ≠ 0 acima de N): o `enxugar` lista, não barra.
- Python e ADVPL: não têm corpo por chaves; aparecem como não medidos.

## Varredura
docs/rainforest/varredura/complexidade-por-funcao.txt — nenhuma Issue, PR ou commit sobre complexidade, cognitiva ou ciclomática; "maiores" casa só com Issues fechadas alheias (#1, #3). Confirma que a medida por função não existe no plugin.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** (D2) ficam para veto no PR.
