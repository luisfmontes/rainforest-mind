# Catraca de mutação lê o placar do vitest (#602)

## Objetivo
`conferir-mutacao.cjs` passa a reconhecer o placar do vitest, para que o vermelho
legítimo de uma bateria vitest com baseline frio não saia `pulada (suspeita de corte
de shell)` (exit 5) e trave o `marcar verificar ok`.

Premissas: serve a quem roda `verificar` com bateria vitest (medido num repositório
de trabalho com front em vitest, duas tarefas no mesmo dia). A forma nova convive
com as existentes (`ok: N falhou: M`, `N ok, M falha(s)`, `ok=N falhou=M`, libtest);
nenhuma é substituída.

## Decisões fechadas
- **D1 — Só o vitest entra agora; Jest e pytest ficam de fora** — porquê: forma sem caso medido é palpite; cada uma entra quando aparecer, como o vitest apareceu na #602.
- **D2 — A linha `Tests` é lida por segmento, não pela regex da issue** — porquê: `Tests\s+(?:(\d+) failed\s*\|\s*)?(\d+) passed` exige `passed`, e mutação que derruba todos os testes imprime `Tests  1 failed (1)`. Com o baseline lido e a pós-mutação sem placar, `bateriaColapsou` daria exit 6 — outro veredito falso. Regra: linha `^\s*Tests\s+<segmentos> (N)`, segmentos separados por `|`, cada um `N failed|passed|skipped|todo`; `ok` = passed, `falhou` = failed, skipped/todo ignorados; várias linhas `Tests` (mais de um comando vitest) se somam, como o libtest; `Test Files` conta arquivos e fica de fora. Entra depois das formas do repo e do libtest, que continuam vencendo.
- **D3 — Aquecimento (rodada descartada antes do baseline) fica fora e vira ideia plantada** — porquê: custa uma rodada extra de bateria em toda mutação (~40 s no caso da issue), e com o placar lido o vermelho vitest já não passa pela razão de tempo. Plantada como `aquecimento-antes-do-baseline-da-catraca`, gancho: próxima bateria sem placar reconhecido que caia em corte de shell por cache frio.
- **D4 — Modelo de ameaça: protege contra vermelho legítimo lido como corte de shell; bateria que imprime placar vitest falso fica fora** — porquê: é o mesmo contrato das outras formas; a catraca confia no placar que a bateria imprime, e mudar isso é outra entrega.

## Avaliado e descartado
- Regex sugerida na issue (`passed` obrigatório): descartada por D2 — `Tests  1 failed (1)` não casa e vira colapso (exit 6).
- Remover sequências ANSI antes de casar: a saída real do vitest 4.1.11 por pipe, no win32, veio sem nenhum `ESC[` — inclusive com `FORCE_COLOR=1`; na revisão 1, medido de novo com `CI=true`, `CI=true FORCE_COLOR=1` e `FORCE_COLOR=3 --color`, e a linha `Tests` continuou sem `ESC[`. Sem cor medida, a remoção seria código para um caso que não existe. Saídas reais capturadas em 2026-10-26: `Tests  2 passed | 1 skipped (3)` (verde), `Tests  1 failed | 1 passed | 1 skipped (3)` (vermelho parcial), `Tests  1 failed (1)` (todos falham), `Tests  no tests` com `Test Files  1 failed (1)` (import quebrado — sem placar, colapso pelo `bateriaColapsou`, como deve).
- Somar `Test Files` ao placar (sugestão da issue): conta arquivos, não asserções; misturar as duas unidades faria o critério de colapso (`ok === 0 && falhou === 0`) medir outra coisa.

## Fora de escopo
- Placar do Jest (`Tests:  1 failed, 14 passed, 15 total`) e do pytest (`1 failed, 14 passed in 3.2s`): D1.
- Aquecimento antes do baseline: D3, plantado.

## Varredura
docs/rainforest/varredura/2026-10-26-placar-vitest.txt — achou a #589 (placar do cargo test, mesma classe, fechada no lote 5 com a forma libtest e o caso 7 de `testa-conferir-mutacao-placar.sh`) e a #475 (`mediuEFalhou` para `node --test`). Nenhuma Issue, branch ou ideia sobre vitest ou aquecimento. Mudou o desenho: o conserto segue o molde da #589 — forma nova em `extrairPlacar`, casos unitários e um caso de ponta a ponta na mesma bateria — e `mediuEFalhou` não muda, porque já confia em `extrairPlacar`.

## Em aberto
