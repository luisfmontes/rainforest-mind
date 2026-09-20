# Formato do manifesto de régua

O arquivo `docs/rainforest/reguas/<slug>.md` obedece um contrato de formato
que é validado por `node scripts/conferir-regua.cjs conferir --slug <slug>`.

## Cabeçalhos de mecanismo

Cada mecanismo é um cabeçalho no formato exato:

```
### M<n> 
```

Onde `<n>` é um número de 1 a 7. **O espaço após o número é obrigatório**; é
separador entre cabeçalho e descrição. Variações como `### M1:` ou `### M1` (sem
espaço) causam rejeição.

## Seção de limite de rodadas

A linha exata:

```
## Freios
```

Define o ponto onde a régua anuncia seu teto de rodadas. Uma seção `## Freios:`
ou `## freios` não passa na validação.
