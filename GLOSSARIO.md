# Glossário

Este arquivo define os termos de domínio do rainforest-mind: o que cada palavra quer dizer aqui, onde ela mora no repositório e um caso real em que aparece. Quem trabalha no repo, humano ou agente, consulta um verbete quando um termo aparece e não está claro; ninguém precisa lê-lo inteiro. É mantido pela skill `/glossario`, e cada verbete entra por commit depois de aprovado pelo dono do repo.

## fluxo
Definição: a sequência de estágios pela qual um trabalho passa no rainforest-mind: design, plano, executar, revisar, verificar e fechar. Cada estágio exige os que estão antes dele fechados.
Onde mora: `scripts/estado.cjs`, na tabela PRE_REQUISITOS; o estado de cada trabalho fica em `docs/rainforest/estado/`, um JSON por slug.
Cenário: `node scripts/estado.cjs exigir --slug <slug> --estagio plano` sai com exit 2 e a linha "RECUSADO: 'plano' exige design fechado(s)." enquanto o design estiver pendente.
Evite: esteira

## estágio
Definição: cada passo do fluxo, com a sua skill. `arqueologia` é o estágio zero e é opcional; `limpar` é manutenção e não conta como estágio.
Onde mora: `scripts/estado.cjs`, nas tabelas DECISAO e PRE_REQUISITOS; a skill de cada estágio fica em `skills/plano/SKILL.md` e nas outras pastas de `skills/`.
Cenário: `arqueologia` fecha como "dispensada" quando alguém olhou o código e decidiu que não precisa de mapa; `limpar` tem a lista de pré-requisitos vazia, então o `exigir` nunca o barra.

## plantar
Definição: guardar uma ideia no acervo para voltar a ela depois, sem agir agora. É o subcomando `plantar` de `scripts/ideias.cjs`.
Onde mora: `scripts/ideias.cjs`, que grava em ideias.jsonl dentro da pasta de dados do usuário, `~/.rainforest`, fora do repo.
Cenário: a ideia `glossario-compartilhado-por-repo` aparece como plantada em `node scripts/ideias.cjs listar`, que mostra as plantadas por padrão.

## colher
Definição: dar uma ideia plantada como entregue, com o resultado do que de fato foi feito. Uma ideia colhida sai da lista das plantadas.
Onde mora: `scripts/ideias.cjs`, subcomando `colher --id <id>`, com `{"resultado": "..."}` pela entrada padrão; grava no mesmo ideias.jsonl.
Cenário: `colher` sem resultado é recusado, porque o comando exige o que de fato foi entregue; por isso a ideia `glossario-compartilhado-por-repo` segue plantada e aparece em `listar`.

## acervo
Definição: os registros que o uso do plugin acumula fora do repo, em `~/.rainforest`: ideias, foco e projetos. Não é o markdown que a skill montar-corpus gera a partir de uma wiki, que ela também chama de acervo. O arquivo `skills/rainforest-mind/references/regra-12-acervo.md` é outra coisa: o histórico de incidentes da regra 12.
Onde mora: `CONTRIBUTING.md`, na seção "Campo obrigatório novo vem com o passado resolvido", e `hooks/lib/raiz.cjs`, que resolve a pasta de dados.
Cenário: em 2026-08-11 o campo `gancho` virou obrigatório sem resolver o acervo que já existia; o `conferir` ficou com 35 problemas em linhas que nenhuma sessão tinha causado, e por isso a seção manda resolver o acervo no mesmo commit.

## território
Definição: o conjunto de ferramentas e agentes de uma linguagem ou domínio, declarado num território.json de plugin próprio, que cada skill de estágio consulta antes de agir.
Onde mora: `scripts/territorio.cjs`, que lê o território.json do plugin instalado e imprime o bloco do estágio.
Cenário: num repositório sem território, `node scripts/territorio.cjs estagio plano` imprime "sem territorio" e sai com 0.

## enxertar
Definição: reimplementar o mecanismo de um repositório de terceiro, depois de lido no código, em vez de instalá-lo. É uma das três trilhas do livro de repos, junto com instalar e ler; a âncora escolhe a trilha antes da busca.
Onde mora: `vigias/livro-de-repos.md`, na seção "Trilha: a âncora escolhe antes da busca", e `vigias/batedor-repos.md`, que traz a trilha de cada candidato da fila.
Cenário: o `trailhq/Graft`, avaliado em 2026-09-01, desceu da trilha instalar para enxertar, e a linha dele em `vigias/livro-de-repos.md` tem o veredito "Instalar → Enxertar: enxerta".
Evite: roubar

## worktree de agente
Definição: o checkout isolado onde roda o subagente que escreve, criado a partir da ponta de `origin/main`, e não da branch de quem despachou.
Onde mora: `.claude/worktrees/`, onde os worktrees ficam; `hooks/gate-worktree.cjs`, que barra com exit 2 a escrita de subagente fora de worktree; e `skills/rainforest-mind/references/regra-11.md`, que manda criar o worktree a partir de `origin/main`.
Cenário: em um clone, `git worktree add .claude/worktrees/x -b fluxo/x origin/main` cria o worktree com `origin/main` no commit A; depois `origin/main` avança para B, e `node scripts/preparar-worktree.cjs --hash <B>` faz `merge --ff-only` e sai com 0 imprimindo `base-ok <B em 12 caracteres> <toplevel>`.

## portaria
Definição: a decisão que admite ou nega um despacho de subagente, com base no manifesto de agentes e no estágio aberto. Agente que não está no manifesto não é barrado: só fica registrado.
Onde mora: `hooks/portaria.cjs`, que lê o manifesto `.rainforest/agentes.padrao.json` do plugin ou o agentes.json do repo, quando existir.
Cenário: um agente com "escreve: true" despachado num estágio fora dos seus "estagios", numa branch de fluxo sem o caminho leve, sai com exit 2 e o motivo no stderr.
