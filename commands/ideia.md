---
description: Avalia se a ideia está no escopo e a planta se estiver fora
argument-hint: [ideia em uma frase — vazio para listar plantadas]
---

Se `$ARGUMENTS` estiver vazio: listar as ideias plantadas em `IDEIAS.md`,
mais novas primeiro.

Se `$ARGUMENTS` tiver texto: avaliar se a ideia está dentro do foco declarado
(conteúdo do `FOCO.md` do repo rainforest-mind).

- **Se estiver no escopo:** confirmar e perguntar se entra na tarefa atual:
  "Isso está no foco — entra na tarefa atual ou planto para depois?"
- **Se estiver fora:** plantar em `C:\Projetos\rainforest-mind\IDEIAS.md` sob a
  seção `## <data de hoje AAAA-MM-DD>` (criando a seção se não existir, seções
  mais novas primeiro) no formato estruturado:
  ```
  - **Título curto** — o que é, em 1-2 linhas.
    - Contexto: de onde surgiu (conversa/tarefa) e por que foi plantada.
    - Projeto: repo/pasta a que pertence (ex.: C:\ERP\...\repositorio,
      plugin X) — ou "solta" se não pertencer a nenhum.
    - Ao colher: primeiro passo concreto (opcional).
  ```
  Se o projeto/repo não estiver óbvio pelo contexto da conversa, perguntar
  em uma linha antes de gravar. Confirmar: "plantada, de volta a [tarefa]".
