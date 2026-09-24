# Plano: Agente despachado é folha

Design: docs/rainforest/design/2026-09-24-revisor-folha.md

## O que não pode quebrar
- Despacho da janela principal (payload sem `agent_id`) segue exatamente como hoje: manifesto, estágio, regra 11 (`isolation`/`name`) — nenhuma bateria existente de `hooks/testa-portaria-*.cjs` muda de resultado.
- `NATIVOS_DO_HARNESS` e o parser de `tools:` da portaria (`parseToolsDoFrontmatter`) não mudam: `disallowedTools` é chave nova, que a portaria não lê.
- O PASSO ZERO da ponte Codex nos agentes (`<!-- ponte-codex -->`) continua funcionando: ele chama `despachar-codex.cjs` por Bash, não a ferramenta `Agent`.
- `skills/*/SKILL.md` dentro do teto de `scripts/testa-teto-skills.sh`.
- Nada escrito fora do worktree; nenhum `~/.claude*` real alterado (regra 15).

## Tarefas

### 1. Confirmar ao vivo os dois fatos da doc [tipo: pesquisar]
atende: D4
arquivos: `docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md`, `hooks/fixtures/portaria-folha/payload-de-subagente.json`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa; o artefato é a captura de um payload real e o registro do que o harness fez, não código de produção.
pronto quando: com um despacho REAL de `Agent` feito de dentro de um subagente nesta máquina (Claude Code 2.1.281), o JSON que o harness entregou ao `PreToolUse` fica salvo em `hooks/fixtures/portaria-folha/payload-de-subagente.json` com `agent_id` e `agent_type` não vazios, e o mesmo registro mostra um payload da janela principal SEM as duas chaves; e um subagente definido com `disallowedTools: Agent` no frontmatter é despachado e relata (com a lista de ferramentas que recebeu colada) que `Agent` não está entre elas. Tudo capturado sem escrever fora do worktree (hook de captura, se preciso, só em `.claude/settings.local.json` do próprio worktree, apagado ao fim). Se o harness não carregar config do worktree e a captura exigir instalar o plugin, a pesquisa diz isso com a evidência e a confirmação passa para o `verificar`, depois de `claude plugin update`.

### 2. Portaria nega `Agent` vindo de dentro de subagente [tipo: implementar]
atende: D4, D5
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-folha.cjs`, `hooks/fixtures/portaria-folha/payload-de-subagente.json`, `hooks/fixtures/portaria-folha/payload-da-janela.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `if (payload.agent_id && agenteFolhaLigado(raiz)) {`
  para: `if (false) {`
  bateria: `node hooks/testa-portaria-folha.cjs`
  fixture: `testa-portaria-folha.cjs, caso "payload de subagente (agent_id presente) e negado"`
pronto quando: com o payload real capturado na tarefa 1 (`agent_id` e `agent_type` presentes) no stdin de `node hooks/portaria.cjs`, a saída é deny (exit 2) com mensagem que (a) nomeia o `agent_type` de quem chamou, (b) diz que agente despachado é folha e não despacha agente, e (c) manda fazer sozinho e, se não couber, devolver parcial com a lista explícita do que não conferiu (D5); o `despachos.jsonl` da caixa ganha linha `decisao: "deny"` com o motivo; o mesmo payload SEM `agent_id` segue o caminho de hoje (manifesto) — provado por `node hooks/testa-portaria-folha.cjs` imprimindo os três casos e por `bash hooks/testa-portaria.sh` sem nenhuma bateria existente mudando de resultado.

### 3. Toggle `agente-folha` [tipo: configurar]
atende: D6
arquivos: `hooks/lib/config.cjs`, `hooks/portaria.cjs`, `hooks/testa-portaria-folha.cjs`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `return ligado('agente-folha', { projeto: raiz });`
  para: `return true;`
  bateria: `node hooks/testa-portaria-folha.cjs`
  fixture: `testa-portaria-folha.cjs, caso "agente-folha desligado no .rainforest/config.json do projeto libera o payload de subagente"`
