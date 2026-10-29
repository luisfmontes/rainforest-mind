# Plano: Colheita das observações: classes recorrentes viram trava mecânica

Design: docs/rainforest/design/2026-10-28-colheita-observacoes.md

## O que não pode quebrar
- O despacho de agente **declarado** na portaria se comporta como hoje: os casos existentes de `hooks/testa-portaria-fluxo-pulado.cjs` continuam verdes sem edição.
- Agente não declarado **sem** `isolation: "worktree"` e com `escreve` inferido `false` (Explore, Plan, general-purpose de leitura) continua liberado em repositório com trilho e sem fluxo.
- Repositório sem trilho de fluxo (`docs/rainforest/estado/` ausente e sem `docs/plans/*.gates.json`) não é barrado por nenhuma das três travas.
- As categorias (a) despacho prometido e (b) espera prometida do `gate-turno-prometido` não mudam: os casos existentes continuam verdes sem edição.
- Hook de Stop nunca derruba a sessão: payload ilegível, transcrito ausente, memória ausente, banco fechado ou estouro de prazo saem com exit 0.
- Barrar é **uma vez**: com `stop_hook_active: true`, os gates de Stop saem com exit 0.

## Tarefas

### 1. Portaria barra agente não declarado que escreve sem fluxo [tipo: implementar]
atende: D3, D8
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: nenhuma
busca:
- repo | rg "escreveDeclarado|inferirConfigNaoDeclarado" hooks | `portaria.cjs:986` barra só o declarado; `inferirConfigNaoDeclarado` (`:488`) já infere `escreve` pelo frontmatter
- livro | pulado: mudança interna de uma trava já existente
desfecho: estender
prova-na-base: verde — a bateria existente passa na base; os casos do não declarado nascem com esta tarefa
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const escrevePorSinal = !escreveDeclarado && ((!declarado && agentConfig.escreve === true) || payload.tool_input.isolation === "worktree");`
  para: `const escrevePorSinal = false;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: `testa-portaria-fluxo-pulado.cjs, casos "N1" a "N3" (não declarado com isolation worktree, sem fluxo, em repo com trilho rainforest e com trilho protheus)`
pronto quando: com o payload real do PreToolUse de `Agent` (`subagent_type: "general-purpose"`, `isolation: "worktree"`, `cwd` num repositório com `docs/rainforest/estado/` e branch `fluxo/x` sem estado aberto), a portaria sai com exit 2 e o stderr nomeia o agente e as duas saídas (abrir o fluxo, `leve`). Casos que **barram** (contornos): N1 `general-purpose` com `isolation: "worktree"`; N2 agente não declarado cujo frontmatter tem `Edit` (fixture de agente com `tools: Read, Edit`), sem `isolation`; N3 o N1 em repo de trilho protheus (`docs/plans/x.gates.json`) sem plano aberto. Casos vizinhos que **passam** (exit 0): N4 `Explore` sem `isolation`; N5 N1 com `leve` declarado na branch; N6 N1 com estágio `executar` aberto na branch da sessão; N7 N1 em repositório sem trilho; N8 N1 com a chave `aviso-fluxo` desligada no `.rainforest/config.json` do repositório. Parada declarada (D8): agente sem `isolation` e com frontmatter ilegível segue liberado. Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` imprimindo `falhou: 0` e uma linha `ok` para cada um de N1 a N8, e pela mutação acima deixando N1 vermelho.

Nota da tarefa 1 — emenda (2026-10-28, rodada 2): a tarefa 7 renomeou e ampliou a linha original (`escreveNaoDeclarado`); a mutação passa a desligar a condição inteira.

### 2. gate-turno-prometido pega o pedido de licença com autonomia ligada [tipo: implementar]
atende: D4, D5, D8
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`, `hooks/fixtures/turno-prometido/pede-licenca-com-autonomia.jsonl`, `hooks/fixtures/turno-prometido/pede-licenca-com-q.jsonl`
depende de: nenhuma
busca:
- repo | rg "RE_PROMETE_DESPACHO|stop_hook_active" hooks | o gate já lê o último texto do transcrito e tem o anti-loop; a categoria nova entra ao lado das duas regex
- livro | pulado: extensão de gate próprio
desfecho: estender
prova-na-base: verde — a bateria existente passa na base; os casos da categoria (c) nascem com esta tarefa
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: `const RE_PEDE_LICENCA = /(?:\b(?:sigo|posso seguir|posso continuar|continuo)\b[^.!?\n]{0,80}\?|\bquer que eu (?:siga|continue)\b[^.!?\n]{0,80}\??)\s*$/i;`
  para: `const RE_PEDE_LICENCA = /(?!)/;`
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: `testa-gate-turno-prometido.cjs, caso "C1" (fixture pede-licenca-com-autonomia.jsonl, repo com fluxo no estágio plano e executar-autonomo ligada)`
pronto quando: com um transcrito no formato real do Claude Code (linhas `{"type":"assistant","message":{"content":[{"type":"text","text":...}]}}`) cujo último texto termina em "Plano escrito. Sigo com o executar?", `cwd` num repositório cuja branch tem fluxo com design aprovado e `fechar` aberto, e `.rainforest/config.json` com `"executar-autonomo": true`, o gate sai com exit 2 e o stderr diz que a autonomia está ligada e manda seguir ou subir uma `Q<n>`. Contornos que **barram**: C1 "Sigo com o executar?"; C2 "posso seguir?" no fim; C3 "Quer que eu siga" sem ponto de interrogação. Vizinhos que **passam** (exit 0): C4 o mesmo texto com uma linha `**Q1 — ...**` antes (fixture `pede-licenca-com-q.jsonl`); C5 o C1 com `executar-autonomo` desligada; C6 o C1 com o fluxo só no estágio `design` (design ainda não aprovado); C7 o C1 com `stop_hook_active: true`; C8 o C1 com "sigo?" no meio do texto e outra frase depois; C9 o C1 em repositório sem fluxo. Os casos existentes das categorias (a) e (b) seguem verdes. Provado por `node hooks/testa-gate-turno-prometido.cjs` com `falhou: 0` e uma linha `ok` de C1 a C9, e pela mutação acima deixando C1 vermelho.

