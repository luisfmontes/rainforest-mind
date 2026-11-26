# Rodada 18: o segmentador lê escape, `$'...'` e comentário como o shell (#736)

## Objetivo

Fechar as formas em que `segmentosComAspas` (`hooks/lib/cwd-efetivo.cjs`) lê uma aspa aberta que o shell não abre, engole a linha de baixo e deixa o `git add -A` dela fora da análise. Medido em 2026-11-25 na base `e9d2b14e` contra `hooks/gate-staging-total.cjs` num repositório de `git init`. Cada comando abaixo sai exit 0, e o bash executa a linha escondida (script com `echo RODOU` no lugar do `git add -A`, rodado no Git Bash):

1. **#736:** `echo $'\' <<'A''` + quebra + `git add -A` + quebra + `A`. O bash lê `$'\' <<'` como uma string ANSI-C só, e `<<'A''` não abre heredoc.
2. **#736 (comentário da Issue):** `echo ${x:-$'\'}<<\'A\''}` + quebra + `git add -A` + quebra + `A`.
3. **Escape fora de aspas (achado da sonda):** `echo \' ; git add -A`. O `\'` é aspa literal, e o segmentador abre aspa simples ali.
4. **Comentário (achado da sonda):** `echo hi # don't` + quebra + `git add -A`, e `echo hi # say "x` + quebra + `git add -A`. A aspa dentro do comentário abre aspa no segmentador.
5. **Comentário com contrabarra no fim (achado da sonda):** `echo hi #x\` + quebra + `git add -A`. O colapso de continuação (`colapsaContinuacaoDeLinhaNoTopo`) junta as duas linhas, mas dentro de comentário a contrabarra é literal e a quebra fecha o comentário.
6. **PowerShell (achado da sonda):** `echo hi # don't` + quebra + `git add -A` e `` echo `'; git add -A `` pela ferramenta PowerShell. A crase escapa a aspa no PowerShell.

Controles na mesma sonda, que o conserto não pode mudar: `echo 'a; git add -A'`, `echo $'a; git add -A'`, `echo a#b'; git add -A'` e `echo $#'; git add -A'` saem 0; `git add -A`, `echo \$'a\'; git add -A`, `echo "$'"; git add -A` e `git add a.txt # sem -A` saem 2.

Dois falsos positivos da base somem com a leitura fiel: `echo $'a\'; git add -A'` e `echo "a\"; git add -A ; echo b"` saem 2 na base e o bash não executa o `git` em nenhum dos dois.

