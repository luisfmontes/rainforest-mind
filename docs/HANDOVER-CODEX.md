# Handover Codex — Rainforest Mind multihost 1.21.1

## Ponto canônico de retomada — 2026-09-22

- Versão corrente: `1.21.1`, conforme os manifestos Claude e Codex.
- Base corrente: `5cdb90e768cb1ba808821d5bdcdf46f7a19fc782`
  (`origin/main`, 1.21.1).
- Merge da base na entrega:
  `5d81ebcebf6ca0b6fd2a852cb1d227e1505b949a`.
- Branch de entrega: `codex/multihost-1.13`.
- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`.
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`.
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`.
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`.
- Gemini continua adiado: nenhum manifesto, hook, adaptador ou fixture de
  payload Gemini pertence a esta entrega.
- `executar` está `ok`, com 9/9 tarefas concluídas e a catraca T1–T9
  reaplicada na árvore integrada. O próximo estágio é uma nova revisão
  independente do diff final.
- Sem aval explícito do usuário, é proibido abrir PR, publicar release, mesclar
  ou alterar a `main`. Commit e push da branch de entrega não equivalem a merge.

Revalide o ponto corrente com:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git merge-base --is-ancestor 5cdb90e768cb1ba808821d5bdcdf46f7a19fc782 HEAD
git show HEAD:.claude-plugin/plugin.json
git show HEAD:.codex-plugin/plugin.json
node scripts/estado.cjs ler --slug 2026-09-12-multihost-sobre-1-11
```

## Evidência corrente de instalação 1.21.1

O export limpo foi produzido por `git archive` do commit
`f02843b91c2f7dd09aa2919b14e5713c5333a9ee`. Ele tem 783 arquivos; o cache
instalado tem 784. Ambos foram enumerados incluindo ocultos, não contêm `.git`
e declaram `1.21.1` nos manifestos Claude e Codex.

A projeção D9/D11 mediu 783 caminhos rastreados, excluiu somente os sete
documentos de governança e comparou os 776 arquivos de produto esperados:
zero ausente e zero divergente no export e no cache. Depois da mesma exclusão,
o único extra do cache é
`.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, a
projeção D11 autorizada.

Os contratos aplicáveis ao cache — manifesto, skills, adaptador e marketplace —
terminaram em exit 0. O contrato Gemini completo continua restrito à worktree
Git, porque depende de `git ls-files`. A bateria da branch foi executada pelo
Git Bash com Node disponível; uma tentativa anterior pelo WSL sem Node foi
inválida e não conta como teste de produto.

A sessão efêmera `01a0c90c-bbe6-7940-9011-e944d8d585ad`, na fixture
anonimizada `<fixture-host-owned>`, recebeu `hook: PreToolUse Blocked` ao tentar
`git add "-A"`. Depois da sessão, a fixture conservava `?? deny-control.txt`,
nada estava staged e não havia `.git/index.lock`.

A evidência literal completa permanece no portão do fluxo. O estado JSON mantém
as chaves canônicas `origem_instalacao`, `projecao_d9` e `contraprova_hook`
alinhadas a esta medição.

## Histórico não operacional

A entrega começou em versões anteriores e passou por reancoragens, diagnósticos
de instalação, correções de fixtures e repetições da contraprova. Essas rodadas
explicam o slug histórico `sobre-1-11`, mas não definem a retomada atual e não
devem ser repetidas. Os detalhes auditáveis continuam disponíveis no histórico
Git e nas seções explicitamente históricas do portão; este handover contém
somente o roteiro corrente de 1.21.1.
