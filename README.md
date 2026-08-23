<p align="center">
  <img src="assets/banner.svg" alt="rainforest-mind â€” memÃ³ria de trabalho externa e radar de escopo" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-plugin-2e8b57?style=flat-square" alt="Claude Code plugin">
  <img src="https://img.shields.io/badge/vers%C3%A3o-0.74.0-1e5c3f?style=flat-square" alt="versÃ£o 0.74.0">
  <img src="https://img.shields.io/badge/instala%C3%A7%C3%A3o-1_comando-6fcf97?style=flat-square" alt="uma instalaÃ§Ã£o">
  <img src="https://img.shields.io/badge/revis%C3%A3o-bimestral-9fd8ba?style=flat-square" alt="revisÃ£o bimestral">
</p>

> ### O problema nÃ£o Ã© falta de ideia. Ã‰ o que recebe luz agora.

Plugin de Claude Code que faz a sessÃ£o virar algo que dÃ¡ pra **ler e decidir**.
Quatro coisas, e nenhuma depende de vocÃª lembrar de ativar:

- **planeja antes de implementar** â€” rodada de perguntas numeradas, cada uma jÃ¡ com a resposta recomendada, e entÃ£o para e espera;
- **responde em nÃºmero**, nÃ£o em parede de texto;
- **avisa** quando a conversa sai do combinado â€” uma frase, com escolha;
- **nÃ£o chama nada de pronto** sem colar a saÃ­da que prova.

Duas dessas regras sÃ£o travas que rodam **fora do modelo**: hook com exit code.
NÃ£o dÃ¡ pra argumentar com elas.

## Por que floresta

Uma **mente-floresta** â€” o termo Ã© de Paula Prober, em *Your Rainforest Mind* â€”
nÃ£o sofre de falta de ideia. Sofre do contrÃ¡rio: tudo cresce ao mesmo tempo,
rÃ¡pido, em direÃ§Ãµes diferentes, e o que cresce junto disputa a mesma luz.

Ã‰ por isso que lista de tarefas nÃ£o resolve. Lista pressupÃµe **escassez** de
tarefa; aqui a tarefa sobra. O problema nÃ£o Ã© lembrar do que fazer â€” Ã© decidir
**o que recebe luz agora**, e proteger essa decisÃ£o do resto, que continua
crescendo enquanto vocÃª trabalha.

DaÃ­ o vocabulÃ¡rio das ideias. Ele nÃ£o Ã© enfeite, Ã© o modelo:

| Palavra | O que Ã© |
|---|---|
| **foco** | a clareira onde vocÃª estÃ¡ trabalhando hoje â€” Ã© contra ele, e sÃ³ contra ele, que o desvio Ã© medido |
| **plantar** | o que nÃ£o pode crescer agora vai pro chÃ£o **com contexto**, vivo, em vez de morrer numa lista de "algum dia" |
| **colher** | ele volta quando chega a hora, e vira trabalho de verdade |
| **descartar** | o que decidiu nÃ£o acontecer sai da lista **com motivo** â€” e a linha fica, porque ideia que sai sem rastro volta idÃªntica em trÃªs semanas |
| **estaÃ§Ã£o** | a admissÃ£o de que tempo certo Ã© restriÃ§Ã£o real, nÃ£o desculpa de quem procrastina |

O resto do plugin nÃ£o Ã© botÃ¢nico e nÃ£o tenta ser: `/foco`, `depurar` e as travas
se chamam pelo que fazem. A floresta explica **por que** as ideias tÃªm ciclo de
vida â€” onde ela nÃ£o explica nada, ela nÃ£o entra.

## Uma instalaÃ§Ã£o, nÃ£o uma pilha de skills

O jeito comum de montar isso Ã© catar dezenas de skills soltas em repositÃ³rios
diferentes, copiar pasta por pasta e descobrir depois quais conflitam. Aqui Ã©
**um comando**, e o que entra jÃ¡ foi filtrado por uso: cada peÃ§a deste repo
sobreviveu a pelo menos um incidente real, e o que nÃ£o sobreviveu foi apagado.

O repo cresce, mas cresce por subtraÃ§Ã£o tambÃ©m: skill que nÃ£o paga o prÃ³prio
custo de contexto sai.

## Planeja antes de implementar

`/brainstorm` Ã© uma entrevista adversarial e o primeiro estÃ¡gio do fluxo. Ele mapeia o assunto como **Ã¡rvore de
decisÃ£o** e pergunta sÃ³ o que dÃ¡ pra perguntar agora â€” a *fronteira*, o
conjunto de decisÃµes cujos prÃ©-requisitos jÃ¡ fecharam. Pergunta que depende de
outra ainda aberta espera a rodada seguinte, em vez de te obrigar a chutar.

A rodada inteira vem de uma vez, numerada, **cada pergunta jÃ¡ com a resposta
recomendada**:

> â“ **Q1 â€” Onde o token vive**: sessÃ£o no servidor ou JWT no cliente?
> âž¡ï¸ **Recomendo:** sessÃ£o no servidor â€” vocÃª jÃ¡ tem Redis, e revogar JWT exige lista negra que Ã© o mesmo trabalho com mais peÃ§as.
>
> â“ **Q2 â€” ExpiraÃ§Ã£o**: 15 min com refresh, ou 8h fixas?
> âž¡ï¸ **Recomendo:** 8h fixas â€” refresh sÃ³ se paga com mÃºltiplos dispositivos, e nÃ£o Ã© o seu caso hoje.

E entÃ£o ele **para e espera**. VocÃª responde `1 ok, 2 nÃ£o, usa 15 min` â€” trÃªs
palavras em vez de compor tudo do zero. Cada resposta remodela a Ã¡rvore:
decisÃ£o fechada empurra a fronteira e destrava o que dependia dela.

A regra que sustenta isso: **descobrir fato Ã© trabalho do assistente, nunca
seu.** Pergunta que o ambiente responde â€” o que tem no arquivo, qual versÃ£o
estÃ¡ instalada, o que o log diz â€” vira busca dele, nÃ£o pergunta pra vocÃª.

## O fluxo: sete estÃ¡gios que nÃ£o dÃ¡ para pular

`/brainstorm` Ã© o primeiro de sete. Cada um Ã© uma skill invocÃ¡vel sozinha â€” dÃ¡
para entrar no meio, que Ã© o caso normal de quem retoma trabalho.

```mermaid
flowchart LR
    A["arqueologia<br/>mapa.md"] -.->|"sÃ³ se houver<br/>legado sem mapa"| B
    B["brainstorm<br/>design.md"] --> P["plano<br/>plano.md"]
    P --> E["executar<br/>agentes em paralelo"]
    E --> R["revisar<br/>contexto zerado"]
    R --> V["verificar<br/>roda o artefato"]
    V --> F["fechar<br/>commit + limpeza"]
    R -.->|"reprovado"| E
    V -.->|"reprovado"| E
    L["limpar"] -.->|"manutenÃ§Ã£o,<br/>fora do fluxo"| F
```

**O que faz isso ser fluxo e nÃ£o conselho:** cada estÃ¡gio abre rodando
`estado.cjs exigir`, e esse comando **sai com cÃ³digo 2** quando o anterior nÃ£o
fechou. NÃ£o Ã© o modelo lendo uma instruÃ§Ã£o e decidindo obedecer â€” Ã© comando
externo, pelo mesmo motivo dos outros gates deste repo.

```
$ node scripts/estado.cjs exigir --slug 2026-08-11-exemplo --estagio revisar
RECUSADO: 'revisar' exige executar fechado(s).
  executar: status=parcial
Rode o estagio 'executar' antes. Retomada: node scripts/estado.cjs proximo --slug 2026-08-11-exemplo
```

