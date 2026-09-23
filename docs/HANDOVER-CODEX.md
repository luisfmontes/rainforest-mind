# Handover Codex — Rainforest Mind multihost 1.23.0

## Ponto canônico de retomada — 2026-09-22

- Versão corrente: `1.23.0`, conforme os manifestos Claude e Codex.
- Base corrente: `4301a205b9c90a101924cc60fdd2cb7b3bed4bfa`
  (`origin/main`, 1.23.0).
- Merge da base na entrega:
  `fc76be76b5f8dd5c3c9dac9016db33098abc5d94`.
- Base e merge históricos: `0e27956c14d52bd7efefdd343531ffbbb8811726`
  e `7febeface33c10de4f2b32395c3e0a595656857a`.
- Branch de entrega: `codex/multihost-1.13`.
- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`.
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`.
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`.
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`.
- Gemini continua adiado: nenhum manifesto, hook, adaptador ou fixture de
  payload Gemini pertence a esta entrega.
- `executar` foi revalidado em 9/9 na base corrente: T1–T5 tiveram mutações
  vermelhas, T6–T9 foram medidos pelos artefatos, e `revisar` é o próximo estágio.
- Esta rodada termina com commit local na branch de entrega: sem push, PR,
  release, merge ou alteração da `main`.

Revalide o ponto corrente com:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git merge-base --is-ancestor 4301a205b9c90a101924cc60fdd2cb7b3bed4bfa HEAD
git show HEAD:.claude-plugin/plugin.json
git show HEAD:.codex-plugin/plugin.json
node scripts/estado.cjs ler --slug 2026-09-12-multihost-sobre-1-11
```

## Evidência corrente de instalação 1.23.0

O export limpo de `fc76be76` está em
`C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.23.0-fc76be76`.
O marketplace ativo aponta para ele e o cache instalado é
`C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.23.0`.
O inventário com `Get-ChildItem -Force -Recurse -File` encontrou 801 arquivos
no export, 802 no cache, zero `.git`, zero ausentes ou SHA-256 divergentes nos
794 arquivos projetados, e somente a skill `source-command-saude` derivada
como extra. A sessão Codex `01a0cbba-023c-7ce1-a9a5-03d8434efb5c` carregou
`rainforest-mind:rainforest-mind`, permitiu `git status` e o pathspec
`git add -- "-A"`, negou `git add "-A"` e o wrapper, e retornou `deny` para JSON inválido.
T1–T5 fecharam `total=5 vermelhas:[1,2,3,4,5]`.

Próximo passo: `node scripts/estado.cjs exigir --slug 2026-09-12-multihost-sobre-1-11 --estagio revisar`, seguido de revisão
independente do diff contra `4301a205`. A referência piloto 1.7 permanece
em `c71ecd01a73ab9208c981ff2d1eea5f6378434d7`.

## Histórico não operacional — evidência 1.21.1

A entrega começou em versões anteriores e passou por reancoragens, diagnósticos
de instalação, correções de fixtures e repetições da contraprova. Essas rodadas
explicam o slug histórico `sobre-1-11`, mas não definem a retomada atual e não
devem ser repetidas. Os detalhes auditáveis continuam disponíveis no histórico
Git e nas seções explicitamente históricas do portão; este handover contém
somente o roteiro corrente de 1.23.0. A instalação 1.21.1 permanece preservada
no estado e no portão sob rótulo histórico explícito.
