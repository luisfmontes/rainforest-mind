# Lote A: saude, gate-fechar-issue e esperar-ci sem falso alarme (#608, #592, #594, #587, #591)

## Objetivo
Tirar os falsos alarmes das três ferramentas que o fluxo usa toda sessão: o `/saude`
(2 ALERTAs falsos em todo uso), o `gate-fechar-issue` (barra a forma que o `/feedback`
prescreve e lê erro de consulta como falta de evidência) e o `esperar-ci` (lê queda de
rede como CI vermelho e repo sem CI de PR como vermelho). Versão 2.0.5 (PATCH: só conserto).

## Decisões fechadas
- **D1 — Alvo e convivência: serve ao Luís no estágio `fechar` e em todo `/saude`; substitui o comportamento atual, sem chave para o antigo** — porquê: o comportamento atual só produz alarme falso; não há o que preservar.
- **D2 — #608, clone raso: com `git rev-parse --is-shallow-repository` = true no clone do marketplace, o discriminador de parentesco vira "o HEAD do clone existe no repo?" (`git cat-file -e <head>^{commit}`); existe → contagem de atraso normal; não existe → `aviso`, nunca `ALERTA` com `reset --hard`** — porquê: em clone raso a raiz do clone é o commit de fronteira, então comparar raízes sempre acusa "sem parentesco"; e sem história não se distingue commit próprio de história reescrita, logo avisar sem acusar.
- **D3 — #608, config dirs que não são conta: lista de padrões ignorados, de fábrica `*bench*` e `*.aposentada`, editável na config do plugin, aplicada às quatro checagens que enumeram `~/.claude*` (plugin instalado, versões das config dirs, skills divergentes, autocompact)** — porquê: elimina os 2 ALERTAs e 4 avisos causados por sandbox de benchmark e conta aposentada. A opção A da issue (comparar só dirs que definem o override) foi descartada — ver abaixo.
- **D4 — #587, rede vs vermelho: quando o `gh pr checks --watch` sai ≠ 0, o `esperar-ci` relê o estado com `gh pr checks --json name,bucket` e decide pelo estado, não pelo texto do erro: algum bucket `fail`/`cancel` → exit 5; a releitura também falha (rede/auth) → exit 69 com stderr começando por `nao-verificavel:`; tudo `pending`/`pass`/`skipping` → exit 69 ("espera interrompida")** — porquê: o `--watch` roda com `stdio: 'inherit'` e não captura stderr; o estado real é a fonte, e o critério da issue (stub de rede → 69, stub com `fail` → 5) segue valendo.
- **D5 — #591, repo sem CI de PR: o `esperar-ci` troca a contagem `actions/workflows` da API pela leitura dos workflows do checkout (`git ls-files .github/workflows`); um workflow conta como CI de PR se o texto cita `pull_request` (inclui `pull_request_target`) ou tem gatilho `push` sem filtro `branches`/`branches-ignore`; nenhum assim E o PR sem check → exit 8** — porquê: o GitHub dispara CI de PR com os workflows da branch do PR, então o checkout é mais fiel que a API (que lista os da branch padrão); funciona offline e testa com fixture. Leitura textual conservadora: na dúvida cai no 5 de hoje, nunca num 8 indevido. A fixture inclui o `protect-main.yml` real da #591 (`on: push: branches: [main]`).
- **D6 — #594, modelo de ameaça do gate: o gate segue fail-closed; `temMarcadorEvidencia` recebe o repo (o `--repo`/`-R` do comando, senão o repo do `cwdPorSegmento` do segmento) e passa `--repo` ao `gh issue view`; status ≠ 0 bloqueia com mensagem própria ("não consegui ler a Issue #n: <stderr>; rode de dentro do repositório ou use --repo"), distinta de "não tem evidência"; as demais consultas `gh … view` do gate são conferidas na mesma classe. Protege contra: fechar Issue por palavra-chave sem comentário de evidência. Fora: fechamento manual no site do GitHub e desligamento explícito do gate (`RAINFOREST_GATE_OFF`/config)** — porquê: liberar no erro abriria a porta; o defeito real era a mensagem que mandava comentar evidência já existente e criava laço.
- **D7 — #592: `commands/feedback.md` passa a prescrever `Segue #<n>: ...` no lugar de `CORRIGE #<n>: ...`, com teste estreito que passa a forma prescrita pela regex de palavra-chave falsa do gate e exige que ela não seja barrada** — porquê: o gate já aceita "Segue #<n>" e o teste pega a volta desta contradição exata; a varredura geral de exemplos foi plantada como ideia `exemplos-prescritos-contra-os-gates`.
- **D8 — Entrega: versão 2.0.5 em `.claude-plugin/plugin.json` e badge do README no mesmo PR; `vigias/ERROS.md` (7 linhas de 05/10 a 16/10, tiradas do PR #611 pela trava de versão) entra neste PR** — porquê: a trava `conferir-versao` exige bump para mudança executável, e o README acompanha toda entrega.

## Emendas da revisão (2026-10-27)
- **D2 vale para qualquer lado raso.** Revisor A: com a FONTE rasa (checkout de CI) e o clone completo, a raiz daqui é a fronteira e a comparação acusava "sem parentesco" com `reset --hard` — o mesmo defeito invertido. O discriminador por `cat-file -e` passa a valer quando qualquer um dos dois é raso, e o aviso de raso não esconde mais o ALERTA de skill faltando. Mesma direção da D2 (avisar sem acusar), só alarga o alcance.
- **D5: `push` com `branches-ignore` ou glob conta como CI de PR.** Revisor B: `branches-ignore: [main]` e `branches: ["**"]` disparam na branch do PR, e a leitura anterior dava 8 (merge sem CI). Agora só `branches:` sem `branches-ignore` e sem `*` no texto tira o `push`; qualquer dúvida cai no 5. É o princípio que a D5 já declarava ("nunca num 8 indevido").
- **D5 (revisão 2): o filtro `branches:` só vale dentro do bloco `push:`.** Revisor da rodada 2: `branches:` de `workflow_run`, de um `with:` ou de comentário tirava um `push` sem filtro, e dava 8 indevido. Forma de fluxo (`on: push`, `push: {...}`) segue contando.
- **D4 (revisão 2): "no checks reported" na releitura é 5, não 69.** O gh 2.96 real, com o PR sem check, sai 1 com stdout vazio e a frase no stderr; o stub da bateria devolvia `[]` com exit 0 e escondia o caso. Rede caída continua 69.
- **D5 (revisão 3): `on:` de fluxo com push (`on: push`, `on: [push]`) conta sempre, e comentário de fim de linha não filtra.** Revisor da rodada 3: um `push:` de `with:`/`env:` com `branches:` tirava um `on: push` inline, e `# branches: [main]` no fim da linha também; os dois davam 8 indevido.
- **D5 (revisão 4): a leitura do filtro é dos filhos diretos do `on:` de topo, não de todo `push:` do texto.** Revisor da rodada 4: `on:` em várias linhas (`- push`, `[push]`, `push: {}`) com um `push:` de `with:` filtrado ainda dava 8. Remendar forma a forma não fechava a família; agora o filtro só vale na forma exata (`on:` em bloco → `push:` sozinho → `branches:` de nomes fixos), e qualquer outra forma que cite push conta.
- **D5 (revisão 5): glob de branch é `*`, `?`, `+` e `[...]`, procurado só no valor de `branches:`.** Revisor da rodada 5: `fluxo/[a-z]` e `fluxo/?` passavam por nomes fixos e davam 8. O `*` de `paths:` deixa de contar, porque não é filtro de branch.

## Avaliado e descartado
- **#608 opção A (comparar autocompact só entre dirs que definem o override)**: esconde exatamente o caso que a checagem existe para pegar — uma conta real editada e a outra esquecida (dir sem override é "usa o padrão", que é a divergência).
- **#587 por padrão de stderr**: o `--watch` é chamado com `stdio: 'inherit'`, então o stderr não chega ao script; e texto de erro do `gh` muda entre versões. Reler o estado é independente do texto.
- **#591 por runs históricos (`actions/runs?event=pull_request`)**: workflow de PR recém-criado, sem run ainda, com o check do PR não registrado no momento da consulta, daria 8 indevido — merge sem CI. A leitura do `on:` erra para o lado seguro.
- **#591 pela API de workflows com conteúdo remoto**: lista os workflows da branch padrão, não os da branch do PR, e depende de rede.

## Fora de escopo
- Varredura geral de exemplos prescritos contra os gates (P2 da #592) — plantada como `exemplos-prescritos-contra-os-gates`.
- #541 e #543 (CI lento e teste flaky do teto de despachos), #606, #609, #610 (catraca de mutação e portaria) — próximo lote.
- Parser YAML completo dos workflows — a leitura textual conservadora basta para o veredito 8 vs 5.

## Varredura
docs/rainforest/varredura/2026-10-27-ferramentas-do-fluxo.txt — achou a ideia `esperar-ci-rede-vs-vermelho` (plantada em 13/10, mesma coisa que a #587; o `ao_colher` dela sugeria ler o stderr, o que D4 substitui por reler o estado) e a #576 fechada, cujo conserto (contar workflows) a #591 corrige. Nenhum PR ou branch em voo sobre as peças. A ideia será colhida no fechar.

## Em aberto
- (vazio)
