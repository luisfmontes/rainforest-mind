# Handover Codex — Rainforest Mind multihost 1.23.3

## Ponto canônico de retomada — 2026-09-23

- Versão corrente: `1.23.3`, conforme os manifestos Claude e Codex.
- Base corrente: `9c05ee9a71b79d763a39f24195c580bc2d915752`
  (`origin/main`, 1.23.3).
- Merge da base na entrega:
  `06be3273c3ba08252ef8fd6d1417cb75fb38bfc4`.
- Base e merge 1.23.1 históricos: `2405f76aa8ae8847a16d66792686d1ec4b6cfee1`
  e `7be5f9e78a0294269218144f0b92bc0275e8f9b3`.
- Base e merge 1.23.0 históricos: `4301a205b9c90a101924cc60fdd2cb7b3bed4bfa`
  e `fc76be76b5f8dd5c3c9dac9016db33098abc5d94`.
- Base e merge históricos: `0e27956c14d52bd7efefdd343531ffbbb8811726`
  e `7febeface33c10de4f2b32395c3e0a595656857a`.
- Branch de entrega: `codex/multihost-1.13`.
- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`.
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`.
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`.
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`.
- Gemini continua adiado: nenhum manifesto, hook, adaptador ou fixture de
  payload Gemini pertence a esta entrega.
- `executar` permanece parcial: T1–T5 passaram suas mutações nesta base; T6
  ainda não tem a contraprova de bloqueio pelo `PreToolUse` em sessão nova.
  A tentativa de instalação 1.23.1 foi interrompida e é apenas histórica.
- Esta rodada termina com commit local na branch de entrega: sem push, PR,
  release, merge ou alteração da `main`.

Revalide o ponto corrente com:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git merge-base --is-ancestor 9c05ee9a71b79d763a39f24195c580bc2d915752 HEAD
git show HEAD:.claude-plugin/plugin.json
git show HEAD:.codex-plugin/plugin.json
node scripts/estado.cjs ler --slug 2026-09-12-multihost-sobre-1-11
```

Reexecute os cinco portões no PowerShell com o teto de P1 (`600000`
ms) configurado no processo pai do executor. O Git Bash em modo login fornece
os utilitários Unix de P1; `TMPDIR` fica em pasta gravável fora dos worktrees:

```powershell
New-Item -ItemType Directory -Force 'C:\Projetos\rainforest-mind\.claude\tmp-portoes-codex-1233'
$env:PATH = 'C:\Program Files\Git\bin;C:\Program Files\nodejs;' + $env:PATH
$env:CHERE_INVOKING = '1'
Remove-Item Env:BASH_ENV -ErrorAction SilentlyContinue
& 'C:\Program Files\Git\bin\bash.exe' -lc 'TMPDIR=/c/Projetos/rainforest-mind/.claude/tmp-portoes-codex-1233 node -p "process.env.TMPDIR"'
& 'C:\Program Files\Git\bin\bash.exe' -lc 'TMPDIR=/c/Projetos/rainforest-mind/.claude/tmp-portoes-codex-1233 PORTOES_TIMEOUT_MS=600000 node scripts/portoes.cjs rodar docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md --reverificar'
node scripts/portoes.cjs lint docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md --strict
node scripts/portoes.cjs status docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md
```

O shell de login pode substituir o `TMPDIR` herdado do PowerShell; a atribuição
dentro de `-lc` faz o processo Node receber o diretório gravável. Dentro de
uma sessão Git Bash de login, defina `TMPDIR=...` no próprio comando junto de
`PORTOES_TIMEOUT_MS=600000` antes de `node scripts/portoes.cjs rodar ...`.

## Evidência corrente de instalação 1.23.3 e pendência do host

O cachebuster `1.23.3+codex.20260923102218` foi instalado para a iteração
local. Depois da prova, os dois manifestos voltaram byte a byte ao HEAD:
Claude blob `5c8322b0500eaafe6cb6234ac97cd04cd7050c7d`, Codex blob
`0e465f7d48e1469b8e4dda410e36ecb27b700037`. O commit candidato de produto
é `ebb5ae58805d61b438573b6a3babbcfc8523ef83`.

`git archive HEAD` gerou o export limpo em
`C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.23.3-ebb5ae58`.
O marketplace ativo aponta para esse export, e o plugin instalado e habilitado
é `1.23.3` em
`C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.23.3`;
o cachebuster não é a instalação ativa. Os inventários
`Get-ChildItem -Force -Recurse -File` encontraram 801 arquivos no export, 802
no cache e zero `.git` em ambos. Na projeção D9, 794 arquivos têm SHA-256
idêntico, zero ausentes e zero divergentes. O único extra é o derivado D11
`.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, SHA-256
`321C30BCFDA44FF56AD53FCA7EF5C3B170987A3BD2BEE646152AF22AAF1DD339`.

