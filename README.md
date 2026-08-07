<p align="center">
  <img src="assets/banner.svg" alt="rainforest-mind — memória de trabalho externa e radar de escopo" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-plugin-2e8b57?style=flat-square" alt="Claude Code plugin">
  <img src="https://img.shields.io/badge/vers%C3%A3o-0.17.0-1e5c3f?style=flat-square" alt="versão 0.17.0">
  <img src="https://img.shields.io/badge/perfil-2e_(TDAH_+_AH%2FSD)-6fcf97?style=flat-square" alt="perfil 2e">
  <img src="https://img.shields.io/badge/revis%C3%A3o-bimestral-9fd8ba?style=flat-square" alt="revisão bimestral">
</p>

Plugin pessoal de Claude Code para uma mente que funciona como navegador com
abas demais: ideias abrem sozinhas, competem com a tarefa atual e consomem
processamento. O assistente vira **memória de trabalho externa e radar de
escopo** — segura as abas para que o foco fique na tarefa. Nunca tutor,
nunca terapeuta: aviso explícito, decisão sempre do dev.

Baseado no perfil 2e — TDAH + altas habilidades — de *Your Rainforest Mind*
(Paula Prober).

## O que muda

Sem o plugin:

> **Dev:** faz a opção 2. Ah, e a gente podia adicionar um cache nisso!
>
> **Assistente:** Ótima ideia! Vou implementar a opção 2 com cache… *(a adição virou escopo sem ninguém decidir)*

Com o plugin:

> **Dev:** faz a opção 2. Ah, e a gente podia adicionar um cache nisso!
>
> **Assistente:** Fechado: opção 2. Você adicionou o cache — entra no escopo agora ou planto? *(a decisão volta pro dono dela)*

## Como funciona

```mermaid
flowchart LR
    A["💭 ideia solta<br/>no meio da tarefa"] --> B{"radar<br/>de escopo"}
    B -->|"está no foco"| C["entra na tarefa<br/>(confirmada)"]
    B -->|"está fora"| D["🌱 plantada em<br/>ideias.jsonl"]
    D --> E["revisão quando<br/>houver espaço"]
    E -->|"chegou a estação"| F["🌳 colhida:<br/>vira trabalho"]
    E -->|"ainda não"| D
    G["FOCO.md<br/>(foco declarado)"] -.->|"injetado a<br/>cada sessão"| B
```

**Plantada ≠ descartada.** A ideia sai da cabeça para um lugar confiável e
cria raiz até a estação certa. O `ideias.jsonl` deste repo guarda plantadas
e colhidas (um JSON por linha, com contexto e projeto/repo de cada uma) —
o histórico de colheita fica visível.

## As 11 regras

| # | Regra | Em uma frase |
|---|-------|--------------|
| 1 | Responder tudo, na ordem | N perguntas recebem N respostas, numeradas, na mensagem final; item resolvido sai e a lista renumera do 1 |
| 2 | Escolha + adição | A emenda nunca vira escopo em silêncio: confirma ou planta |
| 3 | Radar de escopo | Saiu do foco declarado → uma frase, sem julgamento, com escolha |
| 4 | Checkpoint no meio | Tarefa 3+ etapas: "fechamos n/total" a cada etapa |
| 5 | Decisão com o porquê | "Decidido: X, porque Y. Próximo passo: Z." |
| 6 | Plantio de ideias | Ideia solta → "planto essa pra depois?" → `ideias.jsonl` |
| 7 | Tom sênior | Policia pontas soltas e escopo, nunca o mérito |
| 8 | Guarda-corpo de jornada | Jornada real do apontamento-horas: ~9h efetivas produzindo → um aviso, uma vez (fallback: 19h/2h+) |
| 9 | Freio de Pareto | Polimento de algo pronto → barra uma vez, entrega ou planta |
| 10 | Agentes baratos com método | Janela principal pensa; task mecânica → `executor` (haiku), review → `revisor`, testes → `tester` (sonnet); sem `name` por padrão |
| 11 | Worktree de subagente | Isolamento sempre — e conferir o commit-base do worktree; integrar por partes, nunca copiar arquivos inteiros |

