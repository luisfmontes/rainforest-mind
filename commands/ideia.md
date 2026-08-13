---
description: Avalia se a ideia está no escopo e a planta se estiver fora
argument-hint: [ideia em uma frase — vazio para listar plantadas]
---

A fonte da verdade das ideias é o `ideias.jsonl` da **pasta de dados** — não do
repo; descubra onde com `node scripts/ideias.cjs conferir` (ele imprime o
caminho resolvido) e nunca chumbe o caminho. Um objeto JSON por linha, com os
campos: `id` (kebab-case), `titulo`, `descricao`, `contexto` (de onde surgiu e
por quê), `projeto` (**slug do `projetos.json`**, ver abaixo), `gancho`
(obrigatório nas abertas — o gatilho concreto de retorno: que evento, data ou
condição a traz de volta), `ao_colher` (primeiro passo, ou null), `status`
("plantada"/"em-colheita"/"colhida"/"unificada"/"descartada"),
`plantada_em`, e para colhidas `colhida_em` + `resultado`; para descartadas
`descartada_em` + `motivo`. Campo opcional `tipo`: ausente ou
`"ideia"` (padrão) para ideia do usuário; `"observacao"` para as da regra 13 —
geradas por correção dele sobre método, com `ao_colher` = mudança de regra.
`/ideia` sem argumento lista só as ideias; observação é assunto do jardineiro
de sexta.

**`projeto` é slug de vocabulário fechado, não texto livre.** Os slugs vivem no
`projetos.json` da pasta de dados, que é também onde mora o **caminho** de cada
projeto — o dado não guarda caminho. `plantar` recusa slug fora do vocabulário
(e sugere o parecido); se o projeto é novo, registre antes:

```
node scripts/ideias.cjs projetos                                   # o vocabulário
node scripts/ideias.cjs projetos --registrar <slug> --caminho <dir> [--apelido a,b]
```

**Um slug por repositório, não por frente nem por cliente.** O `caminho` é o que
faz o `semear` traduzir pasta em slug, e uma pasta que não é raiz de repo nunca
é a pasta de uma sessão. Frente, cliente ou branch dentro do repo vão no
`projeto_nota` — o campo existe para isso. O primeiro desenho deste vocabulário
errou justamente aqui (criou um slug por cliente, com caminho que não existia no
disco), e é por isso que existe `--remover`.

O campo era texto livre até 2026-08-12 e cobrou os dois preços de sempre:
`C:\Projetos\rainforest-mind` dentro de string JSON virou `C:\Projetos` + CR +
`ainforest-mind` em quatro registros (a barra + `r` é escape de carriage
return), e 22 valores distintos para 7 projetos reais deixaram o campo
inagrupável. Slug não tem barra para escape nenhum comer. Migração de arquivo
antigo: `normalizar-projetos` (ensaio por padrão, `--aplicar` grava).

Se `$ARGUMENTS` estiver vazio: leia o jsonl e liste as **plantadas** em
markdown legível (título, há quantos dias plantada, projeto, contexto em uma
linha), mais novas primeiro; feche com uma linha resumindo as colhidas.

Se `$ARGUMENTS` tiver texto: avalie se a ideia está dentro do foco declarado
(FOCO.md do repo rainforest-mind).

- **Se estiver no escopo:** confirmar e perguntar: "Isso está no foco — entra
  na tarefa atual ou planto para depois?"
- **Se estiver fora:** plantar. Se o `projeto` não estiver óbvio pelo contexto
  da conversa, perguntar em uma linha antes de gravar — e a resposta é um slug
  do vocabulário, nunca um caminho. Confirmar: "plantada, de volta a [tarefa]".

Colher não apaga a linha: reescreve com `resultado`. Colhida ≠ apagada.

**A ideia que não vai acontecer se DESCARTA, e descartar também não apaga.**
`descartar --id <id> --motivo "<texto>"` fecha a linha com status `descartada`,
data e **motivo obrigatório** — e é o único caminho para "tira essa ideia da
lista". Não use `colher` para isso: colher significa **entregue**, e usar para
descarte infla a contagem de colhidas com uma não-entrega. O `motivo` é o que
separa *decidido* de *esquecido*; sem ele a mesma ideia volta idêntica em três
semanas, e o `conferir` derruba descartada sem motivo. O que já fechou
(`colhida`, `unificada`, `descartada`) não se descarta — registro fechado é
história.

**A escrita é do script, nunca sua.** `scripts/ideias.cjs` faz trava entre
sessões paralelas, releitura do arquivo vivo, backup, gravação atômica,
carimbo de data pelo relógio local e conferência byte a byte das linhas que
não eram alvo — e reverte tudo saindo com exit ≠ 0 se qualquer prova falhar.
**Não edite o `ideias.jsonl` à mão nem com script improvisado.** Os quatro
cuidados que moravam aqui em prosa viraram código em 2026-08-08, depois de
dois appends quebrados no mesmo dia, uma data gravada no futuro e um `unificar`
que precisou inventar status no meio do caminho.

