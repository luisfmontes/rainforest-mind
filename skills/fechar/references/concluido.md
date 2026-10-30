# Conferir de fora se o fluxo fechou: concluido

Movido de `skills/fechar/SKILL.md`, seção "Conferir de fora se o fluxo fechou: `concluido`", em 2026-10-30, para abrir folga no teto de 16 KB da skill.

## Conferir de fora se o fluxo fechou: `concluido`

```
node scripts/estado.cjs concluido --slug <slug>
```

Sai `0` se o fluxo fechou até o `fechar`, `2` imprimindo o estágio pendente
se não, `1` se o slug não existe. Sem `--slug`, varre todos os fluxos em
`docs/rainforest/estado/`: `0` se todos concluídos (ou nenhum arquivo), `2`
listando slug e estágio de cada um aberto.

Para que serve, e para quem: quem dispara o fluxo por script — `claude -p`,
CI, uma rodada de bench — não distingue, pelo exit code do **processo**, um
fluxo que fechou de um que morreu no meio do `revisar`: os dois devolvem
`0`. Este verbo responde essa pergunta, sob demanda.

**Não está pendurado no `SessionEnd`.** Pendurar ali transforma um verbo que
responde quando perguntado num vigia que fala sozinho toda sessão, inclusive
nas que legitimamente não têm fluxo aberto. Se o aviso automático fizer
falta depois do verbo em uso, vira fluxo próprio com o barulho medido em vez
de chutado.

Essa recusa é sobre **aviso falado** — um vigia que interrompe toda sessão
para dizer algo que ninguém perguntou. `hooks/titulo-sessao-end.cjs` também
roda no `SessionEnd`, mas escreve o estado do fluxo no título de uma sessão
já encerrada: não fala com ninguém, então não reabre esta decisão (ver
`docs/rainforest/design/2026-09-15-titulo-de-sessao-encerrada.md`, "Fora de
escopo").

**Fica de fora, Issue #180**: o estágio que despacha agente em background
aposta que o turno dura mais que o agente — aposta perdida em toda sessão
não interativa. O `concluido` diz que o fluxo ficou pela metade; ele **não**
impede que fique.