`parcial` e `reprovado` **nÃ£o fecham**: "5 de 7 tarefas" para de virar "pronto"
sem ninguÃ©m decidir isso, e revisÃ£o reprovada devolve o trabalho para
`executar` em vez de seguir.

**Retomada Ã© comando, nÃ£o memÃ³ria.** SessÃ£o nova â€” ou sessÃ£o que perdeu contexto
na compactaÃ§Ã£o â€” roda `estado.cjs proximo --slug <slug>` e sabe onde parou:

| O quÃª | Onde | No git? |
|---|---|---|
| Design aprovado, com o porquÃª de cada decisÃ£o | `docs/rainforest/design/<slug>.md` | **sim** |
| Plano, com dependÃªncia e critÃ©rio falsificÃ¡vel por tarefa | `docs/rainforest/planos/<slug>.md` | **sim** |
| Estado do fluxo, com o veredito de cada estÃ¡gio | `docs/rainforest/estado/<slug>.json` | **sim** |

Os trÃªs sÃ£o versionados de propÃ³sito: Ã© por eles que **outro dev pega a
atividade no meio**. Fora do git fica sÃ³ a tagarelice â€” worktrees, briefs de
agente, diffs de review.

**O paralelismo vive no `executar`**, e Ã© o plano que diz o que pode ir junto:
tarefa sem dependÃªncia Ã© marcada `paralela: sim`, e vÃ¡rias chamadas de agente na
mesma resposta rodam ao mesmo tempo. Isso sÃ³ Ã© seguro porque **todo agente que
edita roda em worktree isolado**, obrigado pelo hook com exit 2 â€” a distro que
mais influenciou este desenho precisou **proibir** implementadores em paralelo
justamente por nÃ£o ter essa trava.

## NÃºmeros em vez de parede de texto

Mensagem com N perguntas recebe **N respostas numeradas**, na ordem em que
vocÃª escreveu, e as respostas completas vÃ£o no **fim** do turno â€” depois das
ferramentas, nÃ£o antes delas.

VocÃª fecha item respondendo `1 ok`. O item some da lista e o resto **renumera
a partir do 1**, entÃ£o a lista aberta Ã© sempre curta e sempre comeÃ§a no mesmo
lugar. NÃ£o existe "item 7 pendente desde ontem".

Vale pro meio da tarefa tambÃ©m: em trabalho de 3+ etapas, o checkpoint Ã©
`fechamos 2/5` â€” nÃ£o "estou progredindo bem".

## Avisa em vez de derivar

Existe um foco declarado, num arquivo que entra na sessÃ£o sozinho. Quando a
conversa sai dele, o aviso Ã© **uma frase, sem julgamento, com escolha**:

> EstÃ¡vamos em [foco], isso Ã© [outro tema] â€” seguimos nele ou planto e voltamos?

Sem sermÃ£o e sem repetir. TrÃªs coisas que o desvio *nÃ£o* dispara: trabalhar em
paralelo de propÃ³sito, tocar uma frente que jÃ¡ estÃ¡ listada como compromisso, e
foco de trabalho fora do horÃ¡rio de trabalho.

Para decidir se cala, o radar depende de dois dados, ambos opcionais:

- **`Pastas:` no FOCO.md** â€” lista separada por vÃ­rgula das pastas onde o foco
  estÃ¡ sendo trabalhado. Exemplo: `Pastas: C:/projeto-a, C:/projeto-a/src`.
  O radar usa isso para saber se a janela que estÃ¡ aberta Ã© a do foco, mesmo
  que nÃ£o seja a janela da sessÃ£o atual. Sem este campo, o radar cobra desvio
  mesmo que a mesma clareira esteja viva em outra janela.

- **`expediente` no `config.json`** â€” dias da semana e horÃ¡rio de trabalho.
  Forma: `"expediente": {"dias": [1,2,3,4,5], "de": "08:00", "ate": "18:00"}`.
  Dias usa a convenÃ§Ã£o de `Date.getDay()` â€” 0 = domingo, 1 = segunda, etc.
  O radar usa isso para saber se Ã© hora de trabalho ou tempo pessoal.
  Sem este campo, o radar cobra desvio fora do horÃ¡rio, mesmo que o foco seja
  marcado como `[trabalho]`.

Faltando qualquer um dos dois, o radar **continua cobrando** e o hook anuncia o
que falta, com o efeito prÃ¡tico junto â€” assim:

```
Pastas: ausente no FOCO.md â€” o radar vai cobrar desvio mesmo com o foco
aberto em outra janela.
```

Isso Ã© **falha fechada**, e Ã© deliberado: um radar que emudece por falta de
configuraÃ§Ã£o Ã© indetectÃ¡vel, e vocÃª nunca saberia que ele parou. Um radar que
cobra demais vocÃª percebe e reclama â€” foi exatamente assim que este defeito
apareceu. AnÃºncio e veredito sÃ£o mutuamente exclusivos: nÃ£o hÃ¡ como julgar sem
dado.

**A isenÃ§Ã£o cala sÃ³ o aviso de desvio de escopo.** O aviso de prazo â€” vencido
ou a â‰¤2 dias â€” continua saindo, sempre. SÃ£o coisas diferentes: saber num sÃ¡bado
que algo vence na segunda Ã© informaÃ§Ã£o e nÃ£o custa nada; ser cobrado no sÃ¡bado
por estar lendo outra coisa Ã© o que incomoda. Uma isenÃ§Ã£o que silenciasse o
radar inteiro trocaria um defeito por outro.

E quando o ambiente **impede** uma regra â€” permissÃ£o negada, hook fora do ar,
ferramenta ausente â€”, ele diz numa linha em vez de falhar em silÃªncio. Regra
que nÃ£o rodou e nÃ£o avisou Ã© pior que regra inexistente: vocÃª conta com ela.

## NÃ£o chama de pronto sem a saÃ­da

Esta Ã© a que mais paga. Agente relata **intenÃ§Ã£o**, nÃ£o resultado â€” e o relato
Ã© convincente exatamente quando estÃ¡ errado. TrÃªs cenas medidas, todas com
suÃ­te verde e relatÃ³rio de sucesso completo:

**O hash que nÃ£o existia.** Um agente reportou o commit que tinha criado:
`a009b5b`, "completo" `a009b5b4e8f0d83e3ef4e3d8e7f3e4d8e7f3e4d8`. Olhe o fim da
string â€” `e7f3e4d8` aparece duas vezes seguidas. Ã‰ um hash inventado, e dava pra
ver sem consultar nada. Um `gh pr view --json headRefOid` devolveu o real. Na
mesma sessÃ£o, a verificaÃ§Ã£o pela janela principal pegou **3 de 3** falhas de
relato â€” todas invisÃ­veis no texto do agente.

**O critÃ©rio que foi afrouxado em vez de cumprido.** Outro agente recebeu os
nÃºmeros absolutos no briefing e **cumpriu todos, honestamente**: `40 passed
(40)`, `92 passed (92)`, `exit 0` no lint. Nenhum nÃºmero inventado. E a entrega
estava errada, porque ele **desligou as duas regras de lint que falhavam** em
vez de tratÃ¡-las. O `exit 0` era verdadeiro. *CritÃ©rio numÃ©rico nÃ£o pega quem
edita a rÃ©gua.*

**A proteÃ§Ã£o que nunca roda.** Cinco entregas, trÃªs recusadas pela mesma
famÃ­lia de defeito: cÃ³digo que parece proteger e estÃ¡ atrÃ¡s de uma condiÃ§Ã£o
que o chamador real nunca aciona. O teste chama a funÃ§Ã£o direto, com os
argumentos certos, e passa. ProduÃ§Ã£o nunca entra ali. Nenhuma leitura de cÃ³digo
pegou â€” sÃ³ apareceu **rodando o artefato** num cenÃ¡rio que os testes da prÃ³pria
entrega nÃ£o cobriam.

