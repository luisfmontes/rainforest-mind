# Campo `busca:` — detalhe

Detalhe do campo `busca:` do plano. O `skills/plano/SKILL.md` diz o que é obrigatório
e quando; aqui ficam o formato da linha, o exemplo e as regras de conferência.

## Exemplo

```
busca:
- repo | rg "busca:|search-first" scripts skills | só o varrer.cjs, que olha história do repo, não reuso
- livro | vigias/livro-de-repos.md "search-first" | ECC skills/search-first é prosa sem checador
desfecho: construir
```

Nesse exemplo a consulta do `repo` tem `|` e vai entre aspas. Sem as aspas, o `|`
separaria um campo a mais e a linha ficaria sem resultado.

## Linha

- `- <canal> | <consulta> | <resultado>`, ou `- <canal> | pulado: <motivo>` quando o
  canal não se aplica.
- Campos são separados por `|` **fora de aspas duplas**. Consulta com `|` (regex do rg)
  vai entre aspas: `rg "a|b"`.
- O resultado é o último campo. Se depois da consulta não sobra resultado, a linha é
  recusada como "sem resultado".
- `pulado:` é o segundo campo e o último da linha. `- repo | pulado: sem rede | offline`
  é recusa: o `pulado:` não leva campo depois dele.

## Canal `repo`

- Obrigatório. Os outros canais sugeridos: `livro` (`vigias/livro-de-repos.md`),
  `ideias` (`ideias.jsonl`), `memoria`, `web`.
- `pulado:` não vale para o `repo`: `- repo | pulado: <motivo>` é recusa, mesmo com
  motivo. Quando a busca no repo não acha nada, o resultado diz isso:
  `- repo | rg "..." scripts | nada reaproveitável`.
- Bloco só com canais `pulado:` (sem `repo` com resultado) é recusa.

## `desfecho:`

Uma destas cinco palavras:

- `adotar`: serve como está.
- `estender`: acrescenta a algo existente.
- `compor`: junta peças existentes.
- `enxertar`: reimplementa o mecanismo de terceiro depois de lido. Trilha em
  `vigias/livro-de-repos.md`.
- `construir`: nada serve.

Outra palavra é recusa.

## Quando conta

- Tarefa `implementar` ou sem tipo, cujo `arquivos:` tem caminho que não existe no
  commit HEAD.
- Não contam: teste (`testa-*`, `test/` e `tests/` em qualquer pasta, `*.test.*`,
  `*_test.*`, `*.spec.*`), `.md` e glob. Tarefa que cria a própria bateria não paga o
  bloco.
- O caminho é conferido com `/`: `\` vira `/` antes da checagem.
- A caixa não muda: o git é sensível, então `Scripts/Existente.cjs` conta como caminho
  novo quando o arquivo está no HEAD como `scripts/existente.cjs`. Escreva o caminho
  com a caixa que o repo tem.

## Quem confere

`node scripts/conferir-busca.cjs plano --slug <slug>`, que o
`estado.cjs marcar --estagio plano` roda junto da cobertura. A recusa diz a tarefa, o
caminho novo que a disparou e o que falta. Sem caminho novo de código no plano, o
checador sai 0 mesmo fora de repositório git: o git só é exigido quando há candidato.

## Origem

O padrão vem do ECC `skills/search-first`, que é só prosa ("agent guidance, not an
executable setup script"). Aqui o "nada encontrado" sem canais é recusa, não atalho.
