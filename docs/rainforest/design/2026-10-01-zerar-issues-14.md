# Rodada 14 — triagem do Gmail (#367), creep da varredura (#368), dívidas da rodada 13 (#369)

## Objetivo
Fazer a triagem de inbox do `sentinela-foco` sobreviver à subida lenta do MCP do Gmail e ler só pelo MCP de leitura, isentar do creep a varredura que o próprio fluxo exige, e pagar as três dívidas menores da revisão da rodada 13.

## Decisões fechadas
- **D1 — #368: `conferir-fluxo creep` isenta `docs/rainforest/varredura/<slug>.txt` do próprio slug; varredura de outro slug continua creep; a seção "Isenções" de `skills/revisar/SKILL.md` lista a classe** — porquê: o `brainstorm` obriga a criar o arquivo e o `marcar --estagio design` o exige; é a mesma família da #279. Critério: creep de um diff com a varredura do próprio slug sai 0; com a de outro slug sai recusando.
- **D2 — #369 item 1: no `raizComEstadoDoSlug`, quando o filtro de janela armada ainda deixa mais de um candidato e o `repoRoot` (toplevel do `payload.cwd`) está entre eles, ele vence** — porquê: o revisor não isolado roda no worktree do fluxo; o empate vem de uma cópia commitada do estado em outro worktree. Critério: dois worktrees não-agente armados, revisor com cwd num deles → grava nele e o outro fica byte a byte igual.
- **D3 — #369 item 2: `--exige` aceita nome que começa com `..` dentro do worktree (`..foo`), recusa `.`/raiz com mensagem própria, e confere existência pelo mesmo caminho resolvido do confinamento (absoluto dentro do worktree passa)** — porquê: os três casos dão resposta errada hoje (recusa legítimo, mensagem que mente, exit 1 em caminho válido). Critério: casos de bateria para os três.
- **D4 — #369 item 3: a normalização `\r\n?` → `\n` sai de `normalizarTexto`** — porquê: medido pelo revisor da rodada 13, a bateria fica igual sem ela; com a regex final o `\r` já cai em `[^"\n]`. O caso `#364-r2 aspa solta crlf` continua cobrindo CRLF.
- **D5 — #367: o `run-vigia.ps1` define `MCP_TIMEOUT=90000` no processo antes de chamar o `claude -p`, só para a ronda** — porquê: causa raiz medida em 01/10 — o `@artymclabin/gmail-mcp` via `npx -y` levou 57,6 s para responder ao `initialize` (2,4 s na execução seguinte), acima dos 30 s do Claude Code; falhou 29 e 30/09, rodou 01/10. Nenhuma variável do usuário nem do sistema muda.
- **D6 — #367: toda ronda nega o servidor `mcp__gmail` inteiro por `--disallowedTools`, e o prompt do `sentinela-foco` nomeia as tools do `gmail-leitura`** — porquê: em 01/10 a triagem leu pelo `gmail` de escopo completo (envia, apaga) em vez do `gmail-leitura` somente leitura que o `comms-vigia` prevê; vigia de leitura não precisa enxergar o outro.
- **D7 — #367: quando o MCP de leitura não sobe nem com o timeout maior, o briefing traz a linha explícita `inbox: não verificado — MCP do Gmail não subiu`, além do registro no `ERROS.md`** — porquê: é o critério de pronto da Issue — aviso explícito em vez de silêncio.
- **D8 — Entrega: um PR, bump de minor sobre a `origin/main` do momento, cada item com caso de bateria vermelho antes do conserto; o log da ronda sem o texto do modelo (03 a 28/09) vira Issue própria** — porquê: formato das rodadas anteriores; o log é outro defeito, sem causa conhecida.

## Avaliado e descartado
- #367 trocar `npx -y` por instalação fixa do pacote ou excluir o cache do antivírus: é mudança no ambiente do usuário (regra 15) e não elimina a carga do `googleapis`; fica como sugestão a ele, fora do repo.
- #367 só esperar mais no prompt (`ping` mais longo): mascara o sintoma; com o timeout de 30 s o servidor já foi dado como falho e não volta na sessão.
- #369 item 1 manter "ambíguo": perde o veredito do revisor não isolado em silêncio.
- #369 item 3 manter a linha com um caso artificial: código que nenhum teste distingue.

## Fora de escopo
- Symlink dentro do worktree apontando para fora no `--exige`: exigiria `realpath` e não tem caso de uso.
- Rotacionar o `GITHUB_PERSONAL_ACCESS_TOKEN` que está em texto puro no `.claude.json`: ação do usuário fora do repo, avisada na sessão.
- O log da ronda sem texto do modelo: Issue própria (D8).

## Varredura
docs/rainforest/varredura/2026-10-01-zerar-issues-14.txt — achou só as próprias #367, #368, #369 e o histórico da rodada 13 (#362–#364, PR #370); nenhuma branch ou ideia duplicando.

## Em aberto
(nenhum)
