# Design: complexidade por função no enxugar

Origem: avaliação do `lboel/untangle` (commit `87bc00d4`, 2026-11-06), pedida para achar código
"duplicado e muito grande" no app (Flutter) e no site (Next.js). O untangle não acha duplicação nem
lê Dart; o que ele tem e o rainforest não tem é **medida de complexidade por função**. O `enxugar`
hoje só conta linhas por arquivo (`catalogo-funcoes.cjs maiores`).

O untangle é **AGPL-3.0-only** (`LICENSE:1-2`). Nada é copiado: o mecanismo é reimplementado a
partir da descrição (complexidade cognitiva no estilo Sonar e ciclomática clássica), e o crédito
fica só aqui (memória: crédito só quando copia código).

Modo: autônomo ("vai fazendo no automatico", 2026-11-06). As decisões são a recomendada de cada
ponto; o PR lista as que foram tomadas sem rodada.

## Decisões

**D1. Subcomando `complexas` no `catalogo-funcoes.cjs`, com a medida num módulo próprio.**
`node scripts/catalogo-funcoes.cjs complexas --raiz <dir> --top N` (padrão 10) usa os mesmos
arquivos e as mesmas definições do `listar` (testes e gerados fora). A medida mora em
`scripts/lib/complexidade.cjs`, função pura sobre o texto, sem dependência nova (Node puro).

**D2. É aproximação por leitura de texto, e a saída diz isso.** Não há parser de Dart em Node puro
e o plugin não traz dependência npm. Um leitor de texto acha o corpo pelo balanço de chaves,
pulando o que não é código:
- comentário `//` e `/* */`;
- string `'` e `"`, que termina no fim da linha se não fechar antes (JS e Dart não aceitam quebra
  de linha nela). Assim o apóstrofo de texto JSX (`<p>Don't</p>`) só cega o resto daquela linha;
- template literal `` ` `` com `${ }` aninhado (JS) e interpolação `${ }` em string Dart;
- string tripla `'''` e `"""` e string crua `r'...'` (Dart);
- regex literal JS (`/.../`), reconhecida quando a barra vem depois de algo que não fecha
  expressão (`(`, `,`, `=`, `:`, `[`, `!`, `&`, `|`, `?`, `{`, `}`, `;`, `return` ou começo de linha).
A última linha da saída é `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`.

**D3. Unidade medida: a definição mais externa.** O corpo vai da primeira `{` depois da assinatura
até a `}` que a fecha; sem `{` antes de um `;` (corpo de uma expressão, `=> x;`), o corpo vai até o
`;`. Definição que começa dentro do corpo de outra já medida não é medida à parte — soma na mãe
(é onde mora o inchaço do `build()` do Flutter e do callback do React). Classe não é unidade: os
métodos dela são.

**D4. Cognitiva (estilo Sonar, regras próprias):**
- `if`, `for`, `while`, `switch`, `catch` e o ternário somam `1 + profundidade`;
- `else` e `else if` somam 1, sem profundidade;
- cada troca de operador numa sequência de `&&`/`||` soma 1 (`a && b && c` = 1; `a && b || c` = 2),
  com a sequência zerada em `(`, `)`, `;`, `,`, `{` e `}`;
- profundidade = blocos abertos por estrutura de controle (`if`, `else`, `for`, `while`, `do`,
  `switch`, `try`, `catch`, `finally`) ou por closure (`{` depois de `=>` ou de `)` sem controle
  pendente) dentro do corpo. `{` de objeto literal, mapa ou classe não aprofunda.
- `?` só é ternário com espaço antes e depois: `String?`, `x?: T`, `?.` e `??` não contam.

**D5. Ciclomática clássica:** `1 +` cada `if`, `for`, `while`, `case`, `catch`, ternário, `&&` e `||`.

**D6. Saída.** Uma linha por função, da maior cognitiva para a menor (empate: ciclomática, depois
caminho e linha): `<c> cognitiva  <y> ciclomática  <arquivo>:L<linha> <nome>`, seguida das 3
maiores contribuições, recuadas: `    +3 L23 if (profundidade 2)`. Depois, o que **não foi medido**:
uma linha por linguagem sem chaves (`não medido: 12 função(ões) py — linguagem sem chaves`) e uma
por função cujo corpo não fechou (`não medido: <arquivo>:L<linha> <nome> — corpo não fechou`). O
`enxugar` não esconde a lacuna (como a escala CONFIRMADO/LACUNA da arqueologia).

**D7. No `enxugar`, é contexto, não achado.** O modo 2 roda `complexas` logo depois do `maiores`;
as funções do topo dizem onde ler primeiro. Não vira tag nem entra no `líquido:` (o mesmo
tratamento que o D10 do lgpd-e-duplicata deu ao `maiores`).

**D8. Fora deste fluxo:** a variação de complexidade no `enxugar --diff` (subiu de 8 para 19) e o
corte por limite. A variação depende desta medida e vira fluxo próprio.

**D9. Versão 2.5.0** (MINOR: subcomando novo), com README e CHANGELOG no mesmo commit.
