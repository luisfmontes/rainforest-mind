# Handover Codex — Rainforest Mind multihost 1.13.2

Atualizado em 2026-09-14. Este documento retoma a entrega local que adapta o
Rainforest Mind ao Codex sem bifurcar o produto.

## Resultado corrente

O Rainforest Mind continua sendo **um único repositório e um único plugin** para
Claude, Codex e o futuro Gemini. O núcleo, as skills e as políticas são
compartilhados; cada host recebe somente o adaptador fino necessário. Nesta
entrega, Claude e Codex estão comprovados. Gemini permanece explicitamente adiado:
nenhum manifesto, hook ou payload Gemini foi criado.

A versão entregue e instalada localmente é `1.13.2`. A execução das nove
tarefas está verde (`9/9`). A revisão anterior, feita sobre
`a4ff25e212905d9422bbe873ff380f71a34e2fca`, foi reprovada por dois achados:
o handover ainda descrevia a T9 como pendente e a igualdade do cache ainda não
estava delimitada pela projeção D9. Ambos foram tratados na T9, iteração 3. O
próximo estágio é **revisar novamente**; até essa nova revisão, o estado de
`revisar` permanece `reprovado`.

## Retomada segura

O worktree de entrega continua com o nome histórico `codex-multihost-1.11`, mas
a branch real é `codex/multihost-1.13`:

```powershell
$entrega = 'C:\Projetos\rainforest-mind\.claude\worktrees\codex-multihost-1.11'
Test-Path -LiteralPath $entrega
git -C $entrega branch --show-current
git -C $entrega rev-parse HEAD
git -C $entrega merge-base --is-ancestor origin/main HEAD
```

`git rev-parse HEAD` é a fonte de verdade para o HEAD corrente. Antes da T8, a
branch estava em `810b0372df0f0ade2445645235d19dd261022550`, commit que integra
a T7 verde. **Esse hash é uma âncora de entrada, não o HEAD final congelado:** o
commit da própria T8 e sua integração necessariamente produzirão um descendente.

Confirme também que a base permanece ancestral e que os dois manifestos têm a
versão esperada:

```powershell
$base = '068468fb956b8d606e9af1800aaa91dd399fdeb8'
git -C $entrega cat-file -e "$base^{commit}"
git -C $entrega show "$base`:.claude-plugin/plugin.json" |
  Select-String '"version": "1.13.2"'
(Get-Content -Raw "$entrega\.claude-plugin\plugin.json" | ConvertFrom-Json).version
(Get-Content -Raw "$entrega\.codex-plugin\plugin.json" | ConvertFrom-Json).version
```

A base desta entrega é `origin/main` em
`068468fb956b8d606e9af1800aaa91dd399fdeb8`, versão `1.13.2`. Não substitua essa
âncora por um hash mais novo sem repetir a análise de sobreposição e reancoragem.

## Documentos do fluxo

O slug conserva `1-11` porque o trabalho começou sobre 1.11, passou por 1.12 e
foi entregue sobre 1.13.2:

- Design: `docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md`
- Plano: `docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md`
- Estado: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`
- Portão: `docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md`
- Mapa: `docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md`

Valide os caminhos no worktree de entrega:

```powershell
@(
  'docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json',
  'docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md'
) | ForEach-Object { "$_=$(Test-Path -LiteralPath (Join-Path $entrega $_))" }
```

## Evidência que importa

A T6 reaberta instalou o cachebuster
`1.13.2+codex.20260913114653`, enumerou 19 skills físicas mais a projeção
`source-command-saude` e bloqueou `git add "-A"` em uma sessão Codex nova. Os
dois manifestos foram restaurados byte a byte para `1.13.2`.

A T7 fez uma reinstalação limpa da versão exata `1.13.2` e terminou verde, sem
casos pulados:

- 702 arquivos rastreados presentes no cache, zero ausentes e zero SHA-256
  divergentes;
- agregado fonte/cache:
  `5fd4319558ce9c5134a8f554d6f985dd1fae855977f645058dc41494d2733e6d`;
- único extra permitido:
  `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, SHA-256
  `321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339`,
  derivado de `commands/saude.md`, SHA-256
  `f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6`;
- skill instalada invocável;
- `git status --short` e `git add -- "-A"` permitidos;
- `git add "-A"` e `bash -c "git status; git add -A"` negados pelo hook;
- JSON malformado recusado com `deny`, stderr vazio e sem vazamento;
- `scripts/testa-plugin-codex.sh` verde e `scripts/testa-versao.sh` em 5/5.

As saídas completas, caminhos de cache, hashes e comandos estão no portão do
fluxo. Não promova o resumo acima no lugar da evidência primária.

Na T9, iteração 3, o cache instalado `1.13.2` foi comparado novamente contra o
HEAD usando a projeção fechada pela D9. Dos 703 arquivos rastreados, foram
excluídos exatamente os sete documentos de governança; os 696 arquivos de
produto restantes tiveram zero ausente e zero SHA-256 divergente. Após aplicar
a mesma exclusão ao inventário do cache, o único extra foi:

- `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md`, SHA-256
  `321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339`;
- origem `commands/saude.md`, SHA-256
  `f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6`.

Essa é a projeção D11 gerada pelo host; não é uma segunda fonte versionada.

## Piloto histórica

A branch `codex/piloto-rainforest`, commit
`c71ecd01a73ab9208c981ff2d1eea5f6378434d7`, pertence à piloto `1.7.0`. Ela é
referência histórica de arquitetura e não é base, aceite ou artefato instalável
da entrega 1.13.2.

Validação:

```powershell
$piloto = 'c71ecd01a73ab9208c981ff2d1eea5f6378434d7'
git -C $entrega cat-file -e "$piloto^{commit}"
git -C $entrega show "$piloto`:.claude-plugin/plugin.json" |
  Select-String '"version": "1.7.0"'
```

## Próximo passo: nova revisão

A T9, iteração 3, já está integrada: `f51168147d15f1bafff538c4f4e9595fb977cd2f`
é ancestral do HEAD corrente. Siga diretamente para uma nova execução
independente do estágio `revisar`, contra o diff real desde
`068468fb956b8d606e9af1800aaa91dd399fdeb8`. A execução já está fechada em
`9/9`; não integre nem repita a T9 como passo prescritivo de retomada. A revisão
deve confirmar especialmente os dois achados anteriores agora tratados: a
projeção D9/D11 do cache e este handover coerente com o estado.

Antes de remover qualquer worktree auxiliar, confirme com `codex plugin list`
qual caminho sustenta o marketplace/cache ativo e reaponte-o para a entrega se
necessário. A configuração externa não foi alterada pela T8.

## Proibição de publicação

Esta entrega permanece local. **Não execute push, merge na `main`, PR, release
ou qualquer publicação sem aval explícito do usuário.** Aprovações anteriores
para continuar a execução local não autorizam publicar nem alterar a `main`.
