# Memória escolhida pelo assunto: pedido, subagente e antes/depois

## Objetivo
A memória deixa de ser escolhida só pela recência na abertura da sessão e passa a chegar
também pelo **assunto**: em cada pedido digitado e no briefing de cada subagente. O relatório
de utilidade mede o antes e o depois com uma régua fixada agora, antes dos dados.

Origem: o relatório de 2026-10-08 (`memoria.cjs utilidade --relatorio`) deu `régua D9: LIGA o
ranking (171 de 255 sessões)`. A memória servida na abertura casou com o trabalho (nota ≥ 0,5)
em 69 de 255 sessões (27%), e em 30 dias só 21 sessões principais (de 4.287 transcritos) e 5
subagentes (de 855) rodaram `memoria.cjs buscar` por conta própria.

## Decisões fechadas
- **D1 — Canal do pedido: hook clássico `UserPromptSubmit`, não o `context` do `prompt.submit` do mod** — porquê: a conta de trabalho barra só `prompt.compose` e `classic.SessionStart` (`CHANGELOG.md:114`), então o hook clássico roda nas duas contas e em quem tem o plugin sem o mod (o mod pede Claude Code 2.1.292+). O input traz `prompt` com o texto enviado (doc oficial de hooks).
- **D2 — A abertura fica intacta nesta entrega: o canal novo convive com o bloco `## Memória (corpus residentes)`** — porquê: mexer nos dois ao mesmo tempo deixa o antes/depois sem causa; a régua D7 mede só o canal novo.
- **D3 — Injeção em todo pedido digitado, no máximo 3 memórias, sem repetir o que a sessão já recebeu, e só acima de um limiar de relevância** — porquê: a sessão troca de assunto no meio (a desta conversa trocou três vezes); só o primeiro pedido perderia os seguintes. O limiar bm25 é calibrado na primeira tarefa do plano sobre os transcritos reais e escrito no plano **antes** de ligar o canal; sem candidata acima dele, nada é injetado.
- **D4 — Busca em todos os projetos, com peso para o projeto atual** — porquê: o banco grava o mesmo projeto com dois nomes (`rainforest-mind` 3.182 e `C--Projetos-rainforest-mind` 1.266 observações), e memória que cruza projetos (Protheus ↔ plugin) é parte do valor.
- **D5 — Subagente: `PreToolUse` na ferramenta `Agent` busca pelo texto do briefing e acrescenta as memórias ao fim do `prompt` via `updatedInput`; a primeira tarefa prova o mecanismo, e se falhar cai para `SubagentStart`** — porquê: `SubagentStart` só recebe `agent_id` e `agent_type`, não o briefing (doc oficial de hooks); `updatedInput` substitui o input inteiro e a doc não traz exemplo para `Agent`, então é premissa a provar, não fato. No fallback, `SubagentStart` injeta por `additionalContext` a busca feita com o tipo de agente mais o último pedido da sessão.
- **D6 — O hook nunca atrapalha o pedido** — porquê: roda em todo pedido. Banco ausente, travado, FTS vazio, erro ou estouro de tempo saem com exit 0 e sem injeção; timeout curto no `hooks.json`; o bloco fica bem abaixo do teto geral de 10.000 caracteres do `additionalContext` (acima disso o harness troca o texto por um arquivo). O `updatedInput` do D5 preserva `description`, `subagent_type` e `model` inteiros.
- **D7 — Régua de sucesso, fixada antes dos dados: 14 dias depois de a versão estar viva no cache, o canal novo fica se as sessões com memória útil (nota ≥ 0,5, qualquer canal) passarem de 27% para ≥ 40% e as perdas para a recência caírem de 171/255 (67%) para ≤ 1/3; abaixo disso, o canal sai** — porquê: régua escrita depois dos dados vira ajuste ao que apareceu (mesma lógica do D9 de `2026-09-23-memoria-sinal-de-utilidade`).
- **D8 — A medição do canal novo não é tautológica** — porquê: memória escolhida por bm25 contra o pedido casa com o pedido por construção. O bloco do canal novo tem cabeçalho próprio (`## Memória do assunto`); o extrator passa a ler as servidas do `UserPromptSubmit` e do `prompt` do `Agent`, marca o canal de cada uma, e a nota de servida do canal novo é calculada **excluindo o pedido (ou briefing) que a disparou** — só o que veio depois conta.
- **D9 — O relatório separa por canal (abertura, pedido, subagente) e conta as buscas ativas (principal e subagente)** — porquê: a pergunta que originou o trabalho ("ele volta lá pra consultar, inclusive os subagentes?") vira número do relatório, em vez de contagem feita à mão sobre os transcritos.
- **D10 — Nenhum texto de sessão novo entra no banco** — porquê: mantém o D10 do design de utilidade; `uso_memoria` só ganha a coluna de canal (enumeração), sem texto.

## Avaliado e descartado
- **`context` do `prompt.submit` no mod como canal do pedido** — só funciona com o mod carregado (2.1.292+); quem usa o plugin sem o mod ficaria de fora (Q1).
- **`SubagentStart` como canal principal do subagente** — o input não traz o briefing (doc oficial), então o revisor e o executor receberiam a mesma memória; fica só como fallback do D5.
- **Injetar só no primeiro pedido** — perde toda troca de assunto dentro da sessão (Q3).

## Fora de escopo
- **A seleção da abertura** (recência) — não muda nesta entrega (D2); o ranking dela é decisão para depois da régua D7.
- **Ferramenta `buscar_memoria` registrada pelo mod** (ideia `mods-ferramenta-buscar-memoria`) — continua plantada; misturar com a injeção confunde a régua D7 (Q6).
- **Normalizar o nome duplicado de projeto no banco** — defeito de dado à parte; vira Issue própria.

## Varredura
docs/rainforest/varredura/2026-10-08-memoria-por-assunto.txt — nenhuma Issue, PR ou branch implementa injeção por pedido ou por subagente. Casou o fluxo anterior `2026-09-23-memoria-sinal-de-utilidade` (PR #326, a medição que agora deu LIGA) e três ideias: `rodar-relatorio-de-utilidade-da-memoria` (gancho 07/10, colhida por este trabalho), `memoria-sinal-de-utilidade-no-ranking` (o sinal observável já existe — `uso_memoria`) e `mods-ferramenta-buscar-memoria` (fora de escopo, Q6). Mudou o design: a régua D7 reaproveita a nota e o denominador da medição anterior, e o D8 nasceu de ler o extrator (`scripts/lib/utilidade.cjs:55`), que só conhece o bloco da abertura.

## Em aberto