A validação direta do adaptador instalado retornou `permissionDecision: deny`
para `git add "-A"`. No CLI, `/hooks` mostrou o `PreToolUse` instalado, ativo e
confiável, matcher `^Bash$` e comando do adaptador no cache correto. Porém as
sessões novas desta máquina não reproduziram `Command blocked by PreToolUse
hook`: a rota restrita falhou antes da criação do processo com `helper_unknown_error:
setup refresh had errors` (sessão `01a0cdda-425d-78c2-b710-6fb464074454`),
e a rota aprovada externa executou `git add` sem evento de hook. Essas saídas
não são vermelho do produto nem prova de T6. Retomar a contraprova em um host
cujo executor de shell dispare o hook, com fixture limpa e sem `.git/index.lock`;
até lá, não avançar para `revisar`.
`codex --version` mostrou `codex-cli 0.155.0-alpha.9.2`, mas o `session_meta`
da sessão diagnóstica registrou `cli_version 0.151.0`; o histórico que bloqueou
usava `0.153.4`. A divergência é hipótese de runtime, não diagnóstico fechado.

## Histórico de instalação 1.23.0 — não aceitar para 1.23.3

O export limpo de `fc76be76` está em
`C:\Projetos\rainforest-mind\.claude\marketplaces\rainforest-mind-export-1.23.0-fc76be76`.
Na medição histórica, o marketplace apontava para ele e o cache instalado era
`C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.23.0`.
O inventário com `Get-ChildItem -Force -Recurse -File` encontrou 801 arquivos
no export, 802 no cache, zero `.git`, zero ausentes ou SHA-256 divergentes nos
794 arquivos projetados, e somente a skill `source-command-saude` derivada
como extra. A sessão Codex `01a0cbba-023c-7ce1-a9a5-03d8434efb5c` carregou
`rainforest-mind:rainforest-mind`, permitiu `git status` e o pathspec
`git add -- "-A"`, negou `git add "-A"` e o wrapper, e retornou `deny` para JSON inválido.
T1–T5 fecharam `total=5 vermelhas:[1,2,3,4,5]`.

O próximo passo histórico era revisão independente do diff contra `4301a205`;
ele não vale para a reancoragem corrente. A referência piloto 1.7 permanece
em `c71ecd01a73ab9208c981ff2d1eea5f6378434d7`.

## Histórico não operacional — evidência 1.21.1

A entrega começou em versões anteriores e passou por reancoragens, diagnósticos
de instalação, correções de fixtures e repetições da contraprova. Essas rodadas
explicam o slug histórico `sobre-1-11`, mas não definem a retomada atual e não
devem ser repetidas. Os detalhes auditáveis continuam disponíveis no histórico
Git e nas seções explicitamente históricas do portão; este handover contém
somente o roteiro corrente de 1.23.3. A instalação 1.21.1 permanece preservada
no estado e no portão sob rótulo histórico explícito.
