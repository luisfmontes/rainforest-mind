# Plano: Folga no teto de 16 KB das skills regua, executar, fechar e plano

Design: docs/rainforest/design/2026-10-30-folga-no-teto-das-skills.md

## O que não pode quebrar
- As frases de `skills/*/invariantes.json` continuam no `SKILL.md` de cada skill (`bash scripts/testa-conferir-invariantes.sh`).
- `scripts/testa-fechar-destino.sh` e `hooks/testa-portaria-manifesto.cjs` continuam lendo o que leem hoje.
- O texto movido é o mesmo, byte a byte.

## Tarefas

### 1. Mover os quatro blocos para references e re-medir as âncoras do Codex [tipo: docs]
atende: D1, D2, D3, D4, D5, D6, D7
arquivos: `skills/regua/SKILL.md`, `skills/regua/references/o-que-falsificaria.md`, `skills/executar/SKILL.md`, `skills/executar/references/catraca-de-mutacao.md`, `skills/fechar/SKILL.md`, `skills/fechar/references/concluido.md`, `skills/plano/SKILL.md`, `skills/plano/references/incidente-pronto-quando.md`, `scripts/contrato-plugin-codex.cjs`
depende de: nenhuma
mutacao: n/a
  motivo: só move texto entre arquivos da mesma skill; não há comportamento executável a inverter, e a conferência byte a byte do critério é o que falsifica a entrega
pronto quando: com os quatro `SKILL.md` e os quatro arquivos novos no HEAD da tarefa, cada bloco de `origin/main` (regua: de "## O que falsificaria esta skill" até antes de "## Onde mora o resto"; executar: de "| exit | significa" até antes de "## Fechamento"; fechar: de "## Conferir de fora se o fluxo fechou" até antes de "## Condição de parada"; plano: de "> 2026-08-19: as 13 tarefas" até antes de "### Evidência do `verificar`") aparece inteiro, byte a byte, no arquivo novo da sua skill e não aparece mais no `SKILL.md`, e cada `SKILL.md` tem ao menos 1.000 bytes de folga sob 16.384 — provado por `node scripts/_conferir-movidos.cjs` (script descartável da tarefa, fora do commit) imprimindo `ok` para as quatro skills com a folga de cada uma, e por `bash scripts/testa-teto-skills.sh`, `bash scripts/testa-plugin-codex.sh`, `bash scripts/testa-conferir-invariantes.sh`, `bash scripts/testa-fechar-destino.sh`, `node hooks/testa-portaria-manifesto.cjs` e `bash scripts/testa-indice-referencias.sh` saindo 0

### 2. CHANGELOG, README e versão 2.2.2 [tipo: docs]
atende: D8
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e número de versão
pronto quando: com o repositório no HEAD da tarefa, a versão é `2.2.2` nos dois `plugin.json` e no badge do README, e o CHANGELOG tem a entrada 2.2.2 nomeando as quatro skills e os quatro arquivos novos — provado por `bash scripts/testa-versao.sh` saindo 0 e `grep -c "o-que-falsificaria.md\|catraca-de-mutacao.md\|concluido.md\|incidente-pronto-quando.md" CHANGELOG.md` devolvendo ao menos `4`
