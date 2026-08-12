# everything-claude-code — leitura de referência

Repositório analisado: `affaan-m/everything-claude-code` (clonado de
`worldflowai/everything-claude-code`), 81 arquivos, 784 KB, último commit
2026-01-23. Autor: Affaan Mustafa, vencedor de hackathon da Anthropic.

Análise feita em 2026-08-11 sobre o clone real, não sobre o README. Toda
afirmação aqui foi conferida no arquivo citado.

---

## Por que este documento existe

O usuario levantou o repo como expressão do que ele imagina para o
rainforest-mind: **"instalar uma coisa e ela cuidar das sessões e
configurações, independente do projeto"**. A pergunta que este documento
responde não é "o repo é bom?", é **"ele entrega esse mundo perfeito, e o que
dele o rainforest deveria pegar?"**.

Resposta curta: **não entrega** — e o pedaço que o rainforest já tem
funcionando é justamente o que lá está pela metade. O que ele tem de melhor
é outra coisa: **amplitude de catálogo** e **três mecanismos pequenos** que o
rainforest não tem.

---

## 1. O que o repositório é, de fato

| Pasta | Conteúdo | Tamanho |
|---|---|---|
| `agents/` | 9 agentes | 87,8 KB |
| `commands/` | 15 comandos | 40,1 KB |
| `skills/` | 11 skills | 95,9 KB |
| `rules/` | 8 arquivos de diretriz | 9,7 KB |
| `contexts/` | 3 modos de trabalho | 1,6 KB |
| `hooks/` + `scripts/` | 1 `hooks.json` + 5 scripts Node | ~30 KB |
| `mcp-configs/` | catálogo de 15 servidores MCP | 4 KB |

É um **catálogo**, não um sistema. As peças não se chamam entre si: nenhum
hook lê `rules/`, nenhum script lê `contexts/`, e o `hooks.json` não sabe da
existência das skills.

## 2. O que o manifesto do plugin realmente instala

`.claude-plugin/plugin.json` tem 27 linhas e **duas** chaves de componente:

```json
  "commands": "./commands",
  "skills": "./skills"
```

Não existe chave `agents`, `hooks`, `rules`, `contexts` nem `mcpServers`. O
README promete em `README.md:207` *"instant access to all commands, agents,
skills, and hooks"* — é prosa, não mecanismo.

O que sobra exige cópia manual, documentada em prosa:

| Item | O que o repo manda fazer |
|---|---|
| `rules/` (8 arquivos, 9,7 KB) | `cp rules/*.md ~/.claude/rules/` (`README.md:223`) |
| `hooks/hooks.json` | *"Copy the hooks to your `~/.claude/settings.json`"* (`README.md:234`) |
| MCPs (15 servidores, 4 placeholders de chave) | editar `~/.claude.json` (`mcp-servers.json:87`) |
| `statusLine` | editar `~/.claude/settings.json` (`examples/statusline.json:17`) |
| Dois CLAUDE.md (~4,9 KB) | colar à mão, **um deles por repositório** |
| `contexts/` | **nenhuma rota de instalação em lugar nenhum** |

E a instrução de copiar o `hooks.json` para o `settings.json`
**quebra os hooks**: cinco deles usam `${CLAUDE_PLUGIN_ROOT}`
(`hooks/hooks.json:50,62,74,140,150`), variável que só é preenchida quando o
arquivo é carregado como plugin. Copiada à mão, ela fica vazia e o comando
vira `node "/scripts/hooks/session-start.js"`.

O próprio autor **não usa o caminho de plugin**: `WORLDFLOWAI.md:160-167`
mostra symlink de quatro pastas + cópia de hooks + `chmod +x`.

> **Contra o critério do usuario:** instalando só o plugin, chega algo entre 40%
> (o que o manifesto declara) e 65% (se `agents/` e `hooks/` forem
> descobertos por convenção). O resto é cópia manual, e um dos arquivos
> precisa ser colado **em cada repositório**.

## 3. "Memória compartilhada": o que existe de verdade

Esta é a parte que mais impressiona no README e a que menos existe no código.

**SessionStart não injeta nada — nem o caminho.**
`scripts/hooks/session-start.js:30-36` procura `*.tmp` dos últimos 7 dias e
imprime:

```js
log(`[SessionStart] Found ${recentSessions.length} recent session(s)`);
log(`[SessionStart] Latest: ${latest.path}`);
```

O conteúdo do `.tmp` nunca é lido — só o caminho é anunciado. E `log()` é
**stderr** (`scripts/lib/utils.js:182-184`: `console.error(message)`). O mesmo
`utils.js` define, logo abaixo, a função que iria para stdout, comentada como
*"Output to stdout (returned to Claude)"* — e **nenhum hook a chama**. Grep em
`scripts/hooks/`: zero `console.log`, zero `output(`, zero
`additionalContext`, zero `hookSpecificOutput`.

