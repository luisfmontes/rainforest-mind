# Plano: testa-rodar-longo.sh confere a identidade do processo, não só o PID

Design: docs/rainforest/design/2026-10-29-rodar-longo-flaky.md

## O que não pode quebrar
- Os casos já existentes de `scripts/testa-rodar-longo.sh` continuam verdes, com as mesmas saídas esperadas do `rodar-longo.cjs` (`exit 3`, `rodando`, `morto`, `exit 127`).
- Processo da bateria que sobrevive ao fim continua deixando a bateria vermelha.
- `scripts/rodar-longo.cjs` não muda.

## Tarefas

### 1. Marca por execução e checagem final por identidade [tipo: teste]
atende: D1, D2, D3, D4, D5, D7
arquivos: `scripts/testa-rodar-longo.sh`
depende de: nenhuma
prova-na-base: verde — os casos de controle nascem na própria tarefa; na base a bateria não os tem e sai 0 na maior parte das execuções
mutacao:
  arquivo: `scripts/testa-rodar-longo.sh`
  de: *"$MARCA"*) return 0 ;;
  para: *"nunca-casa-$MARCA"*) return 0 ;;
  bateria: `bash scripts/testa-rodar-longo.sh`
  fixture: testa-rodar-longo.sh, caso "controle: processo vivo com a marca e reconhecido como da bateria"
pronto quando: com a bateria rodando 3 em paralelo, 12 rodadas seguidas (36 execuções, a carga que reproduziu a #632 em 3 de 36 na base), nenhuma execução sai vermelha, e as duas linhas de controle (`controle: processo vivo com a marca e reconhecido como da bateria`, `controle: processo vivo sem a marca nao e da bateria`) saem `ok` em cada uma — provado por `for r in $(seq 1 12); do for k in 1 2 3; do bash scripts/testa-rodar-longo.sh > "$TEMP/rl-$r-$k.log" 2>&1 & done; wait; done; grep -L "   falhou: 0$" "$TEMP"/rl-*.log` devolvendo nenhuma linha, e `grep -c "ok   controle:" "$TEMP"/rl-1-1.log` devolvendo `3` (o terceiro controle, da consulta sem resposta, entrou pela emenda da revisão 2)

Emenda da revisão 1 (2026-10-29): a checagem final ganha um caso com um processo alheio vivo registrado antes do laço ("o laco final nao conta nem mata o processo alheio registrado"), e `eh_da_bateria` devolve 2 para consulta sem resposta com o processo vivo, que conta como vivo sem `process.kill`. Segundo mutante, que tem de ficar vermelho: `eh_da_bateria "$p"; dono=$?` trocado por `eh_da_bateria "$p"; dono=0` em `scripts/testa-rodar-longo.sh`.

Forma prescrita: função `eh_da_bateria <pid>` que lê a linha de comando (Windows: `powershell -NoProfile -Command` com `Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"`; fora: `ps -o args= -p <pid>`) e decide com um `case` cuja linha casa com o `de:` acima. Linha de comando vazia com o processo ainda vivo (`esta_vivo`) devolve 2 (D4, emenda da revisão 1). A checagem final chama `eh_da_bateria` só para o PID que `esta_vivo` acusou; vivo sem a marca imprime `PID <n> reaproveitado por outro processo, ignorado` e não chama `process.kill`. Nenhum caso afirma sobre o texto do fonte.

### 2. CHANGELOG, README e versão 2.2.1 [tipo: docs]
atende: D6, D8
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e número de versão; o comportamento é medido pela mutação da tarefa 1
pronto quando: com o repositório no HEAD da tarefa, a versão é `2.2.1` nos dois `plugin.json` e no badge do README, e o CHANGELOG tem a entrada 2.2.1 dizendo que a causa da #632 foi reuso de PID (não o filho do vigia) e que a bateria deixou de matar processo alheio — provado por `bash scripts/testa-versao.sh` saindo 0 e `grep -c "reuso de PID" CHANGELOG.md` devolvendo ao menos `1`
