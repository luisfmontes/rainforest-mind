# Impasse: gate-publicacao-gh (#702)

Três revisões reprovadas, cada uma achando outra forma de o texto ou o destino escapar do gate.

## Revisão 1
`gh` depois de heredoc, wrappers de string (`bash -c`, `sh -c`, `eval`), corpo de PR por `"$(cat <<'EOF' ...)"`, here-string do PowerShell e `close`/`reopen --comment` saíam 0 em repositório público.

## Revisão 2
Here-string com apóstrofo ímpar (a segmentação perdia o `gh`), stdin (`printf ... | gh ... -F -`, `<<<`), variável escrita no mesmo comando e `cd` dentro de `bash -c`. Decisão do Luís (Q2 A): o comando inteiro conta como texto.

## Revisão 3
1. **[alta]** URL posicional (`gh issue comment https://github.com/<dono>/<público>/issues/3`) não virava destino; o cwd decidia.
2. **[alta]** O comando inteiro passou por todos os detectores: `--body-file C:/Users/<nome>/...` barrava por caminho de home, `--author-email` por e-mail, nome de arquivo com data por telefone. Regressão contra a base.
3. **[media]** A rede para o `gh` que a segmentação perde não lia o `--body-file`.
4. **[baixa]** Corpo em UTF-16 e `GH_REPO` por `Set-Item Env:`: comentário na Issue #707.
5. **[baixa]** Comentário do código contradizia o código; um caso da bateria não sabia falhar.

A janela confirmou ainda que `gh issue new` é apelido de `create` (`gh issue create --help`).

**Decisão (Luís, 2026-11-13, "vai no automático" sobre a recomendada):** quarta rodada. URL posicional como destino, `new` como apelido de `create`, só o termo privado olha o comando inteiro (caminho, e-mail e telefone voltam aos valores de flag e ao conteúdo dos arquivos), a rede lê o `--body-file`, comentário e caso da bateria corrigidos, baixas na #707.

## Revisão 4
1. **[alta]** Continuação de linha do PowerShell (crase + quebra) deixava `--repo dono/publico` e `--body-file` da linha de baixo fora do segmento do `gh`.
2. **[media]** Um `gh` perdido depois de outro achado escapava: a rede só rodava sem nenhum achado.
3. **[media] [design]** JID e credencial em heredoc/here-string saíam 0: a emenda da revisão 3 deixou o corpo embutido só contra a lista de termos.
4. **[baixa]** A rede lia mal `--body-file` entre aspas com espaço, com `)` ou crase grudados, e relativo depois de `cd`.
5. **[baixa]** Bateria sem caso de continuação do PowerShell.

Nenhuma regressão contra a base; URL posicional, apelido `new` e filtro de termo passaram.

**Decisão (modo automático do Luís, 2026-11-13, recomendada):** quinta rodada com 1 a 4 consertados (tarefas 16 a 19), o item 3 restaurando o D2 original para corpo embutido. `xargs -I{}`, `cd` relativo na rede e JID por stdin/variável vão para a #707.

## Revisão 5
1. **[media]** A rede do `gh` perdido era mais estreita que a gramática: com aspa ímpar antes, `gh issue --repo X comment` e `gh "issue" create` saíam 0.
2. **[media]** Falso positivo com destino privado e cwd público quando o texto tem termo e cita um `gh issue|pr <verbo>`.
3. **[media]** Versão atrás da `origin/main` (2.13.3 e 2.14.0 já saíram).
4. **[baixa]** Caso de crase dentro de aspas simples não discrimina as duas leituras.
5. **[baixa]** A mutação da tarefa 19 lançava exceção em vez de reverter a leitura.

**Decisão (modo automático do Luís, 2026-11-13, recomendada):** sexta rodada, a última. A branch foi mesclada com a `origin/main` antes; o item 1 se conserta (tarefa 20), o 2 fica como falso positivo aceito e documentado no design, no CHANGELOG e no PR, com contorno rodado; o 3 vira 2.14.1; o 5 troca a mutação; o 4 vai para a #707. A revisão 6 confere o código mesclado e só reprova por contorno ou regressão novos contra o `ea57521d`.
