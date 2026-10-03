# Mod: faixa acima do prompt com foco, fluxo em curso e Q abertas

## Objetivo
Uma faixa fixa acima do prompt (Claude Mods, `ui.render` em `AbovePrompt`) que mostra o foco ativo,
os fluxos em curso e as Q abertas da última resposta, para retomar o fio sem rolar a tela.

## Decisões fechadas
- **D1 — Conteúdo: foco ativo + fluxos em curso + Q abertas da última resposta** — porquê: as Q abertas são o que mais some quando a tela rola (regra 1), e dá para tirá-las do próprio texto da resposta, sem depender de o modelo avisar.
- **D2 — Aparece só quando há fluxo em curso ou Q aberta, com botão "esconder"** — porquê: faixa vazia é ruído; o foco sozinho não acende a faixa.
- **D3 — Até 3 linhas, uma por assunto (foco / fluxo / Q), cada uma cortada na largura (`bodyColumns`)** — porquê: o texto inteiro da Q continua na resposta; a faixa só lembra.
- **D4 — Fluxos: todos os em curso no repositório, incluindo os worktrees; o mais recente na linha e "+N" para os outros** — porquê: o estado de cada fluxo mora no worktree dele (`docs/rainforest/estado/<slug>.json`), e o checkout principal só enxerga cópias velhas trazidas por merge (medido em 2026-10-03: no principal, `estado.cjs listar` mostrava `mod-regras-inteiras -> fechar` já fechado no worktree, e não mostrava o `mod-faixa-foco` em curso). A janela costuma abrir na raiz.
- **D5 — "Esconder" vale até algo mudar (nova Q, nova etapa, agente novo em voo)** — porquê: esconde o que já foi visto sem deixar novidade passar.
- **D6 — Visível também durante o turno do modelo** — porquê: turno longo é quando etapa e agentes em voo mais ajudam.
- **D7 — As Q abertas saem do texto da última resposta do assistente, no `turn.complete`, pelos marcadores que o plugin já usa (`**Q<n>.**` e `❓ **Q<n> —`), lidos de `e.answer` do `turn.complete` (o texto final visível do turno)** — porquê: zero cooperação do modelo, sem varrer o transcrito a cada turno; uma resposta sem Q zera a linha. (Emenda de 2026-10-03, no plano: era `$.session.messages()`; o usuário escolheu `e.answer`.)
- **D8 — Foco: o título em negrito da seção `## Ativo` do `FOCO.md` (via o mesmo resolvedor de raiz dos hooks)** — porquê: é a linha que identifica o foco; o resto do foco já chega pela abertura.
- **D9 — Fluxo: etapa, `tarefas_ok/tarefas` e agentes `em_voo` do JSON de estado, lidos com os scripts do repo (`estado.cjs` / `git worktree list`) por `$.process.run`, não reimplementados** — porquê: mesma lição da D8 do fluxo anterior; o módulo do mod não tem Node e duas leituras do estado divergiriam.
- **D10 — A faixa não repete o que a statusline já mostra (jornada, prazo, versão)** — porquê: a statusline do plugin (`statusline/statusline.py`) já cobre isso; duplicar é ruído.
- **D11 — Atualiza no `session.start`, no `turn.complete` e ao pressionar; leitura falha → a linha some, a faixa nunca quebra a sessão** — porquê: falha aberta, como no mod da abertura.

## Avaliado e descartado
- Mostrar só o fluxo do worktree da sessão: medido que o principal não enxerga o fluxo em curso (D4).
- Q informadas pelo modelo por ferramenta registrada (`$.tool.register`): depende de o modelo lembrar, gasta chamada por turno; o texto da resposta já tem os marcadores (D7).
- Faixa sempre visível, ou só por comando: descartadas pelo usuário (D2).

## Fora de escopo
- Codex: não tem mods.
- Jornada e janela parada por relógio (ideia 4, próximo fluxo) e gates em `tool.call` (ideia 2, depois).
- Clicar na Q para responder, ou abrir o plano do fluxo por botão.

## Varredura
docs/rainforest/varredura/2026-10-03-mod-faixa-foco.txt — nada sobre faixa ou `AbovePrompt`. Achou a statusline do plugin (PR #164, #229; `statusline/`), que gerou a D10, e a rota com emoji por etapa da regra 4 (#299, PR #301), que a linha do fluxo pode reaproveitar no formato.

## Em aberto
