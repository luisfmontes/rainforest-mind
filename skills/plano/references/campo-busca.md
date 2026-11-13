# Campo `busca:` — detalhe

Detalhe do campo `busca:` do plano. O `skills/plano/SKILL.md` diz o que é obrigatório
e quando; aqui ficam o formato da linha, o exemplo e as regras de conferência.

<!-- indice -->
**Índice** — arquivo longo: quem parou no meio não leu o campo inteiro. Seções na ordem; cada item é o começo da seção, sem a marcação:

- Exemplo
- Linha
- Canal repo
- Canal catalogo
- Canal doc
- desfecho:
- Quando conta
- Quem confere
- Origem
<!-- /indice -->

## Exemplo

Tarefa que cria arquivo novo leva `repo` e `catalogo`:

```
busca:
- repo | rg "busca:|search-first" scripts skills | só o varrer.cjs, que olha história do repo, não reuso
- catalogo | listar --raiz scripts | nada equivalente
- livro | vigias/livro-de-repos.md "search-first" | ECC skills/search-first é prosa sem checador
desfecho: construir
```

Nesse exemplo a consulta do `repo` tem `|` e vai entre aspas. Sem as aspas, o `|`
separaria um campo a mais e a linha ficaria sem resultado.

Tarefa que edita arquivo existente (`arquivos: scripts/conferir-busca.cjs`) não leva
`repo`, e o `catalogo` aponta a função que ela reaproveita:

```
busca:
- catalogo | listar --raiz scripts | reaproveito recusar de scripts/conferir-busca.cjs:205
desfecho: estender
```

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

- Obrigatório só quando a tarefa cria arquivo de código, isto é, caminho que não existe
  no HEAD. Tarefa que só edita arquivo existente não precisa dele.
- Os outros canais sugeridos: `livro` (`vigias/livro-de-repos.md`), `ideias`
  (`ideias.jsonl`), `memoria`, `web` e `doc` (seção abaixo). O `catalogo` é outro canal:
  vale em toda tarefa que `## Quando conta` cobra, e o `repo` não o substitui.
- `pulado:` não vale para o `repo`: `- repo | pulado: <motivo>` é recusa, mesmo com
  motivo. Quando a busca no repo não acha nada, o resultado diz isso:
  `- repo | rg "..." scripts | nada reaproveitável`.
- Tarefa que cria arquivo sem linha `repo` com resultado é recusa, mesmo que os outros
  canais estejam preenchidos.

## Canal `catalogo`

Tarefa `implementar` (ou sem tipo) que declara arquivo de código em `arquivos:` declara este
canal (`## Quando conta`). Ele procura função que já existe no repositório antes de a tarefa
criar outra. Vem do design `2026-11-13-reuso-antes-de-criar`.

- Forma: `- catalogo | listar --raiz <pasta> | <resultado>`. O resultado diz
  `reaproveito <nome> de <arquivo>:<linha>` quando acha função equivalente, ou
  `nada equivalente`.
- `listar --raiz <pasta>` imprime o caminho **relativo à pasta**: `listar --raiz scripts`
  acha `conferir-busca.cjs`, sem o prefixo `scripts/`. A referência no resultado leva o
  caminho **relativo ao repositório**, com a pasta na frente: `scripts/conferir-busca.cjs:118`.
  O checador lê o arquivo a partir da raiz do repo, então sem a pasta ele não acha.
- Caminho com **espaço** vai entre crases, com a referência inteira dentro: ``reaproveito MT100 de `Ponto de Entrada/69 - Gestão de Contratos/MT100.prw:1` ``.
  Sem as crases o espaço corta o caminho e a referência não é conferida inteira. Crase é
  necessária para espaço, `[`, `]` e `$` no caminho (pasta de rota do Next:
  ``reaproveito Page de `app/[id]/page.tsx:1` ``). Acento sozinho não pede crase, porque a classe
  da referência tem `\p{L}` (`scripts/conferir-busca.cjs:111`). Sem crase, `[`, `]` ou `$` no
  caminho faz a ocorrência sair como `referência sem crase que o checador não lê por inteiro`,
  como em `pages/[id].js:99`.
- `- catalogo | pulado: <motivo>` vale para tarefa que não cria função, por exemplo uma
  correção dentro de uma função que já existe. O motivo não pode ser vazio.