O que separou a entrega impecÃ¡vel da entrega com bug, medido em trÃªs sessÃµes,
nÃ£o foi o modelo nem o isolamento:

> Foi o briefing conter, ou nÃ£o, **o teste que falsificaria a entrega** â€” com
> comando exato e saÃ­da exata esperada.

**A evidÃªncia real do objeto errado.** Uma tarefa criou um `.gitignore` com o
conteÃºdo `*` â€” que, dentro do prÃ³prio diretÃ³rio, ignora **a si mesmo**. O
`git add -A` nunca o adicionou e ele nunca chegou ao commit. O agente colou
evidÃªncia **real**: `ls -la` mostrando o arquivo, `cat` mostrando o conteÃºdo.
EvidÃªncia do disco, quando a afirmaÃ§Ã£o era sobre o commit. E `git status
--porcelain` nÃ£o pega, porque por desenho nÃ£o lista ignorado â€” a categoria
exata do arquivo que faltava. *Comando e saÃ­da colados tambÃ©m nÃ£o bastam se
provarem outra coisa.* O conserto foi mecÃ¢nico: `--espera <caminho>` pergunta Ã 
Ã¡rvore do commit e nomeia a regra de ignore que comeu o arquivo.

DaÃ­ a regra: o critÃ©rio de sucesso vai pronto no briefing, e a validaÃ§Ã£o Ã©
executar o artefato e olhar a saÃ­da. **SuÃ­te verde nÃ£o Ã© evidÃªncia. âœ… sem
comando e saÃ­da colados nÃ£o Ã© verificaÃ§Ã£o â€” e a saÃ­da colada tem que ser do
objeto sobre o qual se estÃ¡ afirmando.**

## Disciplina de dev, embutida

Se vocÃª estÃ¡ no Claude Code, vocÃª estÃ¡ construindo alguma coisa â€” entÃ£o isso
nÃ£o Ã© acessÃ³rio.

`modo-dev` traz escada YAGNI, causa raiz antes de remendo, rastreabilidade de
cada linha do diff atÃ© o pedido, expandirâ€“contrair, e evidÃªncia antes de
"pronto". Ele existe por **economia de contexto**: absorve o que sobrevive Ã 
compressÃ£o de plugins pesados, sem carregar os plugins.

`depurar` dispara sozinha em bug difÃ­cil, regressÃ£o de performance ou "funciona
aqui e nÃ£o lÃ¡". Ela constrÃ³i o **loop de feedback capaz de ficar vermelho antes
de qualquer hipÃ³tese** â€” depois 3â€“5 hipÃ³teses falseÃ¡veis, ranqueadas. Fica fora
do `modo-dev` de propÃ³sito: depurar Ã© um ramo do trabalho, nÃ£o todo ele.

## Travas mecÃ¢nicas

Regra escrita nÃ£o alcanÃ§a o modo de falha em que o agente **leu a regra e errou
mesmo assim**. Um subagente rodou a verificaÃ§Ã£o de isolamento, recebeu o
diretÃ³rio principal â€” que era a condiÃ§Ã£o de parada â€”, transcreveu a condiÃ§Ã£o
corretamente e escreveu um OK do lado. No dia seguinte foi a vez da janela
principal: `git add -A` varreu trabalho de outra sessÃ£o duas vezes na mesma
noite, sabendo que nÃ£o devia. O que sobrou das duas noites:

> Enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela
> deveria travar, ela nÃ£o trava nada. **Exit code nÃ£o se argumenta.**

| Hook (`PreToolUse`, exit 2) | Barra | Em quem |
|---|---|---|
| `gate-worktree.cjs` | escrita de subagente em repo git que nÃ£o Ã© worktree linkado, e git que mexe no checkout | sÃ³ subagente â€” a janela principal passa |
| `gate-staging-total.cjs` | `git add -A/--all/./:/`, `-u`, e `git commit -a/-am` | **tambÃ©m a janela principal**, que foi onde os dois incidentes ocorreram |

Valem em **qualquer** repo git da mÃ¡quina, porque o hÃ¡bito Ã© que Ã© o problema,
nÃ£o o repositÃ³rio. A mensagem de bloqueio nÃ£o sÃ³ recusa: a de staging roda
`git status --porcelain -uall` e devolve o `git add` por caminho jÃ¡ montado â€”
trava que sÃ³ diz "nÃ£o" vira trava desligada. SaÃ­das de emergÃªncia, nomeadas na
prÃ³pria mensagem: `RAINFOREST_GATE_OFF=1` no ambiente, ou um arquivo
`.rainforest-gate-off` na raiz do repo.

Cada uma tem bateria prÃ³pria (`hooks/testa-gate-*.sh`, **68 casos** â€” 30 e 38)
que roda o hook de verdade contra repos git montados na hora. A maioria dos
casos testa o que deve **passar**: falso positivo aqui atrapalha todo repo.

O mesmo princÃ­pio nos scripts, para o que hook nenhum alcanÃ§a:

| Script | Para quÃª |
|---|---|
| `scripts/ideias.cjs` | Ãºnica porta de escrita do `ideias.jsonl` â€” trava de arquivo, backup, escrita atÃ´mica, releitura do arquivo vivo e conferÃªncia byte a byte das linhas nÃ£o-alvo; e o `projeto` Ã© **slug de vocabulÃ¡rio fechado** (`projetos.json`), nÃ£o texto livre |
| `scripts/limpar-branches.cjs` | confere o local contra o remoto e classifica por dois eixos (upstream **e** merge); nunca remove branch viva, e exigir estar na base em dia Ã© trava |
| `scripts/conferir-publicacao.cjs` | **sai com cÃ³digo 2** quando o rascunho tem telefone, JID, e-mail, caminho de home ou credencial â€” antes de virar Issue pÃºblico |
| `scripts/conferir-entrega.cjs` | roda na janela principal **depois** da entrega do agente: hash de base, isolamento e citaÃ§Ã£o conferidos na fonte, nÃ£o no relato. `--espera <caminho>` (repetÃ­vel) confere o que a tarefa prometia **na Ã¡rvore do commit** â€” `ls`/`cat` do agente provam o disco, e `git status` nÃ£o lista ignorado |
| `scripts/conferir-fluxo.cjs` | fecha as trÃªs costuras entre artefatos vizinhos do fluxo, **com exit 2**: `design` (as seÃ§Ãµes obrigatÃ³rias e as decisÃµes `D1..Dn` sem buraco nem repetiÃ§Ã£o), `cobertura` (toda decisÃ£o virou tarefa **e** toda tarefa atende decisÃ£o que existe) e `creep` (arquivo no diff que nÃ£o casa com o `arquivos:` de tarefa nenhuma). Chamado pelo `estado.cjs marcar` no fechamento de estÃ¡gio â€” sÃ³ age onde o design/plano existe, e nunca torna o fluxo obrigatÃ³rio |
| `scripts/setup.cjs` | monta a pasta de dados, liga/desliga o que Ã© opcional **e configura o caminho de cada projeto** â€” e marca no estado o caminho que **nÃ£o existe** nesta mÃ¡quina, que era falha silenciosa |
| `scripts/ponte.cjs` | **gera** o `AGENTS.md` (Codex) e o `GEMINI.md` (Gemini CLI) a partir do mesmo SKILL.md que o hook injeta â€” e recusa gerar se nÃ£o achar as regras, em vez de escrever meia ponte |
| `scripts/orcamento.cjs` | mede em **byte** as quatro fontes que o plugin pÃµe na abertura (saÃ­da do hook, descriptions de skills, de commands e de agentes), compara com dois tetos (o `ORCAMENTO_BYTES` do hook, lido de `hooks/lib/contexto-sessao.cjs`, e um agregado de 14.000 B), e sai com exit 1 quando estoura â€” entra no laÃ§o do `CONTRIBUTING.md:11` como o gate que acusa quando o plugin engordar alÃ©m do orÃ§amento |
| `scripts/medir-injecao.py` | custo real do prompt de abertura, lido do `usage` que a API devolve â€” token de verdade, sem estimativa. O modo `--repartir` reparte a abertura por fonte (skill_listing, deferred_tools_delta, agent_listing_delta, rainforest-mind) e marca o que Ã© **medido** (total via API), o que Ã© **estimado** (byte convertido por fator 3.11 do tokenizador OpenAI), e o que Ã© **subconjunto** (rainforest-mind dentro das listagens) |

