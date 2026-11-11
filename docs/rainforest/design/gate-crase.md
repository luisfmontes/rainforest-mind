# gate-fechar-issue confere o comando dentro de crases

## Objetivo
O `gate-fechar-issue` deixa passar `gh issue close` e `gh pr merge` dentro de crases (Issue #685): `` echo "`gh issue close 12`" ``, `` echo `gh issue close 12` `` e `` echo "`gh pr merge 5 --squash`" `` saem 0, e o bash executa o comando de dentro. A forma `$(...)` já é barrada desde o P4 (`segmentosParaGate`, 2026-09-04).

Brainstorm conduzido em modo autônomo (autorização do Luís em 2026-11-11: "pode decidir e executar no automatico"). Toda decisão abaixo é **decidido pela sessão**, com a opção recomendada, aberta a veto no PR.

## Decisões fechadas
- **D1 — Crase vira segmento adicional, como o `$(...)` entre aspas do P4.** Em `segmentosParaGate`, fora de aspas simples, uma crase não escapada (caractere anterior diferente de `\`) abre substituição até a próxima crase não escapada. O texto de dentro passa por `segmentosParaGate` recursivamente e cada pedaço entra na lista como segmento a mais. O texto original não muda e continua sendo o mesmo segmento de sempre. Crase sem par fecha no fim do comando. — porquê: é o mesmo mecanismo que já fecha `$(...)` dentro de aspas duplas, e não mexer no segmento original preserva as checagens que leem o texto inteiro (o corpo do `gh pr create --body` com crase continua ilegível e barrado). A recursão cobre crase dentro de `bash -c` e `;` dentro da crase.
- **D2 — Vale para as duas ferramentas.** No PowerShell, a crase é escape, não substituição. Mesmo assim, o pedaço entre duas crases (`"a`nb`tc"` dá `nb`) só barra se for ele mesmo um `gh` que escreve, então o falso positivo exige um texto que já é um comando de fechar Issue. — porquê: separar por ferramenta acrescenta um ramo que só evita falso positivo improvável.
- **D3 — Modelo de ameaça e parada.** Protege contra fechar Issue ou mergear PR por substituição de comando com crase, com ou sem aspas duplas. Fica fora: crase montada por variável (`c='`'; ...`), comando montado por substituição (`` `echo gh` issue close 12 ``), heredoc de delimitador nu para `cat` (já documentado como prosa em `verificarTextosDeHeredoc`), e comentário de shell com crase sendo barrado (falso positivo que o `$(` já tinha na base). Achado de revisão nessas formas não reabre o fluxo, vira ideia.
- **D4 — O conteúdo da crase é opaco para o rastreio de aspas de fora.** Depois de extrair o texto da crase, o texto bruto (crases incluídas) entra em `atual` e o índice salta para a crase de fechamento. — porquê: a revisão de segurança automática do commit da tarefa 1 mostrou `` echo `echo "`; gh issue close 12 `` saindo 0: a aspa de dentro da crase abria aspa no laço de fora e o `; gh issue close` virava texto citado. Já saía 0 na base, mas é a mesma classe deste fluxo.
- **D5 — Escape de crase como o bash.** Crase é escapada só com número ímpar de contrabarras logo antes (`escapadaPorContrabarra`), na abertura e no fechamento. Antes de recursar, o texto de dentro é desescapado como o bash faz dentro de crase (`\``, `\\`, `\$`). — porquê: a revisão 1 mediu `` echo `echo \`gh issue close 12\`` `` chamando o `gh` com o gate em 0 (crase aninhada), e a revisão de segurança automática apontou `` echo \\`gh issue close 12` `` (contrabarra literal mais crase viva).
- **D6 — O P4 recursa o conteúdo de `$(...)` entre aspas.** O conteúdo passa por `segmentosParaGate` em vez de entrar cru como um segmento só. — porquê: a revisão 1 mediu `` echo "$(echo `gh issue close 12`)" `` saindo 0, porque o P4 não descia na crase de dentro.
- **D7 — A crase é conferida também dentro de `$(...)` entre aspas, e a segmentação tem teto.** A versão anterior do D6 pulava a crase entre a abertura e o fim do `$(...)` (para não barrar mensagem de commit por heredoc citado), mas achava o fim contando parênteses sem entender aspas nem heredoc. `` echo "$(echo '(' ) '`gh issue close 12`' " `` saía 0 com o `gh` rodando (revisão de segurança automática do commit 6bbfa81), e um `)` sem par no heredoc reabria a crase (revisão 2). O pulo saiu. Mensagem de commit por heredoc que cite um `gh` de escrita entre crases passa a ser barrada: é o falso positivo que o `$(gh ...)` já tinha na base, e o contorno é `git commit -F <arquivo>`. Crase de texto que não é `gh` de escrita continua passando. O `segmentosParaGate` ganha teto de 2000 chamadas por evento; acima dele o gate barra. — porquê: a recursão percorre o texto de dentro mais de uma vez, e `"$(...)"` aninhado 20 vezes já levava 267 ms, dobrando a cada ~4 níveis; hook que estoura o tempo deixa o comando passar.

## Avaliado e descartado
- **Crase como fronteira de segmento (cortar `atual`):** cortaria o `gh pr create --body "`...`"` no meio, e a checagem de corpo ilegível deixaria de ver a crase no corpo inteiro. O P4 descartou a mesma coisa para `$(`.

## Fora de escopo
- O `gate-worktree` e os outros gates têm segmentadores próprios; este fluxo trata só o `gate-fechar-issue`.

## Varredura
docs/rainforest/varredura/gate-crase.txt — a Issue #685 é a única aberta sobre crase no gate; a #580 (fechada) é do `gate-worktree`.

## Em aberto
