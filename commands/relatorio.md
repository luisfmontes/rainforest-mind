---
description: Escreve o relatório de método da sessão em relatorios/, commita e publica
argument-hint: [o achado em uma frase — vazio para você derivar da sessão]
---

Relatório é o registro do que esta sessão ensinou **sobre o método de trabalho** — não
sobre o código. O código já tem commit, PR e teste. O que não tem casa é: o agente
cumpriu o critério e entregou errado; o instrumento de medição estava quebrado; a regra
existia e não alcançou o momento da ação.

Grava em `C:\Projetos\rainforest-mind\relatorios\`, mesmo quando o trabalho aconteceu
noutro repositório — a pasta é o acervo de método do usuário, não do projeto.

## Quando NÃO escrever

Se o achado é "implementei X e funcionou", não é relatório: é mensagem de commit. Relatório
pressupõe que algo no **método** apareceu — uma trava que não travou, um critério
satisfazível por fora, um relato que não bateu com o artefato, um acerto de processo que
vale repetir. Sem isso, diga ao usuário em duas linhas que não houve achado de método e pare.

## Nome do arquivo e numeração

`relatorios/AAAA-MM-DD-<slug-do-achado>.md`. O slug nomeia o **achado**, não o tema:
`protecao-que-nunca-roda`, `baseline-como-armadilha`, `criterio-afrouxado-em-vez-de-cumprido`.
`relatorio-da-sessao` não é slug.

**Não numere o título.** A numeração sequencial morreu em 2026-08-09, quando duas sessões
paralelas gravaram um "Relatório 4" cada uma — e o Relatório 5 ficou citando "o relatório 4"
sem que dê para saber qual. Duas sessões que não se enxergam não conseguem coordenar um
contador. Os relatórios antigos mantêm os números que já têm; **cross-reference novo cita o
slug**, nunca o número. A data no nome do arquivo já ordena.

## Esqueleto

```markdown
# <o achado em uma frase — não o tema>

**Data:** AAAA-MM-DD (manhã/tarde/madrugada)
**Projeto onde ocorreu:** `<repo>` — <a tarefa concreta>
**Relação com os anteriores:** <slug do anterior> tratou de X. Este é sobre Y.

> Se você só for ler um parágrafo: <o achado inteiro, com o número que o sustenta>

## 1..N — as seções do achado
## O que deu certo
## Propostas
## Nota de contexto
```

## As partes obrigatórias, e por que cada uma existe

**O parágrafo `> Se você só for ler um parágrafo`.** O usuário lê de baixo para cima e lê muita
coisa. Se o achado não couber aí, ele não foi entendido ainda — volte e entenda antes de
escrever o resto.

**`## O que deu certo`.** Obrigatória, mesmo quando a sessão foi ruim. O acervo inteiro é de
falha, e isso enviesa a leitura de quem chega depois: sem esta seção, o método parece estar
piorando quando está aprendendo. Registre o gate que barrou, o agente que parou certo, a
verificação que previu o resultado.

**`## Propostas`, numeradas P1..Pn, cada uma com destino executável nomeado.** Esta é a
regra mais importante do comando, e ela veio de um relatório: uma regra escrita em
2026-08-08 foi violada pelo próprio autor 18 horas depois, porque morava só num relatório —
e relatório não é injetado, não é hook, não é `executor.md`. Toda proposta termina dizendo
**onde vira artefato**:

| Destino | Serve para |
|---|---|
| `skills/rainforest-mind/SKILL.md` | regra que precisa valer em toda resposta |
| `agents/executor.md` / `revisor.md` / `tester.md` | passo obrigatório de subagente |
| `hooks/` | trava mecânica — o que dá para fazer o computador cobrar |
| `commands/` | procedimento que o usuário dispara |
| template de briefing | o que muda no despacho |
| `ideias.jsonl` via `/ideia` | proposta boa que não cabe agora |

Proposta sem destino nomeado fica marcada **pendente**, nunca resolvida. Não invente
destino para fechar a lista — pendente é uma resposta honesta.

**Evidência colada, não descrita.** Saída de comando, trecho de diff, número medido: cole.
Descrever permite narrar por cima; colar não. Se você afirma que algo falhou, a linha que
prova está no relatório.

## Commit — não pergunte

**O relatório é commitado e publicado como parte de escrevê-lo.** Não pergunte se pode, não
pergunte se o usuário quer, não deixe untracked esperando resposta. Em 2026-08-09 três
relatórios ficaram parados fora do git porque três sessões pararam para perguntar a mesma
coisa — foi o que originou este comando.

```
git add relatorios/<arquivo>.md
git commit -m "Relatorio: <o achado em uma linha>"
git push
```

A mensagem segue o estilo deste repo — frase em português, sem prefixo de conventional
commit. O `inovacao` usa `feat:`/`fix:` porque tem commitlint; aqui não tem, e o histórico
é prosa (`Planta a proposta da regra 8`, `Arma o gate de staging total`). Escreva o achado,
não a categoria.

Se a sessão estiver noutro repositório, o relatório mesmo assim vai para o
rainforest-mind — `git -C C:\Projetos\rainforest-mind ...`. Commite **só o relatório**:
nada de `git add -A`, que o gate de staging barra e com razão.

Duas exceções, e só estas duas: se o achado citar credencial, dado de cliente ou fonte de
cliente, anonimize antes de gravar; se a árvore do rainforest-mind estiver no meio de outra
coisa não commitada, commite apenas o caminho do relatório e diga isso ao usuário em uma linha.

## Ao terminar

Diga ao usuário, em no máximo cinco linhas: o achado em uma frase, o hash do commit, e as
propostas que ficaram **pendentes por falta de destino**. Não repita o relatório no chat —
ele está no arquivo, e o chat some.
