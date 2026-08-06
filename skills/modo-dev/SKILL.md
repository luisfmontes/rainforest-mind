---
name: modo-dev
description: Use when Luís is developing something — writing code, a feature, a fix, a script or a plugin — in any project. Compact dev discipline absorbed from ponytail (lazy senior) and superpowers (process), so those plugins don't need to load every session.
---

# Modo Dev

Essência de disciplina de desenvolvimento, sob demanda. Absorvido do ponytail
e do superpowers em 2026-08-06 para não carregá-los em toda sessão — os
plugins completos seguem instalados e habilitados nos repos de trabalho.

## Antes de codar

1. **Entender antes de resolver.** Ler o código que a mudança toca, traçar o
   fluxo real de ponta a ponta. Preguiça na solução, nunca na leitura.
2. **Pensar antes de construir.** Pedido criativo/ambíguo → alinhar intenção
   e abordagem com o Luís antes do código (1 pergunta certa > 100 linhas
   erradas).

## A escada (parar no primeiro degrau que segura)

1. Precisa existir? Necessidade especulativa = pular, dizer em 1 linha (YAGNI).
2. Já existe neste codebase? Reusar helper/padrão existente.
3. Stdlib resolve? Usar. Plataforma nativa resolve? Usar.
4. Dependência já instalada resolve? Usar. Nunca adicionar nova pro que cabe em poucas linhas.
5. Só então: o mínimo que funciona. Menor diff, sem abstração não pedida,
   sem scaffolding "pra depois".

**Bug = causa raiz, não sintoma.** Antes de editar, ver todos os callers; a
correção mora onde todos passam, não no caminho que o ticket citou.

## Enquanto coda

- **Commit a cada entrega fechada, sempre.** Nunca deixar trabalho sem commit
  na sessão — já houve perda de trabalho por reset de agente (2026-08-06).
- Lógica não-trivial deixa **um** teste/check executável mínimo. Trivial não
  precisa (YAGNI vale pra teste também).
- Estado e resultados intermediários vão para **arquivo** (plano, notas,
  FOCO/IDEIAS), não para o chat — contexto é recurso finito.

## Antes de dizer "pronto"

- **Evidência antes de afirmação.** Rodar o comando de verificação (lint,
  teste, build) e olhar a saída antes de declarar concluído. Falhou = dizer
  que falhou, com a saída.

Nunca simplificar: validação de entrada em fronteira de confiança, tratamento
de erro que evita perda de dados, segurança, o que foi pedido explicitamente.
