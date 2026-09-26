# Pesquisa: bloqueio do `SubagentStop` ao vivo

Tarefa 1 de `docs/rainforest/planos/2026-09-25-veredito-fora-da-linha.md`.
Claude Code **2.1.282** (`claude --version`), Node **v24.19.0**, nesta
máquina. Método de referência:
`docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md` — leia sua
seção "Efeito colateral": naquela pesquisa, `--settings <arquivo>` **somou**
ao `settings.json` de usuário (onde o plugin `rainforest-mind` está
habilitado) em vez de substituí-lo, e as 5 sessões headless escreveram no
`~/.rainforest` real. Esta pesquisa isola antes de rodar qualquer teste.

## Isolamento

`claude --help` documenta `--setting-sources <sources>` — "Comma-separated
list of setting sources to load (user, project, local)". O habilitar do
plugin (`enabledPlugins.rainforest-mind@rainforest-mind: true`) mora em
`<home>\.claude\settings.json`, escopo **user**:
```
$ grep -n -A1 "rainforest-mind@rainforest-mind" <home>/.claude/settings.json
    "rainforest-mind@rainforest-mind": true,
```
Passando `--setting-sources project,local` (sem `user`), esse escopo não é
lido — o plugin não carrega, então `hooks/hooks.json` do plugin real não
dispara. `--settings <arquivo>` continua funcionando para injetar o hook de
teste (é um mecanismo separado, não um "source" de escopo).

### Prova (antes/depois, isolado de qual sessão escreveu o quê)

`~/.rainforest/portaria/despachos.jsonl` e `~/.rainforest/sessoes.json` são
estado **compartilhado** com outras sessões reais do usuário rodando em
paralelo nesta máquina (confirmado por `sessoes.json` listar `cwd`s de outros
repositórios — `repo-exemplo-agro`, `whatsapp-mcp` — durante o teste).
Comparar hash bruto antes/depois não basta: o arquivo muda por causa de
sessões alheias, não das minhas. O teste que isola é **grep pelo caminho da
pasta de teste e pelo `session_id` das minhas sessões isoladas dentro desses
arquivos** — se não aparecem, minhas sessões não escreveram ali.

Antes (baseline, antes de qualquer sessão isolada):
```
$ wc -l ~/.rainforest/portaria/despachos.jsonl
535 <home>/.rainforest/portaria/despachos.jsonl
$ sha256sum ~/.rainforest/portaria/despachos.jsonl
af7d36bf2b870013276ed31a2854618f7536591a0aabc9696a94466f2a74a3ab
```

Sessão mínima isolada (só para provar o isolamento, sem hook de teste):
```
$ cd $SCRATCH/subagentstop-block-test   # fora de qualquer repo git
$ git rev-parse --show-toplevel
fatal: not a git repository (or any of the parent directories): .git
$ claude -p "Responda apenas a palavra: ok" \
    --setting-sources project,local \
    --output-format json \
    --permission-mode bypassPermissions
EXIT:0   ...  "result":"ok"  ...  session_id: 4bd06b48-1d89-4a10-9feb-ce1b5f19fd1e
```

Depois:
```
$ wc -l ~/.rainforest/portaria/despachos.jsonl
535 <home>/.rainforest/portaria/despachos.jsonl
$ sha256sum ~/.rainforest/portaria/despachos.jsonl
af7d36bf2b870013276ed31a2854618f7536591a0aabc9696a94466f2a74a3ab   # IGUAL
$ grep -c "subagentstop-block-test" ~/.rainforest/portaria/despachos.jsonl
0
$ grep -o "4bd06b48-1d89-4a10-9feb-ce1b5f19fd1e" ~/.rainforest/sessoes.json
(vazio — nenhuma ocorrência)
```
`despachos.jsonl` ficou byte a byte igual (mesmo hash, mesma contagem de
linhas) e nenhum dos dois arquivos contém o `session_id` nem o caminho da
pasta de teste — a sessão isolada não passou pela portaria real nem se
registrou em `sessoes.json`. `sessoes.json` por si só mudou de hash entre as
duas medições (`ecf41e5...` → `81b9d09...`), mas o conteúdo mostra só `cwd`s
de outros repositórios reais em uso simultâneo (`repo-exemplo-agro`,
`whatsapp-mcp`, o próprio worktree desta sessão) — confirma que a mudança
veio de sessões alheias, não da minha.

