---
name: setup
description: Carregue na primeira vez que o rainforest roda numa máquina — conduz a entrevista guiada que monta a pasta de dados e decide o que fica ligado — ou quando o usuário quiser mudar uma peça, por projeto ou para tudo. Também quando o `/saude` acusar que a pasta de dados não existe ou é a do plugin.
---

# Setup

Na primeira vez, o setup é uma **entrevista**: uma pergunta por vez, só o que é decisão
de quem instala, com opções tiradas da máquina dele, e **nada gravado até ele ver o
diff**. Depois disso, é o estado mais "mudar uma parte". **Idempotente**: rodar de novo
não recomeça nada.

Quem faz o trabalho é `node scripts/setup.cjs` — ele detecta, valida e grava. Esta skill
só conversa, e **para nos pontos em que a decisão é dele**.

## Primeira vez ou de novo?

```
node scripts/setup.cjs --plano-entrevista
```

Não escreve nada. Devolve um JSON com `primeira_vez`, os `passos` na ordem da entrevista
(cada chave com valor atual, origem, `detectado` e `perguntar`), as `fixas` (o que não
vira pergunta) e as `sugestoes` de projeto.

- **`primeira_vez: true`** — pasta de dados ausente, vazia (sem `FOCO.md`) ou com
  `nivel: plugin`: conduza a entrevista abaixo. Se for `nivel: plugin`, diga com estas
  palavras: o foco e as ideias que aparecem na abertura são **de quem publicou o
  plugin**, não dele — é dado de outra pessoa entrando na sessão.
- **`primeira_vez: false`** — o setup já foi feito. Pergunte com `AskUserQuestion`:
  **"Mudar uma parte"** (recomendada) ou **"Refazer a entrevista"**. Quem já configurou
  não atravessa a entrevista para trocar uma chave.

## Como andar cada passo

- **Uma pergunta por turno**, com `AskUserQuestion`. Opções geradas do que o
  `--plano-entrevista` e a máquina mostram, nunca lista inventada; marque a recomendada.
- **Chave com `perguntar: false` não vira pergunta.** É ferramenta que não está nesta
  máquina (`detectado: false`) ou chave fixa. Ela aparece no resumo final, não na conversa.
- **Já configurado vira "manter / ajustar / refazer".** Se a chave tem `origem` diferente
  de `padrao`, ou o projeto já está registrado, mostre o valor atual e ofereça manter
  (recomendada), ajustar ou refazer. Valor no padrão é pergunta comum.
- **Nada é gravado durante a entrevista.** As respostas se acumulam e só viram arquivo no
  fim, de uma vez — entrevista abandonada no meio não deixa configuração pela metade.
- **Respondeu "pula" ou "depois"**: fica o valor atual, e segue.

## Ordem da entrevista

### dados — pasta de dados

Diga onde a pasta de dados vai morar (`~/.rainforest/` quando não há outra) e o que ela
guarda: o foco, as ideias, os projetos e a configuração dele. Não é pergunta, é aviso: a
pasta nasce no fim, com o resto, pelo próprio `--aplicar`.

### idioma — idioma das respostas

Sugira o idioma em que ele está escrevendo para você agora. Nunca copie texto da
CLAUDE.md nem da memória dele para inferir nada: só a língua da conversa.

### projetos — os repositórios dele

Ofereça as `sugestoes.projetos` (pastas onde ele já trabalhou com o Claude Code, que
existem e são repositório git) como `multiSelect`, com o slug sugerido de cada uma. Ele
marca os que quer registrar e pode corrigir o slug. O slug é o vocabulário do campo
`projeto` das ideias: **um slug por repositório**.

### ferramentas — o que depende de programa instalado

