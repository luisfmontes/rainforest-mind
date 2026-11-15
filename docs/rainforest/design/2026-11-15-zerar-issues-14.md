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
- **D3 — `$IFS` e `${IFS}` fora de aspas simples valem espaço para o gate.** Antes de
  segmentar, o `gate-fechar-issue` troca cada ocorrência fora de aspas simples por um espaço,
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
- O #707 (`gh api`, `gh release`, `gh gist` no gate de publicação) vai na rodada 15.

## Varredura
docs/rainforest/varredura/2026-11-15-zerar-issues-14.txt. A varredura acha as seis Issues abertas e os fluxos que as revelaram (gate-segmentador, #689; gate-publicacao-gh, #702). As decisões com âncora nos arquivos tocados estão intactas: 37 em gate-fechar-issue.cjs, 11 em tokens-comando.cjs e 6 em gate-subagente-sem-gh.cjs. O design herda as restrições delas, em especial a D1 da zerar-issues-12 (nenhuma expansão de variável) e a D9 do gate-segmentador (o # fica como na base).

## Em aberto
(nenhum)