O mesmo grep foi repetido depois de cada uma das 3 sessões headless com hook
de teste usadas nas seções (a)-(c) abaixo — sempre 0 ocorrências do caminho
`subagentstop-block-test` e 0 ocorrências dos `session_id`s dessas sessões
(`f2a570fe-...`, `cb0776a9-...`, `b45d640d-...`) em `despachos.jsonl` e
`sessoes.json`. `despachos.jsonl` cresceu de 535 para 536 linhas durante a
bateria (outra sessão real de um segundo repositório gravou uma linha
própria no meio do teste — conferido lendo a última linha, `sessao:
"5f6c5f73-..."`, sem relação com este teste).

## Setup do teste

Tudo fora do worktree, em
`$SCRATCH/subagentstop-block-test/` (`$SCRATCH` =
`<home>\AppData\Local\Temp\claude\C--Projetos-rainforest-mind\553122e5-...\scratchpad`),
apagado ao fim (ver "Limpeza").

`settings-teste.json` — hook `SubagentStop` sem matcher (mesmo padrão de
`hooks/hooks.json:190-198`), aponta para `hook-subagentstop.cjs`:
```json
{
  "hooks": {
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "node \"...\\hook-subagentstop.cjs\"" } ] }
    ]
  }
}
```

`hook-subagentstop.cjs`: lê o stdin, anexa a linha crua em `captura.jsonl`;
se `payload.stop_hook_active !== true`, imprime
`{"decision":"block","reason":"Termine a mensagem com a linha exata
FIM-DO-TESTE"}` e sai 0; se `stop_hook_active === true`, sai 0 sem imprimir
nada.

`agents-teste.json` — agente `testeagente` via `--agents`, instruído a
responder uma frase curta **sem** a linha `FIM-DO-TESTE` na primeira
resposta (para forçar o bloqueio).

## (a) o subagente continua depois do bloqueio, e termina com `FIM-DO-TESTE`

```
$ claude -p "Use a ferramenta Agent para despachar subagent_type \"testeagente\" com o prompt exato: \"Diga apenas: Tarefa concluida.\". Aguarde a conclusao completa (incluindo qualquer instrucao extra que o hook do sistema exigir do agente antes de aceitar a parada dele) e depois repita literalmente, sem resumir e sem traduzir, a MENSAGEM FINAL COMPLETA que o agente testeagente respondeu." \
  --setting-sources project,local \
  --settings ./settings-teste.json \
  --agents ./agents-teste.json \
  --output-format json \
  --permission-mode bypassPermissions \
  --max-turns 15
```
`EXIT:0`. Campo `result` da janela principal (relato dela sobre o subagente):
```
"result":"Mensagem final completa do agente testeagente:\n\n```\nTarefa concluida.\nFIM-DO-TESTE\n```"
```
`subagent_stats`: `{"spawned":1,...,"max_depth":1,"completed":1,"failed":0,"killed":{"parent":0,"user":0,"system":0}}`
— o subagente completou normalmente, não foi morto.

Confirmação direta pelo transcrito capturado no hook (`captura.jsonl`, 2
linhas, campo `last_assistant_message` de cada chamada do `SubagentStop`
para o mesmo `agent_id: adc320ec84df66697`):
- 1ª chamada (`stop_hook_active: false`): `"Tarefa concluida."` — sem a
  linha pedida; hook bloqueou.
- 2ª chamada (`stop_hook_active: true`): `"Tarefa concluida.\nFIM-DO-TESTE"`
  — o agente, depois do `reason` do bloqueio, respondeu de novo e desta vez
  terminou com a linha exata pedida.

**CONFIRMADO**: o subagente continuou depois do `decision: "block"` e a
mensagem final seguiu o `reason` (terminou em `FIM-DO-TESTE`).

## (b) payload real da segunda parada (`stop_hook_active: true`)