Ou seja: o volume que chega ao modelo na abertura é **zero em todos os
caminhos**. `WORLDFLOWAI.md:122` promete *"previous context loads
automatically"*; o mecanismo não tem por onde entregar.

**SessionEnd grava um template vazio.** `scripts/hooks/session-end.js:46-70`
escreve, quando o arquivo do dia ainda não existe:

```markdown
## Current State

[Session context goes here]

### Completed
- [ ]
```

Se o arquivo já existe, só troca a linha `**Last Updated:**`. O conteúdo rico
dos exemplos em `examples/sessions/*.tmp` (causa raiz, achados, próximos
passos) **não é produzido por script nenhum** — é digitação humana.

**O aprendizado contínuo nem chega a rodar.**
`scripts/hooks/evaluate-session.js:52-57` busca o transcript assim:

```js
const transcriptPath = process.env.CLAUDE_TRANSCRIPT_PATH;
if (!transcriptPath || !fs.existsSync(transcriptPath)) {
  process.exit(0);
}
```

O caminho do transcript chega ao hook pelo **JSON no stdin** (campo
`transcript_path`), não por variável de ambiente. O próprio `utils.js` tem
`readStdinJson()` (`:154-177`), exportado — e `evaluate-session.js` não a
importa. Resultado: **o hook sai no primeiro `if`, sempre.**

E a suíte não pega, porque o teste injeta a variável à mão
(`tests/hooks/hooks.test.js:210`):

```js
const result = await runScript(path.join(scriptsDir, 'evaluate-session.js'), '', {
  CLAUDE_TRANSCRIPT_PATH: transcriptPath
});
```

**O teste valida o script contra um contrato que o runtime não cumpre** — é a
forma mais cara de suíte verde que existe: prova que a função funciona quando
alguém entrega o que a produção nunca entrega.

Mesmo que rodasse, não extrairia nada: ele conta mensagens por regex
(`/"type":"user"/g`), e as 8 chaves de `config.json` que descrevem um
classificador (`patterns_to_detect`, `ignore_patterns`, `auto_approve`,
`extraction_threshold`) **não têm leitor** — só `min_session_length` e
`learned_skills_path` são consumidas. E está pendurado no **SessionEnd**
(`hooks/hooks.json:145-154`), quando o modelo já saiu, apesar de o cabeçalho
do arquivo dizer *"Runs on Stop hook"*. `~/.claude/skills/learned/` é criado e
permanece vazio, a menos que o usuário rode `/learn` à mão.

**Não há escopo por projeto.** `scripts/lib/utils.js:33-35`:

```js
function getSessionsDir() {
  return path.join(getClaudeDir(), 'sessions');
}
```

Todas as sessões de todos os repositórios caem em `~/.claude/sessions/`, num
arquivo por dia (`session-end.js:27`), sem distinguir projeto nem assunto.
Três projetos abertos na mesma segunda-feira escrevem no mesmo
`2026-08-11-session.tmp`, e o ramo de atualização (`session-end.js:35-39`)
preserva o corpo deixado pelo outro projeto — cruzamento silencioso de
memória entre repositórios.

Pior para esta máquina em particular: `getClaudeDir()` (`utils.js:26-28`)
**hardcoda `.claude`**. Não há env var, parâmetro nem fallback. Numa máquina
com dois config dirs — `~/.claude` (trabalho) e `~/.claude-personal`
(pessoal), que é exatamente o caso do usuario — o ECC escreve sempre no
primeiro, independentemente de qual conta abriu a sessão.

E o `PreCompact` escolhe "a sessão ativa" pelo mtime global, sem `maxAge`
(`pre-compact.js:33-38` sobre `findFiles` ordenado por mtime desc): o marcador
de compactação vai para o `.tmp` mais recentemente tocado **na máquina**, que
pode ser de outra data ou de outro projeto.

## 4. As travas não travam

Dois hooks de `PreToolUse` anunciam bloqueio — servidor de dev fora do tmux
(`hooks.json:10`) e criação de `.md` avulso (`hooks.json:40`). Os dois
terminam em `process.exit(1)`.

No Claude Code, **exit 2** é o código que bloqueia a chamada; qualquer outro
não-zero vira erro não-bloqueante. Contagem no arquivo: `process.exit(1)`
aparece 2 vezes, `process.exit(2)` **zero**.

