# aviso-fluxo deixa passar arquivo ignorado pelo git

## Objetivo
O `hooks/aviso-fluxo.cjs` barra o Edit/Write/MultiEdit de arquivo de código sem fluxo aberto, inclusive quando o arquivo está no `.gitignore` (Issue #623). Arquivo ignorado não entra em commit nem em PR, então não há fluxo a exigir: o bloqueio só desvia a edição para o shell, que o gate não vê. Este trabalho deixa passar o arquivo ignorado e mantém o bloqueio de todo o resto.

Conduzido pela sessão a partir da Issue #623 em 2026-10-29, sob a autorização permanente de seguir o fluxo com a recomendada. As decisões ficam marcadas no PR para veto.

## Decisões fechadas
- **D1 — Arquivo ignorado passa** — quando o hook já ia barrar (sem fluxo aberto e sem `leve`), ele roda `git -C <toplevel do arquivo> check-ignore -q -- <caminho relativo>` e, com exit 0, sai 0 sem mensagem. — porquê: o que o gate protege é o histórico da branch, e um arquivo ignorado não chega a ele. A checagem fica por último, só no caminho que ia barrar, para não gastar um processo `git` a mais em toda edição que já passaria.
- **D2 — Arquivo rastreado continua barrado, mesmo que case com o `.gitignore`** — usa o `check-ignore` sem `--no-index`. — porquê: medido em 2026-10-29, o `check-ignore` padrão devolve 1 para arquivo rastreado que casa com um padrão do `.gitignore` (adicionado com `git add -f`), e `--no-index` devolve 0. Arquivo rastreado entra no próximo commit, então tem de continuar barrado.
- **D3 — Falha do git não libera** — exit diferente de 0 no `check-ignore` (1 = não ignorado, 128 = erro) mantém o bloqueio. — porquê: a trava fecha na dúvida. Liberar por erro de ambiente transformaria qualquer falha do `git` em passe livre.
- **D4 — O comentário do `aviso-fluxo-shell.cjs` deixa de afirmar o contrário** — ele diz hoje que "código em pasta ignorada pelo git não aparece (o Edit já o barra)". Passa a dizer que o arquivo ignorado fica fora dos dois hooks. O README ganha a mesma ressalva na linha do `aviso-fluxo.cjs`. — porquê: a frase vira falsa com D1.
- **D5 — Contra quem protege, e o que fica fora** — continua protegendo contra a janela principal editar código que vai para o histórico da branch padrão sem fluxo. Ficam fora: arquivo ignorado (sem histórico, sem fluxo); extensão que não é de código (já passava). — porquê: modelo de ameaça escrito, para a revisão parar nele.
- **D6 — Versão 2.1.3** — PATCH, com entrada no CHANGELOG e bump nos dois `plugin.json`. — porquê: só conserta comportamento de um hook existente, sem contrato novo (tabela do `CONTRIBUTING.md`).

## Avaliado e descartado
- **Deixar passar só na branch padrão** — a Issue nasceu na `main`, mas um arquivo ignorado não entra no histórico em branch nenhuma. Restringir à padrão manteria o mesmo desvio para o shell nas outras.
- **Checar o `.gitignore` lendo os padrões em Node** — reimplementaria a semântica do git (negação, `.git/info/exclude`, `core.excludesFile`) e erraria nas bordas. O `check-ignore` é a fonte.

## Fora de escopo
- O `aviso-fluxo-shell.cjs` não muda de comportamento: ele decide pelo `git status`, que já não lista arquivo ignorado.

## Varredura
docs/rainforest/varredura/2026-10-29-aviso-fluxo-gitignored.txt — a única Issue aberta sobre o tema é a própria #623. Os precedentes são a #430 (o aviso virou bloqueio) e a #564 (o hook de shell, cujo comentário D4 corrige).

## Em aberto
nada
