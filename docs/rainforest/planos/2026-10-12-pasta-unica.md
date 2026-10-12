# Plano: Uma pasta só de configuração do Claude Code

Design: docs/rainforest/design/2026-10-12-pasta-unica.md

## O que não pode quebrar
- Modo duas pastas (as duas existem): `/conta`, `trocar`, `preparar`, `vigiar` e `agendar` se comportam como na 1.62.0 — as baterias `testa-conta*.sh`/`.cjs` existentes seguem verdes sem edição de caso.
- Credencial nunca é copiada (refresh token de uso único) e nunca aparece em stdout, log ou evento — só `sha256[0:12]`.
- Nada é sobrescrito em `~/.claude` pela migração; sem `--aplicar`, a migração não escreve nada.
- Baterias só com `RFM_TEST=1`, homes falsos e CLI falsa: nunca tocar `~/.claude*`, `~/.rainforest`, a API real, o `schtasks` real nem o `$PROFILE` real.
- Repo público: nenhum caminho da máquina, e-mail, token ou id em código ou teste.

## Fatos medidos que o plano usa (2026-10-12)
- A suposição de duas pastas mora em `scripts/conta.cjs`: `PASTAS` (`:40`), `pastasDir` (`:47-55`), laços `for (const P of PASTAS)` (`:151`, `:419`, `:479`, `:487`, `:655`, `:782`), `outra` (`:733`) e as listas fixas de reservas em `preparar` (`:926`) e `agendar` (`:981`).
- `scripts/lib/conta-decidir.cjs` decide por pasta presente em `pastas` (`Object.keys(pastas)`) — com uma pasta só, não precisa mudar.
- `hooks/lib/contas-claude.cjs`: `contaAtual`, `outraConta` e `PASTAS_DE_CONTA` não têm consumidor fora do próprio arquivo (grep de 2026-10-12, vazio); o único consumidor do módulo (`scripts/transferir-para-codex.cjs`) só usa `homeDoUsuario` e `dentroDeProjetos`, que aceitam caminho em qualquer das duas. `saude.cjs`, `jornada.cjs` e `calibrar-limiar-assunto.cjs` já toleram a pasta pessoal ausente (leitura com `try`/`continue`). Nada a mudar neles.
- O `.claude.json` da pasta padrão mora em `~/.claude.json` (fora de `~/.claude`); o da pessoal, em `~/.claude-personal/.claude.json`.

## Tarefas