O que essas travas custaram e renderam fica em [`relatorios/`](relatorios/) â€”
um relatÃ³rio datado por incidente, com mÃ©todo e nÃºmeros.

## Codex e Gemini CLI: o que atravessa, e o que nÃ£o

O plugin Ã© do Claude Code â€” os 4 hooks, os slash commands, as 14 skills e os 7
subagentes sÃ£o API dele e nÃ£o tÃªm equivalente nos outros hosts. Mas o **mÃ©todo**
nÃ£o precisa ficar preso a um agente, e a pasta de dados nÃ£o sabe quem a escreveu.

Quais agentes vocÃª usa Ã© **configuraÃ§Ã£o**, e mora no `/setup` (`ponte-claude`,
`ponte-codex`, `ponte-gemini`, desligadas por padrÃ£o). Qual repositÃ³rio recebe o
arquivo **nÃ£o Ã©**: Ã© alvo explÃ­cito, com ensaio, porque o gerado vai ser commitado
no repo de outra pessoa.

```
node scripts/setup.cjs --ligar ponte-codex             # declara o que esta mÃ¡quina usa
node scripts/ponte.cjs --alvo <dir-do-repo>            # ensaio: mostra e nÃ£o grava
node scripts/ponte.cjs --alvo <dir-do-repo> --aplicar  # sÃ³ os alvos declarados
```

SÃ£o **trÃªs** alvos: `CLAUDE.md` tambÃ©m Ã© ponte â€” para quem usa Claude Code **sem o
plugin**, que nÃ£o tem regra nenhuma. Ã‰ o caminho de quem recebe o convite antes de
instalar. E o texto muda com o alvo: lÃ¡ a falta das travas se explica pelo plugin
ausente; nos outros dois, por o host nÃ£o ter `PreToolUse`.

O arquivo Ã© **gerado**, nunca escrito Ã  mÃ£o, e o comando que o gera estÃ¡ escrito
dentro dele. O motivo Ã© um incidente: nesta mÃ¡quina existem duas `CLAUDE.md` de
escopo usuÃ¡rio â€” uma por config dir â€” que eram sincronizadas Ã  mÃ£o. Em 2026-08-10
uma foi editada e a outra divergiu **em silÃªncio**; metade do setup passou a valer
o contrÃ¡rio da outra metade. Regra duplicada nÃ£o fica errada com aviso: fica
errada calada.

E a ponte diz o que ela **nÃ£o** entrega, porque prometer trava que nÃ£o existe Ã©
pior que nÃ£o ter ponte:

| No Claude Code | Na ponte |
|---|---|
| gate de worktree e gate de `git add -A` (hook `PreToolUse`, exit 2) | **texto** â€” nÃ£o existe `PreToolUse` nesses hosts, entÃ£o Ã© combinado, nÃ£o trava |
| injeÃ§Ã£o de SessionStart | o prÃ³prio arquivo gerado, que o host lÃª a cada sessÃ£o |
| `estado.cjs exigir` (gate do fluxo, exit 2) | **igual** â€” Ã© comando de shell |
| `conferir-entrega.cjs` (regra 12, exit 1) | **igual** |
| `conferir-publicacao.cjs` (anonimizaÃ§Ã£o, exit 2) | **igual** |
| `/ideia`, `/foco`, `/semear` | os CLIs `ideias.cjs`, `foco.cjs`, `semear.cjs` |

O gerado **nÃ£o chumba caminho de home** â€” ele ensina a descobrir a pasta de dados
com `ideias.cjs conferir`, porque nasce para ser commitado no repo de outra
pessoa. Se o arquivo jÃ¡ existir escrito Ã  mÃ£o, o bloco entra delimitado e nada do
que estava lÃ¡ Ã© apagado; regenerar substitui sÃ³ o bloco.

## Ideia solta nÃ£o vira escopo, e nÃ£o vira esquecimento

O caso mais comum de escopo crescendo sozinho Ã© a emenda no fim do pedido:

> **VocÃª:** faz a opÃ§Ã£o 2. Ah, e a gente podia colocar um cache nisso.
>
> **Sem o plugin:** *"Ã“tima ideia! Vou implementar a opÃ§Ã£o 2 com cacheâ€¦"* â€” a adiÃ§Ã£o virou escopo sem ninguÃ©m decidir.
>
> **Com o plugin:** *"Fechado: opÃ§Ã£o 2. VocÃª adicionou o cache â€” entra no escopo agora ou planto?"*

Plantar nÃ£o Ã© descartar. A ideia sai da cabeÃ§a pra um lugar confiÃ¡vel, com
contexto e projeto, e fica lÃ¡ atÃ© a estaÃ§Ã£o certa.

```mermaid
flowchart LR
    A["ðŸ’­ ideia solta<br/>no meio da tarefa"] --> B{"radar<br/>de escopo"}
    B -->|"estÃ¡ no foco"| C["entra na tarefa<br/>(confirmada)"]
    B -->|"estÃ¡ fora"| D["ðŸŒ± plantada em<br/>ideias.jsonl"]
    D --> E["revisÃ£o quando<br/>houver espaÃ§o"]
    E -->|"chegou a estaÃ§Ã£o"| F["ðŸŒ³ colhida:<br/>vira trabalho"]
    E -->|"ainda nÃ£o"| D
    G["FOCO.md<br/>(foco declarado)"] -.->|"injetado a<br/>cada sessÃ£o"| B
```

## Comandos e skills