### 3. gate-pergunta-memoria: Q<n> conferida contra a memória antes de subir [tipo: implementar]
atende: D6, D8
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`, `hooks/fixtures/pergunta-memoria/memoria-responde.jsonl`, `hooks/fixtures/pergunta-memoria/memoria-nao-responde.jsonl`, `hooks/fixtures/pergunta-memoria/memory/gate-off-so-por-variavel.md`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `scripts/testa-conferir-categoria.sh`, `hooks/testa-titulo-sessao-registro.sh`, `skills/setup/SKILL.md`
emenda (2026-10-28, integração): `testa-titulo-sessao-registro.sh` fixa a contagem de comandos de Stop (5 → 6 com o gate novo) e `testa-conferir-setup.sh` cobra toda chave do catálogo na tabela de `skills/setup/SKILL.md`; as duas ficaram vermelhas na integração da tarefa 3 e só fecham tocando esses arquivos.
depende de: nenhuma
busca:
- repo | rg "buscarPorAssunto|transcript_path|sessoes.json" hooks | `memoria-assunto-prompt.cjs` busca no banco por assunto e o `gate-turno-prometido` lê o último texto; nada confere Q<n>
- memoria | pulado: o mecanismo é o próprio objeto da tarefa
desfecho: compor
prova-na-base: verde — entregue na rodada 1; o arquivo não existia na base d3d57de8, em que a prova saiu ≠ 0 (arquivo ausente)
mutacao:
  arquivo: `hooks/gate-pergunta-memoria.cjs`
  de: `const LIMIAR_TERMOS = 3;`
  para: `const LIMIAR_TERMOS = 999;`
  bateria: `node hooks/testa-gate-pergunta-memoria.cjs`
  fixture: `testa-gate-pergunta-memoria.cjs, caso "P1" (fixture memoria-responde.jsonl contra memory/gate-off-so-por-variavel.md)`
pronto quando: com o payload real do Stop (`session_id`, `transcript_path`, `cwd`, `hook_event_name: "Stop"`, `stop_hook_active: false`) cujo `transcript_path` aponta um transcrito no formato real, com último texto "❓ **Q1 — Desligar o gate**: crio o arquivo .rainforest-gate-off na raiz para desligar o gate de publicação neste repositório cliente?", e uma pasta `memory/` ao lado do transcrito com `gate-off-so-por-variavel.md` (descrição "desligar gate é RAINFOREST_GATE_OFF/config; arquivo .rainforest-gate-off não, por causa de repo de cliente"), o hook sai com exit 2 e o stderr traz `Q1`, o nome `gate-off-so-por-variavel.md` e o trecho da descrição. A forma: termos do texto da `Q` com 5 letras ou mais, minúsculos e sem acento, menos uma lista curta de palavras vazias; acerto quando um arquivo de memória compartilha pelo menos `LIMIAR_TERMOS` termos distintos com a `Q`. O banco do `memoria.cjs` entra pela `buscarPorAssunto` com prazo interno de 1500 ms, e qualquer erro dele é ignorado. Nenhum caso de teste afirma sobre o texto do fonte. Contornos que **barram**: P1 o caso acima; P2 a mesma `Q` escrita `**Q2 -**` (hífen em vez de travessão). Vizinhos que **passam** (exit 0): P3 `Q1` sobre assunto sem memória (fixture `memoria-nao-responde.jsonl`); P4 o texto do P1 sem marcador `Q<n>`; P5 o P1 com `stop_hook_active: true`; P6 o P1 com `agent_id`; P7 o P1 sem pasta `memory/`; P8 o P1 com a chave `gate-pergunta-memoria` desligada; P9 `transcript_path` inexistente. Quando barra, o stderr lista também as sessões vivas de outros repositórios lidas do `sessoes.json` da raiz de dados (a bateria aponta `RFM_ROOT` para um mkdtemp com um `sessoes.json` de duas entradas e confere que a de outro repositório aparece). O hook entra no `hooks.json` em `Stop`, com `timeout` de 10, e tem cabeçalho `// @categoria: sensor`. Provado por `node hooks/testa-gate-pergunta-memoria.cjs` com `falhou: 0` e uma linha `ok` de P1 a P9, pela mutação acima deixando P1 vermelho, e por `bash scripts/testa-conferir-categoria.sh` com 0 falha(s).

