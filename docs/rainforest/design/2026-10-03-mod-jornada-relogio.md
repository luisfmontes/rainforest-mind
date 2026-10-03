# Mod: jornada e janela parada por relógio

## Objetivo
O aviso de jornada (regra 8) e o alerta de janela parada (regra 17) passam a nascer do relógio, e não
da memória do modelo a cada turno: o mod mede em segundo plano e acende uma linha na faixa acima do
prompt quando um limite é cruzado.

## Decisões fechadas
- **D1 — Uma linha a mais na faixa existente, com o mesmo "esconder"; sem toast** — porquê: a faixa já tem lugar e botão; toast passa quando o usuário não está olhando, e o aviso que importa é o que ele não viu.
- **D2 — O mod mostra o fato (jornada efetiva e hora); o ponto de parada e a checagem de corpo continuam com o modelo** — porquê: só o modelo sabe o que está em andamento, e ponto de parada genérico vira ruído; a checagem de corpo pega carona no aviso e nunca vira gatilho próprio (ef76b391, v0.46.0).
- **D3 — A jornada acende pelos números: efetivas acima de 9h, ou depois das 19h com mensagem do usuário nos últimos 30 min; sempre, sem isenção no mod** — porquê: com o "esconder", acender a mais custa um clique; a isenção de "delegar à noite em projeto de descanso" fica com o modelo, que vê o contexto. A linha só existe no limite: a statusline já mostra a jornada o tempo todo.
- **D4 — Janela parada: qualquer janela esperando o usuário além da `Ociosidade máxima:` do FOCO.md (45 min se ausente), nomeada a mais parada pela pasta, contando as demais** — porquê: o usuário roda várias janelas e a que esfria raramente é a do foco; a abertura de 2026-10-03 mostrou "3 esperando você (mais parada: 168 min)" sem dizer qual. Esperando = `stop_ts` mais novo que `prompt_ts` no `sessoes.json` (o mesmo critério do `hooks/heartbeat.cjs`); Claude trabalhando nunca conta; a própria janela não entra.
- **D5 — Quando a linha de jornada acende, o mod deixa uma nota de uma vez no prompt do turno seguinte para o modelo avaliar a regra 8** — porquê: é o que faz o aviso nascer do relógio sem tirar do modelo a decisão de calar quando o usuário está delegando.
- **D6 — "Esconder" não volta com os minutos: a jornada só volta no dia seguinte; a janela parada volta quando outra janela vira a mais parada ou uma nova cruza o limite** — porquê: a regra 8 diz "uma única vez"; reaparecer a cada hora é o ruído que ensina a ignorar o aviso.
- **D7 — Jornada e janela parada dividem uma linha (`⏰ jornada 9h12 · 20h40 | <pasta> parada há 32 min`); a faixa vai a até 4 linhas, e com pouco espaço essa linha sobra antes da Q** — porquê: são dois avisos de relógio do mesmo tipo; a faixa cresce uma linha, não duas.
- **D8 — Relógio pelo `$.clock.every` ligado no `session.start` (e cancelado no `session.end`): `sessoes.json` lido a cada 1 min, `scripts/jornada.cjs` rodado a cada 5 min por `$.process.run`; mudança grava átomo e redesenha** — porquê: medido no tipo do engine 2.1.288 (`claude-code.d.ts`, `clock.every`/`after`) e por teste: não existe evento de tick nem de ócio, e `setTimeout` funciona mas não é contrato; o `jornada.cjs` custa ~3 s, o `sessoes.json` é leitura de arquivo.
- **D9 — Jornada e janela parada vêm dos scripts e arquivos do repo (`scripts/jornada.cjs`, `sessoes.json` resolvido pelo mesmo resolvedor de raiz), nunca reimplementados; falha de leitura apaga só a linha** — porquê: mesma lição da faixa (D9 de 2026-10-03-mod-faixa-foco): duas leituras do mesmo dado divergem, e a regra 8 proíbe inferir jornada de carimbo, log ou mtime.

## Avaliado e descartado
- Toast (`$.ui.toast`) como aviso: descartado pelo usuário (D1).
- Mod como aviso inteiro, com frase fixa, tirando a regra 8 do modelo: descartado (D2).
- Isenção de tempo pessoal no mod: o mod não distingue delegar de produzir; descartado (D3).
- Só a janela do foco, como a regra 17 diz hoje: descartado (D4).
- Reaparecer a cada hora cheia de jornada: descartado (D6).
- Evento de tick ou `session.idle`: não existem no catálogo do engine 2.1.288 (medido); `setTimeout` dispara mas o tipo o declara inexistente (D8).

## Fora de escopo
- Codex: não tem mods.
- Mudar o texto das regras 8 e 17 além do necessário para dizer que o relógio do mod acende o aviso.
- A statusline (`statusline/`), que segue como está.
- Gates em `tool.call` (ideia 2, próximo fluxo).

## Varredura
docs/rainforest/varredura/2026-10-03-mod-jornada-relogio.txt — nada sobre aviso por relógio. Achou o histórico da regra 8 (jornada medida no transcript, corte de 55 min, checagem de corpo que não vira gatilho — ef76b391), a regra 17 cega por PID (#8) e a statusline que já avisa sessão atrasada (#44), que geraram D2, D4 e o "só no limite" da D3.

## Em aberto