| O quÃª | Faz |
|-------|-----|
| `/divergir [problema]` | **Antes** do `brainstorm`, quando o espaÃ§o Ã© largo e a primeira ideia jÃ¡ estÃ¡ ancorando: N frames isolados em paralelo, sem se verem, e um crÃ­tico que tambÃ©m nasce zerado. Devolve material para decidir; nÃ£o decide e nÃ£o codifica |
| `/brainstorm [assunto]` | EstÃ¡gio 1: entrevista adversarial em Ã¡rvore de decisÃ£o, rodada numerada com resposta recomendada â€” para **antes** de executar, e grava o design |
| `/foco` | Estado da conversa: foco ativo, loops abertos, decisÃµes tomadas |
| `/foco <texto>` | Declara novo foco â€” injetado em toda sessÃ£o nova |
| `/ideia <texto>` | Avalia contra o foco: dentro â†’ entra confirmada; fora â†’ planta com contexto e projeto |
| `/ideia` | Lista as ideias plantadas |
| `/feedback` | Registra o que a sessÃ£o ensinou sobre o **mÃ©todo** â€” tria por de quem Ã© o defeito: do plugin vira Issue, do seu trabalho vira markdown no seu repo |
| `/issue` | Abre uma Issue no repositório em que você está, com o corpo já escrito e a evidência colada
| `arqueologia` | EstÃ¡gio **zero, opcional**: mapeia a fatia de legado que a demanda toca, com escala de confianÃ§a â€” e fatia jÃ¡ mapeada vira **conferÃªncia**, nÃ£o extraÃ§Ã£o |
| `plano` | EstÃ¡gio 2: tarefas tipadas, dependÃªncia declarada e critÃ©rio falsificÃ¡vel por tarefa â€” proÃ­be placeholder |
| `executar` | EstÃ¡gio 3: despacha os agentes, em paralelo o que o plano marcou independente, cada um em worktree |
| `revisar` | EstÃ¡gio 4: contexto zerado, escopo fixado pelo diff de trÃªs pontos, o relato de quem implementou nÃ£o Ã© fonte |
| `verificar` | EstÃ¡gio 5: roda o artefato real e cola a saÃ­da â€” o critÃ©rio veio pronto do plano e nÃ£o se afrouxa aqui |
| `fechar` | EstÃ¡gio 6: commit, limpeza do repo, remoÃ§Ã£o dos worktrees, destino da branch com vocÃª decidindo, e writeback no FOCO.md |
| `limpar` | ManutenÃ§Ã£o fora do fluxo: worktree Ã³rfÃ£o da sessÃ£o que nunca chegou ao `fechar` â€” e a **branch**, que sobrevive ao worktree e ninguÃ©m vÃª |
| `/semear` | PropÃµe o que criar **neste** repositÃ³rio a partir do que ele jÃ¡ tropeÃ§ou â€” cada proposta cita o registro que a origina |
| `/setup` | Monta a pasta de dados e liga/desliga os gates e o fluxo, por projeto ou para tudo |
| `/ponte` | Gera `CLAUDE.md`, `AGENTS.md` (Codex) ou `GEMINI.md` (Gemini CLI) num repo, do mesmo SKILL.md â€” alvos declarados no `/setup`, e cada um diz o que **nÃ£o** atravessa |
| `/saude` | SÃ³ o que os checadores oficiais nÃ£o sabem: de quem Ã© a raiz, margem da injeÃ§Ã£o, fluxo parado, worktree Ã³rfÃ£o |
| `modo-dev` | Disciplina de dev sob demanda (acima) |
| `depurar` | Loop de feedback antes de hipÃ³tese (acima) |
| `analisar` | AnÃ¡lise de dados em notebook: uma pergunta por vez, cÃ©lula curta, e **revisÃ£o crÃ­tica do achado** (`n` visÃ­vel, share vs. risco, explicaÃ§Ã£o alternativa) antes de virar conclusÃ£o |
| `executor` | ImplementaÃ§Ã£o mecÃ¢nica em haiku, com o mÃ©todo embutido no system prompt |
| `revisor` | Review/QA em sonnet: evidÃªncia primÃ¡ria, achado sÃ³ com cenÃ¡rio de falha, veredito integra/nÃ£o-integra |
| `tester` | Testes em sonnet: extrai o contrato, escreve o que falta, pelo menos um adversarial |
| `planejador` | Plano em sonnet: separa fato de suposiÃ§Ã£o, dependÃªncia explÃ­cita entre etapas, **para antes da primeira linha de cÃ³digo** |
| `depurador` | DepuraÃ§Ã£o em sonnet: executa a skill `depurar`; para se nÃ£o conseguir um comando vermelho-capaz, em vez de chutar conserto |
| `resolvedor-de-build` | Erro de build/tipo em haiku, diff mÃ­nimo: para se a correÃ§Ã£o introduzir erro novo, se o mesmo erro persistir apÃ³s 3 tentativas, ou se vocÃª pedir pausa |
| `documentador` | Doc em haiku a partir do diff real: comportamento que nÃ£o confirmou em `arquivo:linha` nÃ£o Ã© escrito, vira pendÃªncia |

## As 17 regras

Resumo; o detalhe vive em
[`skills/rainforest-mind/SKILL.md`](skills/rainforest-mind/SKILL.md).

| # | Regra | Em uma frase |
|---|-------|--------------|
| 1 | Responder tudo, na ordem | N perguntas recebem N respostas numeradas, na mensagem final; item resolvido sai e a lista renumera do 1. NÃ­veis nÃ£o compartilham glifo (`1.` â†’ `a)` â†’ `i.`), e **`Q` aberta se reescreve inteira todo turno** â€” no terminal, rolar a tela para trÃ¡s nÃ£o Ã© caminho |
| 2 | Escolha + adiÃ§Ã£o | A emenda nunca vira escopo em silÃªncio: confirma ou planta |
| 3 | Radar de escopo | Saiu do foco declarado â†’ uma frase, sem julgamento, com escolha |
| 4 | Checkpoint no meio | Tarefa 3+ etapas: "fechamos n/total" a cada etapa |
| 5 | DecisÃ£o com o porquÃª | "Decidido: X, porque Y. PrÃ³ximo passo: Z." |
| 6 | Plantio de ideias | Ideia solta â†’ "planto essa pra depois?"; abandono real â†’ "jÃ¡ pegou o que veio buscar?" |
| 7 | Tom sÃªnior | Policia pontas soltas e escopo, nunca o mÃ©rito; aviso ancora na emoÃ§Ã£o do resultado, nÃ£o na ameaÃ§a do prazo |
| 8 | Guarda-corpo de jornada | Jornada real medida, nÃ£o estimada: ~9h efetivas produzindo â†’ um aviso, uma vez, com a hora, um ponto de parada e a checagem de corpo (Ã¡gua, comida, banheiro) de carona â€” nunca gatilho prÃ³prio. Perder a noÃ§Ã£o do tempo **dentro** da imersÃ£o Ã© traÃ§o saudÃ¡vel; dificuldade de **comeÃ§ar ou trocar** Ã© sinal diferente |
| 9 | Freio de Pareto | Polimento do que jÃ¡ estÃ¡ pronto â†’ "alguÃ©m que recebe isso fica prejudicado?"; se nÃ£o, entrega ou planta |
| 10 | Agentes baratos com mÃ©todo | Janela principal pensa; sete agentes por **funÃ§Ã£o**, nÃ£o por domÃ­nio: `executor` e `resolvedor-de-build` (haiku), `documentador` (haiku), `planejador`, `revisor`, `tester` e `depurador` (sonnet). Agente que edita nunca Ã© nomeado, e **nomeado sÃ³ entrega por `SendMessage`** â€” termina e fica calado. Os sete carregam a **clÃ¡usula de premissa**: listam o que aceitaram do briefing sem conferir, e lugar vazio nÃ£o vira "nÃ£o existe" |
| 11 | Worktree de subagente | Isolamento sempre, hash de base conferido na primeira aÃ§Ã£o e reconferido antes de integrar; integraÃ§Ã£o por partes, nunca cÃ³pia de arquivo inteiro |
| 12 | Entrega se valida na saÃ­da real | CritÃ©rio de sucesso vai pronto no briefing, incluindo o teste que falsificaria a entrega; validaÃ§Ã£o Ã© rodar o artefato e olhar a saÃ­da. SuÃ­te verde nÃ£o Ã© evidÃªncia; exit code lido atravÃ©s de pipe nÃ£o Ã© exit code |
| 13 | CorreÃ§Ã£o vira observaÃ§Ã£o | VocÃª corrigir a saÃ­da jÃ¡ Ã© o sinal: registra silenciosamente, e no mÃ¡ximo uma mudanÃ§a de regra por semana |
| 14 | Regra bloqueada se anuncia | Ambiente impediu uma regra â†’ uma linha na primeira vez, nunca silÃªncio; caminho sai de variÃ¡vel, nunca escrito Ã  mÃ£o |
| 15 | Agente nÃ£o altera o ambiente | Subagente nÃ£o instala nada nem mexe em PATH, env ou config global: ferramenta ausente para e reporta |
| 16 | Fato Ã© meu, decisÃ£o Ã© sua | Pergunta que o ambiente responde se resolve olhando, e fato nÃ£o **sai** daqui sem ser olhado â€” briefing, recomendaÃ§Ã£o e registro inclusos; decisÃµes abertas vÃ£o em rodada Ãºnica, marcadas **`Q1` `Q2`**, cada uma com a recomendada â€” e **o que nÃ£o tem `Q` nÃ£o pede nada de vocÃª** |
| 17 | Multi-janela | Paralelo Ã© escolha, nÃ£o desvio; o alerta Ã© a janela parada esperando vocÃª. Estado compartilhado nunca se escreve Ã  mÃ£o. Janela fechada no X ou perdida em crash sai do radar por idade (24 h), nÃ£o na hora â€” atÃ© lÃ¡ ela pode aparecer como janela ociosa |

