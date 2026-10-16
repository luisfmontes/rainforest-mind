# gate-worktree: palavra do bash reconstruída, chaves, `bash -c` e crase (#530, itens 1 a 3)

## Objetivo

Fechar as nove formas medidas em 2026-10-15 (base `9f6b9ca3`) pelas quais um subagente num worktree linkado escreve no checkout principal sem o `gate-worktree` barrar. O desenho reaproveita a peça de desembrulhar que o repo já tem e enxerta do `ruvnet/ruflo` (MIT) a montagem da palavra e a expansão de chaves.

Medição de partida. O payload tem `agent_id`, `agent_type: executor` e `cwd` igual ao worktree, e `<P>` é o principal:

```
exit=2 :: cd <P> && echo x > f                      (referência)
exit=0 :: {cd,<P>} && echo x > f
exit=0 :: 'cd' <P>; echo x > f
exit=0 :: c\d <P>; echo x > f
exit=0 :: $'\x63d' <P>; echo x > f
exit=0 :: bash -c 'cd <P>; echo x > f'
exit=0 :: bash -c 'echo x > <P>/f'                  (escrita absoluta dentro de bash -c)
exit=0 :: echo `cd <P>; echo x > f`                 ($(...) equivalente já sai 2)
exit=0 :: echo "$(cd <P>; echo x > f)"              (substituição dentro de aspas duplas)
exit=0 :: echo "`cd <P>; echo x > f`"               (idem, com crase)
```

