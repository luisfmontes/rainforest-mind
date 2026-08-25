# Agente auditor de API contra OWASP API Security Top 10 2023

## Objetivo

Dar ao usuário um agente que procure vulnerabilidade **em API que já existe**,
contra uma régua externa nomeada, e que reporte sem consertar. Hoje nada faz
isso: a `security-review` embutida do Claude Code só olha `git diff origin/HEAD...`
e diz textualmente *"Do not comment on existing security concerns"*, e o plugin
`rainforest-mind` não tem uma linha sobre segurança em nenhuma das 16 skills,
11 comandos ou 8 agentes.

## Procedência

Este trabalho nasceu de um vídeo que o usuário assistiu em 2026-08-24 ("cinco
falhas de segurança em SaaS feito com IA", síntese em
`~/Downloads/cinco-falhas-saas-com-ia.md`). Naquela sessão só a **falha 4**
(segredo no histórico do git) achou destino, na ideia plantada
`sabia-gitleaks-no-historico-antes-de-abrir`, porque o Sabiá era o único projeto
que casava — *"nao tem front web, nem banco multiusuario, nem rota por ID"*.
**As falhas 1, 2, 3 e 5 ficaram órfãs, e são justamente as que atingem API.**
Este agente é o destino delas.

A tese central do vídeo é o requisito de projeto mais importante daqui:

