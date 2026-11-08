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
  `ideias` (`ideias.jsonl`), `memoria`, `web` e `doc` (seção abaixo).
- `pulado:` não vale para o `repo`: `- repo | pulado: <motivo>` é recusa, mesmo com
  motivo. Quando a busca no repo não acha nada, o resultado diz isso:
  `- repo | rg "..." scripts | nada reaproveitável`.
- Bloco só com canais `pulado:` (sem `repo` com resultado) é recusa.

## Canal `doc`

Para tarefa que escolhe ou usa API de framework ou de biblioteca de terceiro. A API sai da
página oficial da versão em uso, não da memória de treino, que pode ser de outra versão.

- Forma: `- doc | <URL http(s) da página oficial> | <o que a página diz que decide a API>`.
  A versão é a que o manifesto ou o lockfile do projeto declara, e a URL é a da doc dessa
  versão.
- Hierarquia, nesta ordem: a doc oficial; depois o changelog ou o blog oficial do projeto;
  depois padrões web (MDN, RFC); depois a tabela de compatibilidade. Stack Overflow,
  tutorial e memória de treino nunca são fonte.
- Quando a doc não cobre o ponto, o resultado começa com `não verificado:` e diz o que
  faltou. A tarefa segue, e quem revisa sabe onde olhar.
- `- doc | pulado: <motivo>` vale, como nos outros canais que não são o `repo`.
- Exceção às regras de `## Quando conta`: a linha `doc` é conferida em **qualquer** tarefa
  que a declara, de qualquer tipo, e sem git, porque decisão de API costuma editar arquivo
  que já existe. O checador confere só a forma: a consulta tem de ser só a URL, `http://` ou
  `https://` sem espaço nem texto depois. Ele não abre a URL (rede no checador quebraria no CI e offline) e não julga se
  o resultado é verdade nem se a marca `não verificado:` devia estar lá.

Exemplo:

```
- doc | https://nodejs.org/docs/latest-v22.x/api/fs.html#fsrmsyncpath-options | fs.rmSync aceita recursive e force desde a v14.14
```

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
- A linha `doc` é a exceção: conta em qualquer tarefa que a declara (`## Canal \`doc\``).

## Quem confere

`node scripts/conferir-busca.cjs plano --slug <slug>`, que o
`estado.cjs marcar --estagio plano` roda junto da cobertura. A recusa diz a tarefa, o
caminho novo que a disparou e o que falta. Sem caminho novo de código no plano, o
checador sai 0 mesmo fora de repositório git: o git só é exigido quando há candidato.
A linha `doc` inválida é recusada mesmo sem caminho novo de código e fora de git
(`## Canal \`doc\``). Fora de git com caminho novo, o checador sai 69
(`nao-verificavel:`) antes de ler a linha `doc`, e o `marcar --estagio plano` trata o 69
como recusa.

## Origem

O padrão vem do ECC `skills/search-first`, que é só prosa ("agent guidance, not an
executable setup script"). Aqui o "nada encontrado" sem canais é recusa, não atalho.

O canal `doc` enxerta o método do `source-driven-development` do
`addyosmani/agent-skills` (MIT): a hierarquia de fontes e a marca do que a doc não cobre
(lá, `UNVERIFIED`). O cache por ETag de lá ficou de fora (design `2026-11-08-busca-doc`).