### 4. Rascunho da Issue de compilação para o plugin de domínio [tipo: docs]
atende: D2
arquivos: `docs/rainforest/planos/2026-10-28-colheita-observacoes.md`
depende de: nenhuma
mutacao: n/a
  motivo: rascunho de texto guardado fora do repositório; não há comportamento a inverter
pronto quando: com as observações reais da classe Protheus no `ideias.jsonl` (compilar sem avisar ou perguntar, e tela quando o harness REST resolve), existe um rascunho em `~/.rainforest/rascunhos/2026-10-28-issue-compilar-e-harness.md` que cita cada id de observação usado, e o título e o corpo propõem as duas peças do D2 (confirmação antes de `advpls cli` e regra de quando usar o harness REST) — provado por `node -e` que lê o rascunho, extrai os ids citados e confere que cada um existe no `ideias.jsonl`, imprimindo `N ids, N existem` com N ≥ 6, e por `git status --porcelain` do worktree sem nenhum arquivo novo da tarefa.

### 5. Triagem e colheita das observações plantadas [tipo: pesquisar]
atende: D7
arquivos: `docs/rainforest/planos/2026-10-28-colheita-observacoes.md`
depende de: 1, 2, 3
mutacao: n/a
  motivo: a tarefa grava dados do usuário pelo `ideias.cjs colher`, sem código a inverter
pronto quando: com o `ideias.jsonl` real, `node scripts/ideias.cjs listar --tipo observacao` passa a abrir com `0 plantada (observacao)`, e as observações que estavam plantadas no início da tarefa (lista de ids gravada antes, no scratchpad) estão todas `colhidas`, cada uma com `resultado` em uma de três formas: aponta `D3`, `D4` ou `D6` deste design; aponta um arquivo de memória de projeto que existe no disco; ou diz "registrada; reabre se repetir". Provado por `node -e` que cruza a lista inicial com o jsonl e imprime `colhidas: N/N, D: a, memoria: b (todos existem), avulsas: c` com `a + b + c = N`, e pela conferência, na janela principal, de cada citação do relatório do agente de triagem contra o jsonl antes de gravar.

### 6. Documentação, versão e notas [tipo: docs]
atende: D1, D2, D3, D4, D6, D8
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `docs/travas-mecanicas.md`
emenda (2026-10-28, integração): `docs/travas-mecanicas.md` descreve a portaria e o `gate-turno-prometido` com o mesmo texto do README e ficaria desatualizado.
depende de: 1, 2, 3
mutacao: n/a
  motivo: texto e versão; a falsificação é a coerência com o design e com a interface real
