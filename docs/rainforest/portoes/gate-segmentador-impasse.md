# Impasse: gate-segmentador (Issue #689)

Três revisões reprovaram, cada uma com bypass novo aberto pelo próprio diff (gate do HEAD em 0, da base em 2, `gh` executado no Git Bash com stub).

| revisão | causa | consertado em |
|---|---|---|
| 1 | remontagem do wrapper cega à contrabarra (D8); fim do heredoc canônico (D6) | tarefas 8, 9, 11 |
| 2 | `#` do D9 engolindo `; gh` depois de `)`/`${`; here-string de interpretador com `\"` (D1) | tarefas 13, 14, 15 |
| 3 | `#` do D9 engolindo `$(gh ...)`/crase/`<(` depois de `)`/`${` (alta); here-string de palavra nua com aspa (`bash <<< echo\ x";gh issue close 12"`, média); crase do PowerShell escapando `#` (média) | — |

**Leitura:** duas das três reprovações vêm do D9 (comentário). O defeito que ele ataca (`# it's done` + quebra + `gh issue close 12`) já existia na base; cada versão do D9 troca um furo preexistente por um furo novo, porque o gate não sabe, sem um parser de palavras do bash (`$(`, `${`, `<(`, aritmética), quando o `#` abre comentário.

**Opções para a 4ª rodada:**
- **A (recomendada):** tirar o D9 inteiro (o `#` volta ao comportamento da base) e levar o comentário com apóstrofo para a Issue #692; consertar só o achado 2 (here-string de palavra nua com aspa: falhar fechado quando a palavra tem aspa e a linha tem interpretador). Remove os achados 1 e 3 de uma vez.
- **B:** manter o D9 e segmentar também em `$(`, crase, `<(` e `>(` dentro do comentário. Fecha os achados 1 e 3 conhecidos, mas segue a mesma classe que já reprovou duas vezes.
- **C:** fechar o fluxo no estado atual: não, há regressões altas contra a base.

## 4ª rodada (opção A) e a 4ª reprovação

A opção A foi aplicada (D9 revogado, tarefas 16 e 17). A revisão 4 reprovou com um achado novo do diff e quatro preexistentes:

| achado | origem | destino |
|---|---|---|
| `echo $$'\'; bash -c 'gh issue close 12'; echo '\'` sai 0 (base 2): `$$'` lido como ANSI-C | tarefa 2 (D2) | consertado na tarefa 18 (ad-6, ad-7; mutação vermelha) |
| rede do D3 não conhece `gh api` de merge/fechamento | preexistente | Issue #692 |
| `powershell -NoProfile -Command ...` não desembrulha | preexistente | Issue #692 |
| heredoc sem aspas no delimitador executa `$(...)`/crase no corpo | preexistente | Issue #692 |
| `tokensComAspas` não conhece `$'...'` (`FOO=$'\'' gh issue close 12`) | preexistente | Issue #692 |

Nenhum achado reprovado é do D9 nem do here-string; o único do diff é de uma linha, e a correção não reabre decisão do design.

## 5ª reprovação (revisão 5, sobre d3036ad)

| achado | origem | situação |
|---|---|---|
| `eval echo\ x\;gh pr merge 5`, `bash -c echo\ \'x\'\;\ gh\ issue\ close\ 12` e variantes (14 no fuzz do revisor) saem 0 no HEAD, 2 na base, `gh` executado | D8: `textoAPartir` remonta token com espaço como `'...'` com `'\''`, que o desempacotador não reverte; `eval` com vários argumentos não junta os valores | aberto |
| `echo it\'s; gh pr create --body-file b.md` barra (HEAD 2, base 0) | D2 × `cwd-efetivo.cjs` cego à contrabarra; falha fechada, caminho absoluto passa | aberto (baixa) |
| texto de `gh` passado a `bash` por pipe de `echo` passa | preexistente | Issue #692 |

**Leitura:** a quinta revisão seguida acha furo novo aberto pelo próprio diff, agora na remontagem do D8. O revisor rodou um fuzz (mais de 5000 comandos, bash real com stub) que a bateria não tem; cada rodada só descobre o furo na revisão.

## Sexta reprovação (revisão 6, 2026-11-12)

O fuzz local da quinta rodada, refeito com log por processo, não achou contorno aberto pelo diff em 2.400 casos executados. O revisor 6, com geradores novos (`fuzz2.cjs` g4 e g5, ~12 mil casos), achou duas classes, ambas conferidas pela janela com o bash real e o stub de `gh`:

