# Rodada 14: gh escondido do gate de fechamento (#692, #694, #699, #703, #708) e segmentador do heredoc (#706)

## Objetivo
Fechar as seis Issues da família do segmentador e do desempacotador de `bash -c`. Elas são
formas de esconder um `gh` de escrita do `gate-fechar-issue`, mais um falso positivo e o
caractere a mais que o segmentador cola depois de um heredoc. As revisões dos fluxos
`gate-segmentador` (#689) e `gate-publicacao-gh` (#702) acharam todas elas, e todas já existiam
na base.

Decisões tomadas pela sessão em modo autônomo, com a autorização do Luís de 2026-11-15
("vai consertando no fluxo em modo automático até ficar sem issue"). Cada uma vai no PR em
"Decidido sem você".

## Decisões fechadas
- **D1 — No `bash|sh|zsh|ksh|dash -c`, o script é só a PRIMEIRA palavra depois do `-c`.** Um
  `--` entre `-c` e o script é pulado. As palavras seguintes são `$0`, `$1`… e não rodam como
  comando. `desempacotarWrapperDeString` passa a desempacotar só essa palavra (`hooks/lib/tokens-comando.cjs`).
  A palavra é montada como o bash a monta: trechos citados e nus colados até o primeiro espaço
  fora de aspas. A checagem de palavra de aspas mistas com contrabarra do `gate-fechar-issue`
  (`mistaComGh`) olha só essa palavra (#699, #703, #708) — porquê: hoje o resto inteiro (`'script' x`)
  entra no desempacotador, e a aspa do script não sai. O argumento posicional esconde o `gh`, e
  ao mesmo tempo um argumento com aspas mistas barra um comando sem `gh`. Critério: os cinco
  comandos da #699 e `bash -c -- 'gh pr merge 5'` saem 2. `bash -c 'echo hi' x`, `bash -c --
  'echo hi'` e `bash -c 'echo hi' x -I"C:\x"` saem 0. `eval "echo"' \"; gh issue close 12'`
  continua 2.
  Emenda (revisão de segurança do commit da tarefa 1, 2026-11-15): um grupo curto com `c` em
  qualquer posição (`-co`, `-oc`) é o `-c`, e cada `o`/`O` de um grupo consome uma palavra antes
  do script. Palavra citada que, sem as aspas, começa com `-` ou `+` na zona de opções deixa a
  leitura ilegível (falha fechada). Rede de segurança: `gh` como palavra depois da palavra do script
  também deixa ilegível. Critério: `bash -co errexit 'gh issue close 12'`, `bash -oc errexit 'gh issue close 12'`,
  `bash -c '-o' errexit 'gh issue close 12'` e `bash -c -xo errexit 'gh issue close 12'` saem 2;
  `bash -co errexit 'echo hi'` sai 0.
- **D2 — `exec -a <nome>` consome o valor, `builtin` é prefixo que repassa, e `cmd` aceita `//c`
  e `//k` além de `/c` e `/k`** (#703, #694) — porquê: as três formas pulam o desempacotador hoje
  por um detalhe de tabela, e o bash e o MSYS as executam. Critério: `exec -a x bash -c 'gh issue
  close 12'`, `builtin eval 'gh issue close 12'` e `cmd //c bash -c "echo"' \"; gh issue close 12'`
  saem 2. `builtin echo x` sai 0.
- **D3 — `$IFS` e `${IFS}` valem espaço para o gate, no comando inteiro (ver a emenda).** Antes de
  segmentar, o `gate-fechar-issue` troca cada ocorrência por um espaço,
  só na cópia que ele analisa (#694) — porquê: o bash divide a palavra no `$IFS`, e o gate lia
  `gh$IFS` como uma palavra só. Critério: `gh$IFS issue close 12`,
  `gh${IFS}issue${IFS}close${IFS}12` e `echo "$(echo ')'; gh${IFS}issue close 12)"` saem 2.
  `echo "$IFS"` e `IFS=: read a b <<< "x:y"` saem 0.
  Emenda (revisão 1): a troca vale no comando inteiro, sem rastrear aspas (falha fechada). Rastrear
  aspas sem conhecer heredoc e comentário deixava um `Don't` no corpo de um heredoc esconder o
  `gh${IFS}issue${IFS}close${IFS}12` da linha seguinte.
- **D4 — Os quatro resíduos da #692.**
  - (a) A contagem de parênteses do `"$(...)"` (P4) pula a expansão `${...}` inteira, com as
    chaves balanceadas, e não conta o `)` que está dentro dela.
  - (b) A palavra do here-string que começa com `$'` ou `$"` é lida como palavra citada até a
    aspa que fecha. Hoje é lida só até o primeiro espaço.
  - (c) Na ferramenta PowerShell, a crase é escape: `` `" `` é uma aspa literal e não abre
    substituição.
  - (d) O teto do `segmentosParaGate` passa a ser a soma de caracteres varridos (orçamento fixo,
    determinístico), e não o número de chamadas. Estourado o orçamento, o gate barra sempre
    (falha fechada). Emenda de duas revisões de segurança da tarefa 3: cada procura do `gh` no
    estouro deixava passar um disfarce (`gh issue -R o/r close 12`, `gh issue {close,}`,
    `/usr/bin/gh`), e só o comando de mais de 2 milhões de caracteres varridos paga o custo.

  Porquê: cada um é uma forma medida de esconder o `gh` (itens 1 a 3) ou de o gate levar ~83 s
  (item 4). Critério: os seis comandos dos itens 1 a 3 da #692 saem 2. `echo "${x:-a}"`,
  `cat <<< $'texto'` e, no PowerShell, `` Write-Host "a`tb" `` saem 0. 3000 `$(true)` planos saem
  0, e o aninhamento de 16 níveis com 400 KB sai 2 em menos de 5 s. Estourado, sai 2 com ou sem `gh`.
- **Emendas da revisão 1 (D1, D2, D4).**
  - (D1) A rede de segurança olha palavra por palavra: barra quando `normalizarExecutavel(palavra)`
    é `gh`, e não quando `gh` aparece dentro de um caminho (`--repo gh/foo`, `/home/gh/y`). Palavra
    `$'...'` ou `$"..."` como script de wrapper ou de `eval` é ilegível nos dois gates. O gate de
    subagente lê o here-string que alimenta um shell (`bash <<< palavra`) como lê o `bash -c`.
  - (D2) O `cmd` aceita o comando colado à flag (`//cgh ...`, `/c"gh ..."`). O `pwsh`/`powershell`
    acha o `-Command`/`-c`/`-EncodedCommand` depois de outros parâmetros (`-NoProfile`,
    `-ExecutionPolicy Bypass`). O `fish` entra como wrapper de `-c`.
  - (D4b) No `$'...'` do here-string, `\n`, `\t` e `\r` viram o caractere. Escape hexadecimal e
    octal ficam fora (codificação, D6).
  - (D4d) Cada `"$(` cobra do orçamento só o trecho que o laço varreu até o `)` que fecha, e o
    heredoc canônico casa sem copiar o resto do comando. O custo fica linear no tamanho: 600 `"$(`
    em 12 KB estouravam o orçamento.
  Porquê: a revisão 1 reproduziu cada forma com o payload real.
- **Emendas da revisão 2 e das revisões de segurança automáticas (commits 4fb5da84 a 39c15107).**
  - (comentário) Linha com `#` que termina em contrabarra tem duas leituras: o `#` abre
    comentário e a contrabarra não continua nada, ou o `#` está citado ou escapado e o bash junta
    as linhas sem espaço. O `gate-fechar-issue` acompanha as aspas desde o início do comando e
    escolhe a leitura principal pelo que vê. A outra leitura vira segmento extra, julgado pelo
    gate normal, então só barra quando uma das duas é escrita de verdade. A junção atravessa
    várias linhas de continuação, inclusive vazias. Critério: `echo "a #b"; g\` + quebra +
    `h issue close 12` sai 2, e `gh issue comment 5 --body "ver #3" \` + quebra + `--repo o/r`
    sai 0, como na base.
  - (`$IFS` antes de `#`) `close$IFS#12` vira `close \#12`: o espaço separa a palavra, e a
    contrabarra impede que o gate leia comentário onde o bash não lê.
  - (here-string como script) No gate de subagente, `bash <arquivo> <<< palavra` lê o arquivo, e
    a palavra é dado. O caminho só conta como arquivo se não passar por `dev` ou `proc` e não
    tiver variável, substituição, glob, chave, til ou contrabarra. Opção com valor (`-o`, `+O`,
    `--rcfile`, `--init-file`) consome a palavra seguinte.
  - (PowerShell) `pwsh x.ps1` e `pwsh -File x.ps1` rodam arquivo. O `powershell.exe` lê o
    posicional como `-Command`, então o atalho de arquivo só vale quando o caminho é o texto
    inteiro. Caminho tem só caractere de caminho. `-ec` é apelido de `-EncodedCommand`.
  Porquê: cada forma foi reproduzida com o payload real, e o falso positivo do `#3` foi medido
  contra a base 7731a8c0.
- **D5 — O resto do comando depois de um heredoc começa depois do delimitador.** O
  `cmd.slice(heredoc.fim - 1)` vira uma função de `hooks/lib/heredoc.cjs`
  (`restoDepoisDoHeredoc`), usada nas duas cópias do segmentador: `gate-subagente-sem-gh.cjs`
  e `gate-fechar-issue.cjs` (#706) — porquê: o `- 1` cola o último caractere do delimitador no
  último token do comando (`novo.mdF`), e as duas cópias têm a mesma linha. Critério:
  `segmentosParaGate` sobre os três comandos da tabela da #706 devolve
  ` gh pr create --title t --body-file novo.md`, sem o caractere a mais, nas duas cópias.
- **D6 — Modelo de ameaça e parada.** O gate protege contra `gh` de escrita escondido pelas
  formas das seis Issues, além das que as rodadas anteriores já cobrem. Ficam fora o comando
  montado por variável que não seja `$IFS`, por substituição que precisa executar, ou por
  codificação (base64, `printf %b`), e a leitura de arquivo de script em disco. Achado de
  revisão fora do modelo não reabre o fluxo e não vira Issue. A janela principal o registra
  na seção "Fora de escopo" deste design como resíduo aceito, com o comando — porquê: sem modelo
  escrito, cada revisão acha um vetor novo. Foi assim que o #689 gerou seis Issues em oito
  revisões.
  Emenda (parada das revisões automáticas): a revisão de segurança que chega a cada commit
  trouxe 2–3 achados por commit, quase todos sobre as linhas recém-escritas. Cada achado novo é
  reproduzido contra a base 7731a8c0 e contra o HEAD. Se a base barra e o HEAD passa, é
  regressão e se conserta. Se os dois passam, vira resíduo nesta seção "Fora de escopo", sem
  commit.
- **D7 — Entrega em um PR, versão 2.16.0** — porquê: há comportamento novo nos gates. As seis
  Issues fecham pelo `fechar-issue.cjs` depois do merge.

## Avaliado e descartado
- Expandir variáveis em geral: as rodadas 9 e 12 mediram bypass em toda resolução estática
  (`docs/rainforest/design/zerar-issues-12.md`, D1). Só o `$IFS` entra, porque o valor dele é
  conhecido (espaço, tab, quebra de linha) e não depende do comando.
- Barrar todo `bash -c` com argumento posicional: o falso positivo da #708 mostra que isso
  barra um uso legítimo.
- Teto por relógio no segmentador: deixa o gate não determinístico (sugestão da própria #692).

## Fora de escopo
- Resíduo aceito (revisão 1, preexistente): `{gh,issue,close,12}` e `{gh,pr,merge,5}`, com a expansão de
  chaves montando o executável, passam na base e no HEAD. A rede W2 não conhece essa forma.
- Resíduo aceito (revisão 1, fora do modelo da D6): `gh${IFS:0:1}issue...` (expansão de
  substring) e `$'gh\x20issue...'` (codificação hexadecimal).
- Resíduo aceito (volta 2, fora do modelo da D6): `powershell "& ('g'+'h') issue close 12"` monta
  o executável por expressão do PowerShell, que precisa ser avaliada. É a mesma classe da
  substituição que precisa executar.
- Resíduo aceito (revisão 3, preexistente): o colapso de continuação dos dois gates não
  conhece o `\'` dentro de `$'...'` (`echo $'a\'b'` + quebra + `\` + quebra + `gh issue close 12`
  passa na base e no HEAD). A crase tira `\` + quebra antes de ler, uma terceira leitura que
  a regra das duas leituras não cobre (`` echo a `echo b #c \ `` + quebra + `echo don't` + quebra +
  `` gh issue close 12` ``). O gate de subagente não desce em crase (o `--` do `eval` passou a ser pulado na revisão 4).
  Os três passam na base e no HEAD; o `gate-fechar-issue` barra os do gate de subagente.
- Fechado na revisão 4: no gate de subagente, o `eval` confere também o texto depois da remoção
  de aspas que o bash faz antes de entregar as palavras a ele (`desasparComoBash`). Com isso, palavra mista
  (`eval '$'"'gh' issue comment 5"`), `\$\'` escapado e `eval "$'gh'" issue close 12`, que
  passavam na base ou no 6fed0986, saem 2. O fuzz de 130 formas da revisão 4 dá 0 regressões.
- Fechado na revisão de segurança do ab00f990: desde o db99558c (#699), a palavra mista chegava
  crua ao `eval`, e `eval 'gh issue close 12'""`, `eval 'g'"h issue close 12"` e
  `eval "gh"' issue comment 5'` saíam 0 no gate de subagente (a base barrava). Agora o texto
  desaspado é o próprio script lido no `eval`, e o `--` antes dele é pulado. O `iex` segue as aspas do
  PowerShell. `iex '$'"'gh' ..."` sai 0 no HEAD e saía 2 na base, mas não roda `gh` em shell
  nenhum: no PowerShell são dois argumentos e o `iex` dá erro, e no bash o `iex` não existe.
- Fechado na revisão 5: o gate de subagente tokeniza sem a opção `contrabarra`, e o `textoAPartir`
  remontava a palavra que mistura aspa dupla e contrabarra pela primeira aspa. `"gh"\` virava
  `"gh\"` e `"eval \"gh` virava `"eval \gh"`, então `eval "gh"\ issue\ close\ 12` e
  `bash -c "eval \"gh issue comment 5 --body hi\""` saíam 0 (a base barrava). A palavra mista
  com contrabarra passa a guardar o texto original (`raw`), como a palavra mista com aspa simples já
  guardava. Ainda saem 0 no HEAD e 2 na base formas com aspa dupla sem fechar (`eval "gh\" issue close 12`),
  que o bash não executa (erro de sintaxe).
- Resíduo aceito (revisão 5, preexistente): o gate de subagente não confere evento `PowerShell`;
  `gh issue comment` digitado no PowerShell de um subagente sai 0 na base e no HEAD. O
  `gate-fechar-issue` cobre o PowerShell para o fechamento.
- Resíduo aceito (revisão 3, fora do modelo da D6): `echo 'gh issue close 12' | bash` e
  `source <(echo 'gh issue close 12')` são script lido por pipe ou substituição.
- Resíduo aceito (revisão 3): linha de 100 KB de `# ` leva 2,6 s no regex das duas leituras
  (0,3 s na base); ninguém digita isso.
- Aceito (revisão 3 e revisões de segurança de 6fed0986 e 58bd9ab5): qualquer `((` antes do
  `#` deixa o comentário duvidoso, e `$(( n + 1 )) # chamadas ao gh` sai 2 (sem `gh` no
  comentário, sai 0). Contar `((` contra `))` sem rastrear aspas foi enganado duas vezes
  (`(( $((1)) # 2 ))`, `"))"` citado). É o mesmo custo aceito do `${`.
- Aceito (revisão 4): o mesmo vale para `$[` e `[[` em qualquer ponto antes do `#`, inclusive
  dentro de aspas e no PowerShell. `[[ -f x ]] && echo ok # roda gh depois` e
  `echo "a [[ b" # ls gh` saem 2; sem `gh` no comentário, saem 0.
- Aceito (revisão 4): o custo da leitura dupla não é linear quando toda linha tem `#` e termina
  em `\`. Com `echo hi #c \` seguido de 350 ou mais linhas `echo "linha #x" \`, o orçamento
  da D4d estoura e o comando sai 2 (falha fechada; 250 linhas saem 0). Sem `#` em cada linha,
  20.000 linhas saem 0 em 0,3 s.
- Aceito (revisão 3): `cat > doc.md <<'EOF'` + `# Title \` + `gh issue close 12` + `EOF` sai 2. A
  base já barra `gh issue close` em linha de corpo de heredoc (sem o `# … \` também sai 2) e só
  passava esse caso porque juntava as linhas e escondia o `gh`.
- O #707 (`gh api`, `gh release`, `gh gist` no gate de publicação) vai na rodada 15.

## Varredura
docs/rainforest/varredura/2026-11-15-zerar-issues-14.txt. A varredura acha as seis Issues abertas e os fluxos que as revelaram (gate-segmentador, #689; gate-publicacao-gh, #702). As decisões com âncora nos arquivos tocados estão intactas: 37 em gate-fechar-issue.cjs, 11 em tokens-comando.cjs e 6 em gate-subagente-sem-gh.cjs. O design herda as restrições delas, em especial a D1 da zerar-issues-12 (nenhuma expansão de variável) e a D9 do gate-segmentador (o # fica como na base).

## Em aberto
(nenhum)