Os gates do rainforest usam `process.exit(2)` — `gate-worktree.cjs:106` e
`gate-staging-total.cjs:183`. Aqui o rainforest está certo e o ECC está
errado, e é o tipo de erro que ninguém percebe porque a mensagem "BLOCKED"
aparece na tela do mesmo jeito.

## 5. Orquestração sem verificação

`/orchestrate` é encadeamento em prosa com quatro cadeias fixas
(`commands/orchestrate.md:11-33`). O laço é:

```
1. Invoke agent with context from previous agent
2. Collect output as structured handoff document
3. Pass to next agent in chain
```

**O handoff é o que o agente diz que fez**, incluindo a seção
`### Files Modified` autodeclarada (`:57-58`). A única menção a verificar está
numa lista de dicas opcionais (`:173`: *"Run verification between agents if
needed"*).

É exatamente o modo de falha que gerou a regra 12 do rainforest. Reforço
disso: a cadeia `bugfix` chama o agente `explorer` (`:20`), e
**`agents/explorer.md` não existe** — um dos quatro workflows nomeados está
quebrado e ninguém notou.

## 6. Economia de modelo: nenhuma

Os 9 agentes declaram `model: opus`. O resolvedor de erro de build roda no
mesmo modelo do arquiteto. Não há um único agente em sonnet ou haiku.

O rainforest já faz o inverso (regra 10: `executor` haiku, `revisor` e
`tester` sonnet, janela principal pensa).

## 7. Peso morto

Dos 95,9 KB de skills, **49,1 KB (51%) são específicos de stack alheia** —
`backend-patterns`, `frontend-patterns`, `clickhouse-io` e
`project-guidelines-example`. Só 12 KB (12,5%) são os quatro mecanismos
genéricos (`continuous-learning`, `strategic-compact`, `verification-loop`,
`eval-harness`).

Nos agentes, os quatro maiores somam 68% do texto, e o que os engorda é
exemplo de **outro produto**: `agents/e2e-runner.md:598` fixa
`BASE_URL: https://staging.pmx.trade` dentro de um template de CI, e
`commands/e2e.md:284-296` traz uma seção "PMX-Specific Critical Flows" com
"User can withdraw funds" dentro de um comando genérico.

Correlação limpa e invertida: **os arquivos curtos carregam mecanismo, os
longos carregam vocabulário.** Os melhores achados do repo estão em arquivos
de 17, 28, 29 e 59 linhas; os piores em arquivos de 211, 452 e 545.

E 3 das 11 skills — `verification-loop`, `eval-harness` e
`project-guidelines-example` — **não têm frontmatter algum**. Como o
`description` é o gatilho de ativação, elas são empacotadas pelo manifesto,
instaladas no diretório do usuário e **nunca ativam sozinhas**. Nenhum teste
cobre isso: um lint de uma linha ("todo SKILL.md tem `name` e `description`")
teria pego as três.

## 8. A suíte de testes também mente

Vale registrar porque é o modo de falha que o rainforest mais persegue.

`tests/run-all.js:52-63` captura a exceção de um arquivo de teste que estoure
e extrai os totais por **regex sobre a saída**. Se o arquivo morrer antes de
imprimir o sumário, nada casa, `totalFailed` continua 0, e `run-all.js:76`
sai com código 0. Arquivo ausente é só um `⚠ Skipping` (`:31-34`).

E os testes escrevem no HOME real: `hooks.test.js:112-122` roda
`session-end.js` e afirma que `~/.claude/sessions/<data>-session.tmp` existe,
sem sandbox e sem limpeza. Rodar a suíte suja o config dir de quem rodou.

Somado ao `evaluate-session.js` da §3 — teste que injeta o contrato que a
produção não entrega — o padrão é: **a suíte verde do ECC não é evidência de
que os hooks funcionam.** É exatamente a regra 12 vista de fora.

---

## O que vale trazer para o rainforest-mind

### 1. Hook de `PreCompact` — o buraco real

O rainforest cobre `SessionStart`, `PreToolUse`, `UserPromptSubmit`, `Stop` e
`SessionEnd`. **Não cobre `PreCompact`.** É o único evento em que dá para
salvar estado antes da compactação levar o contexto embora — e é o momento em
que o usuario mais perde fio, porque a compactação não avisa.

O `pre-compact.js` do ECC não serve de modelo — ele só registra timestamp e
anexa uma linha ao `.tmp` (o errado, às vezes, ver §3), e o próprio cabeçalho
promete *"preserve important state that might get lost in summarization"* sem
ter acesso ao conteúdo da conversa: não lê stdin, não lê transcript, não
tenta. **O que vale é o gancho, não a implementação.** No rainforest ele teria
conteúdo de verdade: gravar foco ativo, decisões abertas e loops pendentes
antes do resumo levar tudo.

### 2. Contador de chamadas com limiar

`suggest-compact.js` mantém um contador por sessão em arquivo temporário e
avisa aos 50 e depois a cada 25:

```js
const threshold = parseInt(process.env.COMPACT_THRESHOLD || '50', 10);
if (count === threshold) { log('[StrategicCompact] ... consider /compact'); }
```

É barato e é o único jeito de um hook saber "estou fundo na sessão" sem ler
o transcript. Serve ao rainforest para mais que compactação: é o sinal que
falta para a regra 8 (guarda-corpo de jornada) quando o `jornada_cli.py` não
está disponível — que é exatamente o fallback anunciado na abertura desta
sessão.

### 3. Cadeia de resolução de configuração em camadas

`scripts/lib/package-manager.js:146-235` resolve o gerenciador de pacotes em 6
níveis, do mais específico ao mais genérico:

```
env → .claude/ do projeto → campo do package.json → lock file → ~/.claude/ → primeiro instalado
```

**Esta é a resposta técnica ao "independente do projeto".** Não é instalar
tudo global; é ter uma cadeia declarada em que o projeto pode sobrescrever o
global, e a detecção automática cobre quem não declarou nada. O rainforest
hoje resolve caminho por `RFM_ROOT` e pronto — um nível só. Um `FOCO.md` por
projeto que caia para o global quando não existir seria a mesma ideia.

### 4. A ideia de `contexts/` (que lá não existe)

Três arquivos de ~500 B que declaram modo de trabalho — comportamento,
prioridades, ferramentas a favorecer. `contexts/dev.md` inteiro cabe em 20
linhas. Não há mecanismo nenhum que os carregue (a string `contexts/` aparece
**uma vez** no repo inteiro, numa árvore de diretórios do README), mas a
ideia é boa e barata: **modo é mais leve que skill**.

---

## O que não trazer

| Peça | Por quê |
|---|---|
| Todos os agentes em opus | O rainforest já faz tiering por papel (regra 10) e mede o ganho |
| Agentes de 500 linhas com exemplo de projeto alheio | Ocupa contexto sem restringir comportamento — é o que a regra 9 chamaria de polimento que não entrega |
| `/orchestrate` como está | Aceita o relato do agente como verdade; a regra 12 existe porque isso falha |
| `exit(1)` em hook que quer bloquear | Não bloqueia. Manter `exit(2)` |
| Skills específicas de stack | 51% do peso das skills, zero uso fora do projeto do autor |
| `pass@3` sobre autoavaliação (`commands/eval.md:29-32`) | Vocabulário de eval sem o harness que o sustenta — o modelo julga a si mesmo e escreve o resultado |

---

## Onde o rainforest já está à frente

Vale registrar, porque a comparação com um repo premiado tende a puxar para o
lado errado:

| Eixo | ECC | rainforest-mind |
|---|---|---|
| Injeção de contexto na abertura | **zero** — tudo sai por stderr; `output()` existe e nunca é chamada | injeta conteúdo real, com orçamento medido de 8 KB e corte anunciado |
| Estado entre sessões | template vazio, 1 arquivo por dia, global | `FOCO.md` + `ideias.jsonl` + radar multi-janela, com porta de escrita única e conferência byte a byte |
| Travas | `exit(1)` — não bloqueia | `exit(2)`, com 66 casos de teste rodando o hook de verdade |
| Verificação de entrega de agente | inexistente | regra 12 + `conferir-entrega.py`, com o hash re-derivado do git |
| Economia de modelo | opus em tudo | haiku/sonnet por papel, com limiar de despacho medido |
| Escopo por projeto | nenhum | foco declarado, com natureza `[trabalho]`/`[pessoal]` |

O que o ECC tem e o rainforest não tem é **amplitude de catálogo** — 15
comandos e 11 skills cobrindo TDD, e2e, review, segurança, docs — e a
disposição de publicar isso como produto de uso alheio.

---

## A lição que atravessa o repo inteiro

O ECC é um repositório de **prompts bem escritos** vendido como um sistema. O
README descreve um sistema; o código entrega um catálogo com três scripts
pequenos. A distância entre os dois não é má-fé — é o que acontece quando o
que se mede é o tamanho do acervo, não o que roda.

O risco simétrico para o rainforest é o oposto: mecanismo demais, catálogo de
menos. Ele tem trava que trava, injeção que cabe no orçamento e verificação
que pega mentira de agente — e 17 regras que crescem mais rápido que o canal
que as entrega. Se o alvo agora é outros devs usarem, o que falta não é mais
mecanismo: é **caber numa instalação e sobreviver a um repositório que não é
o do usuario**.