### 1. `conta.cjs` em modo uma pasta [tipo: implementar]
atende: D4, D6
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-uma-pasta.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-conta-uma-pasta.sh`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: fs.existsSync(dirs.pessoal)
  para: true
  bateria: `bash scripts/testa-conta-uma-pasta.sh`
  fixture: `testa-conta-uma-pasta.sh, caso "uma pasta: status lista só trabalho e vigiar troca para a reserva pessoal"`
Forma prescrita: uma função `pastasAtivas()` devolve `['trabalho']` ou `['trabalho', 'pessoal']`, e a decisão contém a expressão literal `fs.existsSync(dirs.pessoal)` (a pasta pessoal conta só se existir; `.claude-personal.aposentada` não é ela). Todo uso de `PASTAS` listado nos fatos passa a usar `pastasAtivas()`. Modo uma pasta: `--pasta pessoal` sai 2 dizendo que a pasta não existe; `trocar` não exige "a outra pasta em casa"; `preparar` e `agendar` exigem só a reserva da conta que não é a casa de nenhuma pasta ativa mais as das casas que tenham outra pasta para onde ir (uma pasta → só `reserva-pessoal`); `/conta` mostra uma linha de pasta; `preparar pessoal` em modo uma pasta registra a conta pessoal pelo `/api/oauth/profile` do login recém-feito quando ela ainda não está registrada (a pessoal não é casa de pasta nenhuma, então `registrarCasas` não a registra). Nenhum caso de teste afirma sobre o texto do fonte.
pronto quando: com home falso contendo só `.claude` (sem `.claude-personal`), servidor falso devolvendo team a 98% na `five_hour` e pessoal a 10%/10%, e as reservas gravadas, `conta.cjs vigiar` move a reserva pessoal para `.claude/.credentials.json` e grava `estacionado-trabalho.json`; `conta.cjs` sem argumento imprime exatamente uma linha de pasta (`trabalho`); `conta.cjs agendar --imprimir` com só `reserva-pessoal.json` presente sai 0; `conta.cjs trocar pessoal --pasta pessoal` sai 2 citando que a pasta não existe — provado por `bash scripts/testa-conta-uma-pasta.sh` (zero `skipped`) e, sem regressão, por `bash scripts/testa-conta.sh` com o mesmo placar da base (46/0).

### 2. `conta.cjs unificar`: migração para a pasta única [tipo: implementar]
atende: D1, D2, D3, D7
arquivos: `scripts/conta.cjs`, `scripts/lib/conta-unificar.cjs`, `scripts/testa-conta-unificar.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-conta-unificar.sh`
mutacao:
  arquivo: `scripts/lib/conta-unificar.cjs`
  de: fs.existsSync(destino) && !mesmoConteudo(origem, destino)
  para: false
  bateria: `bash scripts/testa-conta-unificar.sh`
  fixture: `testa-conta-unificar.sh, caso "memoria de mesmo nome e conteudo diferente vira .pessoal.md e o destino fica intacto"`
Forma prescrita: a cópia de arquivo decide o conflito numa expressão só, literal `fs.existsSync(destino) && !mesmoConteudo(origem, destino)`; conflito copia para `<nome>.pessoal.<ext>`; mesmo conteúdo não copia. Lógica de cópia e de fusão (`history.jsonl`, `MEMORY.md`, `.claude.json`) em `scripts/lib/conta-unificar.cjs`; `conta.cjs unificar` só orquestra; `unificar --ajuda` imprime as flags aceitas (uma por linha) e sai 0. Sem `--aplicar`: relatório, nenhuma escrita (o teste compara hash da árvore inteira dos dois homes falsos antes/depois). Com `--aplicar`, nesta ordem: recusa (exit 2, nada escrito) se houver processo `claude` vivo (lista injetável em teste por `RFM_CONTA_PROCESSOS`), sessão viva no `sessoes.json`, a pasta pessoal fora de casa no `estado.json`, ou nome de MCP igual com definição diferente; desagenda o vigia; copia `projects/` (transcritos e `memory/`), `file-history/`, `plans/`, `todos/` e `tasks/` que existirem; acrescenta ao `history.jsonl` as linhas ausentes; acrescenta ao `MEMORY.md` de destino as linhas do índice pessoal cujo alvo não estava lá; une `mcpServers` e `projects` do `.claude.json` pessoal em `~/.claude.json` sem sobrescrever chave; instala e habilita pela CLI (`claude plugin install <p> --scope user`, binário injetável por `RFM_CONTA_CLAUDE_BIN` em teste) cada plugin habilitado só na pessoal; grava a `claudeAiOauth` pessoal como `reserva-pessoal.json` só se não existir reserva pronta (senão a deixa na pasta aposentada); renomeia a pasta para `.claude-personal.aposentada`; reagenda o vigia apontando para o `conta.cjs` do clone de marketplace em `~/.claude`. Não copia `cache/`, `daemon*`, `session-env/`, `sessions/`, `shell-snapshots/`, `telemetry/`, `debug/`, `statsig/`, `stats-cache.json`, `plugins/`. Relatório: contagem por classe, cada conflito renomeado (caminho relativo), cada linha de índice acrescentada, cada plugin instalado, e a linha final `pasta pessoal aposentada: <caminho>` — sem conteúdo de credencial.
pronto quando: com dois homes falsos que reproduzem a forma real (`projects/<p>/<uuid>.jsonl`, `projects/<p>/memory/*.md` + `MEMORY.md`, `history.jsonl`, `.claude.json` com `mcpServers` `whatsapp` idêntico nas duas e `github` só na pessoal, `settings.json` com `security-guidance` habilitado só na pessoal), `conta.cjs unificar` sem `--aplicar` não muda nenhum byte dos dois homes e lista o conflito; `conta.cjs unificar --aplicar` deixa `.claude-personal` inexistente e `.claude-personal.aposentada` presente, o transcrito pessoal no projeto de `~/.claude`, a memória conflitante como `.pessoal.md` com o original intacto (hash), `github` em `~/.claude.json` sem alterar `whatsapp`, a CLI falsa chamada com `plugin install security-guidance`, e o `schtasks` falso chamado com `/Delete` antes e `/Create` apontando para `.claude/plugins/marketplaces/` depois; com processo `claude` vivo injetado, sai 2 e nenhum byte muda; com `whatsapp` divergente, sai 2 e nenhum byte muda — provado por `bash scripts/testa-conta-unificar.sh` (zero `skipped`).

### 3. `unificar` troca os dois comandos do `$PROFILE` por um `claude` só [tipo: implementar]
atende: D5
arquivos: `scripts/conta.cjs`, `scripts/lib/conta-unificar.cjs`, `scripts/testa-conta-unificar-profile.sh`
depende de: 2
paralela: nao
prova: `bash scripts/testa-conta-unificar-profile.sh`
mutacao:
  arquivo: `scripts/lib/conta-unificar.cjs`
  de: Remove-Item Env:CLAUDE_CONFIG_DIR
  para: Remove-Item Env:NADA
  bateria: `bash scripts/testa-conta-unificar-profile.sh`
  fixture: `testa-conta-unificar-profile.sh, caso "profile real reescrito: claude unico remove CLAUDE_CONFIG_DIR e chama o binario"`
Forma prescrita: `unificar --profile <arquivo>` (sem padrão: só com o caminho explícito, emenda D5 de 2026-10-12) remove as funções `claude-pessoal` e `claude-trabalho` e acrescenta uma função `claude` que roda `Remove-Item Env:CLAUDE_CONFIG_DIR`, `Update-ClaudePlugins` e chama o binário por `(Get-Command claude -CommandType Application)` para não recursar. Como função vence aplicação no PowerShell, toda chamada `& claude ` dentro de `Update-ClaudePlugins` também passa a chamar a aplicação (o resto do bloco não muda); sem isso, `claude` → `Update-ClaudePlugins` → `& claude plugin ...` → `claude` vira laço. A instalação de plugin da tarefa 2 passa a usar a chave completa `<plugin>@<marketplace>` (o `enabledPlugins` real usa essa forma; nome nu é ambíguo entre marketplaces). Sem `--aplicar`, imprime o diff e não escreve; com `--aplicar`, grava backup `<profile>.bak-pasta-unica` antes. Profile sem as duas funções: não muda nada e diz isso.
pronto quando: com uma cópia em fixture do formato real do profile (funções `Update-ClaudePlugins`, `claude-pessoal` com `$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-personal"` e `claude-trabalho` com `Remove-Item Env:CLAUDE_CONFIG_DIR`), `unificar --profile <fixture> --aplicar` deixa o arquivo sem `function claude-pessoal` nem `function claude-trabalho`, com `function claude`, com `Update-ClaudePlugins` mudada só nas linhas `& claude ` (as demais linhas do bloco iguais ao original) e com o backup igual ao original (hash); e quando há PowerShell disponível, `powershell -NoProfile -Command ". '<fixture>'; (Get-Command claude -CommandType Function).Name"` imprime `claude`, e com uma aplicação falsa `claude.cmd` à frente no PATH (que registra cada chamada num arquivo) `powershell -NoProfile -Command ". '<fixture>'; claude --version"` termina em até 30 s com a aplicação chamada pelas atualizações e uma vez com `--version`, sem recursão — provado por `bash scripts/testa-conta-unificar-profile.sh` (o caso do PowerShell pula honestamente só se `powershell` não existir no PATH).

### 4. README, comando `/conta` e versão [tipo: docs]
atende: D4, D5, D6, D7
arquivos: `README.md`, `commands/conta.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: texto e número de versão, sem comportamento a inverter; a falsificação é o texto casar com a interface real das tarefas 1–3.
pronto quando: com a interface real das tarefas 1–3, o README descreve os dois modos (uma pasta / duas pastas) com a regra de detecção de D6, o passo a passo da migração na ordem de D7 (fechar janelas, `unificar` sem `--aplicar`, depois `--aplicar`, abrir com `claude`), a conta da casa team de D4, e que a pasta aposentada só sai quando o usuário apagar (D3); cada flag citada existe — provado por `node scripts/conta.cjs unificar --ajuda` listando exatamente as flags que o README cita, e `bash scripts/testa-versao.sh` saindo 0 com a versão nova nos dois `plugin.json`, no badge do README e no CHANGELOG.

### 5. Migração real na máquina do Luís [tipo: configurar]
atende: D1, D2, D3, D4, D5, D7
arquivos: `relatorios/2026-10-12-pasta-unica-migracao.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: execução em ambiente real com as credenciais e pastas do usuário; não há linha de produção a inverter.
pronto quando: com o Luís presente e todas as janelas do Claude fechadas, rodando do clone instalado da versão nova: `conta.cjs unificar` (relatório sem escrita) e depois `conta.cjs unificar --aplicar` saem 0; `Test-Path ~/.claude-personal` dá `False` e `~/.claude-personal.aposentada` existe; uma sessão aberta com `claude` (sem `CLAUDE_CONFIG_DIR`) mostra a memória pessoal do `rainforest-mind` no índice; `conta.cjs` mostra uma pasta só, com a conta team; `schtasks /query /tn \ClaudeVigias\troca-de-conta /v /fo list` mostra o comando apontando para `.claude\plugins\marketplaces\` e próxima execução preenchida; `claude mcp list` lista `github` e `protheus` — tudo colado em `relatorios/2026-10-12-pasta-unica-migracao.md` com caminhos da máquina trocados por `~`.

### 6. Gate de publicação lê o marcador no conteúdo de um Write [tipo: implementar]
atende: D6
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
paralela: sim
prova: `bash hooks/testa-gate-publicacao-destino.sh`
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: nome === "Write" && temMarcadorNoConteudo(conteudo)
  para: false
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: `testa-gate-publicacao-destino.sh, caso "Write de arquivo NOVO com marcador no topo do conteudo -> passa"`
Achado na execução da tarefa 1 (regra 6, cabe no PR): a bateria nova da tarefa 1, com dados falsos e o marcador de dados de exemplo na linha 2, foi barrada porque o gate, no caminho Write/Edit, só procura o marcador no DISCO (`temMarcadorDados(arquivo)`), e arquivo novo ainda não existe no disco. O caminho de commit já lê o conteúdo (`if (temMarcadorNoConteudo(conteudo)) continue;`). Forma prescrita: a linha `if (temMarcadorDados(arquivo)) process.exit(0);` passa a dispensar também quando `nome === "Write" && temMarcadorNoConteudo(conteudo)` (Write traz o arquivo inteiro, então as 5 primeiras linhas do conteúdo são as do arquivo); Edit e MultiEdit continuam lendo só o disco (o fragmento não é o topo do arquivo).
pronto quando: com o payload PreToolUse real de Write (`tool_name: "Write"`, `tool_input.file_path` num arquivo NOVO dentro de um repo git público de teste, `tool_input.content` com o marcador na linha 2 e um JID falso adiante), o gate sai 0; o mesmo Write com o marcador na linha 6 sai 2; um Edit cujo `new_string` começa com o marcador, em arquivo existente sem marcador no disco, sai 2; os casos já existentes (marcador lido do disco no Edit, linha 6 ignorada) seguem com o mesmo exit — provado por `bash hooks/testa-gate-publicacao-destino.sh` com placar sem falha.

### 7. A pasta padrão grava o `oauthAccount` no `~/.claude.json` [tipo: implementar]
atende: D4, D6
arquivos: `scripts/conta.cjs`, `scripts/lib/conta-mover.cjs`, `scripts/testa-conta.sh`, `scripts/testa-conta-uma-pasta.sh`, `scripts/testa-conta-mover.sh`, `scripts/testa-conta-preparar.sh`, `scripts/testa-conta-agendar.sh`, `hooks/testa-mod-conta.cjs`, `scripts/lib/conta-unificar.cjs`, `scripts/testa-conta-unificar.sh`, `CHANGELOG.md`
depende de: 1
paralela: nao
prova-na-base: verde — achado 2 da 3ª revisão: a fixture atual põe o `.claude.json` dentro da pasta padrão, então a base passa; o caso novo que separa os dois arquivos nasce com a tarefa
mutacao:
  arquivo: `scripts/conta.cjs`
  de: P === 'trabalho' ? claudeJsonTrabalho() : path.join(c.pastas[P], '.claude.json')
  para: path.join(c.pastas[P], '.claude.json')
  bateria: `bash scripts/testa-conta-uma-pasta.sh`
  fixture: `testa-conta-uma-pasta.sh, caso "pasta padrão: a troca grava o oauthAccount no .claude.json de fora da pasta"`
Achado na 3ª revisão (impasse `docs/rainforest/portoes/2026-10-12-pasta-unica-impasse.md`, decisão do Luís em 2026-10-12: ajustar tudo na 4ª rodada). O Claude Code guarda o `.claude.json` da pasta padrão (`~/.claude`) em `~/.claude.json`, fora dela; `claudeArq` e `mover` leem/gravam `<pasta>/.claude.json`, então o `oauthAccount` da pasta padrão vai para um arquivo que ela não lê (e `vigiar` morre com ENOENT se ele não existir). Forma prescrita: `claudeArq` passa a ser `(c, P) => (P === 'trabalho' ? claudeJsonTrabalho() : path.join(c.pastas[P], '.claude.json'))`, com a expressão `P === 'trabalho' ? claudeJsonTrabalho() : path.join(c.pastas[P], '.claude.json')` literal uma vez; `mover` recebe o caminho do `.claude.json` como parâmetro (padrão: o de dentro da pasta, para não mudar outros chamadores) e o `conta.cjs` passa `claudeArq(c, P)`. As fixtures das baterias passam a pôr o `.claude.json` da pasta de trabalho no home falso (fora da pasta), como na máquina real, apontado por `RFM_CONTA_CLAUDE_JSON`; isso muda a fixture, não os casos. Emenda da 5ª rodada (Luís, 2026-10-12): toda bateria que roda o `conta.cjs` passa `RFM_CONTA_CLAUDE_JSON` (inclusive `hooks/testa-mod-conta.cjs`), e o `conta.cjs` recusa (exit ≠ 0, nada lido nem gravado) quando `RFM_TEST=1` define `RFM_CONTA_PASTA_TRABALHO` mas não `RFM_CONTA_CLAUDE_JSON`.
pronto quando: com o formato real (pasta padrão sem `.claude.json` dentro dela e o arquivo em `<home>/.claude.json`), `conta.cjs vigiar` no modo uma pasta troca para a reserva pessoal com exit 0 e grava o `oauthAccount` da pessoal em `<home>/.claude.json`, sem criar `<pasta>/.claude.json`; no modo duas pastas, a pasta pessoal continua usando o `.claude.json` de dentro dela — provado por `bash scripts/testa-conta-uma-pasta.sh` e `bash scripts/testa-conta.sh` com os placares sem falha.
