# gate-worktree: variável resolvida, mensagem certa no ramo dinâmico e no `cd -`

## Objetivo

Fechar quatro Issues do `hooks/gate-worktree.cjs`:

- **#580:** um subagente no worktree isolado escreve no checkout principal quando o caminho chega por variável fora do "segmento de leitura simples" (`touch "$CLAUDE_PROJECT_DIR/f"` sai 0).
- **#582:** o gate barraria caminho relativo e `--raiz "$(git rev-parse --show-toplevel)"` em subagente de worktree linkado.
- **#583:** o ramo de comando dinâmico (`source`, `eval`) barra com "Este e o diretorio de trabalho principal" mesmo com o cwd no worktree.
- **#573:** o que sobrou depois do PR #586 foi a mensagem do `cd -` com execução indireta, que nomeia a causa errada.

Para quem e quando: subagente despachado com `isolation: "worktree"` (payload com `agent_id`), em Bash. A janela principal e o PowerShell não mudam.

## Fatos medidos (2026-10-24)

O sandbox tinha `git init` do principal, o worktree do agente em `<P>/.claude/worktrees/agent-x` e o payload de subagente no stdin de `node hooks/gate-worktree.cjs`. Rodou com `CLAUDE_PROJECT_DIR` no principal e também num worktree de sessão. O resultado foi o mesmo no 1.73.0 do cache e no 1.74.0 da branch:

- **#580:** dos 7 comandos do critério, 6 saem 0. Só `echo x > "$CLAUDE_PROJECT_DIR/f"` sai 2, pelo ramo de destino de redirecionamento que começa com variável.
- **#582:** `python3 -c "open('a/b.py')"`, a forma literal da Issue (`ast.parse(open(..., encoding='utf-8'))`) e `node x.cjs --raiz "$(git rev-parse --show-toplevel)"` saem 0. Com o caminho absoluto do principal, sai 2. O único comando achado que bate com o relato é `node <principal>/scripts/conferir-mutacao.cjs ...`, que sai 2. Pelo cache do plugin ou pelo worktree, o mesmo comando sai 0.
- **#583:** `. ./x.sh`, `source ./x.sh`, `source .venv/bin/activate && python -m pytest -q`, `eval "$(ssh-agent)"` e `cd - && source ./x.sh` saem 2. A mensagem diz "diretorio de trabalho principal".
- **#573:** `cd -; export FOO=1; ls` sai 2, e a mensagem cita execução indireta (`$(`, `bash -c`, `source`) que a linha não tem. `cd - && git commit -m "$(date)"` sai 2 pela camada de git, com a mensagem genérica.

## Decisões fechadas

