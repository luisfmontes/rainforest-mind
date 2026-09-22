# Formato do manifesto de régua

O arquivo `docs/rainforest/reguas/<slug>.md` obedece um contrato de formato
que é validado por `node scripts/conferir-regua.cjs conferir --slug <slug>`.

## Cabeçalhos de mecanismo

Cada mecanismo é um cabeçalho no formato exato:

```
### M<n> <nome>
```

Onde `<n>` é um número e `<nome>` é o nome do mecanismo. O validador exige
**espaço após o número e pelo menos um caractere visível depois dele** — ou
seja, o cabeçalho tem de ter nome. São rejeitados: `### M1:` (dois-pontos no
lugar do espaço), `### M1` (nada depois do número), `### M1 ` (espaço e mais
nada) e `### M1	Nome` (tabulação em vez de espaço).

Esta frase é o contrato: o regex é `/^### M(\d+) +\S/`. Se a doc e o regex
divergirem, é defeito — documentação que promete rigor que o código não aplica
faz quem lê evitar formas que passariam, e a que promete menos deixa passar
manifesto que o loop vai recusar na hora errada.

## Seção de limite de rodadas

A linha exata:

```
## Freios
```

Define o ponto onde a régua anuncia seu teto de rodadas. Uma seção `## Freios:`,
`## freios` ou `## Freios ` (espaço no fim, invisível na tela) não passa na
validação — e a recusa nomeia a linha, em vez de dizer que a seção está ausente.

O slug casa o nome do arquivo **na caixa**: `--slug Foo` com `foo.md` no disco
sai 2 (não encontrado) em qualquer plataforma, mesmo onde o sistema de arquivos
não diferencia maiúscula de minúscula — o git diferencia, e o selo é do git.

A rejeição vale **mesmo em manifesto misto**: cinco cabeçalhos bem formados
mais um `### M6:` reprovam o arquivo inteiro. Antes o validador contava só os
que casavam e o resto sumia — cinco dentro da faixa 5-7 e exit 0, com dois
mecanismos que ele nunca viu. Cabeçalho `### M` fora do formato é recusa,
nunca omissão.

## Os quatro contratos que o conferidor aplica

O regex e a linha `## Freios` são dois deles. Os outros dois nunca estiveram
escritos, e regra que o código aplica sem estar enunciada aparece ao autor como
recusa sem causa:

3. **Quantidade: 5 a 7 mecanismos.** Menos que cinco ou mais que sete reprova.
4. **Numeração sequencial a partir de 1**, sem buraco e sem repetido. `M1 M2 M3
   M5` reprova com `mecanismos nao sequenciais ou com buraco: 1, 2, 3, 5` — o
   caso comum é apagar um mecanismo ao editar e não renumerar os de baixo.

## Confira antes de selar

`node scripts/conferir-regua.cjs validar --slug <slug>` aplica os quatro
contratos ao arquivo na árvore, **antes** do commit. É a mesma função que o
`conferir` aplica ao conteúdo selado — as duas não podem divergir.

Não é opcional na prática: a âncora é a **primeira** adição do manifesto, então
manifesto selado com erro de formato fica quebrado para sempre. Corrigir e
commitar de novo não troca a âncora, e apagar e recriar vira "adicionado mais de
uma vez" (selo ambíguo). O único conserto depois de selar é slug novo.

## O que conta como cabeçalho de mecanismo

O que o **markdown renderiza**, não o que a regex estrita casa. Toda linha com
até três espaços de recuo, de um a seis `#`, espaço e `M` seguido de dígito
é cabeçalho de mecanismo aos olhos do crítico cego — e, se não casar o formato
exato `### M<n> <descrição>`, é recusa. `###  M8` (dois espaços), ` ### M8`
(recuado) e `#### M8` reprovam o manifesto. Quatro espaços de recuo já são
bloco de código no markdown e ficam de fora.

Dentro de cerca de código (três crases ou três tis) nada conta: um `### M6
exemplo` cercado é exemplo, não mecanismo — nem soma ao teto, nem reprova.

## Até onde o formato vai

O formato é **lint para autor de boa-fé**, não fronteira contra adversário
(decidido pelo usuário em 2026-09-21). Ele cobre o que se escreve sem perceber:
cabeçalho com dois espaços, recuado ou com dois-pontos; mecanismo comentado com
`<!-- -->` (não conta); exemplo dentro de cerca, inclusive cerca aninhada —
fecha como no CommonMark, com o mesmo caractere e comprimento maior ou igual.

Não persegue construção deliberada: cabeçalho setext (`M8` sublinhado com
`---`), `> ### M8`, `- ### M8`, `### **M8**`. O crítico lê o texto cru, e não
há parser exato para "o que um LLM enxerga como mecanismo" — perseguir isso
não tem fim, e o autor do manifesto não é quem o selo vigia.