- Conferência: só quando a linha não é `pulado:`, toda ocorrência de `arquivo:linha` em
  qualquer campo depois do canal (consulta e resultado) é casada com
  `([\p{L}\p{N}_.\/-]+\.[A-Za-z][A-Za-z0-9]*):L?(\d+)` (com a flag `u`), e a referência
  entre crases (`` `arq:L?n` ``) é casada antes, com espaço no caminho; o `L` antes do número é opcional. A
  contrabarra vale como barra, e URL (`http://` ou `https://`) não conta como referência.
  Fora de crase, uma ocorrência `.ext:N` com caractere fora da classe no caminho (`[`, `]`, `$`)
  é recusada antes das quatro, com `referência sem crase que o checador não lê por inteiro: <token>`,
  e a mensagem manda usar crase. Pontuação `(`, `[`, `"`, `'`, `,` ou `;` colada antes do caminho
  é aceita (`scripts/conferir-busca.cjs:133`).
  Cada referência passa pelas quatro recusas, nesta ordem, e sai com o primeiro motivo
  que casar:
  1. fora do repositório: caminho absoluto (`/...` ou `C:\...`) ou com segmento `..`. `C:`
     colado antes de um caminho também sai assim, porque o checador junta os dois
     (`scripts/conferir-busca.cjs:132`);
  2. extensão que o catálogo não lê. As extensões são as de `EXTENSOES` em
     `hooks/lib/definicoes.cjs`: `.js`, `.cjs`, `.mjs`, `.ts`, `.tsx`, `.jsx`, `.py`,
     `.prw`, `.prx`, `.tlpp`, `.ch` e `.dart`;
  3. arquivo que não existe. O caminho é relativo à raiz do repositório e é lido do disco;
  4. linha onde não começa definição no arquivo.

  Toda recusa cita `arquivo:linha`.
- Resultado sem referência (`nada equivalente`, ou texto livre sem `arquivo:linha`) passa
  sem conferência.
- Artefato isolado de propósito (D4 do design) vai com `desfecho: construir`. O motivo
  vai no resultado da linha `catalogo`, por exemplo
  `isolado de propósito (D4 do design), não reaproveito soma de src/x.js:3`. O checador
  não interpreta o motivo, mas confere as referências dele: `src/x.js:3` ainda tem de
  ser início de definição. Também não cruza o `desfecho:` com o resultado: `construir`
  com `reaproveito` passa.
- O que o checador **não** faz:
  - não julga se `nada equivalente` é verdade. Isso é do `revisar` (D7a do design);
  - não confere se a função citada faz o mesmo que a tarefa cria. Só confere que a linha
    é início de definição;
  - não roda o `listar`; a consulta não é executada, só é varrida para `arquivo:linha` e
    precisa existir;
  - não exige as palavras `reaproveito` nem `nada equivalente`;
  - não separa prosa estranha de referência: uma ocorrência `.ext:N` fora de crase, com
    caractere fora da classe no caminho, pode dar recusa mesmo sem ser caminho
    (`scripts/conferir-busca.cjs:136`). A saída é pôr o caminho entre crases ou, quando a
    tarefa não cria função, `- catalogo | pulado: <motivo>`. A linha pulada não leva
    resultado, então não tem referência a conferir (`scripts/conferir-busca.cjs:204`, `:304`).

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
- Resultado com `|` vai entre aspas: `- doc | <URL> | "aceita string | number"`. Sem as aspas, o
  `|` junta o pedaço do resultado à consulta, e a recusa diz que a consulta não é URL.
- Exceção às regras de `## Quando conta`: a linha `doc` é conferida em **qualquer** tarefa
  que a declara, de qualquer tipo, sem depender de a tarefa criar caminho novo (git: ver
  `## Quem confere`), porque decisão de API costuma editar arquivo
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

- Tarefa `implementar` ou sem tipo cujo `arquivos:` tem caminho de código, novo ou já
  existente no HEAD. Para ela, o bloco vale e leva o canal `catalogo`.
- Caminho que não existe no HEAD faz a tarefa criar arquivo, e aí ela leva também o canal
  `repo`.
- Tipos `docs`, `configurar`, `teste` e `pesquisar` (ou `pesquisa`) ficam fora.
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
primeiro caminho declarado (com `cria` quando é novo e `edita` quando já existe) e o que
falta. Para as referências do canal `catalogo`, o checador lê só os arquivos citados nos
campos depois do canal, com `definicoesDoArquivo` exportada por `scripts/catalogo-funcoes.cjs`.
O checador não cataloga o repo inteiro. O git só é exigido quando alguma tarefa
`implementar` (ou sem tipo) declara em `arquivos:` um caminho que não é glob, teste nem `.md`, novo ou
existente, porque é contra o HEAD que se confere se ele é novo. Sem
nenhuma, o checador roda fora de repositório git: sai 0, ou 2 se houver linha `doc`
inválida (`## Canal \`doc\``). Com alguma e fora de git, sai 69 (`nao-verificavel:`),
imprimindo antes a recusa da linha `doc` se houver, e o `marcar --estagio plano` trata o
69 como recusa.

## Origem

O padrão vem do ECC `skills/search-first`, que é só prosa ("agent guidance, not an
executable setup script"). Aqui o "nada encontrado" sem canais é recusa, não atalho.

O canal `catalogo` vem do design `2026-11-13-reuso-antes-de-criar`. Quando o `busca:` só
cobrava tarefa que cria arquivo, a cópia de função em arquivo que já existia passava.

O canal `doc` enxerta o método do `source-driven-development` do
`addyosmani/agent-skills` (MIT): a hierarquia de fontes e a marca do que a doc não cobre
(lá, `UNVERIFIED`). O cache por ETag de lá ficou de fora (design `2026-11-08-busca-doc`).
