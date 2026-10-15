# Flake gravado pela integração, sem depender da janela (#498)

## Objetivo
O status `flaky` (D6 do fluxo `2026-10-10-flaky-teto`) só dispara se o flake for gravado no estado, e hoje nada o grava mecanicamente. O `rodar-gate.cjs` não tem chamador, e a catraca chamada pela integração não recebe `--slug`/`--tarefa`. O flake passa a ser gravado no caminho que o fluxo já obriga: a integração de cada tarefa.

## Decisões fechadas
- **D1 — A integração repassa `--slug` e `--tarefa` ao `conferir-mutacao`** — porquê: o `integrar-tarefa.cjs` já roda a bateria de cada tarefa por script (o baseline da catraca, com a nova tentativa embutida desde a 1.61.0). Falta só o `conferir-fluxo.cjs mutacoes` repassar os dois ao `conferir-mutacao`, que já sabe gravar o flake (`gravarFlake`, gate `catraca: <bateria>`). O repasse é pedido por uma flag explícita da integração, e o `verificar` (`estado.cjs`, chamada de `mutacoes` sem a flag) continua sem gravar, como fixou o D2 do `flaky-teto`: o laço é `executar` e `revisar`. Não roda a bateria uma vez a mais (Luís, Q1: recomendado).
- **D2 — `rodar-gate.cjs` sai do repositório** — porquê: sem chamador, ele é a prosa que o D4 do `flaky-teto` queria eliminar (a nova tentativa dependendo de a janela lembrar). Saem o script, a bateria `scripts/testa-rodar-gate.sh` (e a linha dela em `scripts/baterias-obrigatorias.txt`), a linha da tabela no `README.md` e no `docs/travas-mecanicas.md`, e o `laco.md` passa a dizer que o flake é gravado pela integração (`integrar-tarefa.cjs`), não por um comando que a janela roda. O CHANGELOG antigo fica como está: é histórico (Luís, Q2: recomendado).

## Avaliado e descartado
- `marcar executar ok` exigir um registro do `rodar-gate.cjs` por tarefa: artefato novo e uma rodada a mais de bateria que leva minutos.
- O `verificar` rodar o critério pelo `rodar-gate.cjs`: o `pronto quando:` é prosa, e exigiria um campo `criterio:` novo no plano; além disso o `verificar` está fora do laço do flaky.
- Manter o `rodar-gate.cjs` como ferramenta manual: continua sem chamador.

## Fora de escopo
- Obrigar o `marcar executar ok` a ter toda tarefa com mutação em `integradas` (janela que pula a integração).
- Tarefa com `mutacao: n/a`: não tem bateria declarada, então não tem flake a gravar.

## Varredura
docs/rainforest/varredura/2026-10-15-rodar-gate-mecanico.txt — só a própria #498 trata do assunto; nenhum PR aberto mexe nesses arquivos.

## Em aberto
nada