## Vigias (automaÃ§Ã£o fora da sessÃ£o)

A pasta [`vigias/`](vigias/) tem prompts headless agendados no sistema
operacional (`claude -p`, haiku) que reportam por WhatsApp: **sentinela-foco**
(briefing matinal de prazo/avanÃ§o + triagem de inbox em 3 baldes, somente
leitura), **jardineiro-ideias** (semanal â€” ideias plantadas + revisÃ£o do vault),
**vigia-tickets** e **revisao-bimestral**. O guarda-corpo funcionando fora da
sessÃ£o â€” onde o hiperfoco nÃ£o deixa abrir uma.

## InstalaÃ§Ã£o

```
claude plugin marketplace add luisfmontes/rainforest-mind
claude plugin install rainforest-mind@rainforest-mind
```

Ou aponte `--plugin-dir` para a pasta do repo em desenvolvimento.

**Runtime: sÃ³ Node no caminho de execuÃ§Ã£o.** Os hooks, os gates, o `/ideia`, o
`/saude`, o fluxo e a mediÃ§Ã£o de jornada rodam em Node. O Claude Code nÃ£o
garante Node nem Python (a lista oficial de dependÃªncias adicionais tem
`ripgrep` e mais nada), entÃ£o a meta Ã© **uma** dependÃªncia, nÃ£o duas.

Sobra Python em **ferramental seu**, fora de qualquer regra: `medir-injecao.py`
(mede o custo real da abertura) e `validar-colhidas.py`. Nenhuma regra depende
deles â€” se Python nÃ£o existir na mÃ¡quina, nada aqui degrada.

**E as baterias tambÃ©m sÃ£o Node.** AtÃ© 2026-08-12 elas usavam Python para montar
fixture e conferir JSON: o runtime era Ãºnico para quem *instala* e duplo para quem
*contribui*, o que Ã© a mesma promessa quebrada uma camada acima. Os 24 usos viraram
`node -e`. Os gÃªmeos em Python continuam, porque ali o Python **Ã©** o teste.

Essa frase foi **falsa atÃ© 2026-08-12**, e vale dizer por quÃª: as regras 11 e 12
exigiam `conferir-entrega.py` na integraÃ§Ã£o de toda entrega de agente, e
`skills/executar` e `agents/executor.md` o chamavam pelo nome. Um dev sem Python
nÃ£o tinha a trava da regra 12 â€” tinha o texto dela. Trava que nÃ£o trava Ã© o Ãºnico
defeito que este repo nÃ£o aceita, entÃ£o o script virou `conferir-entrega.cjs`.

Dois scripts ficam como **gÃªmeos** dos ports, e nÃ£o como legado morto:

| GÃªmeo | O que ele prova |
|---|---|
| `conferir-entrega.py` | a mesma bateria roda contra os dois â€” `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` â€” **23 casos**, e as falhas encenadas (as seis dos relatÃ³rios mais o arquivo que some por `.gitignore`) reprovam nos dois |
| `jornada.py` | os dois medem o mesmo dia e devolvem os mesmos nÃºmeros, lacuna por lacuna |

Apagar o gÃªmeo seria apagar a Ãºnica prova de que o port estÃ¡ certo. O
terceiro gÃªmeo â€” o do `ideias.cjs` â€” foi aposentado em 2026-08-22: a bateria
gÃªmea tinha parado de provar equivalÃªncia (saÃ­a 53 ok / 5 falhas, pulando 5
seÃ§Ãµes inteiras como "recurso novo sÃ³ do .cjs") e virou manutenÃ§Ã£o sem
retorno.

**Nenhuma regra depende de plugin de terceiro.** A regra 8 media a jornada com
um plugin de cliente atÃ© 2026-08-11; hoje mede com `node scripts/jornada.cjs`,
que lÃª o transcript da prÃ³pria sessÃ£o. Quem tiver o plugin pode usÃ¡-lo como
conferÃªncia â€” nunca como requisito.

**E dependÃªncia opcional nÃ£o se anuncia nem se sonda sem alguÃ©m pedir.** Duas
consequÃªncias disso, as duas de 2026-08-12:

- A abertura sÃ³ reporta o que este install **declara**: a bridge do WhatsApp
  aparece quando existe `WHATSAPP_API_BASE_URL` no ambiente, e o claude-mem
  quando estÃ¡ instalado. Antes, toda sessÃ£o de toda mÃ¡quina abria uma conexÃ£o TCP
  para `localhost:3005` e imprimia "bridge WhatsApp FORA" para quem nunca ouviu
  falar dela. Sem nada declarado o bloco inteiro sai da injeÃ§Ã£o (âˆ’169 B).
- **Os vigias nascem desligados** (`vigias`, em `/setup`). As rondas exigem
  PowerShell agendado, `claude.exe` no caminho e um destino de envio; com a chave
  desligada o `run-vigia.ps1` **sai limpo (exit 0)** e nÃ£o escreve em
  `vigias/ERROS.md`, porque desligado nÃ£o Ã© erro. Ele pergunta o estado por
  `node scripts/setup.cjs --ligado vigias` em vez de reimplementar a cadeia de
  trÃªs nÃ­veis em PowerShell â€” segunda cÃ³pia da regra Ã© cÃ³pia que diverge calada.

## Ajuste fino

- As regras vivem em [`skills/rainforest-mind/SKILL.md`](skills/rainforest-mind/SKILL.md) â€” edite e a mudanÃ§a vale na prÃ³xima sessÃ£o.
- **Incidente datado vai em blockquote.** O hook remove as linhas que comeÃ§am
  com `>` antes de injetar: a narrativa continua no arquivo, ao lado da regra
  que fundamenta, e sai do custo de toda sessÃ£o. InstruÃ§Ã£o nunca entra na
  citaÃ§Ã£o â€” se a frase diz o que fazer, fica fora. Rendeu **âˆ’11%** da injeÃ§Ã£o
  sem perder uma linha de conteÃºdo.
- Antes de caÃ§ar token na skill, olhe onde ele estÃ¡ de verdade. Medido com
  `/context all`: as ferramentas de MCP somavam **40,2k tokens** contra ~330 das
  skills deste plugin. Desligar MCP por projeto rendeu **240Ã—** o que traduzir
  as regras inteiras renderia.
- O hook avisa quando a skill passa de **60 dias sem revisÃ£o**.

## OrÃ§amento de token

O rainforest-mind Ã© injetado em toda sessÃ£o, entÃ£o o custo dele Ã© real e precisa de mediÃ§Ã£o contÃ­nua. O `scripts/orcamento.cjs` mede as fontes (hook, skills, commands, agentes) em byte e acusa quando passa do teto de 14.000 B. Ele entra no laÃ§o de testes do `CONTRIBUTING.md:11` pela convenÃ§Ã£o de nome, via `scripts/testa-orcamento.sh` â€” **este repositÃ³rio nÃ£o tem CI**, entÃ£o o gate vale quando alguÃ©m roda o laÃ§o, nÃ£o automaticamente num PR:

