# Issues #642 e #641, e o falso verde do /saude nos vigias

## Objetivo
Fechar as duas Issues abertas e o defeito que escondeu o backup parado: o `/saude`
dizia "todas com proxima execucao" para quatro tarefas desabilitadas. Delegação
prévia do usuário ("segue no modo automatico tudo como recomendado"): as decisões
abaixo são as recomendadas da sessão, para veto no PR.

## Decisões fechadas
- **D1 — #642: órfão se detecta pelo estado, não pelo histórico de eventos: em `reconciliar`, sob a trava, pasta com `conta === casa`, login confirmado pelo servidor e `estacionado-<pasta>.json` presente é órfão e se arquiva; `orfaoPendente` sai** — porquê: em `arqsDaTroca` o estacionado só existe com a pasta fora de casa, então com ela em casa ele sobra por definição. O evento citado na Issue (`manual (/login fora do script, estado reconciliado)`) não sai de código nenhum: `git log --all -S"fora do script" -- scripts/conta.cjs` e o cache do plugin voltam vazios, então foi edição à mão do `eventos.jsonl`. Consertar "o caminho que grava a volta" (a primeira sugestão da Issue) não teria onde entrar; qualquer caminho futuro que deixe o órfão cai nesta cura. Arquivado, nunca apagado, e o aviso de uma vez por hora quando o arquivamento falha continua.
- **D2 — #641: linha opcional `Repo: <caminho absoluto>` no briefing do revisor, ao lado de `Slug:`; o hook procura o estado primeiro no toplevel dela e depois no do `payload.cwd`** — porquê: é a proposta da Issue. Valor não absoluto é ignorado, porque "Repo: rainforest-mind" é rótulo comum em briefing. A chave `contrato-veredito` passa a ser lida no repositório do fluxo quando a linha existe.
- **D3 — #641: o stderr do hook diz onde procurou (`<slug> nao encontrado em <raiz> e worktrees`), `Repo:` que não é repositório avisa, e a recusa do `marcar revisar` ("nenhum veredito gravado") ensina a linha `Repo:`** — porquê: é o critério da Issue, mas stderr de hook com exit 0 não chega à janela principal; quem o vê no primeiro minuto é o `marcar`, um passo depois, então a instrução mora nas duas pontas.
- **D4 — Modelo de ameaça da linha `Repo:`: protege contra o veredito perdido por engano, não contra quem forja o briefing** — porquê: a linha só escolhe entre repositórios em que já exista `docs/rainforest/estado/<slug>.json`, e `estado.cjs veredito` segue conferindo slug e veredito no transcrito real (D12/D14 do contrato). `Repo:` errado com slug que existe lá grava no fluxo errado: é o mesmo risco residual aceito do `Slug:` errado (D13 do contrato), e é critério de parada da revisão, não buraco a fechar.
- **D5 — `/saude`: a consulta de vigias lê `State`; tarefa `Disabled` sai em `aviso` próprio, com nome e remédio, e nunca conta como "com proxima execucao"** — porquê: medido nesta máquina, as quatro tarefas `Disabled` têm `NextRunTime` preenchido, e o checador só olhava esse campo (regra 12 item 7, invertido: campo cheio não prova que roda). É `aviso`, não `alerta`: desabilitar é ato de alguém, e gatilho vencido sem ninguém pedir continua `alerta`. O texto cita que o backup externo depende do `sentinela-foco`, que é a consequência que ficou invisível de 27/10 a 03/11.
- **D6 — `.claude/fixtures/` entra no `.gitignore`, sem apagar nada** — porquê: `.claude/fixtures/multihost-1.21.1-host` pertence ao usuário de sandbox do Codex (o git recusa por dono diferente) e deixa `?? .claude/` em todo `git status` do principal. Ignorar resolve o sintoma sem mexer no que é de outro dono.
- **D7 — Entrega: um PR com bump de patch para 2.3.2 e CHANGELOG, `Closes #641` e `Closes #642`** — porquê: precedente dos últimos PRs, e sem bump o conserto não chega ao clone do marketplace, que é o que a tarefa agendada `troca-de-conta` executa.

## Avaliado e descartado
- #642, arquivar no `trocar` em vez do `reconciliar`: o `vigiar` não passaria por ali e o órfão ficaria até a próxima troca manual. O `reconciliar` roda nas duas portas sob a trava.
- #642, só o `/conta` status acusar: o status roda sem a trava, então só poderia avisar, e a troca seguinte continuaria falhando.
- #641, varrer os projetos de `projetos.json` atrás do slug: slug repetido entre repositórios gravaria no lugar errado sem ninguém ter pedido; explícito no briefing é mais barato.
- `/saude`, `Disabled` como `alerta`: quem desabilitou de propósito passaria a ver alerta em toda rodada, e alerta que não muda vira ruído.

## Fora de escopo
- Agendamento recorrente do backup e chave `poda`: ambos alteram o ambiente do usuário (regra 15) e sobem como `Q` no fim da sessão. O backup avulso de 03/11 já foi gravado.
- `RFM_DIFF_CWD` no fluxo de outro repositório: a marca `[preexistente]` continua conferida no diff da sessão; fora do critério da #641.
- `manutencao-*.lock` acumulando na raiz de dados: nada apaga, e são arquivos vazios; plantado como ideia.

## Varredura
docs/rainforest/varredura/2026-11-03-issues-conta-veredito-saude.txt — confirmou as #329, #363 e #369 (veredito em worktree do mesmo repositório) e a #585 (reconciliação de `/login` de fora), que esta entrega estende sem reabrir. Nenhuma ideia plantada cobria os três temas.

## Em aberto
(nenhum)
