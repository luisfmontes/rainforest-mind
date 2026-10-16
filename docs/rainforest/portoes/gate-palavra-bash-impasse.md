# Impasse: gate-palavra-bash (#530, itens 1–3) — teto de 3 reprovações

Data: 2026-10-15

## Onde parou
Os 17 contornos que o design mirou barram desde a volta 1, e as baterias fecham verdes (gate 291/0, cwd 80/0). As três reprovações vieram do mesmo efeito colateral: a leitura normalizada do bash **tira** bloqueio que a base tinha.

- **Volta 1:** com a ferramenta PowerShell, `C:\PROGRA~1\Git\cmd\git.exe -C P commit` saía 0. `normalizarComando` apagava as contrabarras e o git deixava de ser reconhecido. Houve também um falso positivo `cd hooks; echo "$(echo x > ../f)"`.
- **Volta 2:** a ferramenta PowerShell foi tirada da leitura do bash. O mesmo 2→0 voltou pelo texto interno de `powershell -Command "…"` usado na ferramenta Bash.
- **Volta 3:** o interno de `pwsh`, `powershell` e `cmd` passou a ser lido como PowerShell (`ferramentaDoInterno`). O 2→0 voltou com `;`, `&` ou `|` dentro da string, como em `powershell -c "echo a; C:\…\git.exe -C P commit"`. O motivo é que `verboNaLinha` parte a linha com um split que não respeita aspas. O fragmento depois do `;` não vê o wrapper, é lido como bash e perde as barras. O revisor confirmou que o comando executa de verdade (`git --version` pelo mesmo caminho).

## Não é só defeito de implementação
Cada volta remendou uma **forma** de entrada. A causa é uma só: a leitura nova **substitui** a antiga no reconhecimento do git, em vez de **somar** a ela. Enquanto ela substituir, cada separador, wrapper ou aspa que o remendo não previu reabre o mesmo 2→0. O design deixou a "semântica de união" (item 4 da #530) fora do escopo, e é essa omissão que o laço está pagando.

## Proposta (rodada extra)
Fazer união só onde o git é reconhecido. `subcomandoGit` aceita o git achado no texto **cru** ou no **normalizado**: a leitura do bash só acrescenta bloqueio e nunca tira. Isso fecha a família por construção, sem precisar prever a forma.

- O `ferramentaDoInterno` da volta 3 pode ficar como está ou sair, conforme o diff de 995 comandos do revisor mostrar.
- Custo: os 12 casos `C:\Git\cmd\git.exe -C P commit` sem aspas no Bash voltam a barrar, como na base. Eles não executam no bash real, então o bloqueio é espúrio, mas conservador e sem regressão.
- Junto entram os casos de teste com `;`, `&` e `|` dentro da string do wrapper, a nota no CHANGELOG e o critério de aceite no diferencial: **zero 2→0 contra a base** no corpus do revisor.

Fora desta rodada: a união no resto do gate (escrita, `cd`) segue na #530 e no fluxo próprio do caminho do principal.

## Rodada extra 1 (volta 4): reprovada
A união fechou o 2→0 do reconhecimento do git. O diferencial de 3.980 execuções contra a base deu zero 2→0, e o fuzz do revisor (14.800 execuções) também. O que entrou junto foi um custo exponencial: `subcomandoGit` recursa nas duas leituras. Quando o primeiro token do wrapper difere entre elas (`'eval'`, `\eval`, `'bash' -c`), as duas chamadas recebem o mesmo interno e o custo dobra a cada nível. Medido: com 18 níveis o hook leva 14,7 s, e com 22 passa de 60 s. A base é linear, e o comando executa de verdade. É fail-open por travamento ou timeout.

### Proposta (rodada extra 2)
- **Recursão uma vez por interno distinto.** Junte os internos das duas leituras num `Set` (texto e ferramenta) antes de recursar. Assim o custo volta a ser linear.
- **Teto de profundidade que barra.** Mais de 4 níveis sai com o motivo que o `alvosBashEscrita` já usa, "wrapper aninhado demais para conferir (mais de 4 niveis)".
- **Caso na bateria.** `'eval' ` × 22 seguido de `"git -C P commit …"` → 2 em menos de 2 s.
- **CHANGELOG.** Os itens de `bash -c`/`eval` e de substituição passam a dizer que valem para escrita, não para verbo de git (item 4 da #530).