```bash
node scripts/orcamento.cjs          # sai 0 se dentro do teto, 1 se estourou
node scripts/orcamento.cjs --teto 1000  # sobrescreve o teto para teste
```

O modo `--repartir` do `scripts/medir-injecao.py` lÃª o transcript e reparte a abertura por fonte, respondendo a pergunta "para onde foi cada token?" em vez de sÃ³ "quanto custa?":

```bash
python scripts/medir-injecao.py --repartir
```

MediÃ§Ã£o da abertura de 2026-08-14T00:36 (transcript `570a6723`): das **67.914 tokens**, **18.980 (28%)** sÃ£o atribuÃ­veis pelo transcript â€” o resto Ã© system prompt do Claude Code, schema das tools, CLAUDE.md e memÃ³rias, que o transcript nÃ£o guarda.

O rainforest-mind por si ocupa **13.205 B, uns 4.246 tokens estimados, ou ~6,3%** da abertura. Pelo outro caminho, o `orcamento.cjs` contando arquivos do repositÃ³rio dÃ¡ **13.744 B**. Os dois **nÃ£o medem a mesma coisa** e nÃ£o deveriam bater exatamente: o lado do repositÃ³rio conta `commands/` como parcela prÃ³pria, e o lado do transcript jÃ¡ os traz dentro da listagem de skills; o lado do transcript mede a linha renderizada na listagem, com prefixo e formataÃ§Ã£o, e o do repositÃ³rio mede sÃ³ o texto da `description`. Ficarem a ~4% um do outro Ã© consistÃªncia entre duas rÃ©guas parecidas â€” **nÃ£o Ã© validaÃ§Ã£o cruzada**, e nÃ£o deve ser lida como tal.

**TrÃªs armadilhas que este nÃºmero jÃ¡ pisou, todas deixadas escritas de propÃ³sito:**

1. **NÃ£o some byte de uma mediÃ§Ã£o com token da outra.** Uma versÃ£o deste parÃ¡grafo dizia "13.604 B ... 1.157 tokens ou 1,7%", casando o total do `orcamento.cjs` com o token de um recorte bem mais estreito do `--repartir` â€” errando o custo em quase 4Ã— para menos. Cada linha da tabela traz byte e token da mesma mediÃ§Ã£o; Ã© assim que se lÃª.
2. **Um transcript pode ter mais de uma abertura.** Todo `--resume` grava outro `SessionStart` no mesmo arquivo. O `--repartir` atribui pelo **primeiro**, que Ã© o mesmo que fixou o total em token â€” antes de isso ser consertado, ele somava as fontes de um evento com o total de outro.
3. **Nem tudo que diz "rainforest-mind" Ã© do rainforest-mind.** O `hook_additional_context` da abertura chega como **lista** de itens de plugins diferentes, e o item do claude-mem comeÃ§a com `# [rainforest-mind] recent context` â€” o nome do projeto no claude-mem, nÃ£o o dono do texto. Ele foi contado como nosso por uma rodada inteira, inflando a fatia em 9.018 B. A separaÃ§Ã£o hoje Ã© por marcador do item, nÃ£o pelo nome que aparece nele.

O byte do hook **oscila entre execuÃ§Ãµes** â€” ele embute estado vivo da sessÃ£o (janelas ativas, horÃ¡rios), entÃ£o mediÃ§Ãµes feitas com minutos de diferenÃ§a dÃ£o 7.6xx variando. As trÃªs outras fontes sÃ£o estÃ¡veis. Por isso o teto Ã© agregado e com folga, e por isso o `testa-orcamento.sh` afirma faixas e "nÃ£o pode ser 0 B", nunca igualdade exata contra o repo real.

**Ressalva sobre token estimado:** a coluna de token no `--repartir` Ã© estimada dividindo byte por fator **3.11**, que foi medido com `tiktoken` no encoding `cl100k_base` â€” **que Ã© da OpenAI (GPT-4)**, nÃ£o do Claude. NÃ£o existe tokenizador do Claude disponÃ­vel offline nesta mÃ¡quina. O total da abertura Ã© token **medido** (vem do `usage` da API), tudo mais Ã© **indicativo**.

## Um foco por projeto, sem configurar nada

Onde moram `FOCO.md` e `ideias.jsonl` sai de uma **cadeia de quatro nÃ­veis**, do
mais especÃ­fico para o mais genÃ©rico â€” o projeto sobrescreve o global, e a
detecÃ§Ã£o automÃ¡tica cobre quem nÃ£o declarou nada:

| # | NÃ­vel | Onde | Para quÃª |
|---|---|---|---|
| 1 | `RFM_ROOT` | onde a variÃ¡vel apontar | declaraÃ§Ã£o explÃ­cita, vence tudo |
| 2 | **projeto** | `<repo>/.rainforest/` | **foco e ideias daquele repo** |
| 3 | global | `~/.rainforest/` | o seu estado, valendo em qualquer pasta |
| 4 | plugin | a raiz do prÃ³prio plugin | instalaÃ§Ã£o auto-hospedada (desenvolvimento) |

O que faz uma pasta contar como raiz Ã© ter `FOCO.md` **ou** `ideias.jsonl`
dentro: um `.rainforest/` vazio criado por engano nÃ£o sequestra o seu foco â€” e
tem teste de mutaÃ§Ã£o provando que Ã© o marcador que decide.

**O nÃ­vel 3 Ã© o seu `HOME`, e nÃ£o a pasta de config do Claude Code.** A
diferenÃ§a parece detalhe e nÃ£o Ã©: dÃ¡ para ter mais de uma config dir na mesma
mÃ¡quina â€” uma de trabalho e uma pessoal, por exemplo â€”, e ancorar o estado nela
partiria o seu foco em dois sem avisar. O foco Ã© da pessoa, nÃ£o do perfil.

A pasta de dados tem um terceiro arquivo: o **`projetos.json`**, o vocabulÃ¡rio
fechado de slugs de projeto (`slug â†’ caminho + apelidos`). Ã‰ ele que tira o
caminho de disco de dentro do dado â€” o campo `projeto` das ideias era texto
livre e guardava caminho do Windows dentro de string JSON, onde a barra
invertida seguida de `r` Ã© escape de *carriage return*: quatro registros
tiveram o caminho comido, e 22 valores distintos para 7 projetos reais
deixaram o campo inagrupÃ¡vel. Slug nÃ£o tem barra para escape nenhum comer, e a
pasta de cada projeto passa a ter um lugar sÃ³ seu.

**O repositÃ³rio Ã© sÃ³ cÃ³digo.** `FOCO.md`, `ideias.jsonl` e `projetos.json` nÃ£o
moram aqui e nÃ£o entram no git: quem instala o plugin recebe as regras, nÃ£o o
foco nem as ideias de quem o publicou. Antes disso ser assim, um projeto novo herdava o estado
alheio pela cadeia â€” o nÃ­vel 4 existe para desenvolvimento e Ã© justamente onde
esse defeito nascia.

Criar `.rainforest/FOCO.md` num repositÃ³rio Ã© tudo o que Ã© preciso para aquele
repositÃ³rio ter foco prÃ³prio. Sem variÃ¡vel de ambiente, sem editar config.

### O FOCO.md tem teto, e quem o segura Ã© um script

A seÃ§Ã£o **AvanÃ§os** Ã© append-only por natureza: cada sessÃ£o que anda escreve
uma linha datada, e nenhuma sai. Em 2026-08-12 o arquivo estava com 15,4 KB, dos
quais 11,8 KB sÃ³ de AvanÃ§os â€” e ele Ã© lido **inteiro** por toda sessÃ£o que
precisa conferir prazo, marco ou avanÃ§o, porque Ã© isso que a prÃ³pria injeÃ§Ã£o
manda fazer. Pior: as trÃªs entradas de um Ãºnico dia produtivo custaram mais que
os cinco dias anteriores somados, entÃ£o teto em *contagem de entradas* nÃ£o
segura nada.

