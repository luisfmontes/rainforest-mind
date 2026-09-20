# Portão: adaptação multihost sobre o Rainforest Mind 1.13.2

## Tarefa 6 — iteração local com cachebuster

**Resultado final: OK na iteração 2.** A primeira sessão, no Codex `0.151.0`,
não recebeu a decisão `deny`; essa evidência vermelha foi preservada abaixo. A
repetição no Codex CLI `0.153.4`, primeiro com captura temporária e depois com o
adaptador original byte a byte, recusou `git add "-A"` no `PreToolUse` antes de
qualquer processo `git`. A tarefa 7 está liberada pela segunda evidência.

Nenhum push, merge, PR, release ou publicação foi executado. A branch `main`
não foi tocada.

### Base e worktree

Comando:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git branch --show-current
git status --short
git merge-base --is-ancestor bb1a82ed04fd3e769b4c9d3aa23afb468763b378 HEAD
```

Saída relevante (exit 0):

```text
<REPO>/.claude/worktrees/codex-task6-cachebuster-112
bb1a82ed04fd3e769b4c9d3aa23afb468763b378
codex/task6-cachebuster-112
merge-base-exit=0
```

### Nome e origem do marketplace

O nome foi lido pelo helper oficial, sem editar o marketplace à mão.

Comando:

```powershell
& '<USERPROFILE>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  '<USERPROFILE>\.codex\skills\.system\plugin-creator\scripts\read_marketplace_name.py' `
  --marketplace-path '.agents/plugins/marketplace.json'
```

Saída (exit 0):

```text
rainforest-mind-local
```

Antes da reconfiguração, `codex plugin marketplace list` mostrava:

```text
MARKETPLACE             ROOT
rainforest-mind-local   <REPO>\.claude\worktrees\codex-piloto-locked
```

E `codex plugin list` mostrava:

```text
rainforest-mind@rainforest-mind-local  installed, enabled  1.7.0  <REPO>\.claude\worktrees\codex-piloto-locked
```

Comandos de reconfiguração:

```powershell
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add '<REPO>\.claude\worktrees\codex-task6-cachebuster-112'
codex plugin marketplace list
```

Saída relevante:

```text
Removed marketplace `rainforest-mind-local`.
marketplace-remove-exit=0
Added marketplace `rainforest-mind-local` from <REPO>\.claude\worktrees\codex-task6-cachebuster-112.
Installed marketplace root: <REPO>\.claude\worktrees\codex-task6-cachebuster-112
marketplace-add-exit=0
MARKETPLACE             ROOT
rainforest-mind-local   <REPO>\.claude\worktrees\codex-task6-cachebuster-112
marketplace-list-exit=0
```

### Cachebuster temporário e instalação

Hashes e tamanhos antes da alteração temporária:

```text
f82abab1c71344dede681d73435d71beb52396cdfcfd307a06d804388d0e550b  .claude-plugin/plugin.json  (383 bytes)
13e79f46f0f505c8be03639ab778841ecff9ec2b2bf6965a7c2a943fe0636ccd  .codex-plugin/plugin.json  (923 bytes)
```

Versões antes:

```text
.claude-plugin/plugin.json=1.12.0
.codex-plugin/plugin.json=1.12.0
```

O cachebuster foi produzido pelo helper oficial:

```powershell
& '<USERPROFILE>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  '<USERPROFILE>\.codex\skills\.system\plugin-creator\scripts\update_plugin_cachebuster.py' '.'
```

Saída (exit 0):

```text
Updated plugin version: 1.12.0 -> 1.12.0+codex.20260913030812
```

Durante a instalação, os dois manifestos declaravam exatamente:

```text
.claude-plugin/plugin.json=1.12.0+codex.20260913030812
.codex-plugin/plugin.json=1.12.0+codex.20260913030812
```

Comando:

```powershell
codex plugin add rainforest-mind@rainforest-mind-local
```

Saída (exit 0):

```text
Added plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Installed plugin root: <USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913030812
```

`codex plugin list` confirmou:

```text
rainforest-mind@rainforest-mind-local  installed, enabled  1.12.0+codex.20260913030812  <REPO>\.claude\worktrees\codex-task6-cachebuster-112
```

Caminho real do cache:

```text
<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913030812
```

Versões lidas do cache:

```text
.claude-plugin/plugin.json=1.12.0+codex.20260913030812
.codex-plugin/plugin.json=1.12.0+codex.20260913030812
```

Hashes SHA-256 no cache:

```text
3aa473576ea06978854a4a6a070af4fcfec9a4754b2ad12644a850fa6822530f  .claude-plugin/plugin.json
adbf52d1bef94bb25737132ace9c30e8369cc789b9118949afa60efcf2a96c28  .codex-plugin/plugin.json
5288704159ef9d02556cc133467c2eaf2868cfb788f54e71d93d4c6cf5246277  hooks/codex-gate-staging-total.json
b831643f5d36d5ced5ea94f39a2d237f1520463486065bb5157e8d8a169908fe  hooks/codex-gate-staging-total.cjs
```

O inventário físico do cache contém 19 diretórios com `SKILL.md`:

```text
analisar
arqueologia
brainstorm
depurar
divergir
enxugar
executar
fechar
limpar
modo-dev
montar-corpus
plano
ponte
rainforest-mind
regua
revisar
semear
setup
verificar
COUNT=19
```

### Sessão Codex nova

Ambiente descartável:

```text
<USERPROFILE>\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
```

A primeira tentativa não iniciou a sessão porque a CLI `0.153.4` rejeitou a
combinação de opções que o próprio `--help` expõe separadamente:

```powershell
codex exec --ephemeral --approve-for-me --dangerously-bypass-hook-trust --color never -s workspace-write -C <repo-temporario> <prompt>
```

Saída (exit 1):

```text
error: the argument '--approve-for-me' cannot be used with '--sandbox <SANDBOX_MODE>'
```

A prova foi repetida sem `--sandbox`; `--approve-for-me` informou no cabeçalho
que a sessão usava `sandbox: workspace-write`. Comando:

```powershell
codex exec --ephemeral --approve-for-me --dangerously-bypass-hook-trust --color never -C '<USERPROFILE>\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847' '<prompt de enumeração e execução exata de git add "-A">'
```

A sessão iniciou com o seguinte cabeçalho:

```text
OpenAI Codex v0.151.0
workdir: <USERPROFILE>\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
model: gpt-5.6-sol
approval: on-request
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
```

A sessão enumerou estas 20 entradas `rainforest-mind:*` sem ler o plugin do
filesystem:

```text
rainforest-mind:analisar
rainforest-mind:arqueologia
rainforest-mind:brainstorm
rainforest-mind:depurar
rainforest-mind:divergir
rainforest-mind:enxugar
rainforest-mind:executar
rainforest-mind:fechar
rainforest-mind:limpar
rainforest-mind:modo-dev
rainforest-mind:montar-corpus
rainforest-mind:plano
rainforest-mind:ponte
rainforest-mind:rainforest-mind
rainforest-mind:regua
rainforest-mind:revisar
rainforest-mind:semear
rainforest-mind:setup
rainforest-mind:source-command-saude
rainforest-mind:verificar
COUNT=20
```

O cache físico tem 19 `skills/*/SKILL.md`, enquanto a sessão expôs 20 entradas.
A origem adicional de `rainforest-mind:source-command-saude` não foi inferida;
esta diferença permanece como lacuna a investigar fora da Tarefa 6.

### Divergência bloqueadora do hook

Ao tentar exatamente `git add "-A"`, a sessão registrou:

```text
hook: PreToolUse
hook: PreToolUse Completed
exec
"<USERPROFILE>\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\native\\powershell\\pwsh.exe" -Command 'git add "-A"' in <USERPROFILE>\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
exited 1 in 189ms:
fatal: Unable to create '<USERPROFILE>/AppData/Local/Temp/rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847/.git/index.lock': Permission denied
```

A conclusão literal da própria sessão foi:

```text
Não houve mensagem de recusa do hook: o processo `git` chegou a executar, mas falhou antes de concluir `git add`, ao tentar criar `.git/index.lock`. Código de saída: `1`.
```

O processo `codex exec` terminou com exit 0, mas o efeito requerido pelo plano
não ocorreu. O `deny` não pode ser substituído pela falha posterior do sandbox.

O registro carregado do cache era:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${PLUGIN_ROOT}/hooks/codex-gate-staging-total.cjs\""
          }
        ]
      }
    ]
  }
}
```

Portanto, a interface aceitou e executou um `PreToolUse`, mas o protocolo real
não produziu a decisão de recusa esperada pelo adaptador. A causa não foi
presumida nesta tarefa.

### Restauração da fonte

Depois da prova, os dois manifestos foram restaurados a `1.12.0`.

Hashes SHA-256 depois da restauração:

```text
f82abab1c71344dede681d73435d71beb52396cdfcfd307a06d804388d0e550b  .claude-plugin/plugin.json
13e79f46f0f505c8be03639ab778841ecff9ec2b2bf6965a7c2a943fe0636ccd  .codex-plugin/plugin.json
```

Comparação byte a byte contra as cópias capturadas antes da alteração:

```text
.claude-plugin/plugin.json byte-identical=True bytes=383
.codex-plugin/plugin.json byte-identical=True bytes=923
```

Versões finais da fonte:

```text
.claude-plugin/plugin.json=1.12.0
.codex-plugin/plugin.json=1.12.0
```

Observação operacional: o helper reserializou o manifesto Codex e escapou
caracteres Unicode durante a alteração temporária; a restauração final foi
validada pelos hashes originais, não apenas pelo campo `version`.

## Iteração 2 — prova no runtime Codex atual

### Diagnóstico da divergência anterior

O adaptador da iteração 1, o adaptador da branch de entrega e o adaptador
original usado nesta repetição têm o mesmo SHA-256:

```text
b831643f5d36d5ced5ea94f39a2d237f1520463486065bb5157e8d8a169908fe  hooks/codex-gate-staging-total.cjs
```

A sessão vermelha registrou `OpenAI Codex v0.151.0`; a repetição seguinte
registrou `OpenAI Codex v0.153.4`. Isso sugeriu provisoriamente uma diferença de
runtime, mas a reinstalação limpa da T7 voltou a executar `0.151.0` e bloqueou
corretamente os dois comandos proibidos com o mesmo adaptador. A contraprova
falsifica a hipótese de incompatibilidade: a causa ficou restrita ao estado da
primeira instalação/cache, que foi substituído pela reinstalação limpa.

### Payload real capturado

Uma instalação intermediária instrumentada, descartada depois do diagnóstico,
capturou o envelope real abaixo. Identificadores de sessão foram omitidos; os
campos que governam a decisão estão preservados:

```json
{
  "cwd": "<FIXTURE_HOOK112>",
  "hook_event_name": "PreToolUse",
  "permission_mode": "default",
  "tool_name": "Bash",
  "tool_input": {
    "command": "git add \"-A\""
  }
}
```

O adaptador respondeu com `hookSpecificOutput.hookEventName = "PreToolUse"`,
`permissionDecision = "deny"` e a razão produzida pelo núcleo compartilhado.
A sessão registrou `hook: PreToolUse Blocked`. Isso elimina as hipóteses de
matcher, caminho do comando, formato do payload e schema de decisão incorretos.
A instrumentação temporária foi removida integralmente e não entrou em commit.

### Reinstalação sem instrumentação

Para provar que a captura não alterava o resultado, o adaptador original foi
reinstalado com outro cachebuster:

```text
1.12.0+codex.20260913112347
<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913112347
```

Hashes relevantes dessa entrada de cache:

```text
b8442f616badb52de9e0d8f28a7c2e5feff8860e47748dcf499b517402054cf0  .claude-plugin/plugin.json
e1d594f34b166760ae2bb2f0d02a9127ff54d930703c46aa8a7b372219f23be1  .codex-plugin/plugin.json
5288704159ef9d02556cc133467c2eaf2868cfb788f54e71d93d4c6cf5246277  hooks/codex-gate-staging-total.json
b831643f5d36d5ced5ea94f39a2d237f1520463486065bb5157e8d8a169908fe  hooks/codex-gate-staging-total.cjs
```

Em um repositório descartável novo, a sessão `0.153.4` executou a chamada exata
uma única vez e produziu:

```text
hook: PreToolUse
Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
hook: PreToolUse Blocked
Resultado: o comando `git add "-A"` foi invocado uma única vez, mas bloqueado pelo gate de staging total do rainforest-mind antes da execução.
```

Não houve linha `exec` nem tentativa de criar `.git/index.lock`: a recusa veio
do hook, que é exatamente o efeito exigido pela tarefa 6.

### Contagem de skills

O cache físico final contém 19 diretórios `skills/*/SKILL.md`. A vigésima entrada
da enumeração, `rainforest-mind:source-command-saude`, deriva da migração de
compatibilidade que o Codex faz para `commands/saude.md`; ela não é uma vigésima
skill física nem uma cópia divergente do núcleo. Essa conclusão é uma inferência
apoiada pelo nome `source-command-saude`, pelo arquivo-fonte único
`commands/saude.md` e pela proveniência `migrated-command-skills` exposta pelo
próprio runtime.

### Restauração final da fonte

Os dois manifestos foram novamente restaurados pelas cópias binárias anteriores
ao cachebuster. Os hashes finais são idênticos aos da iteração 1:

```text
f82abab1c71344dede681d73435d71beb52396cdfcfd307a06d804388d0e550b  .claude-plugin/plugin.json
13e79f46f0f505c8be03639ab778841ecff9ec2b2bf6965a7c2a943fe0636ccd  .codex-plugin/plugin.json
```

Versão final da fonte: `1.12.0` nos dois manifestos. Nenhum push, merge, PR,
release, publicação ou alteração da `main` foi realizado.

## Tarefa 7 — reinstalação exata 1.12.0 e contrato ponta a ponta

### Veredito

**PENDENTE por um único critério estrutural.** A reinstalação exata e os
cinco comportamentos do runtime passaram, mas o conjunto literal de arquivos do
cache não é igual ao conjunto do commit: o commit tem 626 arquivos e o cache
tem 627. O arquivo adicional é uma projeção criada pelo Codex para o comando
migrado `saude`:

```text
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
sha256 321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
```

Nenhum dos 626 arquivos oriundos do commit falta ou diverge. Como a tarefa pede
igualdade do **conjunto**, e não apenas igualdade da projeção dos arquivos do
commit, a tarefa não foi contabilizada como concluída.

### Base isolada e divergência posterior da main

Comandos:

```powershell
git rev-parse HEAD
git branch --show-current
git show -s --format='%H %s' origin/main
git merge-base --is-ancestor origin/main HEAD
```

Saída:

```text
b24d2ec4a48372710e34925c93c843861807a47b
codex/task7-e2e-112
068468fb956b8d606e9af1800aaa91dd399fdeb8 Merge pull request #247 from luisfmontes/fluxo/zerar-issues-3
ancestor_exit=1
```

A `origin/main` avançou depois da base aprovada para esta tarefa. Por orientação
explícita do coordenador, a T7 validou o artefato isolado em `b24d2ec4...`, sem
rebasear nem alterar a branch de entrega ou a `main`.

### Fonte exata antes da instalação

```text
.claude-plugin/plugin.json version=1.12.0
.codex-plugin/plugin.json  version=1.12.0
f82abab1c71344dede681d73435d71beb52396cdfcfd307a06d804388d0e550b  .claude-plugin/plugin.json
13e79f46f0f505c8be03639ab778841ecff9ec2b2bf6965a7c2a943fe0636ccd  .codex-plugin/plugin.json
```

O helper oficial confirmou o nome do marketplace:

```powershell
& '<USERPROFILE>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  '<USERPROFILE>\.codex\skills\.system\plugin-creator\scripts\read_marketplace_name.py' `
  --marketplace-path '.agents\plugins\marketplace.json'
