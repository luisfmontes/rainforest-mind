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
- **D6 — Crase dentro de `$(...)` entre aspas fica com a recursão do P4.** O bloco da crase não age entre a abertura e o fechamento de um `$(...)` dentro de aspas duplas (`fimDolarAspas`), e o P4 passa a recursar o conteúdo por `segmentosParaGate` em vez de empurrá-lo cru. — porquê: a revisão 1 mediu `git commit -m "$(cat <<'EOF' ... `gh issue close` ... EOF)"` passando de 0 para 2, com a crase sendo texto do heredoc citado; e `` echo "$(echo `gh issue close 12`)" `` saía 0 porque o P4 não descia na crase.

## Avaliado e descartado
- **Crase como fronteira de segmento (cortar `atual`):** cortaria o `gh pr create --body "`...`"` no meio, e a checagem de corpo ilegível deixaria de ver a crase no corpo inteiro. O P4 descartou a mesma coisa para `$(`.

## Fora de escopo
- O `gate-worktree` e os outros gates têm segmentadores próprios; este fluxo trata só o `gate-fechar-issue`.

## Varredura
docs/rainforest/varredura/gate-crase.txt — a Issue #685 é a única aberta sobre crase no gate; a #580 (fechada) é do `gate-worktree`.

## Em aberto
