# Plano: Fluxo 9 — Portaria (`portaria.cjs`)

Design: docs/rainforest/design/fluxo-9-portaria.md

## Achados que mudam o plano (leia antes das tarefas)

Apurados pelo planejador lendo o repositório real antes de desenhar as tarefas — nenhum é nota de rodapé.

**1. `.claude/agents/<nome>.md` (D3, D5, seção "Peças") não existe neste repositório — CONFIRMADO.** `ls agents/` mostra os nove agentes reais em `agents/*.md`, na raiz do repo, não em `.claude/agents/`. Não há pasta `.claude/agents/` nenhuma. O design foi escrito assumindo a convenção genérica de projeto Claude Code; este repositório é o próprio plugin, e os agentes citados como exemplo no manifesto (`revisor`, `sabotador`, `arqueologo-ativo`) também não batem 1:1 com os nomes reais — `sabotador` não existe em lugar nenhum do código (só aparece em designs de fluxos futuros, 10 e 11), e o real se chama `arqueologo`, não `arqueologo-ativo`. As tarefas abaixo corrigem o caminho para `agents/<nome>.md` e usam nomes reais no manifesto de produção; nomes fictícios (`leitor`, `escritor`) só aparecem nas fixtures de teste, para não confundir com os nove agentes de verdade.

**2. Nenhum agente real declara `tools:` no frontmatter — CONFIRMADO (`grep -rln "tools:" agents/` vazio).** Isso importa porque D3 (passo 6) e D5 (checagem 3) exigem negar/errar todo agente com `escreve:false` cujo frontmatter tenha ferramenta fora de `Read/Grep/Glob`. Sem `tools:` declarado, um agente herda acesso irrestrito — logo, **todo** agente real, hoje, falharia essa checagem se fosse declarado `escreve:false`. E `escreve:false` "sempre, por ora" (D2) é a única opção que o esquema aceita. Consequência prática: `executor`, `documentador`, `resolvedor-de-build` e `tester` **escrevem por definição própria** (a description de cada um diz isso). Se esses quatro entrarem no manifesto real, o lint (D5) os reprova; se ficarem de fora, D3 passo 3 ("agente não declarado → nega") **bloqueia toda chamada a `executor`** assim que o hook (D6) for registrado — o agente mais usado do plugin (regra 10) para de rodar no instante em que este design entra em produção, sem que nenhuma das 8 decisões fechadas diga isso em voz alta.

Duas leituras possíveis, e as duas cabem no texto fechado de D1–D8:

- **Opção A (literal, a que D3 diz ao pé da letra):** fail-closed incondicional. `executor`/`documentador`/`resolvedor-de-build`/`tester` ficam bloqueados até uma extensão futura de `escreve:true` com worktree (já prevista em "Fora de escopo", mas sem data). Registrar D6 em `main` **é** desligar o agente mais usado do plugin.
- **Opção B (a leitura que salva o "fica de fora agora" da seção Fora de escopo):** agente capaz de escrever fica **fora do escopo de governança do manifesto**, e o passo 3 de D3 vira "declarado E capaz de escrever, mas fora do manifesto → permite, fora do escopo" em vez de negar. Isto muda o texto literal de D3 ("nega tudo" incondicional) — decisão do usuário, não do plano.

**As tarefas abaixo implementam a Opção A literal** (é a única com base em D3 fechado), e a Tarefa 9 (verificação manual) trava explicitamente na confirmação por escrito do Luís antes de o hook entrar em `main`.

**3. `estado.cjs` não tem noção de "estágio ativo" sem slug — CONFIRMADO.** A API é toda por `slug`, e `docs/rainforest/estado/` pode ter mais de um fluxo aberto ao mesmo tempo no mesmo checkout (tem agora). A Tarefa 1 fecha essa lacuna reaproveitando o mecanismo que já existe em `scripts/saude.cjs:138-162`: casar a branch atual (`git rev-parse --abbrev-ref HEAD`) contra o slug de cada `docs/rainforest/estado/*.json`, removendo o prefixo de data (`^\d{4}-\d{2}-\d{2}-`) — mesma convenção de `skills/rainforest-mind/references/regra-11.md:32`. Decisão técnica, assumida pelo plano.

**4. Localização do `portaria.cjs`.** O rascunho do design (`.rainforest/portaria.cjs`) contraria a convenção real do repositório: os quatro `PreToolUse` existentes moram em `hooks/`. O plano corrige para `hooks/portaria.cjs`.

