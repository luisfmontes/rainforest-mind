# Segunda opinião (opcional)

Movida de `skills/revisar/SKILL.md` em 2026-10-05: o SKILL.md bateu o teto de 16 KB do `testa-teto-skills.sh`.


Depois que o revisor Claude fecha `ok`, a entrega pode ser submetida a um
segundo auditor de **família de modelo diferente** (Codex ou Gemini). A
segunda opinião é um passo **opcional** — liga-se por `--modelo codex` ou
`--modelo gemini` em `node scripts/segunda-opiniao.cjs`.

Quando ligada, consome:

- `git diff <base>...<head>` (três pontos, o mesmo escopo que `revisar` já fixa
  acima)
- O critério falsificável do briefing (arquivo de texto)
- O commit-base (SHA fornecido)

E devolve:

- Veredito de **uma linha** no stdout, vocabulário fechado: `concordo` ou
  `discordo`
- Parecer completo (justificativa) no stderr

**Arbitra sempre a janela.** O modelo externo aconselha, nunca manda. Se
discordar e a janela rejeitar o parecer, a divergência vai ao log
(`scripts/segunda-opiniao.cjs registrar-divergencia ...`) com motivo nomeado —
não desaparece, mas também não trava a entrega.

**Indisponibilidade reprova.** Se o modelo está ligado mas não responde (exit
≠ 0, stdout vazio, ou timeout), o `segunda-opiniao.cjs` sai com erro — nunca segue
em silêncio. Use `TIMEOUT_SEGUNDA_OPINIAO_MS` para calibrar timeout (default
300000 ms = 5 min).

Quando a segunda opinião concorda, a entrega prossegue com endorsement de
ambos os auditores. Quando discorda e é aceita, o motivo fica registrado e
visível para que revisões futuras de contexto relacionado saibam por quê a
aprovação do externo foi descartada.