Pedido do Luís em 2026-11-25 (rodada própria para a #736, recomendada aceita). Modo autônomo: as decisões são a recomendada; as marcadas *(suposição)* ele revisa no PR.

## Decisões fechadas

- **D1 — O segmentador lê escape e `$'...'` do bash.** Em `segmentosComAspas`, no dialeto bash:
  - fora de aspas e em aspas duplas, a contrabarra leva o caractere seguinte junto, sem efeito de aspa nem de fronteira;
  - `$'` fora de aspas abre uma aspa ANSI-C, em que a contrabarra leva o caractere seguinte e `'` fecha;
  - dentro de aspas simples nada muda.
  - O texto de cada segmento continua um trecho do comando: só a fronteira muda. É o que `cwdDoSegmento` (`hooks/gate-fechar-issue.cjs`) precisa para casar segmentos por texto.
  - **Porquê:** as formas 1, 2 e 3 são a mesma divergência, uma contrabarra que o bash lê e o segmentador não.
  - **Modelo de ameaça:** protege todo gate que segmenta pela lib (`gate-staging-total`, `gate-mensagem-commit`, `gate-worktree`, `gate-bateria-sem-timeout`, e `gate-fechar-issue` pelo `cwdPorSegmento`). Fica fora: `$'` dentro de `"${...}"` (o bash lê `$'` como ANSI-C dentro da expansão entre aspas duplas; o segmentador vê aspas duplas) e `$"..."` (lido como aspas duplas, que é o que o bash faz fora de locale).

- **D2 — Comentário e continuação de linha como o dialeto.** `#` sem aspa nem escape no começo de palavra (começo do texto, ou depois de espaço, `;`, `&`, `|` ou `(` que não foi escapado), fora de crase e de `${...}`, abre comentário até a quebra de linha; aspa e contrabarra dentro dele não contam. Vale no bash e no PowerShell. O colapso de continuação passa a ser `colapsaContinuacaoDoDialeto`: no bash, contrabarra ímpar + quebra some fora de aspas e em aspas duplas, mas não em aspas simples, em `$'...'` nem em comentário; no PowerShell, a continuação é a crase + quebra.
  - **Porquê:** formas 4, 5 e 6. A continuação tinha de saber de comentário, senão a forma 5 passaria a esconder a linha por outro caminho: o colapso juntaria as linhas antes e o comentário engoliria o `git`.
  - **Modelo de ameaça:** `a#b`, `$#`, `${#x}`, `x=#`, `$(x)#` e `<(x)#` não abrem comentário. Quem decide o que é comentário é só o colapso (`colapsaContinuacaoDoDialeto` devolve a marcação por caractere), e o segmentador pula o que vier marcado: os dois não podem discordar.
  - **Emenda da revisão de segurança automática (commit 8ffea4b2, 2026-11-25):** quatro formas em que o comentário novo escondia o `git` que o shell roda, todas medidas: `` echo `echo #`; git add -A `` (o `#` dentro da crase não passa da crase), `echo ${x:-a #}; git add -A` (nem do `}` de `${...}`, no bash e no PowerShell), `echo $(true)#; git add -A` (`#` colado a `)` é meio de palavra) e, no PowerShell, `echo <# x #>; git add -A` (o comentário de bloco fecha no `#>`, também atravessando a quebra). Depois de `<` e `>` o `#` também deixou de abrir comentário: o bash recusa a linha (`echo a >#x`), e a leitura que separa é a que não esconde.
  - **Segunda emenda da revisão de segurança automática (commit a0b55385, 2026-11-25):** `$$` é o PID, então `echo $${ # don't` + quebra + `git add -A` não abre `${` e o `#` comenta; e `echo $$'a\'; git add -A #'` não abre `$'` (este a base barrava: era regressão da rodada). O `$` só abre `${` ou `$'` depois de uma corrida par de `$`. E como a leitura de crase e de `${` pode errar o fechamento (crase solta no corpo de `bash <<'EOF'`, que não passa pela máscara), `#` aberto dentro delas deixa o resto da linha **neutro**: aspa e escape não contam, mas a fronteira separa. O erro possível vira falso positivo, nunca linha escondida. O colapso também passou a ser quem marca onde `$'` abre, e o segmentador só obedece à classe de cada caractere.
  - **Terceira emenda da revisão de segurança automática (commit bcd7e602, 2026-11-25):** o neutro aberto dentro de `${...}` ou de crase seguia até a quebra e ignorava a aspa real depois do `}` ou da crase de fechamento: `echo ${x:-#}'; cd x; '` virava um `cd x` que o bash não roda, e o cwd deduzido mentia. A leitura passa a ser a exata do bash enquanto crase e `${` fecham na mesma linha: em `${...}` o `#` é literal (não abre nada); dentro de crase o comentário fecha na crase, que fecha a substituição (`` echo `echo #`; ... `` roda o que vem depois, medido). O neutro fica só para depois de uma quebra com crase ou `${` abertos (construção em várias linhas, ou crase solta no corpo de heredoc executado), e aí o comando todo sai **incerto**: `segmentosComAspas` marca `segmentos.incerto`, e `cwdPorSegmento` e os dois leitores do `gate-worktree` (`alvosBash`, `alvosBashEscrita`) começam com `estado.incerto`, que já é o caminho conservador deles (usar também o cwd do evento).
  - **Quarta emenda da revisão de segurança automática (commit 6f2abe19, 2026-11-25):** crase com contrabarra antes (`` \` ``) fechava o comentário de dentro da crase, e a crase aberta dentro de `${...}` não mandava no `#` (os contadores eram independentes). O aninhamento de `${`, crase e `$(` passou a uma pilha, e o `#` obedece ao mais interno; dentro do comentário em crase, contrabarra leva o caractere seguinte. E uma rede para a família inteira: **aspa aberta no fim da leitura** — que o shell recusaria — prova que a leitura errou; o texto depois da aspa vira segmento também e a linha sai incerta. Só nos dialetos que leem escape.
  - **Quinta (commit 8a5bdc2c):** com `$(` aberto dentro de crase, o `#` virava comentário até a quebra e escondia `` echo `echo $(echo # `; git add -A ``, que a base barrava e o bash roda (medido). Dentro de crase o bash acha a crase de fechamento antes de olhar `$(` e `${`: a crase em qualquer nível da pilha manda no comentário, e ao fechar desempilha tudo o que abriu depois dela. `#` lido com mais de um nível na pilha deixa a linha incerta.
  - **Sexta (revisor do fluxo, head a29d6af2):** quatro formas que a base barrava e o head deixava passar, todas executadas pelo bash ou pelo PowerShell: (1) separador escapado no alvo de um redirecionamento que vem antes do comando (`<<\; git add -A`, `>out\; git add -A`), porque o escape junta o texto e o gate não acha o `git` depois do redirecionamento. O texto depois do escape vira segmento, e a linha sai incerta. (2) `\s` do JavaScript aceitava CR, NBSP e BOM como espaço antes do `#`; agora só espaço, tab e quebra. (3) `#` dentro de `$(( ))` e `(( ))` é literal (aritmética). (4) PowerShell `<#` só abre comentário no começo de token.
  - **Sétima (revisão automática do commit bf7dfb13):** o reconhecimento do alvo de redirecionamento pela palavra deixava passar `> "a b"\; git add -A` e `>$(echo a b)\; git add -A` (a base barrava, o bash roda). Passou a falhar fechado: basta `<` ou `>` em qualquer ponto antes do separador escapado. E o espaço antes do `#` passou a depender do dialeto: o PowerShell trata NBSP, FF, VT, U+2003, U+3000 e U+0085 como espaço e não trata BOM nem ZWSP (medido com `powershell -File`), então o conjunto só do bash fazia ler aspa dentro de comentário e esconder a linha seguinte.
  - **Resíduo declarado:** a leitura de `#`, crase, `${` e `$(` continua sendo um modelo do bash, não o bash. Forma nova em que ela diverge e o resultado é o mesmo da base (sai 0 na base e no head) não reprova esta rodada; forma em que ela esconde o que a base barrava, sim.
  - **Avaliado e descartado:** mudar `colapsaContinuacaoDeLinha` (`hooks/lib/tokens-comando.cjs`). Ela também serve o desempacotador e o `gate-fechar-issue`, que tem leitura própria de comentário com contrabarra (rodada zerar-issues-14). O colapso novo fica local ao segmentador.

- **D3 — O dialeto chega ao segmentador.**
  - `gate-staging-total` e `gate-mensagem-commit` passam o dialeto da ferramenta (`PowerShell` → PowerShell; `Bash` → bash) a `segmentosComAspas`. O `gate-staging-total` passa o mesmo dialeto a `cwdPorSegmento`, que tem de segmentar igual (o índice do segmento casa com o do cwd). O `gate-worktree` já passava `ehPowerShell`.
  - O texto desempacotado de um wrapper (`bash -c`, `pwsh -Command`, `eval`, `iex`) se segmenta no dialeto do wrapper (`dialetoDoWrapper`, exportada pela lib), mas só quando a linha de fora é bash. Com o PowerShell por fora, o desempacotador tira as aspas pelas regras do bash (`'a''b'` vira `ab`, não `a'b`), e ler escape nesse texto esconderia o que a leitura antiga via (`bash -c 'echo \''; git add -A'` pela ferramenta PowerShell). Aí, e em `cmd /c` e wrapper desconhecido, vale a leitura "sem-escape", que é a de antes desta rodada.
  - **Porquê:** no PowerShell a contrabarra é literal e `$'` não é aspa. Ler `echo $'a\'; git add -A` pelo bash esconderia um `git add -A` que o PowerShell executa (medido: `powershell -File` com essa linha roda o segundo comando).
  - **Avaliado e descartado:** reusar `dialetoDoWrapper` de `hooks/gate-fechar-issue.cjs`. Ela devolve só Bash/PowerShell, sem a leitura sem escape, e mora no gate, não na lib. Trazê-la para a lib mexeria no `gate-fechar-issue`, fora do escopo.

- **D4 — Duas leituras, uma decisão (decidido pelo Luís em 2026-11-26, depois da segunda reprovação do revisor do fluxo).**
  - **O que é:** `gate-staging-total`, `gate-mensagem-commit` e `gate-worktree` rodam o `main` duas vezes pela `hooks/lib/duas-leituras.cjs`: primeiro com a leitura nova (D1 a D3); se ela libera (exit 0), de novo com a leitura antiga ("sem-escape" em toda chamada de `segmentosComAspas`, ligada por `definirLeituraAntiga`). Barram se qualquer das duas barrar. A entrada é lida uma vez e servida às duas passadas; exit diferente de 0 na primeira sai na hora. A segunda passada só roda quando o comando tem contrabarra, crase, `#`, CR ou `$'`, os únicos pontos em que as leituras divergem.
  - **Porquê:** a leitura nova junta texto que a antiga separava, e a antiga pegava comandos justamente por separar. Cada revisão achou uma forma em que a base barrava e o head não (sete emendas, e a segunda volta do revisor achou mais quatro: escape de `(`, `)`, `{`, `}` no alvo de redirecionamento, `\|&`, crase + CR + LF no PowerShell, e estouro de pilha pela recursão do remendo de redirecionamento). Corrigir forma por forma não convergia: o remendo da sexta emenda causou o estouro de pilha (exit 1, que não bloqueia) e falsos positivos no `gate-worktree`. Com duas leituras, "a base barra ⇒ o head barra" vale por construção.
  - **Medido antes de decidir:** a leitura "sem-escape" do head é idêntica à da base `e9d2b14e` em 200 mil linhas aleatórias, Bash e PowerShell (0 diferenças em `segmentosComAspas`).
  - **O que sai:** os dois remendos que só existiam para recuperar o que a base pegava. O texto depois de aspa aberta no fim deixa de virar segmento (quarta emenda) e o separador escapado depois de `<`/`>` deixa de abrir segmento (sexta e sétima). Tirados um a um, nenhum caso de gate ficou vermelho; só os testes de unidade dos próprios remendos.
  - **O custo, aceito:** voltam os falsos positivos da base, porque a leitura antiga barra o que barrava: `echo $'a\'; git add -A'`, `echo "a\"; git add -A ; echo b"`, ``echo "a`"; git add -A"`` no PowerShell, `cmd /c "echo a\" & git add -A"` e `echo $$$'a\'; git add -A'`. E fica um falso positivo da quinta emenda no `gate-worktree`, de subagente em worktree: atribuição com crase em várias linhas (`` x=`echo a`` + quebra + `` echo b` ``) seguida de commit deixa a linha incerta.
  - **Fora da D4:** `gate-fechar-issue`, `gate-subagente-sem-gh` e `gate-publicacao-destino` recebem da lib só o cwd (`cwdPorSegmento`), e o `main` deles guarda estado de módulo (texto de heredoc, contador de varredura), o que tornaria a segunda passada insegura. Medido com os casos do revisor: nenhuma regressão no `gate-fechar-issue`.
  - **Avaliado e descartado:** juntar os segmentos das duas leituras numa lista só. O `gate-worktree` deduz o cwd pela ordem dos segmentos, e a união embaralharia a ordem.

## Avaliado e descartado

- **Mudar `colapsaContinuacaoDeLinha` (`hooks/lib/tokens-comando.cjs`)** para conhecer comentário e `$'...'`: ela também serve o desempacotador e o `gate-fechar-issue`, que tem leitura própria de comentário com contrabarra (zerar-issues-14). O colapso novo fica local ao segmentador (D2).
- **Reusar `dialetoDoWrapper` de `hooks/gate-fechar-issue.cjs`:** devolve só Bash/PowerShell, sem a leitura sem escape, e mora no gate (D3).
- **Ler o texto de `bash -c` chamado pelo PowerShell no dialeto bash:** esconde `bash -c 'echo \''; git add -A'`, que a leitura antiga barrava (medido na execução, D3).
- **Seguir emendando a leitura nova forma por forma:** sete emendas e duas reprovações do revisor sem convergir, e o remendo da sexta emenda estourou a pilha. Trocado pela D4.
- **Encerrar a rodada sem merge e levar o #736 ao `/brainstorm`:** a opção B da decisão de 2026-11-26. Recomendada a D4.

## Fora de escopo

- Desaspar pelas regras do PowerShell o texto de wrapper chamado pela ferramenta PowerShell (`''` dentro de aspas simples, crase em aspas duplas). É defeito do desempacotador (`hooks/lib/tokens-comando.cjs`), anterior a esta rodada. A D3 só evita que a leitura nova piore esse caso.
- A classe da máscara de heredoc (#737).

## Varredura

docs/rainforest/varredura/2026-11-25-zerar-issues-18.txt. Só #736 e #737 abertas no tema. As fechadas mais próximas (#313, #339, #689, #692) consertaram escape e `$'...'` no texto de wrapper e no segmentador próprio do `gate-fechar-issue`, não em `segmentosComAspas`; seguem valendo, e esta rodada não toca nenhum dos dois. Nenhuma ideia do `ideias.jsonl` no tema.

## Em aberto

(nada)

## Pronto quando

- Os casos 1 a 6 do Objetivo saem exit 2 na seção da rodada 18 de `hooks/testa-gate-staging-total.sh`, os controles mantêm o exit, e a bateria inteira fica com 0 falhas.
- `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-fechar-issue.sh`, `node hooks/testa-gate-bateria-sem-timeout.cjs` e `node hooks/testa-gate-subagente-sem-gh.cjs` ficam com 0 falhas.
- D4: a seção "D4: propriedade" de `hooks/testa-gate-staging-total.sh` imprime `violacoes 0` numa amostra com semente fixa de comandos gerados contra o gate da base `e9d2b14e` (base barra ⇒ head barra, e o head nunca sai 1), e fica vermelha com a segunda passada desligada.