pronto quando: com os hooks entregues pelas tarefas 1 a 3, o README descreve as três travas com o mesmo comportamento que as baterias provam: quem barra, quando, a chave que desliga e o que fica fora (D8). A versão sobe para a próxima minor acima da que estiver na `main` no momento da tarefa, nos dois `plugin.json` e no selo do README, e o CHANGELOG ganha a seção dessa versão. Provado por `node -e` que confere que as duas versões dos `plugin.json`, a do selo do README e o primeiro `## ` do CHANGELOG são iguais, e pela leitura, no revisar, de cada frase do README contra o caso de bateria que a sustenta (N1–N8, C1–C9, P1–P9).

## Rodada 2 (revisão 1 reprovada, 2026-10-28)

### 7. Portaria: isolation worktree é sinal de escrita para qualquer agente [tipo: implementar]
atende: D3, D8
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 1
busca:
- repo | rg "escreveNaoDeclarado|parseToolsDoFrontmatter" hooks | a linha da tarefa 1 e a inferência de frontmatter, as duas na portaria
- livro | pulado: emenda de trava própria
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; os casos G nascem com a tarefa
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const escrevePorSinal = !escreveDeclarado && ((!declarado && agentConfig.escreve === true) || payload.tool_input.isolation === "worktree");`
  para: `const escrevePorSinal = !escreveDeclarado && (!declarado && agentConfig.escreve === true);`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: `testa-portaria-fluxo-pulado.cjs, caso "G1" (general-purpose declarado escreve:false com isolation worktree, sem fluxo)`
pronto quando: com o payload real do PreToolUse de `Agent` com `subagent_type: "general-purpose"` e `isolation: "worktree"`, em repo com trilho e branch sem estágio aberto nem `leve`, a portaria sai com exit 2 (G1); o mesmo para `Explore` com `isolation` (G2). Agente não declarado cujo frontmatter existe sem linha `tools:` é tratado como escritor (G3, exit 2 sem fluxo). Vizinhos que **passam**: G4 `general-purpose` **sem** `isolation` e sem fluxo (busca de leitura); G5 `general-purpose` com `isolation` e estágio `executar` aberto; G6 `rainforest-mind:revisor` sem `isolation` e sem fluxo. Os casos A3 e A4 passam a despachar sem `isolation`, que é como o revisor e o planejador são despachados de verdade (skills `revisar` e `plano`); nenhum outro caso antigo muda. Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` com `falhou: 0` e linhas `ok` de G1 a G6, por todas as `hooks/testa-portaria-*.cjs` com `falhou: 0`, e pela mutação acima deixando G1 vermelho.

### 8. gate-pergunta-memoria lê a memória do repositório principal e casa só por nome e descrição [tipo: implementar]
atende: D6, D8
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`, `hooks/fixtures/pergunta-memoria/memory/gate-off-so-por-variavel.md`, `hooks/fixtures/pergunta-memoria/memory/corpo-sem-relacao.md`
depende de: 3
busca:
- repo | rg "git-common-dir|projects" hooks/lib | `hooks/lib/config.cjs` tem raizDoPrincipal; o slug de pasta de projeto do Claude Code é o caminho com todo caractere fora de [A-Za-z0-9] trocado por "-"
- livro | pulado: emenda de gate próprio
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; os casos P10 a P12 nascem com a tarefa
mutacao:
  arquivo: `hooks/gate-pergunta-memoria.cjs`
  de: `const slugDoProjeto = (p) => p.replace(/[^A-Za-z0-9]/g, "-");`
  para: `const slugDoProjeto = (p) => "nao-existe";`
  bateria: `node hooks/testa-gate-pergunta-memoria.cjs`
  fixture: `testa-gate-pergunta-memoria.cjs, caso "P10" (transcrito na pasta do slug do worktree, memória só na pasta do slug do principal)`
pronto quando: com o payload real do Stop cujo `transcript_path` está em `<projects>/<slug do worktree>/<sessao>.jsonl`, `cwd` dentro de um worktree linkado de um repositório git real, e a memória só em `<projects>/<slug do principal>/memory/`, o hook sai com exit 2 citando o arquivo (P10). Casamento só por nome e `description`: um arquivo cujo corpo compartilha os termos da `Q` mas cuja descrição não compartilha **não** barra (P11, fixture `corpo-sem-relacao.md`). A perna do banco é exercitada: com um `rainforest.db` montado no `RFM_ROOT` pelo caminho que as baterias de memória já usam, contendo uma observação que casa com a `Q` e sem `memory/`, o hook sai com exit 2 citando o banco (P12). P1 a P9 seguem verdes. Provado por `node hooks/testa-gate-pergunta-memoria.cjs` com `falhou: 0` e linhas `ok` de P1 a P12, e pela mutação acima deixando P10 vermelho.

### 9. Pedido de licença com fecho formatado [tipo: implementar]
atende: D4
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`
depende de: 2
busca:
- repo | rg "RE_PEDE_LICENCA" hooks | só a regex da tarefa 2
- livro | pulado: emenda de gate próprio
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; os casos C10 a C12 nascem com a tarefa
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: `const fimSemFormatacao = (t) => t.replace(/(?:\s|\*\*|__|\([^()\n]{0,80}\)|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}])+$/u, "");`
  para: `const fimSemFormatacao = (t) => t;`
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: `testa-gate-turno-prometido.cjs, caso "C10" (último texto "**Sigo com o executar?**")`
pronto quando: com o C1 trocado só no último texto, o gate barra (exit 2) "**Sigo com o executar?**" (C10), "Sigo com o executar? 👍" (C11) e "Sigo com o executar? (o plano está em docs/)" (C12). C1 a C9 seguem como estão. Provado por `node hooks/testa-gate-turno-prometido.cjs` com `falhou: 0` e linhas `ok` de C10 a C12, e pela mutação acima deixando C10 vermelho.

