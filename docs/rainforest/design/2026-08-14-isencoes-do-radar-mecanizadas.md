# Isenções do radar mecanizadas — a regra 3 para de cobrar quando não deve

## Objetivo

A regra 3 tem duas isenções escritas, e nenhuma das duas é computada por nada: o
radar cobra desvio de escopo em toda sessão, inclusive quando o foco está sendo
trabalhado em outra janela e inclusive fora do expediente. Esta entrega faz o
hook **decidir** essas duas condições e emitir o veredito, em vez de deixá-las
como prosa que o modelo deveria aplicar sem ter o dado.

## Decisões fechadas

- **D1 — As duas isenções entram na mesma entrega** — porquê: elas compartilham o mecanismo (o hook computa uma condição e emite veredito), e meia mecanização é pior de ler que nenhuma: vendo o radar cobrar, não se saberia se é defeito ou se aquela metade não existe.

- **D2 — O foco declara as pastas em campo explícito no FOCO.md, aceitando lista** — porquê: hoje o projeto do foco é prosa (`Projeto: worktree \`gestao-projetos-template\``), e casar isso com o `cwd` das sessões exigiria heurística de nome, que erra em silêncio quando dois repos têm pasta parecida. Lista desde já porque um foco pode viver em repo e worktree ao mesmo tempo, e trocar campo único por lista depois custaria migrar o FOCO.md. Há precedente de campo extraído do FOCO.md por regex: a `Ociosidade máxima`, em `hooks/foco-session-start.cjs:196`.

- **D3 — O hook emite VEREDITO, não fato** — porquê: o fato **já é emitido hoje** — o bloco "Outras sessões recentes" lista `cwd` e minutos de cada janela — e mesmo assim o radar cobrou em toda sessão. Dar mais fato ao mesmo mecanismo que já falhou é esperar resultado diferente. Neste repo o que muda comportamento é imperativo ou exit code, não contexto para ponderar.

- **D4 — O expediente mora no `config.json`, escopo usuário** — porquê: expediente é do usuário, não do foco. Declarar por foco significaria redeclarar a cada troca, e esquecer numa delas devolve o problema. O `scripts/setup.cjs` já escreve nesse arquivo, com `--escopo projeto|usuario`.

- **D5 — O veredito é uma linha imperativa; o bloco do foco permanece** — porquê: o bloco carrega prazo e critério de pronto, que servem a outras coisas. Suprimi-lo esconderia isso e deixaria a sessão sem saber que existe foco. O veredito é sobre **cobrar**, não sobre **mostrar**.

- **D6 — Falha fechada: sem dado, cobra — e a ausência se anuncia em uma linha** — porquê: radar mudo por falta de config é indetectável, e o usuário nunca saberia que parou. Radar que cobra demais ele percebe e reclama, que foi exatamente como este defeito apareceu. O anúncio, no espírito da regra 14, é o que evita o pior dos dois mundos: nem silêncio, nem cobrança sem explicação.

- **D7 — "Foco ativo em outra janela" = sinal humano dentro da `Ociosidade máxima` que o foco já declara** — porquê: o `sessoes.json` só tem `cwd`, `prompt_ts` e `stop_ts`, então "ativa" precisa de um limiar. Reusar os 15 min já declarados evita inventar parâmetro, e os dois usos são coerentes: dentro da janela a sessão do foco está quente e isenta esta; passando dela, a própria regra 17 já quer avisar que "a janela do foco esfriou".

- **D8 — Expediente é dias da semana + faixa horária, sem feriado** — porquê: feriado exigiria fonte de calendário, que é dependência externa, envelhece e falha em silêncio. E trabalhar em feriado é escolha do usuário; o filtro de *qual* (assunto declaradamente pessoal) já cobre o caso em que ele não quer ser cobrado. Forma: `{"dias": [1,2,3,4,5], "de": "08:00", "ate": "18:00"}`.

- **D9 — A isenção de tempo pessoal cala só o aviso de DESVIO, nunca o de prazo** — porquê: o aviso de prazo é informação, não policiamento. Saber no sábado que algo vence segunda é útil e não custa nada; ser cobrado no sábado por estar lendo outra coisa é o que incomoda. A regra 3 já trata os dois em parágrafos separados.

- **D10 — Um único veredito componível, não uma linha por isenção** — porquê: aritmética de orçamento. Medido em 2026-08-14, o hook emite 7.798 B contra teto de 8.000, ou seja 202 B de folga; duas linhas independentes somariam ~205 B se disparassem juntas e estourariam. Uma linha que carrega os motivos aplicáveis cabe. O anúncio do D6 não concorre com o veredito: não há como julgar sem dado, então os dois são mutuamente exclusivos.

## Avaliado e descartado

- **Casar a pasta do foco por nome de worktree, sem campo novo** — heurística que erra em silêncio: dois repos com pasta de nome parecido, ou foco declarado por branch em vez de pasta, e o radar afrouxa na sessão errada. Erro de isenção é invisível — ninguém reclama de não ser cobrado.
- **Derivar "é tempo pessoal" do `scripts/jornada.cjs`** — ele mede jornada efetiva a partir dos timestamps das mensagens, ou seja, responde "trabalhou 5h hoje", não "agora é expediente". Derivar tempo pessoal da ausência de mensagens é circular: silêncio viraria pessoal, e o radar nunca cobraria.
- **Fonte de feriados** — dependência externa que envelhece e falha calada, para cobrir um caso que o filtro de assunto já cobre.
- **Emitir fato e deixar o modelo decidir** — é exatamente o que existe hoje, e é o que falhou: o bloco de sessões paralelas já está na injeção e o radar cobrou assim mesmo.
- **Suprimir o bloco do foco quando a isenção vale** — esconde prazo e critério de pronto, que não têm relação com cobrar desvio.
- **Falha aberta (sem dado, não cobra)** — desliga em silêncio a função central do plugin; ninguém detecta um radar que parou.

## Fora de escopo

- **Mudar a semântica da regra 3** — a elaboração dela já especifica os dois filtros (*quando* e *qual*) com precisão. O que falta é mecanizar, não redecidir.
- **O aviso de prazo na abertura** — permanece como está, por D9.
- **Calendário de feriados**, por D8.
- **A linha 117 do `ideias.jsonl`** (`observacao-radar-foco-trabalho-vs-estudo`, sem `gancho`) — foi o que levantou este trabalho, mas é dado, não código; segue bloqueando o `conferir` e é decisão do dono do arquivo.
- **Declarar a trilha de estudo como foco `[estudo]`** — proposta que mora naquela observação; é uso do mecanismo, não construção dele.

## Em aberto

- O custo real em bytes das linhas novas só se conhece depois de escritas. A estimativa que sustentou o D10 (~110 B e ~95 B) é de projeto, não medição — se o veredito real passar dos 202 B de folga do hook, a decisão de subir o teto ou cortar em outro lugar volta para o usuário, com o número medido na mão pelo `scripts/orcamento.cjs`.
