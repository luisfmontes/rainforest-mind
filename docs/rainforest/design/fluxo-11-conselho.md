# Design — Fluxo 11: Conselho (formato canônico para o checador)

Este arquivo é a forma canônica (`conferir-fluxo.cjs design/cobertura`) do
design consolidado em `docs/rainforest/design/fluxo-11-design-conselho.md` —
leia aquele para a narrativa completa, origem (karpathy/llm-council, sem
licença — idea-mining, nenhuma linha copiada) e a emenda Q2. Divergência entre
os dois se resolve a favor do consolidado; este existe para dar às decisões o
identificador `D<n>` que o plano referencia.

## Objetivo

Debate estruturado de decisões de design antes do plano — o ponto do fluxo em
que uma escolha errada ainda é barata. Três fases mecânicas (pareceres →
revisão anonimizada → síntese) com catracas por exit code contra os dois modos
de falha de comitês de LLM: convergência de instâncias do mesmo modelo e
consenso fabricado. Membros são executáveis declarados, o que permite modelos
de treinamento distinto (Claude, Codex, Gemini) com erro descorrelacionado.

## Decisões fechadas

- **D1 — Passo opcional do estágio `design`, ativado pela presença de `.rainforest/conselho/`.** Não é fluxo independente no grafo (Q1, fechada pelo Luís em 2026-08-31, recomendada do índice consolidado v2). Padrão opt-in das rubricas.
- **D2 — Três fases serializadas em JSON no diretório da rodada** `.rainforest/conselho/<id-rodada>/`: `conselho.cjs abrir --questao <arquivo.md>` gera um prompt-arquivo por membro; cada membro produz `parecer-<membro>.json` (`posicao`, `argumentos`, `objecoes`, `riscos`); `conselho.cjs revisar` distribui os pareceres alheios anonimizados e colhe `revisao-<membro>.json` (ranking total + crítica por parecer); `conselho.cjs sintetizar` valida, agrega e grava `sintese.json` (`decisao_recomendada`, `fundamentos`, `divergencias_nao_resolvidas`, `ranking_agregado`). `conselho.cjs conferir --fase <f>` é o CHECK determinístico de cada portão.
- **D3 — Catracas por exit code, nunca por pedido.** `objecoes: []` reprova citando o membro (defesa contra convergência Claude-com-Claude); ranking incompleto ou com empate reprova; síntese sem `divergencias_nao_resolvidas` e sem `--unanime` explícito reprova; terceira tentativa consecutiva reprovada na mesma fase registra **ABANDONA** no estado.
- **D4 — Anonimização é função do script, não instrução de prompt.** Embaralhar e renomear (membro-A/B/C) antes da fase 2, com teste provando que a identidade da persona não vaza nos arquivos da fase 2.
- **D5 — Chairman mecânico.** Agregação de ranking (posição média, desempate por contagem de primeiros lugares) é código puro, testável sem modelo nenhum, separado do passo de redação — a bateria não depende de LLM.
- **D6 — Personas v1: `cetico`, `arquiteto`, `usuario-final`.** Persona é papel (prompt de membro); conhecimento de domínio, quando preciso, vem de skill — mesma separação do design de territórios.
- **D7 — Contrato de membro: executável declarado em config, nunca modelo hard-coded.** `{nome, cmd}` com placeholders `{prompt}` (caminho do arquivo de prompt) e `{saida}` (caminho do JSON a escrever), exit 0 em sucesso; spawn via `child_process` com shell explícito por plataforma; JSON inválido reprova com mensagem apontando o campo.
- **D8 — Adaptadores `codex` e `gemini` entram na v1 como integração declarável DESLIGADA por padrão** (Q2, emenda de 2026-08-31); os três membros Claude são os únicos ligados por padrão, e o dev sem CLIs externos usa o conselho exatamente como a v1 original. O liga/desliga aparece no `/setup`; os `cmd` padrão dos externos embutem os fatos operacionais medidos em 2026-08-31 (codex: `exec -s read-only --skip-git-repo-check` com stdin fechado; gemini: `-m` fixado no melhor modelo da chave, `--skip-trust --approval-mode plan`, stdin fechado; credencial vem de fonte do dev, nunca de arquivo versionado).
- **D9 — Membro ligado e indisponível reprova a fase (falha fechada).** Saída vazia, exit ≠ 0 ou erro de API depois dos retries não é parecer — nunca "segue com os que responderam"; ausência se resolve desligando o membro, não silenciando a falha.
- **D10 — Portão de quórum: N ≥ 3 membros ligados, conferido na abertura da rodada.** Fase 2 é inexistente com N=1 e degenerada com N=2; reprovação lista os membros ligados.
- **D11 — Baterias usam membros-fixture** (scripts que escrevem JSON conhecido, bom e ruim) e nunca dependem de CLI externo instalado; codex/gemini reais entram só na validação manual final.
- **D12 — `/saude` ganha seção do conselho** (rodadas abertas, ABANDONAs) no padrão do fluxo 3: item só quando há o que dizer, quebrado é `aviso` (exit 0), nunca `alerta`.
- **D13 — Atribuição obrigatória a karpathy/llm-council** no cabeçalho de `conselho.cjs` e nos docs; o repo original não tem licença — nenhuma linha de código é reaproveitada.
- **D14 — Zero dependência npm; `path.join` sempre; Windows é requisito** — a suíte roda igual em Linux e Windows.

## Avaliado e descartado

- **Debate multi-rodada com convergência:** valor marginal baixo, custo triplica; reavaliar se a síntese acumular divergências recorrentes.
- **Ranking com notas numéricas:** ordem total simples basta; notas convidam falsa precisão.
- **Anonimização criptográfica:** embaralhamento + renome basta no caso solo; não há adversário real.
- **UI web e OpenRouter do original:** o rainforest-mind é CLI, solo, zero-dependency.
- **OAuth Google (Code Assist individual) para o gemini:** descontinuado pelo Google (`UNSUPPORTED_CLIENT`, medido em 2026-08-31); a via é `GEMINI_API_KEY`.

## Fora de escopo

- **`sabotador` como quarto membro** — entra quando existir como agente no backlog criativo.
- **Motor de portões (fluxo 6)** — o conselho declara os portões; não altera nem implementa o motor.
- **Fluxo 7 (`nao_provado`)** — só o padrão do campo é reutilizado (`divergencias_nao_resolvidas`); não há código a esperar.
- **Retorno de veredito pela ponte** — modelos externos participam como membros locais; nenhum caminho de volta por repositório alheio.

## Em aberto

- Nenhuma — Q1 e Q2 fechadas em 2026-08-31 (registradas no consolidado e no estado da rodada).
