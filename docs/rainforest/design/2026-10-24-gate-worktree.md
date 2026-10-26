# gate-worktree: caminho que começa com variável barra em todo ramo, mensagem certa no ramo dinâmico e no `cd -`

## Objetivo

Fechar quatro Issues do `hooks/gate-worktree.cjs`:

- **#580:** um subagente no worktree isolado escreve no checkout principal quando o caminho chega por variável fora do "segmento de leitura simples" (`touch "$CLAUDE_PROJECT_DIR/f"` sai 0).
- **#582:** o gate barraria caminho relativo e `--raiz "$(git rev-parse --show-toplevel)"` em subagente de worktree linkado.
- **#583:** o ramo de comando dinâmico (`source`, `eval`) barra dizendo "Este e o diretorio de trabalho principal" mesmo com o cwd no worktree.
- **#573:** o que sobrou depois do PR #586 é a mensagem do `cd -` com execução indireta, que nomeia a causa errada.

Para quem e quando: subagente despachado com `isolation: "worktree"` (payload com `agent_id`), em Bash. A janela principal e o PowerShell não mudam.

## Fatos medidos (2026-10-24)

Sandbox: `git init` do principal, o worktree do agente em `<P>/.claude/worktrees/agent-x` e o payload de subagente no stdin de `node hooks/gate-worktree.cjs`, com `CLAUDE_PROJECT_DIR` no principal e também num worktree de sessão. O resultado foi o mesmo no 1.73.0 do cache e no 1.74.0 da branch:

- **#580:** dos 7 comandos do critério, 6 saem 0. Só `echo x > "$CLAUDE_PROJECT_DIR/f"` sai 2, pelo ramo "destino de redirecionamento começa com variável" do segmento de leitura.
- **#582:** saem 0 o `python3 -c "open('a/b.py')"`, a forma literal da Issue (`ast.parse(open(..., encoding='utf-8'))`) e o `node x.cjs --raiz "$(git rev-parse --show-toplevel)"`. Com o caminho absoluto do principal, sai 2. O único comando achado que bate com o relato é `node <principal>/scripts/conferir-mutacao.cjs ...`, que sai 2. Pelo cache do plugin ou pelo worktree, o mesmo comando sai 0.
- **#583:** saem 2 os comandos `. ./x.sh`, `source ./x.sh`, `source .venv/bin/activate && python -m pytest -q`, `eval "$(ssh-agent)"` e `cd - && source ./x.sh`, com "diretorio de trabalho principal" na mensagem.
- **#573:** `cd -; export FOO=1; ls` sai 2, e a mensagem cita execução indireta (`$(`, `bash -c`, `source`) que a linha não tem. `cd - && git commit -m "$(date)"` sai 2 pela camada de git, com a mensagem genérica.

## Decisões fechadas