**5. `.claude/settings.json` versionado (D6) diverge da convenção dos outros 4 gates** (registrados em `hooks/hooks.json` do plugin). Diferença defensável: os quatro gates são redes de segurança universais; a portaria nega despacho de agente e um projeto pode querer isso como opt-in explícito, não herdado por habilitar o plugin. D6 é decisão fechada — seguida; a divergência fica registrada porque o "por quê" nunca foi escrito em D6.

## Premissas aceitas sem conferir plenamente

- Sintaxe de `PreToolUse` com `matcher: "Task"` em `.claude/settings.json` de projeto, expansão de `${CLAUDE_PROJECT_DIR}` no `command`, e exit-code-2-mais-stderr como forma de negar — vêm da doc oficial (`code.claude.com/docs/en/hooks`), não de execução contra o harness real. A Tarefa 9 fecha esta lacuna.
- O nome exato do campo em `tool_input` que identifica o subagente **não foi confirmado** — é o que D7/Tarefa 2 existe para resolver.
- Não confirmado se `${CLAUDE_PLUGIN_ROOT}` é utilizável no `command` de um `.claude/settings.json` de **projeto**. Irrelevante aqui (raiz do projeto = raiz do plugin), mas registrado: distribuir para outros projetos não está coberto por este plano.

## O que não pode quebrar

- Os quatro gates `PreToolUse` existentes (`hooks/gate-worktree.cjs`, `gate-staging-total.cjs`, `gate-publicacao-destino.cjs`, `gate-repo-alheio.cjs`) continuam rodando sem alteração — `portaria.cjs` é hook adicional.
- `scripts/estado.cjs` e `scripts/saude.cjs` continuam como hoje — a portaria só **lê** `docs/rainforest/estado/*.json`.
- `.rainforest/portaria/despachos.jsonl` nunca é reescrito — só append (D4); byte count não decresce entre execuções.
- Payload de stdin ilegível nunca derruba a sessão com exceção não tratada — mesmo princípio do `gate-worktree.cjs`.
- Nenhum agente hoje em uso fica bloqueado silenciosamente: a Opção A só entra em `main` com registro explícito de que o Luís sabe e aceitou (Tarefa 9).

## Tarefas

### 1. Resolver "estágio ativo" sem slug explícito [tipo: implementar]
atende: D3
arquivos: `hooks/lib/estagio-ativo.cjs`, `hooks/testa-estagio-ativo.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/estagio-ativo.cjs`
  de: `candidatos.length !== 1` → devolve `null` (nega quando zero OU mais de um fluxo aberto casa com a branch atual)
  para: `candidatos.length < 1` → devolve `null` (aceita ambiguidade, usa o primeiro candidato)
  bateria: `node hooks/testa-estagio-ativo.cjs`
  fixture: sandbox git real (`fs.mkdtempSync` + `git init` + `git checkout -b x`) com dois arquivos de estado — `docs/rainforest/estado/2026-01-01-x.json` e `docs/rainforest/estado/2026-02-02-x.json` — cujo slug pós-data colide em `x`, ambos com estágio aberto
pronto quando: com o sandbox acima, `resolver({ cwd: sandbox })` devolve `null` (ambíguo) e, num segundo sandbox com um único arquivo de estado cujo slug pós-data casa com a branch e tem `plano.status: "pendente"`, devolve `{ slug, estagio: "plano" }` — provado por `node hooks/testa-estagio-ativo.cjs` devolvendo `todos os casos: OK` e exit 0

### 2. Hook em modo captura + registro (D6) + amostra real (D7) [tipo: configurar]
atende: D6, D7
arquivos: `.claude/settings.json`, `hooks/portaria.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `if (!fs.existsSync(amostraPath))` grava a amostra (primeira captura vence, D7)
  para: grava sempre, mesmo se `amostraPath` já existir (última captura vence)
  bateria: `node hooks/testa-portaria-captura.cjs`
  fixture: duas execuções consecutivas do script com stdin simulado (payloads JSON distintos — mede só a idempotência da gravação)
pronto quando: com uma sessão real do Claude Code despachando um subagente via `Task`, depois de `hooks/portaria.cjs` registrado em `.claude/settings.json` como `PreToolUse`/`matcher: "Task"`, o arquivo `.rainforest/portaria/amostra.json` existe, é JSON válido e tem um campo identificável com o nome do agente despachado — provado por abrir o arquivo e apontar o campo (ex.: `tool_input.subagent_type`). Este passo é o único jeito honesto de responder a Premissa 2 (nome exato do campo)

### 3. `portaria.cjs` núcleo — decisão 1–7 e log append-only [tipo: implementar]
atende: D1, D3, D4, D7
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-nucleo.cjs`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: manifesto ausente ou JSON inválido → decisão `negar` (fail-closed, D3 passo 2)
  para: manifesto ausente ou JSON inválido → decisão `permitir` (fail-open)
  bateria: `node hooks/testa-portaria-nucleo.cjs`
  fixture: sandbox sem `.rainforest/agentes.json`, stdin simulado reproduzindo os campos reais confirmados pela Tarefa 2
