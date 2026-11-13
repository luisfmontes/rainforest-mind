# gate-publicacao confere o texto de `gh issue`/`gh pr` (#702)

## Objetivo

O `hooks/gate-publicacao-destino.cjs` barra dado sensível (termo da lista privada, telefone, JID, CPF, credencial) que entra em arquivo versionado de repositório público. A escrita é vista em dois pontos, `Write`/`Edit`/`MultiEdit` e `git commit` (Issue #165). O texto que sai por `gh issue create|comment|edit` e `gh pr create|comment|edit|review|merge` não passa por nenhum dos dois. Esse texto é tão público quanto um arquivo, e o GitHub guarda o histórico de edição.

Em 2026-11-12 a #701 saiu com um termo da lista no corpo. No mesmo dia, o mesmo texto escrito num arquivo de design foi barrado pelo gate. Medido em `origin/main` (`57963349`): no `main()`, um evento `Bash`/`PowerShell` só chega a `conferirCommit`, e esse `conferirCommit` sai 0 quando o comando não casa com `RE_GIT_COMMIT`.

## Decisões fechadas

Rodada em modo autônomo: cada decisão é a recomendada, e as marcadas *(suposição)* são escolhas minhas que o Luís revisa no PR.

- **D1 — Comandos conferidos.** São conferidos os segmentos de um evento `Bash` ou `PowerShell` cujo comando é `gh` com família/verbo:
  - `issue` com `create`, `comment` ou `edit`;
  - `pr` com `create`, `comment`, `edit`, `review` ou `merge`.

  Os segmentos saem de `segmentosParaGate` (exportado por `hooks/gate-subagente-sem-gh.cjs`, que já serve dois outros gates). Os tokens saem de `tokensComAspas` (`hooks/lib/tokens-comando.cjs`). A conferência roda **antes** de `conferirCommit`, porque `conferirCommit` sai 0 em comando que não é commit. — porquê: são as escritas de texto livre que o fluxo usa (corpo de Issue e de PR, comentário de evidência, mensagem de squash).

- **D2 — Texto conferido.**
  - **Valores:** o valor de `--title`/`-t`, `--body`/`-b` e `--subject`/`-s` (este só do `merge`). O valor pode vir no token seguinte, depois de `=` ou colado à flag curta.
  - **Arquivo de corpo:** o conteúdo do arquivo de `--body-file`/`-F`. Caminho relativo resolve contra o `cwd` do evento; caminho MSYS (`/c/...`) passa por `normalizarMsys` (`hooks/lib/cwd-efetivo.cjs`).
  - **Heredoc:** quando o arquivo do `--body-file` não existe, conta o corpo de todo heredoc do mesmo comando, que é o caso em que o comando cria o arquivo antes do `gh`. Esses corpos saem de `posicoesDeOperadorHeredoc` + `corpoDeHeredoc` (`hooks/lib/heredoc.cjs`).

  Nunca conta o texto do comando inteiro: caminho de pasta de cliente num `cd` antes do `gh` seria falso positivo em toda Issue aberta de sessão de cliente para este repositório. — porquê: é o texto que vira Issue ou PR, e só ele.

- **D3 — Valor ilegível passa.** *(suposição)* Ficam de fora:
  - `--body-file` com variável (`$f`, `$env:TEMP\x.md`) ou com `-` (stdin);
  - `--body` com `$(...)` ou crase;
  - arquivo que não existe, sem heredoc no comando.

  Nada disso barra. — porquê: a falha fechada aqui barraria a forma de rotina do PowerShell (`--body-file $f`) em todo repositório, público ou não. O vazamento medido foi `--body-file` com caminho literal, que este design cobre. O resíduo fica nomeado em "Fora de escopo".

- **D4 — Repositório de destino.**
  - **Com `--repo`/`-R`:** com `owner/repo` (ou URL `https://github.com/owner/repo`), a visibilidade é a desse repositório, por `visibilidadeDeUmRepo`.
  - **Sem `--repo`:** é a do repositório git do `cwd`, por `visibilidadeDoRepo(gitTop)`, que já falha fechada quando há qualquer remoto público.
  - **Sem `--repo` e fora de repo git:** passa, porque o `gh` não teria destino.
  - **Valor de `--repo` ilegível** (variável): conta como `desconhecida`.

  `privada` passa. `desconhecida` barra, e o filtro de `declaradaPrivada` só vale quando o destino é o repositório do `cwd`. — porquê: é a mesma regra de visibilidade do resto do gate. `--repo` é o caso comum de sessão de cliente abrindo Issue aqui (regra 6), e o `cwd` dela é o repositório privado do cliente.

- **D5 — Achados conferidos: todos os de `conferirConteudo`, sem isenção de marcador.** *(suposição)* O `rainforest-gate: dados-de-exemplo` não dispensa texto de `gh`. — porquê: Issue pública com telefone é tão pública quanto arquivo. O marcador existe para fixture de teste versionada, que não sai por `gh`. Para falso positivo, a saída é a de sempre: `setup.cjs --desligar gate-publicacao` ou `RAINFOREST_GATE_OFF`.

- **D6 — Mensagem de bloqueio.** O cabeçalho troca `Arquivo: <caminho>` por `Comando: gh <família> <verbo>`, mais a origem do achado (`--body`, `--title`, `--subject`, `--body-file <caminho>` ou `heredoc`). O parágrafo sobre `git add` não aparece. Diz também que o GitHub guarda o histórico de edição de Issue e PR, então corrigir depois não apaga. — porquê: a mensagem atual fala de arquivo versionado e de índice, que não é o caso.

- **D7 — Versão 2.13.3 (PATCH).** CHANGELOG e as duas `plugin.json`. A linha do gate na tabela do README passa a citar o texto de `gh issue`/`gh pr`. — porquê: é conserto de cobertura de um gate existente, sem contrato novo.

## Avaliado e descartado

- **Conferir o comando inteiro como texto:** falso positivo com caminho de cliente (ver D2).
- **Falha fechada no ilegível:** ver D3.
- **Novo hook separado:** a visibilidade, o cache, os achados e a mensagem já moram em `gate-publicacao-destino.cjs`. Um hook novo duplicaria tudo isso.

## Varredura

`node scripts/varrer.cjs --slug gate-publicacao-gh "body-file" "termo-privado"`, com a saída em `docs/rainforest/varredura/gate-publicacao-gh.txt`.
- Só a #702 está aberta sobre o tema.
- As Issues de `body-file` fechadas são do `gate-fechar-issue`: grafias de flag (#664, #344) e heredoc que cria o arquivo (#407). O parse do D2 segue as mesmas grafias, mas o código fica neste gate. O `gate-fechar-issue.cjs` está em mudança no fluxo `gate-segmentador` (#689), e extrair uma lib comum agora conflitaria com aquele PR.

## Em aberto

- Nada que trave o plano. As suposições D3 e D5 vão listadas no PR para o Luís revisar.

## Fora de escopo

- `gh api` com `-f body=...` e `gh release`/`gh gist`.
- Corpo ilegível (D3).
- Apagar a revisão da #701 no GitHub, que é ato manual do Luís.

## Pronto quando

Payload real de `PreToolUse` com o `gh` falso de visibilidade da bateria e termo da lista no `HOME` de areia:
- `gh issue create --body-file <arquivo com o termo>` num repositório público sai 2 com `[termo-privado]` e `Comando: gh issue create`.
- A mesma coisa sai 2 por `--body`, `--title`, `-F`, heredoc que cria o arquivo e `gh pr create`/`comment`/`merge --body`, e pelo evento `PowerShell`.
- Com o repositório privado, sai 0.
- Com `--repo dono/publico` a partir de um `cwd` privado, sai 2. Com `--repo dono/priv` a partir de um `cwd` público, sai 0.
- `gh issue view 12`, `gh issue create --body-file $f` e `gh pr list` sem achado saem 0.
