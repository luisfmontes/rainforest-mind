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
  mais novas primeiro) no formato `- **Título curto** — uma linha de contexto.`
  e confirmar: "plantada, de volta a [tarefa]".
