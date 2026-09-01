# Fluxo 5 — Design: `poda.cjs` (proxy de contexto)

> Status: design · Depende de: fluxo 1 fechado (estado.cjs endurecido) · Alvo: Claude Code via `ANTHROPIC_BASE_URL`

## Problema

Sessões longas de `executar` incham a janela de contexto com tool outputs (bash, grep, leituras de arquivo) que já cumpriram seu papel. Isso custa token, degrada foco do modelo e encarece cada turno. Soluções prontas (Headroom) existem, mas: repositório de terceiro (lição do claude-mem), issues abertas de Windows, e são genéricas — não conhecem o pipeline.

## Princípios (regras da casa)

1. **Node puro, `.cjs`, zero dependências.** Só `http`, `https`, `crypto`, `fs`, `path`.
2. **Windows-first.** `127.0.0.1` (nunca `0.0.0.0`), `path.join` sempre, sem sudo, sem unix-only. Testar em PowerShell e cmd.
3. **Mecânico, não instrucional.** O proxy decide por regra, não por prompt.
4. **Evidência antes de otimização.** Fase 0 só mede. Compressão só entra depois que os números mostram onde o token vai.
5. **Reversível sempre.** Nada comprimido é perdido — original vai pra disco.

## Arquitetura

```
Claude Code ──ANTHROPIC_BASE_URL──▶ poda.cjs (127.0.0.1:4141)
                                      │  reescreve SÓ o body do request
                                      │  headers (auth) passam intactos
                                      ▼
                              api.anthropic.com
                                      │
                                      ▼  response passa DIRETO (SSE intacto)
                                 Claude Code
```

- **Request-only rewrite.** A resposta nunca é tocada — streaming SSE atravessa byte a byte. Isso elimina response handler, tool injection e metade da complexidade do Headroom.
- Um arquivo, `scripts/poda.cjs`, alvo de ~300 linhas.
- Liga/desliga: `poda.cjs iniciar` / `poda.cjs parar` + instrução de env var pros dois mundos:
  - PowerShell: `$env:ANTHROPIC_BASE_URL="http://127.0.0.1:4141"`
  - bash/zsh: `export ANTHROPIC_BASE_URL=http://127.0.0.1:4141`

## Regra de ouro: o cache manda

Cache da Anthropic exige prefixo byte-idêntico (cache read ≈ 10% do preço). Portanto:

- **R1.** Nunca reescrever blocos que já foram enviados numa forma. Compressão acontece **uma vez**, quando o bloco entra, e é determinística — mesmo input, mesmo output, sempre.
- **R2.** Exceção única e controlada: **fronteira de estágio**. Quando `fechar` aprova um estágio, o proxy pode podar o transcript daquele estágio inteiro. Quebra o cache uma vez, num momento raro e previsível, e o prefixo re-estabiliza no request seguinte. Nenhum proxy genérico pode fazer isso; o nosso lê o `estado.cjs`.
- **R3.** Se a métrica da fase 0 mostrar que cache hit domina o custo, compressão agressiva pode ser desligada por config — o proxy nunca pode custar mais caro que a ausência dele.

## Fases

### Fase 0 — Passthrough + medição (obrigatória, entrega isolada)

- Proxy que só encaminha, sem tocar em nada.
- Por request, gravar JSONL em `.rainforest/poda/metricas.jsonl`:
  - timestamp, estágio ativo (via estado.cjs), nº de mensagens, bytes do body
  - da resposta: `usage.input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` (extraídos do stream SSE sem alterá-lo — parse do evento `message_start`/`message_delta` em cópia, passthrough intacto)
- `/custo` (novo comando ou seção do `/saude`): soma por estágio, % de cache hit, top ofensores por tipo de bloco.
- **Gate de saída da fase 0:** relatório de uma semana de uso real. Sem ele, fase 1 não abre.

### Fase 1 — Compressão live-zone (heurística, determinística)