```
node scripts/foco.cjs caminho                 # onde mora o foco desta raiz
node scripts/foco.cjs rotacionar              # ensaio: diz o que sairia
node scripts/foco.cjs rotacionar --aplicar    # move de verdade
```

O que passa do teto (5.000 B por padrÃ£o, em **bytes**) vai para o `AVANCOS.md`
ao lado, em ordem cronolÃ³gica, e o FOCO.md ganha no topo do bloco uma linha
`- (histÃ³rico: N avanÃ§os de â€¦ a â€¦ em AVANCOS.md.)` â€” que o hook trata como
residente, para a injeÃ§Ã£o nunca dizer que as entradas antigas "continuam no
FOCO.md" quando elas jÃ¡ nÃ£o estÃ£o. Nada Ã© apagado: a igualdade entre o que sai
e o que entra Ã© conferida **antes** de qualquer escrita, e sem `--aplicar` o
script nÃ£o toca em disco. O `fechar` e o `/foco` chamam a rotaÃ§Ã£o logo depois de
escrever o avanÃ§o.

- Fork Ã  vontade: troque os arquivos de dado pelos seus e as regras pelo seu
  jeito de trabalhar. Nenhum caminho Ã© cravado no cÃ³digo:

  | VariÃ¡vel | Resolve |
  |---|---|
  | `RFM_ROOT` | raiz dos dados â€” nÃ­vel 1 da cadeia acima |
  | `CLAUDE_CONFIG_DIR` | pasta de config: a checagem de dependÃªncias e o nÃ­vel 3 |
  | `WHATSAPP_API_BASE_URL` | host e porta do bridge, para os vigias e o hook |
  | `RFM_CLAUDE_EXE` | binÃ¡rio do Claude Code usado pelos vigias headless |

## De onde isso veio

**O problema nÃ£o Ã© falta de ideia. Ã‰ o que recebe luz agora.** Essa frase
nasceu de um perfil especÃ­fico â€” **2e**, altas habilidades com TDAH â€” e Ã© ele
que explica por que a ferramenta Ã© assim: pensamento associativo rÃ¡pido abre
ideias como abas que competem com a tarefa aberta, e a resposta foi construir
memÃ³ria de trabalho externa e radar de escopo.

O que a origem explica Ã© o **rigor**, nÃ£o o pÃºblico. Um assistente que sÃ³
funciona quando o usuÃ¡rio lembra de ativÃ¡-lo nÃ£o serve pra quem esquece â€” entÃ£o
nada aqui depende de lembrar. Um aviso que dispara errado ensina a ignorar o
aviso â€” entÃ£o cada gatilho Ã© medido antes de entrar. Uma checagem redigida por
quem ela deveria travar nÃ£o trava nada â€” entÃ£o virou hook com exit code.

Essas trÃªs restriÃ§Ãµes nasceram de uma necessidade pessoal e valem pra qualquer
um. Ã‰ por isso que o repo Ã© pÃºblico.

Desenho orientado por pesquisa sobre dupla excepcionalidade em adultos
profissionais (Barkley, ADDitude, CHADD) e por anÃ¡lise de skills pÃºblicas de
ADHD para assistentes de IA. Lacuna que nenhuma delas cobria: **aviso de desvio
de escopo** e **fechamento de loops abertos**.

## CrÃ©ditos

- *Your Rainforest Mind* â€” Paula Prober, a metÃ¡fora que dÃ¡ nome ao plugin.
- [i-have-adhd](https://github.com/ayghri/i-have-adhd) â€” inspiraÃ§Ã£o de formato e prova de que skill de neurodivergÃªncia funciona.
- Pesquisa 2e: suporte camuflado em conversa casual nÃ£o funciona â€” por isso toda intervenÃ§Ã£o aqui Ã© explÃ­cita e sinalizada.
- [task-observer](https://github.com/rebelytics/one-skill-to-rule-them-all) â€” Eoghan Henn (rebelytics.com), CC BY 4.0: o gatilho "correÃ§Ã£o do usuÃ¡rio = observaÃ§Ã£o" e o ciclo de revisÃ£o que viraram a regra 13. Adotado o mecanismo, nÃ£o o log paralelo.
- [mattpocock/skills](https://github.com/mattpocock/skills) â€” MIT: a Ã¡rvore de decisÃ£o e a fronteira de `grilling` (regra 16 e `/brainstorm`), o loop vermelho-capaz de `diagnosing-bugs` (skill `depurar`), nÃ©voa e fora de escopo de `wayfinder`, expandirâ€“contrair de `to-tickets`, ponto de variaÃ§Ã£o e teste da deleÃ§Ã£o de `codebase-design`, e o portÃ£o triplo do registro de decisÃ£o de `domain-modeling`. Acoplado por compressÃ£o â€” nenhuma das 35 skills instalada.
- [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) â€” a rastreabilidade de cada linha do diff atÃ© o pedido, e o tratamento de cÃ³digo morto alheio vs. Ã³rfÃ£o da prÃ³pria mudanÃ§a, no `modo-dev`.
- [UditAkhourii/adhd](https://github.com/UditAkhourii/adhd) â€” a tese que sustenta o `/divergir`: *tree-of-thought* alarga a busca mas caminha num contexto compartilhado, entÃ£o a ancoragem persiste entre os ramos â€” **problema de arquitetura, nÃ£o de prompt**. Contrato reimplementado a partir da descriÃ§Ã£o, sem copiar cÃ³digo, porque regra deste plugin nÃ£o depende de plugin de terceiro. O frame `premissa`, o cenÃ¡rio concreto exigido na refutaÃ§Ã£o e o teste que falsifica a prÃ³pria skill sÃ£o daqui.

## Mexer no plugin

Bateria verde nas 15 suÃ­tes (mais os dois gÃªmeos em Python), mutaÃ§Ã£o em bateria
nova, e duas regras que este repo aprendeu do jeito caro:

- **campo obrigatÃ³rio novo vem com o passado resolvido no mesmo commit** â€” backfill,
  anistia por data em constante declarada, ou opcional para quem nasceu antes;
- **arquivo novo na pasta de dados nasce com trÃªs portas** â€” quem escreve, quem
  **mostra** no `/setup` e quem checa no `/saude`. A porta do meio Ã© mecÃ¢nica: uma
  lista sÃ³ (`ARQUIVOS`, no `setup.cjs`) Ã© lida por quem semeia e por quem mostra, e
  a bateria compara o disco com a saÃ­da, com mutaÃ§Ã£o.

EstÃ¡ tudo em [`CONTRIBUTING.md`](CONTRIBUTING.md), com o incidente que originou cada
item.

## LicenÃ§a

[MIT](LICENSE) â€” use, modifique e redistribua, inclusive comercialmente,
mantendo o aviso de copyright.

Ã‰ a mesma licenÃ§a de boa parte do que estÃ¡ creditado acima, e a escolha Ã© por
coerÃªncia: este plugin foi montado aproveitando trabalho que outras pessoas
liberaram, e devolvÃª-lo sob condiÃ§Ã£o mais apertada do que a que o tornou
possÃ­vel nÃ£o faria sentido.

O que **nÃ£o** estÃ¡ sob esta licenÃ§a Ã© a sua pasta de dados â€” `FOCO.md`,
`ideias.jsonl` e `projetos.json` moram em `~/.rainforest`, nunca no
repositÃ³rio, e sÃ£o sÃ³ seus.
