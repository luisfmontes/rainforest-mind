# Plano: effort fixado no frontmatter dos agentes

Design: docs/rainforest/design/effort-nos-agentes.md

## O que não pode quebrar
- `scripts/testa-agentes-folha.sh` continua verde (frontmatter mantém `disallowedTools: Agent` e não ganha `tools:`).
- `scripts/despachar-codex.cjs` continua extraindo `model:` (a linha `effort:` entra depois de `model:`).

## Tarefas

### 1. Effort por papel nos nove agentes, com bateria por glob [tipo: implementar]
atende: D1, D2, D3
arquivos: `agents/*.md`, `scripts/testa-agentes-effort.sh`, `scripts/tempos-baterias.json`
depende de: nenhuma
paralela: nao
prova: `bash scripts/testa-agentes-effort.sh`
mutacao:
  arquivo: `agents/revisor.md`
  de: effort: high
  para: effort: medium
  bateria: `bash scripts/testa-agentes-effort.sh`
  fixture: revisor-com-effort-errado
pronto quando: com os `agents/*.md` como o harness os carrega, cada um traz `effort:` igual ao mapa D1/D2 (high: revisor, tester, depurador, auditor-de-seguranca, planejador, arqueologo; medium: executor, documentador, resolvedor-de-build) — provado por `for a in revisor tester depurador auditor-de-seguranca planejador arqueologo; do sed -n '2,/^---$/p' agents/$a.md | grep -qx 'effort: high' || exit 1; done; for a in executor documentador resolvedor-de-build; do sed -n '2,/^---$/p' agents/$a.md | grep -qx 'effort: medium' || exit 1; done` saindo 0, e `bash scripts/testa-agentes-folha.sh` saindo 0

### 2. CHANGELOG diz o que muda para quem usa [tipo: docs]
atende: D4
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md` (versão 1.57.0 sobe junto da nota)
depende de: 1
paralela: nao
mutacao: n/a
  motivo: nota de versão; não há comportamento executável a inverter
pronto quando: com a entrada da versão nova do CHANGELOG, ela nomeia os dois grupos de effort e a precedência de `CLAUDE_CODE_EFFORT_LEVEL` — provado por `awk '/^## /{n++} n==1' CHANGELOG.md | grep -c "CLAUDE_CODE_EFFORT_LEVEL"` devolvendo 1 ou mais e `awk '/^## /{n++} n==1' CHANGELOG.md | grep -c "effort"` devolvendo 2 ou mais