- **D1 — O gate resolve o valor conhecível de variável em todo ramo da rede (#580)**: em `alvosDaRede`, antes de julgar caminho, uma palavra com expansão de variável ou substituição é reescrita pelo valor, quando ele é conhecível. A ordem é esta:
  1. Atribuição literal na própria linha, antes do uso (`D=/x/y; touch "$D/f"`, `export D=/x/y`). Literal é texto sem `$`, crase nem `$(`.
  2. Substituição de comando com valor conhecido: `$(pwd)` e `$PWD` dão o cwd do segmento, `$(git rev-parse --show-toplevel)` dá o toplevel do cwd do segmento, e `$(mktemp ...)` dá um caminho no diretório temporário do sistema, fora do repositório.
  3. Variável do ambiente do hook (`process.env`), como `$CLAUDE_PROJECT_DIR`, `$TEMP`, `$TMPDIR` e `$HOME`. A casa segue a regra que já existe, e HOME redefinido na linha continua caindo em `casaRedefinida`.
  4. Variável que não está em nenhum dos três é tratada como vazia, como no Bash.

  Onde vale: no destino de redirecionamento de qualquer segmento, nos argumentos dos segmentos fora de leitura, nas linhas `naoConfiavel` (com `$(`, crase, `$'` ou continuação) e nos segmentos de pipeline com escritor. O caminho resolvido passa pelo `protegido` de hoje.
  - porquê: escolha do usuário (Q1, opção A). A variável que de fato aponta para o principal dentro de um worktree é a `$CLAUDE_PROJECT_DIR` (memória "Hook de projeto roda do principal"). Ela e o `$(dirname "$PWD")/../..` do critério resolvem por esta lista. `$(mktemp)` e `$(pwd)` são o que o briefing de revisor manda usar, então não podem ser barrados.

- **D2 — Valor que não resolve, em posição de escrita, barra (#580)**: atribuição não literal (`X=$(cat dir.txt)`, `X=$Y$(date)`) ou substituição fora da lista da D1 deixam a palavra **incerta**.
  - A palavra incerta barra quando está no destino de redirecionamento ou é argumento de um segmento fora de leitura, e a expansão incerta está no **início do caminho**: `"$X/f"`, `"$(cmd)"/f`, `--out=$X/f`. Expansão depois de um prefixo literal (`out-$(date).json`, `./dist/$NOME.js`) fica relativa ao prefixo e não barra.
  - A mensagem nomeia a variável ou a substituição, e dá a saída: escrever o caminho literal no comando ou usar a ferramenta Write.
  - Palavra incerta em segmento de leitura (`ls "$X"`, `cat "$X/f"`) não barra.
  - porquê: escolha do usuário (Q1). O custo aceito é barrar `X=$(cat dir.txt); echo > "$X/f"`.

- **D3 — A #582 fecha com regressão, sem mudar veredito**: os três comandos do critério entram em `hooks/testa-gate-worktree.sh`, com payload de subagente em worktree linkado e `CLAUDE_PROJECT_DIR` no principal:
  - `python3 -c "open('a/b.py')"` sai 0;
  - `node x.cjs --raiz "$(git rev-parse --show-toplevel)"` sai 0, e a D1 precisa manter isso;
  - o mesmo comando com o caminho absoluto do principal sai 2.

  `node <principal>/scripts/x.cjs` continua barrado: roda código do checkout principal, e a saída é rodar pelo worktree ou pelo cache do plugin. A Issue fecha com a medição de "Fatos medidos" como evidência.
  - porquê: escolha do usuário (Q2). O caso não reproduz em 1.73.0 nem em 1.74.0.

- **D4 — O ramo de comando dinâmico diz o worktree quando o cwd é worktree (#583)**: o `bloqueia(...)` do ramo `incerto` em `main` passa a receber o `ehWorktreeAlvo`, como a #573 (D4) fez para a `bloqueiaPelaRede`.
  - Com cwd no worktree, o stderr não contém "diretorio de trabalho principal" e nomeia o comando dinâmico como causa.
  - Com cwd no checkout principal, a mensagem continua dizendo "Este e o diretorio de trabalho principal".
  - Os vereditos não mudam: os cinco casos da Issue continuam saindo 2.
  - porquê: o critério da própria Issue.

- **D5 — A mensagem do `cd -` nomeia a causa que está na linha (#573)**: no ramo `medivel` de `casaRedefinida`, a mensagem lista só os construtos da linha que impedem medir: `$(`, crase, `bash -c`/`sh -c`, `source`/`.`, `eval`, `export`/`unset`/`read`/atribuição.
  - Quando a camada de git barra uma linha que tem `cd -` (`cd - && git commit -m "$(date)"`), a mensagem dela acrescenta a linha do `cd -` com a mesma saída: trocar pelo caminho absoluto.
  - Os vereditos não mudam.
  - A #573 fecha. O destino do `cd -` não é resolvido, porque essa tentativa foi refutada na 3ª revisão do lote 2026-10-21b.
  - porquê: escolha do usuário (Q3).

- **D6 — Entrega**: um PR, versão 1.74.1 (PATCH: conserto, sem contrato novo), com `Closes #573, closes #580, closes #582, closes #583`.
  - porquê: escolha do usuário (Q4).

## Avaliado e descartado

- **Barrar toda variável não resolvida nos ramos novos (Q1, opção B)**: barraria `$(mktemp)` e `$(pwd)`, que o briefing de revisor manda usar.
- **Só `$CLAUDE_PROJECT_DIR` em todo ramo (Q1, opção C)**: fecharia a #580 pela metade. Os outros 5 casos do critério seguiriam passando.
- **Liberar script do principal rodado por caminho absoluto (Q2)**: muda veredito e pede um modelo de ameaça próprio, porque o script roda código do checkout principal.
- **Resolver o destino do `cd -` (Q3)**: refutado na 3ª revisão do lote 2026-10-21b. O gate errava o destino quando o `cd` anterior não rodava.
- **Dois PRs, um de mensagem e outro de veredito (Q4)**: as quatro Issues mexem na mesma função (`alvosDaRede`) e na mesma bateria.

## Fora de escopo

- PowerShell: `$env:X` e variável de PowerShell em caminho seguem como hoje.
- `source` de arquivo do próprio worktree continua barrado. Mudar isso muda veredito, e a #583 o deixou fora.
- Comando que roda script do principal por caminho absoluto continua barrado (D3).
- Construir um parser de shell. A resolução da D1 é a lista fechada acima. Forma nova que não resolve cai na D2 (barra), não em código novo.

## Regra de parada

Contorno que exija nova forma de expansão (aritmética, `${X:-y}`, `${X/a/b}`, indireção `${!X}`) cai na D2 e barra. Não vira caso novo na D1. Achado dessa classe vai como nota no PR.