Cada forma foi conferida no bash real (Git Bash, script em arquivo), e todas mudam o cwd. **`{c,}d <P>` não entra**: o bash a expande para `cd d <P>`, que falha com `cd: too many arguments` sem mudar o cwd. O exit 0 do gate nesse caso está certo, e a forma vira caso vizinho na bateria. A primeira medição (comentário na #530) a listava como buraco porque eu tinha medido só o exit do gate.

## Decisões fechadas

- **D1 — Modelo de ameaça: o subagente que reescreve o comando até passar, não um adversário com shell livre.** — porquê: é o padrão observado (agente barrado reescreve até o gate liberar). O que fica de fora vira critério de parada da revisão: `GIT_DIR`/`--git-dir`, `cd` por função, alias ou script, `cd $VAR` e `cd $(...)` (hoje `incerto`, liberado a partir do worktree), cmdlet de escrita do PowerShell (#533) e semântica de união para `cd` condicional (item 4 da #530). Achado de revisão nessas classes não reprova a entrega: vai para a #530 ou a #533.
- **D2 — A escrita dentro de `bash -c` entra no escopo, junto com o `cd`.** — porquê: as duas se fecham pelo mesmo mecanismo, que é desembrulhar e passar o texto interno pelo mesmo cálculo de alvos de escrita (`alvosBashEscrita`, com `cwdPorSegmento`). `bash -c 'echo x > <P>/f'` com caminho absoluto é a forma mais grave das oito.
- **D3 — `bash -c`, `sh -c`, `eval` e afins passam por `desempacotarWrapperDeString` (`hooks/lib/tokens-comando.cjs`), com no máximo 4 níveis.** — porquê: a peça já é usada por `subcomandoGit` neste mesmo gate e por outros gates. Duas leituras do mesmo wrapper divergiriam. Conteúdo `ilegivel` (com `$`, crase, `$(`, ou arquivo de `source`/`.`) **barra**, como o caminho do git já faz. Passar de 4 níveis também barra.
- **D4 — Montagem da palavra e expansão de chaves numa lib nova, `hooks/lib/palavra-bash.cjs`, enxertada de `plugins/ruflo-mods/hooks/guard/dangerous-command.ts` (ruflo, MIT, crédito no cabeçalho).** — porquê: a lib junta pedaços de aspas, aplica `\` e decodifica `$'...'` com os escapes ANSI-C, guardando uma máscara paralela (`u` para sem aspas, `q` para com aspas ou escapado). Expande `{a,b}` só com chave e vírgula sem aspas, sem `{1..3}` e sem nada dentro de `${...}`. A expansão é aplicada **só à palavra em posição de comando** dentro de `resolverMovedor`. Isso preserva o conserto da #514 (chave em argumento não vira fronteira) e fecha `'cd'`, `c\d`, `$'\x63d'` e `{cd,<P>}`. As palavras expandidas substituem a primeira palavra do segmento, e o resto fica cru. Assim `{c,}d <P>` vira `cd d <P>`, que não casa com o `cd` de um argumento, como no bash. A palavra de expansão de chaves (`{` colado, fechando na mesma palavra, com vírgula) deixa de ser fronteira de segmento também em posição de comando, e o `incerto` que o #535 punha ali vira resolução exata. Chave com aspa, `$` ou crase dentro continua fronteira, e portanto `incerto`, como hoje.
- **D5 — Expansão que estoura o teto barra com exit 2, e a mensagem diz o motivo.** — porquê: o teto é de 4.096 palavras e 1.000.000 de caracteres de trabalho, como no ruflo. Nenhum comando legítimo chega perto disso, e liberar sem olhar contradiz o gate.
- **D6 — Corpo de substituição de comando lido como comando próprio: crase sem aspas, e `$(...)` e crase dentro de aspas duplas.** — porquê: hoje `echo $(cd <P>; echo x > f)` sai 2, e a crase e as duas formas entre aspas duplas saem 0, mas o bash executa as três do mesmo jeito. O corpo passa pelo mesmo cálculo de alvos do `bash -c` (D2/D3), partindo do cwd do segmento, até 4 níveis. Aspas simples não executam nada, e o texto ali continua sendo texto.
- **D8 — Entrega PATCH (1.67.x), com CHANGELOG e README.** — porquê: conserta um gate sem mudar contrato, e o README cita a versão.
- **D7 — Diferencial base × branch nos consumidores de `cwd-efetivo.cjs`, como no #535.** — porquê: `resolverMovedor` e o caminho de escrita são lib comum a 5 gates. Os casos que passam de 2 para 0 têm que ser zero. Os que passam de 0 para 2 têm que ser só as oito formas e seus gêmeos.

## Avaliado e descartado

- **Portar o `rescan` recursivo do ruflo (`hasRootDelete(body, depth + 1)` com `looseRootDelete`) para `bash -c` e crase.** O repo já tem `desempacotarWrapperDeString`, que cobre mais wrappers que o ruflo (`eval`, `pwsh -Command`, `-EncodedCommand`, `cmd /c`, `env -S`, `source`). Medido nesta varredura: `bash -c 'git -C <P> commit -m x'` já sai 2 por ele. Uma segunda leitura do mesmo wrapper divergiria da primeira.
- **Expandir chaves em toda palavra da linha.** Faria de novo a chave em argumento virar fronteira de comando, o falso positivo que a #514 consertou (PR #535).

## Fora de escopo

- Semântica de união para `cd` condicional (`&&`, `||`, corpo de bloco): item 4 da #530. É desenho, não mecânica.
- `GIT_DIR`/`--git-dir` e `cd` por função, alias ou script: #530.
- `cd $VAR` e `cd $(...)` a partir do worktree: hoje são `incerto` e liberados de propósito. Mudar isso é decisão de política, não buraco desta classe.
- Escrita por cmdlet do PowerShell: #533.

## Varredura

`docs/rainforest/varredura/gate-palavra-bash.txt`. Achou a #530 aberta (origem), a #514 e o PR #535 (o conserto da chave em argumento que a D4 preserva) e uma série de commits antigos de `bash -c` nos gates de git e de issue (`15f35257`, `795c2383`, `eeaaeab0`). Esses commits levaram à descoberta de `desempacotarWrapperDeString` e mudaram a D3: em vez de portar o rescan do ruflo, reaproveitar a peça do repo. Ideias casadas: `gate-worktree-barra-quem-esta-no-lugar-certo` e `trava-entrega-os-casos-que-ela-nao-pode-barrar`. Esta segunda pede que a bateria traga os gêmeos legítimos que precisam continuar passando, e entra no plano: `bash -c 'echo x > f'` dentro do worktree, `{a,b}` em argumento e `'cd' sub && echo x > f` no próprio worktree.

## Em aberto

- (nenhum)
