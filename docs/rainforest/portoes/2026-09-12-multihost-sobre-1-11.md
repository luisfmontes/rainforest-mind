# Portão: adaptação multihost sobre o Rainforest Mind 1.12

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
C:/Projetos/rainforest-mind/.claude/worktrees/codex-task6-cachebuster-112
bb1a82ed04fd3e769b4c9d3aa23afb468763b378
codex/task6-cachebuster-112
merge-base-exit=0
```

### Nome e origem do marketplace

O nome foi lido pelo helper oficial, sem editar o marketplace à mão.

Comando:

```powershell
& 'C:\Users\Luis\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  'C:\Users\Luis\.codex\skills\.system\plugin-creator\scripts\read_marketplace_name.py' `
  --marketplace-path '.agents/plugins/marketplace.json'
```

Saída (exit 0):

```text
rainforest-mind-local
```

Antes da reconfiguração, `codex plugin marketplace list` mostrava:

```text
MARKETPLACE             ROOT
rainforest-mind-local   C:\Projetos\rainforest-mind\.claude\worktrees\codex-piloto-locked
```

E `codex plugin list` mostrava:

```text
rainforest-mind@rainforest-mind-local  installed, enabled  1.7.0  C:\Projetos\rainforest-mind\.claude\worktrees\codex-piloto-locked
```

Comandos de reconfiguração:

```powershell
codex plugin marketplace remove rainforest-mind-local
codex plugin marketplace add 'C:\Projetos\rainforest-mind\.claude\worktrees\codex-task6-cachebuster-112'
codex plugin marketplace list
```

Saída relevante:

```text
Removed marketplace `rainforest-mind-local`.
marketplace-remove-exit=0
Added marketplace `rainforest-mind-local` from \\?\C:\Projetos\rainforest-mind\.claude\worktrees\codex-task6-cachebuster-112.
Installed marketplace root: C:\Projetos\rainforest-mind\.claude\worktrees\codex-task6-cachebuster-112
marketplace-add-exit=0
MARKETPLACE             ROOT
rainforest-mind-local   C:\Projetos\rainforest-mind\.claude\worktrees\codex-task6-cachebuster-112
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
& 'C:\Users\Luis\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  'C:\Users\Luis\.codex\skills\.system\plugin-creator\scripts\update_plugin_cachebuster.py' '.'
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
Installed plugin root: C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913030812
```

`codex plugin list` confirmou:

```text
rainforest-mind@rainforest-mind-local  installed, enabled  1.12.0+codex.20260913030812  C:\Projetos\rainforest-mind\.claude\worktrees\codex-task6-cachebuster-112
```

Caminho real do cache:

```text
C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913030812
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
C:\Users\Luis\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
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
codex exec --ephemeral --approve-for-me --dangerously-bypass-hook-trust --color never -C 'C:\Users\Luis\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847' '<prompt de enumeração e execução exata de git add "-A">'
```

A sessão iniciou com o seguinte cabeçalho:

```text
OpenAI Codex v0.151.0
workdir: C:\Users\Luis\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
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
"C:\\Users\\Luis\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\native\\powershell\\pwsh.exe" -Command 'git add "-A"' in C:\Users\Luis\AppData\Local\Temp\rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847
exited 1 in 189ms:
fatal: Unable to create 'C:/Users/Luis/AppData/Local/Temp/rainforest-task6-session-e29f3e9d14c64a84876170e7dd4c9847/.git/index.lock': Permission denied
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

A diferença observável relevante foi o runtime. A sessão vermelha registrou
`OpenAI Codex v0.151.0`; a sessão final registrou `OpenAI Codex v0.153.4` e a
CLI usada respondeu `codex-cli 0.153.4`. Não houve correção de código: o
protocolo emitido pelo plugin é válido para o runtime atual. A explicação mais
forte para o vermelho anterior é incompatibilidade do protocolo de bloqueio no
runtime `0.151.0`; ela permanece marcada como inferência porque esse executável
antigo já não está disponível na instalação local para uma contraprova.

### Payload real capturado

Uma instalação intermediária instrumentada, descartada depois do diagnóstico,
capturou o envelope real abaixo. Identificadores de sessão foram omitidos; os
campos que governam a decisão estão preservados:

```json
{
  "cwd": "C:\\...\\hook112-real-probe",
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
C:\Users\Luis\.codex\plugins\cache\rainforest-mind-local\rainforest-mind\1.12.0+codex.20260913112347
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
