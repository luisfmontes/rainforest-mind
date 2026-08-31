# Fluxo 8 — Design: `handover.cjs` + `regente.cjs` (sessões descartáveis, fluxo autônomo)

> Status: design · Depende de: fluxo 1 fechado (estado.cjs), fase 0 do fluxo 5 (medição de contexto); sinergia com fluxo 6 (portões — o regente lê os mesmos exit codes) · Alvo: rodar o pipeline sem interação humana, sem brainrot

## Problema

Sessão longa apodrece: o contexto incha, o modelo degrada, e o pior — quem escreveria o resumo de recuperação é justamente o modelo já degradado. Ao mesmo tempo, o objetivo do pipeline é rodar **sem interação**: pedir pro humano reiniciar sessão a cada estágio vai contra a autonomia. E com trabalho paralelo no mesmo repo, "o que entregar pra próxima sessão" e "o que a próxima sessão busca" não podem depender de julgamento.

Resposta: sessões curtas e descartáveis, renascendo limpas — com um **handover mecânico por tarefa** e um **orquestrador externo** que reinicia sessões sozinho.

## Princípios

1. **O trilho escolhe, a sessão não.** Sessão nunca decide o que ler nem o que entregar — o handover é montado por mecânica e injetado por hook.
2. **Handover se escreve na força, não na exaustão.** Montagem incremental a cada gate aprovado; nunca um "resumo de emergência" com o contexto a 95%.
3. **Reinício é mecânico.** Quem mata e sobe sessão é o `regente.cjs`, por sinal medido (gate fechado ou limiar de contexto), não por sensação.
4. **Um handover por tarefa, não por sessão.** Trabalho paralelo no mesmo repo não colide.
5. **Node puro `.cjs`, zero dependências, Windows-first** (regras da casa).

## Peça 1 — `handover.cjs` (montador incremental)

- Local: `.rainforest/handover/<tarefa-id>/atual.md`
- **Montagem mecânica** (sem julgamento do modelo): estágio atual do `estado.cjs`, decisões e evidências dos gates aprovados, arquivos tocados (git status/diff --stat), comandos de verificação que passaram.
- **Seção do modelo** (única parte escrita por LLM): "próximos passos + armadilhas", 10 linhas no máximo, escrita **logo após** cada `fechar` aprovado — momento de contexto ainda saudável.
- Cada atualização **substitui** a anterior (documento vivo, não log).
- `handover.cjs status <tarefa>` retorna frescor (idade, estágio) com exit code — moeda dos gates.

## Peça 2 — `regente.cjs` (orquestrador externo)

O loop que transforma o pipeline de assistido em autônomo:

```
regente iniciar <tarefa-id>
  └─ loop:
      1. lê estado.cjs → estágio atual da tarefa
      2. sobe sessão headless: claude -p "<prompt do estágio>" --tarefa <id>
         (hook de início injeta handover da tarefa + memórias 9+5)
      3. espera fim da sessão; lê exit code do gate
      4. gate aprovado → handover atualizado → mata sessão → próximo estágio
         gate reprovado → aplica política de reprova (ver Q1)
      5. tarefa concluída no estado → rotina de encerramento → fim
```

- **Reinício no meio de estágio longo:** a fase 0 da poda grava `.rainforest/poda/contexto.json` com `usage.input_tokens` real. Regente monitora; cruzou o limiar (Q2), sinaliza a sessão pra gerar a seção do modelo, mata e sobe continuação **do mesmo estágio** com handover fresco. Anti-brainrot sem humano olhando.
- **Sessão interativa (você presente):** regente é opcional. Hook de início lista tarefas com handover fresco e pergunta qual assumir — único ponto de escolha humana, e é seu por direito.
- Regente **não** interpreta conteúdo de sessão: só exit codes, estado em disco e o JSON da poda. Se não consegue decidir, para e escreve `.rainforest/handover/<tarefa>/BLOQUEADO.md` com o motivo.

## Ciclo de vida da tarefa (correção importante)

O encerramento pertence ao **ciclo de vida da tarefa**, não a um estágio. `colher` é o fim do fluxo de **ideias**; atividade de trabalho comum termina no último `fechar` e nunca passa pelo colher. A rotina de encerramento é a mesma nos dois casos — muda só o destino do que sobrevive:

| Tipo de tarefa | Fim detectado por | Permanente vai para | Transiente |
|---|---|---|---|
| Fluxo de ideia | `colher` aprovado | `docs/` (registro commitado) | apagado |
| Atividade de trabalho | último `fechar` do fluxo | **memória** (`memoria.cjs`: decisão, lição, comando que funcionou) | apagado |

Transiente = handover da tarefa, CCR da poda, métricas, worktree (se houver). O transcript morre; a decisão sobrevive — em documento quando é ideia, em memória consultável quando é trabalho.

## Fronteira com o git

Régua: **git guarda regra e resultado; `.rainforest/` guarda andamento.** Teste do caso cinzento: *"clonado em máquina limpa, esse arquivo ajuda ou confunde?"*

`.gitignore` (na raiz do `.rainforest/`):

```
.rainforest/handover/
.rainforest/poda/
.rainforest/*.jsonl
.rainforest/*.sqlite*
.rainforest/estado-tarefas/
```

- `handover/` — estado de máquina viva; commitado vira conflito entre worktrees e handover velho enganando clone alheio.
- `poda/` — **risco de segurança, não só higiene**: CCR guarda tool output bruto (um `env` dumpado, um `.env` lido por engano). Não pode existir a chance de commit.
- Métricas e SQLite — voláteis, merge impossível.

**Entram no git:** configs (`docs/rainforest/*.json`, limiares do regente), os `.cjs`, os SKILL.md, os designs de fluxo, e os registros destilados pelo encerramento de ideias em `docs/`.

## Trabalho paralelo no mesmo repo

- v1: paralelismo por **tarefa-id** — handovers, estados e CCR separados por tarefa; sessões simultâneas só se não tocarem os mesmos arquivos.
- v2 (avaliar, ver Q4): `git worktree` por tarefa — diretório de trabalho isolado, criado e destruído pelo regente, merge no encerramento. Elimina pisadas de pé por construção.

## Riscos e mitigação

1. **Regente em loop infinito de reprova.** → Política de reprova com teto (Q1) + BLOQUEADO.md + parada.
2. **Handover injetado velho/errado.** → TTL (Q3) + validação de estágio: hook só injeta se o estágio do handover bate com o do estado; divergiu, injeta aviso em vez do conteúdo.
3. **Duas sessões na mesma tarefa.** → lockfile por tarefa em `.rainforest/handover/<id>/.lock` (pid + timestamp; stale lock expira).
4. **Headless no Windows** (spawn, sinais, encoding do PowerShell). → e2e do regente roda nas duas plataformas antes do gate; nada de sinais unix pra matar sessão — usar mecanismo portátil.
5. **Seção do modelo alucinar próximos passos.** → limitada a 10 linhas, sempre subordinada à parte mecânica; a sessão seguinte confia no estado/gates, e trata a seção como dica, não como fato.

## Questões abertas

- **Q1.** Política de reprova do regente: parar e chamar humano na 1ª, ou N retries com o motivo da reprova anotado no handover? Proposta inicial: 2 retries anotados, depois BLOQUEADO.
- **Q2.** Limiar de contexto que força reinício no meio de estágio (proposta: 100k tokens de input, configurável na poda.json) — calibrar com dados da fase 0.
- **Q3.** TTL do handover pra injeção automática (proposta: 24h; mais velho que isso, hook pergunta em vez de injetar).
- **Q4.** Worktree entra no v1 do regente ou vira fluxo próprio (9)? Depende de quanto trabalho paralelo real existe hoje.
- **Q5.** O que exatamente uma atividade de trabalho destila pra memória no encerramento — formato e quem escreve (mecânico a partir dos gates, ou a seção do modelo do último handover)?

## Fora de escopo

- Compressão de contexto — território do fluxo 5 (poda).
- Memória semântica — território do `memoria.cjs`; handover é bastão descartável da tarefa ativa, superseded pelo próximo, nunca fonte de longo prazo.
- Multi-repo / multi-máquina — o regente orquestra um repo local por vez.

## Ordem na fila

Depois do fluxo 5 fase 0 (o gatilho de contexto depende da medição). `handover.cjs` pode nascer antes do regente e já servir sessões interativas — entrega isolada candidata a domingo; o regente fecha o pacote da autonomia.