As chaves do grupo `ferramentas` com `perguntar: true`: pontes (Codex, Gemini, Claude sem
o plugin), conselho com Codex ou Gemini, transferência e revisão pelo Codex, integrações
(WhatsApp, Sabiá) e vigias. Agrupe por ferramenta — "você usa o Codex aqui?" cobre
`ponte-codex`, `conselho-codex` e `transfer-codex` — e diga em uma linha o que cada uma
faz ligada. **`gate-review-codex` é pergunta própria**, nunca carona no "uso o Codex":
ligada, ela barra o fim do turno quando o Codex falha (falha fechada), e gate que bloqueia
se liga com a palavra dele sobre o bloqueio, não sobre a ferramenta. Vigias: a geral liga
as rondas; as cinco `vigia-*` vêm ligadas e servem para calar uma ronda só.

### fechar — como o fluxo termina

`fechar-mergear` (o fluxo mergeia o PR depois do CI verde, ou para no PR aberto) e
`executar-autonomo` (do plano aprovado ao merge sem perguntar entre estágios). As duas
vêm desligadas; diga o que muda em cada lado.

### estrategia — as frentes dele (opcional)

"Quer declarar suas frentes agora?" — com opção clara de **pular**. Quem está começando
raramente tem; pergunta obrigatória vira resposta inventada. Com resposta, ela vira o
`ESTRATEGIA.md`, que só nasce se ainda não existir.

### foco — o primeiro foco

Pergunte em que ele está trabalhando agora. **Não grave**: o dono do `FOCO.md` é o
`/foco`. Guarde o texto e, depois do `--aplicar`, rode `/foco <texto>`. Sem foco
declarado o radar de escopo não tem contra o que medir.

## Fechar a entrevista

1. Monte o payload num arquivo temporário (nome único, fora do repositório):
   `{ "chaves": {...}, "projetos": [{ "slug", "caminho" }], "estrategia": "..." }` —
   só o que ele decidiu; campo ausente fica como está.
2. `node scripts/setup.cjs --aplicar <arquivo> --ensaio` e mostre a saída **inteira**:
   cada chave com valor de antes e de depois, cada projeto, o `ESTRATEGIA.md` e o escopo.
   Acrescente a lista das `fixas` — os gates de segurança ficam ligados sem pergunta, e
   ele precisa saber que existem.
3. Confirme com `AskUserQuestion`: **"Gravar"** (recomendada) ou **"Ajustar"** (volta à
   pergunta que ele apontar). Sem a palavra dele, nada é gravado.
4. `node scripts/setup.cjs --aplicar <arquivo>`. Exit 2 é recusa e **nada foi
   gravado**: leia o stderr. Erro de chave, valor ou caminho se corrige no payload — volte
   ao passo 2. Recusa de escopo `usuario` porque a pasta de dados resolvida é a
   `.rainforest/` do **projeto** não se corrige no payload: diga a ele que a configuração
   de usuário iria parar no repositório, e ofereça as duas saídas — gravar no projeto
   (`--escopo projeto`, sabendo que pode ir para o commit) ou apontar `RFM_ROOT` para uma
   pasta de dados própria e refazer o `--ensaio`.
5. **Confira pela saída real**: rode `node scripts/setup.cjs --plano-entrevista` e
   confira, chave a chave, que o `valor` de cada chave do payload é o decidido — é ele que
   traz o valor de chave de texto (`idioma`), que o estado sem argumento não mostra. Linha
   do `--ensaio` com aviso de que o projeto vence o escopo usuário termina com o valor do
   projeto, e isso é o esperado; fora disso, divergência é defeito a reportar, não detalhe.
6. Entregue o foco ao `/foco` e apague o arquivo temporário.

## Mudar uma parte

Comece por `node scripts/setup.cjs`, que não escreve nada: ele diz onde está a pasta de
dados, o que está ligado e **de onde veio cada valor** — projeto, usuário ou padrão. Leia
isso antes de propor mudança: metade das vezes o que ele quer já está do jeito que quer.

```
node scripts/setup.cjs --desligar <chave> [--escopo projeto|usuario]
node scripts/setup.cjs --ligar    <chave> [--escopo projeto|usuario]
node scripts/setup.cjs --projeto <slug> --caminho <dir> [--apelido a,b]
node scripts/setup.cjs --remover-projeto <slug>
```

