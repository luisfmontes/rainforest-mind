# Batedor — 2026-08-21

**Ronda:** semanal (batedor-repos)  
**Data:** 2026-08-21  
**Problemas ancorados:** 3 de 5 propostas do relatório "Bateria que passa com defeito presente" (2026-08-19)

## Propostas escolhidas

1. **P1** — O briefing de conserto passa a exigir medição nos dois lados, com comando pronto
2. **P3** — `limpar-branches.cjs` nunca remove a branch padrão
3. **P4** — A prova de eficácia entra no estágio `verificar`, não só no `revisar`

Ficaram de fora: P2 (bateria com stdin/timeout) e P5 (padrão de bateria honesto).

## Busca ancorada

Procurei em GitHub por ferramentas que resolvam esses problemas: briefing de conserto com medição bidirecional, limpeza segura de branches, ou validação em estágios. 

Candidatos encontrados:
- `ctrf-io/github-test-reporter` — GitHub Action de reporting com flaky-test detection
- `WithSecureOpenSource/flaky-tests-detection` — Ferramenta de detecção de testes frágeis (parada desde 2022)
- `runetsk/ttgo` — Plataforma completa de testes com flaky-test detection

## Avaliações

### 1. `ctrf-io/github-test-reporter`

| # | Pergunta | Resultado |
|---|---|---|
| 1 | Resolve o problema ancorado? | **❌ Não** — é action de reporting + flaky detection, não entrega nenhuma das 5 propostas |
| 2 | Colide com o que já roda? | ✅ Não — GitHub Action, zero colisão |
| 3 | Custo por sessão? | ✅ Zero — roda em CI, fora de sessão |
| 4 | Windows é primeira classe? | ✅ Sim — runner de CI |
| 5 | Dá pra instalar em pedaço? | ✅ Sim — seletivo via `with:` |
| 6 | Está vivo? | ✅ Sim — 373⭐, push 2026-08-21, MIT |

**Veredito:** `não acopla` — reprova em P1 (não ataca nenhuma ideia aberta).

### 2. `WithSecureOpenSource/flaky-tests-detection`

**Veredito:** `não acopla` — **P6** (parado desde 2022-12-15, 3+ anos sem push).

### 3. `runetsk/ttgo`

**Veredito:** `não acopla` — **P1** (plataforma de testes genérica, não resolve as propostas específicas de conserto/validação em estágio). License "Other" não identificada.

## Resultado

Nenhum candidato resolveu o problema ancorado. Voltar de mãos vazias é resultado válido: **não há solução pronta em GitHub para as propostas do relatório de 2026-08-19**. As melhorias devem ser implementadas internamente no rainforest-mind, conforme o design proposto.