Comprime apenas `tool_result` **novos** (último turno), uma vez, e o resultado vira a forma permanente do bloco:

| Tipo detectado | Heurística | Ganho esperado |
|---|---|---|
| Array JSON grande | primeiros 10 + últimos 5 itens + `[N itens no total]` | alto |
| Log/output longo (>200 linhas) | head 30 + tail 30 + **todas** as linhas com `error/fail/exception/warn` preservadas | alto |
| Diff grande | stats por arquivo + hunks dos arquivos citados no turno atual | médio |
| Prosa/código curto | não toca | — |

- **CCR-lite:** antes de comprimir, original inteiro vai pra `.rainforest/poda/<sha1-8>.txt`. O stub termina com: `[saída completa: .rainforest/poda/ab12cd34.txt — use Read se precisar]`. Sem tool injection: o modelo já tem Read/Bash.
- Limpeza: arquivos CCR do estágio são apagados no `colher` (ou por idade, config).

### Fase 2 — Poda em fronteira de estágio (estado-aware)

- No evento de `fechar` aprovado, o proxy marca o ponto e, no próximo request, colapsa os turnos do estágio encerrado num bloco único: decisão registrada + evidência do gate + ponteiro CCR pro transcript integral.
- Custo: um cache miss por fechamento. Medir na métrica se compensa (deve, em estágio com muitos turnos de retry).

## Integração com o ecossistema

- `/saude`: se `poda` declarado — porta responde? env var setada na sessão? taxa de economia dos últimos N requests? CCR órfão acumulando?
- `proximo`: pode exibir uma linha de custo do estágio atual (opcional, config).
- Config em `docs/rainforest/poda.json`: porta, compressão on/off por tipo, limiares, retenção do CCR.

## Riscos e mitigação

1. **Compressão mal calibrada aumenta custo** (cache miss > token economizado). → Fase 0 obrigatória + R3 (kill switch por config) + métrica compara custo com/sem.
2. **SSE no Windows** (buffering do Node http em proxy chain). → Teste e2e da fase 0 inclui streaming longo no PowerShell; `res.flushHeaders()` e passthrough por pipe, sem bufferizar.
3. **Auth**: nunca logar headers; `Authorization`/`x-api-key` passam intactos e não aparecem no JSONL.
4. **Heurística corta o dado que importava.** → CCR-lite garante reversibilidade; linhas de erro sempre preservadas por regra.
5. **Claude Code muda formato do body.** → Proxy valida shape; se não reconhecer, passthrough puro + warning no log (nunca falha o request).

## Questões abertas (pro Claude Code responder do ambiente real)

- **Q1.** Como o Claude Code se comporta com `ANTHROPIC_BASE_URL` na conta por assinatura (OAuth) vs API key? Validar que os headers passam e autenticam nos dois modos.
- **Q2.** Contagem de tokens do request sem tokenizer: usar `usage` da resposta como fonte de verdade e bytes/4 como estimativa a priori — suficiente?
- **Q3.** Detecção do tipo de tool_result: pelo shape do conteúdo, ou dá pra correlacionar com o `tool_use` (nome da ferramenta) do turno anterior no mesmo body?

## Fora de escopo (decisão explícita)

- Compressor de ML (modelo tipo Kompress) — viola zero-dependência e não roda leve no Windows.
- Tool injection / response rewrite — CCR-lite via arquivo resolve com o harness que já existe.
- Memória — território do `memoria.cjs`; o proxy não grava nem lê memória semântica.

## Ordem na fila

Depois dos fluxos 1–4. Fase 0 é pequena e isolada — candidata a entrar num domingo junto com outro fluxo; fases 1 e 2 só com o relatório de evidência em mãos.

---

**Status (2026-08-31):** fase 0 entregue — plano em
`docs/rainforest/planos/2026-08-31-fluxo-5-fase-0-poda.md`. Fases 1 e 2 seguem
aguardando o relatório de 7 dias do `scripts/relatorio-poda.cjs`.
