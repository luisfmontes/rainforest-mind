---
name: setup
description: Carregue na primeira vez que o rainforest roda numa máquina, ou quando o usuário quiser ligar/desligar uma peça — os dois gates de git ou o fluxo, por projeto ou para tudo. Também quando o `/saude` acusar que a pasta de dados não existe ou é a do plugin.
---

# Setup

Monta a pasta de dados e decide o que fica ligado. **Idempotente**: rodar de novo
não recomeça nada — mostra o estado e é por ele que se liga ou desliga peça.

Quem faz o trabalho é `node scripts/setup.cjs`. Esta skill conduz a conversa e
**para nos pontos em que a decisão é dele**.

## Sempre comece pelo estado

```
node scripts/setup.cjs
```

Ele não escreve nada. Diz onde está a pasta de dados, por qual nível da cadeia
ela foi resolvida, o que está ligado, e **de onde veio cada valor** — projeto,
usuário ou padrão. Leia isso em voz alta para o usuário antes de propor qualquer
mudança: metade das vezes o que ele quer já está do jeito que ele quer.

## Se não houver pasta de dados

É o caso de quem acabou de instalar, e é o mais importante de acertar.

```
node scripts/setup.cjs --criar
```

Cria `~/.rainforest/` com um `FOCO.md` modelo e um `ideias.jsonl` vazio. **Nunca
sobrescreve** o que já existe.

Se o estado disser `nivel: plugin`, é pior que não ter: a pasta encontrada é a do
**plugin**, e o foco e as ideias que aparecem na abertura são de quem o publicou.
Diga isso ao usuário com essas palavras — não é detalhe de configuração, é dado de
outra pessoa entrando na sessão dele.

Depois de criar, o passo seguinte é dele: `/foco <texto>` para declarar o
primeiro foco. Sem foco declarado o radar de escopo não tem contra o que medir.

## Ligar e desligar

```
node scripts/setup.cjs --desligar <chave> [--escopo projeto|usuario]
node scripts/setup.cjs --ligar    <chave> [--escopo projeto|usuario]
```

| Chave | O que ela faz quando ligada |
|---|---|
| `gate-worktree` | barra escrita de subagente fora de worktree isolado |
| `gate-staging` | barra `git add -A` e `git commit -a` |
| `fluxo` | os sete estágios, de `brainstorm` a `fechar` |
| `conselho-codex` | Codex participa do conselho como membro externo (exige `codex` CLI) |
| `conselho-gemini` | Gemini participa do conselho como membro externo (exige `GEMINI_API_KEY` no ambiente) |

**O escopo é a parte que exige a palavra dele**, e a pergunta é sempre a mesma:
*isto vale só neste repositório, ou em tudo?* `--escopo projeto` vence o de
usuário e grava dentro do repo — o que significa que pode acabar no commit de
alguém. Diga isso antes de gravar, e deixe a decisão de versionar com ele.

O padrão é `usuario` quando ele não disser. Não adivinhe `projeto` só porque a
conversa começou dentro de um repositório.

## O que este setup NÃO faz

Ele não recomenda o que criar de automação no projeto — hooks, MCP, subagentes,
skills novas. Isso tem dono oficial e é bom: a skill `claude-automation-recommender`,
do plugin `claude-code-setup` da Anthropic. Aponte para ela em vez de opinar.

E ele não conserta instalação: `claude doctor` faz isso, e `/saude` cobre o que
nenhum dos dois sabe.

**Condição de parada**: nada é gravado sem ele ter visto o estado antes e dito o
que quer. Setup que escolhe sozinho vira configuração que ninguém lembra de ter
feito — e configuração esquecida é indistinguível de defeito.
