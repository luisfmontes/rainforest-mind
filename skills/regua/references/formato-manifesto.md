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
