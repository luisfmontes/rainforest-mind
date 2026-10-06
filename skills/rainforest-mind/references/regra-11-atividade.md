# Regra 11 — um worktree por atividade

Separado de `regra-11.md` pelo mesmo motivo que `regra-11-principal.md`: o
teto de bytes de um `reference`. A frase curta que vale em toda consulta mora em
`regra-11.md`; aqui está a elaboração.

**Um worktree por ATIVIDADE, não por estágio — e não se troca de worktree com
agente em voo.** Antes de `git worktree add`, perguntar se já existe worktree
desta atividade: se existe, o trabalho continua nele. Worktree novo é para
atividade nova, ou para dois editores simultâneos de verdade — e aí se commita
antes, não se abre branch separada por conveniência (agentes em série não têm
concorrência a isolar). Quanto à troca: `EnterWorktree` com agente em voo faz o
guard do harness comparar o cwd do comando ao worktree **atual** da sessão, não
ao do despacho, e recusar todo o shell do agente. Despachar já do worktree
destino, ou esperar a entrega. O `gate-agente-em-voo` só barra o fim do turno,
não a troca.

> 2026-09-03: criei dois worktrees e duas branches para uma atividade (design e
> plano numa, código dos subagentes noutra); um merge a mais e o histórico
> partido até consolidar. 2026-09-08: chamei `EnterWorktree` com dois
> planejadores em voo e o guard recusou qualquer comando de shell deles, até
> `pwd` — cerca de 365 mil tokens de agente sem rodar bateria alguma.