- **D1 — Caminho que começa com variável ou substituição barra em todo ramo da rede, sem resolver valor (#580)**. A regra que hoje vale só para o destino de redirecionamento do segmento de leitura (`variavelNoInicio`, mensagem com saída) passa a valer em três lugares de `alvosDaRede`:
  1. no destino de redirecionamento de qualquer segmento, inclusive nos ramos de pipeline com escritor (`pipelineComEscritor`), de lista com `||`/`&&` e de linha não confiável (`naoConfiavel`, com `$(`, crase, `$'` ou continuação);
  2. nos argumentos-alvo dos escritores conhecidos de Bash: `touch`, `cp`, `mv`, `tee`, `mkdir`, `rm`, `ln`, `install` e `sed -i`, além do `of=` do `dd`;
  3. quando o caminho começa com `$NOME`, `${...}`, `$(...)` ou crase. `"$X/f"`, `"$(cmd)"/f` e `--target=$X` contam. Expansão depois de um prefixo literal (`out-$(date).json`, `./dist/$NOME.js`) não conta.

  O gate **não resolve** o valor de nenhuma variável ou substituição: o veredito é 2 com a mensagem existente, que dá a saída (escrever o caminho literal no comando, ou usar a ferramenta Write). Argumento de comando que não está na lista de escritores (`node x.cjs --raiz "$(git rev-parse --show-toplevel)"`, `python -m pytest "$X"`) continua sem ser julgado, como hoje. O atalho de casa no início do caminho (`$HOME/...`) segue a regra existente: conta como a casa e não como variável.
  - porquê: escolha do usuário (Q1 reescrita, opção B'). Resolver o valor (D3 do lote 2026-10-21b) foi implementado e recuado em 2026-10-22, porque abriu contorno novo em três rodadas seguidas de revisão (atribuição não executada, `printf -v`, laço, glob). Estender a falha fechada é a mesma regra que já vale no redirecionamento.

- **D2 — Os vizinhos do critério da #580 mudam de veredito**: `D=<fora>; touch "$D/f"` e `D=<fora>; cp a.txt "$D/f"` passam a sair 2, como já sai `D=<fora>; echo x > "$D/f"`. A #580 fecha com o critério emendado no comentário de evidência: os 7 comandos saem 2, e esses dois vizinhos saem 2 com a mensagem da saída. Saem 0 os casos sem variável no início: `touch "<W>/f"` (literal), `cp a.txt sub/f` e `out-$(date).json` como argumento de `touch`.
  - porquê: consequência da D1 e aceita no Q1 B'.

- **D3 — A #582 fecha com regressão, sem mudar veredito**: os três comandos do critério entram em `hooks/testa-gate-worktree.sh`, com payload de subagente em worktree linkado e `CLAUDE_PROJECT_DIR` no principal:
  - `python3 -c "open('a/b.py')"` sai 0;
  - `node x.cjs --raiz "$(git rev-parse --show-toplevel)"` sai 0, e a D1 precisa manter isso;
  - o mesmo comando com o caminho absoluto do principal sai 2.

  `node <principal>/scripts/x.cjs` continua barrado, porque roda código do checkout principal. A saída é rodar pelo worktree ou pelo cache do plugin. A Issue fecha com a medição de "Fatos medidos" como evidência.
  - porquê: escolha do usuário (Q2). O relato não reproduz em 1.73.0 nem em 1.74.0.

- **D4 — O ramo de comando dinâmico diz o worktree quando o cwd é worktree (#583)**: o `bloqueia(...)` do ramo `incerto` em `main` passa a receber o `ehWorktreeAlvo`, como a #573 (D4) fez para a `bloqueiaPelaRede`.
  - Com cwd no worktree, o stderr não contém "diretorio de trabalho principal" e nomeia o comando dinâmico como causa.
  - Com cwd no checkout principal, continua dizendo "Este e o diretorio de trabalho principal".
  - Os vereditos não mudam: os cinco casos da Issue continuam saindo 2.
  - porquê: o critério da própria Issue.

- **D5 — A mensagem do `cd -` nomeia a causa que está na linha (#573)**: no ramo `medivel` de `casaRedefinida`, a mensagem lista só o que está na linha e impede medir: `$(`, crase, `bash -c`/`sh -c`, `source`/`.`, `eval`, `export`/`unset`/`read`/atribuição.
  - Quando a camada de git barra uma linha que tem `cd -` (`cd - && git commit -m "$(date)"`), a mensagem dela acrescenta o trecho do `cd -`, com a mesma saída: trocar pelo caminho absoluto.
  - Os vereditos não mudam.
  - A #573 fecha. O destino do `cd -` não é resolvido: isso foi refutado na 3ª revisão do lote 2026-10-21b.
  - porquê: escolha do usuário (Q3).

- **D6 — Entrega**: um PR, versão 2.0.4 (era 2.0.2; o PR #603 entrou antes como 2.0.3) (PATCH: conserto sem contrato novo), com `Closes #573, closes #580, closes #582, closes #583`.
  - porquê: escolha do usuário (Q4).

## Avaliado e descartado

- **Resolver o valor da variável (Q1 A)**: foi a D3 do lote 2026-10-21b, implementada e recuada em 2026-10-22 depois de três rodadas seguidas de contorno: atribuição que o shell não executa, `printf -v`, `mapfile`/`let`, reatribuição em laço depois do destino e glob no valor.
- **Só `$CLAUDE_PROJECT_DIR` no início do caminho (Q1 C)**: fecharia a #580 pela metade.
- **Barrar toda variável não resolvida, inclusive no argumento de comando desconhecido**: barraria o `--raiz "$(git rev-parse --show-toplevel)"` que o briefing do `executar` manda usar (#582).
- **Liberar script do principal rodado por caminho absoluto (Q2)**: muda veredito e pede modelo de ameaça próprio, porque o script roda código do checkout principal.
- **Resolver o destino do `cd -` (Q3)**: refutado na 3ª revisão do lote 2026-10-21b. O gate errava o destino quando o `cd` anterior não rodava.
- **Dois PRs, um de mensagem e outro de veredito (Q4)**: as quatro Issues mexem na mesma função (`alvosDaRede`) e na mesma bateria.

## Fora de escopo

- PowerShell: `$env:X` e variável de PowerShell em caminho seguem como hoje.
- `source` de arquivo do próprio worktree continua barrado. Mudar isso muda veredito, e a #583 o deixou fora.
- Comando que roda script do principal por caminho absoluto continua barrado (D3).
- Escritor que não está na lista da D1 (`python -c "open(...,'w')"`, `node -e`, `npm`): não é julgado pelo argumento, como hoje.

## Em aberto

Nada. As quatro decisões de fronteira foram respondidas em 2026-10-24 (Q1 reescrita como B', Q2, Q3 e Q4 recomendadas).

## Varredura

`docs/rainforest/varredura/2026-10-24-gate-worktree.txt`. As Issues abertas do gate são exatamente as quatro. O histórico mostra:

- o lote 2026-10-21b (PR #586), que resolveu a mensagem da rede (D4) e tentou e recuou duas resoluções: variável no destino (`4ec37fa2` → `2604e097`) e destino do `cd -` (`8684667d` → `5e41fd23`). Esse recuo é o que reescreveu a Q1;
- a #552 (PR #563) criou a rede de caminho do principal;
- a #561 (PR #572) criou o `casaRedefinida`;
- a #350 (PR #357) fez os gates dizerem quando a causa é variável.

Nenhuma branch, PR ou ideia aberta trata destes defeitos, então nada foi reaproveitado.

## Regra de parada

Escritor novo ou forma nova de expansão que o revisor achar passando entra como nota no PR. Não vira caso novo nesta entrega, e a resolução de valor não volta.