A 2ª linha de `captura.jsonl` acima **é** o payload real que o harness manda
para o hook na segunda tentativa de parada do subagente, depois do bloqueio
da primeira. Salvo, sem edição de conteúdo (só reformatado com
`JSON.stringify(obj, null, 2)`), em
`hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json`:
```json
{
  "session_id": "f2a570fe-7cc0-45bd-ac9a-b8cedb1660cf",
  "transcript_path": "<home>\\.claude-personal\\projects\\...\\f2a570fe-7cc0-45bd-ac9a-b8cedb1660cf.jsonl",
  "cwd": "<home>\\AppData\\Local\\Temp\\claude\\...\\subagentstop-block-test",
  "prompt_id": "58c493c5-8e3f-43c5-8f1d-326ed1fa94f5",
  "permission_mode": "bypassPermissions",
  "agent_id": "adc320ec84df66697",
  "agent_type": "testeagente",
  "effort": { "level": "medium" },
  "hook_event_name": "SubagentStop",
  "stop_hook_active": true,
  "agent_transcript_path": "<home>\\.claude-personal\\projects\\...\\subagents\\agent-adc320ec84df66697.jsonl",
  "last_assistant_message": "Tarefa concluida.\nFIM-DO-TESTE",
  "background_tasks": [],
  "session_crons": []
}
```
(a fixture salva no repositório mantém o caminho local completo — passou
sem achado por `node scripts/conferir-publicacao.cjs
hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json`,
`EXIT:0`, "CONFERIDO — nao achei nada com forma de dado sensivel"; aqui no
corpo do doc uso `<home>` pelo mesmo motivo do gate de publicação).

Sem segredo: só caminhos de arquivo locais da máquina (`transcript_path`,
`agent_transcript_path`, `cwd` — todos dentro do `$SCRATCH` de teste) e IDs
gerados pelo harness (`session_id`, `agent_id`, `prompt_id`). Nenhuma
credencial, token ou dado do usuário.

O formato bate campo a campo com o que `hooks/testa-veredito-revisor.sh`
já assumia como payload real (`session_id, transcript_path, cwd, prompt_id,
permission_mode, agent_id, agent_type, effort, hook_event_name,
stop_hook_active, last_assistant_message, background_tasks,
session_crons` + `agent_transcript_path`) — sem campo novo e sem campo
faltando.

## (c) o que acontece se o hook bloquear também a segunda parada (e a terceira, ...)

Variante `hook-subagentstop-sempre.cjs`: bloqueia **sempre**, inclusive com
`stop_hook_active: true` (nunca lê esse campo). `settings-teste-sempre.json`
aponta para ela. Rodei duas vezes, com `--max-turns` diferentes, para separar
o efeito de `--max-turns` (turnos da sessão PRINCIPAL) de um possível limite
próprio do `SubagentStop`:

Rodada 1 (`--max-turns 8`):
```
$ claude -p "Use a ferramenta Agent para despachar subagent_type \"testeagente\" com o prompt exato: \"Diga apenas: Tarefa concluida.\". Aguarde a conclusao (mesmo que demore varias tentativas) e depois relate uma frase curta com o resultado, incluindo se o agente foi encerrado sem terminar." \
  --setting-sources project,local --settings ./settings-teste-sempre.json \
  --agents ./agents-teste.json --output-format json \
  --permission-mode bypassPermissions --max-turns 8
```
`EXIT:0`. `result`: `"O agente testeagente terminou e devolveu \"Tarefa
concluida.\", mas foi bloqueado 8 vezes seguidas pelo hook SubagentStop
antes de conseguir parar. Não foi encerrado sem terminar. [...]"`.
`subagent_stats`: `{"completed":1,"failed":0,"killed":{"parent":0,"user":0,"system":0}}`,
`terminal_reason: "completed"`.

Rodada 2 (`--max-turns 30`, mesmo hook, sessão nova):
```
$ claude -p "..." --setting-sources project,local --settings ./settings-teste-sempre.json \
  --agents ./agents-teste.json --output-format json \
  --permission-mode bypassPermissions --max-turns 30
```
`EXIT:0`. `result`: `"...disse que o hook hook-subagentstop-sempre.cjs
barrou a parada oito vezes antes de ele conseguir sair. [...]"`.
`subagent_stats`: mesmo padrão — `completed:1`, `killed` todos 0.

