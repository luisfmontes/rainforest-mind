# Evidência do `verificar` precisa citar um sensor

Seção tirada de `skills/plano/SKILL.md` no lote 1 (2026-10-24), sem reescrita. O SKILL guarda só o resumo.


Fechar o estágio `verificar` com `ok` exige mais do que `comando`/`saida`
presentes na evidência (`--json` de `node scripts/estado.cjs marcar`):
`comando` precisa casar com um **sensor**. Duas formas contam:

- **peça do repo marcada `sensor`** por `node scripts/conferir-categoria.cjs`
  (ex.: `node scripts/conferir-categoria.cjs` propriamente, ou outro
  `scripts/conferir-*.cjs`) — `comando` cita o caminho da peça; ou
- **sensor externo declarado** pelo campo `sensor_externo`, no mesmo
  `--json` — string não vazia que precisa aparecer DENTRO de `comando`:

  ```
  --json '{"comando":"bash scripts/testa-estado.sh","saida":"...","sensor_externo":"bash scripts/testa-estado.sh"}'
  ```

Sem um dos dois, `scripts/estado.cjs` recusa o fechamento com exit 2. Só
`verificar` barra — `executar` (o outro estágio que exige evidência) apenas
avisa em stderr e fecha normalmente, porque barrar ali pararia trabalho
legítimo no meio.

**`scripts/testa-*.sh` NÃO são peças marcadas `sensor`** —
`conferir-categoria.cjs` os exclui de propósito. Quase todo critério deste
repo é "provado por `bash scripts/testa-*.sh`", então **critério do
`verificar` cujo `comando` não seja peça marcada `sensor` precisa declarar
`sensor_externo`**, mesmo sendo um script do próprio repo — senão o
fechamento recusa.

Este canal é diferente da linha `Sensor:` do briefing de despacho (ver
`skills/executar/SKILL.md`) — aquela é lida por `hooks/portaria.cjs` a
partir do prompt de despacho de agente; este é campo do `--json` de
fechamento, lido por `scripts/estado.cjs`, que nunca recebe texto de
briefing.
