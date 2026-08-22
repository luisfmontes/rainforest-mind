# O conserto da Issue #25 mandou abrir branch nova — e em diretório compartilhado é a branch nova que derruba a outra sessão

**Data:** 2026-08-21
**Onde ocorreu:** repo do próprio plugin — avaliar dois repos de terceiro (`fable-foreman`, `gauntlet-loop`) e acoplar a skill `regua` + o backstop de mutação, com outra sessão viva no mesmo diretório trabalhando a esteira da statusline

> Se você só for ler um parágrafo: a Issue #25 (fechada em 2026-08-20) ensinou "branch tem dono; se a atual não é sua, **o trabalho novo começa em branch nova, tirada da base**". Segui a prescrição ao pé da letra 24 horas depois — `git checkout -b regua-e-backstop-de-mutacao` — e foi **isso** que quebrou. `git checkout` age no **diretório**, não na sessão: as duas janelas trabalhavam em `C:\Projetos\rainforest-mind`, e criar a branch arrancou a outra sessão de `statusline-no-plugin-e-temp-da-bateria` sem ela saber. Nos 18 minutos seguintes ela commitou 3 vezes na minha branch. Nada se perdeu, mas o remédio da #25 é a doença nova, e o `gate-worktree.cjs` — que já casa `checkout` no regex — isenta a janela principal por desenho, que é exatamente quem errou.

## 1 — A prescrição da #25 é o ato que falhou

`skills/rainforest-mind/SKILL.md:392-401`, escrito depois da #25:

```
Antes do **primeiro commit de um trabalho novo**, a branch atual é sua só se as
duas valerem:
  - não há esteira aberta cujo slug case com o nome dela [...]
  - o working tree não tem modificação de outro dono.
Qualquer uma falhando, o trabalho novo começa em branch nova, tirada da base —
não daqui.
```

Apliquei corretamente: a branch atual tinha dono, então abri branch nova a partir da base. O texto não erra em nada do que afirma. Ele só **pressupõe que abrir branch é um ato local à sessão**, e não é — é um ato global ao diretório.

E a condição de disparo ("antes do **primeiro commit**") chega tarde: o dano de hoje aconteceu no `checkout -b`, antes de existir commit nenhum.

Reflog, sem interpretação:

```
HEAD@{19:25} checkout: moving from statusline-no-plugin-e-temp-da-bateria to regua-e-backstop-de-mutacao
HEAD@{19:29} commit: Skill regua: criterio de aceite para a tarefa que nao tem teste
HEAD@{19:41} merge worktree-agent-a659cd5e81b1cd98f: Merge made by the 'ort' strategy.
HEAD@{19:41} merge worktree-agent-afc0525e17140234c: Merge made by the 'ort' strategy.
HEAD@{19:43} commit: Rodada 2 do executar: os tres achados da revisao independente, fechados
```

As linhas de 19:41 e 19:43 não são minhas. São a outra sessão, na minha branch, sem nenhum sinal para ela de que tinha mudado de lugar.

## 2 — O gate vê o comando e isenta quem errou

`hooks/gate-worktree.cjs:45` já casa o subcomando:

```js
const GIT_QUE_MEXE = /\bgit\b[^\n;&|]*?\b(stash|checkout|switch|reset|merge|rebase|commit|clean|cherry-pick|revert)\b/;
```

E `hooks/gate-worktree.cjs:27` decide não usá-lo aqui:

```
 *   - so age quando ha `agent_id` — a janela principal nunca e barrada;
```

O escopo estreito foi deliberado e está certo para o que ele foi feito: proteger o diretório do usuário contra subagente. O caso que ele não modela é **N janelas principais**, em que cada uma é "o usuário" para si e "outra sessão" para a vizinha. Não falta mecanismo — falta uma condição no mecanismo que já existe.

## 3 — O radar da regra 17 tinha o fato, na abertura, e não virou decisão

O hook de abertura desta sessão imprimiu, antes da minha primeira linha:

```
## Outras sessões recentes (radar multi-janela, regra 17)
- <outro projeto> — Claude trabalhando (turno em curso há 11 min)
- C:\Projetos\rainforest-mind — Claude trabalhando (turno em curso há 11 min)
```

