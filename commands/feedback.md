---
description: Registra o que a sessão ensinou sobre o MÉTODO — Issue no repo do plugin se o defeito é do plugin, markdown no seu repo se é do seu trabalho
argument-hint: [o achado em uma frase — vazio para você derivar da sessão]
---

Relatório é o registro do que esta sessão ensinou **sobre o método de trabalho** —
não sobre o código. O código já tem commit, PR e teste. O que não tem casa é: o
agente cumpriu o critério e entregou errado; o instrumento de medição estava
quebrado; a regra existia e não alcançou o momento da ação.

## 1. Primeiro: de quem é o defeito?

Esta pergunta decide tudo o que vem depois, e ela **não** é sobre formato — é
sobre quem pode consertar.

| O achado é sobre | Vai para | Por quê |
|---|---|---|
| **o plugin** — regra que não disparou, gate que barrou errado, skill que fez besteira, script que mentiu | **Issue** em `luisfmontes/rainforest-mind` | é o único canal que chega em quem mantém o plugin |
| **o seu trabalho** — bug do seu projeto, agente que errou numa task daquele repo, processo da sua equipe | **markdown** em `<seu-repo>/relatorios/` | é assunto do seu projeto, e o acervo é seu |

**Por que o Issue existe.** Enquanto o `/feedback` só gravava markdown, o
relatório nascia no repositório de quem estava trabalhando — privado, na máquina
dessa pessoa. Um defeito do plugin encontrado por outro dev morria ali, e quem
mantém o plugin nunca ficava sabendo. Defeito que ninguém reporta é
indistinguível de plugin que funciona.

É o mesmo desenho da skill `feedback` de um plugin interno de cliente, e pelo
mesmo motivo: ela não grava arquivo local nenhum, manda para a base remota,
porque aprendizado que fica na máquina de quem aprendeu não serve para o
próximo.

**Na dúvida, pergunte em uma linha.** "Isso é defeito do plugin ou do seu
projeto?" custa uma pergunta; adivinhar errado manda o incidente para o lugar
onde ninguém vai lê-lo.

## 2. Quando NÃO escrever

Se o achado é "implementei X e funcionou", não é relatório: é mensagem de commit.
Relatório pressupõe que algo no **método** apareceu — uma trava que não travou,
um critério satisfazível por fora, um relato que não bateu com o artefato, um
acerto de processo que vale repetir. Sem isso, diga em duas linhas que não houve
achado de método e pare.

## 3. O corpo, que é o mesmo nos dois caminhos

```markdown
# <o achado em uma frase — não o tema>

**Data:** AAAA-MM-DD
**Onde ocorreu:** <repo/contexto> — <a tarefa concreta>

> Se você só for ler um parágrafo: <o achado inteiro, com o número que o sustenta>

## 1..N — as seções do achado
## O que deu certo
## Propostas
```

**O parágrafo `> Se você só for ler um parágrafo`.** Se o achado não couber aí,
ele não foi entendido ainda — volte e entenda antes de escrever o resto.

**`## O que deu certo`.** Obrigatória, mesmo quando a sessão foi ruim. Um acervo
só de falha enviesa quem chega depois: sem esta seção, o método parece estar
piorando quando está aprendendo.

**`## Propostas`, numeradas P1..Pn, cada uma com destino nomeado.** Esta é a
regra mais importante do comando, e veio de um relatório: uma regra escrita foi
violada pelo próprio autor 18 horas depois, porque morava só num relatório — e
relatório não é injetado, não é hook, não é `executor.md`. Toda proposta termina
dizendo **onde vira artefato**: skill, agente, hook, comando, ou `ideias.jsonl`
via `/ideia` quando é boa e não cabe agora. Proposta sem destino fica marcada
**pendente**, nunca resolvida — pendente é resposta honesta.

**Evidência colada, não descrita.** Saída de comando, trecho de diff, número
medido: cole. Descrever permite narrar por cima; colar não.

