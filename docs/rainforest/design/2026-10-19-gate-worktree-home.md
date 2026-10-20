# gate-worktree: HOME redefinido na linha falha fechado (#561)

## Objetivo
Linha que redefine a casa (`HOME`, `USERPROFILE`, `HOMEDRIVE`, `HOMEPATH`) e usa atalho de
home deixa de ser lida com a casa real: o `gate-worktree.cjs` a barra sem tentar adivinhar
para onde o atalho aponta. Hoje `HOME=<W>; touch ~/../../../f` passa, porque o gate expande
`~` para a casa real e o shell expande para o worktree, que sobe para o principal.

## Decisões fechadas
- **D1 — Regra ampla por menção, não lista de grafias** — porquê: a #552 tentou listar
  `HOME=`, `read HOME`, `printf -v HOME`, `$env:USERPROFILE=` e cada revisão achou uma grafia
  nova (`${HOME:-x}`, `export {HOME,X}=`, `$HOMEDRIVE$HOMEPATH`). A regra: tira da linha as
  formas de **leitura** (`$NOME`, `${NOME}`, `$env:NOME`, `${env:NOME}`, `%NOME%`); sobrando
  qualquer menção a um dos quatro nomes, a linha "mexe na casa". Mexendo na casa **e** usando a
  casa (o `ATALHO_DE_HOME` casa, ou há referência `$`/`${`/`%` a um dos quatro nomes), a rede
  devolve o alvo incerto: falha fechado. Só vale com cwd em worktree linkado, como toda a rede.
  *Emenda da revisão de segurança de `0c8b0991` (aplicada como recomendada, no espírito da Q2):*
  a menção se procura sem aspas nem escapes (`H""OME=`); com a casa em uso, comando que define
  variável pelo nome (`export`, `declare`, `read`, `unset`, `eval`, `env`, `printf -v`,
  `Set-Variable`, `Set-Item env:`, `iex`, `[Environment]::SetEnvironmentVariable`) também falha
  fechado, porque o nome pode vir montado (`export $(echo HOME)=`); e `cd`/`pushd` sem argumento
  conta como uso da casa. `export FOO=1; touch ~/x` dentro do worktree passa a cair.
  *Emenda da revisão de segurança de `a36ec012`:* qualquer `~` na linha conta como uso da casa
  (`{~,x}/..`), e, com a casa em uso, execução indireta falha fechado: substituição (`$(`, `<(`,
  crase no Bash), interpretador com `-c`/`-e`/`-Command`/`/c`, `source`/`.` em posição de
  comando, `[scriptblock]`, `$ExecutionContext`, `& {`, `Set-Item` e, no PowerShell, `env:` fora
  de leitura.
  *Emenda da revisão do fluxo (rodada 1):* "qualquer `~`" vira til em posição de expansão
  (início de palavra, depois de `=`, `:`, `,`, `(` ou `{`), porque `HEAD~1` não é a casa e
  barrava `git diff HEAD~1 | grep export`; `cd` sem destino aceita opções, redirecionamento,
  comentário e quebra de linha depois; `printf -v` colado ao nome, `mapfile` e `readarray`
  entram nos definidores; o interpretador com `-c` casa sem token no meio (`bash -c`, `-lc`).
  *Emenda da revisão do fluxo (rodada 2):* no Bash, o til e o `cd` entre aspas simples (ou duplas
  sem `$` nem crase) e no corpo de heredoc de dado não usam a casa, porque não expandem; sem isso
  o commit por heredoc com `~30 tokens` caía. Com interpretador na linha (`bash`, `node`, `eval`,
  `source`...), as aspas podem virar comando e nada se mascara: `grep "~" .; node -e "1"` cai
  (aceito). No PowerShell, atribuição composta (`+=`, `??=`), em lista (`$env:X, $y =`) e por
  `foreach ($env:X in ...)` contam como escrita, e `)` entra antes do til (`case`).
  *Emenda da revisão de segurança de `371a6b6b`:* a lista de interpretadores vira lista de
  comandos inertes: só se mascaram as aspas quando todo comando da linha não avalia argumento
  (`echo`, `printf` sem `-v`, `cat`, `grep`, `ls`, `touch`, `git` com subcomando de leitura ou
  commit, `gh pr`/`gh issue`...). `awk`, `find -exec`, `git -c alias` e qualquer outro deixam o
  texto cru, e a regra falha fechado. O `cd` sem destino se procura sem aspas (`"cd"` em
  posição de comando roda o `cd`).
  *Emenda da revisão de segurança de `e12adb1c` e da rodada 3 do fluxo (teto liberado pelo
  usuário, impasse em `docs/rainforest/portoes/2026-10-19-gate-worktree-home-impasse.md`):* a
  lista de inertes virou lista de grafias (`HOME=$OLDPWD; echo`, `printf -vHOME`,
  `>/dev/null HOME=x git push --receive-pack=...` passavam por inertes). Troca de princípio:
  linha que **mexe na casa** (menção a um dos quatro nomes fora de leitura, ou comando
  definidor) nunca tem as aspas mascaradas e cai sempre que usa a casa. A lista de inertes só
  vale para linha que não mexe na casa, onde serve para não barrar o commit por heredoc. O til
  depois de `-`, `+`, `?` (`${U:-~}`) e de crase também está em posição de expansão. Custo
  aceito: `git commit -m "ajusta HOME ~30"` dentro de worktree cai.
  *Emenda da rodada 4 do fluxo (teto liberado de novo pelo usuário, mesmo arquivo de impasse):* a
  lista de caracteres antes do til ainda era lista de grafias (`${X/y/~}`, `${Y#~}` passavam). Regra
  de classe: o til conta como uso da casa sempre que não vier depois de caractere de palavra (`\w`)
  nem de contrabarra. A continuação de linha (`\` + quebra no Bash, crase + quebra no PowerShell) se
  desfaz antes de procurar o nome, e `builtin`/`command` antes de `source`/`.` conta como execução
  indireta. Custo aceito: linha que mexe na casa ou chama interpretador e tem til fora de palavra
  (`@~1`) cai.
  *Emenda da rodada 5 do fluxo (teto liberado pela terceira vez, mesmo arquivo de impasse):* todas
  as checagens rodam sobre o texto com a continuação de linha desfeita, não só a busca do nome; e,
  com a casa em uso, `source`/`.` como palavra em qualquer posição (depois de `if`, `time`,
  redirecionamento, `builtin`, quebra de linha; procurado sem aspas nem escapes) é execução
  indireta. Custo aceito: linha que usa a casa e tem ` . ` solto (`git add . && cat ~/x.txt`) cai.
  O critério de contorno se fecha: conta a forma que a sessão escreveria sem intenção de escapar.
- **D2 — Caixa: exata no Bash, indiferente no PowerShell e no cmd** — porquê (Q1 do usuário):
  no Bash `home` minúsculo é outra variável e nome comum de pasta; no PowerShell `$env:home=`
  redefine `HOME`.
- **D3 — A linha inteira cai, mesmo só lendo** — porquê (Q2 do usuário): a checagem roda antes
  da segmentação, como a linha não confiável; `HOME=x; cat ~/f` também é barrado. Restringir a
  quem cita caminho do repositório deixaria escapar o caminho por variável, a classe que
  derrubou a #552. Caso legítimo raro; sem atalho de home na linha nada muda
  (`HOME=/tmp/h npm test`, `git commit -m "ajusta HOME"` seguem passando).
- **D4 — Bateria em `hooks/testa-gate-worktree.sh`, com os contornos da #552 e os vizinhos** —
  porquê: é o pronto da Issue. Contornos barrados: `HOME=`, `read HOME`, `printf -v HOME`,
  `export {HOME,X}=`, `${HOME:-<W>}` com `unset HOME`, `HOMEPATH=` com `$HOMEDRIVE$HOMEPATH`,
  `$env:USERPROFILE=` e `$env:home=` no PowerShell. Vizinhos que passam: leitura de `$HOME`,
  `home=` minúsculo no Bash, nome no texto sem atalho, os casos que já existem.
- **D5 — PATCH 1.70.1, CHANGELOG e comentário do código** — porquê (Q3 do usuário): conserto
  de trava, sem contrato novo. O comentário que dizia "HOME redefinido fica fora de escopo"
  passa a apontar a regra.

## Avaliado e descartado
- Lista de grafias de atribuição: é o que a #552 tentou e não fechou.
- Barrar só quando a linha cita caminho do repositório: ver D3.

## Fora de escopo
- Til com nome de outro usuário e casa mudada por arquivo de perfil do shell: o gate só vê a
  linha.
- Ofuscação deliberada fora das classes de D1 (nome montado por concatenação numa expressão sem
  cmdlet de variável, por exemplo): a trava protege contra o engano da sessão, não contra quem
  tenta escapar dela, o mesmo modelo de ameaça das outras travas.
- Referência indireta (`n=HOME; touch ${!n}/..`), lacuna que a rede já tinha para caminho por
  variável com chave, e `cd $VAZIA` (cd com variável vazia).
- Construção feita para escapar (decisão do usuário no teto da rodada 5): nome partido por
  continuação de linha dentro de `${...}`/`$NOME` além do que a junção da linha já cobre, nome
  montado por concatenação e interpretador chamado por caminho completo (`/usr/bin/perl -e`).

## Varredura
docs/rainforest/varredura/2026-10-19-gate-worktree-home.txt — só a #561 e a #552 (que a
originou) tratam do assunto.

## Em aberto
- (vazio)
