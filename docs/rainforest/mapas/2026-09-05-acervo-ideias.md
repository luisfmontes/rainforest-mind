# Mapa: acervo de ideias abertas (2026-09-05)

Fatia: as ideias **abertas** (`plantada` + `em-colheita`) do acervo pessoal em
`<home>/.rainforest/ideias.jsonl`, cruzadas contra o repositório
`rainforest-mind` (este worktree, hash-base
`b31634bd3de54a48d08cfbead372ba31ebdacc94`). Fonte de dados: **só leitura** —
nenhuma linha do `ideias.jsonl` foi tocada por esta rodada. Hash SHA-256 do
arquivo antes de eu ler qualquer coisa:
`f42d0c83a1009db752357ed31e9299dd60db6b2406b1f086fe6760609b137e3b` — confira
que ele está idêntico depois.

## Panorama, e uma divergência que vale registrar

**CONFIRMADO** (contagem feita nesta rodada, lendo as 347 linhas): 223
`plantada` + 1 `em-colheita` = 224 abertas, 117 `colhida`, 3 `unificada`, 3
`descartada` — bate com o panorama do briefing.

**A distribuição por projeto do briefing NÃO bateu**, e o motivo importa mais
que o número: o briefing citava `rainforest-mind 83`, `protheus-inovacao 10`,
`claude-plugins 7`, `sabia 6`, `solta 4`, `whatsapp-mcp 3`, `segundo-cerebro
1` — soma 114, não 224. A contagem real por campo `projeto` das 224 abertas,
medida agora:

| projeto | abertas |
|---|---|
| rainforest-mind | 144 |
| protheus-inovacao | 36 |
| solta | 12 |
| claude-plugins | 9 |
| sabia | 8 |
| apontamento-horas | 5 |
| whatsapp-mcp | 4 |
| protheus-clientes | 2 |
| whatsapp-message-standards | 2 |
| segundo-cerebro | 1 |
| tbc-licensing | 1 |

Total 224, bate com o total de abertas. O panorama do briefing estava **defasado
ou incompleto** nessa quebra específica (a soma nem fechava 224) — sinalizo
como `LACUNA` a razão exata da divergência, não fui atrás disso porque não é o
que a fatia pede. A tabela acima é `CONFIRMADO` por contagem direta do arquivo.

Também medi o campo `gancho`: **20** ideias abertas não têm o campo (o
briefing pedia 19 — ver seção 4, que lista as 20 encontradas com data e
projeto; um id (`sem-branch-antes-de-editar-stec187`) não é `rainforest-mind`,
os outros 19 são).

## Método