pronto quando: com `{"agente-folha": false}` no `.rainforest/config.json` do projeto da caixa, o payload real de subagente da tarefa 1 deixa de ser negado pela regra de folha (segue para o manifesto); sem a chave, é negado; `node scripts/setup.cjs` lista `agente-folha` com a descrição — provado por `node hooks/testa-portaria-folha.cjs` e pela saída de `node scripts/setup.cjs` contendo a linha do toggle.

### 4. Os 9 agentes do plugin perdem a ferramenta `Agent` [tipo: configurar]
atende: D1, D2, D4
arquivos: `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`, `scripts/testa-agentes-folha.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `agents/revisor.md`
  de: `disallowedTools: Agent`
  para: `disallowedTools: NotebookEdit`
  bateria: `bash scripts/testa-agentes-folha.sh`
  fixture: `testa-agentes-folha.sh, caso "todo agents/*.md declara disallowedTools com Agent"`
pronto quando: com os 9 arquivos reais de `agents/`, cada frontmatter tem `disallowedTools` contendo `Agent` e nenhum ganhou `tools:` (herdam o resto do pool); a bateria lê a lista de agentes de `agents/*.md` (não de uma lista fixa), então agente novo sem a chave reprova; e `node hooks/portaria.cjs` com despacho de `rainforest-mind:revisor` da janela continua liberando — provado por `bash scripts/testa-agentes-folha.sh` e pela bateria da portaria inalterada.

### 5. Regra 10 e briefing: folha, parcial com lacuna, fechamento de rodada [tipo: docs]
atende: D2, D3, D5
arquivos: `skills/rainforest-mind/references/regra-10.md`, `skills/rainforest-mind/SKILL.md`, `skills/modo-dev/SKILL.md`
depende de: 2, 4
paralela: nao
mutacao: n/a
  motivo: doc; a falsificação é a coerência com D2, D3 e D5 e com o comportamento real da portaria e dos agentes (tarefas 2 e 4).
pronto quando: `regra-10.md` diz, coerente com o design: (a) agente despachado é folha — os 9 do plugin sem a ferramenta, a portaria negando o resto, com o toggle `agente-folha` (D4, D6); (b) folha com trabalho grande faz sozinha e devolve parcial com a lista do que não conferiu, e quem particiona é quem despachou (D1, D5); (c) antes de declarar pronta uma rodada com agentes em paralelo, a janela roda `ListAgents` e para o que ela abriu e sobrou (D3) — com os dois incidentes datados; `skills/modo-dev/SKILL.md` põe no briefing a agente nativo do harness a linha "não despache agente" (D2); o núcleo da regra 10 em `skills/rainforest-mind/SKILL.md` ganha uma frase de folha + fechamento sem estourar o teto — conferido lendo cada frase contra `hooks/portaria.cjs` e `agents/*.md` da tarefa 2 e 4, e por `bash scripts/testa-teto-skills.sh` sem skill acima do teto.

### 6. Versão 1.23.10 [tipo: configurar]
atende: fechar
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `.claude-plugin/plugin.json` e o selo da linha 7 do `README.md` dizem a versão seguinte à da `origin/main` no momento do bump (hoje `1.23.9` → `1.23.10`) — conferido por `MSYS_NO_PATHCONV=1 git show origin/main:.claude-plugin/plugin.json`. Feita no `fechar`, depois do `revisar`.

### 7. Verificador de publicação não recusa `noreply@` [tipo: implementar]
atende: D4
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
paralela: nao
Emenda de 2026-09-24: o commit da tarefa 4 foi barrado pelo `gate-verificador-staged` — cinco `agents/*.md` já traziam no corpo o trailer `Co-Authored-By: ... <noreply@...>`, e arquivo staged diferente de HEAD é varrido inteiro. Defeito do repo da sessão atrapalhando a entrega: conserto na hora (regra 6).
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `re: /\b(?!noreply@)[\w.+-]+@`
  para: `re: /\b[\w.+-]+@`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: `testa-conferir-publicacao.sh, caso "trailer noreply@ nao acende a regra de e-mail"`
pronto quando: com o arquivo real `agents/executor.md` (que traz o trailer), `node scripts/conferir-publicacao.cjs agents/executor.md --json` devolve `achados: []`; um arquivo com o trailer e um e-mail real continua achado `email` — provado por `bash scripts/testa-conferir-publicacao.sh` nos dois casos novos e pelo commit da tarefa 4 passando no gate.
