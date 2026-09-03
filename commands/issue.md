---
description: Abre uma Issue no repositório em que você está trabalhando, com o corpo já escrito e a evidência colada
argument-hint: [o erro em uma frase — vazio para você derivar da sessão]
---

Uma Issue é para **defeito, erro ou comportamento errado** que precisa de evidência
e de alguém para consertar. Não é ideia de melhoria — isso vai para `/ideia`.
Não é achado sobre o **método de trabalho** — isso vai para `/feedback`.

## 1. O repositório sai de comando, nunca de memória

O repositório é derivado, não digitado:

```
gh repo view --json nameWithOwner,hasIssuesEnabled
```

Chumbar o nome ou digitar é como se manda Issue para o lugar errado. Se o repo
tem Issues desligadas, a degradação cai na seção final.

## 2. Triagem: defeito, não ideia

| O achado é | Vai para |
|---|---|
| Bug, erro ou comportamento errado **no código/produto** | **`/issue`** (aqui) |
| Ideia de melhoria ou feature | **`/ideia`** (planta com gancho de retorno) |
| Achado sobre o **método de trabalho** | **`/feedback`** (Issue ou markdown privado) |

Na dúvida, pergunte em uma linha.

## 3. Não é duplicata?

```
gh issue list --search "<termos>" --state all
```

Se existir, comente nela com a evidência nova em vez de abrir outra.

## 4. Conferência de dado sensível

**Antes de publicar**, rode o gate. Ele **sai com código 2** e recusa quando acha
telefone, JID de WhatsApp, e-mail, caminho de pasta pessoal ou credencial. É o
mesmo gate do `/feedback`, e vale aqui pelo mesmo motivo, com um agravante: o
repositório costuma ser de cliente, e Issue é pública no instante em que nasce —
fica no índice de busca mesmo depois de editada. Não há "corrigir antes".

**O script mora no plugin, e a sessão quase nunca está no repo dele.** É por isso
que o caminho não é fixo: resolva nesta ordem, e pare na primeira que existir.

```
# 1. sessão no próprio repo do plugin
node scripts/conferir-publicacao.cjs <arquivo>

# 2. plugin instalado — pegue a versão mais alta, não a primeira da lista
ls -d ~/.claude*/plugins/cache/rainforest-mind/rainforest-mind/*/
node <caminho-da-maior-versao>/scripts/conferir-publicacao.cjs <arquivo>
```

**Não achou nenhuma das duas: não publique em silêncio.** Leia o rascunho à mão
procurando as cinco formas acima, e **diga em uma linha que o gate não rodou** —
regra bloqueada pelo ambiente se anuncia, porque o silêncio faz a pessoa
acreditar que ele rodou.

**O que ele não vê:** nome de pessoa, cliente e sistema interno. Leia o rascunho
procurando isso antes de mandar.

## 5. O corpo da Issue

O **título é o erro em uma frase, não o tema.** `ADVPL: erro ao gravar` é tema;
`Grava contrato com filial vazia quando o usuário troca de filial no meio` é erro.
O título é o que decide se alguém abre a Issue.

```markdown
**Data:** AAAA-MM-DD
**Onde:** <arquivo:linha> ou <tela/rotina>

> Se você só for ler um parágrafo: <o defeito inteiro, com a prova em uma frase>

## Como reproduzir

1. Passo primeiro
2. Passo segundo

## O que acontece

<descrição do comportamento errado>

## O que se esperava

<descrição do comportamento correto>

## Evidência

<saída de comando, log ou diff — colado, não descrito>

## Critério de pronto (falsificável)

Comando e saída esperada que **prova** que o defeito foi consertado — não adjetivo como "funciona" ou "sem erro".

## Correção sugerida

(Opcional — marcada como sugestão, porque quem mantém o repo pode conhecer restrição que você não conhece.)
```

**Evidência colada, não descrita.** Descrever permite narrar por cima; colar não.

## 6. Mostre o rascunho e espere

Nunca publique sem confirmação — Issue não tem "desfazer" que apague o que já
foi indexado.

## 7. Publique

```
gh issue create --repo <owner/repo> --title "<erro>" --body-file <arquivo>
```

## 8. Degradação — sem instalar nada

Se `hasIssuesEnabled` for false ou repo não tem remote GitHub:

```
git add relatorios/<arquivo>.md
git commit -m "Issue: <o erro em uma linha>"
git push
```

Grave em `<seu-repo>/relatorios/AAAA-MM-DD-<slug-do-erro>.md` (mesmo lugar do
`/feedback` privado) e avise que o tracker não existe.

Se `gh` estiver ausente ou não autenticado, **não instale nada** (regra do
plugin): monte a URL

```
https://github.com/<owner>/<repo>/issues/new?title=<urlencode>&body=<urlencode>
```

e entregue o link para a pessoa clicar. Corpo muito grande para URL? Entregue o
link com o título e peça para colar o corpo — degradação assim é melhor que
pedir para instalar.

## Ao terminar

No máximo cinco linhas: o erro em uma frase e para onde foi (número da Issue ou
hash do commit). Não repita o corpo no chat.
