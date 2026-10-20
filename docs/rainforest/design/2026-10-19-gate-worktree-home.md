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

## Varredura
docs/rainforest/varredura/2026-10-19-gate-worktree-home.txt — só a #561 e a #552 (que a
originou) tratam do assunto.

## Em aberto
- (vazio)