```

```text
rainforest-mind-local
```

### Remoção do cachebuster e reinstalação limpa

Comandos executados, nesta ordem:

```powershell
codex plugin remove rainforest-mind@rainforest-mind-local
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add '<REPO>\.claude\worktrees\codex-task7-e2e-112'
codex plugin add rainforest-mind@rainforest-mind-local
codex plugin marketplace list
codex plugin list
```

Saída relevante:

```text
Removed plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Removed marketplace `rainforest-mind-local`.
Added marketplace `rainforest-mind-local` from <REPO>\.claude\worktrees\codex-task7-e2e-112.
Installed marketplace root: <REPO>\.claude\worktrees\codex-task7-e2e-112
Added plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Installed plugin root: <USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0
rainforest-mind@rainforest-mind-local  installed, enabled  1.12.0  <REPO>\.claude\worktrees\codex-task7-e2e-112
```

### Varredura byte a byte do cache

A lista do commit veio de `git ls-tree -r --name-only HEAD`; a lista do cache
veio da enumeração recursiva de arquivos. Cada caminho rastreado foi comparado
por SHA-256 entre o worktree limpo e o cache. Por fim, foi calculado um SHA-256
agregado das linhas ordenadas `<caminho>\t<sha256>\n` para os 626 caminhos do
commit, tanto na fonte quanto na projeção correspondente do cache.

```text
tracked=626
cached=627
missing=0
different=0
extra=1
aggregate_source=7f16e3d0e536f0a8b7d741f4685b21998aeb6966d27086a45cb59261e35aa86b
aggregate_cache_projection=7f16e3d0e536f0a8b7d741f4685b21998aeb6966d27086a45cb59261e35aa86b
EXTRA .codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
```

Os manifestos no cache mantiveram a versão e os hashes da fonte:

```text
cache_versions claude=1.12.0 codex=1.12.0
f82abab1c71344dede681d73435d71beb52396cdfcfd307a06d804388d0e550b  .claude-plugin/plugin.json
13e79f46f0f505c8be03639ab778841ecff9ec2b2bf6965a7c2a943fe0636ccd  .codex-plugin/plugin.json
```

### Sessão Codex nova: skill, allow e deny

Runtime realmente executado:

```text
<USERPROFILE>\AppData\Local\OpenAI\Codex\bin\fd4c151a749f3ab4\codex.exe
codex-cli 0.151.0
OpenAI Codex v0.151.0
```

Esse resultado falsifica a inferência registrada na T6 de que o runtime
`0.151.0` seria incompatível com a decisão de bloqueio: nesta instalação exata,
o mesmo runtime bloqueou os dois comandos proibidos.

Em um repositório descartável, uma sessão nova recebeu um roteiro sem casos
opcionais. Ela leu explicitamente a skill instalada
`rainforest-mind:source-command-saude` e executou cada comando exato uma vez.
Marcadores e efeitos observados:

```text
SKILL_OK `node scripts/saude.cjs`

hook: PreToolUse
hook: PreToolUse Completed
exec ... -Command 'git status --short'
?? -A
?? denied-control.txt
STATUS_OK

hook: PreToolUse
hook: PreToolUse Completed
exec ... -Command 'git add -- "-A"'
PATHSPEC_OK

Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
hook: PreToolUse Blocked
TOTAL_DENY_OK

Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
Command: bash -c "git status; git add -A"
hook: PreToolUse Blocked
WRAPPER_DENY_OK
```

Na primeira sessão, o pathspec foi permitido pelo hook, mas o sandbox interno
barrou a criação de `.git/index.lock`. Para provar também a conclusão do Git,
uma segunda sessão nova, com acesso total limitado ao repositório descartável,
executou somente o mesmo comando:

```text
hook: PreToolUse
hook: PreToolUse Completed
exec ... -Command 'git add -- "-A"'
succeeded in 216ms
PATHSPEC_GIT_OK
```

O status posterior prova que apenas o arquivo chamado `-A` entrou no índice;
o arquivo-controle continuou fora dele:

```text
A  -A
?? denied-control.txt
```

### JSON malformado no adaptador instalado

O adaptador foi executado diretamente a partir do cache `1.12.0` com JSON
truncado contendo a sentinela `sentinela-malformado-t7`. A saída foi parseada e
os quatro campos foram verificados pelo processo chamador:

```text
exit=0
stderr_bytes=0
decision=deny
reason=Falha interna do gate de staging; comando recusado por seguranca.
secret_leaked=False
```

### Baterias locais e estado final da fonte

```powershell
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
```

As baterias terminaram verdes. A primeira nomeou 19 skills descobertas,
manifestos, adaptador, allow, deny, falha inesperada, falha de spawn, JSON
malformado, mutação do handler, marketplace e escopo negativo Gemini. A segunda
terminou com:

```text
ok: 5   falhou: 0
```

Depois de toda a prova, o worktree continuou com os dois manifestos exatamente
em `1.12.0` e com os hashes de fonte registrados acima. Nenhum cachebuster foi
criado nesta tarefa. Nenhum push, merge, PR, release, publicação, rebase ou
alteração da `main` foi realizado.

## Tarefa 6 reaberta — cachebuster sobre 1.13.2

Esta seção preserva integralmente as evidências históricas de 1.12 acima e
registra a repetição da T6 depois da reancoragem da entrega em 1.13.2.

### Base e isolamento

```powershell
git rev-parse HEAD
git branch --show-current
git merge-base --is-ancestor 068468fb956b8d606e9af1800aaa91dd399fdeb8 HEAD
```

```text
c614ae2d3d7ca8dee3f474cbe8701183b9a260b2
codex/task6-cachebuster-113
base_ancestor_exit=0
```

Worktree usado:

```text
<REPO>\.claude\worktrees\codex-task6-cachebuster-113
```

Nenhum rebase ou alteração foi feito na branch de entrega
`codex/multihost-1.13` ou na `main`.

### Âncoras binárias antes da mutação temporária

```text
claude_version=1.13.2
codex_version=1.13.2
76d1a40cdf0c228e921d5ddbc591d20391bc05f7eca291fcc33e04fd419f611f  .claude-plugin/plugin.json
91125f387b1b740c2948951dabe3014cbd34d21bf5dbc8da5068227d2a07b8cf  .codex-plugin/plugin.json
```

Antes de qualquer edição, os dois arquivos foram copiados em modo binário para
um diretório temporário único. Os hashes das cópias foram idênticos aos da
fonte acima.

O helper oficial validou o marketplace:

```powershell
& '<USERPROFILE>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  '<USERPROFILE>\.codex\skills\.system\plugin-creator\scripts\read_marketplace_name.py' `
  --marketplace-path '.agents\plugins\marketplace.json'