Li as 144 ideias abertas do projeto `rainforest-mind` na íntegra (id, título,
descrição, `ao_colher`, `andamento` quando existia). Para cada uma que
sugeria mecanismo verificável, procurei o `arquivo:linha` no repo por grep
direcionado (nome de arquivo citado, string literal, nome de skill/comando) e
só marquei `CONFIRMADO` depois de abrir o arquivo e ler o trecho. Ideias dos
outros 10 projetos (80 ideias) são sobre bases de código que não são este
repositório (ADVPL/Protheus, o plugin `sabia`, `whatsapp-mcp`, etc.) — não
cabem na tabela 1 por definição do próprio pedido ("para cada ideia do
projeto rainforest-mind"), mas entraram na leitura de título/descrição para
as seções 2 e 3, que cobrem o acervo inteiro.

Não usei subagente para o cruzamento: o manifesto `.rainforest/agentes.json`
deste worktree só admite `revisor`, `auditor-de-seguranca`, `planejador` e
`executor`, nos estágios `revisar`/`design`/`plano`/`executar` — nenhum serve
para uma tarefa de pesquisa fora de estágio, e a portaria (`hooks/portaria.cjs`)
recusou minhas quatro tentativas de despachar `general-purpose`. O trabalho
foi feito na janela deste agente, com leitura direta e grep.

---

## 1. Candidatas a colher

Mecanismo **confirmado** no código atual do repositório para uma ideia
**aberta**. Cada linha foi lida, não deduzida.

| id da ideia | o que ela pedia | onde está no repo | confiança |
|---|---|---|---|
| `controle-que-compartilha-o-confundidor-nao-e-controle` | Regra de método: antes de usar "rodei numa versão/branch anterior e deu igual" como prova de causa, checar o que os dois lados leem em comum. | `referencias/perfil-de-trabalho.md:28` (tabela de procedência, cita o id **literalmente**) e `:65-67` (texto do bloco); propagado por `scripts/perfil.cjs` para os 7 agentes, ex. `agents/executor.md:241`. | Alta |
| `commitar-em-branch-alheia-atrapalha-outra-sessao` | Regra de método: antes do primeiro commit, conferir de quem é a branch atual; esteira aberta ou modificação alheia = criar branch própria. | `referencias/perfil-de-trabalho.md:32` (cita o id **literalmente**) e `:80-82`; propagado para `agents/executor.md:256`. | Alta |
| `worktree-de-subagente-nasce-na-main-nao-na-branch` | Briefing/skill do `executar`/`modo-dev` ganhar uma seção "Base" com: base esperada, de onde ela sai (branch, não main), e autorização nominal de `git merge --ff-only <hash>` quando o worktree nasce num hash velho conhecido. | `agents/executor.md:11-23` — o agente já confere `--show-toplevel`, compara o hash contra o commit-base do briefing, e faz `git merge --ff-only` só quando o hash está na lista de "hashes velhos conhecidos" do briefing; qualquer outra divergência é PARE-e-reporte. | Alta |
| `trava-entrega-os-casos-que-ela-nao-pode-barrar` | `gate-worktree` estava testado só pelo que barra; faltava caso para o que ele **atrapalha** (grep de leitura com `>`, `=>`, `<tag>` no padrão de busca). | `hooks/gate-worktree.cjs:416-417` (`OPERADOR_REDIRECT`, regex que só conta `>` como redirecionamento no início do token) + `hooks/testa-gate-worktree.sh:483` (`grep com <project> no padrao — o caso real`) e `:486` (`grep com => no padrao`) — comentário de contexto em `:459-471` nomeia o conserto como "Conserto de 2026-09-01". | Alta |
| `payload-de-teste-de-hook-montado-a-mao` | Bateria de hook que monta payload JSON com `printf`/`esc()` fica "verde" mesmo com JSON inválido (aspas duplas quebram o payload); virar payload montado por ferramenta de verdade. | `hooks/testa-gate-worktree.sh:468-471` (comentário: "`jesc` existe porque `esc` só troca barra... verde tautológico") e `:475-477` (helper `b()` monta o payload chamando `node -e` com `JSON.stringify`, não `printf`). | Alta |
| `conferir-entrega-nao-sabe-lidar-com-despacho-paralelo` | As checagens 4/5 do `conferir-entrega.cjs` (repo tocado / HEAD mexeu) davam falso positivo quando a janela principal integrava outra tarefa entre o despacho e a conferência; pedia noção de "o HEAD avançou de propósito" via `--head-antes` + checagem de ancestralidade. | `scripts/conferir-entrega.cjs:173` e `:242` (flag `--head-antes` já existe) e `:580-604` — quando o HEAD mudou, confere `merge-base --is-ancestor` (avanço vira aviso, não falha) e, se foi lateral, cruza os arquivos do novo HEAD com os arquivos do agente (função `arquivosAgente`) antes de reprovar. | Alta |
| `revisao-dos-nomes-de-comando-antes-da-traducao` | (A parte já resolvida do pedido, e o próprio `ao_colher` da ideia já registrava isso em 2026-08-12.) `/grill` vira `/brainstorm`. | `commands/brainstorm.md` existe com esse nome e essa skill (`Skill(brainstorm)` citado no corpo); `commands/grill.md` não existe mais — conferido por `ls commands/`. | Alta (só a parte do nome principal; a ideia também cobria outros nomes de comando ainda em aberto — não colher a ideia inteira, só marcar este pedaço) |

## 1b. Achados parciais — não entram na tabela 1

O pedido da ideia só está **parcialmente** coberto, ou o próprio texto da
ideia já se autodeclarava parcial. Confiança média, não vira colheita:

- **`conferir-esteira-le-markdown-por-linha-e-isso-tem-tres-bordas`** — a
  ideia lista três defeitos do checador de markdown por linha, em ordem de
  custo. O primeiro e mais barato ("decisão dentro de bloco de código conta
  como decisão real") **está corrigido**: `scripts/conferir-fluxo.cjs:266-302`
  tem `mascaraDeCerca()`, que marca linhas dentro de cerca (` ``` `/`~~~`) e é
  usada antes de contar decisões/tarefas (`:306`, `:330`). Os outros dois
  itens da ideia (contagem de tarefas, e o terceiro item que a descrição não
  detalha no trecho lido) não foram conferidos — não dá para marcar a ideia
  inteira como colhida.
- **`mapa-que-ninguem-confere-envelhece-em-silencio`** — o próprio
  `ao_colher` já diz "PARCIAL, conferido em 2026-08-12" e nomeia o que falta
  (o protocolo de reconferência, não só a rotação do FOCO.md).
- **`publicar-o-rainforest-separando-codigo-de-dado`** — o próprio
  `ao_colher` diz "METADE FEITA". Conferi de fato: `LICENSE` é MIT (raiz do
  repo), o repo é **público** no GitHub (`gh api repos/luisfmontes/rainforest-mind
  --jq .private` devolveu `false` nesta rodada — fato do GitHub, não tem
  `arquivo:linha` deste repo, por isso não entra na tabela 1). Falta a
  "embalagem" que o próprio texto nomeia.
- **`cadencia-abre-trabalho-com-marcador-de-permissao`** — o `ao_colher`
  confere um fato lateral (nenhum vigia abre Issue, por desenho —
  `vigias/batedor-repos.md:4`), mas o pedido principal da ideia (gate de
  cadência) não tem mecanismo no repo.
- **`cobertura-do-design-no-plano`** e **`creep-se-mede-no-diff-contra-o-plano`**
  — os dois `ao_colher` dizem "pré-requisito já conferido... e passou", mas é
  só o pré-requisito da investigação, não a entrega da trava em si.

---

## 2. Agrupamentos

Ideias abertas que são a mesma coisa (ou o mesmo defeito, reobservado), em
prosas diferentes.

| tema | ids | por que são a mesma |
|---|---|---|
| Briefing proíbe rodar em background, o agente roda em background mesmo assim | `agente-que-manda-comando-pro-background-nunca-relata`, `briefing-que-proibe-background-nao-impede-o-background` | A segunda se declara **literalmente** "Segunda ocorrência" da primeira no próprio título/descrição: mesmo defeito (agente que joga comando para `run_in_background` trava sem relatar), mesma proibição escrita no briefing, reincidiu depois de já registrada. |
| Dependência não observada diretamente vira afirmação de fato | `caminho-de-projeto-registrado-sem-olhar-o-disco`, `controle-que-compartilha-o-confundidor-nao-e-controle`, `teste-que-le-saida-externa-cola-a-saida-crua-medida` | A terceira ideia se autodeclara "família com 6 registros no acervo" e cita as outras duas (mais três já `colhida`: `premissa-afirmada-sem-ser-olhada`, `medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia`, `timestamp-de-log-e-utc-nao-local`) como a mesma classe de erro. |
| Ambiente/dependência externa bloqueada trava o turno sem anúncio | `esperei-permissao-para-despachar-em-vez-de-despachar`, `abertura-mede-e-anuncia-ultracode-e-workflows` | A segunda se autodeclara "família com 5 registros" e cita a primeira (mais três já `colhida`: `regra-bloqueada-em-silencio`, `aviso-de-bloqueio-chega-tarde-demais`, `observacao-2026-08-20-aviso-de-regra-10-bloqueada-nao-parou-o-turno`). |
| Extensão da skill `arqueologia` com histórico de git | `arqueologia-com-historico-de-git-como-fonte`, `frames-de-compreensao-na-arqueologia` | O `ao_colher` da segunda manda **explicitamente** "Colher JUNTO com `arqueologia-com-historico-de-git-como-fonte`, no mesmo commit" e nomeia o primeiro passo como comum às duas. Não são texto idêntico, mas foram declaradas uma unidade de entrega pelo próprio autor das ideias. |
| Subiu pergunta/decisão ao usuário sem checar um fato que já estava disponível | `perguntei-worktree-que-a-regra-11-ja-fecha`, `decisao-subida-sem-o-fato-que-a-decidia`, `numero-na-propria-tabela-nao-seguido` | As três descrevem o mesmo movimento: a resposta já existia (numa regra do plugin, num log de despacho, ou na própria tabela que o agente tinha acabado de montar) e, em vez de aplicá-la, o agente escalou como pergunta/decisão para o Luís. |
| Palavra reaproveitada ancora a leitura do pedido | `vocabulario-do-sistema-estreitou-o-pedido`, `verbo-reaproveitado-ancora-a-leitura` | Mesmo mecanismo de erro: uma palavra (verbo do sistema num caso, verbo da própria frase anterior do agente no outro) determina a leitura do pedido do usuário sem checar se é a leitura certa — "colher" lido como operação de arquivo; "abrir" lido como "criar card" porque o próprio agente tinha usado a palavra assim um turno antes. |
| Triagem errada do próprio erro (ideia vs. issue vs. feedback) | `obs-2026-08-24-defeito-do-plugin-oferecido-como-ideia`, `erro-reconhecido-no-chat-nao-e-feedback-registrado` | As duas são o mesmo tipo de falha de roteamento: um problema achado durante o trabalho não vai para o registro certo por conta própria — uma vez o agente ofereceu como "ideia" um defeito que era Issue, a outra vez reconheceu erro em prosa no chat sem abrir o `/feedback` que o método exige. |
| Radar de foco confia numa lista de sessões que pode estar incompleta ou desatualizada | `obs-radar-foco-sessao-paralela-nao-listada`, `obs-2026-09-04-listagents-nao-cruza-config-dir` | As duas descrevem o radar de escopo (regra 3/17) cobrando desvio de foco a partir de uma lista de sessões paralelas que não enxergava a sessão real — uma vez por a lista estar defasada, a outra por o `ListAgents` não cruzar os dois config dirs (`~/.claude` e `~/.claude-personal`). |

Fora da tabela, registrado como observação e não como agrupamento forçado: as
quatro ideias lidas de repositórios de terceiro em 2026-09-01
(`sonda-de-drift-do-mapa-por-stat-e-hash`, `memo-de-hash-com-tres-estados-pendente-pronto-velho`,
`escada-de-confianca-derivada-da-estrategia`, `lacuna-declarada-por-maquina-no-mapa`)
propõem **mecanismos diferentes entre si**, mas todas mirando o mesmo alvo (o
mapa da `arqueologia`) — não são a mesma ideia dita diferente, mas competem
pelo mesmo lugar de implementação e valem uma decisão conjunta de escopo antes
de qualquer uma virar código.

---

## 3. As 10 que valem uma rodada agora

**Critério de ordenação, explícito**: RECORRÊNCIA (quantas vezes o mesmo
defeito já se repetiu ou já causou dano medido) cruzado com BARATO-DE-FECHAR
(o conserto é pequeno, mecânico, e o molde já existe em algum lugar do
próprio repo). Isso empurra para fora do top 10, de propósito, as ideias de
escopo grande (tradução para inglês, engenharia reversa de repo de terceiro,
multi-repo) — não por serem menos importantes, mas porque "vale uma rodada
agora" pede algo que fecha numa sessão.

1. **`briefing-que-proibe-background-nao-impede-o-background`** (+ `agente-que-manda-comando-pro-background-nunca-relata`) — reincidiu depois de já registrada uma vez com a proibição escrita duas vezes no mesmo briefing; texto no briefing provou não bastar, o próprio `ao_colher` já pede o mecanismo em vez de mais linha de prosa.
2. **`duas-sessoes-bumparam-a-mesma-versao`** — já aconteceu de verdade (duas PRs bumparam `0.70.0` ao mesmo tempo); o conserto que a própria ideia desenha é dois comandos (`git tag -l` + `ls` no cache instalado).
3. **`trava-no-atualizar-cli`** (+ `bateria-do-wrapper-de-lock`) — o molde do lock por `mkdir` atômico já existe ao lado, em `statusline-versao.sh`; é cópia com adaptação, não desenho novo.
4. **`2026-09-02-principal-sempre-na-main`** — é exatamente a regra que abre o *meu próprio* despacho como agente de arqueologia (conferir toplevel/hash antes de tudo); já rendeu correção do Luís em sessão real, e o próprio `ao_colher` já aponta o candidato a trava (`estado.cjs iniciar` ou hook).
5. **`creep-isenta-relatorios`** — confirmado nesta rodada que ainda não está feito (`globs_isentos` em `scripts/conferir-fluxo.cjs:509-513` não tem `relatorios/**`); o conserto é uma linha.
6. **`entrega-vazia-com-paralelo-nunca-cruza`** — buraco lógico real e concreto: com `--paralelo`, um commit vazio faz o cruzamento de arquivos nunca reprovar nada, e a infraestrutura ao redor (`arquivosAgente`, `--head-antes`) já existe e está confirmada nesta rodada.
7. **`substituicao-de-texto-sem-assercao-entrega-codigo-morto`** — já causou entrega real de mecanismo morto (episódio nomeado, `exige_e2e` nunca chamada); o conserto é disciplina barata (`assert` de contagem) a acrescentar ao método dos agentes que editam.
8. **`observar-estoura-orcamento-sessionend`** — risco concreto e medido (o `SessionEnd` real do harness compartilha um teto entre todos os hooks, e o valor declarado hoje estoura ele); o conserto é trocar dois números, já dimensionados no próprio texto da ideia.
9. **`2026-09-03-ideias-backups-sem-rodizio`** — 386 cópias, 196 MB, 92% da raiz de dados, medido; `foco.cjs` e `memoria.cjs` já implementam o mesmo teto (30) que falta aqui.
10. **`limpar-remove-worktree-limpo-de-outra-sessao-sem-perguntar`** — risco de dano real em repo multi-janela (apagar isolamento de sessão alheia); a fonte do conserto já está nomeada (`sessoes.json` do heartbeat + `git worktree list`).

---

## 4. Dívida de gancho

O briefing pedia 19; **encontrei 20** ideias abertas sem o campo `gancho`
(medição desta rodada, `ideias.jsonl` sem alteração). Uma delas
(`sem-branch-antes-de-editar-stec187`) é do projeto `protheus-clientes`, não
`rainforest-mind` — mantida na lista porque o pedido era "as 19/20 ideias
antigas", sem recorte de projeto. Ordenadas por `plantada_em`. Cada sugestão
é só sugestão — nenhum `gancho` foi escrito no arquivo real.

| id | projeto | plantada em | gancho sugerido |
|---|---|---|---|
| `claude-central-despachante` | solta | 2026-08-05 | Próxima vez que o Luís disser "quero trabalhar em X" sem apontar pasta/comando — testar se o fluxo atual já resolve sozinho antes de desenhar algo novo. |
| `pilha-de-voz-local-voicestudio` | solta | 2026-08-07 | Quando o plugin `sabia` (que já nasceu de metade desta ideia — transcrição) ganhar o pedido de texto-para-áudio, ou na revisão bimestral de 2026-10-05, conferir se a outra metade ainda falta. |
| `vigia-de-resposta-whatsapp-sem-token` | rainforest-mind | 2026-08-07 | Próxima vez que precisar esperar resposta de UM contato específico no WhatsApp sem gastar uma sessão inteira olhando — ou quando o bridge Windows nativo (já colhido) completar 30 dias estável. |
| `sol-foreman-delegacao-verificada` | rainforest-mind | 2026-08-08 | No próximo brainstorm sobre orçamento de token ou sobre o "gate do P1", reler os `skills/` do `sol-foreman` antes de desenhar do zero. |
| `task-observer-e-a-regra-13-com-diff` | rainforest-mind | 2026-08-08 | Na próxima ronda 4 do `vigias/jardineiro-ideias.md`, abrir de fato o repo `rebelytics/one-skill-to-rule-them-all` para ver como o diff é montado. |
| `beads-no-lugar-ou-por-cima-do-ideias-jsonl` | rainforest-mind | 2026-08-09 | Se o `steveyegge/beads` aparecer citado num quarto repo/fonte independente, ou na revisão bimestral de 2026-10-05, rodar as seis perguntas do `livro-de-repos.md`. |
| `publicar-o-rainforest-separando-codigo-de-dado` | rainforest-mind | 2026-08-09 | Quando alguém além do Luís de fato instalar o plugin (ver `publico-recomendado-como-privado`), conferir se a "embalagem" que falta virou bloqueio real. |
| `rainforest-publico-em-ingles` | rainforest-mind | 2026-08-09 | No dia em que o repo receber a primeira Issue ou PR de alguém que não é o Luís, decidir se a tradução vem antes ou depois disso. |
| `rainforest-fora-do-windows` | rainforest-mind | 2026-08-09 | Na próxima vez que uma bateria `testa-*.sh` for criada ou alterada, rodar em GitHub Actions Linux e listar o que quebra. |
| `prompt-da-psicologa-converge-com-as-regras-7-8-9` | rainforest-mind | 2026-08-09 | Na próxima edição das regras 7, 8 ou 9, registrar a procedência (Análise do Comportamento, genérico) na mesma rodada de edição. |
| `falta-a-regra-de-comecar-ativacao-comportamental` | rainforest-mind | 2026-08-09 | Na próxima vez que o Luís travar para começar uma tarefa técnica, testar ao vivo a sequência de 6 passos antes de formalizar a skill. |
| `revisao-dos-nomes-de-comando-antes-da-traducao` | rainforest-mind | 2026-08-09 | (Parte já resolvida — ver tabela 1.) Para o resto: quando a tradução para inglês começar, fechar os nomes de comando ainda em aberto antes de traduzir os que já têm nome fechado. |
| `recomendei-plantar-o-que-ele-queria-consertado` | rainforest-mind | 2026-08-10 | Próxima vez que eu oferecer "planto ou ataco agora" para uma dependência quebrada — o próprio menu se repetindo é o gatilho de checar se a lição pegou. |
| `design-so-no-chat-antes-do-worktree` | rainforest-mind | 2026-08-10 | Na próxima revisão da regra 12 ou da skill `modo-dev`, decidir a regra explícita sobre gravar design/plano em arquivo antes de criar worktree. |
| `orcamento-de-fontes-no-plano` | rainforest-mind | 2026-08-10 | Na próxima revisão da skill `plano`, ler a seção "Fechar a lista de fontes" do plugin `protheus` da TBC e decidir onde o teto mora. |
| `arquivo-de-regressao-por-fatia` | rainforest-mind | 2026-08-10 | Na próxima revisão da skill `arqueologia` (que já existe aqui — o texto original da ideia presumia que não existia), decidir se a medição de alcance entra como passo do `modo-dev`. |
| `publico-recomendado-como-privado` | rainforest-mind | 2026-08-11 | Próxima vez que eu for recomendar escopo de audiência (público/privado) para qualquer ferramenta — perguntar o fato antes de recomendar é o próprio teste. |
| `pedido-de-fluxo-lido-como-pedido-de-dominio` | rainforest-mind | 2026-08-11 | Próxima vez que o Luís pedir análise de plugin/repo de terceiro sem dizer DOMÍNIO ou FORMA — essa é a ocorrência que testa se a lição pegou. |
| `sem-branch-antes-de-editar-stec187` | protheus-clientes | 2026-08-11 | Próxima sessão ADVPL/TLPP antes da primeira edição de fonte — conferir branch é o mesmo mecanismo de `commitar-em-branch-alheia-atrapalha-outra-sessao` (já resolvido no rainforest-mind); portar a mesma disciplina para o repo Protheus. |
| `observacao-radar-foco-trabalho-vs-estudo` | rainforest-mind | 2026-08-13 | **Prazo do grupo FIAP é 05/09/2026 — hoje.** Conferir se a trilha [estudo] já está declarada no `FOCO.md` e se o radar distingue [trabalho] de [estudo] antes do prazo fechar. |

Nota lateral: a ideia `mutirao-de-gancho-nas-35-abertas-herdadas` (ainda
aberta, ela mesma) já pede exatamente este trabalho — escrever gancho aos
poucos, em rodada, sem inventar em lote. Esta seção é sugestão, não execução:
o comando `reparar --id <id> --gancho "<texto>"` que a própria ideia cita
continua por conta de quem decidir aplicar.
