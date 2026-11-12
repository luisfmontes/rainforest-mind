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
