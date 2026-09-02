# O conserto que não alcança o uso que o motivou

**Data:** 2026-09-02
**Onde ocorreu:** `luisfmontes/rainforest-mind` — fluxo 6 (portões), branch `fluxo/portoes`

> Se você só for ler um parágrafo: consertei uma trava que estava inerte havia um
> fluxo inteiro — a `cobertura` nunca disparava porque o gate derivava o caminho
> do design de `<slug>.md` e nenhum design deste repositório se chama assim. O
> conserto foi ler o campo `design.arquivo` que o estado já gravava. Só que o
> gate recebe o estado lido do **disco**, de antes da fusão com o `--json` da
> própria chamada — e como `design` não tem estado intermediário entre `pendente`
> e `aprovado`, **a única forma de anotar esse campo é no mesmo `marcar` que
> fecha o estágio**. O conserto não alcançava o único momento em que o caso que
> ele conserta acontece. A trava continuou inerte, agora com código novo por cima
> e uma bateria verde de 11 asserções que não a exercitava.

## 1 — A cadeia inteira, com as saídas

A `cobertura` cruza design e plano: prova que toda decisão virou tarefa e que
toda tarefa cita decisão que existe. Ela roda no fechamento do `plano`.

```js
// scripts/estado.cjs, antes de 2026-09-02
function docDe(tipo, slug) {
  return path.join(RAIZ, 'docs', 'rainforest', tipo, `${slug}.md`);
}
```

Nenhum design deste repositório se chama `<slug>.md`. Eles se chamam
`fluxo-9-design-portaria.md`, `fluxo-6-design-portoes.md`. E o estado **sabe**
disso — `fluxo-9-portaria.json` grava:

```json
"design": { "status": "aprovado", "arquivo": "docs/rainforest/design/fluxo-9-design-portaria.md" }
```

O campo estava lá. O gate olhava para outro lugar. Resultado: a `cobertura`
passou o fluxo 9 inteiro — 9 tarefas, 6 rodadas de revisão, 10 críticos — sem
rodar uma única vez.

**O conserto (tarefa 6):** `docDoEstagio` lê o campo antes de cair no slug. Testado,
com 11 asserções verdes e catraca de mutação matando. E funcionou de verdade —
a `cobertura` disparou no fechamento do `plano` deste fluxo:

```
ok: cobertura válida — 10 decisão(ões), 6 tarefa(s)
```

**O que o conserto não alcançava**, achado por revisão independente horas depois:

```
$ node scripts/estado.cjs marcar --slug c1 --estagio design --status aprovado \
    --json '{"arquivo":".../malformado.md"}'
design: aprovado
proximo: plano
EXIT=0

$ node scripts/conferir-fluxo.cjs design --slug c1 --design .../malformado.md
RECUSADO: seção obrigatória ausente: ## Objetivo
EXIT=2
```

O arquivo `malformado.md` tem uma linha de texto solto. Fechou como `aprovado`.
A mesma checagem, rodada à mão contra o mesmo arquivo, sai 2.

A causa: `conferirFechamento(estagio, slug, extra, estado)` recebe o `estado`
lido do disco. O `extra` — o `--json` desta chamada — nunca era consultado por
`docDoEstagio`. E `design` só tem `pendente` e `aprovado` (`DECISAO.design`), sem
estado intermediário em que se pudesse pré-gravar o `arquivo`. Logo a única
forma de anotá-lo é na chamada que fecha — exatamente onde o gate era cego.

**Por que a bateria não pegou.** O caso G10, que eu escrevi para provar o
conserto, setava `design.arquivo` numa chamada **separada e anterior** ao
fechamento. Passava. E passava por um motivo real — aquele caminho funciona.
Só que não é o caminho que as pessoas percorrem.

## 2 — O padrão, que não é sobre este defeito

Isto é a terceira ocorrência da mesma forma neste repositório em quinze dias:

| Data | Trava | Como estava inerte |
|---|---|---|
| 2026-09-01 | guarda de "não remover worktree sujo" (Issue #142) | `git -C <dir>` subia para o repositório pai e respondia por ele |
| 2026-09-02 | `cobertura` | o gate derivava o caminho de `<slug>.md`; o estado guardava o real |
| 2026-09-02 | o **conserto** da `cobertura` | não via o `--json` da própria chamada, que é o único lugar onde o campo é declarado |

As três compartilham a assinatura: **o instrumento responde**. Não estoura, não
fica em branco, não avisa. Devolve `exit 0` e segue. E as três foram achadas por
alguém olhando de fora — nunca pela bateria, que em todos os casos estava verde.

A terceira é a mais instrutiva porque **eu já estava alerta para a segunda**.
Escrevi o comentário que explica o defeito, escrevi a bateria, rodei a mutação, e
mesmo assim testei o caminho que funcionava em vez do caminho que era o motivo.

## 3 — A cerca furada dentro da cerca nova

O mesmo dia, a mesma função. A revisão apontou (A3) que `design.arquivo` não era
confinado à árvore do projeto — um rascunho no temp era aceito como design
aprovado. Escrevi a cerca:

```js
const dentro = declarado === path.resolve(RAIZ)
  || declarado.startsWith(path.resolve(RAIZ) + path.sep);
```

Horas depois, a auditoria cross-model:

> `scripts/estado.cjs:693-696`: `design.arquivo` apontando para symlink/junction
> dentro da raiz cujo destino está fora → o teste lexical com
> `path.resolve`/`startsWith` aceita e o checador lê o arquivo externo; faltou
> validar `realpath`.

Correto. `path.resolve` normaliza `..` e separadores; não resolve link. E no
Windows uma junction se cria sem privilégio nenhum. A cerca escrita para fechar
um buraco tinha um buraco da mesma família.

## 4 — Onde os achados vieram de fora da família de modelo

Contagem desta sessão, por origem:

| Origem | Críticos | Avisos |
|---|---|---|
| revisor (mesma família) | 2 | 3 |
| auditoria cross-model (codex) | 2 | 0 |
| dogfooding (submeter o fluxo à própria ferramenta) | 1 | 0 |

Os dois do cross-model foram: (a) as recusas paravam na primeira, então
"checagens independentes em sequência" era promessa não cumprida; (b) a cerca
léxica acima. Nenhum dos dois apareceu nas rodadas da mesma família — repetindo
o que já tinha acontecido no fluxo 9, em que o crítico nº 9 (erro de raciocínio
sobre contrato de plataforma) escapou de seis rodadas e o modelo de fora pegou
de primeira.

**Um "achado" do cross-model era erro meu de enunciado, não defeito.** Eu havia
escrito como critério "nenhuma das três checagens antigas mudou de
comportamento" — quando a tarefa 6 existe justamente para a `cobertura` mudar de
inerte para ativa. O modelo discordou com razão. Registro porque a tentação de
contar isso como "falso positivo do revisor" é real, e seria falsear a conta.

## 5 — E o gate novo, no seu primeiro uso real, aprovou lendo o arquivo

O fluxo 6 instala um gate no `verificar`: com portões declarados, o `ok` só grava
se os oráculos re-executarem e passarem. Ao fechar o `verificar` **deste próprio
fluxo**, o gate rodou e imprimiu:

```
P0: cumprido (pulado; use --reverificar para re-executar)
P1: cumprido (pulado; use --reverificar para re-executar)
...
TODOS OS PORTOES CUMPRIDOS — 6 portão(ões).
verificar: ok
```

Seis "pulado", e um `ok`. O gate aprovou **lendo o arquivo**, porque os portões
já tinham evidência gravada de execuções anteriores — sem `--reverificar`, o
`rodar` pula todo portão cumprido, e essa é a semântica certa para uso manual.
Como gate, é o defeito exato que o fluxo existe para fechar: aceitar evidência
gravada é aceitar evidência colada, só em JSON em vez de prosa. E é a decisão D2
do próprio design ao contrário — "o arquivo não é a verdade; a execução é".

Achado por **usar** a coisa, não por revisar a coisa. Nem o revisor da mesma
família nem a auditoria cross-model pegaram, e nenhum dos dois falhou: os dois
liam o código do gate, e o código do gate estava certo — quem estava errado era
a chamada. Só o fechamento real do estágio expunha isso.

O caso que prova é o único que a re-execução distingue: um portão com evidência
de **sucesso** gravada cujo `CHECK:` hoje **reprova**. Quem lê o arquivo aprova;
quem executa, recusa.

## 6 — Um campo de máquina aceitando texto livre, e o `undefined (undefined)`

Ao reprovar o `verificar` de propósito, passei `reaberto_por` no `--json` como
string. O campo é preenchido pela máquina e tem forma de objeto (`.estagio`,
entre outros). O `marcar` aceitou a string sem checar nada, e o `exigir`
seguinte imprimiu:

```
RECUSADO: 'executar' foi reaberto por reprovação em 'undefined' (undefined). Rode 'executar' antes.
```

Dois defeitos numa linha, os dois em `scripts/estado.cjs`, os dois **anteriores
a este fluxo** e fora do escopo dele:

1. **`marcar` deixa texto livre sobrescrever um campo que a máquina possui.** A
   invariante "o `--json` aceita metadado arbitrário, sem allowlist que rejeite"
   é deliberada e boa — mas `reaberto_por` e `pendentes` não são metadado do
   usuário: são o mecanismo de reabertura. Escrevê-los à mão corrompe a máquina
   de estados em silêncio.
2. **`exigir` recusou e `marcar` deixou passar.** No mesmo estado, o `exigir
   --estagio verificar` saiu RECUSADO e o `marcar --estagio verificar --status
   ok` seguinte fechou. `marcar` confere `estaFechado` do upstream; `reaberto_por`
   só é lido pelo `exigir`. Quem roda direto o `marcar` não é barrado — e o
   contrato desta casa é que a trava vale por exit code, não por disciplina.

## O que deu certo

- **A catraca de mutação pegou uma mutação FALSA minha.** Ao provar a cerca do
  A3, escrevi um caso cujo "fora da árvore" ficava **dentro** da raiz do sandbox
  (`$S` É a raiz naquela bateria). A catraca recusou com `bateria VERDE com o
  comportamento invertido`, e a recusa estava certa: o caso não media nada.
  Sem ela eu teria commitado uma asserção decorativa.
- **Submeter o fluxo à própria ferramenta achou defeito que nenhuma bateria
  acharia.** Rodei o `lint` novo contra os portões deste próprio fluxo e levei
  quatro avisos — o formato canônico de bateria daqui é
  `== resultado: N ok, 0 falha(s) ==`, e meu detector de "termo de erro" disparava
  contra ele. Detector que acusa o padrão correto do repositório não é rigoroso:
  é ruído, e ruído ensina a ignorar o detector.
- **O guarda de snapshot do `revisar` disparou e estava certo.** Consertei os
  achados durante o estágio, o HEAD andou, e ele recusou o fechamento dizendo
  que a revisão fora feita contra outra árvore. Recapturar e refechar custou
  trinta segundos e a recusa era legítima.
- **O gate de staging barrou meu `git add -A`.** Ele teria varrido o
  `vigias/ERROS.md`, que é evidência de outra frente, deixada suja de propósito.

## Propostas

**P1 — Um caso obrigatório por conserto: o caminho que MOTIVOU o conserto.**
Não o caminho que o exercita. A pergunta a fazer ao escrever a bateria é "qual
sequência de comandos a pessoa realmente digita?", e não "qual sequência prova
que meu código roda?". Nos três incidentes da tabela da seção 2 a bateria
exercitava o segundo.
*Destino:* `skills/rainforest-mind/references/regra-12.md` — a régua de entrega,
onde já mora "entrega se valida na saída real".

**P2 — Submeter o artefato à própria ferramenta, quando ela se aplica.** Este
fluxo tem `docs/rainforest/portoes/<slug>.md` com os seus próprios portões,
rodados pelo próprio `portoes.cjs`. Foi o que achou o falso positivo do lint.
Vale como passo do `verificar` quando o trabalho produz uma ferramenta que
poderia se aplicar a ele.
*Destino:* `skills/verificar/SKILL.md`.

**P3 — Confinamento de caminho é por `realpath`, nunca por comparação de
string.** Vale para todo lugar deste repositório que aceite caminho vindo de
arquivo de estado ou de `--json`.
*Destino:* `skills/rainforest-mind/references/regra-15.md` (ambiente do usuário)
+ varredura dos outros scripts que aceitam caminho. **Pendente** — não varri os
outros; só corrigi o que este fluxo introduziu.

**P4 — Dois de dois agentes desta sessão sinalizaram "disponível" sem
entregar.** O `planejador` e o `revisor` emitiram `idle_notification` com
`idleReason: "available"` e nenhum conteúdo; os dois entregaram o trabalho
completo e correto quando pedido de novo por `SendMessage`. Não é perda de
trabalho, é perda de turno — e uma janela que confiasse na notificação concluiria
que o agente não fez nada.
*Destino:* `skills/rainforest-mind/references/regra-10.md`, na parte de "nomeado
só entrega por `SendMessage`" — a nota prática de que a notificação de idle não
é a entrega, e que se pede de volta em vez de re-despachar.

**P5 — Usar o artefato para fechar o próprio estágio, quando ele se aplica.**
Não é o mesmo que P2. P2 é rodar a ferramenta contra o trabalho; isto é
**fechar o estágio pela ferramenta** e olhar a saída do fechamento. Foi o que
achou o gate aprovando por leitura — e nem o revisor da mesma família nem a
auditoria cross-model pegaram, porque os dois liam o código do gate, que estava
certo. Quem estava errada era a chamada.
*Destino:* `skills/verificar/SKILL.md`, junto com P2.

**P6 — Campos que a máquina possui não se aceitam do `--json`.** `reaberto_por`
e `pendentes` são o mecanismo de reabertura, não metadado do usuário. A
invariante de "sem allowlist que rejeite chave nova" continua valendo para
metadado; estes dois são outra categoria. E `exigir` e `marcar` divergem sobre
`reaberto_por`: um recusa, o outro deixa passar no mesmo estado.
*Destino:* `scripts/estado.cjs` + `scripts/testa-estado.sh`. **Fora do escopo do
fluxo 6** — é território do fluxo 1, e entra por Issue.

**P7 — "Campo vazio não é campo ok" e "o instrumento responde" viram uma
entrada só no acervo.** Já são quatro ocorrências datadas (Issue #142, os dois
vigias mortos do handover de hoje, e os dois desta sessão). O acervo tem a
heurística de medição uniforme; falta a irmã: **medição que não estoura não é
medição que funcionou.**
*Destino:* `skills/rainforest-mind/references/regra-12.md`, seção do acervo.