> *"a mesma IA que abriu o buraco acha o buraco — mas só se você mandar
> procurar especificamente. Pedido genérico ('acha as vulnerabilidades', 'acha
> XSS') não funciona, porque ela não conhece a regra de negócio e não foi
> ensinada a desconfiar."*

## Decisões fechadas

- **D1 — É agente, não skill, e nasce um só** — porquê: só a `description` paga
  orçamento; o corpo carrega sob demanda. Medição de 2026-08-24: folga de
  **579 B de 14000**, já abaixo do limiar de aviso de 700 B. Agente sozinho
  (~230 B; a média das 8 descriptions atuais é 225 B) deixa ~349 B; agente +
  skill (~455 B) deixaria ~124 B, que a Issue #74 já indica ser insustentável.
  O corpo pode ser gordo de graça — e vai ser.

- **D2 — A régua é a OWASP API Security Top 10 2023, nomeada categoria a
  categoria no corpo** — porquê: é a edição vigente (verificada em 2026-08-24;
  não há edição 2025/2026), o projeto é **Production** na OWASP, e as dez
  categorias são critério falsificável pronto. As categorias entram **por título
  e por descrição escrita aqui**, com link para a fonte — o conteúdo da OWASP é
  **CC BY-SA 4.0** e este repositório é MIT: cita-se e aponta-se, nunca se copia
  o texto para dentro.

- **D3 — O agente acha, e não conserta** — porquê: é a conclusão do próprio
  vídeo, *"enquanto ela está consertando, ela para de procurar"*, e já é o item
  (g) do `revisor` (*"Não conserte"*). Consertar exige decidir sobre regra de
  negócio que o agente não conhece, e num repo de cliente isso é mudança que só
  o dono autoriza.

- **D4 — A busca é dirigida por categoria, com padrão de código concreto por
  categoria — nunca pedido genérico** — porquê: é o requisito que veio do vídeo.
  Cada uma das dez categorias entra no corpo com **o que procurar em código**
  (ex.: API1 → handler que consulta pelo id do path sem cruzar com a identidade
  do token), não com a definição abstrata da OWASP.

- **D5 — Todo achado sai com `arquivo:linha`, rótulo de evidência e cenário
  concreto de exploração** — porquê: herda o item (h) do `revisor`
  (`CONFIRMADO` / `INFERIDO` / `LACUNA`), com `CONFIRMADO` exigindo a linha
  colada. Achado de segurança é acusação, e acusação inferida queima a
  credibilidade das outras. Sem cenário concreto (quem chama o quê, com que
  entrada, e o que recebe de volta) não é achado, é opinião.

- **D6 — O relatório é obrigado a ter uma seção por categoria, API1 a API10,
  inclusive as que não acharam nada** — porquê: é a trava contra a Issue **#61**
  (*"o agente não burla o critério — ele o SUBSTITUI por um mais barato e
  devolve com o número do original"*). Um agente que recebe "rode a OWASP Top
  10" e devolve "revisei, está tudo certo" trocou dez varreduras por uma
  impressão. Categoria sem seção = entrega incompleta, e a seção precisa dizer
  **o que foi procurado** quando não achou.

- **D7 — Análise estática, leitura de código. O agente não manda requisição a
  endpoint nenhum** — porquê: os alvos do usuário incluem ambiente de **cliente**
  (Protheus/TOTVS), e disparar tráfego contra sistema de terceiro sem
  autorização escrita é ilegal na maioria das jurisdições. Vale a regra 15
  (ninguém altera o ambiente do usuário) estendida: nem o de terceiro.

- **D8 — Segredo se reporta por nome de variável e `arquivo:linha`, nunca
  transcrevendo o valor; e a varredura inclui o histórico do git** — porquê:
  transcrever segredo em relatório multiplica o vazamento em vez de contê-lo. E
  o histórico entra porque a `security-review` embutida exclui segredo **por
  escrito duas vezes** (HARD EXCLUSION #2, e *"these are handled by other
  processes"*) — e esses "other processes" **não existem nesta máquina**. É a
  falha 4 do vídeo, a única que já tinha destino.

- **D9 — Modelo `sonnet`** — porquê: é função de julgamento, mesma classe de
  `revisor`, `tester` e `depurador`. Achado de segurança falso-positivo custa
  mais caro que o token economizado com `haiku`.

- **D10 — O alvo de validação é o `tbc-licensing`, em leitura** — porquê: é API,
  é do usuário, e a regra 12 exige validar na saída real. "O agente ficou
  pronto" não é entrega; "o agente rodou no `tbc-licensing` e devolveu achados
  com `arquivo:linha` conferíveis" é.

- **D11 — O `strix` fica fora desta entrega, registrado como fase 2** — porquê:
  ele é a única coisa que fecharia o vazio *"nada valida em execução"*, e a
  revisita do batedor em 2026-08-24 derrubou a reprovação de 11/08 (ele testa
  API de verdade: `strix/utils/api_spec.py` reconhece OpenAPI/Swagger/Postman
  como tipo de alvo de primeira classe). Mas exige Docker de 1,44 GB, e a trava
  de autorização dele é **só texto**: `strix/core/inputs.py:223` crava
  `"authorization_source": "strix_platform_verified_targets"` a partir do que
  veio no `--target`, e o system prompt manda `NEVER ask for permission or
  confirmation`. Entra depois, opt-in, em staging do usuário — nunca em
  ambiente de cliente.

- **D12 — O conserto do `skills/fechar/SKILL.md` entra neste mesmo trabalho** —
  porquê: dois defeitos, os dois de custo zero em orçamento (corpo de skill não
  é injetado), e sozinhos não pagariam um fluxo próprio. São: (a) o passo 4
  ainda oferece "merge / PR / manter" com **"Não decida por ele"** em negrito,
  contra a decisão já tomada de que destino de branch é sempre PR; e (b) a skill
  não diz que o corpo do PR precisa da palavra-chave de fechamento **em inglês**
  — foi o que deixou as Issues #81 e #79 abertas depois do merge do PR #85 em
  2026-08-24, com o corpo dizendo "Fecha #81 e #79", que o GitHub ignora.

## Avaliado e descartado

- **Pendurar a régua na skill `regua`** — descartado por leitura do mecanismo:
  o loop dela é builder contra **crítico cego** devolvendo veredito **binário
  A ou B** entre dois artefatos rivais, e OWASP não é artefato rival da API do
  usuário, é taxonomia. O crítico devolveria "A ou B", não "API3 presente, API5
  ausente". E a própria skill se exclui: *"Se a tarefa tem teste, o teste é a
  régua e esta skill é overhead puro"*, com gatilho *"você não consegue escrever
  a frase 'isto está pronto quando ___'"* — para OWASP essa frase se escreve
  item por item.

- **Usar o `OWASP/www-project-agentic-skills-top-10` como régua desta entrega** —
  descartado por medição: busca nos 465 KB de markdown do repo devolveu
  `BOLA: 0`, `Broken Object Level: 0`, `Broken Authentication: 0`, `JWT: 0`,
  `mass assignment: 0`. "API" só aparece lá como credencial roubada e como
  documento lido pelo agente, nunca como superfície auditada. Ele é a régua
  certa para **outra** pergunta (segurança de skill/agente) e fica plantado
  como tal.

- **Habilitar o `security-auditor` do plugin `code-modernization`** (o único
  artefato em disco que já ancora em OWASP + CWE) — descartado porque está na
  config dir de **trabalho** e não em `enabledPlugins` de nenhuma das duas;
  ligá-lo é alterar o ambiente do usuário (regra 15) e traria injeção fixa do
  plugin inteiro, não do agente sozinho.

- **Estender o agente `revisor` em vez de criar um novo** — descartado porque
  mistura dois vereditos: o `revisor` decide "integra ou não integra" um diff, e
  este decide "onde esta API está exposta". Segurança aparece no `revisor`
  apenas como terceiro degrau da escala de severidade (*"quebra/corrompe >
  comportamento errado > risco/segurança > dívida"*) — isso ordena achado, não
  procura achado.

## Fora de escopo

- Consertar o que o agente achar. O agente aponta; consertar é trabalho
  separado, com a autorização de quem é dono do repo.
- Rodar qualquer ferramenta contra alvo vivo (OWASP ZAP, strix, scanner de
  rede). Fase 2, opt-in, staging próprio.
- Segurança de skill/agente (prompt injection, tool poisoning). É a outra régua,
  plantada como ideia.
- ADVPL/TLPP por dentro. Endpoint REST de Protheus entra como superfície HTTP
  se e quando o usuário apontar; ler o fonte `.prw`/`.tlpp` é outra entrega, e o
  `protheus-toolkit` já tem SEC-01 para SQL injection lá.
- Instalar Gitleaks, Semgrep ou qualquer binário. A varredura de segredo é por
  leitura e por `git log`, com as ferramentas **nomeadas como recomendação** no
  relatório.

## Em aberto

- Nenhum. As decisões D1 a D12 foram tomadas pela sessão sob a autorização
  explícita do usuário em 2026-08-24 ("faz o recomendado para tudo; amanhã vou
  avaliar o resultado antes do merge"), e **cada uma é contestável na revisão do
  PR** — foi por isso que cada D carrega o porquê e a medição que a sustenta.
