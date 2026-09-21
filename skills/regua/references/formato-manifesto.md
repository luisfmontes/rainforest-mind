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

Define o ponto onde a régua anuncia seu teto de rodadas. Uma seção `## Freios:`
ou `## freios` não passa na validação.

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
