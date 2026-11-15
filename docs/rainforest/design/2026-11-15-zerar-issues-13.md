# Rodada 13: fechar pós-squash (#714), busca: com continuação (#709), revisor que roda código do projeto (#697) e preexistente que vira Issue

## Objetivo
Fechar as Issues #714, #709 e #697 e cortar a causa de as revisões abrirem Issue nova a cada
rodada: hoje todo achado `[preexistente]` é encaminhado para "virar Issue", mesmo quando está no
arquivo que a própria entrega edita. Foi assim que as revisões do fluxo `gate-segmentador`
(#689) abriram seis das dez Issues abertas em 2026-11-15.

Decisões tomadas pela sessão em modo autônomo, com a autorização do Luís de 2026-11-15
("vai consertando no fluxo em modo automático até ficar sem issue"). Cada uma vai no PR em
"Decidido sem você".

## Decisões fechadas
- **D1 — `marcar fechar ok` cujo HEAD não contém o `verificar.head` (branch nova da `main`
  depois do squash) compara o `verificar.head` com a ponta do PR mergeado, não com o HEAD.
  O PR vem do `pr` do `--json` do `marcar`. A ponta vem de `gh pr view <pr> --json
  state,headRefOid` e só vale com `state` `MERGED`. Sem `pr`, ou com o PR não mergeado, a
  comparação volta a ser contra o HEAD, como na base (é o caso do rebase da branch do fluxo
  depois do `verificar`), e a recusa, se houver, acrescenta a dica de passar o `pr` do PR
  mergeado. Sem `gh` ou sem rede, sai 69. (Emendado na revisão 1, decidido sem o usuário: a
  primeira versão recusava sem `pr` e quebrava o fechar depois de um rebase.)** —
  porquê: o que foi mergeado é a ponta do PR. Comparar o código verificado com ela mede
  exatamente o que a D1 da #567 quer medir: código que mudou depois do `verificar` e entrou
  na `main`. Contra o HEAD de uma branch nova, o diff `merge-base..HEAD` sai vazio e qualquer
  arquivo que a `main` mudou por cima depois do squash (o CHANGELOG da #714) passa por
  "código alterado". A recusa atual manda reabrir um executar cujo código já está na `main`.
  Critério: na reprodução da #714 (estado com `verificar.head` = A, PR mergeado cuja ponta
  tem o mesmo conteúdo de A, HEAD numa branch nova da `main` com o CHANGELOG da `main`
  diferente), o `marcar` sai 0. Com um arquivo de código diferente entre A e a ponta do PR,
  sai 2. Sem `pr`, sai 2 e a recusa traz a dica do `pr`. Na branch do fluxo rebaseada depois
  do `verificar`, sem PR mergeado, sai 0 como na base. Na branch do fluxo, onde o HEAD contém
  A, nada muda.
- **D2 — Linha de continuação dentro de `busca:` vira recusa.** Quando há `desfecho:` depois
  do `busca:`, o bloco vai até ele, e toda linha não vazia que não é item `- ` é recusada
  (indentada ou na margem, `-catalogo` sem espaço). Item depois de linha em branco continua
  sendo item e é conferido. Sem `desfecho:` depois, vale a regra da indentação: uma linha
  indentada, sem hífen e não vazia, logo depois de um item ou de outra continuação, é recusada pelo
  `conferir-busca` com o número da tarefa e o formato esperado: cada item cabe numa linha
  só. Antes ela era descartada em silêncio, e o `arquivo:linha` que caía nela não era
  conferido (#709) — porquê: recusar é o que a doc já promete ("confere toda ocorrência"),
  e juntar a linha ao item exigiria decidir quanto de indentação é continuação. Os planos do
  repo já escrevem um item por linha, então nenhum plano existente passa a ser recusado.
  Critério: o cenário da #709 (`nada.js:99` na linha de continuação) sai 2, e um plano com
  todos os itens numa linha só continua 0.
- **D3 — Revisor e tester só rodam código do projeto pela bateria do projeto, ou com a pasta
  pessoal desviada.** Fora da bateria, o comando roda com `HOME`, `USERPROFILE`, `APPDATA` e
  `LOCALAPPDATA` apontados para um `mktemp -d`, no mesmo comando. "Fora do repositório"
  deixa de contar como seguro. O molde do briefing do revisor (`skills/revisar/SKILL.md`)
  ganha essa linha e nunca escreve "experimento ad hoc" sem ela (#697, P1 e P2) — porquê: o
  perigo não é onde o script mora, é o que o código do projeto grava quando roda sem o
  isolamento da bateria. Desviar a pasta pessoal cobre o caso do incidente
  (`~/.claude/time-tracker/...`) sem proibir o que este repo faz o tempo todo: rodar um hook
  com um payload. Critério: `agents/revisor.md`, `agents/tester.md` e o molde do briefing
  trazem a regra com as quatro variáveis.
- **D4 — Achado `[preexistente]` em arquivo que o diff da entrega toca não vira Issue.** O
  `critica-do-revisor.cjs` separa os preexistentes aceitos em duas seções do stderr:
  - arquivo que o diff toca: `## Preexistentes no arquivo da entrega (corrigir nesta branch ou
    registrar no design como resíduo aceito, nunca Issue)`;
  - arquivo fora do diff: a seção atual, que continua indo para Issue.

  O `laco.md`, o `SKILL.md` do revisar e o `agents/revisor.md` dizem o mesmo — porquê: o
  defeito que já existia no arquivo que se está consertando é do trabalho em curso, pela
  regra que o Luís deu em 2026-09-08 ("erro desse trabalho deve ser corrigido"). Mandar para
  Issue gerou a cadeia #692→#708. A marca continua não reprovando sozinha, e quem decide
  entre corrigir e registrar como resíduo é a janela principal. Assim o laço não perde o
  critério de parada. Critério: com um reprovado gravado cujo achado preexistente cita uma
  linha de um arquivo que o diff toca, mas fora dos trechos alterados, o achado sai na seção
  nova. Com o mesmo achado citando um arquivo fora do diff, sai na seção antiga.
- **D5 — Entrega em um PR, versão 2.15.0** — porquê: há comportamento novo no `estado`, no
  `conferir-busca` e na `critica-do-revisor`. Segue o formato das rodadas anteriores: bump
  dos dois manifestos, selo do README e entrada no CHANGELOG. As três Issues fecham pelo
  `fechar-issue.cjs` depois do merge.

## Avaliado e descartado
- Fazer o `fechar` pular a trava sempre que o PR está `MERGED` (primeira sugestão da #714):
  perde a medição da #567. Código commitado depois do `verificar` e mergeado passaria sem
  aviso.
- Só documentar na skill `fechar` que o `marcar` roda na branch do fluxo (segunda sugestão da
  #714): deixa a mensagem errada ("reabra o executar") no caminho que o modo autônomo de fato
  percorre (`obs-2026-10-27-estado-fechar-fora-do-pr`).
- Proibir o revisor de rodar qualquer código do projeto fora da bateria (P1 literal da #697):
  barraria rodar um hook com um payload, que é o jeito de revisar gate neste repo.
- Juntar a linha de continuação ao item (#709): exige decidir a indentação e aceita um
  formato que a doc não descreve.

## Fora de escopo
- Resíduos aceitos da D4, achados nas revisões 2 e 3, sem cenário neste repositório: (1) caminho de fora do diff com espaço cujo trecho depois do último espaço coincide com um arquivo do diff; (2) citação absoluta de arquivo dentro de um diretório de topo chamado `a` ou `b` perde o diretório no corte do prefixo do git. Os dois só desviam o achado para a seção de Issue, sem liberar marca recusada.
- P3 da #697 (hook que avisa `python`/`node` fora da bateria num subagente de leitura): a
  própria Issue o marca como pendente por falso positivo alto. Vai para `/ideia`.
- A família de bypass do tokenizador (#692, #694, #699, #703, #706, #708) e o #707: rodadas 14
  e 15.

## Varredura
docs/rainforest/varredura/2026-11-15-zerar-issues-13.txt. Três achados:
- `fechar-marcar-antes-do-merge` e `obs-2026-10-27-estado-fechar-fora-do-pr` confirmam que o
  estado do `fechar` vai num PR curto, numa branch nova, depois do merge. Esse é o caminho
  que a D1 conserta.
- #575 e #567 são a origem da trava que a D1 preserva.
- Não há Issue nem PR anterior sobre `extrairBusca` ou "experimento ad hoc".

## Em aberto
(nenhum)
