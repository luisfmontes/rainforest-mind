# Transferir sessão entre contas do Claude Code

## Objetivo
`/transferir claude` copia a sessão atual da conta em que ela roda (`~/.claude` = trabalho,
`~/.claude-personal` = pessoal) para a outra e imprime a linha pronta para retomá-la lá com
`claude --resume`, com o contexto inteiro, sem resumo e sem gastar token.

## Decisões fechadas
- **D1 — Alvo: só o usuário, no meio de uma sessão, nesta máquina, entre as duas contas** — porquê: é o caso que motivou (rodada levada da conta de trabalho para a pessoal em 2026-10-06); outra máquina e outra pessoa ficam fora.
- **D2 — Estende o `/transferir` com destino (`/transferir claude`); Codex continua o padrão sem argumento** — porquê: uma porta só para "levar esta sessão para outro lugar", e o comando atual não muda de comportamento para quem já usa.
- **D3 — Destino automático: a outra conta; `--para pessoal|trabalho` aceito como explícito** — porquê: são só duas contas. A conta atual sai de `CLAUDE_CONFIG_DIR` (vazio ou `~/.claude` = trabalho; `~/.claude-personal` = pessoal); o explícito igual à atual recusa.
- **D4 — Copia, nunca move; a mensagem final manda fechar a janela de origem** — porquê: reversível; apagar transcript não tem volta, e duas cópias andando divergem.
- **D5 — Destino que já tem a sessão: recusa com exit não-zero, `--forcar` sobrescreve** — porquê: a cópia de lá pode ter avançado, e sobrescrever em silêncio apaga esse trabalho.
- **D6 — Entrega = copiar e imprimir `cd "<cwd>" && claude --resume <id>` (com o `CLAUDE_CONFIG_DIR` da conta destino quando ela não for a padrão); não abre sessão** — porquê: abrir em background depende do teste do `claude --bg` em pasta não confiada, que é da ideia `claude-central-despachante`.
- **D7 — Sem chave de opt-in** — porquê: a chave `transfer-codex` existe pela CLI externa que gasta cota; copiar arquivo entre as próprias contas não gasta nada e só roda quando chamado.
- **D8 — Copia junto a pasta irmã `<id>/` (subagentes e saídas de ferramenta persistidas)** — porquê: sem ela a conversa retomada aponta para arquivos que só existem na conta de origem.
- **D9 — A sessão atual se acha por `CLAUDE_CODE_SESSION_ID` (exportado pelo harness) em `<conta>/projects/*/<id>.jsonl`; o `cwd` da linha de retomada sai do próprio transcript** — porquê: dispensa o hook SessionStart do Codex (que só exporta com a chave ligada) e o slug da pasta de projeto não é reversível para caminho.
- **D10 — Conserta junto o `validarCaminhoTranscript` do `transferir-para-codex.cjs`, que só aceita `~/.claude/projects`** — porquê: na conta pessoal o `/transferir` para Codex sai exit 2; a validação vira código compartilhado nesta branch e passa a aceitar as duas contas.

## Avaliado e descartado
- Transferir por resumo para sessão nova (formato do Codex): perde detalhe; a cópia nativa foi medida em 2026-10-06 — transcript copiado de `~/.claude` para `~/.claude-personal` e `claude -p --resume <id>` na conta pessoal devolveu a palavra memorizada (`JABUTICABA-4471`), gravando só na cópia pessoal (344 KB → 437 KB; origem intacta).

## Fora de escopo
- Abrir a sessão retomada automaticamente (`claude --bg`): ideia `claude-central-despachante`.
- Outra máquina ou outra pessoa.
- Mover (apagar a origem).

## Varredura
docs/rainforest/varredura/2026-10-06-transferir-entre-contas.txt — nenhuma Issue, PR ou branch sobre transferir entre contas; acha só o `/transferir` para Codex (PR #222, #227) e os helpers de duas config dirs (`jornada.cjs`, `saude.cjs configDirsDoHarness`). Mudou: reaproveitar o comando existente (D2) e expôs o defeito da validação só em `~/.claude` (D10).

## Em aberto
- (vazio)