pronto quando: com o payload real (campos confirmados por `.rainforest/portaria/amostra.json`) simulado no stdin, agente **não declarado** recebe negação (exit 2, stderr citando o nome — "agente '<nome>' não consta no manifesto"), agente declarado fora do estágio ativo recebe negação citando o estágio atual e os permitidos, e agente declarado no estágio certo recebe aprovação (exit 0) **e** uma linha JSON nova em `.rainforest/portaria/despachos.jsonl` com `ts/agente/estagio/decisao/sessao` — provado por `node hooks/testa-portaria-nucleo.cjs` devolvendo `todos os casos: OK` e exit 0

### 4. `.gitignore` para o log de despacho [tipo: configurar]
atende: D4
arquivos: `.gitignore`, `hooks/testa-portaria-gitignore.cjs`
depende de: 3
paralela: nao
mutacao:
  arquivo: `.gitignore`
  de: adiciona a linha `.rainforest/portaria/despachos.jsonl`
  para: omite essa linha
  bateria: `node hooks/testa-portaria-gitignore.cjs`
  fixture: uma linha real gravada em `.rainforest/portaria/despachos.jsonl` por uma decisão `allow` de verdade (reaproveita a Tarefa 3), gerada e removida dentro do próprio teste
pronto quando: depois de `hooks/portaria.cjs` gravar uma linha real em `.rainforest/portaria/despachos.jsonl` neste repositório, `git status --short` não lista esse caminho — provado por `git check-ignore -q .rainforest/portaria/despachos.jsonl && echo ignorado` devolvendo `ignorado`; e `.rainforest/agentes.json` + `.rainforest/portaria/amostra.json` continuam **fora** do `.gitignore` (documentação versionada por D2/D7) — `git check-ignore -q .rainforest/agentes.json` deve **falhar**

### 5. `portaria.cjs --lint` (D5) e fixtures [tipo: implementar]
atende: D5
arquivos: `hooks/portaria.cjs`, `test/fixtures/portaria/agentes/leitor.md`, `test/fixtures/portaria/agentes/escritor.md`, `test/fixtures/portaria/manifesto-ok.json`, `test/fixtures/portaria/manifesto-agente-sem-arquivo.json`, `test/fixtures/portaria/manifesto-escreve-inconsistente.json`, `test/fixtures/portaria/manifesto-estagio-desconhecido.json`, `test/fixtures/portaria/manifesto-invalido.json`, `hooks/testa-portaria-lint.cjs`
depende de: 3
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `escreve: false` com `tools:` do frontmatter fora de `Read/Grep/Glob` → erro (checagem 3 de D5)
  para: checagem removida — nunca marca erro para esse caso
  bateria: `node hooks/testa-portaria-lint.cjs`
  fixture: `test/fixtures/portaria/manifesto-escreve-inconsistente.json` (declara `escritor`, `escreve: false`) + `test/fixtures/portaria/agentes/escritor.md` (frontmatter com `tools: Read, Write`)
pronto quando: `node hooks/portaria.cjs --lint --manifesto test/fixtures/portaria/manifesto-escreve-inconsistente.json --agentes-dir test/fixtures/portaria/agentes` sai ≠ 0 imprimindo o nome do agente inconsistente (`escritor`); o mesmo comando contra `test/fixtures/portaria/manifesto-ok.json` sai 0; a checagem de "estágio desconhecido" usa a lista real de `scripts/estado.cjs` (`PRE_REQUISITOS` menos `limpar`), não lista copiada — provado por `node hooks/testa-portaria-lint.cjs` devolvendo `todos os casos: OK`

