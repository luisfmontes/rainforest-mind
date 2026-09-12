# Handover — `zerar-issues`: a fatia limpa foi para a main, o resto nao

**Data:** 2026-09-12
**Fluxo:** `zerar-issues` (`docs/rainforest/estado/zerar-issues.json`)
**Estagio:** `executar` REABERTO (o `revisar` reprovou com 5 achados)
**Worktree do fluxo:** `C:\Projetos\rainforest-mind\.claude\worktrees\fluxo-zerar-issues`
(branch `fluxo/zerar-issues`, ponta `a28d58db` + o commit de estado `c90a0c30`)

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

---
🤖 Gerado com [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01SxPdHsQ6A3ZX5Q6hnLorUg
