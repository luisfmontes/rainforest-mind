# gate-fechar-issue: here-string, contrabarra e `"$(...)"` não escondem mais o `gh`

## Objetivo
Quatro defeitos do `segmentosParaGate` (Issue #689, todos já na base antes do fluxo `gate-crase`) deixam o bash executar `gh issue close` ou `gh pr merge` com o gate em 0. Tabela medida em 2026-11-11 na base `e3d7896`, com o payload real de PreToolUse e o mesmo comando no Git Bash com um `gh` falso que registra a chamada (gate / bash):

| comando | gate | bash |
|---|---|---|
| ``cat <<< `gh issue close 12` `` | 0 | gh executado |
| ``cat <<< "`gh issue close 12`"`` | 0 | gh executado |
| `cat <<< $(gh issue close 12)` | 0 | gh executado |
| `echo \"; gh issue close 12` | 0 | gh executado |
| ``echo \'`gh issue close 12` `` | 0 | gh executado |
| `echo "\""; gh issue close 12` | 0 | gh executado |
| `echo $'\''; gh issue close 12` | 0 | gh executado |
| `echo "$(echo ')' ; gh issue close 12)"` | 0 | gh executado |
| `echo "$(echo ')' && gh issue close 12)"` | 0 | gh executado |
| `echo "$(echo ')' ; gh pr merge 5)"` | 0 | gh executado |
| `echo "$(echo "'")"; gh issue close 12` | 0 | gh executado |

Vizinhos medidos que ficam como estão: `cat <<< "texto comum"` 0; `echo \"oi\"` 0; `echo "$(echo ')' ; echo oi)"` 0; ``echo '`gh issue close 12`'`` 0; `bash <<<'gh issue close 12'` 2; `echo 'a\'; gh issue close 12` 2 (em aspas simples a contrabarra não escapa); commit por heredoc com apóstrofo e `)` solto sem `gh` 0; no PowerShell, `cd C:\x\; gh issue close 12` e `Write-Host "C:\"; gh issue close 12` 2 (lá a contrabarra é literal).

Brainstorm conduzido em modo autônomo (autorização do Luís em 2026-11-11: "pode decidir e executar no automatico"). Toda decisão abaixo é **decidido pela sessão**, com a opção recomendada, aberta a veto no PR.

## Decisões fechadas
- **D1 — A palavra do here-string volta ao laço principal.** O ramo do `<<<` consome só os três `<` (`atual += "<<<"`, índice avança dois) e deixa o laço andar a palavra: crase, `"..."` e `$(` caem nos ramos que já existem. A extração de `conteudo` continua só para a recursão de interpretador (`bash <<<'...'`) e para o `TEXTOS_DE_HEREDOC`. — porquê: o defeito é o ramo engolir a palavra inteira (`atual += cmd.slice(i, k)`), e a palavra nua para no primeiro espaço; devolver a palavra ao laço é o conserto menor e não cria um segundo leitor de palavra.
- **D2 — Contrabarra escapa como no bash, só no Bash.** Com a ferramenta `Bash` (no PowerShell a contrabarra é literal): fora de aspas, `\` mais o caractere seguinte entram juntos em `atual` e o índice salta os dois; dentro de aspas duplas, `\` antes de `"`, `\`, `$` ou crase idem; aspas ANSI-C `$'...'` viram um estado de aspa próprio, em que `\` escapa o seguinte e a crase é literal. Aspas simples continuam sem escape. — porquê: o rastreio de aspas ignorava a contrabarra, e uma aspa escapada abria aspa na leitura do gate (`echo \"; gh issue close 12`). `"\""` e `$'\''` são a mesma classe, medidos na base, e entram aqui.
- **D3 — `"$(...)"` com interior que o gate não lê com segurança barra quando há `gh` de escrita depois.** No ramo do P4, se o interior achado pela contagem de parênteses tem aspa, crase, `#`, `<`, contrabarra ou a palavra `case`, e `temGhLiteralQueEscreve` acha um `gh` de escrita no texto do `$(` até o fim do comando, o gate barra como ilegível. É um gatilho booleano, sem contagem de `gh` verificado, e não depende do estado de aspas depois do `$(`. Vale para as duas ferramentas (no PowerShell `"$(...)"` também executa). — porquê: a causa dos defeitos 3 e 4 é o fim do `$(...)` sair de uma contagem de parênteses que não entende aspas, heredoc, comentário nem `case`, e o laço de fora reler o interior com o estado de aspas de fora. Um localizador de fim "mais esperto" foi o caminho que o D6→D7 do `gate-crase` já derrubou; falhar fechado só quando o interior é complexo e há `gh` de escrita deixa `cd "$(git rev-parse --show-toplevel)" && gh pr create --body-file x` passar (interior simples). Contagem de `gh` verificados foi descartada: a crase dentro de `"$(...)"` é visitada duas vezes, e uma visita dupla legítima compensaria um `gh` escondido.
- **D4 — Falso positivo aceito e contorno.** Fora da forma canônica do D6, `"$(...)"` com interior complexo seguido de um `gh` de escrita em qualquer ponto do comando passa a ser barrado (ex.: `x="$(cat <<EOF ...)" && gh pr create --body-file y`). Contorno: rodar o `gh` em comando separado; corpo por `--body-file`/`-F <arquivo>`. — porquê: sem achar o fim do `$(...)` com segurança, o gate não distingue o `gh` de depois do que está escondido; o leitor cego do plano mostrou que, sem o D6, a forma padrão de commit seguida de `&& gh ...` cairia aqui.
- **D6 — A forma canônica `"$(cat <<'DELIM'` ... `DELIM` + quebra + `)"` é opaca e isenta do D3.** No ramo do P4, quando o texto a partir do `$(` casa `/^\$\(cat <<'([A-Za-z_][A-Za-z0-9_]*)'\n[\s\S]*?\n\1\n\)/` (heredoc de delimitador citado, `cat` sem nada mais na linha, a primeira linha igual ao delimitador fecha, e o `)` vem logo depois), o interior é recursado como hoje, o texto casado entra em `atual` e o índice salta até o `)`; o `"` de fora fecha normalmente. — porquê: é a forma padrão de mensagem de commit do Claude Code; o fim dela é exato (o bash fecha o heredoc na primeira linha igual ao delimitador), e o corpo de heredoc citado é literal. Pular o corpo também fecha um furo da base medido no protótipo: `git commit -m "$(cat <<'EOF'` + `foo " bar` + `EOF` + `)"; gh issue close 12` saía 0 (a aspa do corpo dessincronizava o laço de fora) e passa a 2. Efeito colateral aceito e desejado: o falso positivo do D7 do `gate-crase` some para essa forma — commit por heredoc canônico que cita `` `gh issue close` `` entre crases volta a sair 0 (o caso (crase-12) muda de 2 para 0), porque o bash nunca executa aquele texto.
- **D5 — Modelo de ameaça e parada.** Protege contra `gh` de escrita escondido por here-string, contrabarra antes de aspa, `"$(...)"` com interior complexo e aspa no corpo do heredoc canônico. Fica fora: comando montado por variável ou por substituição (D3 do `gate-crase`), e o teto de segmentação (abaixo). Achado de revisão fora disso não reabre o fluxo, vira ideia ou Issue.

## Avaliado e descartado
- **Localizador de fim de `$(...)` que entende aspas:** heredoc com apóstrofo, comentário com `)` e `case x in a)` fazem o fim sair cedo; cada furo pede mais um caso, e o D6→D7 do `gate-crase` já pagou esse caminho.
- **Rede por contagem (textual > verificados):** visitas duplas do mesmo `gh` inflam o lado verificado.
- **Contrabarra também no PowerShell:** abriria `cd C:\x\; gh issue close 12`.

## Fora de escopo
- O teto do `segmentosParaGate` (2000 chamadas, Issue #689 "pontos de baixa"): limita chamadas, não trabalho, e um comando plano com mais de 2000 substituições bate nele. Vai para Issue própria no `fechar`, com a sugestão de limitar a soma de caracteres varridos (não o relógio, que deixaria o gate não determinístico).

## Varredura
docs/rainforest/varredura/gate-segmentador.txt — a #689 é a única aberta sobre here-string, contrabarra ou o segmentador.

## Em aberto
nada
