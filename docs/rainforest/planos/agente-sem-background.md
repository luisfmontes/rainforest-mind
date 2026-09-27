# Plano: subagente preso por bateria sem `timeout`

Design: docs/rainforest/design/agente-sem-background.md

## O que não pode quebrar
- Janela principal (payload sem `agent_id`) nunca é barrada por este gate.
- Ler o arquivo de uma bateria (`cat`, `grep`, `sed -n`, `head`) nunca é barrado.
- Payload ilegível, vazio ou de outra ferramenta: exit 0, como os gates irmãos.
- `gate-busca-raiz` e os demais hooks de `Bash` continuam com o mesmo comportamento.

## Tarefas

### 1. Gate nega bateria sem `timeout` em subagente [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-bateria-sem-timeout.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-bateria-sem-timeout.cjs`
  de: const temTimeout = typeof entrada.timeout === "number" && entrada.timeout > 120000;
  para: const temTimeout = true;
  bateria: `node hooks/testa-gate-bateria-sem-timeout.cjs`
  fixture: `testa-gate-bateria-sem-timeout.cjs, caso "bash hooks/testa-gate-worktree.sh sem timeout em subagente → 2"`
pronto quando: com o payload `PreToolUse` real de `Bash` vindo de subagente (os campos comuns da captura em `docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md`, com `agent_id`, trocando só `tool_name`/`tool_input`), o hook novo sai **2** para: `cd <wt> && bash hooks/testa-gate-worktree.sh 2>&1 | tail -5` sem `timeout`; `node hooks/testa-gate-busca-raiz.cjs` sem `timeout`; `timeout 300 bash scripts/testa-estado.sh` sem o parâmetro `timeout`; `node scripts/conferir-mutacao.cjs --arquivo x --de a --para b --bateria c` sem `timeout`; `node scripts/conferir-fluxo.cjs mutacoes --slug x` sem `timeout`; `./scripts/testa-estado.sh` sem `timeout`; `bash hooks/testa-gate-worktree.sh` com `timeout: 120000`. E sai **0** para: o mesmo `bash hooks/testa-gate-worktree.sh` com `timeout: 600000`; `cat hooks/testa-gate-worktree.sh`; `grep -n x scripts/testa-estado.sh`; `sed -n 1,5p hooks/testa-gate-busca-raiz.cjs`; `node scripts/conferir-fluxo.cjs cobertura --slug x`; `cat <<'EOF'` com `bash hooks/testa-x.sh` no corpo do heredoc; payload **sem** `agent_id` com a bateria sem `timeout`; toggle `"bateria-sem-timeout": false` em `.rainforest/config.json` do `cwd` do evento; `tool_name` diferente de `Bash`; stdin vazio. A mensagem em stderr diz `timeout: 600000` e como desligar. O hook é registrado em `hooks/hooks.json` no bloco `PreToolUse`/`Bash` ao lado do `gate-busca-raiz.cjs`, e o toggle aparece em `hooks/lib/config.cjs` com `padrao: true`. Provado por `node hooks/testa-gate-bateria-sem-timeout.cjs` imprimindo cada caso com o exit esperado e o obtido, e por `bash scripts/varrer-baterias.sh --so hooks/testa-gate-bateria-sem-timeout.cjs` saindo 0. *(Emenda de 2026-09-27, revisão 1: faltavam formas honestas que passavam com exit 0 — caminho direto sem interpretador (`scripts/testa-estado.sh`, `hooks/testa-gate-worktree.sh`, `/c/Projetos/rainforest-mind/scripts/testa-estado.sh`, `C:/Projetos/rainforest-mind/scripts/testa-estado.sh`), continuação de linha (`bash ` + quebra + `hooks/testa-gate-worktree.sh`), subshell (`(cd <wt> && bash scripts/testa-estado.sh)`) e substituição (`echo $(bash scripts/testa-estado.sh)`). Todas, sem `timeout`, saem **2**; `scripts/varrer-baterias.sh` direto com `timeout: 600000` sai **2** (tarefa 2). A bateria passa a asserir também o stderr: `timeout: 600000` e o toggle na mensagem da tarefa 1, `--so` na da tarefa 2.)*

### 2. Varredura completa negada em subagente [tipo: implementar]
atende: D2
arquivos: `hooks/gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-bateria-sem-timeout.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/gate-bateria-sem-timeout.cjs`
  de: const varreduraCompleta = analise.ehVarredor && !analise.args.includes("--so");
  para: const varreduraCompleta = false;
  bateria: `node hooks/testa-gate-bateria-sem-timeout.cjs`
  fixture: `testa-gate-bateria-sem-timeout.cjs, caso "bash scripts/varrer-baterias.sh com timeout 600000 em subagente → 2"`
pronto quando: com o mesmo payload real de subagente, `bash scripts/varrer-baterias.sh` com `timeout: 600000` sai **2** com mensagem que manda usar `--so <bateria>` e diz que a varredura completa é de quem integra; `cd <wt> && bash scripts/varrer-baterias.sh 2>&1 | tail -30` com `timeout: 600000` sai **2**; `bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh` com `timeout: 600000` sai **0**; o mesmo `--so` sem `timeout` sai **2** (regra da tarefa 1); `bash scripts/varrer-baterias.sh` sem `agent_id` sai **0**. Provado por `node hooks/testa-gate-bateria-sem-timeout.cjs` com os casos impressos. *(Emenda de 2026-09-27, integração: o executor leu `ehVarredor`/`args` de um objeto `analise`; o alvo de mutação passou a ser a linha real, com a mesma semântica.)*

### 3. Texto acompanha o mecanismo, versão e changelog [tipo: docs]
atende: D4, D5
arquivos: `referencias/perfil-de-trabalho.md`, `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`, `hooks/gate-busca-raiz.cjs`, `skills/executar/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: só texto, versão e changelog; o comportamento está nas tarefas 1 e 2
pronto quando: com a árvore real, a linha "Nada seu fica rodando" do perfil cita o `gate-bateria-sem-timeout` e diz que a varredura completa não roda dentro de agente (D1, D2), e os `agents/*.md` ficam idênticos ao perfil aplicado — provado por `node scripts/perfil.cjs --conferir` saindo 0; o "Não protege contra" de `hooks/gate-busca-raiz.cjs` aponta o gate novo; a seção "Critério que roda bateria carrega o placar" de `skills/executar/SKILL.md` diz que o laço inteiro é rodado pela integração e que o agente cola o placar das baterias que a tarefa toca, coerente com D2; `plugin.json` e o badge do README no minor seguinte ao da `origin/main` (provado por `node scripts/conferir-versao.cjs` saindo 0); o CHANGELOG tem entrada com o número medido no design (10 de 14 subagentes) e o toggle `bateria-sem-timeout`. O README só muda no badge: ele não lista toggles nem gates (medido: nenhuma menção a `busca-na-raiz`/`agente-folha`).
