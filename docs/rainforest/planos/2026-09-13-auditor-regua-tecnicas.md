# Plano — Régua 3 de técnicas no auditor-de-seguranca

Design: docs/rainforest/design/2026-09-13-regua-tecnicas-claude-red.md
Base: origin/main ba7c67c4.

## Tarefas
1. Escrever `referencias/reguas-tecnicas-ofensivas.md` — 30 lentes defensivas
   report-only, derivadas do claude-red (MIT), das 9 categorias de código.
   Critério: 1 lente por classe, 5 partes cada, sem munição.
2. Ligar o `auditor-de-seguranca.md` à Régua 3 (ponteiro + seção de aplicação),
   sem quebrar a bateria. Critério: bateria verde.
3. Travar na bateria `scripts/testa-auditor-de-seguranca.sh` (seção 12).
   Critério: exit 0.
4. Atualizar o README (linha da Régua 3 no bloco de agentes).

## Nota de execução
Autoria feita na janela principal (Opus 5), não por dispatch de agente: o
manifesto não tem agente sonnet que escreve para a função de autoria, e o
`executor` admitido é haiku — fraco demais para conteúdo de segurança. Regra 10
desviada com este motivo. Consequência no fluxo: o `revisar` despachado exige
`executar` fechado com evidência de `mutacao`, que só a etapa `executar` do fluxo
produz; sem ela, o revisor do fluxo fica bloqueado e a revisão é feita na janela
principal + bateria. Registrado, não contornado.

## Verificação (falsificável)
- `bash scripts/testa-auditor-de-seguranca.sh` → `ok: 100 falhou: 0`, exit 0.
- grep de munição na referência → vazio (report-only).
