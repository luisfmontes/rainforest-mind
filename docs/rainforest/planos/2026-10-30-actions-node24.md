# Plano: actions dos workflows em Node 24

Design: docs/rainforest/design/2026-10-30-actions-node24.md

## O que não pode quebrar
- Os gatilhos, a matriz, os shards, o `fetch-depth: 0` e as permissões dos dois workflows não mudam. Só a linha `uses:` das três actions muda.
- O `baterias.yml` continua sendo o único workflow que roda em PR (`publicar-branch.cjs` conta os workflows de PR).

## Tarefas

### 1. As três actions sobem para v7 nos dois workflows [tipo: configurar]
atende: D1, D3
arquivos: `.github/workflows/baterias.yml`, `.github/workflows/release.yml`
depende de: nenhuma
mutacao: n/a
  motivo: YAML de workflow não roda localmente; a prova é o run real do `baterias.yml` na branch (D3)
pronto quando: com os dois arquivos no HEAD da tarefa, `grep -hc "actions/checkout@v7\|actions/setup-node@v7\|actions/setup-python@v7" .github/workflows/baterias.yml .github/workflows/release.yml` imprime `3` e `2`, e `grep -c "@v4\|setup-python@v5" .github/workflows/*.yml` imprime `0` nos dois (o número impresso é o sinal; o `grep -c` sai 1 com zero casamentos). E um run do `baterias.yml` disparado por `gh workflow run baterias.yml --ref fluxo/actions-node24` no HEAD da tarefa, com o id re-derivado de `gh run list --workflow baterias.yml --branch fluxo/actions-node24 --limit 1`, termina com `conclusion` `success`, e `gh run view <id> --log | grep -c "Node.js 20 is deprecated"` imprime `0`.

### 2. CHANGELOG e versão 2.3.1 [tipo: docs]
atende: D2
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e número de versão; o comportamento é o da tarefa 1
pronto quando: com o repositório no HEAD da tarefa, a versão é `2.3.1` nos dois `plugin.json` e no badge do README, e o CHANGELOG tem a seção `## 2.3.1` citando as três actions — provado por `bash scripts/testa-versao.sh` saindo 0 e por `node scripts/release-da-versao.cjs --sha HEAD --seco` imprimindo as notas da seção 2.3.1, com `actions/checkout@v7` entre elas.