### 6. Testes dos portões P1–P5 (bateria offline) [tipo: teste]
atende: D1, D2, D3, D4, D5
arquivos: `hooks/testa-portaria-portoes.cjs`
depende de: 3, 5
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: gravação da linha de log é `fs.appendFileSync` (nunca trunca o arquivo existente)
  para: gravação sempre reescreve o arquivo inteiro com só a linha nova (perde histórico)
  bateria: `node hooks/testa-portaria-portoes.cjs`
  fixture: sandbox com estágio ativo `revisar` e um agente declarado nesse estágio; duas chamadas consecutivas de `hooks/portaria.cjs` com stdin simulado (payload real confirmado pela Tarefa 2)
pronto quando: rodando duas vezes seguidas contra o mesmo sandbox, `despachos.jsonl` termina com exatamente duas linhas JSON válidas e a contagem de bytes não decresce entre as execuções; removendo `.rainforest/agentes.json` do sandbox, qualquer despacho recai em negação (fail-closed, P5) — provado por `node hooks/testa-portaria-portoes.cjs` devolvendo `P1..P5: OK` e exit 0

### 7. Regra 10 reescrita — núcleo e elaboração [tipo: docs]
atende: D1, D8
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-10.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa de documentação — não há comportamento de código para mutar. O texto de `SKILL.md` e a elaboração em `regra-10.md` passam a afirmar, além do roteamento por função que já descrevem, que a admissão de subagente é por `.rainforest/agentes.json` + estágio ativo, decidida por código (hook `PreToolUse`), e que o humano não é perguntado em runtime — exceção é editar o manifesto
pronto quando: lendo o trecho do núcleo em `SKILL.md` e a elaboração em `regra-10.md`, as três afirmações são verificáveis por leitura semântica (não por grep de string): (1) cita o manifesto por arquivo (`.rainforest/agentes.json`); (2) cita o estágio ativo como condição de admissão; (3) afirma que não há pergunta em runtime e a única exceção é diff no manifesto — provado pelo agente `revisor` respondendo às três perguntas por escrito contra o texto final

### 8. Manifesto real — `.rainforest/agentes.json` [tipo: configurar]
atende: D2
arquivos: `.rainforest/agentes.json`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: tarefa de configuração de dado, não de código — a lógica que consome este arquivo já foi mutada e testada nas Tarefas 3, 5 e 6. O conteúdo é aferido pelo `--lint` já construído
pronto quando: `node hooks/portaria.cjs --lint` sai 0 contra o manifesto real e os arquivos reais em `agents/`. Conteúdo recomendado (decisão do usuário antes de commitar): só os agentes confirmadamente read-only pela própria description — `revisor` (`["revisar"]`), `auditor-de-seguranca` (`["revisar"]`), `planejador` (`["design", "plano"]`). `arqueologo` fica de fora (a description confirma que escreve em `docs/rainforest/mapas/`); `executor`, `documentador`, `resolvedor-de-build`, `tester` e `depurador` ficam de fora — e ficar de fora, sob a Opção A, significa bloqueados assim que o hook for registrado (ver Achado 2 e Tarefa 9)

### 9. Verificação manual única [tipo: teste]
atende: D8
arquivos: `docs/rainforest/estado/fluxo-9-portaria.json`
depende de: 2, 3, 8
paralela: nao
mutacao: n/a
  motivo: verificação manual única, um só episódio de evidência — o mecanismo que ela observa já foi mutado e testado nas Tarefas 1, 2, 3, 5 e 6. Confirma comportamento do harness real, que nenhuma bateria offline reproduz
pronto quando: numa sessão real do Claude Code, com `hooks/portaria.cjs` registrado em `.claude/settings.json` e o manifesto da Tarefa 8 no lugar, despachar `rainforest-mind:revisor` (declarado, estágio `revisar`) não produz nenhum prompt de autorização ao humano — e despachar `rainforest-mind:executor` (não declarado, Opção A) é negado com exit 2 e o motivo aparece para a sessão, sem crash. **Pré-condição desta tarefa: confirmação por escrito do Luís de que aceita o bloqueio de `executor`/`documentador`/`resolvedor-de-build`/`tester` até a extensão futura de `escreve:true`** — sem ela, o hook não entra em `main`, só em branch/worktree isolado. Evidência: trecho do transcript da sessão (ou do `despachos.jsonl` gerado) colado no registro de fechamento do fluxo