```
node scripts/ideias.cjs plantar  < nova.json                    # JSON por stdin
node scripts/ideias.cjs colher   --id <id> < resultado.json     # {"resultado": "..."}
node scripts/ideias.cjs editar   --id <id> < mudancas.json      # só o que ainda está aberto
node scripts/ideias.cjs iniciar  --id <id>                      # plantada → em-colheita
node scripts/ideias.cjs descartar --id <id> --motivo "<texto>"  # não vai acontecer; motivo é obrigatório
node scripts/ideias.cjs unificar --manter <id> --absorver <id> < fundida.json
node scripts/ideias.cjs reparar  [--id <id> | --todas] [--conferir]
node scripts/ideias.cjs listar   [--status plantada] [--tipo ideia|observacao|todos] [--projeto <slug>]
node scripts/ideias.cjs conferir                                # saúde do arquivo + caminho dele
node scripts/ideias.cjs projetos [--registrar <slug> --caminho <dir> --apelido a,b]
node scripts/ideias.cjs projetos --remover <slug>               # recusa se alguma linha usa
node scripts/ideias.cjs normalizar-projetos [--mapear id=slug,...] [--aplicar]
```

Node porque o plugin é instalado por outra gente: os hooks já exigem Node, e o
Claude Code não garante Python (a lista oficial de dependências extras tem
`ripgrep` e mais nada). O `scripts/ideias.py` continua no repo como gêmeo — a
mesma bateria roda contra os dois (`IDEIAS="python scripts/ideias.py" bash
scripts/testa-ideias.sh`), e é assim que se prova que o port não perdeu nada.
Escrita nova vai pelo `.cjs`.

**O `conferir` separa dívida herdada de problema novo, e só falha no segundo.**
`gancho` passou a ser cobrado em 2026-08-11 (`GANCHO_EXIGIDO_DESDE`, no
`ideias.cjs`): linha plantada nesse dia ou antes aparece na saída como **dívida
herdada**, com a contagem, e **não** derruba o exit code. Linha nova sem gancho
derruba — e linha **sem `plantada_em`** também, porque aí não há prova de ser
antiga. A dívida continua impressa em toda execução: anistia que esconde vira
esquecimento. Fechá-la é curadoria de uma linha por vez
(`reparar --id <id> --gancho "<texto>"`), e está plantada como
`mutirao-de-gancho-nas-35-abertas-herdadas`.

Toda contagem diz **de qual conjunto saiu** (`35 de 56 abertas`). Isso não é
enfeite: o mesmo arquivo já mostrou 35 num comando e 72 em outro, sem nenhum dos
dois declarar o universo — e o 72 era o errado, porque cobrava gatilho de retorno
de ideia já colhida.

`reparar` é para a linha que **entrou no arquivo sem passar pelo script** — o
`conferir` acusa "status desconhecido" ou campo de estado vazio, e o `editar`
não resolve porque `status` e `plantada_em` são proibidos na entrada (é essa
proibição que impede o modelo de digitar data). Ele só preenche o que está
**ausente**: valor errado porém existente é assunto do `editar`, que deixa
rastro de decisão. O `status` sai inferido do próprio registro e a
`plantada_em` sai da **data do commit que introduziu a linha** — se o git não
souber, ele recusa em vez de carimbar hoje numa linha que não nasceu hoje, e
aí a data vai à mão em `--plantada-em AAAA-MM-DD`. Rode com `--conferir`
antes: descreve tudo que faria, sem gravar.

**`--todas` não aborta por causa de uma linha.** A varredura conserta o que
consegue inferir, **relata** o que precisa de texto seu (gancho, ou data que o git
não sabe) e sai com **código 1**, porque reparo parcial não é reparo pronto. Com
`--id`, o pedido é sobre aquela linha e a exigência continua: sem `--gancho` ou
`--plantada-em`, ele recusa em vez de inventar. Até 2026-08-12 a varredura
abortava na primeira pendência, e com isso não consertava `status` de nenhuma
linha — o comando estava morto desde que uma única linha irreparável existisse.

Dois cuidados continuam seus, porque o script não alcança:

- **Escreva o JSON com a ferramenta de escrita de arquivo, nunca por heredoc
  do shell** — o shell come as barras do caminho do Windows. Em 2026-08-08
  isso quebrou uma gravação e o script recusou, em vez de gravar corrompido.
  O `projeto` virando slug tirou o pior caso das mãos do aviso (era ele que
  guardava caminho), mas `descricao` e `contexto` ainda são texto livre.
- **Não passe data nenhuma.** `plantada_em`, `colhida_em` e afins vindos da
  entrada são erro, não aviso: quem carimba é o script, do relógio local.

Com `$ARGUMENTS` vazio, `listar` já entrega as plantadas com a idade contada —
formate legível a partir da saída dele, sem recontar nada por conta própria.