### 10. Documentação diz o que fica fora [tipo: docs]
atende: D8
arquivos: `README.md`, `docs/travas-mecanicas.md`, `CHANGELOG.md`
depende de: 6, 7, 8, 9
mutacao: n/a
  motivo: texto; a falsificação é a coerência com os casos de bateria
pronto quando: com os hooks da rodada 2, a linha da portaria no README e a primeira coluna da tabela de `docs/travas-mecanicas.md` dizem que o pedido de `isolation: "worktree"` torna qualquer agente escritor e que sem `isolation` e sem frontmatter legível o despacho passa; o parágrafo do `gate-turno-prometido` diz que turno com `Q<n>` e pergunta em prosa fora do padrão passam; o do `gate-pergunta-memoria` diz que a memória é a do repositório principal, casada por nome e descrição, e que o banco do `memoria.cjs` também é consultado. Provado pela leitura, no revisar, de cada frase contra G1–G6, C10–C12 e P10–P12.

## Rodada 3 (revisão 2 aprovada com 4 achados que cabem no PR, 2026-10-28)

Decididas sem o usuário (`estado.cjs decidir`, chave `executar-autonomo`): a inferência de frontmatter sem `tools:` vale só para o fluxo pulado; o `gate-pergunta-memoria` só conta `Q<n>` que abre linha e tem `?`, ignora o vocabulário do projeto e o banco só conta observação do projeto atual.

Emenda na tarefa 12 (integração): a forma real das perguntas é `❓ **Q1`, então o marcador aceita emoji e marca combinante antes do `Q<n>`; o `de:` da 12 é a linha ampliada.

Emenda na tarefa 11 (integração): a mensagem nova da regra 11 para o não declarado muda a asserção do caso 6a de `hooks/testa-portaria-manifesto.cjs`, que entra no `arquivos:`.

Emenda na tarefa 11 (revisão de segurança na integração): a primeira forma (`&& !agentConfig.semTools` no ramo inteiro) pulava também a regra 11 com trilho e a regra 10; a dispensa virou `dispensaIsolamento`, só sem trilho, e o `de:` da 11 é essa linha.

Emenda na tarefa 11 (revisão 3): caso N12 prova a regra 10 para o agente sem `tools:`; README e CHANGELOG dizem que a dispensa vale só sem trilho.

Emenda na tarefa 9: a tarefa 13 troca a linha de `fimSemFormatacao`; o `de:` da 9 passa a ser a linha nova, com o mesmo `para:`.

