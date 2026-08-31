# Fluxo 10 — Agente `critico` (rubrica por estágio)

> **Nota de renumeração (2026-08-30):** este design nasceu como "Fluxo 8" na
> conversa de origem. Renumerado para **10** pelo `LEIA-PRIMEIRO-CONSOLIDADO-v2`
> (o 8 pertence a handover+regente, o 9 à portaria). Conteúdo inalterado.

**Status:** rascunho — Q1–Q4 abertas, recomendação marcada em cada uma
**Depende de:** fluxo 1 fechado (aresta `reprovado → executar` por máquina, contador de tentativas); fica melhor com fluxo 6 ativo (lint como precedente e infraestrutura de veredito)
**Origem/atribuição:** semente registrada no adendo do fluxo 5 — `rubric.py` do deepagents (langchain-ai, MIT): avaliar saída de agente contra rubrica declarada. Reescrita total, zero código copiado. Atribuir no cabeçalho de `critica.cjs` e aqui. Parente conceitual do `sabotador` do backlog (ideia 21), que continua separado: o `sabotador` ataca, o `critico` julga contra critério declarado.

---

## Motivação

Hoje a qualidade do produto de cada estágio (design, plano, código do executar) só é testada pelo portão seguinte ou pela evidência colada. Não existe um passo que force uma segunda rodada *antes* do estágio fechar. A proposta: um papel de crítico que reprova com base em rubrica declarada e devolve o artefato pra mais uma volta — com teto, pra não virar loop de refinamento infinito.

## Princípios (herdados da casa)

1. **Papel é agente, domínio é skill.** Um único agente `critico`; o que muda por estágio é a rubrica, não o papel. Três agentes seriam três cópias do mesmo contrato com prompt diferente — manutenção triplicada, zero ganho.
2. **Exit code, não instrução.** A opinião do crítico não vale nada solta em prosa. O veredito é JSON serializável gravado no estado, e a reprovação reusa a aresta `reprovado → executar` (ou `→ design`/`→ plano`, conforme o estágio) que o fluxo 1 já materializou por máquina.
3. **Crítica falsificável ou crítica inválida.** "Poderia ser melhor" não reprova. Cada reprovação aponta `criterio` (ID da rubrica), `evidencia` (trecho/linha/comando concreto) e `faltou` (o que satisfaria o critério). Veredito sem os três campos é rejeitado pelo `critica.cjs` com exit não-zero — o crítico desonesto é pego pela mesma lógica do lint de oráculos do fluxo 6.

## Mecânica

### `critica.cjs` (Node puro, CommonJS, zero deps, cross-platform)

Comandos:

- `critica.cjs lint --rubrica <arquivo>` — audita a rubrica *no plano*, antes de qualquer execução. Erro: critério sem ID; critério não-falsificável (sem verbo de resultado verificável — "ser claro", "estar bom"); rubrica vazia. Aviso: critério que duplica um portão existente (crítica não substitui portão; se dá pra checar por comando, é portão, não rubrica). `--strict` promove aviso a falha.
- `critica.cjs veredito --slug <s> --estagio <e> --json <arquivo>` — grava o veredito. Valida o contrato: `{"resultado": "aprovado"|"reprovado", "itens": [{"criterio": "R3", "evidencia": "...", "faltou": "..."}]}`. `reprovado` com `itens` vazio → exit 1, nada gravado. `aprovado` com `itens` não-vazio → exit 1 (aprovação com ressalva não existe; ressalva vira observação de memória, não veredito).
- `critica.cjs proximo --slug <s>` — imprime o bloco da última reprovação (criterio, evidencia, faltou) pra colar na rodada seguinte — mesmo padrão do `proximo` do estado.

Escrita atômica (temp + rename), `\r\n` normalizado, como o resto.

### Rubricas

Uma por estágio criticável: `rubricas/design.md`, `rubricas/plano.md`, `rubricas/executar.md`. Formato: lista de critérios `R1..Rn`, cada um uma frase falsificável ("toda decisão em aberto tem recomendação e razão", "todo item do plano tem alvo de mutação que morde"). O core traz defaults mínimos; território pode substituir ou estender (mesmo contrato do sistema de territórios — a rubrica é domínio, logo é do território, não do agente).