```

```text
rainforest-mind-local
```

### Marketplace apontado ao worktree desta iteração

```powershell
codex plugin remove rainforest-mind@rainforest-mind-local
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add '<REPO>\.claude\worktrees\codex-task6-cachebuster-113'
codex plugin marketplace list
```

```text
Removed plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Removed marketplace `rainforest-mind-local`.
Added marketplace `rainforest-mind-local` from <REPO>\.claude\worktrees\codex-task6-cachebuster-113.
Installed marketplace root: <REPO>\.claude\worktrees\codex-task6-cachebuster-113
rainforest-mind-local   <REPO>\.claude\worktrees\codex-task6-cachebuster-113
```

### Cachebuster oficial e cache criado

Comando:

```powershell
& '<USERPROFILE>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  '<USERPROFILE>\.codex\skills\.system\plugin-creator\scripts\update_plugin_cachebuster.py' `
  '<REPO>\.claude\worktrees\codex-task6-cachebuster-113'
```

```text
Updated plugin version: 1.13.2 -> 1.13.2+codex.20260913114653
```

O manifesto Claude foi temporariamente sincronizado para a mesma versão. Antes
da instalação, os dois manifestos informavam:

```text
claude_version=1.13.2+codex.20260913114653
codex_version=1.13.2+codex.20260913114653
86ae110feac7eabca7bea061049dd6fae8969c60449a5f19badc3c71480206e5  .claude-plugin/plugin.json
2fa142e81d537e8319e4df45f17df362d393832910c6de82ab6f868160b86c14  .codex-plugin/plugin.json
```

Instalação:

```powershell
codex plugin add rainforest-mind@rainforest-mind-local
codex plugin list
```

```text
Added plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Installed plugin root: <USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.13.2+codex.20260913114653
rainforest-mind@rainforest-mind-local  installed, enabled  1.13.2+codex.20260913114653  <REPO>\.claude\worktrees\codex-task6-cachebuster-113
```

Versões e hashes medidos diretamente nessa entrada de cache:

```text
cache_claude_version=1.13.2+codex.20260913114653
cache_codex_version=1.13.2+codex.20260913114653
86ae110feac7eabca7bea061049dd6fae8969c60449a5f19badc3c71480206e5  .claude-plugin/plugin.json
2fa142e81d537e8319e4df45f17df362d393832910c6de82ab6f868160b86c14  .codex-plugin/plugin.json
b831643f5d36d5ced5ea94f39a2d237f1520463486065bb5157e8d8a169908fe  hooks/codex-gate-staging-total.cjs
5288704159ef9d02556cc133467c2eaf2868cfb788f54e71d93d4c6cf5246277  hooks/codex-gate-staging-total.json
```

O cache continha 19 skills físicas em `skills/*/SKILL.md` e uma projeção
migrada:

```text
physical_skills=19
migrated_skills=1
source-command-saude
```

### Sessão Codex nova

Uma sessão efêmera `OpenAI Codex v0.151.0` foi aberta em um repositório
descartável com acesso total somente para eliminar falso vermelho do sandbox.
O repositório continha `deny-control.txt` não rastreado. O roteiro exigiu a
enumeração das skills realmente carregadas e uma única tentativa literal de
`git add "-A"`.

Enumeração devolvida pela sessão:

```text
rainforest-mind:analisar
rainforest-mind:arqueologia
rainforest-mind:brainstorm
rainforest-mind:depurar
rainforest-mind:divergir
rainforest-mind:enxugar
rainforest-mind:executar
rainforest-mind:fechar
rainforest-mind:limpar
rainforest-mind:modo-dev
rainforest-mind:montar-corpus
rainforest-mind:plano
rainforest-mind:ponte
rainforest-mind:rainforest-mind
rainforest-mind:regua
rainforest-mind:revisar
rainforest-mind:semear
rainforest-mind:setup
rainforest-mind:source-command-saude
rainforest-mind:verificar
TOTAL_RFM=20
```

Recusa real:

```text
Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
Command: git add "-A"
hook: PreToolUse Blocked
DENY_REAL_OK
```

Depois da sessão, `git status --short` ainda mostrou somente:

```text
?? deny-control.txt
```

Logo o comando não chegou ao Git e nenhum arquivo foi stageado.

### Restauração byte a byte e baterias

Os manifestos foram restaurados pelas cópias binárias capturadas antes do
cachebuster. A versão, os hashes e o diff específico depois da restauração foram:

```text
claude_version=1.13.2
codex_version=1.13.2
76d1a40cdf0c228e921d5ddbc591d20391bc05f7eca291fcc33e04fd419f611f  .claude-plugin/plugin.json
91125f387b1b740c2948951dabe3014cbd34d21bf5dbc8da5068227d2a07b8cf  .codex-plugin/plugin.json
MANIFEST_DIFF=<vazio>
```

Comandos de verificação posteriores:

```powershell
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
```

A primeira bateria terminou verde depois de validar as 19 skills físicas,
manifestos, adaptador, allow, deny, falhas seguras, mutação, marketplace e
escopo negativo Gemini. A segunda terminou:

```text
ok: 5   falhou: 0
```

Resultado da T6 reaberta: **verde**. O cachebuster existe somente no cache local;
nenhum byte dele permaneceu no diff da fonte. Nenhum push, merge, PR, release,
publicação, rebase ou alteração da `main` foi realizado.

## Tarefa 7 revisada — reinstalação exata 1.13.2

### Veredito

**VERDE, zero caso pulado.** Todos os 702 arquivos rastreados existem no cache
com SHA-256 idêntico. O cache contém 703 arquivos: o único extra é exatamente a
projeção Codex permitida em D11. A sessão nova provou skill invocável, os dois
allows, os dois denies e a falha fechada para JSON malformado.

### Base e fonte exata

```powershell
git rev-parse HEAD
git branch --show-current
git merge-base --is-ancestor 068468fb956b8d606e9af1800aaa91dd399fdeb8 HEAD
```

```text
9c1ee894c3302d78fcbf568ea267b4ef7780ad76
codex/task7-e2e-113
base_ancestor_exit=0
```

Worktree:

```text
<REPO>\.claude\worktrees\codex-task7-e2e-113
```

Antes da reinstalação, os manifestos já estavam na versão final exata e o
cache exato ainda não existia:

```text
claude_version=1.13.2
codex_version=1.13.2
exact_cache_before=False
76d1a40cdf0c228e921d5ddbc591d20391bc05f7eca291fcc33e04fd419f611f  .claude-plugin/plugin.json
91125f387b1b740c2948951dabe3014cbd34d21bf5dbc8da5068227d2a07b8cf  .codex-plugin/plugin.json
f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6  commands/saude.md
```

O helper oficial validou `rainforest-mind-local` como nome do marketplace.

### Reinstalação limpa

Comandos executados em ordem:

```powershell
codex plugin remove rainforest-mind@rainforest-mind-local
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add '<REPO>\.claude\worktrees\codex-task7-e2e-113'
codex plugin add rainforest-mind@rainforest-mind-local
codex plugin marketplace list
codex plugin list
```

```text
Removed plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Removed marketplace `rainforest-mind-local`.
Added marketplace `rainforest-mind-local` from <REPO>\.claude\worktrees\codex-task7-e2e-113.
Installed marketplace root: <REPO>\.claude\worktrees\codex-task7-e2e-113
Added plugin `rainforest-mind` from marketplace `rainforest-mind-local`.
Installed plugin root: <USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.13.2
rainforest-mind@rainforest-mind-local  installed, enabled  1.13.2  <REPO>\.claude\worktrees\codex-task7-e2e-113
```

### Todos os arquivos rastreados e whitelist de extras

A fonte veio de `git ls-tree -r --name-only HEAD`; o cache foi enumerado
recursivamente. Para cada caminho rastreado, os dois arquivos foram medidos por
SHA-256. O hash agregado usa linhas ordenadas
`<caminho>\t<sha256>\n` para os 702 caminhos da fonte e para a mesma projeção
no cache.

```text
tracked=702
cached=703
missing=0
different=0
extra=1
unexpected_extra=0
aggregate_source=5fd4319558ce9c5134a8f554d6f985dd1fae855977f645058dc41494d2733e6d
aggregate_cache_projection=5fd4319558ce9c5134a8f554d6f985dd1fae855977f645058dc41494d2733e6d
EXTRA .codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
WHITELIST_EXACT_OK
```

Proveniência e hashes do derivado:

```text
321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339  .codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6  cache/commands/saude.md
f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6  fonte/commands/saude.md
91125f387b1b740c2948951dabe3014cbd34d21bf5dbc8da5068227d2a07b8cf  cache/.codex-plugin/plugin.json
```

O derivado declara `name: "source-command-saude"`, informa que migra o source
command `saude` e preserva o template `Rode node scripts/saude.cjs e apresente o
resultado.`. O arquivo-fonte `commands/saude.md` também está no cache com o mesmo
hash da branch. Não existe nenhum segundo extra.

### Sessão Codex nova: cinco casos comportamentais

Uma sessão efêmera `OpenAI Codex v0.151.0` foi aberta com acesso total limitado
a um repositório descartável. O acesso total elimina a possibilidade de confundir
negação do sandbox com decisão do hook. O repositório começou com dois arquivos
não rastreados: `-A` e `denied-control.txt`.

O roteiro exigiu cada comando literal uma única vez, continuidade após as
recusas e um marcador por caso. Saída relevante:

```text
SKILL_OK `node scripts/saude.cjs`

hook: PreToolUse
hook: PreToolUse Completed
exec ... -Command 'git status --short'
?? -A
?? denied-control.txt
STATUS_OK

hook: PreToolUse
hook: PreToolUse Completed
exec ... -Command 'git add -- "-A"'
succeeded in 182ms
PATHSPEC_OK

Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
Command: git add "-A"
hook: PreToolUse Blocked
TOTAL_DENY_OK

Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
Comando: git add -A
Command: bash -c "git status; git add -A"
hook: PreToolUse Blocked
WRAPPER_DENY_OK

Nenhum caso foi pulado ou repetido.
```

Depois dos dois denies, o índice continha apenas o pathspec explicitamente
permitido; o controle permaneceu não rastreado:

```text
A  -A
?? denied-control.txt
```

Isso prova que nenhum dos dois comandos recusados chegou ao Git.

### JSON malformado no adaptador instalado

O adaptador do cache exato foi executado diretamente com JSON truncado contendo
a sentinela `sentinela-malformado-t7-113`. O processo chamador parseou a resposta
e conferiu decisão, canais e vazamento:

```text
exit=0
stderr_bytes=0
decision=deny
reason=Falha interna do gate de staging; comando recusado por seguranca.
secret_leaked=False
```

### Baterias e fonte final

```powershell
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
```

A primeira bateria terminou verde cobrindo 19 skills físicas, manifestos,
adaptador, allow, deny, falhas seguras, mutação, marketplace e Gemini adiado. A
segunda terminou:

```text
ok: 5   falhou: 0
```

Os manifestos nunca foram mutados nesta tarefa e continuam exatamente em
`1.13.2`, com os hashes registrados no início desta seção. O marketplace final
permanece apontado para o worktree isolado da T7 e o plugin instalado permanece
no cache exato `1.13.2`, aguardando integração.

Resultado da T7 revisada: **verde, 7/9**. Nenhum push, merge, PR, release,
publicação, rebase ou alteração da `main` ou da branch de entrega foi realizado.

## Tarefa 8 — handover factual da entrega 1.13.2

### Veredito

**VERDE.** `docs/HANDOVER-CODEX.md` foi criado porque não existia na base da
tarefa. Uma retomada por esse arquivo identifica o produto único, a entrega
real, a origem, as âncoras históricas, o rastro 1.11 → 1.12 → 1.13.2, a
evidência T6/T7, o adiamento de Gemini e a proibição de publicar sem aval.

### Base isolada e HEAD rederivável

```powershell
git rev-parse HEAD
git branch --show-current
git merge-base --is-ancestor 068468fb956b8d606e9af1800aaa91dd399fdeb8 HEAD
```

```text
810b0372df0f0ade2445645235d19dd261022550
codex/task8-handover-113
base_ancestor_exit=0
```

O handover registra `810b0372...` como âncora **anterior** à T8 e explica que
ela não é o HEAD final. O ponteiro corrente é deliberadamente rederivado com:

```powershell
git -C '<REPO>\.claude\worktrees\codex-multihost-1.11' rev-parse HEAD
```

Assim, o commit que adiciona o próprio handover não invalida a instrução de
retomada.

### Entrega, base e versões

Comandos:

```powershell
$entrega = '<REPO>\.claude\worktrees\codex-multihost-1.11'
$base = '068468fb956b8d606e9af1800aaa91dd399fdeb8'
Test-Path -LiteralPath $entrega
git -C $entrega branch --show-current
git -C $entrega rev-parse HEAD
git -C $entrega merge-base --is-ancestor $base HEAD
git -C $entrega cat-file -e "$base^{commit}"
git -C $entrega rev-parse origin/main
git -C $entrega show "$base`:.claude-plugin/plugin.json"
(Get-Content -Raw "$entrega\.claude-plugin\plugin.json" | ConvertFrom-Json).version
(Get-Content -Raw "$entrega\.codex-plugin\plugin.json" | ConvertFrom-Json).version
```

Saída relevante:

```text
exists=True
codex/multihost-1.13
810b0372df0f0ade2445645235d19dd261022550
base_ancestor_exit=0
base_cat_file_exit=0
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
base .claude-plugin/plugin.json version=1.13.2
delivery .claude-plugin/plugin.json version=1.13.2
delivery .codex-plugin/plugin.json version=1.13.2
```

### Caminhos do fluxo

Os caminhos foram avaliados com `Test-Path -LiteralPath` no worktree isolado da
T8, que contém o handover ainda não integrado:

```text
docs/HANDOVER-CODEX.md=True
docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md=True
docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md=True
docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json=True
docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md=True
docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md=True
```

### Piloto histórica

```powershell
$piloto = 'c71ecd01a73ab9208c981ff2d1eea5f6378434d7'
git -C $entrega cat-file -e "$piloto^{commit}"
git -C $entrega rev-parse codex/piloto-rainforest
git -C $entrega show "$piloto`:.claude-plugin/plugin.json"
```

```text
pilot_cat_file_exit=0
c71ecd01a73ab9208c981ff2d1eea5f6378434d7
pilot .claude-plugin/plugin.json version=1.7.0
```

O handover classifica esse commit exclusivamente como referência histórica,
nunca como base ou aceite da entrega 1.13.2.

### Contrato textual do handover

Uma verificação literal confirmou a presença de cada informação exigida:

```text
repo_unico=True
claude=True
codex=True
gemini_futuro=True
gemini_adiado=True
branch=True
worktree=True
base=True
base_version=True
head_anchor=True
head_dynamic=True
pilot=True
pilot_version=True
slug_history=True
t6=True
t7=True
no_publish=True
```

### Coerência com os números do portão

A conferência foi limitada ao bloco `## Tarefa 7 revisada` para não contar como
duplicata a evidência histórica 1.12. Cada marcador abaixo ocorreu exatamente
uma vez nesse bloco e coincide com o handover:

```text
tracked=702 => 1
cached=703 => 1
missing=0 => 1
different=0 => 1
extra=1 => 1
unexpected_extra=0 => 1
aggregate_source=5fd4319558ce9c5134a8f554d6f985dd1fae855977f645058dc41494d2733e6d => 1
WHITELIST_EXACT_OK => 1
SKILL_OK `node scripts/saude.cjs` => 1
PATHSPEC_OK => 1
TOTAL_DENY_OK => 1
WRAPPER_DENY_OK => 1
secret_leaked=False => 1
```

Antes da atualização do estado pela T8, o JSON confirmou
`tarefas_ok=7 tarefas=9`; depois desta entrega ele registra 8/9 e deixa somente
a T9 pendente.

### Limites preservados

Gemini continua adiado dentro do mesmo produto e repositório. A T8 não alterou
marketplace, cache ou outra configuração externa. Nenhum push, merge, PR,
release, publicação, rebase ou alteração da `main` ou da branch de entrega foi
realizado. A `main` só pode receber esta entrega depois de aval explícito do
usuário.

## Tarefa 9 — tentativa de fechamento local

### Veredito

**PENDENTE, permanece 8/9.** Quatro dos cinco comandos literais terminaram
verdes. O quinto saiu 1 porque a invocação declarada no plano não fornece
`--base`. A execução diagnóstica com `--base` e `--head` revelou ainda dois
mapas no diff sem tarefa correspondente. Nenhuma dessas divergências foi
reinterpretada ou corrigida durante a T9.

### Base, isolamento e Git Bash

```text
base/HEAD=f3a38ba9d862ec787b4637cc31341b27ab83136a
branch=codex/task9-final-113
worktree=<REPO>\.claude\worktrees\codex-task9-final-113
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
origin_main_ancestor_exit=0
```

O `bash.exe` descoberto primeiro no PATH era
`<BASH_EXE>`, launcher do WSL. Para evitar o falso vermelho
de ambiente já observado em Windows, esta bateria fixou explicitamente:

```powershell
Set-Alias -Name bash -Value '<GIT_HOME>\bin\bash.exe' -Scope Local
bash --version
```

```text
GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)
```

### Cinco comandos literais

Todos os comandos declarados pelo plano foram executados, sem pular o quinto
depois dos quatro verdes:

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11
```

Resultados:

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0

CMD2: manifesto, 19 skills, adaptador, allow/deny, falhas seguras, mutacao,
      marketplace e Gemini adiado verdes
cmd2_exit=0

CMD3: ok: 5   falhou: 0
cmd3_exit=0

CMD4: ok: cobertura válida — 11 decisão(ões), 9 tarefa(s)
cmd4_exit=0

CMD5: erro: falta --base
cmd5_exit=1

total=5 vermelhas=1
```

O quinto comando foi mantido literalmente como exigido; adicionar argumentos e
apresentar o resultado como se fosse essa mesma invocação apagaria o vermelho
do contrato.

### Diagnóstico suplementar do creep

Apenas para determinar se o problema era exclusivamente a interface do comando,
foram acrescentados os dois argumentos que o checker atual exige:

```powershell
node scripts/conferir-fluxo.cjs creep `
  --slug 2026-09-12-multihost-sobre-1-11 `
  --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 `
  --head f3a38ba9d862ec787b4637cc31341b27ab83136a
```

```text
RECUSADO: arquivo(s) no diff sem tarefa correspondente:
  docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md
  docs/rainforest/mapas/COBERTURA.md
Emendar o plano: adicione uma tarefa com campos arquivos: que cubra este(s) arquivo(s)
diagnostic_exit=2
```

Portanto, corrigir apenas os argumentos ainda não deixaria a T9 verde.

### Diff contra os caminhos autorizados

Comando:

```powershell
git diff --name-only 068468fb956b8d606e9af1800aaa91dd399fdeb8...HEAD
```

O diff contém 18 caminhos:

```text
.agents/plugins/marketplace.json
.codex-plugin/plugin.json
docs/HANDOVER-CODEX.md
docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json
docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/mapas/COBERTURA.md
docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md
hooks/codex-gate-staging-total.cjs
hooks/codex-gate-staging-total.json
scripts/testa-plugin-codex.cjs
scripts/testa-plugin-codex.sh
scripts/testa-versao.sh
skills/fechar/SKILL.md
skills/modo-dev/SKILL.md
skills/montar-corpus/SKILL.md
skills/regua/SKILL.md
```

As linhas `arquivos:` das nove tarefas enumeram 16 caminhos. Uma comparação
direta acrescenta design, plano e os dois mapas como não listados. O checker
oficial reconhece design e plano como rastro intrínseco, mas confirma como
creep os dois mapas mostrados no diagnóstico acima. Assim, a trava de escopo
também está vermelha.

### Branch, status e ausência operacional de publicação

Antes de registrar este portão, o worktree isolado estava limpo:

```text
codex/task9-final-113
f3a38ba9d862ec787b4637cc31341b27ab83136a
git status --short=<vazio>
```

A branch de entrega permaneceu no mesmo commit, com a modificação de estado
que já existia antes do despacho preservada:

```text
codex/multihost-1.13
f3a38ba9d862ec787b4637cc31341b27ab83136a
 M docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json
```

A `main` também permaneceu no mesmo commit e com sua sujeira anterior:

```text
main
068468fb956b8d606e9af1800aaa91dd399fdeb8
 M vigias/ERROS.md
?? cross-cutting-principles.md
?? skill-observations/
```

A evidência operacional desta T9 é o ledger de comandos executados acima e os
ponteiros Git inalterados; ocorrências textuais de `push`, `merge`, `PR` ou
`release` nos documentos são regras e comandos de exemplo, não execuções. Esta
tarefa não executou operação de push, merge, PR, release, publicação, rebase,
nem alterou configuração externa ou o plugin instalado.

Resultado: a execução não pode ser marcada `ok` nem 9/9 até o plano declarar a
interface correta do `creep` e cobrir os dois mapas. A proibição de publicar ou
mesclar na `main` sem aval explícito do usuário permanece integralmente ativa.

## Tarefa 9 — iteração 2 após correção do critério

### Veredito

**OK, 9/9.** A iteração 1 acima permanece como evidência histórica do contrato
vermelho. Nesta segunda iteração, o plano já traz a interface completa do
`creep` e inclui os dois mapas nos caminhos da tarefa 8. Os cinco comandos
literais terminaram com exit 0 e o checker confirmou os 18 caminhos cobertos.

### Base e isolamento

```text
base/HEAD=1340850bdf2b81afac13c1759b59f3cad724a17a
branch=codex/task9-final-113-i2
worktree=<REPO>\.claude\worktrees\codex-task9-final-113-i2
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
origin_main_ancestor_exit=0
git status --short=<vazio antes do registro do portão/estado>
```

No Windows, `<GIT_HOME>\bin\bash.exe` foi executado como shell de
login para disponibilizar os utilitários do Git for Windows. O preflight
confirmou `/usr/bin/dirname`, `/usr/bin/mktemp`, `/usr/bin/grep`,
`/mingw64/bin/git` e o Node instalado. Duas tentativas anteriores à bateria
válida foram descartadas como falha de bootstrap: a primeira não tinha
`/usr/bin` no PATH; a segunda já tinha os utilitários, mas o sandbox recusou a
caixa efêmera em `%TEMP%`. A execução válida abaixo recebeu acesso somente para
o teste criar e remover essa caixa temporária; nenhuma configuração persistente
foi alterada.

### Cinco comandos literais — execução válida

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0

CMD2: manifesto, 19 skills, adaptador, allow/deny, falhas seguras, mutacao,
      marketplace e Gemini adiado verdes
cmd2_exit=0

CMD3: ok: 5   falhou: 0
cmd3_exit=0

CMD4: ok: cobertura válida — 11 decisão(ões), 9 tarefa(s)
cmd4_exit=0

CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0

total=5 vermelhas=0
```

### Escopo do diff

`git diff --name-only 068468fb956b8d606e9af1800aaa91dd399fdeb8...HEAD`
retornou estes 18 caminhos:

```text
.agents/plugins/marketplace.json
.codex-plugin/plugin.json
docs/HANDOVER-CODEX.md
docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json
docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/mapas/COBERTURA.md
docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md
hooks/codex-gate-staging-total.cjs
hooks/codex-gate-staging-total.json
scripts/testa-plugin-codex.cjs
scripts/testa-plugin-codex.sh
scripts/testa-versao.sh
skills/fechar/SKILL.md
skills/modo-dev/SKILL.md
skills/montar-corpus/SKILL.md
skills/regua/SKILL.md
```

O resultado literal `ok: sem creep — 18 arquivo(s) coberto(s)` valida esse
conjunto contra as nove tarefas do plano corrigido, incluindo os dois mapas na
tarefa 8 e o design/plano como rastro intrínseco do fluxo.

### Estado e ausência operacional de publicação

O estado foi fechado por `scripts/estado.cjs` com `executar.status = ok`,
`tarefas_ok = 9`, `tarefas = 9`, carimbo da tarefa 9 na base desta iteração,
comando/saída da bateria e a matriz de mutação das nove tarefas. O próximo
estágio informado foi `revisar`.

A branch de entrega permaneceu em `codex/multihost-1.13` no commit
`1340850bdf2b81afac13c1759b59f3cad724a17a`; a `main` permaneceu em
`068468fb956b8d606e9af1800aaa91dd399fdeb8`. Nesta iteração não houve push,
merge, PR, release, publicação, rebase, alteração de configuração externa ou
mudança no plugin instalado. Ocorrências desses termos nos documentos são
regras e exemplos, não comandos executados. A entrega continua aguardando aval
explícito do usuário antes de qualquer publicação ou mesclagem na `main`.

## Tarefa 9 — iteração 3, correção dos achados da revisão

### Veredito

**OK, executar permanece 9/9.** A revisão anterior sobre
`a4ff25e212905d9422bbe873ff380f71a34e2fca` encontrou dois problemas: o
handover ainda prescrevia uma T9 pendente e a prova do cache não delimitava a
projeção D9 contra o HEAD documental final. Nesta iteração, o handover foi
atualizado e a projeção fechada passou. O estágio `revisar` permanece
`reprovado` até uma nova revisão independente; o próximo estágio é `revisar`.

### Base e isolamento

```text
base/HEAD=f51168147d15f1bafff538c4f4e9595fb977cd2f
branch=codex/task9-final-113-i3
worktree=<REPO>\.claude\worktrees\codex-task9-final-113-i3
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
origin_main_ancestor_exit=0
review_head_exists_exit=0
```

### Projeção D9 do cache instalado 1.13.2

`codex plugin list` confirmou o plugin instalado e habilitado em `1.13.2`. A
entrada medida, sem reinstalação ou mudança de configuração, foi:

```text
<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.13.2
cache_claude_version=1.13.2
cache_codex_version=1.13.2
```

O inventário da fonte veio de `git ls-tree -r --name-only HEAD`. Foram
excluídos exatamente estes sete documentos de governança, tanto do conjunto
esperado quanto da classificação de extras do cache:

```text
docs/HANDOVER-CODEX.md
docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json
docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md
docs/rainforest/mapas/COBERTURA.md
```

Para cada arquivo restante, `Get-FileHash -Algorithm SHA256` comparou a fonte
no HEAD com o caminho correspondente no cache:

```text
tracked_total=703
governance_excluded=7
projection_expected=696
cache_total=703
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
```

O único extra é a projeção D11 gerada pelo host. Origem e hashes medidos:

```text
derived_path=.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
derived_sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_path=commands/saude.md
origin_sha256=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
```

O frontmatter do derivado declara `name: "source-command-saude"` e seu corpo
informa que migra o comando-fonte `saude`, corroborando a origem sem criar uma
segunda fonte versionada.

### Cinco comandos literais

Executados com `<GIT_HOME>\bin\bash.exe` como shell de login e uma
caixa efêmera em `%TEMP%`:

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0
CMD2: contrato Codex completo verde
cmd2_exit=0
CMD3: ok: 5   falhou: 0
cmd3_exit=0
CMD4: ok: cobertura válida — 11 decisão(ões), 9 tarefa(s)
cmd4_exit=0
CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0
total=5 vermelhas=0
```

### Escopo, estado e ausência de publicação

`git diff --name-only 068468fb956b8d606e9af1800aaa91dd399fdeb8...HEAD`
retornou 18 caminhos, e o `creep` literal confirmou todos cobertos pelas nove
tarefas. Antes dos três registros autorizados desta iteração, o worktree estava
limpo; seu diff local ficou restrito a `docs/HANDOVER-CODEX.md`, ao estado e a
este portão.

O estado recebeu o carimbo da tarefa 9, iteração 3, na base
`f51168147d15f1bafff538c4f4e9595fb977cd2f`, mantém `executar.status = ok`,
`tarefas_ok = 9` de `9`, registra a bateria e a projeção D9, e preserva
`revisar.status = reprovado` com os dois achados anteriores até nova revisão.

Não houve push, merge, PR, release, publicação, rebase, reinstalação, mudança no
plugin instalado ou alteração de configuração externa. A branch de entrega e a
`main` não foram alteradas. Menções documentais a essas operações são regras e
evidência, não comandos executados. A proibição de publicar ou mesclar na
`main` sem aval explícito do usuário permanece ativa.

## Tarefa 9 — iteração 4, handover coerente com a integração

### Veredito

**OK, executar permanece 9/9.** O commit da T9, iteração 3,
`f51168147d15f1bafff538c4f4e9595fb977cd2f`, já é ancestral do HEAD. A
instrução residual para integrá-lo foi removida do handover, cujo próximo passo
agora é diretamente uma nova revisão independente. O estágio `revisar`
permanece `reprovado` até essa revisão acontecer.

### Base e ancestralidade

```text
worktree=<REPO>/.claude/worktrees/codex-multihost-1.11
branch=codex/multihost-1.13
base/HEAD=46fcf099bad98c1a89cd8cdde62e12c93aed46c1
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
f511681_ancestor_exit=0
estado_exigir_exit=0
```

### Projeção D9/D11 do cache instalado 1.13.2

Sem reinstalação ou alteração de configuração, a projeção do HEAD excluiu
exatamente os sete documentos de governança definidos pela D9 e comparou os
arquivos restantes por SHA-256 contra o cache `1.13.2`:

```text
cache_claude_version=1.13.2
cache_codex_version=1.13.2
tracked_total=703
governance_excluded=7
projection_expected=696
cache_total=703
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
derived_sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_sha256=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
```

O único extra continua sendo a projeção D11 autorizada, derivada de
`commands/saude.md`.

### Cinco comandos literais

Executados uma única vez, em sequência, com
`<GIT_HOME>\bin\bash.exe` como alias `bash` local ao processo:

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0
CMD2: contrato Codex completo verde
cmd2_exit=0
CMD3: ok: 5   falhou: 0
cmd3_exit=0
CMD4: ok: cobertura válida — 11 decisão(ões), 9 tarefa(s)
cmd4_exit=0
CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0
total=5 vermelhas=0
```

### Handover, estado e ausência de publicação

O handover não manda mais integrar nem repetir a T9. Ele registra que
`f51168147d15f1bafff538c4f4e9595fb977cd2f` é ancestral do HEAD e encaminha a
retomada diretamente para `revisar`. O estado registra a T9 iteração 4,
`executar.status = ok`, `tarefas_ok = 9` de `9`, e conserva
`revisar.status = reprovado` até uma nova revisão independente.

Nenhum push, merge, PR, release, publicação, rebase, reinstalação, mudança no
plugin instalado ou alteração de configuração externa foi executado. A `main`
não foi tocada e continua protegida pela exigência de aval explícito do usuário.

## Tarefa 9 — iteração 5, histórico das revisões

### Veredito

**OK, executar permanece 9/9.** O handover agora distingue as duas tentativas
anteriores: a primeira, sobre `a4ff25e212905d9422bbe873ff380f71a34e2fca`,
levantou dois achados tratados na T9 i3; a seguinte, sobre
`4b153ced395d96d3dbd885ea5b77f75ffacb323a`, deixou um único achado residual,
tratado na T9 i4. O próximo passo continua sendo uma nova revisão independente,
e `revisar` permanece `reprovado` até ela acontecer.

### Base e estado reaberto

```text
worktree=<REPO>/.claude/worktrees/codex-multihost-1.11
branch=codex/multihost-1.13
base/HEAD=44ac4c2a02fe7aaf66518c6934afc618ba2a39e1
origin/main=068468fb956b8d606e9af1800aaa91dd399fdeb8
revisar.status=reprovado
revisar.tentativas=3
```

A terceira revisão reabriu `executar` exclusivamente porque o resumo inicial
do handover chamava a revisão de `a4ff25e...` de “anterior” e omitia a tentativa
posterior em `4b153ced...` com seu achado residual.

### Projeção D9/D11 do cache instalado 1.13.2

```text
tracked_total=703
governance_excluded=7
projection_expected=696
cache_total=703
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
derived_sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_sha256=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
```

O único extra continua sendo a projeção D11 autorizada, derivada de
`commands/saude.md`.

### Cinco comandos literais

Executados uma única vez, em sequência, com Git Bash como alias local ao
processo:

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0
CMD2: contrato Codex completo verde
cmd2_exit=0
CMD3: ok: 5   falhou: 0
cmd3_exit=0
CMD4: ok: cobertura válida — 11 decisão(ões), 9 tarefa(s)
cmd4_exit=0
CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0
total=5 vermelhas=0
```

### Estado e ausência de publicação

O estado recebeu o quinto carimbo da T9, mantém `executar.status = ok` e
`tarefas_ok = 9` de `9`, e preserva `revisar.status = reprovado` até nova
revisão. O handover aponta diretamente para esse próximo estágio.

Nenhum push, merge, PR, release, publicação, rebase, reinstalação, mudança no
plugin instalado ou alteração de configuração externa foi executado. A `main`
não foi tocada e continua protegida pela exigência de aval explícito do usuário.

## Tarefa 7 — iteração 3, instalação a partir de export limpo

### Veredito

**OK.** A causa do P1 foi corrigida na origem, não escondida por uma nova
exceção: instalar diretamente de clone ou worktree copia metadados `.git` para
o cache. O marketplace ativo aponta agora para um export limpo do commit
`77b0226e6b168f97848d5fa8021d58c06dda8f6f`, produzido por `git archive`.

### Origem ativa

```text
MARKETPLACE             ROOT
rainforest-mind-local   <REPO>\.claude\marketplaces\rainforest-mind-export-1.13.2
marketplace_list_exit=0

rainforest-mind@rainforest-mind-local  installed, enabled  1.13.2  <REPO>\.claude\marketplaces\rainforest-mind-export-1.13.2
plugin_list_exit=0
```

### Export contra commit e cache completo

Todos os inventários de filesystem usaram
`Get-ChildItem -Force -Recurse -File`. Cada arquivo do export foi comparado ao
blob correspondente do HEAD, e cada arquivo instalado foi comparado por
SHA-256 ao export:

```text
head=77b0226e6b168f97848d5fa8021d58c06dda8f6f
tracked_total=703
export_total_force=703
export_dotgit_exists=False
export_missing=0
export_different=0
export_extra=0
cache_total_force=704
cache_dotgit_exists=False
cache_missing=0
cache_different=0
cache_extra=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
derived_sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_sha256=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
```

O cache contém os 703 arquivos do export, inclusive ocultos, e somente a
projeção D11 como extra. Não há `.git` no export nem no cache. A allowlist D9
permanece com os mesmos sete documentos de governança e D11 continua aceitando
um único derivado.

## Tarefa 9 — iteração 6, fechamento após a correção causal

### Decisão registrada e projeção final

A D12 formaliza o export limpo do commit candidato como origem da instalação
local verificável. As tarefas 7 e 9 agora exigem inventário com `-Force` e
ausência de `.git`; cobertura e critério foram fortalecidos sem afrouxar D9 ou
D11.

Projetando o cache completo contra o HEAD e excluindo somente os sete documentos
de governança:

```text
tracked_total=703
governance_excluded=7
projection_expected=696
cache_total_force=704
export_dotgit_exists=False
cache_dotgit_exists=False
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
```

### Cinco comandos literais

Executados uma única vez, em sequência, com Git Bash como alias local ao
processo:

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0
CMD2: contrato Codex completo verde
cmd2_exit=0
CMD3: ok: 5   falhou: 0
cmd3_exit=0
CMD4: ok: cobertura válida — 12 decisão(ões), 9 tarefa(s)
cmd4_exit=0
CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0
total=5 vermelhas=0
```

### Estado e ausência de publicação

O estado registra uma nova iteração da T7 e a T9 iteração 6 na base
`77b0226e6b168f97848d5fa8021d58c06dda8f6f`, mantém `executar.status = ok` e
`tarefas_ok = 9` de `9`, e preserva `revisar.status = reprovado` até nova
revisão independente.

Nenhum push, merge, PR, release, publicação, rebase, mudança na `main` ou nova
alteração de configuração externa foi executado durante esta formalização. A
reconfiguração para o export e a reinstalação exata foram feitas antes desta
execução e são a origem factual medida acima.

## Tarefa 9 — iteração 7, retomada fail-closed

### Veredito

**OK, executar permanece 9/9.** A retomada agora resolve e normaliza para
Windows tanto `$entrega` quanto `git rev-parse --show-toplevel`, compara os
caminhos com `OrdinalIgnoreCase` e só depois consulta branch, HEAD e
ancestralidade. Diretório ausente, falha de resolução ou top-level diferente
abortam claramente; nenhum desses casos pode subir até o repositório pai e
validar a `main`.

### Prova da retomada

```text
retomada_top_level=<REPO>\.claude\worktrees\codex-multihost-1.11
branch=codex/multihost-1.13
head=f9339f475f317b01761d1f0176af505b833c57ef
base_ancestral=True
ausente=ABORTO: worktree de entrega ausente ou não é diretório: <REPO>\.claude\worktrees\nao-existe
subdiretorio=ABORTO: top-level Git inesperado; esperado='<REPO>\.claude\worktrees\codex-multihost-1.11\docs'; obtido='<REPO>\.claude\worktrees\codex-multihost-1.11'
```

### Projeção D9/D11 com ocultos

```text
tracked_total=703
governance_excluded=7
projection_expected=696
cache_total_force=704
export_dotgit_exists=False
cache_dotgit_exists=False
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
EXIT=0
```

### Cinco comandos literais

Executados em sequência. O runner recebeu `/usr/bi<GIT_BIN>` explicitamente e a
bateria que cria fixtures temporários foi executada fora do sandbox restrito;
duas tentativas preparatórias anteriores não mediram o produto porque o ambiente
não oferecia `dirname`/`mktemp` e depois recusou a criação dos fixtures em
`%TEMP%`.

```powershell
bash hooks/testa-gate-staging-total.sh
bash scripts/testa-plugin-codex.sh
bash scripts/testa-versao.sh
node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-multihost-sobre-1-11 --base 068468fb956b8d606e9af1800aaa91dd399fdeb8 --head HEAD
```

```text
CMD1: == resultado: 106 ok, 0 falha(s) ==
cmd1_exit=0
CMD2: ok Gemini adiado: caminhos rastreados nao contem manifesto, hook, adaptador ou fixture de payload Gemini fora dos documentos do fluxo
cmd2_exit=0
CMD3: ok: 5   falhou: 0
cmd3_exit=0
CMD4: ok: cobertura válida — 12 decisão(ões), 9 tarefa(s)
cmd4_exit=0
CMD5: ok: sem creep — 18 arquivo(s) coberto(s)
cmd5_exit=0
total=5 vermelhas=0
```

### Estado e ausência de publicação

O estado registra a T9 iteração 7 na base
`f9339f475f317b01761d1f0176af505b833c57ef`, fecha novamente
`executar.status = ok` com `9/9` e mantém `revisar.status = reprovado` até nova
revisão independente.

Nenhum push, merge, PR, release, publicação, rebase, reinstalação, mudança na
`main` ou alteração de configuração externa foi executado.

## Tarefa 6/7 — iteração 8, contraprova do hook em fixture host-owned (2026-09-19)

### Veredito

**OK.** A reprovação de `verificar` era falso vermelho de ambiente: a fixture
anterior pertencia ao usuário `CodexSandboxOffline`, `git rev-parse --git-dir`
saía 128 por `dubious ownership` e o núcleo tratava o diretório como fora de
Git. Repetida em fixture de propriedade do usuário corrente, a sessão Codex nova
recebeu `deny` do hook **antes** de o Git rodar, nas duas instalações medidas:
o export diagnóstico e, depois, o export limpo `1.13.2` que é a entrega.

### Fixture e estado de controle

```text
fixture=<USERPROFILE>\.codex\visualizations\2026\09\08\01a07ef1-6e62-7301-b14c-e07018b98ed6\t6-cachebuster-session-host
git rev-parse --git-dir -> .git (exit 0)
git status --short (antes) -> ?? deny-control.txt
.git/index.lock (antes) -> ausente
```

### Prova 1 — plugin diagnóstico `1.13.2+codex.20260915000908`

Comando:

```text
codex exec --ephemeral --approve-for-me --dangerously-bypass-hook-trust --color never -C <fixture> '<prompt de execução literal de git add "-A">'
```

Saída literal da sessão (`session id: 01a0b9a5-8533-77b3-8fae-7aa60a3b3433`):

```text
hook: PreToolUse
2026-09-19T12:30:34.594634Z ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.

Comando: git add -A
Repo: <USERPROFILE>/.codex/visualizations/2026/09/08/01a07ef1-6e62-7301-b14c-e07018b98ed6/t6-cachebuster-session-host
Quem: janela principal
...
O que o comando pegaria AGORA (git status --porcelain):
  ?? deny-control.txt
...
hook: PreToolUse Blocked
```

Conclusão literal da própria sessão:

```text
Código de saída: não foi produzido; o hook bloqueou o comando antes da execução. O executor reportou `Script failed`.
```

Diagnóstico do núcleo na mesma execução:

```text
{"stage":"start","cwd":"...t6-cachebuster-session-host","toolName":"Bash","command":"git add \"-A\""}
{"stage":"config","gateLigado":true}
{"stage":"motivo","motivo":"git add -A","dirC":null,"indiceSegmento":0}
{"stage":"gitdir","dir":"...t6-cachebuster-session-host","gitDir":".git"}
```

`git-error-diagnostic.jsonl` **não cresceu** (2 linhas antes e depois): o
`dubious ownership` não reapareceu. A única entrada de erro ali continua sendo
a da fixture antiga `t6-cachebuster-session` (sem `-host`).

Estado após a prova — o bloqueio foi efetivo, não uma falha posterior do Git:

```text
git status --short   -> ?? deny-control.txt
git diff --cached --name-only -> (vazio)
.git/index.lock      -> ausente
```

### Restauração da instalação final

```powershell
codex plugin remove rainforest-mind@rainforest-mind-local        # exit 0
codex plugin marketplace remove rainforest-mind-local            # exit 0
codex plugin marketplace add '...\rainforest-mind-export-1.13.2' # exit 0
codex plugin add rainforest-mind@rainforest-mind-local           # exit 0
```

```text
MARKETPLACE             ROOT
rainforest-mind-local   <REPO>\.claude\marketplaces\rainforest-mind-export-1.13.2
marketplace_list_exit=0

rainforest-mind@rainforest-mind-local  installed, enabled  1.13.2
plugin_list_exit=0
plugin_root=<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.13.2
```

O export permanece válido para o HEAD corrente: o diff de
`77b0226e6b168f97848d5fa8021d58c06dda8f6f` até `d1cfe613c806042da1a4bc4dfd8b3f18524bbd07` toca
exatamente cinco caminhos, todos dentro da lista fechada de governança da D9
(`docs/HANDOVER-CODEX.md`, design, plano, estado e portão). Nenhum arquivo de
produto mudou, portanto nenhuma reancoragem do export é devida.

### Prova 2 — instalação final limpa `1.13.2`

Mesma fixture, mesma forma de comando, com a instalação que é a entrega:

```text
COUNT=20        (19 skills físicas + a projeção D11 source-command-saude)
hook: PreToolUse
2026-09-19T12:35:21.312231Z ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
hook: PreToolUse Blocked
```

Conclusão literal da sessão:

```text
Código de saída: não produzido/informado, pois o hook impediu que o processo fosse iniciado.
```

O único `PreToolUse Completed` desta sessão foi de um `Get-Content` alheio ao
teste; o `git add "-A"` recebeu `Blocked`. Estado após a prova:

```text
git status --short   -> ?? deny-control.txt
git diff --cached --name-only -> (vazio)
.git/index.lock      -> ausente
```

Os arquivos `*-diagnostic.jsonl` **não cresceram** nesta segunda sessão
(22 e 52 linhas antes e depois), como esperado: o export limpo não carrega a
instrumentação de diagnóstico. A prova do bloqueio aqui é a saída da própria
sessão, não o log.

### Projeção D9/D11 com ocultos, contra o HEAD corrente

Inventário recursivo incluindo arquivos ocultos, comparação por blob SHA-1 do
Git (bytes literais, sem filtro de EOL) e SHA-256 dos extras:

```text
head=d1cfe613c806042da1a4bc4dfd8b3f18524bbd07
tracked_total=703
governance_excluded=7
projection_expected=696
export_source_commit=77b0226e6b168f97848d5fa8021d58c06dda8f6f
export_tracked_total=703
export_total_force=703
export_dotgit_exists=false
export_missing=0
export_different=0
export_extra=0
cache_total_force=704
cache_dotgit_exists=false
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md  sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_sha256(commands/saude.md)=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
EXIT=0
```

Números idênticos aos das iterações 6 e 7, agora reproduzidos contra o HEAD
corrente. Nenhuma exceção nova foi adicionada à D9 ou à D11.

### Baterias

Na worktree versionada:

```text
CMD1 bash hooks/testa-gate-staging-total.sh
     == resultado: 106 ok, 0 falha(s) ==                                  cmd1_exit=0
CMD2 bash scripts/testa-plugin-codex.sh
     ok Gemini adiado: caminhos rastreados nao contem manifesto, hook,
     adaptador ou fixture de payload Gemini fora dos documentos do fluxo  cmd2_exit=0
CMD3 bash scripts/testa-versao.sh
     ok: 5   falhou: 0                                                    cmd3_exit=0
CMD4 node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-multihost-sobre-1-11
     ok: cobertura válida — 12 decisão(ões), 9 tarefa(s)                  cmd4_exit=0
CMD5 node scripts/conferir-fluxo.cjs creep --slug ... --base 068468fb... --head HEAD
     ok: sem creep — 18 arquivo(s) coberto(s)                             cmd5_exit=0
total=5 vermelhas=0
```

Contra o cache instalado, somente os modos aplicáveis — o modo Gemini chama
`git ls-files` e um export não é repositório, portanto continua rodando só na
worktree versionada:

```text
node scripts/testa-plugin-codex.cjs --contrato-manifesto        exit=0
node scripts/testa-plugin-codex.cjs --contrato-skills           exit=0  (19 skills)
node scripts/testa-plugin-codex.cjs --contrato-adaptador-hook   exit=0
node scripts/testa-plugin-codex.cjs --contrato-marketplace      exit=0
```

### Mutação nesta iteração, e por que a lista de 2026-09-14 continua valendo

`catraca_mutacao` permanece em `2026-09-14`: o campo registra quando
`exigir --estagio executar` armou a catraca, não quando os mutantes foram
exercitados. Uma primeira gravação desta iteração o moveu para `2026-09-19` por
leitura errada do campo e foi corrigida; o comportamento do gate é idêntico nos
dois valores, porque ambos são posteriores a `FIXTURE_EXIGIDA_DESDE`
(`2026-08-23`), mas o registro estava falso.

A lista de mutantes foi herdada sem alteração, e isso é deliberado: a árvore de
produto é byte a byte a mesma do HEAD em que eles rodaram. De
`52245a7fd0e7c6f7a74dd56b6a7310bd1fb753cc` até aqui mudaram somente documentos
da lista fechada de governança da D9 — nenhum arquivo que um mutante alcança.
Refazer a bateria de mutação mediria exatamente os mesmos bytes.

Além disso, o mutante da T3 **foi** reexercitado nesta iteração, porque
`scripts/testa-plugin-codex.sh` o executa dentro do modo
`--contrato-adaptador-hook`:

```text
ok mutacao handler Codex -> core direto: vermelho e bytes restaurados
```

### Distância até a `origin/main`

Fato registrado aqui porque muda o que `fechar` vai custar, não porque mude esta
entrega:

```text
git ls-remote --heads origin codex/multihost-1.13   -> (vazio; a branch nunca foi enviada)
git rev-list --count HEAD..origin/main              -> 185
origin/main .claude-plugin/plugin.json              -> 1.19.1
base desta entrega (068468fb)                       -> 1.13.2
```

A base continua ancestral do HEAD e a entrega continua correta sobre ela, mas a
`origin/main` avançou seis versões menores desde o ancoramento. Qualquer
integração futura exige repetir a análise de sobreposição e reancoragem que o
handover já condiciona — não é trabalho desta sessão nem do estágio `verificar`.

### Projeção reconferida no HEAD entregue

```text
head=a8fcfd6f18755d2d25b4993b4a16533af03362c0
tracked_total=703
cache_total_force=704
missing_count=0
sha_divergent_count=0
extra_count=1
```

Idêntica à medição feita em `d1cfe613`, como a D9 prevê. O script que produz
esses números foi escrito no scratchpad da sessão e **não** é versionado; ele
compara o blob SHA-1 do Git contra os bytes em disco em vez de reidratar o blob
por redirecionamento de shell, porque no PowerShell 5.1 redirecionar saída
binária de executável nativo re-codifica o conteúdo e falsearia o hash. A
concordância com o método das iterações 6 e 7, que era outro, é parte da
evidência.

### Ausência de publicação

Nenhum push, merge, PR, release, publicação, rebase, mudança na `main` ou
remoção de worktree foi executado. A fixture, o export diagnóstico e os logs de
`visualizations` foram preservados como evidência. `revisar` e `verificar`
permanecem intocados nesta sessão: a revisão final independente e a verificação
ficam com o Codex, conforme a divisão do handover.

## Reancoragem na `origin/main` 1.19.2 — iteração 9 (2026-09-19)

### Por que a âncora mudou

A entrega nasceu sobre `068468fb956b8d606e9af1800aaa91dd399fdeb8`, versão
`1.13.2`. Entre aquele ponto e hoje a `main` andou 188 commits e seis versões
menores, até `2adbae270782a5a36512c28a5c2a5354ba05c73e`, versão `1.19.2`. O
handover proíbe trocar a âncora sem repetir a análise de sobreposição; ela foi
feita antes do merge e está registrada abaixo.

### Análise de sobreposição

A `main` **não encosta em nenhum dos oito arquivos de produto** da adaptação
Codex — eles simplesmente não existem lá:

```text
.codex-plugin/plugin.json          ausente na main
.agents/plugins/marketplace.json   ausente na main
hooks/codex-gate-staging-total.cjs ausente na main
hooks/codex-gate-staging-total.json ausente na main
scripts/testa-plugin-codex.cjs     ausente na main
scripts/testa-plugin-codex.sh      ausente na main
scripts/testa-versao.sh            0 commits da main desde a base
docs/rainforest/mapas/COBERTURA.md 0 commits da main desde a base
```

Dos quatro `SKILL.md` que a entrega toca, a `main` mexeu em dois — `fechar`
(quatro para seis passos) e `modo-dev`. Como a entrega só altera o
**frontmatter** desses arquivos e a `main` só altera o **corpo**, os dois lados
sobrevivem ao merge. Conferido no arquivo mesclado, não presumido: `fechar`
ficou com a `description` entre aspas da entrega e com os seis passos da `main`.

Isso é a D10 funcionando. A adaptação foi reaplicada como diff mínimo em vez de
merge da piloto, e foi por isso que atravessou 188 commits sem conflito.

### O que a reancoragem quebrou, e por quê

Merge textual limpo não é entrega verde. Medido rodando as baterias numa árvore
de merge descartável, antes de tocar na branch:

```text
testa-versao.sh        FALHA manifesto Codex na mesma versao da fonte Claude
                       (esperava '1.19.1', veio '1.13.2')     -> 4 ok, 1 falha
testa-plugin-codex.sh  FALHA version Codex diverge do manifesto Claude
testa-plugin-codex.sh  FALHA corpo fechar diverge da ancora binaria: 9986 bytes
testa-plugin-codex.sh  FALHA corpo modo-dev diverge da ancora binaria: 13414 bytes
conferir-fluxo creep   exit 2 com a base velha: 188 commits da main sem cobertura
```

Nenhuma dessas é defeito. O teste de versão existe para impedir que dois hosts
sejam instalados com bytes diferentes, e as âncoras existem para provar que a
entrega normalizou frontmatter sem tocar em corpo. Os três gates gritaram
exatamente no que foram construídos para pegar.

### Os consertos, um por gate

**Manifesto Codex → `1.19.2`.** Só o valor do campo; a formatação do arquivo
ficou intacta.

**Âncoras de `fechar` e `modo-dev` → os corpos da `main`.** A âncora não
descreve o que a entrega escreveu; descreve o que ela **não** tocou. O valor
certo é portanto sempre o da `main`, e foi verificado lendo os blobs de
`origin/main` direto do Git, sem passar pelo disco:

```text
BATE    fechar         ancora=9986B   origin/main=9986B
BATE    modo-dev       ancora=13414B  origin/main=13414B
BATE    montar-corpus  ancora=2935B   origin/main=2935B   (sem frontmatter na main)
BATE    regua          ancora=13394B  origin/main=13394B
```

`montar-corpus` e `regua` não precisaram de nada: a `main` não os alterou.

**Base do `creep` → `2adbae27`.** A lista de arquivos declarada no plano
**não** precisou de reescrita: com a base nova ela fecha nos mesmos 18 arquivos.

### Baterias na base reancorada

```text
CMD1 bash hooks/testa-gate-staging-total.sh
     == resultado: 133 ok, 0 falha(s) ==                        cmd1_exit=0
CMD2 bash scripts/testa-plugin-codex.sh
     contrato Codex completo, Gemini adiado                     cmd2_exit=0
CMD3 bash scripts/testa-versao.sh
     ok: 5   falhou: 0                                          cmd3_exit=0
CMD4 node scripts/conferir-fluxo.cjs cobertura --slug ...
     ok: cobertura válida — 12 decisão(ões), 9 tarefa(s)        cmd4_exit=0
CMD5 node scripts/conferir-fluxo.cjs creep --slug ... --base 2adbae27 --head HEAD
     ok: sem creep — 18 arquivo(s) coberto(s)                   cmd5_exit=0
total=5 vermelhas=0
```

O gate passou de 106 para 133 casos: 27 vieram da própria `main`.

### Evidência de instalação, refeita

A evidência anterior provava a árvore `1.13.2` e deixou de valer no instante em
que a versão mudou. Export novo por `git archive` a partir do commit candidato
`eabeb898706cf9160e72e45d534162dcfa30b6d8`, em
`<REPO>\.claude\marketplaces\rainforest-mind-export-1.19.2`:

```text
codex plugin remove rainforest-mind@rainforest-mind-local        # exit 0
codex plugin marketplace remove rainforest-mind-local            # exit 0
codex plugin marketplace add '...\rainforest-mind-export-1.19.2' # exit 0
codex plugin add rainforest-mind@rainforest-mind-local           # exit 0

rainforest-mind@rainforest-mind-local  installed, enabled  1.19.2
plugin_root=<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.19.2
```

Projeção D9/D11 com arquivos ocultos, contra o commit candidato:

```text
head=eabeb898706cf9160e72e45d534162dcfa30b6d8
tracked_total=765
governance_excluded=7
projection_expected=758
export_source_commit=eabeb898706cf9160e72e45d534162dcfa30b6d8
export_tracked_total=765
export_total_force=765
export_dotgit_exists=false
export_missing=0
export_different=0
export_extra=0
cache_total_force=766
cache_dotgit_exists=false
missing_count=0
sha_divergent_count=0
extra_count=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md  sha256=321c30bcfda44ff56ad53fca7ef5c3b170987a3bd2bee646152af22aaf1dd339
origin_sha256(commands/saude.md)=f044c166ccbfaca6470e4090229011354b82d4007adc80a278581a6565f6a6f6
EXIT=0
```

Os totais subiram de 703/704 para 765/766 porque a `main` trouxe 62 arquivos
novos. A estrutura da prova não mudou: zero `.git`, zero ausente, zero
divergente e o mesmo extra D11 único, com os mesmos dois SHA-256 — a `main` não
tocou em `commands/saude.md`.

### Contraprova do hook, refeita na 1.19.2

Mesma fixture host-owned, mesma forma de comando, agora contra a instalação
`1.19.2` (`session id: 01a0bb99-1f24-7310-bc4a-689613d1589e`):

```text
COUNT=20
hook: PreToolUse
2026-09-19T21:36:20.730558Z ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: BLOQUEADO pelo gate de staging total do rainforest-mind.
hook: PreToolUse Blocked
```

Conclusão literal da sessão:

```text
Código de saída: `N/A` — processo não iniciado.
```

Estado da fixture depois:

```text
git status --short            -> ?? deny-control.txt
git diff --cached --name-only -> (vazio)
.git/index.lock               -> ausente
```

### Escopo que ficou de fora, de propósito

A `main` acrescentou dois ganchos ao `hooks/hooks.json` do Claude que o
adaptador Codex não recebe: `portaria.cjs` em `PreToolUse` com matcher
`Task|Agent`, e `titulo-sessao-end.cjs` em `Stop`. O adaptador continua
declarando um único gancho, `PreToolUse`/`^Bash$`, como a decisão de design
original determina — e essa decisão é anterior aos dois ganchos existirem.

Não é regressão: nada que a entrega provava deixou de valer. É escopo novo, e
foi **plantado como ideia** (`hooks-novos-da-main-no-adaptador-codex`) em vez de
emendado aqui, porque alargar reabriria uma execução já fechada. A ideia carrega
o gancho de retorno e a observação de que
`ok hook seletivo Codex: PreToolUse/Bash, 1 adaptador` vira mentira no dia em
que um segundo adaptador entrar.

### Modos aplicáveis contra o cache 1.19.2

O modo Gemini continua rodando só na worktree versionada, porque chama
`git ls-files` e um export não é repositório. Os quatro aplicáveis, dentro de
`<USERPROFILE>\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.19.2`:

```text
node scripts/testa-plugin-codex.cjs --contrato-manifesto       exit=0  ok skills compartilhadas descobertas: 19
node scripts/testa-plugin-codex.cjs --contrato-skills          exit=0  ok frontmatter Codex: 19 skills descobertas dinamicamente
node scripts/testa-plugin-codex.cjs --contrato-adaptador-hook  exit=0  ok mutacao handler Codex -> core direto: vermelho e bytes restaurados
node scripts/testa-plugin-codex.cjs --contrato-marketplace     exit=0  ok marketplace rainforest-mind: source.path ./ resolve a raiz com manifestos Claude e Codex
```

### Mensagem errada no commit de merge

O commit de merge `1cd74a2ee1f565c2d026199d3f9aa1a4ac18b73e` diz na mensagem
"origin/main 1.19.1" e "185 commits". A ponta efetivamente mesclada foi
`2adbae270782a5a36512c28a5c2a5354ba05c73e`, versão `1.19.2`, 188 commits: a
`main` andou três commits entre a medição da análise de sobreposição e o merge,
e o merge pegou a ponta corrente, que é o comportamento certo. O commit não foi
reescrito porque já estava publicado na branch. Quem ler o `git log` deve
derivar a base com `git merge-base`/`git rev-parse`, não da prosa da mensagem.

### Nota sobre a análise de sobreposição e a base medida

A análise que autorizou a troca de âncora foi feita contra
`95e0b7bc786978ff230e5248faf8b9ace5bbc88c` (1.19.1) e o merge consumiu
`2adbae27` (1.19.2). Os três commits de diferença foram cobertos pela
revalidação: as âncoras foram conferidas contra os blobs de `origin/main` **na
ponta mesclada**, e as cinco baterias, a projeção D9/D11 e a contraprova do
hook rodaram todas depois do merge, sobre a árvore final. Nenhuma conclusão
desta iteração repousa sobre a medição feita em 1.19.1.
### Ausência de publicação

Nenhum merge na `main`, PR, release ou alteração da `main`. A branch de entrega
foi commitada e enviada para o `origin`, o que o usuário esclareceu em
2026-09-19 estar liberado — o veto sempre foi a `main`, não o push. A fixture,
os exports anteriores e os logs de `visualizations` foram preservados.
`revisar` e `verificar` continuam com o Codex.

## Tarefa 6/9 — iteração 10, correções da revisão em 1.19.2

Data: 2026-09-20.

### Cachebuster refeito sobre a versão corrente

O helper oficial do `plugin-creator` preservou o prefixo e produziu uma única
sufixação de desenvolvimento:

```text
Updated plugin version: 1.19.2 -> 1.19.2+codex.20260920005618
marketplace=rainforest-mind-local
installed_version=1.19.2+codex.20260920005618
```

O marketplace foi apontado temporariamente para `<REPO>/.claude/worktrees/codex-multihost-1.11`
somente durante a prova. Uma sessão nova e efêmera, na fixture host-owned sob
`<USERPROFILE>/.codex/visualizations/.../t6-cachebuster-session-host`, informou:

```text
COUNT=20
hook: PreToolUse
Command blocked by PreToolUse hook
hook: PreToolUse Blocked
```

O comando `git add "-A"` foi tentado uma vez. Depois da sessão:

```text
git status --short            -> ?? deny-control.txt
git diff --cached --name-only -> (vazio)
.git/index.lock               -> ausente
```

Os dois manifestos foram restaurados byte a byte para `1.19.2`. O contrato
Gemini ganhou a contraprova `test/fixtures/gemini/request.json`: antes da
correção, `--contrato-gemini` saiu 1 com `detector Gemini deixou passar`; depois,
saiu 0. `referencias/gemini/request-for-comments.md` permanece permitido.

Re-verificar:

```powershell
node scripts/testa-plugin-codex.cjs --contrato-gemini
node scripts/testa-plugin-codex.cjs --contrato-manifesto
git diff --exit-code -- .claude-plugin/plugin.json .codex-plugin/plugin.json
```

### Instalação final exata depois das correções

O commit candidato `68dbcf6e3493084f3faa6a41a5a3e012c6281bbb` foi exportado por
`git archive` para `<export-clean-1.19.2-reviewfix-68dbcf6e>`. O marketplace
temporário da T6 foi removido e o plugin foi reinstalado desse export:

```text
installed_version=1.19.2
export_total_force=765
cache_total_force=766
export_dotgit=false
cache_dotgit=false
```

A projeção excluiu somente os sete documentos de governança da D9 e comparou
blob Git → export → cache:

```text
tracked_total=765
governance_excluded=7
expected=758
export_missing=0
export_different=0
cache_missing=0
cache_different=0
extras=1
.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md
```

Contra o cache instalado, `--contrato-manifesto`, `--contrato-skills`,
`--contrato-adaptador-hook` e `--contrato-marketplace` terminaram em exit 0.
O contrato Gemini roda na árvore versionada porque depende de `git ls-files`.

A mutação T4 sobre a versão corrigida também fechou pelo motivo esperado:

```text
baseline: 1.19.2 == 1.19.2 -> 5 ok, 0 falhas
mutação:  1.19.3 != 1.19.2 -> 4 ok, 1 falha
```

A declaração de mutação da T3 passou a representar as aspas escapadas do JSON;
trocar o adaptador pelo core casou uma ocorrência e produziu
`FALHA handler Codex chama core direto`.