### 11. Inferência sem `tools:` não aciona a regra 11 [tipo: implementar]
atende: D3, D8
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`, `hooks/testa-portaria-manifesto.cjs`
depende de: 7
busca:
- repo | rg "if \(agentConfig.escreve === true\)" hooks/portaria.cjs | o ramo da regra 11, único
- livro | pulado: emenda de trava própria
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; o caso N9 nasce com a tarefa
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const dispensaIsolamento = agentConfig.semTools === true && trilho === null;`
  para: `const dispensaIsolamento = false;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: `testa-portaria-fluxo-pulado.cjs, caso "N9" (repo git sem trilho, agente nao declarado com frontmatter sem tools:, sem isolation)`
pronto quando: com o payload real do PreToolUse de `Agent` para um agente não declarado cujo frontmatter não tem `tools:`, sem `isolation`, num repositório git sem trilho de fluxo, a portaria sai 0 (N9); com trilho e sem estágio aberto o mesmo despacho segue barrado pelo fluxo pulado (G3 inalterado). Com trilho e estágio `executar` aberto, o mesmo agente sem `isolation` é barrado pela regra 11 (N11): a dispensa vale só sem trilho, e a regra 10 (`name`) vale sempre. Agente não declarado com tool de escrita listada e sem `isolation` continua barrado pela regra 11, e a mensagem diz "tem tool de escrita no frontmatter" em vez de "declara 'escreve: true'" (N10). Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` com `falhou: 0` e linhas `ok` de N9 a N12 (N12: o N9 com `name` barra pela regra 10), todas as `hooks/testa-portaria-*.cjs` com `falhou: 0`, e pela mutação acima deixando N9 vermelho.

### 12. gate-pergunta-memoria: só pergunta de verdade, sem vocabulário do projeto, trecho útil do banco [tipo: implementar]
atende: D6
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`
depende de: 8
busca:
- repo | rg "matchAll\(/\bQ" hooks | só o `perguntas()` deste hook
- livro | pulado: emenda de trava própria
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; os casos P14 a P16 nascem com a tarefa
mutacao:
  arquivo: `hooks/gate-pergunta-memoria.cjs`
  de: `const RE_MARCADOR_Q = /^[ \t>*_\-\p{Extended_Pictographic}\p{M}]*Q(\d+)\b/gmu;`
  para: `const RE_MARCADOR_Q = /\bQ(\d+)\b/g;`
  bateria: `node hooks/testa-gate-pergunta-memoria.cjs`
  fixture: `testa-gate-pergunta-memoria.cjs, caso "P14" (Q1 no meio da prosa, com ? depois, casando 3 termos de uma memoria)`
pronto quando: com o transcrito real do Stop, um recap "Fechado: Q1 (b), ... <termos de uma memória>?" com `Q1` no meio da linha sai 0 (P14); `Q1 — Convivência com o hook atual?` contra uma memória que só compartilha vocabulário do projeto (`regra`, `fluxo`, `worktree`, `agente`, `plano`, `entrega`, `codex`, `claude`, `continua`, `ficar`) sai 0 (P15); observação do banco do projeto atual cujo conteúdo abre com `---` e um cabeçalho mostra, na mensagem, a primeira linha de texto, nunca `---` (P16); observação de outro projeto não barra. P1 a P13 seguem como estão. Provado por `node hooks/testa-gate-pergunta-memoria.cjs` com `falhou: 0` e linhas `ok` de P14 a P16, e pela mutação acima deixando P14 vermelho.

### 13. Regex do fecho formatado sem backtracking exponencial [tipo: implementar]
atende: D4
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`
depende de: 9
busca:
- repo | rg "fimSemFormatacao" hooks | só a linha da tarefa 9
- livro | pulado: emenda de gate próprio
desfecho: estender
prova-na-base: verde — a base desta rodada já tem a bateria verde; o caso C13 nasce com a tarefa
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: `const fimSemFormatacao = (t) => t.replace(/(?:\s|\*\*|__|\([^()\n]{0,80}\)|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}])+$/u, "");`
  para: `const fimSemFormatacao = (t) => t.replace(/(?:\s|\*\*|__|\(|\)|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]|\([^()\n]{0,80}\))+$/u, "");`
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: `testa-gate-turno-prometido.cjs, caso "C13" (ultimo texto "Sigo com o executar? " + "()" repetido 30 vezes + " fim", hook termina em menos de 3 s)`
pronto quando: com o C1 trocado só no último texto para "Sigo com o executar? " + "()"×30 + " fim", o hook termina em menos de 3 s (C13); C10, C11 e C12 seguem barrando. Provado por `node hooks/testa-gate-turno-prometido.cjs` com `falhou: 0` e linhas `ok` de C10 a C13, e pela mutação acima (a regex antiga) deixando C13 vermelho por estouro de tempo.
