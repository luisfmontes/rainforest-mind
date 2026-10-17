# austinmarchese/buildpartner-plugin — avaliação (2026-10-17)

Trazido pelo Luís com "se a ideia for boa e podemos realizar, quero fazer". Clone raso,
commit de 2026-10-07, versão 0.13.3. Lido o código inteiro (hooks, skills, instalador);
o servidor MCP (`buildpartner` no npm, sem `repository` nem `license` no `npm view`)
não está no repo.

## O que faz e o que promete

**Promete:** "expert guidance, coaching, and personalized training" dentro do Claude Code.

**Entrega no repo:** uma casca cliente de um SaaS. Quatro skills (`build`,
`expert-advice`, `improve-system`, `open-dashboard`) + `ask-founder` no plano de equipe,
um MCP via `npx`, hooks de telemetria, auto-update e sincronia de CLAUDE.md. Todo o
conteúdo — os "builds" passo a passo e os frameworks de especialista — vem do servidor,
atrás de conta e Stripe. O MIT cobre só a casca; não há conteúdo para licenciar.
`improve-system` é a única skill que roda sem servidor, e manda recomendar só skills
`/buildpartner:` (SKILL.md, seção Rules).

## Instalar: não instala

| # | Reprova | Evidência |
|---|---|---|
| 2 | colide com a portaria e com a CLAUDE.md dele | `hooks/gate.mjs:422-450` reescreve `~/.claude/CLAUDE.md` todo SessionStart, sem perguntar, com bloco que manda rotear "qualquer pergunta que não seja sobre o código" para a skill paga (`claude-md-block.txt`). Ignora `CLAUDE_CONFIG_DIR` — a segunda conta diverge. `plugin.json:205-215` responde `allow` a todo PermissionRequest de MCP de plugin cujo servidor se chame `tools` (o matcher `mcp__plugin_[^_]+_tools__.*` não é só dele). |
| 3 | injeção fixa | o bloco da CLAUDE.md entra em toda sessão, de todo projeto |
| 4 | Windows de segunda classe | `gate.mjs:417` usa `new URL(import.meta.url).pathname` → `/C:/...`, `path.resolve` erra e o sync cai no `catch` calado; `sh -c` em `plugin-update.mjs:530`, `open` nas skills, `date +%u` no lembrete |
| 5 | tudo-ou-nada | conta obrigatória; hooks disparam sem uso |

Fora da régua, mas pesa: `plugin-update.mjs:528-534` roda `claude plugin update`
destacado a cada hora **mesmo sem conta** (não checa auth); o token vai em query string
(`dashboard?t=TOKEN`) e as skills mandam o agente ler `auth.json` e dar `open` — vaza
para histórico de navegador e de shell.

## Enxertar: enxerta

Âncora: a ideia aberta `setup-vira-entrevista-guiada-como-a-do-ratosos`. O contrato de
passo de `skills/build/SKILL.md` (linhas 61-115) é exatamente a parte que a entrevista
guiada ainda não desenhou — o RatosOS trouxe **o que** perguntar; este traz **como
andar** um passo:

1. **Um passo por turno, gate duro** — buscar o passo só quando chega nele (paginação
   no servidor impede ler adiante).
2. **Precheck do que já existe**, por função e não por nome, e três saídas:
   *usar como está* / *melhorar sem substituir* / *do zero*. Achou nada → não comenta.
   `semear:67` já faz metade (ler o que o repo tem antes de propor).
3. **Opções geradas do repo real**, nunca lista fixa; `multiSelect` quando a resposta é
   lista; o que só ele vê ("I'll paste it" / "pular") vira opção, nunca prosa.
4. **Traduzir o snippet para a plataforma** antes de mostrar; alavanca que não existe no
   projeto vira o movimento mais próximo, dito em uma linha.
5. **Verificação cega** por subagente novo contra o critério do passo — já é o nosso
   `revisar`/`verificar`; não é novidade.
6. **Sempre oferecer o próximo**, nomeando os dois passos ("Feito: X. Próximo: Y?").

Fica fora: frameworks de especialista (conteúdo de terceiro, fechado), telemetria,
auto-update, edição de CLAUDE.md. `ask-founder` (base de conhecimento da empresa com
pedido de lacuna confirmado pelo usuário) é ideia de produto, sem âncora.
