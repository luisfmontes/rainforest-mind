# Adendo ao Fluxo 5 (`poda.cjs`) — padrões validados pelo deepagents

> Status: adendo ao design existente do fluxo 5 · Não é fluxo novo
> Origem: langchain-ai/deepagents (MIT), diretório `middleware/`. Nada de código entra — é Python sobre LangGraph, stack errada. Entram os números e os formatos que eles já validaram em produção.

## Por que este adendo existe

O design do fluxo 5 (proxy de contexto) foi desenhado do zero. O deepagents implementa o mesmo padrão — offload de tool result pra disco + stub com instrução de recuperação — como middleware de produção. Onde o nosso design e o deles convergem sem combinar, é sinal de que o desenho está certo. Onde eles têm um número calibrado e nós tínhamos chute, adotar o número.

## 1. Defaults calibrados

| Parâmetro | deepagents | Adotar no poda.cjs |
|---|---|---|
| Gatilho de compactação | 85% da janela | 85% — era o que faltava definir na fase 1 |
| Quanto preservar intacto | 10% mais recente | 10% (além do estágio ativo, que é intocável) |
| Offload proativo por tool result | limiar de tamanho por chamada | manter: podar na chegada, não só na pressão |

Duas mecânicas distintas, e vale manter as duas separadas como eles fazem: **proativa** (tool result individual acima do limiar vira arquivo na hora, independente da pressão de janela) e **reativa** (compactação do histórico quando cruza 85%). A proativa é a barata e cobre o caso comum; a reativa é a rede de segurança.

## 2. Formato do stub (o template deles, traduzido)

O `TOO_LARGE_TOOL_MSG` do deepagents ensina o modelo a se servir sozinho — exatamente a decisão do nosso design de não injetar tool de retrieve. Versão rainforest:

```
[podado] Resultado desta ferramenta era grande demais e foi salvo em:
.rainforest/poda/<hash>.txt

Leia por partes com Read usando offset e limit (ex.: offset=0, limit=100).
Nunca leia o arquivo inteiro de uma vez.

Prévia (início e fim; "... [N linhas omitidas] ..." marca o meio):

<primeiras 5 linhas, numeradas>
... [N linhas omitidas] ...
<últimas 5 linhas, numeradas>
```

Detalhes que eles acertaram e valem copiar:
- **Prévia com números de linha** — o modelo já sabe o offset certo antes de ler.
- **Head E tail, 5+5** — erro costuma estar no fim, contexto no início.
- **Instrução explícita de leitura parcial dentro do stub** — sem depender de regra no SKILL.md; a instrução viaja com o dado.

## 3. Histórico despejado é append-only

No deepagents, cada evento de compactação **anexa** uma seção ao arquivo de histórico da sessão — nunca reescreve o que já foi despejado. Isso confirma a regra central do nosso design (compressão determinística e estável, prefixo nunca reprocessado) e dá o formato concreto: um `\.rainforest/poda/sessao-<id>.md` que só cresce, com uma seção datada por evento de poda. Auditável com `cat`, compatível com cache por construção.

## 4. Anotação pra depois (fora do fluxo 5)

O `rubric.py` deles avalia saída de agente contra rubrica declarada — parente do nosso `verificar` para critérios que nenhum comando decide. Com o fluxo 6 (portões), isso vira: portão manual pode ganhar uma rubrica estruturada em vez de prosa livre. **Não fazer agora** — registrar como semente de melhoria do portão manual, avaliar depois que fluxos 6 e 7 fecharem.

> **Semente encerrada em 2026-09-05.** Ela foi avaliada e **rejeitada**, e não pelos
> fluxos 6 ou 7: quem herdou esse território foi o fluxo 12 (régua), fechado em
> 2026-09-04. `docs/rainforest/design/fluxo-12-regua.md`, D5 — "o `bar.md` não altera
> o veredito binário nem a lacuna única... rubrica pontuada é o modo de falha que a
> skill inteira evita". Não reabrir sem evidência nova contra essa decisão.

## O que explicitamente não copiar

- Middleware de summarização com chamada de LLM pra resumir histórico antigo. Custo e não-determinismo; as heurísticas determinísticas do design original ficam. Se a fase 0 (medição) mostrar que heurística não basta, aí sim reabrir essa decisão — com evidência.
- Qualquer dependência do ecossistema LangChain. Zero deps continua sendo regra.

---

## Status (2026-09-05): BLOQUEADO pelo gate de evidência da fase 0

Este adendo é, do início ao fim, conteúdo de **fase 1** — números calibrados,
formato do stub, histórico append-only. A própria equipe já tinha registrado isso na
época: `docs/rainforest/estado/2026-08-31-fluxo-5-fase-0-poda.json` diz, em
2026-08-31, *"fase 0 só passthrough+medição; adendo deepagents é todo fase 1"*.

E o design original condiciona **abrir** a fase 1 — não só ativá-la — a evidência de
uso real, duas vezes: `fluxo-5-design-poda.md:53` (*"Gate de saída da fase 0:
relatório de uma semana de uso real. Sem ele, fase 1 não abre"*) e `:107-108`
(*"fases 1 e 2 só com o relatório de evidência em mãos"*).

Estado medido nesta máquina em 2026-09-05:

```
$ node scripts/relatorio-poda.cjs --json
{"gate":"FECHADO","dias_distintos":0,"faltam":7}
```

(exit 1). Não existe `metricas.jsonl` real nem no repositório nem na raiz de dados —
o proxy nunca rodou contra tráfego real, só contra fixtures de teste. Sem dado, não
há como saber se o cache hit já resolve o custo sozinho (R3) nem se a heurística
está calibrada (Risco 1) — que é exatamente o que a regra existe para impedir.

**Gancho de retorno:** o mesmo comando, outra saída. `node scripts/relatorio-poda.cjs
--json` devolvendo `"gate":"ABERTO"` (com `dias_distintos >= 7`) e exit 0. É a única
condição. A partir daí, reabrir direto no `design` do fluxo 5 — a arqueologia já foi
feita e está em `docs/rainforest/design/adendo-fluxo-5-deepagents-canonico.md`, junto
com as decisões (D1–D9) e as sete perguntas que ficam para quando houver evidência.

Até lá, nenhuma tarefa de código deste adendo entra em plano. As duas decisões que
**não** dependem do gate já foram aplicadas: a correção `colher` → `fechar` em
`fluxo-5-design-poda.md` (D4) e o encerramento da seção 4 acima (D7).
