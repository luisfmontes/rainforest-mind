# Revisita do `mksglu/context-mode` — #514 (gate barra leitura com chaves), ranking bm25 no `buscar`, livro de repos

## Objetivo
O Luís trouxe o `context-mode` de novo em 2026-10-15. A revisita do livro já era devida: 65 dias desde
2026-08-11 e push em 2026-10-14. Ela foi feita lendo o código, com três leitores em paralelo. Esta entrega
fecha o que a revisita e a sessão acharam no próprio repo:
- o falso positivo do `gate-worktree` (#514), que o leitor de sandbox da revisita também sofreu;
- a busca do CLI de memória, que ordena por data e não por relevância.

Também registra a revisita no livro e planta os enxertos.

## Decisões fechadas
- **D1 — #514 (P1): redirecionamento para `/dev/null` ou `$null` não é alvo de escrita em
  `alvosBashEscrita`. `NUL` continua sendo alvo.**
  - Porquê: os dois descartam a saída. No bash, `$null` expande para vazio: dá "ambiguous redirect" e não
    escreve nada. `NUL` fica de fora porque no MSYS/Cygwin `> nul` pode criar um arquivo literal `nul`.
  - Medido em 2026-10-15 na base `bae41ad3`, com Explore no principal: `(ls x) 2>/dev/null` sai 2 e
    `(ls x) > $null` (PowerShell) sai 2. Só P1 conserta esses dois.
- **D2 — #514 (P2): `{…}` deixa de ser fronteira de segmento em `segmentosComAspas`
  (`hooks/lib/cwd-efetivo.cjs`) só quando é expansão de chaves em posição de argumento.** As três
  condições:
  - (a) fecha na mesma palavra, sem espaço, aspas, `$`, crase, parêntese ou outra chave dentro;
  - (b) tem `,` ou é uma sequência `x..y` com as duas pontas alfanuméricas;
  - (c) o segmento já tem uma palavra de comando antes. Atribuição `A=1`, redirecionamento, palavra
    reservada (`if then else elif do while until time !`) e wrapper (`builtin command exec eval env sudo
    nohup xargs nice`) não contam como palavra de comando.

  Fora disso o comportamento é o de hoje, e `&{git checkout main}` (que tem espaço) continua cortando.
  - Porquê: a causa raiz é `cwd-efetivo.cjs:138-160`. O `{` vira segmento de um caractere e marca
    `incerto`. Com qualquer alvo já presente, o cwd do principal entra como alvo. A hipótese da issue
    apontava para `alvosBashEscrita`, e não é ali.
  - Só P2 conserta `ls 2>/tmp/x.log; echo a/{b,c}/d`: medido 2, deve ir a 0. Sem as chaves sai 0.
- **D3 — `memoria.cjs buscar --texto` ordena por `bm25(observacoes_fts)`, com desempate por
  `criada_em DESC`. Sem `--texto`, continua por recência.**
  - Porquê: hoje devolve o mais recente que casa. Em 2026-10-15, `buscar --texto "context-mode"` trouxe
    primeiro uma observação sobre rubricas.
  - Os hooks de abertura e de assunto não passam por `cmdBuscar`: usam `hooks/lib/memoria-assunto.cjs`,
    que já ranqueia. Então a seleção medida por `uso_memoria` não muda.
  - A query segue a forma de `buscarCandidatas` (JOIN + `ORDER BY bm25`), e o catch que repete a busca com
    os termos citados fica.
- **D4 — A revisita entra na linha existente do `vigias/livro-de-repos.md`: a linha mantém a data
  2026-08-11 e ganha "revisita 2026-10-15: …". Os 4 enxertos restantes são plantados pelo
  `ideias.cjs plantar`, cada um com a nota de licença ELv2 ("reimplementar, não copiar").**
  - Porquê: o livro não sobrescreve avaliação. O 5º enxerto (bm25) é entregue aqui (D3), e plantá-lo seria
    ruído.
- **D5 — Os três contornos que o gate já tem viram uma Issue própria, fora desta entrega:
  `{cd,<principal>}`, `A=1 cd <principal>` e `if …; then cd <principal>; fi`. Os três saem 0 na base,
  medidos a partir do worktree.**
  - Porquê: é defeito do repo, mas alheio à #514. D2 não pode piorá-los, e pela condição (c) não piora.
  - *Emenda de 2026-10-15 (security review do commit `79a6a60c`):* D2 piorava, sim, por outro caminho. Na base, uma chave inocente **antes** na linha (`echo {a,b}; A=1 cd <principal>; git commit`) marcava a linha toda como incerta e barrava por acaso, e sem isso esses casos passavam (medido: base 2, branch 0). A P1 da #530 entra nesta entrega: `semPrefixoSintaticoDeBuiltin` pula atribuição (`A=1`, `A="a b"`) e palavra reservada (`then do else elif if while until time !`) antes de testar `cd`/`pushd`. `{cd,X}` e a P2 da #530 continuam fora.
  - *Emenda 2 de 2026-10-15 (security review do commit `deeb1692`):* tomar `then cd X` como certeza era fail-open. A partir do principal, `if false; then cd <worktree>; fi; echo x > f` escreve no principal, e o gate liberava (base 2, branch 0). Agora `cd`/`pushd`/`popd` depois de `then`/`else`/`elif`/`do` marca `incerto`. `A=1 cd X`, `if cd X` e `! cd X` continuam como certeza, porque o `cd` roda. *(Refutado pelo revisor, ver emenda 3.)* Argumento de superfície para o D2: na branch, uma palavra com chave em posição de argumento é tratada igual a uma palavra comum. Então todo comando com chave que passa tem um gêmeo sem chave que já passava na base. A base só barrava por acaso o comando que usava chave (`false && cd X`, por exemplo, passa nas duas e é #530).
  - *Emenda 3 de 2026-10-15 (revisor, volta 1, reprovado):* o argumento só vale com a classificação argumento×comando certa, e ela não estava. O prefixo era partido por espaço sem respeitar aspas nem `\`. Com isso, `A="a b" {cd,<P>}`, `> "a b" {cd,<P>}`, `\builtin {cd,<P>}` e `"eval" {cd,<P>}`, seguidos de `git commit`, passavam (base 2, branch 0), e o bash roda `cd <P>`. Conserto: com prefixo fora do conjunto `[\w\s./:=+,@%-]`, a chave segue fronteira. Os 9 casos estão na bateria com caminho **sem** aspas dentro da chave: com aspas, a mutação sobrevivia, porque a chave já era fronteira por outra regra.
- **D6 — Entrega num PR só, com bump de patch sobre `origin/main` no `fechar`. A #514 é fechada pelo
  `fechar-issue.cjs` depois do merge.**
  - Porquê: são consertos pequenos e independentes.

## Avaliado e descartado
- Instalar o `context-mode`: continua não acoplando. Registra seis hooks, reescreve o prompt de todo
  subagente, nega o WebFetch, roda `npm install` sozinho e não é sandbox de verdade.
- Isentar `NUL`: risco de criar arquivo literal no MSYS.
- Parar de cortar em `{` sem a condição (c): abriria `{cd,X}` em posição de comando quando o cwd não é o
  worktree.
- Opção `--ordem recentes` no `buscar`: YAGNI, porque sem `--texto` já lista por recência.

## Fora de escopo
- Os três contornos do D5, que vão para a Issue.
- Os enxertos 2 a 5, que ficam plantados:
  - trigram + RRF;
  - decisão Q→A do AskUserQuestion;
  - snippet por `highlight()`;
  - bloco de retomada com teto.

## Varredura
docs/rainforest/varredura/revisita-context-mode.txt — a única issue aberta é a própria #514. Nenhuma branch remota tem os termos. O `context-mode` só aparece no PR #84 (livro). O bm25 só aparece no #436 (fechada) e nos PRs #437/#305, que ranqueiam a injeção por assunto e não o `buscar` do CLI.

## Em aberto
(nenhum)
