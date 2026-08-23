# Agente arqueologo: passadas e triagem para fontes legados grandes

## Objetivo

Dar à skill `arqueologia` um agente que execute a extração, e os dois mecanismos
que faltam para ela servir a fonte legado grande de verdade — triagem antes de
ler, e fatia dentro de um arquivo só. Caso motivador: `templates/OG/.../IAG67M12.prw`
no `inovacao`, 13.691 linhas e 219 funções, e `templates/Expordics/updiag.prw`,
27.991 linhas e 481 campos declarados.

## Decisões fechadas

- **D1 — Um agente `arqueologo`, não cinco papéis** — porquê: no rainforest um arquivo em `agents/` e uma funcao, com entregavel e parada proprios. Scout, Archaeologist e Detective do `sandeco/reversa` tem o MESMO entregavel (fragmento de mapa com CONFIRMADO/INFERIDO/LACUNA e arquivo:linha) e a mesma parada — sao passadas, nao funcoes. Cinco arquivos duplicariam bloco de worktree, `perfil-de-trabalho` e escala de confianca em tres lugares que divergem no primeiro ajuste. E fatia paraleliza, passada nao: com um agente se despacham N blocos em paralelo; com cinco papeis fixos ha uma fila.
- **D2 — O metodo das tres passadas (superficie, mecanismo, regra implicita) mora na `Skill(arqueologia)`; o agente a carrega** — porquê: `/arqueologia` roda na janela e o agente roda despachado; metodo no agente faz os dois divergirem. Precedente exato: `agents/depurador.md` executa a `Skill(depurar)` em vez de duplica-la.
- **D3 — A triagem e um script deterministico (`scripts/triagem.cjs`), nao uma passada de LLM** — porquê: a triagem que separou `updiag` de `IAG67M12` foi `wc -l`, contagem de `function` e linha mais repetida — tres medidas, zero julgamento. Medida que script da de graca nao deve custar chamada de modelo, e script nao mente sobre o que mediu.
- **D4 — A triagem so mede e classifica; a estrategia de leitura fica com a janela** — porquê: script que recomenda acao vira script que decide, e a decisao fica enterrada num `if` que ninguem revisa. Medida e fato e envelhece bem; estrategia e julgamento e muda com o caso. Mesma divisao que o `estado.cjs` ja faz: registra, nao escolhe o proximo estagio.
- **D5 — O agente grava o fragmento dele direto em `docs/rainforest/mapas/<fatia>/<bloco>.md`; a janela consolida** — porquê: com N blocos em paralelo sobre 219 funcoes, devolver o texto pela mensagem joga o mapa inteiro dentro da janela, que e o custo que o despacho existe para evitar. A restricao da skill (escrita so em `docs/rainforest/mapas/`) continua valendo, entao o agente segue sem poder tocar em fonte.
- **D6 — Fragmento e permanente: a pasta fica e o `COBERTURA.md` passa a indexar pasta alem de arquivo** — porquê: consolidar 219 funcoes num arquivo unico recria o que a arqueologia existe para evitar — documento que nao cabe numa sessao, e que a reconferencia tem de reler inteiro para checar um `CONFIRMADO`. Com pasta, reconferir um bloco custa um bloco. O preco aceito e o `COBERTURA.md` aprender dois formatos.
- **D7 — Fatia dentro de um arquivo se identifica por funcao ancora (`IAG67M12.prw#A67ValidSaldo`), com a faixa de linhas anotada so como referencia** — porquê: faixa de linhas apodrece no primeiro `#include` que entra no topo, e a reconferencia acusaria divergencia em 219 funcoes de uma vez. Nome de funcao sobrevive. Renomear a funcao ja cai na segunda saida da tabela de conferencia da skill ("a referencia mudou, o comportamento nao"), entao nao precisa de caso novo.
- **D8 — A passada de regra implicita grava numa secao `## Regras implicitas` do proprio mapa, nao num artefato `adrs/` separado** — porquê: regra extraida de legado e quase sempre `INFERIDO`, porque quem escreveu nao deixou o porque. Arquivo chamado `adrs/` da a essa inferencia aparencia de decisao registrada — o `INFERIDO` disfarcado de fato contra o qual a propria skill avisa. Dentro do mapa ela herda a escala de confianca e fica sujeita a reconferencia.

## Avaliado e descartado

- **Adotar o Discovery do `sandeco/reversa` como esta (5 agentes, base inteira)** — o reversa extrai a base toda (`inventory.md`, `erd-complete.md`); a skill tem trava dura de fatia. Filosofias opostas, e a da fatia e a que serve ao modo de trabalho aqui. Alem disso o reversa sao dez Teams com fluxo proprio (Ideation, Forward, Migration), concorrente ao rainforest, nao peca encaixavel.
- **Copiar a escala de confianca do reversa** — nao ha o que copiar: 🟢CONFIRMED/🟡INFERRED/🔴GAP (README l.392-394) e identica a CONFIRMADO/INFERIDO/LACUNA (`SKILL.md:31-34`). Convergencia independente, nao novidade.
- **Deriva de mapa por adendo, como o `/reversa-sync`** (README l.376, "Original extraction artifacts are never edited") — a reconferencia da skill, com `## Divergencias desta rodada` e `## Arquivadas`, resolve melhor: adendo acumula sem nunca desconfiar do antigo.
- **Agente `arqueologo` "magro", so executando a skill como esta** — recomendacao inicial, derrubada pela medicao: com 219 funcoes de regra de negocio implicita num arquivo, a passada de regra implicita e o motivo de existir do agente, nao um extra. E a trava de fatia da skill pressupoe "quais arquivos", nao "qual comportamento dentro de um arquivo".

## Fora de escopo

- Artefato visual (C4, ERD, maquina de estado em Mermaid) e matriz de rastreabilidade codigo-spec — o reversa tem, aqui nao entra nesta rodada.
- Mapear o `inovacao` de verdade: a prova desta entrega roda sobre copia no temp. Mapa real la depois, em worktree de la, sob demanda.
- Conserto da chave de projeto da memoria — trabalho separado, branch `chave-de-projeto-da-memoria`.

## Em aberto

- Quantas classes a triagem precisa e com que limiares numericos — aguardando a medicao dos 628 fontes do `inovacao`.
- Teto de um bloco de fatia (quantas funcoes cabem) — mesma medicao.
