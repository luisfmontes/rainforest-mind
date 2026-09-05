# LEIA-PRIMEIRO — CONSOLIDADO v2 (2026-08-30)

> Mapa único de todos os fluxos do rainforest-mind projetados entre 28–29/08.
> Claude Code lê este arquivo primeiro. Os designs completos estão nos zips
> de cada conversa (arquivos não atravessam sessões — só o texto atravessa).
> Substitui o `LEIA-PRIMEIRO-CONSOLIDADO.md` de 29/08.

## Correção de numeração (registrar e não reabrir)

Três frentes reivindicaram o número 8 em conversas paralelas:
handover+regente, critica e portaria. Resolução:

| Nº | Componente | Motivo da posição |
|----|-----------|-------------------|
| 8  | `handover.cjs` + `regente.cjs` | Já havia sido renumerado para 8 com nota de correção gravada no índice de 29/08 — mantém |
| 9  | `portaria.cjs` | Hook PreToolUse independente; só precisa do padrão de manifesto, não do circuito de reprovação |
| 10 | `critica.cjs` | Depende do fluxo 1 fechado (back-edge `reprovado→executar` + contador compartilhado) |
| 11 | `conselho.cjs` | Decisão Q em aberto (fluxo independente vs. passo opcional do `design`) — entra por último |

Qualquer documento antigo que diga "fluxo 8 — crítico" ou "fluxo 8 — portaria"
lê-se como 10 e 9 respectivamente.

## Fluxo 10 (crítico) — superado, não avança (2026-09-05)

Arqueologia comparou o design de 2026-08-30 com o repositório de 2026-09-05,
seis dias depois. Cada promessa do design nasceu coberta por mecanismo que não
existia quando ele foi escrito:

| Promessa do design do fluxo 10 | Mecanismo que a cumpre hoje |
|---|---|
| Reprovar `design` com segunda rodada antes de fechar | `scripts/conselho.cjs` (fluxo 11), opt-in por `.rainforest/conselho/` antes de marcar `aprovado` — `skills/brainstorm/SKILL.md:111-115` |
| Reprovar `plano` — estrutura, cobertura D↔tarefa, alvo de mutação | `scripts/conferir-fluxo.cjs:72-260` (`cmdDesign`, `cmdCobertura`, `conferirBlocoMutacao`) |
| Reprovar `executar` com segunda rodada | `agents/revisor.md` + `skills/revisar/SKILL.md`, `scripts/segunda-opiniao.cjs` (cross-model, falha fechada) e a catraca de mutação (`scripts/estado.cjs:446`) |
| Pegar oráculo desonesto pela mesma lógica do lint | `scripts/portoes.cjs:16-22` — o lint de autoria, que o próprio arquivo chama de peça de maior valor |
| Opt-in por presença de diretório, território estende | padrão já estabelecido pelos fluxos 6 e 11; era precedente, não invenção do crítico |

**A dependência declarada era falsa.** A linha do 10 na fila abaixo dizia
"depende do fluxo 1 (back-edge `reprovado→executar` + contador compartilhado)",
e o design pedia essa aresta também para `design` e `plano`. Ela nunca existiu
para os estágios de decisão, e a ausência é escolha deliberada:
`scripts/estado.cjs:84-95` define `design: ['pendente','aprovado']` e
`plano: ['pendente','ok']`, e `scripts/estado.cjs:262-263` registra por
comentário que "para estágios de decisão (design, plano), não há upstream a
reabrir". Reproduzido na saída real em 2026-09-05:

```
$ node scripts/estado.cjs marcar --slug fluxo-10-critico --estagio design --status reprovado
erro: status 'reprovado' invalido para 'design' — use pendente|aprovado
exit 1, estado intacto
```

Um crítico que reprova `design` e `plano` precisaria reabrir essa máquina de
estados — seria um segundo motor de reprovação em paralelo ao que os fluxos 1,
6 e 11 já mantêm, não uma peça faltando.

O teto compartilhado que o design recomendava (Q4) some junto: sem essa aresta,
o `TETO_TENTATIVAS` de `scripts/estado.cjs:151` nunca chega a compor com
contador nenhum, e onde o repo teve escolha livre ele adotou teto local — o
`scripts/conselho.cjs:267-278` tem o seu, por fase. Não é Q respondida pelo
dono: é pergunta que ficou sem objeto.

**O que sobrevive.** Ninguém audita hoje conteúdo semântico de `design` e
`plano`, só estrutura — "toda decisão em aberto tem recomendação e razão", "o
`pronto quando` nomeia entrada real e não `a bateria sai 0`". O
`conferir-fluxo.cjs` conta seção e numeração; o conselho debate uma questão
específica e não varre o documento inteiro. Fatia fina e sem substituto,
plantada como ideia em vez de virar fluxo: construí-la exigiria dar ao
`estado.cjs` a aresta que o fluxo 1 recusou.

**Numeração.** O 10 fica reservado como superado. Fluxo novo pega o próximo
número livre; ninguém reaproveita o 10, para que documento antigo que diga
"fluxo 10 — crítico" continue resolvendo para este registro.

## Fila oficial dos 11 fluxos

