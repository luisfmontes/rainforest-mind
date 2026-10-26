# Plano: gate-worktree — caminho que começa com expansão barra em todo ramo da rede, mensagem certa no ramo dinâmico e no `cd -` (#573, #580, #582, #583)

Design: docs/rainforest/design/2026-10-24-gate-worktree.md

## O que não pode quebrar
- Todo caso de `hooks/testa-gate-worktree.sh` que hoje espera 2 continua 2. Os que esperam 0 continuam 0, com duas exceções da D2, que mudam no mesmo commit da tarefa 2:
  - `#573 A: vizinho D=<scratchpad>; touch "$D/f" passa` passa a esperar 2;
  - `#573 B: incidente reescrito com cd <worktree> passa` continua esperando 0, mas o texto reescrito troca `"$F"` e `"$SCR/..."` pelos caminhos literais. O caso mede a troca do `cd -`, e o `cp "$F" "$SCR/x"` do incidente passa a barrar pela D1.
- `node hooks/testa-corpus-comandos.cjs`, o corpus de comandos legítimos, sai sem bloqueio novo.
- A rede (`alvosDaRede`) só age com o cwd num worktree linkado. A janela principal (sem `agent_id`), o subagente com cwd no principal e o PowerShell têm o veredito de hoje.
- `node x.cjs --raiz "$(git rev-parse --show-toplevel)"`, de subagente no worktree, continua 0. É a forma que o briefing do `executar` manda usar (#582).
- `$HOME/...` e `${HOME}/...` no início do caminho seguem a regra de casa de hoje: valem como a casa, e não como variável.
- Nenhum caso de teste afirma sobre o texto do fonte. As baterias medem o comportamento do gate rodado como processo, com o payload de subagente no stdin.
- O gate não resolve o valor de nenhuma variável nem substituição (D1). Resolução que apareça no diff é achado de revisão.
- Nenhum modelo de briefing do plugin manda o subagente escrever num alvo que começa com `$`. Conferido em 2026-10-24 com Grep em `skills/`, `agents/` e `hooks/**/*.md`, sem ocorrência. A mutação no lugar roda por `conferir-mutacao.cjs`, em Node, fora do gate de Bash.
- As linhas `de:` das tarefas 1, 2, 4, 5 e 6 são código a nascer. O briefing do `executar` as cita literalmente como requisito, porque a catraca só aplica a mutação se o texto casar byte a byte e uma única vez.

## Base medida (f99164b6, 2026-10-24)
`bash hooks/testa-gate-worktree.sh` saiu `811 ok, 2 falha(s)`. As duas falhas são de tempo, com o veredito certo:
- `(#530) rodada extra 2: 'eval ' x22`: exit 2 em 2064 ms;
- `'bash' -c aninhado 6 niveis`: exit 2 em 2150 ms.

O teto dos dois casos é 2000 ms, e a máquina estava sob carga de outra sessão. Esses dois casos não contam como regressão da entrega. Qualquer outra falha conta.

## Notas para a revisão
- O `barraSemConferir` (#530) também chama `bloqueia` sem `ehWorktreeAlvo`. É a mesma classe da #583, mas fica fora da D4, que trata só o ramo `incerto` de `procuraCLI`. Se a revisão apontar, vira nota no PR.

## Regra de parada (a trava reimplementa gramática de shell)
O modelo de ameaça é o engano da sessão: o subagente escreve no principal achando que está no worktree. Ofuscação deliberada fica fora.

O que fica dentro:
- redirecionamento;
- os escritores da lista da D1: `touch`, `cp`, `mv`, `tee`, `mkdir`, `rm`, `ln`, `install`, `sed -i` e o `of=` do `dd`, inclusive quando são chamados por wrapper que repassa o comando (`env`, `sudo`, `command`, nome entre aspas);
- os mesmos escritores dentro de substituição (`$(...)`, crase) e de `bash -c`/`sh -c`.

Escritor fora da lista, expansão no meio da palavra, `xargs`, `find -exec` e `python -c`/`node -e` ficam como hoje.

Contorno novo que o revisor achar fora disso vira nota no PR (seção "Deixado para depois"), não caso novo. A resolução de valor não volta: foi recuada no lote 2026-10-21b, depois de três rodadas de contorno.

## Tarefas

### 1. Destino de redirecionamento que começa com expansão barra em todo ramo da rede [tipo: implementar]
atende: D1, D2
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
prova-na-base: verde — os casos entram na bateria existente, que na base roda sem eles; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (expansaoNoInicio(destino)) return destino;`
  para: `if (false) return destino;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#580 D1: destino de redirecionamento com expansao no inicio", caso "true | true; echo x > \"$CLAUDE_PROJECT_DIR/f\" barra"`
pronto quando: forma do código, a mutação depende dela:
- `variavelNoInicio(destino)` vira a função de topo `expansaoNoInicio(palavra)`. Ela tira as aspas iniciais e devolve o texto da expansão quando a palavra começa com `$NOME`, `${...}`, `$(` ou crase; senão devolve `null`. Os nomes de `NOMES_DA_CASA` (`$HOME`, `${HOME}` e afins) devolvem `null`.
- Dentro de `alvosDaRede`, uma função interna `destinoComExpansao(texto)` percorre `destinosDeRedirecionamento(texto, false)`, pula `ehDescarteDeSaida` e tem a linha exata `if (expansaoNoInicio(destino)) return destino;`. O corpo de heredoc é dado (passa por `mascaraHeredocsBash`). Só o Bash entra.
- Ela é chamada no ramo `naoConfiavel`, antes do `citaProtegido`, e em cada segmento do laço, antes do `if (leitura[i] && !pipelineComEscritor)`, valendo para segmento de leitura, de pipeline com escritor e fora de leitura.
- Quando acha, `alvo(...)` usa a mensagem de hoje ("Destino de redirecionamento comeca com variavel" + a saída: caminho literal ou a ferramenta Write).

Com payload de subagente no worktree, saem 2 os cinco comandos de redirecionamento do critério da #580 (os outros dois, `touch` e `cp`, são da tarefa 2):
- `echo x > "$CLAUDE_PROJECT_DIR/f"`;
- `D=$(dirname "$PWD")/../..; echo x > "$D/f"`;
- `true | true; echo x > "$CLAUDE_PROJECT_DIR/f"`;
- `true || true; echo x > "$CLAUDE_PROJECT_DIR/f"`;
- `echo "$(date)" > "$CLAUDE_PROJECT_DIR/f"`.

Contornos que também saem 2:
- `echo x > "${CLAUDE_PROJECT_DIR}/f"`;
- `echo x >> "$(git rev-parse --show-toplevel)/../../f"`;
- `` echo x > `pwd`/f ``;
- `ls | tee x >/dev/null; echo x 2> "$D/f"`;
- `cd /tmp; echo x > "$D/f"`, porque a rede barra mesmo com o cwd movido para fora.

Vizinhos que saem 0:
- `echo x > out-$(date).json`;
- `echo x > ./dist/$NOME.js`;
- `echo x > /dev/null`;
- `echo x 2>&1`;
- `git commit -m "$(printf 'echo x > "$X/f"')"`;
- `cat <<'EOF' > f.txt` + linha `echo x > "$X/f"` + `EOF`, com o heredoc como dado e o destino literal;
- `grep -rn 'echo x > "$X"' docs/`.

Superfície humana: o stderr do bloqueio traz o destino e a saída ("escreva o caminho literal", "ferramenta Write"), e não diz `diretorio de trabalho principal`. O critério falha se a saída sumir.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`.

### 2. Alvo de escritor conhecido que começa com expansão barra [tipo: implementar]
atende: D1, D2
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 1
prova-na-base: verde — os casos entram na bateria existente, que na base roda sem eles; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (!ESCRITORES_DA_REDE.has(nome)) return [];`
  para: `if (true) return [];`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#580 D1: alvo de escritor com expansao no inicio", caso "touch \"$CLAUDE_PROJECT_DIR/f\" barra"`
pronto quando: forma do código, a mutação depende dela:
- A constante de topo é `const ESCRITORES_DA_REDE = new Set(["touch", "cp", "mv", "tee", "mkdir", "rm", "ln", "install", "sed", "dd"]);`.
- A função de topo `alvosDeEscritor(toks)` acha o comando por `posicaoDeComando`, que já atravessa `env`, `sudo`, `command` e nome entre aspas. Ela tira o caminho e o `.exe` do nome, e a linha exata `if (!ESCRITORES_DA_REDE.has(nome)) return [];` vem antes de qualquer outra regra.
- O que ela devolve como alvo:
  - em `cp`, `mv`, `ln` e `install`, o último posicional e o valor de `-t`/`--target-directory=`;
  - em `sed`, os posicionais depois do script, só com `-i`;
  - em `dd`, o valor de `of=`;
  - nos demais (`touch`, `mkdir`, `rm`, `tee`), todos os posicionais.
  - Opção com valor colado (`--target-directory=$X`) conta pelo valor.
- Em `alvosDaRede`, os alvos de cada segmento são conferidos com `expansaoNoInicio`. Entram também:
  - os corpos de substituição (`corposDeSubstituicao`);
  - o texto interno de `bash -c`/`sh -c` (`desempacotarWrapperDeString`).
- O corpo de heredoc é dado, e o texto de mensagem de `git`/`gh` (`semTextoDeMensagem`) não conta.
- A mensagem nomeia o comando e o alvo e dá a mesma saída: caminho literal ou a ferramenta Write.
- Na bateria, `#573 A: vizinho D=<scratchpad>; touch "$D/f" passa` passa a esperar 2. O texto reescrito de `#573 B: incidente reescrito com cd <worktree> passa` troca `"$F"` e `"$SCR/..."` pelos caminhos literais e continua esperando 0.

Com payload de subagente no worktree, saem 2:
- `touch "$CLAUDE_PROJECT_DIR/f"` e `cp a.txt "$CLAUDE_PROJECT_DIR/f"`, do critério da #580;
- os vizinhos da D2: `D=<fora>; touch "$D/f"` e `D=<fora>; cp a.txt "$D/f"`.

Contornos que também saem 2:
- `mv a.txt "$X/f"`;
- `echo x | tee -a "$X/f"`;
- `mkdir -p "$X/d"`;
- `rm -rf "$X/d"`;
- `ln -s a.txt "$X/l"`;
- `install -D a.txt "$X/f"`;
- `sed -i 's/a/b/' "$X/f"`;
- `dd if=a.txt of="$X/f"`;
- `cp -t "$X" a.txt`;
- `cp --target-directory="$X" a.txt`;
- `touch -- "$X/f"`;
- `env FOO=1 touch "$X/f"`;
- `"touch" "$X/f"`;
- `touch "$(git rev-parse --show-toplevel)/../../f"`;
- `echo "$(touch "$X/f")"`;
- `bash -c 'touch "$X/f"'`.

Vizinhos que saem 0:
- `touch "<W>/f"` (literal);
- `cp a.txt sub/f`;
- `touch out-$(date).json`;
- `touch ./dist/$NOME.js`;
- `cp "$SRC/a.txt" b.txt` (só a origem é variável);
- `sed -i "s/$X/y/" f.txt` (variável só no script);
- `sed "s/a/b/" "$X/f"` (sem `-i`);
- `node x.cjs "$X/f"`;
- `grep -rn 'touch "$X/f"' docs/`;
- `echo 'cp a "$X/f"'`;
- `git commit -m "$(printf 'touch "$X/f"')"`;
- `git commit -F msg.txt` precedido de um heredoc cujo corpo tem `rm -rf "$X"`.

Superfície humana: o stderr traz o comando, o alvo e a saída, e não diz `diretorio de trabalho principal`.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`, e por `node hooks/testa-corpus-comandos.cjs` sem falha.

### 3. Regressão da #582: argumento de comando desconhecido não é julgado [tipo: teste]
atende: D3
arquivos: `hooks/testa-gate-worktree.sh`
depende de: 2
prova-na-base: verde — os casos documentam o veredito de hoje e entram na bateria existente; o vermelho é medido pela mutação, que faz a D1 julgar todo comando
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (!ESCRITORES_DA_REDE.has(nome)) return [];`
  para: `if (false) return [];`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#582: subagente em worktree linkado", caso "node x.cjs --raiz \"$(git rev-parse --show-toplevel)\" passa"`
pronto quando: a seção `#582: subagente em worktree linkado` usa payload de subagente com cwd no worktree linkado e `CLAUDE_PROJECT_DIR` no principal.
- Saem 0:
  - `python3 -c "open('a/b.py')"`;
  - `python3 -c "import ast;ast.parse(open('a/b.py', encoding='utf-8').read())"`;
  - `node x.cjs --raiz "$(git rev-parse --show-toplevel)"`.
- Saem 2:
  - `node x.cjs --raiz "<principal>"`, com o caminho absoluto do principal;
  - `node <principal>/scripts/x.cjs`, que roda código do checkout principal.
- Com a mutação, que faz `alvosDeEscritor` julgar os posicionais de qualquer comando, o caso `--raiz "$(git rev-parse ...)"` fica vermelho.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`.

### 4. Ramo de comando dinâmico diz o worktree quando o cwd é worktree (#583) [tipo: implementar]
atende: D4
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 3
prova-na-base: verde — os casos entram na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `null, estadoAqui.ehWorktree`
  para: `null, false`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#583: comando dinamico com cwd no worktree", caso "source ./x.sh nao diz diretorio principal"`
pronto quando: forma do código. A chamada `bloqueia(...)` do ramo `if (incerto)` de `procuraCLI` em `main` recebe os dois argumentos finais `null, estadoAqui.ehWorktree`. É a única ocorrência desse texto no arquivo.

Com payload de subagente no worktree, saem 2:
- `. ./x.sh`;
- `source ./x.sh`;
- `source .venv/bin/activate && python -m pytest -q`;
- `eval "$(ssh-agent)"`;
- `cd - && source ./x.sh`.

Em todos, o stderr contém `Comando dinamico` e não contém `diretorio de trabalho principal`.

Com cwd no checkout principal, `source ./x.sh` sai 2 e o stderr continua contendo `Este e o diretorio de trabalho principal`.

Superfície humana: o agente no worktree lê a causa (comando dinâmico) e não lê que está no principal. O critério falha se o texto do principal voltar.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`.

### 5. Mensagem do `cd -` lista só a causa que está na linha (#573) [tipo: implementar]
atende: D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 4
prova-na-base: verde — os casos entram na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `causasDoCdMenos(comando).join(", ")`
  para: `"bash -c, source"`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#573 D5: causa do cd - na mensagem", caso "cd -; export FOO=1; ls nomeia export e nao bash -c"`
pronto quando: forma do código:
- A função de topo `causasDoCdMenos(comando)` devolve a lista de rótulos dos construtos presentes na linha, nesta ordem:
  1. `$(` ou `<(`/`>(`;
  2. crase;
  3. `bash -c`/`sh -c`, o interpretador com `-c`/`-e`;
  4. `source`/`.`;
  5. `eval`;
  6. `export`/`unset`/`read`/`declare` (definição de variável).
- Ela reaproveita as regex que já existem (`EXECUCAO_INDIRETA`, `FONTE_DE_SCRIPT`, `DEFINE_VARIAVEL`), sem gramática nova. Nunca devolve lista vazia: sem nenhum dos construtos, devolve um rótulo genérico ("comando que o gate nao mede").
- A mensagem do ramo `medivel` de `casaRedefinida` passa a usar `causasDoCdMenos(comando).join(", ")` no lugar da lista fixa, e mantém a saída ("troque o `cd -` pelo caminho absoluto").

Com payload de subagente no worktree, os vereditos não mudam:
- `cd -; export FOO=1; ls` sai 2, e o stderr contém `export` e não contém `bash -c` nem `$(`;
- `cd -; echo "$(pwd)"` sai 2 com `$(` e sem `export`;
- `cd - && bash -c "echo x > f"` sai 2 com `bash -c`;
- `cd -; eval x` sai 2 com `eval`.

Seguem como hoje:
- os casos `#573 D4` da bateria que exigem a saída do `cd -`;
- os casos que exigem a mensagem geral da casa (`cd; cd -; echo $(date)`, `HOME=<P>; cd -; echo $(date)`, `cd - ; echo ~ $(date)`).

Superfície humana: o agente lê a causa que de fato está na linha que ele escreveu. O critério falha se aparecer construto ausente.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`.

### 6. Bloqueio da camada de git em linha com `cd -` cita o `cd -` (#573) [tipo: implementar]
atende: D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 5
prova-na-base: verde — o caso entra na bateria existente; o vermelho desta tarefa é medido pela mutação
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `+ dicaDoCdMenos(entrada.command)`
  para: `+ ""`
  bateria: `bash hooks/testa-gate-worktree.sh`
  timeout: `3600000`
  fixture: `testa-gate-worktree.sh, secao "#573 D5: causa do cd - na mensagem", caso "cd - && git commit -m \"$(date)\" cita o cd -"`
pronto quando: forma do código:
- O `motivo` do ramo `if (verbo)` de `main` passa a ser `` `Comando que mexe no estado do repo: git ${verbo}` + dicaDoCdMenos(entrada.command) ``.
- A função de topo `dicaDoCdMenos(comando)` devolve `""` sem `cd -`/`pushd -` fora de aspas. Com eles, devolve uma quebra de linha mais o trecho que diz que a linha usa `cd -`, que o gate não sabe para onde ele leva, e manda trocá-lo pelo caminho absoluto do diretório.
- A detecção usa a mesma regex do ramo `medivel`.

Com payload de subagente no worktree:
- `cd - && git commit -m "$(date)"` sai 2, e o stderr contém `git commit` e `troque o \`cd -\``;
- `cd "$D" && git commit -m x` sai 2 sem o trecho do `cd -`;
- `git commit -m "cd - e outras"` (o `cd -` só dentro da mensagem) não ganha o trecho;
- `cd <W> && git commit -m "$(date)"`, com o caminho literal, sai 0.

Superfície humana: o agente barrado na camada de git recebe a saída do `cd -`. O critério falha se o trecho sumir.

Provado por `bash hooks/testa-gate-worktree.sh` com o placar `0 falha(s)`.

### 7. Versão 2.0.4, CHANGELOG e README [tipo: docs]
atende: D6, D2
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `docs/rainforest/estado/2026-10-23-conta-vigia.json`, `docs/rainforest/estado/2026-10-26-papel-da-skill.json`
depende de: 6
mutacao: n/a
  motivo: documentação e número de versão, sem comportamento a inverter. A coerência com a interface é conferida por `testa-versao.sh` e pela leitura do texto contra as decisões
pronto quando:
- A versão é `2.0.4` nos dois manifestos e no selo do README, provado por `bash scripts/testa-versao.sh` sem falha.
- A seção `2.0.4` do `CHANGELOG.md` cita #573, #580, #582 e #583 e descreve:
  - a regra da D1, com os três lugares (destino de redirecionamento em todo ramo, alvo dos dez escritores, expansão só no início);
  - o efeito da D2, em que `D=<fora>; touch "$D/f"` e `cp a.txt "$D/f"` passam a barrar, com a saída do caminho literal ou da ferramenta Write;
  - a #582 fechada por regressão, sem mudança de veredito;
  - as duas mensagens da D4 e da D5.
- O texto não diz que o gate resolve valor de variável. A leitura confere cada item contra D1 a D6 do design.
- Se o README descreve o que a rede do gate julga, a descrição passa a incluir o alvo de escritor com expansão no início.

## Retomada (2026-10-26)
Retomado na branch `fluxo/gate-worktree-retomada`, rebaseada sobre `e455fb40` (2.0.1). `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh` e `hooks/testa-corpus-comandos.cjs` não mudaram desde `f99164b6` (`git diff --stat` vazio), então as tarefas 1 a 6 valem como escritas; a versão da tarefa 7 passa de 1.74.1 a 2.0.2. A tarefa 7 também carrega o estado de fechamento de dois fluxos anteriores (`conta-vigia`, `papel-da-skill`), que só pode ir para a main na branch seguinte ao merge deles. O PR #603 entrou antes como 2.0.3, e a versão desta entrega passou a 2.0.4.
