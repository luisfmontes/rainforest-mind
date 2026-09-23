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

## A portaria de subagente não se liga — ela já está ligada

Não há chave para ela na tabela acima, e isso é de propósito. A portaria está
registrada no `hooks/hooks.json` do **plugin**, com matcher `Task|Agent`: ela
decide em toda sessão em que o plugin está habilitado, em qualquer repositório
— é o que a regra 10 promete.

**Não há nada a instalar, e é isso que o usuário precisa ouvir.** O manifesto que
ela lê vem embarcado no plugin, em `.rainforest/agentes.padrao.json`: repo sem
manifesto próprio é o caso **normal**, não o caso negado.

Um repositório que queira outra lista cria o próprio `.rainforest/agentes.json`,
e ele **substitui o padrão por inteiro** — não soma. Diga "substitui", não
"sobrescreve as chaves": o que está escrito no arquivo é o que vale, e um agente
que ele não declarar não volta pelo padrão. É assim que um repo consegue
*barrar* um agente; com soma, não conseguiria.

O que o portão exige para admitir um despacho continua sendo manifesto **e**
estágio ativo. Num repositório sem fluxo aberto não há estágio, e o caminho de lá
é a autorização explícita do usuário na própria sessão — que dispensa o portão de
estágio e **só** ele.

Quando um despacho for negado, o stderr diz qual dos dois manifestos foi lido e
de qual nível ele veio. Leia essa linha antes de propor mudança: metade das
negações é o padrão embarcado decidindo num repo que ninguém configurou.

## O que este setup NÃO faz

**Ele não instala manifesto de agentes.** O padrão vem embarcado no plugin (ver a
seção acima). Se a portaria acusar `instalacao incompleta do rainforest-mind`,
isso **não** é configuração faltando neste repositório: é o
`.rainforest/agentes.padrao.json` ausente da instalação do plugin, e o conserto é
atualizar ou reinstalar o plugin — nunca criar arquivo no repo do usuário para
calar a mensagem.

Ele não recomenda o que criar de automação no projeto — hooks, MCP, subagentes,
skills novas. Isso tem dono oficial e é bom: a skill `claude-automation-recommender`,
do plugin `claude-code-setup` da Anthropic. Aponte para ela em vez de opinar.

E ele não conserta instalação: `claude doctor` faz isso, e `/saude` cobre o que
nenhum dos dois sabe.

**Condição de parada**: nada é gravado sem ele ter visto o estado antes e dito o
que quer. Setup que escolhe sozinho vira configuração que ninguém lembra de ter
feito — e configuração esquecida é indistinguível de defeito.