A segunda linha é **este diretório**, com outra sessão ativa. O fato chegou, no lugar certo, antes do erro. A regra 17 o enquadra como *"paralelo é intenção, deixe o radar leve"* — e nesse enquadramento a informação vira permissão, não cautela. É o mesmo mecanismo da seção 2 da #25: o instrumento tinha o fato e o apresentou com a moldura que desativa a ação.

## 4 — Terceira reincidência do mesmo padrão, e a única que teve mecanismo se comportou

Três achados fechados voltaram nesta sessão. A diferença entre eles é o que interessa:

| Issue | Como voltou hoje | Tinha mecanismo? |
|---|---|---|
| **#25** branch sem noção de dono | `checkout -b` derrubou a outra sessão | não — só texto na regra 11 |
| **#21** critério "a bateria sai 0" satisfazível por fora | agente entregou trava quebrada com 49/49 verde | não — critério em texto no briefing |
| **#4** worktree de agente nasce em base velha | worktree nasceu em `3035e1e`, 2 commits atrás | **sim** — e funcionou |

A #4 é a prova do desenho: o briefing levava o hash, o agente conferiu, **parou sem editar nada** e reportou. Zero dano. As outras duas não tinham nada além de prosa, e as duas cobraram o preço inteiro.

## 5 — A entrega verde e quebrada, nos dois sentidos

O agente cumpriu o critério falsificável do briefing (quatro casos, mutação, saída colada) e entregou uma trava que **recusava o caminho feliz sempre**. Dois defeitos, ambos invisíveis para a bateria dele:

1. `exigir` tirava o instantâneo e logo depois gravava o instantâneo no arquivo de estado — que é **versionado** aqui. O arquivo ficava sujo depois da foto, e o `marcar ok` acusava de mutação a escrita que a própria trava fez.
2. `statusOutput.trim()` antes do `split` comia o espaço inicial da primeira linha do porcelain (`␣M caminho`), e o `substring(3)` cortava um caractere a mais.

Os dois na mesma saída reproduzida:

```
--- exigir revisar ---   snapshot capturado: HEAD=7768ed5, 0 arquivo(s) sujo(s)
--- ninguem mutou nada. marcar ok: ---
RECUSADO: novos arquivos sujaram durante a revisao: ocs/rainforest/estado/s1.json
EXIT=2
```

**Os dois eram armadilha de fixture, não de código.** A bateria montava um repo de teste que nunca commitava o arquivo de estado — lá ele já estava sujo e untracked antes da foto, e caía dentro dela — e nunca punha um rastreado-modificado na primeira linha. O fixture não reproduzia o repositório onde a trava ia rodar, e por isso mediu outra coisa. É a mesma família do relatório de 2026-08-19, com uma causa nova e nomeável: **o fixture divergia do alvo numa propriedade que o alvo tem e o fixture não — o arquivo ser versionado.**

O caso de regressão que pega isso me custou **três tentativas erradas**, e as três por premissa não medida:

```
1. z-rastreado.txt ordena por ultimo    -> nunca era a primeira linha
2. git status --porcelain ordena por caminho -> NAO: rastreado primeiro, untracked depois
3. 1-rastreado.txt e 2-rastreado.txt    -> mangled colidem, ambos viram -rastreado.txt
```

Só na quarta (`alpha.txt` / `bravo.txt`) o teste ficou vermelho com o defeito presente.

## 6 — O `conferir-entrega.cjs` reprovou a entrega boa

Checagem 4 exige o diretório principal **limpo**, e a sujeira era da outra sessão, carimbada 19:24 — cinco minutos antes do despacho:

```
4. O repo principal foi tocado? (C:\Projetos\rainforest-mind)
   M docs/rainforest/estado/2026-08-20-statusline-no-plugin-e-temp-da-bateria.json
   FALHA  1 alteracao(oes) no diretorio principal do usuario
```

O script tem `--head-antes` para o HEAD e **nada equivalente para a árvore de trabalho**: a checagem 5 compara contra um instantâneo, a 4 compara contra um ideal ("limpo"). O `--paralelo` contorna cruzando com os arquivos do agente, mas é contorno — e num diretório onde outra sessão trabalha, a árvore quase nunca está limpa.

É o mesmo defeito do item 1 da seção 5, no script vizinho: **comparar contra um estado ideal em vez de contra o estado de antes.**