## 4. A conferência, que não é opcional

**Antes de publicar qualquer coisa, rode:**

```
node scripts/conferir-publicacao.cjs <arquivo>
```

O caminho acima vale com a sessão no próprio repo do plugin. Do lado do seu
trabalho ela quase nunca está, e aí o script se acha no plugin instalado —
`ls -d ~/.claude*/plugins/cache/rainforest-mind/rainforest-mind/*/`, versão mais
alta. Não achando nenhum dos dois, **não publique em silêncio**: leia o rascunho
à mão e diga em uma linha que o gate não rodou.

Ele **sai com código 2** e recusa quando acha telefone, JID de WhatsApp, e-mail,
caminho de pasta pessoal ou credencial. Isto não é zelo: até 2026-08-10 este
comando dizia por escrito "anonimize dado de cliente antes de gravar", e um
relatório foi gravado assim mesmo com o telefone e o nome completo de um
terceiro, mais o caminho e o parâmetro do sistema do cliente. Ficou no
repositório por um dia. Regra escrita não alcança quem a leu e errou mesmo
assim — código com exit code alcança.

**O que ele não vê, e continua com você:** nome de pessoa. Não há padrão para
isso, e foi exatamente o que passou. Leia o rascunho procurando nome de gente,
de cliente e de sistema interno antes de mandar.

Com Issue isso pesa mais do que pesava: markdown num repo privado dava para
corrigir antes de alguém ver; Issue é público no instante em que é criado, e
fica no índice de busca mesmo depois de editado.

## 5. Se é do plugin: abrir o Issue

**Primeiro, procure duplicata.** Reportar de novo o que já está aberto custa
triagem alheia:

```
gh issue list --repo luisfmontes/rainforest-mind --state all --search "<termos do achado>"
```

Se existir, comente no Issue existente com a evidência nova em vez de abrir
outro. Se o novo achado **corrige ou supera** um anterior, diga isso na primeira
linha: `CORRIGE #<n>: ...`.

**Depois, mostre o rascunho e espere.** Nunca publique sem confirmação — Issue
não tem "desfazer" que apague o que já foi indexado.

**Então publique**, na ordem de preferência:

```
gh issue create --repo luisfmontes/rainforest-mind --title "<achado>" --body-file <arquivo>
```

Se o `gh` não estiver instalado ou autenticado, **não instale nada** (regra 15):
monte a URL com o corpo já preenchido e entregue o link para a pessoa clicar —
funciona sem credencial nenhuma e mantém a confirmação humana:

```
https://github.com/luisfmontes/rainforest-mind/issues/new?title=<urlencode>&body=<urlencode>
```

Se o corpo for grande demais para a URL, entregue o link com o título e peça
para colar o corpo — degradar assim é melhor que pedir para a pessoa instalar
uma ferramenta.

## 6. Se é do seu trabalho: gravar e commitar

`<seu-repo>/relatorios/AAAA-MM-DD-<slug-do-achado>.md`. O slug nomeia o
**achado**, não o tema: `protecao-que-nunca-roda`, `baseline-como-armadilha`.
`relatorio-da-sessao` não é slug. **Não numere o título** — duas sessões
paralelas já gravaram um "Relatório 4" cada uma, e a data no nome já ordena.

**Commite como parte de escrever**, sem perguntar: três relatórios já ficaram
fora do git porque três sessões pararam para perguntar a mesma coisa.

```
git add relatorios/<arquivo>.md
git commit -m "Relatorio: <o achado em uma linha>"
git push
```

Commite **só o relatório** — nada de `git add -A`, que o gate de staging barra e
com razão.

## Ao terminar

No máximo cinco linhas: o achado em uma frase, para onde foi (número do Issue ou
hash do commit), e as propostas que ficaram **pendentes por falta de destino**.
Não repita o relatório no chat — ele está no arquivo ou no Issue, e o chat some.
