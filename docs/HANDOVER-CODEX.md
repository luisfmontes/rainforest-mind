# Handover Codex — Rainforest Mind multihost 1.23.0

## Ponto canônico de retomada — 2026-09-22

- Versão corrente: `1.23.0`, conforme os manifestos Claude e Codex.
- Base corrente: `0e27956c14d52bd7efefdd343531ffbbb8811726`
  (`origin/main`, 1.23.0).
- Merge da base na entrega:
  `7febeface33c10de4f2b32395c3e0a595656857a`.
- Base anterior corrente: `5cdb90e768cb1ba808821d5bdcdf46f7a19fc782`.
- Branch de entrega: `codex/multihost-1.13`.
- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`.
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`.
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`.
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`.
- Gemini continua adiado: nenhum manifesto, hook, adaptador ou fixture de
  payload Gemini pertence a esta entrega.
- `executar` está parcial: os contratos locais foram reancorados, mas instalação,
  cache, projeção D9/D11 e contraprova de host em 1.23.0 permanecem pendentes.
- Sem aval explícito do usuário, é proibido abrir PR, publicar release, mesclar
  ou alterar a `main`. Commit e push da branch de entrega não equivalem a merge.

Revalide o ponto corrente com:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git merge-base --is-ancestor 0e27956c14d52bd7efefdd343531ffbbb8811726 HEAD
git show HEAD:.claude-plugin/plugin.json
git show HEAD:.codex-plugin/plugin.json
node scripts/estado.cjs ler --slug 2026-09-12-multihost-sobre-1-11
```

## Evidência corrente de instalação 1.23.0

A instalação externa não foi executada nesta reancoragem. O export limpo, o
cache instalado, a projeção D9/D11 e a contraprova em sessão Codex para 1.23.0
permanecem pendentes; provas anteriores não são promovidas a aceite corrente.

## Histórico não operacional — evidência 1.21.1

A entrega começou em versões anteriores e passou por reancoragens, diagnósticos
de instalação, correções de fixtures e repetições da contraprova. Essas rodadas
explicam o slug histórico `sobre-1-11`, mas não definem a retomada atual e não
devem ser repetidas. Os detalhes auditáveis continuam disponíveis no histórico
Git e nas seções explicitamente históricas do portão; este handover contém
somente o roteiro corrente de 1.23.0. A instalação 1.21.1 permanece preservada
no estado e no portão sob rótulo histórico explícito.
