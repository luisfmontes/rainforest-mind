# Rodada 19: o resto da #736 — `cd X #comentário` e o segmentador do gate de bateria

## Objetivo

Fechar o que a rodada 18 (PR #741) deixou aberto na #736. Medido em 2026-11-26 no `main` `b76d80f8`:

1. **`cd X #comentário` não move o cwd.** As seis regex de movedor de `hooks/lib/cwd-efetivo.cjs` (`CD`, `PUSHD`, `POPD`, `SET_LOCATION`, `PUSH_LOCATION`, `POP_LOCATION`) ancoram em `\s*$` logo depois do destino. Com um comentário no fim, a regex não casa, o segmento não é movedor e o cwd segue o de antes, com `incerto:false`. Medido com o gate real, num repositório com worktree linkado:
   - a partir do worktree, `cd <principal> #c` + quebra + `git add -A` → `gate-staging-total` sai **0**; sem o `#c`, sai 2. O `git add -A` roda no principal;
   - a partir do principal, `cd <worktree> #c` + quebra + `git add -A` → sai 2; sem o `#c`, sai 0;
   - `gate-fechar-issue`, `gate-subagente-sem-gh` e `gate-publicacao-destino` leem `--body-file` relativo no diretório de antes do `cd`.
2. **`gate-bateria-sem-timeout` tem leitura própria e perde a linha de baixo** (comentário da #736 vindo da #740). Ferramenta Bash, payload com `agent_id`, sem `timeout`, os três saem 0 e o bash roda a bateria:
   - `echo $'\' <<'A''` + quebra + `bash hooks/testa-x.sh`. A máscara de heredoc do gate (`semCorpoDeHeredoc`, por linha) acha `<<'A'` dentro do `$'...'` e engole o resto como corpo;
   - `echo hi # don't` + quebra + `bash hooks/testa-x.sh`. O segmentador (`segmentosComAspasESubcomandos`) abre aspa no `'` do comentário;
   - `echo hi #x\` + quebra + `bash hooks/testa-x.sh`. O colapso de continuação (`colapsaContinuacaoDeLinha`) junta as linhas, e dentro de comentário a contrabarra é literal.

Já resolvido, só conferido: o primeiro comentário da #736, `echo ${x:-$'\'}<<\'A\''}` + quebra + `git add -A` + quebra + `A`, sai 2 no `gate-staging-total` do `main` (sonda de 2026-11-26).

Pedido do Luís em 2026-11-26 ("sim" à rodada 19 para fechar o resto da #736). Modo autônomo: as decisões são a recomendada, e ele revisa no PR.

## Decisões fechadas

- **D1 — Comentário no fim do movedor faz parte da sintaxe dele.** As seis regex aceitam `(?:\s+#.*)?` antes do `\s*$` final. `cd X #c` move para X, `popd #c` desempilha, `Set-Location X #c` move. Vale nas duas leituras de `segmentosComAspas`: a regex mora em `resolverMovedor`, que roda depois da segmentação nas duas.
  - **Porquê:** é o que o bash e o PowerShell fazem (o `#` depois de espaço abre comentário nos dois). Marcar `incerto` não serve: `gate-staging-total.cjs:371` usa o cwd do evento quando o segmento é incerto, a mesma resposta errada de hoje.
  - **Mão dupla:** o exit muda nos dois sentidos. A régua desta decisão não é "base barra ⇒ head barra": é `gate(cd M #c ⏎ cmd) == gate(cd M ⏎ cmd)`, no exit e no mapa de cwd.
  - **Modelo de ameaça:** o destino sem aspas é `[^\s;&|]+`, então `cd a#b` segue com destino `a#b` (o `#` no meio da palavra não abre comentário). `cd 'a #b'` e `cd "a #b"` seguem com o destino entre aspas. `cd #c` segue casando com destino `#c`, que não existe em disco e vira `incerto`, como hoje.
  - **Efeito na rodada 18:** os três gates fora da D4 deixam de ser idênticos à base nesse caso (`cd X #c`), e passam a rastrear o `cd` como o shell. A emenda vai no CHANGELOG.
- **D2 — Segunda leitura no gate de bateria, sem tirar a primeira.** `gate-bateria-sem-timeout` analisa o comando duas vezes e barra se qualquer uma achar bateria:
  - a leitura de hoje, intacta (`colapsaContinuacaoDeLinha` → `semCorpoDeHeredoc` → `segmentosComAspasESubcomandos`);
  - uma leitura nova sobre o comando **cru**: `mascararCorposDeHeredoc` (`hooks/lib/heredoc.cjs`, sem `scriptNaoShell`) → `segmentosComAspas(cmd, false)` (`hooks/lib/cwd-efetivo.cjs`, leitura nova) → cada segmento por `segmentosComAspasESubcomandos`, para separar `$(...)` e crase, que a lib deixa dentro do segmento.
  - **Porquê:** cada linha do Objetivo 2 morre num passo diferente da leitura de hoje (colapso, máscara, segmentador). A lib já lê os três como o bash desde a rodada 18. A união faz "a base barra ⇒ o head barra" valer por construção, como a D4 da rodada 18.
  - **Modelo de ameaça:** o gate é de categoria `guia` (bateria sem `timeout` em subagente). O risco do conserto é falso positivo, não fuga.
- **D3 — `cat <<EOF` sem aspas com bateria no corpo passa a barrar.** A máscara da lib não mascara corpo de heredoc com delimitador sem aspas, porque ele expande `$(...)`. A leitura nova vê a linha do corpo como comando. Aceito: é falso positivo de um gate guia, num padrão raro. O caso existente `cat <<'EOF'` (com aspas) segue saindo 0.

## Avaliado e descartado

- **Trocar a leitura do gate de bateria pela da lib:** perde o `$(bash testa-x.sh)` e a crase, que a lib deixa dentro de um segmento só (medido: `echo $(bash hooks/testa-x.sh)` vira um segmento com o `echo` na frente). A união com a leitura de hoje mantém os dois.
- **Marcar `incerto` quando a palavra é de movedor e a regex não casa:** no `gate-staging-total` o incerto cai no cwd do evento, que é justamente o erro (D1).
- **Tirar o comentário do segmento antes das regex, pela marcação de comentário da leitura nova:** os gates fora da D4 rodam na leitura antiga (`comLeituraAntiga`), que não marca comentário. A regex vale nas duas.

## Fora de escopo

- **Ferramenta PowerShell no gate de bateria:** o gate sai 0 para qualquer ferramenta que não seja Bash (`gate-bateria-sem-timeout.cjs:309`), por desenho. As linhas PowerShell do comentário da #740 ficam fora.
- **`cd X <# c #>` no PowerShell:** comentário de bloco depois do destino segue sem casar.
- **Gates fora da D4 com a leitura antiga:** `cd sub # don't` + quebra + `gh ...` segue perdendo a linha de baixo neles, porque a leitura antiga abre aspa no `'` do comentário. É o resíduo declarado da rodada 18 (os três gates ficam na leitura da base); não reprova esta rodada.
- **Política de `incerto` do `gate-staging-total`** (cwd do evento para `cd $VAR`): anterior, inalterada.

## Varredura

docs/rainforest/varredura/2026-11-26-zerar-issues-19.txt. Só a #736 aberta no tema; nenhuma ideia do `ideias.jsonl` casou. `deriva` em `hooks/lib/cwd-efetivo.cjs`: 10 decisões com âncora intacta e 1 perdida (revisita-context-mode D2, já sumida antes desta rodada); em `hooks/gate-bateria-sem-timeout.cjs`, a D9 da zerar-issues-15 (`--listar` não é varredura) intacta, e a D2 não a toca.

## Em aberto

(nada)

## Pronto quando

- D1: em `hooks/testa-cwd-efetivo.sh`, `cwdPorSegmento("cd <dir> #c\n...")` dá ao segundo segmento o cwd `<dir>`, igual a sem o `#c`, para `cd`, `pushd`/`popd` e `Set-Location`; os controles `cd a#b`, `cd 'a #b'` e `cd #c` mantêm o destino de hoje. Em `hooks/testa-gate-staging-total.sh`, a partir do worktree, `cd <principal> #c` + quebra + `git add -A` sai 2. Em `hooks/testa-gate-fechar-issue.sh`, `cd <B> #c` + quebra + `gh pr create --body-file corpo.txt` lê o corpo de B.
- D2: as três linhas do Objetivo 2 saem 2 em `hooks/testa-gate-bateria-sem-timeout.cjs`; o caso `cat <<'EOF'` existente segue 0; a bateria inteira fica com 0 falhas.
- `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-fechar-issue.sh`, `node hooks/testa-gate-subagente-sem-gh.cjs` e `bash hooks/testa-gate-publicacao-destino.sh` com 0 falhas.
