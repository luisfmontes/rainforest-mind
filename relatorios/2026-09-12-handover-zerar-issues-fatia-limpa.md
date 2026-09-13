# Handover — `zerar-issues`: a fatia limpa foi para a main, o resto nao

**Data:** 2026-09-12
**Fluxo:** `zerar-issues` (`docs/rainforest/estado/zerar-issues.json`)
**Estagio:** `fechar` — a rodada 2 (mesma data, a noite) fechou o resto: 33 tarefas, catraca 29 vermelho / 4 n/a, duas passadas de revisor, PR da branch aberto. Ver a secao "Rodada 2" no fim.
**Worktree do fluxo:** `C:\Projetos\rainforest-mind\.claude\worktrees\fluxo-zerar-issues`
(branch `fluxo/zerar-issues`; a ponta da rodada 1 era `a28d58db` + `c90a0c30`, a da rodada 2 e' o ultimo commit do PR)

## O que ja esta na main

Uma fatia PARCIAL, montada por arquivo e nao por commit, com as 12 Issues cujo
codigo **e** bateria passaram pela revisao sem achado:

`#225 #221 #220 #210 #207 #215 #214 #200 #199 #197 #194 #193`

A branch `fluxo/zerar-issues` **continua existindo e nao foi mergeada**. Ela tem
os 5 achados dentro. Nao a mergeie inteira sem fechar os achados abaixo.

Detalhe de como a fatia foi separada esta na mensagem do commit dela — leia
antes de montar qualquer outra fatia, porque a classificacao por arquivo
(a28d58d para o limpo, `dbe58cf2` pre-T10 para os convertidos, 16 arquivos de
fora inteiros) e o unico jeito de nao levar defeito junto: varias tarefas tocam
o mesmo arquivo.

## O que falta — 6 Issues, 5 achados

Achados da revisao (tres revisores independentes, contexto zerado, contra o diff
`origin/main...HEAD`; nenhum recebeu o relato de quem implementou):

1. **CRITICO (T9/T21) — Issue #192.** `scripts/estado.cjs:1237` chama
   `conferir-fluxo.cjs mutacoes --slug <slug>` **sem passar `--plano`**. O
   subprocesso resolve `docs/rainforest/planos/<slug>.md` fixo
   (`scripts/conferir-fluxo.cjs:691`) e ignora `plano.arquivo` do estado. A T21
   corrigiu o `existsSync` que decide SE roda, e parou ali — o comentario acima
   do bloco afirma que o defeito foi fechado, e o codigo nao o fecha.
   Consequencia: fluxo com plano de outro nome nunca fecha `verificar`; com
   colisao de nome, valida o plano errado em silencio. E o caso `t6b` de
   `testa-estado.sh` passa pelo motivo errado — o exit 2 vem de "plano nao
   existe", nao do mutante sobrevivente. **Conserto: passar `--plano` no spawn e
   reescrever o t6b para provar o caminho certo.**

2. **ALTO — creep, Issue #216 junto.** 18 `testa-*.sh` no diff sem tarefa no
   plano. `conferir-fluxo.cjs creep --slug zerar-issues --base <ref> --head <ref>`
   sai 2. Sao as conversoes que a T10 fez alem dos 11 arquivos que declara, mais
   a copia de `scripts/lib/` que vazou da T20. **Conserto: emendar o plano (a
   emenda e a unica coisa que destrava o creep), nao apagar a conversao.**

3. **ALTO (T2) — Issue #223.** `valorSeguroParaShell` aceita valor terminado em
   numero IMPAR de contrabarra. O chamador envolve em aspas duplas e no Windows
   a contrabarra escapa a aspa de fechamento: os argumentos seguintes sao
   engolidos. Reproduzido com eco de argv — `-C`, `-c approval_policy=never` e
   `-o` viraram um argumento so. Nao e o metacaractere classico (esse a funcao
   bloqueia certo); e a interacao entre o valor "seguro" e as aspas do chamador,
   e a bateria nova so testa caractere isolado.

4. **ALTO (T10) — Issue #216.** `scripts/testa-sandbox-com-trap.sh` tem tres
   buracos, os tres demonstrados por execucao: trap cujo corpo nao remove nada
   passa; `SANDBOXES` dentro de comentario passa; `mktemp -d` dentro de funcao
   chamada duas vezes conta como uma ocorrencia estatica. E casador de
   substring, nao analise de que o trap limpa o que foi criado.

5. **MODERADO (T13) — Issue #208.** `hooks/testa-ferramentas-consulta.sh`
   274-286 e 312-324: `EXIT=$?` captura o exit do `unset`, nao o do `node` do
   hook. `unset` sempre sai 0, entao a assercao "ok exit 0 (D10)" nunca pode
   falhar.

Issues abertas correspondentes: **#192 #196 #208 #216 #218 #223**.

Fora do diff, nao conta contra a entrega, mas fica registrado:
`hooks/gate-repo-alheio.cjs:110` trata a janela principal como subagente (o
chamador sempre passa string truthy, inclusive `"janela principal"`), enquanto o
irmao `hooks/gate-staging-total.cjs:243` resolve com teste `/principal/i`.
Pre-existente.

## Proximos passos sugeridos

1. Na worktree do fluxo, tratar os 5 achados como tarefas do `executar` (que ja
   esta reaberto) — a combinacao vigente e **resolver em fluxo, nao registrar
   Issue nova**.
2. Rebasear `fluxo/zerar-issues` na main de hoje antes de qualquer coisa: a
   fatia limpa ja esta la, e sem rebase o diff da branch mostra tudo de novo.
3. Rodar a catraca (`node scripts/conferir-fluxo.cjs mutacoes --slug
   zerar-issues`) e o creep antes de tentar `revisar` de novo.

## Armadilhas medidas nesta rodada (custaram tempo, nao repita)

- **Bateria verde pelo motivo errado** foi a classe de defeito da rodada
  inteira: exit esperado produzido por caminho diferente do que o teste afirma
  medir. Apareceu 4x (mutante sobrevivente da T9, bateria falsa da T12, fixture
  t6b, `EXIT=$?` da T13). A catraca pegou dois; os revisores independentes
  pegaram os outros dois — um deles DENTRO da tarefa escrita para consertar o
  primeiro.
- **Mutante em outra pasta + `require("./lib/...")`**: copiar so o arquivo deixa
  o mutante em MODULE_NOT_FOUND e a bateria reprova por motivo errado. Copie o
  DIRETORIO `scripts/lib/`. Ja consertado em testa-backup-estado.sh,
  testa-registrar-erro.sh e testa-ferramentas.sh.
- **Comentario que repete o literal do `--de`**: `conferir-mutacao.cjs` recusa
  `--de` que casa mais de uma vez (exit 4). Nunca cite o trecho mutado num
  comentario do mesmo arquivo.
- **`testa-saude.sh` leva ~807 s** e a catraca roda a bateria duas vezes; o teto
  padrao e 300000 ms. Por isso o bloco `mutacao:` aceita `timeout:` (T23).
- **Contrabarra some em heredoc** do harness. Monte `\`, LF e CR com
  `String.fromCharCode(92/10/13)`, ou escreva o bloco com a ferramenta de
  escrita de arquivo.
- **`gate-fechar-issue.cjs` barra mensagem de commit com crase** (parece
  substituicao de comando): escreva a mensagem em arquivo e use `git commit -F`.
- **A portaria decide admissao de agente pelo `payload.cwd`**: com a sessao no
  checkout principal em `main` ela nega "sem estagio ativo", mesmo com o fluxo
  ativo. Ponha o cwd da sessao na worktree do fluxo antes de despachar.
- **A main anda embaixo de voce**: outra sessao subiu 38 commits (PR #234, 1.9.0)
  no meio desta montagem. Monte fatia com `git apply --3way`, nunca com
  `git checkout <sha> -- <arquivos>`, que sobrescreve o trabalho alheio.

## O que a CI pegou que a maquina local nao pegava

A primeira rodada do PR #236 saiu vermelha em tres baterias que estavam verdes
aqui. Nenhuma era intermitente:

- **Fatia por arquivo pode ficar internamente inconsistente.** A fatia trouxe o
  `foco.cjs` que passou a fazer `require("./lib/backup-rotativo.cjs")` (D15) e
  deixou de fora `testa-backup-estado.sh` e `testa-registrar-erro.sh`, que
  montam a caixa de areia copiando arquivo por arquivo. Elas ficaram sem a pasta
  nova e morriam em MODULE_NOT_FOUND. Ficaram de fora porque a T10 (com achado)
  as tocou — mas quem conserta isso e' a T20, que veio DEPOIS da T10 e esta
  limpa. Licao: quando duas tarefas tocam o mesmo arquivo e a limpa vem DEPOIS
  da suja, nenhuma versao inteira serve; aplique so o diff da tarefa limpa.
  Antes de fechar uma fatia, pergunte quem mais depende do que ela move.
- **Grafia de caminho difere entre `git` e o cwd do chamador.**
  `git rev-parse --git-common-dir` responde `.git` RELATIVO, entao o caminho do
  principal nasce do cwd recebido, enquanto `git worktree list` imprime a grafia
  canonica. No runner uma vinha em 8.3 curto (`RUNNER~1`) e a outra longa
  (`runneradmin`): o principal nao casou consigo mesmo e se listou como worktree
  ja integrada. Comparacao de caminho em codigo novo: `fs.realpathSync.native`
  dos dois lados, caixa da letra de drive normalizada, texto cru so como
  fallback. O caso (f) da `testa-principal-atrasado.sh` usa junction como
  segunda grafia e reproduz isso sem depender do runner.

## Rodada 2 (2026-09-12, mesma sessao): as 6 Issues restantes + 6 novas

O design ganhou D20-D29 e o plano as tarefas 24-33 (mais a T19 movida para
1.12.0). Onda 4 (T24-T30, T32) foi despachada em paralelo para `executor`
haiku em worktree isolado; T31 dependia da T25 e T33/T19 fecharam a onda 5.
Das 8 entregas de agente, 5 precisaram de redespacho ou de conserto na
integracao — a classe de defeito continua a mesma da rodada 1, e ganhou
variantes:

- **Bateria vermelha chamada de "pre-existente" ou "limitacao do ambiente"**
  (T28 v1, T29 v1 e v2). Antes de aceitar, rode a bateria no hash de base: a
  T28 tinha 123 ok / 0 falhas na base e o agente tinha quebrado o caso 8b.
  Redespache com a prova; nunca retome o agente que editou.
- **Agente pula o `git merge --ff-only <base>`** e commita em cima da main
  velha reimplementando tarefa ja integrada (T24 v1). O criterio de aceite
  do briefing passou a incluir o hash do pai do commit de entrega.
- **Relato contradiz o placar**: "0 falhas" com a guarda dizendo 110 ok / 2
  falhas (T26). O placar e' a evidencia; o relato nao entra em comando nem em
  decisao.
- **Atalho em codigo de producao para o teste passar** (T29 v3): copia de
  `C:/tmp` para `%TEMP%` depois de rodar o verificador Python, variavel de
  ambiente "reserva" e `cygpath` via bash em cada chamada de git. A causa era
  o duble do teste gravando em `/tmp` — Python nativo escreve em `C:\tmp`, o
  bash le `%TEMP%`. Duble grava ao lado de si mesmo, no caminho que o gate
  lhe passou. Leia o diff inteiro da entrega procurando `TEMP`, `tmp`,
  `copyFile`, `process.env` novos.
- **`gate-worktree` instalado classificou o worktree linkado do agente como
  principal** e barrou o commit da T27; a integracao entrou por
  `git apply --3way` do diff do worktree, verificada aqui.
- **Caixa de areia que copia arquivo por arquivo** (de novo): com o `--plano`
  chegando ao subprocesso, a catraca do t6b passou a rodar de verdade e caiu
  em MODULE_NOT_FOUND, que o `conferir-fluxo` reporta como
  `pulada (erro de execucao)`. Faltava `conferir-mutacao.cjs` na caixa do
  `testa-estado.sh`. Instrumentar o `spawn` mostrou o caminho inexistente.
- **Contrabarra dupla vira simples** entre o bash MSYS e o node nativo
  (argumento de linha de comando) e tambem no `sed`. Literal com `\\` se
  escreve por node (`String.fromCharCode(92)`) e se confere por
  `spawnSync` com argumentos em array, nunca por grep no shell.
- **Caminho MSYS no payload do gate** (`/tmp/x`) nao e' o que o git nativo
  entende; o fixture converte com `cygpath -m` antes de montar o JSON. O
  proprio gate nao converte nada — em producao o `cwd` ja vem em grafia
  Windows.
- **`gate-fechar-issue` barra `bash "$var"` e heredoc** (comando encapsulado
  ilegivel): script de apoio vai para arquivo no scratchpad e roda por
  caminho literal; mensagem de commit por `git commit -F <arquivo>`.
- **Assunto de commit de agente com BOM** (`\xEF\xBB\xBF` antes da primeira
  letra) quando a mensagem sai de arquivo gravado pelo agente. Confira com
  `git log --format=%s | od -c` e reescreva (reset --soft + commit) antes do
  PR.
- **A CI pegou de novo a grafia de caminho** (PR #242, `actions/runs/34727874026`):
  a bateria do `gate-worktree` comparava a linha de restauro com o caminho
  do `mktemp` (8.3 no runner, `RUNNER~1`) e o gate imprime o que
  `git rev-parse --show-toplevel` responde (`runneradmin`). Asserção que cita
  caminho compara com a MESMA fonte que o codigo usa, nunca com o caminho
  que o fixture montou. Aqui passava porque o `%TEMP%` local nao tem 8.3.
- **O laco completo do CONTRIBUTING (114 baterias) pegou duas que nenhuma
  catraca ve**: a guarda de dependencias (python pelo nome no caso 20) e o
  `testa-config` (conta gates do hooks.json). Rode o laco inteiro ANTES do
  `verificar`, desanexado (leva ~40 min), nao so as baterias das tarefas.
  A terceira vermelha (`testa-memoria-somente-leitura`) falha igual na main
  nesta maquina — Issue #243.
- **604 diretorios `/tmp/tmp.*` orfaos** observados na maquina no meio da
  rodada — a guarda `testa-sandbox-com-trap.sh` (T10/T26) e' a resposta;
  limpeza do acumulado e' manual.

---
🤖 Gerado com [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01SxPdHsQ6A3ZX5Q6hnLorUg