**O escopo é a parte que exige a palavra dele**: *isto vale só neste repositório, ou em
tudo?* `--escopo projeto` vence o de usuário e grava dentro do repo — pode acabar no
commit de alguém. Diga isso antes de gravar. O padrão é `usuario`; não adivinhe
`projeto` só porque a conversa começou dentro de um repositório. Na primeira vez o
escopo é sempre `usuario`.

## Chaves

A coluna **Grupo** diz em que passo da entrevista a chave vira pergunta; `—` é chave fixa
(fica no padrão, aparece no resumo e muda só por "mudar uma parte"). O
`node scripts/conferir-setup.cjs` confere que o conjunto de chaves desta tabela é o do
catálogo de `hooks/lib/config.cjs` — chave nova sem linha aqui reprova — e que a ordem
dos passos acima é a do catálogo. A coluna **Grupo** e a descrição são escritas à mão:
o grupo que vale é o do campo `entrevista` no catálogo.

| Chave | Grupo | O que ela faz |
|---|---|---|
| `gate-worktree` | — | barra escrita de subagente fora de worktree isolado |
| `gate-staging` | — | barra `git add -A` e `git commit -a` |
| `gate-publicacao` | — | barra escrita de dados sensíveis em arquivo rastreado |
| `gate-repo-alheio` | — | barra escrita cujo destino está dentro de outro repositório git |
| `gate-git-verificacao` | — | barra pulo de verificação no git (`--no-verify`, `-n` em commit, `--no-gpg-sign`) |
| `gate-fechar-issue` | — | barra `gh issue close` direto, palavra-chave falsa e `gh pr`/`gh issue` de escrita sem evidência |
| `gate-merge-auto` | — | barra `gh pr merge --auto`, que sem check obrigatório mergeia sem esperar o CI |
| `gate-agente-em-voo` | — | barra sessão quando há agente em voo que morreu |
| `gate-turno-prometido` | — | barra turno que promete despacho ou espera de máquina sem concretizar |
| `gate-verificador-staged` | — | barra commit quando o `verificador-staged` do config reprova o staged |
| `contrato-veredito` | — | grava o veredito de uma linha do revisor em SubagentStop |
| `agente-folha` | — | a portaria nega Agent vindo de dentro de subagente |
| `busca-na-raiz` | — | nega `find` a partir da raiz do disco dentro de subagente |
| `bateria-sem-timeout` | — | nega bateria sem timeout explícito dentro de subagente |
| `subagente-sem-gh` | — | nega `gh` de escrita dentro de subagente |
| `subagente-sem-instalar` | — | nega instalação de pacotes e desligamento de gate dentro de subagente |
| `matar-por-nome` | — | barra matar processo por nome; mata-se pelo PID |
| `aviso-fluxo` | — | bloqueia edição e despacho que escreve sem fluxo aberto nem `leve`, quando o repo tem fluxo |
| `fluxo` | — | os sete estágios (brainstorm → plano → … → fechar) |
| `vigias` | ferramentas | as rondas headless agendadas (exigem PowerShell, `claude.exe` e destino de envio) |
| `vigia-batedor-repos` | ferramentas | ronda batedor-repos; só roda com `vigias` também ligado |
| `vigia-jardineiro-ideias` | ferramentas | ronda jardineiro-ideias; só roda com `vigias` também ligado |
| `vigia-revisao-bimestral` | ferramentas | ronda revisao-bimestral; só roda com `vigias` também ligado |
| `vigia-sentinela-foco` | ferramentas | ronda sentinela-foco; só roda com `vigias` também ligado |
| `vigia-tickets` | ferramentas | ronda vigia-tickets; só roda com `vigias` também ligado |
| `ponte-claude` | ferramentas | gera CLAUDE.md para Claude Code sem o plugin (regras sem as travas) |
| `ponte-codex` | ferramentas | gera AGENTS.md para o Codex |
| `ponte-gemini` | ferramentas | gera GEMINI.md para o Gemini CLI |
| `branch-forcar` | — | usa `git branch -D` (apaga sem conferir merge) em vez de `-d` |
| `conselho-codex` | ferramentas | Codex participa do conselho como membro externo (exige `codex`) |
| `conselho-gemini` | ferramentas | Gemini participa do conselho como membro externo (exige `GEMINI_API_KEY`) |
| `principal-livre` | — | libera `estado.cjs iniciar` no checkout principal fora da branch padrão |
| `poda` | — | passthrough de proxy medido: escreve `metricas.jsonl` e `contexto.json` |
| `integracao-whatsapp-mcp` | ferramentas | MCP para a bridge WhatsApp local |
| `integracao-sabia` | ferramentas | Sabiá: transcrição local de reunião com diarização |
| `visibilidade-repo` | — | declara o repositório privado quando o `gh` não o enxerga |
| `idioma` | idioma | idioma preferido para respostas na compactação |
| `pastas` | — | pastas de mapas/design/planos quando o repo já usa outras |
| `codex-modelo-haiku` | — | modelo do Codex para agente `haiku` (vazio = `~/.codex/config.toml`) |
| `codex-modelo-sonnet` | — | modelo do Codex para agente `sonnet` (vazio = `~/.codex/config.toml`) |
| `codex-modelo-opus` | — | modelo do Codex para agente `opus` (vazio = `~/.codex/config.toml`) |
| `transfer-codex` | ferramentas | transfere a sessão para uma thread Codex, sob demanda |
| `gate-review-codex` | ferramentas | o revisor em Codex revisa a última resposta no Stop; falha fechada |
| `fechar-mergear` | fechar | o `fechar` mergeia o PR (squash) depois do CI verde; desligada, para no PR aberto |
| `executar-autonomo` | fechar | do plano ok ao merge, decide sem perguntar e registra com `estado.cjs decidir` |