1. **[alta] Palavra com aspas mistas no `eval`/`bash -c`.** `internoDoEval` e `textoAPartir` decidem a redução de contrabarra pela primeira aspa do token e a aplicam ao token inteiro. `eval -- "echo"' \"; gh issue close 12'` e `eval "eval \"echo\"' \\\"; gh issue close 12'"` passam no HEAD (0) e a base barrava (2). Variantes (`bash -c`, `env bash -c`, `command eval`, `time eval`) já passavam na base, na classe do D8.
2. **[media] ANSI-C com `\xHH` ou octal dentro de `"$(...)"`.** A rede do D3 tira aspas mas não decodifica: `echo "$(echo ')' ; gh issue $'clo\x73e' 12)"` executa `gh issue close 12` com HEAD 0 e base 0.
3. **[media] CHANGELOG duplicado** no commit f4044697 (2070 para 4139 linhas, bullet da 2.12.3 truncado). Erro da janela (replace com `$\``), observação plantada.
4. **[baixa]** texto entre aspas com `gh` de escrita depois de um `"$(...)"` é barrado (D3 usa string como executável).
5. **[baixa]** `cwd-efetivo` cego à contrabarra, já declarado no CHANGELOG como falso positivo aceito.

Padrão das seis rodadas: cada revisão acha uma construção nova de quoting que a remontagem textual do `eval`/`bash -c` interpreta diferente do bash. Remendar a remontagem converge devagar.

## Sétima reprovação (revisão 7, 2026-11-12)

O fuzz r7 da janela (5.400 casos) não achou contorno; o revisor 7, com gerador novo (g6, `$'` falso antes do `gh`), achou:

1. **[alta] Regressão da decodificação de ANSI-C (D3).** A regex `\$'...'` casa num `$'` falso (fim de `'$'`, ou `"$'"`), e `iss\ue` vira `iss`+U+000E. O comando de prova está em `scratchpad/rev/r8c.json` da sessão: com um `echo '$'` antes de `gh iss\ue close 12` dentro de `"$(...)"`, o bash executa o fechamento com HEAD 0; a versão da 6ª rodada barrava (2). 46 de 1.500 casos do g6.
2. **[media] Achado 2 da 6ª segue aberto** quando um `$'` falso desloca os spans: `$'clo\x73e'` não é decodificado. Base e 6ª rodada também passam — não é regressão.
3. **[media] Falso positivo novo no PowerShell.** `mistaComGh` vale para `&`, `cmd /c`, `pwsh -Command` e `iex`, onde a contrabarra é literal: `& "C:\Microsiga\advpls.exe" appre x.prw -I"C:\Microsiga\includes"` passa a ser barrado (base 0). O D8 só fala de `eval`/`bash -c`.
4. **[alta] [preexistente]** `bash -c "<gh de escrita>" x` (argumento posicional depois do script) passa no HEAD e na base. Fora das Issues #692 e #694.

**Leitura:** sete rodadas, e cada rede nova abre uma classe nova. O que converge é parar de acrescentar decodificação e fechar só as regressões contra a base, mandando as classes preexistentes para Issue.

## Oitava reprovação (revisão 8, 2026-11-12)

Critério desta rodada (Q1 B do Luís): a branch não pode ser mais fraca que a base `e3d7896d`. **Contornos: nenhum novo.** O revisor comparou cerca de 100 casos manuais, um fuzz diferencial de cerca de 2.900 comandos com bash real e um corpus de 9.700 comandos dos transcritos locais. Nenhum caso com HEAD 0 e base 2 em que o bash executasse o `gh`. Os bypasses achados passam também na base: estão nas Issues #692, #694 e #699, e os novos foram para #703 e para um comentário em #694.

Reprovou por **falso positivo novo contra a base**:

1. **[alta] [design] Rede do D3.** Qualquer aspa dentro de `"$(...)"`, seguida de `gh` de escrita no mesmo comando, barra. Exemplos que saem 2 no HEAD e 0 na base, sem nada de errado executado:
   - `cd "$(dirname "$0")" && gh issue comment 5 --body-file f.md`
   - `echo "feito: $(git log -1 --format='%h %s')" && gh issue comment 12 --body-file m.txt`
   - no PowerShell, `$f = "$env:TEMP\b-$(Get-Date -Format 'HHmmss').md"; ...; gh issue create --body-file $f`

   O D4 aceitou esse falso positivo no primeiro desenho, e o CHANGELOG fala em "interior complexo". Só não diz que uma aspa simples qualquer já conta.
2. **[media] [design] `mistaComGh`** olha todos os tokens depois do wrapper, não só o script. `bash -c 'echo hi' x -I"C:\x"` barra sem nenhum `gh` no comando.
3. **[media]** A versão 2.12.3 ficou atrás da `origin/main` (2.13.1). Resolve no rebase do `fechar`.
4. **[baixa]** O texto da D8 descreve aspas simples onde o código usa duplas.
5. **[baixa]** O cabeçalho do caso (cm-8) da bateria dá `bad substitution`.

**Leitura:** a regressão de segurança que motivou as rodadas 2 a 8 está fechada (nenhum contorno novo contra a base). O que sobra é o preço da falha fechada do D3, que existe desde o primeiro desenho.