Detalhe completo em [`skills/rainforest-mind/SKILL.md`](skills/rainforest-mind/SKILL.md).

## Comandos e skills

| O quê | Faz |
|-------|-----|
| `/foco` | Estado da conversa: foco, loops abertos, decisões tomadas |
| `/foco <texto>` | Declara novo foco em `FOCO.md` — injetado em toda sessão nova |
| `/ideia <texto>` | Avalia contra o foco: dentro → entra confirmada; fora → planta em `ideias.jsonl` (com contexto e projeto/repo) |
| `/ideia` | Lista as ideias plantadas (lendo o jsonl) |
| `modo-dev` (skill) | Essência de disciplina de dev sob demanda: escada YAGNI, causa raiz, commit a cada entrega, evidência antes de "pronto" |
| `executor` (agente) | Implementação/execução mecânica em haiku com o método de trabalho embutido no system prompt (`agents/executor.md`) |
| `revisor` (agente) | Review/QA em sonnet com método de revisão embutido (`agents/revisor.md`): evidência primária, achado só com cenário de falha, veredito integra/não-integra |
| `tester` (agente) | Testes em sonnet com método embutido (`agents/tester.md`): extrai o contrato, escreve os testes que faltam, pelo menos um adversarial, reporta números exatos |

A skill `modo-dev` existe para **economia de contexto**: absorve os
principais pontos de plugins pesados (ponytail, superpowers) que não
precisam carregar em toda sessão.

## Vigias (automação fora do Claude)

A pasta [`vigias/`](vigias/) tem prompts headless agendados no Windows Task
Scheduler (`claude -p`, haiku) que reportam por WhatsApp: **sentinela-foco**
(briefing matinal de prazo/avanço + triagem do inbox Gmail em 3 baldes —
responder hoje / pode esperar / FYI, somente leitura —, dias úteis 7h52),
**jardineiro-ideias**
(sexta 15h52 — ideias plantadas + revisão periódica do vault
segundo-cerebro), **vigia-tickets** (2x/dia até o marco) e **revisao-bimestral**
(one-shot). O guarda-corpo funcionando fora da sessão — onde o hiperfoco
não deixa abrir uma.

## Instalação

```
claude plugin marketplace add luisfmontes/rainforest-mind
claude plugin install rainforest-mind@rainforest-mind
```

Ou aponte `--plugin-dir` para a pasta do repo em desenvolvimento.

## Ajuste fino

- As regras vivem em [`skills/rainforest-mind/SKILL.md`](skills/rainforest-mind/SKILL.md) — edite e a mudança vale na próxima sessão.
- O hook avisa quando a skill passa de **60 dias sem revisão** (data no cabeçalho do SKILL.md): o perfil muda, a skill acompanha.
- Fork à vontade: troque `FOCO.md`/`ideias.jsonl` pelos seus arquivos e as regras pelo seu perfil.

## Base

Desenho orientado por pesquisa (ago/2026) sobre dupla excepcionalidade em
adultos profissionais (Barkley, ADDitude, CHADD, The Center for ADHD) e por
análise de 6 skills públicas de ADHD para assistentes de IA
([i-have-adhd](https://github.com/ayghri/i-have-adhd) e derivadas). Lacuna
que este plugin cobre e nenhuma delas cobria: **aviso de desvio de escopo**
e **fechamento de loops abertos** da conversa.

## Créditos

- *Your Rainforest Mind* — Paula Prober, a metáfora que dá nome ao plugin.
- [i-have-adhd](https://github.com/ayghri/i-have-adhd) — inspiração de formato e prova de que skill de neurodivergência funciona.
- Pesquisa 2e: suporte camuflado em conversa casual não funciona — por isso toda intervenção aqui é explícita e sinalizada.
