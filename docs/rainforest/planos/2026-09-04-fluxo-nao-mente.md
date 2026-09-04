# Plano: R1+R8 — o fluxo não mente sobre ter terminado, e o executor não pula verificação

Design: docs/rainforest/design/2026-09-04-fluxo-nao-mente.md

## O que não pode quebrar

- `node scripts/estado.cjs proximo` e `listar` continuam saindo 0 no que já saíam —
  nenhum chamador atual muda de comportamento (D2).
- `bash scripts/testa-estado.sh` continua verde no que já cobria (941 linhas hoje).
- Nenhum arquivo de `fluxo/guardas` é tocado: `hooks/gate-worktree.cjs`,
  `hooks/portaria.cjs`, `scripts/conferir-entrega.cjs`, `skills/limpar/SKILL.md`.
- O gate novo não pode barrar `git push -n`, que é `--dry-run` e é legítimo (D10).
- Commit normal (`git commit -m`) não pode ficar mais lento nem ser negado.

## Tarefas

### 1. Verbo `concluido` no estado.cjs [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: o `process.exit(2)` do ramo em que `proximo(estado)` devolve um estágio (fluxo não concluído) no comando `concluido`
  para: `process.exit(0)`
  bateria: `bash scripts/testa-estado.sh`
  fixture: os casos novos de `testa-estado.sh` que rodam `concluido` contra um estado com `fechar` pendente e exigem exit 2
pronto quando: com os arquivos de estado **reais** do repo em `docs/rainforest/estado/`, `node scripts/estado.cjs concluido --slug 2026-08-26-catraca-por-relogio` sai `0`, `node scripts/estado.cjs concluido --slug 2026-09-04-fluxo-nao-mente` sai `2` nomeando na saída o estágio que `proximo` aponta, e `node scripts/estado.cjs concluido` sem slug sai `2` listando os fluxos abertos — provado por `node scripts/estado.cjs concluido --slug 2026-08-26-catraca-por-relogio; echo $?` devolvendo `0`, `node scripts/estado.cjs concluido --slug 2026-09-04-fluxo-nao-mente; echo $?` devolvendo `2`, e `node scripts/estado.cjs concluido | grep -q camada-obsidian; echo $?` devolvendo `0`

### 2. Gate que barra pulo de verificação no git [tipo: implementar]
atende: D8, D9, D10, D11
arquivos: `hooks/gate-git-verificacao.cjs`, `hooks/hooks.json`, `hooks/testa-gate-git-verificacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-git-verificacao.cjs`
  de: o `process.exit(2)` do ramo que casa `--no-verify` no comando recebido
  para: `process.exit(0)`
  bateria: `bash hooks/testa-gate-git-verificacao.sh`
  fixture: o caso de `testa-gate-git-verificacao.sh` que manda o payload PreToolUse com `tool_input.command` igual a `git commit --no-verify -m x` e exige exit 2
pronto quando: com o JSON que o harness realmente manda no stdin de um `PreToolUse` — mesma forma de `.rainforest/portaria/amostra.json`, com `tool_name` igual a `"Bash"` e o comando em `tool_input.command` —, `git commit --no-verify -m x`, `git commit -n -m x`, `git commit --no-gpg-sign -m x` e `git push --no-verify` são negados, enquanto `git commit -m x` e `git push -n` passam — provado por, para cada um dos quatro primeiros, `printf '%s' "$PAYLOAD" | node hooks/gate-git-verificacao.cjs; echo $?` devolvendo `2`, e para os dois últimos devolvendo `0`

### 3. Prosa do R8 no briefing do executor [tipo: docs]
atende: D8
arquivos: `skills/executar/SKILL.md`, `agents/executor.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: texto de briefing não tem ramo de execução a inverter; a falsificação dele é casar com o que o gate da tarefa 2 realmente nega, e é isso que o critério abaixo mede
pronto quando: as flags que os dois textos nomeiam como proibidas são exatamente as que o gate da tarefa 2 nega, sem sobra nem falta — provado por, para cada flag citada como proibida nos dois arquivos, o gate devolver `2` com um payload que a use; e por `git push -n` (que os textos não podem listar como proibida) o gate devolver `0`, com `grep -c 'push -n' skills/executar/SKILL.md agents/executor.md` devolvendo `0` em ambos

### 4. Documentar o verbo e registrar o que ficou de fora [tipo: docs]
atende: D7, D12
arquivos: `skills/fechar/SKILL.md`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: a skill é texto lido por quem conduz o estágio, sem ramo de execução; a falsificação é o texto prometer exit codes que o verbo não devolve, e é isso que o critério mede
pronto quando: `skills/fechar/SKILL.md` descreve o `concluido` com os exit codes que ele devolve de verdade, diz que ele é sob demanda (nunca pendurado no `SessionEnd`), e cita o número de uma Issue aberta para a frente 1 do R1 (o `revisar` esperar em foreground) — provado por rodar cada invocação citada no texto e conferir que o exit code observado bate com o que o texto promete, e por `gh issue view <n> --json state -q .state` devolvendo `OPEN` para o número citado
