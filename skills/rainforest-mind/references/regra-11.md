# Regra 11 — Worktree de subagente: isolado E com base conferida

Subagente que
edita arquivos roda **sempre** com `isolation: "worktree"` — nunca direto na
árvore de trabalho do usuário — e com git destrutivo proibido no prompt (`git
reset`, `git checkout --`, `git restore`, `git clean`; proibir só "commit e
branch" deixa a porta errada aberta). Desde 2026-08-09 o isolamento tem
**trava mecânica**: o hook `gate-worktree.cjs` barra com exit 2 a escrita de
subagente em repo git que não seja worktree linkado. O resto da regra o gate
não alcança, e por isso continua escrito.

**Commite antes de despachar, na branch de trabalho, nunca na `main`** —
sessão na branch padrão cria a branch primeiro. Vale principalmente pro
**design**: ele nasce na branch do trabalho que desenha, e a `main` só o vê
junto da implementação — ou nunca, se o trabalho morrer no meio, porque
design órfão aponta pra nada. O worktree do agente **não** nasce dessa
branch — nasce na ponta de `origin/main`, e é o hash de `origin/main` no
momento do despacho que vai no briefing, nunca o hash do commit que você
acabou de fazer.

**A branch tem dono, e "não é a `main`" não prova que é sua.** A forma binária
(`main` proibida, "a branch de trabalho" certa) pressupõe uma sessão por
repositório: "a" branch de trabalho, no singular, é a sua por definição. O
terceiro estado existe — branch de trabalho de **outra** sessão — e a regra
binária dá autorização por eliminação: você confere que não está na `main`,
passa, e commita em cima do trabalho alheio.

Antes de **trocar de branch** — e de novo antes do **primeiro commit**, porque a
outra sessão pode ter movido o HEAD debaixo de você — a branch atual é sua só se
as duas valerem:

- não há fluxo aberto cujo slug (`<data>-<branch>`) case com o nome dela — o
  `/saude` responde isso em uma linha, e desde a Issue #25 ele diz **`ESTA
  branch tem dono`** em vez de só contar trabalhos abertos;
- o working tree não tem modificação de outro dono.

Qualquer uma falhando, o trabalho novo começa num worktree novo via `git
worktree add` — cada sessão fica dona do próprio HEAD. Em diretório
compartilhado, `git checkout -b` move o HEAD do diretório inteiro e derruba a
outra sessão. O gate de sessão co-locada (`hooks/gate-worktree.cjs`) já recusa
`checkout`/`switch` com exit code 2 quando há outra sessão viva no mesmo
diretório, e a mensagem oferece `git worktree add` como saída.

> 2026-08-20: os dois instrumentos tinham o fato antes do commit. O `/saude`
> imprimiu `fluxo: 1 trabalho(s) em aberto -> revisar` 20 minutos antes, e o
> `git status` mostrou 4 arquivos de outro dono — que a sessão **verbalizou**
> ("essas outras mudanças são do trabalho em aberto do fluxo, não minhas"),
> aplicou corretamente ao `git add` por caminho, e não aplicou à branch. O fato
> chegou, foi dito em voz alta, e não alcançou a decisão adjacente.
>
> O custo não foi o commit no lugar errado: foi **duas** perturbações. Quando a
> correção veio, a outra sessão já tinha commitado por cima, e sair exigiu
> `rebase --onto` + `push --force-with-lease`, trocando o hash do commit dela.
> Commit no lugar errado perturba uma vez; com trabalho por cima, perturba de
> novo na hora de sair — e é isso que faz a checagem valer antes do primeiro
> commit, não depois.

Isolamento não garante base certa: o worktree nasce na ponta de `origin/main`,
não no commit de trabalho — isso não é defeito intermitente, é o
comportamento do harness. O que varia é ONDE a ponta de `origin/main` estava
quando o worktree nasceu: ela pode ter avançado depois que a janela principal
mediu o hash, ou o worktree pode ter nascido antes de um commit que a janela
principal já considerava feito. Não dá pra assumir que o hash informado no
briefing e o hash real de nascimento do worktree são o mesmo.

> 2026-08-23: esteira url-doutor-e-ata-em-audio do Sabiá, dois despachos com
> `isolation:worktree` — os dois worktrees nasceram na ponta da main
> (`7e77e21`), não na branch de trabalho commitada (`1033218`) informada no
> briefing. Os dois agentes diagnosticaram a divergência e pararam sem editar,
> do jeito que a regra manda — mas o hash informado é que estava errado, não o
> agente. Custo: ~113k tokens de subagente, zero linha entregue, redespacho das
> duas tarefas.

> 2026-08-07: 3 de 3 worktrees nasceram velhos, o pior 7 commits atrás,
> antes de existir a spec que o agente devia ler; mesclar teria revertido as
> correções do dia.

Portanto, dupla conferência. **(1) O briefing informa o hash esperado** e
manda rodar `git log -1` como primeira ação, abortando se divergir — **de
dentro do worktree, com `cd`, e nunca com `git -C`**. `git -C <dir>` sobe para
o repositório pai **em silêncio** quando `<dir>` não é repositório, e devolve o
hash de lá como se fosse o de cá: a regra que existe para impedir trabalho
sobre base errada é cumprida por um comando que mente nessa situação exata.
Por isso o primeiro comando é `git rev-parse --show-toplevel`, e ele tem que
bater com o worktree do briefing **antes** de qualquer hash ser aceito. O
`conferir-entrega.cjs` já checa nessa ordem; o briefing é que não checava.

> 2026-08-19: a conferência devolveu o hash esperado e estava errada — o
> diretório não era repositório, e o hash "confirmado" era o do repo
> principal. O worktree tinha sido auto-removido por estar inalterado (o
> agente conferiu a base, divergiu e parou sem editar, que é o que a regra
> manda), e o resume caiu num diretório fantasma: duas pastas vazias, sem
> `.git`, ausente de `git worktree list`. Duas regras corretas — "pare se a
> base divergir" e "remova worktree inalterado" — se combinam num laço em que
> a tarefa nunca começa. Custou duas rodadas de agente, e quando a base foi
> reconferida ela **já estava certa**: a divergência era corrida na criação do
> worktree, não estado estável. Daí o `--ff-only` abaixo ser preferível a
> parar, quando o toplevel está certo e só o HEAD diverge.

A única
saída autorizada: o briefing lista também os **hashes velhos conhecidos**, e
só para esses `git merge --ff-only <hash esperado>` é permitido e obrigatório
antes de editar — fast-forward não descarta nada, qualquer outro hash
continua sendo aborto. **(2) Na integração, a janela principal confere com
evidência primária, nunca pelo relato** — `node scripts/conferir-entrega.cjs
--worktree <wt> --base <hash> --head-antes <hash>` faz as cinco checagens
(toplevel é worktree mesmo, base do commit **entregue**, sujeira não
commitada, diretório principal tocado, HEAD do usuário movido) e sai com
exit ≠ 0. Base errada → rebasear ou aplicar por patch.

Integrar **por partes, com âncora conferida** — nunca copiar arquivos
inteiros de volta. Número que não fecha entre o relato e a base local (654
testes vs 655) tem causa própria aqui e é a primeira a checar: **base
errada**. "Testes passando" no worktree não vale: a suíte dele pode estar tão
desatualizada quanto a base. Integrado o trabalho, **remover worktree e
branch** — órfãos acumulam em `.claude/worktrees/` e agente novo pode ser
encaixado num sobrevivente; antes de limpar, conferir se algum guarda
trabalho não integrado.
