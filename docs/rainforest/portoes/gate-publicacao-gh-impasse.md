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