### Agente `critico`

Um único agente. Recebe: artefato do estágio + rubrica do estágio + bloco da reprovação anterior (se houver). Contrato de saída: exclusivamente o JSON do veredito. O prompt instrui; o `critica.cjs veredito` **força** — JSON malformado ou veredito sem evidência não grava e devolve exit 1.

### Encaixe no pipeline

- Opt-in por fluxo, como os portões: presença de `rubricas/` ativa; ausência mantém o comportamento de hoje, byte a byte.
- O gate de fechamento do estágio, quando crítica está ativa, exige veredito `aprovado` gravado. `reprovado` reabre o estágio pela aresta existente e **incrementa o mesmo contador de tentativas** do fluxo 1 — não existe segundo teto. Na terceira reprovação, saída definida: `ABANDONA:` + devolução, nunca rodada 4.
- `lint` da rubrica roda no fechamento do `plano` quando `rubricas/` existe — rubrica ruim é defeito de planejamento, pega na origem (mesma regra dos portões).

## O que fica de fora e por quê

- **Três agentes (um por área).** Papel é um; domínio (a rubrica) é que varia. Ver princípio 1.
- **Nota numérica / scoring.** Número de LLM-judge é não-determinístico e não-falsificável; o veredito é binário com evidência ou não é nada.
- **Debate multi-crítico / crítico do crítico.** Paralelismo e recursão contra a regra do pipeline sequencial solo. Se um crítico com teto não basta, o defeito é da rubrica.
- **Crítica em `revisar`/`verificar`/`fechar`/`colher`.** `verificar` já tem portões e evidência; `fechar`/`colher` ganharam recibo no fluxo 7. Crítica cobre os estágios generativos (design, plano, executar) onde não há oráculo executável.
- **Chamada de LLM dentro do `critica.cjs`.** O script valida e grava; quem pensa é o agente na sessão. Zero deps continua regra.

## Pronto quando (falsificável)

1. `critica.cjs lint` reprova rubrica com critério não-falsificável e aprova as três rubricas default; provado na bateria com fixture de rubrica ruim.
2. `veredito` com `reprovado` e `itens` vazio retorna exit 1 e não grava; provado na bateria.
3. Com crítica ativa, `marcar` de fechamento do estágio sem veredito `aprovado` retorna exit não-zero; sem `rubricas/`, a saída de hoje não muda byte; provado comparando as duas execuções na bateria.
4. Terceira reprovação faz o `proximo` instruir `ABANDONA:` + devolução em vez de rodada 4; provado na bateria com três vereditos `reprovado` em sequência.

## Portões (rascunho para este fluxo)

- [ ] P0: rubricas default têm critérios honestos
  CHECK: node scripts/critica.cjs lint --rubrica rubricas/design.md --strict
  ESPERA: LINT OK
- [ ] P1: veredito desonesto não grava
  CHECK: node scripts/testa-critica.cjs caso-veredito-vazio
  ESPERA: TESTE OK
- [ ] P2: teto compartilhado dispara ABANDONA
  CHECK: node scripts/testa-critica.cjs caso-teto
  ESPERA: TESTE OK

## Decisões em aberto

- **Q1 — Um agente ou três?** Recomendada: **um** (`critico`), rubrica por estágio. Razão: papel é agente, domínio é skill; três agentes triplicam manutenção do mesmo contrato.
- **Q2 — Onde vivem as rubricas?** Recomendada: **defaults mínimos no core, override por território.** Razão: rubrica é conhecimento de domínio; territórios vivem fora do core por decisão já fechada.
- **Q3 — Obrigatório ou opt-in?** Recomendada: **opt-in por fluxo** (presença de `rubricas/`), como portões. Razão: fluxo pequeno não deve pagar rodada de crítica; regra de território pode obrigar depois.
- **Q4 — Contador próprio ou teto compartilhado?** Recomendada: **compartilhado** com o contador de tentativas do fluxo 1. Razão: dois tetos independentes permitem 3×3 = 9 rodadas pela porta dos fundos; um teto único preserva a garantia de terminação.
