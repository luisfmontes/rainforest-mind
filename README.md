# rainforest-mind

Plugin pessoal de Claude Code: memória de trabalho externa e radar de escopo
para um perfil 2e — TDAH + altas habilidades (*Your Rainforest Mind*, Paula
Prober). A mente funciona como abas de navegador: ideias abrem sozinhas,
competem com a tarefa atual e consomem processamento. Este plugin faz o
assistente segurar as abas para que o foco fique na tarefa.

## O que faz

- **7 regras de interação** sempre ativas (injetadas por hook a cada sessão):
  responder tudo na ordem, confirmar escolha+adição, radar de escopo,
  checkpoints no meio, registro de decisões, estacionamento de ideias, tom
  sênior. Detalhe em [`skills/rainforest-mind/SKILL.md`](skills/rainforest-mind/SKILL.md).
- **`/foco`** — estado da conversa (loops abertos, decisões) ou declara novo
  foco, gravado em `FOCO.md` e injetado em **toda** sessão nova, em qualquer
  pasta.
- **`IDEIAS.md`** — estacionamento: a aba sai da cabeça, vai para o arquivo.
- **Revisão bimestral** — o hook avisa quando a skill passa de 60 dias sem
  revisão (data no cabeçalho do SKILL.md).

## Instalação

```
claude plugin marketplace add <caminho-ou-url-deste-repo>
claude plugin install rainforest-mind
```

Ou aponte `--plugin-dir` para a pasta do repo em desenvolvimento.

## Base

Desenho orientado por pesquisa (ago/2026) sobre dupla excepcionalidade em
adultos profissionais (Barkley, ADDitude, CHADD, The Center for ADHD) e por
análise de 6 skills públicas de ADHD para assistentes de IA (i-have-adhd e
derivadas). Lacuna que este plugin cobre e nenhuma delas cobria: aviso de
desvio de escopo e fechamento de loops abertos da conversa.