## A portaria de subagente não se liga — ela já está ligada

Não há chave para ela, de propósito. A portaria está registrada no `hooks/hooks.json` do
**plugin**, com matcher `Task|Agent`: decide em toda sessão em que o plugin está
habilitado, em qualquer repositório — é o que a regra 10 promete.

**Não há nada a instalar, e é isso que o usuário precisa ouvir.** O manifesto que ela lê
vem embarcado no plugin, em `.rainforest/agentes.padrao.json`: repo sem manifesto próprio
é o caso **normal**. Um repositório que queira outra lista cria o próprio
`.rainforest/agentes.json`, e ele **substitui o padrão por inteiro** — não soma; um agente
que ele não declarar não volta pelo padrão. É assim que um repo consegue *barrar* um
agente.

O portão exige manifesto **e** estágio ativo. Num repositório sem fluxo aberto não há
estágio, e o caminho é a autorização explícita do usuário na própria sessão — que
dispensa o portão de estágio e **só** ele. Quando um despacho for negado, o stderr diz
qual manifesto foi lido e de qual nível; leia essa linha antes de propor mudança.

## O que este setup NÃO faz

**Não instala manifesto de agentes.** Se a portaria acusar `instalacao incompleta do
rainforest-mind`, é o `.rainforest/agentes.padrao.json` ausente da instalação do plugin:
o conserto é atualizar ou reinstalar o plugin, nunca criar arquivo no repo do usuário.

**Não recomenda automação para o projeto** — hooks, MCP, subagentes, skills novas. Isso
tem dono oficial: a skill `claude-automation-recommender`, do plugin `claude-code-setup`
da Anthropic. Aponte para ela.

**Não conserta instalação**: `claude doctor` faz isso, e `/saude` cobre o que nenhum dos
dois sabe.

**Condição de parada**: nada é gravado sem ele ter visto o diff e dito "gravar". Setup que
escolhe sozinho vira configuração que ninguém lembra de ter feito — e configuração
esquecida é indistinguível de defeito.