| Nº | Nome | Script(s) | Depende de | Origem/atribuição |
|----|------|-----------|------------|-------------------|
| 1 | Endurecer estado | `estado.cjs` | — | próprio (code review) |
| 2 | Memória | `memoria.cjs` | — | próprio |
| 3 | Ponte/setup | — | — | próprio |
| 4 | Território contract | — (rascunho) | 3 | próprio; AdvPL = 2º implementador |
| 5 | Poda (proxy) | `poda.cjs` | — | headroomlabs-ai/headroom (reescrita) + deepagents (adendo: 85%/10%, stub numerado) |
| 6 | Portões executáveis | `portoes.cjs` | 1 | unlazy (Leonxlnx, MIT — reescrita) |
| 7 | Recibo criptográfico | incremento em `fechar`/`colher` | 1 | archify (tt-a1i, MIT — ideia) |
| 8 | Handover + regente | `handover.cjs`, `regente.cjs` | Fase 0 do 5 | próprio |
| 9 | Portaria | `portaria.cjs` | — | próprio; hermes-agent (NousResearch, MIT) = convergência independente, validação pós-hoc |
| 10 | Crítico — **SUPERADO em 2026-09-05** | não construído | dependência declarada era falsa | próprio; ver o bloco "Fluxo 10 (crítico) — superado" acima |
| 11 | Conselho | `conselho.cjs` | — | karpathy/llm-council (sem licença — só mineração de ideia, atribuição obrigatória) |

## Ordem de execução recomendada (hoje)

1. **Fluxo 1** — endurece o `estado.cjs` que cobra todos os outros
   (evidência obrigatória no `marcar --status ok`, back-edge
   `reprovado→executar` como transição de máquina, contador de tentativas).
2. **Fluxos 2 e 3** na sequência já planejada (memória: triggers FTS5,
   slots 9+5, `consolidar`, seção no `/saude`; ponte: entrevista de repo,
   blocos `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`, integrações declaráveis).
3. **Fase 0 do fluxo 5** — passthrough + medição, pequena e isolada;
   destrava o gatilho do fluxo 8.
4. **Fluxos 6 e 7** com o 1 fechado.
5. **Fluxo 9 (portaria)** — independente, pode entrar em paralelo com 6/7.
6. **Fluxo 8** — `handover.cjs` primeiro (já serve sessão interativa),
   `regente.cjs` fecha a autonomia headless.
7. ~~**Fluxo 10 (crítico)**~~ — **superado em 2026-09-05**, sai da ordem.
   O circuito de reprovação que ele exigia não existe para `design` e `plano`,
   e o que ele prometia já é feito pelos fluxos 1, 6 e 11 — ver o bloco de
   veredito acima.
8. **Fluxo 11 (conselho)** — fechar antes a Q aberta (recomendação:
   passo opcional dentro do `design`, ativado por presença de
   `.rainforest/conselho/`, seguindo o padrão opt-in das `rubricas/`).
9. **Fluxo 4 (território)** fica para depois do núcleo estável —
   validar interface com o repo AdvPL.

## De onde baixar cada pacote (uma conversa = um zip)

| Conversa | Conteúdo | Arquivo |
|----------|----------|---------|
| "Harness, loop engineering e graphic engineering" | Fluxos 1–4 (designs + planos), backlog de 21 ideias, checklist de README | `rainforest-pacote-completo-2026-08-28.zip` |
| "Analisar repos para incorporar no Rainforest-Mind" | Fluxos 6, 7 + adendo do fluxo 5 | zip da conversa de 29/08 |
| "Proxy para reduzir consumo de token" | Fluxos 5 e 8 + índice antigo (superado por este) | `rainforest-pacote-2026-08-29.zip` |
| "Agentes e orquestração no Rainforest" | Fluxo 9 (portaria, versão final com análise hermes-agent) | `fluxo-8-design-portaria*.md` → renomear para `fluxo-9-…` |
| "Agente crítico para validação de produto" | Fluxo 10 (crítico) | `fluxo-8-design-critico.md` → renomear para `fluxo-10-design-critico.md` |
| "Subagentes debatendo múltiplas perspectivas" | Fluxo 11 (conselho) | `design-conselho.md` → renomear para `fluxo-11-design-conselho.md` |

## Onde colocar no repo

- Todos os designs → `docs/designs/` (ou o diretório de designs já usado
  pelo repo), commitáveis.
- Este arquivo → raiz de `docs/designs/` como índice.
- Lembretes de fronteira git já decididos: `.rainforest/` quase inteiro
  no `.gitignore`; `poda/CCR` é risco de segurança (tool output bruto),
  nunca commita.

## Pendências registradas (não bloqueiam o início)

- Q do conselho: fluxo independente vs. passo do design (recomendação acima).
- Adaptadores de modelo externo do conselho (Codex, Gemini): suportados
  na arquitetura v1, fora do escopo inicial.
- `subagente_worktree.py` (hermes-agent): opção futura documentada para
  filhos com escrita em worktrees isolados — exige atribuição.
- Instalação do rainforest-mind como Skill no ambiente claude.ai: ficou
  pendente na conversa do conselho; irrelevante para a execução local.