## O que deu certo

- **A conferência de base da regra 11 pagou de novo.** Worktree nasceu em `3035e1e`, o agente conferiu contra o hash do briefing, parou sem editar e reportou. Segundo despacho com worktree criada à mão na base certa.
- **A validação da regra 12 pegou o que a bateria do agente não pegou.** Rodar o fluxo real num repo que imita este — em vez de aceitar 49/49 verde — achou os dois defeitos em uma execução.
- **A mutação como catraca da própria correção.** Reintroduzir cada defeito e exigir que o caso novo ficasse vermelho matou três testes meus que não provavam nada. Sem esse passo eu teria commitado a terceira tentativa achando que estava coberto.
- **Nada se perdeu no emaranhado, e deu para provar.** Cherry-pick dos dois lados em branches temporárias e `git diff` da união contra a árvore emaranhada saiu **vazio** antes de mexer em ref nenhuma. Tags `backup/emaranhado-afedeef` e `backup/statusline-10c6d3b` continuam no repo.
- **Os conjuntos de arquivos eram disjuntos**, o que só foi verdade porque a outra sessão trabalhava `statusline/` e eu `skills/` + `scripts/estado*`. Foi sorte, não desenho — e é a razão de a separação ter custado 10 minutos em vez de uma tarde.

## Propostas

**P1 — O gate deixa de isentar a janela principal quando há outra sessão viva no mesmo diretório.** `gate-worktree.cjs` já casa `checkout|switch` no `GIT_QUE_MEXE`; falta a segunda condição: sem `agent_id`, mas com sessão ativa registrada **neste** diretório pelo radar da regra 17, `git checkout`/`switch`/`checkout -b` recusa com exit 2 e a mensagem oferece a saída certa (`git worktree add`). **Destino: `hooks/gate-worktree.cjs` + caso novo em `hooks/testa-gate-worktree.sh`.** Pendente.

**P2 — A regra 11 troca "branch nova" por "worktree nova" quando o diretório é compartilhado.** O texto de `SKILL.md:400` prescreve o ato que falhou. A correção não é acrescentar aviso: é que a saída para "esta branch tem dono" seja `git worktree add`, não `git checkout -b` — e que a condição de disparo saia de "antes do primeiro commit" para "antes de trocar de branch". **Destino: `skills/rainforest-mind/SKILL.md`, regra 11.** Pendente.

**P3 — O radar da regra 17 separa "outra janela neste diretório" de "outra janela noutro projeto".** Hoje as duas saem na mesma lista, com a mesma moldura de "paralelo é intenção". Sessão viva **no mesmo diretório** é uma categoria diferente, e a linha dela tem de dizer o efeito prático (`git checkout aqui move a janela dela`), não só o tempo de turno. **Destino: `hooks/foco-session-start.cjs`.** Pendente.

**P4 — `conferir-entrega.cjs` ganha instantâneo de árvore, como já tem de HEAD.** Um `--sujo-antes` (ou a lista capturada no despacho) faz a checagem 4 comparar contra o estado de antes em vez de contra "limpo", e acaba o falso positivo em diretório com outra sessão. Arrasta o gêmeo `conferir-entrega.py` e a bateria que roda contra os dois. **Destino: Issue no repo do plugin, com a saída desta sessão colada.** Pendente.

**P5 — Briefing de trava passa a exigir que o fixture declare em que o repo real difere dele.** Uma linha: "o fixture difere do alvo em X, Y" — e se o item medido depende de X, o critério não fecha. Aqui o fixture não versionava o arquivo de estado, que era **a** propriedade que a trava tocava. É mais barato que exigir fixture fiel, e nomeia o buraco em vez de escondê-lo. **Destino: `agents/tester.md` e `skills/plano/SKILL.md`.** Pendente.

**P6 — Nome de arquivo em teste de parsing posicional precisa diferir além do primeiro caractere.** Custou uma tentativa inteira: `1-rastreado.txt` e `2-rastreado.txt` colapsam no mesmo valor quando o defeito corta um caractere, e o teste passa com o defeito presente. **Destino: comentário já gravado em `scripts/testa-estado.sh`; generalizar em `agents/tester.md`.** Pendente.
