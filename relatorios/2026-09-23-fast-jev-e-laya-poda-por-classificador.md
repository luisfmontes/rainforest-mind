# fast-jev-compaction + Laya: poda de contexto por classificador, e onde o par quebra

Data: 2026-09-23. Pedido do usuario: analisar em profundidade, **pelo código e não pelo
README**, dois repos que ele trouxe como complementares — `tamaratran/fast-jev-compaction`
e `mizorewww/laya-coreml` ("versão free do Jev").

**Âncora declarada antes do veredito:** compaction do Claude Code que perde informação
(caminho, erro exato, restrição) ao resumir, e a economia de token na janela. É a mesma
dor das memórias `autocompact-nao-respeita-override-com-1m` e
`handover-quando-contexto-alto`.

## O que foi lido e rodado

- fast-jev: `src/` inteiro (`state.ts`, `compact.ts`, `request.ts`, `client.ts`,
  `types.ts`), `hooks/fast-jev.ts`, `plugin.json`, e o contrato de `session.compact` em
  `types/claude-code.d.ts:7183-7285`. `npm ci && npx vitest run` → **29/29 verdes**;
  `npx tsc --noEmit` → exit 0.
- laya-coreml: `agent.py`, `ane.py`, `common.py`, `prompt.py`, `result.py`, `inputs.py`,
  `hub.py`, `cli.py`, `torch_model.py`. Não rodado: exige macOS 15 + Apple Silicon.
- Upstream `NandhaKishorM/laya`, clonado para conferir `laya/serve.py` e
  `laya/common.py`.

## fast-jev-compaction — o mecanismo

Não resume nada. Poda **pares tool_use/tool_result** e deixa todo o resto verbatim:

1. Pareia cada `tool_use` com o `tool_result` por `tool_use_id` (`state.ts:62-93`). A
   primeira mensagem e as `preserveRecentMessages` (6) últimas ficam fixas.
2. Monta um `state` com a conversa inteira, com os resultados trocados por uma nota
   (`ok, 4213 chars (omitted)`), e encaixa em 25k tokens estimados numa escada de sete
   degraus (`state.ts:195-304`): inputs cortados em 1000/200/60 caracteres → textos
   abreviados em cabeça+cauda → mensagens velhas viram `[… N chars omitted …]` → calls
   velhas viram uma linha → mensagens sem call saem → calls consecutivas se fundem → throw.
3. Duas perguntas `noul` por call (`compact.ts:56-67`): a **call** ainda importa? o
   **resultado** ainda precisa ficar verbatim?
4. Decisão em três vias contra `keepThreshold` 0,5 (`compact.ts:101-115`): mantém tudo /
   mantém a call e trunca o resultado a 300 chars + nota / apaga o par.
5. Reconstrói preservando **identidade de objeto** do que não mudou (`compact.ts:149-225`),
   o que no hook vira preservação do `handle` do engine (`hooks/fast-jev.ts:130-157`).
6. O hook cai para o resumo nativo (`next(event)`) em qualquer erro **ou** se a redução
   ficar abaixo de 25% (`hooks/fast-jev.ts:271-277`).

O estimador de tokens sem tokenizer (`state.ts:28-38`: palavra = 1 token a cada 6 letras,
dígito = 0,5, símbolo = 0,9) é um achado à parte — calibrado para errar **para cima**.

### Achados de código

- **O juiz decide sem ver o que está julgando.** O resultado vai ao Jev só como tamanho;
  se a saída de um `Bash` tinha o erro exato, o modelo só sabe disso pelo texto do
  assistente que veio depois. É por construção, e o README não diz.
- **Não filtra `trigger`.** O hook roda também em `precompute` (`claude-code.d.ts:7285`),
  que é compaction especulativa — gasta requisição paga sem compaction nenhuma acontecer.
- **`turn.complete` chama `$.session.compact()` a 60%** (`hooks/fast-jev.ts:292-307`):
  segunda política de autocompact por cima da do engine. Com a memória do bug do override
  `[1m]`, são duas réguas brigando.
- **O plugin não expõe `baseUrl`.** A biblioteca aceita (`client.ts:10`), mas o hook monta
  o request sem ele (`hooks/fast-jev.ts:94`): apontar o plugin para um servidor Laya exige
  patch.
- **Privacidade:** a conversa inteira, com inputs de tool, vai para `api.typesafe.ai`. Para
  sessão de trabalho, é código de cliente saindo para um terceiro.
- Depende de function hooks **early access** (`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`, tipos
  gerados no 2.1.274; a máquina está no 2.1.280). `package.json` 0.2.0 ≠ `plugin.json`
  0.3.0. 17 dos 30 commits são do Devin AI; repo criado em 17/09.