Contagem de chamadas ao hook nas duas rodadas (`wc -l captura-sempre.jsonl`,
recriado do zero antes de cada rodada): **9 em ambas** — 1 chamada com
`stop_hook_active: false` (o primeiro `Stop`) + **8** chamadas seguidas com
`stop_hook_active: true`, todas recebendo `decision: "block"` do hook (ele
nunca para de bloquear). Depois da 9ª chamada — que também devolveu
`block` — o harness **não chamou o hook uma 10ª vez**: a sessão terminou
(`terminal_reason: "completed"`), o subagente não foi morto
(`killed.system: 0`), e a última mensagem capturada (linha 9,
`stop_hook_active: true`, terminando em `FIM-DO-TESTE`) foi aceita como
final apesar do `block` que o hook mandou para ela.

**CONFIRMADO**: o harness **não laça infinito**. Ele honra o `block` do
`SubagentStop` por um número finito e fixo de tentativas — medido em **8**
chamadas consecutivas com `stop_hook_active: true` (9 no total, contando a
primeira sem esse campo) —, reproduzido identicamente em duas rodadas com
`--max-turns` diferentes (8 e 30), o que descarta `--max-turns` da sessão
principal como a causa do corte (o número de turnos da janela principal não
mudou o resultado). Depois da 8ª recusa em sequência, o harness para de
honrar o `block` e deixa o subagente terminar, sem matá-lo. **LACUNA**: não
encontrei essa contagem (8) documentada explicitamente na ajuda do CLI nem
teria como confirmar se é um valor fixo do harness ou algo variável por
versão — é um dado medido nesta versão (2.1.282), não uma garantia de API.

## Conclusões (para a tarefa 3 do plano)

1. **(a)** Um `SubagentStop` que bloqueia a primeira parada com
   `decision: "block"` devolve a vez ao subagente, que recebe o `reason` e
   pode responder de novo — a segunda resposta pode terminar exatamente como
   pedido. CONFIRMADO ao vivo.
2. **(b)** O payload da segunda tentativa de parada chega com
   `stop_hook_active: true` e os mesmos campos do payload real já usados em
   `hooks/veredito-revisor.cjs`/`hooks/testa-veredito-revisor.sh` — sem
   surpresa de schema. Fixture salva em
   `hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json`.
3. **(c)** Um hook que bloqueia SEMPRE (ignorando `stop_hook_active`) não
   trava a sessão para sempre: o harness desiste de honrar o bloqueio depois
   de 8 recusas seguidas (9 chamadas no total) e deixa o subagente terminar
   normalmente. Isso é uma rede de segurança do próprio harness — não
   substitui o comportamento pedido pelo design (D3: o hook do plugin deve
   parar de bloquear já na 2ª tentativa, não depender desse limite do
   harness).

## Limpeza feita

Apagados (todos fora do worktree, dentro de `$SCRATCH`):
`settings-teste.json`, `settings-teste-sempre.json`, `hook-subagentstop.cjs`,
`hook-subagentstop-sempre.cjs`, `agents-teste.json`, `captura.jsonl`,
`captura-sempre.jsonl`, `payload-segunda-parada-pretty.json`,
`isolamento-stdout.json`, `isolamento-stderr.log`, `sessao{1,2,3}-stdout.json`,
`sessao{1,2,3}-stderr.log`, e a pasta `subagentstop-block-test/` inteira.
Os transcritos reais das sessões isoladas ficaram em
`<home>/.claude-personal/.../projects/...-subagentstop-block-test/` (aceito
pelo briefing, mesma lógica da pesquisa de referência) — não apaguei.

## Premissas aceitas sem conferir

- Que `--setting-sources project,local` é suficiente para não carregar
  `enabledPlugins` de escopo `user` — conferido empiricamente aqui (grep
  mostrou 0 escritas em `~/.rainforest`), não lido na doc oficial de hooks.
- Que a contagem de 8 bloqueios consecutivos em (c) é estável entre versões
  do Claude Code — só medi na 2.1.282, duas vezes, mesma máquina, mesmo dia;
  não é uma garantia de API documentada (ver LACUNA acima).
- Que os campos do payload de `SubagentStop` capturados aqui (idênticos aos
  já assumidos por `hooks/testa-veredito-revisor.sh`) continuam estáveis
  entre 2.1.281 (pesquisa de referência) e 2.1.282 (esta) — não notei
  diferença nos campos, mas não fiz diff campo a campo contra uma captura
  anterior de `SubagentStop` especificamente (a pesquisa de referência
  capturou payloads de `PreToolUse` para `Agent`/`Task`, não de
  `SubagentStop`).