## laya-coreml — o que ele é, e o que não é

Port de terceiro do **Laya** (Convai Innovations, Apache-2.0) para Core ML / Neural
Engine. O Laya é um ModernBERT/mmBERT (322M–421M) com cabeça de decisão: responde
`choice`/`score`/`noul` num único forward pass, sem gerar token, marcando cada opção com
um `[MASK]` e pontuando o hidden state dele (`torch_model.py:192-222`). A resposta sai no
formato do Jev — o método se chama `system_one` (`result.py:10`).

- **O "Jev free" é o upstream, não este repo.** Quem expõe `POST /v1/systemone` é
  `NandhaKishorM/laya/laya/serve.py`; o campo `model: 'jev-latest'` que o fast-jev manda
  cai em auto-roteamento (`serve.py:51-64`), então o formato de fio bate de verdade.
- **laya-coreml não roda na máquina do usuario** (Windows): `coremltools` + macOS 15 +
  Apple Silicon. O upstream roda em PyTorch CPU/CUDA e tem `Dockerfile`/`compose.cuda.yaml`.
- O headline de **5 ms** é do bundle ANE de **96 tokens** no total — o único que não serve
  para compaction. O bundle de 1024 tokens a 1024 leva ~91,7 ms (README deles, não conferido).
- Engenharia honesta: gates de fidelidade (189/189 contra o upstream), variantes de 6 e 4
  bits **reprovadas e não publicadas**, e o clamp de temperatura (`common.py:127-175`) —
  o checkpoint vem com `choice:11+` = 0,1006, que transformaria 0,24 em 0,99 de confiança.
  Isso vale para quem usar o upstream também.
- Números Laya 0,766 vs Jev 0,727 de acurácia e "6-7× mais rápido": **[README, não conferido]**.

## Onde o par quebra: a janela

O fast-jev manda o histórico inteiro como estado (até 25k tokens, feito para os 32k do
Jev). O Laya tem teto de 512/1024 tokens, e `build_sequence` (upstream `common.py:82-86`,
igual em `laya-coreml/common.py:100-106`) corta o estado **pela cauda, sem erro**
(`truncate_left=False`). O modelo recebe a pergunta sobre `t40` e responde com
probabilidade calibrada sem nunca ter visto `t40`. Só o bundle ANE de 96 levanta erro.

Medido com o próprio `fitState` do fast-jev, numa sessão sintética de 40 calls:

```
estado estimado: 4117 tokens, estagio: full , candidatos: 37
janela de 900 tokens de estado ve 7/40 calls: t1,t2,t3,t4,t5,t6,t7
janela de 70 tokens de estado ve 0/40 calls:
fitState(900): history too large for Jev (~2752 tokens after truncation, limit 900)
```

(Tokens pelo estimador do fast-jev, não pelo tokenizer do mmBERT — ordem de grandeza.)

Numa sessão modesta, 30 das 37 decisões seriam dadas às cegas, e a cara da resposta seria
a mesma. **O par não é plug-and-play.** Para funcionar, o estado tem de ser **por
pergunta**: objetivo + a call em questão + a vizinhança dela + o que veio depois que a cita
— um request por call, que no Laya custa 2 forwards de ~33 ms. É um redesenho do
`fitState`, não uma troca de `baseUrl`.

## Vereditos

- `tamaratran/fast-jev-compaction` — **Instalar → Enxertar: enxerta.** Instalar reprova
  em 3 (custo: API paga, e a conversa sai para terceiro) e 6 (early access + repo de 6 dias
  majoritariamente escrito por bot). A peça enxertável é a **política**, ~300 linhas MIT:
  pino do primeiro + N últimos, duas perguntas por call, decisão em três vias, invariante
  "resultado nunca sem a call", fallback com redução mínima, e o estimador de tokens.
  Acrescenta às ideias já plantadas `poda-de-resultado-com-invariante-de-convergencia`
  (deepseek, heurística fixa) e `contrato-de-compressao-do-headroom-reimplementado`
  (proxy): aqui quem decide é um **classificador**, e o que fica é verbatim.
- `mizorewww/laya-coreml` — **Instalar → Enxertar → Ler: vale voltar.** Reprova em 4 de
  Instalar (só Apple). Enxertar não tem peça para Windows: o que ele tem é o grafo ANE. Vale
  voltar pelo método de gate de fidelidade e pelo clamp de temperatura. O repo operante para
  este usuario é o upstream `NandhaKishorM/laya`, **não avaliado aqui** além de `serve.py`
  e `common.py`.

Decisão pendente com o usuario: plantar ou não o enxerto da política como ideia.
